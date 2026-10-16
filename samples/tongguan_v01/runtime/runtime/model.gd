extends RefCounted
var host: RefCounted
var recipe: Dictionary={}
var metadata: Dictionary={}
var water: Dictionary={}
var template_checks: Dictionary={}
var coarse: Dictionary={}
var view: Dictionary={}
var load_error: String=""
var camera_x:=0.0
var camera_y:=0.0
var zoom:=2.4
var lod:=3
var selected_site: String="tongguan"
var selected_slot: String="tongguan.slot.rear_storage_01"
var selected_tree: String=""
var probe:=Vector2.ZERO
var preview: Dictionary={}
var show_buildings:=true
var show_vegetation:=true
var custom_bookmarks: Dictionary={}
var polygon_indices: Dictionary={}
func _init()->void:
	host=Engine.get_main_loop().root.get_node("Session").state
	load_error=host.error
	recipe=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/geography_recipe.json"))
	metadata=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/geography_metadata.json"))
	water=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/modern_water.json"))
	template_checks=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/template_checks.json"))
	coarse=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/coarse_overview.json"))
	view={"world_origin":[1000000000.0+float(metadata.origin_albers_m[0]),-2000000000.0-float(metadata.origin_albers_m[1])],"bookmarks":{"east_asia":{"name":"东亚示意","world_local":[-500000,100000],"zoom":0.00014},"guanzhong_east":{"name":"关河背景","world_local":[-800,300],"zoom":0.15},"tongguan_context":{"name":"关城全景","world_local":[-300,-100],"zoom":0.5},"gate_close":{"name":"建设槽位","world_local":[-470,-205],"zoom":2.4}}}
	recall_bookmark("gate_close")
func site_world()->Array:return view.world_origin.duplicate()
func world_to_screen(world: Array,viewport: Vector2)->Vector2:return viewport*0.5+Vector2((float(world[0])-camera_x)*zoom,(float(world[1])-camera_y)*zoom)
func screen_to_world(screen: Vector2,viewport: Vector2)->Array:
	var p=(screen-viewport*0.5)/zoom;return [camera_x+float(p.x),camera_y+float(p.y)]
func local_to_screen(point: Array,viewport: Vector2)->Vector2:return world_to_screen([float(view.world_origin[0])+float(point[0]),float(view.world_origin[1])+float(point[1])],viewport)
func local_from_screen(point: Vector2,viewport: Vector2)->Vector2:
	var world=screen_to_world(point,viewport);return Vector2(float(world[0])-float(view.world_origin[0]),float(world[1])-float(view.world_origin[1]))
func site_screen(viewport: Vector2)->Vector2:return world_to_screen(site_world(),viewport)
func pick_site(point: Vector2,viewport: Vector2)->String:return "tongguan" if point.distance_to(site_screen(viewport))<=22 else ""
func set_zoom(value: float)->void:
	zoom=clampf(value,0.00006,2.4);var limits=[0.05,0.2,0.64]
	while lod<3 and zoom>limits[lod]*1.15:lod+=1
	while lod>0 and zoom<limits[lod-1]*0.85:lod-=1
func zoom_at(factor: float,cursor: Vector2,viewport: Vector2)->void:
	var before=screen_to_world(cursor,viewport);set_zoom(zoom*factor);var after=screen_to_world(cursor,viewport);camera_x+=float(before[0])-float(after[0]);camera_y+=float(before[1])-float(after[1])
func pan_pixels(delta: Vector2)->void:camera_x-=delta.x/zoom;camera_y-=delta.y/zoom
func camera_snapshot()->Dictionary:return {"camera_x":camera_x,"camera_y":camera_y,"zoom":zoom,"lod":lod}
func save_bookmark(id: String)->bool:custom_bookmarks[id]=camera_snapshot();return true
func recall_bookmark(id: String)->bool:
	if custom_bookmarks.has(id):
		var b: Dictionary=custom_bookmarks[id];camera_x=b.camera_x;camera_y=b.camera_y;zoom=b.zoom;lod=int(b.lod);return true
	if not view.bookmarks.has(id):return false
	var b: Dictionary=view.bookmarks[id];camera_x=float(view.world_origin[0])+float(b.world_local[0]);camera_y=float(view.world_origin[1])+float(b.world_local[1])
	# A fixed review bookmark has a reproducible tier; continuous wheel zoom
	# retains the original hysteresis. Legacy bookmarks without lod are unchanged.
	if b.has("lod"):lod=int(b.lod)
	set_zoom(b.zoom);return true
func slot_center(id: String)->Vector2:
	var slot=host.slot_by_id(id);var p=Vector2.ZERO
	for point in slot.get("polygon_local_m",[]):p+=Vector2(point[0],point[1])
	return p/maxi(1,slot.get("polygon_local_m",[]).size())
func polygon_contains(point: Vector2,points: Array)->bool:
	var polygon=PackedVector2Array()
	for p in points:polygon.append(Vector2(p[0],p[1]))
	return Geometry2D.is_point_in_polygon(point,polygon)
func pick_entities(point: Vector2,viewport: Vector2)->void:
	var local=local_from_screen(point,viewport)
	for slot in host.layout.slots:
		if polygon_contains(local,slot.polygon_local_m):selected_slot=slot.id;selected_site="tongguan";return
func focus_module(id: String)->void:
	var p=slot_center(id) if not host.slot_by_id(id).is_empty() else Vector2.ZERO;camera_x=float(view.world_origin[0])+p.x;camera_y=float(view.world_origin[1])+p.y;set_zoom(2.4)
func focus_forest()->void:camera_x=float(view.world_origin[0])-2200;camera_y=float(view.world_origin[1])+650;set_zoom(0.45)
func gate_open()->bool:return bool(host.runtime.gate_open)
func set_gate_open(opened: bool)->bool:return bool(host.set_gate_open(opened).ok)
func sync_gate_from_host()->void:pass
func run_diagnostics(_force:=false)->Dictionary:
	return {"main_army":gate_open(),"direct_river":false,"light_unknown":gate_open(),"light_known":true,"control_feature_id":"main_valley","authority":"declared_preview_edges_only","campaign_movement_connected":false}
func draw_local_polygon(canvas: CanvasItem,points: Array,color: Color,viewport: Vector2)->void:
	# Triangulate once in local meters. Re-triangulating distant screen points
	# loses precision during the six-order-of-magnitude camera transition.
	var key=hash(points)
	if not polygon_indices.has(key):
		var local=PackedVector2Array()
		for p in points:local.append(Vector2(p[0],p[1]))
		polygon_indices[key]=Geometry2D.triangulate_polygon(local)
		if polygon_indices[key].is_empty():push_error("Invalid published polygon: "+str(key))
	if polygon_indices[key].is_empty():return
	var screen=PackedVector2Array()
	for p in points:screen.append(local_to_screen(p,viewport))
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),polygon_indices[key],screen,PackedColorArray([color]),PackedVector2Array())
func draw_overview(canvas: CanvasItem,viewport: Vector2,font: Font)->void:
	for shape in coarse.polygons:
		var points=[]
		for p in shape:points.append([(float(p[0])-float(coarse.site[0]))*1000,(float(p[1])-float(coarse.site[1]))*1000])
		draw_local_polygon(canvas,points,Color("c1c1a0"),viewport)
	if lod==0:canvas.draw_string(font,Vector2(20,60),"东亚粗示意底图 · 非历史疆界 / 真实地理仅限潼关工作区",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dce2cc"))
