extends RefCounted

class_name TangClanService

const CLANS_DEF_PATH := "res://data/scenarios/anshi_rebellion/tang_clans_definition.json"
const CLANS_EXPANSION_PATH := "res://data/scenarios/anshi_rebellion/tang_clan_characters_expansion.json"
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")

var _cached_clans: Dictionary = {}
var _cached_elites: Dictionary = {}
var _cached_scions: Dictionary = {}

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	if FileAccess.file_exists(CLANS_DEF_PATH):
		var file := FileAccess.open(CLANS_DEF_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary and (parsed as Dictionary).get("clans", []) is Array:
				for raw in (parsed as Dictionary).get("clans", []):
					if raw is Dictionary and raw.has("clan_id"):
						_cached_clans[str(raw.get("clan_id"))] = (raw as Dictionary).duplicate(true)
	
	if FileAccess.file_exists(CLANS_EXPANSION_PATH):
		var exp_file := FileAccess.open(CLANS_EXPANSION_PATH, FileAccess.READ)
		if exp_file != null:
			var exp_parsed: Variant = JSON.parse_string(exp_file.get_as_text())
			exp_file.close()
			if exp_parsed is Dictionary:
				for raw_elite in (exp_parsed as Dictionary).get("tier_2_elites", []):
					if raw_elite is Dictionary and raw_elite.has("id"):
						_cached_elites[str(raw_elite.get("id"))] = (raw_elite as Dictionary).duplicate(true)
				for raw_scion in (exp_parsed as Dictionary).get("tier_3_scion_pool", []):
					if raw_scion is Dictionary and raw_scion.has("id"):
						_cached_scions[str(raw_scion.get("id"))] = (raw_scion as Dictionary).duplicate(true)

func get_all_clans(data: Dictionary = {}) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var composed := _cached_clans.duplicate(true)
	for clan in data.get("tang_clans_definition", {}).get("clans", []):
		if clan is Dictionary and clan.has("clan_id"): composed[clan.clan_id] = clan
	for clan in composed.values():
		list.append((clan as Dictionary).duplicate(true))
	return list

func get_clan(clan_id: String) -> Dictionary:
	if _cached_clans.has(clan_id):
		return (_cached_clans[clan_id] as Dictionary).duplicate(true)
	return {}

func get_tier_2_elite(elite_id: String) -> Dictionary:
	if _cached_elites.has(elite_id):
		return (_cached_elites[elite_id] as Dictionary).duplicate(true)
	return {}

func get_tier_3_scion(scion_id: String) -> Dictionary:
	if _cached_scions.has(scion_id):
		return (_cached_scions[scion_id] as Dictionary).duplicate(true)
	return {}

func get_clan_definition(clan_id: String, data: Dictionary = {}) -> Dictionary:
	return _scenario_clan(data, clan_id)

func _scenario_clan(data: Dictionary, clan_id: String) -> Dictionary:
	for clan in data.get("tang_clans_definition", {}).get("clans", []):
		if clan is Dictionary and clan.get("clan_id") == clan_id: return clan.duplicate(true)
	return get_clan(clan_id)

# Initial estate definitions are scenario grants, never a live balance or a rumor.
func project_finances(state, clan_id: String, viewer_id: String) -> Dictionary:
	var unknown := {"known": false, "text": "现金未获知 · 粮储未获知"}
	if state == null or clan_id.is_empty(): return unknown
	var accounts = Accounts.new()
	var seen := {}
	var cash := 0
	var available := 0
	var sources: Array[String] = []
	var ids: Array = state.resource_accounts.keys()
	ids.sort()
	for id in ids:
		var account: Dictionary = state.resource_accounts[id]
		if account.unit_id != "cash_unit": continue
		if account.owner_ref != {"entity_kind": "clan", "entity_id": clan_id} or not accounts.can_operate(state, str(id), viewer_id): continue
		var key := Storage.key(account.storage_ref)
		if seen.has(key): continue
		seen[key] = true
		sources.append(str(id))
		cash += accounts.balance(state, str(id))
		available += accounts.available(state, str(id))
	if sources.is_empty(): return unknown
	return {"known": true, "cash": cash, "available": available, "reserved": cash - available, "unit_id": "cash_unit", "source_account_ids": sources, "text": "已知现金 %d · 可用 %d · 占用 %d（记账单位）\n粮储未获知" % [cash, available, cash - available]}

func get_character_clan_profile(state, data: Dictionary, character_id: String) -> Dictionary:
	var character := _find_character_all(data, character_id)
	if character.is_empty():
		return {}
	
	var clan_id := str(character.get("clan_id", ""))
	if clan_id.is_empty():
		clan_id = _infer_character_clan_id(character_id)
	
	var clan_def := _scenario_clan(data, clan_id)
	if clan_id.is_empty() or clan_def.is_empty():
		var is_eunuch := (str(character.get("faction_id", "")) == "eunuch_network" or character_id in ["li_fuguo", "cheng_yuanzhen", "yu_chaoen"])
		return {
			"has_clan": false,
			"clan_id": "",
			"clan_name": "内廷中官 (无宗族世家)" if is_eunuch else "无显赫宗族 (寒素士人)",
			"clan_type": "eunuch_household" if is_eunuch else "plebeian_bureaucrats",
			"clan_role": "independent",
			"renown_tier": 0,
			"renown_name": "中官内侍" if is_eunuch else "寒微士族",
			"is_patriarch": false,
			"patriarch_id": ""
		}
	
	var patriarch_id := resolve_clan_patriarch(state, data, clan_id)
	var is_patriarch := (character_id == patriarch_id)
	var clan_role := "patriarch" if is_patriarch else str(character.get("clan_role", "scion"))
	if not is_patriarch and clan_role == "patriarch": clan_role = "former_patriarch"
	var renown_tier := int(clan_def.get("renown_tier", 1))
	var tier_names: Array[String] = ["寒微士族", "累世冠带", "阀阅名家", "钟鸣鼎食", "天下甲第"]
	var tier_name: String = tier_names[clampi(renown_tier, 0, 4)]
	
	return {
		"has_clan": true,
		"clan_id": clan_id,
		"clan_name": str(clan_def.get("name", "世家宗族")),
		"clan_type": str(clan_def.get("clan_type", "guanlong_nobility")),
		"origin_county": str(clan_def.get("origin_county", "")),
		"clan_role": clan_role,
		"renown": int(clan_def.get("renown", 100)),
		"renown_tier": renown_tier,
		"renown_name": tier_name,
		"is_patriarch": is_patriarch,
		"patriarch_id": patriarch_id,
		"ancestral_legacy": (clan_def.get("ancestral_legacy", {}) as Dictionary).duplicate(true)
	}

func resolve_clan_patriarch(state, data: Dictionary, clan_id: String) -> String:
	if state != null and state.get("flags") is Dictionary:
		var actual: String = preload("res://scripts/core/clan_succession_service.gd").head(state, clan_id)
		if actual != "": return actual
	var clan_def := _scenario_clan(data, clan_id)
	if clan_def.is_empty():
		return ""
	var default_head := str(clan_def.get("default_patriarch_id", ""))
	if not default_head.is_empty():
		return default_head
	var members := get_clan_living_members(clan_id, data)
	if members.is_empty():
		return ""
	return str(members[0].get("id", ""))

func get_clan_living_members(clan_id: String, data: Dictionary) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for raw in data.get("characters", []):
		if raw is Dictionary:
			var c_clan := str((raw as Dictionary).get("clan_id", _infer_character_clan_id(str((raw as Dictionary).get("id", "")))))
			if c_clan == clan_id:
				members.append((raw as Dictionary).duplicate(true))
	for elite in _cached_elites.values():
		if elite is Dictionary and str((elite as Dictionary).get("clan_id", "")) == clan_id and not members.any(func(member): return member.get("id") == elite.get("id")):
			members.append((elite as Dictionary).duplicate(true))
	return members

func calculate_clan_opinion_modifier(actor_id: String, target_id: String, state, data: Dictionary) -> int:
	var actor_profile := get_character_clan_profile(state, data, actor_id)
	var target_profile := get_character_clan_profile(state, data, target_id)
	
	if not bool(actor_profile.get("has_clan", false)) and not bool(target_profile.get("has_clan", false)):
		return 0
	
	var actor_clan_id := str(actor_profile.get("clan_id", ""))
	var target_clan_id := str(target_profile.get("clan_id", ""))
	if not actor_clan_id.is_empty() and actor_clan_id == target_clan_id:
		return 25
	
	var actor_type := str(actor_profile.get("clan_type", "plebeian_bureaucrats"))
	var target_type := str(target_profile.get("clan_type", "plebeian_bureaucrats"))
	
	var clan_def := _scenario_clan(data, actor_clan_id)
	if not clan_def.is_empty():
		var base_mods: Dictionary = clan_def.get("base_opinion_modifiers", {})
		if base_mods.has(target_type):
			return int(base_mods[target_type])
	
	return 0

func get_character_opinion_of_player(state, data: Dictionary, character_id: String) -> int:
	var base_op: int = 50
	if character_id in ["li_heng", "li_chu"]:
		return 100
	var clan_mod := calculate_clan_opinion_modifier(character_id, "li_heng", state, data)
	return clampi(base_op + clan_mod, -100, 100)

func calculate_marriage_compatibility(groom_id: String, bride_clan_id: String, state, data: Dictionary) -> Dictionary:
	var groom_profile := get_character_clan_profile(state, data, groom_id)
	if not _cached_clans.has(bride_clan_id):
		return {"ok": false, "error": "unknown_bride_clan"}
	
	var bride_clan: Dictionary = _cached_clans[bride_clan_id]
	var bride_tier := int(bride_clan.get("renown_tier", 1))
	var groom_tier := int(groom_profile.get("renown_tier", 0))
	var bride_type := str(bride_clan.get("clan_type", ""))
	
	var is_five_great := (bride_type == "five_great_clans")
	var tier_diff := bride_tier - groom_tier
	
	var base_score := 70 - (tier_diff * 20)
	if is_five_great and groom_tier < 3:
		base_score -= 30
	
	var prestige_cost := maxi(0, tier_diff * 100 + (150 if is_five_great else 0))
	var accepted := (base_score >= 40)
	
	return {
		"ok": true,
		"groom_id": groom_id,
		"bride_clan_id": bride_clan_id,
		"bride_clan_name": str(bride_clan.get("name", "")),
		"compatibility_score": clampi(base_score, 0, 100),
		"prestige_cost": prestige_cost,
		"is_five_great_clan": is_five_great,
		"accepted": accepted,
		"opinion_bond_delta": 30 if accepted else 0,
		"marriage_reason": "门当户对，天作之合" if accepted else "门第悬殊，宗族执事不允此桩婚配"
	}

func generate_patronage_recommendations(state, data: Dictionary) -> Array[Dictionary]:
	var recs: Array[Dictionary] = []
	for clan_id in _cached_clans.keys():
		var clan_def: Dictionary = _cached_clans[clan_id]
		var tier := int(clan_def.get("renown_tier", 1))
		if tier < 2:
			continue
		var patriarch_id := resolve_clan_patriarch(state, data, clan_id)
		var scions: Array[Dictionary] = []
		for s in _cached_scions.values():
			if s is Dictionary and str((s as Dictionary).get("clan_id", "")) == clan_id:
				scions.append((s as Dictionary).duplicate(true))
		if not scions.is_empty():
			var selected_scion := scions[0]
			recs.append({
				"clan_id": clan_id,
				"clan_name": str(clan_def.get("name", "")),
				"patriarch_id": patriarch_id,
				"scion_id": str(selected_scion.get("id", "")),
				"scion_name": str(selected_scion.get("name", "")),
				"potential_field": str(selected_scion.get("potential", "governance")),
				"aptitude": int(selected_scion.get("aptitude", 70)),
				"recommendation_title": "%s族长奏请门荫推恩：%s" % [str(clan_def.get("name", "")), str(selected_scion.get("name", ""))],
				"cost_silver": 100,
				"opinion_gain": 20
			})
	return recs

func _find_character_all(data: Dictionary, character_id: String) -> Dictionary:
	for raw in data.get("characters", []):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == character_id:
			return (raw as Dictionary).duplicate(true)
	if _cached_elites.has(character_id):
		return (_cached_elites[character_id] as Dictionary).duplicate(true)
	return {}

func _infer_character_clan_id(character_id: String) -> String:
	match character_id:
		"li_heng", "li_chu", "li_tan", "li_lin":
			return "clan_li_longxi_imperial"
		"li_bi", "li_xian", "li_hua":
			return "clan_li_zhaojun"
		"guo_ziyi", "guo_xi", "guo_ai":
			return "clan_guo_huazhou"
		"pugu_huaien", "pugu_yang":
			return "clan_pugu_shuofang"
		"cui_yuan", "cui_huan", "cui_youfu":
			return "clan_cui_qinghe"
		"cui_guangyuan":
			return "clan_cui_boling"
		"lu_yi", "lu_qi":
			return "clan_lu_fanyang"
		"zheng_qian":
			return "clan_zheng_xingyang"
		"wang_wei", "wang_jin", "wang_hong":
			return "clan_wang_taiyuan"
		"wei_jiansu", "wei_zhi":
			return "clan_wei_jingzhao"
		"du_hongjian", "du_fu", "du_you":
			return "clan_du_jingzhao"
		"yang_wan", "yang_yan":
			return "clan_yang_hongnong"
	return ""
