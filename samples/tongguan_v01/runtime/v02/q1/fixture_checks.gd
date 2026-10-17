extends RefCounted
var checks:=0
var failures: Array=[]
var observations: Array=[]
var tree: SceneTree
var app: Control
var output: String
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("Q1_FIXTURE_FAILED ",label)
func frames(n: int=3) -> void:
	for i in n:await tree.process_frame
func settled(limit: int=1800) -> bool:
	for i in limit:
		await tree.process_frame
		var okay:=true
		for id in app.service.manager.demands:
			if int(app.service.manager.demands[id])<=2 and not app.service.manager.ready(id):okay=false;break
		if okay and not app.renderer._deferred:return true
	return false
func drain() -> void:
	app.service.suspend_display()
	for i in 1800:
		await tree.process_frame
		if app.service.manager.accounting().inflight==0:await frames(4);return
	check(false,"drain timeout")
func move(x: float,y: float,z: float=2.4) -> void:app.service.suspended=false;app.x=x;app.y=y;app.zoom=z;app.refresh()
func choose(id: String) -> void:
	app.choose(id);app.service.prefetch=false;app.renderer.fade_seconds=0
	if not app.service.loader.sites.is_empty():app.service.selected_site=app.service.loader.sites[0].site_id
	app.service.manager.set_budget(app.config.profiles.stream if id=="stream" else app.config.profiles.normal)
func capture(name: String) -> void:
	await frames();await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image();check(image.get_size()==Vector2i(1920,1080),"actual FHD "+name);image.save_png(output.get_base_dir()+"/"+name+".png")
func evidence(tag: String) -> Dictionary:
	return {"case":tag,"usec":Time.get_ticks_usec(),"telemetry":app.service.telemetry(),"renderer":app.renderer.stats.duplicate(true),"backend":app.service.manager.backend.stats.duplicate(),"events":app.service.manager.events.duplicate(true)}
