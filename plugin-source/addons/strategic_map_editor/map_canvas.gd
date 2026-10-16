@tool
extends Control
const Doc = preload("document.gd")
const RuntimeLabels = preload("runtime_label_policy.gd")
var runtime_label_tier := "" # Empty preserves workshop and export label behavior.
var runtime_camera_zoom := 1.0
var runtime_label_surface: Node2D
var runtime_label_rebuilds := 0
var runtime_draw_chunks: Array[Node2D] = []
const ArtCatalog = preload("art_catalog.gd")
const ArtLibrary = preload("art_library.gd")
const ArtRibbon = preload("art_ribbon.gd")
const WaterBrush = preload("water_brush.gd")
var water_input = preload("water_brush_input.gd").new()
var water_width := 24.0
var water_radius := 60.0
var water_connect := true
var water_whole := false
var water_end_styles: Array=["auto","auto"]
var water_last_commit_ms := 0.0
var water_join = preload("water_join.gd").new()
const Spatial = preload("art_spatial.gd")
var show_footprints := false
var show_prefectures := true
var show_country_borders := true
var show_dao_borders := true
var show_site_anchors := true
var anchor_draw_records: Array = []
const TANG_DAO_NAMES := ["京畿道","都畿道","关内道","河南道","河东道","河北道","陇右道","山南东道","山南西道","剑南道","淮南道","江南东道","江南西道","黔中道","岭南道"]
var show_dao_labels := true
# Runtime camera scale at the full-map view; the editor keeps its own zoom.
var dao_label_screen_scale := 1.0
var show_factions := true
var art_group_mode := false
var art_drag_ids: Array=[]
var _depth_items: Array = []
var _depth_order_input: Array=[]
var _depth_order: Array=[]
var _depth_labels: Array = []
var label_draw_records: Array = []
var _label_rects: Array[Rect2] = []
var _drawing_depth_labels := false
var _spatial_index = preload("spatial_index.gd").new()
var _spatial_cache: Array = []
var _spatial_valid := false
var _spatial_generation:=-1
var _placement_entries: Array=[]
var _placement_index=preload("spatial_index.gd").new()
var _placement_generation:=-1
var _detail_preview:=false
var geometry_revision:=0
var _geometry_state: Array = []
var _layer_features: Dictionary = {}
var _packed_features: Dictionary = {}
var _detail_cache: Dictionary = {}
var _surface_cells: Dictionary = {}
var _surface_batches: Dictionary = {}
var _terrain_scatter_key: Array = []
var _terrain_scatter_items: Array = []
var _water_prepared_key: Array = []
var _label_water_cache: Dictionary={}
var _label_waters: Array=[]
var _label_bodies: Array=[]
var _depth_by_id: Dictionary={}
var _frame_art_entries: Array=[]
var _water_query_cache: Dictionary = {}
const ART_PAPER := Color("efe6c9")
const ART_COLORS := {"mountain":ART_PAPER,"hills":ART_PAPER,"forest":Color("ede9d0"),"basin":ART_PAPER,"water":Color("aed0ce")}
var art = ArtLibrary.new()
var map_viewport: SubViewport
var map_display: TextureRect
const CACHE_MARGIN := 384
var art_exclusions: Array = []
func has_art() -> bool:
	return doc != null and doc.data.get("art_style","schematic") == "tongguan_v1" and view_mode != "structure"

const Geometry = preload("geometry_ops.gd")
signal selection_changed(id: String)
signal art_selection_changed(id: String)
signal message(text: String)
signal endpoint_chosen(point: Vector2, is_start: bool)
signal pointer_changed(point: Vector2, scale: float)

const PAPER := Color("e7dfc7")
const INK := Color("514c3e")
const BOUNDARY_COLORS := {"country_border":Color("ac493e"),"province_border":Color("7760ab"),"prefecture":Color("927b59")}
const COLORS := {"mountain":Color("b4b39e"),"hills":Color("ccc7a9"),"forest":Color("a9b99b"),"basin":Color("ded9b7"),"water":Color("8eafba")}
var doc: RefCounted
var tool := "select"
var selected := ""
var zoom := 0.6
var pan := Vector2(30,40)
var draft: Array = []
var pointer := Vector2.ZERO
var panning := false
var hand_panning := false
var dragging := false
var drag_vertex := -1
var active_ring := -1
var drag_ring := -1
var drag_origin := Vector2.ZERO
var drag_points: Array = []
var ghost: Array = []
var selection_overlay = preload("selection_overlay.gd").new()
var drag_outline_only := false
var drag_preview_revision := 0

func selection_handles() -> Array:
	selection_overlay.prepare(self,true)
	return selection_overlay.handles

func _geometry_preview(id: String) -> bool:
	return not ghost.is_empty() and not drag_outline_only and id in selection_ids

func _dense_selection() -> bool:
	var count:=0
	for id in selection_ids:
		var f: Dictionary=doc.find_feature(id)
		count+=f.get("points",[]).size()
		for hole in f.get("holes",[]):count+=hole.size()
	return count>512
var show_rules := true
var export_mode := false
var runtime_mode := false
var export_layer := "composite" # composite, terrain, sites, labels
var transparent_page := false
var include_labels := true
var include_auxiliary := false
var export_debug := false
var route := PackedVector2Array()
var start_point := Vector2(250,430)
var end_point := Vector2(1330,430)
var background: Texture2D
var background_key := ""
var ink_font: SystemFont
const LABEL_FONT_SIZE:=64
var freehand := false
var stroke_active := false
var brush_width := 3.0
var simplify_pixels := 2.0
var snap_mode := 0
var grid_step := 32.0
var show_grid := false
var reference_drag := false
var reference_origin := Vector2.ZERO
var reference_ghost := Vector2.ZERO
var active_reference := "primary"
var reference_cache: Dictionary = {}
var reference_view_key := ""
var check_scope := Rect2()
var feature_bounds: Dictionary = {}
var polygon_meshes: Dictionary = {}
var polygon_signatures: Dictionary = {}
var _water_shapes: Dictionary = {}
var last_mesh_rebuilds := 0
var selection_ids: Array = []
var show_bound_sites := true
var show_site_labels := true
var show_author_paths := true
var filter_game_sites := false
var visible_bound_instance_sites: Dictionary = {}
var view_mode := "art" # structure, art, overlay; all use one source document.
var selected_art_id := ""
var brush_asset := "tree_broad"
var brush_scale := 1.0
var pointer_over_canvas := false
var art_dragging := false
var art_drag_origin := Vector2.ZERO
var art_drag_start := Vector2.ZERO
var art_ghost := Vector2.ZERO
var art_stroke_active := false
var art_stroke_points: Array[Vector2] = []
var art_erase_ids: Array[String] = []
var visual_issues: Array = []
var visual_curve_feature_id := ""
var visual_curve_kind := "" # ribbon, path or ridge_guide; authoring overlay only.
var visual_curve_points: Array = []
var visual_curve_widths: Array = []
var visual_curve_style := ""
var visual_curve_default_width := 12.0
var visual_curve_active_index := -1
var visual_curve_drag_index := -1
var selection_guard: Callable
signal tool_changed(value: String)

func select_many(ids: Array) -> void:
	active_ring=-1
	selection_ids = ids.filter(func(id): return not doc.find_feature(str(id)).is_empty())
	selected = str(selection_ids[-1]) if not selection_ids.is_empty() else ""
	selection_changed.emit(selected)
	_redraw_interaction()

func visible_world_rect() -> Rect2:
	if _drawing_surface: return _camera_cache_rect
	if doc == null: return Rect2()
	return Rect2(world_at(Vector2.ZERO),size/zoom).intersection(Rect2(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])))

func center_on(point: Vector2) -> void:
	pan = size*0.5-point*zoom
	pointer_changed.emit(point,zoom)
	queue_redraw()

func locate_feature(id: String) -> void:
	var f: Dictionary = doc.find_feature(id)
	if f.is_empty(): return
	var bounds: Rect2 = feature_bounds.get(id,Rect2(Vector2(f.points[0][0],f.points[0][1]),Vector2.ONE))
	zoom = clampf(minf(size.x/maxf(bounds.size.x+100,240),size.y/maxf(bounds.size.y+100,240)),0.002,3.0)
	center_on(bounds.get_center())
	select_feature(id)
	if not doc.layer(f.layer).visible: message.emit("已定位；该对象图层目前隐藏，可在图层面板打开。")

static func reference_bounds(ref: Dictionary) -> Rect2:
	var origin := Vector2(ref.position[0],ref.position[1])
	var extent := Vector2(ref.size[0],ref.size[1])
	var center := origin+extent*0.5
	var bounds := Rect2(center,Vector2.ZERO)
	for corner in [Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)]:
		bounds = bounds.expand(center+(corner-extent*0.5).rotated(deg_to_rad(ref.rotation)))
	return bounds

func _process(_delta: float) -> void:
	if doc == null or export_mode or not is_visible_in_tree(): return
	var key := str(pan,size,zoom)
	if key != reference_view_key:
		reference_view_key = key
		_refresh_references()

func _refresh_references() -> void:
	if export_mode: return
	var changed_cache:=false
	var visible_refs: Array = []
	for ref in doc.references():
		if ref.visible and not ref.path.is_empty() and reference_bounds(ref).intersects(visible_world_rect()): visible_refs.append(ref)
	# 128 MiB preview budget. Source files remain unchanged in the portable project.
	var limit := 2048
	while visible_refs.size()*limit*limit*4 > 128*1024*1024: limit /= 2
	var keep: Array = []
	for ref in visible_refs:
		var key: String = doc.resolve_reference_path(ref.get("id","primary"))
		keep.append(key)
	for key in reference_cache.keys():
		if key not in keep or reference_cache[key].limit != limit:
			reference_cache.erase(key)
			changed_cache=true
	for ref in visible_refs:
		var key: String = doc.resolve_reference_path(ref.get("id","primary"))
		if reference_cache.has(key): continue
		changed_cache=true
		var img := Image.new()
		var texture: Texture2D
		if img.load(key) == OK and img.get_width() <= 8192 and img.get_height() <= 8192:
			var ratio := minf(1.0,float(limit)/maxi(img.get_width(),img.get_height()))
			if ratio < 1: img.resize(maxi(1,roundi(img.get_width()*ratio)),maxi(1,roundi(img.get_height()*ratio)),Image.INTERPOLATE_BILINEAR)
			texture = ImageTexture.create_from_image(img)
		else: message.emit("参考图读取失败或超过 8192 像素："+key.get_file())
		reference_cache[key] = {"texture":texture,"limit":limit}
	background_key = doc.resolve_reference_path()
	background = reference_cache.get(background_key,{}).get("texture")
	if changed_cache:
		_camera_cache_valid=false
		queue_redraw()

var interaction_overlay: Control
var render_surface: Node2D
var terrain_surface: Node2D
var _terrain_cache_key: Array=[]
var _terrain_layers: Array=[]
var terrain_command_rebuilds:=0
var camera_settle: Timer
var _drawing_surface:=false
var _camera_motion_only:=false
var _camera_cache_valid:=false
var _camera_cache_rect:=Rect2()
var _camera_cache_pan:=Vector2.ZERO
var _camera_cache_zoom:=1.0
var _camera_cache_size:=Vector2.ZERO
var _camera_cache_revision:=-1
var _camera_cache_panning:=false
var _camera_cache_options: Array=[]
var map_command_rebuilds:=0

func _redraw_interaction() -> void:
	if is_instance_valid(interaction_overlay): interaction_overlay.queue_redraw()

func _ready() -> void:
	art.load_failed.connect(func(issue): message.emit(issue))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	ink_font = SystemFont.new()
	# A shared raster atlas avoids synchronous MSDF generation for every newly
	# revealed Chinese glyph. Fixed-size glyphs plus mipmaps retain zoom quality.
	ink_font.multichannel_signed_distance_field = false
	ink_font.generate_mipmaps = true
	ink_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	render_surface=Node2D.new()
	render_surface.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if export_mode:
		add_child(render_surface)
	else:
		map_viewport=SubViewport.new()
		map_viewport.disable_3d=true
		map_viewport.transparent_bg=true
		map_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		add_child(map_viewport)
		var offset:=Node2D.new();offset.position=Vector2.ONE*CACHE_MARGIN
		map_viewport.add_child(offset);offset.add_child(render_surface)
		map_display=TextureRect.new()
		map_display.mouse_filter=Control.MOUSE_FILTER_IGNORE
		map_display.texture=map_viewport.get_texture()
		map_display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		map_display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		add_child(map_display)
	render_surface.draw.connect(_render_map)
	if runtime_mode and export_mode:
		runtime_label_surface=Node2D.new()
		runtime_label_surface.name="RuntimeLabels"
		runtime_label_surface.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(runtime_label_surface)
		runtime_label_surface.draw.connect(_render_runtime_labels)
	terrain_surface=Node2D.new()
	terrain_surface.show_behind_parent=true
	render_surface.add_child(terrain_surface)
	terrain_surface.draw.connect(_render_terrain)
	camera_settle=Timer.new();camera_settle.one_shot=true;camera_settle.wait_time=.12
	camera_settle.timeout.connect(func():_camera_motion_only=false;queue_redraw())
	add_child(camera_settle)
	interaction_overlay=preload("interaction_overlay.gd").new()
	interaction_overlay.canvas=self
	interaction_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(interaction_overlay)
	interaction_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func():_camera_motion_only=true;queue_redraw())
	mouse_entered.connect(func(): pointer_over_canvas = true; _redraw_interaction())
	mouse_exited.connect(func(): pointer_over_canvas = false; _redraw_interaction())

func bind_document(value: RefCounted) -> void:
	if doc != null and doc.changed.is_connected(_document_changed): doc.changed.disconnect(_document_changed)
	_end_visual_curve()
	doc = value
	water_join.revision=-1
	doc.changed.connect(_document_changed)
	_document_changed()

func _document_changed() -> void:
	_camera_cache_valid=false
	_spatial_valid=false
	if is_instance_valid(runtime_label_surface):runtime_label_surface.queue_redraw()
	if has_art():
		art.set_bundle(str(doc.data.get("presentation", {}).get("bundle", {}).get("id", "tongguan_v1")))
		var error: String = art.ensure_loaded()
		if not error.is_empty(): message.emit(error)
	route.clear()
	if not selected.is_empty() and doc.find_feature(selected).is_empty():
		selected = ""
		selection_changed.emit("")
	if not selected_art_id.is_empty() and doc.find_art_instance(selected_art_id).is_empty():
		selected_art_id = ""
		art_selection_changed.emit("")
	if doc.get_reference(active_reference).is_empty(): active_reference = "primary"
	# Art transactions retain the exact geography array; avoid comparing every
	# coordinate with a deep copy on each stamp, drag commit and history step.
	if doc.last_change_art_only and is_same(_geometry_state,doc.data.features):
		queue_redraw()
		return
	_placement_generation=-1
	geometry_revision+=1
	_geometry_state=doc.data.features
	_layer_features.clear();_packed_features.clear()
	_detail_cache.clear(); _surface_cells.clear(); _surface_batches.clear(); _water_query_cache.clear(); _label_water_cache.clear()
	_label_waters=doc.data.features.filter(func(f):return f.kind=="water" and f.get("visual",{}).get("visible",true) and not f.get("visual",{}).has("ribbon"))
	art_exclusions = doc.data.features.filter(func(f): return f.kind in ["river","valley","trail","water"])
	feature_bounds.clear()
	var updated_meshes: Dictionary = {}
	var updated_signatures: Dictionary = {}
	var updated_water: Dictionary = {}
	last_mesh_rebuilds = 0
	for f in doc.data.features:
		var points := Doc.packed(f.points)
		_packed_features[f.id]=points
		if not _layer_features.has(f.layer):_layer_features[f.layer]=[]
		_layer_features[f.layer].append(f)
		var bounds := Rect2(points[0],Vector2.ZERO)
		for p in points: bounds = bounds.expand(p)
		# Include labels and symbol overhang in the culling bounds.
		var padding: float = maxf(f.width,128*f.scale)
		if points.size() == 1: padding = maxf(padding,f.name.length()*34*f.scale)
		feature_bounds[f.id] = bounds.grow(padding)
		if f.kind in Doc.POLYGONS:
			var signature: String = Doc.canonical_digest([f.points, f.holes])
			updated_signatures[f.id] = signature
			if f.kind=="water":
				if polygon_signatures.get(f.id,"")==signature and _water_shapes.has(f.id):updated_water[f.id]=_water_shapes[f.id]
				else:
					var origin: Vector2=points[0];var outer:=points.duplicate();var holes: Array=[]
					for n in range(outer.size()):outer[n]-=origin
					for source_hole in f.holes:
						var hole:=Doc.packed(source_hole)
						for n in range(hole.size()):hole[n]-=origin
						holes.append(hole)
					updated_water[f.id]={"origin":origin,"outer":outer,"holes":holes}
			if polygon_signatures.get(f.id, "") == signature and polygon_meshes.has(f.id):
				updated_meshes[f.id] = polygon_meshes[f.id]
			else:
				updated_meshes[f.id] = Geometry.triangles(f)
				last_mesh_rebuilds += 1
	polygon_meshes = updated_meshes
	polygon_signatures = updated_signatures
	_water_shapes=updated_water
	selection_ids = selection_ids.filter(func(id): return not doc.find_feature(str(id)).is_empty())
	var selected_feature: Dictionary=doc.find_feature(selected)
	if selected_feature.is_empty() or active_ring >= selected_feature.holes.size(): active_ring=-1
	check_scope = Rect2()
	reference_view_key = ""
	_refresh_references()
	var extent := Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])
	start_point = start_point.clamp(Vector2.ZERO,extent)
	end_point = end_point.clamp(Vector2.ZERO,extent)
	queue_redraw()

