@tool
extends Control
## In-workbench modal shell: header/footer never participate in content scrolling.
const Surface = preload("workspace_panel.gd")
signal confirmed
signal canceled
var panel
var content: VBoxContainer
var confirm_button: Button
var cancel_button: Button
var title := "设置"
var dialog_text := ""
var ok_button_text := "确认"
var cancel_button_text := "取消"
var _return_focus: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.03,0.06,0.05,0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = Surface.new()
	panel.floating = true
	panel.parent_bounds = self
	panel.custom_minimum_size = Vector2(360,170)
	add_child(panel)
	content = panel.content
	panel.close_button.tooltip_text = "关闭（Esc），放弃尚未应用的设置"
	panel.close_requested.connect(_cancel)
	cancel_button = panel.add_action(cancel_button_text,_cancel)
	confirm_button = panel.add_action(ok_button_text,func(): hide(); confirmed.emit(); _restore_focus())
	resized.connect(func(): if visible: panel.fit_inside())
	hide()

func clear_content() -> VBoxContainer:
	content = panel.clear_content()
	return content

func popup_centered(dimensions: Vector2i = Vector2i(520,320)) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	get_parent().move_child(self,get_parent().get_child_count()-1)
	panel.set_caption(title)
	confirm_button.text = ok_button_text
	cancel_button.text = cancel_button_text
	if not dialog_text.is_empty():
		clear_content()
		var label := Label.new()
		label.text = dialog_text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	show()
	panel.size = Vector2(dimensions).min((size-Vector2(32,32)).max(Vector2(360,170)))
	panel.position = (size-panel.size)*0.5
	panel.fit_inside()
	confirm_button.grab_focus()

func get_panel_rect() -> Rect2:
	return Rect2(panel.position,panel.size)

func get_ok_button() -> Button: return confirm_button
func get_cancel_button() -> Button: return cancel_button

func _cancel() -> void:
	hide()
	canceled.emit()
	_restore_focus()

func _restore_focus() -> void:
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree(): _return_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()
