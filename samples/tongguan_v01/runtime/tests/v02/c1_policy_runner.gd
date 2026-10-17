extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var path:="res://v02/c1/display_policy.gd"
	if not ResourceLoader.exists(path):printerr("C1_RED: missing display policy");quit(1);return
	var result: Dictionary=load("res://v02/c1/policy_checks.gd").new().run()
	print("C1_POLICY ",JSON.stringify(result));quit(0 if result.failures.is_empty() else 1)