func fit_map() -> void:
	if doc == null: return
	var extent := Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])
	zoom = maxf(0.002, minf((size.x-48)/extent.x,(size.y-48)/extent.y))
	pan = (size-extent*zoom)*0.5
	queue_redraw()

func set_tool(value: String) -> void:
	water_input.active=false
	if value != "visual_curve": _end_visual_curve()
	tool = value
	draft.clear()
	ghost.clear()
	dragging = false
	stroke_active = false
	reference_drag = false
	panning = false
	hand_panning = false
	art_dragging = false
	art_stroke_active = false
	art_stroke_points.clear()
	art_erase_ids.clear()
	mouse_default_cursor_shape = Control.CURSOR_DRAG if value == "hand" else Control.CURSOR_ARROW
	queue_redraw()
	tool_changed.emit(value)

func begin_visual_curve(feature_id: String) -> bool:
	if doc == null: return false
	var f: Dictionary = doc.find_feature(feature_id)
	if f.is_empty() or f.kind not in ["water", "valley", "mountain", "hills"] or doc.layer(f.layer).locked: return false
	if not has_art() and not (view_mode!="structure" and f.kind=="water" and f.get("visual",{}).has("ribbon")): return false
	set_tool("visual_curve")
	visual_curve_feature_id = feature_id
	visual_curve_kind = "ribbon" if f.kind == "water" else ("path" if f.kind == "valley" else "ridge_guide")
	var visual: Dictionary = f.get("visual", {})
	if f.kind == "water":
		var ribbon: Dictionary = visual.get("ribbon", {})
		visual_curve_points = ribbon.get("points", []).duplicate(true)
		visual_curve_widths = ribbon.get("widths", []).duplicate(true)
		visual_curve_style = str(ribbon.get("render_style", "inked_varied"))
	elif f.kind == "valley":
		visual_curve_points = visual.get("path", f.points).duplicate(true)
		visual_curve_widths = []
		visual_curve_style = str(visual.get("path_style", "painted"))
	else:
		visual_curve_points = visual.get("ridge_guide", []).duplicate(true)
		visual_curve_widths = []
		visual_curve_style = ""
	visual_curve_active_index = -1
	select_feature(feature_id)
	queue_redraw()
	return true

func _end_visual_curve() -> void:
	visual_curve_feature_id = ""
	visual_curve_kind = ""
	visual_curve_points.clear()
	visual_curve_widths.clear()
	visual_curve_active_index = -1
	visual_curve_drag_index = -1

func visual_curve_pending() -> bool:
	if visual_curve_feature_id.is_empty() or doc == null: return false
	var f: Dictionary = doc.find_feature(visual_curve_feature_id)
	if f.is_empty(): return false
	var visual: Dictionary = f.get("visual", {})
	if visual_curve_kind == "ribbon":
		var ribbon: Dictionary = visual.get("ribbon", {})
		return visual_curve_points != ribbon.get("points", []) or visual_curve_widths != ribbon.get("widths", []) or visual_curve_style != str(ribbon.get("render_style", "inked_varied"))
	if visual_curve_kind == "path":
		return visual_curve_points != visual.get("path", f.points) or visual_curve_style != str(visual.get("path_style", "painted"))
	if visual_curve_kind == "ridge_guide": return visual_curve_points != visual.get("ridge_guide", [])
	return false

func has_uncommitted_canvas_input() -> bool:
	return not draft.is_empty() or visual_curve_pending()

func add_visual_curve_point(p: Vector2) -> bool:
	if visual_curve_kind not in ["ribbon","ridge_guide"] or visual_curve_points.size() >= 128 or not _inside(p): return false
	var f: Dictionary = doc.find_feature(visual_curve_feature_id)
	if f.is_empty() or not Geometry.contains(f,p): return false
	if not visual_curve_points.is_empty() and Vector2(visual_curve_points[-1][0],visual_curve_points[-1][1]).distance_to(p) < 2: return false
	visual_curve_points.append([p.x,p.y])
	if visual_curve_kind == "ribbon": visual_curve_widths.append(visual_curve_default_width)
	visual_curve_active_index = visual_curve_points.size()-1
	queue_redraw()
	return true

func move_visual_curve_point(index: int, p: Vector2) -> bool:
	if index < 0 or index >= visual_curve_points.size() or not _inside(p): return false
	visual_curve_points[index] = [p.x,p.y]
	visual_curve_active_index = index
	queue_redraw()
	return true

func insert_visual_curve_point(index: int, p: Vector2) -> bool:
	if index < 1 or index >= visual_curve_points.size() or visual_curve_points.size() >= 128 or not _inside(p): return false
	visual_curve_points.insert(index,[p.x,p.y])
	if visual_curve_kind == "ribbon":
		visual_curve_widths.insert(index,(float(visual_curve_widths[index-1])+float(visual_curve_widths[index]))*0.5)
	visual_curve_active_index = index
	queue_redraw()
	return true

func remove_visual_curve_point(index: int) -> bool:
	if index < 0 or index >= visual_curve_points.size() or visual_curve_points.size() <= 2: return false
	if visual_curve_kind == "path" and index in [0,visual_curve_points.size()-1]: return false
	visual_curve_points.remove_at(index)
	if visual_curve_kind == "ribbon": visual_curve_widths.remove_at(index)
	visual_curve_active_index = mini(index,visual_curve_points.size()-1)
	queue_redraw()
	return true

func set_visual_curve_width(index: int, width: float) -> bool:
	if visual_curve_kind != "ribbon" or index < 0 or index >= visual_curve_widths.size() or not is_finite(width) or width < 6 or width > 128: return false
	visual_curve_widths[index] = width
	visual_curve_active_index = index
	queue_redraw()
	return true

func commit_visual_curve() -> bool:
	if visual_curve_feature_id.is_empty() or visual_curve_points.size() < 2: return false
	var values: Dictionary
	if visual_curve_kind == "ribbon":
		values = {"ribbon":{"points":visual_curve_points.duplicate(true),"widths":visual_curve_widths.duplicate(true),"render_style":visual_curve_style}}
		var previous: Dictionary=doc.find_feature(visual_curve_feature_id).get("visual",{}).get("ribbon",{})
		if previous.has("end_styles"): values.ribbon.end_styles=previous.end_styles.duplicate()
	elif visual_curve_kind == "path":
		values = {"path":visual_curve_points.duplicate(true),"path_style":visual_curve_style}
	else:
		values = {"ridge_guide":visual_curve_points.duplicate(true)}
	if not doc.update_appearance(visual_curve_feature_id,values):
		message.emit("表现线未应用：请检查控制点、宽度与源水域 / 谷道边界；原地图未改。")
		return false
	message.emit("表现线已保存，可继续拖点、Shift 加点、Alt 删点；源地理与通行规则未改。")
	queue_redraw()
	return true

func _visual_curve_point_at(p: Vector2) -> int:
	var nearest := 10.0 / zoom
	var index := -1
	for i in range(visual_curve_points.size()):
		var distance := Vector2(visual_curve_points[i][0],visual_curve_points[i][1]).distance_to(p)
		if distance < nearest: nearest = distance; index = i
	return index

func _visual_curve_segment_at(p: Vector2) -> int:
	var nearest := 15.0 / zoom
	var index := -1
	for i in range(visual_curve_points.size()-1):
		var a := Vector2(visual_curve_points[i][0],visual_curve_points[i][1])
		var b := Vector2(visual_curve_points[i+1][0],visual_curve_points[i+1][1])
		var distance := Geometry2D.get_closest_point_to_segment(p,a,b).distance_to(p)
		if distance < nearest: nearest = distance; index = i+1
	return index

func world_at(screen: Vector2) -> Vector2:
	return (screen-pan)/zoom

func _inside(p: Vector2) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x <= doc.data.canvas_size[0] and p.y <= doc.data.canvas_size[1]

func snap_point(p: Vector2) -> Vector2:
	var value := p
	if snap_mode == 1: value = p.snapped(Vector2.ONE*grid_step)
	elif snap_mode == 2:
		var distance := 12.0/zoom
		for f in doc.data.features:
			if not doc.layer(f.layer).visible: continue
			for point in Doc.packed(f.points):
				if point.distance_to(p) < distance:
					value = point
					distance = point.distance_to(p)
	return value.clamp(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1]))

func finish_shape() -> void:
	var required := 3 if tool in Doc.POLYGONS or tool == "hole" else 2
	if draft.size() < required:
		message.emit("至少需要 %d 个点。" % required)
		return
	if tool == "hole":
		if doc.add_hole(selected,draft):
			draft.clear(); active_ring=doc.find_feature(selected).holes.size()-1
			message.emit("已挖孔洞；选择工具可拖动蓝色顶点，支持撤销。")
		else: message.emit("孔洞未应用：请先选择未锁定的区域；孔洞须完整位于内部且互不接触。")
		queue_redraw(); return
	var id: String = doc.add_feature(tool, draft, "", brush_width if tool in Doc.BOUNDARIES else -1)
	if id.is_empty(): message.emit("未能创建：请检查自交边界、重复点和图层锁定。")
	else:
		draft.clear()
		select_feature(id)
		message.emit("已创建“%s”。可在右侧编辑通行性质。" % Doc.NAMES[tool])
	queue_redraw()

func select_feature(id: String) -> void:
	if not visual_curve_feature_id.is_empty() and id != visual_curve_feature_id: set_tool("select")
	active_ring=-1
	selected = id
	selection_ids = [] if id.is_empty() else [id]
	selection_changed.emit(id)
	_redraw_interaction()

func request_select_feature(id: String) -> bool:
	if id != selected and selection_guard.is_valid() and not selection_guard.call("feature",id): return false
	select_feature(id)
	return true

func request_select_many(ids: Array) -> bool:
	var next := str(ids[-1]) if not ids.is_empty() else ""
	if (next != selected or ids != selection_ids) and selection_guard.is_valid() and not selection_guard.call("many",ids.duplicate()): return false
	select_many(ids)
	return true

func select_art_instance(id: String) -> void:
	selected_art_id = id
	art_selection_changed.emit(id)
	queue_redraw()

func request_select_art_instance(id: String) -> bool:
	if id != selected_art_id and selection_guard.is_valid() and not selection_guard.call("art",id): return false
	select_art_instance(id)
	return true

func _hit_art(p: Vector2) -> String:
	if not has_art(): return ""
	if depth_enabled():
		var entries:=spatial_query(Rect2(p-Vector2.ONE,Vector2.ONE*2),true)
		entries.sort_custom(func(a,b):
			if a.paint_plane!=b.paint_plane: return a.paint_plane<b.paint_plane
			return Spatial.before(a,b) if a.paint_plane==2 else a.paint_index<b.paint_index)
		entries.reverse()
		for entry in entries:
			if not entry.rect.has_point(p): continue
			var image: Image=art.hit_image(entry.asset)
			var uv: Vector2=(p-entry.rect.position)/entry.rect.size
			if entry.flip_h: uv.x=1.0-uv.x
			if image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1)).a*entry.get("opacity",1.0)<.2: continue
			return entry.get("instance_id","")
		return ""
	var instances: Array = doc.data.get("presentation", {}).get("instances", [])
	for i in range(instances.size()-1, -1, -1):
		var item: Dictionary = instances[i]
		var at := Vector2(item.position[0], item.position[1])
		if art.instance_rect(item.asset, at, item.scale).has_point(p): return item.id
	return ""

func _record_art_stroke_point(p: Vector2) -> void:
	if tool == "art_erase":
		var hit := _hit_art(p)
		if not hit.is_empty() and hit not in art_erase_ids: art_erase_ids.append(hit)
		return
	var point := snap_point(p)
	var key := "tree_grove" if brush_asset == "mixed_forest" else brush_asset
	var descriptor := ArtCatalog.descriptor(key)
	if descriptor.is_empty(): return
	var spacing := maxf(8, float(descriptor.width) * brush_scale * 0.58)
	if not art_stroke_points.is_empty() and art_stroke_points[-1].distance_to(point) < spacing: return
	if art_stroke_points.size() < 500: art_stroke_points.append(point)
	queue_redraw()

func _stamp_asset(point: Vector2) -> String:
	if brush_asset != "mixed_forest": return brush_asset
	var variants: Array = ArtCatalog.group("forest").filter(func(key): return ArtCatalog.bundle_contains(art.bundle_id, ArtCatalog.asset_bundle(key)))
	return "tree_grove" if variants.is_empty() else str(variants[posmod(hash(str(point, 0)), variants.size())])

func _place_single_art(p: Vector2) -> void:
	if not has_art():
		message.emit("请先切换到手绘淡彩的成图视图，再放置素材。")
		return
	var point := snap_point(p)
	if not _inside(point): return
	var key := _stamp_asset(point)
	if depth_enabled() and not placement_conflicts(key, art.instance_rect(key, point, brush_scale)).is_empty():
		message.emit("这里与城市占地重叠，请换一个落点。")
		return
	var result: Dictionary = doc.apply_art_stroke([{"asset":key,"position":[point.x,point.y],"scale":brush_scale}])
	if result.ok:
		select_art_instance(result.ids[0])
		message.emit("已放置“%s”；继续左键点放，右键 / Esc 退出后拖动部件，撤销可回退。" % ArtCatalog.label(key))
	else: message.emit(result.error)

func _finish_art_stroke() -> void:
	art_stroke_active = false
	var stamps: Array = []
	var variants: Array = ArtCatalog.group("forest")
	for i in range(art_stroke_points.size()):
		var point: Vector2 = art_stroke_points[i]
		var asset := brush_asset
		if asset == "mixed_forest" and not variants.is_empty(): asset = variants[posmod(hash(str(point, i)), variants.size())]
		stamps.append({"asset":asset,"position":[point.x,point.y],"scale":brush_scale})
	if depth_enabled():
		var original_count:=stamps.size()
		stamps=stamps.filter(func(stamp): return placement_conflicts(stamp.asset,art.instance_rect(stamp.asset,Vector2(stamp.position[0],stamp.position[1]),stamp.scale)).is_empty())
		if stamps.size()<original_count: message.emit("已避让城市占地：跳过 %d 件部件。" % (original_count-stamps.size()))
		if stamps.is_empty() and art_erase_ids.is_empty():
			art_stroke_points.clear(); queue_redraw(); return
	var result: Dictionary = doc.apply_art_stroke(stamps, art_erase_ids, "brush_%s" % Time.get_ticks_usec())
	if result.ok:
		if not result.ids.is_empty(): select_art_instance(result.ids[-1])
		elif tool == "art_erase": select_art_instance("")
	else:
		message.emit(result.error)
	art_stroke_points.clear()
	art_erase_ids.clear()
	queue_redraw()

