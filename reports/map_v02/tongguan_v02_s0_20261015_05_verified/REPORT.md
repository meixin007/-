# 潼关 v0.2 S0 技术候选

构建 `tongguan_v02_s0_20261015_05`，分支 `codex/tongguan-v02-s0`。本批完成基线接线、独立入口、观测与旧回归，停止在S0验收；不是整套v0.2完成。源检查、原生检查和百分位预算分别见下。用户验收pending。

## 版本与执行环境

主项目 `H:/tongguan_reviewfix_20261015`；历史项目 `H:/tongguan_slice_v01_20261014` 只读追溯。原HEAD `3a67d91e25a24d2c42b5fdd2a370f807c9812fc1` 与设计合并基线 `62546a547895e1a6185904ad60bf15fa58c03244` 文件树一致，工作分支从合并提交创建。开工时无未提交修改。

Godot4.6.1 official，GL Compatibility，RTX4060，实际渲染纹理固定1920×1080，客户端与DPI独立实测。探针使用viewport基础分辨率，正常手动入口保留canvas_items；不将窗口放大说成提高渲染分辨率。硬件原始来源见environment.json；Win32_VideoController.AdapterRAM存在32位限制，不将其数值当作实际显存总量。窗口模式更小缓冲及_04运行期间尺寸变化的失败证据保留。

运行时配置（同一配置去重列出）：
- 渲染 [1920, 1080]，客户端 [1920, 1080]，DPI 96，content_scale_mode=2，factor=1.0

## 正确性、失败与未执行项

当前源码回归：`True`；原生兼容：`True`；S0正确性与源码一致性：`True`。原生旧入口 `58` 项，REV-02树边缘像素 `86` 项。所有原始命令、退出码与诊断在source/及native/。

开发期失败全部保留在development_evidence/：新入口尚不存在时的契约红灯；Release不支持命令行覆盖场景；原生探针两个变量无法推断类型（增加显式脚本解析回归后修复）；窗口尺寸未达到目标；JSON数字浮点数组与整型实测数组比较导致的尺寸误判（独立红绿回归后修复）；_04首轮60秒因渲染尺寸变化退出1（固定探针基础缓冲后重测，旧数据不计入正式结果）。构建工具早期Git中文路径引用错误发生在产物目录创建前，已改为NUL分隔原始路径解析；该次无发行产物。早期_01—_04构建保留在review-work，不作为交付。

初次报告的默认Git空白检查将原生CRLF误报为行尾空白。按仓库`* -text`及既有CRLF格式，仅在该条命令启用`cr-at-eol`后通过，仍检查行尾空格与缩进；运行源码字节未改。原失败输出保存在development_evidence/initial_whitespace_check/。

流式调度/淘汰、V1新组合画面、历史准确性、第二节点、全国容量及Q1全矩阵均未执行。正式样本没有>33ms帧；_04无效样本的长帧原始记录保留，未作外部/地图归因。

## 当前实现

新入口为runtime/v02/main.tscn。Session在创建缓存前选择视觉服务，两个模式共用原控制器、GameState/Context和一份六页缓存。v02通过组合委托旧显示；未创建新游戏权威、存档格式或生成器。原绘制计划仍为全量重建，计数如实显示。

指标说明见[观测字段](../../../docs/map_v02/S0_METRICS.md)，落地范围见[实施清单](../../../docs/map_v02/S0_IMPLEMENTATION.md)。实际资源请求、候选、树提交及唯一纹理估算已采集；释放数为null/not_instrumented。唯一字节数按RGBA8完整mip链估算，Windows GPU占用另采，不能互相替代。

## 视觉边界

composition.png为计时外的旧素材同镜头截图。新旧模式截图哈希一致性见screenshot_comparison.json；这只验证S0显示保持一致，不是V1手绘组合认可。美术、历史与用户验收保持独立。

## 固定profile与帧时

同一S0 PCK、同一组旧素材、3秒预热、30秒固定轨迹。每模式3×60秒及1×300秒，全部六种镜头阶段的逐帧覆盖：`True`。无截图读回进入性能循环。开始/结束进程快照检查，不擅自终止用户程序，也不声称清空OS磁盘缓存。

|运行|实测秒|p95 ms|p99 ms|最大 ms|>33/50/100ms帧数|百分位预算|
|---|---:|---:|---:|---:|---|---|
|01_legacy_60s|60.003|7.374|8.799|14.280|0/0/0|达标|
|02_v02_60s|60.003|7.362|8.700|13.371|0/0/0|达标|
|03_v02_60s|60.003|7.332|8.927|12.530|0/0/0|达标|
|04_legacy_60s|60.003|7.474|8.590|13.048|0/0/0|达标|
|05_legacy_60s|60.004|7.404|8.540|12.582|0/0/0|达标|
|06_v02_60s|60.002|7.406|8.823|10.813|0/0/0|达标|
|07_legacy_300s|300.004|7.496|8.968|23.415|0/0/0|达标|
|08_v02_300s|300.001|7.315|8.563|12.473|0/0/0|达标|

冻结预算p95≤16.7ms、p99≤25ms。全部百分位预算：`True`；全部性能运行资格：`True`。每模式最差轮次和Windows内存峰值另列worst_by_mode.json，不挑最好一轮。正式样本中>33/50/100ms均为0；结论范围是本机S0旧素材基线，不是Q1或全国容量验收。

## 旧源码回归

|用例|断言数/标记|结果|
|---|---:|---|
|old_document|PASS标记|通过|
|art_import|14|通过|
|geometry|24|通过|
|ownership|14|通过|
|publication|6|通过|
|view|41|通过|
|passage|34|通过|
|construction|52|通过|
|save_migration|32|通过|
|original_host|29|通过|
|manual_layout|62|通过|
|authoring|208|通过|
|size_guard|PASS标记|通过|
|s0_contract|26|通过|

REV-01/03保留原回归，REV-02实际纹理像素检查在原生Release执行。新契约包含默认选择、显式覆盖、重复/非法模式、脚本编译、单缓存、共享状态、真实计数、空指标和JSON尺寸比较。

## 兼容、交付与回退

scope.json逐文件核对 `851` 个不允许修改的基线文件。旧v4、Save22、world/site/slot、通道、人工补丁、删除、锁区及PNG未改；插件仍为空素材注册表。sealed_protection.txt复验580封存源码及旧EXE/PCK/ZIP。旧REVIEW/PUBLIC/历史build清单原样保留，新源码使用V02_SOURCE_MANIFEST.json，当前构建用独立BUILD.json与ARTIFACTS.json追溯。

Windows包：[打开S0](../../../review-work/map_v02/tongguan_v02_s0_20261015_05/release/Windows/Start-S0.cmd)；[打开本批legacy对照](../../../review-work/map_v02/tongguan_v02_s0_20261015_05/release/Windows/Start-Legacy.cmd)。无需Godot或Python运行。两个EXE与各自同名PCK必须一起保留。S0手动入口保存路径为user://tests/map_v02/manual，未接管玩家默认存档。

回退优先直接运行旧封存_02或_03发行包；源码回退在独立目录检出 `62546a547895e1a6185904ad60bf15fa58c03244` 即可。当前工作分支保留全部S0改动；不要重置或覆盖主工程、旧发行包或用户地图。本批未提交、推送或发布GitHub Release。
