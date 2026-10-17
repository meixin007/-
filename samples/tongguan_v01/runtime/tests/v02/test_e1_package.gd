extends SceneTree
var checks := 0
var failures: Array = []
func _initialize() -> void:
	create_timer(90).timeout.connect(func():printerr("E1_TEST_TIMEOUT");quit(1))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func finish() -> void:
	var path := "user://tests/map_v02/e1_source.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):path=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("E1_SOURCE ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
func run() -> void:
	check(FileAccess.file_exists("res://v02/e1/package_loader.gd"),"shared E1 package loader exists")
	check(FileAccess.file_exists("res://v02/e1/effective_map_adapter.gd"),"read-only effective snapshot adapter exists")
	if not failures.is_empty():finish();return
	var loader_script=load("res://v02/e1/package_loader.gd")
	check(loader_script!=null and loader_script.can_instantiate(),"runtime loader parses")
	var adapter=load("res://v02/e1/effective_map_adapter.gd").new()
	var session=root.get_node("Session")
	var before: String=session.army.digest(session.army.context.state.to_dictionary())
	var result: Dictionary=adapter.capture("res://bundle/authoring_publication.json")
	check(result.ok,"original publication validator accepts effective snapshot")
	if result.ok:
		check(result.snapshot.objects.size()==72,"all 72 effective source objects retained")
		check(result.snapshot.compatibility.world_id==session.army.definition.world_id,"existing world identity retained")
		check(result.snapshot.compatibility.graph_version==session.army.definition.graph_version,"existing corridor identity retained")
		var ids: Array=[]
		for item in result.snapshot.objects:ids.append(item.id)
		check(ids.has("manual.1"),"manual object retained")
		check(not ids.has("tongguan.decor.forest_east.0.1"),"tombstone remains deleted")
		check(result.snapshot.patch_sidecar.pins.size()>0,"pins retained")
		check(result.snapshot.authoring.slot_pins.size()==8,"eight slot locks retained")
		result.snapshot.objects[0].position_m[0]+=999
		var again: Dictionary=adapter.capture("res://bundle/authoring_publication.json")
		check(again.ok and again.snapshot.objects[0].position_m[0]!=result.snapshot.objects[0].position_m[0],"snapshots are deep isolated")
	check(session.army.digest(session.army.context.state.to_dictionary())==before,"snapshot reads never mutate authority")
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring_publication.json"))
	for kind in ["duplicate_raw","wrong_key"]:
		var bad: Dictionary=original.duplicate(true)
		if kind=="duplicate_raw":bad.source_v4.presentation.instances.append(bad.source_v4.presentation.instances[0].duplicate(true))
		else:bad.runtime_authoring.generated[bad.runtime_authoring.generated.keys()[0]].id="wrong_identity"
		bad.erase("content_sha256");bad.content_sha256=session.army.digest(bad)
		var path: String="user://tests/map_v02/e1_adapter_"+str(kind)+".json"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir());var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(bad));file.close()
		var rejected: Dictionary=adapter.capture(path)
		check(not rejected.ok and rejected.code=="invalid_publication","source integrity rejection "+kind)
	finish()