func freeze_selected_scatter() -> Dictionary:
	var f: Dictionary = doc.find_feature(selected)
	if f.is_empty() or f.kind not in ["mountain", "hills", "forest"]: return {"ok":false,"error":"请选择高山、丘陵或林地区域。"}
	var region := visible_world_rect()
	if not region.has_area(): return {"ok":false,"error":"当前视野没有地图。"}
	var candidates := _scatter_candidates(f, Doc.packed(f.points), region)
	var stamps: Array = []
	for candidate in candidates:
		stamps.append({"asset":candidate.asset,"position":[candidate.position.x,candidate.position.y],"scale":candidate.scale})
	return doc.freeze_art_region(f.id, region, stamps)

func regenerate_selected_scatter(seed_value: int) -> Dictionary:
	var f: Dictionary = doc.find_feature(selected)
	if f.is_empty() or f.kind not in ["mountain", "hills", "forest"]: return {"ok":false,"error":"请选择高山、丘陵或林地区域。"}
	return doc.regenerate_art_region(f.id, visible_world_rect(), seed_value)

func _gui_input(event: InputEvent) -> void:
	if doc == null or export_mode: return
	if water_input.input(self,event): return
	if event is InputEventMouseButton:
		pointer = world_at(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom = clampf(zoom*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),0.002,6.0)
			pan = event.position-pointer*zoom
			_camera_motion_only=true
			camera_settle.start()
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			_camera_motion_only=false
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if tool == "art_stamp":
				set_tool("art_select")
				message.emit("已退出点放；现在可选中并拖动美术部件。")
				accept_event()
				return
			if tool == "visual_curve":
				set_tool("select")
				message.emit("已退出表现线编辑；未提交的控制点已丢弃。")
				accept_event()
				return
			draft.clear()
			dragging = false
			stroke_active = false
			reference_drag = false
			ghost.clear()
			drag_preview_revision+=1
			art_dragging = false
			art_stroke_active = false
			art_stroke_points.clear()
			art_erase_ids.clear()
			queue_redraw()
			return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		grab_focus()
		if not event.pressed and hand_panning:
			panning = false
			hand_panning = false
			_camera_motion_only=false
			queue_redraw()
			accept_event()
			return
		if event.pressed and (tool == "hand" or Input.is_key_pressed(KEY_SPACE)):
			panning = true
			hand_panning = true
			_camera_motion_only=false
			queue_redraw()
			accept_event()
			return
		if not event.pressed:
			var filled_preview: bool=not ghost.is_empty() and not drag_outline_only
			if tool == "visual_curve" and visual_curve_drag_index >= 0:
				visual_curve_drag_index = -1
				var f: Dictionary = doc.find_feature(visual_curve_feature_id)
				if f.get("visual",{}).has(visual_curve_kind): commit_visual_curve()
				accept_event()
				return
			if art_stroke_active:
				_finish_art_stroke()
				accept_event()
				return
			if art_dragging:
				if not art_ghost.is_equal_approx(art_drag_start):
					var result: Dictionary=doc.edit_art_group(selected_art_id,art_group_mode,"move",art_ghost-art_drag_start)
					if not result.ok: message.emit(result.error)
				art_dragging = false
				art_drag_ids.clear()
				if depth_enabled():
					for issue in Spatial.conflict_pairs(spatial_entries()):
						if issue.instance_id==selected_art_id: message.emit(issue.message); break
				queue_redraw()
				return
			if reference_drag:
				doc.update_reference({"position":[reference_ghost.x,reference_ghost.y]},active_reference)
				reference_drag = false
			if stroke_active:
				stroke_active = false
				var points := Doc.simplify_stroke(Doc.packed(draft),simplify_pixels/zoom)
				draft.clear()
				for p in points: draft.append([p.x,p.y])
				finish_shape()
			elif dragging and not ghost.is_empty():
				var moved: bool
				if drag_ring >= 0: moved=doc.update_ring(selected,drag_ring,ghost)
				elif drag_vertex < 0: moved = doc.translate_features(selection_ids,Vector2(ghost[0][0]-drag_points[0][0],ghost[0][1]-drag_points[0][1]))
				else: moved = doc.update_feature(selected, {"points":ghost})
				if not moved: message.emit("移动未应用：对象受保护、图层锁定或边界无效。")
			dragging = false
			ghost.clear()
			drag_preview_revision+=1
			if tool=="select":
				if filled_preview:queue_redraw()
				_redraw_interaction()
				return
			queue_redraw()
			return
		if tool == "reference":
			var ref: Dictionary = doc.get_reference(active_reference)
			if ref.locked: message.emit("参考图已锁定，请在参考图设置中解锁。")
			elif not ref.path.is_empty():
				reference_drag = true
				drag_origin = pointer
				reference_origin = Vector2(ref.position[0],ref.position[1])
				reference_ghost = reference_origin
			return
		if not _inside(pointer): return
		if tool in ["select","art_select","art_stamp","art_place","art_erase","insert_vertex","remove_vertex"] and selection_guard.is_valid() and not selection_guard.call("canvas_edit",tool):
			accept_event(); return
		if tool == "art_stamp":
			_place_single_art(pointer)
			accept_event()
			return
		if tool == "visual_curve":
			if visual_curve_feature_id.is_empty(): return
			var point := snap_point(pointer)
			if event.alt_pressed:
				var at := _visual_curve_point_at(point)
				if at < 0 or not remove_visual_curve_point(at): message.emit("请选择可删除的中间控制点。")
				elif doc.find_feature(visual_curve_feature_id).get("visual",{}).has(visual_curve_kind): commit_visual_curve()
			elif event.shift_pressed:
				var at := _visual_curve_segment_at(point)
				if at < 0 or not insert_visual_curve_point(at,point): message.emit("请点击表现线段附近添加控制点。")
				elif doc.find_feature(visual_curve_feature_id).get("visual",{}).has(visual_curve_kind): commit_visual_curve()
			else:
				var at := _visual_curve_point_at(point)
				if at >= 0:
					visual_curve_active_index = at
					visual_curve_drag_index = at
				elif add_visual_curve_point(point):
					if doc.find_feature(visual_curve_feature_id).get("visual",{}).has(visual_curve_kind): commit_visual_curve()
				else: message.emit("水域表现线点必须留在所选水域；谷道请用 Shift 在源线之间加点。")
			queue_redraw()
			accept_event()
			return
		if tool in ["art_place", "art_erase"]:
			art_stroke_active = true
			art_stroke_points.clear()
			art_erase_ids.clear()
			_record_art_stroke_point(pointer)
		elif tool == "art_select":
			var hit_id := _hit_art(pointer)
			if not request_select_art_instance(hit_id): accept_event(); return
			if not hit_id.is_empty():
				art_drag_ids=doc.art_group_ids(hit_id,art_group_mode)
				for id in art_drag_ids:
					if doc.find_art_instance(id).locked:
						message.emit("所选范围含锁定部件，可在右侧解锁。")
						art_drag_ids.clear(); return
				art_dragging = true
				art_drag_origin = pointer
				var instance: Dictionary = doc.find_art_instance(hit_id)
				art_drag_start = Vector2(instance.position[0], instance.position[1])
				art_ghost = art_drag_start
		elif tool in ["insert_vertex","remove_vertex"]:
			_edit_vertex(pointer,tool == "insert_vertex")
		elif tool in ["start","end"]:
			if tool == "start": start_point = pointer
			else: end_point = pointer
			route.clear()
			endpoint_chosen.emit(pointer, tool == "start")
		elif tool == "select":
			if event.ctrl_pressed:
				var hit := _hit(pointer)
				var ids := selection_ids.duplicate()
				if hit in ids: ids.erase(hit)
				elif not hit.is_empty(): ids.append(hit)
				if not request_select_many(ids): accept_event(); return
				accept_event()
				return
			drag_vertex = _vertex_at(pointer)
			if selection_ids.size() > 1: drag_vertex = -1
			drag_ring = active_ring if drag_vertex >= 0 else -1
			if drag_vertex < 0:
				var hit:=_hit(pointer)
				if not hit in selection_ids:
					if not request_select_feature(hit): accept_event(); return
			if not selected.is_empty():
				var f: Dictionary = doc.find_feature(selected)
				if not doc.layer(f.layer).locked:
					dragging = true
					drag_outline_only = _dense_selection()
					drag_origin = pointer
					drag_points = (f.holes[drag_ring] if drag_ring >= 0 else f.points).duplicate(true)
			_redraw_interaction()
			accept_event()
			return
		elif tool in Doc.POLYGONS or tool in Doc.LINES or tool == "hole":
			pointer = snap_point(pointer)
			if freehand:
				draft = [[pointer.x,pointer.y]]
				stroke_active = true
			elif event.double_click:
				finish_shape()
			elif draft.is_empty() or Vector2(draft[-1][0],draft[-1][1]).distance_to(pointer) > 1:
				draft.append([pointer.x,pointer.y])
		else:
			pointer = snap_point(pointer)
			var id: String = doc.add_feature(tool,[[pointer.x,pointer.y]],"")
			if id.is_empty(): message.emit("当前图层锁定，无法放置。")
			else: select_feature(id)
		queue_redraw()
		accept_event()
	if event is InputEventMouseMotion:
		pointer = world_at(event.position)
		pointer_changed.emit(pointer,zoom)
		if panning:
			pan += event.relative
			_camera_motion_only=true
		elif tool == "visual_curve" and visual_curve_drag_index >= 0 and _inside(pointer):
			move_visual_curve_point(visual_curve_drag_index,snap_point(pointer))
		elif reference_drag: reference_ghost = reference_origin+pointer-drag_origin
		elif art_dragging:
			art_ghost = (art_drag_start + pointer - art_drag_origin).clamp(Vector2.ZERO, Vector2(doc.data.canvas_size[0], doc.data.canvas_size[1]))
		elif art_stroke_active and _inside(pointer):
			_record_art_stroke_point(pointer)
		elif stroke_active:
			pointer = snap_point(pointer)
			if draft.size() < 4096 and Vector2(draft[-1][0],draft[-1][1]).distance_to(pointer)*zoom >= 3:
				draft.append([pointer.x,pointer.y])
		elif dragging:
			if ghost.is_empty() and pointer.distance_to(drag_origin)*zoom<4:
				return
			drag_preview_revision+=1
			ghost = drag_points.duplicate(true)
			if drag_vertex >= 0:
				pointer = snap_point(pointer)
				ghost[drag_vertex] = [clampf(pointer.x,0,doc.data.canvas_size[0]),clampf(pointer.y,0,doc.data.canvas_size[1])]
			else:
				var delta := snap_point(Vector2(drag_points[0][0],drag_points[0][1])+pointer-drag_origin)-Vector2(drag_points[0][0],drag_points[0][1])
				for p in drag_points:
					delta.x = clampf(delta.x,-p[0],doc.data.canvas_size[0]-p[0])
					delta.y = clampf(delta.y,-p[1],doc.data.canvas_size[1]-p[1])
				for p in ghost:
					p[0] += delta.x
					p[1] += delta.y
			if drag_outline_only:
				_redraw_interaction()
				return
		if panning or reference_drag or art_dragging or art_stroke_active or stroke_active or dragging or not draft.is_empty() or tool == "visual_curve":
			queue_redraw()
		else: _redraw_interaction()
	if event is InputEventKey and event.pressed and not event.echo:
		if tool=="select" and event.keycode==KEY_ESCAPE and dragging:
			var filled_preview: bool=not ghost.is_empty() and not drag_outline_only
			dragging=false;ghost.clear();drag_preview_revision+=1
			if filled_preview:queue_redraw()
			_redraw_interaction();accept_event();return
		if tool == "art_stamp" and event.keycode == KEY_ESCAPE:
			set_tool("art_select")
			message.emit("已退出点放；现在可选中并拖动美术部件。")
			accept_event()
			return
		if tool == "visual_curve" and event.keycode == KEY_ENTER:
			commit_visual_curve()
			accept_event()
			return
		if tool == "visual_curve" and event.keycode == KEY_ESCAPE:
			set_tool("select")
			message.emit("已退出表现线编辑；未提交的控制点已丢弃。")
			accept_event()
			return
		if event.keycode == KEY_ENTER and not draft.is_empty(): finish_shape(); accept_event()
		if event.keycode == KEY_ESCAPE: drag_preview_revision+=1; draft.clear(); ghost.clear(); dragging=false; stroke_active=false; reference_drag=false; art_dragging=false; art_stroke_active=false; art_stroke_points.clear(); art_erase_ids.clear(); queue_redraw(); accept_event()
		if event.keycode == KEY_DELETE and tool == "art_select" and not selected_art_id.is_empty():
			if selection_guard.is_valid() and not selection_guard.call("canvas_edit","delete"): accept_event(); return
			var result: Dictionary=doc.edit_art_group(selected_art_id,art_group_mode,"delete")
			if not result.ok: message.emit(result.error)
			accept_event()
			return
		if event.keycode == KEY_DELETE and not selected.is_empty():
			if not doc.remove_feature(selected): message.emit("对象已锁定或仍被通道引用；请先解除绑定。")
			accept_event()

func _edit_vertex(p: Vector2, insert: bool) -> void:
	var f: Dictionary = doc.find_feature(selected)
	if f.is_empty() or not f.kind in Doc.POLYGONS+Doc.LINES:
		message.emit("请先选择一个区域或线条。")
		return
	if not insert:
		var index := _vertex_at(p)
		if index < 0 or not doc.remove_vertex(selected,index,active_ring): message.emit("请点选顶点；轮廓至少保留 3 点，线至少保留 2 点，且不得交叉。")
		return
	var nearest := 16.0/zoom
	var at := -1
	var projected := p
	for ring in range(-1,f.holes.size()):
		var pts:=Doc.packed(f.points if ring == -1 else f.holes[ring])
		for i in range(pts.size() if f.kind in Doc.POLYGONS else pts.size()-1):
			var candidate := Geometry2D.get_closest_point_to_segment(p,pts[i],pts[(i+1)%pts.size()])
			if candidate.distance_to(p) < nearest:
				nearest = candidate.distance_to(p); at = i+1; projected = candidate; active_ring=ring
	if at < 0 or not doc.insert_vertex(selected,at,snap_point(projected),active_ring): message.emit("请点击所选边线附近，且不能产生自交边界。")

func _vertex_at(p: Vector2) -> int:
	var f: Dictionary = doc.find_feature(selected)
	if f.is_empty() or f.points.size() == 1: return -1
	var closest:=9.0; var index:=-1
	for handle in selection_handles():
		if handle.id != selected:continue
		var distance: float=handle.screen.distance_to(p*zoom+pan)
		if distance<closest: closest=distance; index=handle.index; active_ring=handle.ring
	return index

func _preview_feature(f: Dictionary, overlay: bool=false) -> Dictionary:
	if ghost.is_empty() or not f.id in selection_ids or (drag_outline_only and not overlay): return f
	var copy: Dictionary=f.duplicate(true)
	if f.id == selected and drag_ring >= 0:
		if drag_ring < copy.holes.size(): copy.holes[drag_ring]=ghost
		return copy
	if drag_vertex >= 0:
		if f.id == selected: copy.points=ghost
		return copy
	var offset:=Vector2(ghost[0][0]-drag_points[0][0],ghost[0][1]-drag_points[0][1])
	for ring in [copy.points]+copy.holes:
		for p in ring: p[0]+=offset.x; p[1]+=offset.y
	if copy.get("visual",{}).has("ribbon"):
		for p in copy.visual.ribbon.points: p[0]+=offset.x;p[1]+=offset.y
	return copy

