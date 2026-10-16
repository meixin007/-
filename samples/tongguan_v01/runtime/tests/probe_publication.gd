extends SceneTree
func _initialize()->void:
	var value=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring_publication.json"))
	var expected=value.content_sha256;value.erase("content_sha256")
	print("PUB_STORED ",expected," ACTUAL ",preload("res://runtime/settlement_state.gd").digest(value))
	FileAccess.open("res://publication_canonical.txt",FileAccess.WRITE).store_string(preload("res://runtime/settlement_state.gd").canonical(value));quit(0)
