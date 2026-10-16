extends Control
var model: RefCounted
var canvas: Control
var state_label: Label
var economy_label: Label
var quote_label: Label
var work_label: Label
var message_label: Label
var gate_button: Button
var rear_button: Button
var fore_button: Button
var play_button: Button
var pause_button: Button
var step_button: Button
var save_button: Button
var load_button: Button
var quote_button: Button
var build_button: Button
var slot_choice: OptionButton
var kind_choice: OptionButton
var growth_choice: OptionButton
var controls_scroll: ScrollContainer
var tabs: TabContainer
var auto_running := false
var step_seconds := 1.6
var _remaining := 1.6
var _busy := false
var _quote_token := ""
var _selected_slot := ""
var save_path := "user://construction/session.json"
func army(): return get_node("/root/Session").army
func label(parent: Node, value: String, font_size := 16) -> Label:
	var item = Label.new(); item.text=value; item.add_theme_font_size_override("font_size",font_size)
	item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; item.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(item); return item
func button(parent: Node, value: String, action: Callable) -> Button:
	var item=Button.new(); item.text=value; item.custom_minimum_size.y=36; item.pressed.connect(action); parent.add_child(item); return item
func row(parent: Node) -> HBoxContainer:
	var item=HBoxContainer.new(); parent.add_child(item); return item
func scroll_page(title: String) -> VBoxContainer:
	var scroll=ScrollContainer.new(); scroll.name=title; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; tabs.add_child(scroll)
	var panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_constant_override("separation",8); scroll.add_child(panel); return panel
func _ready() -> void:
	model=load("res://runtime/model.gd").new()
	var font=SystemFont.new(); font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"])
	var tv=Theme.new(); tv.default_font=font; tv.default_font_size=16; theme=tv
	var background=ColorRect.new(); background.color=Color("142b33"); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	get_window().title="潼关 · R2 建设与统一状态验收"
	var title=label(self,"潼关  /  建设、军队与同一时间",28); title.position=Vector2(26,20); title.size=Vector2(1400,40)
	var subtitle=label(self,"756年候选地理 · 工款与材料实际入账 · 施工按日推进 · 独立副本",16); subtitle.position=Vector2(28,67); subtitle.size=Vector2(1400,28); subtitle.modulate=Color("b0c5bb")
	canvas=load("res://army/canvas.gd").new(); canvas.model=model; canvas.font=font; canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.offset_left=24; canvas.offset_top=112; canvas.offset_right=-460; canvas.offset_bottom=-48; add_child(canvas); canvas.view_changed.connect(on_map_changed)
	controls_scroll=ScrollContainer.new(); controls_scroll.anchor_left=1; controls_scroll.anchor_right=1; controls_scroll.anchor_bottom=1
	controls_scroll.offset_left=-436; controls_scroll.offset_right=-24; controls_scroll.offset_top=112; controls_scroll.offset_bottom=-48
	controls_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(controls_scroll)
	var panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_constant_override("separation",8); controls_scroll.add_child(panel)
	var cameras=GridContainer.new(); cameras.columns=2; panel.add_child(cameras)
	for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:
		button(cameras,model.view.bookmarks[id].name,func():model.recall_bookmark(id);refresh()).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var camera_row=row(panel); button(camera_row,"保存镜头",func():model.save_bookmark("custom");show_result({"ok":true},"已保存本次镜头。")); button(camera_row,"恢复镜头",func():show_result({"ok":model.recall_bookmark("custom")},"已恢复镜头。"))
	state_label=label(panel,"")
	var time_row=row(panel); play_button=button(time_row,"连续推进",play); pause_button=button(time_row,"暂停",pause); step_button=button(time_row,"推进一天",single_step)
	var save_row=row(panel); save_button=button(save_row,"保存并暂停",save); load_button=button(save_row,"重读本阶段存档",restore)
	tabs=TabContainer.new(); tabs.custom_minimum_size.y=430; tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_child(tabs)
	var build_panel=scroll_page("建设")
	economy_label=label(build_panel,"")
	label(build_panel,"选择地块（也可直接点地图空地）")
	slot_choice=OptionButton.new(); build_panel.add_child(slot_choice)
	for slot in model.host.layout.slots: slot_choice.add_item(slot.name+" · "+str(slot.id).get_slice(".",2))
	slot_choice.item_selected.connect(func(index):select_slot(str(model.host.layout.slots[index].id)))
	kind_choice=OptionButton.new(); build_panel.add_child(kind_choice); kind_choice.item_selected.connect(func(_index):invalidate_quote())
	var build_row=row(build_panel); quote_button=button(build_row,"查看施工报价",preview_build); build_button=button(build_row,"确认开工",commit_build); build_button.disabled=true
	quote_label=label(build_panel,"选择设施后查看报价，再确认开工。",15)
	work_label=label(build_panel,""); work_label.custom_minimum_size.y=62
	var grow_row=row(build_panel); label(grow_row,"成长显示")
	growth_choice=OptionButton.new(); grow_row.add_child(growth_choice)
	for name in ["简约","常态","强化"]: growth_choice.add_item(name)
	growth_choice.item_selected.connect(func(index):show_result(model.host.set_growth(index+1),"已切换成长；原地块和工程身份保持。"))
	button(build_panel,"切换选中设施损毁 / 修复",func():show_result(model.host.set_damage(model.selected_slot,(int(army().projection().module_damage[model.selected_slot])+1)%3),"已切换损毁；施工合同、费用与位置保持。"))
	var army_panel=scroll_page("军队与主关")
	rear_button=button(army_panel,"向关后（西）行军",func():command("tg_rear")); fore_button=button(army_panel,"向关前（东）行军",func():command("tg_fore"))
	gate_button=button(army_panel,"",toggle_gate); button(army_panel,"定位部队",focus_army)
	button(army_panel,"切换关楼损毁（通行仍由主关控制）",func():show_result(model.host.set_damage("gate",(int(army().projection().module_damage.gate)+1)%3),"已切换关楼损毁。"))
	for entry in [["显示城市与关楼","buildings"],["显示树林","trees"],["显示验证道路","route"]]:
		var item=CheckBox.new(); item.text=entry[0]; item.button_pressed=true; army_panel.add_child(item); item.toggled.connect(func(value):
			if entry[1]=="buildings": canvas.show_buildings=value; canvas.show_icon=value
			elif entry[1]=="trees": canvas.show_trees=value
			else: canvas.show_route=value
			canvas.queue_redraw())
	button(army_panel,"测试直接跨主河",func():show_result(army().order("river_north"),""))
	button(panel,"重置本次验收（磁盘存档保留）",reset)
	message_label=label(panel,"先在仓储空地选择仓库，查看报价并开工，再推进三天。",15); message_label.custom_minimum_size.y=60
	label(panel,"工款与工期为验证参数，非历史价格。\n初始营房沿用已验收占位；新设施走实际工程。\n1—4 镜头 / G 主关 / 空格 暂停继续 / Esc 退出",14).modulate=Color("9fb6b5")
	var footer=label(self,"同一存档：军队 · 主关 · 资源 · 工程 · 成长与损毁　 /　主工程和旧验收入口保留",14)
	footer.anchor_top=1; footer.anchor_bottom=1; footer.anchor_right=1; footer.offset_left=26; footer.offset_right=-24; footer.offset_top=-31; footer.offset_bottom=-6
	select_slot(model.selected_slot); focus_construction(); refresh()
