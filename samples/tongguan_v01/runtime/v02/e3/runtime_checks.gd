extends RefCounted
var checks:=0
var failures: Array=[]
var observations: Array=[]
var tree: SceneTree
var app: Control
var verified_pixels: Dictionary={}
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func frames(n: int=3) -> void:
	for i in n:await tree.process_frame
func settled() -> bool:
	for id in app.service.manager.demands:
		if int(app.service.manager.demands[id])<=2 and not app.service.manager.ready(id):return false
	return true
func wait_settled(limit: int=240) -> bool:
	for i in limit:
		await tree.process_frame
		if settled():return true
	return false
func wait_drain(limit: int=240) -> bool:
	for i in limit:
		await tree.process_frame
		if app.service.manager.accounting().inflight==0:return true
	return false
func alive() -> int:
	var count:=0
	for row in app.service.manager.ledger:
		if row.weak.get_ref()!=null:count+=1
	return count
func capture(output: String,name: String) -> String:
	await frames();await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual 1920x1080 "+name)
	check(image.save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
	var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(image.get_region(Rect2i(20,96,1600,940)).get_data());return h.finish().hex_encode()
func move_to(x: float,y: float,zoom: float=2.4) -> void:app.x=x;app.y=y;app.zoom=zoom;app.refresh()
func evidence(tag: String) -> Dictionary:
	var m=app.service.manager
	return {"case":tag,"telemetry":app.service.telemetry(),"events":m.events.duplicate(true),"frames":m.frames.duplicate(true),"retired_weak_alive":alive(),"renderer":app.renderer.stats.duplicate(true)}
func reset_events() -> void:app.service.manager.events=[];app.service.manager.frames=[]
func clear() -> void:
	app.service.release_all();await wait_drain();await frames()
func verify_pixels() -> void:
	for key in app.service.manager.entries:
		var entry: Dictionary=app.service.manager.entries[key]
		if entry.state!="RESIDENT" or verified_pixels.has(key):continue
		var image=entry.texture.get_image()
		var valid: bool=image!=null
		if valid:
			if image.is_compressed():valid=image.decompress()==OK
			valid=valid and not image.has_mipmaps();image.convert(Image.FORMAT_RGBA8)
			var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
			valid=valid and hash.finish().hex_encode()==entry.row.pixel_sha256
		check(valid,"native imported pixel identity outside scheduler: "+entry.row.path)
		verified_pixels[key]=valid
func run(boot: Node,output: String) -> Dictionary:
	tree=boot.get_tree()
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e3/config.json"))
	var core: Dictionary=load("res://v02/e3/contract_checks.gd").new().run()
	checks+=core.checks;failures.append_array(core.failures)
	var e2: Dictionary=load("res://v02/e2/contract_checks.gd").new().run();checks+=e2.checks;failures.append_array(e2.failures)
	var e1: Dictionary=load("res://v02/e1/checks.gd").new().run(config,true);checks+=e1.checks;failures.append_array(e1.failures)
	app=load("res://v02/e3/app.gd").new();boot.add_child(app)
	app.service.manager.record_full_history=true
	app.renderer.fade_seconds=0;app.service.prefetch=false;move_to(256,256)
	check(await wait_settled(),"native initial visible resources ready")
	check(app.errors.is_empty(),"native service initializes without legacy cache")
	check(app.service.loader.textures.is_empty(),"E1 eager texture cache remains empty")
	var all_bytes:=0;var hashes: Dictionary={}
	for row in app.service.loader.files.values():
		if row.kind=="texture":all_bytes+=int(row.pixel_size[0]*row.pixel_size[1]*4);hashes[row.pixel_sha256]=true
	check(hashes.size()==261,"261 distinct terrain textures, including 256 fine pages")
	check(all_bytes>int(config.profiles.stream.soft)*3,"unique decoded stream data exceeds frozen soft budget x3")
	var first_hash: String=await capture(output,"stream_start")
	reset_events()
	var windows: Array=[];var touched: Dictionary={};var peak_alive:=0
	# 64 viewpoints span four separated rows and all 32 columns of one world.
	for round_id in 20:
		for row in [0,2,4,6]:
			for col in range(0,32,2):
				move_to(col*512+256,row*512+256)
				var done: bool=await wait_settled()
				if not done:check(false,"route resources timeout round %d col %d row %d"%[round_id,col,row]);break
				verify_pixels()
				for id in app.service.coverage.requests:
					for file in app.service.loader.pages[id].texture_files:touched[app.service.manager.key_for(file)]=true
				peak_alive=maxi(peak_alive,alive())
		await frames(3)
		var account: Dictionary=app.service.manager.accounting()
		windows.append({"round":round_id+1,"accounting":account,"retired_weak_alive":alive(),"engine_texture_memory":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"engine_objects":Performance.get_monitor(Performance.OBJECT_COUNT),"engine_resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)})
		check(alive()==0,"round %d actual retired Texture2D references dead"%(round_id+1))
	var visited_bytes:=0
	for key in touched:
		for descriptor in app.service.manager.descriptors.values():
			if descriptor.key==key:visited_bytes+=int(descriptor.bytes);break
	check(visited_bytes>int(config.profiles.stream.soft)*3,"actually visited unique detailed textures exceed soft x3")
	check(app.service.manager.stats.reloads>0 and app.service.manager.stats.drops>0,"native distinct resources released and physically requested again")
	check(app.service.manager.stats.peak_inflight<=2,"native concurrency bounded by two")
	var hard_ok:=true;var decoded_ok:=true
	for frame in app.service.manager.frames:
		if frame.total>frame.hard:hard_ok=false
		if frame.decoded_reserved>int(config.profiles.stream.decoded):decoded_ok=false
	check(hard_ok,"fixed-profile resident plus reservation never exceeds hard admission budget")
	check(decoded_ok,"decoded/ready reservation bounded")
	check(app.service.manager.backend.stats.premature_gets==0,"native never gets before loaded")
	var tail: Array=windows.slice(15);var baseline: int=windows[0].accounting.resident
	check(tail.all(func(w):return int(w.accounting.resident)==baseline and int(w.retired_weak_alive)==0),"same viewpoint settled resident/reference windows stable across 20 rounds")
	check(tail.all(func(w):return w.engine_resources<=windows[0].engine_resources),"settled engine Resource count does not grow across route rounds")
	var stream: Dictionary=evidence("20_round_native_stream");stream.unique_total_bytes=all_bytes;stream.unique_visited_bytes=visited_bytes;stream.unique_visited_textures=touched.size();stream.windows=windows;stream.peak_retired_weak_alive=peak_alive;observations.append(stream)
	move_to(256,256);check(await wait_settled(),"return first stream view ready")
	check(await capture(output,"stream_return")==first_hash,"first view pixels identical after evict/reload")
	await clear();check(alive()==0 and app.service.manager.accounting().total==0,"stream fully drains and releases")
	# Missing E1 fine page is a real absent exported file, with a real parent retained.
	app.choose("lab");app.service.prefetch=false;app.renderer.fade_seconds=0;move_to(256,-256)
	var missing:="fine_2_1"
	for i in 240:
		await tree.process_frame
		if app.service.manager.page_states.get(missing)=="FAILED" and app.service.manager.ready("parent_1_0"):break
	var fallback: Dictionary=app.service.coverage.resolve(missing,app.service.manager)
	check(app.service.manager.page_states.get(missing)=="FAILED","actual missing fine file reports FAILED")
	check(fallback.ok and not fallback.detail_ok and fallback.selected=="parent_1_0","actual missing fine falls back to compatible resident parent")
	check(not app.service.manager.failures.is_empty(),"missing resource error recorded rather than marked successful")
	await capture(output,"missing_child_parent_ready")
	app.service.loader.pages.parent_1_0.build_id="old_parent_build"
	check(app.service.coverage.resolve(missing,app.service.manager).get("code")=="page_build_mismatch","old parent/new child version mismatch detected")
	app.service.loader.pages.parent_1_0.build_id=app.service.loader.manifest.build_id
	observations.append(evidence("missing_and_parent_version"));await clear()
	# Wrong hash is injected at the same real backend validation boundary, without corrupting source files.
	reset_events();var child_file: String=app.service.loader.pages.fine_0_0.texture_files[0]
	app.service.manager.backend.faults[child_file]="hash";move_to(-768,-768)
	for i in 240:
		await tree.process_frame
		if app.service.manager.page_states.get("fine_0_0")=="FAILED" and app.service.manager.ready("parent_0_0"):break
	check(app.service.manager.page_states.get("fine_0_0")=="FAILED","wrong source hash rejected by real backend")
	check(app.service.coverage.resolve("fine_0_0",app.service.manager).selected=="parent_0_0","wrong hash keeps parent coverage")
	app.service.manager.backend.faults.clear();app.service.manager.retry_failed()
	check(await wait_settled(),"explicit retry after hash fault removal reloads")
	observations.append(evidence("hash_failure_retry"));await clear()
	# Delay the notification of a real already-started ResourceLoader task.
	reset_events();app.service.manager.backend.faults[child_file]="delay";move_to(-768,-768);await frames(3)
	var held_key: String=app.service.manager.key_for(child_file)
	check(app.service.manager.backend.holds.has(held_key),"delay positive control reached real async task")
	var old_epoch: int=app.service.manager.epoch
	move_to(768,768);await frames(3);move_to(-768,-768);await frames(2)
	check(app.service.manager.epoch==old_epoch,"A-B-A camera motion preserves world epoch")
	app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear()
	check(await wait_settled(),"A-B-A late content adopted only by current compatible consumers")
	observations.append(evidence("ABA_current_content"));await clear()
	reset_events();app.service.manager.backend.faults[child_file]="delay";move_to(-768,-768);await frames(3)
	var old_key: String=app.service.manager.key_for(child_file);var stale_before: int=app.service.manager.stats.stale_drained
	app.choose("tongguan");app.service.prefetch=false;app.renderer.fade_seconds=0;app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear()
	check(await wait_settled(),"new package visible content ready while old task drains")
	check(app.service.manager.epoch==old_epoch+1 and app.service.manager.stats.stale_drained>stale_before,"old package native completion drained")
	check(not app.service.manager.entries.has(old_key),"no old texture attached to current package")
	check(app.service.loader.textures.is_empty(),"real Tongguan also uses residency service instead of E1 eager cache")
	await frames(10);var native_tongguan: String=await capture(output,"tongguan_streamed")
	verify_pixels()
	observations.append(evidence("package_switch_stale"))
	# Retained command negative control: deleting the manager cache alone leaves references alive.
	await clear();move_to(0,-270,.84);check(await wait_settled(),"real map reload for draw-reference control");await frames(3)
	app.set_process(false)
	var callback: Callable=app.service.manager.on_evict;app.service.manager.on_evict=Callable();app.service.manager.clear_demands();await frames(1)
	var held_alive:=alive()
	check(held_alive>0,"negative control detects draw commands retaining textures after own cache cleared")
	app.renderer.clear();await frames(3)
	check(alive()==0,"clearing CanvasItem commands and node texture refs kills retired textures")
	app.service.manager.on_evict=callback;callback=Callable()
	app.set_process(true)
	app.service._view_key=[];app.refresh();check(await wait_settled(),"reload after complete reference clear succeeds")
	check(await capture(output,"tongguan_reloaded")==native_tongguan,"actual Tongguan pixels identical after full release/reload")
	observations.append({"case":"retained_command_positive_control","retained_alive":held_alive,"after_clear_alive":alive()})
	# Shared tree atlas retains both consumers, then one, then neither.
	await clear();reset_events()
	var tree_ids: Array=[]
	for id in app.service.loader.objects:
		if app.service.loader.objects[id].record_type=="sprite" and app.service.loader.objects[id].asset_id.begins_with("tree"):tree_ids.append("object:"+id)
	check(tree_ids.size()>=2,"real source has shared atlas consumers")
	app.service.manager.set_demands({tree_ids[0]:2,tree_ids[1]:2});check(await wait_settled(),"two real atlas consumers ready")
	var atlas_key: String=app.service.manager.key_for(app.service.manager.page_files[tree_ids[0]][0])
	check(app.service.manager.entries[atlas_key].consumers.size()==2,"shared atlas counted once with two consumers")
	var drop_before: int=app.service.manager.stats.drops
	app.service.manager.set_demands({tree_ids[1]:2});await frames(3)
	check(app.service.manager.entries.has(atlas_key) and app.service.manager.entries[atlas_key].consumers.size()==1 and app.service.manager.stats.drops==drop_before,"first atlas consumer drop keeps resource")
	app.service.manager.set_demands({});app.service.manager.set_budget({"grace_usec":0});await frames(3)
	check(not app.service.manager.entries.has(atlas_key) and alive()==0,"last atlas consumer and retained commands release together")
	observations.append(evidence("shared_atlas_last_reference"));await clear()
	# Transition double holding is charged, then budget shrink clears detail commands first.
	app.choose("stream");app.service.prefetch=false;app.renderer.fade_seconds=10;reset_events();move_to(256,256)
	check(await wait_settled(),"transition source/target loaded")
	await frames(3);check(not app.renderer.fades.is_empty(),"native parent/child crossfade active")
	var before_shrink: Dictionary=app.service.manager.accounting()
	app.service.manager.set_budget({"id":"e3_shrink_to_base","soft":278784,"hard":278784,"decoded":557568,"grace_usec":0})
	await frames(5)
	check(app.service.manager.accounting().total<=278784,"mid-fade budget reduction returns within new hard budget")
	check(app.service.manager.ready("root_0_0"),"mid-fade reduction preserves affordable low-resolution root")
	check(app.service.coverage.resolve("fine_0_0",app.service.manager).selected=="root_0_0","mid-fade detail falls back to root")
	check(alive()==0,"mid-fade evicted texture refs actually released")
	await capture(output,"budget_shrink_root_fallback")
	var shrink: Dictionary=evidence("mid_fade_budget_shrink");shrink.before_shrink=before_shrink;observations.append(shrink)
	await clear();app.choose("stream");app.renderer.fade_seconds=0;reset_events()
	var root_file: String=app.service.loader.pages.root_0_0.texture_files[0]
	var parent_file: String=app.service.loader.pages.parent_0_0.texture_files[0]
	app.service.manager.backend.faults[root_file]="delay";app.service.manager.backend.faults[parent_file]="delay";move_to(256,256)
	await frames(4)
	check(app.service.coverage.resolve("fine_0_0",app.service.manager).code=="coverage_pending","real delayed root and parent remain explicitly pending")
	check(app.service.manager.accounting().inflight==2,"not-ready parents remain tracked while input/update continues")
	app.service.manager.backend.faults.clear();app.service.manager.backend.holds.clear()
	check(await wait_settled(),"delayed parent/root resume and cover without stale state")
	observations.append(evidence("parent_not_ready_delay"))
	await clear();check(app.service.manager.entries.is_empty() and alive()==0,"shutdown no tasks/strong references")
	check(app.renderer.errors.is_empty() and app.errors.is_empty(),"no renderer/service submission errors")
	var backend: Dictionary=app.service.manager.backend.stats.duplicate()
	app.service.dispose();boot.remove_child(app);app.queue_free();app=null;await frames(3)
	return {"checks":checks,"failures":failures,"profiles":config.profiles,"observations":observations,"verified_import_pixels":verified_pixels,"core":core,"e2_core":{"checks":e2.checks,"failures":e2.failures},"e1_core":{"checks":e1.checks,"failures":e1.failures},"backend":backend,"engine":Engine.get_version_info(),"actual_viewport":[1920,1080],"gpu":RenderingServer.get_video_adapter_name(),"gpu_memory_actual":null,"frame_performance_acceptance":"not_run_Q1"}