func run(boot: Node,path: String) -> Dictionary:
	tree=boot.get_tree();output=path
	app=load("res://v02/c1/app.gd").new();boot.add_child(app);app.service.manager.record_full_history=true
	check(not OS.is_debug_build(),"actual release template")
	check(not ResourceLoader.has_cached("res://bundle/terrain_fallback.png"),"legacy six-page cache not initialized")
	choose("stream");move(256,256);check(await settled(),"stream start ready")
	var touched: Dictionary={};var windows: Array=[];var all_bytes:=0
	for row in app.service.manager.descriptors.values():all_bytes+=int(row.bytes)
	check(all_bytes>3*int(app.config.profiles.stream.soft),"unique full fixture exceeds stream soft budget x3")
	for round_id in 20:
		for row in [0,2,4,6]:
			for col in range(0,32,2):
				move(256+col*512,256+row*512);check(await settled(),"stream round %d row %d col %d"%[round_id,row,col])
				for id in app.service.coverage.requests:
					if app.service.loader.pages[id].level==2:
						for file in app.service.manager.page_files[id]:touched[file]=true
		move(256,256);check(await settled(),"same end view round "+str(round_id));await frames(4)
		var m=app.service.manager;var a: Dictionary=m.accounting()
		windows.append({"round":round_id+1,"usec":Time.get_ticks_usec(),"accounting":a,"engine_resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"engine_objects":Performance.get_monitor(Performance.OBJECT_COUNT),"engine_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)})
		check(a.external_alive_bytes==0,"actual retired references dead round "+str(round_id))
		print("Q1_STREAM_ROUND ",round_id+1," resident=",a.resident)
	var visited_bytes:=0
	for file in touched:visited_bytes+=int(app.service.manager.descriptors[file].bytes)
	check(visited_bytes>3*int(app.config.profiles.stream.soft),"actual visited unique bytes exceed soft budget x3")
	check(app.service.manager.stats.drops>0 and app.service.manager.stats.reloads>0,"real release and reload events occurred")
	check(windows.slice(15).all(func(w):return w.accounting.resident==windows[0].accounting.resident and w.engine_resources<=windows[0].engine_resources),"same-view settled bytes/resources do not grow")
	var stream: Dictionary=evidence("20_round_stream");stream.unique_total_bytes=all_bytes;stream.unique_visited_bytes=visited_bytes;stream.unique_visited_textures=touched.size();stream.windows=windows
	stream.frames=app.service.manager.frames.duplicate(true);observations.append(stream)
	check(stream.frames.all(func(f):return f.total<=f.hard and f.decoded_reserved<=app.config.profiles.stream.decoded and f.inflight<=2),"every stream frame respects hard/decode/concurrency admission")
	await capture("stream_return");await drain();check(app.service.manager.accounting().external_alive_bytes==0,"stream final references released")
	# Actual absent file and same-build parent coverage.
	choose("lab");move(256,-256)
	for i in 900:
		await tree.process_frame
		if app.service.manager.page_states.get("fine_2_1")=="FAILED" and app.service.manager.ready("parent_1_0"):break
	var fallback: Dictionary=app.service.coverage.resolve("fine_2_1",app.service.manager)
	check(app.service.manager.page_states.get("fine_2_1")=="FAILED" and fallback.ok and fallback.selected=="parent_1_0","missing physical file reports failure and uses parent")
	observations.append(evidence("physical_missing"));await capture("missing_parent_fallback");await drain()
	var file: String=app.service.loader.pages.fine_0_0.texture_files[0]
	app.service.manager.backend.faults[file]="hash";move(-768,-768)
	for i in 900:
		await tree.process_frame
		if app.service.manager.page_states.get("fine_0_0")=="FAILED" and app.service.manager.ready("parent_0_0"):break
	check(app.service.manager.page_states.get("fine_0_0")=="FAILED","wrong hash reports failed, not success")
	check(app.service.coverage.resolve("fine_0_0",app.service.manager).selected=="parent_0_0","wrong hash parent fallback")
	app.service.manager.backend.faults.clear();app.service.manager.retry_failed();check(await settled(),"hash removed then explicit retry succeeds");observations.append(evidence("hash_retry"));await drain()
	# Delayed real requests, rapid A-B-A and package/world epochs.
	app.service.manager.backend.faults[file]="delay";move(-768,-768);await frames(5)
	var epoch: int=app.service.manager.epoch;var held: String=app.service.manager.key_for(file)
	check(app.service.manager.backend.holds.has(held),"real request delayed at completion notification")
	move(768,768);await frames(3);move(-768,-768);await frames(3)
	check(app.service.manager.epoch==epoch,"rapid camera travel does not invalidate world epoch")
	app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear();check(await settled(),"A-B-A current consumers adopt compatible completed task")
	observations.append(evidence("delay_ABA"));await drain()
	app.service.manager.backend.faults[file]="delay";move(-768,-768);await frames(5)
	var stale: int=app.service.manager.stats.stale_drained
	choose("tongguan");app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear();move(0,-270,.84);check(await settled(),"switch to real package while old task drains")
	check(app.service.manager.epoch==epoch+1 and app.service.manager.stats.stale_drained>stale and not app.service.manager.entries.has(held),"old world completion cannot attach")
	observations.append(evidence("world_package_switch"));await drain()
	# Positive control: merely removing manager entries must be detected as a leak.
	move(0,-270,.84);check(await settled(),"reference control loaded");await frames(6);app.set_process(false)
	var callback: Callable=app.service.manager.on_evict;app.service.manager.on_evict=Callable();app.service.manager.clear_demands();await frames(2)
	var retained: int=app.service.manager.accounting().external_alive_bytes;check(retained>0,"negative control detects retained command textures")
	app.renderer.clear();await frames(4);check(app.service.manager.accounting().external_alive_bytes==0,"clearing commands and texture refs releases them")
	app.service.manager.on_evict=callback;callback=Callable();app.set_process(true);observations.append({"case":"reference_negative_control","retained_bytes":retained,"after_clear_bytes":app.service.manager.accounting().external_alive_bytes});await drain()
	# Shared existing atlas: one unique byte charge until the last consumer leaves.
	var ids: Array=[]
	for id in app.service.loader.objects:
		if app.service.loader.objects[id].get("asset_id","").begins_with("tree_"):ids.append("object:"+id)
	app.service.manager.set_demands({ids[0]:2,ids[1]:2});check(await settled(),"shared atlas consumers ready")
	var atlas: String=app.service.manager.key_for(app.service.manager.page_files[ids[0]][0]);check(app.service.manager.entries[atlas].consumers.size()==2,"two consumers share one atlas")
	app.service.manager.set_demands({ids[1]:2});await frames(3);check(app.service.manager.entries[atlas].consumers.size()==1,"first consumer removal preserves atlas")
	app.service.manager.set_budget({"grace_usec":0});app.service.manager.set_demands({});await frames(5);check(not app.service.manager.entries.has(atlas),"last consumer releases atlas");observations.append(evidence("shared_atlas"));await drain()
	choose("stream");move(256,256);check(await settled(),"budget shrink source ready")
	app.renderer.fade_seconds=10;app.renderer.finished_fades={};app.renderer._plan_key=[];await frames(4)
	app.service.manager.set_budget({"id":"q1_shrink_root","soft":278784,"hard":278784,"decoded":557568,"grace_usec":0});await frames(6)
	check(app.service.manager.accounting().total<=278784 and app.service.manager.ready("root_0_0"),"budget reduction mid-transition keeps affordable root")
	observations.append(evidence("mid_fade_shrink"));await capture("budget_root_fallback");await drain()
	choose("stream");var root: String=app.service.loader.pages.root_0_0.texture_files[0];var parent: String=app.service.loader.pages.parent_0_0.texture_files[0]
	app.service.manager.backend.faults[root]="delay";app.service.manager.backend.faults[parent]="delay";move(256,256);await frames(5)
	check(app.service.coverage.resolve("fine_0_0",app.service.manager).code=="coverage_pending","not-ready parents remain explicitly pending")
	app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear();check(await settled(),"parent delay recovery");observations.append(evidence("parent_not_ready"));await drain()
	# E-sites / E-labels use exactly the C1 service/manager, with bounded detail payload.
	for kind in ["sites","labels"]:
		choose(kind);move(1306 if kind=="sites" else 4096,1306 if kind=="sites" else 2048,.65 if kind=="sites" else .18);check(await settled(),"engineering "+kind+" ready");await frames(5)
		check(app.service.loader.sites.size()==(32 if kind=="sites" else 2000),"engineering count "+kind)
		check(app.renderer.label_plan.size()<=64,"label screen limit "+kind)
		if kind=="labels":check(not app.renderer.label_plan.is_empty() and app.renderer.label_plan[0].site_id==app.service.selected_site,"selected site wins dense 2000-label priority")
		var details:=0
		for id in app.renderer.nodes:
			if id.begins_with("object:lab.detail."):details+=1
		check(details==(4 if kind=="sites" else 0),"four detailed engineering sites; label fixture proxies only "+kind)
		observations.append(evidence(kind));await capture(kind+"_screen");await drain()
	# Timed slow oscillation around all semantic thresholds and the texture threshold.
	choose("tongguan");var slow: Array=[]
	for threshold in [32.0/1200,128.0/1200,384.0/1200,180.0/512]:
		move(0,0,threshold*.8);check(await settled(),"slow threshold warmup")
		await tree.create_timer(2.1).timeout
		var before_requests: int=app.service.manager.stats.requests;var before_switches: int=app.service.integration_stats.semantic_switches;var texture_level: int=app.service.coverage.selected_level;var begin:=Time.get_ticks_usec()
		for cycle in 20:
			for forward in [true,false]:
				for step in 6:
					var factor: float=lerpf(.98,1.02,float(step if forward else 5-step)/5);move(0,0,threshold*factor)
					slow.append({"threshold_zoom":threshold,"cycle":cycle,"usec":Time.get_ticks_usec(),"zoom":app.zoom,"semantic":app.service.semantic_lod,"texture":app.service.coverage.selected_level,"requests":app.service.manager.stats.requests})
					await tree.create_timer(.02).timeout
		check(Time.get_ticks_usec()-begin>=4800000,"slow 20-round trace elapsed")
		check(app.service.manager.stats.requests==before_requests and app.service.integration_stats.semantic_switches==before_switches and app.service.coverage.selected_level==texture_level,"slow threshold oscillation has no request or LOD chatter")
		await capture("slow_threshold_"+str(roundi(threshold*100000)))
	observations.append({"case":"slow_threshold_20_rounds","samples":slow});await drain()
	# Full E1 positive/negative package matrix and actual imported pixel hashes.
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://v02/q1/config.json"))
	var e1: Dictionary=load("res://v02/e1/checks.gd").new().run(config,false);checks+=e1.checks;failures.append_array(e1.failures);observations.append({"case":"E1_package_matrix","result":e1})
	check(app.service.manager.backend.stats.premature_gets==0,"all actual gets follow LOADED")
	var backend: Dictionary=app.service.manager.backend.stats.duplicate();var remaining: Dictionary=app.service.manager.accounting();app.service.dispose();boot.remove_child(app);app.queue_free();app=null;await frames(3)
	return {"checks":checks,"failures":failures,"observations":observations,"backend":backend,"remaining":remaining,"actual_viewport":[1920,1080],"same_map_service":"res://v02/c1/map_service.gd","engine":Engine.get_version_info()}
