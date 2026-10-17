extends RefCounted
## S0 composes the existing renderer/cache. No streaming or second game state.
const Instances = preload("res://runtime/instance_index.gd")
var mode: String
var cache: RefCounted
var lifecycle: Array = []
var plan_rebuilds := 0
var candidates_tested := 0
var submitted_objects := 0
var draw_calls := 0
var last_draw := {"candidates_tested":0, "submitted_objects":0, "plan_rebuilds":0, "plan_usec":0}
var request_count := 0
var request_failures: Array = []
var requests: Array = []
func _init(selected: String) -> void:
	mode = selected
	lifecycle.append("selected:" + mode)
	cache = load("res://runtime/asset_cache.gd").new(self)
	lifecycle.append("cache_created")
func resource_requested(path: String, kind: String, result: int) -> void:
	request_count += 1
	requests.append({"path":path, "kind":kind, "result":result, "since_engine_start_usec":Time.get_ticks_usec()})
	if result != OK: request_failures.append({"path":path, "result":result})
func begin_draw() -> void:
	draw_calls += 1
	last_draw = {"candidates_tested":0, "submitted_objects":0, "plan_rebuilds":0, "plan_usec":0}
func plan_instances(records: Array) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = Instances.plan(records)
	plan_rebuilds += 1
	candidates_tested += records.size()
	last_draw.candidates_tested += records.size()
	last_draw.plan_rebuilds += 1
	last_draw.plan_usec += Time.get_ticks_usec() - started
	return result
func tree_submitted() -> void:
	submitted_objects += 1
	last_draw.submitted_objects += 1
static func estimate_rgba8_mips(width: int, height: int) -> int:
	if width <= 0 or height <= 0: return 0
	var total := 0
	while true:
		total += width * height * 4
		if width == 1 and height == 1: return total
		width = maxi(1, width >> 1)
		height = maxi(1, height >> 1)
	return total
func _texture_row(texture: Texture2D, unique: Dictionary) -> void:
	if texture == null: return
	if texture is AtlasTexture:
		_texture_row(texture.atlas, unique)
		return
	var id := texture.get_instance_id()
	if unique.has(id): return
	unique[id] = {"resource_id":id, "path":texture.resource_path, "width":texture.get_width(), "height":texture.get_height(),
		"estimated_bytes":estimate_rgba8_mips(texture.get_width(), texture.get_height())}
func snapshot() -> Dictionary:
	# Ints/strings only in returned records; telemetry never retains resources.
	var unique := {}
	for texture in [cache.fallback, cache.slope, cache.gate, cache.reference]: _texture_row(texture, unique)
	for art in cache.tree_art.values(): _texture_row(art.texture, unique)
	for texture in cache.tile_textures.values(): _texture_row(texture, unique)
	var bytes := 0
	for row in unique.values(): bytes += int(row.estimated_bytes)
	return {"visual_mode":mode, "delegate":"legacy", "streaming_implemented":false,
		"cache_instance_id":cache.get_instance_id(), "lifecycle":lifecycle.duplicate(),
		"tree_plan_rebuilds":plan_rebuilds, "tree_candidates_tested":candidates_tested,
		"tree_submitted_objects":submitted_objects, "draw_calls":draw_calls, "last_draw":last_draw.duplicate(),
		"resources":{"request_count":request_count, "request_failures":request_failures.duplicate(true),
			"requests":requests.duplicate(true), "resident_unique_textures":unique.size(), "resident_textures":unique.values(),
			"resident_terrain_pages":cache.tile_textures.size(), "unique_estimated_bytes":bytes,
			"estimate_model":"RGBA8 plus complete mip chain; cache-owned textures only; not measured VRAM",
			"release_count":null, "release_status":"not_instrumented", "async_attach_count":cache.attach_ms.size()}}
