extends RefCounted
var tree: SceneTree
var output: String
var captures: Array=[]
var checks:=0
var failures: Array=[]
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func frames(n: int=4) -> void:
	for i in n:await tree.process_frame
func capture(app: Control, name: String) -> void:
	await frames();await RenderingServer.frame_post_draw
	var image:=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual image1920x1080 "+name)
	var path:=output.get_base_dir()+"/"+name+".png"
	check(image.save_png(path)==OK,"save capture "+name)
	captures.append({"name":name,"path":path,"camera":app.model.camera_snapshot(),"legacy":app.canvas.compare,"guides":app.canvas.rig.guides,"terrain_only":app.canvas.rig.terrain_only})
func run(boot: Node) -> void:
	tree=boot.get_tree();output="user://tests/map_v02/v1_capture/result.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	tree.create_timer(120).timeout.connect(func():printerr("V1_CAPTURE_TIMEOUT");tree.quit(1))
	check(not OS.is_debug_build(),"actual Release template")
	var app=load("res://v02/v1/app.gd").new();boot.add_child(app);await frames(6)
	check(app.setup_errors.is_empty(),"shared construction service prepared sample")
	check(app.canvas.rig.socket_error()<0.001,"actual sprite sockets meet")
	var before: String=app.army().digest(app.army().context.state.to_dictionary())
	for camera in ["composition","gate","shore","courtyard"]:
		app.recall(camera);await capture(app,camera+"_new")
		app.toggle_compare();await capture(app,camera+"_legacy");app.toggle_compare()
	check(app.army().digest(app.army().context.state.to_dictionary())==before,"camera and comparison preserve authority")
	app.recall("gate");await frames();await RenderingServer.frame_post_draw
	var north_visible:=tree.root.get_texture().get_image().get_data()
	app.canvas.rig.get_node("Objects/NorthWall").visible=false;await frames();await RenderingServer.frame_post_draw
	check(north_visible!=tree.root.get_texture().get_image().get_data(),"north wall contributes real pixels above terrain")
	app.canvas.rig.get_node("Objects/NorthWall").visible=true
	app.recall("gate");app.toggle_guides();await capture(app,"gate_guides");app.toggle_guides()
	app.recall("composition");app.toggle_terrain();await capture(app,"terrain_only");app.toggle_terrain()
	app.recall("courtyard");app.state_view("before");await capture(app,"construction_before")
	check(app.army().projection().slot_occupancy["tongguan.slot.rear_storage_01"].status=="empty","actual empty state")
	app.state_view("after");await capture(app,"construction_after")
	check(app.army().economy().cash==120 and app.army().economy().timber==60,"actual construction paid existing resources")
	var position: Vector2=app.canvas.rig.get_node("Objects/Warehouse").position
	app.state_view("damaged");await capture(app,"damage_placeholder")
	app.state_view("after");await capture(app,"restored")
	check(app.canvas.rig.get_node("Objects/Warehouse").position==position,"repair keeps same anchor")
	app.recall("composition")
	for i in 24:
		app.model.camera_x+=2.0;app.model.camera_y-=1.0;app.model.set_zoom(.84+sin(float(i)/23.0*PI)*.34);app.canvas.sync()
		await capture(app,"sequence_%02d"%i)
	var style: Dictionary=app.style
	boot.remove_child(app);app.queue_free();await frames()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"style_id":style.style_id,"visual_review":"pending","camera_count":4,"damage_art":"placeholder_only","scope":"V1 composition review; no streaming or capacity claim"},"\t"))
	print("V1_CAPTURE ",JSON.stringify({"checks":checks,"failures":failures}));tree.quit(0 if failures.is_empty() else 1)
