@tool
extends EditorPlugin
## 骨骼权重编辑器 - EditorPlugin 入口（精简版）
## 选中 Polygon2D 后，右侧 Dock 显示"点选顶点 + 各骨骼权重"面板。
## 不再接管 2D 视口输入/叠加绘制。

const PanelScene := preload("res://addons/bone_weight_editor/weight_panel.tscn")

var _panel: Control
var _current_poly: Polygon2D

func _enter_tree() -> void:
	_panel = PanelScene.instantiate()
	_panel.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _panel)
	_panel.hide()

func _exit_tree() -> void:
	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null

## 只处理 Polygon2D（2D 蒙皮网格）。
func _handles(object: Object) -> bool:
	return object is Polygon2D

func _edit(object: Object) -> void:
	_current_poly = object as Polygon2D
	if _panel:
		_panel.set_target(_current_poly)
		_panel.show()

func _make_visible(visible: bool) -> void:
	if _panel:
		_panel.visible = visible
