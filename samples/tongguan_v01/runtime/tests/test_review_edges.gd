extends SceneTree
var acceptance: RefCounted
func _initialize()->void:call_deferred("run")
func run()->void:
	acceptance=load("res://review/tree_edge_acceptance.gd").new()
	await acceptance.run(root)
	acceptance=null
