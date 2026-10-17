extends Control
## Persistent CanvasItem commands; camera-only motion changes the root transform.
const Audit=preload("res://v02/e2/submission_audit.gd")
var planner: RefCounted
var loader: RefCounted
var pages: Array=[]
var art: Dictionary={}
var reference_source: Array=[]
var reference_mode:=false
var guides:=true
var presenter: WeakRef
var audit=Audit.new()
var last_plan: Dictionary={}
var errors: Array=[]
var draw_origin: Array=[0.0,0.0]
var stats: Dictionary={"object_draw_callbacks":0,"terrain_draw_callbacks":0,"actual_object_submissions":0,"camera_transform_updates":0,"ordinary_frame_reuses":0,"reference_global_sorts":0}
var _key: Array=[]
var _plan_version:=-1
var _draw_records: Array=[]
var _reference_sorted: Array=[]
var _root: Node2D
var _terrain: Node2D
var _objects: Node2D
var _guides: Node2D
class Layer extends Node2D:
	var host: WeakRef
	var kind:=0
	func _draw() -> void:
		if host==null or host.get_ref()==null:return
		if kind==0:host.get_ref().draw_terrain(self)
		elif kind==1:host.get_ref().draw_objects(self)
		else:host.get_ref().draw_guides(self)
func _ready() -> void:
	clip_contents=true
	var paper=ColorRect.new();paper.color=Color("ded8bc");paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);paper.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(paper)
	_root=Node2D.new();add_child(_root)
	for i in 3:
		var layer=Layer.new();layer.host=weakref(self);layer.kind=i;_root.add_child(layer)
		if i==0:_terrain=layer
		elif i==1:_objects=layer
		else:_guides=layer
func bind(source_loader: RefCounted,source_planner: RefCounted,terrain: Array,atlases: Dictionary,raw: Array) -> void:
	loader=source_loader;planner=source_planner;pages=terrain;art=atlases;reference_source=raw
	_reference_sorted=[];_key=[];_plan_version=-1;last_plan={};errors=[]
	_terrain.queue_redraw();_guides.queue_redraw()
func update_view(x: float,y: float,zoom: float,display_revision: String="1",lod: String="detail") -> Dictionary:
	if planner==null:return {"ok":false,"code":"not_bound"}
	var next_key: Array=[x,y,zoom,size.x,size.y,planner.index.epoch,reference_mode,guides,display_revision,lod]
	if next_key==_key:stats.ordinary_frame_reuses+=1;return last_plan
	var view:=Rect2(x-size.x/(zoom*2),y-size.y/(zoom*2),size.x/zoom,size.y/zoom)
	var result: Dictionary=planner.plan(view,display_revision,lod)
	if not result.ok:errors.append(result);return result
	var origin: Array=[floor(x/8192.0)*8192.0,floor(y/8192.0)*8192.0]
	var origin_changed: bool=origin!=draw_origin
	draw_origin=origin
	_root.position=size*.5-Vector2(x-draw_origin[0],y-draw_origin[1])*zoom;_root.scale=Vector2(zoom,zoom)
	stats.camera_transform_updates+=1
	var mode_changed: bool=_key.is_empty() or _key[6]!=reference_mode
	if reference_mode:
		if _reference_sorted.is_empty():
			_reference_sorted=reference_source.duplicate();_reference_sorted=planner.sorted_records(_reference_sorted);stats.reference_global_sorts+=1
		_draw_records=_reference_sorted
	else:_draw_records=result.records
	if _plan_version!=int(planner.stats.visible_plan_builds) or origin_changed or mode_changed:
		_objects.queue_redraw();_plan_version=int(planner.stats.visible_plan_builds)
	if origin_changed:_terrain.queue_redraw()
	if origin_changed or _key.is_empty() or _key[7]!=guides:_guides.queue_redraw()
	_key=next_key;last_plan=result;return result
func local_rect(b: Array) -> Rect2:return Rect2(b[0]-draw_origin[0],b[1]-draw_origin[1],b[2],b[3])
func local_point(p: Array) -> Vector2:return Vector2(p[0]-draw_origin[0],p[1]-draw_origin[1])
func draw_terrain(target: Node2D) -> void:
	if loader==null:return
	stats.terrain_draw_callbacks+=1
	for page in pages:
		for file in page.texture_files:
			target.draw_texture_rect_region(loader.textures[file],local_rect(page.bounds_m),Rect2(page.gutter_px,page.gutter_px,page.core_px[0],page.core_px[1]),Color.WHITE,false,false)
func draw_objects(target: Node2D) -> void:
	audit.begin_frame();stats.object_draw_callbacks+=1
	for item in _draw_records:
		if item.get("baked_representation",false):continue
		var submitted: Dictionary=audit.submit(item.id,item.get("representation_id","detail"))
		if not submitted.ok:errors.append(submitted);continue
		if item.record_type=="sprite":
			if not art.has(item.asset_id):errors.append({"code":"missing_art","id":item.id});continue
			target.draw_texture_rect(art[item.asset_id],local_rect(item.paint_bounds_m),false)
		else:
			var points=PackedVector2Array()
			for p in item.points_m:points.append(local_point(p))
			target.draw_polyline(points,Color(str(item.color)),item.width_m,true)
		stats.actual_object_submissions+=1
func draw_guides(target: Node2D) -> void:
	if loader==null or not guides:return
	for page in loader.pages.values():
		if page.level!=2 and loader.manifest.compatibility.world_id=="stream_lab_v02":continue
		if page.level!=1 and loader.manifest.compatibility.world_id!="stream_lab_v02":continue
		target.draw_rect(local_rect(page.bounds_m),Color("ad8244") if page.optional else Color("496d68",.65),false,2.0)
	for site in loader.sites:
		for slot in site.slots:
			var outline=PackedVector2Array()
			for p in slot.polygon_local_m:outline.append(local_point(p))
			outline.append(outline[0]);target.draw_polyline(outline,Color("a58054"),1.5,true)
func force_draw() -> void:_terrain.queue_redraw();_objects.queue_redraw();_guides.queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if presenter==null or presenter.get_ref()==null:return
	var app=presenter.get_ref()
	if event is InputEventMouseMotion and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:app.pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:app.change_zoom(1.15)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:app.change_zoom(1/1.15)
func telemetry() -> Dictionary:
	return {"renderer":stats.duplicate(true),"last_submissions":audit.submissions.duplicate(true),"submission_errors":audit.errors.duplicate(true),"errors":errors.duplicate(true),"planner":planner.telemetry() if planner!=null else {}}
