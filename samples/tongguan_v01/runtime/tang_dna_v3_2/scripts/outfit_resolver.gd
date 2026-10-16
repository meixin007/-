class_name OutfitResolver
extends RefCounted
## 衣着由场景、身份与明确资格决定；此模块不读 DNA。
## dress_rank 应由官制模块计算，不直接等同 office_rank。


static func resolve(character: Dictionary, context: Dictionary,
		profile: Dictionary, _catalog: Dictionary) -> Dictionary:
	var social: Dictionary = character.get("social", {})
	var state: Dictionary = character.get("appearance_state", {})
	var occasion: String = context.get("occasion", "private")
	var year: int = int(context.get("year", profile["reference_year"]))
	var evidence: Array = []
	var suppressed: Array = []
	var result: Dictionary = {
		"ok": true, "profile_id": profile["profile_id"], "occasion": occasion,
		"color_id": "common", "fish_bag_material": "none", "requests": [],
		"evidence": evidence, "suppressed": suppressed,
	}
	if year < int(profile.get("valid_from_year", year)) or year > int(profile.get("valid_until_year", year)):
		result["ok"] = false
		evidence.append(_evidence("profile_year_out_of_range", "年份超出该时代配置适用范围；须选择或新增正确的profile。"))
		return _finish(result, profile)
	if bool(state.get("is_captive", false)):
		result["color_id"] = "common"
		result["requests"] = [_request("base_garment", "robe_plain")]
		evidence.append(_evidence("captivity_priority", "被俘状态优先；演示采用朴素羁押衣着，原身份与赐服资格保留在角色数据。"))
		if bool(context.get("armor_requested", false)) or occasion == "campaign":
			suppressed.append("captivity_overrides_armor")
		suppressed.append("rank_headwear_and_fish_bag_hidden_in_captivity")
		return _finish(result, profile)
	if occasion == "campaign" and bool(context.get("armor_requested", true)):
		if bool(social.get("armor_entitled", false)):
			result["requests"] = [
				_request("base_garment", "campaign_tunic"),
				_request("outer_garment", "armor_tang_lamellar"),
				_request("headwear", "helmet_tang"),
			]
			evidence.append(_evidence("campaign_equipment", "出征场景且有甲胄装备资格；同一人物平时不穿战甲。"))
			suppressed.append("fish_bag_hidden_during_campaign")
			return _finish(result, profile)
		evidence.append(_evidence("armor_not_entitled", "出征请求没有甲胄资格，回退到身份衣着。"))
	elif bool(context.get("armor_requested", false)):
		suppressed.append("armor_request_conflicts_with_occasion")
		evidence.append(_evidence("occasion_blocks_armor", "非出征场景忽略穿甲请求。"))
	if occasion not in ["ordinary_audience", "campaign", "private"]:
		result["requests"] = [_request("base_garment", "robe_plain")]
		evidence.append(_evidence("unsupported_occasion", "此原型未实现该礼仪场景，输出显式普通衣着回退；不能据此生成正式祭礼服。"))
		return _finish(result, profile)
	var role: String = social.get("role", "civilian")
	var color: String = "common"
	var garment: String = "robe_plain"
	var headwear: String = ""
	var accepts_color_grant: bool = false
	if role == "eunuch":
		var uniform_class: String = social.get("uniform_class", "eunuch_service")
		var uniform: Dictionary = profile["uniform_classes"].get(uniform_class, profile["uniform_classes"]["eunuch_service"])
		garment = uniform["asset_id"]
		color = uniform["base_color"]
		headwear = uniform.get("headwear", "")
		accepts_color_grant = bool(uniform.get("accepts_color_grant", false))
		evidence.append(_evidence("eunuch_uniform_class", "宦官衣着读取显式 uniform_class；不把文官服色映射直接套给宦官。"))
	elif role in ["civil_official", "military_official"]:
		garment = "robe_official_regular"
		headwear = "futou_regular"
		var dress_rank: int = int(social.get("dress_rank", 0))
		color = _rank_color(dress_rank, profile)
		accepts_color_grant = true
		evidence.append(_evidence("official_dress_rank", "常服读取官制模块提供的 dress_rank=" + str(dress_rank) + "；本色表为可配置的约830年游戏简化。"))
	elif role == "emperor":
		garment = "robe_imperial_regular"
		color = "imperial_ochre"
		headwear = "futou_regular"
		evidence.append(_evidence("imperial_regular_only", "此分支仅为帝王日常袍服示例；祭祀、册命等大礼另建规则。"))
	else:
		evidence.append(_evidence("plain_role_fallback", "该身份使用普通衣着回退，详细民间、女官、妃嫔、僧道服饰尚待扩展。"))
	if accepts_color_grant:
		var granted_color: String = _choose_grant(social.get("robe_color_grants", []), "color", profile["robe_grant_priority"], year, occasion, "robe_color", evidence)
		if not granted_color.is_empty():
			var base_priority: int = profile["robe_grant_priority"].find(color)
			var grant_priority: int = profile["robe_grant_priority"].find(granted_color)
			if base_priority < 0 or grant_priority < base_priority:
				color = granted_color
				evidence.append(_evidence("explicit_robe_color_grant", "有效赐服资格扩展到 " + color + "；此资格不自动推导鱼袋。"))
			else:
				evidence.append(_evidence("grant_does_not_downgrade_rank", "已有基础服色资格不低于赐服；保留 " + color + "，旧赐服不导致晋升后降色。"))
	result["color_id"] = color
	result["requests"].append(_request("base_garment", garment))
	if not headwear.is_empty():
		result["requests"].append(_request("headwear", headwear))
	if occasion == "ordinary_audience" and role in ["civil_official", "military_official", "eunuch"]:
		var fish_bag: String = _choose_grant(social.get("fish_bag_grants", []), "material", ["gold", "silver"], year, occasion, "fish_bag", evidence)
		if not fish_bag.is_empty():
			result["fish_bag_material"] = fish_bag
			result["requests"].append(_request("accessory", "fish_bag_" + fish_bag))
			evidence.append(_evidence("independent_fish_bag_grant", "鱼袋只读取独立授予记录；历史上的连授可由同一事件写入两条资格。"))
	return _finish(result, profile)


