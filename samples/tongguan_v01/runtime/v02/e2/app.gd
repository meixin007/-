extends Control
const Loader=preload("res://v02/e1/package_loader.gd")
const Planner=preload("res://v02/e2/visibility_planner.gd")
const Adapter=preload("res://v02/e2/source_adapter.gd")
const MapRenderer=preload("res://v02/e2/map_renderer.gd")
var config: Dictionary
var loader: RefCounted
var planner=Planner.new()
var renderer: Control
var info: Label
var note: Label
var camera_x:=0.0
var camera_y:=0.0
var zoom:=.42
var active_case:="lab"
var active_package:=""
var setup_errors: Array=[]
var _ui_usec:=0
func label_at(text: String,pos: Vector2,extent: Vector2,font_size: int=16) -> Label:
	var label=Label.new();label.text=text;label.position=pos;label.size=extent;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);add_child(label);return label
func button_at(text: String,y: float,callback: Callable) -> void:
	var button=Button.new();button.text=text;button.position=Vector2(1640,y);button.size=Vector2(250,38);button.pressed.connect(callback);add_child(button)
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e1/config.json"))
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var skin=Theme.new();skin.default_font=font;skin.default_font_size=16;theme=skin
	var bg=ColorRect.new();bg.color=Color("273c3c");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	label_at("潼关 / 可见查询与绘制计划",Vector2(24,17),Vector2(1000,40),27)
	label_at("E2 · 原分页加载器 · 完整绘制范围 · 稳定排序与提交审计",Vector2(25,58),Vector2(1400,30),15)
	renderer=MapRenderer.new();renderer.presenter=weakref(self);renderer.position=Vector2(20,96);renderer.size=Vector2(1600,940);add_child(renderer)
	label_at("查询验证",Vector2(1640,110),Vector2(250,40),23)
	button_at("1　4×4 工程夹具",175,func():choose("lab"))
	button_at("2　原潼关有效快照",223,func():choose("tongguan"))
	button_at("3　四桶树冠 / owner在外",271,func():choose("giant"))
	button_at("参考全量绘制　R",329,toggle_reference)
	button_at("页界与原地块　G",377,func():renderer.guides=not renderer.guides;refresh())
	info=label_at("",Vector2(1640,447),Vector2(250,230),15)
	note=label_at("",Vector2(1640,710),Vector2(250,270),15)
	label_at("拖动平移 / 滚轮缩放 / Esc退出　·　工程巨树只验证范围，不写回旧地图或素材",Vector2(24,1043),Vector2(1580,25),13)
	choose("lab")
func choose(id: String) -> void:
	var package: String="lab" if id=="giant" else id
	if active_package!=package:
		var entry: Dictionary=config.packages[package]
		var candidate=Loader.new();var admitted: Dictionary=candidate.admit(entry.path,entry.expected,entry.build_id)
		if not admitted.ok:report_error(admitted);return
		var terrain: Array=[];var seen: Dictionary={}
		for page in candidate.pages.values():
			var ready: Dictionary=candidate.resolve_page(page.id)
			if not ready.ok:report_error(ready);return
			if not seen.has(ready.selected_page):terrain.append(ready.page);seen[ready.selected_page]=true
		terrain.sort_custom(func(a,b):return a.level<b.level)
		var art: Dictionary={}
		for asset in candidate.assets.values():
			var texture: Dictionary=candidate.texture(asset.texture_file)
			if not texture.ok:report_error(texture);return
			var atlas=AtlasTexture.new();atlas.atlas=texture.texture;atlas.region=candidate.rect(asset.rect_px);atlas.filter_clip=true;art[asset.asset_id]=atlas
		var adapter=Adapter.new();var snapshot: Dictionary=adapter.snapshot(candidate)
		var adopted: Dictionary=planner.sync_source(adapter.token(candidate),func():return snapshot)
		if not adopted.ok:report_error(adopted);return
		loader=candidate;active_package=package
		renderer.bind(loader,planner,terrain,art,snapshot.records)
	active_case=id;renderer.reference_mode=false
	if id=="giant":camera_x=760;camera_y=190;zoom=1.6
	elif id=="tongguan":camera_x=0;camera_y=-270;zoom=.84
	else:camera_x=0;camera_y=0;zoom=.42
	refresh()
func report_error(error: Dictionary) -> void:setup_errors.append(error);note.text=JSON.stringify(error)
func refresh() -> void:
	var result: Dictionary=renderer.update_view(camera_x,camera_y,zoom)
	if not result.ok:report_error(result)
	refresh_text()
func refresh_text() -> void:
	if renderer.last_plan.is_empty():return
	var t: Dictionary=planner.telemetry()
	info.text="对象总数：%d\n候选：%d / 可见：%d\n源快照读取：%d\n完整索引建立：%d\n可见排序次数：%d\n绘制命令重建：%d"%[t.objects,renderer.last_plan.candidate_ids.size(),renderer.last_plan.visible_ids.size(),t.planner.snapshot_reads,t.index.full_index_builds,t.planner.sort_calls,renderer.stats.object_draw_callbacks]
	note.text=("参考：全部对象交给画布裁剪" if renderer.reference_mode else "索引：仅提交可见绘制计划")+"\n\n"+("大树root/owner在视口外\n可见树冠仍提交一次\n依赖保留原payload" if active_case=="giant" else "相机移动不读取完整快照\n候选不变时复用排序\n相同计划只更新画布变换")
	if not renderer.errors.is_empty():note.text=JSON.stringify(renderer.errors)
func pan(relative: Vector2) -> void:camera_x-=relative.x/zoom;camera_y-=relative.y/zoom;refresh()
func change_zoom(factor: float) -> void:zoom=clampf(zoom*factor,.03,2.4);refresh()
func toggle_reference() -> void:renderer.reference_mode=not renderer.reference_mode;refresh()
func _process(_delta: float) -> void:
	if loader==null:return
	renderer.update_view(camera_x,camera_y,zoom)
	if Time.get_ticks_usec()-_ui_usec>100000:refresh_text();_ui_usec=Time.get_ticks_usec()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_1:choose("lab")
	elif event.keycode==KEY_2:choose("tongguan")
	elif event.keycode==KEY_3:choose("giant")
	elif event.keycode==KEY_R:toggle_reference()
	elif event.keycode==KEY_G:renderer.guides=not renderer.guides;refresh()
	elif event.keycode==KEY_ESCAPE:get_tree().quit(0)
