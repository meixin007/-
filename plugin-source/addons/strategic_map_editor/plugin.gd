@tool
extends EditorPlugin
var panel: Control
var loading_label: Label
var requested_visible := false
var load_pending := false

func _enter_tree() -> void:
	# A hidden main-screen plugin must not load the national map at editor startup.
	pass

func _exit_tree() -> void:
	# Editor shutdown may not process queued frees. The tool button group is a
	# RefCounted resource owned by this panel, so release the panel immediately.
	if is_instance_valid(panel): panel.free()
	if is_instance_valid(loading_label): loading_label.free()

func _has_main_screen() -> bool:
	return true

func _make_visible(value: bool) -> void:
	requested_visible=value
	if value and not is_instance_valid(panel):
		if not is_instance_valid(loading_label):
			loading_label=Label.new()
			loading_label.text="正在加载上次的地图…"
			loading_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			loading_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			loading_label.size_flags_vertical=Control.SIZE_EXPAND_FILL
			EditorInterface.get_editor_main_screen().add_child(loading_label)
		loading_label.show()
		if not load_pending:
			load_pending=true
			_load_workbench.call_deferred()
	elif is_instance_valid(loading_label):loading_label.hide()
	if not is_instance_valid(panel): return
	panel.visible = value
	if value: panel.activate_workspace()

func _load_workbench() -> void:
	# Let the editor and loading message paint before restoring a large document.
	await get_tree().process_frame
	await get_tree().process_frame
	load_pending=false
	if not requested_visible or not is_inside_tree():return
	var workbench_script:=load("res://addons/strategic_map_editor/workbench.gd") as GDScript
	if workbench_script==null:
		loading_label.text="地图工坊加载失败，请查看编辑器错误面板。"
		push_error(loading_label.text)
		return
	panel=workbench_script.new()
	panel.restore_last_map_on_start = true
	EditorInterface.get_editor_main_screen().add_child(panel)
	loading_label.hide()
	panel.activate_workspace()

func _get_plugin_name() -> String:
	return "山河工坊"

func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not is_instance_valid(panel) or not panel.has_unsaved_editor_session(): return ""
	return "山河工坊有未保存的地图或未应用输入。选择保存会创建恢复副本（含属性和表现线草稿）；下次在工坊‘恢复项目’继续，原地图文件不覆盖。"

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.has_unsaved_editor_session(): panel.save_editor_session()

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMap","EditorIcons")