func _hit(p: Vector2) -> String:
	if show_site_anchors and not export_mode and not runtime_mode and doc.layer("sites").visible and not doc.layer("sites").locked:
		for f in doc.data.features:
			if f.get("visual",{}).get("anchor_only",false) and Vector2(f.points[0][0],f.points[0][1]).distance_to(p)<12/zoom:return f.id
	for li in range(doc.data.layers.size()-1,-1,-1):
		var lid: String = doc.data.layers[li].id
		if not doc.layer(lid).visible: continue
		for i in range(doc.data.features.size()-1,-1,-1):
			var f: Dictionary = doc.data.features[i]
			if f.layer != lid: continue
			if f.get("visual",{}).get("anchor_only",false):continue
			if (f.kind=="country_border" and not show_country_borders) or (f.kind=="province_border" and not show_dao_borders):continue
			if f.kind=="prefecture":
				if not show_prefectures: continue
				# Administrative areas are picked at their edges, leaving rivers editable.
				var rings: Array=[f.points]+f.holes
				for ring in rings:
					var outline:=Doc.packed(ring)
					for j in range(outline.size()):
						if Geometry2D.get_closest_point_to_segment(p,outline[j],outline[(j+1)%outline.size()]).distance_to(p)<=6/zoom: return f.id
				continue
			if f.kind in Doc.POLYGONS+Doc.LINES and feature_bounds.has(f.id) and not feature_bounds[f.id].grow(10/zoom).has_point(p):continue
			var pts := Doc.packed(f.points)
			if f.kind in Doc.POLYGONS and Geometry.contains(f,p): return f.id
			if f.kind in Doc.LINES:
				for j in range(pts.size()-1):
					if Geometry2D.get_closest_point_to_segment(p,pts[j],pts[j+1]).distance_to(p) <= maxf(f.width*0.5,10/zoom): return f.id
			elif has_art() and f.kind in ["city","pass"] and art.site_rect(f,pts[0]).has_point(p): return f.id
			elif not f.kind in Doc.POLYGONS and p.distance_to(pts[0]) < 30*f.scale + 10/zoom: return f.id
	return ""

func _draw() -> void:
	_redraw_interaction()
	if not transparent_page: draw_rect(Rect2(Vector2.ZERO,size),Color("222c2c"))
	if not is_instance_valid(render_surface): return
	if doc==null:
		render_surface.hide()
		if map_display!=null: map_display.hide()
		return
	render_surface.show()
	if map_display!=null: map_display.show()
	var view:=visible_world_rect()
	var ratio:=zoom/_camera_cache_zoom
	var options: Array=[runtime_label_tier,runtime_camera_zoom,show_country_borders,show_dao_borders,show_dao_labels,dao_label_screen_scale,show_site_anchors,show_prefectures,show_factions,view_mode,tool,selected_art_id,art_group_mode,show_footprints,show_rules,show_grid,grid_step,export_layer,transparent_page,include_labels,include_auxiliary,export_debug,show_bound_sites,show_site_labels,show_author_paths,filter_game_sites,visible_bound_instance_sites.duplicate(),route.duplicate(),start_point,end_point,check_scope,active_reference]
	var editing: bool=art_dragging or art_stroke_active or stroke_active or reference_drag or not draft.is_empty() or (not ghost.is_empty() and not drag_outline_only) or tool=="visual_curve"
	var reusable: bool=not export_mode and not editing and _camera_motion_only and _camera_cache_valid and options==_camera_cache_options and _camera_cache_revision==doc.revision and _camera_cache_rect.encloses(view) and ratio>=.67 and ratio<=1.5
	if reusable and (not panning or _camera_cache_panning):
		render_surface.position=pan-_camera_cache_pan*ratio
		render_surface.scale=Vector2.ONE*ratio
		if map_display!=null:
			map_display.position=render_surface.position-Vector2.ONE*CACHE_MARGIN*ratio
			map_display.scale=Vector2.ONE*ratio
	else:
		_camera_cache_pan=pan;_camera_cache_zoom=zoom;_camera_cache_size=size
		_camera_cache_revision=doc.revision;_camera_cache_panning=panning
		_camera_cache_options=options
		_camera_cache_rect=view
		if not export_mode and (panning or not camera_settle.is_stopped()):
			_camera_cache_rect=view.grow(384/zoom).intersection(Rect2(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])))
		render_surface.position=Vector2.ZERO;render_surface.scale=Vector2.ONE
		_camera_cache_valid=true
		if map_display!=null:
			map_viewport.size=Vector2i(size.ceil())+Vector2i.ONE*CACHE_MARGIN*2
			map_display.size=Vector2(map_viewport.size)
			map_display.position=-Vector2.ONE*CACHE_MARGIN;map_display.scale=Vector2.ONE
			map_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		render_surface.queue_redraw()
	_camera_motion_only=false

func _render_map() -> void:
	map_command_rebuilds+=1
	_drawing_surface=true
	# Dense edits stay in the interaction overlay; filled previews invalidate details.
	var previewing: bool=(not ghost.is_empty() and not drag_outline_only) or tool == "visual_curve"
	if previewing or _detail_preview:
		_detail_cache.clear(); _surface_cells.clear(); _surface_batches.clear(); _water_query_cache.clear(); _label_water_cache.clear()
		water_join.revision=-1
	if previewing or _detail_preview:_water_prepared_key.clear()
	_detail_preview=previewing
	_frame_art_entries=spatial_query(visible_world_rect().grow(10),true) if has_art() else []
	_depth_items.clear()
	_depth_labels.clear()
	if runtime_label_tier.is_empty():label_draw_records.clear()
	anchor_draw_records.clear()
	if runtime_label_tier.is_empty():_label_rects.clear()
	if doc == null:
		_drawing_surface=false
		return
	render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
	var extent := Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])
	var water_features: Array=doc.data.features.filter(func(f):return f.kind!="water" or doc.layer(f.layer).visible)
	if previewing: water_features=water_features.map(func(f):return _preview_feature(f))
	water_join.prepare(water_features,geometry_revision)
	# Prepare complete river display geometry once at map/layer load. Camera
	# movement must never pay polygon unions for a newly revealed river.
	var water_key: Array=[geometry_revision,has_art(),view_mode]
	if not previewing and view_mode!="structure" and water_key!=_water_prepared_key:
		for water in water_join.waters:
			if water_join.natural(water):_prepare_natural_water(water)
		_water_prepared_key=water_key
	if runtime_mode and not runtime_label_tier.is_empty() and not depth_enabled():
		_build_runtime_draw_chunks()
		_drawing_surface=false
		return
	_terrain_layers=[]
	var cache_terrain: bool=not export_mode and not previewing and not reference_drag
	for layer in doc.data.layers:
		if layer.id=="sites":break
		# Labels need the current art/depth layout; use the original painter path
		# when the user moves their layer ahead of the sites layer.
		if layer.id=="notes":cache_terrain=false
		_terrain_layers.append(layer.id)
	if art_dragging:
		for item in doc.data.presentation.instances:
			if item.plane=="ground" and (item.id==selected_art_id or item.id in art_drag_ids):cache_terrain=false;break
	terrain_surface.visible=cache_terrain
	if cache_terrain:
		var ground: Array=doc.data.presentation.instances.filter(func(item):return item.plane=="ground")
		var key: Array=[geometry_revision,pan,zoom,size,_camera_cache_rect,show_country_borders,show_dao_borders,show_prefectures,show_factions,view_mode,export_layer,transparent_page,include_auxiliary,show_author_paths,show_rules,show_bound_sites,filter_game_sites,visible_bound_instance_sites,ArtCatalog.generation,ground]
		if key!=_terrain_cache_key:
			_terrain_cache_key=key.duplicate(true)
			terrain_surface.queue_redraw()
		# Procedural mountain/forest sprites participate in foreground depth order.
		# Collect them before drawing labels, even while geography commands are reused.
		if depth_enabled():
			if key!=_terrain_scatter_key:
				for lid in _terrain_layers:_render_feature_layer(lid,true)
				_terrain_scatter_items=_depth_items.duplicate()
				_terrain_scatter_key=key.duplicate(true)
			else:_depth_items.append_array(_terrain_scatter_items)
	else:
		_terrain_cache_key.clear()
		_draw_map_background()
	for layer in doc.data.layers:
		var lid: String=layer.id
		if lid=="sites":_draw_art_instances("terrain")
		if cache_terrain and lid in _terrain_layers:continue
		_render_feature_layer(lid)
	if depth_enabled(): _draw_depth_items()
	_draw_art_instances("foreground")
	if depth_enabled():
		_depth_by_id.clear(); _label_bodies.clear()
		for body in _depth_items:
			_depth_by_id[body.id]=body
			var h: float=body.body_rect.size.y*zoom
			if (body.group in ["city","pass"] and h>=8) or (body.group=="forest" and zoom>=1.25 and h>=20): _label_bodies.append(body)
		_drawing_depth_labels=true
		_depth_labels.sort_custom(func(a,b):return _label_priority(a)>_label_priority(b))
		for feature in _depth_labels: _draw_feature(feature,Doc.packed(feature.points))
		_drawing_depth_labels=false
		if (show_footprints or art_dragging or art_stroke_active) and not export_mode: _draw_footprints()
	_draw_reference(true)
	if export_debug: _draw_authoring_overlay()
	if not export_mode:
		if show_rules or view_mode == "overlay": _draw_authoring_overlay()
		if show_grid and grid_step*zoom >= 8:
			for x in range(0,int(extent.x)+1,int(grid_step)):
				render_surface.draw_line(Vector2(x,0),Vector2(x,extent.y),Color(0.2,0.3,0.25,0.18),1/zoom)
			for y in range(0,int(extent.y)+1,int(grid_step)):
				render_surface.draw_line(Vector2(0,y),Vector2(extent.x,y),Color(0.2,0.3,0.25,0.18),1/zoom)
		if route.size() > 1:
			render_surface.draw_polyline(route,Color("fff8ce"),7/zoom,true)
			render_surface.draw_polyline(route,Color("ba623b"),3/zoom,true)
		if check_scope.has_area(): render_surface.draw_rect(check_scope,Color("eab64a"),false,2/zoom)
		_marker(start_point,Color("327f63"),"起")
		_marker(end_point,Color("b0523c"),"终")
		if not selected_art_id.is_empty() and has_art():
			for id in doc.art_group_ids(selected_art_id,art_group_mode):
				var instance: Dictionary = doc.find_art_instance(id)
				var p: Vector2 = _art_preview_position(instance)
				render_surface.draw_rect(art.instance_rect(instance.asset, p, instance.scale), Color("db9851"), false, 2/zoom)
		if art_stroke_active and tool == "art_place":
			for i in range(art_stroke_points.size()):
				var key := brush_asset
				if key == "mixed_forest":
					var variants: Array = ArtCatalog.group("forest")
					if not variants.is_empty(): key = variants[posmod(hash(str(art_stroke_points[i], i)), variants.size())]
				var tex: Texture2D = art.texture(key)
				if tex != null: render_surface.draw_texture_rect(tex, art.instance_rect(key, art_stroke_points[i], brush_scale), false, Color(1,1,1,0.68))
		if tool == "visual_curve" and not visual_curve_feature_id.is_empty(): _draw_visual_curve_editor()
		if not draft.is_empty() and tool not in WaterBrush.TOOLS:
			var pts := Doc.packed(draft)
			pts.append(pointer)
			render_surface.draw_polyline(pts,Color("956440"),2/zoom,true)
	if not transparent_page: render_surface.draw_rect(Rect2(Vector2.ZERO,extent),Color("867e63"),false,2/zoom)
	render_surface.draw_set_transform(Vector2.ZERO)

	_drawing_surface=false

func _render_feature_layer(lid: String,scatter_only: bool=false) -> void:
	if not doc.layer(lid).visible:return
	var features: Array=_layer_features.get(lid,[])
	if lid=="water" and view_mode!="structure":features=water_join.ordered.filter(func(f):return f.layer==lid)
	for f in features:
		if f.kind=="water" and not WaterBrush.visible(f) and view_mode!="structure": continue
		if not show_bound_sites and not f.domain_id.is_empty(): continue
		if not show_author_paths and f.kind in Doc.PASSAGES: continue
		if export_layer == "terrain" and f.kind in ["city", "pass", "ford", "label"]: continue
		if export_layer == "sites" and f.kind not in ["city", "pass", "ford"]: continue
		if export_layer == "labels" and f.kind not in ["city", "pass", "ford", "label"]: continue
		if has_art() and f.get("visual", {}).get("auxiliary", false) and not include_auxiliary: continue
		if has_art() and not f.get("visual", {}).get("visible", true): continue
		if not _geometry_preview(f.id) and not feature_bounds.get(f.id,Rect2()).intersects(visible_world_rect()): continue
		var rendered:=_preview_feature(f)
		if scatter_only:
			if f.kind in ["mountain","hills","forest"]:_art_symbols(rendered,_packed_features[f.id])
			continue
		_draw_feature(rendered,Doc.packed(rendered.points) if _geometry_preview(f.id) else _packed_features.get(f.id,Doc.packed([])))

func _build_runtime_draw_chunks() -> void:
	# One CanvasItem for the entire atlas defeats Godot's offscreen culling.
	# Retain the original painter order, but give each feature its own bounds.
	for chunk in runtime_draw_chunks:
		chunk.hide();chunk.get_parent().remove_child(chunk);chunk.queue_free()
	runtime_draw_chunks.clear()
	terrain_surface.hide()
	_add_runtime_draw_chunk("background")
	for layer in doc.data.layers:
		if layer.id=="sites":_add_runtime_draw_chunk("terrain_art")
		if not layer.visible:continue
		var features: Array=_layer_features.get(layer.id,[])
		if layer.id=="water" and view_mode!="structure":features=water_join.ordered.filter(func(f):return f.layer==layer.id)
		for f in features:
			if f.kind=="label" or f.get("visual",{}).get("anchor_only",false):continue
			if f.kind=="water" and not WaterBrush.visible(f) and view_mode!="structure":continue
			if not show_bound_sites and not f.domain_id.is_empty():continue
			if not show_author_paths and f.kind in Doc.PASSAGES:continue
			if has_art() and f.get("visual",{}).get("auxiliary",false) and not include_auxiliary:continue
			if not f.get("visual",{}).get("visible",true):continue
			_add_runtime_draw_chunk("feature",f)
	_add_runtime_draw_chunk("foreground")

func _add_runtime_draw_chunk(kind: String, feature: Dictionary = {}) -> void:
	var chunk:=Node2D.new()
	chunk.set_meta("feature_kind",feature.get("kind",kind))
	render_surface.add_child(chunk)
	runtime_draw_chunks.append(chunk)
	chunk.draw.connect(_render_runtime_chunk.bind(chunk,kind,feature))

func _render_runtime_chunk(chunk: Node2D, kind: String, feature: Dictionary) -> void:
	var original:=render_surface
	render_surface=chunk
	_drawing_surface=true
	chunk.draw_set_transform(pan,0,Vector2.ONE*zoom)
	match kind:
		"background":_draw_map_background()
		"terrain_art":_draw_art_instances("terrain")
		"feature":_draw_feature(feature,_packed_features.get(feature.id,Doc.packed([])))
		"foreground":
			_draw_art_instances("foreground")
			_draw_reference(true)
			if not transparent_page:chunk.draw_rect(Rect2(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])),Color("867e63"),false,2/zoom)
	chunk.draw_set_transform(Vector2.ZERO)
	_drawing_surface=false
	render_surface=original

