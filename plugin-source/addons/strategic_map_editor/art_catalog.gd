@tool
extends RefCounted
## Presentation only. The descriptor is a resource registry, never a map rule source.
const STYLES := ["schematic", "tongguan_v1"]
const ART_ROOT := "res://addons/strategic_map_editor/art/"
const ROOT := "res://addons/strategic_map_editor/art/tongguan_v1/"
const EXTENSION_ROOT := "res://addons/strategic_map_editor/art/tongguan_v2/"
const V3_ROOT := "res://addons/strategic_map_editor/art/tongguan_v3/"
const V4_ROOT := "res://addons/strategic_map_editor/art/tongguan_v4/"
static var registry_root := ART_ROOT # Tests may point this at an isolated user:// fixture.
static var _cache: Dictionary = {}
static var _error := ""
static var _bundles: Dictionary = {}
static var _bundle_order: Array = []
static var _asset_bundles: Dictionary = {}
static var generation := 0
static var _groups: Dictionary = {}
static var _library_deleted: Dictionary = {}
static var _library_loaded := false
static var _library_error := ""

# Library deletion is reversible. Keep descriptors and atlases for existing maps
# and automatic terrain composition; never change a map's recorded bundle hash.
static func library_error() -> String:
	if not _library_loaded:
		_library_loaded = true
		var path := registry_root.path_join("library_deleted.json")
		if FileAccess.file_exists(path):
			var json := JSON.new()
			var parse_error := json.parse(FileAccess.get_file_as_string(path))
			var parsed: Variant = json.data
			if parse_error != OK or not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("deleted") is Dictionary:
				_library_error = "素材库删除记录无法读取，未覆盖原记录：" + path
			else:
				for key in parsed.deleted:
					if not parsed.deleted[key] is bool or not parsed.deleted[key]:
						_library_error = "素材库删除记录格式错误：" + path
						break
				if _library_error.is_empty(): _library_deleted = parsed.deleted
	return _library_error

static func is_library_deleted(key: String) -> bool:
	library_error()
	return _library_deleted.has(key)

static func library_keys(deleted: bool = false) -> Array:
	return catalog().get("assets", {}).keys().filter(func(key): return is_library_deleted(key) == deleted)