static func _rank_color(dress_rank: int, profile: Dictionary) -> String:
	for band in profile["regular_robe_rank_bands"]:
		if dress_rank >= int(band["min_rank"]) and dress_rank <= int(band["max_rank"]):
			return band["color_id"]
	return "common"


static func _choose_grant(grants: Array, field: String, priority: Array, year: int,
		occasion: String, scope: String, evidence: Array) -> String:
	var eligible: Array = []
	for grant in grants:
		var reason: String = ""
		var allowed: Array = grant.get("allowed_occasions", [])
		if not bool(grant.get("active", true)):
			reason = "inactive"
		elif year < int(grant.get("valid_from_year", -9999)) or year > int(grant.get("valid_until_year", 9999)):
			reason = "year_out_of_range"
		elif grant.get("grant_scope", scope) != scope:
			reason = "scope_mismatch"
		elif not allowed.is_empty() and not allowed.has(occasion):
			reason = "occasion_mismatch"
		if reason.is_empty():
			eligible.append(grant)
		else:
			evidence.append(_evidence("grant_rejected", str(grant.get("grant_id", "unnamed")) + ": " + reason))
	for desired in priority:
		for grant in eligible:
			if grant.get(field, "") == desired:
				return str(desired)
	return ""


static func _request(slot: String, asset_id: String) -> Dictionary:
	return {"slot": slot, "asset_id": asset_id}


static func _evidence(rule: String, reason: String) -> Dictionary:
	return {"rule": rule, "reason": reason}


static func _finish(result: Dictionary, profile: Dictionary) -> Dictionary:
	result["tint_srgb"] = profile["palette"].get(result["color_id"], profile["palette"]["common"])
	return result

