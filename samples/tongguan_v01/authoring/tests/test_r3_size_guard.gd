extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var host=preload("res://r3_authoring/resolver.gd").new();var path="user://r3_tests/size_guard_%d.json"%Time.get_ticks_usec()
	var initial=host._atomic_write(path,{"old_version":true});var before=FileAccess.get_file_as_string(path)
	var result=host._atomic_write(path,{"padding":"x".repeat(16*1024*1024)})
	var passed=initial.ok and not result.ok and FileAccess.get_file_as_string(path)==before
	var out="user://r3_tests/size_guard.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir());FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"large_write_rejected":not result.ok,"old_version_preserved":FileAccess.get_file_as_string(path)==before}))
	print("R3_SIZE_GUARD: ","PASS" if passed else "FAIL");host=null;quit(0 if passed else 1)
