extends RefCounted
var tree: SceneTree
var root: Window
var checks:=0
var failures: Array[String]=[]
var output="user://tests/r3_scene.json"
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func frames(n:=3)->void:
	for i in n:await tree.process_frame
func click(control: Control)->void:
	var parent=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames(2);var at=control.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event,true)
	await frames()
func select(option: OptionButton,index: int)->void:
	await click(option);var popup=option.get_popup();await tree.create_timer(0.2).timeout;popup.set_focused_item(index)
	for pressed in [true,false]:
		var event=InputEventKey.new();event.keycode=KEY_ENTER;event.physical_keycode=KEY_ENTER;event.unicode=13;event.pressed=pressed;root.push_input(event,true)
	await frames()
	print("R3_OPTION ",option.get_item_text(index)," selected=",option.selected)
func capture(name: String)->void:
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
func logic(app)->String:
	return app.army().digest({"force":app.army().snapshot().force,"city":app.army().projection(),"economy":app.army().economy(),"day":app.army().snapshot().day,"corridors":app.army().context.state.transit_corridors})
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());tree.create_timer(100).timeout.connect(func():printerr("R3_SCENE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual Release template")
	var cache=tree.root.get_node("Session").cache
	cache.suspended=true;cache.ready=false;cache.detail_blend=0
	var app=load("res://integrity/ui.gd").new();boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await frames(5)
	app.save_path="user://tests/r3_native_session.json"
	check(app.army().error.is_empty(),"actual runtime initializes")
	if not app.army().error.is_empty():await finish(app);return
	check(not DirAccess.dir_exists_absolute("res://addons"),"runtime works without editor plugin")
	if OS.get_cmdline_user_args().has("--performance"):cache.suspended=false;await performance(app);return
	await capture("01_fallback")
	var original=logic(app);cache.suspended=false;var saw_blend=false;var started=Time.get_ticks_msec();var last_alpha=0.0
	while (not cache.ready or cache.detail_blend<1) and Time.get_ticks_msec()-started<4000:
		await frames(1)
		if cache.detail_blend>0 and cache.detail_blend<1:saw_blend=true
		check(cache.detail_blend>=last_alpha,"terrain fade is monotonic");last_alpha=cache.detail_blend
	check(cache.ready and saw_blend and cache.detail_blend==1.0 and logic(app)==original,"fallback-to-detail fade preserves authoritative state")
	var textures=cache.tile_textures.size()
	var slow_started=Time.get_ticks_msec()
	for limits in [[0.035,0.065],[0.16,0.28],[0.50,0.78]]:
		for cycle in 20:
			for i in 10:app.model.set_zoom(lerpf(limits[0],limits[1],float(i)/9.0));app.refresh();await tree.create_timer(0.02).timeout
			for i in 10:app.model.set_zoom(lerpf(limits[1],limits[0],float(i)/9.0));app.refresh();await tree.create_timer(0.02).timeout
	check(Time.get_ticks_msec()-slow_started>=24000 and logic(app)==original and cache.tile_textures.size()==textures,"all three LOD thresholds: twenty timed slow roundtrips each, stable state and resident textures")
	app.focus_construction();app.tabs.current_tab=1;await frames()
	await click(app.gate_button);await select(app.route_choice,1);await click(app.rear_button)
	print("R3_ORDINARY ",app.army().snapshot().order.status," ",app.message_label.text)
	check(app.army().snapshot().order.status=="idle" and app.message_label.text.contains("普通军队"),"native ordinary army cannot use trail")
	await select(app.profile_choice,1);await click(app.rear_button)
	print("R3_LIGHT ",app.army().snapshot().force.movement_profile," ",app.message_label.text)
	check(app.army().snapshot().force.movement_profile=="light" and app.message_label.text.contains("尚未"),"native light profile still needs knowledge")
	await click(app.known_choice);await click(app.rear_button)
	for i in 3:await click(app.step_button)
	app.canvas.finish_animation();await frames()
	check(app.army().snapshot().force.current_corridor_id=="tg_synthetic_trail" and app.army().position_local()[1]>50,"native light force follows registered bent path")
	await capture("02_light_on_synthetic_path")
	await select(app.profile_choice,0);check(app.army().snapshot().force.movement_profile=="light","native in-march profile change rejected")
	await click(app.known_choice);var stopped=app.army().digest(app.army().snapshot().force);await click(app.step_button)
	check(app.army().snapshot().order.status=="waiting" and app.army().digest(app.army().snapshot().force)==stopped,"native revoked condition holds in-edge force")
	await click(app.save_button);await click(app.known_choice);await click(app.step_button);await click(app.load_button)
	check(not app.army().path_known() and app.army().digest(app.army().snapshot().force)==stopped,"native save restores exact condition and in-edge progress")
	await click(app.known_choice)
	for i in 5:await click(app.step_button)
	check(app.army().snapshot().order.status=="arrived" and not app.army().projection().gate_open,"known light path reaches rear while main gate remains closed")
	app.tabs.current_tab=2;await frames();var before=logic(app);var old_art=app.army().digest(app.model.host.authoring)
	check(FileAccess.file_exists("user://authoring/tests_native_publication.json"),"actual authoring tool publication is available for end-to-end import")
	app.publication_path.text="user://authoring/tests_native_publication.json";await click(app.import_button)
	check(logic(app)==before and app.army().digest(app.model.host.authoring)!=old_art,"native publication updates only art while preserving clock, army, city and money")
	await click(app.save_button);var art=app.army().digest(app.model.host.authoring)
	app.publication_path.text="res://bundle/authoring_publication.json";await click(app.import_button);await click(app.load_button)
	check(app.army().digest(app.model.host.authoring)==art,"native selected publication restores through same GameState save")
	app.canvas.show_buildings=false;app.canvas.show_trees=false;app.canvas.show_icon=false;app.canvas.queue_redraw();await frames()
	check(logic(app)==before,"hiding all art changes no passage or force conditions")
	app.canvas.show_buildings=true;app.canvas.show_trees=true;app.canvas.show_icon=true;app.model.focus_forest();app.refresh();await frames();await capture("03_imported_authoring")
	await finish(app)
func performance(app)->void:
	app.preview_build();app.commit_build();app.army().set_movement_profile("light");app.army().set_path_known(true);app.route_choice.select(1);app.command("tg_rear");app.play()
	var started=Time.get_ticks_usec();var previous=started;var frames_ms: Array[float]=[];var drawcalls: Array[float]=[];var texture_peak:=0.0;var switches=0
	while Time.get_ticks_usec()-started<60000000:
		await tree.process_frame;var now=Time.get_ticks_usec();frames_ms.append(float(now-previous)/1000.0);previous=now
		drawcalls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));texture_peak=maxf(texture_peak,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		var next=floori(float(now-started)/5000000.0)
		if next>switches:
			switches=next;app.model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][switches%4]);app.toggle_gate()
			var order=app.army().snapshot().order
			if order.status=="arrived":app.command("tg_fore" if order.goal=="tg_rear" else "tg_rear")
			app.refresh()
	app.pause();frames_ms.sort();drawcalls.sort();check(app.army().construction_for("tongguan.slot.rear_storage_01").status=="completed","performance trajectory completes native construction")
	await finish(app,{"duration_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"frames":frames_ms.size(),"frame_p95_ms":frames_ms[floori(frames_ms.size()*0.95)],"frame_p99_ms":frames_ms[floori(frames_ms.size()*0.99)],"frame_max_ms":frames_ms[-1],"draw_calls_p95":drawcalls[floori(drawcalls.size()*0.95)],"texture_peak_bytes":texture_peak,"shared_days":app.army().snapshot().day})
func finish(app,metrics: Dictionary={})->void:
	app.auto_running=false;var result={"checks":checks,"failures":failures};result.merge(metrics)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R3_SCENE: "+JSON.stringify(result));app.get_parent().remove_child(app);app.queue_free();await frames(2);tree.quit(0 if failures.is_empty() else 1)
