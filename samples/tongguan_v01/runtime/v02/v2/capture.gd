extends RefCounted
const Adapter=preload("res://v02/v2/adapter.gd")
var checks:=0
var failures: Array=[]
var captures: Array=[]
var tree: SceneTree
var output: String
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func frames(n: int=4) -> void:
	for i in n:await tree.process_frame
func capture(app: Control,name: String) -> Image:
	await frames();await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual1920x1080 "+name)
	check(image.save_png(output.get_base_dir()+"/"+name+".png")==OK,"save "+name)
	captures.append({"name":name,"camera":app.model.camera_snapshot(),"state":app.canvas.plan.duplicate(true)})
	return image.get_region(Rect2i(20,96,1600,940))
func run(boot: Node) -> void:
	tree=boot.get_tree();tree.create_timer(180).timeout.connect(func():printerr("V2_CAPTURE_TIMEOUT");tree.quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	if output.is_empty():tree.quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var core: Dictionary=load("res://v02/v2/checks.gd").new().run();checks+=core.checks;failures.append_array(core.failures)
	# Core left a completed warehouse. Restore the original scenario through its own host.
	var session=tree.root.get_node("Session");session.army=load("res://final/controller.gd").new();session.state=load("res://runtime/settlement_state.gd").new(session.army)
	var app=load("res://v02/v2/app.gd").new();boot.add_child(app);await frames(8)
	check(app.errors.is_empty(),"V2 prepares original construction service")
	check(session.get_script().resource_path=="res://v02/v2/session.gd","native sole original host selected before visual startup")
	check(not "cache" in session,"native does not initialize legacy texture cache")
	var authored: String=app.army().digest(app.army().authoring_projection());var layout: String=app.army().digest(app.model.host.layout)
	check(app.canvas.rig.socket_error()<.001,"intact original gate/wall socket alignment")
	var published_count:=0;var sample_count:=0
	for node in app.canvas.rig.get_node("Objects").get_children():
		if node.has_meta("source_id"):published_count+=1
		if node.has_meta("v1_sample_id"):sample_count+=1
	check(published_count==72 and sample_count==13,"72 original source IDs plus 13 explicitly separate accepted V1 preview placements")
	var building: String=app.army().projection().slot_occupancy[Adapter.STORAGE].building_id
	var warehouse: Sprite2D=app.canvas.rig.get_node("Objects/Warehouse");var wall: Sprite2D=app.canvas.rig.get_node("Objects/SouthWall")
	var transforms: Array=[warehouse.position,warehouse.scale,warehouse.offset,wall.position,wall.scale,wall.offset]
	for camera in app.cameras:app.recall(camera);await capture(app,camera+"_intact")
	app.recall("composition");app.canvas.terrain_only=true;app.canvas.sync();await capture(app,"terrain_only");app.canvas.terrain_only=false;app.canvas.sync()
	app.recall("courtyard");app.reset_before();await capture(app,"construction_before")
	check(not warehouse.visible,"empty slot does not show completed warehouse")
	app.build_storage();await capture(app,"construction_started")
	check(app.army().projection().slot_occupancy[Adapter.STORAGE].status=="building" and not warehouse.visible,"contract shows scaffold instead of finished roof")
	app.advance_day();await capture(app,"construction_day1");app.advance_day();await capture(app,"construction_day2");app.advance_day()
	var intact: Image=await capture(app,"construction_completed")
	check(warehouse.visible and app.army().economy().cash==120 and app.army().economy().timber==60,"actual construction completes with paid resource effects")
	var contract: String=app.army().digest(app.army().construction_for(Adapter.STORAGE));var economics: String=app.army().digest(app.army().economy())
	app.damage(2);var damaged: Image=await capture(app,"courtyard_damaged")
	check(warehouse.texture.resource_path=="res://v02/v2/assets/warehouse_damaged_v01.png","actual warehouse damage raster displayed")
	check(wall.texture.resource_path=="res://v02/v2/assets/wall_damaged_v01.png","actual wall damage raster displayed")
	check(intact.get_data()!=damaged.get_data(),"collapse produces changed actual pixels")
	app.recall("wall");await capture(app,"wall_damaged");app.damage(0);await capture(app,"wall_repaired")
	app.recall("courtyard");var repaired: Image=await capture(app,"courtyard_repaired")
	check(intact.get_data()==repaired.get_data(),"same camera repair map pixels exactly restore original")
	check([warehouse.position,warehouse.scale,warehouse.offset,wall.position,wall.scale,wall.offset]==transforms,"damage/repair preserve registered transforms")
	check(app.army().projection().slot_occupancy[Adapter.STORAGE].building_id==building,"repair keeps exact old building identity")
	check(app.army().digest(app.army().economy())==economics and app.army().digest(app.army().construction_for(Adapter.STORAGE))==contract,"native repair preserves original economics and contract")
	app.canvas.guide=true;app.canvas.sync();await capture(app,"ground_and_socket_guides");app.canvas.guide=false;app.canvas.sync()
	for stage in [2,3,1]:app.result(app.model.host.set_growth(stage),"原有成长档位");await capture(app,"growth_"+str(stage))
	var gate: bool=app.army().projection().gate_open;app.result(app.army().set_gate_open(not gate),"原有关门");app.damage(2)
	check(app.army().projection().gate_open==(not gate),"damage independent of main gate control")
	app.damage(0);app.result(app.army().set_gate_open(gate),"原有关门恢复")
	app.result(app.army().write_save(app.after_path),"保存独立审阅进度");app.damage(2);app.result(app.army().read_save(app.after_path),"恢复已有Save22审阅进度")
	check(app.army().projection().module_damage[Adapter.STORAGE]==0,"actual Save22 restores damaged/repaired state")
	app.sync()
	check(app.army().digest(app.army().authoring_projection())==authored and app.army().digest(app.model.host.layout)==layout,"all interactive actions preserve published geometry and slots")
	var authority: String=app.army().digest(app.army().context.state.to_dictionary())
	for i in 12:
		app.recall("composition");app.model.camera_x+=i*7;app.model.camera_y-=i*3;app.model.set_zoom(.84+sin(i/11.0*PI)*.35);app.canvas.sync();await capture(app,"sequence_%02d"%i)
	check(app.army().digest(app.army().context.state.to_dictionary())==authority,"camera sequence never changes gameplay authority")
	check(app.errors.is_empty(),"no silent UI action errors")
	var receipts: Array=app.receipts.duplicate(true)
	boot.remove_child(app);app.queue_free();await frames(6)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"receipts":receipts,"core":core,"visual_review":"candidate_pending_user_review","damage_art":"two actual ruin rasters; not tint","new_painted_assets":3,"actual_pixels_restored":intact.get_data()==repaired.get_data(),"old_geometry_preserved":true},"\t"));print("V2_NATIVE ",checks," ",JSON.stringify(failures));tree.quit(0 if failures.is_empty() else 1)
