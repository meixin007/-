extends "res://construction/ui.gd"
var profile_choice: OptionButton
var route_choice: OptionButton
var known_choice: CheckBox
var passage_label: Label
var publication_label: Label
var publication_path: LineEdit
var import_button: Button
func _ready()->void:
	super._ready();get_window().title="潼关 · R3 制作与通行完整性验收"
	for node in get_children():
		if node is Label and node.text=="潼关  /  建设、军队与同一时间":node.text="潼关  /  制作发布与受控通行"
	var panel=rear_button.get_parent()
	var controls=VBoxContainer.new();panel.add_child(controls);panel.move_child(controls,0)
	label(controls,"合成险径条件（非历史道路）")
	profile_choice=OptionButton.new();profile_choice.add_item("普通军队配置");profile_choice.add_item("轻装配置（同一验证部队）");controls.add_child(profile_choice)
	profile_choice.item_selected.connect(func(index):show_result(army().set_movement_profile("ordinary" if index==0 else "light"),"已切换验证部队配置，兵额保持100人。"))
	known_choice=CheckBox.new();known_choice.text="部队已知合成险径";controls.add_child(known_choice);known_choice.toggled.connect(func(known):show_result(army().set_path_known(known),"已更新运行时已知条件。"))
	route_choice=OptionButton.new();route_choice.add_item("命令路线：主通道");route_choice.add_item("命令路线：合成险径");controls.add_child(route_choice)
	passage_label=label(controls,"",14)
	var publications=scroll_page("制作发布")
	publication_label=label(publications,"")
	label(publications,"先在独立制作工具编辑并发布，再读取。此处只更新表现，不替换通道定义或施工规则。",15)
	publication_path=LineEdit.new();publication_path.text="user://authoring/publication.json";publications.add_child(publication_path)
	import_button=button(publications,"读取制作发布",import_presentation)
	button(publications,"选择发布文件",func():
		pause()
		var dialog=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["*.json ; 制作发布文件"]);add_child(dialog)
		dialog.file_selected.connect(func(path):publication_path.text=path;dialog.queue_free())
		dialog.canceled.connect(func():dialog.queue_free());dialog.popup_centered_ratio(0.7))
	label(publications,"读取后的表现与发布身份随本阶段存档保存。制作的v4源文档、补丁和撤销历史保存在制作工具目录中。",14)
	refresh()
func refresh()->void:
	super.refresh()
	if profile_choice==null or not army().error.is_empty():return
	var force: Dictionary=army().snapshot().force
	profile_choice.select(0 if force.movement_profile=="ordinary" else 1);known_choice.set_pressed_no_signal(army().path_known())
	state_label.text=state_label.text.replace("主关候行","通道候行")+" · "+("普通配置" if force.movement_profile=="ordinary" else "轻装配置")
	var passage=army().passage("tg_synthetic_trail")
	passage_label.text="险径：允许通行" if passage.is_passable else "险径："+str(passage.get("reason","条件未满足"))
	if publication_label!=null:
		var meta: Dictionary=army().context.state.local_node_state[army().NODE_ID][army().PRESENTATION_FIELD]
		publication_label.text="当前制作发布："+str(meta.publication_sha256).left(16)+"\n表现对象："+str(meta.authoring.generated.size())
func command(goal: String)->void:
	var mode="trail" if route_choice!=null and route_choice.selected==1 else "main"
	show_result(army().order(goal,mode),"已下达路线命令；实际日步持续核对单位与已知条件。")
func advance()->void:
	if _busy:return
	_busy=true;var result=army().advance_step();_busy=false
	if result.ok:canvas.animate_path(result.get("visual_points",[]),step_seconds*0.8);refresh()
	else:auto_running=false;show_result(result,"")
func import_presentation()->void:
	var result=army().import_publication(publication_path.text.strip_edges());show_result(result,"已读取制作发布；军队、主关、资金、日期与工程保持。")
func _process(delta: float)->void:
	super._process(delta)
	var cache=get_node("/root/Session").cache
	if canvas!=null and (not cache.ready or cache.detail_blend<1.0):canvas.queue_redraw()