func _draw_map_background() -> void:
	render_surface.draw_set_transform(Vector2.ZERO)
	if not transparent_page:render_surface.draw_rect(Rect2(Vector2.ZERO,size),Color("222c2c"))
	render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
	var extent:=Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])
	if not transparent_page:render_surface.draw_rect(Rect2(Vector2.ZERO,extent),ART_PAPER if has_art() else PAPER)
	_draw_reference(false)
	_draw_art_instances("ground")

func _render_terrain() -> void:
	terrain_command_rebuilds+=1
	var foreground:=render_surface
	render_surface=terrain_surface
	_drawing_surface=true
	_draw_map_background()
	for lid in _terrain_layers:_render_feature_layer(lid)
	render_surface.draw_set_transform(Vector2.ZERO)
	_drawing_surface=false
	render_surface=foreground

func _draw_visual_curve_editor() -> void:
	var f: Dictionary = doc.find_feature(visual_curve_feature_id)
	if f.is_empty(): return
	if visual_curve_kind == "ribbon":
		for i in range(visual_curve_points.size()-1):
			var a := Vector2(visual_curve_points[i][0],visual_curve_points[i][1])
			var b := Vector2(visual_curve_points[i+1][0],visual_curve_points[i+1][1])
			render_surface.draw_line(a,b,Color("e7b866",0.34),(float(visual_curve_widths[i])+float(visual_curve_widths[i+1]))*0.5,true)
	else:
		if visual_curve_points.size() > 1: render_surface.draw_polyline(Doc.packed(visual_curve_points),Color("e7b866",0.4),7,true)
	if visual_curve_kind == "ribbon" and visual_curve_points.size() > 0 and visual_curve_points.size() < 128:
		var tail := Vector2(visual_curve_points[-1][0],visual_curve_points[-1][1])
		if Geometry.contains(f,pointer): render_surface.draw_line(tail,pointer,Color("e7b866",0.35),visual_curve_default_width,true)

func _draw_art_instances(plane: String) -> void:
	if not has_art() or export_layer == "labels": return
	for entry in _frame_art_entries:
		if not entry.has("instance_id") or entry.render_plane != plane: continue
		var group: String=entry.group
		if filter_game_sites:
			var site_id: String=entry.site_id
			if not site_id.is_empty() and not visible_bound_instance_sites.has(site_id): continue
			if site_id.is_empty() and group in ["city","pass"]: continue
		if export_layer == "terrain" and group in ["city","pass"]: continue
		if export_layer == "sites" and group not in ["city","pass"]: continue
		var rect: Rect2=entry.rect
		if not rect.intersects(visible_world_rect().grow(10)): continue
		var tex: Texture2D=art.texture(entry.asset)
		if tex == null: continue
		if depth_enabled() and plane=="terrain" and group!="ground":
			_depth_items.append(entry)
			continue
		var modulation:=Color(1,1,1,float(entry.opacity))
		if entry.flip_h:
			render_surface.draw_set_transform(pan+Vector2(rect.end.x,rect.position.y)*zoom,0,Vector2(-zoom,zoom))
			render_surface.draw_texture_rect(tex,Rect2(Vector2.ZERO,rect.size),false,modulation)
			render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
		else: render_surface.draw_texture_rect(tex,rect,false,modulation)

func depth_enabled() -> bool:
	return has_art() and doc.data.presentation.get("depth_sort",false)

func _art_preview_position(item: Dictionary) -> Vector2:
	var point:=Vector2(item.position[0],item.position[1])
	if art_dragging and (item.id==selected_art_id or item.id in art_drag_ids): return point+art_ghost-art_drag_start
	return point

func _spatial_entry(id: String, asset: String, rect: Rect2, placement: Dictionary = {}, flipped: bool = false, extra: Dictionary = {}) -> Dictionary:
	# A flat game map only draws these rectangles. Pixel-scanned footprints are
	# authoring/depth-sort data and cannot affect this rendering branch.
	if runtime_mode and not depth_enabled():
		var entry: Dictionary={"id":id,"asset":asset,"rect":rect,"body_rect":rect,"placement":placement,"flip_h":flipped,"group":ArtCatalog.descriptor(asset).get("group",""),"depth":0.0,"footprint":PackedVector2Array()}
		entry.merge(extra,true)
		return entry
	var body: Rect2=art.body_rect(asset,rect) if ArtCatalog.descriptor(asset).get("group","") in ["city","mountain","forest"] else rect
	var entry: Dictionary={"id":id,"asset":asset,"rect":rect,"body_rect":body,"placement":placement,"flip_h":flipped,"group":ArtCatalog.descriptor(asset).get("group",""),"depth":Spatial.depth(asset,body,placement),"footprint":Spatial.footprint(asset,body,placement,flipped)}
	entry.merge(extra,true)
	return entry

func _build_spatial_entries() -> Array:
	var entries: Array=[]
	if not has_art(): return entries
	for feature in doc.data.features:
		if feature.get("visual",{}).get("anchor_only",false):continue
		if feature.kind not in ["city","pass"] or not doc.layer(feature.layer).visible or not feature.get("visual",{}).get("visible",true) or feature.get("visual",{}).get("auxiliary",false): continue
		var p:=Vector2(feature.points[0][0],feature.points[0][1])
		entries.append(_spatial_entry(feature.id,ArtCatalog.site_variant(feature),art.site_rect(feature,p),feature.get("visual",{}).get("placement",{}),false,{"feature_id":feature.id,"name":feature.name,"paint_plane":2,"paint_index":0}))
	var paint_index:=0
	for item in doc.data.presentation.instances:
		paint_index+=1
		if item.get("opacity",1.0)<=0: continue
		var p:=Vector2(item.position[0],item.position[1])
		var plane:=0 if item.plane=="ground" else (3 if item.plane=="foreground" else (1 if ArtCatalog.descriptor(item.asset).get("group","")=="ground" else 2))
		entries.append(_spatial_entry(item.id,item.asset,art.instance_rect(item.asset,p,item.scale),item.get("placement",{}),item.get("flip_h",false),{"instance_id":item.id,"paint_plane":plane,"paint_index":paint_index,"opacity":item.get("opacity",1.0),"render_plane":item.plane,"site_id":item.get("site_id","")}))
	return entries

func _ensure_spatial() -> void:
	if not has_art():
		_spatial_cache.clear(); _spatial_valid=false
		return
	if _spatial_valid and _spatial_generation==ArtCatalog.generation: return
	_spatial_generation=ArtCatalog.generation
	_spatial_cache=_build_spatial_entries()
	_spatial_index.build(_spatial_cache.map(func(e):return e.rect if e.footprint.is_empty() else e.rect.merge(Spatial.bounds(e.footprint))))
	_spatial_valid=true

func spatial_query(rect: Rect2, include_ground: bool = false) -> Array:
	_ensure_spatial()
	return _spatial_results(_spatial_index.query(rect),include_ground,rect)

func spatial_entries(include_ground: bool = false) -> Array:
	_ensure_spatial()
	return _spatial_results(range(_spatial_cache.size()),include_ground)

func _spatial_results(indices: Array, include_ground: bool, rect: Rect2 = Rect2()) -> Array:
	var result: Array=[]
	for i in indices:
		var entry: Dictionary=_spatial_cache[i]
		if not include_ground and entry.paint_plane==0: continue
		if art_dragging and (entry.get("instance_id","") in art_drag_ids or entry.get("instance_id","")==selected_art_id): continue
		result.append(entry)
	if art_dragging:
		var moving:=art_drag_ids.duplicate()
		if not selected_art_id.is_empty() and not selected_art_id in moving: moving.append(selected_art_id)
		for id in moving:
			var item: Dictionary=doc.find_art_instance(id)
			if item.is_empty(): continue
			var bounds:=art.instance_rect(item.asset,_art_preview_position(item),item.scale)
			var footprint:=Spatial.footprint(item.asset,art.body_rect(item.asset,bounds),item.get("placement",{}),item.get("flip_h",false))
			if rect.has_area() and not (bounds if footprint.is_empty() else bounds.merge(Spatial.bounds(footprint))).intersects(rect,true): continue
			var plane:=0 if item.plane=="ground" else (3 if item.plane=="foreground" else (1 if ArtCatalog.descriptor(item.asset).get("group","")=="ground" else 2))
			if plane==0 and not include_ground: continue
			result.append(_spatial_entry(id,item.asset,bounds,item.get("placement",{}),item.get("flip_h",false),{"instance_id":id,"paint_plane":plane,"paint_index":doc.data.presentation.instances.find(item)+1,"opacity":item.get("opacity",1.0),"render_plane":item.plane,"site_id":item.get("site_id","")}))
	if art_dragging: result.sort_custom(func(a,b):return a.paint_index<b.paint_index)
	return result

func placement_conflicts(asset: String, rect: Rect2, placement: Dictionary = {}) -> Array:
	if placement.get("allow_overlap",false): return []
	var polygon:=Spatial.footprint(asset,art.body_rect(asset,rect),placement)
	if polygon.is_empty(): return []
	if _placement_generation!=ArtCatalog.generation:
		_placement_entries.clear()
		for f in doc.data.features:
			if f.kind!="city" or f.get("visual",{}).get("auxiliary",false) or not f.get("visual",{}).get("visible",true): continue
			var settings: Dictionary=f.get("visual",{}).get("placement",{})
			if settings.get("allow_overlap",false): continue
			var p:=Vector2(f.points[0][0],f.points[0][1])
			var key:=ArtCatalog.site_variant(f)
			_placement_entries.append({"id":f.id,"footprint":Spatial.footprint(key,art.body_rect(key,art.site_rect(f,p)),settings)})
		_placement_index.build(_placement_entries.map(func(e):return Spatial.bounds(e.footprint)))
		_placement_generation=ArtCatalog.generation
	var conflicts: Array=[]
	for i in _placement_index.query(Spatial.bounds(polygon)):
		var entry: Dictionary=_placement_entries[i]
		if Spatial.overlaps(polygon,entry.footprint): conflicts.append(entry.id)
	return conflicts

func _draw_depth_items() -> void:
	var order_input: Array=_depth_items.map(func(e):return [e.id,e.depth])
	if order_input != _depth_order_input:
		_depth_order_input=order_input
		_depth_order=range(_depth_items.size())
		_depth_order.sort_custom(func(a,b):return Spatial.before(_depth_items[a],_depth_items[b]))
	var sorted: Array=[]
	for i in _depth_order: sorted.append(_depth_items[i])
	_depth_items=sorted
	# All ground treatment precedes objects, so foreground trees remain visible.
	for entry in _depth_items:
		if entry.group=="city" and entry.placement.get("grounding",true): _draw_city_ground(entry)
	for entry in _depth_items:
		var texture: Texture2D=art.texture(entry.asset)
		if texture==null: continue
		var rect: Rect2=entry.rect
		var tint:=Color(1,1,1,entry.get("opacity",1.0))
		if entry.flip_h:
			render_surface.draw_set_transform(pan+Vector2(rect.end.x,rect.position.y)*zoom,0,Vector2(-zoom,zoom))
			render_surface.draw_texture_rect(texture,Rect2(Vector2.ZERO,rect.size),false,tint)
			render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
		else: render_surface.draw_texture_rect(texture,rect,false,tint)

func _draw_city_ground(entry: Dictionary) -> void:
	var rect: Rect2=entry.body_rect
	var center:=rect.position+rect.size*Vector2(.5,.87)
	var rng:=RandomNumberGenerator.new(); rng.seed=hash(entry.id)
	var outline:=PackedVector2Array()
	for i in range(24):
		var angle:=TAU*i/24.0
		outline.append(center+Vector2(cos(angle)*rect.size.x*.57,sin(angle)*rect.size.y*.22)*rng.randf_range(.94,1.06))
	# A faint irregular earth wash and short ground strokes, not a detached shadow.
	render_surface.draw_colored_polygon(outline,Color("d1c5a4",.14))
	for i in range(12):
		var at:=center+Vector2(rng.randf_range(-.56,.56)*rect.size.x,rng.randf_range(.04,.20)*rect.size.y)
		render_surface.draw_line(at,at+Vector2(rng.randf_range(1.2,3.6),rng.randf_range(-.4,.4)),Color("968867",.26),.45,true)
	var contact:=PackedVector2Array([rect.position+rect.size*Vector2(.30,.98),rect.position+rect.size*Vector2(.48,1.0),rect.position+rect.size*Vector2(.73,.99)])
	render_surface.draw_polyline(contact,Color("71674e",.12),.65,true)

func _draw_footprints() -> void:
	var entries:=spatial_query(visible_world_rect())
	var conflicting: Dictionary={}
	for issue in Spatial.conflict_pairs(spatial_entries()): conflicting[issue.city_id]=true; conflicting[issue.other_id]=true
	for entry in entries:
		var polygon: PackedVector2Array=entry.footprint.duplicate()
		if polygon.is_empty() or not Spatial.bounds(polygon).intersects(visible_world_rect()): continue
		polygon.append(polygon[0])
		render_surface.draw_polyline(polygon,Color("c44b36",.85) if conflicting.has(entry.id) else Color("48886b",.6),1.2/zoom,true)

func _draw_authoring_overlay() -> void:
	# This overlay is inspection UI, never part of a clean export or game rule.
	for issue in visual_issues:
		var rect: Rect2 = issue.get("rect",Rect2())
		if rect.has_area() and rect.intersects(visible_world_rect()): render_surface.draw_rect(rect,Color("e4a840"),false,2/zoom)
	for f in doc.data.features:
		if not doc.layer(f.layer).visible: continue
		var p := Vector2(f.points[0][0], f.points[0][1])
		if not visible_world_rect().grow(24).has_point(p): continue
		if f.kind in ["pass", "ford"]:
			render_surface.draw_circle(p + Vector2(22, -16) / zoom, 6 / zoom, Color("5c9671") if f.gate_open else Color("be513c"))
		if f.protected: render_surface.draw_arc(p, 11 / zoom, 0, TAU, 20, Color("ad8441"), 1.5 / zoom, true)
		if not f.domain_id.is_empty(): render_surface.draw_circle(p, 3 / zoom, Color("557ba1"))

func _draw_reference(above: bool) -> void:
	if export_mode: return
	for ref in doc.references():
		if not ref.visible or ref.above_art != above: continue
		var texture: Texture2D = reference_cache.get(doc.resolve_reference_path(ref.get("id","primary")),{}).get("texture")
		if texture == null: continue
		var origin := reference_ghost if reference_drag and ref.get("id","primary") == active_reference else Vector2(ref.position[0],ref.position[1])
		var extent := Vector2(ref.size[0],ref.size[1])
		render_surface.draw_set_transform(pan+(origin+extent*0.5)*zoom,deg_to_rad(ref.rotation),Vector2.ONE*zoom)
		render_surface.draw_texture_rect(texture,Rect2(-extent*0.5,extent),false,Color(1,1,1,ref.opacity))
	render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)

func _marker(p: Vector2, color: Color, text: String) -> void:
	# Render in screen coordinates; 0.2% world zoom must not allocate a 7500 px glyph.
	render_surface.draw_set_transform(pan+p*zoom)
	render_surface.draw_circle(Vector2.ZERO,13,color)
	render_surface.draw_string(ink_font,Vector2(-7,6),text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
	render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)

