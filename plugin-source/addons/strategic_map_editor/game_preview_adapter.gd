extends Node
## Non-CK3, opt-in visual carrier. Never writes campaign data or movement permissions.
const Doc = preload("document.gd")
const Canvas = preload("map_canvas.gd")
const Library = preload("art_library.gd")
const Catalog = preload("art_catalog.gd")
const RegionalShader = preload("regional_preview.gdshader")
const GeometryCache = preload("runtime_geometry_cache.gd")
const RuntimeLabels = preload("runtime_label_policy.gd")
const FRAME := "game_map_3720x2400_scaled_4"
const EAST_ASIA_FRAME := "game_map_east_asia_4380x2400_scaled_4"
var target: Node2D
var art: Control
var previous_3d := false
var previous_camera := {}
var previous_visibility: Array = []
var document
var active := false
var styled_markers: Array = []
var previous_route_style := false
var region_id := ""
var region_rect := Rect2()
var region_container: Control
var load_timings: Dictionary = {}
var external_markers: Array = []
var full_atlas_overview := false
var prepared_map: Dictionary = {}
var place_layer: Node2D

func attach(canvas: Node2D, path: String, nodes: Array, marker_root: Node = null, requested_region: String = "") -> String:
	var error:=prepare(path,nodes,marker_root,requested_region)
	if not error.is_empty():return error
	return activate_prepared(canvas,marker_root,requested_region)

func prepare(path: String, nodes: Array, marker_root: Node = null, requested_region: String = "") -> String:
	if active: return "已显示候选图，请先退出预览。"
	prepared_map.clear()
	load_timings.clear()
	var started := Time.get_ticks_usec()
	var source_hash:=FileAccess.get_sha256(path)
	var copy=Doc.new()
	var error: String=copy.load_file(path)
	load_timings.document_ms=(Time.get_ticks_usec()-started)/1000.0
	if not error.is_empty(): return error
	var source_size := Vector2(copy.data.canvas_size[0],copy.data.canvas_size[1])
	var full_atlas: bool = copy.data.production.coordinate_frame == EAST_ASIA_FRAME and source_size == Vector2(17520,9600)
	if not full_atlas and (copy.data.production.coordinate_frame != FRAME or source_size != Vector2(14880,9600)): return "候选图坐标不匹配；需要已登记的游戏地图四倍图面坐标。"
	region_rect = Rect2()
	if not requested_region.is_empty():
		for region in copy.data.production.get("regions",[]):
			if str(region.get("id","")) == requested_region:
				var values: Array = region.rect
				region_rect = Rect2(values[0]*0.25,values[1]*0.25,values[2]*0.25,values[3]*0.25)
		if not region_rect.has_area(): return "找不到有效样区范围："+requested_region
	var index := {}
	for node in nodes: index[str(node.node_id)]=node
	var count:=0
	var seen := {}
	for f in copy.data.features:
		if f.domain_id.is_empty(): continue
		if not index.has(f.domain_id) or seen.has(f.domain_id) or f.points.size() != 1: return "候选图绑定了未知或不唯一的地点："+f.domain_id
		seen[f.domain_id]=true
		var p: Array=index[f.domain_id].coords
		if Vector2(p[0]*14880,p[1]*9600).distance_to(Vector2(f.points[0][0],f.points[0][1])) > 0.01: return "地点偏离当前项目锚点："+f.name
		count+=1
	# The registered atlas is a geographic base. Campaign nodes remain supplied
	# by the game, and no authoring feature creates or moves a gameplay node.
	if count == 0 and not full_atlas: return "候选图缺少既有地点绑定。"
	var library := Library.new()
	var library_started := Time.get_ticks_usec()
	var appearances: Array = []
	if copy.data.presentation.has("bundle") and marker_root != null:
		library.set_bundle(str(copy.data.presentation.bundle.id))
		error = library.ensure_loaded()
		if not error.is_empty(): return error
		for f in copy.data.features:
			if f.domain_id.is_empty() or f.kind not in ["city","pass"]: continue
			if region_rect.has_area() and not region_rect.has_point(Vector2(f.points[0][0],f.points[0][1])*0.25): continue
			var marker := marker_root.find_child("MapNodeMarker__"+str(f.domain_id),true,false)
			if marker == null or not marker.has_method("set_workshop_art"): return "缺少既有地点外观接口："+str(f.domain_id)
			var texture: Texture2D = library.texture(Catalog.site_variant(f))
			if texture == null: return "缺少地点素材："+str(f.domain_id)
			var rect := library.site_rect(f,Vector2.ZERO)
			var label: Array = f.get("visual",{}).get("label_offset",[0,0])
			appearances.append([marker,texture,Rect2(rect.position*0.25,rect.size*0.25),Vector2(label[0],label[1])*0.25])
	load_timings.library_ms=(Time.get_ticks_usec()-library_started)/1000.0
	if source_hash!=FileAccess.get_sha256(path):return "地图正在保存，请稍后重载。"
	prepared_map={"document":copy,"source_size":source_size,"full_atlas":full_atlas,"appearances":appearances,"source_hash":source_hash}
	return ""

