extends Node
func _ready() -> void:
	var window=get_window();window.title="潼关 · E2 可见查询与绘制缓存"
	window.content_scale_size=Vector2i(1920,1080);window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	call_deferred("run")
func run() -> void:
	var native:="--e2-native-check" in OS.get_cmdline_user_args()
	if not native and "--e2-check" not in OS.get_cmdline_user_args():add_child(load("res://v02/e2/app.gd").new());return
	get_tree().create_timer(240).timeout.connect(func():printerr("E2_RUNTIME_TIMEOUT");get_tree().quit(1))
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():printerr("Explicit E2 report required");get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var runner=load("res://v02/e2/runtime_checks.gd").new()
	var result: Dictionary=await runner.run(self,native,output)
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("E2_RUNTIME ",JSON.stringify({"checks":result.checks,"failures":result.failures}));get_tree().quit(0 if result.failures.is_empty() else 1)
