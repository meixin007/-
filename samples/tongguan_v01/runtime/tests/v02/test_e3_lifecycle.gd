extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	create_timer(90).timeout.connect(func():printerr("E3_CORE_TIMEOUT");quit(1))
	var report:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.substr(9)
	if report.is_empty():printerr("Explicit report required");quit(1);return
	var result: Dictionary={"checks":0,"failures":["E3 lifecycle implementation missing"]}
	if FileAccess.file_exists("res://v02/e3/contract_checks.gd"):
		var script=load("res://v02/e3/contract_checks.gd")
		if script!=null and script.can_instantiate():result=script.new().run()
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	var file=FileAccess.open(report,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("E3_CORE ",JSON.stringify(result));quit(0 if result.failures.is_empty() else 1)