func activate_prepared(canvas: Node2D, marker_root: Node = null, requested_region: String = "") -> String:
	if active or prepared_map.is_empty():return "地图尚未完成载入检查。"
	var copy=prepared_map.document
	var source_size: Vector2=prepared_map.source_size
	var full_atlas: bool=prepared_map.full_atlas
	var appearances: Array=prepared_map.appearances
	var path: String=copy.current_path
	target=canvas
	region_id=requested_region
	document=copy
	previous_3d=canvas.use_3d_map
	var camera: Camera2D=canvas.get_camera()
	previous_camera={"position":camera.position,"zoom":camera.zoom.x,"max_zoom":camera.max_zoom,"min_zoom":camera.min_zoom,"bounds":camera.map_bounds}
	if requested_region.is_empty(): camera.map_bounds = Rect2(Vector2.ZERO,source_size*0.25)
	# Workshop source is four times game coordinates. Allow the same close view.
	camera.max_zoom = maxf(camera.max_zoom,12.0)
	# The replacement atlas owns its drawn geography. Gameplay routes remain in
	# the campaign; corridor_at_screen also excludes this hidden visual layer.
	full_atlas_overview = full_atlas and region_id.is_empty()
	if full_atlas_overview:
		var routes: CanvasItem = canvas.get_corridor_visual()
		previous_visibility.append([routes,routes.visible]); routes.hide()
	if region_id.is_empty():
		for layer in [canvas.get_faction_layer(),canvas.get_mountain_layer(),canvas.get_terrain_masks(),canvas.get_state_name_layer()]:
			if layer != null: previous_visibility.append([layer,layer.visible]); layer.hide()
		for layer in canvas.get_geography_layer().get_children():
			if layer is CanvasItem: previous_visibility.append([layer,layer.visible]); layer.hide()
	canvas.set_use_3d(false)
	if canvas.has_method("set_workshop_route_style"):
		previous_route_style = canvas.workshop_route_style
		canvas.set_workshop_route_style(true)
	art=Canvas.new()
	art.runtime_mode=true
	art.show_bound_sites=copy.data.presentation.get("depth_sort",false)
	art.show_site_labels=false
	art.show_author_paths=false
	art.filter_game_sites=not full_atlas
	art.export_mode=true; art.show_rules=false; art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.size=source_size*0.25; art.zoom=0.25
	if region_rect.has_area():
		region_container=Control.new()
		region_container.name="WorkshopSampleRegion"
		region_container.position=region_rect.position
		region_container.size=region_rect.size
		region_container.clip_contents=true
		region_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
		canvas.add_child(region_container)
		canvas.move_child(region_container,canvas.get_region_layer().get_index())
		var composite := CanvasGroup.new()
		composite.name="SampleComposite"
		var material := ShaderMaterial.new()
		material.shader=RegionalShader
		material.set_shader_parameter("region_size",region_rect.size)
		composite.material=material
		region_container.add_child(composite)
		composite.add_child(art)
		art.position=-region_rect.position
	else:
		canvas.get_geography_layer().add_child(art)
	# Canvas._ready sets editor input defaults; override AFTER entering the tree.
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.focus_mode=Control.FOCUS_NONE
	var bind_started := Time.get_ticks_usec()
	var prepared := GeometryCache.read(path) if full_atlas and prepared_map.source_hash==FileAccess.get_sha256(path) else {}
	if not prepared.is_empty():
		art.polygon_meshes=prepared.polygon_meshes.duplicate()
		art.polygon_signatures=prepared.polygon_signatures.duplicate()
		art._water_shapes=prepared.water_shapes.duplicate()
	art.bind_document(copy)
	if not prepared.is_empty(): GeometryCache.apply_details(art,prepared)
	load_timings.geometry_cache_hit=not prepared.is_empty()
	load_timings.canvas_bind_ms=(Time.get_ticks_usec()-bind_started)/1000.0
	art.pan=Vector2.ZERO
	for entry in appearances:
		entry[0].set_workshop_art(entry[1],entry[2],entry[3],art.show_bound_sites)
		styled_markers.append(entry[0])
	if full_atlas and marker_root != null:
		for marker in marker_root.find_children("MapNodeMarker__*","",true,false):
			if marker.has_method("set_base_map_art_external"):
				external_markers.append([marker,marker.base_map_art_external])
				marker.set_base_map_art_external(true)
	active=true
	if full_atlas_overview and marker_root != null and marker_root.has_method("select_workshop_place"):
		place_layer = preload("workshop_place_layer.gd").new()
		place_layer.name = "WorkshopPlaceSelection"
		canvas.add_child(place_layer)
		place_layer.configure(copy.data,art,canvas)
		place_layer.place_clicked.connect(marker_root.select_workshop_place)
		for entry in external_markers:
			entry[0].set_workshop_place_input_external(true)
	prepared_map.clear()
	_process(0.0)
	return ""

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(art): return
	if full_atlas_overview:
		var camera: Camera2D = target.get_camera()
		var viewport_size: Vector2 = camera.get_viewport_rect().size
		var overview_zoom := minf(viewport_size.x/camera.map_bounds.size.x,viewport_size.y/camera.map_bounds.size.y)
		var label_tier := RuntimeLabels.tier_for_zoom(camera.zoom.x,overview_zoom)
		if art.runtime_label_tier != label_tier or not is_equal_approx(art.runtime_camera_zoom,camera.zoom.x):
			art.set_runtime_label_view(label_tier,camera.zoom.x)
			target.workshop_label_tier = label_tier
	# A full atlas does not filter art by campaign marker visibility. LOD changes
	# to those markers must not invalidate the unchanged geographic draw list.
	if not art.filter_game_sites:return
	var visible_sites := {}
	for marker in styled_markers:
		if is_instance_valid(marker) and marker.is_visible_in_tree() and marker.projection_status != "fog_of_war" and not marker.is_in_far_mode():
			visible_sites[marker.node_id] = true
	if art.visible_bound_instance_sites != visible_sites:
		art.visible_bound_instance_sites = visible_sites
		art.queue_redraw()

