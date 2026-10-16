extends "res://r3_authoring/acceptance.gd"
func pixel_hash(app,point: Array)->String:
	var at: Vector2=app.canvas.global_position+app.canvas.screen(point)
	# At zoom .7 this contains the complete visible crown and remains inside
	# the 180x140m lock region, avoiding an unprotected outside border.
	var image=root.get_texture().get_image();var rect=Rect2i(Vector2i(at-Vector2(35,48)),Vector2i(70,65))
	if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect):return "outside"
	return image.get_region(rect).get_data().hex_encode().sha256_text()
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root
	tree.create_timer(110).timeout.connect(func():printerr("R5_AUTHORING_TIMEOUT");tree.quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual final authoring Release")
	var app=load("res://final/ui.gd").new();boot.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await frames(5)
	app.workspace_path="user://tests/final_native_workspace.json";app.publication_path="user://tests/final_native_publication.json"
	check(app.host.error.is_empty(),"final authoring initializes")
	check(not FileAccess.file_exists("res://scripts/core/game_state.gd"),"authoring project has no GameState authority")
	await click(app.warehouse_button);await click(app.pin_slot_button)
	check(app.host.layout_record().warehouse_offset_m==[4,0],"native warehouse layout patch")
	var road=find_button(app,"微调关后支路");await click(road)
	await map_click(app,[-2750,1250]);await click(app.add_button);var pinned: String=app.canvas.selected;await click(app.pin_button)
	await click(app.lock_button);await map_click(app,[-2000,1200]);await click(app.exclude_button)
	var ids=app.host.state.objects.keys();ids.sort();var erased: String=ids[0]
	if erased==pinned:erased=ids[1]
	check(app.host.delete_object(erased).ok,"explicit deletion before repeated generation")
	app.canvas.selected=pinned;app.canvas.probe=Vector2(-2000,1200);app.canvas.preview={}
	app.canvas.center=Vector2(-520,-200);app.canvas.zoom=2.4;app.refresh();await frames(4);await RenderingServer.frame_post_draw
	var warehouse_rect=Rect2i(app.canvas.global_position,app.canvas.size)
	var warehouse_pixels=root.get_texture().get_image().get_region(warehouse_rect).get_data().hex_encode().sha256_text()
	app.canvas.center=Vector2(-2250,900);app.canvas.zoom=0.7;app.refresh();await frames(4);await RenderingServer.frame_post_draw
	var protected=app.host.protected_hash();var tree_point: Array=app.host.state.objects[pinned].position_m
	var pixels=pixel_hash(app,tree_point);check(pixels!="outside","fixed protected-tree camera region")
	await capture("01_manual_layout_and_locked_tree")
	for i in 50:
		var diff=app.host.preview_regeneration(["forest_west"],93000+i,0.3+float(i%4)*0.15,1+i%2)
		check(diff.ok and app.host.commit_regeneration(diff.token).ok and app.host.protected_hash()==protected and not app.host.state.objects.has(erased),"full protected content and deletion cycle "+str(i))
		check(app.host.undo().ok and app.host.redo().ok,"same authoring undo/redo chain cycle "+str(i))
		app.canvas.preview={};app.refresh();await frames(2);await RenderingServer.frame_post_draw
		check(pixel_hash(app,tree_point)==pixels,"locked tree pixels fixed cycle "+str(i))
	app.canvas.center=Vector2(-520,-200);app.canvas.zoom=2.4;app.refresh();await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_region(warehouse_rect).get_data().hex_encode().sha256_text()==warehouse_pixels,"warehouse and manual road fixed-camera pixels after fifty regeneration and undo/redo cycles")
	await capture("02_warehouse_and_road_patch")
	await click(app.save_button);var saved=app.host.digest(app.host.snapshot());await click(app.warehouse_button);await click(app.load_button)
	check(app.host.digest(app.host.snapshot())==saved,"same save restores warehouse, road, locks, tombstones and history")
	await click(app.publish_button)
	check(FileAccess.file_exists(app.publication_path) and app.host.v4_validate().is_empty(),"actual native publication and original v4 validator")
	var value: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(app.publication_path))
	check(app.host.digest(value.runtime_authoring.manual_overrides[app.host.WAREHOUSE_SLOT].offset_m)==app.host.digest([4,0]),"runtime publication carries warehouse patch")
	await capture("03_complete_publication")
	var result={"checks":checks,"failures":failures,"cycles":50,"protected_pixel_sha256":pixels,"publication_path":ProjectSettings.globalize_path(app.publication_path),"publication_sha256":FileAccess.get_sha256(app.publication_path)}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R5_AUTHORING: "+JSON.stringify({"checks":checks,"failures":failures}));app.get_parent().remove_child(app);app.queue_free();await frames(3);tree.quit(0 if failures.is_empty() else 1)
