extends RefCounted
## Shared synchronous E1 reader. No gameplay authority, scripts, async cache or eviction.
var root_path := ""
var manifest: Dictionary={}
var catalog: Dictionary={}
var files: Dictionary={}
var pages: Dictionary={}
var objects: Dictionary={}
var assets: Dictionary={}
var sites: Array=[]
var provenance: Dictionary={}
var textures: Dictionary={}
var requests: Array=[]
const COMPAT=["world_id","site_id","layout_version","layout_slots_sha256","fixed_refs_sha256","graph_version","coordinate_sha256"]
func canonical_fixed6(value: Variant) -> String:
	if value is Dictionary:
		var keys=value.keys();keys.sort();var fields: Array[String]=[]
		for key in keys:fields.append(JSON.stringify(str(key))+":"+canonical_fixed6(value[key]))
		return "{"+",".join(fields)+"}"
	if value is Array:
		var fields: Array[String]=[]
		for item in value:fields.append(canonical_fixed6(item))
		return "["+",".join(fields)+"]"
	if value is int or value is float:return "%.6f"%float(value)
	return JSON.stringify(value)
func fail(code: String, detail: String="") -> Dictionary:
	return {"ok":false,"code":code,"message":code+": "+detail}
func valid_point(value: Variant) -> bool:
	if not value is Array or value.size()!=2:return false
	for v in value:
		if not (v is int or v is float) or not is_finite(v) or absf(v)>1.0e9:return false
	return true
func valid_rect(value: Variant) -> bool:
	return value is Array and value.size()==4 and valid_point(value.slice(0,2)) and valid_point(value.slice(2,4)) and value[2]>0 and value[3]>0
func rect(value: Array) -> Rect2:
	return Rect2(value[0],value[1],value[2],value[3])
func relative_path(value: Variant, suffixes: Array=[".json",".png.bin"]) -> bool:
	if not value is String or value.is_empty() or value.begins_with("/"):return false
	var regex=RegEx.new();regex.compile("^[A-Za-z0-9_./-]+$")
	if regex.search(value)==null:return false
	for part in value.split("/",true):
		if part in ["",".",".."]:return false
	for suffix in suffixes:
		if value.ends_with(suffix):return true
	return false
func is_hash(value: Variant) -> bool:
	if not value is String:return false
	var regex=RegEx.new();regex.compile("^[a-f0-9]{64}$");return regex.search(value)!=null
func data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return fail("missing_file",path)
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return fail("unreadable_file",path)
	if file.get_length()>8*1024*1024:return fail("data_too_large",path)
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return fail("invalid_json",path)
	return {"ok":true,"value":parser.data}
func admit(path: String, expected: Dictionary, expected_build: String="") -> Dictionary:
	# Parse into locals; a rejected replacement cannot destroy the active package.
	var candidate: Dictionary=parse_package(path.trim_suffix("/"),expected,expected_build)
	if not candidate.ok:return candidate
	root_path=path.trim_suffix("/");manifest=candidate.manifest;catalog=candidate.catalog
	files=candidate.files;pages=candidate.pages;objects=candidate.objects;assets=candidate.assets
	sites=candidate.sites;provenance=candidate.provenance;textures.clear();requests.clear()
	return {"ok":true,"optional_missing":candidate.optional_missing,"object_count":objects.size(),"page_count":pages.size()}