func _draw_feature(f: Dictionary, pts: PackedVector2Array) -> void:
	var kind: String = f.kind
	if f.get("visual",{}).get("anchor_only",false):
		if show_site_anchors and not export_mode and not runtime_mode:
			var color:=Color("97452f") if kind=="pass" else Color("316c77")
			render_surface.draw_set_transform(pan+pts[0]*zoom)
			render_surface.draw_rect(Rect2(-5,-5,10,10),color,false,1.5)
			render_surface.draw_line(Vector2(-9,0),Vector2(9,0),color,1)
			render_surface.draw_line(Vector2(0,-9),Vector2(0,9),color,1)
			render_surface.draw_string(ink_font,Vector2(12,-9),f.name+" · 定位",HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
			render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
			anchor_draw_records.append(f.id)
		return
	if (kind=="country_border" and not show_country_borders) or (kind=="province_border" and not show_dao_borders):return
	if kind=="prefecture":
		_draw_prefecture(f)
		return
	if depth_enabled() and not _drawing_depth_labels and kind in ["city","pass","label","ford"]:
		if kind in ["city","pass"] and filter_game_sites and (f.domain_id.is_empty() or not visible_bound_instance_sites.has(f.domain_id)): return
		_depth_labels.append(f)
		if kind in ["city","pass"] and export_layer!="labels":
			var key:=ArtCatalog.site_variant(f)
			_depth_items.append(_spatial_entry(f.id,key,art.site_rect(f,pts[0]),f.get("visual",{}).get("placement",{}),false,{"feature_id":f.id,"name":f.name}))
		return
	if export_layer == "labels" and kind == "ford":
		if include_labels and runtime_label_tier.is_empty(): render_surface.draw_string(ink_font,pts[0]+Vector2(-25,43)*f.scale,f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,int(22*f.scale),INK)
		return
	if view_mode!="structure" and water_join.natural(f):
		_draw_natural_water(f)
		return
	if has_art() and kind == "water" and f.get("visual", {}).has("ribbon"):
		_draw_ribbon(f)
		return
	if has_art() and kind in ["city","pass"]:
		var tex: Texture2D = art.texture(ArtCatalog.site_variant(f))
		if tex != null:
			var rect: Rect2 = art.site_rect(f,pts[0])
			if export_layer != "labels" and not _drawing_depth_labels: render_surface.draw_texture_rect(tex,rect,false)
			var visual: Dictionary = f.get("visual", {})
			if include_labels and show_site_labels and export_layer != "sites" and visual.get("show_label", true):
				var font_size := int(visual.get("label_size", maxf(10, 22*f.scale)))
				var label_width := ink_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
				var offset: Array = visual.get("label_offset", [0,0])
				var label_pos := Vector2(pts[0].x-label_width*0.5+offset[0],rect.end.y+13*f.scale+offset[1])
				if visual.has("label_lod") and zoom<float(visual.label_lod.get("legacy_min_zoom",INF)): _draw_scaled_label(f,label_pos+Vector2(label_width*.5,0),font_size)
				else: render_surface.draw_string(ink_font,label_pos,f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,INK)
			return
	if kind in Doc.POLYGONS:
		var fill: Color = ART_COLORS[kind] if has_art() else COLORS[kind]
		var inked_water: bool = has_art() and kind == "water" and f.get("visual",{}).get("water_style","plain") == "inked"
		if inked_water: fill=Color("a5cadb")
		var triangles: Array = Geometry.triangles(f) if _geometry_preview(f.id) else polygon_meshes.get(f.id,[])
		if not (transparent_page and kind in ["mountain", "hills", "forest", "basin"]):
			if _geometry_preview(f.id):
				for triangle in triangles: render_surface.draw_primitive(triangle,PackedColorArray([fill]),PackedVector2Array())
			else:
				var mesh_key: String=f.id+":fill"
				if not _detail_cache.has(mesh_key):
					var vertices:=PackedVector3Array()
					for triangle in triangles:
						for point in triangle: vertices.append(Vector3(point.x,point.y,0))
					var mesh:=ArrayMesh.new()
					if not vertices.is_empty():
						var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
						mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
					_detail_cache[mesh_key]=mesh
				if _detail_cache[mesh_key].get_surface_count()>0: render_surface.draw_mesh(_detail_cache[mesh_key],null,Transform2D.IDENTITY,fill)
		for hole in f.holes:
			var outline := Doc.packed(hole)
			outline.append(outline[0])
			if not has_art() or kind == "water": _water_outline(f,outline,Color("729d9e",.45) if inked_water else fill.darkened(0.03 if has_art() else 0.15),1 if has_art() else 2)
		var closed := pts.duplicate()
		closed.append(pts[0])
		if not has_art() or kind == "water": _water_outline(f,closed,Color("729d9e",.45) if inked_water else fill.darkened(0.03 if has_art() else 0.15),1 if has_art() else 2)
		if inked_water: _water_outline(f,closed,Color("3f5653",.38),.45)
		if has_art() and kind in ["water","basin"]: _surface_marks(f,pts)
		if has_art() and kind=="water" and f.get("visual",{}).has("surface_flow"): _draw_surface_flow(f)
		if kind in ["mountain","hills","forest"]:
			if has_art(): _art_symbols(f,pts)
			else: _symbols(f,pts)
		if show_rules and not export_mode and f.rule in ["blocked","water"]:
			render_surface.draw_polyline(closed,Color(0.65,0.27,0.17,0.6) if f.rule == "blocked" else Color(0.2,0.43,0.58,0.7),1.5/zoom,true)
	elif kind in Doc.BOUNDARIES:
		var col: Color = Color("527c86") if kind == "coastline" else BOUNDARY_COLORS[kind]
		var line: Dictionary=f.get("visual",{}).get("boundary_line",{})
		var stroke: float=f.width if line.is_empty() else clampf(f.width*zoom,line.min_pixels,line.max_pixels)/zoom
		if kind=="coastline" and view_mode!="structure":
			for run in water_join.runs(f,pts,true): render_surface.draw_polyline(run,col,stroke,true)
		elif not export_mode or kind=="coastline" or line.get("style","")=="solid":
			render_surface.draw_polyline(pts,col,stroke,true)
		else:
			for i in range(pts.size()-1): render_surface.draw_dashed_line(pts[i],pts[i+1],col,stroke,12 if kind=="country_border" else 6,true)
	elif kind == "river":
		render_surface.draw_polyline(pts,Color("819b94") if has_art() else Color("718e98"),f.width+3 if has_art() else f.width+5,true)
		render_surface.draw_polyline(pts,ART_COLORS.water if has_art() else Color("8eafba"),f.width,true)
		if has_art(): _water_marks(f,pts)
	elif kind in Doc.PASSAGES:
		# Authoring corridors are natural gaps; no permanent road texture.
		if kind != "crossing":
			if has_art() and kind == "valley":
				# A faint approach cue follows the existing corridor; it grants no path.
				var path_width_factor := clampf(float(f.get("visual",{}).get("width_factor",1.0)),0.5,2.0)
				var visual_line := pts
				if f.get("visual",{}).has("path"):
					var key: String=f.id+":path"
					if not _detail_cache.has(key):
						var widths: Array=[]
						for p in f.visual.path: widths.append(5.0)
						var sampled: Array=ArtRibbon.sample(f.visual.path,widths)
						var line:=PackedVector2Array()
						for sample in sampled: line.append(sample.position)
						_detail_cache[key]=line
					visual_line=_detail_cache[key]
				if f.get("visual",{}).get("path_style", "subtle") == "earth":
					var key: String=f.id+":earth"
					if not _detail_cache.has(key): _detail_cache[key]=preload("earth_path.gd").build(visual_line,6.0*path_width_factor,str(f.id))
					var earth: Dictionary=_detail_cache[key]
					if earth.polygon.size()>2: _draw_cached_polygon(f.id+":earth_mesh",earth.polygon,Color("bdaa80",.36))
					for mark in earth.marks:render_surface.draw_line(mark.start,mark.end,Color("86745a",mark.alpha),mark.width,true)
				elif f.get("visual",{}).get("path_style", "subtle") == "painted":
					render_surface.draw_polyline(visual_line,Color("b6a47b",0.46),7*path_width_factor,true)
					render_surface.draw_polyline(visual_line,Color("fff3d8",0.86),3.8*path_width_factor,true)
				else:
					render_surface.draw_polyline(visual_line,Color("d6c8a4",0.42),7*path_width_factor,true)
					render_surface.draw_polyline(visual_line,Color("f0e8ce",0.72),3.5*path_width_factor,true)
			elif not (has_art() and kind == "trail"):
				render_surface.draw_polyline(pts,Color("e5dec3" if has_art() else "d4ceb5"),f.width,true)
		if show_rules and not export_mode:
			var col := Color("857449") if kind != "crossing" else Color("3c758e")
			for i in range(pts.size()-1): render_surface.draw_dashed_line(pts[i],pts[i+1],col,2/zoom,8/zoom,true)
	elif kind == "label":
		if not runtime_label_tier.is_empty():
			return # Runtime text has its own draw list; camera zoom never rebuilds geography.
		if not show_dao_labels and _is_dao_label(f):
			label_draw_records.append({"id":f.id,"drawn":false,"reason":"overview_only"});return
		var visual: Dictionary = f.get("visual", {})
		if include_labels and export_layer != "sites" and (not has_art() or visual.get("show_label", true)):
			var offset: Array = visual.get("label_offset", [0,0])
			if visual.has("label_lod"): _draw_scaled_label(f,pts[0]+Vector2(offset[0],offset[1]),int(visual.get("label_size",34*f.scale)))
			else: render_surface.draw_string(ink_font,pts[0]+Vector2(offset[0],offset[1]),f.name,HORIZONTAL_ALIGNMENT_CENTER,-1,int(visual.get("label_size",34*f.scale)),INK)
	else:
		var p: Vector2 = pts[0]
		var s: float = f.scale
		if kind == "city":
			render_surface.draw_rect(Rect2(p-Vector2(23,15)*s,Vector2(46,30)*s),Color("dad0aa"))
			render_surface.draw_rect(Rect2(p-Vector2(23,15)*s,Vector2(46,30)*s),INK,false,3*s)
			for x in [-20,0,20]:
				_roof(p+Vector2(x,-16)*s,10*s)
			render_surface.draw_rect(Rect2(p+Vector2(-5,6)*s,Vector2(10,9)*s),INK)
		elif kind == "pass":
			render_surface.draw_line(p+Vector2(0,-44)*s,p+Vector2(0,44)*s,INK,8*s,true)
			render_surface.draw_rect(Rect2(p-Vector2(14,12)*s,Vector2(28,24)*s),Color("cbb383"))
			_roof(p-Vector2(0,13)*s,22*s)
			render_surface.draw_rect(Rect2(p-Vector2(4,0)*s,Vector2(8,12)*s),INK)
			if show_rules and not export_mode: render_surface.draw_circle(p+Vector2(26,-20)*s,6*s,Color("5c9671") if f.gate_open else Color("be513c"))
		elif kind == "ford":
			render_surface.draw_arc(p,18*s,0,PI,24,INK,3*s,true)
			render_surface.draw_line(p-Vector2(24,0)*s,p+Vector2(24,0)*s,INK,3*s,true)
		if ink_font and include_labels and export_layer != "sites" and runtime_label_tier.is_empty():
			render_surface.draw_string(ink_font,p+Vector2(-25,43)*s,f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,int(22*s),INK)

func set_runtime_label_view(tier: String, camera_zoom: float) -> void:
	if runtime_label_tier==tier and is_equal_approx(runtime_camera_zoom,camera_zoom):return
	runtime_label_tier=tier
	runtime_camera_zoom=camera_zoom
	show_dao_labels=tier=="region"
	if is_instance_valid(runtime_label_surface):runtime_label_surface.queue_redraw()

func _render_runtime_labels() -> void:
	runtime_label_rebuilds+=1
	if runtime_label_tier.is_empty():return
	label_draw_records.clear()
	_label_rects.clear()
	if doc==null or runtime_label_tier=="close":return
	for feature in doc.data.features:
		if feature.kind!="label" or not doc.layer(feature.layer).visible or not feature.get("visual",{}).get("visible",true):continue
		_draw_runtime_label(feature,Vector2(feature.points[0][0],feature.points[0][1]))
	runtime_label_surface.draw_set_transform(Vector2.ZERO)

func _draw_runtime_label(f: Dictionary, center: Vector2) -> void:
	var tier := RuntimeLabels.feature_tier(f)
	if tier != runtime_label_tier or not include_labels or export_layer == "sites" or not f.get("visual",{}).get("show_label",true):
		label_draw_records.append({"id":f.id,"drawn":false,"reason":"label_tier"}); return
	# Canvas coordinates are 4x game coordinates; compensate BOTH scales.
	var effective_zoom := maxf(zoom*runtime_camera_zoom,0.001)
	var pixels := RuntimeLabels.pixel_size(tier)
	var font_scale := pixels / (LABEL_FONT_SIZE*effective_zoom)
	var offset: Array = f.get("visual",{}).get("label_offset",[0,0])
	center += Vector2(offset[0],offset[1])
	var extent := ink_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_FONT_SIZE)*font_scale
	extent.y = ink_font.get_height(LABEL_FONT_SIZE)*font_scale
	var ascent := ink_font.get_ascent(LABEL_FONT_SIZE)*font_scale
	var gap := 6.0/effective_zoom
	var base := center-Vector2(extent.x*.5,0)
	var shifts: Array[Vector2] = [Vector2.ZERO,Vector2(0,extent.y+gap),Vector2(0,-extent.y-gap),Vector2(extent.x*.5+gap,0),Vector2(-extent.x*.5-gap,0),Vector2(0,2*(extent.y+gap)),Vector2(0,-2*(extent.y+gap))]
	for shift in shifts:
		var pos := base+shift
		var rect := Rect2(pos-Vector2(0,ascent),extent)
		var blocked := false
		for prior in _label_rects:
			if prior.intersects(rect.grow(3.0/effective_zoom)): blocked=true; break
		if blocked: continue
		# Use cached image rectangles, including replaceable artwork with no game ID.
		for body in spatial_query(rect.grow(gap)):
			if body.group in ["city","pass"] and body.rect.intersects(rect.grow(gap)):
				blocked=true; break
		if blocked: continue
		runtime_label_surface.draw_set_transform(pan,0,Vector2.ONE*zoom*font_scale)
		runtime_label_surface.draw_string(ink_font,pos/font_scale,f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_FONT_SIZE,INK)
		_label_rects.append(rect)
		label_draw_records.append({"id":f.id,"drawn":true,"tier":tier,"screen_pixels":pixels,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
		return
	label_draw_records.append({"id":f.id,"drawn":false,"reason":"overlap"})

func _label_priority(f: Dictionary) -> float:
	var lod: Dictionary=f.get("visual",{}).get("label_lod",{})
	return 1000.0 if lod.is_empty() or zoom>=float(lod.get("legacy_min_zoom",INF)) else float(lod.get("priority",0))

func _water_contains(f: Dictionary,p: Vector2) -> bool:
	# A display query only. Keep packed local rings across redraws instead of
	# rebuilding thousands of vertices for each water mark or label candidate.
	if _geometry_preview(f.id) or not _water_shapes.has(f.id):return Geometry.contains(f,p)
	if not _water_query_cache.has(f.id): _water_query_cache[f.id]={}
	var cache: Dictionary=_water_query_cache[f.id]
	if cache.has(p): return cache[p]
	var key: String=f.id+":label_query"
	if not _detail_cache.has(key):_detail_cache[key]=Geometry.prepare_containment(f)
	var inside:=Geometry.contains_prepared(_detail_cache[key],p)
	if cache.size()>20000: cache.clear()
	cache[p]=inside
	return inside

func _label_on_water(rect: Rect2) -> bool:
	if _label_water_cache.has(rect): return _label_water_cache[rect]
	var inside:=false
	for f in _label_waters:
		if not feature_bounds.get(f.id,Rect2()).intersects(rect): continue
		for fraction in [Vector2(.1,.25),Vector2(.5,.25),Vector2(.9,.25),Vector2(.1,.75),Vector2(.5,.75),Vector2(.9,.75)]:
			if _water_contains(f,rect.position+rect.size*fraction): inside=true; break
		if inside: break
	if _label_water_cache.size()>20000: _label_water_cache.clear()
	_label_water_cache[rect]=inside
	return inside

func _is_dao_label(f: Dictionary) -> bool:
	return f.kind == "label" and f.get("group_id","") == "atlas_labels" and f.name in TANG_DAO_NAMES

func _draw_scaled_label(f: Dictionary,center: Vector2,base_size: int) -> void:
	var lod: Dictionary=f.visual.label_lod
	if zoom<float(lod.get("min_zoom",0.0)):
		label_draw_records.append({"id":f.id,"drawn":false,"reason":"zoom"});return
	var label_zoom := zoom*dao_label_screen_scale if _is_dao_label(f) else zoom
	var font_size:=maxi(8,int(ceil(clampf(base_size*label_zoom,float(lod.get("min_pixels",8)),float(lod.get("max_pixels",40)))/maxf(label_zoom,.01))))
	# Reuse one glyph atlas at every zoom. Logical map size is a transform,
	# not a new raster/MSDF font cache for each camera position/scale.
	var font_scale:=float(font_size)/LABEL_FONT_SIZE
	var site_body:=Rect2()
	if f.kind in ["city","pass"]:
		for item in [_depth_by_id.get(f.id,{})]:
			if not item.is_empty():
				var body: Rect2=item.body_rect
				site_body=body
				var offset: Array=f.visual.get("label_offset",[0,0])
				var visual_offset: Array=f.visual.get("offset",[0,0])
				center=Vector2(body.get_center().x+float(offset[0])-float(visual_offset[0]),body.end.y+ink_font.get_ascent(LABEL_FONT_SIZE)*font_scale+6/zoom+float(offset[1]));break
	var width:=ink_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_FONT_SIZE).x*font_scale
	var ascent:=ink_font.get_ascent(LABEL_FONT_SIZE)*font_scale
	var height:=ink_font.get_height(LABEL_FONT_SIZE)*font_scale
	var base:=center-Vector2(width*.5,0)
	var shifts: Array[Vector2]=[Vector2.ZERO,Vector2(0,-height-5/zoom),Vector2(0,height+5/zoom),Vector2(width*.55+8/zoom,0),Vector2(-width*.55-8/zoom,0)]
	shifts.append_array([Vector2(0,2*(height+5/zoom)),Vector2(width+12/zoom,0),Vector2(-width-12/zoom,0),Vector2(width*.7+8/zoom,height+5/zoom),Vector2(-width*.7-8/zoom,height+5/zoom)])
	if site_body.has_area():
		shifts.append(Vector2(0,site_body.position.y-(height-ascent)-6/zoom-center.y))
		var beside_y:=site_body.get_center().y+ascent-height*.5-center.y
		shifts.append(Vector2(site_body.end.x+8/zoom-base.x,beside_y))
		shifts.append(Vector2(site_body.position.x-8/zoom-width-base.x,beside_y))
	for shift in shifts:
		var pos:=base+shift
		var rect:=Rect2(pos-Vector2(0,ascent),Vector2(width,height))
		if lod.get("avoid_overlap",true):
			var collision=false
			for prior in _label_rects:
				if prior.intersects(rect.grow(3/zoom)):collision=true;break
			if collision or _label_on_water(rect):continue
			for body in _label_bodies:
				if body.body_rect.intersects(rect):collision=true;break
			if collision:continue
		if site_body.has_area() and shift.length()*zoom>18 and zoom>=.25:
			var start: Vector2=rect.get_center().clamp(site_body.position,site_body.end)
			var end: Vector2=site_body.get_center().clamp(rect.position,rect.end)
			var crosses_water=false
			for step in range(1,7):
				var point:=start.lerp(end,step/7.)
				for water in _label_waters:
					if feature_bounds.get(water.id,Rect2()).has_point(point) and _water_contains(water,point):crosses_water=true;break
				if crosses_water:break
			if crosses_water:continue
			if start.distance_to(end)*zoom>12:render_surface.draw_line(start,end,Color(INK,.28),.65/zoom,true)
		render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom*font_scale)
		render_surface.draw_string(ink_font,pos/font_scale,f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,LABEL_FONT_SIZE,INK)
		render_surface.draw_set_transform(pan,0,Vector2.ONE*zoom)
		_label_rects.append(rect)
		label_draw_records.append({"id":f.id,"drawn":true,"font_size":font_size,"zoom":zoom,"position":[pos.x,pos.y],"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"shift":[shift.x,shift.y]})
		return
	label_draw_records.append({"id":f.id,"drawn":false,"reason":"overlap"})

func _draw_surface_flow(f: Dictionary) -> void:
	if zoom<.4:return
	var color:=Color("f6f0d6",minf(.32,(zoom-.3)*.2))
	var visible:=visible_world_rect().grow(12)
	var key: String=f.id+":flow"
	if not _detail_cache.has(key):
		var strokes: Array=[]
		for stroke in f.visual.surface_flow:
			var points:=Doc.packed(stroke)
			var segments: Array=[]
			for i in range(points.size()-1):
				if _water_contains(f,points[i]) and _water_contains(f,points[i+1]) and _water_contains(f,(points[i]+points[i+1])*.5): segments.append([points[i],points[i+1]])
			strokes.append({"points":points,"segments":segments})
		_detail_cache[key]=strokes
	for stroke in _detail_cache[key]:
		var points: PackedVector2Array=stroke.points
		if not Array(points).any(func(p):return visible.has_point(p)):continue
		for segment in stroke.segments: render_surface.draw_line(segment[0],segment[1],color,.55,true)

func _water_outline(f: Dictionary,points: PackedVector2Array,color: Color,width: float) -> void:
	for run in water_join.runs(f,points) if f.kind=="water" and view_mode!="structure" else [points]:
		_water_outline_raw(f,run,color,width)

func _prepare_natural_water(f: Dictionary) -> void:
	if _detail_cache.has(f.id+":natural_fill") and _detail_cache.has(f.id+":natural_shores") and (not has_art() or _detail_cache.has(f.id+":natural_marks")): return
	var style: String=f.visual.ribbon.get("render_style","inked_brush")
	var clip:=WaterBrush.crop(f)
	var key: String=f.id+":natural_fill"
	var surfaces: Array=water_join.surface(f)
	if not _detail_cache.has(key):
		var vertices:=PackedVector3Array()
		for shape in surfaces:
			for triangle in Geometry.triangles(shape): _append_ribbon_polygon(triangle,clip,vertices)
		var mesh:=ArrayMesh.new()
		if not vertices.is_empty():
			var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_detail_cache[key]=mesh
	var shore_key: String=f.id+":natural_shores"
	if not _detail_cache.has(shore_key):
		var shores: Array=[]
		for shape in surfaces:
			for ring in [shape.points]+shape.holes:
				var shore:=Doc.packed(ring);shore.append(shore[0])
				shores.append_array(water_join.runs(f,shore))
		_detail_cache[shore_key]=shores
	if has_art():
		var mark_key: String=f.id+":natural_marks"
		if not _detail_cache.has(mark_key):
			var samples: Array=preload("natural_water.gd").samples(f.visual.ribbon,[water_join.endpoint_connected(f,0),water_join.endpoint_connected(f,1)])
			var marks: Array=ArtRibbon.brush_marks(samples,f.id) if style in ["inked_brush","soft"] else ArtRibbon.varied_marks(samples,f.id)
			var queries: Array=surfaces.map(func(s):return Geometry.prepare_containment(s))
			_detail_cache[mark_key]=marks.filter(func(m):return queries.any(func(q):return Geometry.contains_prepared(q,m.start) and Geometry.contains_prepared(q,m.middle) and Geometry.contains_prepared(q,m.end)))

func _draw_natural_water(f: Dictionary) -> void:
	_prepare_natural_water(f)
	var style: String=f.visual.ribbon.get("render_style","inked_brush")
	var fill: Color=(Color("abd0d2") if style=="soft" else Color("a5cadb")) if has_art() else COLORS.water
	var clip:=WaterBrush.crop(f)
	var key: String=f.id+":natural_fill"
	if _detail_cache[key].get_surface_count()>0: render_surface.draw_mesh(_detail_cache[key],null,Transform2D.IDENTITY,fill)
	for run in _detail_cache[f.id+":natural_shores"]:_ribbon_polyline(run,fill.darkened(.15),1.0 if has_art() else 2.0,clip)
	if has_art():
		var fade:=clampf((zoom-.08)/.42,0,1)
		if fade>.01:
			for mark in _detail_cache.get(f.id+":natural_marks",[]):
				# Subpixel decorative ripples contribute little to the image but
				# thousands of commands to overview frames. Export keeps full detail.
				if not export_mode and mark.thickness*zoom<.45:continue
				_ribbon_polyline(PackedVector2Array([mark.start,mark.middle,mark.end]),Color(.98,.97,.88,mark.opacity*fade),mark.thickness,clip)
	if show_rules and not export_mode:
		var outline:=Doc.packed(f.points);outline.append(outline[0])
		render_surface.draw_polyline(outline,Color(.2,.43,.58,.7),1.5/zoom,true)

func _water_outline_raw(f: Dictionary,points: PackedVector2Array,color: Color,width: float) -> void:
	var masks: Array=f.get("visual",{}).get("shore_masks",[])
	if masks.is_empty():render_surface.draw_polyline(points,color,width,true);return
	var key: Array=[f.id,"shore",points]
	if not _detail_cache.has(key):
		var runs: Array=[]
		var run:=PackedVector2Array()
		for n in range(points.size()-1):
			var masked=false
			for values in masks:
				var rect:=Rect2(values[0],values[1],values[2],values[3])
				if rect.has_point(points[n]) or rect.has_point(points[n+1]) or rect.has_point((points[n]+points[n+1])*.5): masked=true; break
			if masked:
				if run.size()>1:runs.append(run)
				run=PackedVector2Array(); continue
			if run.is_empty():run.append(points[n])
			run.append(points[n+1])
		if run.size()>1:runs.append(run)
		_detail_cache[key]=runs
	for run in _detail_cache[key]: render_surface.draw_polyline(run,color,width,true)

func _roof(p: Vector2, s: float) -> void:
	render_surface.draw_primitive(PackedVector2Array([p+Vector2(-s,4),p+Vector2(0,-s*0.65),p+Vector2(s,4)]),PackedColorArray([INK]),PackedVector2Array())

func _draw_prefecture(f: Dictionary) -> void:
	if not show_prefectures: return
	var faction: Dictionary=f.get("visual",{}).get("faction",{})
	if show_factions and not faction.is_empty():
		var tint:=Color(Color.html(faction.color),.16)
		var triangles: Array=polygon_meshes.get(f.id,[])
		for triangle in triangles: render_surface.draw_primitive(triangle,PackedColorArray([tint]),PackedVector2Array())
	for ring in [f.points]+f.holes:
		var outline:=Doc.packed(ring)
		outline.append(outline[0])
		render_surface.draw_polyline(outline,Color(BOUNDARY_COLORS.prefecture,.85),maxf(f.width,.8/zoom),true)

func _draw_ribbon(f: Dictionary) -> void:
	var ribbon: Dictionary = f.visual.ribbon
	var key: String=f.id+":samples"
	if not _detail_cache.has(key): _detail_cache[key]=ArtRibbon.sample(ribbon.points,ribbon.widths)
	var samples: Array = _detail_cache[key]
	if samples.size() < 2: return
	if ribbon.get("render_style", "soft") in ["inked", "inked_varied", "inked_brush"]:
		_draw_inked_ribbon(f,samples)
		return
	var bank := Color("7faaa9", 0.75)
	var water := Color("abd0d2")
	var joined:=water_join.affected(f)
	for color in [bank, water]:
		if joined and color==bank: continue
		var extra := 3.0 if color == bank else 0.0
		for i in range(samples.size()-1):
			var a: Dictionary = samples[i]
			var b: Dictionary = samples[i+1]
			var width: float = (float(a.width)+float(b.width))*0.5+extra
			render_surface.draw_line(a.position, b.position, color, width, true)
		for i in range(samples.size()):
			render_surface.draw_circle(samples[i].position, (samples[i].width+extra)*0.5, color)
	if joined:
		var outline:=Doc.packed(water_join.shape(f).points)
		outline.append(outline[0])
		for run in water_join.runs(f,outline): render_surface.draw_polyline(run,bank,2.0,true)
	var fade := clampf((zoom-0.1)/0.5,0,1)
	if fade <= 0.01: return
	for i in range(3,samples.size()-3,4):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(f.id, ":ribbon:", i))
		if rng.randf() < 0.35: continue
		var tangent: Vector2 = (samples[i+1].position-samples[i-1].position).normalized()
		var normal := tangent.orthogonal()
		var offset: float = rng.randf_range(-0.18,0.18)*float(samples[i].width)
		var start: Vector2 = samples[i].position+normal*offset
		var length := rng.randf_range(3,9)
		render_surface.draw_line(start,start+tangent.rotated(rng.randf_range(-0.12,0.12))*length,Color(0.87,0.93,0.85,rng.randf_range(.25,.58)*fade),.65,true)

func _draw_inked_ribbon(f: Dictionary, samples: Array) -> void:
	var clip := Rect2()
	if f.visual.has("ribbon_clip_rect"):
		var values: Array=f.visual.ribbon_clip_rect
		clip=Rect2(values[0],values[1],values[2],values[3])
	var bank_key: String=f.id+":banks"
	if not _detail_cache.has(bank_key): _detail_cache[bank_key]=ArtRibbon.inked_banks(samples,f.id)
	var banks: Dictionary = _detail_cache[bank_key]
	var left: PackedVector2Array = banks.left
	var right: PackedVector2Array = banks.right
	var water := Color("a5cadb")
	var fill_key: String=f.id+":ribbon_fill"
	if not _detail_cache.has(fill_key):
		var vertices:=PackedVector3Array()
		var circles: Array=[]
		for i in range(samples.size()-1):
			_append_ribbon_polygon(PackedVector2Array([left[i],right[i],left[i+1]]),clip,vertices)
			_append_ribbon_polygon(PackedVector2Array([right[i],right[i+1],left[i+1]]),clip,vertices)
		for sample in samples:
			var radius: float=sample.width*0.41
			if not clip.has_area() or clip.encloses(Rect2(sample.position-Vector2.ONE*radius,Vector2.ONE*radius*2)):
				circles.append([sample.position,radius])
			elif clip.intersects(Rect2(sample.position-Vector2.ONE*radius,Vector2.ONE*radius*2)):
				var circle:=PackedVector2Array()
				for n in range(64):circle.append(sample.position+Vector2.from_angle(TAU*n/64.)*radius)
				_append_ribbon_polygon(circle,clip,vertices)
		var mesh:=ArrayMesh.new()
		if not vertices.is_empty():
			var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_detail_cache[fill_key]={"mesh":mesh,"circles":circles}
	var fill: Dictionary=_detail_cache[fill_key]
	if fill.mesh.get_surface_count()>0: render_surface.draw_mesh(fill.mesh,null,Transform2D.IDENTITY,water)
	for circle in fill.circles: render_surface.draw_circle(circle[0],circle[1],water)
	for bank in [left,right]:
		for run in water_join.runs(f,bank):
			_ribbon_polyline(run,Color("729d9e",0.45),1.0,clip)
			_ribbon_polyline(run,Color("3f5653",0.38),0.45,clip)
	var fade := clampf((zoom-0.08)/0.42,0,1)
	if fade <= 0.01: return
	var style: String = f.visual.ribbon.get("render_style", "inked")
	if style in ["inked_varied", "inked_brush"]:
		var mark_key: String=f.id+":marks"
		if not _detail_cache.has(mark_key):
			var generated: Array=ArtRibbon.brush_marks(samples,f.id) if style=="inked_brush" else ArtRibbon.varied_marks(samples,f.id)
			_detail_cache[mark_key]=generated.filter(func(m):return _water_contains(f,m.start) and _water_contains(f,m.middle) and _water_contains(f,m.end))
		var marks: Array = _detail_cache[mark_key]
		for mark in marks:
			_ribbon_polyline(PackedVector2Array([mark.start,mark.middle,mark.end]),Color(0.98,0.97,0.88,mark.opacity*fade),mark.thickness,clip)
		return
	for i in range(3,samples.size()-3,2):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(f.id, ":ink:", i))
		if rng.randf() < 0.28: continue
		var tangent: Vector2 = (samples[i+1].position-samples[i-1].position).normalized()
		var normal := tangent.orthogonal()
		var start: Vector2 = samples[i].position + normal * rng.randf_range(-0.23,0.23) * float(samples[i].width)
		var length := rng.randf_range(4.0,11.0)
		var end: Vector2 = start+tangent.rotated(rng.randf_range(-0.11,0.11))*length
		if _water_contains(f,start) and _water_contains(f,end):
			_ribbon_polyline(PackedVector2Array([start,end]),Color(0.96,0.96,0.85,rng.randf_range(0.28,0.65)*fade),0.7,clip)

