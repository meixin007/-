extends SceneTree
var checks:=0
var failures: Array=[]
func check(value: bool,label: String)->void:
	checks+=1
	if not value:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var validator=load("res://integrity/publication.gd").new()
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring_publication.json"))
	for offset in [[0,0],[4,0],[9,4],[-9,-4],[0,4],[0,-4]]:
		var body: Dictionary=template.runtime_authoring.duplicate(true)
		body.manual_overrides["tongguan.slot.rear_storage_01"]={"offset_m":offset,"authoring_pin":true}
		var meta={"schema_version":1,"publication_sha256":template.content_sha256,"authoring_sha256":validator.City.digest(body),"authoring":body}
		var allowed=offset in [[0,0],[4,0]]
		check(validator.validate_meta(meta).is_empty()==allowed,"complete roof footprint "+str(offset))
	var out="user://tests/final_publication.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir());var result={"checks":checks,"failures":failures};FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R5_PUBLICATION_FOOTPRINT: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
