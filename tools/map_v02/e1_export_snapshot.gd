extends SceneTree
func _initialize() -> void:
	create_timer(60).timeout.connect(func():printerr("E1_SNAPSHOT_TIMEOUT");quit(1))
	call_deferred("run")
func run() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():printerr("E1 snapshot requires explicit output");quit(1);return
	var result: Dictionary=load("res://v02/e1/effective_map_adapter.gd").new().capture("res://bundle/authoring_publication.json")
	if not result.ok:printerr(JSON.stringify(result));quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file==null:printerr("E1 snapshot write failed");quit(1);return
	file.store_string(JSON.stringify(result.snapshot,"\t"));file.close()
	print("E1_SNAPSHOT objects=",result.snapshot.objects.size());quit(0)
