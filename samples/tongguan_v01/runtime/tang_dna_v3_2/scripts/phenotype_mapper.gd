class_name TangPhenotypeMapper
extends RefCounted
## V3.2: derive 36 normalized render controls from the LEGACY 24-trait_definition genome.
## Nothing in this file mutates the inherited 96 allele values. These mappings are
## art heuristics, not additional independent genes or a model of human genetics.

const Dna = preload("res://tang_dna_v3_2/scripts/dna_core.gd")
const Contract = preload("character_contract.gd")
const CONTROL_KEYS: Dictionary = {
    "bone":["face_length","face_width","temple_width","cheekbone_width","jaw_width","chin_length","forehead_height","jaw_roundness"],
    "eyes":["eye_length","eye_openness","eye_tilt","eye_spacing","upper_lid_cover","inner_canthus_shape","outer_canthus_shape","lid_fold_strength"],
    "brows":["brow_length","brow_thickness","brow_peak_position","brow_tail_angle","brow_eye_distance"],
    "nose":["nose_length","bridge_width","bridge_depth","nostril_width","tip_width","tip_droop"],
    "mouth":["mouth_width","upper_lip_fullness","lower_lip_fullness","cupid_bow","philtrum_length","resting_corner_angle"],
    "asymmetry":["eye_pair_delta","brow_pair_delta","mouth_pair_delta"]
}


static func build(character: Dictionary, schema: Dictionary,
        mapping: Dictionary, bone_presets: Dictionary) -> Dictionary:
    var family: String = str(character.get("portrait_family", ""))
    if family != "male" and family != "female":
        return {"ok": false, "errors": ["portrait_family 必须显式指定 male/female；不可从服饰、名字或 DNA 推断。"]}
    var errors: Array = Contract.validate(character, schema)
    if not errors.is_empty():
        return {"ok": false, "errors": errors}
    var dna: Dictionary = character["dna"]
    if str(mapping.get("legacy_schema_version", "")) != str(schema.get("schema_version", "")):
        return {"ok": false, "errors": ["表现映射所需的旧DNA版本不匹配。"]}
    if str(mapping.get("legacy_algorithm_version", "")) != str(schema.get("algorithm_version", "")):
        return {"ok": false, "errors": ["表现映射所需的遗传算法版本不匹配。"]}
    if not mapping.get("controls") is Dictionary:
        return {"ok": false, "errors": ["表现映射缺少控制参数。"]}
    for group_name in ["bone", "eyes", "brows", "nose", "mouth", "asymmetry"]:
        if not mapping["controls"].get(group_name) is Dictionary or mapping["controls"][group_name].is_empty():
            return {"ok": false, "errors": ["表现映射缺少参数组: " + group_name]}
    var raw: Dictionary = Dna.express(dna, schema)
    var mapping_errors: Array = _validate_mapping(mapping, raw)
    if not mapping_errors.is_empty():
        return {"ok":false,"errors":mapping_errors}
    var groups: Dictionary = {}
    for group_name in mapping.get("controls", {}):
        var group: Dictionary = {}
        for key in mapping["controls"][group_name]:
            group[key] = clampf(_evaluate(mapping["controls"][group_name][key], raw), 0.0, 1.0)
        groups[group_name] = group
    var selected_bone: String = _nearest_bone(groups["bone"], family, bone_presets)
    if selected_bone.is_empty():
        return {"ok": false, "errors": ["没有对应资源族的正面骨相参数母型。"]}
    return {
        "ok": true,
        "asset_family": family,
        "view": "front",
        "phenotype_version": str(mapping["version"]),
        "raw_legacy_phenotype": raw,
        "controls": groups,
        "face_template_id": selected_bone,
        "mouth_geometry_parameters": mouth_geometry_parameters(groups),
    }


