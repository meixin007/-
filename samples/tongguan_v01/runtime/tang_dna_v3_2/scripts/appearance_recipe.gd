class_name AppearanceRecipe
extends RefCounted
## V3.2: separate face, eyes, brows, nose, mouth, ears, apparel requests.
## Data-only recipe; full portraits still require completed art for all mandatory layers.

const Dna = preload("res://tang_dna_v3_2/scripts/dna_core.gd")
const Outfit = preload("res://tang_dna_v3_2/scripts/outfit_resolver.gd")
const Mapper = preload("res://tang_dna_v3_2/scripts/phenotype_mapper.gd")
const Scorer = preload("res://tang_dna_v3_2/scripts/appearance_scorer.gd")
const DataIo = preload("res://tang_dna_v3_2/scripts/data_io.gd")
const Contract = preload("character_contract.gd")


static func build(character: Dictionary, context: Dictionary, schema: Dictionary,
        profile: Dictionary, catalog: Dictionary) -> Dictionary:
    var errors: Array = Contract.validate(character, schema)
    if not errors.is_empty():
        return {"ok": false, "errors": errors}
    var dna: Dictionary = character["dna"]
    if not catalog.get("rigs") is Dictionary or not catalog.get("assets") is Dictionary or not catalog.get("layer_order") is Array:
        return {"ok": false, "errors": ["资源目录缺少 rigs / assets / layer_order。"]}
    var family: String = str(character.get("portrait_family", ""))
    if family != "male" and family != "female":
        return {"ok": false, "errors": ["缺少有效portrait_family；旧档需显式迁移，不能从身份或DNA猜测。"]}
    var state: Dictionary = character.get("appearance_state", {})
    var style: Dictionary = character.get("style", {})
    var age_value: Variant = state.get("age_years")
    if typeof(age_value) != TYPE_INT and typeof(age_value) != TYPE_FLOAT:
        return {"ok": false, "errors": ["appearance_state.age_years 缺失或非法。"]}
    if not is_finite(float(age_value)) or float(age_value) < 0.0:
        return {"ok": false, "errors": ["appearance_state.age_years 必须为有限非负数。"]}
    var is_child: bool = float(age_value) < float(schema["adult_rig_min_age"])
    var age_class: String = "child" if is_child else "adult"
    var rig_id: String = "tang_portrait_" + age_class + "_" + family + "_v3"
    var rig_known: bool = catalog["rigs"].has(rig_id)
    var mapping: Dictionary = DataIo.read_cached_dictionary("res://tang_dna_v3_2/data/phenotype_mapping_v3_2.json")
    var bones: Dictionary = DataIo.read_cached_dictionary("res://tang_dna_v3_2/data/bone_presets_v3_2.json")
    var feature_presets: Dictionary = DataIo.read_cached_dictionary("res://tang_dna_v3_2/data/feature_presets_v3_2.json")
    if mapping.is_empty() or bones.is_empty() or feature_presets.is_empty():
        return {"ok": false, "errors": ["缺少V3.2外貌参数定义。"]}
    var phenotype: Dictionary = Mapper.build(character, schema, mapping, bones)
    if not phenotype.get("ok", false):
        return phenotype
    var outfit: Dictionary = Outfit.resolve(character, context, profile, catalog)
    if not outfit.get("ok", false):
        return {"ok": false, "errors": ["服饰profile年份不匹配。"], "outfit": outfit}
    var original: Dictionary = phenotype["raw_legacy_phenotype"]
    var render_parameters: Dictionary = {}
    for trait_definition in schema["traits"]:
        var render: Dictionary = trait_definition["render"]
        var value: float = float(original[trait_definition["id"]])
        render_parameters[trait_definition["id"]] = {"target": render["target"], "kind": render["kind"], "value": clampf(lerpf(float(render["min"]), float(render["max"]), value), float(render["min"]), float(render["max"]))}
    var requests: Array = []
    if is_child:
        requests.append({"slot": "body_base", "asset_id": "body_child_base"})
        requests.append({"slot": "head", "asset_id": "head_child_base"})
        for slot in ["ears", "eyes", "brows", "nose", "mouth"]:
            requests.append({"slot": slot, "asset_id": family + "_child_" + slot})
    else:
        requests.append({"slot": "body_base", "asset_id": "body_adult_base"})
        requests.append({"slot": "head", "asset_id": "head_adult_base"})
        for slot in ["ears", "eyes", "brows", "nose", "mouth"]:
            var aid: String = family + "_" + slot + "_neutral"
            if slot == "mouth" and family == "female":
                var nearest: String = Mapper.closest_mouth_shape(phenotype["mouth_geometry_parameters"], feature_presets)
                if not nearest.is_empty():
                    aid = "female_mouth_" + nearest
            requests.append({"slot": slot, "asset_id": aid})
    requests.append_array(outfit["requests"])
    if not str(style.get("hair_asset_id", "")).is_empty():
        requests.append({"slot": "hair_front", "asset_id": str(style["hair_asset_id"])})
    if not str(style.get("beard_asset_id", "")).is_empty():
        requests.append({"slot": "beard", "asset_id": str(style["beard_asset_id"])})
    var layers: Array = []
    var hide_tags: Array = []
    var missing: Array = []
    for request in requests:
        if not catalog["layer_order"].has(request["slot"]):
            missing.append({"slot": request["slot"], "requested_asset_id": request["asset_id"], "reason": "slot_not_in_layer_order"})
    for slot in catalog["layer_order"]:
        for request in requests:
            if str(request["slot"]) != str(slot):
                continue
            var asset_id: String = _family_asset_id(str(request["asset_id"]), family, catalog)
            var resolution: Dictionary = _resolve_asset(asset_id, str(slot), family, rig_id, str(profile["profile_id"]), str(outfit["occasion"]), catalog)
            resolution["original_request"] = request["asset_id"]
            resolution["asset_family"] = family
            resolution["face_template_id"] = phenotype["face_template_id"] if slot == "head" else ""
            if slot == "head":
                resolution["geometry_parameters"] = phenotype["controls"]["bone"]
            if phenotype["controls"].has(str(slot)):
                resolution["geometry_parameters"] = phenotype["controls"][str(slot)]
            if slot == "mouth":
                resolution["geometry_parameters"] = phenotype["mouth_geometry_parameters"]
            resolution["asymmetry_parameters"] = phenotype["controls"]["asymmetry"]
            layers.append(resolution)
            for tag in resolution.get("hide_tags", []):
                if not hide_tags.has(tag):
                    hide_tags.append(tag)
            if resolution["status"] != "ready":
                missing.append({"slot": slot, "requested_asset_id": request["asset_id"], "reason": resolution["status"]})
    return {
        "ok": true,
        "recipe_version": "tang-portrait-recipe-3.2.0",
        "dna_schema_version": dna["schema_version"],
        "dna_algorithm_version": dna["algorithm_version"],
        "phenotype_mapping_version": phenotype["phenotype_version"],
        "character_id": character["id"],
        "dna_fingerprint": JSON.stringify(dna["values"], "", true, true).sha256_text(),
        "asset_family": family, "view": "front", "rig_id": rig_id,
        "rig_contract_available": rig_known, "needs_child_rig": is_child and not rig_known,
        "face_template_id": phenotype["face_template_id"],
        "phenotype": phenotype["raw_legacy_phenotype"],
        "face_controls": phenotype["controls"],
        "render_parameters": render_parameters,
        "appearance_score_test": Scorer.evaluate(phenotype["controls"]),
        "appearance_state": state.duplicate(true), "style": style.duplicate(true),
        "outfit": outfit, "layers": layers, "hide_tags": hide_tags,
        "missing_assets": missing, "can_render": rig_known and missing.is_empty(),
        "can_preview": not is_child,
        "preview_kind": "procedural_technical_adult",
        "note": "Mouth shape preview is geometry-ready; complete portraits remain unavailable until all required texture layers exist.",
    }


