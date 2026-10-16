@tool
extends PanelContainer
## A dockable authoring panel. Drag/resize affects only workspace layout.
signal close_requested
signal float_requested
signal dock_requested
signal layout_changed
var header: HBoxContainer
var title_label: Label
var close_button: Button
var dock_button: Button
var body_scroll: ScrollContainer
var content: VBoxContainer
var footer: HBoxContainer
var resize_grip: Button
var floating := false
var allow_docking := false
var dragging := false
var resizing := false
var pointer_origin := Vector2.ZERO
var rect_origin := Rect2()
var parent_bounds: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("243330")
	style.border_color = Color("657a68")
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	add_child(column)
	header = HBoxContainer.new()
	header.custom_minimum_size.y = 32
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_header_input)
	column.add_child(header)
	title_label = Label.new()
	title_label.text = "面板"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	header.add_child(title_label)
	dock_button = Button.new()
	dock_button.text = "浮动"
	dock_button.visible = allow_docking
	dock_button.pressed.connect(func():
		if floating: dock_requested.emit()
		else: float_requested.emit())
	header.add_child(dock_button)
	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "关闭；可从顶部布局按钮恢复"
	close_button.pressed.connect(func(): close_requested.emit())
	header.add_child(close_button)
	body_scroll = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(body_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	body_scroll.add_child(content)
	footer = HBoxContainer.new()
	column.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	resize_grip = Button.new()
	resize_grip.text = "◢"
	resize_grip.tooltip_text = "拖动调整面板大小"
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_grip.gui_input.connect(_resize_input)
	footer.add_child(resize_grip)
	set_floating(floating)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): dragging=false; resizing=false)

func set_caption(text: String) -> void:
	title_label.text = text
	header.tooltip_text = "拖动标题栏移动窗口" if floating else "拖动标题栏可浮动；拖动面板之间的分隔线可调整宽度"

func set_floating(value: bool) -> void:
	floating = value
	if not is_instance_valid(resize_grip): return
	resize_grip.visible = value
	dock_button.visible = allow_docking
	dock_button.text = "收回" if value else "浮动"

func clear_content() -> VBoxContainer:
	body_scroll.remove_child(content)
	content.queue_free()
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	body_scroll.add_child(content)
	body_scroll.scroll_vertical = 0
	return content

func add_action(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	footer.add_child(button)
	footer.move_child(button,footer.get_child_count()-3)
	return button

func fit_inside() -> void:
	if not floating or not is_instance_valid(parent_bounds): return
	var extent := (parent_bounds.size-Vector2(16,16)).max(Vector2(160,120))
	size = size.clamp(Vector2(160,120).max(get_combined_minimum_size()),extent)
	position = position.clamp(Vector2(8,8),(parent_bounds.size-size-Vector2(8,8)).max(Vector2(8,8)))

func _header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = header.get_global_transform()*event.position
		if not floating and allow_docking: float_requested.emit()
		if not floating: return
		_begin_drag(point,false)
		accept_event()

func _resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_drag(resize_grip.get_global_transform()*event.position,true)
		accept_event()

func _begin_drag(point: Vector2, resize: bool) -> void:
	if not floating or not is_instance_valid(parent_bounds): return
	get_parent().move_child(self,get_parent().get_child_count()-1)
	dragging = not resize
	resizing = resize
	pointer_origin = parent_bounds.get_global_transform().affine_inverse()*point
	rect_origin = Rect2(position,size)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (dragging or resizing): return
	if event is InputEventMouseMotion:
		var pointer: Vector2 = parent_bounds.get_global_transform().affine_inverse()*event.position
		var delta := pointer-pointer_origin
		if dragging: position = rect_origin.position+delta
		else: size = rect_origin.size+delta
		fit_inside()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		resizing = false
		layout_changed.emit()
		get_viewport().set_input_as_handled()
