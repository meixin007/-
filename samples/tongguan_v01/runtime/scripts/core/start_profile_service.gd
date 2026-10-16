extends RefCounted

# Definition selection happens before any new-world mutation. Historical fixtures
# without profiles retain their own definition; the current campaign requires one.
static func prepare(data: Dictionary, profile_id: String = "") -> Dictionary:
	var profiles: Variant = data.get("start_profiles", {})
	if not profiles is Dictionary:
		return _fail("start_profiles must be a dictionary")
	if profiles.is_empty():
		if not profile_id.is_empty() or data.get("campaign_id") == "anshi_beta_1_14":
			return _fail("missing start_profiles")
		return {"ok": true, "data": data.duplicate(true)}
	var selected := profile_id if not profile_id.is_empty() else str(data.get("default_start_profile_id", ""))
	if not profiles.get(selected) is Dictionary:
		return _fail("unknown start profile: " + selected)
	var profile: Dictionary = profiles[selected]
	for key in ["start_profile_id", "player_character_id", "organization_id", "location_id"]:
		if not profile.get(key) is String or str(profile[key]).is_empty():
			return _fail("start profile requires " + key)
	if profile.start_profile_id != selected:
		return _fail("start profile identity mismatch: " + selected)
	var characters: Array = data.get("characters", [])
	if not characters.any(func(c): return c is Dictionary and c.get("id") == profile.player_character_id and c.get("status", "alive") not in ["dead", "deceased"]):
		return _fail("start profile references missing living character: " + str(profile.player_character_id))
	var clans: Array = data.get("tang_clans_definition", {}).get("clans", [])
	var regional: Dictionary = data.get("management", {}).get("regional_administration", {})
	var local_head: bool = regional.get("organizations", []).any(func(org): return org.get("organization_id") == profile.organization_id and org.get("location_id") == profile.location_id and regional.get("initial_terms", []).any(func(term): return term.get("office_id") == org.get("head_office_id") and term.get("holder_id") == profile.player_character_id))
	if not local_head and not clans.any(func(c): return c.get("clan_id") == profile.organization_id and c.get("default_patriarch_id") == profile.player_character_id):
		return _fail("start profile organization or patriarch is invalid: " + str(profile.organization_id))
	if not (data.get("local_nodes", []) as Array).any(func(n): return n.get("node_id", n.get("id")) == profile.location_id):
		return _fail("start profile location is missing: " + str(profile.location_id))
	if not profile.get("initial_asset_grants") is Array or not profile.get("initial_office_terms") is Array:
		return _fail("start profile requires grant and office arrays")
	for term in profile.initial_office_terms:
		if not term is Dictionary or not regional.get("initial_terms", []).has(term): return _fail("start profile term has no matching world definition")
	var seen := {}
	for grant in profile.initial_asset_grants:
		if not grant is Dictionary or str(grant.get("source_id", "")).is_empty() or seen.has(grant.get("source_id")):
			return _fail("invalid or duplicate initial grant source")
		seen[grant.source_id] = true
		if grant.get("resource_key") != "silver" or not _amount(grant.get("amount")):
			return _fail("invalid initial personal grant: " + str(grant.source_id))
	var prepared := data.duplicate(true)
	prepared["player_character_id"] = profile.player_character_id
	prepared["selected_start_profile"] = profile.duplicate(true)
	prepared["resources"]["silver"] = 0
	for grant in profile.initial_asset_grants:
		prepared["resources"]["silver"] += int(grant.amount)
		if not _amount(prepared.resources.silver):
			return _fail("initial personal grants exceed amount limit")
	return {"ok": true, "data": prepared}

