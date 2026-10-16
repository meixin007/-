extends Control
const Model=preload("res://runtime/model.gd")
const Canvas=preload("res://runtime/city_canvas.gd")
const NAMES={"warehouse":"仓库","granary":"粮仓","barracks":"营房","training_ground":"训练场","workshop":"工坊","repair_yard":"维修场","housing":"民居","shop":"商铺","market":"市集","inn":"客舍","infirmary":"医舍","camp":"营地"}
var model=Model.new()
var auto_load:=false
var save_path: String="user://runtime/session.json"
var canvas: Control
var slot_label: Label
var message_label: Label
var camera_label: Label
var facility_picker: OptionButton
var growth_picker: OptionButton
var damage_target: OptionButton
var damage_picker: OptionButton
var build_button: Button
var finish_button: Button
var seed_edit: SpinBox
var density_edit: SpinBox
var asset_picker: OptionButton
var scope_picker: OptionButton
var slot_pin: CheckBox
var preview_label: Label
var syncing:=false
var tabs: TabContainer
var zoom_slider: HSlider
var _facility_ids: Array=[]
var _damage_ids: Array=[]
func label(parent: Node,text: String,size_value:=16)->Label:
	var item=Label.new();item.text=text;item.add_theme_font_size_override("font_size",size_value);parent.add_child(item);return item
func button(parent: Node,text: String,action: Callable)->Button:
	var item=Button.new();item.text=text;item.pressed.connect(action);parent.add_child(item);return item
func _tab(tabs: TabContainer,name_value: String)->VBoxContainer:
	var scroll=ScrollContainer.new();scroll.name=name_value;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;tabs.add_child(scroll)
	var panel=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_constant_override("separation",8);scroll.add_child(panel);return panel
func _message(result: Dictionary,success: String)->void:
	message_label.text=success if result.get("ok",false) else "未执行："+str(result.get("message","未知原因"));sync()
