extends Node
var probe: RefCounted
func _ready() -> void:
	var session = get_node("/root/Session")
	if not session.startup_error.is_empty(): get_tree().quit(1); return
	if OS.get_cmdline_user_args().has("--s0-probe"):
		var script = load("res://v02/probe.gd")
		if script == null or not script.can_instantiate():
			printerr("S0 probe cannot be instantiated."); get_tree().quit(1); return
		probe = script.new()
		await probe.run(self)
		probe = null
		return
	var app = load("res://final/ui.gd").new()
	add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.save_path = "user://tests/map_v02/manual/session.json"
	app.publication_path.text = "user://tests/map_v02/manual/publication.json"
	get_window().title = "潼关 · v0.2 S0 验证（沿用旧显示）"