func _append_ribbon_polygon(points: PackedVector2Array,clip: Rect2,vertices: PackedVector3Array) -> void:
	var pieces: Array=[points]
	if clip.has_area() and not Array(points).all(func(p):return clip.has_point(p)):
		var boundary:=PackedVector2Array([clip.position,Vector2(clip.end.x,clip.position.y),clip.end,Vector2(clip.position.x,clip.end.y)])
		pieces=Geometry2D.intersect_polygons(points,boundary)
	for piece in pieces:
		var indices:=PackedInt32Array([0,1,2]) if piece.size()==3 else Geometry2D.triangulate_polygon(piece)
		for index in indices: vertices.append(Vector3(piece[index].x,piece[index].y,0))

func _ribbon_segment(a: Vector2,b: Vector2,clip: Rect2) -> PackedVector2Array:
	if clip.has_point(a) and clip.has_point(b):return PackedVector2Array([a,b])
	var delta:=b-a;var low:=0.;var high:=1.
	for pair in [[-delta.x,a.x-clip.position.x],[delta.x,clip.end.x-a.x],[-delta.y,a.y-clip.position.y],[delta.y,clip.end.y-a.y]]:
		var p: float=pair[0];var q: float=pair[1]
		if absf(p)<.00001:
			if q<0:return PackedVector2Array()
			continue
		var t:=q/p
		if p<0:low=maxf(low,t)
		else:high=minf(high,t)
		if low>high:return PackedVector2Array()
	return PackedVector2Array([a if low==0. else a+delta*low,b if high==1. else a+delta*high])

