# v0.2 S0 代码落地清单

以 `H:/tongguan_reviewfix_20261015` 为主项目；`H:/tongguan_slice_v01_20261014` 只用于追溯、封存完整性检查，不回写。开工时主项目干净，HEAD `3a67d91e25a24d2c42b5fdd2a370f807c9812fc1`，与设计基线合并提交 `62546a547895e1a6185904ad60bf15fa58c03244` 文件树一致。S0 工作分支 `codex/tongguan-v02-s0` 从该合并提交建立。

需求来源为下载目录两份 v0.2 文档。用户在本聊天确认主目录并要求开工；本批只执行 S0，不自动执行后续批次。

|接入位置|本批动作与验证|
|---|---|
|runtime/army/session.gd|在 autoload 创建缓存前选定 legacy/v02；共享原控制器、GameState/Context 与 city adapter|
|runtime/v02/service_selection.gd、map_services.gd|新场景自动选 v02，显式参数支持 A/B；当前两模式都组合旧显示，不实现流式加载|
|runtime/runtime/asset_cache.gd|同步和异步请求计数；弱引用观测器避免循环引用；仍只有一份旧六页缓存|
|runtime/runtime/city_canvas.gd、review/canvas.gd|原计划和实际树木提交旁采集计数，不实现索引优化|
|runtime/v02/main.tscn、boot.gd、probe.gd|独立入口、固定旧资产、实际尺寸、固定镜头轨迹、原始帧间隔；截图仅在计时外|
|runtime/tests/v02/|先红后绿验证选择顺序、单缓存、共享权威、空指标与实际计数|
|tools/map_v02/|新目录收集命令、退出码、诊断、Release构建、逐次采样、哈希和兼容保护|
|schemas/map_v02/s0_scope.json|精确登记旧文件改动和允许新增路径；不放宽插件素材规则|

旧 v4、Save22、world/site/slot ID、通道、人工补丁、删除与锁区不改。旧 manifest、旧发布包、旧报告保留。新源码 manifest 独立记录旧基线与当前哈希；仓库检查同时验证允许范围。

复验包括 REV-01 完整占地、REV-02 原生树边缘像素、REV-03 原始ID与跨块提交，以及相关旧视图、建设、存档、制作发布和原权威接入。另跑插件源检查及封存保护检查。每次输出写入新的独立目录，保留红灯与失败记录。

观测值严格区分：树候选/实际提交、资源请求/当前缓存持有的唯一纹理、RGBA8完整mip链估算/Windows测量GPU占用。释放次数尚未采集，写 null；不把隐藏或缓存保留说成卸载。帧间隔为CPU单调时钟观测，不冒充GPU提交/呈现时间。

固定原生profile：实际1920×1080渲染缓冲、Godot4.6.1 Compatibility、旧资产、3秒预热、相同30秒镜头轨迹；legacy/v02各三次60秒及一次300秒。探针临时使用viewport缩放模式固定光栅负载，客户端尺寸/DPI独立实测并检查全程稳定。记录所有轮次、最差值和33/50/100ms长帧，预算p95≤16.7ms、p99≤25ms。任何实测尺寸或预算失败照实保留。

交付：可运行入口与独立Windows包、当前源码清单/产物哈希、旧回归和实际尺寸证据、指标说明、未执行/失败项、改动清单及回退说明。完成后停在S0验收；V1组合画面、美术认可、流式调度、全国容量和Q1总验收保持未完成。
