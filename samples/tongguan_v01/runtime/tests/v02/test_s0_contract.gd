extends SceneTree
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func run() -> void:
	var selector_path := "res://v02/service_selection.gd"
	check(FileAccess.file_exists(selector_path), "S0 selector exists")
	if not FileAccess.file_exists(selector_path): finish(); return
	var selector = load(selector_path)
	for path in ["res://v02/probe.gd", "res://v02/boot.gd"]:
		var script = load(path)
		check(script != null and script.can_instantiate(), "new entry script parses: " + path)
	var probe = load("res://v02/probe.gd").new()
	check(probe.has_method("target_dimensions_match"), "dimensions compare decoded JSON numerically")
	if probe.has_method("target_dimensions_match"):
		check(probe.target_dimensions_match({"viewport_texture_px":[1920,1080], "window_client_px":[1920,1080]}, JSON.parse_string("[1920,1080]")), "decoded numeric target accepts exact dimensions")
		check(not probe.target_dimensions_match({"viewport_texture_px":[1853,1043], "window_client_px":[1920,1061]}, JSON.parse_string("[1920,1080]")), "smaller actual buffer rejected")
		check(probe.target_dimensions_match({"viewport_texture_px":[1920,1080], "window_client_px":[2880,1618]}, JSON.parse_string("[1920,1080]")), "fixed render target independent of client scaling")
	check(selector.choose([], []).mode == "legacy", "old entry defaults to legacy")
	check(selector.choose(["res://v02/main.tscn"], []).mode == "v02", "new scene selects v02 before autoload cache")
	check(selector.choose(["res://v02/main.tscn"], ["--map-service=legacy"]).mode == "legacy", "explicit A/B override")
	check(not selector.choose([], ["--map-service=unknown"]).ok, "unsupported mode rejected")
	check(not selector.choose([], ["--map-service=v02", "--map-service=legacy"]).ok, "ambiguous duplicate rejected")
	var session = root.get_node("Session")
	check(session.visual_mode == "legacy", "legacy autoload compatibility")
	check(session.visual_service.cache == session.cache, "one shared visual cache")
	check(session.visual_service.lifecycle == ["selected:legacy", "cache_created"], "selection precedes cache")
	check(session.state._provider == session.army, "existing city adapter shares authority")
	var service = session.visual_service
	var start: int = service.plan_rebuilds
	service.begin_draw()
	var records := [{"id":"probe", "position_m":[0,0], "asset_version":1}]
	var plan: Dictionary = service.plan_instances(records)
	check(plan.ok and service.plan_rebuilds == start + 1, "actual plan rebuild instrumented")
	service.tree_submitted()
	check(service.last_draw.candidates_tested == 1 and service.last_draw.submitted_objects == 1, "candidates and real submits separate")
	var observations: Dictionary = service.snapshot()
	check(observations.resources.release_count == null, "unimplemented releases are null")
	check(observations.resources.request_count >= 9, "sync art and async terrain requests observed")
	check(observations.resources.resident_unique_textures > 0, "resident references counted")
	check(observations.resources.unique_estimated_bytes > 0, "unique estimate populated")
	check(not observations.streaming_implemented, "S0 delegation is explicit")
	check(service.estimate_rgba8_mips(4, 4) == 84, "mip chain estimate includes all levels")
	check(service.estimate_rgba8_mips(1, 4) == 28, "non-square mip estimate")
	service.begin_draw()
	check(service.last_draw.candidates_tested == 0 and service.last_draw.submitted_objects == 0, "new draw clears previous visibility")
	finish()
func finish() -> void:
	var report := "user://tests/map_v02/s0_contract.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(report.get_base_dir())
	FileAccess.open(report, FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	print("S0_CONTRACT ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
