extends "res://review/acceptance.gd"
var boot_node: Node
var ready_metrics: Dictionary={}
func argument(prefix: String,fallback: String)->String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):return arg.substr(prefix.length())
	return fallback
func new_app()->Control:
	var app=load("res://final/ui.gd").new();boot_node.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.save_path="user://tests/r5_native_%d.json"%OS.get_process_id();return app
func percentile(values: Array,ratio: float)->float:
	var ordered=values.duplicate();ordered.sort();return ordered[mini(ordered.size()-1,maxi(0,ceili(ordered.size()*ratio)-1))] if not ordered.is_empty() else 0.0
func gameplay(app)->String:
	var snapshot=app.army().snapshot();snapshot.erase("revision");snapshot.order.erase("receipts")
	return app.army().digest({"snapshot":snapshot,"graph":app.army().context.state.transit_corridors,"money":app.army().economy()})
func select(option: OptionButton,index: int)->void:
	await click(option);await tree.create_timer(0.2).timeout;option.get_popup().set_focused_item(index)
	await key(KEY_ENTER)
func run(boot: Node)->void:
	boot_node=boot;tree=boot.get_tree();root=tree.root;output=argument("--report=","user://tests/r5_native.json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var mode=argument("--mode=","verify");tree.create_timer(420).timeout.connect(func():printerr("R5_NATIVE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual final Release template")
	var started=Time.get_ticks_usec();var cache=root.get_node("Session").cache
	if mode=="verify":cache.suspended=true;cache.ready=false;cache.detail_blend=0
	var app=new_app();await frames(5)
	check(app.army().error.is_empty() and not DirAccess.dir_exists_absolute("res://addons"),"final runtime uses native authority without editor")
	ready_metrics.first_view_ms=(Time.get_ticks_usec()-started)/1000.0
	print("R5_READY "+JSON.stringify({"first_view_ms":ready_metrics.first_view_ms,"pid":OS.get_process_id()}))
	if mode=="verify":
		check(cache.fallback_draw_count>0 and app.model.pick_site(app.model.site_screen(app.canvas.size),app.canvas.size)=="tongguan","fallback proxy remains visible and selectable")
		await capture(app,"00_fallback_proxy");cache.suspended=false
	var wait_started=Time.get_ticks_msec()
	while (not cache.ready or cache.detail_blend<1) and Time.get_ticks_msec()-wait_started<4000:await frames(1)
	check(cache.ready and cache.detail_blend==1,"all six terrain resources ready with fade")
	ready_metrics.tiles_ready_ms=(cache.ready_usec-cache.started_usec)/1000.0;ready_metrics.attach_max_ms=percentile(cache.attach_ms,1)
	if mode in ["performance","soak","profile"]:await trace(app,15.0 if mode=="profile" else (60.0 if mode=="performance" else 300.0));return
	if mode=="cycles":await cycles(app);return
	if mode=="load":await synthetic_load(app);return
	await verify(app)
func verify(app)->void:
	var cache=root.get_node("Session").cache;var before=logic(app)
	for i in 4:
		await key(KEY_1+i);var at: Vector2=app.model.site_screen(app.canvas.size)
		await map_click(app.canvas.global_position+at)
		check(app.model.lod==i and app.model.selected_site=="tongguan","four native tiers and stable site "+str(i))
		app.canvas.show_buildings=false;app.canvas.show_icon=false;app.canvas.show_trees=false;app.canvas.show_route=false;app.refresh();await frames()
		check(logic(app)==before,"visibility and LOD preserve all authority "+str(i))
		app.canvas.show_buildings=true;app.canvas.show_icon=true;app.canvas.show_trees=true;app.canvas.show_route=true;app.refresh();await frames();await capture(app,"lod_%d"%i)
	var resident=cache.tile_textures.size();var slow_start=Time.get_ticks_msec()
	for limits in [[0.035,0.065],[0.16,0.30],[0.50,0.78]]:
		for cycle in 20:
			for i in 10:app.model.set_zoom(lerpf(limits[0],limits[1],float(i)/9));app.refresh();await tree.create_timer(0.02).timeout
			for i in 10:app.model.set_zoom(lerpf(limits[1],limits[0],float(i)/9));app.refresh();await tree.create_timer(0.02).timeout
	check(Time.get_ticks_msec()-slow_start>=24000 and cache.tile_textures.size()==resident and logic(app)==before,"three slow LOD thresholds each twenty timed roundtrips")
	var worst=0.0;var origin=app.model.view.world_origin.duplicate()
	for i in 100:
		app.model.recall_bookmark("gate_close");app.model.pan_pixels(Vector2(sin(i)*23,cos(i)*19));var p: Vector2=app.model.site_screen(app.canvas.size);var world: Array=app.model.screen_to_world(p,app.canvas.size);worst=maxf(worst,p.distance_to(app.model.world_to_screen(world,app.canvas.size)))
	check(worst<1 and app.model.view.world_origin==origin,"large-coordinate anchor remains below one pixel")
	ready_metrics.anchor_error_px=worst
	app.model.recall_bookmark("guanzhong_east");cache.draw_reference=true;app.refresh();await frames();await RenderingServer.frame_post_draw
	var rect=Rect2i(app.canvas.global_position,app.canvas.size);var reference=root.get_texture().get_image().get_region(rect)
	cache.draw_reference=false;app.refresh();await frames();await RenderingServer.frame_post_draw;var tiled=root.get_texture().get_image().get_region(rect)
	reference.save_png(output.get_base_dir()+"/chunk_reference.png");tiled.save_png(output.get_base_dir()+"/chunk_tiles.png")
	var a=reference.get_data();var b=tiled.get_data();var sum=0.0;var peak=0
	for i in a.size():
		if i%4==3:continue
		var diff=absi(a[i]-b[i]);sum+=diff;peak=maxi(peak,diff)
	ready_metrics.terrain_tile_rgb_mean_8bit=sum/(a.size()*0.75);ready_metrics.terrain_tile_channel_max=peak
	check(ready_metrics.terrain_tile_rgb_mean_8bit<0.1 and peak<=3,"tiled terrain matches continuous reference with bleed")
	check(app.model.host.authoring.generated.size()==app.model.host.authoring.generated.keys().size() and cache.tile_textures.size()==6,"unique object ownership and six cached tiles")
	await key(KEY_4);app.tabs.current_tab=0;await frames()
	var cash=app.army().economy().cash;await click(app.quote_button);await click(app.build_button)
	check(app.army().economy().cash<cash,"warehouse construction spends actual account")
	for i in 3:await click(app.step_button)
	check(app.army().construction_for("tongguan.slot.rear_storage_01").status=="completed","warehouse finishes through shared daily settlement")
	var slot_geometry=app.army().digest(app.model.host.layout.slots)
	for growth in [1,2,3]:
		for damage in [0,1,2]:
			check(app.model.host.set_growth(growth).ok and app.model.host.set_damage("tongguan.slot.rear_storage_01",damage).ok,"independent growth and damage combination")
			check(app.army().digest(app.model.host.layout.slots)==slot_geometry,"no slot geometry changes with growth or damage")
	app.model.host.set_damage("tongguan.slot.rear_storage_01",0);app.refresh();await frames();await capture(app,"warehouse_repaired")
	app.tabs.current_tab=1;await frames();await click(app.gate_button);await click(app.rear_button)
	for i in 3:await click(app.step_button)
	check(app.army().snapshot().order.status=="waiting" and not app.army().passage("tg_main_gate").is_passable,"closed native main corridor holds force")
	await click(app.gate_button)
	for i in 5:await click(app.step_button)
	check(app.army().snapshot().order.status=="arrived" and app.army().passage("tg_main_gate").is_passable,"open main corridor reaches actual endpoint")
	check(not app.army().order("river_north").ok,"no bridge edge means no main-river crossing")
	await select(app.route_choice,1);await click(app.fore_button)
	check(app.message_label.text.contains("普通军队"),"ordinary force cannot use synthetic trail")
	await select(app.profile_choice,1);await click(app.fore_button)
	check(app.message_label.text.contains("尚未"),"unknown trail denied to light force")
	await click(app.known_choice);await click(app.gate_button);await click(app.fore_button)
	for i in 3:await click(app.step_button)
	check(app.army().snapshot().force.current_corridor_id=="tg_synthetic_trail","light known trail uses actual registered bent edge")
	await click(app.known_choice);var held=app.army().digest(app.army().snapshot().force);await click(app.step_button)
	check(app.army().snapshot().order.status=="waiting" and app.army().digest(app.army().snapshot().force)==held,"revoked knowledge holds exact progress")
	app.tabs.current_tab=2;await frames();app.publication_path.text="user://tests/final_native_publication.json";before=gameplay(app);await click(app.import_button)
	check(gameplay(app)==before and app.model.host.authoring.manual_overrides["tongguan.slot.rear_storage_01"].offset_m[0]==4,"actual authoring publication preserves gameplay while recording normal audit revision")
	await click(app.save_button);var authored=app.army().digest(app.model.host.authoring);app.army().import_publication("res://bundle/authoring_publication.json");await click(app.load_button)
	check(app.army().digest(app.model.host.authoring)==authored,"same native save restores selected presentation and gameplay")
	app.tabs.current_tab=4;await frames();app.migration_source.text="res://final/fixtures/r4_save.json";before=logic(app);await click(app.migration_preview_button)
	check(not app.migration_commit_button.disabled and logic(app)==before,"native old-save preview changes no gameplay")
	await click(app.migration_commit_button)
	check(app.army().snapshot().day==2 and app.army().economy().cash==120,"native migration preserves actual previous economy and date")
	await click(app.save_button);var saved=logic(app);app.army().set_gate_open(not app.army().projection().gate_open);await click(app.save_button)
	FileAccess.open(app.save_path,FileAccess.WRITE).store_string("{torn")
	await click(app.recovery_button);check(logic(app)==saved,"native explicit backup restores complete old generation")
	app.tabs.current_tab=3;app.model.recall_bookmark("tongguan_context");app.refresh();await frames();await capture(app,"final_composition")
	await finish_final(app)
func trace(app,seconds: float)->void:
	app.preview_build();app.commit_build();app.command("tg_rear");app.play();await frames(30)
	var start=Time.get_ticks_usec();var previous=start;var times=[];var draws=[];var texture_peak=0.0;var states=0
	while Time.get_ticks_usec()-start<seconds*1000000:
		var elapsed=(Time.get_ticks_usec()-start)/1000000.0;var phase=0.5-0.5*cos(TAU*elapsed/30.0)
		app.model.set_zoom(exp(lerpf(log(0.00014),log(2.4),phase)))
		# Reach the real geography before detail zoom; otherwise most of a naive
		# linear camera trace measures empty coarse background at high zoom.
		var focus=smoothstep(0,0.5,phase)
		app.model.camera_x=float(app.model.view.world_origin[0])+lerpf(-500000,-220,focus)+sin(elapsed)*130*phase
		app.model.camera_y=float(app.model.view.world_origin[1])+lerpf(100000,-100,focus)+cos(elapsed*0.7)*90*phase
		var next=int(elapsed/5)
		if next>states:
			states=next;app.model.host.set_growth(1+states%3);app.model.host.set_damage("gate",states%3);app.canvas.show_constraints=states%3==0
			if app.army().snapshot().order.status=="arrived":app.command("tg_fore" if app.army().snapshot().order.goal=="tg_rear" else "tg_rear")
			app.refresh()
		app.canvas.queue_redraw();await tree.process_frame;var now=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));texture_peak=maxf(texture_peak,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	app.pause();check(app.army().construction_for("tongguan.slot.rear_storage_01").status=="completed","full trace completes actual construction")
	await finish_final(app,{"duration_seconds":(Time.get_ticks_usec()-start)/1000000.0,"frames":times.size(),"frame_p95_ms":percentile(times,0.95),"frame_p99_ms":percentile(times,0.99),"frame_max_ms":percentile(times,1),"draw_calls_p95":percentile(draws,0.95),"texture_peak_bytes":texture_peak,"shared_days":app.army().snapshot().day})
func cycles(app)->void:
	app.auto_running=false;boot_node.remove_child(app);app.queue_free();await frames(6);var hot=[];var resident=root.get_node("Session").cache.tile_textures.size()
	for i in 20:
		var started=Time.get_ticks_usec();app=new_app();await frames(4);hot.append((Time.get_ticks_usec()-started)/1000.0)
		app.model.host.set_growth(1+i%3);app.model.host.set_damage("gate",i%3);app.refresh();await frames(2)
		check(root.get_node("Session").cache.tile_textures.size()==resident,"same resident terrain set during enter "+str(i))
		app.auto_running=false;boot_node.remove_child(app);app.queue_free();await frames(6)
		print("R5_CYCLE "+JSON.stringify({"cycle":i,"tick_usec":Time.get_ticks_usec(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"node_count":root.get_child_count()}));await tree.create_timer(0.25).timeout
	await finish_final(null,{"cycles":20,"hot_enter_ms":hot})
func synthetic_load(app)->void:
	app.canvas.hide();var report=[]
	for count in [1,4,16]:
		var grid=GridContainer.new();grid.columns=4;grid.position=Vector2(24,112);boot_node.add_child(grid);var displays=[]
		for i in count:
			var canvas=load("res://review/canvas.gd").new();canvas.model=load("res://runtime/model.gd").new();canvas.model.recall_bookmark("tongguan_context");canvas.font=app.theme.default_font;canvas.custom_minimum_size=Vector2(340,200);grid.add_child(canvas);displays.append(canvas)
		await frames(5);var started=Time.get_ticks_usec();var previous=started;var times=[]
		while Time.get_ticks_usec()-started<3000000:
			for canvas in displays:canvas.queue_redraw()
			await tree.process_frame;var now=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		report.append({"display_copies":count,"frame_p95_ms":percentile(times,0.95),"frame_p99_ms":percentile(times,0.99),"frames":times.size()});boot_node.remove_child(grid);grid.queue_free();await frames(6)
	check(app.army().context.state.military_forces.size()==1,"synthetic display copies do not create worlds or forces")
	await finish_final(app,{"synthetic_display_load":report,"scope":"copies of existing display only; not additional historical nodes"})
func finish_final(app,metrics: Dictionary={})->void:
	var result={"checks":checks,"failures":failures,"captures":captures};result.merge(ready_metrics);result.merge(metrics)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R5_NATIVE: "+JSON.stringify({"checks":checks,"failures":failures}))
	if app!=null:app.auto_running=false;app.get_parent().remove_child(app);app.queue_free();await frames(3)
	tree.quit(0 if failures.is_empty() else 1)
