extends RefCounted
var checks:=0
var failures: Array=[]
var observations: Array=[]
const Loader=preload("res://v02/e1/package_loader.gd")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func write_json(path: String,value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,"\t"));file.close()
func clone_case(original: String, tag: String) -> String:
	var base:="user://tests/e1_cases/"+str(Time.get_ticks_usec())+"_"+tag
	var m: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(original+"/presentation.package.json"))
	write_json(base+"/presentation.package.json",m)
	for row in m.files:
		if not FileAccess.file_exists(original+"/"+row.path):continue
		DirAccess.make_dir_recursive_absolute((base+"/"+row.path).get_base_dir())
		var file=FileAccess.open(base+"/"+row.path,FileAccess.WRITE);file.store_buffer(FileAccess.get_file_as_bytes(original+"/"+row.path));file.close()
	return base
func rewrite_data(base: String,path: String,value: Dictionary) -> void:
	write_json(base+"/"+path,value)
	var m: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/presentation.package.json"))
	for row in m.files:
		if row.path==path:row.sha256=FileAccess.get_sha256(base+"/"+path)
	write_json(base+"/presentation.package.json",m)
func run(config: Dictionary, native: bool) -> Dictionary:
	if native:
		check(not OS.is_debug_build(),"actual Release template")
		check(not FileAccess.file_exists("res://bundle/authoring_publication.json"),"no original project data in clean package reader")
		check(not ResourceLoader.has_cached("res://bundle/terrain_fallback.png"),"legacy terrain cache never initialized")
	for id in ["lab","tongguan"]:
		var entry: Dictionary=config.packages[id];var loader=Loader.new()
		var admitted: Dictionary=loader.admit(entry.path,entry.expected,entry.build_id)
		check(admitted.ok,"admit "+id)
		if not admitted.ok:observations.append(admitted);continue
		var loaded:=0
		for path in loader.files:
			var row: Dictionary=loader.files[path]
			if row.kind!="texture" or not row.required:continue
			var texture: Dictionary=loader.texture(path)
			check(texture.ok,"imported RGBA pixels and dependencies "+id+"/"+path)
			if not texture.ok:observations.append({"texture_failure":id+"/"+path,"result":texture})
			if texture.ok:loaded+=1
		if id=="lab":
			check(loader.pages.size()==21,"16 fine pages, four parents and one overview")
			check(admitted.optional_missing==["terrain/fine_2_1.png.bin"],"only declared child missing")
			var fallback: Dictionary=loader.resolve_page("fine_2_1")
			check(fallback.ok and not fallback.detail_ok and fallback.selected_page=="parent_1_0" and fallback.status=="detail_failed_fallback_ready","missing detail fails while matching parent succeeds")
			var memberships:=0
			for page in loader.pages.values():
				if page.level==2 and "lab.tree.cross_border" in page.object_ids:memberships+=1
			check(memberships==4,"full crown intersects four pages across negative-coordinate border")
		else:
			check(loader.provenance.source_effective_ids.size()==72,"72 original effective IDs")
			check(loader.objects.has("manual.1") and not loader.objects.has("tongguan.decor.forest_east.0.1"),"manual add and tombstone unchanged")
			check(loader.sites[0].slots.size()==8,"original eight slots")
		observations.append({"package":id,"build_id":loader.manifest.build_id,"pages":loader.pages.size(),"objects":loader.objects.size(),"imported_textures_verified":loaded,"optional_missing":admitted.optional_missing,"texture_requests":loader.requests.duplicate(true)})
	var entry: Dictionary=config.packages.lab
	var control:=clone_case(entry.path,"control")
	check(Loader.new().admit(control,entry.expected,entry.build_id).ok,"copied data control accepted before fault injection")
	for key in Loader.COMPAT:
		var expected: Dictionary=entry.expected.duplicate(true);expected[key]="wrong"
		var result: Dictionary=Loader.new().admit(entry.path,expected,entry.build_id)
		check(not result.ok and result.code=="incompatible_"+key,"compatibility gate "+key)
	var build_result: Dictionary=Loader.new().admit(entry.path,entry.expected,"another_build")
	check(not build_result.ok and build_result.code=="incompatible_build_id","build identity gate")
	var cases={"schema":"unsupported_schema","missing":"missing_file","hash":"hash_mismatch","escape":"unsafe_path","absolute":"unsafe_path","script":"unsafe_path","duplicate_file":"duplicate_file_path","duplicate_object":"duplicate_object_id","source_key":"source_key_mismatch","owner":"owner_mismatch","paint_dependency":"paint_dependency_mismatch","parent":"invalid_parent","page_build":"page_build_mismatch","coordinates":"coordinate_payload_mismatch","visual_receipt":"visual_receipt_mismatch"}
	for tag in cases:
		var base:=clone_case(entry.path,tag)
		var m: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/presentation.package.json"))
		if tag=="schema":m.schema_version=9
		elif tag=="missing":DirAccess.remove_absolute(base+"/instances/objects.json")
		elif tag=="hash":
			var file=FileAccess.open(base+"/terrain/fine_0_0.png.bin",FileAccess.WRITE);file.store_string("damaged");file.close()
		elif tag in ["escape","absolute","script"]:m.files[0].path={"escape":"../escape.json","absolute":"C:/outside.json","script":"payload.gd"}[tag]
		elif tag=="duplicate_file":m.files.append(m.files[0].duplicate(true))
		elif tag in ["duplicate_object","source_key","owner"]:
			var shard: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/instances/objects.json"))
			if tag=="duplicate_object":shard.objects.append(shard.objects[0].duplicate(true))
			elif tag=="source_key":shard.objects[0].source_key="another_id"
			else:shard.objects[0].owner=[0,0]
			rewrite_data(base,"instances/objects.json",shard)
		elif tag in ["paint_dependency","parent","page_build","coordinates"]:
			var c: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"/world.catalog.json"))
			if tag=="paint_dependency":c.pages[0].object_ids.clear()
			elif tag=="parent":c.pages[1].parent_id=c.pages[1].id
			elif tag=="coordinates":c.coordinates.origin_m[0]+=1
			else:c.pages[0].build_id="stale_build"
			rewrite_data(base,"world.catalog.json",c)
		elif tag=="visual_receipt":
			m.visual_review_sha256="0".repeat(64);write_json(base+"/presentation.package.json",m)
		if tag in ["schema","escape","absolute","script","duplicate_file"]:write_json(base+"/presentation.package.json",m)
		var result: Dictionary=Loader.new().admit(base,entry.expected,entry.build_id)
		check(not result.ok and result.code==cases[tag],"fault "+tag+" expected="+cases[tag]+" actual="+str(result.get("code","accepted")))
		observations.append({"fault":tag,"expected":cases[tag],"actual":result.get("code","accepted")})
	var stable=Loader.new();var adopted: Dictionary=stable.admit(entry.path,entry.expected,entry.build_id)
	var previous: String=stable.manifest.get("build_id","")
	var rejected: Dictionary=stable.admit(entry.path,entry.expected,"bad")
	check(adopted.ok and not rejected.ok and stable.manifest.build_id==previous,"rejected replacement preserves active package")
	# Keep the real imported resource path in res:// for this fault. A deliberately
	# wrong expected pixel hash must fail after raw bytes passed admission.
	var pixel_loader=Loader.new();var pixel_adopted: Dictionary=pixel_loader.admit(entry.path,entry.expected,entry.build_id)
	pixel_loader.files["assets/trees.png.bin"].pixel_sha256="0".repeat(64)
	var bad_pixels: Dictionary=pixel_loader.texture("assets/trees.png.bin")
	check(pixel_adopted.ok and not bad_pixels.ok and bad_pixels.code=="imported_pixel_mismatch","imported pixel hash fault is detected")
	var malformed:=clone_case(entry.path,"malformed_json")
	var broken=FileAccess.open(malformed+"/instances/objects.json",FileAccess.WRITE);broken.store_string("{");broken.close()
	var malformed_manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(malformed+"/presentation.package.json"))
	for row in malformed_manifest.files:
		if row.path=="instances/objects.json":row.sha256=FileAccess.get_sha256(malformed+"/"+row.path)
	write_json(malformed+"/presentation.package.json",malformed_manifest)
	var malformed_result: Dictionary=Loader.new().admit(malformed,entry.expected,entry.build_id)
	check(not malformed_result.ok and malformed_result.code=="invalid_json","malformed JSON detected after matching byte hash")
	return {"checks":checks,"failures":failures,"observations":observations,"engine_version":Engine.get_version_info(),"native_release":native,"scope":"E1 package validation and synchronous requests; not E2/E3 capacity"}
