extends Control

signal view_changed
var model: RefCounted
var font: Font
var dragging := false
var drag_distance := 0.0
var last_pointer := Vector2.ZERO
const INK := Color("354951")
const PAPER := Color("e6e3d4")
const WATER := Color("8fb5be")

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if model == null or not model.load_error.is_empty(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				model.zoom_at(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, event.position, size)
				view_changed.emit()
				queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				dragging = true
				drag_distance = 0.0
				last_pointer = event.position
			else:
				if dragging and drag_distance < 5.0 and event.button_index == MOUSE_BUTTON_LEFT:
					model.selected_site = model.pick_site(event.position, size)
				dragging = false
				view_changed.emit()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_pointer
		drag_distance += delta.length()
		model.pan_pixels(delta)
		last_pointer = event.position
		view_changed.emit()
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		model.zoom_at(event.factor, event.position, size)
		view_changed.emit()
		queue_redraw()

func _label(at: Vector2, text: String, color: Color = INK, font_size: int = 16) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _local_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(model.local_to_screen(point, size))
	return result

func _sample_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(model.sample_to_screen(point, size))
	return result