static func _family_asset_id(asset_id: String, family: String, catalog: Dictionary) -> String:
    var by_family: Dictionary = catalog.get("family_variants", {}).get(asset_id, {})
    if by_family.has(family):
        return str(by_family[family])
    # Explicitly reject a missing variant instead of loading the other family's art.
    if not by_family.is_empty():
        return "__family_unavailable__" + asset_id
    return asset_id


static func _resolve_asset(requested: String, slot: String, family: String, rig_id: String,
        era: String, occasion: String, catalog: Dictionary) -> Dictionary:
    if requested.begins_with("__family_unavailable__"):
        return _missing_result(requested, slot, "family_not_supported", [])
    var current: String = requested
    var seen: Array = []
    var evidence: Array = []
    var last_status: String = "unknown_asset"
    while not current.is_empty() and not seen.has(current):
        seen.append(current)
        var asset: Dictionary = catalog["assets"].get(current, {})
        if asset.is_empty():
            last_status = "unknown_asset"
            evidence.append({"asset_id": current, "reason": last_status})
            break
        if str(asset.get("asset_family", "")) != family:
            last_status = "family_mismatch"
        elif str(asset.get("slot", "")) != slot:
            last_status = "slot_mismatch"
        elif str(asset.get("rig_id", "")) != rig_id:
            last_status = "rig_mismatch"
        elif str(asset.get("view", "")) != "front":
            last_status = "view_mismatch"
        elif not asset.get("era", []).has(era):
            last_status = "era_mismatch"
        elif not asset.get("allowed_occasions", []).is_empty() and not asset["allowed_occasions"].has(occasion):
            last_status = "occasion_mismatch"
        elif str(asset.get("status", "")) == "rejected_fixture":
            last_status = "rejected_fixture"
        elif str(asset.get("resource_path", "")).is_empty() or not ResourceLoader.exists(str(asset["resource_path"])):
            last_status = "missing_art"
        else:
            return {
                "slot": slot, "requested_asset_id": requested, "selected_asset_id": current,
                "status": "ready", "fallback_chain": seen,
                "fallback_evidence": evidence,
                "anchors": asset.get("anchors", {}), "hide_tags": asset.get("hide_tags", []),
                "resource_path": asset["resource_path"],
                "geometry_resource": asset.get("geometry_resource", ""),
                "render_mode": asset.get("render_mode", "texture"),
                "texture_layers": asset.get("texture_layers", []),
                "shape_id": asset.get("shape_id", ""),
                "compatibility": asset.get("compatibility", {}),
                "tags": asset.get("tags", []),
                "tint_mode": asset.get("tint_mode", "none"),
            }
        evidence.append({"asset_id": current, "reason": last_status})
        var fallback: String = str(asset.get("fallback", ""))
        # No cross-family fallback is allowed. Nor may a child rig use an adult asset.
        if not fallback.is_empty():
            var candidate: Dictionary = catalog["assets"].get(fallback, {})
            if str(candidate.get("asset_family", "")) != family or str(candidate.get("rig_id", "")) != rig_id:
                last_status = "fallback_family_or_rig_mismatch"
                break
        current = fallback
    if seen.has(current) and not current.is_empty() and evidence.size() > 0:
        evidence.append({"asset_id": current, "reason": "fallback_cycle"})
    return _missing_result(requested, slot, last_status, seen, evidence)


static func _missing_result(requested: String, slot: String, reason: String,
        seen: Array, evidence: Array = []) -> Dictionary:
    return {
        "slot": slot, "requested_asset_id": requested, "selected_asset_id": null,
        "status": reason, "fallback_chain": seen, "fallback_evidence": evidence,
        "anchors": {}, "hide_tags": [], "resource_path": "",
        "geometry_resource": "", "render_mode": "none", "texture_layers": [],
        "shape_id": "", "compatibility": {},
    }
