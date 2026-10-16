extends Control
signal changed
var host: RefCounted
var font: Font
var selected: String=""
var probe=Vector2(-2750,1250)
var center=Vector2(-2250,900)
var zoom:=0.7
var show_footprints:=true
var preview: Dictionary={}
var texture: Texture2D
var _dragging:=false
var _last:=Vector2.ZERO
var _distance:=0.0
func _ready()->void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	texture=load("res://r3_authoring/trees.png")
func screen(point: Array)->Vector2:return size*0.5+(Vector2(point[0],point[1])-center)*zoom
func local(point: Vector2)->Vector2:return center+(point-size*0.5)/zoom
func points(value: Array)->PackedVector2Array:
	var result=PackedVector2Array()
	for p in value:result.append(screen(p))
	return result
func label(at: Vector2,text: String,color: Color=Color("314d4d"))->void:draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
func _gui_input(event: InputEvent)->void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before=local(event.position);zoom=clampf(zoom*(1.18 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.18),0.05,3.0);center+=before-local(event.position);queue_redraw()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			_dragging=event.pressed;_last=event.position
			if event.pressed:_distance=0
			elif _distance<5:
				probe=local(event.position);var best=45.0*zoom;selected=""
				for object in host.state.objects.values():
					var distance=screen(object.position_m).distance_to(event.position)
					if distance<best:best=distance;selected=object.id
				changed.emit();queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		var delta=event.position-_last;_last=event.position;_distance+=delta.length();center-=delta/zoom;queue_redraw()
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("d0cfb3"))
	if host==null or font==null:return
	for x in range(-8192,8193,512):
		var at=screen([x,center.y]);draw_line(Vector2(at.x,0),Vector2(at.x,size.y),Color(0.3,0.4,0.4,0.14),1)
	for y in range(-8192,8193,512):
		var at=screen([center.x,y]);draw_line(Vector2(0,at.y),Vector2(size.x,at.y),Color(0.3,0.4,0.4,0.14),1)
	for road in host.source.layout.roads:
		var line: Array=host.state.feature_patches.get(road.id,{}).get("points_m",road.points_m);draw_polyline(points(line),Color("ae9260"),maxf(2,zoom*8),true)
	draw_polyline(points(host.source.layout.fixed_refs.main_corridor),Color("be9e62"),maxf(3,zoom*12),true)
	for slot in host.source.layout.slots:
		var polygon=points(slot.polygon_local_m);draw_colored_polygon(polygon,Color(0.4,0.6,0.4,0.3));polygon.append(polygon[0]);draw_polyline(polygon,Color("587b65"),1.5,true)
	var objects=host.state.objects.values();objects.sort_custom(func(a,b):return a.position_m[1]<b.position_m[1])
	for object in objects:
		var point=screen(object.position_m)
		if not Rect2(-120,-120,size.x+240,size.y+240).has_point(point):continue
		var rect=Rect2(point-Vector2(40,62.4)*zoom,Vector2(80,80)*zoom)
		var region=Rect2(1024,0,512,512) if int(object.asset_version)==1 else Rect2(512,512,512,512)
		draw_texture_rect_region(texture,rect,region,Color.WHITE,false,true)
		if show_footprints or object.id==selected:
			var footprint=points(host.rect_points(host.paint_bounds(object)));footprint.append(footprint[0]);draw_polyline(footprint,Color("f7d76a") if object.id==selected else Color(0.22,0.4,0.4,0.35),2.5 if object.id==selected else 1,true)
		if host.state.pins.has(object.id) or host.state.zone_pins.has(object.id):label(point+Vector2(5,-10),"锁",Color("6b4063"))
	for zone in host.state.zones.values():
		var polygon=points(zone.polygon_m);var color=Color("975f8b") if zone.kind=="lock" else Color("778a57")
		draw_colored_polygon(polygon,Color(color,0.2));polygon.append(polygon[0]);draw_polyline(polygon,color,2,true);label(polygon[0],"锁区" if zone.kind=="lock" else "排除生成",color)
	for id in preview.get("added",[]):
		var point=screen(preview.candidate_objects[id].position_m);draw_circle(point,8,Color(0.2,0.7,0.5,0.6))
	for id in preview.get("removed",[]):
		if host.state.objects.has(id):
			var point=screen(host.state.objects[id].position_m);draw_line(point-Vector2(6,6),point+Vector2(6,6),Color("b64743"),2);draw_line(point+Vector2(-6,6),point+Vector2(6,-6),Color("b64743"),2)
	for conflict in preview.get("conflicts",[]):
		if conflict.has("footprint_m"):
			var polygon=points(conflict.footprint_m);draw_colored_polygon(polygon,Color(0.8,0.2,0.2,0.3));polygon.append(polygon[0]);draw_polyline(polygon,Color("b63b35"),3,true)
	var cursor=screen([probe.x,probe.y]);draw_line(cursor-Vector2(9,0),cursor+Vector2(9,0),Color("7d4438"),2);draw_line(cursor-Vector2(0,9),cursor+Vector2(0,9),Color("7d4438"),2)
	draw_rect(Rect2(0,0,size.x,32),Color("203b40"));label(Vector2(12,22),"制作视图 · 512m网格 · 黄框选中 · 占地含树冠与边缘 · 滚轮缩放 / 拖动平移",Color("e1e7d7"))
