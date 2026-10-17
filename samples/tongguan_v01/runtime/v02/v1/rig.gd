@tool
extends Node2D
## Presentation only. All source geometry and shared state are read-only here.
var style: Dictionary = {}
var layout: Dictionary = {}
var water: Dictionary = {}
var guides := false:
	set(value):
		guides=value
		if is_instance_valid(guide_layer): guide_layer.queue_redraw()
var terrain_only := false
var guide_layer: Node2D
var paint_layer: Node2D
class PaintLayer extends Node2D:
	var rig: WeakRef
	var overlay := false
	func _draw() -> void:
		if rig == null or rig.get_ref() == null: return
		if overlay: rig.get_ref().draw_guides(self)
		else: rig.get_ref().paint(self)
func _ready() -> void:
	style=JSON.parse_string(FileAccess.get_file_as_string("res://v02/v1/style.json"))
	layout=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/layout.json"))
	water=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/modern_water.json"))
	paint_layer=PaintLayer.new(); paint_layer.name="RoadsAndBrushes"; paint_layer.z_index=1; paint_layer.rig=weakref(self); add_child(paint_layer); move_child(paint_layer,1)
	guide_layer=PaintLayer.new(); guide_layer.name="SocketGuides"; guide_layer.z_index=5; guide_layer.rig=weakref(self); guide_layer.overlay=true; add_child(guide_layer)
func points(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in raw: result.append(Vector2(float(p[0]),float(p[1])))
	return result
func warehouse_entry() -> Vector2:
	return $Objects/Warehouse.position + Vector2(142,140)*(80.0/1536.0)
func socket_error() -> float:
	var gate: Sprite2D=$Objects/Gate
	var north: Vector2=gate.position+(Vector2(544,268)-Vector2(665,690))*gate.scale
	var south: Vector2=gate.position+(Vector2(1097,956)-Vector2(665,690))*gate.scale
	var north_wall: Sprite2D=$Objects/NorthWall
	var south_wall: Sprite2D=$Objects/SouthWall
	var north_cut: Vector2=north_wall.position+Vector2(625,510)*north_wall.scale-Vector2(7,6)
	# The south joint inserts 8m into the opaque end cap. This is a paint
	# socket, not a moved ground anchor or an asserted historical wall point.
	return maxf(north.distance_to(north_cut),south.distance_to(south_wall.position+Vector2(8,2)))
func paint(canvas: Node2D) -> void:
	# Shores follow the existing modern water polygon. Short broken pen lines
	# and translucent edges are stylistic, not new geographic/route features.
	if $Terrain/Water.visible:
		for feature in water.get("features",[]):
			if feature.geometry != "polygon": continue
			var p: PackedVector2Array=points(feature.points_m)
			if p.size()<3: continue
			for i in range(p.size()-1):
				var a: Vector2=p[i];var b: Vector2=p[i+1];var delta: Vector2=b-a
				if delta.length()<2 or delta.length()>180:continue
				var normal:=Vector2(-delta.y,delta.x).normalized()
				if Geometry2D.is_point_in_polygon((a+b)*.5+normal*5,p):normal=-normal
				if normal.y>.15:
					var foot:=normal*18
					canvas.draw_colored_polygon(PackedVector2Array([a,b,b+foot,a+foot]),Color("aaa485",.52))
					canvas.draw_line(a+foot,b+foot,Color("8d9679",.30),2.1,true)
					if i%4==0:canvas.draw_line(a+normal*3,a+normal*15,Color("7c8b76",.25),.9,true)
			p.append(p[0]); canvas.draw_polyline(p,Color("b9af8c",.42),8.0,true)
			canvas.draw_polyline(p,Color("687f78",.60),1.15,true)
			for i in range(0,p.size()-1,3):
				if p[i].distance_to(p[i+1])<80: canvas.draw_line(p[i],p[i].lerp(p[i+1],.62),Color("e3dfc2",.6),1.5,true)
	# Only existing centerlines; source sockets/permissions are not rewritten.
	var path: PackedVector2Array=points(layout.fixed_refs.main_corridor)
	canvas.draw_polyline(path,Color("988c6d",.45),12.0,true)
	canvas.draw_polyline(path,Color(style.palette.road),8.0,true)
	canvas.draw_polyline(path,Color("e0ce9e",.6),4.0,true)
	for road in layout.roads:
		canvas.draw_polyline(points(road.points_m),Color("a99b77"),7.0,true)
		canvas.draw_polyline(points(road.points_m),Color("d6c395"),4.6,true)
	var entry := warehouse_entry()
	canvas.draw_polyline(PackedVector2Array([Vector2(-567.5,-205),Vector2(-565,-212),entry]),Color("cdbb8f"),4.0,true)
	if not terrain_only:
		for location in style.sample_trees_m:
			var at:=Vector2(location[0],location[1])
			canvas.draw_set_transform(at,0,Vector2(1,.35)); canvas.draw_circle(Vector2.ZERO,13,Color("4b5945",.10)); canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_set_transform(Vector2(0,2),0,Vector2(1,.28)); canvas.draw_circle(Vector2.ZERO,49,Color("706647",.09));canvas.draw_set_transform(Vector2.ZERO)
	# Sparse irregular slope-foot marks, independently editable source points.
	for mark in [[-950,355,-880,340],[-870,370,-790,347],[-410,310,-338,294],[280,365,350,345],[330,390,390,374]]:
		canvas.draw_line(Vector2(mark[0],mark[1]),Vector2(mark[2],mark[3]),Color("7f8968",.27),2.0,true)
	for i in 12:
		var at:=Vector2(-930+i*105,385+sin(i*2.1)*38)
		canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(-6,1),at+Vector2(-2,-3),at+Vector2(4,-2),at+Vector2(7,2)]),Color("9b9b7c",.35))
func draw_guides(canvas: Node2D) -> void:
	if not guides: return
	var width: float=1.2/maxf(scale.x,.1)
	for x in range(-1024,1025,512):canvas.draw_dashed_line(Vector2(x,-1024),Vector2(x,512),Color("4f9197",.38),width,10)
	for y in range(-1024,513,512):canvas.draw_dashed_line(Vector2(-1024,y),Vector2(1024,y),Color("4f9197",.38),width,10)
	var gate: Sprite2D=$Objects/Gate
	for px in [Vector2(544,268),Vector2(1097,956),Vector2(665,690)]:
		var p: Vector2=gate.position+(px-Vector2(665,690))*gate.scale
		canvas.draw_circle(p,4/maxf(scale.x,.1),Color("c45e3c")); canvas.draw_line(p-Vector2(10,0),p+Vector2(10,0),Color.WHITE,width,true)
	canvas.draw_polyline(points(layout.fixed_refs.main_corridor),Color("b85c3d",.7),width,true)
	for slot in layout.slots:
		var p:=points(slot.polygon_local_m);p.append(p[0]);canvas.draw_polyline(p,Color("8c7959",.75),width,true)
	var origin:=Vector2(0,0)
	canvas.draw_line(origin,Vector2(120,0),Color("b15b41"),width*1.5,true)
	canvas.draw_line(origin,Vector2(0,120),Color("4b7d76"),width*1.5,true)
	canvas.draw_circle(warehouse_entry(),4/maxf(scale.x,.1),Color("478a91"))
func set_layers(terrain: bool, trees: bool, buildings: bool, show_water: bool) -> void:
	terrain_only=terrain
	$Terrain/Water.visible=show_water
	for node in $Objects.get_children():
		node.visible=not terrain and (trees if node.name.begins_with("Tree_") else buildings)
	paint_layer.queue_redraw()
