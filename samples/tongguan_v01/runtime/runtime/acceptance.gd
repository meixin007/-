extends RefCounted
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func argument(prefix: String,fallback: String)->String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(prefix):return value.substr(prefix.length())
	return fallback
func frames(tree: SceneTree,n:=3)->void:
	for i in range(n):await tree.process_frame
func percentile(values: Array,ratio: float)->float:
	if values.is_empty():return 0
	var sorted=values.duplicate();sorted.sort();return sorted[mini(sorted.size()-1,int(ceil(sorted.size()*ratio))-1)]
func app_new(boot: Node)->Control:
	var app=load("res://runtime/ui.gd").new();app.auto_load=false;boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);return app
func run(boot: Node)->void:
	var tree=boot.get_tree();var session=boot.get_node("/root/Session");var mode=argument("--mode=","verify");var report=argument("--report=","user://acceptance.json")
	var started=Time.get_ticks_usec();var app=app_new(boot);await frames(tree,6)
	check(not OS.is_debug_build(),"release template is in use")
	check(not DirAccess.dir_exists_absolute("res://addons") and not DirAccess.dir_exists_absolute("res://p4"),"workshop is absent")
	check(app.model.load_error.is_empty(),"runtime data loads")
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/manifest.json"))
	var initial_ms=(Time.get_ticks_usec()-started)/1000.0
	print("P5_READY "+JSON.stringify({"first_view_ms":initial_ms,"pid":OS.get_process_id()}))
	for i in range(240):
		if session.cache.ready:break
		await tree.process_frame
	check(session.cache.ready,"threaded tiles become ready")
	var results={"mode":mode,"build_id":manifest.build_id,"release":not OS.is_debug_build(),"viewport":str(tree.root.get_visible_rect().size),"pid":OS.get_process_id(),"first_view_ms":initial_ms,"tiles_ready_ms":(session.cache.ready_usec-session.cache.started_usec)/1000.0,"tile_attach_max_ms":percentile(session.cache.attach_ms,1.0)}
	if mode=="verify":
		app.model.set_zoom(0.04);app.model.camera_x=app.model.view.world_origin[0];app.model.camera_y=app.model.view.world_origin[1];app.sync()
		session.cache.draw_reference=true;await frames(tree);await RenderingServer.frame_post_draw;var reference_image=tree.root.get_texture().get_image()
		session.cache.draw_reference=false;app.sync();await frames(tree);await RenderingServer.frame_post_draw;var tiled_image=tree.root.get_texture().get_image()
		var rect=Rect2i(app.canvas.global_position,app.canvas.size);var ref_data=reference_image.get_region(rect).get_data();var tile_data=tiled_image.get_region(rect).get_data();var sum=0.0;var peak=0
		DirAccess.make_dir_recursive_absolute(report.get_base_dir())
		reference_image.save_png(report.get_base_dir()+"/terrain_reference_frame.png");tiled_image.save_png(report.get_base_dir()+"/terrain_tiled_frame.png")
		for i in range(ref_data.size()):
			if i%4==3:continue
			var diff=absi(int(ref_data[i])-int(tile_data[i]));sum+=diff;peak=maxi(peak,diff)
		results.terrain_tile_rgb_mean_8bit=sum/(ref_data.size()*0.75);results.terrain_tile_channel_max=peak
		check(results.terrain_tile_rgb_mean_8bit<0.1 and peak<=3,"CHUNK-01 tiled terrain matches continuous reference")
		session.cache.suspended=true;session.cache.ready=false;app.sync();await frames(tree);check(session.cache.fallback_draw_count>0 and session.cache.fallback!=null,"fallback remains visible before details are ready");session.cache.ready=true;session.cache.suspended=false
		var expected_lod=0
		for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:
			app.model.recall_bookmark(id);app.sync();await frames(tree)
			check(app.model.lod==expected_lod,"four distinct display levels "+id);expected_lod+=1
			check(app.model.pick_site(app.model.site_screen(app.canvas.size),app.canvas.size)=="tongguan","stable site "+id)
			var policy=app.model.run_diagnostics();app.canvas.show_buildings=false;app.canvas.show_trees=false;app.sync();await frames(tree)
			check(app.model.run_diagnostics()==policy,"visibility and LOD do not change declared movement edges "+id)
			app.canvas.show_buildings=true;app.canvas.show_trees=true;app.sync();await frames(tree)
			var folder=report.get_base_dir();DirAccess.make_dir_recursive_absolute(folder)
			await RenderingServer.frame_post_draw;tree.root.get_texture().get_image().save_png(folder+"/"+id+".png")
		var state=session.state;var slot="tongguan.slot.rear_storage_01"
		check(state.construct(slot,"warehouse").ok and state.finish_construction(slot).ok,"runtime construction")
		check(state.set_growth(3).ok and state.set_damage("gate",2).ok,"runtime growth and damage")
		state.set_gate_open(false);check(not app.model.run_diagnostics().main_army,"runtime gate state")
		check(state.write_save("user://acceptance/runtime_save.json").ok,"runtime save")
		var saved=state.digest(state.runtime);state.set_growth(1);check(state.read_save("user://acceptance/runtime_save.json").ok and state.digest(state.runtime)==saved,"runtime reload")
		var authored=state.digest(state.authoring);var building_id=state.runtime.slot_occupancy[slot].building_id
		check(state.set_damage("gate",0).ok and state.runtime.growth_stage==3 and state.runtime.slot_occupancy[slot].building_id==building_id,"repair preserves growth and building identity")
		check(state.set_growth(1).ok and state.runtime.slot_occupancy[slot].status=="built" and state.digest(state.authoring)==authored,"growth never removes completed construction or changes published authoring")
		var bad=state.export_save();bad.runtime.growth_stage=99;var untouched=state.digest(state.runtime)
		check(not state.restore_save(bad).ok and state.digest(state.runtime)==untouched,"corrupt runtime save rejected atomically")
		for limit in [0.05,0.2,0.64]:
			for i in range(20):
				app.model.set_zoom(limit);var old=app.model.lod;app.model.set_zoom(limit*1.03);app.model.set_zoom(limit*0.97);check(app.model.lod==old,"20-cycle LOD hysteresis")
		var origin=app.model.view.world_origin.duplicate();var worst=0.0
		for i in range(100):
			app.model.recall_bookmark("gate_close");app.model.pan_pixels(Vector2(sin(i)*23,cos(i)*19));var p=app.model.site_screen(app.canvas.size);var world=app.model.screen_to_world(p,app.canvas.size);var again=app.model.world_to_screen(world,app.canvas.size);worst=maxf(worst,p.distance_to(again))
		check(worst<1.0 and app.model.view.world_origin==origin,"large-coordinate roundtrip below one pixel");results.anchor_error_px=worst
		for tile in session.cache.tiles:check(session.cache.tile_textures.has(tile.path),"unique terrain tile "+tile.path)
	elif mode=="performance":
		await frames(tree,30);var intervals=[];var draws=[];var texture=[];var video=[];var start=Time.get_ticks_usec();var last=start
		while Time.get_ticks_usec()-start<60000000:
			var elapsed=(Time.get_ticks_usec()-start)/1000000.0;var phase=0.5-0.5*cos(TAU*elapsed/30.0)
			app.model.set_zoom(exp(lerpf(log(0.00014),log(2.4),phase)))
			app.model.camera_x=float(app.model.view.world_origin[0])+lerpf(-500000,-300,phase)+sin(elapsed)*150*phase
			app.model.camera_y=float(app.model.view.world_origin[1])+lerpf(100000,-100,phase)+cos(elapsed*0.7)*100*phase
			app.sync();await tree.process_frame;var now=Time.get_ticks_usec();intervals.append((now-last)/1000.0);last=now
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));texture.append(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED));video.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		results.merge({"duration_seconds":(Time.get_ticks_usec()-start)/1000000.0,"frames":intervals.size(),"frame_p95_ms":percentile(intervals,0.95),"frame_p99_ms":percentile(intervals,0.99),"frame_max_ms":percentile(intervals,1.0),"draw_calls_p95":percentile(draws,0.95),"texture_peak_bytes":percentile(texture,1.0),"video_reported_peak_bytes":percentile(video,1.0)})
	elif mode=="cycles":
		app.queue_free();await frames(tree,5);var load_ms=[]
		for i in range(20):
			var start=Time.get_ticks_usec();app=app_new(boot);await frames(tree,4);load_ms.append((Time.get_ticks_usec()-start)/1000.0)
			app.model.host.set_growth(1+i%3);app.model.host.set_damage("gate",i%3);app.sync();await frames(tree,2);app.queue_free();await frames(tree,6)
			print("P5_CYCLE "+JSON.stringify({"cycle":i,"tick_usec":Time.get_ticks_usec(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}))
			await tree.create_timer(0.25).timeout
		results.hot_enter_ms=load_ms;results.cycles=20;app=null
	if app!=null:app.queue_free();await frames(tree,5)
	results.checks=checks;results.failures=failures
	var file=FileAccess.open(report,FileAccess.WRITE)
	if file==null:printerr("cannot write acceptance report");tree.quit(1);return
	file.store_string(JSON.stringify(results,"\t",true,true));file.close();print("P5_RUNTIME: "+JSON.stringify(results));tree.quit(0 if failures.is_empty() else 1)
