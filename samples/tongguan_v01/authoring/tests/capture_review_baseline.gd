extends SceneTree
func _initialize()->void:
	call_deferred("run")
func run()->void:
	var host=load("res://final/resolver.gd").new()
	var out=OS.get_environment("REVIEW_BASELINE")
	var value={"state":host.snapshot(),"state_sha256":host.digest(host.snapshot()),"publication_sha256":host.publication().content_sha256,"input_sha256":host._input_hash,"error":host.error}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
	print("BASELINE_CAPTURE ",host.state.objects.size()," ",value.state_sha256)
	quit(0 if host.error.is_empty() else 1)
