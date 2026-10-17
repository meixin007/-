extends RefCounted
var checks:=0
var failures: Array=[]
var observations: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func frames(tree: SceneTree,n: int=4) -> void:
	for i in n:await tree.process_frame
func screenshot(tree: SceneTree,path: String) -> Image:
	await frames(tree);await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.get_size()==Vector2i(1920,1080),"actual 1920x1080 "+path.get_file())
	check(image.save_png(path)==OK,"save native "+path.get_file())
	return image
func image_hash(image: Image) -> String:
	var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(image.get_data());return h.finish().hex_encode()
func compare_revision(tree: SceneTree,app: Control,output: String,tag: String) -> void:
	app.renderer.reference_mode=false;app.refresh();app.renderer.force_draw()
	var indexed: Image=await screenshot(tree,output.get_base_dir()+"/"+tag+"_indexed.png")
	app.renderer.reference_mode=true;app.refresh();app.renderer.force_draw()
	var reference: Image=await screenshot(tree,output.get_base_dir()+"/"+tag+"_reference.png")
	var a=indexed.get_region(Rect2i(20,96,1600,940));var b=reference.get_region(Rect2i(20,96,1600,940))
	check(a.get_data()==b.get_data(),"live revision invalidates draw commands: "+tag)
	observations.append({"live_revision":tag,"map_pixel_equal":a.get_data()==b.get_data(),"indexed_map_sha256":image_hash(a),"reference_map_sha256":image_hash(b),"telemetry":app.renderer.telemetry()})
	app.renderer.reference_mode=false;app.refresh();app.renderer.force_draw();await frames(tree)