func parse_package(base: String, expected: Dictionary, expected_build: String) -> Dictionary:
	var parsed: Dictionary=data(base+"/presentation.package.json")
	if not parsed.ok:return parsed
	var m: Dictionary=parsed.value
	if m.get("schema_id")!="tongguan.presentation_package" or not (m.get("schema_version") is int or m.get("schema_version") is float) or m.schema_version!=1:return fail("unsupported_schema")
	if not m.get("build_id") is String or m.build_id.is_empty():return fail("invalid_manifest")
	if m.get("compiler_version")!="e1_compiler_v1" or m.get("load_policy")!="synchronous_e1_no_residency_budget" or not m.get("style_id") is String or not is_hash(m.get("visual_review_sha256")):return fail("invalid_manifest")
	var import_contract={"engine_major":4,"engine_minor":6,"texture_compression":"lossless","fix_alpha_border":false,"premult_alpha":false,"mipmaps":false,"pixel_hash":"rgba8_base_only"}
	if canonical_fixed6(m.get("import_contract"))!=canonical_fixed6(import_contract):return fail("unsupported_import_contract")
	if Engine.get_version_info().major!=4 or Engine.get_version_info().minor!=6:return fail("unsupported_engine")
	if not expected_build.is_empty() and m.build_id!=expected_build:return fail("incompatible_build_id")
	if not m.get("compatibility") is Dictionary:return fail("invalid_manifest")
	for key in COMPAT:
		if not expected.get(key) is String or m.compatibility.get(key)!=expected[key]:return fail("incompatible_"+key)
	if not m.get("files") is Array or m.files.is_empty() or m.files.size()>2048:return fail("invalid_manifest")
	var fs: Dictionary={};var missing: Array=[]
	for row in m.files:
		if not row is Dictionary or not relative_path(row.get("path")):return fail("unsafe_path")
		var rel: String=row.path
		if fs.has(rel):return fail("duplicate_file_path",rel)
		if not row.get("required") is bool or not is_hash(row.get("sha256")) or row.get("kind") not in ["json","texture"]:return fail("invalid_file_record",rel)
		if row.kind=="json" and (not rel.ends_with(".json") or not row.required):return fail("invalid_file_record",rel)
		if row.kind=="texture":
			if not relative_path(row.get("resource_path"),[".png"]) or row.resource_path!=rel.trim_suffix(".bin"):return fail("unsafe_path",rel)
			if not is_hash(row.get("pixel_sha256")) or not valid_point(row.get("pixel_size")) or row.pixel_size[0]<=0 or row.pixel_size[1]<=0 or row.pixel_size[0]>8192 or row.pixel_size[1]>8192:return fail("invalid_texture_record",rel)
		fs[rel]=row.duplicate(true)
		if not FileAccess.file_exists(base+"/"+rel):
			if row.required:return fail("missing_file",rel)
			missing.append(rel);continue
		var opened=FileAccess.open(base+"/"+rel,FileAccess.READ)
		if opened==null or opened.get_length()>32*1024*1024:return fail("unreadable_file",rel)
		opened.close()
		if FileAccess.get_sha256(base+"/"+rel)!=row.sha256:return fail("hash_mismatch",rel)
	if not relative_path(m.get("catalog"),[".json"]) or not fs.has(m.catalog):return fail("undeclared_dependency","catalog")
	parsed=data(base+"/"+m.catalog)
	if not parsed.ok:return parsed
	var c: Dictionary=parsed.value
	if c.get("schema_version")!=1 or c.get("build_id")!=m.build_id or c.get("compatibility")!=m.compatibility:return fail("catalog_identity")
	if not c.get("coordinates") is Dictionary or canonical_fixed6(c.coordinates).sha256_text()!=m.compatibility.coordinate_sha256:return fail("coordinate_payload_mismatch")
	if not valid_rect(c.get("bounds_m")) or not c.get("object_shards") is Array or not c.get("pages") is Array:return fail("invalid_catalog")
	for key in ["art_bundle","sites","provenance"]:
		if not relative_path(c.get(key),[".json"]) or not fs.has(c[key]):return fail("undeclared_dependency",key)
	parsed=data(base+"/"+c.art_bundle)
	if not parsed.ok:return parsed
	if parsed.value.get("schema_version")!=1 or not parsed.value.get("assets") is Array:return fail("invalid_art_bundle")
	var arts: Dictionary={}
	for asset in parsed.value.assets:
		if not asset is Dictionary or not asset.get("asset_id") is String or arts.has(asset.asset_id):return fail("duplicate_asset_id")
		if not fs.has(asset.get("texture_file")) or fs[asset.texture_file].kind!="texture":return fail("undeclared_dependency","asset")
		if not valid_rect(asset.get("rect_px")) or not valid_point(asset.get("anchor_px")) or not (asset.get("width_m") is float or asset.get("width_m") is int) or asset.width_m<=0:return fail("invalid_art_bounds")
		var sz: Array=fs[asset.texture_file].pixel_size
		if asset.rect_px[0]<0 or asset.rect_px[1]<0 or asset.rect_px[0]+asset.rect_px[2]>sz[0] or asset.rect_px[1]+asset.rect_px[3]>sz[1]:return fail("invalid_art_bounds")
		arts[asset.asset_id]=asset.duplicate(true)
	var objs: Dictionary={};var object_shards: Dictionary={}
	for shard in c.object_shards:
		if not relative_path(shard,[".json"]) or not fs.has(shard):return fail("undeclared_dependency","shard")
		parsed=data(base+"/"+shard)
		if not parsed.ok:return parsed
		if parsed.value.get("schema_version")!=1 or not parsed.value.get("objects") is Array:return fail("invalid_shard")
		# Check the raw list before any id->record projection.
		for item in parsed.value.objects:
			if not item is Dictionary or not item.get("id") is String or item.id.is_empty():return fail("invalid_object")
			if objs.has(item.id):return fail("duplicate_object_id",item.id)
			if item.get("source_key",item.id)!=item.id:return fail("source_key_mismatch",item.id)
			if not valid_point(item.get("position_m")) or not valid_rect(item.get("paint_bounds_m")):return fail("invalid_object_bounds",item.id)
			var owner: Array=[floori(item.position_m[0]/512.0),floori(item.position_m[1]/512.0)]
			if not valid_point(item.get("owner")) or item.owner[0]!=owner[0] or item.owner[1]!=owner[1]:return fail("owner_mismatch",item.id)
			if item.get("record_type")=="sprite":
				if not arts.has(item.get("asset_id")):return fail("unknown_asset",item.id)
				var a: Dictionary=arts[item.asset_id];var s: float=a.width_m/a.rect_px[2]
				var b: Array=[item.position_m[0]-a.anchor_px[0]*s,item.position_m[1]-a.anchor_px[1]*s,a.rect_px[2]*s,a.rect_px[3]*s]
				for i in 4:
					if absf(b[i]-item.paint_bounds_m[i])>.00001:return fail("paint_bounds_mismatch",item.id)
			elif item.get("record_type")=="polyline":
				if not item.get("points_m") is Array or item.points_m.size()<2 or item.points_m.size()>20000:return fail("invalid_polyline",item.id)
				if not (item.get("width_m") is float or item.get("width_m") is int) or item.width_m<=0:return fail("invalid_polyline",item.id)
				for point in item.points_m:
					if not valid_point(point) or not rect(item.paint_bounds_m).has_point(Vector2(point[0],point[1])):return fail("invalid_polyline",item.id)
			else:return fail("invalid_object_kind",item.id)
			objs[item.id]=item.duplicate(true)
			object_shards[item.id]=shard
	var pg: Dictionary={}
	for page in c.pages:
		if not page is Dictionary or not page.get("id") is String or pg.has(page.id):return fail("duplicate_page_id")
		if page.get("build_id")!=m.build_id:return fail("page_build_mismatch")
		if not valid_rect(page.get("bounds_m")) or not valid_point(page.get("core_px")) or not page.get("texture_files") is Array or page.texture_files.is_empty():return fail("invalid_page")
		if not (page.get("level") is int or page.get("level") is float) or page.level<0 or page.level!=floor(page.level):return fail("invalid_page")
		if not (page.get("gutter_px") is int or page.get("gutter_px") is float) or page.gutter_px<0:return fail("invalid_page")
		if not page.get("object_ids") is Array or not page.get("object_shards") is Array:return fail("invalid_page")
		var refs: Dictionary={}
		for id in page.object_ids:
			if refs.has(id):return fail("duplicate_page_object",str(id))
			if not objs.has(id):return fail("unknown_object",str(id))
			refs[id]=true
			if object_shards[id] not in page.object_shards:return fail("undeclared_dependency","owner payload")
		for item in objs.values():
			if rect(item.paint_bounds_m).intersects(rect(page.bounds_m))!=refs.has(item.id):return fail("paint_dependency_mismatch",item.id)
		for texture in page.texture_files:
			if not fs.has(texture) or fs[texture].kind!="texture":return fail("undeclared_dependency","page texture")
			var size: Array=fs[texture].pixel_size
			if size[0]!=page.core_px[0]+2*page.gutter_px or size[1]!=page.core_px[1]+2*page.gutter_px:return fail("invalid_page_size")
		if page.get("texture_sha256")!=fs[page.texture_files[0]].sha256:return fail("page_texture_identity")
		pg[page.id]=page.duplicate(true)
	for page in pg.values():
		if not page.get("parent_id") is String:return fail("invalid_parent")
		var parent: String=page.parent_id
		if not parent.is_empty() and (not pg.has(parent) or pg[parent].level>=page.level or not rect(pg[parent].bounds_m).encloses(rect(page.bounds_m))):return fail("invalid_parent")
	parsed=data(base+"/"+c.sites)
	if not parsed.ok:return parsed
	if not parsed.value.get("sites") is Array:return fail("invalid_sites")
	var site_rows: Array=parsed.value.sites
	if not fs.has("receipts/visual_review.json") or fs["receipts/visual_review.json"].sha256!=m.visual_review_sha256:return fail("visual_receipt_mismatch")
	parsed=data(base+"/receipts/visual_review.json")
	if not parsed.ok:return parsed
	if parsed.value.get("status")!="accepted" or parsed.value.get("style_id")!=m.style_id:return fail("visual_receipt_mismatch")
	parsed=data(base+"/"+c.provenance)
	if not parsed.ok:return parsed
	return {"ok":true,"manifest":m.duplicate(true),"catalog":c.duplicate(true),"files":fs,"pages":pg,"objects":objs,"assets":arts,"sites":site_rows.duplicate(true),"provenance":parsed.value.duplicate(true),"optional_missing":missing}
