extends RefCounted
var checks:=0
var failures: Array=[]
var observations: Array=[]
var tree: SceneTree
var app: Control
var output: String
var gpu_comparisons: Array=[]
var verified_pixels: Dictionary={}
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("C1_CHECK_FAILED ",label)
func frames(n: int=3) -> void:
	for i in n:await tree.process_frame
func settle() -> bool:
	for i in 1200:
		await tree.process_frame
		var ready:=true
		for id in app.service.manager.demands:
			if int(app.service.manager.demands[id])<=2 and not app.service.manager.ready(id):ready=false;break
		if ready and not app.renderer._deferred and app.renderer.fades.is_empty():
			await tree.create_timer(.25).timeout;await frames(4)
			if not app.renderer._deferred and app.renderer.fades.is_empty() and (not app.service.detail_ready or app.renderer.detail_alpha>=1):return true
	return false
func drain() -> void:
	for i in 1200:
		await tree.process_frame
		if app.service.manager.accounting().inflight==0:await frames(4);return
	check(false,"all physical loading tasks drained")
func alive() -> int:
	var n:=0
	for row in app.service.manager.ledger:
		if row.weak.get_ref()!=null:n+=1
	return n
func capture(name: String) -> String:
	await frames();await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual FHD "+name)
	check(image.save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
	var commands: Dictionary={}
	for id in app.renderer.nodes:commands[id]=app.renderer.nodes[id].signature
	var detail={"camera":[app.x,app.y,app.zoom],"fades":app.renderer.fades,"finished":app.renderer.finished_fades,"commands":commands,"deferred":app.renderer._deferred,"detail_alpha":app.renderer.detail_alpha}
	var file=FileAccess.open(output.get_base_dir()+"/"+name+"_commands.json",FileAccess.WRITE);file.store_string(JSON.stringify(detail,"\t"));file.close()
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_region(Rect2i(20,96,1600,940)).get_data());return hash.finish().hex_encode()
func observe(tag: String) -> void:
	observations.append({"case":tag,"lod":app.service.semantic_lod,"state":app.army().snapshot(),"economy":app.army().economy(),"city":app.service.city.duplicate(true),"telemetry":app.service.telemetry(),"integration":app.service.integration_stats.duplicate(true),"renderer":app.renderer.stats.duplicate(true),"retired_alive":alive(),"labels":app.renderer.label_plan.size()})
func verify_pixels() -> void:
	for key in app.service.manager.entries:
		var entry: Dictionary=app.service.manager.entries[key]
		if entry.state!="RESIDENT" or verified_pixels.has(key):continue
		var image: Image=entry.texture.get_image();var valid: bool=image!=null
		if valid:
			if image.is_compressed():valid=image.decompress()==OK
			valid=valid and not image.has_mipmaps();image.convert(Image.FORMAT_RGBA8)
			var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data());valid=valid and hash.finish().hex_encode()==entry.row.pixel_sha256
		check(valid,"actual imported texture pixels "+entry.row.path);verified_pixels[key]=valid
func gpu_compare(tag: String,negative: bool=false) -> void:
	var a: String=tag+"_paged";var b: String=tag+"_reference"
	await capture(a)
	var sprite=Sprite2D.new();sprite.texture=load("res://v02/c1/reference_fine.png");sprite.centered=false;sprite.position=Vector2(-1024-app.renderer.origin[0],-1024-app.renderer.origin[1]);sprite.scale=Vector2.ONE*.5;sprite.region_enabled=true;sprite.region_rect=Rect2(32,32,4096,3072);sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	app.renderer.root.add_child(sprite)
	if negative:sprite.position.x+=40
	await capture(b)
	RenderingServer.canvas_item_clear(sprite.get_canvas_item());sprite.texture=null;app.renderer.root.remove_child(sprite);sprite.queue_free();await frames()
	gpu_comparisons.append({"case":tag,"a":a+".png","b":b+".png","roi":[20,96,1600,940],"expect_equal":not negative,"frozen_max_channel_delta":1})
