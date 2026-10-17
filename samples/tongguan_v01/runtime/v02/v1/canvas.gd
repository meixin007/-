extends Control
signal camera_changed
var model: RefCounted
var rig: Node2D
var legacy: Control
var compare := false
var dragging := false
var last_mouse := Vector2.ZERO
func _ready() -> void:
	clip_contents=true; mouse_filter=Control.MOUSE_FILTER_STOP
	rig=load("res://v02/v1/composition.tscn").instantiate(); add_child(rig)
	legacy=load("res://review/canvas.gd").new(); legacy.model=model
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);legacy.font=font
	add_child(legacy); legacy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);legacy.mouse_filter=Control.MOUSE_FILTER_IGNORE;legacy.visible=false
	resized.connect(sync);sync()
func sync() -> void:
	if rig==null:return
	rig.position=model.site_screen(size);rig.scale=Vector2.ONE*model.zoom
	rig.visible=not compare;legacy.visible=compare; legacy.queue_redraw();rig.guide_layer.queue_redraw();queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("ded8be"))
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed;last_mouse=event.position
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			model.zoom_at(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.12,event.position,size);model.set_zoom(clampf(model.zoom,.42,2.4));sync();camera_changed.emit()
	elif event is InputEventMouseMotion and dragging:
		model.pan_pixels(event.position-last_mouse);last_mouse=event.position;sync();camera_changed.emit()
