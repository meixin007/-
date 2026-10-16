extends RefCounted
## Boundary validation around the unchanged legacy inheritance algorithm.
const Dna = preload("dna_core.gd")

static func validate(character: Dictionary, schema: Dictionary) -> Array:
    var errors: Array = []
    if not schema.get("traits") is Array or not schema.get("loci") is Array or not schema.has("schema_version") or not schema.has("algorithm_version"):
        return ["缺少有效的遗传 schema。"]
    if not character.get("dna") is Dictionary:
        return ["角色缺少有效 dna 对象。"]
    var dna: Dictionary = character["dna"]
    errors.append_array(Dna.validate(dna, schema))
    var id: String = str(character.get("id", ""))
    var dna_id: String = str(dna.get("character_id", ""))
    if id.is_empty() or dna_id.is_empty() or id != dna_id:
        errors.append("角色 id 与 dna.character_id 必须非空且一致。")
    if not dna.get("provenance") is Dictionary:
        errors.append("DNA 缺少亲缘来源记录。")
    else:
        var provenance: Dictionary = dna["provenance"]
        var kind: String = str(provenance.get("kind", ""))
        if kind not in ["founder", "child"]:
            errors.append("DNA 来源必须为 founder 或 child。")
        if kind == "child":
            var father: String = str(provenance.get("father_id", ""))
            var mother: String = str(provenance.get("mother_id", ""))
            if father.is_empty() or mother.is_empty() or father == mother or id in [father, mother]:
                errors.append("子代必须有不同的有效双亲 ID，且不能指向自身。")
    for key in ["appearance_state", "style", "social"]:
        if not character.get(key, {}) is Dictionary:
            errors.append(key + " 必须为对象。")
    if character.get("appearance_state", {}) is Dictionary:
        var state: Dictionary = character.get("appearance_state", {})
        for key in ["age_years", "weight_delta", "fatigue", "sun_exposure", "hair_grey_fraction"]:
            if not state.has(key) and key != "age_years":
                continue
            var value: Variant = state.get(key)
            if not (value is float or value is int) or not is_finite(float(value)):
                errors.append(key + " 必须为有限数值。")
            elif key == "age_years" and float(value) < 0.0:
                errors.append("年龄不能为负数。")
    return errors

static func inherit_child(child_id: String, father: Dictionary, mother: Dictionary, seed_text: String, schema: Dictionary) -> Dictionary:
    var errors: Array = validate(father, schema)
    errors.append_array(validate(mother, schema))
    if child_id.is_empty() or child_id in [str(father.get("id", "")), str(mother.get("id", ""))] or father.get("id") == mother.get("id"):
        errors.append("子代与双亲必须使用不同的非空人物 ID。")
    if not errors.is_empty():
        return {"ok":false,"errors":errors}
    var dna: Dictionary = Dna.inherit_child(child_id, father["dna"], mother["dna"], seed_text, schema)
    return {"ok":not dna.is_empty(),"dna":dna,"errors":[] if not dna.is_empty() else ["遗传核心拒绝生成后代。"]}
