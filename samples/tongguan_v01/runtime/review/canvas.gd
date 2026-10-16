extends "res://army/canvas.gd"
const Rules=preload("res://review/view_rules.gd")
var rules=Rules.new()
var policy: Dictionary={}
var audit: Dictionary={}
var contour_lines: Array=[]
var water_shapes: Array=[]
var overview_shapes: Array=[]
var baseline_view:=false
var show_contours:=true
var show_crossings:=true
var show_footprints:=false
var label_rects: Array=[]
func _ready()->void:
	super._ready()
	policy=JSON.parse_string(FileAccess.get_file_as_string("res://review/policy.json"))
	audit=JSON.parse_string(FileAccess.get_file_as_string("res://review/geometry_audit.json"))
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://review/relief_contours.json"))
	for contour in raw.features:
		var points=PackedVector2Array();var box=Rect2()
		for p in contour.points_m:
			var value=Vector2(p[0],p[1]);points.append(value)
			box=Rect2(value,Vector2.ZERO) if points.size()==1 else box.expand(value)
		contour_lines.append({"points":points,"bounds":box,"level":contour.level_m})
	for feature in model.water.features:
		water_shapes.append(_cached_shape(feature.points_m,feature.geometry=="polygon"))
	for shape in model.coarse.polygons:
		var local=[]
		for p in shape:local.append([(float(p[0])-float(model.coarse.site[0]))*1000,(float(p[1])-float(model.coarse.site[1]))*1000])
		overview_shapes.append(_cached_shape(local,true))
func _cached_shape(raw: Array,polygon: bool)->Dictionary:
	var points=PackedVector2Array();var box=Rect2()
	for p in raw:
		var v=Vector2(p[0],p[1]);points.append(v);box=Rect2(v,Vector2.ZERO) if points.size()==1 else box.expand(v)
	var result={"points":points,"bounds":box,"polygon":polygon}
	if polygon:
		result.indices=Geometry2D.triangulate_polygon(points);result.outline=points.duplicate();result.outline.append(points[0])
	return result
func _cached_polygon(shape: Dictionary,color: Color)->void:
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),shape.indices,shape.points,PackedColorArray([color]),PackedVector2Array())
func _visible_local()->Rect2:
	var a: Vector2=model.local_from_screen(Vector2.ZERO,size)
	var b: Vector2=model.local_from_screen(size,size)
	return Rect2(a,b-a).grow(180)
func _path(points: Array,color: Color,width: float,dashed:=false)->void:
	var screen=points_screen(points)
	if screen.size()<2:return
	if dashed:
		for i in range(screen.size()-1):draw_dashed_line(screen[i],screen[i+1],color,width,7,true)
	else:draw_polyline(screen,color,width,true)
func _walls()->void:
	var site: Vector2=model.site_screen(size)
	var rect=rules.gate_rect(site,model.zoom,policy)
	var alpha=rules.gate_alpha(model.zoom)
	for id in ["north","south"]:
		var local=[]
		for point in policy.wall[id+"_local_m"]:
			if Vector2(point[0],point[1]).length()<=float(policy.wall.display_limit_from_gate_m):local.append(point)
		var path=points_screen(local)
		var socket=rules.socket(rect,policy.gate["socket_"+id+"_px"],policy)
		if id=="north":path.append(socket)
		else:path.insert(0,socket)
		var damage=int(model.host.runtime.module_damage["wall_west" if id=="north" else "wall_east"])
		var color=Color("b4aa92") if damage==0 else Color("9c8774")
		draw_polyline(path,Color("596453",0.6*alpha),maxf(2.0,model.zoom*8),true)
		draw_polyline(path,Color(color,alpha),maxf(1.5,model.zoom*(5 if damage<2 else 2)),true)
		if model.zoom>0.5 and damage<2:
			for i in range(path.size()-1):
				var count=maxi(1,int(path[i].distance_to(path[i+1])/22))
				for j in count:
					var at=path[i].lerp(path[i+1],(float(j)+0.3)/count)
					draw_circle(at,maxf(1.2,model.zoom*1.4),Color("d8c9aa",alpha))
