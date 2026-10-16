extends Control
var model: RefCounted
var canvas: Control
var state_label: Label
var message_label: Label
var gate_button: Button
var rear_button: Button
var fore_button: Button
var play_button: Button
var pause_button: Button
var step_button: Button
var save_button: Button
var load_button: Button
var controls_scroll: ScrollContainer
var auto_running:=false
var step_seconds:=1.6
var _remaining:=1.6
var _busy:=false
var save_path: String="user://army/session.json"
func army():return get_node("/root/Session").army
func label(parent: Node,value: String,font_size:=16)->Label:
	var item=Label.new();item.text=value;item.add_theme_font_size_override("font_size",font_size);item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(item);return item
func button(parent: Node,value: String,action: Callable)->Button:
	var item=Button.new();item.text=value;item.custom_minimum_size.y=36;item.pressed.connect(action);parent.add_child(item);return item
func show_result(result: Dictionary,success: String)->void:
	message_label.text=success if result.get("ok",false) else "未执行："+str(result.get("message",result.get("error","未知原因")))
	message_label.modulate=Color("cde6c8") if result.get("ok",false) else Color("f5b19a");refresh()
func _ready()->void:
	model=load("res://runtime/model.gd").new();model.view.bookmarks.gate_close.world_local=[0,0]
	model.view.bookmarks.gate_close.name="关门近景"
	model.recall_bookmark("gate_close");model.set_zoom(1.7)
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);var tv=Theme.new();tv.default_font=font;tv.default_font_size=16;theme=tv
	var background=ColorRect.new();background.color=Color("142b33");background.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	get_window().title="潼关 · 军队受控移动验收"
	var title=label(self,"潼关  /  军队受控移动",28);title.position=Vector2(26,20);title.size=Vector2(1400,40)
	var subtitle=label(self,"756年候选地理 · 独立测试部队 · 主关控制逻辑道路 · 存档与主工程分开",16);subtitle.position=Vector2(28,67);subtitle.size=Vector2(1400,28);subtitle.modulate=Color("b0c5bb")
	canvas=load("res://army/canvas.gd").new();canvas.model=model;canvas.font=font;canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.offset_left=24;canvas.offset_top=112;canvas.offset_right=-436;canvas.offset_bottom=-48;add_child(canvas);canvas.view_changed.connect(refresh)
	controls_scroll=ScrollContainer.new();controls_scroll.anchor_left=1;controls_scroll.anchor_right=1;controls_scroll.anchor_bottom=1;controls_scroll.offset_left=-412;controls_scroll.offset_right=-24;controls_scroll.offset_top=112;controls_scroll.offset_bottom=-48;controls_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(controls_scroll)
	var panel=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_constant_override("separation",8);controls_scroll.add_child(panel)
	var grid=GridContainer.new();grid.columns=2;panel.add_child(grid)
	for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:button(grid,model.view.bookmarks[id].name,func():model.recall_bookmark(id);refresh()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(panel,"定位部队",focus_army)
	var zoom=HSlider.new();zoom.min_value=log(0.00006);zoom.max_value=log(2.4);zoom.step=0.001;zoom.value=log(model.zoom);zoom.value_changed.connect(func(value):model.zoom_at(exp(value)/model.zoom,canvas.size*0.5,canvas.size);refresh());panel.add_child(zoom)
	state_label=label(panel,"");state_label.custom_minimum_size.y=92
	rear_button=button(panel,"向关后（西）行军",func():command("tg_rear"))
	fore_button=button(panel,"向关前（东）行军",func():command("tg_fore"))
	var row=HBoxContainer.new();panel.add_child(row)
	play_button=button(row,"继续演示",play);pause_button=button(row,"暂停",pause);step_button=button(row,"单步一天",single_step)
	gate_button=button(panel,"",toggle_gate)
	button(panel,"切换关楼损毁（不改变通行）",func():var city=army().projection();city.module_damage.gate=(int(city.module_damage.gate)+1)%3;show_result(army().adopt_candidate(city,"damage"),"已切换关楼损毁；通行仍由主关状态控制。"))
	for entry in [["显示城市与关楼","buildings"],["显示树林","trees"],["显示验证道路","route"]]:
		var item=CheckBox.new();item.text=entry[0];item.button_pressed=true;panel.add_child(item);item.toggled.connect(func(value):
			if entry[1]=="buildings":canvas.show_buildings=value;canvas.show_icon=value
			elif entry[1]=="trees":canvas.show_trees=value
			else:canvas.show_route=value
			canvas.queue_redraw())
	button(panel,"测试直接跨主河",func():show_result(army().order("river_north"),""))
	var save_row=HBoxContainer.new();panel.add_child(save_row);save_button=button(save_row,"保存并暂停",save);load_button=button(save_row,"重读行军存档",restore)
	button(panel,"重置本次演示（不改存档）",reset)
	message_label=label(panel,"先点“向关后行军”。关闭主关后，部队会到关前候行；开放后点继续。",15);message_label.custom_minimum_size.y=72
	label(panel,"测试部队与六个逻辑日步用于验证。\n不模拟真实600米行军时长、战斗或军粮。\n1—4 镜头 / G 主关 / 空格 暂停继续 / Esc退出",14).modulate=Color("9fb6b5")
	var footer=label(self,"蓝旗：通行验收队　·　绿 / 红道路：主关放行 / 关闭　·　旧场景与主战役未改写",14);footer.name="Footer";footer.anchor_top=1;footer.anchor_bottom=1;footer.anchor_right=1;footer.offset_left=26;footer.offset_right=-24;footer.offset_top=-31;footer.offset_bottom=-6;footer.modulate=Color("b0c5bb")
	refresh()
func refresh()->void:
	if state_label==null:return
	if not army().error.is_empty():state_label.text=army().error;return
	var state=army().snapshot();var names={"idle":"待命","marching":"行军","waiting":"主关候行","arrived":"已到达"};var force: Dictionary=state.force
	state_label.text="通行验收队 · 100人 · %s\n验证日 %d · %s\n%s"%[names[state.order.status],state.day,"已暂停" if state.paused else ("连续演示" if auto_running else "等待操作"),"道路：%s · 进度 %d / 2"%[force.current_corridor_id,int(force.corridor_progress_days)] if not str(force.current_corridor_id).is_empty() else "驻点："+str(army().context.state.strategic_nodes[force.current_node_id].name)]
	gate_button.text="主关：开放 · 点击关闭" if state.city.gate_open else "主关：关闭 · 点击开放"
	canvas.queue_redraw()
func command(goal: String)->void:
	var result=army().order(goal)
	if result.ok:army().set_paused(false);auto_running=true;_remaining=step_seconds
	show_result(result,"已下达行军命令；沿登记道路前进，主关关闭时在关前候行。")
func play()->void:
	if army().snapshot().order.status not in ["marching","waiting"]:show_result({"ok":false,"message":"请先下达行军命令。"},"");return
	var result=army().set_paused(false)
	if result.ok:auto_running=true;_remaining=0.1
	show_result(result,"继续当前行军命令。")
func pause()->void:
	auto_running=false;canvas.finish_animation();show_result(army().set_paused(true),"部队与验证日期已暂停。")
func advance()->void:
	if _busy:return
	_busy=true;var result=army().advance_step();_busy=false
	if result.ok:
		canvas.animate_to(army().position_local(),step_seconds*0.8)
		if result.movement.get("blocked",false):auto_running=false;message_label.text="主关关闭：当前日步受阻，部队原地候行。开放主关后点“继续演示”。"
		elif army().snapshot().order.status=="arrived":auto_running=false;message_label.text="已到达目标端点；可下达返程命令。"
		refresh()
	else:auto_running=false;show_result(result,"")
func single_step()->void:
	auto_running=false;var was_paused=army().snapshot().paused
	if was_paused:army().set_paused(false)
	advance()
	if was_paused:army().set_paused(true)
	refresh()
func toggle_gate()->void:show_result(army().set_gate_open(not army().projection().gate_open),"已切换主关，后续行军日步按当前通行条件执行。")
func focus_army()->void:
	var p: Array=army().position_local();model.camera_x=float(model.view.world_origin[0])+p[0];model.camera_y=float(model.view.world_origin[1])+p[1];model.set_zoom(1.7);refresh()
func save()->void:
	auto_running=false;canvas.finish_animation();var paused=army().set_paused(true)
	show_result(army().write_save(save_path) if paused.ok else paused,"已保存并暂停：部队、命令、日期、主关与损毁状态。")
func restore()->void:
	auto_running=false;var result=army().read_save(save_path)
	if result.ok:canvas.finish_animation()
	show_result(result,"已重读同一部队和行军日步；点击继续恢复演示。")
func reset()->void:
	auto_running=false;get_node("/root/Session").recreate();model.host=get_node("/root/Session").state;model.load_error=model.host.error;canvas.finish_animation();show_result({"ok":true},"演示已重置，磁盘存档保持。")
func _process(delta: float)->void:
	if not auto_running or _busy:return
	_remaining-=delta
	if _remaining<=0:_remaining=step_seconds;advance()
func _unhandled_key_input(event: InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode>=KEY_1 and event.keycode<=KEY_4:model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][event.keycode-KEY_1]);refresh()
	elif event.keycode==KEY_G:toggle_gate()
	elif event.keycode==KEY_SPACE:
		if auto_running:pause()
		else:play()
	elif event.keycode==KEY_ESCAPE:get_tree().quit()
