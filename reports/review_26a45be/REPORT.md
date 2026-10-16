# 26a45be 阶段一审查修复与复验

构建：`tongguan_v01_revfix_20261015_02`。只读基线：`26a45be93e62fc56199ed42d98895926380383c5`。
独立修复副本：H:/tongguan_reviewfix_20261015；分支 codex/tongguan-rev01-03-20261015。基线提交和封存发行未改写。
先提交可失败回归：`959cac0`；三个审查项完成技术修复，等待用户本阶段验收。

## 审查项与红绿对应

|项|固定旧基线实测|修复后实测|结论|
|---|---|---|---|
|REV-01|19项中8失败|24项全通过|有限线段到闭合矩形的最短距离覆盖内部穿越、端点、斜线；40/45m半宽与相切内外测试通过|
|REV-02|85项中16失败|Release86项全通过|实际柳树/树丛及高比例合成素材，最大缩放2.4，四边7个缓慢进出位置，整块像素与无剔除对照一致|
|REV-03|6项中3失败|14项全通过＋原生58项中的实际提交审计|原始v4列表在字典投影前查重，key/record.id一致；跨4块索引只派生一个owner，重复提交/错误owner变异会失败|

红灯JSON、退出码及对照图见 [red](red/summary.json)。原生对照将内容缩放关闭，避免坐标采样错位；早期伸缩画布的无效尝试未计入红灯证据。
REV-01新增采用、移动、候选和发布使用严格检查；完整占地相切允许，比较容差0.0001m，内外回归相差0.001m。
缓存仅复用不变有限线段，避免逐对象反复建立线段数据。REV-02只替换树的视口判定，使用真实尺寸和锚点加1px余量。

## 旧数据与保存语义

默认95个对象的完整制作状态SHA256前后一致：
`f3572d76788116863cc6ed1de64a0d0eb96df28be48b8afdf31abe9c49bc6a9a`。
输入及发布哈希也一致，见 [identity_preservation.json](identity_preservation.json)。
现有地点、八地块、生成对象ID、人工补丁、删除记录、锁区、v4 features/presentation.instances和Save22语义保留。
world_id仍为 tongguan_final_validation_v1，图版本仍为 tongguan_controlled_corridor_r3_v01，生成器仍为 forest_grid_sha256_v2。

新检查下默认95对象冲突数为0。另构造旧算法允许而新算法拒绝的校验有效旧工作区，证明重读不改对象/文件；只读报告列明ID、原因及完整占地；未改变的旧内容可带明确警告发布，用户显式删除仍保留tombstone，撤销/重做恢复同ID。
制作端增加“报告完整占地冲突（只读）”入口。没有静默迁移、移动、删除或重新编号旧内容。
owner仅是派生显示索引，没有写入v4或存档。

## 源码回归

|项目|断言数|结果|明细|
|---|---:|---|---|
|旧v4文档与编辑器路径诊断|原PASS标记|通过|[证据](source/old_document/runtime.txt)|
|既有美术导入反馈|14|通过|[证据](source/art_import/runtime.txt)|
|制作保存容量上限与旧文件保留|1|通过|[证据](source/size_guard/runtime.txt)|
|REV-01完整占地|24|通过|[证据](source/geometry/runtime.txt)|
|REV-03原始ID与跨块唯一性|14|通过|[证据](source/ownership/runtime.txt)|
|发布占地保护|6|通过|[证据](source/publication/runtime.txt)|
|四档视图与拾取计算|41|通过|[证据](source/view/runtime.txt)|
|主关/河流/合成险径通行|34|通过|[证据](source/passage/runtime.txt)|
|实际资源建设与日结|52|通过|[证据](source/construction/runtime.txt)|
|R3/R4存档迁移、校验及恢复|32|通过|[证据](source/save_migration/runtime.txt)|
|原GameState/Context/SaveManager接入|29|通过|[证据](source/original_host/runtime.txt)|
|仓库补丁与地块保护|62|通过|[证据](source/manual_layout/runtime.txt)|
|人工补丁/删除/锁区/撤销/发布|208|通过|[证据](source/authoring/runtime.txt)|

插件、运行端和制作端的headless导入均通过；插件空注册表检查通过。未修改原战役移动权威链，编辑器RoutePreview仍只做诊断。

## 原生Release复验

|项目|断言数|执行|明细|
|---|---:|---|---|
|原生制作保护|163|通过|[证据](native/authoring/result.json)|
|原生四档/慢速阈值往返/拾取/主关/建设/存档|58|通过|[证据](native/verify/result.json)|
|REV-02实际树种＋高合成素材四边像素|86|通过|[证据](native/tree_edges/result.json)|
|20次界面进出与驻留缓存|23|通过|[证据](native/cycles/result.json)|

