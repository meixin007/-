extends SceneTree
var checks:=0
var failures: Array[String]=[]
var output:="user://tests/r5_saves.json"
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:
	create_timer(80).timeout.connect(func():printerr("R5_SAVES_TIMEOUT");quit(1))
	run.call_deferred()
func finish()->void:
	var result={"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R5_SAVES: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	check(FileAccess.file_exists("res://final/controller.gd"),"final controller adds explicit migration and backup recovery")
	if not FileAccess.file_exists("res://final/controller.gd"):finish();return
	var script=load("res://final/controller.gd");var host=script.new()
	check(host.error.is_empty(),"current actual host initializes")
	var root=OS.get_environment("TONGGUAN_R5_FIXTURES")
	check(not root.is_empty(),"actual older-host fixture directory supplied")
	if root.is_empty():finish();return
	for stage in ["r3","r4"]:
		var path=root.path_join(stage+"_save.json");var bytes=FileAccess.get_file_as_bytes(path);var before=host.digest(host.context.state.to_dictionary())
		var preview=host.preview_import(path,"user://tests/r5_import_"+stage+".json")
		check(preview.ok and preview.summary.source_campaign_id in ["tongguan_integrity_validation_v1","tongguan_review_validation_v1"],"preview actual "+stage+" save")
		check(preview.get("summary",{}).get("source_sha256")==FileAccess.get_sha256(path),"preview bound to exact original file bytes "+stage)
		check(host.digest(host.context.state.to_dictionary())==before,"preview cannot mutate live state "+stage)
		if not preview.ok:continue
		preview.summary.day=99999
		check(host.commit_import(preview.token).ok,"explicit import commits "+stage)
		var raw: Dictionary=JSON.parse_string(bytes.get_string_from_utf8());raw.erase("checksum");raw.campaign_id=host.definition.world_id;raw.flags.campaign_id=host.definition.world_id
		check(host.digest(host.context.state.to_dictionary())==host.digest(raw),"all state preserved except declared world identity "+stage)
		check(FileAccess.get_file_as_bytes(path)==bytes,"source save byte exact "+stage)
		check(not host.commit_import(preview.token).ok,"import token is single use "+stage)
		var live=host.digest(host.context.state.to_dictionary());check(host.read_save("user://tests/r5_import_"+stage+".json").ok and host.digest(host.context.state.to_dictionary())==live,"migrated native save reload "+stage)
	var source=root.path_join("r4_save.json")
	var original=host.digest(host.context.state.to_dictionary());var epoch=host.context.world_epoch
	check(not host.preview_import(root.path_join("r2_save.json"),"user://tests/never_r2.json").ok,"older economic/graph contract rejected explicitly")
	check(not host.preview_import(source,"res://bundle/authoring.json").ok,"migration never writes sources")
	check(not host.preview_import(source,source).ok,"source path cannot become output")
	check(host.digest(host.context.state.to_dictionary())==original and host.context.world_epoch==epoch,"rejections preserve live state and epoch")
	var quote=host.preview_import(source,"user://tests/r5_stale.json");host.set_gate_open(not host.projection().gate_open)
	check(not host.commit_import(quote.get("token","")).ok and not FileAccess.file_exists("user://tests/r5_stale.json"),"newer world state invalidates preview before writing")
	var copy="user://tests/r5_mutable_source.json";DirAccess.make_dir_recursive_absolute("user://tests");FileAccess.open(copy,FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(source))
	quote=host.preview_import(copy,"user://tests/r5_changed_source.json");FileAccess.open(copy,FileAccess.WRITE).store_string("{torn")
	check(not host.commit_import(quote.get("token","")).ok and not FileAccess.file_exists("user://tests/r5_changed_source.json"),"source modification after preview rejects before adoption")
	check(not host.preview_import(copy,"user://tests/r5_bad.json").ok,"torn source JSON rejected quietly")
	var backup_path="user://tests/r5_generations_%d.json"%Time.get_ticks_usec()
	check(host.write_save(backup_path).ok,"native complete save A")
	var version_a=host.digest(host.context.state.to_dictionary());host.set_gate_open(not host.projection().gate_open)
	check(host.write_save(backup_path).ok,"native save B rotates A backup")
	var version_b=host.digest(host.context.state.to_dictionary());FileAccess.open(backup_path,FileAccess.WRITE).store_string("{torn")
	check(not host.read_save(backup_path).ok and host.digest(host.context.state.to_dictionary())==version_b,"bad main save does not mutate current host")
	check(host.restore_previous_save(backup_path).ok and host.digest(host.context.state.to_dictionary())==version_a,"explicit validated previous generation restores whole native state")
	var recovered_bytes=FileAccess.get_file_as_bytes(backup_path)
	var invalid: Dictionary=JSON.parse_string(recovered_bytes.get_string_from_utf8());invalid.local_node_state.tongguan_pass_node.tongguan_settlement_runtime_v1.layout_version="unmapped_layout"
	invalid.erase("checksum");var repository=host.Saves.new(host.definition.world_id).repository;invalid.checksum=repository._checksum_for(invalid).checksum
	FileAccess.open(backup_path+".bak",FileAccess.WRITE).store_string(JSON.stringify(invalid,"",true,true))
	var current=host.digest(host.context.state.to_dictionary());epoch=host.context.world_epoch
	check(not host.restore_previous_save(backup_path).ok and FileAccess.get_file_as_bytes(backup_path)==recovered_bytes and host.digest(host.context.state.to_dictionary())==current and host.context.world_epoch==epoch,"semantically invalid backup rejected before disk or state replacement")
	var upgraded: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source));upgraded.local_node_state.tongguan_pass_node.tongguan_settlement_runtime_v1.layout_version="unmapped_layout"
	var old_repository=host.Saves.new(upgraded.campaign_id).repository;upgraded.erase("checksum");upgraded.checksum=old_repository._checksum_for(upgraded).checksum
	FileAccess.open(copy,FileAccess.WRITE).store_string(JSON.stringify(upgraded,"",true,true))
	check(not host.preview_import(copy,"user://tests/never_layout.json").ok,"unknown layout refuses instead of random slot remapping")
	host=null;finish()
