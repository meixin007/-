extends SceneTree
var checks:=0
var failures: Array=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var service=load("res://integrity/publication.gd").new()
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring_publication.json"))
	check(service.load_publication("res://bundle/authoring_publication.json").ok,"original publication remains valid")
	var duplicate=source.duplicate(true);duplicate.source_v4.presentation.instances.append(duplicate.source_v4.presentation.instances[0].duplicate(true))
	duplicate.erase("content_sha256");duplicate.content_sha256=service.City.digest(duplicate)
	var path="user://tests/review_duplicate_raw.json";FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(duplicate,"",true,true))
	check(not service.load_publication(path).ok,"duplicate raw v4 ID rejected before dictionary projection")
	var mismatch=source.duplicate(true);var first=mismatch.runtime_authoring.generated.keys()[0];mismatch.runtime_authoring.generated[first].id="different"
	mismatch.erase("content_sha256");mismatch.content_sha256=service.City.digest(mismatch);path="user://tests/review_key_mismatch.json";FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(mismatch,"",true,true))
	check(not service.load_publication(path).ok,"dictionary key must match record ID")
	var wrong_shape=source.duplicate(true);wrong_shape.source_v4="invalid";wrong_shape.erase("content_sha256");wrong_shape.content_sha256=service.City.digest(wrong_shape)
	path="user://tests/review_v4_shape.json";FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(wrong_shape,"",true,true));check(not service.load_publication(path).ok,"malformed raw v4 rejected explicitly")
	var missing_generated=source.duplicate(true);missing_generated.runtime_authoring.erase("generated");missing_generated.erase("content_sha256");missing_generated.content_sha256=service.City.digest(missing_generated)
	path="user://tests/review_missing_projection.json";FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(missing_generated,"",true,true));check(not service.load_publication(path).ok,"missing generated projection rejected before raw-ID mapping")
	var script_path="res://runtime/instance_index.gd"
	check(FileAccess.file_exists(script_path),"cross-chunk submission validator exists")
	if FileAccess.file_exists(script_path):
		var index=load(script_path)
		var a={"id":"stable.cross","position_m":[512,512],"asset_version":1}
		var b={"id":"stable.other","position_m":[100,100],"asset_version":2}
		var plan=index.plan([a,b])
		check(plan.ok and plan.memberships["stable.cross"].size()==4,"cross-boundary object indexed in all four chunks")
		check(plan.entries.filter(func(row):return row.id=="stable.cross").size()==1 and plan.entries[0].owning_chunk=="0:0","stable sorted plan has a single derived owner")
		check(index.select_chunks(plan,["0:0","1:0","0:1","1:1"]).size()==2,"overlapping visible chunk queries submit each ID once")
		check(not index.plan([a,a.duplicate(true)]).ok,"raw duplicate ID mutant fails")
		var twice=plan.entries.duplicate(true);twice.append(plan.entries[0].duplicate(true));check(not index.audit(twice).ok,"duplicate submission mutant fails")
		var bad_owner=plan.entries.duplicate(true);bad_owner[0].owning_chunk="99:99";check(not index.audit(bad_owner).ok,"second or mismatched owner mutant fails")
		var moved=a.duplicate(true);moved.position_m=[1024,512];var moved_plan=index.plan([moved]);check(moved_plan.ok and moved_plan.entries[0].id==a.id and moved_plan.entries[0].owning_chunk=="2:1","crossing owner boundary keeps stable ID and one new derived owner")
		check(service.City.digest(a)==service.City.digest({"id":"stable.cross","position_m":[512,512],"asset_version":1}),"indexing does not mutate saved record")
	var out="user://tests/review_ownership.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir());FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("REVIEW_OWNERSHIP ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
