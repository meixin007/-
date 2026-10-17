extends Control
const Service=preload("res://v02/e3/map_service.gd")
const Renderer=preload("res://v02/e3/map_renderer.gd")
var service=Service.new()
var renderer: Control
var config: Dictionary
var info: Label
var note: Label
var x:=256.0
var y:=256.0
var zoom:=1.5
var active:="stream"
var errors: Array=[]
var _stamp:=0
var _shutting_down:=false
func label_at(text: String,pos: Vector2,extent: Vector2,font_size: int=16) -> Label:
	var label=Label.new();label.text=text;label.position=pos;label.size=extent;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);add_child(label);return label
func button(text: String,y_pos: float,callback: Callable) -> void:
	var node=Button.new();node.text=text;node.position=Vector2(1640,y_pos);node.size=Vector2(250,38);node.pressed.connect(callback);add_child(node)
func _ready() -> void:
	get_tree().auto_accept_quit=false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e3/config.json"))
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var skin=Theme.new();skin.default_font=font;skin.default_font_size=16;theme=skin
	var background=ColorRect.new();background.color=Color("273c3c");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	label_at("潼关 / 按需加载、释放与重载",Vector2(24,17),Vector2(1200,40),27)
	label_at("E3 · 同一调度服务 · 真实异步请求 · 唯一纹理字节与引用记录",Vector2(25,58),Vector2(1400,30),15)
	renderer=Renderer.new();renderer.presenter=weakref(self);renderer.position=Vector2(20,96);renderer.size=Vector2(1600,940);add_child(renderer);service.bind_renderer(renderer)
	button("1　256页流式夹具",165,func():choose("stream"))
	button("2　4×4 边界 / 缺页夹具",213,func():choose("lab"))
	button("3　原潼关有效快照",261,func():choose("tongguan"))
	button("N　跳往下一片区域",319,next_region)
	button("C　释放全部后重新加载",367,reload_view)
	button("B　切换低预算 / 默认预算",415,toggle_budget)
	info=label_at("",Vector2(1640,485),Vector2(260,330),15)
	note=label_at("",Vector2(1640,825),Vector2(260,175),14)
	label_at("拖动平移 / 滚轮缩放 / Esc退出　·　工程分页不写入战役；缺失细页保留父页覆盖",Vector2(24,1043),Vector2(1590,25),13)
	choose("stream")
func choose(id: String) -> void:
	var result: Dictionary=service.open(config.packages[id])
	if not result.ok:errors.append(result);return
	active=id
	service.manager.set_budget(config.profiles.stream if id=="stream" else config.profiles.normal)
	if id=="stream":x=256;y=256;zoom=1.5
	elif id=="lab":x=0;y=0;zoom=.65
	else:x=0;y=-270;zoom=.84
	refresh()
func refresh() -> void:
	var result: Dictionary=service.set_view(Rect2(x-renderer.size.x/(zoom*2),y-renderer.size.y/(zoom*2),renderer.size.x/zoom,renderer.size.y/zoom),zoom)
	if not result.ok:errors.append(result)
func _process(_delta: float) -> void:
	if service.loader==null:return
	service.tick();renderer.render(service,x,y,zoom)
	if Time.get_ticks_msec()-_stamp<100:return
	_stamp=Time.get_ticks_msec();var t: Dictionary=service.manager.telemetry();var a: Dictionary=t.accounting
	info.text="配置：%s\n驻留：%.2f MiB\n在途预留：%.2f MiB\n软 / 硬：%.1f / %.1f MiB\n在途：%d / 2\n请求 / 采用：%d / %d\n释放 / 重载：%d / %d\n候选 / 可见：%d / %d\n挂接最大：%.2f ms\n挂接超2ms：%d"%[t.profile.id,a.resident/1048576.0,a.reserved/1048576.0,t.profile.soft/1048576.0,t.profile.hard/1048576.0,a.inflight,t.stats.requests,t.stats.attaches,t.stats.drops,t.stats.reloads,service.object_plan.candidate_ids.size(),service.object_plan.visible_ids.size(),t.stats.max_attach_usec/1000.0,t.stats.attach_overruns]
	note.text="256个唯一工程细页\n低预算会保留概括覆盖\n\n资源级失败：%d\n%s"%[t.failures.size(),"" if errors.is_empty() else JSON.stringify(errors.back())]
func pan(relative: Vector2) -> void:x-=relative.x/zoom;y-=relative.y/zoom;refresh()
func change_zoom(factor: float) -> void:zoom=clampf(zoom*factor,.025,2.4);refresh()
func next_region() -> void:x=fposmod(x+4096,16384);y=fposmod(y+1024,4096);refresh()
func reload_view() -> void:service.release_all();refresh()
func toggle_budget() -> void:service.manager.set_budget(config.profiles.normal if service.manager.profile.id!="normal_256_320" else config.profiles.stream);refresh()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_1:choose("stream")
	elif event.keycode==KEY_2:choose("lab")
	elif event.keycode==KEY_3:choose("tongguan")
	elif event.keycode==KEY_N:next_region()
	elif event.keycode==KEY_C:reload_view()
	elif event.keycode==KEY_B:toggle_budget()
	elif event.keycode==KEY_ESCAPE:call_deferred("shutdown")
func shutdown() -> void:
	if _shutting_down:return
	_shutting_down=true;set_process(false)
	service.dispose()
	for i in 600:
		service.tick()
		if service.manager.accounting().inflight==0:get_tree().quit(0);return
		await get_tree().process_frame
	printerr("E3_SHUTDOWN_DRAIN_TIMEOUT");get_tree().quit(1)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:call_deferred("shutdown")
