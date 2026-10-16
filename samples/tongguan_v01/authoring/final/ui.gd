extends "res://r3_authoring/workshop.gd"
var geometry_label: Label
var warehouse_button: Button
var pin_slot_button: Button
func _ready()->void:
	super._ready();host=load("res://final/resolver.gd").new()
	var previous=canvas;remove_child(previous)
	canvas=load("res://final/canvas.gd").new();canvas.host=host;canvas.font=theme.default_font
	for field in ["anchor_left","anchor_right","anchor_top","anchor_bottom","offset_left","offset_right","offset_top","offset_bottom"]:canvas.set(field,previous.get(field))
	previous.queue_free();add_child(canvas);canvas.changed.connect(refresh)
	workspace_path="user://authoring/workspace.json";publication_path="user://authoring/publication.json"
	get_window().title="潼关 · v0.1 制作与发布"
	for node in get_children():
		if node is Label and node.position.y<90 and node.text.contains("潼关"):node.text="潼关 / v0.1 制作与发布"
	var panel=scroll.get_child(0)
	var extra=VBoxContainer.new();panel.add_child(extra);panel.move_child(extra,0)
	geometry_label=label(extra,"旧数据几何冲突仅报告；不自动移动或删除。",14)
	button(extra,"报告完整占地冲突（只读）",func():var rows=host.geometry_conflicts();result_label.text="几何冲突 %d；对象保持：\n"%rows.size()+JSON.stringify(rows,"\t"))
	warehouse_button=button(extra,"仓库表现水平偏移 4m / 归位",func():show_result(host.move_warehouse([4,0] if host.layout_record().warehouse_offset_m==[0,0] else [0,0]),"仓库表现补丁已记录；地块和建设状态保持。"))
	pin_slot_button=button(extra,"冻结仓储地块几何",func():show_result(host.pin_layout_slot("tongguan.slot.rear_storage_01",true),"几何已冻结；玩家仍可在允许地块建设。"))
	button(extra,"定位仓库制作接地点",func():canvas.center=Vector2(-500,-205);canvas.zoom=2.4;refresh())
	label(extra,"偏移与地块冻结进入同一撤销、保存和发布链。制作工具不保存玩家钱款、施工或军队。",14)
	refresh()

func refresh()->void:
	super.refresh()
	if geometry_label!=null:geometry_label.text="完整占地冲突 %d（仅报告，对象保持）"%host.geometry_conflicts().size()
