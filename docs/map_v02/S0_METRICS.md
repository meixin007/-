# S0 观测字段与复现

S0 两个模式均使用旧显示器与六页常驻缓存。`v02` 是新入口和可观测性接线，不是完成的流式地图。模式在 Session autoload 构造缓存之前选定；不存在第二个 GameState、Context 或同时运行的第二份完整缓存。

|字段|采集来源与含义|
|---|---|
|dimensions.viewport_texture_px|`Window.get_texture().get_size()`，实际可读回渲染纹理尺寸；另以计时外PNG尺寸交叉核对|
|dimensions.window_client_px|`DisplayServer.window_get_size()`，不以配置值代替|
|content_scale_size / mode / factor|运行时Window属性；同时记录显示服务、DPI、引擎与驱动API字符串|
|tree_plan_rebuilds|实际调用原 `Instances.plan()` 的累计次数；S0仍会随重绘增加|
|tree_candidates_tested|进入原全量计划的记录数累计值，尚非空间查询返回数|
|tree_submitted_objects|树木通过实际绘制矩形剔除并调用 `draw_texture_rect()` 后累计计数；不等于所有类型的GPU draw call|
|last_draw|当前绘制调用的候选、提交、计划次数和CPU计划耗时；低LOD无树绘制时清零|
|resources.request_count|实际同步load及异步load_threaded_request调用数；失败单列，未按文件路径去重|
|resident_unique_textures|枚举当前缓存持有的纹理，AtlasTexture追到共享底图，按Resource实例去重；不统计整个引擎的所有资源|
|unique_estimated_bytes|上述纹理宽高按RGBA8、完整mip链估算；不做每帧get_image，不等于实际GPU显存|
|async_attach_count / attach_max_ms|旧缓存实际获取异步纹理结果的计数与CPU耗时；不是GPU上传计时|
|release_count|null，`not_instrumented`。S0没有实现淘汰与真实最后引用释放观测|
|frame_p95_ms / p99 / max|`Time.get_ticks_usec()`观测相邻process_frame的CPU侧间隔；不声称是GPU单项耗时或精确呈现时间|
|entry_to_interactive_upper_bound_ms|进入probe之后至UI创建并经过若干帧、可拾取的上界；不包括进程创建前阶段|
|gpu_first_frame_timestamp|null，没有可靠的GPU首帧时间来源|
|Windows private / dedicated GPU|独立进程监测器100ms内存采样、约1Hz GPU采样；GPU计数不可用时保留null|

`frames.csv`逐帧记录单调时间、帧间隔、实际镜头阶段、LOD、候选、提交、计划耗时和累计计划次数。每秒保留资源快照。>33/50/100ms长帧保留时间和镜头，不删外部抖动。截图只在预热前采集；性能循环不做截图读回。

profile位于运行端 `v02/profiles.json`。正常档为每模式3×60秒及1×300秒；30秒固定轨迹覆盖总览、区域、地形、关门、树林与近景。短于30秒的冒烟运行压缩周期并显式标记diagnostic，不参加正常profile验收。

性能探针临时使用Window.CONTENT_SCALE_MODE_VIEWPORT和1920×1080基础大小，固定实际光栅缓冲；客户端随全屏/桌面大小变化，独立记录，绝不冒称客户端也是1920×1080。每秒记录并校验尺寸、缩放与DPI稳定。正常手动入口仍使用原canvas_items配置。所有A/B性能运行使用同一个S0 PCK、同一组旧素材，通过 `--map-service=legacy|v02` 选择模式。另导出旧默认入口PCK，验证兼容。

此修正来自_04首轮60秒的失败证据：启动纹理1920×1080，结束4309×2425，窗口变为2880×1618；该轮退出1且不参加预算结论。Godot官方说明：全屏匹配显示器尺寸，canvas_items按目标大小绘制，viewport按基础大小绘制后再缩放。见[Window内容缩放模式](https://docs.godotengine.org/en/4.6/classes/class_window.html#enum-window-contentscalemode)与[多分辨率说明](https://docs.godotengine.org/en/4.6/tutorials/rendering/multiple_resolutions.html)。

官方Windows Release模板禁用命令行场景路径覆盖，因此启动器使用各自PCK中预设的入口。源码项目的默认main.tscn不变；构建S0 PCK时在隔离staging中临时设置v02/main.tscn，完成后恢复staging的project.godot。两个EXE来自同一官方Release模板，功能区别在同名PCK。

进程检查只采集开始/结束快照，不宣称持续检测所有瞬时外部进程。已有用户进程不会被关闭；必要的超时终止仅限本次runner创建的子进程。不清空OS磁盘缓存，重复运行不称为冷启动。

所有探针写入独立证据目录或user://tests/map_v02；手动S0入口的保存/导入目标也改为该测试域。旧默认入口的手动存档行为保持兼容；原生兼容测试使用既有user://tests路径。不会读取并修改玩家默认存档。

```powershell
python tools/map_v02/check_source.py --output review-work/map_v02/source_final
python tools/map_v02/build_s0.py --build-id <fresh_build_id>
python tools/map_v02/run_native.py --build-id <fresh_build_id> --mode v02 --seconds 3 --default-selection --output review-work/map_v02/<fresh_smoke>
python tools/map_v02/run_profiles.py --build-id <fresh_build_id>
python plugin-source/verify_source.py
python verify_repository.py
python tools/verify_review_protection.py
```

脚本拒绝覆盖已有构建和结果目录；复跑必须使用新目录。`source_final`为套件默认的当前源码回归收据位置，若已经存在，应保留旧目录并调整套件收据路径，不覆盖旧记录。