func _courtyards()->void:
	var authored: Dictionary=model.host.authoring
	for road in authored.roads:
		_path(road.points_m,Color("9e9270"),maxf(1.4,model.zoom*6))
		_path(road.points_m,Color("d3bc88"),maxf(1.0,model.zoom*3.2))
	for index in model.host.layout.slots.size():
		var slot: Dictionary=model.host.layout.slots[index]
		var occupied: Dictionary=model.host.runtime.slot_occupancy[slot.id]
		var center: Vector2=model.slot_center(slot.id)
		var selected=slot.id==model.selected_slot
		var unlocked=int(model.host.runtime.growth_stage)>=int(slot.unlock_stage)
		var screen=points_screen(slot.polygon_local_m)
		var fill=Color("d1bd91") if unlocked else Color("a7ac96")
		draw_colored_polygon(screen,Color(fill,0.22 if occupied.status=="empty" else 0.38))
		screen.append(screen[0]);draw_polyline(screen,Color("f8df99") if selected else Color(fill,0.75),2 if selected else 1,true)
		var socket: Vector2=model.local_to_screen(slot.road_socket_m,size)
		var edge: Vector2=model.local_to_screen([center.x,slot.polygon_local_m[2][1] if index<4 else slot.polygon_local_m[0][1]],size)
		draw_line(socket,edge,Color("c4b081"),maxf(1,model.zoom*2),true)
		if show_buildings and occupied.status!="empty":
			var offset: Array=authored.manual_overrides.get(slot.id,{}).get("offset_m",[0,0])
			_building(center+Vector2(offset[0],offset[1]),occupied.building_type,int(model.host.runtime.module_damage[slot.id]),occupied.status=="building")
		if show_footprints:
			for row in audit.slots:
				if row.id==slot.id:
					var footprint=points_screen(row.footprint_m);footprint.append(footprint[0]);draw_polyline(footprint,Color("65978c"),1.5,true)
		if model.zoom>0.8:
			_label(model.local_to_screen([center.x,center.y],size)+Vector2(-5,-21*model.zoom),str(index+1),Color("3c4d42"),14)
func _constraints()->void:
	for c in model.recipe.constraints:
		if c.has("external_geometry"):continue
		var color=Color("ba7261")
		if c.kind=="highground":color=Color("827f62")
		elif c.kind=="city_allowed":color=Color("648f74")
		elif c.kind=="main_corridor":color=Color("bc9a5e")
		if c.geometry=="polygon":
			model.draw_local_polygon(self,c.points_m,Color(color,0.12),size)
			var points=points_screen(c.points_m);points.append(points[0]);draw_polyline(points,Color(color,0.6),1.2,true)
		else:_path(c.points_m,Color(color,0.55),2,true)
	var site: Vector2=model.site_screen(size)
	draw_arc(site,1500*model.zoom,0,TAU,120,Color("c89c60",0.65),1,true)
func _registered_routes()->void:
	var runtime=army();var routes=runtime.effective_corridors()
	if show_route and model.lod>0:
		for route in routes.values():
			if route.corridor_id=="tg_synthetic_trail":
				_path(route.points_m,Color("9a8076",0.8) if route.is_blocked else Color("609f9a"),1.5,true)
			else:
				_path(route.points_m,Color("817551"),maxf(2,model.zoom*5.5))
				_path(route.points_m,Color("d7c08c"),maxf(1.5,model.zoom*3.0))
				if route.corridor_id=="tg_main_gate":_path(route.points_m,Color("a44d47") if route.is_blocked else Color("5b9874"),2)
		for id in ["tg_fore","tg_rear"]:
			var at: Vector2=model.local_to_screen(runtime.context.state.strategic_nodes[id].position_m,size)
			draw_circle(at,3,Color("9f895d"))
func _army_overlay()->Array:
	var state=army().snapshot()
	var local=visual_position();var at: Vector2=model.local_to_screen([local.x,local.y],size)
	if not Rect2(-30,-30,size.x+60,size.y+60).has_point(at):return []
	# Strategic unit marker stays above art; it is not an occluding soldier sprite.
	var tint=Color("efb86d") if state.order.status=="waiting" else Color("73c6db")
	draw_circle(at,9,Color("234a55"));draw_arc(at,11,0,TAU,36,tint,2,true)
	if model.lod>0:
		draw_line(at+Vector2(0,-2),at+Vector2(0,-30),Color("334c50"),2,true)
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-30),at+Vector2(20,-25),at+Vector2(0,-18)]),tint)
	return [{"id":"army","priority":90,"at":at+Vector2(-55,-58),"size":Vector2(135,22),"text":"验收队 · 100人","color":Color("263f45")}]
