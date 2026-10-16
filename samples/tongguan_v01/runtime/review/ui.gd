extends "res://integrity/ui.gd"
var review_panel: VBoxContainer
var baseline_button: Button
var buildings_choice: CheckBox
var constraints_choice: CheckBox
var footprint_choice: CheckBox
var crossings_choice: CheckBox
var contour_choice: CheckBox
var slope_choice: CheckBox
var crossing_picker: OptionButton
var geometry_label: Label
var history: Dictionary={}
var policy: Dictionary={}
func _ready()->void:
	super._ready()
	policy=JSON.parse_string(FileAccess.get_file_as_string("res://review/policy.json"))
	history=JSON.parse_string(FileAccess.get_file_as_string("res://review/history.json"))
	model.view.bookmarks=policy.bookmarks.duplicate(true)
	var previous=canvas;remove_child(previous);previous.queue_free()
	canvas=load("res://review/canvas.gd").new();canvas.model=model;canvas.font=theme.default_font
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.offset_left=24;canvas.offset_top=112;canvas.offset_right=-460;canvas.offset_bottom=-48
	add_child(canvas);canvas.view_changed.connect(on_map_changed)
	get_window().title="潼关 · R4 地理与组合画面验收"
	for node in get_children():
		if not node is Label:continue
		if node.position.y==20:node.text="潼关  /  地理与组合画面"
		elif node.position.y==67:node.text="756年关址阶段 · 现代地理参照 · 同锚点关楼 · 工程占位候选"
		elif node.anchor_top==1:node.text="滚轮缩放 / 拖动平移 / 1—4 镜头 · 图层不改军队、建设或主关许可 · Copernicus / © OpenStreetMap"
	var buttons=_all_buttons(controls_scroll)
	var old_names=["东亚示意","关河背景","关城全景","建设槽位"]
	var ids=["east_asia","guanzhong_east","tongguan_context","gate_close"]
	for item in buttons:
		var index=old_names.find(item.text)
		if index>=0:item.text=policy.bookmarks[ids[index]].name
	review_panel=scroll_page("地理与画面");tabs.current_tab=tabs.get_tab_count()-1
	geometry_label=label(review_panel,"8个地块完整占地与接路通过。\n长通道有4处现代水线交点，均未授权桥渡。",15)
	baseline_button=button(review_panel,"查看 R3 同镜头基线",toggle_baseline)
	buildings_choice=_toggle("显示关楼、墙体和院落",true,func(value):canvas.show_buildings=value;canvas.show_icon=value)
	constraints_choice=_toggle("叠加人工约束与1500米审查圈",false,func(value):canvas.show_constraints=value)
	footprint_choice=_toggle("叠加院落完整占地",false,func(value):canvas.show_footprints=value)
	crossings_choice=_toggle("标出未核跨沟点",true,func(value):canvas.show_crossings=value)
	contour_choice=_toggle("显示现代地形等高线",true,func(value):canvas.show_contours=value)
	slope_choice=_toggle("切换现代坡度参照",false,func(value):canvas.show_slope=value)
	label(review_panel,"未核交点（不新增桥渡）",16)
	crossing_picker=OptionButton.new();review_panel.add_child(crossing_picker)
	for i in canvas.audit.candidate_crossings.size():crossing_picker.add_item("%d · 现代水线交点"%(i+1))
	button(review_panel,"定位选定跨沟点",focus_crossing)
	label(review_panel,"历史选择与边界",19)
	label(review_panel,"按691迁近黄河后的关址阶段核查756语境。精确关门、唐城防线、岸线与跨沟设施仍待核。1500米圈为人工审图范围。",15)
	label(review_panel,"门楼沿用你选定的图像；大小是显示夸张。院落、续墙和损毁仍为工程占位，本轮不新增正式素材批次。",15)
	label(review_panel,"依据：潼关县志第12、539页；资治通鉴卷218；Copernicus DSM及OSM现代参照。完整来源与资产缺口见本阶段报告。",14)
	save_path="user://review/session.json"
	model.recall_bookmark("gate_close");refresh()
func _all_buttons(node: Node)->Array:
	var values=[]
	for child in node.get_children():
		if child is Button:values.append(child)
		values.append_array(_all_buttons(child))
	return values
func _toggle(text_value: String,initial: bool,action: Callable)->CheckBox:
	var item=CheckBox.new();item.text=text_value;item.button_pressed=initial;review_panel.add_child(item)
	item.toggled.connect(func(value):action.call(value);canvas.queue_redraw())
	return item
func toggle_baseline()->void:
	canvas.baseline_view=not canvas.baseline_view
	baseline_button.text="返回 R4 组合候选" if canvas.baseline_view else "查看 R3 同镜头基线"
	canvas.queue_redraw()
func focus_crossing()->void:
	var crossing: Dictionary=canvas.audit.candidate_crossings[crossing_picker.selected]
	var p: Array=crossing.points_m[0]
	model.camera_x=float(model.view.world_origin[0])+p[0];model.camera_y=float(model.view.world_origin[1])+p[1];model.set_zoom(0.6);refresh()
	geometry_label.text="现代水线交点 %d：\n跨沟设施、历史位置均未核定，未授权军队通行。"%(crossing_picker.selected+1)
