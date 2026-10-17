extends Control
var model: RefCounted
var canvas: Control
var style: Dictionary
var status: Label
var state_label: Label
var before_path := "user://tests/map_v02/v1/before.json"
var after_path := "user://tests/map_v02/v1/after.json"
var setup_errors: Array=[]
func army(): return get_node("/root/Session").army
func label_at(text_value: String, at: Vector2, dimensions: Vector2, font_size: int=16) -> Label:
	var node:=Label.new();node.text=text_value;node.position=at;node.size=dimensions;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.add_theme_font_size_override("font_size",font_size);add_child(node);return node
func button_at(text_value: String, at: Vector2, callback: Callable, width: float=112) -> Button:
	var node:=Button.new();node.text=text_value;node.position=at;node.size=Vector2(width,36);node.pressed.connect(callback);add_child(node);return node
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var theme_value:=Theme.new();theme_value.default_font=font;theme_value.default_font_size=16;theme=theme_value
	var background:=ColorRect.new();background.color=Color("273c3c");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	style=JSON.parse_string(FileAccess.get_file_as_string("res://v02/v1/style.json"))
	model=load("res://runtime/model.gd").new()
	canvas=load("res://v02/v1/canvas.gd").new();canvas.model=model;add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.offset_left=20;canvas.offset_top=92;canvas.offset_right=-300;canvas.offset_bottom=-44
	label_at("潼关 / 坡岸与关城",Vector2(24,16),Vector2(600,38),27)
	label_at("V1 · 候选 A　|　固定方向 · 原锚点 · 组合审阅",Vector2(25,57),Vector2(1100,26),14)
	var side:=Control.new();side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);side.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(side)
	# Fixed 1080p review layout. Main canvas remains responsive in a smaller window.
	var x:=1640.0
	label_at("组合审阅",Vector2(x,106),Vector2(255,36),23)
	label_at("坡岸、水、树、道路、墙、关楼\n12 个组件 / 仅补 2 张素材",Vector2(x,151),Vector2(255,62),15)
	var i:=0
	for id in style.cameras:
		var camera_id: String=id
		button_at(str(i+1)+"  "+str(style.cameras[id].name),Vector2(x,224+i*43),func():recall(camera_id),250);i+=1
	button_at("新 / 旧画面  B",Vector2(x,411),toggle_compare,250)
	button_at("接点与参考线  G",Vector2(x,454),toggle_guides,250)
	button_at("地形独显  T",Vector2(x,497),toggle_terrain,250)
	button_at("建设前",Vector2(x,558),func():state_view("before"),119)
	button_at("建设后",Vector2(x+130,558),func():state_view("after"),119)
	button_at("损毁示意",Vector2(x,601),func():state_view("damaged"),119)
	button_at("原位恢复",Vector2(x+130,601),func():state_view("after"),119)
	state_label=label_at("",Vector2(x,655),Vector2(250,60),14)
	label_at("审阅重点",Vector2(x,738),Vector2(250,32),20)
	label_at("坡面是否连续\n建筑是否接地\n道路是否穿门\n墙段接点与树木尺度\n同一光向、线条与颜色",Vector2(x,780),Vector2(250,150),15)
	status=label_at("待你审阅 · 尚未认定美术通过",Vector2(x,963),Vector2(250,60),14)
	status.modulate=Color("e7c990")
	label_at("滚轮缩放 / 拖动平移　·　现代地理参照，非756年实测　·　新增样板不写旧地图或素材库",Vector2(24,1042),Vector2(1570,24),13)
	prepare_fixture();recall("composition");sync_state()
func prepare_fixture() -> void:
	var result: Dictionary=army().write_save(before_path)
	if not result.ok:setup_errors.append(result);return
	var quote: Dictionary=army().preview_construction("tongguan.slot.rear_storage_01","warehouse")
	if not quote.ok:setup_errors.append(quote);return
	result=army().commit_construction(quote.token)
	if not result.ok:setup_errors.append(result);return
	army().set_paused(false)
	for i in 3:
		result=army().advance_step()
		if not result.ok:setup_errors.append(result)
	army().set_paused(true)
	result=army().write_save(after_path)
	if not result.ok:setup_errors.append(result)
func recall(id: String) -> void:
	var camera: Dictionary=style.cameras[id]
	model.camera_x=float(model.view.world_origin[0])+float(camera.center_m[0]);model.camera_y=float(model.view.world_origin[1])+float(camera.center_m[1]);model.set_zoom(float(camera.zoom));canvas.sync()
func toggle_compare() -> void: canvas.compare=not canvas.compare;canvas.sync()
func toggle_guides() -> void: canvas.rig.guides=not canvas.rig.guides
func toggle_terrain() -> void: canvas.rig.set_layers(not canvas.rig.terrain_only,true,true,true);sync_state()
func state_view(which: String) -> void:
	var result: Dictionary=army().read_save(before_path if which=="before" else after_path)
	if not result.ok:setup_errors.append(result)
	if which=="damaged":
		model.host.set_damage("tongguan.slot.rear_storage_01",2)
		model.host.set_damage("wall_east",2)
	sync_state()
func sync_state() -> void:
	var occupancy: Dictionary=army().projection().slot_occupancy["tongguan.slot.rear_storage_01"]
	var rig: Node2D=canvas.rig
	rig.get_node("Objects/Warehouse").visible=not rig.terrain_only and occupancy.status!="empty"
	var damage: int=int(army().projection().module_damage["tongguan.slot.rear_storage_01"])
	# V1 damage is an explicit mask/ink preview, not a finished ruin asset.
	rig.get_node("Objects/Warehouse").modulate=Color("948d7f") if damage==2 else Color.WHITE
	rig.get_node("Objects/SouthWall").modulate=Color("948d7f") if int(army().projection().module_damage.wall_east)==2 else Color.WHITE
	state_label.text="仓储：%s　损毁 %d\n钱 %d / 木材 %d"%[occupancy.status,damage,army().economy().cash,army().economy().timber]
	if not setup_errors.is_empty():status.text="小样状态准备失败，见日志";printerr("V1_SETUP ",JSON.stringify(setup_errors))
	canvas.sync()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:recall(style.cameras.keys()[event.keycode-KEY_1])
	elif event.keycode==KEY_B:toggle_compare()
	elif event.keycode==KEY_G:toggle_guides()
	elif event.keycode==KEY_T:toggle_terrain()
	elif event.keycode==KEY_ESCAPE:get_tree().quit(0)
