extends Control
const Adapter=preload("res://v02/v2/adapter.gd")
var model: RefCounted
var canvas: Control
var info: Label
var note: Label
var errors: Array=[]
var receipts: Array=[]
var before_path: String
var after_path: String
var style: Dictionary
var cameras: Dictionary={"composition":[0,-270,.84],"courtyard":[-535,-227.5,2.4],"wall":[95,50,2.4],"shore":[-60,-600,1.4]}
func army():return get_node("/root/Session").army
func label_at(text: String,p: Vector2,s: Vector2,font_size: int=16) -> Label:
	var node=Label.new();node.text=text;node.position=p;node.size=s;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.add_theme_font_size_override("font_size",font_size);add_child(node);return node
func button(text: String,y: float,callback: Callable) -> void:
	var node=Button.new();node.text=text;node.position=Vector2(1640,y);node.size=Vector2(255,34);node.pressed.connect(callback);add_child(node)
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);var skin=Theme.new();skin.default_font=font;skin.default_font_size=16;theme=skin
	var background=ColorRect.new();background.color=Color("273c3c");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	model=load("res://runtime/model.gd").new();canvas=load("res://v02/v2/canvas.gd").new();canvas.model=model;canvas.position=Vector2(20,96);canvas.size=Vector2(1600,940);add_child(canvas)
	label_at("潼关 / 院落、坡岸与原位损毁",Vector2(24,17),Vector2(1300,40),27)
	label_at("V2 · 同一地块、建筑ID与状态服务 · 候选组合，待你审阅",Vector2(25,58),Vector2(1400,30),15)
	button("1　关河组合",116,func():recall("composition"));button("2　仓储与驻军院落",157,func():recall("courtyard"));button("3　墙段与关楼",198,func():recall("wall"));button("4　连续坡岸",239,func():recall("shore"))
	button("回到建设前",296,reset_before);button("报价并建造仓库",337,build_storage);button("推进一天（已有时钟）",378,advance_day)
	button("仓库＋墙段损毁",435,func():damage(2));button("原位修复",476,func():damage(0))
	button("成长档位循环 1 / 2 / 3",533,func():result(model.host.set_growth(int(army().projection().growth_stage)%3+1),"切换已有成长档位"))
	button("主关开闭",574,func():result(army().set_gate_open(not army().projection().gate_open),"切换已有主关控制"))
	button("接地点 / 八地块　G",631,func():canvas.guide=not canvas.guide;canvas.sync())
	button("地形独显　T",672,func():canvas.terrain_only=not canvas.terrain_only;canvas.sync())
	info=label_at("",Vector2(1640,727),Vector2(260,175),15);note=label_at("待审阅 · 仅补3张必要小样",Vector2(1640,923),Vector2(255,100),14)
	label_at("拖动 / 滚轮　·　原位修复沿用既有损毁状态切换；不新增修复费用或施工规则",Vector2(24,1043),Vector2(1590,25),13)
	var run_id:="%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec()];before_path="user://tests/v02/v2/"+run_id+"/before.json";after_path=before_path.replace("before.json","after.json")
	result(army().write_save(before_path),"准备独立审阅状态");build_storage()
	for i in 3:advance_day()
	result(army().write_save(after_path),"示例已完成，实付120钱／20木，可回到建设前重演")
	recall("courtyard")
func result(value: Dictionary,action: String) -> void:
	receipts.append({"action":action,"result":value.duplicate(true),"snapshot":army().snapshot(),"economy":army().economy()})
	if not value.ok:errors.append(value);note.text=str(value.get("message",value));note.modulate=Color("e5a77e")
	else:note.text=action;note.modulate=Color("e5cf9c")
	sync()
func build_storage() -> void:
	var quote: Dictionary=army().preview_construction(Adapter.STORAGE,"warehouse")
	if not quote.ok:result(quote,"报价未通过");return
	result(army().commit_construction(quote.token),"已按原合同开工：120钱／20木／3天")
func advance_day() -> void:
	var resumed: Dictionary=army().set_paused(false)
	if not resumed.ok:result(resumed,"时钟未恢复");return
	result(army().advance_step(),"已有时钟推进一天");result(army().set_paused(true),"审阅暂停")
func damage(level: int) -> void:
	var first: Dictionary=model.host.set_damage(Adapter.STORAGE,level)
	if not first.ok:result(first,"仓库状态切换未通过");return
	result(model.host.set_damage("wall_east",level),"原位修复完成" if level==0 else "同址损毁：仓库塌顶、墙段缺口")
func reset_before() -> void:result(army().read_save(before_path),"恢复独立建设前检查点")
func recall(id: String) -> void:
	var camera: Array=cameras[id];model.camera_x=model.view.world_origin[0]+camera[0];model.camera_y=model.view.world_origin[1]+camera[1];model.set_zoom(camera[2]);canvas.sync()
func sync() -> void:
	if canvas==null or info==null:return
	canvas.sync();var p: Dictionary=army().projection();var e: Dictionary=army().economy();var order: Dictionary=army().construction_for(Adapter.STORAGE)
	info.text="第%d天 / 成长%d档\n仓储：%s（损毁%d）\n钱 %d / 木 %d\n施工：%s\n八地块与主通道保持\n未批准区只在本候选副本审阅"%[army().context.state.current_day,p.growth_stage,p.slot_occupancy[Adapter.STORAGE].status,p.module_damage[Adapter.STORAGE],e.cash,e.timber,str(order.get("status","未开工"))]
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:recall(cameras.keys()[event.keycode-KEY_1])
	elif event.keycode==KEY_G:canvas.guide=not canvas.guide;canvas.sync()
	elif event.keycode==KEY_T:canvas.terrain_only=not canvas.terrain_only;canvas.sync()
	elif event.keycode==KEY_B:canvas.show_sample_trees=not canvas.show_sample_trees;canvas.sync()
	elif event.keycode==KEY_ESCAPE:get_tree().quit(0)