func run(boot: Node,path: String) -> Dictionary:
	tree=boot.get_tree();output=path
	var policy: Dictionary=load("res://v02/c1/policy_checks.gd").new().run();checks+=policy.checks;failures.append_array(policy.failures)
	var e2: Dictionary=load("res://v02/e2/contract_checks.gd").new().run();checks+=e2.checks;failures.append_array(e2.failures)
	var e3: Dictionary=load("res://v02/e3/contract_checks.gd").new().run();checks+=e3.checks;failures.append_array(e3.failures)
	app=load("res://v02/c1/app.gd").new();boot.add_child(app)
	app.service.prefetch=false;app.service.manager.record_full_history=true
	app.refresh();check(await settle(),"initial composition ready")
	verify_pixels()
	var controller_id: int=app.army().get_instance_id();var context_id: int=app.army().context.get_instance_id()
	check(get_node_session(boot).get_script().resource_path=="res://v02/v2/session.gd","new visual mode selected before legacy cache creation")
	check(app.service.loader.textures.is_empty(),"E1 eager texture cache empty")
	check(app.service.validate_authoring(app.army().authoring_projection()).ok,"saved effective authoring agrees with package")
	var changed_authoring: Dictionary=app.army().authoring_projection();changed_authoring.revision+=1
	check(not app.service.validate_authoring(changed_authoring).ok,"different saved authoring explicitly rejected")
	check(app.errors.is_empty(),"C1 app initialized")
	var gate_before: bool=app.army().projection().gate_open;app.toggle_gate();check(app.army().projection().gate_open!=gate_before,"existing gate service works in C1");app.toggle_gate()
	for stage in [2,3,1]:app.cycle_growth();check(app.army().projection().growth_stage==stage,"existing growth service stage %d"%stage)
	check(await settle(),"existing controls settled")
	await capture("composition");app.camera("courtyard");check(await settle(),"courtyard ready")
	var completed_before: Dictionary=app.renderer.finished_fades.duplicate();app.renderer.detach_resource("absent_unrelated_resource")
	check(app.renderer.finished_fades==completed_before,"unrelated eviction preserves visible terrain transitions")
	var initial: String=await capture("courtyard_intact");var snapshot: Dictionary=app.army().snapshot()
	var reads: int=app.service.integration_stats.authority_reads;var sorts: int=app.service.planner.stats.sort_calls;var snapshots: int=app.service.planner.stats.snapshot_reads
	await frames(30)
	check(reads==app.service.integration_stats.authority_reads and sorts==app.service.planner.stats.sort_calls and snapshots==app.service.planner.stats.snapshot_reads,"ordinary frames reuse authority snapshot and sorted plans")
	app.damage(2);check(await settle(),"damage assets adopted")
	check(app.service.planner.index.record("tongguan.slot.rear_storage_01").asset_id=="warehouse_damaged","live warehouse damage delta")
	check(app.service.planner.index.record("wall_east").asset_id=="wall_damaged","live wall damage delta")
	var damaged: String=await capture("courtyard_damaged");check(initial!=damaged,"visible damage pixels differ")
	app.damage(0);check(await settle(),"repair assets adopted");var repaired: String=await capture("courtyard_repaired");check(initial==repaired,"repair restores same camera pixels exactly")
	check(app.army().economy()==app.receipts[app.receipts.size()-3].economy,"visual repair changes no economic rules")
	var frozen: Dictionary=app.army().snapshot()
	for camera in ["far","region","composition","courtyard"]:
		app.camera(camera);check(await settle(),"full-range return "+camera);await capture("lod_"+camera)
		check(app.service.selected_site=="tongguan","selected site stable "+camera)
		check(app.army().snapshot()==frozen,"camera has no authority mutation "+camera)
	check(app.army().get_instance_id()==controller_id and app.army().context.get_instance_id()==context_id,"single original controller/context across LOD")
	app.x=-300;app.y=-100;app.zoom=.18;app.refresh();check(await settle(),"simplified layout ready");check(app.service.semantic_lod==2,"independent simplified tier selected");await capture("lod_simplified")
	# Real streaming threshold oscillations: no semantic chatter or resource requests after warmup.
	var thresholds: Array=[32.0,128.0,384.0]
	for tier in 3:
		app.x=0;app.y=0;app.zoom=thresholds[tier]*.8/1200;app.refresh();check(await settle(),"threshold warmup %d"%tier)
		await tree.create_timer(2.1).timeout
		var requests: int=app.service.manager.stats.requests;var switches: int=app.service.integration_stats.semantic_switches
		for i in 20:
			for factor in [.99,1.01]:app.zoom=thresholds[tier]*factor/1200;app.refresh();await frames(2)
		check(app.service.integration_stats.semantic_switches==switches,"20 native hysteresis oscillations tier %d"%tier)
		check(app.service.manager.stats.requests==requests,"no request storm tier %d"%tier)
		observe("threshold_"+str(tier))
	app.x=0;app.y=0;app.zoom=180*.8/512;app.refresh();check(await settle(),"texture threshold warmup")
	var texture_level: int=app.service.coverage.selected_level;var texture_requests: int=app.service.manager.stats.requests
	for i in 20:
		for factor in [.99,1.01]:app.zoom=180*factor/512;app.refresh();await frames(2);check(app.service.coverage.selected_level==texture_level,"texture LOD hysteresis sample")
	check(app.service.manager.stats.requests==texture_requests,"texture LOD no request storm")
	observe("texture_threshold")
	# Offscreen construction and damage remain the existing authoritative service's work.
	app.camera("courtyard");app.reset_before();var funds: Dictionary=app.army().economy();app.build_storage();check(await settle(),"construction marker loaded")
	check(app.army().economy().cash==funds.cash-120 and app.army().economy().timber==funds.timber-20,"construction pays existing 120 cash and 20 timber")
	await capture("construction_before_unload")
	var before_day: int=app.army().context.state.current_day;var before_unload: Dictionary=app.army().snapshot();app.unload_display();await drain()
	check(app.army().snapshot()==before_unload,"display unload neither advances nor pauses clock")
	check(app.renderer.nodes.is_empty(),"all retained commands removed on unload")
	check(alive()==0 and app.service.manager.accounting().resident==0,"all actual streamed texture references released")
	observe("unloaded")
	for i in 3:app.advance_day()
	app.damage(2);check(app.army().context.state.current_day==before_day+3,"original clock advances offscreen exactly 3 days")
	check(app.army().projection().slot_occupancy["tongguan.slot.rear_storage_01"].status=="built","original construction completes offscreen")
	check(app.service.manager.demands.is_empty(),"state changes while suspended do not load visuals")
	var after_offscreen: Dictionary=app.army().snapshot();app.reload_display();check(await settle(),"offscreen latest state reload ready")
	check(app.army().snapshot()==after_offscreen,"reload does not mutate gameplay")
	check(app.service.planner.index.record("tongguan.slot.rear_storage_01").asset_id=="warehouse_damaged","reload reads latest damage, not stale intact state")
	check(app.service.planner.index.record("tongguan.slot.rear_storage_01").position_m==[-567.5,-227.5],"warehouse anchor unchanged after reload")
	await capture("offscreen_built_damaged_reload");app.damage(0);check(await settle(),"offscreen repair ready");await capture("offscreen_repaired")
	# Repeat releases at a fixed view: no survivor references, deterministic pixels.
	var same: String=await capture("reload_baseline")
	for i in 5:
		app.unload_display();await drain();check(alive()==0,"release weak refs cycle %d"%i);app.reload_display();check(await settle(),"reload cycle %d"%i);check(same==await capture("reload_%d"%i),"reload same pixels cycle %d"%i);observe("reload_"+str(i))
	# Sparse mixed coverage, with one detail deliberately absent at runtime.
	app.camera("composition");check(await settle(),"mixed coverage warmup")
	var id:="fine_0_0";var full: String=await capture("coverage_full")
	var saved_demands: Dictionary=app.service.manager.demands.duplicate();var subset: Dictionary=saved_demands.duplicate();subset.erase(id);app.service.manager.set_demands(subset)
	for file in app.service.manager.page_files[id]:app.service.manager.drop(app.service.manager.key_for(file),"C1 mixed coverage test")
	app.renderer._plan_key=[];app.renderer.finished_fades={};await frames()
	var fallback: Dictionary=app.service.coverage.resolve(id,app.service.manager);check(fallback.ok and fallback.selected=="context","missing child keeps same-build parent coverage")
	await capture("coverage_mixed_parent_child");app.service.manager.set_demands(saved_demands);check(await settle(),"mixed child restored");check(full==await capture("coverage_restored"),"mixed coverage returns exact full view")
	# Faction color only: zero terrain requests or command rebuilds after color swap.
	app.camera("far");check(await settle(),"far factions ready");app.renderer.factions=true;await capture("far_factions_a")
	var requests: int=app.service.manager.stats.requests;var builds: int=app.renderer.stats.command_builds
	app.swap_factions();await capture("far_factions_b")
	check(app.service.manager.stats.requests==requests and app.renderer.stats.command_builds==builds,"faction changes never rebuild terrain or reload textures")
	app.renderer.factions=false
	# Same class/manager/reader handles a world of 256 engineering sites and pages.
	app.choose("multi");check(await settle(),"same-loader multi-region fixture")
	check(app.service.loader.sites.size()==256,"256 engineering sites, no second real city")
	check(app.renderer.label_plan.size()<=64,"actual screen label cap")
	for a in app.renderer.label_plan.size():
		for b in range(a+1,app.renderer.label_plan.size()):check(not app.renderer.label_plan[a].rect.intersects(app.renderer.label_plan[b].rect),"native label rectangles avoid overlap")
	await capture("engineering_labels")
	for i in 4:app.next_region();check(await settle(),"multi-region pan %d"%i)
	check(app.army().get_instance_id()==controller_id and app.army().context.get_instance_id()==context_id,"engineering fixtures do not duplicate authority")
	app.choose("tongguan");app.camera("courtyard");check(await settle(),"return from fixture to real latest authority")
	check(app.service.loader.textures.is_empty(),"eager cache still empty")
	# Pressure profile forces graceful proxy fallback without changing gameplay.
	var authority_before: Dictionary=app.army().snapshot();app.service.manager.set_budget(app.config.profiles.pressure);app.camera("composition");await tree.create_timer(1.0).timeout
	check(app.service.manager.accounting().total<=app.config.profiles.pressure.hard,"pressure hard admission limit")
	check(app.army().snapshot()==authority_before,"budget degradation changes no gameplay")
	await capture("pressure_proxy");observe("pressure")
	app.service.manager.set_budget(app.config.profiles.normal);app.refresh();check(await settle(),"normal profile returns detail")
	# Compare the streamed fine pages to a test-only complete field at four scales,
	# including junctions; the 40m wrong-position control must be detected.
	app.renderer.terrain_only=true
	for z in [.42,.84,1.4,2.4]:
		app.x=0;app.y=-270;app.zoom=z;app.refresh();check(await settle(),"GPU zoom ready");verify_pixels();await gpu_compare("gpu_zoom_"+str(z).replace(".","_"))
	for point in [[-512,0],[0,-512],[512,0]]:
		app.x=point[0];app.y=point[1];app.zoom=1.4;app.refresh();check(await settle(),"GPU junction ready");await gpu_compare("gpu_joint_%d_%d"%[point[0],point[1]])
	await gpu_compare("gpu_negative_40m",true);app.renderer.terrain_only=false
	app.camera("composition");check(await settle(),"review baseline restored");await capture("final_composition")
	check(app.errors.is_empty() and app.renderer.errors.is_empty() and app.service.manager.failures.is_empty(),"no integration/renderer/resource failures")
	var events: Array=app.service.manager.events.duplicate(true);observe("final")
	app.service.dispose();await drain();check(alive()==0,"shutdown actual texture references released")
	return {"checks":checks,"failures":failures,"observations":observations,"events":events,"receipts":app.receipts,"profile":app.config,"single_controller_id":controller_id,"single_context_id":context_id,"gpu_comparisons":gpu_comparisons,"verified_texture_count":verified_pixels.size(),"visual":"pending","q1":"not_claimed"}
func get_node_session(boot: Node) -> Node:return boot.get_node("/root/Session")
