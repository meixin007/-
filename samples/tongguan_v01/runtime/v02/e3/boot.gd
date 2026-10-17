extends Node
func _ready() -> void:
	get_window().title="潼关 · E3 加载状态机与资源生命周期"
	get_window().content_scale_size=Vector2i(1920,1080);get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	call_deferred("run")
func run() -> void:
	if "--e3-check" not in OS.get_cmdline_user_args():add_child(load("res://v02/e3/app.gd").new());return
	get_tree().create_timer(300).timeout.connect(func():printerr("E3_RUNTIME_TIMEOUT");get_tree().quit(1))
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():printerr("Explicit report required");get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var result: Dictionary=await load("res://v02/e3/runtime_checks.gd").new().run(self,output)
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("E3_RUNTIME ",JSON.stringify({"checks":result.checks,"failures":result.failures}));get_tree().quit(0 if result.failures.is_empty() else 1)