func _ready()->void:
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);var tv=Theme.new();tv.default_font=font;tv.default_font_size=16;theme=tv
	var background=ColorRect.new();background.color=Color("142b33");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	get_window().title="潼关 · P5 独立运行包"
	var title=label(self,"潼关  /  P5 独立运行包",28);title.position=Vector2(26,20)
	var subtitle=label(self,"756年候选布局 · 独立验证存档 · 施工由验收按钮推进 · 建设不会解除关隘封锁",16);subtitle.position=Vector2(28,66);subtitle.modulate=Color("b0c5bb")
	canvas=Canvas.new();canvas.model=model;canvas.font=font;canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.offset_left=24;canvas.offset_top=112;canvas.offset_right=-374;canvas.offset_bottom=-34;add_child(canvas);canvas.view_changed.connect(sync)
	var right=VBoxContainer.new();right.anchor_left=1;right.anchor_right=1;right.anchor_bottom=1;right.offset_left=-350;right.offset_right=-24;right.offset_top=112;right.offset_bottom=-30;right.add_theme_constant_override("separation",7);add_child(right)
	var grid=GridContainer.new();grid.columns=2;right.add_child(grid)
	for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:button(grid,model.view.bookmarks[id].name,func():model.recall_bookmark(id);sync()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	camera_label=label(right,"")
	zoom_slider=HSlider.new();zoom_slider.min_value=log(0.00006);zoom_slider.max_value=log(2.4);zoom_slider.step=0.001;zoom_slider.value=log(model.zoom);zoom_slider.value_changed.connect(func(value: float):model.zoom_at(exp(value)/model.zoom,canvas.size*0.5,canvas.size);sync());right.add_child(zoom_slider)
	tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(tabs)
	var play=_tab(tabs,"建设与状态")
	slot_label=label(play,"");slot_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;slot_label.custom_minimum_size.x=295
	facility_picker=OptionButton.new();play.add_child(facility_picker)
	var build_row=HBoxContainer.new();play.add_child(build_row)
	build_button=button(build_row,"开始建设",func():_message(model.host.construct(model.selected_slot,str(_facility_ids[facility_picker.selected])),"已进入在建状态。"))
	finish_button=button(build_row,"完成施工",func():_message(model.host.finish_construction(model.selected_slot),"施工完成；原地块与建筑身份保留。"))
	button(play,"拆除所选设施",func():_message(model.host.demolish(model.selected_slot),"已拆除，地块恢复空置。"))
	label(play,"成长程度",18);growth_picker=OptionButton.new()
	for text in ["1 简约","2 常态","3 强化"]:growth_picker.add_item(text)
	growth_picker.item_selected.connect(func(index: int):_message(model.host.set_growth(index+1),"已切换成长；已有建筑与损毁保留。"));play.add_child(growth_picker)
	label(play,"独立损毁",18);damage_target=OptionButton.new();play.add_child(damage_target)
	for entry in [["gate","主关楼"],["wall_west","北段墙体"],["wall_east","南段墙体"]]:_damage_ids.append(entry[0]);damage_target.add_item(entry[1])
	for slot in model.host.layout.slots:_damage_ids.append(slot.id);damage_target.add_item(slot.name+"设施")
	damage_target.item_selected.connect(func(_index: int):sync())
	damage_picker=OptionButton.new()
	for text in ["完好","局部受损","严重受损"]:damage_picker.add_item(text)
	damage_picker.item_selected.connect(func(index: int):_message(model.host.set_damage(str(_damage_ids[damage_target.selected]),index),"损毁已更新；成长和主关开闭保持独立。"));play.add_child(damage_picker)
	var damage_row=HBoxContainer.new();play.add_child(damage_row)
	button(damage_row,"定位目标",func():model.focus_module(str(_damage_ids[damage_target.selected]));sync())
	button(damage_row,"原位修复",func():_message(model.host.set_damage(str(_damage_ids[damage_target.selected]),0),"已原位修复。"))
	var save_row=HBoxContainer.new();play.add_child(save_row);button(save_row,"保存样本",save_session);button(save_row,"重读样本",load_session)
	message_label=label(play,"选择地块后建设。状态只写入本独立样本，不接战役资源与移动。",14);message_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message_label.custom_minimum_size.x=295
	var view=_tab(tabs,"显示与通行")
	for entry in [["显示建筑与损毁","show_buildings"],["显示树林","show_trees"],["显示P3地理约束","show_constraints"],["显示现代水系","show_water"]]:
		var item=CheckBox.new();item.text=entry[0];item.button_pressed=bool(canvas.get(entry[1]));item.toggled.connect(func(value: bool):canvas.set(entry[1],value);if entry[1]=="show_buildings":canvas.show_icon=value;sync());view.add_child(item)
	button(view,"切换示例主关开闭",func():model.set_gate_open(not model.gate_open());var result=model.run_diagnostics(true);_message({"ok":true},"运行包示例：普通军队"+("可通" if result.main_army else "受阻")))
	label(view,"损毁图片不会改变通行。\n精确历史关址与岸线仍待核查。\n示例通道不授予战役移动。\nEsc 退出；1—4 镜头。",14)
	var footer=label(self,"滚轮缩放 · 拖拽平移 · 点击地块 / 树林　｜　独立样本 · Copernicus GLO-30 / © OpenStreetMap contributors",13);footer.anchor_top=1;footer.anchor_bottom=1;footer.offset_left=26;footer.offset_top=-28;footer.offset_bottom=-4;footer.modulate=Color("a7bbb6")
	if auto_load and FileAccess.file_exists(save_path):load_session()
	sync()
func sync()->void:
	if slot_label==null:return
	syncing=true;canvas.queue_redraw()
	if not model.load_error.is_empty():slot_label.text=model.load_error;syncing=false;return
	var slot: Dictionary=model.host.slot_by_id(model.selected_slot);var state: Dictionary=model.host.runtime;var authored: Dictionary=model.host.authoring
	var occupancy: Dictionary=state.slot_occupancy[slot.id]
	var status={"empty":"空置","building":"在建","built":"已建"}.get(occupancy.status,occupancy.status)
	slot_label.text="潼关 · "+slot.name+"地块\n状态："+status+" / 成长 "+str(int(slot.unlock_stage))+"开放\n设施："+str(NAMES.get(occupancy.building_type,"无"))+"\n制作冻结与建设许可分开。"
	if _facility_ids!=slot.allowed_buildings:
		_facility_ids=slot.allowed_buildings.duplicate();facility_picker.clear()
		for id in _facility_ids:facility_picker.add_item(str(NAMES.get(id,id)))
	growth_picker.select(int(state.growth_stage)-1)
	damage_picker.select(int(state.module_damage[_damage_ids[damage_target.selected]]))
	camera_label.text="主关%s · 成长%d · 树林%d簇"%["开放" if state.gate_open else "关闭",int(state.growth_stage),authored.generated.size()]
	zoom_slider.set_value_no_signal(log(model.zoom))
	syncing=false
func save_session()->void:_message(model.host.write_save(save_path),"已保存独立验证样本。")
func load_session()->void:
	var result: Dictionary=model.host.read_save(save_path)
	if result.ok:model.sync_gate_from_host();model.preview={}
	_message(result,"已重读：建设、成长、损毁、人工覆盖与删除记录均已恢复。")
func _unhandled_key_input(event: InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode>=KEY_1 and event.keycode<=KEY_4:model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][event.keycode-KEY_1]);sync()
	elif event.keycode==KEY_G:model.set_gate_open(not model.gate_open());sync()
	elif event.keycode==KEY_ESCAPE:get_tree().quit(0)
