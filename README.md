# KE-GODOT-TOOL
用来存储自己用DSH写的一些GODOT插件

所有插件统一放在仓库的 `addons/` 目录下，每个插件一个子文件夹（符合 Godot 插件规范）。
使用某个插件时，把对应的 `addons/<插件名>` 文件夹复制到目标项目的 `addons/` 下，
再在 **Project → Project Settings → 插件 / Plugins** 里启用即可。

## 插件列表

- [骨骼权重编辑器 (Bone Weight Editor)](./addons/bone_weight_editor/README.md) —— 为 `Polygon2D`（2D 蒙皮网格）提供逐顶点、逐骨骼的权重查看与设置。
