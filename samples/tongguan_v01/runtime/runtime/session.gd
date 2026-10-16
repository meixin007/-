extends Node
var cache: RefCounted
var state: RefCounted
func _ready()->void:
	cache=load("res://runtime/asset_cache.gd").new()
	state=load("res://runtime/settlement_state.gd").new()
	if not OS.get_cmdline_user_args().has("--acceptance") and FileAccess.file_exists("user://runtime/session.json"):state.read_save("user://runtime/session.json")
func _process(_delta: float)->void:
	if cache!=null:cache.tick()
