extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const SOURCE := "scenario:military_grain_756"

static func initialize(state, data: Dictionary) -> Dictionary:
	var rule: Dictionary = data.get("management", {}).get("military_grain", {})
	if rule.is_empty(): return {"ok": true}
	if state.flags.has("military_grain_rules"): return Rules.fail("军粮来源已经登记")
	state.flags["military_grain_rules"] = rule.duplicate(true)
	for source in rule.forces:
		if state.military_forces.has(source.force_id): return Rules.fail("实际军队来源重复")
		var force: Dictionary = source.duplicate(true)
		force.merge({"source_id": SOURCE, "current_corridor_id": "", "target_node_id": "", "corridor_progress_days": 0, "active_directive_id": "", "supervisor_id": "", "grain_meals": [], "last_grain_day": int(state.current_day), "supply_line_active": false})
		state.military_forces[source.force_id] = force
		refresh(state, force)
	return {"ok": true}

static func troop_count(force: Dictionary) -> int:
	var total := 0
	for count in force.troop_tiers.values(): total += int(count)
	return total

static func daily_need(state, force: Dictionary) -> int:
	return int(ceil(float(troop_count(force)) / int(state.flags.military_grain_rules.troops_per_grain)))

static func refresh(state, force: Dictionary) -> void:
	var depot: Dictionary = state.depot_states[force.depot_id]
	var need := daily_need(state, force)
	# Compatibility display only: physical grain remains the sole balance.
	force["rations_on_hand_days"] = int(depot.stock.grain) / need if need > 0 else 0
	depot.location_node_id = force.current_node_id
	depot.owner_character_id = force.commander_id

static func refresh_all(state) -> void:
	for force in state.military_forces.values():
		if force.get("source_id") == SOURCE: refresh(state, force)

static func at_node(state, depot_id: String, node: String) -> bool:
	var depot: Dictionary = state.depot_states[depot_id]
	if not depot.has("military_force_id"): return depot.location_node_id == node
	var force: Dictionary = state.military_forces.get(depot.military_force_id, {})
	return force.get("current_node_id") == node and str(force.get("current_corridor_id", "")).is_empty()

static func settle_daily(state) -> Dictionary:
	if not state.flags.has("military_grain_rules"): return {"ok": true}
	for force in state.military_forces.values():
		if force.get("source_id") != SOURCE: continue
		refresh(state, force)
		if int(force.last_grain_day) >= int(state.current_day): continue
		var depot: Dictionary = state.depot_states[force.depot_id]
		var need := daily_need(state, force)
		var eaten: int = mini(need, int(depot.stock.grain))
		depot.stock.grain -= eaten
		var penalty: int = int(ceil(10.0 * (need - eaten) / need)) if need > 0 else 0
		force.morale = maxi(0, int(force.morale) - penalty)
		force.grain_meals.append({"day": int(state.current_day), "troops": troop_count(force), "required": need, "consumed": eaten, "shortfall": need - eaten, "morale_penalty": penalty})
		force.last_grain_day = int(state.current_day)
		force.supply_line_active = eaten == need and need > 0
		refresh(state, force)
	return {"ok": true}

static func consumed(raw: Dictionary, depot_id: String) -> int:
	var total := 0
	for force in raw.get("military_forces", {}).values():
		if force.get("source_id") != SOURCE or force.get("depot_id") != depot_id: continue
		for meal in force.get("grain_meals", []): total += int(meal.get("consumed", 0))
	return total

static func validate(raw: Dictionary) -> Dictionary:
	if not raw.get("military_forces", {}) is Dictionary: return Rules.fail("实际军队集合类型无效")
	for force in raw.get("military_forces", {}).values():
		if not force is Dictionary: return Rules.fail("实际军队记录类型无效")
	var rule: Variant = raw.get("flags", {}).get("military_grain_rules", {})
	if not rule is Dictionary: return Rules.fail("军粮来源类型无效")
	if rule.is_empty():
		if raw.get("military_forces", {}).values().any(func(force): return force.get("source_id") == SOURCE): return Rules.fail("军粮初始来源丢失")
		return {"ok": true}
	if rule.get("source_id") != SOURCE or not Rules.amount(rule.get("troops_per_grain"), true) or not rule.get("forces") is Array: return Rules.fail("军粮初始规则无效")
	var ids := {}
	var depots := {}
	for source in rule.forces:
		if not source is Dictionary or ids.has(source.get("force_id")) or depots.has(source.get("depot_id")): return Rules.fail("军粮主体重复或缺失")
		ids[source.get("force_id")] = true
		depots[source.get("depot_id")] = true
		var force: Dictionary = raw.get("military_forces", {}).get(source.get("force_id"), {})
		var depot: Dictionary = raw.get("depot_states", {}).get(source.get("depot_id"), {})
		if force.get("source_id") != SOURCE or force.get("depot_id") != source.depot_id or depot.get("military_force_id") != source.force_id or depot.get("location_node_id") != force.get("current_node_id") or not raw.character_states.has(force.get("commander_id")): return Rules.fail("军队实物库存缺少真实军队和地点")
		if not force.get("troop_tiers") is Dictionary or not force.get("grain_meals") is Array or not Rules.amount(force.get("last_grain_day")) or int(force.last_grain_day) > int(raw.current_day): return Rules.fail("军粮兵额或消耗履历无效")
		for count in force.troop_tiers.values():
			if not Rules.amount(count): return Rules.fail("军队兵额不能为负或小数")
		var last_day := 0
		for meal in force.grain_meals:
			if not meal is Dictionary: return Rules.fail("军粮消耗记录类型无效")
			for key in ["day", "troops", "required", "consumed", "shortfall", "morale_penalty"]:
				if not Rules.amount(meal.get(key)): return Rules.fail("军粮消耗缺少数量或日期")
			var need := int(ceil(float(meal.troops) / int(rule.troops_per_grain)))
			var penalty: int = int(ceil(10.0 * int(meal.shortfall) / need)) if need > 0 else 0
			if int(meal.day) <= last_day or int(meal.day) > int(force.last_grain_day) or meal.required != need or int(meal.consumed) > need or int(meal.shortfall) != need - int(meal.consumed) or meal.morale_penalty != penalty: return Rules.fail("军粮实际消耗与兵额和日期不符")
			last_day = int(meal.day)
		if last_day != int(force.last_grain_day): return Rules.fail("军粮最近结算日缺少履历")
		var need := int(ceil(float(troop_count(force)) / int(rule.troops_per_grain)))
		if not depot.get("stock") is Dictionary or not Rules.amount(depot.stock.get("grain")): return Rules.fail("随军实粮数量无效")
		var days_left: int = int(depot.stock.grain) / need if need > 0 else 0
		if force.get("rations_on_hand_days") != days_left: return Rules.fail("口粮天数只能由实际随军粮和兵额推导")
	for force in raw.get("military_forces", {}).values():
		if force.get("source_id") == SOURCE and not ids.has(force.get("force_id")): return Rules.fail("实际军队没有初始来源")
	return {"ok": true}
