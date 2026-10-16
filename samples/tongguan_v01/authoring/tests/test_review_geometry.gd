extends SceneTree
var checks:=0
var failures: Array=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func clean():
	var h=load("res://r3_authoring/resolver.gd").new()
	h.source._layout.slots=[];h.source._water_features=[];h._water_bounds=[]
	h.source._layout.fixed_refs.main_corridor=[[-500,0],[500,0]]
	for region in h.state.region_settings:h.state.region_settings[region].density=0
	h.state.objects={};h._generated_cache.clear();h._safe_cache.clear()
	return h
func object_at(point: Array,id: String="manual.1")->Dictionary:
	return {"id":id,"position_m":point,"region_id":"manual","grid":[],"source_seed":0,"asset_version":1,"kind":"forest"}
func _initialize()->void:
	create_timer(100).timeout.connect(func():printerr("GEOMETRY_TIMEOUT");quit(1))
	call_deferred("run")
func run()->void:
	var initial=load("res://final/resolver.gd").new()
	check(initial.digest(initial.snapshot())=="f3572d76788116863cc6ed1de64a0d0eb96df28be48b8afdf31abe9c49bc6a9a" and initial.state.objects.size()==95,"default complete state and95 object IDs match read-only26a45be fingerprint")
	var h=clean()
	var actual=load("res://p4/settlement_host.gd").new().layout.fixed_refs.main_corridor
	h.source._layout.fixed_refs.main_corridor=actual
	check(h._safe_uncached(object_at([-3000,-97.6]))=="main_corridor_footprint","actual corridor crosses interior while all four corners exceed40m")
	h.source._layout.fixed_refs.main_corridor=[[-500,0],[500,0]]
	for row in [[[0,22.4],false],[[0,112.399],false],[[0,112.4],true],[[0,112.401],true],[[0,300],true]]:
		check(h._safe_uncached(object_at(row[0])).is_empty()==row[1],"road threshold "+str(row[0]))
	h.source._layout.fixed_refs.main_corridor=[[-500,-1000],[500,-1000]]
	for row in [
		{"line":[[-100,0],[0,0]],"point":[0,22.4],"safe":false,"label":"water endpoint inside"},
		{"line":[[-100,-100],[100,100]],"point":[0,22.4],"safe":false,"label":"diagonal water edge"},
		{"line":[[-200,0],[200,0]],"point":[0,117.399],"safe":false,"label":"water45 inside"},
		{"line":[[-200,0],[200,0]],"point":[0,117.4],"safe":true,"label":"water45 tangent"},
		{"line":[[-200,0],[200,0]],"point":[0,117.401],"safe":true,"label":"water45 outside"}]:
		h.source._water_features=[{"geometry":"line","points_m":row.line}]
		h._water_bounds=[Rect2(-1000,-1000,2000,2000)]
		check(h._safe_uncached(object_at(row.point)).is_empty()==row.safe,row.label)
	h=clean();var before=h.digest(h.state);var added=h.add_object([0,22.4],1)
	check(not added.ok and h.digest(h.state)==before,"add refuses unsafe footprint without state change")
	h=clean();var good=h.add_object([200,400],1);check(good.ok,"legal distant add")
	before=h.digest(h.state);var moved=h.update_object(good.id,{"position_m":[0,22.4]})
	check(not moved.ok and h.digest(h.state)==before,"move refuses interior crossing and keeps old object")
	h=clean()
	var region=h.source.layout.decoration_regions[0];var setting={"seed":123,"density":0.5,"asset_version":1}
	var gid="tongguan.decor."+str(region.id)+".0.0";var record=object_at([0,22.4],gid);record.region_id=region.id;record.grid=[0,0]
	h._generated_cache[str(region.id)+h.digest(setting)]={gid:record}
	var quote=h.preview_regeneration([region.id],123,0.5,1)
	check(quote.ok and not quote.candidate_objects.has(gid) and quote.skipped.any(func(row):return row.id==gid),"new generated crossing is reported as skipped, not adopted")
	h=clean();var bad=object_at([0,22.4]);h.state.objects[bad.id]=bad
	h.state.patches[bad.id]={"op":"add","record":bad,"generator_version":h.GENERATOR};h._counter=1
	check(not h.publish("user://tests/review_direct_unsafe.json").ok,"publish rejects an unadopted newly unsafe object")
	# A checksum-valid legacy workspace is loaded as-is, never sanitized.
	var value={"schema_version":1,"input_sha256":h._input_hash,"state":h.snapshot(),"journal":[],"undo":[],"redo":[],"id_counter":1}
	value.content_sha256=h.digest(value)
	var path="user://tests/review_legacy_geometry.json";FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value,"",true,true))
	var bytes=FileAccess.get_file_as_bytes(path);var loaded=clean();var result=loaded.read_save(path)
	check(result.ok and loaded.digest(loaded.state)==h.digest(h.state) and FileAccess.get_file_as_bytes(path)==bytes,"legacy conflicting workspace reopens byte-preserved state")
	check(loaded.has_method("geometry_conflicts"),"read-only geometry report exists")
	if loaded.has_method("geometry_conflicts"):
		var digest=loaded.digest(loaded.state);var conflicts=loaded.geometry_conflicts()
		check(conflicts.any(func(row):return row.id==bad.id and row.reason=="main_corridor_footprint") and loaded.digest(loaded.state)==digest,"legacy conflict is reported without moving or removing ID")
		check(loaded.publish("user://tests/review_legacy_publication.json").ok,"unchanged legacy content publishes with explicit warning")
		check(loaded.delete_object(bad.id).ok and loaded.state.tombstones.has(bad.id),"explicit deletion of reported legacy object keeps tombstone")
		check(loaded.undo().ok and loaded.state.objects.has(bad.id),"undo explicitly restores same legacy ID")
		check(loaded.redo().ok and not loaded.state.objects.has(bad.id),"redo preserves deliberate deletion")
	h=null;loaded=null
	var out="user://tests/review_geometry.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("REVIEW_GEOMETRY ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
