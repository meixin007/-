extends Control
const Service=preload("res://v02/c1/map_service.gd")
const Renderer=preload("res://v02/c1/map_renderer.gd")
const City=preload("res://v02/v2/adapter.gd")
var service=Service.new()
var renderer: Control
var model: RefCounted
var config: Dictionary
var info: Label
var note: Label
var label_style: StyleBoxFlat
var x:=0.0
var y:=-270.0
var zoom:=.84
var active:="tongguan"
var errors: Array=[]
var receipts: Array=[]
var before_path: String
var _stamp:=0
var _shutting_down:=false
func army():return get_node("/root/Session").army
func label_at(text: String,p: Vector2,s: Vector2,font_size: int=16) -> Label:
	var node=Label.new();node.text=text;node.position=p;node.size=s;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.add_theme_font_size_override("font_size",font_size);add_child(node);return node
func button(text: String,y_pos: float,callback: Callable) -> void:
	var node=Button.new();node.text=text;node.position=Vector2(1640,y_pos);node.size=Vector2(255,32);node.pressed.connect(callback);add_child(node)
func _ready() -> void:
	get_tree().auto_accept_quit=false;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://v02/c1/config.json"))
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);var skin=Theme.new();skin.default_font=font;skin.default_font_size=16;theme=skin
	label_style=StyleBoxFlat.new();label_style.bg_color=Color("eee4c9",.88);label_style.corner_radius_top_left=4;label_style.corner_radius_bottom_right=4
	var paper=ColorRect.new();paper.color=Color("273c3c");paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(paper)
	label_at("潼关 / 地形、城镇与流式地图整合",Vector2(24,17),Vector2(1500,40),27)
	label_at("C1 待审阅　·　滚轮连续缩放 / 拖动平移 / 点击地点　·　唯一玩法状态与 E1—E3 表现服务",Vector2(25,58),Vector2(1550,30),15)
	var growth_button=Button.new();growth_button.text="H　成长 1 / 2 / 3";growth_button.position=Vector2(1170,20);growth_button.size=Vector2(205,32);growth_button.pressed.connect(cycle_growth);add_child(growth_button)
	var gate_button=Button.new();gate_button.text="J　主关开闭";gate_button.position=Vector2(1390,20);gate_button.size=Vector2(205,32);gate_button.pressed.connect(toggle_gate);add_child(gate_button)
	model=load("res://runtime/model.gd").new()
	renderer=Renderer.new();renderer.app=weakref(self);renderer.presenter=weakref(self);renderer.position=Vector2(20,96);renderer.size=Vector2(1600,940);add_child(renderer)
	service.bind_renderer(renderer);service.bind_authority(army(),model.host)
	button("1　关河组合",108,func():camera("composition"));button("2　院落近景",145,func():camera("courtyard"));button("3　区域地势",182,func():camera("region"));button("4　东亚粗示意远景",219,func():camera("far"))
	button("5　工程多区域 / N 下一片",268,func():choose("multi"))
	button("U　卸载显示",317,unload_display);button("R　重载当前视野",354,reload_display)
	button("C　回到建设前",403,reset_before);button("B　报价并建造仓库",440,build_storage);button("D　推进一天",477,advance_day)
	button("X　仓库与墙段损毁",526,func():damage(2));button("F　原位修复",563,func():damage(0))
	button("Tab　工程势力覆盖",612,toggle_factions);button("K　切换工程归属颜色",649,swap_factions)
	button("G　地块与分页线 / T 地形",686,func():renderer.guides=not renderer.guides)
	info=label_at("",Vector2(1640,732),Vector2(260,225),14);note=label_at("",Vector2(1640,966),Vector2(260,65),13)
	label_at("1—4 固定机位　·　T 地形独显 / G 接点　·　远景底图与势力区域为示意，详细地形沿用现有现代数据",Vector2(24,1043),Vector2(1590,26),13)
	before_path="user://tests/v02/c1/%d_%d/before.json"%[Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	result(army().write_save(before_path),"独立审阅检查点")
	choose("tongguan");build_storage()
	for i in 3:advance_day()
	camera("composition")
func choose(id: String) -> void:
	var value: Dictionary=service.open(config.packages[id])
	if not value.ok:errors.append(value);return
	active=id;service.selected_site="tongguan" if id=="tongguan" else "lab.site.000"
	service.manager.set_budget(config.profiles.normal)
	if id=="tongguan":x=0;y=-270;zoom=.84
	else:x=4096;y=2048;zoom=.15
	refresh()
func camera(id: String) -> void:
	if active!="tongguan":choose("tongguan")
	var cameras: Dictionary={"composition":[0,-270,.84],"courtyard":[-535,-227.5,2.4],"region":[-600,800,.105],"far":[-500000,100000,.00014]}
	var c: Array=cameras[id];x=c[0];y=c[1];zoom=c[2];service.suspended=false;refresh()
func refresh() -> void:
	if renderer==null or service.loader==null:return
	model.camera_x=model.view.world_origin[0]+x;model.camera_y=model.view.world_origin[1]+y;model.set_zoom(zoom)
	var value: Dictionary=service.set_view(Rect2(x-800/zoom,y-470/zoom,1600/zoom,940/zoom),zoom)
	if not value.ok:errors.append(value)
func _process(_delta: float) -> void:
	if service.loader==null or _shutting_down:return
	var token: Array=service._authority_token.duplicate()
	var value: Dictionary=service.sync_authority()
	if not value.ok:errors.append(value)
	if token!=service._authority_token:refresh()
	service.tick();renderer.render(service,x,y,zoom)
	if Time.get_ticks_msec()-_stamp<100:return
	_stamp=Time.get_ticks_msec();var t: Dictionary=service.manager.telemetry();var p: Dictionary=army().projection();var e: Dictionary=army().economy()
	var status: String={"empty":"未建","building":"施工中","built":"已建"}.get(p.slot_occupancy[City.STORAGE].status,p.slot_occupancy[City.STORAGE].status)
	info.text="选中：%s\n显示：%s / %s\n第%d天　仓库 %s\n损毁%d　钱%d / 木%d\n纹理 %.1f MiB　请求%d\n释放%d / 重载%d\n细节：%s\n%s"%["潼关" if service.selected_site=="tongguan" else service.selected_site,["图标","剪影","简化布局","详细院落"][service.semantic_lod],"已卸载" if service.suspended else "显示中",army().context.state.current_day,status,p.module_damage[City.STORAGE],e.cash,e.timber,t.accounting.resident/1048576.0,t.stats.requests,t.stats.drops,t.stats.reloads,"就绪" if service.detail_ready else "代理保留", "工程夹具，无历史地点内容" if active=="multi" else "原八地块与通道"]
	note.text="待审阅 · C1 整合候选" if errors.is_empty() else str(errors.back())
func pan(delta: Vector2) -> void:x-=delta.x/zoom;y-=delta.y/zoom;refresh()
func change_zoom(factor: float,cursor: Vector2=Vector2(800,470)) -> void:
	var old: Vector2=(cursor-Vector2(800,470))/zoom;zoom=clampf(zoom*factor,.00006,2.4);var next: Vector2=(cursor-Vector2(800,470))/zoom;x+=old.x-next.x;y+=old.y-next.y;refresh()
func pick(at: Vector2) -> void:
	for row in service.loader.sites:
		if renderer.screen(row.position_m).distance_to(at)<=24:service.selected_site=row.site_id;refresh();return
func unload_display() -> void:service.suspend_display()
func reload_display() -> void:
	var value: Dictionary=service.resume_display()
	if not value.ok:errors.append(value)
func result(value: Dictionary,action: String) -> void:
	receipts.append({"action":action,"result":value.duplicate(true),"snapshot":army().snapshot(),"economy":army().economy()})
	if not value.ok:errors.append(value)
	refresh()
func build_storage() -> void:
	var quote: Dictionary=army().preview_construction(City.STORAGE,"warehouse")
	if not quote.ok:result(quote,"报价未通过");return
	result(army().commit_construction(quote.token),"已有合同开工")
func advance_day() -> void:
	result(army().set_paused(false),"恢复时钟");result(army().advance_step(),"推进一天");result(army().set_paused(true),"暂停审阅")
func damage(level: int) -> void:result(model.host.set_damage(City.STORAGE,level),"仓库状态");result(model.host.set_damage("wall_east",level),"墙段状态")
func reset_before() -> void:result(army().read_save(before_path),"建设前检查点")
func cycle_growth() -> void:result(model.host.set_growth(int(army().projection().growth_stage)%3+1),"原成长档位")
func toggle_gate() -> void:result(army().set_gate_open(not army().projection().gate_open),"原主关控制")
func toggle_factions() -> void:renderer.factions=not renderer.factions
func swap_factions() -> void:renderer.faction_swapped=not renderer.faction_swapped;renderer.faction_revision+=1
func next_region() -> void:
	if active!="multi":choose("multi")
	x=fposmod(x+4096,16384);y=fposmod(y+1024,4096);zoom=1.5;refresh()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:camera(["composition","courtyard","region","far"][event.keycode-KEY_1])
	elif event.keycode==KEY_5:choose("multi")
	elif event.keycode==KEY_U:unload_display()
	elif event.keycode==KEY_R:reload_display()
	elif event.keycode==KEY_C:reset_before()
	elif event.keycode==KEY_B:build_storage()
	elif event.keycode==KEY_D:advance_day()
	elif event.keycode==KEY_X:damage(2)
	elif event.keycode==KEY_F:damage(0)
	elif event.keycode==KEY_TAB:toggle_factions()
	elif event.keycode==KEY_K:swap_factions()
	elif event.keycode==KEY_N:next_region()
	elif event.keycode==KEY_G:renderer.guides=not renderer.guides
	elif event.keycode==KEY_T:renderer.terrain_only=not renderer.terrain_only
	elif event.keycode==KEY_H:cycle_growth()
	elif event.keycode==KEY_J:toggle_gate()
	elif event.keycode==KEY_ESCAPE:call_deferred("shutdown")
func shutdown() -> void:
	if _shutting_down:return
	_shutting_down=true;service.dispose()
	for i in 600:
		service.tick()
		if service.manager.accounting().inflight==0:get_tree().quit(0);return
		await get_tree().process_frame
	printerr("C1_SHUTDOWN_DRAIN_TIMEOUT");get_tree().quit(1)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:call_deferred("shutdown")