static func _validate_mapping(mapping: Dictionary, raw: Dictionary) -> Array:
    var errors: Array = []
    if str(mapping.get("version", "")).is_empty():
        errors.append("表现映射缺少版本。")
    for group_name in CONTROL_KEYS:
        for key in CONTROL_KEYS[group_name]:
            var rule: Variant = mapping["controls"][group_name].get(key)
            if not rule is Dictionary:
                errors.append("缺少控制规则: " + group_name + "." + key)
                continue
            if rule.has("source") or rule.has("invert"):
                if not raw.has(rule.get("source", rule.get("invert"))):
                    errors.append("控制规则引用未知遗传特征: " + key)
            elif rule.get("mix") is Dictionary and not rule["mix"].is_empty():
                var total: float = 0.0
                for source in rule["mix"]:
                    var weight: Variant = rule["mix"][source]
                    if not raw.has(source) or not (weight is float or weight is int):
                        errors.append("混合规则来源或权重无效: " + key)
                    elif not is_finite(float(weight)) or float(weight) < 0.0:
                        errors.append("混合权重必须是非负有限数值: " + key)
                    else:
                        total += float(weight)
                if total <= 0.0:
                    errors.append("混合权重和必须大于零: " + key)
            else:
                errors.append("无法识别的控制规则: " + key)
    return errors


static func _evaluate(rule: Dictionary, raw: Dictionary) -> float:
    if rule.has("source"):
        return float(raw[rule["source"]])
    if rule.has("invert"):
        return 1.0 - float(raw[rule["invert"]])
    var total: float = 0.0
    var weight_sum: float = 0.0
    for trait_id in rule.get("mix", {}):
        var weight: float = float(rule["mix"][trait_id])
        total += weight * float(raw[trait_id])
        weight_sum += weight
    if weight_sum <= 0.0:
        return 0.5
    return total / weight_sum


static func _nearest_bone(control: Dictionary, family: String, presets: Dictionary) -> String:
    var closest: String = ""
    var best: float = INF
    for entry in presets.get("presets", []):
        if str(entry.get("asset_family", "")) != family:
            continue
        if str(entry.get("view", "")) != "front":
            continue
        var cost: float = 0.0
        for dimension in entry["geometry_seed"]:
            if not control.has(dimension):
                continue
            var difference: float = float(control[dimension]) - float(entry["geometry_seed"][dimension])
            cost += difference * difference
        if cost < best:
            best = cost
            closest = str(entry["id"])
    return closest


static func mouth_geometry_parameters(groups: Dictionary) -> Dictionary:
    var mouth: Dictionary = groups["mouth"]
    var asym: Dictionary = groups["asymmetry"]
    var delta: float = 2.0 * float(asym["mouth_pair_delta"]) - 1.0
    var c: float = float(mouth["cupid_bow"])
    return {
        "width": lerpf(0.5, 1.8, float(mouth["mouth_width"])),
        "upper": lerpf(0.2, 2.2, float(mouth["upper_lip_fullness"])),
        "lower": lerpf(0.2, 2.2, float(mouth["lower_lip_fullness"])),
        "cupid": c,
        "tilt_deg": 7.0 * delta,
        "peak_shift": 0.1 * delta,
        "upper_bias": 0.24 * delta,
        "lower_bias": -0.2 * delta,
        "seam_bow": lerpf(-2.0, 2.0, float(mouth["resting_corner_angle"])),
        "seam_skew": 2.5 * delta,
        "upper_shoulder": lerpf(0.38, 0.90, 1.0 - c),
        "lower_boxiness": lerpf(0.05, 0.85, 1.0 - c),
    }


static func closest_mouth_shape(parameters: Dictionary, preset_data: Dictionary) -> String:
    var best: float = INF
    var chosen: String = ""
    for item in preset_data.get("mouth", {}).get("female", []):
        var src: Dictionary = item["parameters"]
        var cost: float = 0.0
        for key in ["width", "upper", "lower", "cupid", "tilt_deg"]:
            var delta: float = float(parameters[key]) - float(src[key])
            if key == "tilt_deg":
                delta /= 12.0
            cost += delta * delta
        if cost < best:
            best = cost
            chosen = str(item["id"])
    return chosen