Release模板检查通过。全部原生运行退出正常，无SCRIPT ERROR、ERROR、WARNING、退出资源泄漏诊断。
四档慢速阈值往返各20轮；大坐标锚点、地块与地点拾取、主关闭锁/重开、无桥不可跨河、轻装险径条件仍通过。
原生实际绘制提交检查非空ID列表及跨块平移后的唯一owner，替代Dictionary数量恒等式。
20次界面进出（保留Session.cache）私有内存中位窗口差为 -4.957MiB，预算≤16MiB；它不代表卸载/加载大量不同区域。

## 本机构建与性能边界

Windows10 19045，Ryzen7 5700X，约16GB RAM，RTX4060 8188MiB，驱动616.92，Godot4.6.1 official，GL Compatibility。
项目配置1920×1080；本机窗口受桌面边框限制，实际客户端截图1886×1061（专用树边缘对照禁用内容缩放后为1920×1061）；不能把本次窗口测量称为全屏1080p认证。
所有性能模式启动前其他Godot/Tongguan进程数见各result.json；不结束用户其他进程。

|配置|采样时长|p95 ms|p99 ms|最大帧 ms|执行|百分位预算|
|---|---|---:|---:|---:|---|---|
|60秒实景轨迹|60.032s|9.596|13.086|89.802|通过|达标|
|300秒实景耐久|300.032s|9.345|11.321|189.667|通过|达标|
|1个纯显示副本|约3s|5.699|7.350|—|通过|达标|
|4个纯显示副本|约3s|15.145|17.663|—|通过|达标|
|16个纯显示副本|约3s|60.792|73.306|—|通过|超预算|

预算：p95≤16.7ms、p99≤25ms；进程私有内存≤4GiB、独占GPU采样≤1.5GiB。每档另有execution_passed/budget_passed，load顶层passed同时要求全部档达标。
first_view_ms起点在验收入口内；进程启动到日志观察ready只是受日志缓冲影响的上界，均不是精确冷启动首帧。
RAM采用连续Windows采样窗口；Release日志缓冲后的读取时间不冒充每次退出时内存。
显示副本只是同一对象集的绘制压力，不是独立城市、不增加世界或军队，不能推导全国容量。

## 产物哈希

|文件|字节数|SHA256|
|---|---:|---|
|TongguanAuthoring.exe|104576512|6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20|
|TongguanAuthoring.pck|4462504|ffa0c9db9b2533fa049b0dcd29a4e27e2e90ce930472f0c80103ece55d207580|
|TongguanFinal.exe|104576512|6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20|
|TongguanFinal.pck|15375484|2a04c8d80eb66e1010169422de59faa056896916af26634ce2a14b374b10495b|

[发行记录](RELEASE.json) · [587文件冻结源码清单](SOURCE_MANIFEST.json)。
两EXE哈希相同是同一官方Release模板，修复内容位于不同PCK；必须与本次同名PCK一起运行。

## 封存保护与已知问题

[保护检查](protection.json)：旧_03的580源码、4个Windows产物、原ZIP均匹配原SHA256；146项插件/样板bundle/旧fixture/历史文档等基线文件未变。旧GitHub导出副本仍在基线且干净。
原主工程没有本任务写入；没有初始完整Git状态快照，因此不声称其全工作区状态与过去严格相同。
旧PUBLIC_SOURCE_MANIFEST、PUBLIC_FILES、历史验收记录保留为基线收据；当前样板源码校验改用REVIEW_SOURCE_MANIFEST.json。

- 正式美术、透视/岸坡组合、精确756地理仍待独立视觉与史料验收。
- 当前仍是六地形块的单节点缓存，树列表仍全量生成显示计划；没有完成全国流式加载或容量认证。
- 多显示副本超预算见上表，保留为未解决限制；本次不借机实现全国生成器或新增历史节点。
- 本次_01为补齐缺失投影错误处理前的内部构建，保留在临时目录；仅_02作为交付候选。
- 技术修复完成不等于用户最终验收，也不自动进入下一阶段。

## 复现

Windows安装Godot4.6.1及对应官方Windows Release模板。设置GODOT_BIN/GODOT_WINDOWS_TEMPLATE可覆盖本机路径。

```powershell
python tools/run_review_red.py
python tools/run_review_checks.py
python tools/build_review_release.py
python tools/run_review_native_suite.py
python tools/verify_review_protection.py
python verify_repository.py
```

red工具重新展开固定提交并只复制回归夹具，旧核心不变；退出0表示预期回归成功暴露，夹具子进程分别退出1。
构建和原生报告路径拒绝覆盖；复跑需新的构建ID和独立工作目录。封存保护检查依赖原隔离副本路径；不在该机器时请提供该封存目录。
完整命令参数在tools脚本；测试仅写独立副本和user://tests测试目录，不接管玩家存档或主工程。
