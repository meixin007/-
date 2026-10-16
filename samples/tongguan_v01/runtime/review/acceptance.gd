extends RefCounted
var tree: SceneTree
var root: Window
var checks:=0
var failures: Array[String]=[]
var output:="user://tests/r4_native.json"
var captures: Array=[]
func check(ok: bool,message: String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func frames(n:=3)->void:
	for i in n:await tree.process_frame
func click(control: Control)->void:
	var parent=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames(2)
	var at=control.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event,true)
	await frames()
func map_click(at: Vector2)->void:
	var motion=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event,true)
	await frames()
func capture(app,name: String)->void:
	await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	check(image.save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
	captures.append({"name":name,"camera":app.model.camera_snapshot(),"baseline":app.canvas.baseline_view,"buildings":app.canvas.show_buildings,"constraints":app.canvas.show_constraints,"logic_sha256":logic(app)})
func logic(app)->String:
	return app.army().digest({"snapshot":app.army().snapshot(),"graph":app.army().context.state.transit_corridors,"money":app.army().economy()})
func key(value: int)->void:
	for pressed in [true,false]:
		var event=InputEventKey.new();event.keycode=value;event.physical_keycode=value;event.pressed=pressed;root.push_input(event,true)
	await frames()
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	tree.create_timer(150).timeout.connect(func():printerr("R4_NATIVE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual release template")
	var app=load("res://review/ui.gd").new();boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await frames(8)
	app.save_path="user://tests/r4_native_session.json"
	check(app.army().error.is_empty(),"native inherited state initializes")
	if not app.army().error.is_empty():await finish(app);return
	check(root.title=="潼关 · R4 地理与组合画面验收","R4 identifiable entry")
	check(not DirAccess.dir_exists_absolute("res://addons"),"independent runtime without editor")
	if OS.get_cmdline_user_args().has("--performance"):await performance(app);return
	var cache=root.get_node("Session").cache
	var started=Time.get_ticks_msec()
	while (not cache.ready or cache.detail_blend<1) and Time.get_ticks_msec()-started<4000:await frames(1)
	check(cache.ready and cache.detail_blend==1,"existing terrain tiles ready")
	var original=logic(app)
	for i in 4:
		await key(KEY_1+i)
		check(app.model.lod==i,"native bookmark deterministic LOD "+str(i+1))
		var site: Vector2=app.model.site_screen(app.canvas.size)
		check(Rect2(Vector2.ZERO,app.canvas.size).has_point(site),"site remains onscreen at camera "+str(i+1))
		await map_click(app.canvas.global_position+site)
		check(app.model.selected_site=="tongguan","native stable picking at camera "+str(i+1))
		await capture(app,"camera_%d_candidate"%(i+1))
		var camera=app.model.camera_snapshot()
		await click(app.baseline_button)
		check(app.canvas.baseline_view and app.model.camera_snapshot()==camera,"same-camera renderer baseline "+str(i+1))
		await capture(app,"camera_%d_baseline"%(i+1))
		await click(app.baseline_button)
	check(logic(app)==original,"camera, native picking and baseline comparison preserve all authority")
	await key(KEY_3);await click(app.buildings_choice)
	check(not app.canvas.show_buildings and not app.canvas.show_icon,"native hide buildings leaves terrain and roads visible")
	await capture(app,"geography_without_buildings")
	await click(app.constraints_choice);await click(app.footprint_choice)
	await capture(app,"geography_constraints")
	check(logic(app)==original,"constraint and complete-footprint overlays preserve all authority")
	await click(app.buildings_choice);await click(app.constraints_choice);await click(app.footprint_choice)
	await key(KEY_4)
	var resident=cache.tile_textures.size()
	var slow_start=Time.get_ticks_msec()
	for limits in [[0.035,0.065],[0.16,0.30],[0.50,0.78]]:
		for cycle in 20:
			for i in 10:app.model.set_zoom(lerpf(limits[0],limits[1],float(i)/9.0));app.refresh();await tree.create_timer(0.02).timeout
			for i in 10:app.model.set_zoom(lerpf(limits[1],limits[0],float(i)/9.0));app.refresh();await tree.create_timer(0.02).timeout
	check(Time.get_ticks_msec()-slow_start>=24000 and cache.tile_textures.size()==resident and logic(app)==original,"all 3 LOD thresholds: 20 timed roundtrips each, no state or resident texture churn")
	await key(KEY_4)
	# Same native construction buttons still quote, deduct and finish a real order.
	app.tabs.current_tab=0;await frames()
	var cash=app.army().economy().cash
	await click(app.quote_button);await click(app.build_button)
	check(app.army().economy().cash<cash,"native construction uses original account")
	for i in 3:await click(app.step_button)
	check(app.army().construction_for("tongguan.slot.rear_storage_01").status=="completed","R4 construction keeps original daily settlement")
	app.canvas.finish_animation();app.tabs.current_tab=3;await frames()
	await capture(app,"warehouse_completed")
	var slot=app.model.selected_slot
	check(app.model.host.set_damage(slot,2).ok,"same-slot damaged state")
	check(app.model.host.set_damage("gate",2).ok,"same-anchor gate damaged state")
	app.refresh();await frames();await capture(app,"damaged_placeholders")
	check(app.model.host.set_damage(slot,0).ok and app.model.host.set_damage("gate",0).ok,"same modules repaired without regeneration")
	app.refresh();await frames();await capture(app,"repaired_placeholders")
	app.tabs.current_tab=1;await frames();await click(app.gate_button);await click(app.rear_button)
	for i in 3:await click(app.step_button)
	check(app.army().snapshot().order.status=="waiting","closed main gate holds real march in R4")
	await click(app.save_button);var saved=logic(app)
	await click(app.gate_button);await click(app.step_button);await click(app.load_button)
	check(logic(app)==saved,"same-state native R4 save restores held march and resources")
	await click(app.gate_button)
	for i in 5:await click(app.step_button)
	check(app.army().snapshot().order.status=="arrived","reopened main gate completes native march")
	check(not app.army().order("river_north").ok,"candidate drawings do not authorize crossing main river")
	app.tabs.current_tab=3;app.model.recall_bookmark("tongguan_context");app.refresh();await frames();await capture(app,"final_composition")
	await finish(app)
func performance(app)->void:
	app.preview_build();app.commit_build();app.command("tg_rear");app.play()
	var started=Time.get_ticks_usec();var previous=started
	var frames_ms: Array[float]=[];var calls: Array[float]=[];var peak=0.0;var switches=0
	while Time.get_ticks_usec()-started<60000000:
		await tree.process_frame;var now=Time.get_ticks_usec();frames_ms.append((now-previous)/1000.0);previous=now
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));peak=maxf(peak,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		var next=int((now-started)/4000000)
		if next>switches:
			switches=next;app.model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][next%4]);app.canvas.show_constraints=next%3==0;app.refresh()
			var state=app.army().snapshot()
			if state.order.status=="arrived":app.command("tg_fore" if state.order.goal=="tg_rear" else "tg_rear")
	app.pause();frames_ms.sort();calls.sort()
	check(app.army().construction_for("tongguan.slot.rear_storage_01").status=="completed","performance trace completes original construction")
	await finish(app,{"duration_seconds":(Time.get_ticks_usec()-started)/1000000.0,"frames":frames_ms.size(),"frame_p95_ms":frames_ms[floori(frames_ms.size()*0.95)],"frame_p99_ms":frames_ms[floori(frames_ms.size()*0.99)],"frame_max_ms":frames_ms[-1],"draw_calls_p95":calls[floori(calls.size()*0.95)],"texture_peak_bytes":peak})
func finish(app,metrics: Dictionary={})->void:
	app.auto_running=false
	var result={"checks":checks,"failures":failures,"captures":captures};result.merge(metrics)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R4_NATIVE: "+JSON.stringify({"checks":checks,"failures":failures}))
	app.get_parent().remove_child(app);app.queue_free();await frames(3);tree.quit(0 if failures.is_empty() else 1)