func _draw()->void:
	if baseline_view:
		super._draw()
		return
	draw_rect(Rect2(Vector2.ZERO,size),Color("8db3ba"))
	if model==null or font==null or policy.is_empty() or not model.load_error.is_empty():return
	# Static local-meter geometry is packed/triangulated once. Subtract the
	# double-precision world origin before setting the renderer transform.
	var visible=_visible_local()
	draw_set_transform(model.site_screen(size),0,Vector2.ONE*model.zoom)
	for shape in overview_shapes:
		if visible.intersects(shape.bounds):_cached_polygon(shape,Color("c1c1a0"))
	draw_set_transform(Vector2.ZERO)
	if model.lod==0:draw_string(font,Vector2(20,60),"东亚粗示意底图 · 非历史疆界 / 真实地理仅限潼关工作区",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dce2cc"))
	var top_left: Vector2=model.local_to_screen([-12000,-8000],size)
	var bounds=Rect2(top_left,Vector2(24000,16000)*model.zoom)
	if show_slope:draw_texture_rect(slope_texture,bounds,false)
	else:get_node("/root/Session").cache.draw_terrain(self,bounds)
	draw_set_transform(model.site_screen(size),0,Vector2.ONE*model.zoom)
	if show_contours and model.lod>0:
		for contour in contour_lines:
			if not visible.intersects(contour.bounds):continue
			draw_polyline(contour.points,Color("7b8064",0.22),0.8/model.zoom,true)
	if show_water:
		for shape in water_shapes:
			if not visible.intersects(shape.bounds):continue
			if shape.polygon:
				_cached_polygon(shape,Color("91bac0"));draw_polyline(shape.outline,Color("668d91"),1/model.zoom,true)
			else:draw_polyline(shape.points,Color("64949f"),maxf(0.8/model.zoom,3),true)
	draw_set_transform(Vector2.ZERO)
	if show_constraints:_constraints()
	if model.lod>0:
		# Extend the visible design line to the real rear-road socket. It remains dashed.
		_path(model.host.layout.fixed_refs.main_corridor,Color("b5996c",0.8),maxf(1.2,model.zoom*3),true)
	if show_trees and model.lod>=2:
		var trees: Array=model.host.authoring.generated.values()
		trees.sort_custom(func(a: Dictionary,b: Dictionary):return float(a.position_m[1])<float(b.position_m[1]))
		for tree in trees:_tree(tree)
	if model.lod>=2:_courtyards()
	_registered_routes()
	var site: Vector2=model.site_screen(size)
	if show_buildings and model.lod>=2:_walls()
	if show_icon and gate_texture!=null and rules.gate_alpha(model.zoom)>0:
		draw_texture_rect(gate_texture,rules.gate_rect(site,model.zoom,policy),false,Color(1,1,1,rules.gate_alpha(model.zoom)))
		var damage=int(model.host.runtime.module_damage.gate)
		if damage>0:
			var rect=rules.gate_rect(site,model.zoom,policy)
			var mark=site+Vector2(rect.size.x*0.05,-rect.size.y*0.15)
			draw_line(mark-Vector2(8,21),mark+Vector2(9,13),Color("93594a"),3,true)
			if damage==2:draw_arc(mark,19,0,TAU,30,Color("93594a",0.8),3,true)
			_label(site+Vector2(32,-32),"损毁占位 %d"%damage,Color("824c42"),14)
	draw_arc(site,10,0,TAU,40,Color("f2da97"),1.6,true)
	if model.lod>0:
		draw_line(site-Vector2(0,9),site+Vector2(0,9),Color("5a9b78") if model.gate_open() else Color("b25e53"),2.5,true)
	if show_crossings and model.lod>0:
		for crossing in audit.candidate_crossings:
			for point in crossing.points_m:
				var at: Vector2=model.local_to_screen(point,size)
				draw_arc(at,9,0,TAU,24,Color("a66051"),1.5,true)
				if model.zoom>0.2:_label(at+Vector2(12,-6),"跨沟待核",Color("875548"),13)
	var labels=_army_overlay()
	var site_label=site+Vector2(18,21)
	if model.lod>=2 and show_icon:
		var gate_rect=rules.gate_rect(site,model.zoom,policy)
		site_label=gate_rect.position+Vector2(gate_rect.size.x*0.65,-15)
	labels.append({"id":"site","priority":100,"at":site_label,"size":Vector2(150,23),"text":"潼关 · 756候选","color":Color("33483f")})
	if model.lod>=2 and show_footprints:
		var slot: Dictionary=model.host.slot_by_id(model.selected_slot);var center: Vector2=model.slot_center(slot.id)
		labels.append({"id":"selected","priority":95,"at":model.local_to_screen([center.x,center.y],size)+Vector2(-20,20),"size":Vector2(110,22),"text":str(slot.name)+" · 地块","color":Color("3b5648")})
	label_rects=rules.place_labels(labels,Rect2(8,40,size.x-16,size.y-85))
	for item in label_rects:
		draw_rect(Rect2(item.at-Vector2(3,1),item.size),Color("e6dfc9",0.9))
		_label(item.at+Vector2(0,16),item.text,item.color,15)
	# Metric and direction guides do not rotate the map or assert true north.
	draw_rect(Rect2(0,0,size.x,33),Color("253f40",0.94))
	_label(Vector2(12,23),"实线：登记通道　虚线：设计候选　红圈：跨沟待核　|　地形 / 水系为现代参照",Color("dce2d0"),14)
	_label(Vector2(size.x-84,57),"↑ 格网北",Color("3d5950"),13)
	var distance=2000.0 if model.zoom<0.1 else (500.0 if model.zoom<0.5 else 100.0)
	if model.lod>0:
		draw_rect(Rect2(12,size.y-39,distance*model.zoom+80,30),Color("253f40",0.9))
		draw_line(Vector2(22,size.y-22),Vector2(22+distance*model.zoom,size.y-22),Color("e8e3d0"),2,true)
		_label(Vector2(30+distance*model.zoom,size.y-17),"%d m"%distance,Color("e8e3d0"),13)
