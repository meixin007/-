@tool
extends Control
const Doc = preload("document.gd")
var canvas: Control
var last_view := Rect2()
var dragging := false
var background: Control
var drawn_document: RefCounted
var drawn_geometry := -1
var meshes: Array[ArrayMesh] = []
func _ready() -> void:
	background=Control.new()
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent=true
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.draw.connect(_draw_map)
	resized.connect(background.queue_redraw)
	custom_minimum_size = Vector2(200,125)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "点击或拖动小地图定位；橙框是当前视野"
func map_rect() -> Rect2:
	if canvas == null: return Rect2()
	var extent := Vector2(canvas.doc.data.canvas_size[0],canvas.doc.data.canvas_size[1])
	var ratio := minf((size.x-12)/extent.x,(size.y-12)/extent.y)
	return Rect2((size-extent*ratio)*0.5,extent*ratio)
func _process(_delta: float) -> void:
	if canvas == null: return
	if drawn_document != canvas.doc or drawn_geometry != canvas.geometry_revision:
		drawn_document=canvas.doc; drawn_geometry=canvas.geometry_revision
		background.queue_redraw()
	var view: Rect2 = canvas.visible_world_rect()
	if view != last_view: last_view=view; queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if canvas == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and dragging:
		var rect := map_rect()
		var point: Vector2 = (event.position-rect.position)/rect.size
		canvas.center_on(point.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(canvas.doc.data.canvas_size[0],canvas.doc.data.canvas_size[1]))
		accept_event()
func _draw_map() -> void:
	meshes.clear()
	background.draw_rect(Rect2(Vector2.ZERO,size),Color("182323"))
	if canvas == null: return
	var rect := map_rect()
	var ratio: float = rect.size.x/canvas.doc.data.canvas_size[0]
	background.draw_rect(rect,Color("e7dfc7"))
	for layer in canvas.doc.data.layers:
		if not layer.visible: continue
		for f in canvas.doc.data.features:
			if f.layer != layer.id: continue
			if f.kind=="prefecture": continue
			var points := Doc.packed(f.points)
			for i in range(points.size()): points[i] = rect.position+points[i]*ratio
			if f.kind in Doc.POLYGONS:
				var vertices:=PackedVector3Array()
				for triangle in canvas.polygon_meshes.get(f.id,[]):
					for p in triangle:
						var point: Vector2=rect.position+p*ratio
						vertices.append(Vector3(point.x,point.y,0))
				if not vertices.is_empty():
					var mesh:=ArrayMesh.new()
					var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
					meshes.append(mesh)
					background.draw_mesh(mesh,null,Transform2D.IDENTITY,canvas.COLORS[f.kind])

			elif f.kind in Doc.LINES: background.draw_polyline(points,Color("638695") if f.kind == "river" else Color("a58e68"),1.0,true)
			else: background.draw_circle(points[0],2,Color("624c36"))

func _draw() -> void:
	if canvas == null: return
	var rect:=map_rect()
	var ratio: float=rect.size.x/canvas.doc.data.canvas_size[0]
	var view: Rect2 = canvas.visible_world_rect()
	draw_rect(Rect2(rect.position+view.position*ratio,view.size*ratio),Color("e29037"),false,2)
