@tool
extends Control
## 骨骼权重编辑器 - Dock 面板（精简版）
## 只保留两块：
##   ① 面板内"点选顶点"预览 —— 点击一个点选中该顶点（点按该骨骼权重着色）；
##   ② "当前顶点：各骨骼权重" —— 列出所有骨骼，用数值框设置该点在各骨骼上的权重。
## 读写统一走官方 API：get_bone_count / get_bone_path / get_bone_weights / set_bone_weights。

## 面板内嵌的"点选"预览视图：绘制 Polygon2D 的轮廓和顶点，点击一个点即拾取该顶点。
## 完全用控件自身坐标，不受编辑器缩放/平移影响，保证点选精确。
class PointPickerView:
	extends Control

	signal point_clicked(index: int)

	var _pts: PackedVector2Array = PackedVector2Array()
	var _weights: PackedFloat32Array = PackedFloat32Array()
	var _selected := -1
	const PAD := 12.0
	const PICK_R := 10.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_data(pts: PackedVector2Array, weights: PackedFloat32Array, selected: int) -> void:
		_pts = pts
		_weights = weights
		_selected = selected
		queue_redraw()

	func _bounds_min() -> Vector2:
		var lo := Vector2(INF, INF)
		for p in _pts:
			lo.x = minf(lo.x, p.x)
			lo.y = minf(lo.y, p.y)
		return lo

	func _bounds_max() -> Vector2:
		var hi := Vector2(-INF, -INF)
		for p in _pts:
			hi.x = maxf(hi.x, p.x)
			hi.y = maxf(hi.y, p.y)
		return hi

	# 多边形点 -> 控件坐标（缩放并居中）
	func _plot(p: Vector2) -> Vector2:
		var w := size.x - PAD * 2
		var h := size.y - PAD * 2
		if w <= 0 or h <= 0:
			return Vector2.ZERO
		var lo := _bounds_min()
		var hi := _bounds_max()
		var pw := maxf(hi.x - lo.x, 0.0001)
		var ph := maxf(hi.y - lo.y, 0.0001)
		var scale := minf(w / pw, h / ph)
		var out: Vector2 = (p - lo) * scale
		out += Vector2((w - pw * scale) * 0.5 + PAD, (h - ph * scale) * 0.5 + PAD)
		return out

	func _draw() -> void:
		if _pts.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(PAD, PAD), "无顶点数据", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.6))
			return
		if size.x < PAD * 2 + 8 or size.y < PAD * 2 + 8:
			return  # 控件还没布局/尺寸过小，跳过绘制
		if _pts.size() >= 3:
			var polygon := PackedVector2Array()
			for p in _pts:
				polygon.append(_plot(p))
			var outline := polygon.duplicate()
			outline.append(polygon[0])
			draw_polyline(outline, Color(0.6, 0.75, 0.9, 0.8), 1.5, true)
		for i in _pts.size():
			var c: Vector2 = _plot(_pts[i])
			var w := _weights[i] if i < _weights.size() else 0.0
			var col := Color(0.3, 0.6, 1.0).lerp(Color(1.0, 0.3, 0.2), w)
			draw_circle(c, 4.0, col)
			if i == _selected:
				draw_arc(c, 8.0, 0.0, TAU, 20, Color.WHITE, 2.0, true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
			var best := -1
			var best_d := PICK_R * PICK_R
			for i in _pts.size():
				var d := (_plot(_pts[i]) - (event as InputEventMouseButton).position).length_squared()
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				point_clicked.emit(best)
				accept_event()

var plugin: EditorPlugin

var _poly: Polygon2D
var _selected_bone := -1   # 点选预览按此骨骼权重着色
var _selected_vertex := -1
var _vertex_spin_map: Dictionary = {}   # bone_idx -> SpinBox

# ---- UI ----
var _target_label: Label
var _bone_select: OptionButton
var _picker: PointPickerView
var _detail_box: VBoxContainer
var _status_label: Label

func _init() -> void:
	custom_minimum_size = Vector2(280, 0)
	_build_ui()

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var title := Label.new()
	title.text = "骨骼权重编辑器"
	title.add_theme_font_size_override("font_size", 15)
	root.add_child(title)

	_target_label = Label.new()
	_target_label.text = "未选择 Polygon2D"
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_target_label)

	root.add_child(HSeparator.new())

	var bone_lbl := Label.new()
	bone_lbl.text = "着色骨骼（点选视图按此骨骼权重染色）"
	root.add_child(bone_lbl)
	_bone_select = OptionButton.new()
	_bone_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bone_select.item_selected.connect(_on_bone_selected)
	root.add_child(_bone_select)

	var pk_lbl := Label.new()
	pk_lbl.text = "点选顶点（点击一个点查看该点各骨骼权重）"
	root.add_child(pk_lbl)
	_picker = PointPickerView.new()
	_picker.point_clicked.connect(_on_picker_point_clicked)
	root.add_child(_picker)

	root.add_child(HSeparator.new())

	var detail_lbl := Label.new()
	detail_lbl.text = "当前顶点：各骨骼权重"
	root.add_child(detail_lbl)
	_detail_box = VBoxContainer.new()
	root.add_child(_detail_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	root.add_child(_status_label)

# ================= 数据装载 =================

func set_target(poly: Polygon2D) -> void:
	_poly = poly
	_selected_vertex = -1
	_selected_bone = -1
	if poly == null:
		_target_label.text = "未选择 Polygon2D"
		_bone_select.clear()
		_clear_detail()
		_update_picker()
		_status_label.text = ""
		return
	_target_label.text = "%s  (%d 顶点)" % [poly.name, _vertex_count_of(poly)]
	_bone_select.clear()
	var n := poly.get_bone_count()
	for i in n:
		_bone_select.add_item(_pretty_bone_name(poly.get_bone_path(i)))
		_bone_select.set_item_metadata(i, i)
	if n == 0:
		_status_label.text = "该 Polygon2D 还没有骨骼。\n先在 UV 编辑器的 Bones 面板点 “Sync Bones to Polygon”，或由脚本添加骨骼（add_bone）。"
	else:
		# 阻塞信号避免 select() 与显式调用重复触发
		_bone_select.set_block_signals(true)
		_bone_select.select(0)
		_bone_select.set_block_signals(false)
		_selected_bone = 0
		_status_label.text = ""
	_update_picker()

static func _vertex_count_of(poly: Polygon2D) -> int:
	if poly.internal_vertex_count > 0:
		return poly.internal_vertex_count
	return poly.polygon.size()

func _pretty_bone_name(path: NodePath) -> String:
	var s := String(path)
	var last := s.get_slice("/", s.get_slice_count("/") - 1) if s.get_slice_count("/") > 0 else s
	return last

## 刷新点选预览：写入当前着色骨骼的权重，并同步选中顶点。
func _update_picker() -> void:
	if _picker == null:
		return
	if _poly == null:
		_picker.set_data(PackedVector2Array(), PackedFloat32Array(), -1)
		return
	var w := _poly.get_bone_weights(_selected_bone) if _selected_bone >= 0 else PackedFloat32Array()
	_picker.set_data(_poly.polygon, w, _selected_vertex)

# ================= 点选 / 骨骼选择 =================

func _on_bone_selected(idx: int) -> void:
	_selected_bone = idx
	_update_picker()

func _on_picker_point_clicked(index: int) -> void:
	_selected_vertex = index
	_rebuild_detail()
	_update_picker()

# ================= 当前顶点：各骨骼权重 =================

func _rebuild_detail() -> void:
	if _poly == null or _selected_vertex < 0:
		_clear_detail()
		return
	var n := _poly.get_bone_count()
	for bi in n:
		var weights := _poly.get_bone_weights(bi)
		if _selected_vertex >= weights.size():
			continue
		if _vertex_spin_map.has(bi):
			var spin: SpinBox = _vertex_spin_map[bi]
			spin.set_value_no_signal(weights[_selected_vertex])
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = _pretty_bone_name(_poly.get_bone_path(bi))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var new_spin := SpinBox.new()
		new_spin.min_value = 0.0
		new_spin.max_value = 1.0
		new_spin.step = 0.01
		new_spin.value = weights[_selected_vertex]
		new_spin.custom_minimum_size.x = 90
		new_spin.value_changed.connect(_on_detail_spin_changed.bind(bi))
		row.add_child(new_spin)
		_detail_box.add_child(row)
		_vertex_spin_map[bi] = new_spin
	# 移除已不存在的骨骼行
	var stale: Array = []
	for bi in _vertex_spin_map:
		if bi >= n:
			stale.append(bi)
	for bi in stale:
		var spin: SpinBox = _vertex_spin_map[bi]
		_detail_box.remove_child(spin.get_parent())
		spin.get_parent().queue_free()
		_vertex_spin_map.erase(bi)

func _clear_detail() -> void:
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	_vertex_spin_map.clear()

func _on_detail_spin_changed(value: float, bone_idx: int) -> void:
	if _poly == null or _selected_vertex < 0:
		return
	var weights := _poly.get_bone_weights(bone_idx)
	if _selected_vertex >= weights.size():
		return
	var old := weights[_selected_vertex]
	if absf(old - value) < 0.0001:
		return
	_set_bone_vertex_weight(bone_idx, _selected_vertex, value)

## 把 bone_idx 在 vertex 处的权重设为 value，走 UndoRedo。
func _set_bone_vertex_weight(bone_idx: int, vertex: int, value: float) -> void:
	if _poly == null or bone_idx < 0 or vertex < 0:
		return
	var weights := _poly.get_bone_weights(bone_idx)
	if vertex >= weights.size():
		return
	var ur: EditorUndoRedoManager = plugin.get_undo_redo()
	var old_w := weights.duplicate()
	var new_w := weights.duplicate()
	new_w[vertex] = clampf(value, 0.0, 1.0)
	ur.create_action("设置骨骼权重", UndoRedo.MERGE_ENDS)
	ur.add_do_method(_poly, "set_bone_weights", bone_idx, new_w)
	ur.add_undo_method(_poly, "set_bone_weights", bone_idx, old_w)
	ur.commit_action()
	_rebuild_detail()
	_update_picker()
