extends RefCounted
const Catalog = preload("res://scripts/domain/tang_office_catalog.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")

static func merge_definitions(data: Dictionary, config: Variant) -> Dictionary:
	if not config is Dictionary or not str(config.get("source_id", "")).begins_with("scenario:") or not config.get("content_basis") is String or not config.get("offices") is Array or not config.get("branches") is Array or not config.get("office_overrides") is Array: return fail("中央官署配置缺少明确来源或目录")
	var branches := {}
	for branch in config.branches:
		if not branch is Dictionary or not branch.get("id") is String or str(branch.id).is_empty() or not branch.get("name") is String or str(branch.name).is_empty() or branches.has(branch.id): return fail("中央机构分组无效或重复")
		branches[branch.id] = true
	var offices := {}
	for office in data.offices_catalog.offices: offices[office.id] = office
	for office in config.offices:
		if not office is Dictionary or not office.get("id") is String or str(office.id).is_empty() or offices.has(office.id) or office.get("office_kind") != "central" or office.get("source_id") != config.source_id or not branches.has(office.get("branch")): return fail("中央职位缺少来源、分组或与已有职位重复")
		offices[office.id] = office.duplicate(true)
		data.offices_catalog.offices.append(offices[office.id])
	for patch in config.office_overrides:
		if not patch is Dictionary or not offices.has(patch.get("office_id")): return fail("中央机构层级引用未知职位")
		for key in patch:
			if key not in ["office_id", "parent_office_id", "branch"]: return fail("机构层级配置不得改写人物、任职或财产")
			if key != "office_id": offices[patch.office_id][key] = patch[key]
		offices[patch.office_id]["hierarchy_source_id"] = config.source_id
	data.offices_catalog.branches = config.branches.duplicate(true)
	data.management["central_administration"] = config.duplicate(true)
	return {"ok": true}

static func assess(state, office_id: String, person: String) -> Dictionary:
	var office: Dictionary = state.office_state.get(office_id, {})
	for held in state.office_state.values():
		if held.get("office_kind") == "central" and held.get("holder_id") == person and held.get("status") == "appointed" and Catalog.canonical_id(str(held.office_id)) != Catalog.canonical_id(office_id): return fail("本人仍任%s，须先办理该职离任交接" % str(held.name))
	if office.get("office_kind") != "central": return {"ok": true, "applicable": false}
	var offers: Array = office.get("service_offers", []).filter(func(row): return row.get("character_id") == person)
	if offers.size() != 1 or not offers[0].get("willing", false): return fail("本人尚未同意接受本署职任，须先协商")
	var offer: Dictionary = offers[0]
	var reference: Dictionary = office.authority_ref
	var principal: String = str(state.office_state.get(reference.entity_id, {}).get("holder_id", "")) if reference.entity_kind == "office_holder" else str(reference.entity_id)
	if int(state.character_states.get(person, {}).get("relationships", {}).get(principal, 0)) < int(offer.minimum_relation): return fail("本人目前不愿受该任命者差遣")
	var location: String = office.jurisdiction[0]
	if not Presence.present(state, person, location) or Accounts.new().location(state, person + "_cash") != location: return fail("本人及俸给收款地点尚未完成同地到任核验")
	for other in state.office_state.values():
		if other.get("holder_id") == person and other.get("status") == "appointed" and Catalog.canonical_id(str(other.office_id)) != Catalog.canonical_id(office_id): return fail("本人仍任%s，须先办理该职离任交接" % str(other.get("name", other.office_id)))
	return {"ok": true, "applicable": true, "appointment_entry": {"source_id": office.source_id, "offer_source_id": offer.source_id, "location_id": location, "consent": true}, "reason": "已核验本人协助意愿、同地到任及原职交接；任免须由本职实际权源办理"}

static func validate_offices(offices: Dictionary, characters: Dictionary) -> Dictionary:
	for id in offices:
		var office: Dictionary = offices[id]
		if office.get("office_kind") != "central" and not office.has("hierarchy_source_id"): continue
		var seen := {Catalog.canonical_id(str(id)): true}
		var parent: Variant = office.get("parent_office_id")
		if not parent is String or parent.is_empty() or not offices.has(parent) or Catalog.canonical_id(parent) != parent: return fail("中央职位缺少规范机构上级")
		while not str(parent).is_empty():
			if seen.has(parent) or not offices.has(parent): return fail("中央机构层级循环或断裂")
			seen[parent] = true
			parent = offices[parent].get("parent_office_id", "")
		if office.get("office_kind") != "central": continue
		if not str(office.get("source_id", "")).begins_with("scenario:") or not office.get("content_basis") is String or not office.get("organization_id") is String or str(office.organization_id).is_empty() or not office.get("authority_ref") is Dictionary or not office.get("required_stats") is Dictionary or office.required_stats.is_empty() or not office.get("service_offers") is Array or not office.get("jurisdiction") is Array or office.jurisdiction.size() != 1: return fail("中央职位缺少职责、实际权源或到任规则来源")
		for value in office.required_stats.values():
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)) or int(value) < 1 or int(value) > 100: return fail("中央职位才能阈值无效")
		var people := {}
		for offer in office.service_offers:
			if not offer is Dictionary or not characters.has(offer.get("character_id")) or people.has(offer.get("character_id")) or not offer.get("willing") is bool or not str(offer.get("source_id", "")).begins_with("scenario:") or typeof(offer.get("minimum_relation")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(offer.minimum_relation)) or float(offer.minimum_relation) != floor(float(offer.minimum_relation)) or int(offer.minimum_relation) < -100 or int(offer.minimum_relation) > 100: return fail("中央受职意愿缺少有效本人或来源")
			people[offer.character_id] = true
	return {"ok": true}

static func validate(raw: Dictionary) -> Dictionary:
	for office in raw.office_state.values():
		if office.get("office_kind") != "central": continue
		if not raw.get("local_node_state", {}).has(office.jurisdiction[0]): return fail("中央到任规则缺少实际地点")
		if office.get("status") == "appointed":
			var active: Array = raw.office_terms.values().filter(func(term): return term.get("office_id") == office.office_id and term.get("holder_id") == office.holder_id and int(term.get("end_day", 0)) < 0)
			if active.size() != 1: return fail("中央在任者缺少唯一实际任期")
	for term in raw.get("office_terms", {}).values():
		var office: Dictionary = raw.office_state.get(term.get("office_id"), {})
		if office.get("office_kind") != "central":
			if term.has("appointment_entry"): return fail("受职凭据指向错误职位")
			continue
		var offers: Array = office.service_offers.filter(func(offer): return offer.character_id == term.holder_id)
		if offers.size() != 1 or term.get("appointment_entry") != {"source_id": office.source_id, "offer_source_id": offers[0].source_id, "location_id": office.jurisdiction[0], "consent": true}: return fail("中央实际任期丢失本人同意及到任来源")
		var receipt: Dictionary = raw.action_receipts.get(term.get("appointment_transaction_id"), {}).get("official_record", {})
		if receipt.get("term_ref") != term.term_id or receipt.get("appointment_entry") != term.appointment_entry: return fail("中央受职缺少共同任命回执")
	return {"ok": true}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "code": "central_office_requirements"}
