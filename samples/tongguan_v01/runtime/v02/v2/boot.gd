extends Node
func _ready() -> void:
	get_window().title="潼关 · V2 原位建设、损毁与修复 · 待审阅"
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;get_window().content_scale_size=Vector2i(1920,1080);get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	if "--v2-capture" in OS.get_cmdline_user_args():await load("res://v02/v2/capture.gd").new().run(self)
	else:add_child(load("res://v02/v2/app.gd").new())
