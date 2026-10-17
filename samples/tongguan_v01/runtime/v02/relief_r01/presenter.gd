extends Node
## Composition around the frozen V2 app; source state/rules and old scenes are untouched.
var app: Control
var terrain: Node2D
var reference: Sprite2D
var contours: Node2D
var roads: Node2D
var mode:=0
var old:=false
var reference_mode:=false
var contour_rows: Array=[]
var _camera: Array=[]
var _appearance: Array=[]
var config: Dictionary
class InkLayer extends Node2D:
	var presenter: WeakRef
	var contour:=false
	func _draw() -> void:
		if presenter==null or presenter.get_ref()==null:return
		if contour:presenter.get_ref().draw_contours(self)
		else:presenter.get_ref().draw_roads(self)
class InputPane extends Control:
	var presenter: WeakRef
	func _gui_input(event: InputEvent) -> void:
		if presenter==null or presenter.get_ref()==null:return
		var host=presenter.get_ref();var model=host.app.model
		if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:model.pan_pixels(event.relative);host.refresh_camera()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:model.zoom_at(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.12,event.position,size);model.set_zoom(clampf(model.zoom,.06,2.4));host.refresh_camera()
func setup(parent: Node) -> void:
	app=load("res://v02/v2/app.gd").new();parent.add_child(app)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://v02/relief_r01/terrain.json"))
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://review/relief_contours.json"))
	for item in raw.features:
		var points=PackedVector2Array();var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
		for p in item.points_m:
			var q:=Vector2(p[0],p[1]);points.append(q);low=low.min(q);high=high.max(q)
		contour_rows.append({"points":points,"bounds":Rect2(low,high-low),"level":item.level_m})
	var rig=app.canvas.rig
	terrain=load("res://v02/relief_r01/terrain.tscn").instantiate();rig.get_node("Terrain").add_child(terrain)
	reference=Sprite2D.new();reference.name="IndependentFieldReference";reference.centered=false;reference.position=Vector2(config.bounds_m[0],config.bounds_m[1]);reference.scale=Vector2.ONE*.5;reference.region_enabled=true;reference.region_rect=Rect2(32,32,4096,3072);reference.region_filter_clip_enabled=false;reference.visible=false;terrain.add_child(reference);terrain.move_child(reference,2)
	var ink=InkLayer.new();ink.presenter=weakref(self);ink.z_index=7;ink.contour=true;rig.add_child(ink);contours=ink
	var route=InkLayer.new();route.presenter=weakref(self);route.z_index=1;rig.add_child(route);roads=route
	for child in app.get_children():
		if child is Label and child.position.y==17:child.text="潼关 / 高度场与脊谷结构修订"
		elif child is Label and child.position.y==58:child.text="F1 组合 / F2 地形独显 / F3 等高线校核 / F4 区域地势　·　O 新旧地形对照"
		elif child is Button and child.text=="地形独显　T":
			for connection in child.pressed.get_connections():child.pressed.disconnect(connection.callable)
			child.text="组合 / 地形 / 等高线　Tab";child.pressed.connect(func():set_mode((mode+1)%3))
	for i in 3:
		var button=Button.new();button.text=["F1　完整组合","F2　地形独显","F3　等高线校核"][i];button.position=Vector2(1030+i*195,18);button.size=Vector2(185,32);var selected:=i;button.pressed.connect(func():set_mode(selected));app.add_child(button)
	var pane=InputPane.new();pane.presenter=weakref(self);pane.position=app.canvas.position;pane.size=app.canvas.size;pane.mouse_filter=Control.MOUSE_FILTER_STOP;app.add_child(pane);app.canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.recall("composition");set_mode(0)
func set_mode(value: int) -> void:mode=value;_appearance=[];apply()
func set_old(value: bool) -> void:old=value;_appearance=[];apply()
func set_reference(value: bool) -> void:
	reference_mode=value
	reference.texture=load(config.reference_path) if value else null
	_appearance=[];apply()
func region_camera() -> void:
	app.model.camera_x=app.model.view.world_origin[0]-600;app.model.camera_y=app.model.view.world_origin[1]+800;app.model.set_zoom(.105);set_mode(1);refresh_camera()
func refresh_camera() -> void:app.canvas.sync();_appearance=[];apply()
func apply() -> void:
	if app==null:return
	app.canvas.terrain_only=mode!=0;app.canvas.sync()
	var rig=app.canvas.rig
	rig.get_node("Terrain/Ground").visible=old;rig.get_node("Terrain/Water").visible=old;terrain.visible=not old
	rig.paint_layer.visible=old and mode==0;app.canvas.overlay.visible=mode==0;roads.visible=not old and mode==0
	contours.visible=mode==2
	reference.visible=reference_mode
	for i in 12:terrain.get_node("Tile_%02d"%(2+2*i)).visible=not reference_mode
	contours.queue_redraw();roads.queue_redraw()
	_appearance=[mode,old,reference_mode]
func _process(_delta: float) -> void:
	if app==null:return
	var camera: Array=[app.model.camera_x,app.model.camera_y,app.model.zoom,app.canvas.terrain_only]
	if camera!=_camera or _appearance!=[mode,old,reference_mode]:apply();_camera=camera
func draw_roads(target: Node2D) -> void:
	var layout: Dictionary=app.model.host.layout
	var points=PackedVector2Array()
	for p in layout.fixed_refs.main_corridor:points.append(Vector2(p[0],p[1]))
	target.draw_polyline(points,Color("988c6d",.45),12,true);target.draw_polyline(points,Color("d2bb8c"),8,true);target.draw_polyline(points,Color("e0ce9e",.6),4,true)
	for road in layout.roads:
		points=PackedVector2Array()
		for p in road.points_m:points.append(Vector2(p[0],p[1]))
		target.draw_polyline(points,Color("a99b77"),7,true);target.draw_polyline(points,Color("d6c395"),4.6,true)
func draw_contours(target: Node2D) -> void:
	var model=app.model;var zoom: float=model.zoom
	var x: float=model.camera_x-model.view.world_origin[0];var y: float=model.camera_y-model.view.world_origin[1]
	var view:=Rect2(x-800/zoom,y-470/zoom,1600/zoom,940/zoom)
	for row in contour_rows:
		if not view.intersects(row.bounds):continue
		target.draw_polyline(row.points,Color("805d45",.60),.9/zoom,true)
		var anchor: Vector2=row.points[row.points.size()/2]
		if view.has_point(anchor):target.draw_string(ThemeDB.fallback_font,anchor+Vector2(3,-3)/zoom,"%dm"%row.level,HORIZONTAL_ALIGNMENT_LEFT,-1,clampi(roundi(12/zoom),6,160),Color("734f39"))
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode in [KEY_F1,KEY_F2,KEY_F3]:set_mode(event.keycode-KEY_F1)
	elif event.keycode==KEY_F4:region_camera()
	elif event.keycode==KEY_O:set_old(not old)
	elif event.keycode==KEY_TAB:set_mode((mode+1)%3)
