extends Node
func _ready() -> void:
	get_window().title="潼关 · V2 地形结构修订 R1 · 待审阅"
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;get_window().content_scale_size=Vector2i(1920,1080);get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	call_deferred("run")
func run() -> void:
	if "--relief-capture" in OS.get_cmdline_user_args():await load("res://v02/relief_r01/capture.gd").new().run(self);return
	var presenter=load("res://v02/relief_r01/presenter.gd").new();add_child(presenter);presenter.setup(self);presenter.region_camera()
