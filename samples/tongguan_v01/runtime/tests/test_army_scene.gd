extends SceneTree
var acceptance: RefCounted
func _initialize()->void:run.call_deferred()
func run()->void:
    acceptance=load("res://army/acceptance.gd").new()
    await acceptance.run(root)
    acceptance=null
