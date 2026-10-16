class_name DnaCore
extends RefCounted
## 美术参数的游戏遗传规则，不是人类遗传学模型，也不是 CK3 内部实现。
## values[trait_id][locus_index] = [父源拷贝, 母源拷贝]。

const Rng = preload("stable_rng.gd")


static func create_founder(character_id: String, seed_text: String,
		schema: Dictionary, template_data: Dictionary) -> Dictionary:
	var templates: Array = template_data["templates"]
	var template_index: int = Rng.index(seed_text, ["founder", character_id, "template"], templates.size())
	var template: Dictionary = templates[template_index]
	var values: Dictionary = {}
	for trait_definition in schema["traits"]:
		var trait_id: String = trait_definition["id"]
		var group: String = trait_definition["sample_group"]
		var center: float = float(template["means"].get(trait_id, 0.5))
		if bool(trait_definition.get("independent_base", false)):
			center = 0.18 + 0.64 * Rng.unit(seed_text, ["founder", character_id, trait_id, "base"])
		center += float(trait_definition["group_strength"]) * Rng.centered(seed_text, ["founder", character_id, "group", group])
		center = clampf(center, 0.08, 0.92)
		var locus_values: Array = []
		for locus in schema["loci"]:
			var copies: Array = []
			for copy_index in range(2):
				var sample_path: Array = ["founder", character_id, trait_id, locus["id"], str(copy_index), "residual"]
				var sampled: float = center + float(trait_definition["founder_noise"]) * Rng.centered(seed_text, sample_path)
				copies.append(clampf(sampled, 0.0, 1.0))
			locus_values.append(copies)
		values[trait_id] = locus_values
	return {
		"schema_version": schema["schema_version"],
		"algorithm_version": schema["algorithm_version"],
		"character_id": character_id,
		"provenance": {"kind": "founder", "seed": seed_text, "template_id": template["id"]},
		"values": values,
	}


static func inherit_child(child_id: String, father_dna: Dictionary,
		mother_dna: Dictionary, seed_text: String, schema: Dictionary) -> Dictionary:
	var errors: Array = validate(father_dna, schema)
	errors.append_array(validate(mother_dna, schema))
	if not errors.is_empty():
		push_error("亲代 DNA 无效: " + str(errors))
		return {}
	if float(schema.get("mutation_probability", 0.0)) != 0.0:
		push_error("此版本仅实现无突变遗传；不可悄悄启用新算法。")
		return {}
	var values: Dictionary = {}
	for trait_definition in schema["traits"]:
		var trait_id: String = trait_definition["id"]
		var child_loci: Array = []
		for locus_index in range(schema["loci"].size()):
			var locus_id: String = schema["loci"][locus_index]["id"]
			var father_index: int = Rng.index(seed_text, ["inheritance", child_id, trait_id, locus_id, "paternal"], 2)
			var mother_index: int = Rng.index(seed_text, ["inheritance", child_id, trait_id, locus_id, "maternal"], 2)
			child_loci.append([
				father_dna["values"][trait_id][locus_index][father_index],
				mother_dna["values"][trait_id][locus_index][mother_index],
			])
		values[trait_id] = child_loci
	return {
		"schema_version": schema["schema_version"],
		"algorithm_version": schema["algorithm_version"],
		"character_id": child_id,
		"provenance": {
			"kind": "child", "seed": seed_text, "father_id": father_dna["character_id"],
			"mother_id": mother_dna["character_id"], "mutation_probability": 0.0,
		},
		"values": values,
	}


static func express(dna: Dictionary, schema: Dictionary) -> Dictionary:
	var errors: Array = validate(dna, schema)
	if not errors.is_empty():
		push_error("DNA 无效，拒绝生成表现值: " + str(errors))
		return {}
	var phenotype: Dictionary = {}
	for trait_definition in schema["traits"]:
		var trait_id: String = trait_definition["id"]
		var result: float = 0.0
		for locus_index in range(schema["loci"].size()):
			var copies: Array = dna["values"][trait_id][locus_index]
			result += float(schema["loci"][locus_index]["weight"]) * (float(copies[0]) + float(copies[1])) * 0.5
		phenotype[trait_id] = clampf(result, 0.0, 1.0)
	return phenotype


static func validate(dna: Dictionary, schema: Dictionary) -> Array:
	var errors: Array = []
	if dna.get("schema_version", "") != schema["schema_version"]:
		errors.append("schema_version 不匹配：需显式迁移，不能重新掷骰。")
	if dna.get("algorithm_version", "") != schema["algorithm_version"]:
		errors.append("algorithm_version 不匹配。")
	if typeof(dna.get("values")) != TYPE_DICTIONARY:
		errors.append("values 必须为对象。")
		return errors
	var values: Dictionary = dna["values"]
	if values.size() != schema["traits"].size():
		errors.append("DNA 特征数量不匹配。")
	for trait_definition in schema["traits"]:
		var trait_id: String = trait_definition["id"]
		if typeof(values.get(trait_id)) != TYPE_ARRAY:
			errors.append(trait_id + " 缺少两位点数组。")
			continue
		var loci: Array = values[trait_id]
		if loci.size() != 2:
			errors.append(trait_id + " 必须恰有两个位点。")
			continue
		for locus in loci:
			if typeof(locus) != TYPE_ARRAY:
				errors.append(trait_id + " 位点必须为数组。")
				continue
			if locus.size() != 2:
				errors.append(trait_id + " 位点必须恰有父源、母源两份拷贝。")
				continue
			for value in locus:
				if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
					errors.append(trait_id + " 拷贝必须为数值。")
				elif not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
					errors.append(trait_id + " 拷贝超出 [0,1]。")
	return errors

