extends RefCounted
var tree: SceneTree
var checks := 0
var failures: Array = []
func argument(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.substr(prefix.length())
	return fallback
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func percentile(values: Array, ratio: float) -> Variant:
	if values.is_empty(): return null
	var sorted := values.duplicate(); sorted.sort()
	return sorted[mini(sorted.size() - 1, maxi(0, ceili(sorted.size() * ratio) - 1))]
func frames(count: int = 3) -> void:
	for i in count: await tree.process_frame
func target_dimensions_match(observed: Dictionary, target: Array) -> bool:
	# JSON numbers decode as float; Array equality distinguishes float/int.
	var expected := [int(target[0]), int(target[1])]
	return observed.viewport_texture_px == expected
func dimensions() -> Dictionary:
	var window := tree.root
	var texture_size := window.get_texture().get_size()
	var client := DisplayServer.window_get_size()
	return {"viewport_texture_px":[int(texture_size.x),int(texture_size.y)],
		"window_client_px":[client.x,client.y], "window_size_px":[window.size.x,window.size.y],
		"content_scale_size":[window.content_scale_size.x,window.content_scale_size.y],
		"content_scale_mode":window.content_scale_mode, "content_scale_factor":window.content_scale_factor,
		"screen_dpi":DisplayServer.screen_get_dpi(), "display_server":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method(),
		"video_adapter":RenderingServer.get_video_adapter_name(), "video_vendor":RenderingServer.get_video_adapter_vendor(),
		"video_api_version":RenderingServer.get_video_adapter_api_version(), "engine":Engine.get_version_info()}
func camera_at(app: Control, profile: Dictionary, seconds: float) -> String:
	var phase: float = fposmod(seconds, float(profile.trace_period_seconds)) / float(profile.trace_period_seconds) * profile.trace.size()
	var index := mini(profile.trace.size() - 1, int(phase))
	var row: Dictionary = profile.trace[index]
	var blend: float = phase - index
	app.model.camera_x = float(app.model.view.world_origin[0]) + float(row.local_m[0]) + sin(blend * TAU) * 90.0
	app.model.camera_y = float(app.model.view.world_origin[1]) + float(row.local_m[1]) + cos(blend * TAU) * 55.0
	app.model.set_zoom(float(row.zoom) * (1.0 + 0.08 * sin(blend * TAU)))
	app.canvas.queue_redraw()
	return str(row.name)
func run(boot: Node) -> void:
	tree = boot.get_tree()
	var output := argument("--report=", "user://tests/map_v02/probe/result.json")
	var evidence_root := ProjectSettings.globalize_path(argument("--evidence-root=", "user://tests/map_v02/" )).simplify_path().replace("\\", "/").trim_suffix("/")
	var resolved := ProjectSettings.globalize_path(output).simplify_path().replace("\\", "/")
	if not resolved.begins_with(evidence_root + "/"):
		printerr("S0 report is outside the explicit evidence root."); tree.quit(1); return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if FileAccess.file_exists(output): printerr("S0 refuses existing report."); tree.quit(1); return
	var seconds := float(argument("--seconds=", "60"))
	if not is_finite(seconds) or seconds <= 0 or seconds > 300:
		printerr("S0 duration must be in (0,300]."); tree.quit(1); return
	tree.create_timer(seconds + 90).timeout.connect(func(): printerr("S0_PROBE_TIMEOUT"); tree.quit(1))
	var session = tree.root.get_node("Session")
	var service = session.visual_service
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://v02/profiles.json"))
	# Benchmark-only render target. Fullscreen/OS DPI may resize the native
	# client; VIEWPORT mode keeps raster work at the declared base resolution.
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	tree.root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	tree.root.content_scale_factor = 1.0
	tree.root.content_scale_size = Vector2i(int(profile.target_viewport_px[0]), int(profile.target_viewport_px[1]))
	await frames(6)
	if seconds < float(profile.trace_period_seconds):
		profile.trace_period_seconds = seconds
		profile.diagnostic_compressed_trace = true
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://v02/build.json")) if FileAccess.file_exists("res://v02/build.json") else {"build_id":"source_working_tree", "release":false}
	check(not OS.get_cmdline_user_args().has("--expect-release") or not OS.is_debug_build(), "actual Release template")
	check(service.cache == session.cache and service.lifecycle.size() == 2, "one cache selected before creation")
	check(not service.snapshot().streaming_implemented, "S0 reports legacy delegation")
	var startup := Time.get_ticks_usec()
	var app = load("res://final/ui.gd").new()
	boot.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.save_path = "user://tests/map_v02/probe_%d/session.json" % OS.get_process_id()
	app.publication_path.text = "user://tests/map_v02/probe_%d/publication.json" % OS.get_process_id()
	check(session.state._provider == app.army(), "existing authority shared with state adapter")
	var before: String = app.army().digest({"snapshot":app.army().snapshot(), "authoring":app.model.host.authoring, "corridors":app.army().context.state.transit_corridors})
	await frames(5)
	var first_interactive_ms := (Time.get_ticks_usec() - startup) / 1000.0
	check(app.model.pick_site(app.model.site_screen(app.canvas.size), app.canvas.size) == "tongguan", "proxy picking ready")
	var deadline := Time.get_ticks_msec() + 10000
	while (not session.cache.ready or session.cache.detail_blend < 1.0) and Time.get_ticks_msec() < deadline: await frames(1)
	check(session.cache.ready and session.cache.tile_textures.size() == 6, "legacy six-page cache ready")
	check(service.snapshot().resources.request_failures.is_empty(), "all recorded resource requests succeeded")
	var size_start := dimensions()
	check(target_dimensions_match(size_start, profile.target_viewport_px), "actual 1920x1080 render target")
	check(DisplayServer.get_name() != "headless", "native rendering measured")
	# Capture once before warmup; no pixel readback occurs in the timed loop.
	app.model.recall_bookmark("gate_close"); app.refresh(); await frames(4)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(output.get_base_dir() + "/composition.png")
	var warm_started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_started < float(profile.warmup_seconds) * 1000000:
		camera_at(app, profile, (Time.get_ticks_usec() - warm_started) / 1000000.0); await frames(1)
	var observations_start: Dictionary = service.snapshot()
	var samples := FileAccess.open(output.get_base_dir() + "/frames.csv", FileAccess.WRITE)
	if samples == null: printerr("Cannot open S0 frame evidence."); tree.quit(1); return
	samples.store_csv_line(PackedStringArray(["elapsed_s","frame_interval_ms","camera","lod","tree_candidates","tree_submitted","tree_plan_usec","plan_rebuilds_total"]))
	var values: Array = []
	var long_frames: Array = []
	var periodic: Array = []
	var counts := {"over_33ms":0, "over_50ms":0, "over_100ms":0}
	var started := Time.get_ticks_usec()
	var last := started
	var next_observation := 1000000
	var phase := camera_at(app, profile, 0)
	while Time.get_ticks_usec() - started < seconds * 1000000:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var elapsed := (now - started) / 1000000.0
		var interval := (now - last) / 1000.0
		last = now; values.append(interval)
		for threshold in [33,50,100]:
			if interval > threshold: counts["over_%dms" % threshold] += 1
		if interval > 33: long_frames.append({"elapsed_s":elapsed, "interval_ms":interval, "camera":phase, "lod":app.model.lod, "async_attach_count":session.cache.attach_ms.size()})
		samples.store_csv_line(PackedStringArray(["%.6f" % elapsed, "%.6f" % interval, phase, str(app.model.lod), str(service.last_draw.candidates_tested), str(service.last_draw.submitted_objects), str(service.last_draw.plan_usec), str(service.plan_rebuilds)]))
		if now - started >= next_observation:
			periodic.append({"elapsed_s":elapsed, "dimensions":dimensions(), "observations":service.snapshot()}); next_observation += 1000000
		phase = camera_at(app, profile, elapsed)
	samples.close()
	var duration := (Time.get_ticks_usec() - started) / 1000000.0
	var observations_end: Dictionary = service.snapshot()
	var size_end := dimensions()
	check(size_start == size_end, "actual rendering configuration remained stable")
	check(duration >= seconds and not values.is_empty(), "full requested duration sampled")
	check(observations_end.tree_plan_rebuilds > observations_start.tree_plan_rebuilds, "legacy full-plan rebuilding is visible")
	check(observations_end.tree_submitted_objects > observations_start.tree_submitted_objects, "actual nonempty tree submissions recorded")
	check(before == app.army().digest({"snapshot":app.army().snapshot(), "authoring":app.model.host.authoring, "corridors":app.army().context.state.transit_corridors}), "camera trace preserves gameplay and authoring")
	var result := {"build":build, "profile":profile, "mode":session.visual_mode, "release":not OS.is_debug_build(), "checks":checks, "failures":failures,
		"dimensions":size_start, "dimensions_end":size_end, "requested_seconds":seconds, "duration_seconds":duration, "sample_count":values.size(),
		"frame_p95_ms":percentile(values,0.95), "frame_p99_ms":percentile(values,0.99), "frame_max_ms":percentile(values,1.0),
		"long_frame_counts":counts, "long_frames":long_frames, "periodic_observations":periodic,
		"observations_start":observations_start, "observations_end":observations_end,
		"entry_to_interactive_upper_bound_ms":first_interactive_ms, "gpu_first_frame_timestamp":null,
		"engine_start_to_cache_ready_ms":session.cache.ready_usec / 1000.0,
		"attach_max_ms":percentile(session.cache.attach_ms,1.0), "player_default_save_accessed":false,
		"timing_source":"monotonic process-frame intervals; CPU observation includes rendering and scheduling; no GPU timestamp or cleared OS disk cache claim",
		"streaming_acceptance":"not_implemented_S0", "visual_acceptance":"pending_user_review"}
	boot.remove_child(app); app.queue_free(); await frames(4)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: printerr("Cannot write S0 result."); tree.quit(1); return
	file.store_string(JSON.stringify(result,"\t")); file.close()
	print("S0_NATIVE ", JSON.stringify({"mode":session.visual_mode, "checks":checks, "failures":failures, "p95":result.frame_p95_ms, "p99":result.frame_p99_ms}))
	tree.quit(0 if failures.is_empty() else 1)
