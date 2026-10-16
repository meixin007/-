# scripts/core/geo_map_data_contract.gd
extends RefCounted

class_name GeoMapDataContract

const DEFAULT_NODES_PATH := "res://data/map/tang_geo_nodes.json"
const DEFAULT_CORRIDORS_PATH := "res://data/map/tang_geo_corridors.json"
const DEFAULT_REGIONS_PATH := "res://data/map/tang_macro_regions.json"

var nodes: Dictionary = {} # id -> Dictionary
var corridors: Dictionary = {} # id -> Dictionary
var regions: Dictionary = {} # id -> Dictionary
var is_loaded: bool = false
var last_validation_errors: Array[String] = []

func load_all(nodes_path: String = DEFAULT_NODES_PATH, corridors_path: String = DEFAULT_CORRIDORS_PATH, regions_path: String = DEFAULT_REGIONS_PATH) -> Dictionary:
	nodes.clear()
	corridors.clear()
	regions.clear()
	last_validation_errors.clear()
	
	var nodes_result := _load_json_file(nodes_path)
	if not bool(nodes_result.get("ok", false)):
		return nodes_result
	var nodes_raw = nodes_result.get("data", {}).get("nodes", [])
	if nodes_raw is Array:
		for item in nodes_raw:
			if item is Dictionary and item.has("id"):
				nodes[str(item["id"])] = item
				
	var corridors_result := _load_json_file(corridors_path)
	if not bool(corridors_result.get("ok", false)):
		return corridors_result
	var corridors_raw = corridors_result.get("data", {}).get("corridors", [])
	if corridors_raw is Array:
		for item in corridors_raw:
			if item is Dictionary and item.has("id"):
				corridors[str(item["id"])] = item
				
	var regions_result := _load_json_file(regions_path)
	if not bool(regions_result.get("ok", false)):
		return regions_result
	var regions_raw = regions_result.get("data", {}).get("regions", [])
	if regions_raw is Array:
		for item in regions_raw:
			if item is Dictionary and item.has("id"):
				regions[str(item["id"])] = item
				
	is_loaded = true
	var validation := validate_integrity()
	if not bool(validation.get("ok", false)):
		return validation
		
	return {
		"ok": true,
		"nodes_count": nodes.size(),
		"corridors_count": corridors.size(),
		"regions_count": regions.size()
	}

func get_node(node_id: String) -> Dictionary:
	if not is_loaded:
		load_all()
	return nodes.get(node_id, {}).duplicate(true)

func get_all_nodes() -> Dictionary:
	if not is_loaded:
		load_all()
	return nodes.duplicate(true)

func get_corridor(corridor_id: String) -> Dictionary:
	if not is_loaded:
		load_all()
	return corridors.get(corridor_id, {}).duplicate(true)

func get_all_corridors() -> Dictionary:
	if not is_loaded:
		load_all()
	return corridors.duplicate(true)

func get_region(region_id: String) -> Dictionary:
	if not is_loaded:
		load_all()
	return regions.get(region_id, {}).duplicate(true)

func get_all_regions() -> Dictionary:
	if not is_loaded:
		load_all()
	return regions.duplicate(true)

func get_node_screen_position(node_id: String, base_resolution: Vector2 = Vector2(3720, 2400)) -> Vector2:
	var node_data := get_node(node_id)
	if node_data.is_empty():
		return Vector2.ZERO
	var coords = node_data.get("coords", [0.5, 0.5])
	if coords is Array and coords.size() >= 2:
		return Vector2(float(coords[0]) * base_resolution.x, float(coords[1]) * base_resolution.y)
	return Vector2.ZERO

func validate_integrity() -> Dictionary:
	var errors: Array[String] = []
	
	if nodes.is_empty():
		errors.append("No geo nodes loaded")
	if corridors.is_empty():
		errors.append("No geo corridors loaded")
		
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		var coords = node.get("coords", [])
		if not (coords is Array and coords.size() == 2):
			errors.append("Node %s has invalid coords format" % node_id)
		else:
			var cx := float(coords[0])
			var cy := float(coords[1])
			if cx < 0.0 or cx > 1.0 or cy < 0.0 or cy > 1.0:
				errors.append("Node %s coords [%f, %f] out of normalized bounds [0, 1]" % [node_id, cx, cy])
		var reg_id := str(node.get("region_id", ""))
		if not reg_id.is_empty() and not regions.has(reg_id):
			errors.append("Node %s references unknown region %s" % [node_id, reg_id])
			
	for corridor_id in corridors.keys():
		var corr: Dictionary = corridors[corridor_id]
		var from_id := str(corr.get("from_node_id", ""))
		var to_id := str(corr.get("to_node_id", ""))
		if not nodes.has(from_id):
			errors.append("Corridor %s references missing from_node_id: %s" % [corridor_id, from_id])
		if not nodes.has(to_id):
			errors.append("Corridor %s references missing to_node_id: %s" % [corridor_id, to_id])
		var days := int(corr.get("base_travel_days", 0))
		if days <= 0:
			errors.append("Corridor %s has invalid base_travel_days: %d" % [corridor_id, days])
			
	last_validation_errors = errors
	return {
		"ok": errors.is_empty(),
		"errors": errors
	}

func _load_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "error": "File not found: " + file_path}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open file: " + file_path}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "error": "JSON parse error (%d) at line %d in %s" % [err, json.get_error_line(), file_path]}
	if not (json.data is Dictionary):
		return {"ok": false, "error": "JSON root is not a Dictionary in " + file_path}
	return {"ok": true, "data": json.data}