func _ribbon_polyline(points: PackedVector2Array,color: Color,width: float,clip: Rect2) -> void:
	if not clip.has_area():render_surface.draw_polyline(points,color,width,true);return
	if not _detail_cache.has("ribbon_lines"): _detail_cache["ribbon_lines"]={}
	var cache: Dictionary=_detail_cache.ribbon_lines
	var key: Array=[clip,points]
	if not cache.has(key):
		var runs: Array=[]
		var run:=PackedVector2Array()
		for n in range(points.size()-1):
			var segment:=_ribbon_segment(points[n],points[n+1],clip)
			if segment.size()==2:
				if run.size()>0 and not run[-1].is_equal_approx(segment[0]):
					runs.append(run);run=PackedVector2Array()
				if run.is_empty():run.append(segment[0])
				run.append(segment[1])
			elif run.size()>1:runs.append(run);run=PackedVector2Array()
		if run.size()>1:runs.append(run)
		cache[key]=runs
	for run in cache[key]: render_surface.draw_polyline(run,color,width,true)

func _symbols(f: Dictionary, polygon: PackedVector2Array) -> void:
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: bounds = bounds.expand(p)
	var rng := RandomNumberGenerator.new()
	var spacing := 65 if f.kind == "mountain" else 48
	if spacing*zoom < 5: return
	var visible_bounds := bounds.intersection(visible_world_rect().grow(64))
	if not visible_bounds.has_area(): return
	var origin := bounds.position+Vector2(20,30)
	var first := ((visible_bounds.position-origin)/spacing).floor().max(Vector2.ZERO)
	var last := ((visible_bounds.end-origin)/spacing).ceil()
	for iy in range(int(first.y),int(last.y)+1):
		for ix in range(int(first.x),int(last.x)+1):
			var x := origin.x+ix*spacing
			var y := origin.y+iy*spacing
			# Per-cell randomness keeps the same symbols across export tiles and camera positions.
			rng.seed = hash(str(f.id,":",ix,":",iy))
			var p := Vector2(x+rng.randf_range(-14,14),y+rng.randf_range(-9,9))
			if not Geometry.contains(f,p): continue
			if f.kind == "mountain":
				var h := rng.randf_range(22,42)
				var tri := PackedVector2Array([p+Vector2(-26,10),p+Vector2(0,-h),p+Vector2(28,10)])
				if not Geometry.contains(f,tri[0]) or not Geometry.contains(f,tri[1]) or not Geometry.contains(f,tri[2]): continue
				render_surface.draw_primitive(tri,PackedColorArray([Color("d6d4bc")]),PackedVector2Array())
				render_surface.draw_primitive(PackedVector2Array([p,p+Vector2(0,-h),p+Vector2(28,10)]),PackedColorArray([Color("969e8c")]),PackedVector2Array())
				render_surface.draw_polyline(tri,Color("7e8677"),1.5,true)
			elif f.kind == "hills": render_surface.draw_arc(p+Vector2(0,10),18,PI,TAU,14,Color("9e9b7a"),2,true)
			else:
				render_surface.draw_circle(p,10,Color("819873"))
				render_surface.draw_circle(p-Vector2(3,4),8,Color("b2c19b"))

func _art_symbols(f: Dictionary, polygon: PackedVector2Array) -> void:
	if depth_enabled() and render_surface==terrain_surface:return
	for candidate in _scatter_candidates(f, polygon, visible_world_rect().grow(160)):
		var tex: Texture2D = art.texture(candidate.asset)
		if tex == null: continue
		if depth_enabled():
			_depth_items.append(_spatial_entry(f.id+str(candidate.position),candidate.asset,candidate.rect,{},false,{"opacity":candidate.fade}))
		else: render_surface.draw_texture_rect(tex, candidate.rect, false, Color(1,1,1,candidate.fade))

func _scatter_candidates(f: Dictionary, polygon: PackedVector2Array, region: Rect2) -> Array:
	var result: Array = []
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: bounds = bounds.expand(p)
	var visual: Dictionary = f.get("visual",{})
	if not visual.get("scatter", true): return result
	var forest: bool = f.kind == "forest"
	# A world-aligned grid and fixed cell IDs keep existing candidates in place
	# when the polygon bounding box or density changes. Density adds/removes cells.
	var spacing := 26.0 if forest else 65.0
	var fade := clampf((spacing*zoom-1.5)/4.0, 0.0, 1.0)
	if fade <= 0.01: return result
	var visible_bounds := bounds.intersection(region)
	if not visible_bounds.has_area(): return result
	var origin := Vector2(12,18)
	var first := ((visible_bounds.position-origin)/spacing).floor()
	var last := ((visible_bounds.end-origin)/spacing).ceil()
	var rng := RandomNumberGenerator.new()
	var choices: Array = ArtCatalog.scatter_group(f.kind)
	if choices.is_empty(): return result
	var masks: Array = visual.get("scatter_masks", [])
	var overrides: Array = visual.get("scatter_overrides", [])
	for iy in range(int(first.y),int(last.y)+1):
		for ix in range(int(first.x),int(last.x)+1):
			var cell := origin+Vector2(ix*spacing,iy*spacing)
			var seed_value: int = int(visual.get("seed",0))
			for override in overrides:
				var rect: Array = override.rect
				if Rect2(rect[0],rect[1],rect[2],rect[3]).has_point(cell): seed_value = override.seed
			rng.seed = hash(str(f.id,":",ix,":",iy,":",seed_value))
			if rng.randf() > minf(1.0, float(visual.get("density",1.0))*0.85): continue
			var point := cell+Vector2(rng.randf_range(-spacing*.34,spacing*.34),rng.randf_range(-spacing*.25,spacing*.25))
			if not region.has_point(point): continue
			var masked := false
			for area in masks:
				var rect: Array = area.get("rect",[]) if area is Dictionary else area
				if Rect2(rect[0],rect[1],rect[2],rect[3]).has_point(point): masked = true; break
			if masked: continue
			if not Geometry.contains(f,point): continue
			var key: String = visual.get("variant","auto")
			if key == "auto": key = choices[rng.randi_range(0,choices.size()-1)]
			var tex: Texture2D = art.texture(key)
			if tex == null: continue
			var width := rng.randf_range(26,43) if forest else rng.randf_range(72,114)
			if f.kind == "hills": width *= 0.8
			var extent := Vector2(width,width*tex.get_height()/tex.get_width())
			var rect := Rect2(point-extent*Vector2(.5,.72),extent)
			# Keep the footprint inside the terrain and outside holes. Roof/tree tops may overhang.
			if not Geometry.contains(f,point+Vector2(-width*.36,0)) or not Geometry.contains(f,point+Vector2(width*.36,0)): continue
			if _art_overlaps_corridor(rect): continue
			if depth_enabled() and not placement_conflicts(key,rect).is_empty(): continue
			var descriptor: Dictionary = ArtCatalog.descriptor(key)
			var anchor: Array = descriptor.anchor
			result.append({"asset":key, "position":rect.position+extent*Vector2(anchor[0],anchor[1]), "scale":width/float(descriptor.width), "rect":rect, "fade":fade})
	return result

func _art_overlaps_corridor(rect: Rect2) -> bool:
	for obstacle in art_exclusions:
		# National coastlines must not be scanned for every distant tree. Bounds
		# already include line width; missing caches retain the exact fallback.
		if feature_bounds.has(obstacle.id) and not feature_bounds[obstacle.id].intersects(rect,true): continue
		var points := Doc.packed(obstacle.points)
		if obstacle.kind == "water":
			var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for corner in corners:
				if Geometry.contains(obstacle,corner): return true
			if Geometry.contains(obstacle,rect.get_center()): return true
			for ring in [obstacle.points]+obstacle.holes:
				for i in range(ring.size()):
					var a := Vector2(ring[i][0],ring[i][1])
					var b := Vector2(ring[(i+1)%ring.size()][0],ring[(i+1)%ring.size()][1])
					if rect.has_point(a): return true
					for j in range(4):
						if Geometry2D.segment_intersects_segment(a,b,corners[j],corners[(j+1)%4]) != null: return true
			continue
		var grown := rect.grow(float(obstacle.width)*0.5+2)
		var corners := [grown.position,Vector2(grown.end.x,grown.position.y),grown.end,Vector2(grown.position.x,grown.end.y)]
		for i in range(points.size()-1):
			if grown.has_point(points[i]) or grown.has_point(points[i+1]): return true
			for j in range(4):
				if Geometry2D.segment_intersects_segment(points[i],points[i+1],corners[j],corners[(j+1)%4]) != null: return true
	return false

func _water_marks(f: Dictionary, points: PackedVector2Array) -> void:
	# Stable marks follow the existing river; no new geography or simulated water.
	for segment in range(points.size()-1):
		var length := points[segment].distance_to(points[segment+1])
		var direction := points[segment].direction_to(points[segment+1])
		var normal := direction.orthogonal()
		var rng := RandomNumberGenerator.new()
		for index in range(int(length/14)):
			rng.seed = hash(str(f.id,":wave:",segment,":",index))
			var p := points[segment]+direction*(index*14+7)+normal*rng.randf_range(-f.width*.32,f.width*.32)
			if not visible_world_rect().grow(12).has_point(p): continue
			var mark_dir := direction.rotated(rng.randf_range(-0.2,0.2))
			render_surface.draw_line(p,p+mark_dir*rng.randf_range(3,9),Color("d9e7d7", rng.randf_range(0.45,0.8)),.7,true)

func _surface_marks(f: Dictionary, polygon: PackedVector2Array) -> void:
	var water: bool = f.kind == "water"
	# Large connected water silhouettes can keep a quiet fill. This avoids
	# scanning their mostly dry bounding rectangle for decorative surface marks.
	if water and not f.get("visual",{}).get("surface_marks",true): return
	var spacing := Vector2(13,7) if water else Vector2(31,23)
	var fade := clampf((spacing.y*zoom-1.5)/4.0, 0.0, 1.0)
	if fade <= 0.01: return
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: bounds=bounds.expand(p)
	var visible_bounds := bounds.intersection(visible_world_rect().grow(12))
	if not visible_bounds.has_area(): return
	var first := ((visible_bounds.position-bounds.position)/spacing).floor().max(Vector2.ZERO)
	var last := ((visible_bounds.end-bounds.position)/spacing).ceil()
	# Decoration needs screen-space density, not one mark per world cell at
	# every zoom. Keep stable grid coordinates/seeds when sampling distant marks.
	var stride:=maxi(1,ceili(12.0/(spacing.y*zoom))) if not export_mode else 1
	first=(first/float(stride)).floor()*stride
	var batch_key: Array=[f.id,"surface_batch",first,last,stride]
	var ink := Color("d9e8d8") if water else Color("e1d9b7")
	ink.a=fade
	# Tiny paper-grain strokes can generate millions of AA fringe triangles.
	# Keep their exact coordinates/color/width; only the game grain omits fringes.
	var grain_antialiased := runtime_label_tier.is_empty() or water
	if _surface_batches.has(batch_key):
		var cached: PackedVector2Array=_surface_batches[batch_key]
		if not cached.is_empty():render_surface.draw_multiline(cached,ink,.65,grain_antialiased)
		return
	var lines:=PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	if not _surface_cells.has(f.id): _surface_cells[f.id]={}
	var cells: Dictionary=_surface_cells[f.id]
	# A national land silhouette may contain thousands of vertices. Reuse the
	# exact indexed containment test for all marks instead of repacking both
	# rings at each endpoint. Geometry/preview changes clear _detail_cache.
	var query_key: String=f.id+":surface_query"
	if not _detail_cache.has(query_key): _detail_cache[query_key]=Geometry.prepare_containment(f)
	var queries: Array=_detail_cache[query_key]
	for y in range(int(first.y),int(last.y)+1,stride):
		for x in range(int(first.x),int(last.x)+1,stride):
			var cell:=Vector2i(x,y)
			if not cells.has(cell):
				rng.seed=hash(str(f.id,":surface:",x,":",y))
				var mark: Array=[]
				if rng.randf() >= .32:
					var p := bounds.position+Vector2(x*spacing.x,y*spacing.y)+Vector2(rng.randf_range(-4,4),rng.randf_range(-2,2))
					var end := p+Vector2(rng.randf_range(2,7),rng.randf_range(-.7,.7))
					if Geometry.contains_prepared(queries,p) and Geometry.contains_prepared(queries,end): mark=[p,end]
				# Bound the working set when exploring an entire national map.
				if cells.size() >= 100000: cells.clear()
				cells[cell]=mark
			var mark: Array=cells[cell]
			if not mark.is_empty():lines.append(mark[0]);lines.append(mark[1])
	if _surface_batches.size()>=64:_surface_batches.clear()
	_surface_batches[batch_key]=lines
	if not lines.is_empty():render_surface.draw_multiline(lines,ink,.65,grain_antialiased)

func _draw_cached_polygon(key: String, polygon: PackedVector2Array, tint: Color) -> void:
	if not _detail_cache.has(key):
		var indices:=Geometry2D.triangulate_polygon(polygon)
		var vertices:=PackedVector3Array()
		for p in polygon: vertices.append(Vector3(p.x,p.y,0))
		var mesh:=ArrayMesh.new()
		if not indices.is_empty():
			var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_INDEX]=indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_detail_cache[key]=mesh
	if _detail_cache[key].get_surface_count()>0: render_surface.draw_mesh(_detail_cache[key],null,Transform2D.IDENTITY,tint)