static func initialize(state, data: Dictionary) -> Dictionary:
	var profile: Dictionary = data.get("selected_start_profile", {})
	if profile.is_empty():
		return {"ok": true}
	if state.flags.has("start_profile_id"):
		return _fail("start profile already initialized")
	state.flags["start_profile_id"] = profile.start_profile_id
	state.flags["player_organization_id"] = profile.organization_id
	state.flags["player_location_id"] = profile.location_id
	state.flags["initial_asset_grants"] = profile.initial_asset_grants.duplicate(true)
	state.character_states[profile.player_character_id]["location_id"] = profile.location_id
	var cash_seed := _initialize_personal_and_public_cash(state, data, profile)
	if not cash_seed.get("ok", false): return cash_seed
	for presence in data.get("management", {}).get("initial_presence", []):
		if not presence is Dictionary or not state.character_states.has(presence.get("character_id")) or not state.local_node_state.has(presence.get("location_id")) or not str(presence.get("source_id", "")).begins_with("scenario:"):
			return _fail("初始经营人物所在位置缺少定义依据")
		if presence.character_id != profile.player_character_id:
			state.character_states[presence.character_id].location_id = presence.location_id
	var clans: Array = data.get("tang_clans_definition", {}).get("clans", [])
	for entry in data.get("management", {}).get("clan_cash_locations", []):
		if not entry is Dictionary or not state.local_node_state.has(entry.get("location_id")):
			return _fail("management cash location is invalid")
		var matches := clans.filter(func(c): return c.get("clan_id") == entry.get("clan_id"))
		if matches.size() != 1:
			return _fail("management clan is invalid")
		var clan: Dictionary = matches[0]
		var operator_id: String = clan.default_patriarch_id
		if not state.character_states.has(operator_id):
			return _fail("management clan has no living initial operator")
		var cash: Variant = clan.get("estate_resources", {}).get("silver")
		if not _amount(cash):
			return _fail("management clan cash source is invalid")
		var account_id: String = clan.clan_id + "_cash"
		var depot_id: String = "estate_" + clan.clan_id
		if state.depot_states.has(depot_id) or state.resource_accounts.has(account_id):
			return _fail("duplicate initial management account")
		state.character_states[operator_id]["clan_id"] = clan.clan_id
		state.depot_states[depot_id] = {"depot_id": depot_id, "location_node_id": entry.location_id, "owner_organization_id": clan.clan_id, "owner_character_id": "", "capacity": 1000000000, "stock": {"silk_cash": int(cash)}}
		var owner := {"entity_kind": "clan", "entity_id": clan.clan_id}
		state.resource_accounts[account_id] = {"account_id": account_id, "owner_ref": owner, "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "silk_cash"}, "operator_refs": [{"entity_kind": "character", "entity_id": operator_id}]}
		var grant_id := "initial:" + account_id
		if int(cash) > 0:
			state.resource_journal[grant_id] = {"entry_id": grant_id, "execution_id": grant_id, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": clan.clan_id, "rule_id": "scenario:clan_estate_resources"}, "destination_ref": owner.duplicate(true), "destination_account_id": account_id, "amount": int(cash), "unit_id": "cash_unit", "reason_ref": "definition:estate_resources.silver", "day": 0}
	for entry in data.get("management", {}).get("character_cash_grants", []):
		if not entry is Dictionary or not state.character_states.has(entry.get("character_id")) or not state.local_node_state.has(entry.get("location_id")) or not _amount(entry.get("amount")) or str(entry.get("source_id", "")).is_empty():
			return _fail("人物资金来源、人物或地点无效")
		var account_id: String = entry.character_id + "_cash"
		var depot_id: String = "personal_" + entry.character_id
		if entry.character_id == profile.player_character_id and profile.initial_asset_grants.size() == 1 and profile.initial_asset_grants[0].source_id == entry.source_id and profile.initial_asset_grants[0].amount == entry.amount and profile.location_id == entry.location_id:
			continue # Same source was already seeded once as the player's private account.
		if state.resource_accounts.has(account_id) or state.depot_states.has(depot_id):
			return _fail("重复人物现金账户")
		var owner := {"entity_kind": "character", "entity_id": entry.character_id}
		state.depot_states[depot_id] = {"depot_id": depot_id, "location_node_id": entry.location_id, "owner_character_id": entry.character_id, "owner_organization_id": "", "capacity": 1000000000, "stock": {"silk_cash": int(entry.amount)}}
		state.resource_accounts[account_id] = {"account_id": account_id, "owner_ref": owner, "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "silk_cash"}, "operator_refs": [owner.duplicate(true)]}
		if int(entry.amount) > 0:
			var grant_id := "initial:" + account_id
			state.resource_journal[grant_id] = {"entry_id": grant_id, "execution_id": grant_id, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": entry.character_id, "rule_id": entry.source_id}, "destination_ref": owner.duplicate(true), "destination_account_id": account_id, "amount": int(entry.amount), "unit_id": "cash_unit", "reason_ref": entry.source_id, "day": 0}
	var food: Dictionary = preload("res://scripts/core/household_subsistence_service.gd").initialize(state, data)
	if not food.get("ok", false): return food
	var commodities: Dictionary = preload("res://scripts/core/commodity_stock_service.gd").initialize(state, data)
	if not commodities.get("ok", false): return commodities
	var assets: Dictionary = preload("res://scripts/core/pawnshop_service.gd").initialize(state, data)
	if not assets.get("ok", false):
		return assets
	var items: Dictionary = preload("res://scripts/core/managed_item_service.gd").initialize(state)
	if not items.get("ok", false): return items
	var offices: Dictionary = preload("res://scripts/core/family_office_rules.gd").initialize(state, data)
	if not offices.get("ok", false):
		return offices
	var regional_offices: Dictionary = preload("res://scripts/core/regional_office_rules.gd").initialize(state, data)
	if not regional_offices.get("ok", false): return regional_offices
	var motives: Dictionary = preload("res://scripts/core/official_initiative_service.gd").initialize(state, data)
	if not motives.get("ok", false): return motives
	var local_fiscal: Dictionary = preload("res://scripts/core/local_fiscal_policy_service.gd").initialize(state, data)
	if not local_fiscal.get("ok", false): return local_fiscal
	var public_works: Dictionary = preload("res://scripts/core/public_works_service.gd").initialize(state, data)
	if not public_works.get("ok", false): return public_works
	var education: Dictionary = preload("res://scripts/core/education_service.gd").initialize(state, data)
	if not education.get("ok", false): return education
	var grain: Dictionary = preload("res://scripts/core/regional_grain_service.gd").initialize(state, data)
	if not grain.get("ok", false): return grain
	var military_grain: Dictionary = preload("res://scripts/core/military_grain_service.gd").initialize(state, data)
	if not military_grain.get("ok", false): return military_grain
	var partition: Dictionary = preload("res://scripts/core/family_partition_service.gd").initialize(state, data)
	if not partition.get("ok", false): return partition
	var estate: Dictionary = preload("res://scripts/core/personal_estate_service.gd").initialize(state, data)
	if not estate.get("ok", false): return estate
	var player_succession: Dictionary = preload("res://scripts/core/player_succession_service.gd").initialize(state, data)
	if not player_succession.get("ok", false): return player_succession
	var succession: Dictionary = preload("res://scripts/core/clan_succession_service.gd").initialize(state, data)
	if not succession.get("ok", false): return succession
	var marriage: Dictionary = preload("res://scripts/core/marriage_service.gd").initialize(state, data)
	if not marriage.get("ok", false): return marriage
	var envoy: Dictionary = preload("res://scripts/core/official_journey_service.gd").initialize(state, data)
	if not envoy.get("ok", false): return envoy
	# Actual scenario appointments retain one term per canonical office. Legacy
	# aliases are views of that office, never extra posts or assistant authority.
	if data.get("campaign_id") == "anshi_beta_1_14":
		for initial in data.get("initial_office_overlay", []):
			var office_id: String = preload("res://scripts/domain/tang_office_catalog.gd").canonical_id(str(initial.get("office_id", "")))
			var office: Dictionary = state.office_state.get(office_id, {})
			if office.get("office_kind") in ["regional", "family"] or str(initial.get("holder_id", "")).is_empty(): continue
			if office.get("holder_id") != initial.holder_id or not state.character_states.has(initial.holder_id): return _fail("中央初始任期与实际职位来源不符")
			var term_id := "initial_central:" + office_id
			if state.office_terms.has(term_id): return _fail("同一中央职位重复发放初始任期")
			state.office_terms[term_id] = {"term_id": term_id, "office_id": office_id, "holder_id": initial.holder_id, "start_day": 0, "end_day": -1, "appointment_mode": "initial", "appointment_transaction_id": "bootstrap|anshi_beta_1_14", "ended_by": "", "performance_refs": [], "settled_reward_keys": []}
	var assistant: Dictionary = preload("res://scripts/core/player_assistant_service.gd").initialize(state, data)
	if not assistant.get("ok", false): return assistant
	return preload("res://scripts/core/assistant_advice_service.gd").initialize(state, data)

static func _initialize_personal_and_public_cash(state, data: Dictionary, profile: Dictionary) -> Dictionary:
	var id: String = profile.player_character_id
	var account_id := id + "_cash"
	var depot_id := "personal_" + id
	if state.resource_accounts.has(account_id) or state.depot_states.has(depot_id):
		return _fail("重复玩家私款来源")
	var initial := 0
	for grant in profile.initial_asset_grants: initial += int(grant.amount)
	var owner := {"entity_kind": "character", "entity_id": id}
	state.depot_states[depot_id] = {"depot_id": depot_id, "location_node_id": profile.location_id, "owner_character_id": id, "owner_organization_id": "", "capacity": 1000000000, "stock": {"silk_cash": initial}}
	state.resource_accounts[account_id] = {"account_id": account_id, "owner_ref": owner, "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "silk_cash"}, "operator_refs": [owner.duplicate(true)]}
	for grant in profile.initial_asset_grants:
		if int(grant.amount) == 0: continue
		var entry_id: String = "initial:%s:%s" % [id, grant.source_id]
		state.resource_journal[entry_id] = {"entry_id": entry_id, "execution_id": entry_id, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": id, "rule_id": grant.source_id}, "destination_ref": owner.duplicate(true), "destination_account_id": account_id, "amount": int(grant.amount), "unit_id": "cash_unit", "reason_ref": grant.source_id, "day": 0}
	state.resources.erase("silver")
	var public: Variant = data.get("management", {}).get("public_cash_account")
	if not public is Dictionary or public.get("account_id") != "court_treasury" or public.get("resource_key") != "treasury" or not _amount(state.resources.get("treasury")) or not state.office_state.has(public.get("office_id")) or not state.character_states.has(public.get("operator_id")) or not state.local_node_state.has(public.get("location_id")) or not str(public.get("source_id", "")).begins_with("scenario:"):
		return _fail("国帑来源、经办权源或交割地缺少配置")
	var public_owner := {"entity_kind": "office", "entity_id": public.office_id}
	state.resource_accounts[public.account_id] = {"account_id": public.account_id, "owner_ref": public_owner, "location_id": public.location_id, "resource_key": "treasury", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "resource_pool", "storage_id": "resources", "resource_key": "treasury"}, "operator_refs": [{"entity_kind": "character", "entity_id": public.operator_id}]}
	if int(state.resources.treasury) > 0:
		var entry_id := "initial:court_treasury"
		state.resource_journal[entry_id] = {"entry_id": entry_id, "execution_id": entry_id, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": public.office_id, "rule_id": public.source_id}, "destination_ref": public_owner.duplicate(true), "destination_account_id": public.account_id, "amount": int(state.resources.treasury), "unit_id": "cash_unit", "reason_ref": public.source_id, "day": 0}
	return {"ok": true}

static func _amount(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 1000000000

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "invalid_start_profile", "error": message, "message": message}
