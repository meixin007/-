extends RefCounted
var tree: SceneTree
var root: Window
var checks := 0
var failures: Array[String] = []
var output := "user://tests/r2_scene.json"
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message); printerr("FAIL: ",message)
func frames(n:=3) -> void:
	for i in n: await tree.process_frame
func click(control: Control) -> void:
	control.grab_focus(); await frames(2)
	var at=control.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new(); motion.position=at; root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new(); event.position=at; event.global_position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0; root.push_input(event,true)
	await frames()
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
func run(boot: Node) -> void:
	tree=boot.get_tree(); root=tree.root
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	tree.create_timer(95).timeout.connect(func():printerr("R2_SCENE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"): check(not OS.is_debug_build(),"real release template")
	var app=load("res://construction/ui.gd").new(); boot.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); await frames(5)
	app.save_path="user://tests/r2_native_session.json"
	check(app.army().error.is_empty(),"actual host and UI initialize")
	if not app.army().error.is_empty(): await finish(app); return
	check(not DirAccess.dir_exists_absolute("res://addons"),"runtime does not depend on workshop")
	check(app.model.host._local.is_empty(),"map reads the single state provider")
	if OS.get_cmdline_user_args().has("--performance"): await performance(app); return
	var authored=app.army().digest(app.model.host.authoring)
	var clicked_slot="tongguan.slot.rear_workshop_01"
	var local=app.model.slot_center(clicked_slot); var at=app.canvas.global_position+app.model.local_to_screen([local.x,local.y],app.canvas.size)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new(); event.position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)
	await frames()
	check(app.model.selected_slot==clicked_slot and app.slot_choice.selected==2,"native map picking selects same stable plot and dropdown")
	app.select_slot("tongguan.slot.rear_storage_01")
	await capture("01_initial")
	await click(app.quote_button); check(not app.build_button.disabled and app.quote_label.text.contains("120"),"native quote shows actual cost")
	await click(app.build_button); check(app.army().economy().cash==120 and app.work_label.text.contains("0 / 3"),"native confirmation starts paid project")
	await capture("02_paid_working")
	await click(app.step_button); check(app.army().construction_for(app.model.selected_slot).work_days==1,"native day button performs one work day")
	await click(app.save_button); var saved=app.army().digest(app.army().context.state.to_dictionary())
	await click(app.step_button); await click(app.step_button); check(app.work_label.text.contains("已竣工"),"native third day completes module")
	await click(app.load_button); check(app.army().digest(app.army().context.state.to_dictionary())==saved and app.work_label.text.contains("1 / 3"),"native mid-construction load restores cash, time and work")
	await capture("03_restored_midwork")
	app.tabs.current_tab=1; await frames()
	await click(app.gate_button); await click(app.rear_button)
	for i in 3: await click(app.step_button)
	check(app.army().snapshot().order.status=="waiting" and not app.army().projection().gate_open,"closed gate holds native army")
	check(app.army().construction_for(app.model.selected_slot).status=="completed","construction completes while army waits")
	app.tabs.current_tab=0; app.refresh(); await frames(); await capture("04_completed_closed_gate")
	var invariant=app.army().digest(app.army().context.state.to_dictionary())
	for id in ["east_asia","guanzhong_east","tongguan_context","gate_close"]:
		app.model.recall_bookmark(id); app.refresh(); await frames()
		check(app.army().digest(app.army().context.state.to_dictionary())==invariant,"LOD preserves work and army "+id)
	app.focus_construction(); app.canvas.show_buildings=false; app.canvas.show_icon=false; app.canvas.show_trees=false; app.canvas.queue_redraw(); await frames()
	check(app.army().digest(app.army().context.state.to_dictionary())==invariant,"art visibility never changes paid building or passage")
	app.canvas.show_buildings=true; app.canvas.show_icon=true; app.canvas.show_trees=true
	app.model.host.set_growth(3); app.select_slot("tongguan.slot.expansion_01"); app.kind_choice.select(1); await frames()
	await click(app.quote_button); check(app.build_button.disabled and app.message_label.text.contains("建设款不足"),"native insufficient cash explains refusal")
	app.select_slot("tongguan.slot.rear_storage_01"); app.focus_construction(); app.refresh(); await frames()
	await capture("05_insufficient_funds")
	check(app.army().digest(app.model.host.authoring)==authored,"building and save never overwrite manual authoring or geometry")
	app.reset(); await click(app.quote_button); await click(app.step_button); await click(app.build_button)
	check(app.army().economy().cash==240 and app.message_label.text.contains("重新查看"),"native stale quote cannot charge")
	app.preview_build(); app.commit_build(); app.step_seconds=0.1; await click(app.play_button)
	var started=Time.get_ticks_msec()
	while app.army().construction_for(app.model.selected_slot).status!="completed" and Time.get_ticks_msec()-started<5000: await frames(1)
	await click(app.pause_button); check(app.army().construction_for(app.model.selected_slot).status=="completed","continuous time completes construction without army orders")
	var paused=app.army().digest(app.army().context.state.to_dictionary()); await tree.create_timer(0.3).timeout
	check(app.army().digest(app.army().context.state.to_dictionary())==paused,"pause stops automatic clock and work")
	await finish(app)
func performance(app: Control) -> void:
	app.preview_build(); app.commit_build(); app.command("tg_rear"); app.step_seconds=1.6; app.play()
	var times: Array[float]=[]; var draws: Array[float]=[]; var texture_peak:=0.0
	var started=Time.get_ticks_usec(); var previous=started; var switches=0
	while Time.get_ticks_usec()-started<60000000:
		await tree.process_frame
		var now=Time.get_ticks_usec(); times.append(float(now-previous)/1000.0); previous=now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)); texture_peak=maxf(texture_peak,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		var next=floori(float(now-started)/5000000.0)
		if next>switches:
			switches=next; app.model.recall_bookmark(["east_asia","guanzhong_east","tongguan_context","gate_close"][switches%4]); app.toggle_gate()
			var order=app.army().snapshot().order
			if order.status=="arrived": app.command("tg_fore" if order.goal=="tg_rear" else "tg_rear")
			app.refresh()
	app.pause(); times.sort(); draws.sort()
	check(app.army().construction_for(app.model.selected_slot).status=="completed","performance trajectory completes actual construction")
	var metrics={"duration_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"frames":times.size(),"frame_p95_ms":times[floori(times.size()*0.95)],"frame_p99_ms":times[floori(times.size()*0.99)],"frame_max_ms":times[-1],"draw_calls_p95":draws[floori(draws.size()*0.95)],"texture_peak_bytes":texture_peak,"shared_days":app.army().snapshot().day}
	await finish(app,metrics)
func finish(app: Control, metrics: Dictionary={}) -> void:
	app.auto_running=false
	var result={"checks":checks,"failures":failures}; result.merge(metrics)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t")); print("R2_SCENE: "+JSON.stringify(result))
	app.get_parent().remove_child(app); app.queue_free(); await frames(2)
	tree.quit(0 if failures.is_empty() else 1)
