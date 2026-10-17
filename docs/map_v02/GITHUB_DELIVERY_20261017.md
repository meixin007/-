# 潼关地图 v0.2：源码、运行包与验收证据

v0.2的S0/V1/E1/E2/E3/V2/C1/Q1已完成。C1由用户通过，Q1包含35项矩阵、19组保护回归、本机实际1080p三次60秒和一次300秒压力测试。最差p95为2.853ms、p99为3.26467ms，正常稳态没有超过33ms的帧。

## 下载并运行

[v0.2 Q1 Release](https://github.com/meixin007/-/releases/tag/tongguan-v0.2-q1-20261017)提供：

- `Tongguan-v0.2-Q1-Windows-x64.zip`：完整解压后运行`Start-Q1.cmd`。EXE与PCK保持同目录；不需要编辑器。
- `Tongguan-v0.2-Q1-editable-Godot-project.zip`：完整解压，以Godot4.6.1打开`GodotProject/project.godot`，入口`v02/q1/main.tscn`。冻结的表现包、纹理导入参数和脚本UID均包含，`.godot`缓存排除；无需依赖开发机器的`review-work`目录。
- `Tongguan-v0.2-Q1-complete-evidence.zip`：完整封存Q1报告，包括Git忽略的原始日志与无损压缩的重复大回执。对照其中`DELIVERY_MANIFEST.json`可验证每个成员。
- `Tongguan-v0.2-Q1-native-fixtures.avi`：未剪辑的工程夹具、故障回退与阈值切换录像。固定30fps，与正式不限帧性能统计分开。
- `SHA256SUMS.txt`及`RELEASE_MANIFEST.json`：下载产物校验。

## 操作与报告

1—4切换组合、院落、区域和远景；滚轮缩放，拖动平移。U/R卸载与重载，C/B建设前与开工，D一天，X/F损毁与修复，H/J成长与关门，G/T分页线与地形独显。5/N为工程夹具与下一片，Tab/K为工程势力与归属颜色。

[系统设计](01_系统设计文档_v0.2.md) · [批次说明](02_实施批次与首条开发任务_v0.2.md) · [Q1报告](../../reports/map_v02/tongguan_v02_q1_20261016_04/REPORT.md) · [验收矩阵](../../reports/map_v02/tongguan_v02_q1_20261016_04/ACCEPTANCE_MATRIX.json) · [最终本地包校验](../../reports/map_v02/tongguan_v02_q1_20261016_04/DELIVERY.json)

开发机报告中的绝对路径作为原始证据保留。跨机器阅读请使用本页的Release与相对源码链接；完整可编辑项目从上述源工程ZIP打开，仓库原默认入口继续保留旧版本。源码构建脚本在`tools/map_v02/`，包协议在`schemas/map_v02/`。

## 已验证范围

视觉继承用户认可C1；工程、兼容保护、实际释放重载、本机1080p性能及本地发布回退通过。1939个开工前文件不变，没有覆盖旧地图、素材或旧发行；未生成新AI美术，未量产内容。旧内容A/B兼容适配有额外开销，未宣称提速。

精确756年历史复原、全国容量与内容生产、第二真实地理节点、主工程默认入口接入均不属于本次完成声明。现代地形/水域来源及东亚粗示意保留原范围；Godot与素材授权见仓库来源说明及发行包内的通知。

| 发行文件 | 字节 | SHA256 |
|---|---:|---|
| Tongguan-v0.2-Q1-Windows-x64.zip | 210488549 | `1015008595e818d642988e0bbf124afe5eb6d6d1b6e5f77fa82da30ae3fa8ec8` |
| Tongguan-v0.2-Q1-editable-Godot-project.zip | 103424105 | `af20d6dca0097d7e63d8544e20515ec04741e0715b1d7c46e0a31e131ac15aaa` |
| Tongguan-v0.2-Q1-complete-evidence.zip | 147957898 | `695874df0690b0a34e6f7eeb93c1daa7c2cec978fa6c8f67d3b8d6611db274a3` |
| Tongguan-v0.2-Q1-native-fixtures.avi | 463665608 | `47abb19eb40c01921592d7c57ce97dee83a89a45435f90a529a6524d4c5fa77b` |
