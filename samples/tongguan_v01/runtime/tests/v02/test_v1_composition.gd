extends SceneTree
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	check(FileAccess.file_exists("res://v02/v1/composition.tscn"), "editable V1 composition scene exists")
	if not FileAccess.file_exists("res://v02/v1/composition.tscn"): finish(); return
	check(FileAccess.file_exists("res://v02/v1/rig.gd"), "V1 rig exists")
	if not FileAccess.file_exists("res://v02/v1/rig.gd"): finish(); return
	var script = load("res://v02/v1/rig.gd")
	check(script != null and script.can_instantiate(), "V1 rig script parses")
	if script == null or not script.can_instantiate(): finish(); return
	for path in ["res://v02/v1/app.gd","res://v02/v1/canvas.gd","res://v02/v1/boot.gd"]:
		var dependency=load(path)
		check(dependency!=null and dependency.can_instantiate(),"entry parses: "+path)
	var scene = load("res://v02/v1/composition.tscn")
	check(scene != null, "composition can be loaded")
	if scene == null: finish(); return
	var session = root.get_node("Session")
	var before: String = session.army.digest(session.army.context.state.to_dictionary())
	var rig = scene.instantiate(); root.add_child(rig)
	await process_frame
	check(session.army.digest(session.army.context.state.to_dictionary()) == before, "loading V1 never changes shared authority")
	check(rig.socket_error() < 0.001, "both wall cuts meet gate sockets")
	check(rig.get_node("Objects/Gate").rotation == 0, "selected gate remains unrotated")
	check(rig.get_node("Objects/Warehouse").position == Vector2(-567.5,-227.5), "warehouse keeps original slot center")
	check(rig.style.visual_review == "pending", "no automatic art acceptance")
	check(rig.style.assets.gate.sha256 == FileAccess.get_sha256("res://bundle/art/gate_eastwest.png"), "old gate hash preserved")
	check(rig.style.new_painted_assets == 2, "bounded new painted assets")
	check(rig.get_node("Terrain/Ground").get_child_count() == 12 and rig.get_node("Terrain/Water").get_child_count() == 12, "continuous field crosses adjacent pages")
	var original: Vector2 = rig.get_node("Objects/Gate").position
	rig.guides = true; rig.queue_redraw(); await process_frame
	check(rig.get_node("Objects/Gate").position == original, "guides do not move assets")
	root.remove_child(rig); rig.queue_free(); await process_frame
	finish()
func finish() -> void:
	var path := "user://tests/map_v02/v1_contract.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): path=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("V1_CONTRACT ",JSON.stringify({"checks":checks,"failures":failures})); quit(0 if failures.is_empty() else 1)
