extends Node
var cache: RefCounted
var state: RefCounted
var army: RefCounted
func _ready()->void:
	cache=load("res://runtime/asset_cache.gd").new();recreate()
func recreate()->void:
	army=load("res://final/controller.gd").new()
	state=load("res://runtime/settlement_state.gd").new(army)
func _process(_delta: float)->void:
	if cache!=null:cache.tick()