func run(boot: Node,native: bool,output: String) -> Dictionary:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://v02/e1/config.json"))
	var core: Dictionary=load("res://v02/e2/contract_checks.gd").new().run()
	checks+=core.checks;failures.append_array(core.failures)
	var legacy: Dictionary=load("res://v02/e1/checks.gd").new().run(config,native)
	checks+=legacy.checks;failures.append_array(legacy.failures)
	if native:
		var tree=boot.get_tree();var app=load("res://v02/e2/app.gd").new();boot.add_child(app);await frames(tree)
		check(app.setup_errors.is_empty(),"E2 package and renderer initialize")
		for id in ["lab","tongguan","giant"]:
			app.choose(id);app.renderer.reference_mode=false;app.refresh();app.renderer.force_draw()
			var indexed: Image=await screenshot(tree,output.get_base_dir()+"/"+str(id)+"_indexed.png")
			var actual: Dictionary=app.renderer.telemetry()
			var submitted: Array=[]
			for row in actual.last_submissions:submitted.append(row.id)
			var planned: Array=[]
			for record in app.renderer.last_plan.records:planned.append(record.id)
			check(submitted==planned,"actual CanvasItem submissions match ordered visible plan "+id)
			check(actual.submission_errors.is_empty() and actual.errors.is_empty(),"no actual duplicate or draw errors "+id)
			app.renderer.reference_mode=true;app.refresh();app.renderer.force_draw()
			var reference: Image=await screenshot(tree,output.get_base_dir()+"/"+str(id)+"_reference.png")
			var a=indexed.get_region(Rect2i(20,96,1600,940));var b=reference.get_region(Rect2i(20,96,1600,940))
			var equal: bool=a.get_data()==b.get_data()
			check(equal,"indexed pixels equal all-source GPU-clipped reference "+id)
			observations.append({"case":id,"map_pixel_equal":equal,"indexed_map_sha256":image_hash(a),"reference_map_sha256":image_hash(b),"actual_submissions":actual,"reference_draw_source_count":app.renderer.reference_source.size()})
			app.renderer.reference_mode=false;app.refresh();app.renderer.force_draw();await frames(tree)
			if id=="giant":
				var visible: Array=app.renderer.last_plan.visible_ids
				check("lab.tree.giant_four_buckets" in visible,"actual giant crown is visible")
				var item: Dictionary=app.planner.index.record("lab.tree.giant_four_buckets")
				var view=Rect2(app.camera_x-800/app.zoom,app.camera_y-470/app.zoom,1600/app.zoom,940/app.zoom)
				check(not Rect2(item.owner[0]*512,item.owner[1]*512,512,512).intersects(view),"actual giant owner bucket entirely outside viewport")
				check(item.payload_shard in app.renderer.last_plan.required_shards and FileAccess.file_exists(app.loader.root_path+"/"+item.payload_shard),"actual offscreen owner payload present and required")
		# An engineering producer changes metadata in memory, never the source map.
		# Its raw reference is updated independently of the derived index.
		var giant_id:="lab.tree.giant_four_buckets"
		var original_giant: Dictionary=app.planner.index.record(giant_id).duplicate(true)
		var moved: Dictionary=original_giant.duplicate(true)
		moved.position_m=[-2000,800];moved.owner=[-4,1];moved.paint_bounds_m=[-2400,176,800,800]
		var reindexed: int=app.planner.index.stats.records_reindexed
		check(app.planner.index.apply_delta([moved],[],"native_move_1").ok,"native runtime object delta accepted")
		check(app.planner.index.stats.records_reindexed==reindexed+1,"native runtime delta reindexes only changed object")
		var reference_rows: Array=app.renderer.reference_source.duplicate(true)
		for i in reference_rows.size():
			if reference_rows[i].id==giant_id:reference_rows[i]=moved.duplicate(true)
		app.renderer.reference_source=reference_rows;app.renderer._reference_sorted=[]
		await compare_revision(tree,app,output,"moved")
		check(giant_id not in app.renderer.last_plan.visible_ids,"moved giant is removed from actual visible draw plan")
		check(app.planner.index.apply_delta([original_giant],[],"native_move_restore").ok,"native stable ID restored")
		var descriptor: Dictionary=app.loader.assets.tree_giant_fixture.duplicate(true);descriptor.width_m=1600
		check(app.planner.index.update_asset("tree_giant_fixture",descriptor,2).ok,"native asset bounds revision accepted")
		var enlarged: Dictionary=original_giant.duplicate(true)
		# Producer formula from declared source pixels, separate from index output.
		var scale: float=descriptor.width_m/descriptor.rect_px[2]
		enlarged.paint_bounds_m=[400-descriptor.anchor_px[0]*scale,800-descriptor.anchor_px[1]*scale,descriptor.rect_px[2]*scale,descriptor.rect_px[3]*scale]
		for i in reference_rows.size():
			if reference_rows[i].id==giant_id:reference_rows[i]=enlarged
		app.renderer.reference_source=reference_rows;app.renderer._reference_sorted=[]
		await compare_revision(tree,app,output,"enlarged")
		check(app.planner.index.record(giant_id).position_m==original_giant.position_m,"native resize preserves original ground anchor")
		var before: Dictionary=app.renderer.telemetry()
		for i in 40:app.pan(Vector2(.08,0));await frames(tree,1)
		var after: Dictionary=app.renderer.telemetry()
		check(before.planner.planner.snapshot_reads==after.planner.planner.snapshot_reads,"native camera does not reread source snapshot")
		check(before.planner.index.full_index_builds==after.planner.index.full_index_builds and before.planner.index.source_records_validated==after.planner.index.source_records_validated and before.renderer.reference_global_sorts==after.renderer.reference_global_sorts,"native camera does not rebuild source index or global reference plan")
		check(before.planner.planner.sort_calls==after.planner.planner.sort_calls,"native same-set camera movement reuses visible sorting")
		check(before.renderer.object_draw_callbacks==after.renderer.object_draw_callbacks,"native same-plan camera movement reuses CanvasItem draw commands")
		observations.append({"native_camera_before":before,"native_camera_after":after})
		var original: Array=app.renderer._draw_records
		var duplicated: Array=original.duplicate();duplicated.append(original[0]);app.renderer._draw_records=duplicated;app.renderer._objects.queue_redraw();await frames(tree)
		check(app.renderer.audit.errors.size()==1 and app.renderer.audit.errors[0].code=="duplicate_representation","real renderer duplicate submission fault caught")
		check(app.renderer.audit.submissions.size()==original.size(),"real renderer duplicate not drawn twice")
		observations.append({"actual_duplicate_fault":app.renderer.telemetry()})
		app.renderer._draw_records=original;app.renderer.errors=[];app.renderer._objects.queue_redraw();await frames(tree)
		check(app.renderer.audit.errors.is_empty() and app.renderer.errors.is_empty(),"renderer clean after explicit fault restoration")
		boot.remove_child(app);app.queue_free();await frames(tree)
	return {"checks":checks,"failures":failures,"core":core,"e1_regression":legacy,"observations":observations,"native_release":native,"engine_version":Engine.get_version_info(),"scope":"E2 visible-object query and draw-plan cache; E3 residency/capacity not implemented"}