func texture(file_path: String) -> Dictionary:
	if textures.has(file_path):return {"ok":true,"texture":textures[file_path]}
	if not files.has(file_path) or files[file_path].kind!="texture":return fail("undeclared_dependency",file_path)
	var row: Dictionary=files[file_path]
	if not FileAccess.file_exists(root_path+"/"+file_path):return fail("missing_texture",file_path)
	if FileAccess.get_sha256(root_path+"/"+file_path)!=row.sha256:return fail("hash_mismatch",file_path)
	var resource_path:=root_path+"/"+str(row.resource_path)
	if not ResourceLoader.exists(resource_path,"Texture2D"):return fail("missing_imported_texture",resource_path)
	var loaded=ResourceLoader.load(resource_path,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if loaded==null:return fail("invalid_imported_texture",resource_path)
	var image=loaded.get_image()
	if image==null or image.get_width()!=row.pixel_size[0] or image.get_height()!=row.pixel_size[1]:return fail("imported_size_mismatch",resource_path)
	if image.is_compressed() and image.decompress()!=OK:return fail("imported_decompress_failed",resource_path)
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(image.get_data())
	if hashing.finish().hex_encode()!=row.pixel_sha256:return fail("imported_pixel_mismatch",resource_path)
	textures[file_path]=loaded
	requests.append({"path":resource_path,"source_sha256":row.sha256,"imported_pixel_sha256":row.pixel_sha256})
	return {"ok":true,"texture":loaded}
func resolve_page(id: String) -> Dictionary:
	if not pages.has(id):return fail("unknown_page",id)
	var candidate:=id;var failures: Array=[]
	while not candidate.is_empty():
		var page: Dictionary=pages[candidate];var ready:=true
		for file in page.texture_files:
			var loaded: Dictionary=texture(file)
			if not loaded.ok:failures.append({"page_id":candidate,"code":loaded.code});ready=false;break
		if ready:return {"ok":true,"requested_page":id,"selected_page":candidate,"detail_ok":candidate==id,"status":"detail_ready" if candidate==id else "detail_failed_fallback_ready","failures":failures,"page":page.duplicate(true)}
		candidate=page.parent_id
	return {"ok":false,"code":"fallback_failed","failures":failures}
