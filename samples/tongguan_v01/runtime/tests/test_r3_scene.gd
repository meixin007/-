extends SceneTree
var acceptance: RefCounted
func _initialize()->void:run.call_deferred()
func run()->void:
	var boot=Node.new();root.add_child(boot);acceptance=load("res://integrity/acceptance.gd").new();await acceptance.run(boot);acceptance=null
