# 山河形胜二维地图工坊 · 源码版

2026-10-14 从当前本地 `addons/strategic_map_editor` 导出的独立源码。保留地图编辑、几何运算、河流笔刷、资源导入、恢复与导出代码；不携带原美术素材、素材包描述、地图草稿、截图、缓存、凭据或主游戏数据。

## 使用

使用 Godot 4.6.1 标准版打开本目录的 `project.godot`，运行即可进入空白工坊。也可以只复制 `addons/strategic_map_editor` 到自己的 Godot 工程，在项目设置 → 插件中启用，进入“山河工坊”。安装目录名称应保留。

两个原本位于主游戏的纯表现脚本已移入插件目录，相关 preload 改为相对路径。启动示例使用独立 user:// 目录，不恢复原项目的上次地图。

`art/tongguan_v1/catalog.json` 和 `manifest.json` 是新生成的空注册表配置，assets 为空；它们不是原美术素材清单。可通过工坊导入自己的透明 PNG：边长 32–4096 像素、不超过 16 MiB、四边留透明边缘。导入后的图片及非空注册表不得上传到本源码目录。

## 验证

```bash
python verify_source.py
godot --headless --path . --editor --quit
godot --headless --path . --script tests/test_art_import_feedback.gd
godot --headless --path . --script tests/test_document.gd
godot --headless --path . --quit-after 8
```

`verify_source.py` 检查源码允许列表、空素材注册表、空白示例和 preload 依赖闭包。导入反馈检查沿用现有的 14 项回归；文档检查覆盖编辑、撤销、保存重开及通行规则。测试图片在独立 user:// 中生成，不包含于仓库。当前验证结果记录于 `VALIDATION.json`。

## 范围

普通编辑、保存与导出不依赖主游戏。插件仍保留“更新游戏主地图”和“在现有游戏地图中预览”的原集成代码；这些入口要求原游戏地图坐标、地点定义或主游戏工程，独立源码版不具备对应数据。现有含素材地图需要用户自行提供匹配素材包，不能用本版的空注册表替代。

原 `input/` 是 2026-09-30 的只读历史快照，未由本次更新修改。旧历史快照已经含有图片，本次仅新增源码，不删除历史图片、不重写 Git 历史。Linux 渲染、原生编辑器交互和美术认可仍需各自验证。

本次不新增开源许可证；仓库现有权限和使用授权保持。
