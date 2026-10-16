extends RefCounted
var tree: SceneTree
var root: Window
var checks:=0
var failures: Array[String]=[]
var output: String="user://tests/scene_checks.json"
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func frames(n:=3)->void:
	for i in range(n):await tree.process_frame
func click(control: Control)->void:
	var at=control.get_global_rect().get_center();var motion=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event,true)
	await frames()
func capture(name: String)->void:
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
func until(app: Control,status: String)->void:
	var started=Time.get_ticks_msec()
	while app.army().snapshot().order.status!=status and Time.get_ticks_msec()-started<8000:await tree.process_frame
	check(app.army().snapshot().order.status==status,"automatic visible army reaches "+status)
func initialize_input()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	tree.create_timer(90 if OS.get_cmdline_user_args().has("--performance") else 60).timeout.connect(func():printerr("ARMY_SCENE_TIMEOUT");tree.quit(1))
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root;initialize_input()
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual release template")
	check(not DirAccess.dir_exists_absolute("res://addons"),"workshop absent from movement runtime")
	if not ResourceLoader.exists("res://army/ui.gd"):check(false,"army scene exists");tree.quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var app=load("res://army/ui.gd").new();boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await frames(5)
	if not app.is_inside_tree():check(false,"army app enters active scene tree");tree.quit(1);return
	app.save_path="user://tests/scene_session.json"
	if OS.get_cmdline_user_args().has("--performance"):await performance(app);return
	app.step_seconds=0.18;check(app.army().error.is_empty(),"runtime starts with actual host")
	check(app.state_label.text.contains("100"),"visible unit identity and troops")
	await capture("01_fore")
	await click(app.gate_button);check(not app.army().projection().gate_open,"native gate button closes authoritative gate")
	await click(app.rear_button);await until(app,"waiting");app.auto_running=false;app.canvas.finish_animation();app.refresh();await frames()
	check(app.army().snapshot().force.current_node_id=="tg_east_hold" and app.state_label.text.contains("候行"),"closed gate visibly holds east of threshold")
	await capture("02_closed_waiting")
	var before=app.army().digest(app.army().snapshot())
	app.canvas.show_buildings=false;app.canvas.show_icon=false;app.canvas.show_trees=false;app.canvas.show_route=false;app.canvas.queue_redraw();await frames()
	check(app.army().digest(app.army().snapshot())==before,"hiding all map art never moves army or opens gate")
	for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:
		app.model.recall_bookmark(id);app.refresh();await frames();check(app.army().digest(app.army().snapshot())==before,"LOD keeps military authority "+id)
		app.model.selected_site="";var at=app.canvas.global_position+app.model.site_screen(app.canvas.size)
		for pressed in [true,false]:
			var event=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
		await frames();check(app.model.selected_site=="tongguan","site remains pickable "+id)
	app.canvas.show_buildings=true;app.canvas.show_icon=true;app.canvas.show_trees=true;app.canvas.show_route=true;app.focus_army();app.refresh()
	await click(app.gate_button);await click(app.play_button);await until(app,"arrived");app.auto_running=false;app.canvas.finish_animation();await frames()
	check(app.army().snapshot().force.current_node_id=="tg_rear" and app.canvas.visual_position().distance_to(Vector2(-300,-34.285714))<0.01,"reopen reaches west endpoint on same road")
	await capture("03_open_arrived")
	await click(app.fore_button);await until(app,"arrived");app.auto_running=false;app.canvas.finish_animation();await frames()
	check(app.army().snapshot().force.current_node_id=="tg_fore","native return command returns east")
	await click(app.pause_button);check(app.army().snapshot().paused and not app.auto_running,"pause reaches actual host clock")
	await click(app.rear_button);app.auto_running=false;await click(app.step_button)
	check(app.army().snapshot().force.corridor_progress_days==1,"native single step advances existing military service")
	await click(app.save_button);var saved=app.army().digest(app.army().snapshot())
	app.army().set_gate_open(false);app.refresh();await click(app.load_button)
	check(app.army().digest(app.army().snapshot())==saved,"native save/reload restores force and gate and date")
	check(not app.auto_running,"reloading does not issue an extra future movement step")
	root.size=Vector2i(1280,720);await frames(5)
	check(app.canvas.size.x>700 and app.canvas.size.y>450,"minimum window keeps usable map")
	check(app.controls_scroll.size.y>400,"narrow window provides scrollable controls")
	check(app.get_node("Footer").size.x>1000 and app.get_node("Footer").size.y<40,"footer remains a horizontal readable line")
	await capture("04_layout_1280")
	var result={"checks":checks,"failures":failures,"native_clicks":true,"automatic_motion":true,"viewport":str(root.get_visible_rect().size)}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("P6_ARMY_SCENE: "+JSON.stringify(result));app.queue_free();app=null;await frames(6);tree.quit(0 if failures.is_empty() else 1)
func percentile(values: Array,ratio: float)->float:
	if values.is_empty():return 0
	var sorted=values.duplicate();sorted.sort();return sorted[mini(sorted.size()-1,maxi(0,int(ceil(sorted.size()*ratio))-1))]
func performance(app: Control)->void:
	await frames(30);app.command("tg_rear")
	var intervals=[];var draw_calls=[];var texture=[];var started=Time.get_ticks_usec();var last=started;var previous_phase=-1
	while Time.get_ticks_usec()-started<60000000:
		var elapsed=(Time.get_ticks_usec()-started)/1000000.0;var phase=int(elapsed/10.0)
		if phase!=previous_phase:
			app.army().set_gate_open(phase%2==0);previous_phase=phase
		var state=app.army().snapshot()
		if state.order.status=="arrived":app.command("tg_fore" if state.force.current_node_id=="tg_rear" else "tg_rear")
		elif state.order.status=="waiting" and state.city.gate_open and not app.auto_running:app.play()
		var scale=0.5-0.5*cos(TAU*elapsed/30.0);app.model.set_zoom(exp(lerpf(log(0.00014),log(2.4),scale)))
		app.model.camera_x=float(app.model.view.world_origin[0])+lerpf(-500000,0,scale);app.model.camera_y=float(app.model.view.world_origin[1])+lerpf(100000,0,scale);app.refresh()
		await tree.process_frame;var now=Time.get_ticks_usec();intervals.append((now-last)/1000.0);last=now
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));texture.append(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var result={"mode":"performance","duration_seconds":(Time.get_ticks_usec()-started)/1000000.0,"frames":intervals.size(),"frame_p95_ms":percentile(intervals,0.95),"frame_p99_ms":percentile(intervals,0.99),"frame_max_ms":percentile(intervals,1.0),"draw_calls_p95":percentile(draw_calls,0.95),"texture_peak_bytes":percentile(texture,1.0),"movement_days":app.army().snapshot().day,"gate_phases":previous_phase+1,"checks":checks,"failures":failures,"release":not OS.is_debug_build(),"viewport":str(root.get_visible_rect().size)}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("P6_ARMY_PERFORMANCE: "+JSON.stringify(result));app.queue_free();app=null;await frames(6);tree.quit(0 if failures.is_empty() else 1)
