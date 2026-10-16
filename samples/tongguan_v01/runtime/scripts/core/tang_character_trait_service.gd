extends RefCounted

class_name TangCharacterTraitService

const CharacterKnowledgeServiceScript = preload("res://scripts/core/character_knowledge_service.gd")
const TangClanServiceScript = preload("res://scripts/core/tang_clan_service.gd")
const TANG_TRAITS_PATH := "res://data/scenarios/anshi_rebellion/tang_traits_definition.json"

var _traits_data: Dictionary = {}
var _categories_data: Dictionary = {}

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	if not FileAccess.file_exists(TANG_TRAITS_PATH):
		return
	var file := FileAccess.open(TANG_TRAITS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		_traits_data = json.data.get("traits", {})
		_categories_data = json.data.get("categories", {})

func get_all_traits() -> Dictionary:
	if _traits_data.is_empty():
		_load_definitions()
	return _traits_data

func get_all_categories() -> Dictionary:
	if _categories_data.is_empty():
		_load_definitions()
	return _categories_data

func get_trait_definition(trait_id: String) -> Dictionary:
	if _traits_data.is_empty():
		_load_definitions()
	return _traits_data.get(trait_id, {})

## 获取角色完整多类别特性档案（含分类组装与明暗状态）
func get_categorized_trait_profile(state, data: Dictionary, character_id: String) -> Dictionary:
	var knowledge_service = CharacterKnowledgeServiceScript.new()
	var char_data := _find_char_data(data, character_id)

	# 1. 搜集基础明暗特质
	var configured_public: Array = char_data.get("tang_traits", []).duplicate(true)
	var configured_hidden: Array = char_data.get("hidden_traits", []).duplicate(true)
	var configured_suspected: Array = char_data.get("suspected_traits", []).duplicate(true)

	# 叠加动态赋予的特性 (例如崩溃习得)
	var custom_traits: Dictionary = {}
	if state != null and state.get("flags") is Dictionary and state.flags.get("custom_character_traits") is Dictionary:
		custom_traits = state.flags.get("custom_character_traits", {}).get(character_id, {})
	for dyn_trait in custom_traits.get("added_public", []):
		if not configured_public.has(dyn_trait):
			configured_public.append(dyn_trait)
	for dyn_hidden in custom_traits.get("added_hidden", []):
		if not configured_hidden.has(dyn_hidden):
			configured_hidden.append(dyn_hidden)
	for dyn_removed in custom_traits.get("removed", []):
		configured_public.erase(dyn_removed)
		configured_hidden.erase(dyn_removed)

	# 2. 查询知识库已确凿勘破的 claim
	var confirmed_unmasked: Array = []
	if state != null:
		var trait_field: Dictionary = knowledge_service.get_visible_field(state, character_id, "traits")
		if str(trait_field.get("status", "")) == "confirmed":
			var val = trait_field.get("value", [])
			if val is Array:
				for item in val:
					confirmed_unmasked.append(str(item))
			elif typeof(val) == TYPE_STRING:
				confirmed_unmasked.append(str(val))

	# 3. 构建五类分类结果
	var by_category: Dictionary = {
		"personality": [],
		"education_origin": [],
		"physical_health": [],
		"fame_lifestyle": [],
		"stress_coping": []
	}

	var public_traits: Array = []
	var exposed_traits: Array = []
	var suspected_traits: Array = []
	var hidden_count := 0

	for tid in configured_public:
		var def := get_trait_definition(str(tid))
		if def.is_empty():
			continue
		var entry := def.duplicate(true)
		entry["visibility_status"] = "public"
		public_traits.append(entry)
		var cat := str(def.get("category", "personality"))
		if by_category.has(cat):
			by_category[cat].append(entry)

	for tid in configured_hidden:
		var def := get_trait_definition(str(tid))
		if def.is_empty():
			continue
		if confirmed_unmasked.has(str(tid)):
			var exp_entry := def.duplicate(true)
			exp_entry["visibility_status"] = "exposed"
			exposed_traits.append(exp_entry)
			var cat := str(def.get("category", "personality"))
			if by_category.has(cat):
				by_category[cat].append(exp_entry)
		else:
			hidden_count += 1

	for tid in configured_suspected:
		var def := get_trait_definition(str(tid))
		if not def.is_empty():
			var susp_entry := def.duplicate(true)
			susp_entry["visibility_status"] = "suspected"
			suspected_traits.append(susp_entry)

	return {
		"character_id": character_id,
		"public_traits": public_traits,
		"exposed_traits": exposed_traits,
		"suspected_traits": suspected_traits,
		"hidden_count": hidden_count,
		"by_category": by_category
	}

## 保持向后兼容的简明档案入口
func get_character_trait_profile(state, data: Dictionary, character_id: String) -> Dictionary:
	return get_categorized_trait_profile(state, data, character_id)

## 计算 AI 处事风格七维向量 (-100 ~ 100) 与处事标签
func calculate_ai_personality(character_id: String, state, data: Dictionary) -> Dictionary:
	var profile := get_categorized_trait_profile(state, data, character_id)
	var active_traits: Array = []
	active_traits.append_array(profile.get("public_traits", []))
	active_traits.append_array(profile.get("exposed_traits", []))

	var vectors := {
		"boldness": 0,
		"compassion": 0,
		"greed": 0,
		"honor": 0,
		"rationality": 0,
		"vengefulness": 0,
		"zeal": 0
	}

	for trait_entry in active_traits:
		var t_dict: Dictionary = trait_entry as Dictionary
		var ai_mods: Dictionary = t_dict.get("ai_modifiers", {})
		for key in vectors.keys():
			vectors[key] = clampi(int(vectors[key]) + int(ai_mods.get(key, 0)), -100, 100)

	# 依据极值生成处事总评标签
	var archetype := _derive_archetype_label(vectors)

	return {
		"character_id": character_id,
		"vectors": vectors,
		"archetype_name": archetype.get("name", "沉稳持中"),
		"archetype_desc": archetype.get("desc", "行事中规中矩，无极端倾向。")
	}

func _derive_archetype_label(vectors: Dictionary) -> Dictionary:
	var b: int = int(vectors.get("boldness", 0))
	var c: int = int(vectors.get("compassion", 0))
	var g: int = int(vectors.get("greed", 0))
	var h: int = int(vectors.get("honor", 0))
	var r: int = int(vectors.get("rationality", 0))
	var v: int = int(vectors.get("vengefulness", 0))
	var z: int = int(vectors.get("zeal", 0))

	if h >= 50 and b >= 30:
		return {"name": "刚烈孤忠之臣", "desc": "风骨凛然，敢于犯颜直谏，视社稷重于身家。"}
	if h >= 50 and c >= 25:
		return {"name": "仁善忠厚长者", "desc": "温良恭俭，体恤士庶，恪尽人臣本分。"}
	if g >= 50 and h <= -30:
		return {"name": "弄权贪墨奸佞", "desc": "唯利是图，擅弄权柄，视纲纪如草芥。"}
	if b >= 40 and h <= -20:
		return {"name": "跋扈自雄悍将", "desc": "恃武骄横，桀骜不驯，极难驾驭。"}
	if r >= 50 and h >= 20:
		return {"name": "老成明察谋士", "desc": "深谋远虑，精于算度，处事稳妥严谨。"}
	if z >= 50 and g <= -40:
		return {"name": "清修玄道高士", "desc": "澹泊名利，潜心至道，超然朝野之外。"}
	if b <= -30 and r <= -20:
		return {"name": "惊疑多惧庸才", "desc": "优柔寡断，遇危则乱，易生猜忌之心。"}
	return {"name": "持重沉稳之臣", "desc": "恪守官箴，循序渐进，无突出偏执。"}

## 计算两人相互好恶打分与数学渊源明细
func calculate_mutual_opinion(char_a_id: String, char_b_id: String, state, data: Dictionary) -> Dictionary:
	var prof_a := get_categorized_trait_profile(state, data, char_a_id)
	var prof_b := get_categorized_trait_profile(state, data, char_b_id)

	var traits_a: Array = []
	for t in prof_a.get("public_traits", []): traits_a.append(str(t.get("id", "")))
	for t in prof_a.get("exposed_traits", []): traits_a.append(str(t.get("id", "")))

	var traits_b: Array = []
	for t in prof_b.get("public_traits", []): traits_b.append(str(t.get("id", "")))
	for t in prof_b.get("exposed_traits", []): traits_b.append(str(t.get("id", "")))

	var total_score := 0
	var reasons: Array[Dictionary] = []

	# 1. 基础关系（来自 characters.json 中的配置）
	var char_a := _find_char_data(data, char_a_id)
	var rels: Dictionary = char_a.get("relationships", {})
	var base_rel := int(rels.get(char_b_id, 0))
	if base_rel != 0:
		total_score += base_rel
		reasons.append({
			"label": "宿世私谊与过往纠葛",
			"delta": base_rel
		})

	# 2. 特性好恶相生相克匹配
	for tid_a in traits_a:
		var def_a := get_trait_definition(tid_a)
		var op_mods: Dictionary = def_a.get("opinion_modifiers", {})
		for tid_b in traits_b:
			if op_mods.has(tid_b):
				var delta := int(op_mods[tid_b])
				total_score += delta
				var def_b := get_trait_definition(tid_b)
				var label_prefix := "同气相求: " if delta > 0 else "冰炭不洽: "
				reasons.append({
					"label": label_prefix + str(def_a.get("name", tid_a)) + " 遇 " + str(def_b.get("name", tid_b)),
					"delta": delta
				})

		# 检查全局声望特质加成 (如 all)
		if op_mods.has("all"):
			var global_delta := int(op_mods["all"])
			total_score += global_delta
			reasons.append({
				"label": "令名感召: " + str(def_a.get("name", tid_a)),
				"delta": global_delta
			})

	# 3. 宗族门阀渊源与好恶加成
	var clan_service = TangClanServiceScript.new()
	var clan_mod: int = clan_service.calculate_clan_opinion_modifier(char_a_id, char_b_id, state, data)
	if clan_mod != 0:
		total_score += clan_mod
		var prof_a_clan: Dictionary = clan_service.get_character_clan_profile(state, data, char_a_id)
		var prof_b_clan: Dictionary = clan_service.get_character_clan_profile(state, data, char_b_id)
		var label_str := "宗族同门/同气: %s" % str(prof_a_clan.get("clan_name", "")) if (str(prof_a_clan.get("clan_id", "")) == str(prof_b_clan.get("clan_id", "")) and not str(prof_a_clan.get("clan_id", "")).is_empty()) else ("门第羁绊: %s 与 %s" % [str(prof_a_clan.get("clan_name", "")), str(prof_b_clan.get("clan_name", ""))] if clan_mod > 0 else "门第相轻: %s 视 %s" % [str(prof_a_clan.get("clan_name", "")), str(prof_b_clan.get("clan_name", ""))])
		reasons.append({
			"label": label_str,
			"delta": clan_mod
		})

	total_score = clampi(total_score, -100, 100)
	return {
		"source_id": char_a_id,
		"target_id": char_b_id,
		"opinion_score": total_score,
		"reasons": reasons
	}

## 评估特定政治/政务决断对角色心智压力的契合与违逆影响
func evaluate_action_stress_impact(character_id: String, action_kind: String, action_params: Dictionary, state, data: Dictionary) -> Dictionary:
	var prof := get_categorized_trait_profile(state, data, character_id)
	var all_active: Array = []
	all_active.append_array(prof.get("public_traits", []))
	all_active.append_array(prof.get("exposed_traits", []))

	var total_stress_delta := 0
	var explanations: Array[String] = []

	for trait_info in all_active:
		var t_dict: Dictionary = trait_info as Dictionary
		var triggers: Dictionary = t_dict.get("stress_triggers", {})
		if triggers.has(action_kind):
			var delta := int(triggers[action_kind])
			total_stress_delta += delta
			var trait_name := str(t_dict.get("name", ""))
			if delta > 0:
				explanations.append("【%s】违逆心性，增添心神负担 (+%d)" % [trait_name, delta])
			elif delta < 0:
				explanations.append("【%s】符合本心，平复心神烦忧 (%d)" % [trait_name, delta])

	var congruence := "neutral"
	if total_stress_delta > 0:
		congruence = "violating"
	elif total_stress_delta < 0:
		congruence = "congruent"

	return {
		"character_id": character_id,
		"action_kind": action_kind,
		"stress_delta": total_stress_delta,
		"congruence": congruence,
		"explanations": explanations
	}

## 动态赋予角色新特质 (如崩溃抉择或重大政治事件)
func add_character_trait(state, data: Dictionary, character_id: String, trait_id: String, is_hidden: bool = false) -> Dictionary:
	var def := get_trait_definition(trait_id)
	if def.is_empty():
		return {"ok": false, "error": "unknown trait id: " + trait_id}

	if state.get("flags") == null:
		state.flags = {}
	var custom_traits: Dictionary = state.flags.get("custom_character_traits", {}).duplicate(true)
	var char_record: Dictionary = custom_traits.get(character_id, {"added_public": [], "added_hidden": [], "removed": []}).duplicate(true)

	if is_hidden:
		if not char_record.added_hidden.has(trait_id):
			char_record.added_hidden.append(trait_id)
	else:
		if not char_record.added_public.has(trait_id):
			char_record.added_public.append(trait_id)
	char_record.removed.erase(trait_id)

	custom_traits[character_id] = char_record
	state.flags["custom_character_traits"] = custom_traits

	return {
		"ok": true,
		"character_id": character_id,
		"trait_id": trait_id,
		"trait_name": str(def.get("name", trait_id)),
		"is_hidden": is_hidden
	}

## 动态移除角色特质
func remove_character_trait(state, data: Dictionary, character_id: String, trait_id: String) -> Dictionary:
	if state.get("flags") == null:
		state.flags = {}
	var custom_traits: Dictionary = state.flags.get("custom_character_traits", {}).duplicate(true)
	var char_record: Dictionary = custom_traits.get(character_id, {"added_public": [], "added_hidden": [], "removed": []}).duplicate(true)

	char_record.added_public.erase(trait_id)
	char_record.added_hidden.erase(trait_id)
	if not char_record.removed.has(trait_id):
		char_record.removed.append(trait_id)

	custom_traits[character_id] = char_record
	state.flags["custom_character_traits"] = custom_traits

	return {"ok": true, "character_id": character_id, "trait_id": trait_id}

## 检查并触发特质曝光事件
func check_and_trigger_trait_exposure(state, data: Dictionary, event_id: String, context: Dictionary = {}) -> Dictionary:
	var knowledge_service = CharacterKnowledgeServiceScript.new()
	var unmasked_records: Array = []

	var default_triggers := [
		{
			"trigger_event": "palace_gate_lockdown",
			"character_id": "li_fuguo",
			"unmask_trait": "sinister_usurper",
			"reason": "灵武封锁宫门擅调宿卫，暴露其阴鸷擅权之野心",
			"claim_confidence": 1.0
		},
		{
			"trigger_event": "audit_grain_treasury",
			"character_id": "grain_official_lingwu",
			"unmask_trait": "greedy_grain_hoarder",
			"reason": "清查灵武粮仓巨额亏空，确凿核实其贪墨渎职之品性",
			"claim_confidence": 1.0
		}
	]

	var triggers := default_triggers.duplicate(true)
	if context.has("custom_triggers") and context.get("custom_triggers") is Array:
		triggers.append_array(context.get("custom_triggers"))

	for trigger in triggers:
		if str(trigger.get("trigger_event", "")) != event_id:
			continue
		var target_char_id := str(trigger.get("character_id", ""))
		var unmask_trait_id := str(trigger.get("unmask_trait", ""))
		var reason := str(trigger.get("reason", "因事件处置暴露真实品性"))
		var confidence := float(trigger.get("claim_confidence", 0.95))

		var claim := {
			"source_id": "event_" + event_id,
			"acquired_day": int(state.current_day),
			"confidence": confidence,
			"value": [unmask_trait_id],
			"status": "confirmed"
		}
		var record_res := knowledge_service.record_claim(state, target_char_id, "traits", claim)
		if record_res.get("ok", false):
			var def := get_trait_definition(unmask_trait_id)
			unmasked_records.append({
				"character_id": target_char_id,
				"character_name": _get_char_name(data, target_char_id),
				"trait_id": unmask_trait_id,
				"trait_name": str(def.get("name", unmask_trait_id)),
				"reason": reason,
				"day": int(state.current_day)
			})

	if not unmasked_records.is_empty():
		var history: Array = state.flags.get("tang_trait_exposure_history", []).duplicate(true)
		history.append_array(unmasked_records)
		state.flags["tang_trait_exposure_history"] = history

	return {
		"ok": true,
		"unmasked_records": unmasked_records
	}

## 依据考绩/事务结果锁定官员确凿能力值
func reveal_ability_from_task_outcome(state, data: Dictionary, character_id: String, ability_key: String, exact_value: int, reason: String) -> Dictionary:
	var knowledge_service = CharacterKnowledgeServiceScript.new()
	var claim := {
		"source_id": "task_eval_day_%d" % int(state.current_day),
		"acquired_day": int(state.current_day),
		"confidence": 1.0,
		"value": exact_value,
		"status": "confirmed"
	}
	var record_res := knowledge_service.record_claim(state, character_id, ability_key, claim)
	if not record_res.get("ok", false):
		return record_res

	var evaluations: Array = state.flags.get("ability_evaluations_history", []).duplicate(true)
	evaluations.append({
		"character_id": character_id,
		"character_name": _get_char_name(data, character_id),
		"ability_key": ability_key,
		"exact_value": exact_value,
		"reason": reason,
		"day": int(state.current_day)
	})
	state.flags["ability_evaluations_history"] = evaluations

	return {
		"ok": true,
		"character_id": character_id,
		"ability_key": ability_key,
		"exact_value": exact_value,
		"reason": reason
	}

func _find_char_data(data: Dictionary, character_id: String) -> Dictionary:
	for raw_c in data.get("characters", []):
		if raw_c is Dictionary and str((raw_c as Dictionary).get("id", "")) == character_id:
			return (raw_c as Dictionary).duplicate(true)
	var clan_service = TangClanServiceScript.new()
	if clan_service._cached_elites.has(character_id):
		return (clan_service._cached_elites[character_id] as Dictionary).duplicate(true)
	return {}

func _get_char_name(data: Dictionary, character_id: String) -> String:
	var c := _find_char_data(data, character_id)
	return str(c.get("name", character_id))
