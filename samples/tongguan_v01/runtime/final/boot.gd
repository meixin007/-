extends Node
var acceptance: RefCounted
func _ready()->void:
	if OS.get_cmdline_user_args().has("--probe-build"):
		var target="user://build_probe.json"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--report="):target=arg.substr(9)
		var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://final/build_manifest.json"))
		FileAccess.open(target,FileAccess.WRITE).store_string(JSON.stringify({"build_id":manifest.build_id,"release":not OS.is_debug_build(),"world_id":manifest.world_id}))
		get_tree().quit();return
	if OS.get_cmdline_user_args().has("--acceptance"):
		acceptance=load("res://final/acceptance.gd").new();await acceptance.run(self);acceptance=null;return
	var app=load("res://final/ui.gd").new();add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
