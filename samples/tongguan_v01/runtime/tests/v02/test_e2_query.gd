extends SceneTree
func _initialize() -> void:
	create_timer(240).timeout.connect(func():printerr("E2_TEST_TIMEOUT");quit(1))
	call_deferred("run")
func run() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():printerr("Explicit E2 report required");quit(1);return
	var result: Dictionary={"checks":1,"failures":["E2 query implementation must exist"]}
	var session=root.get_node_or_null("Session")
	var state_before: String=session.army.digest(session.army.context.state.to_dictionary()) if session!=null else ""
	if FileAccess.file_exists("res://v02/e2/contract_checks.gd") and FileAccess.file_exists("res://v02/e2/spatial_index.gd"):
		var script=load("res://v02/e2/contract_checks.gd")
		if script!=null and script.can_instantiate():result=script.new().run()
	if session!=null:
		result.checks+=1
		if session.army.digest(session.army.context.state.to_dictionary())!=state_before:result.failures.append("E2 mutated shared game authority")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("E2_SOURCE ",JSON.stringify({"checks":result.checks,"failures":result.failures}));quit(0 if result.failures.is_empty() else 1)
