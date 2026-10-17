extends RefCounted
var checks:=0
var failures: Array=[]
var captures: Array=[]
var comparisons: Array=[]
var tree: SceneTree
var output: String
var presenter: Node
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func frames(n: int=4) -> void:
	for i in n:await tree.process_frame
func shot(name: String) -> Image:
	await frames();await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual1920x1080 "+name)
	check(image.save_png(output.get_base_dir()+"/"+name+".png")==OK,"save "+name)
	captures.append({"name":name,"mode":presenter.mode,"old":presenter.old,"camera":presenter.app.model.camera_snapshot()})
	return image.get_region(Rect2i(20,96,1600,940))
func camera(x: float,y: float,zoom: float) -> void:
	var model=presenter.app.model;model.camera_x=model.view.world_origin[0]+x;model.camera_y=model.view.world_origin[1]+y;model.set_zoom(zoom);presenter.refresh_camera()
func pair(tag: String,expect_equal: bool=true) -> void:
	presenter.set_reference(false);await shot(tag+"_paged")
	presenter.set_reference(true);await shot(tag+"_reference")
	comparisons.append({"case":tag,"a":tag+"_paged.png","b":tag+"_reference.png","expect_equal":expect_equal,"roi":[20,96,1600,940],"frozen_max_channel_delta":1})
	presenter.set_reference(false)
func run(boot: Node) -> void:
	tree=boot.get_tree();tree.create_timer(240).timeout.connect(func():printerr("RELIEF_CAPTURE_TIMEOUT");tree.quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():tree.quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var core: Dictionary=load("res://v02/v2/checks.gd").new().run();checks+=core.checks;failures.append_array(core.failures)
	var session=tree.root.get_node("Session");session.army=load("res://final/controller.gd").new();session.state=load("res://runtime/settlement_state.gd").new(session.army)
	presenter=load("res://v02/relief_r01/presenter.gd").new();boot.add_child(presenter);presenter.setup(boot);await frames(6)
	var app=presenter.app;var authority: String=app.army().digest(app.army().context.state.to_dictionary())
	check(app.errors.is_empty(),"original V2 actions initialize")
	check(presenter.config.source_height_sha256==FileAccess.get_sha256("res://bundle/elevation_f32.bin"),"current numeric source identity")
	for id in ["composition","shore","courtyard"]:
		app.recall(id);presenter.set_mode(0);await shot(id+"_new_full")
		presenter.set_mode(1);await shot(id+"_new_terrain")
		presenter.set_mode(2);await shot(id+"_new_contours")
		presenter.set_mode(0);presenter.set_old(true);await shot(id+"_old_full");presenter.set_old(false)
	presenter.region_camera();await shot("region_new_terrain");presenter.set_mode(2);await shot("region_new_contours")
	for zoom in [.42,.84,1.4,2.4]:
		camera(-256,-256,zoom);presenter.set_mode(1);await pair("zoom_"+str(zoom).replace(".","_"))
	for p in [[-512,0],[0,-512],[512,0]]:
		camera(p[0],p[1],1.4);await pair("junction_%d_%d"%[p[0],p[1]])
	# Positive control: a one-cell displacement of a page must be detected.
	camera(600,200,1.4);var tile: Node2D=presenter.terrain.get_node("Tile_24");var original: Vector2=tile.position;tile.position.x+=40
	await pair("injected_page_displacement",false);tile.position=original
	check(app.army().digest(app.army().context.state.to_dictionary())==authority,"all terrain/contour/camera switches preserve authority")
	var transforms: Array=[]
	for name in ["Gate","NorthWall","SouthWall","Warehouse","Barracks"]:
		var node=app.canvas.rig.get_node("Objects/"+name);transforms.append([node.position,node.scale,node.offset])
	app.reset_before();check(app.army().projection().slot_occupancy["tongguan.slot.rear_storage_01"].status=="empty","original empty state")
	app.build_storage();check(app.army().projection().slot_occupancy["tongguan.slot.rear_storage_01"].status=="building","real contract starts")
	for day in 3:app.advance_day()
	app.recall("courtyard");presenter.set_mode(0);presenter.set_old(false)
	var before: Image=await shot("courtyard_built")
	var order: String=app.army().digest(app.army().construction_for("tongguan.slot.rear_storage_01"));var economy: String=app.army().digest(app.army().economy())
	app.damage(2);presenter.apply();await shot("courtyard_damaged");app.recall("wall");presenter.apply();await shot("wall_damaged")
	app.damage(0);app.recall("courtyard");presenter.apply();var after: Image=await shot("courtyard_repaired")
	check(before.get_data()==after.get_data(),"repair restores exact pixels over new numeric terrain")
	check(app.army().digest(app.army().construction_for("tongguan.slot.rear_storage_01"))==order and app.army().digest(app.army().economy())==economy,"terrain candidate preserves contract/economy")
	var now: Array=[]
	for name in ["Gate","NorthWall","SouthWall","Warehouse","Barracks"]:
		var node=app.canvas.rig.get_node("Objects/"+name);now.append([node.position,node.scale,node.offset])
	check(now==transforms,"no terrain-driven object displacement")
	var saved: String=app.army().digest(app.army().context.state.to_dictionary())
	for i in 12:
		camera(-400+i*58,-400+i*37,.7+sin(i/11.0*PI)*.6);presenter.set_mode(1);await shot("pan_%02d"%i)
	check(app.army().digest(app.army().context.state.to_dictionary())==saved,"continuous terrain sequence read-only")
	check(app.errors.is_empty(),"no original UI action failures")
	var receipts: Array=app.receipts.duplicate(true)
	boot.remove_child(app);app.queue_free();boot.remove_child(presenter);presenter.queue_free();await frames(6)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"comparisons":comparisons,"receipts":receipts,"visual":"candidate_pending_user_review","mip_scope":"base-level linear only","source":"original modern 40m DSM and matching contours"},"\t"))
	print("RELIEF_NATIVE ",checks," ",JSON.stringify(failures));tree.quit(0 if failures.is_empty() else 1)