func focus_construction() -> void:
	model.camera_x=float(model.view.world_origin[0])-220; model.camera_y=float(model.view.world_origin[1])-130; model.set_zoom(1.1); refresh()
func select_slot(id: String) -> void:
	model.selected_slot=id; _selected_slot=id; kind_choice.clear()
	var slot=model.host.slot_by_id(id)
	for kind in slot.allowed_buildings:
		kind_choice.add_item(army()._economy.catalog.facilities.get(kind,{"name":kind}).name); kind_choice.set_item_metadata(kind_choice.item_count-1,kind)
	for i in model.host.layout.slots.size():
		if model.host.layout.slots[i].id==id: slot_choice.select(i)
	invalidate_quote(); refresh()
func invalidate_quote() -> void:
	_quote_token=""
	if build_button!=null: build_button.disabled=true
	if quote_label!=null: quote_label.text="请选择允许设施并查看报价；日期或状态变化后需重新报价。"
func on_map_changed() -> void:
	if model.selected_slot!=_selected_slot: select_slot(model.selected_slot)
	refresh()
func preview_build() -> void:
	var kind: String=str(kind_choice.get_item_metadata(kind_choice.selected))
	var result=army().preview_construction(model.selected_slot,kind)
	_quote_token=str(result.get("token","")); build_button.disabled=not result.ok
	if result.ok: quote_label.text="%s：工款 %d · 木料 %d · 工期 %d 天\n工匠、产权、面积和材料已检查；确认后扣费开工。"%[result.name,result.price,result.material_quantity,result.duration_days]
	show_result(result,"报价有效，可确认开工。")
