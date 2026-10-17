extends Node
var cache: RefCounted
var state: RefCounted
var army: RefCounted
var visual_service: RefCounted
var visual_mode := "legacy"
var startup_error := ""
func _ready()->void:
	var scenes := Array(OS.get_cmdline_args())
	scenes.append(ProjectSettings.get_setting("application/run/main_scene", ""))
	var selection: Dictionary = load("res://v02/service_selection.gd").choose(scenes, Array(OS.get_cmdline_user_args()))
	if not selection.ok:
		startup_error = selection.message
		printerr(startup_error);get_tree().quit(1);return
	visual_mode = selection.mode
	visual_service = load("res://v02/map_services.gd").new(visual_mode)
	cache = visual_service.cache
	recreate()
func recreate()->void:
	army=load("res://final/controller.gd").new()
	state=load("res://runtime/settlement_state.gd").new(army)
func _process(_delta: float)->void:
	if cache!=null:cache.tick()