func detach() -> void:
	if not active: return
	active=false
	if is_instance_valid(place_layer):
		place_layer.get_parent().remove_child(place_layer)
		place_layer.queue_free()
	place_layer = null
	for entry in external_markers:
		if is_instance_valid(entry[0]):
			entry[0].set_workshop_place_input_external(false)
			entry[0].set_base_map_art_external(entry[1])
	external_markers.clear()
	for marker in styled_markers:
		if is_instance_valid(marker): marker.set_workshop_art(null)
	styled_markers.clear()
	if is_instance_valid(art):
		art.hide()
		art.get_parent().remove_child(art)
		art.queue_free()
	if is_instance_valid(region_container):
		region_container.get_parent().remove_child(region_container)
		region_container.queue_free()
	region_container=null
	for entry in previous_visibility:
		if is_instance_valid(entry[0]): entry[0].visible=entry[1]
	previous_visibility.clear()
	if is_instance_valid(target):
		target.workshop_label_tier = ""
		if target.has_method("set_workshop_route_style"):
			target.set_workshop_route_style(previous_route_style)
		target.set_use_3d(previous_3d)
		var camera: Camera2D=target.get_camera()
		camera.max_zoom = previous_camera.max_zoom
		camera.min_zoom = previous_camera.min_zoom
		camera.map_bounds = previous_camera.bounds
		camera.focus_on_position(previous_camera.position,previous_camera.zoom,true)
	document=null

func _exit_tree() -> void:
	detach()
