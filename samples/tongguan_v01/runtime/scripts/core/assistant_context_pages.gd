extends RefCounted

const Canonical = preload("res://scripts/core/canonical_json.gd")
const PAGE_SIZE := 8
const TEXT_SIZE := 1024
const TRANSIENT := ["context_paging", "context_page", "planning_continuation"]

static func _source(visible: Dictionary) -> Dictionary:
	var source := visible.duplicate(true)
	for field in TRANSIENT: source.erase(field)
	return source

static func project(visible: Dictionary, compact: bool = false) -> Dictionary:
	var source := _source(visible)
	var result: Dictionary = _preview(source, []) if compact else source.duplicate(true)
	result["context_paging"] = {"snapshot_hash": Canonical.hash_value(source).get("hash", ""), "array_page_size": PAGE_SIZE, "text_page_size": TEXT_SIZE}
	for field in ["context_page", "planning_continuation"]:
		if visible.has(field): result[field] = visible[field].duplicate(true)
	return result

static func _preview(value: Variant, path: Array) -> Variant:
	if value is Array:
		var items: Array = []
		for index in mini(value.size(), PAGE_SIZE): items.append(_preview(value[index], path + [index]))
		return {"page_ref": {"path": path, "total_count": value.size(), "next_offset": PAGE_SIZE}, "preview": items} if value.size() > PAGE_SIZE else items
	if value is Dictionary:
		var result := {}
		for field in value: result[field] = _preview(value[field], path + [field])
		return result
	if value is String and value.length() > TEXT_SIZE:
		return {"page_ref": {"path": path, "total_count": value.length(), "next_offset": TEXT_SIZE}, "text_preview": value.left(TEXT_SIZE)}
	return value

static func parse_request(value: Variant) -> Dictionary:
	var fields := ["schema_version", "kind", "snapshot_hash", "path", "offset"]
	if not value is Dictionary or value.size() != fields.size() + (1 if value.has("notes") else 0): return _fail("读取上下文字段不完整")
	for field in fields:
		if not value.has(field): return _fail("读取上下文缺少 " + field)
	if value.schema_version != 2 or value.kind != "context_request" or not value.snapshot_hash is String or value.snapshot_hash.length() != 64 or not value.path is Array or value.path.is_empty() or value.path.size() > 12 or not preload("res://scripts/core/management_state_contract.gd").amount(value.offset): return _fail("上下文页位置或快照无效")
	for element in value.path:
		if element is String:
			if element.is_empty() or element.length() > 256: return _fail("上下文路径无效")
		elif not preload("res://scripts/core/management_state_contract.gd").amount(element): return _fail("上下文数组位置无效")
	if value.has("notes") and (not value.notes is String or value.notes.length() > 2048): return _fail("临时阅读笔记须为有限文字")
	return {"ok": true, "context_request": value.duplicate(true)}

static func read(visible: Dictionary, request: Variant) -> Dictionary:
	var parsed := parse_request(request)
	if not parsed.ok: return parsed
	var source := _source(visible)
	if visible.get("projection_kind") != "assistant_player_visible_v1" or Canonical.hash_value(source).get("hash", "") != request.snapshot_hash: return _fail("上下文快照已变化，不能混用旧页")
	var value: Variant = source
	for element in request.path:
		if value is Dictionary and element is String and value.has(element): value = value[element]
		elif value is Array and not element is String and int(element) < value.size(): value = value[int(element)]
		else: return _fail("请求不在本次允许的可见上下文内")
	var offset := int(request.offset)
	var page := {"snapshot_hash": request.snapshot_hash, "path": request.path.duplicate(), "offset": offset, "next_offset": null}
	if request.has("notes"): page["model_notes_not_world_facts"] = request.notes
	if value is Array:
		if offset >= value.size(): return _fail("上下文页超出已有记录")
		var end := mini(offset + PAGE_SIZE, value.size())
		page["total_count"] = value.size(); page["values"] = []
		for index in range(offset, end): page["values"].append(_preview(value[index], request.path + [index]))
		if end < value.size(): page.next_offset = end
	elif value is String:
		if offset >= value.length(): return _fail("上下文页超出已有文字")
		page["total_count"] = value.length(); page["text"] = value.substr(offset, TEXT_SIZE)
		if offset + TEXT_SIZE < value.length(): page.next_offset = offset + TEXT_SIZE
	else: return _fail("只可分页读取已展示的记录集合或文字")
	return {"ok": true, "page": page}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "failure_kind": "invalid_result"}
