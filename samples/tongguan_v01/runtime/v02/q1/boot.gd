extends Node
func _ready() -> void:
	get_window().content_scale_size=Vector2i(1920,1080);get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	get_window().title="潼关 v0.2 · Q1 验证版"
	call_deferred("run")
func run() -> void:
	var args: Array=Array(OS.get_cmdline_user_args());var kind:="interactive";var output:=""
	for arg in args:
		if arg.begins_with("--q1="):kind=arg.substr(5)
		if arg.begins_with("--report="):output=arg.substr(9)
	if kind=="interactive":add_child(load("res://v02/q1/app.gd").new());return
	if output.is_empty():printerr("Q1 explicit report required");get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	get_tree().create_timer(900).timeout.connect(func():printerr("Q1_RUNTIME_GUARD_TIMEOUT");get_tree().quit(1))
	if kind=="performance":
		var runner=load("res://v02/q1/performance.gd").new();runner.output=output;add_child(runner);return
	var script: String={"c1":"res://v02/c1/runtime_checks.gd","fixtures":"res://v02/q1/fixture_checks.gd","smoke":"res://v02/q1/smoke.gd","query":"res://v02/q1/query_checks.gd","ab":"res://v02/q1/ab_checks.gd"}.get(kind,"")
	if script.is_empty():printerr("Q1 unknown mode ",kind);get_tree().quit(1);return
	var result: Dictionary=await load(script).new().run(self,output)
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Q1_RESULT ",JSON.stringify({"kind":kind,"checks":result.get("checks",0),"failures":result.get("failures",[])}));get_tree().quit(0 if result.get("failures",[]).is_empty() else 1)
