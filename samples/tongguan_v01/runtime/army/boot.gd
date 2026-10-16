extends Node
var acceptance: RefCounted
func _ready()->void:
	if OS.get_cmdline_user_args().has("--acceptance"):
		acceptance=load("res://army/acceptance.gd").new();await acceptance.run(self);acceptance=null;return
	var app=load("res://army/ui.gd").new();add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
