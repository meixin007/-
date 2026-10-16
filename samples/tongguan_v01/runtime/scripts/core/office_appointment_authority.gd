extends RefCounted

const Catalog = preload("res://scripts/domain/tang_office_catalog.gd")
const UNAVAILABLE := ["departed", "exiled", "defected", "irreconcilable", "dead", "executed", "deceased", "missing", "imprisoned", "unreachable"]

# A reference to an office means its current appointed holder. It is not a
# transitive power to appoint every subordinate of that holder.
static func resolve(offices: Dictionary, characters: Dictionary, office_id: String) -> Dictionary:
	var canonical := Catalog.canonical_id(office_id)
	var office: Variant = offices.get(canonical, offices.get(office_id))
	if not office is Dictionary or office.is_empty(): return _fail("职位不存在，无法确定任免权源。")
	var reference: Variant = office.get("authority_ref")
	if not office.has("authority_ref"):
		# Only the existing catalog has the old imperial appointment default.
		if Catalog.get_office_definition(canonical).is_empty(): return _fail("职位未配置任免权源。")
		reference = {"entity_kind": "office_holder", "entity_id": "imperial_court"}
	var valid := validate_reference(offices, characters, canonical, reference)
	if not valid.ok: return valid
	var holder: String = reference.entity_id
	if reference.entity_kind == "office_holder":
		var parent: Dictionary = offices[reference.entity_id]
		holder = str(parent.get("holder_id", ""))
		if parent.get("status") != "appointed" or holder.is_empty(): return _fail("任命权源职位当前空缺，须由有权任命者处理。")
	if not characters.get(holder) is Dictionary or characters[holder].get("status") in UNAVAILABLE:
		return _fail("任命权源人物不存在或已无法履职。")
	return {"ok": true, "authority_ref": reference.duplicate(true), "authority_holder_id": holder}

static func validate_reference(offices: Dictionary, characters: Dictionary, office_id: String, reference: Variant) -> Dictionary:
	if not reference is Dictionary or reference.size() != 2 or reference.get("entity_kind") not in ["character", "office_holder"] or not reference.get("entity_id") is String or str(reference.entity_id).is_empty():
		return _fail("职位任免权源格式无效。")
	if reference.entity_kind == "character":
		if not characters.get(reference.entity_id) is Dictionary: return _fail("任免权源指向不存在的人物。")
	else:
		if Catalog.canonical_id(reference.entity_id) != reference.entity_id or not offices.get(reference.entity_id) is Dictionary or Catalog.canonical_id(office_id) == reference.entity_id:
			return _fail("任免权源必须指向另一个实际职位的规范标识。")
	return {"ok": true}

static func validate(offices: Dictionary, characters: Dictionary) -> Dictionary:
	for id in offices:
		var office: Variant = offices[id]
		if not office is Dictionary: return _fail("职位记录无效。")
		if office.get("office_kind") == "family": continue
		if office.get("office_kind") == "regional" and (not office.has("authority_ref") or not office.get("organization_id") is String or str(office.organization_id).is_empty()):
			return _fail("地方职位缺少所属组织或明确任免权源。")
		if office.has("authority_ref"):
			var valid := validate_reference(offices, characters, str(id), office.authority_ref)
			if not valid.ok: return valid
		var canonical := Catalog.canonical_id(str(id))
		if canonical != id and offices.has(canonical):
			if not offices[canonical] is Dictionary or office.get("authority_ref") != offices[canonical].get("authority_ref"):
				return _fail("职位别名与实际职位的任免权源不一致。")
	return preload("res://scripts/core/central_office_rules.gd").validate_offices(offices, characters)

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "office_authority_required", "error": message, "message": message}
