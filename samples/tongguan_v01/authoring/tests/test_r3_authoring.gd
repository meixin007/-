extends SceneTree
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:
	create_timer(75).timeout.connect(func():printerr("R3_AUTHORING_TIMEOUT");quit(1))
	run.call_deferred()
func finish()->void:
	var out="user://r3_tests/authoring.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var result={"checks":checks,"failures":failures};FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R3_AUTHORING: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func run()->void:
	check(FileAccess.file_exists("res://r3_authoring/resolver.gd"),"general authoring patch and footprint resolver exists")
	if not FileAccess.file_exists("res://r3_authoring/resolver.gd"):finish();return
	var engine=preload("res://r3_authoring/patch_engine.gd")
	for kind in ["warehouse","wall","road","forest"]:
		var generated={"existing":{"id":"existing","kind":kind,"position":[1,2],"footprint":[[0,0],[4,0],[4,4],[0,4]]}}
		var patches={"existing":{"op":"update","record":{"id":"existing","kind":kind,"position":[3,4]}},"new":{"op":"add","record":{"id":"new","kind":kind,"position":[5,6]}}}
		var before_input=engine.canonical(generated)
		var merged=engine.merge(generated,patches,{},{},{})
		check(merged.ok and merged.objects.existing.position==[3,4] and merged.objects.has("new"),"record-independent add/update "+kind)
		check(engine.canonical(generated)==before_input,"generic patch merge does not mutate input "+kind)
		var locked={"existing":generated.existing};merged=engine.merge(generated,patches,locked,{},{})
		check(not merged.ok and engine.canonical(merged.objects)==before_input,"generic protected-update conflict keeps full old candidate "+kind)
		merged=engine.merge(generated,{"existing":{"op":"delete"}},{},{},{"existing":true})
		check(merged.ok and not merged.objects.has("existing"),"record-independent tombstone "+kind)
	var host=load("res://r3_authoring/resolver.gd").new()
	check(host.error.is_empty(),"authoring input is valid: "+host.error)
	if not host.error.is_empty():finish();return
	var initial=host.digest(host.snapshot())
	print("R3_AUTHORING_INITIALIZED")
	var ids=host.state.objects.keys();ids.sort();var id: String=ids[0]
	var moved=host.update_object(id,{"position_m":[-512.0,650.0]})
	check(moved.ok,"manual update is not limited to old warehouse shortcut")
	check(host.state.objects.has(id) and host.state.patches[id].op=="update","moving across chunk keeps stable identity and update patch")
	var chunks=host.chunk_memberships(id)
	check(chunks.size()>=2,"paint footprint occupies neighboring chunks even when anchor belongs to one")
	var before_delete=host.snapshot()
	check(host.delete_object(id).ok and not host.state.objects.has(id) and host.state.tombstones.has(id),"cross-chunk delete records tombstone")
	check(not host.spatial_query([-600,500,250,250]).has(id),"all chunk query references disappear after deletion")
	check(host.undo().ok and host.state.objects.has(id),"undo restores complete authoring version")
	check(host.redo().ok and host.state.tombstones.has(id),"redo restores tombstone")
	var added=host.add_object([-2700,1250],1)
	check(added.ok and str(added.id).begins_with("manual."),"manual add gets stable non-coordinate identity")
	var added_id: String=added.get("id","")
	check(host.update_object(added_id,{"asset_version":2}).ok,"manual asset update")
	check(host.pin_object(added_id,true).ok,"pin manual instance")
	var protected=host.protected_hash()
	var before_preview=host.digest(host.snapshot());var quote=host.preview_regeneration(["forest_west"],17001,0.5,2)
	check(quote.ok,"constrained generation previews valid candidate")
	check(host.digest(host.snapshot())==before_preview,"preview does not commit")
	check(host.commit_regeneration(quote.get("token","")).ok,"commit candidate atomically")
	check(host.protected_hash()==protected and not host.state.objects.has(id) and host.state.objects.has(added_id),"pin, manual update and tombstone survive regeneration")
	check(host.export_v4().schema_version==4 and host.v4_validate().is_empty(),"new document uses original v4 validator")
	var target_ids=host.state.objects.keys();target_ids.sort();var target: String=target_ids[0]
	var paint=host.paint_bounds(host.state.objects[target]);var zone=[paint[0]+paint[2]-3,paint[1],10,paint[3]]
	var locked=host.add_zone(zone,"lock")
	check(locked.ok and host.state.zone_pins.has(target),"zone locks full paint footprint when anchor is outside")
	var locked_before=host.digest(host.state.objects[target])
	quote=host.preview_regeneration(["forest_west","forest_east"],19191,0.7,1)
	check(quote.ok and host.commit_regeneration(quote.token).ok and host.digest(host.state.objects[target])==locked_before,"zone-locked full footprint preserved")
	check(not host.update_object(target,{"position_m":[0,0]}).ok,"locked object cannot silently move")
	check(host.add_zone([-2500,900,320,240],"exclude_generation").ok,"exclude generation is separate from gameplay buildability")
	quote=host.preview_regeneration(["forest_west"],20202,1.0,2)
	check(quote.ok and host.commit_regeneration(quote.token).ok,"exclude region constrains generator before merge")
	check(host.exclusion_violations().is_empty(),"automatic paint footprints do not enter exclusion area")
	var snapshot=host.digest(host.snapshot())
	var conflict=host.preview_conflict("locked_boundary")
	check(not conflict.ok and conflict.conflicts.size()>0 and host.digest(host.snapshot())==snapshot,"candidate boundary crossing locked footprint aborts whole candidate")
	var outside={"generator_version":host.GENERATOR,"objects":host.state.objects.duplicate(true),"features":[{"id":"nonintersecting_bank","paint_footprint_m":[[5000,5000],[5100,5000],[5100,5100],[5000,5100]]}]}
	check(host.preview_candidate(outside).ok,"same candidate validator accepts a boundary outside locked footprints")
	var unsafe=outside.duplicate(true);unsafe.objects[added_id].position_m[0]+=20
	check(not host.preview_candidate(unsafe).ok,"same candidate validator rejects actual changed manual content")
	conflict=host.preview_conflict("id_upgrade")
	check(not conflict.ok and str(conflict.conflicts).contains("id_mismatch") and host.digest(host.snapshot())==snapshot,"generator ID upgrade refuses without migration")
	quote=host.preview_regeneration(["forest_west"],30303,0.6,1)
	host.add_object([-2850,1300],1)
	check(not host.commit_regeneration(quote.token).ok,"stale authoring preview cannot overwrite newer edit")
	check(host.write_save("user://r3_tests/workspace.json").ok,"authoring save writes whole version")
	var saved=host.digest(host.snapshot());var restored=host.get_script().new()
	check(restored.read_save("user://r3_tests/workspace.json").ok and restored.digest(restored.snapshot())==saved,"reopen preserves patches, zones, tombstones and IDs")
	check(host.publish("user://r3_tests/publication.json").ok,"publish separate v4 source, patch sidecar and runtime projection")
	var published=host.publication();var payload=JSON.parse_string(JSON.stringify(published));payload.erase("content_sha256")
	check(published.content_sha256==host.digest(payload),"publication checksum survives JSON and StringName-key normalization")
	var road_host=host.get_script().new();var points=road_host.source.layout.roads[1].points_m.duplicate(true);points[1][0]=-610
	check(road_host.update_feature("tongguan.road.connector",points).ok,"generic registered road edit records patch while preserving endpoint IDs")
	points[0][0]-=10;check(not road_host.update_feature("tongguan.road.connector",points).ok,"road endpoint disconnection rejected")
	check(road_host.add_zone([-635,-165,40,50],"lock").ok,"lock around actual road control point")
	points=road_host.source.layout.roads[1].points_m.duplicate(true)
	check(not road_host.update_feature("tongguan.road.connector",points).ok,"road stroke footprint cannot cross locked region")
	var case_path="user://r3_tests/recovery_%d.json"%Time.get_ticks_usec()
	check(road_host.write_save(case_path).ok,"save complete version A")
	var version_a=road_host.digest(road_host.snapshot());road_host.add_object([-2850,1300],1);check(road_host.write_save(case_path).ok,"save complete version B with A backup")
	var version_b=road_host.digest(road_host.snapshot())
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(case_path),ProjectSettings.globalize_path(case_path+".pending"))==OK,"simulate interruption after old-file rotation")
	var recover=road_host.get_script().new();var recovery=recover.read_save(case_path)
	check(recovery.ok and recovery.recovered and recover.digest(recover.snapshot())==version_a,"reopen chooses complete old version after interrupted publication")
	FileAccess.open(case_path+".previous",FileAccess.WRITE).store_string("{partial")
	recovery=recover.read_save(case_path)
	check(recovery.ok and recovery.recovered and recover.digest(recover.snapshot())==version_b,"if old version is unusable only a fully validated pending version can recover")
	var damaged=JSON.parse_string(FileAccess.get_file_as_string(case_path+".pending"));damaged.undo=[{"before":{}}];damaged.erase("content_sha256");damaged.content_sha256=recover.digest(damaged)
	FileAccess.open(case_path+".pending",FileAccess.WRITE).store_string(JSON.stringify(damaged))
	var recovery_before=recover.digest(recover.snapshot())
	check(not recover.read_save(case_path).ok and recover.digest(recover.snapshot())==recovery_before,"semantic bad history rejected without replacing working authoring state")
	road_host=null;recover=null
	for i in 50:
		if i%10==0:print("R3_AUTHORING_CYCLE ",i);await process_frame
		var stable=host.protected_hash();quote=host.preview_regeneration(["forest_west"],40000+i,0.3+float(i%4)*0.15,1+i%2)
		check(quote.ok and host.commit_regeneration(quote.token).ok,"bounded regeneration cycle "+str(i))
		check(host.protected_hash()==stable,"protected canonical content cycle "+str(i))
		check(host.undo().ok and host.redo().ok,"undo/redo full version cycle "+str(i))
	host=null;restored=null;finish()
