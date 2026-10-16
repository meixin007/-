extends SceneTree
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:
	create_timer(75).timeout.connect(func():printerr("FINAL_LAYOUT_TIMEOUT");quit(1));run.call_deferred()
func finish()->void:
	var path="user://tests/final_layout.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):path=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());var result={"checks":checks,"failures":failures};FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("FINAL_LAYOUT: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func run()->void:
	check(FileAccess.file_exists("res://final/resolver.gd"),"warehouse layout overrides participate in the same authoring state")
	if not FileAccess.file_exists("res://final/resolver.gd"):finish();return
	var host=load("res://final/resolver.gd").new()
	check(host.error.is_empty(),"final authoring initializes")
	check(host.move_warehouse([4,0]).ok,"warehouse display offset is an authoring patch")
	var moved=host.digest(host.layout_record())
	check(host.undo().ok and host.layout_record().warehouse_offset_m==[0,0],"warehouse edit can undo")
	check(host.redo().ok and host.digest(host.layout_record())==moved,"warehouse edit can redo")
	check(not host.move_warehouse([9,4]).ok,"complete roof and edge footprint cannot leave its slot")
	check(host.pin_layout_slot("tongguan.slot.rear_storage_01",true).ok,"geometry pin is separate from player construction")
	var protected=host.protected_hash()
	for i in 50:
		var diff=host.preview_regeneration(["forest_west"],81000+i,0.3+float(i%3)*0.15,1+i%2)
		check(diff.ok and host.commit_regeneration(diff.token).ok and host.protected_hash()==protected,"warehouse and slot survive regeneration "+str(i))
	check(host.write_save("user://tests/final_layout_workspace.json").ok,"warehouse patch saves with full history")
	var saved=host.digest(host.snapshot());var restored=host.get_script().new()
	check(restored.read_save("user://tests/final_layout_workspace.json").ok and restored.digest(restored.snapshot())==saved,"warehouse patch survives reopening")
	var publication=restored.publication()
	check(restored.digest(publication.runtime_authoring.manual_overrides["tongguan.slot.rear_storage_01"].offset_m)==restored.digest([4,0]),"published runtime projection carries same numeric patch after JSON roundtrip")
	check(publication.source_v4.schema_version==4 and restored.v4_validate().is_empty(),"original v4 document remains compatible and separate")
	check(restored.publish("user://tests/final_layout_publication.json").ok,"complete source, recipe, patch sidecar and active publication written")
	host=null;restored=null;finish()
