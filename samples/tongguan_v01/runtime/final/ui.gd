extends "res://review/ui.gd"
var migration_source: LineEdit
var migration_preview_button: Button
var migration_commit_button: Button
var recovery_button: Button
var migration_summary: Label
var migration_token:=""
func _ready()->void:
	super._ready();get_window().title="潼关 · v0.1 最终验收"
	save_path="user://final/session.json"
	for node in get_children():
		if node is Label and node.position.y==20:node.text="潼关 / v0.1 最终验收"
	var panel=scroll_page("存档导入")
	label(panel,"R3 / R4 → 最终验证场景",18)
	label(panel,"只导入相同布局和通道合同。军队、工程、资源与日期完整保留；原文件不修改。R1/R2或其他战役会明确拒绝。",15)
	migration_source=LineEdit.new();migration_source.placeholder_text="选择已有R3/R4存档JSON";panel.add_child(migration_source)
	button(panel,"选择旧存档",choose_migration)
	migration_preview_button=button(panel,"预览导入（不采用）",preview_migration)
	migration_commit_button=button(panel,"采用并保存到本阶段存档",commit_migration);migration_commit_button.disabled=true
	migration_summary=label(panel,"先暂停日期，再选择旧存档并预览。地块映射固定，未映射版本不重绑建筑。",15)
	recovery_button=button(panel,"恢复本阶段存档的上一代备份",recover_previous)
	label(panel,"最终制作工具使用独立入口，发布后可在“制作发布”页读取。地图、工程、军队仍由同一GameState与日期管理。",14)
	# Keep all five entry points visible within the fixed review sidebar.
	for i in 5:tabs.set_tab_title(i,["建设","军队","制作发布","地理画面","存档导入"][i])
	publication_path.text="user://authoring/publication.json"
	tabs.current_tab=3;refresh()
func choose_migration()->void:
	var dialog=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["*.json ; 存档JSON"]);add_child(dialog)
	dialog.file_selected.connect(func(path):migration_source.text=path;migration_token="";migration_commit_button.disabled=true;dialog.queue_free())
	dialog.canceled.connect(func():dialog.queue_free());dialog.popup_centered_ratio(0.7)
func preview_migration()->void:
	if auto_running:show_result({"ok":false,"message":"请先暂停日期，再预览存档导入。"},"");return
	var result=army().preview_import(migration_source.text.strip_edges(),save_path)
	migration_token=result.get("token","");migration_commit_button.disabled=not result.ok
	if result.ok:
		var summary: Dictionary=result.summary
		migration_summary.text="原场景：%s\n验证日 %d / 成长 %d / 地块 %d\n将完整采用；原文件保留。"%[summary.source_campaign_id,int(summary.day),int(summary.growth_stage),int(summary.slots)]
	show_result(result,"导入预览通过，当前游戏状态保持。")
func commit_migration()->void:
	auto_running=false;var result=army().commit_import(migration_token);migration_token="";migration_commit_button.disabled=true
	if result.ok:canvas.finish_animation();invalidate_quote()
	show_result(result,"已导入并保存完整状态；原文件未修改。")
func recover_previous()->void:
	auto_running=false;var result=army().restore_previous_save(save_path)
	if result.ok:canvas.finish_animation();invalidate_quote()
	show_result(result,"已恢复经过验证的上一代完整存档。")
func on_map_changed()->void:
	# Camera movement changes the drawing, not the business panels or quote.
	if model.selected_slot!=_selected_slot:select_slot(model.selected_slot)
	else:canvas.queue_redraw()
