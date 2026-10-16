extends RefCounted
## Optional precomputed drawing geometry, never authoritative game/map data.
## Any map or renderer change rejects the cache and uses normal preparation.
const VERSION := 2
const ROOT := "res://addons/strategic_map_editor/"
static func cache_path(map_path: String) -> String:
	return map_path+".render.res"
static func signature(map_path: String) -> String:
	var files := DirAccess.get_files_at(ROOT)
	files.sort()
	var parts: Array[String]=[str(VERSION),Engine.get_version_info().string,FileAccess.get_sha256(map_path)]
	for file in files:
		if file.ends_with(".gd") or file.ends_with(".gdshader"):
			parts.append(file+":"+FileAccess.get_sha256(ROOT+file))
	return "\n".join(parts).sha256_text()
static func read(map_path: String) -> Dictionary:
	var path:=cache_path(map_path)
	if not FileAccess.file_exists(path): return {}
	var saved=ResourceLoader.load(path,"Resource",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or saved.get_meta("signature","")!=signature(map_path):return {}
	var data: Variant=saved.get_meta("prepared",null)
	if not data is Dictionary:return {}
	for key in ["polygon_meshes","polygon_signatures","water_shapes","natural_details","water_join","surface_cells"]:
		if not data.get(key) is Dictionary:return {}
	for key in ["shapes","runs_cache","profiles","connections","mask_cache"]:
		if not data.water_join.get(key) is Dictionary:return {}
	return data
static func apply_details(canvas: Control, prepared: Dictionary) -> void:
	canvas._detail_cache.merge(prepared.natural_details)
	canvas._surface_cells=prepared.surface_cells.duplicate(true)
	var features: Array=canvas.doc.data.features.filter(func(f):return f.kind!="water" or canvas.doc.layer(f.layer).visible)
	canvas.water_join.prepare(features,canvas.geometry_revision)
	for key in prepared.water_join: canvas.water_join.set(key,prepared.water_join[key].duplicate(true))
static func write(map_path: String, canvas: Control) -> Error:
	var details := {}
	for key in canvas._detail_cache:
		if key is String and (key.ends_with(":natural_fill") or key.ends_with(":natural_shores") or key.ends_with(":natural_marks")):
			details[key]=canvas._detail_cache[key]
	var resource:=Resource.new()
	var water := {}
	for key in ["shapes","runs_cache","profiles","connections","mask_cache"]: water[key]=canvas.water_join.get(key)
	resource.set_meta("signature",signature(map_path))
	resource.set_meta("prepared",{"polygon_meshes":canvas.polygon_meshes,"polygon_signatures":canvas.polygon_signatures,"water_shapes":canvas._water_shapes,"natural_details":details,"water_join":water,"surface_cells":canvas._surface_cells})
	return ResourceSaver.save(resource,cache_path(map_path),ResourceSaver.FLAG_COMPRESS)
