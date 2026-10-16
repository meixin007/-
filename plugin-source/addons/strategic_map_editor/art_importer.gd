@tool
extends RefCounted
## Imports one transparent, manually placed authoring sprite into a bundle.
## This never changes map geometry, rules, or an open document's recorded hash.

const MAX_PNG_BYTES := 16 * 1024 * 1024
const MIN_EDGE := 32
const MAX_EDGE := 4096
const GROUPS := ["forest", "mountain", "ground", "city", "pass"]

static func probe(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "png" or not FileAccess.file_exists(path):
		return {"ok":false,"error":"请选择已有的 PNG 图片。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 100 or file.get_length() > MAX_PNG_BYTES:
		return {"ok":false,"error":"素材 PNG 无法读取或超过 16 MiB。"}
	var size := file.get_length()
	var bytes := file.get_buffer(size)
	file.close()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return {"ok":false,"error":"无法计算素材 PNG 哈希。"}
	var sha256 := hashing.finish().hex_encode()
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return {"ok":false,"error":"素材 PNG 解码失败。"}
	var width := image.get_width()
	var height := image.get_height()
	if width < MIN_EDGE or height < MIN_EDGE or width > MAX_EDGE or height > MAX_EDGE:
		return {"ok":false,"error":"素材边长应为 32–4096 像素。"}
	if not image.get_used_rect().has_area():
		return {"ok":false,"error":"素材 PNG 全透明。"}
	for x in range(width):
		if image.get_pixel(x,0).a > .1 or image.get_pixel(x,height-1).a > .1:
			return {"ok":false,"error":"素材触及上下边界；请保留透明边缘。"}
	for y in range(height):
		if image.get_pixel(0,y).a > .1 or image.get_pixel(width-1,y).a > .1:
			return {"ok":false,"error":"素材触及左右边界；请保留透明边缘。"}
	return {"ok":true,"width":width,"height":height,"bytes":size,"sha256":sha256,"content":bytes,"image":image}

static func suggest_id(path: String, existing: Dictionary) -> String:
	var stem := path.get_file().get_basename().to_lower()
	var cleaned := ""
	for i in range(stem.length()):
		var character := stem.substr(i,1)
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_": cleaned += character
		elif not cleaned.ends_with("_"): cleaned += "_"
	cleaned = cleaned.trim_prefix("_").trim_suffix("_")
	if cleaned.length() < 3 or not cleaned.substr(0,1) in "abcdefghijklmnopqrstuvwxyz": cleaned = "art_" + cleaned
	cleaned = cleaned.substr(0,56)
	var candidate := cleaned
	var number := 2
	while existing.has(candidate) or candidate == "auto":
		candidate = "%s_%d" % [cleaned,number]
		number += 1
	return candidate

static func _valid_id(id: String) -> bool:
	if id == "auto" or id.length() < 3 or id.length() > 64 or not id.substr(0,1) in "abcdefghijklmnopqrstuvwxyz": return false
	for i in range(id.length()):
		if not id.substr(i,1) in "abcdefghijklmnopqrstuvwxyz0123456789_": return false
	return true

static func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value,"\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

static func _write_png(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

static func _read_bundle(root: String) -> Dictionary:
	var catalog_path := root.path_join("catalog.json")
	var manifest_path := root.path_join("manifest.json")
	if not FileAccess.file_exists(catalog_path) or not FileAccess.file_exists(manifest_path):
		return {"ok":false,"error":"素材包缺少 catalog.json 或 manifest.json。"}
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not catalog is Dictionary or not catalog.get("assets") is Dictionary or catalog.get("bundle_id") != "tongguan_v1" or catalog.get("version") != 1:
		return {"ok":false,"error":"素材描述格式或版本错误。"}
	if not manifest is Dictionary or not manifest.get("assets") is Array or manifest.get("bundle_id") != catalog.bundle_id or manifest.get("version") != catalog.version:
		return {"ok":false,"error":"素材清单格式或版本错误。"}
	return {"ok":true,"catalog":catalog,"manifest":manifest}

static func install(root: String, source: String, id: String, label: String, group: String, visual_width: float, anchor: Vector2, gate_anchor: Vector2 = Vector2(-1,-1)) -> Dictionary:
	if not root.is_absolute_path() or not DirAccess.dir_exists_absolute(root):
		return {"ok":false,"error":"素材包目录无效。"}
	if not _valid_id(id): return {"ok":false,"error":"素材 ID 应为 3–64 位小写字母、数字或下划线，且以字母开头。"}
	if label.strip_edges().is_empty() or label.length() > 80:
		return {"ok":false,"error":"素材名称应为 1–80 个字符。"}
	if group not in GROUPS or not is_finite(visual_width) or visual_width < 4 or visual_width > 512 or not is_finite(anchor.x) or not is_finite(anchor.y) or anchor.x < 0 or anchor.x > 1 or anchor.y < 0 or anchor.y > 1:
		return {"ok":false,"error":"素材类别、视觉宽度或锚点无效。"}
	if group in ["city","pass"]:
		if gate_anchor == Vector2(-1,-1): gate_anchor = anchor
		if not gate_anchor.is_finite() or gate_anchor.x < 0 or gate_anchor.x > 1 or gate_anchor.y < 0 or gate_anchor.y > 1:
			return {"ok":false,"error":"城关门口锚点应在 0–1 范围内。"}
	var bundle := _read_bundle(root)
	if not bundle.ok: return bundle
	if bundle.catalog.assets.has(id): return {"ok":false,"error":"素材 ID 已存在，请换一个 ID。"}
	var png_name := id + ".png"
	var target := root.path_join(png_name)
	if FileAccess.file_exists(target): return {"ok":false,"error":"同名 PNG 已存在，不会覆盖。"}
	for entry in bundle.manifest.assets:
		if entry is Dictionary and entry.get("file") == png_name:
			return {"ok":false,"error":"素材清单已有同名 PNG。"}
	var inspected := probe(source)
	if not inspected.ok: return inspected
	var descriptor := {"label":label.strip_edges(),"group":group,"atlas":png_name,"rect":[0,0,inspected.width,inspected.height],"width":visual_width,"anchor":[anchor.x,anchor.y],"manual_only":true}
	if group in ["city","pass"]: descriptor.gate_anchor = [gate_anchor.x,gate_anchor.y]
	var catalog: Dictionary = bundle.catalog.duplicate(true)
	var manifest: Dictionary = bundle.manifest.duplicate(true)
	catalog.assets[id] = descriptor
	manifest.assets.append({"file":png_name,"width":inspected.width,"height":inspected.height,"mode":"RGBA","sha256":inspected.sha256,"bytes":inspected.bytes,"sprites":1,"status":"USER_IMPORTED_UNREVIEWED"})
	var catalog_path := root.path_join("catalog.json")
	var manifest_path := root.path_join("manifest.json")
	var suffix := ".import_" + str(Time.get_ticks_usec()) + "_" + str(randi())
	var catalog_temp := catalog_path + suffix + ".tmp"
	var manifest_temp := manifest_path + suffix + ".tmp"
	var catalog_backup := catalog_path + suffix + ".bak"
	var manifest_backup := manifest_path + suffix + ".bak"
	if not _write_json(catalog_temp,catalog) or not _write_json(manifest_temp,manifest):
		DirAccess.remove_absolute(catalog_temp)
		DirAccess.remove_absolute(manifest_temp)
		return {"ok":false,"error":"无法预写素材描述与清单。"}
	if DirAccess.copy_absolute(catalog_path,catalog_backup) != OK or DirAccess.copy_absolute(manifest_path,manifest_backup) != OK:
		DirAccess.remove_absolute(catalog_temp)
		DirAccess.remove_absolute(manifest_temp)
		return {"ok":false,"error":"无法备份素材描述与清单。"}
	if not _write_png(target,inspected.content) or FileAccess.get_sha256(target) != inspected.sha256:
		DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(catalog_temp)
		DirAccess.remove_absolute(manifest_temp)
		return {"ok":false,"error":"PNG 复制或哈希检查失败；原素材包保留。"}
	if DirAccess.rename_absolute(catalog_temp,catalog_path) != OK:
		DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(catalog_temp)
		DirAccess.remove_absolute(manifest_temp)
		return {"ok":false,"error":"素材描述替换失败；原素材包保留。"}
	if DirAccess.rename_absolute(manifest_temp,manifest_path) != OK:
		DirAccess.copy_absolute(catalog_backup,catalog_path)
		DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(manifest_temp)
		return {"ok":false,"error":"素材清单替换失败；已尝试恢复原描述，请检查备份。"}
	return {"ok":true,"id":id,"file":target,"catalog_backup":catalog_backup,"manifest_backup":manifest_backup,"sha256":inspected.sha256}