func commit_build() -> void:
	var result=army().commit_construction(_quote_token); _quote_token=""; build_button.disabled=true
	show_result(result,"已开工：工款与木料已入账，点击推进一天或连续推进。")
func show_result(result: Dictionary, success: String) -> void:
	if message_label!=null:
		message_label.text=success if result.get("ok",false) else "未执行："+str(result.get("message",result.get("error","未知原因")))
		message_label.modulate=Color("cde6c8") if result.get("ok",false) else Color("f5b19a")
	refresh()
func refresh() -> void:
	if state_label==null: return
	if not army().error.is_empty(): state_label.text=army().error; return
	var snapshot=army().snapshot(); var names={"idle":"待命","marching":"行军","waiting":"主关候行","arrived":"已到达"}
	state_label.text="验证日 %d · %s\n通行验收队 100人 · %s"%[snapshot.day,"已暂停" if snapshot.paused else ("连续推进" if auto_running else "等待推进"),names[snapshot.order.status]]
	if economy_label!=null:
		var resources=army().economy(); economy_label.text="建设款 %d  /  工匠已收 %d\n工匠可用木料 %d"%[resources.cash,resources.artisan_cash,resources.timber]
		var order=army().construction_for(model.selected_slot); var slot=model.host.slot_by_id(model.selected_slot)
		if not order.is_empty(): work_label.text="%s · %s\n实际工日 %d / %d%s"%[slot.name,"已竣工" if order.status=="completed" else "施工中",order.work_days,order.recipe.duration_days,"\n"+order.blocked_reason if not str(order.blocked_reason).is_empty() else ""]
		else: work_label.text="%s · %s"%[slot.name,"初始营房（沿用布局）" if slot.initial_building!="empty" else ("空地可建设" if snapshot.city.growth_stage>=slot.unlock_stage else "成长至第%d档开放"%slot.unlock_stage)]
		growth_choice.select(int(snapshot.city.growth_stage)-1)
	if gate_button!=null: gate_button.text="主关：开放 · 点击关闭" if snapshot.city.gate_open else "主关：关闭 · 点击开放"
	canvas.queue_redraw()
func command(goal: String) -> void: show_result(army().order(goal),"已下达行军命令；推进日期后沿受控道路移动。")
func play() -> void:
	var result=army().set_paused(false)
	if result.ok: auto_running=true; _remaining=step_seconds
	show_result(result,"连续推进同一日期；施工与行军一起结算。")
func pause() -> void:
	auto_running=false; canvas.finish_animation(); show_result(army().set_paused(true),"已暂停日期、施工和行军。")
func advance() -> void:
	if _busy: return
	_busy=true; var result=army().advance_step(); _busy=false
	if result.ok: canvas.animate_to(army().position_local(),step_seconds*0.8); refresh()
	else: auto_running=false; show_result(result,"")
func single_step() -> void:
	auto_running=false; var resumed=army().set_paused(false)
	if not resumed.ok: show_result(resumed,""); return
	advance(); show_result(army().set_paused(true),"已推进一天并暂停。")
func toggle_gate() -> void: show_result(army().set_gate_open(not army().projection().gate_open),"已切换主关；候行与施工分别按规则结算。")
func focus_army() -> void:
	var p=army().position_local(); model.camera_x=float(model.view.world_origin[0])+p[0]; model.camera_y=float(model.view.world_origin[1])+p[1]; model.set_zoom(1.7); refresh()
func save() -> void:
	auto_running=false; canvas.finish_animation(); var paused=army().set_paused(true)
	show_result(army().write_save(save_path) if paused.ok else paused,"已保存：工程、工款、材料、日期、军队、主关与城市状态。")
func restore() -> void:
	auto_running=false; var result=army().read_save(save_path)
	if result.ok: canvas.finish_animation(); invalidate_quote()
	show_result(result,"已重读本阶段完整状态；可继续施工与行军。")
func reset() -> void:
	auto_running=false; get_node("/root/Session").recreate(); model.host=get_node("/root/Session").state; model.load_error=model.host.error
	canvas.finish_animation(); invalidate_quote(); show_result({"ok":true},"已恢复本次初始验收资源，磁盘存档保留。")
func _process(delta: float) -> void:
	if not auto_running or _busy: return
	_remaining-=delta
	if _remaining<=0: _remaining=step_seconds; advance()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode>=KEY_1 and event.keycode<=KEY_4: model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][event.keycode-KEY_1]); refresh()
	elif event.keycode==KEY_G: toggle_gate()
	elif event.keycode==KEY_SPACE:
		if auto_running: pause()
		else: play()
	elif event.keycode==KEY_ESCAPE: get_tree().quit()
