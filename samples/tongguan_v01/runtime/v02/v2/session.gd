extends Node
## The original controller creates the sole GameState/Context. No legacy visual cache.
var army: RefCounted
var state: RefCounted
func _ready() -> void:
	army=load("res://final/controller.gd").new()
	state=load("res://runtime/settlement_state.gd").new(army)
	if not army.error.is_empty():printerr(army.error);get_tree().quit(1)
