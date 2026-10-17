extends Node
func _ready() -> void:
	var window=get_window();window.title="潼关 · E1 分页包验证"
	window.content_scale_size=Vector2i(1920,1080);window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	call_deferred("run")
func frames() -> void:
	for i in 5:await get_tree().process_frame
func run() -> void:
	var native:="--e1-native-check" in OS.get_cmdline_user_args()
	var checking:=native or "--e1-check" in OS.get_cmdline_user_args()
	if not checking:
		add_child(load("res://v02/e1/app.gd").new());return
	get_tree().create_timer(120).timeout.connect(func():printerr("E1_CHECK_TIMEOUT");get_tree().quit(1))
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():printerr("Explicit E1 report required");get_tree().quit(1);return
	var runner=load("res://v02/e1/checks.gd").new()
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e1/config.json"))
	var result: Dictionary=runner.run(config,native)
	if native and result.failures.is_empty():
		var app=load("res://v02/e1/app.gd").new();add_child(app)
		result.captures=[]
		for id in ["lab","tongguan"]:
			app.choose(id);await frames();await RenderingServer.frame_post_draw
			var image=get_viewport().get_texture().get_image()
			if image.get_size()!=Vector2i(1920,1080):result.failures.append("actual 1920x1080 screenshot "+id)
			var path: String=output.get_base_dir()+"/"+str(id)+".png"
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			if image.save_png(path)!=OK:result.failures.append("save screenshot "+id)
			result.captures.append({"package":id,"path":path,"size":[image.get_width(),image.get_height()]})
		remove_child(app);app.queue_free();await frames()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("E1_RUNTIME ",JSON.stringify({"checks":result.checks,"failures":result.failures}));get_tree().quit(0 if result.failures.is_empty() else 1)
