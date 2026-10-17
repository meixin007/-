extends Control
const Loader=preload("res://v02/e1/package_loader.gd")
var config: Dictionary
var loader: RefCounted
var active_id:="lab"
var canvas: Control
var info: Label
var note: Label
var displayed: Array=[]
var ordered: Array=[]
var art: Dictionary={}
var center:=Vector2.ZERO
var zoom:=.42
var guides:=true
class MapCanvas extends Control:
	var host: WeakRef
	func _draw() -> void:
		if host!=null and host.get_ref()!=null:host.get_ref().paint(self)
	func _gui_input(event: InputEvent) -> void:
		var app=host.get_ref()
		if event is InputEventMouseMotion and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:
			app.center-=event.relative/app.zoom;queue_redraw()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:app.zoom=minf(app.zoom*1.15,2.4);queue_redraw()
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:app.zoom=maxf(app.zoom/1.15,.03);queue_redraw()
func label_at(text: String,pos: Vector2,extent: Vector2,font_size: int=16) -> Label:
	var label=Label.new();label.text=text;label.position=pos;label.size=extent;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);add_child(label);return label
func button_at(text: String,y: float,callback: Callable) -> void:
	var button=Button.new();button.text=text;button.position=Vector2(1640,y);button.size=Vector2(250,40);button.pressed.connect(callback);add_child(button)
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e1/config.json"))
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var skin=Theme.new();skin.default_font=font;skin.default_font_size=16;theme=skin
	var bg=ColorRect.new();bg.color=Color("273c3c");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	label_at("潼关 / 独立分页包",Vector2(24,17),Vector2(900,40),27)
	label_at("V1组合方向已认可　·　E1 数据包与发行读取验证",Vector2(25,58),Vector2(1400,30),15)
	canvas=MapCanvas.new();canvas.host=weakref(self);canvas.position=Vector2(20,96);canvas.size=Vector2(1600,940);canvas.clip_contents=true;add_child(canvas)
	label_at("分页包预览",Vector2(1640,110),Vector2(250,40),23)
	button_at("1　4×4 工程夹具",185,func():choose("lab"))
	button_at("2　原潼关有效快照",235,func():choose("tongguan"))
	button_at("页界与原地块　G",300,func():guides=not guides;canvas.queue_redraw())
	button_at("回到固定机位",350,func():reset_camera();canvas.queue_redraw())
	info=label_at("",Vector2(1640,420),Vector2(250,220),16)
	note=label_at("",Vector2(1640,670),Vector2(250,300),15)
	label_at("拖动平移 / 滚轮缩放 / Esc退出　·　夹具为工程地理；潼关为只读制作快照预览",Vector2(24,1043),Vector2(1580,25),13)
	choose("lab")
func reset_camera() -> void:
	center=Vector2.ZERO if active_id=="lab" else Vector2(0,-270)
	zoom=.42 if active_id=="lab" else .84
func choose(id: String) -> void:
	var entry: Dictionary=config.packages[id]
	var candidate=Loader.new();var adopted: Dictionary=candidate.admit(entry.path,entry.expected,entry.build_id)
	if not adopted.ok:note.text=adopted.message;return
	var next_displayed: Array=[];var seen: Dictionary={};var fallback_count:=0
	for page in candidate.pages.values():
		var ready: Dictionary=candidate.resolve_page(page.id)
		if not ready.ok:note.text=JSON.stringify(ready);return
		if not ready.detail_ok:fallback_count+=1
		if not seen.has(ready.selected_page):next_displayed.append(ready.page);seen[ready.selected_page]=true
	var next_art: Dictionary={}
	for asset in candidate.assets.values():
		var texture: Dictionary=candidate.texture(asset.texture_file)
		if not texture.ok:note.text=texture.message;return
		var atlas=AtlasTexture.new();atlas.atlas=texture.texture;atlas.region=candidate.rect(asset.rect_px);atlas.filter_clip=true;next_art[asset.asset_id]=atlas
	loader=candidate;active_id=id;displayed=next_displayed;art=next_art
	displayed.sort_custom(func(a,b):return a.level<b.level)
	ordered=loader.objects.values()
	ordered.sort_custom(func(a,b):
		if a.render_plane!=b.render_plane:return a.render_plane<b.render_plane
		if a.ground_depth!=b.ground_depth:return a.ground_depth<b.ground_depth
		return a.id<b.id)
	reset_camera()
	info.text=("工程世界" if id=="lab" else "原潼关世界")+"\n页目录：%d\n对象：%d\n实际载入纹理：%d\n缺页回退：%d"%[loader.pages.size(),loader.objects.size(),loader.textures.size(),fallback_count]
	note.text="黄色框：细节页缺失\n同版本父页保持覆盖\n\n跨页树保留原ID\n道路和水岸跨页连续" if id=="lab" else "原72个有效实例\n手工新增、删除与固定保留\n原八地块与通道未改\n\n本窗口只读预览制作数据"
	canvas.queue_redraw()
func paint(surface: Control) -> void:
	surface.draw_rect(Rect2(Vector2.ZERO,surface.size),Color("ded8bc"))
	if loader==null:return
	surface.draw_set_transform(surface.size*.5-center*zoom,0,Vector2(zoom,zoom))
	for page in displayed:
		for file in page.texture_files:
			var source=Rect2(page.gutter_px,page.gutter_px,page.core_px[0],page.core_px[1])
			surface.draw_texture_rect_region(loader.textures[file],loader.rect(page.bounds_m),source,Color.WHITE,false,false)
	var view_bounds=Rect2(center-surface.size/(zoom*2),surface.size/zoom)
	for item in ordered:
		if not view_bounds.intersects(loader.rect(item.paint_bounds_m)):continue
		if item.record_type=="sprite":surface.draw_texture_rect(art[item.asset_id],loader.rect(item.paint_bounds_m),false)
		else:
			var points=PackedVector2Array()
			for p in item.points_m:points.append(Vector2(p[0],p[1]))
			surface.draw_polyline(points,Color(str(item.color)),item.width_m,true)
	if guides:
		for page in loader.pages.values():
			if (active_id=="lab" and page.level!=2) or (active_id=="tongguan" and page.level!=1):continue
			var color=Color("b88035") if page.optional else Color("496d68",.65)
			surface.draw_rect(loader.rect(page.bounds_m),color,false,1.3/zoom)
		for site in loader.sites:
			for slot in site.slots:
				var outline=PackedVector2Array()
				for p in slot.polygon_local_m:outline.append(Vector2(p[0],p[1]))
				outline.append(outline[0]);surface.draw_polyline(outline,Color("a58054"),1/zoom,true)
	for site in loader.sites:
		var position=Vector2(site.position_m[0],site.position_m[1])
		if active_id=="lab":surface.draw_circle(position,8/zoom,Color("8f5e37"))
		if active_id=="lab":surface.draw_string(get_theme_default_font(),position+Vector2(12/zoom,-8/zoom),site.label,HORIZONTAL_ALIGNMENT_LEFT,-1,int(16/zoom),Color("374f4a"))
	surface.draw_set_transform(Vector2.ZERO)
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_1:choose("lab")
	elif event.keycode==KEY_2:choose("tongguan")
	elif event.keycode==KEY_G:guides=not guides;canvas.queue_redraw()
	elif event.keycode==KEY_ESCAPE:get_tree().quit(0)
