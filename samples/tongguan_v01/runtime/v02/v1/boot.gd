extends Node
var probe: RefCounted
func _ready() -> void:
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(1920,1080)
	get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	get_window().title="潼关 · V1 组合小样 A · 待审阅"
	if OS.get_cmdline_user_args().has("--v1-capture"):
		var script=load("res://v02/v1/capture.gd")
		if script==null or not script.can_instantiate():get_tree().quit(1);return
		probe=script.new();await probe.run(self);probe=null;return
	var app=load("res://v02/v1/app.gd").new();add_child(app)
