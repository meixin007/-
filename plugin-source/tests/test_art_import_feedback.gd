extends SceneTree
const Bench = preload("res://addons/strategic_map_editor/workbench.gd")
const Shell = preload("res://addons/strategic_map_editor/dialog_shell.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: ", message)

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): printerr("ART_IMPORT_FEEDBACK_TIMEOUT"); quit(1))
	run.call_deferred()

func visible_dialog(bench):
	for child in bench.get_children():
		if child is Shell and child.visible: return child
	return null

func run() -> void:
	root.size = Vector2i(1280, 900)
	var bench = Bench.new()
	bench.autosave_enabled = false
	bench.layout_persistence_enabled = false
	bench.restore_last_map_on_start = false
	bench.recovery_store.root_path = "user://import-feedback-recovery"
	root.add_child(bench)
	await process_frame
	var before: Dictionary = bench.doc.data.duplicate(true)
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(8, 8, 48, 48), Color.WHITE)
	var source := "user://import-feedback.png"
	for edge in [Vector2i(20, 0), Vector2i(0, 20)]:
		image.set_pixelv(edge, Color.WHITE)
		check(image.save_png(source) == OK, "border fixture saved")
		bench.file_action = "art_png"
		bench._file_selected(source)
		await process_frame
		var dialog = visible_dialog(bench)
		check(dialog != null, "invalid PNG opens visible feedback")
		if dialog != null:
			check(dialog.dialog_text.contains("透明边缘") and dialog.dialog_text.contains("import-feedback.png"), "feedback names file and cause")
			check(dialog.ok_button_text == "重新选择 PNG", "feedback offers retry")
			dialog._cancel()
			await process_frame
		image.set_pixelv(edge, Color.TRANSPARENT)
	check(image.save_png(source) == OK, "valid fixture saved")
	bench._file_selected(source)
	await process_frame
	var valid_dialog = visible_dialog(bench)
	check(valid_dialog != null, "valid PNG opens settings")
	if valid_dialog != null:
		check(valid_dialog.ok_button_text == "校验并导入素材包", "valid PNG retains import action")
		valid_dialog._cancel()
		await process_frame
	bench._file_selected("user://missing-import-feedback.png")
	await process_frame
	var missing_dialog = visible_dialog(bench)
	check(missing_dialog != null, "missing file opens feedback")
	if missing_dialog != null:
		missing_dialog.get_ok_button().pressed.emit()
		await process_frame
		check(bench.file_dialog.visible and bench.file_action == "art_png", "retry reopens PNG picker")
		bench.file_dialog.hide()
	check(bench.doc.data == before, "probe and cancel preserve map")
	bench.queue_free()
	await process_frame
	print("ART_IMPORT_FEEDBACK: ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