static func set_library_deleted(key: String, deleted: bool) -> Dictionary:
	if descriptor(key).is_empty(): return {"ok":false,"error":"请选择一个真实素材；混合预设不能删除。"}
	var issue := library_error()
	if not issue.is_empty(): return {"ok":false,"error":issue}
	var next := _library_deleted.duplicate()
	if deleted: next[key] = true
	else: next.erase(key)
	if next == _library_deleted: return {"ok":true}
	var path := registry_root.path_join("library_deleted.json")
	var temp := path + ".%s.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return {"ok":false,"error":"无法写入素材库删除记录。"}
	file.store_string(JSON.stringify({"version":1,"deleted":next}, "\t") + "\n")
	file.flush()
	var error_code := file.get_error()
	file.close()
	if error_code != OK or DirAccess.rename_absolute(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		return {"ok":false,"error":"无法保存素材库删除记录，素材库保持不变。"}
	_library_deleted = next
	generation += 1
	return {"ok":true}

static func catalog() -> Dictionary:
	if not _cache.is_empty() or not _error.is_empty(): return _cache
	var directories := DirAccess.get_directories_at(registry_root)
	directories.sort()
	for directory in directories:
		var root := registry_root + directory + "/"
		var path := root + "catalog.json"
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not parsed.get("assets") is Dictionary or parsed.get("bundle_id") != directory or not (parsed.get("version") is int or parsed.get("version") is float) or parsed.version < 1 or parsed.version != floorf(parsed.version):
			_error = "美术素材描述格式或版本错误：" + path
			return {}
		var parent: Variant = parsed.get("extends", "")
		if not parent is String:
			_error = "素材包依赖格式错误：" + path
			return {}
		_bundles[directory] = {"root":root,"catalog":parsed,"parent":parent}
	if not _bundles.has("tongguan_v1"):
		_error = "缺少基础美术素材描述：" + registry_root + "tongguan_v1/catalog.json"
		return {}
	var visiting := {}
	var visited := {}
	for id in directories:
		if not _bundles.has(id): continue
		var issue := _visit_bundle(id,visiting,visited)
		if not issue.is_empty():
			_error = issue
			return {}
	_cache = _bundles["tongguan_v1"].catalog.duplicate(true)
	_cache.assets = {}
	for id in _bundle_order:
		for key in _bundles[id].catalog.assets:
			if _cache.assets.has(key):
				_error = "素材 ID 在多个资源包中冲突：" + str(key)
				_cache = {}
				return {}
			_cache.assets[key] = _bundles[id].catalog.assets[key]
			_asset_bundles[key] = id
	return _cache

static func _visit_bundle(id: String, visiting: Dictionary, visited: Dictionary) -> String:
	if visited.has(id): return ""
	if visiting.has(id): return "素材包依赖形成循环：" + id
	visiting[id] = true
	var parent: String = _bundles[id].parent
	if not parent.is_empty():
		if not _bundles.has(parent): return "素材包缺少依赖：" + id + " → " + parent
		var issue := _visit_bundle(parent,visiting,visited)
		if not issue.is_empty(): return issue
	elif id != "tongguan_v1": return "扩展素材包缺少基础依赖：" + id
	visiting.erase(id)
	visited[id] = true
	_bundle_order.append(id)
	return ""

static func invalidate_cache() -> void:
	generation += 1
	_library_loaded = false
	_library_deleted = {}
	_library_error = ""
	_groups.clear()
	_cache = {}
	_error = ""
	_bundles = {}
	_bundle_order = []
	_asset_bundles = {}

static func error() -> String:
	catalog()
	return _error

static func descriptor(key: String) -> Dictionary:
	return catalog().get("assets", {}).get(key, {})

static func asset_root(key: String) -> String:
	catalog()
	return bundle_root(str(_asset_bundles.get(key,"tongguan_v1")))

static func asset_bundle(key: String) -> String:
	catalog()
	return str(_asset_bundles.get(key,""))

static func bundle_root(id: String) -> String:
	catalog()
	return str(_bundles.get(id,{}).get("root",""))

static func available_bundle_ids() -> Array:
	catalog()
	return _bundle_order.duplicate()

static func bundle_chain(id: String) -> Array:
	catalog()
	if not _bundles.has(id): return []
	var chain: Array = []
	var current := id
	while not current.is_empty():
		chain.push_front(current)
		current = str(_bundles[current].parent)
	return chain

static func bundle_contains(id: String, dependency: String) -> bool:
	return dependency in bundle_chain(id)

static func requires_extension(instances: Array) -> bool:
	return required_bundle_id(instances) != "tongguan_v1"

static func bundle_rank(id: String) -> int:
	catalog()
	return _bundle_order.find(id)

static func required_bundle_id(instances: Array, features: Array = []) -> String:
	catalog()
	var required := "tongguan_v1"
	var keys: Dictionary = {}
	for feature in features:
		if not feature is Dictionary: continue
		var visual: Variant = feature.get("visual", {})
		if not visual is Dictionary: continue
		var variant := str(visual.get("variant", "auto"))
		if variant != "auto": keys[variant]=true
	for item in instances:
		if not item is Dictionary: continue
		keys[str(item.get("asset", ""))]=true
	for key in keys:
		var source := str(_asset_bundles.get(key,""))
		if source.is_empty(): continue # Unknown assets are reported by the document validator.
		if bundle_contains(source,required): required = source
		elif not bundle_contains(required,source): return "" # Incompatible sibling bundles.
	return required

static func label(key: String) -> String:
	return "自动混合 / 按城镇类型" if key == "auto" else str(descriptor(key).get("label", key))

static func group(kind: String) -> Array:
	if _groups.has(kind): return _groups[kind].duplicate()
	var result: Array = []
	for key in catalog().get("assets", {}):
		var item: Dictionary = descriptor(key)
		if item.get("group") == kind or (kind == "hills" and item.get("hills_compatible", false)):
			result.append(key)
	_groups[kind] = result
	return result.duplicate()

static func scatter_group(kind: String) -> Array:
	return group(kind).filter(func(key): return not descriptor(key).get("manual_only", false))

static func variants(kind: String) -> Array:
	# Extended manual composition pieces are instances, not generated feature skins.
	return ["auto"] + group(kind).filter(func(key): return not (asset_root(key) != ROOT and descriptor(key).get("manual_only", false)))

static func bundle_info(bundle_id: String = "tongguan_v1") -> Dictionary:
	if catalog().is_empty(): return {}
	var chain := bundle_chain(bundle_id)
	if chain.is_empty(): return {}
	var hashes: Dictionary = {}
	var catalog_hashes: Array[String] = []
	var manifest_hashes: Array[String] = []
	for id in chain:
		var root := bundle_root(id)
		var path := root + "manifest.json"
		if not FileAccess.file_exists(path): return {}
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not manifest is Dictionary or manifest.get("bundle_id") != id or manifest.get("version") != _bundles[id].catalog.version or manifest.get("extends", "") != _bundles[id].parent or not manifest.get("assets") is Array: return {}
		for asset in manifest.assets:
			if not asset is Dictionary or not asset.get("file") is String or not asset.get("sha256") is String: return {}
			if hashes.has(asset.file) and hashes[asset.file] != asset.sha256: return {}
			hashes[asset.file] = asset.sha256
		catalog_hashes.append(FileAccess.get_sha256(root + "catalog.json"))
		manifest_hashes.append(FileAccess.get_sha256(path))
	var catalog_hash := catalog_hashes[0] if chain.size() == 1 else ":".join(catalog_hashes).sha256_text()
	var manifest_hash := manifest_hashes[0] if chain.size() == 1 else ":".join(manifest_hashes).sha256_text()
	return {"id":bundle_id,"version":_bundles[bundle_id].catalog.version,"catalog_sha256":catalog_hash,"manifest_sha256":manifest_hash,"asset_hashes":hashes}

static func bundle_differences(recorded: Dictionary) -> Array:
	var differences: Array = []
	if recorded.is_empty(): return differences
	var current := bundle_info(str(recorded.get("id", "tongguan_v1")))
	if current.is_empty(): return [{"file":"catalog.json", "reason":"当前素材包无法读取。"}]
	if recorded.get("id") != current.id or recorded.get("version") != current.version or recorded.get("catalog_sha256") != current.catalog_sha256:
		differences.append({"file":"catalog.json","reason":"素材描述或版本已变化。"})
	if recorded.has("manifest_sha256") and recorded.manifest_sha256 != current.manifest_sha256:
		differences.append({"file":"manifest.json","reason":"资源清单已变化。"})
	var prior: Dictionary = recorded.get("asset_hashes", {})
	if not prior.is_empty():
		for file in prior:
			if not current.asset_hashes.has(file): differences.append({"file":file,"reason":"文档素材在当前包缺失。"})
			elif prior[file] != current.asset_hashes[file]: differences.append({"file":file,"reason":"图片内容已变化。"})
		for file in current.asset_hashes:
			if not prior.has(file): differences.append({"file":file,"reason":"当前包新增图片。"})
	return differences

static func validate_descriptor(key: String) -> String:
	var item := descriptor(key)
	if item.is_empty(): return "未知素材：" + key
	if not item.get("atlas") is String or str(item.atlas).get_file() != item.atlas or not item.get("rect") is Array or item.rect.size() != 4:
		return "素材描述缺少图集或裁切区域：" + key
	for number in item.rect:
		if not (number is int or number is float) or number < 0: return "素材裁切区域无效：" + key
	if item.rect[2] < 1 or item.rect[3] < 1: return "素材裁切区域为空：" + key
	if not item.get("width") is float and not item.get("width") is int: return "素材视觉宽度无效：" + key
	if item.width < 4 or item.width > 512: return "素材视觉宽度超出范围：" + key
	if not item.get("anchor") is Array or item.anchor.size() != 2: return "素材落点无效：" + key
	for number in item.anchor:
		if not (number is int or number is float) or number < 0 or number > 1: return "素材落点超出范围：" + key
	if item.get("group") in ["city","pass"]:
		if not item.get("gate_anchor") is Array or item.gate_anchor.size() != 2: return "城关素材缺少门口锚点：" + key
		for number in item.gate_anchor:
			if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 1: return "城关素材门口锚点无效：" + key
	return ""

static func validate(kind: String, visual: Variant) -> String:
	if not visual is Dictionary: return "美术设置必须是对象。"
	if visual.has("anchor_only") and (not visual.anchor_only is bool or kind not in ["city","pass","ford"]): return "地点锚点只用于城池、关口和渡口，开关须为布尔值。"
	if visual.has("shared_boundary_set"):
		if kind not in ["prefecture","country_border","province_border","coastline"] or not visual.shared_boundary_set is String or visual.shared_boundary_set.is_empty() or visual.shared_boundary_set.length()>64:return "共享边界标识只适用于边界，且长度须为 1–64 字。"
	if visual.has("boundary_line"):
		var line: Variant=visual.boundary_line
		if kind not in ["country_border","province_border","coastline"] or not line is Dictionary:return "边界线型只用于国界、道界或海岸线。"
		if line.get("style","") not in ["solid","dashed"]:return "边界线型无效。"
		for key in ["min_pixels","max_pixels"]:
			if not (line.get(key) is float or line.get(key) is int) or not is_finite(float(line[key])) or line[key]<.1 or line[key]>8:return "边界屏幕线宽应为 0.1–8。"
		if line.min_pixels>line.max_pixels:return "边界最小线宽不得大于最大线宽。"
	if visual.has("faction"):
		var faction: Variant=visual.faction
		if kind!="prefecture" or not faction is Dictionary: return "势力颜色只用于州域。"
		if not faction.get("name") is String or faction.name.strip_edges().is_empty() or faction.name.length()>64: return "势力名称应为 1–64 字。"
		if not faction.get("color") is String or not Color.html_is_valid(faction.color): return "势力颜色无效。"
	if visual.has("surface_marks") and (kind != "water" or not visual.surface_marks is bool): return "水面细纹开关只适用于水域。"
	if visual.has("water_style") and (kind != "water" or not visual.water_style is String or visual.water_style not in ["plain","inked"]): return "水面色调只可选普通或手绘，且仅适用于水域。"
	if visual.has("label_lod"):
		if kind not in ["city","pass","label","ford"] or not visual.label_lod is Dictionary: return "缩放标注只适用于地点和地形文字。"
		var lod: Dictionary=visual.label_lod
		for key in lod:
			if key not in ["min_zoom","min_pixels","max_pixels","priority","avoid_overlap","legacy_min_zoom"]: return "未知缩放标注设置。"
		for key in ["min_zoom","min_pixels","max_pixels","priority","legacy_min_zoom"]:
			if not lod.has(key): continue
			var value: Variant=lod[key]
			if not (value is int or value is float) or not is_finite(float(value)): return "缩放标注参数必须为有限数值。"
		if lod.get("min_zoom",0.0)<0 or lod.get("min_zoom",0.0)>32: return "标注缩放门槛应为0–32。"
		if lod.has("legacy_min_zoom") and (lod.legacy_min_zoom<lod.get("min_zoom",0.0) or lod.legacy_min_zoom>32):return "保留原近景标注门槛应在缩放下限至32之间。"
		if lod.get("min_pixels",8.0)<8 or lod.get("max_pixels",40.0)>64 or lod.get("min_pixels",8.0)>lod.get("max_pixels",40.0): return "屏幕标注字号应为8–64且下限不大于上限。"
		if lod.get("priority",0)<0 or lod.get("priority",0)>100 or lod.get("priority",0)!=floorf(float(lod.get("priority",0))): return "标注优先级应为0–100整数。"
		if lod.has("avoid_overlap") and not lod.avoid_overlap is bool: return "标注避让必须为开关。"
	if visual.has("ribbon_clip_rect"):
		var crop=visual.ribbon_clip_rect
		if kind!="water" or not crop is Array or crop.size()!=4: return "水道表现裁剪范围需要水域及四个数值。"
		for value in crop:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value))>65536: return "水道表现裁剪范围无效。"
		if float(crop[2])<=0 or float(crop[3])<=0: return "水道表现裁剪范围必须有面积。"
	if visual.has("shore_masks"):
		if kind!="water" or not visual.shore_masks is Array or visual.shore_masks.size()>16: return "岸线接缝遮罩只适用于水域，最多16块。"
		for mask in visual.shore_masks:
			if not mask is Array or mask.size()!=4: return "岸线接缝遮罩需要四个数值。"
			for value in mask:
				if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value))>65536: return "岸线接缝遮罩坐标无效。"
			if float(mask[2])<=0 or float(mask[3])<=0:return "岸线接缝遮罩必须有面积。"
	if visual.has("surface_flow"):
		if kind!="water" or not visual.surface_flow is Array or visual.surface_flow.size()>512: return "水面笔触只适用于水域，最多512段。"
		for stroke in visual.surface_flow:
			if not stroke is Array or stroke.size()<2 or stroke.size()>32: return "水面笔触需要2–32个坐标。"
			for point in stroke:
				if not point is Array or point.size()!=2: return "水面笔触坐标无效。"
				for number in point:
					if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number))>65536: return "水面笔触坐标无效。"
	if visual.get("variant", "auto") not in variants(kind): return "素材不适用于此对象类型。"
	var density: Variant = visual.get("density", 1.0)
	var seed_value: Variant = visual.get("seed", 0)
	if not (density is int or density is float) or not is_finite(float(density)) or density < 0.5 or density > 2: return "素材密度应为 0.5–2。"
	if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or seed_value != floorf(seed_value) or seed_value < 0 or seed_value > 999999: return "变化编号应为 0–999999 的整数。"
	for key in ["offset", "label_offset"]:
		if not visual.has(key): continue
		var value: Variant = visual[key]
		if not value is Array or value.size() != 2: return "外观偏移需要两个坐标。"
		for component in value:
			if not (component is float or component is int) or not is_finite(float(component)) or absf(float(component)) > 1024: return "外观偏移超出范围。"
	for key in ["width_factor", "label_size"]:
		if not visual.has(key): continue
		var value: Variant = visual[key]
		if not (value is int or value is float) or not is_finite(float(value)): return "外观比例或字号无效。"
		if key == "width_factor" and (value < 0.5 or value > 2): return "外观比例应为 0.5–2。"
		if key == "label_size" and (value < 8 or value > 48): return "标签字号应为 8–48。"
	for key in ["visible", "show_label", "scatter", "auxiliary"]:
		if visual.has(key) and not visual[key] is bool: return "外观开关无效。"
	if visual.has("scatter_masks"):
		if kind not in ["mountain", "hills", "forest"] or not visual.scatter_masks is Array or visual.scatter_masks.size() > 128: return "局部散布锁定区无效。"
		for area in visual.scatter_masks:
			var rect: Variant = area.get("rect") if area is Dictionary else area
			if not rect is Array or rect.size() != 4: return "局部散布锁定区需要矩形坐标。"
			if area is Dictionary and (not area.get("group_id") is String or area.group_id.is_empty()): return "局部散布锁定区缺少实例组。"
			for number in rect:
				if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 65536: return "局部散布锁定区坐标无效。"
			if rect[2] <= 0 or rect[3] <= 0: return "局部散布锁定区尺寸无效。"
	if visual.has("scatter_overrides"):
		if kind not in ["mountain", "hills", "forest"] or not visual.scatter_overrides is Array or visual.scatter_overrides.size() > 128: return "局部散布变化区无效。"
		for item in visual.scatter_overrides:
			if not item is Dictionary or not item.get("rect") is Array or item.rect.size() != 4: return "局部散布变化区需要矩形坐标。"
			for number in item.rect:
				if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 65536: return "局部散布变化区坐标无效。"
			if item.rect[2] <= 0 or item.rect[3] <= 0 or not item.get("seed") is int or item.seed < 0 or item.seed > 999999: return "局部散布变化编号无效。"
	if visual.has("water_brush") and (kind != "water" or not visual.water_brush is bool): return "水系画笔标记只能用于水域。"
	if visual.has("ribbon"):
		if kind != "water" or not visual.ribbon is Dictionary: return "水面表现曲线只可用于水域。"
		if visual.ribbon.has("end_styles"):
			if not visual.ribbon.end_styles is Array or visual.ribbon.end_styles.size()!=2: return "河流起笔与收笔各需要一种端点样式。"
			for style in visual.ribbon.end_styles:
				if not style is String or style not in ["auto","source","join","mouth"]: return "河流端点样式无效。"
		if not visual.ribbon.get("points") is Array or not visual.ribbon.get("widths") is Array or visual.ribbon.points.size() < 2 or visual.ribbon.points.size() > 128 or visual.ribbon.points.size() != visual.ribbon.widths.size(): return "水面表现曲线需要 2–128 个坐标及对应宽度。"
		for point in visual.ribbon.points:
			if not point is Array or point.size() != 2: return "水面表现曲线坐标无效。"
			for number in point:
				if not (number is int or number is float) or not is_finite(float(number)): return "水面表现曲线坐标无效。"
		for width in visual.ribbon.widths:
			if not (width is int or width is float) or not is_finite(float(width)) or width < 6 or width > 128: return "水面表现宽度应为 6–128。"
	if visual.has("path"):
		if kind not in ["valley", "trail", "crossing"] or not visual.path is Array or visual.path.size() < 2 or visual.path.size() > 128: return "通道表现线只可用于自然通道。"
		for point in visual.path:
			if not point is Array or point.size() != 2: return "通道表现线坐标无效。"
			for number in point:
				if not (number is int or number is float) or not is_finite(float(number)): return "通道表现线坐标无效。"
	if visual.has("path_style") and (kind != "valley" or visual.path_style not in ["subtle", "painted", "earth"]): return "谷道表现样式无效。"
	if visual.has("ridge_guide"):
		if kind not in ["mountain","hills"] or not visual.ridge_guide is Array or visual.ridge_guide.size() < 2 or visual.ridge_guide.size() > 128: return "山脊引导线只可用于山地，需 2–128 个点。"
		for point in visual.ridge_guide:
			if not point is Array or point.size() != 2: return "山脊引导线坐标无效。"
			for number in point:
				if not (number is int or number is float) or not is_finite(float(number)): return "山脊引导线坐标无效。"
	return ""

static func site_variant(f: Dictionary) -> String:
	var chosen: String = f.get("visual", {}).get("variant", "auto")
	if chosen != "auto": return chosen
	if f.kind == "pass": return "pass_gate"
	if f.domain_id == "changan_pressure_node" or f.name == "长安": return "city_capital"
	return "city_timber" if f.name.contains("镇") or f.id in ["tg_west_city", "tg_east_city"] else "city_walled"
