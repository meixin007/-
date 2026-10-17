# E3：资源生命周期实现边界

本批在`runtime/v02/e3`新增一套表现资源调度，复用未修改的E1包验证器、E2源适配／空间查询／排序／提交审计。工程流式夹具、4×4边界夹具和实际潼关使用同一个MapService与ResidencyManager。原默认玩法入口、唯一GameState、v4、Save22与旧封存交付保持原样；C1负责后续正式入口整合。

## 调度契约

1. E1只解析和验证不可变包元数据、源文件哈希及兼容性，不调用其同步texture()/resolve_page()。准入解析仍同步校验包文件，不把它描述为后台包解析。纹理经Godot4.6线程请求加载，仅LOADED后get；每个已开始任务保留到取回或明确失败。相机改需求序号，世界／包切换才增加epoch。
2. UNLOADED→QUEUED→LOADING→READY_CPU→ATTACHING→RESIDENT；失败保留FAILED，显式retry。淘汰先EVICT_PENDING、清除CanvasItem命令和Node纹理引用，再移除唯一资源强引用。共享纹理以导入路径+源哈希合并，消费者按页／稳定对象ID引用；过期任务若无当前消费者则取回后释放，当前兼容消费者可认领相同内容。
3. 稀疏目录建立页桶；镜头按层查询实际存在的页，祖先提供覆盖，不遍历全部详细对象。根底图优先于中间父页，详细页次之，预取最后且最多4页。大视野选粗层。E2对象候选决定共享图集需求。显示层的节点与缓存只持有当前资源，旧绘制命令在淘汰回调中同步清空，再remove_child/queue_free。
4. 唯一RGBA8逻辑字节包含真实宽高、gutter与base层，符合E1无mip／lossless导入契约。共享图集只计一次，父子过渡同时计入。resident+LOADING/READY预留受硬准入限制，解码预留另受限，最多2个请求在途。软预算抑制细节/预取，先清无依赖旧页，再退详细页／中间父页，保留可负担根底图。硬预算突然小于已开始预留时停止新准入、保留任务并安全排空；该暂时超额必须出现在账本。
5. get、采用和验证共用2ms不可抢占预算；用完后推迟后续操作。绘制命令构建使用该帧剩余预算，未完成计划下一帧继续，已有低清覆盖保留。记录单操作超时，绝不称2ms为驱动/GPU硬上限。生产采用不做GPU图像读回；发行验证在稳定帧另行读回实际纹理检查pixel_sha256，不混入挂接或正式帧时数据。
6. 短时父子淡化受同一驻留预算约束。缩预算时先移除详细命令，下一帧回退到仍驻留的父／根页。对象不双画；未完成语义地点LOD、经济或建设玩法迁移。

## 可复现证据

`e3_build.py --build-id <fresh-id>`生成新的独立SOURCE_RUNTIME、exe/pck/cmd和构建收据，不写旧发行。工程流式页为8×32个256px core、4px gutter的数值地形；每页具有不同内容哈希。这是低分辨率工程压力夹具，不代表已完成1024px正式地形或历史城市内容。配置在运行前冻结：正常256/320MiB、64MiB解码；压力4/8MiB、4MiB解码、宽限0（有意强制淘汰），均为并发2、2ms挂接。

`e3_native.py --build-id <id> --run-id <fresh-run>`从只含exe/pck/cmd的目录执行：实际1920×1080；20轮、64机位单世界往返；唯一访问量>软预算3倍；每资源request/attach/drop/reload/实际WeakRef失效事件；相同机位的驻留集、引擎Resource数和纹理内存窗口。记录自有进程PrivateUsage，驱动独占显存未测时为null。无GPU/RSS立即回零承诺。

故障包括真实缺页、源哈希拒绝、延迟真实请求、A→B→A、包切换旧完成、父子build不匹配、共享图集最后消费者、预算在淡化中下降。还有反向对照：故意断开淘汰回调并暂停自动重绘，清自有缓存后检测到真实绘制节点仍持有纹理；恢复清理后WeakRef失效。测试不能只看失败数组，还必须看退出码、超时及ERROR/WARNING/泄漏诊断。

交互模式的事件/逐帧历史有界，已失效WeakRef转为轻量事件后丢弃，避免观测器自身积累Resource对象；验收模式显式保留完整日志。因此PrivateUsage同时包含测试历史与引擎分配池，不能直接等同驻留纹理。

原包文件、原地图和PNG按开工前哈希逐一核验。旧几何、owner、发布、通道、建设、存档、E1/E2契约重跑；旧V1美术收据不改。Q1的3×60s+300s正常帧时矩阵、独占GPU预算、C1正式玩法接线和V2完整视觉不由E3签署。

API依据：[Godot 4.6 ResourceLoader](https://docs.godotengine.org/en/4.6/classes/class_resourceloader.html)、[后台加载](https://docs.godotengine.org/en/4.6/tutorials/io/background_loading.html)、[RenderingServer命令清除](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#class-renderingserver-method-canvas-item-clear)。
