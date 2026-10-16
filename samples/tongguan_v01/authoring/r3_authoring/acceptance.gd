extends RefCounted
var tree: SceneTree
var root: Window
var failures: Array[String]=[]
var checks:=0
var output="user://r3_tests/native/result.json"
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
	await frames(2);var point=control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;root.push_input(event,true)
	await frames()
func map_click(app,point: Array)->void:
	var at=app.canvas.global_position+app.canvas.screen(point)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await frames()
func capture(name: String)->void:
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(output.get_base_dir()+"/"+name+".png")==OK,"capture "+name)
func find_button(node: Node,text: String)->Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var result=find_button(child,text)
		if result!=null:return result
	return null
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root
	tree.create_timer(70).timeout.connect(func():printerr("R3_AUTHORING_SCENE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual authoring Release template")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var app=load("res://r3_authoring/workshop.gd").new();boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await frames(5)
	app.workspace_path="user://r3_tests/native_workspace.json"
	app.publication_path=OS.get_environment("APPDATA").replace("\\","/").path_join("tongguan_slice_v01_integrity/authoring/tests_native_publication.json")
	check(app.host.error.is_empty(),"new authoring UI initializes without changing old scene")
	await map_click(app,[-2750,1250]);await click(app.add_button)
	var id: String=app.canvas.selected;check(id.begins_with("manual.") and app.host.state.patches.has(id),"native manual add")
	await click(app.move_button);check(app.host.state.objects.has(id) and app.host.state.objects[id].position_m[0]>-2600,"native cross-chunk move preserves ID")
	await click(app.delete_button);check(not app.host.state.objects.has(id) and app.host.state.tombstones.has(id),"native delete retains tombstone")
	await click(app.undo_button);check(app.host.state.objects.has(id),"native undo restores deleted object")
	await click(app.redo_button);check(not app.host.state.objects.has(id),"native redo deletes same ID")
	await click(app.add_button);var pinned: String=app.canvas.selected;await click(app.pin_button)
	check(app.host.state.pins.has(pinned),"native pin")
	await click(app.lock_button);check(app.host.state.zones.size()==1,"native lock region")
	await map_click(app,[-2000,1200]);await click(app.exclude_button);check(app.host.state.zones.size()==2,"native exclude region")
	var protected=app.host.protected_hash();var before=app.host.digest(app.host.snapshot())
	await click(app.preview_button);check(not app.commit_button.disabled and app.host.digest(app.host.snapshot())==before,"native diff preview has no mutation")
	await capture("01_authoring_diff")
	await click(app.commit_button);check(app.host.protected_hash()==protected,"native commit preserves manual footprint and tombstone")
	await click(find_button(app,"检查穿过锁区的河岸候选"));check(app.canvas.preview.get("conflicts",[]).size()>0 and app.commit_button.disabled,"native crossing candidate rejected with visible conflict")
	await capture("02_footprint_conflict")
	await click(app.save_button);var saved=app.host.digest(app.host.snapshot())
	await map_click(app,[-2850,1300]);await click(app.add_button);await click(app.load_button)
	check(app.host.digest(app.host.snapshot())==saved,"native save/reopen restores whole authoring state and history")
	await click(app.publish_button);check(FileAccess.file_exists(app.publication_path) and app.result_label.text.contains("已发布"),"native publication writes separate runtime package")
	check(app.host.v4_validate().is_empty(),"native published source is accepted by original v4 validator")
	await capture("03_authoring_published")
	var result={"checks":checks,"failures":failures,"publication_path":app.publication_path}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R3_AUTHORING_SCENE: "+JSON.stringify(result))
	app.get_parent().remove_child(app);app.queue_free();await frames(2);tree.quit(0 if failures.is_empty() else 1)
