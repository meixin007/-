extends Control
const Adapter=preload("res://v02/v2/adapter.gd")
var model: RefCounted
var rig: Node2D
var atlas: Dictionary={}
var assets: Dictionary={}
var plan: Dictionary={}
var terrain_only:=false
var guide:=false
var legacy:=false
var show_sample_trees:=true
var presenter: WeakRef
var overlay: Node2D
var original_slots: Array=[]
class Overlay extends Node2D:
	var host: WeakRef
	func _draw() -> void:
		if host!=null and host.get_ref()!=null:host.get_ref().paint_overlay(self)
func army():return get_node("/root/Session").army
func _ready() -> void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	assets=JSON.parse_string(FileAccess.get_file_as_string("res://v02/v2/assets.json"))
	for key in assets.assets:atlas[key]=load(assets.assets[key].path)
	rig=load("res://v02/v2/composition.tscn").instantiate();add_child(rig)
	original_slots=rig.layout.slots.duplicate(true)
	for node in rig.get_node("Objects").get_children():
		if node.name.begins_with("Tree_"):node.set_meta("v1_sample_id","v1.preview."+str(node.name))
	var published: Dictionary=army().authoring_projection()
	for id in published.generated:
		var record: Dictionary=published.generated[id];var tree=Sprite2D.new();tree.name=id
		tree.texture=rig.get_node("Objects/Gate").texture # replaced with the original tree atlas region
		var texture=AtlasTexture.new();texture.atlas=load("res://bundle/art/trees.png");texture.region=Rect2(1024,0,512,512) if int(record.asset_version)==1 else Rect2(512,512,512,512);texture.filter_clip=true
		tree.texture=texture;tree.centered=false;tree.offset=Vector2(-256,-399.36);tree.scale=Vector2.ONE*(80.0/512);tree.position=Vector2(record.position_m[0],record.position_m[1]);tree.set_meta("source_id",id);rig.get_node("Objects").add_child(tree)
	overlay=Overlay.new();overlay.host=weakref(self);overlay.z_index=4;rig.add_child(overlay)
	resized.connect(sync);sync()
func sync() -> void:
	if rig==null:return
	rig.position=model.site_screen(size);rig.scale=Vector2.ONE*model.zoom
	plan=Adapter.new().project(army(),model.host)
	for item in plan.records:
		var node: Sprite2D=rig.get_node("Objects/Warehouse" if item.slot_id==Adapter.STORAGE else "Objects/Barracks")
		node.position=Vector2(item.position_m[0],item.position_m[1]);node.modulate=Color.WHITE
		node.visible=not terrain_only and item.construction_state=="built"
		if not item.asset_id.is_empty():node.texture=atlas["warehouse" if legacy and item.slot_id==Adapter.STORAGE else item.asset_id]
	rig.get_node("Objects/SouthWall").texture=atlas["wall_ns" if legacy else plan.wall_asset]
	rig.set_layers(terrain_only,true,true,true)
	for node in rig.get_node("Objects").get_children():
		if node.has_meta("v1_sample_id"):node.visible=not terrain_only and show_sample_trees
	for item in plan.records:rig.get_node("Objects/Warehouse" if item.slot_id==Adapter.STORAGE else "Objects/Barracks").visible=not terrain_only and item.construction_state=="built"
	rig.guides=guide;overlay.queue_redraw();queue_redraw()
func _draw() -> void:draw_rect(Rect2(Vector2.ZERO,size),Color("ded8be"))
func paint_overlay(target: Node2D) -> void:
	if plan.is_empty():return
	# Roads are purely painted extensions from the original registered sockets.
	for item in plan.records:
		var slot: Dictionary=model.host.slot_by_id(item.slot_id);var p:=Vector2(item.position_m[0],item.position_m[1]);var entry:=p+Vector2(142,140)*(80.0/1536)
		target.draw_polyline(PackedVector2Array([Vector2(slot.road_socket_m[0],slot.road_socket_m[1]),entry]),Color("d2bb8c"),3.0,true)
		if terrain_only:continue
		if item.construction_state=="building":
			var polygon=PackedVector2Array()
			for point in slot.polygon_local_m:polygon.append(Vector2(point[0],point[1]))
			target.draw_colored_polygon(polygon,Color("b5a27d",.65));polygon.append(polygon[0]);target.draw_polyline(polygon,Color("796d52"),.8,true)
			for point in polygon:target.draw_line(point,point-Vector2(0,8),Color("7f6441"),1.4,true)
		if guide:
			var polygon=PackedVector2Array()
			for point in slot.polygon_local_m:polygon.append(Vector2(point[0],point[1]))
			polygon.append(polygon[0]);target.draw_polyline(polygon,Color("54867c"),.7,true);target.draw_circle(p,1.4,Color("bd6144"))
	if not terrain_only:
		var local: Array=army().position_local();var p:=Vector2(local[0],local[1]);target.draw_line(p,p-Vector2(0,16),Color("5a5245"),1.2,true);target.draw_colored_polygon(PackedVector2Array([p-Vector2(0,16),p+Vector2(13,-12),p-Vector2(0,8)]),Color("b57649"))
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:model.pan_pixels(event.relative);sync()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:model.zoom_at(1.12,event.position,size);model.set_zoom(clampf(model.zoom,.42,2.4));sync()
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:model.zoom_at(1/1.12,event.position,size);model.set_zoom(clampf(model.zoom,.42,2.4));sync()
