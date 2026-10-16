extends RefCounted

class_name MapStatusProjection

const PREVIOUS_KEY := "map_status_previous"
const GRAIN_SOURCE_COURT_RESOURCES := "court_resources"

const ITEM_DEFINITIONS := [
	{"key": "grain", "snapshot_key": "grain", "resource_key": "grain", "label": "太仓", "positive_is_good": true},
	{"key": "treasury", "snapshot_key": "treasury", "resource_key": "treasury", "label": "国帑", "positive_is_good": true},
	{"key": "stability", "snapshot_key": "stability_score", "label": "大势", "positive_is_good": true},
	{"key": "legitimacy", "snapshot_key": "legitimacy", "resource_key": "legitimacy", "label": "统", "positive_is_good": true},
	{"key": "public_order", "snapshot_key": "public_order", "resource_key": "public_order", "label": "民", "positive_is_good": true},
	{"key": "authority", "snapshot_key": "authority", "resource_key": "court_authority", "label": "权", "positive_is_good": true},
	{"key": "faction", "snapshot_key": "faction_pressure", "label": "派压", "positive_is_good": false},
	{"key": "war", "snapshot_key": "war_threat", "label": "敌压", "positive_is_good": false},
	{"key": "stress", "snapshot_key": "emperor_stress", "label": "心神", "positive_is_good": false},
	{"key": "tasks", "snapshot_key": "tasks", "label": "待办", "positive_is_good": false}
]

func snapshot(state) -> Dictionary:
	var resources := _dictionary(_read(state, "resources", {}))
	var flags := _dictionary(_read(state, "flags", {}))
	var stress_state := _dictionary(flags.get("emperor_stress_state", {}))
	
	# 朝廷粮食指标只读现有 resources.grain。仓廪非空不得改源、相加或替代。
	var grain := _resource(resources, "grain")
	var daily_burn := 0
	var forces: Dictionary = _dictionary(_read(state, "military_forces", {}))
	for f in forces.values():
		if f is Dictionary:
			var total_troops := 0
			var tiers: Dictionary = f.get("troop_tiers", {})
			for count in tiers.values():
				total_troops += int(count)
			daily_burn += maxi(1, int(ceil(float(total_troops) * 0.02)))
			
	# 大势稳定度评分 (0-100)
	var stability_score := 70
	if grain < 5000:
		stability_score -= 30
	elif grain > 30000:
		stability_score += 10
		
	var usurped_count := 0
	var controls: Dictionary = _dictionary(_read(state, "control_relations", {}))
	for c in controls.values():
		if c is Dictionary and str(c.get("control_type", "")) == "usurped":
			usurped_count += 1
	stability_score = clampi(stability_score - usurped_count * 15, 10, 100)
	
	return {
		"grain": grain,
		"total_realm_grain": grain,
		"daily_grain_burn": daily_burn,
		"grain_source": GRAIN_SOURCE_COURT_RESOURCES,
		"treasury": _resource(resources, "treasury"),
		"stability_score": stability_score,
		"legitimacy": _resource(resources, "legitimacy"),
		"public_order": _resource(resources, "public_order"),
		"authority": _resource(resources, "court_authority"),
		"faction_pressure": _highest(_read(state, "faction_states", {}), "pressure"),
		"war_threat": _highest(_read(state, "battlefront_states", {}), "threat"),
		"emperor_stress": int(stress_state.get("stress_level", 30)),
		"tasks": _array(_read(state, "active_tasks", [])).size()
	}

func project(state) -> Dictionary:
	var profile_flags := _dictionary(_read(state, "flags", {}))
	var offices := _dictionary(_read(state, "office_state", {}))
	var player_id := str(_read(state, "player_character_id", ""))
	if profile_flags.has("start_profile_id") and str(offices.get("imperial_court", {}).get("holder_id", "")) != player_id:
		var accounts := _dictionary(_read(state, "resource_accounts", {}))
		var family_cash := 0
		var spendable := 0
		var service = preload("res://scripts/core/resource_account_service.gd").new()
		var seen := {}
		var regional: bool = offices.values().any(func(office): return office.get("office_kind") == "regional" and office.get("organization_id") == profile_flags.get("player_organization_id"))
		var authorized := false
		for account in accounts.values():
			if account.get("unit_id") != "cash_unit" or account.get("organization_id", account.owner_ref.get("entity_id")) != profile_flags.get("player_organization_id") or not account.operator_refs.any(func(ref): return ref.get("entity_id") == player_id):
				continue
			if account.owner_ref.get("entity_kind") == "office": regional = true
			authorized = true
			var source: String = account.storage_ref.storage_id + ":" + account.storage_ref.resource_key
			if seen.has(source):
				continue
			seen[source] = true
			family_cash += service.balance(state, account.account_id)
			spendable += service.available(state, account.account_id)
		var local_items := {
			"family_cash": _item("州库" if regional else "家资", family_cash, null, true),
			"personal_cash": _item("私款", state.personal_cash_balance() if state is Object and state.has_method("personal_cash_balance") else int(_dictionary(_read(state, "resources", {})).get("silver", 0)), null, true),
			"reserved_cash": _item("占用", family_cash - spendable, null, false),
			"available_cash": _item("可用", spendable, null, true)
		}
		if not authorized:
			for key in ["family_cash", "reserved_cash", "available_cash"]:
				local_items[key].value = null
				local_items[key].display = (("州库" if regional else "家资") if key == "family_cash" else ("占用" if key == "reserved_cash" else "可用")) + " 未知"
				local_items[key].tooltip = "当前无本州公账经办权，不能读取实际余额。" if regional else "当前无家族账户经办权，实际余额未获知。"
		return {"ok": true, "items": local_items}
	var current := snapshot(state)
	var previous := _previous_snapshot(state)
	var grain_baseline_ok := _grain_baseline_comparable(previous)
	var items: Dictionary = {}
	for definition in ITEM_DEFINITIONS:
		var item_definition: Dictionary = definition
		var item_key := str(item_definition.get("key", ""))
		var snapshot_key := str(item_definition.get("snapshot_key", item_key))
		var previous_value: Variant = previous.get(snapshot_key, null)
		if not grain_baseline_ok and (snapshot_key == "grain" or snapshot_key == "stability_score"):
			previous_value = null
		var item_data := _item(
			str(item_definition.get("label", item_key)),
			int(current.get(snapshot_key, 0)),
			previous_value,
			bool(item_definition.get("positive_is_good", true))
		)
		
		# 定制太仓与大势 Tooltip。不展示未证实仓储合计或未公开投影的全军日耗。
		if item_key == "grain":
			var grain_change_text: String = "尚无昨日基线"
			if _is_integer(item_data.get("delta")):
				var delta_val: int = int(item_data.get("delta"))
				if delta_val != 0:
					grain_change_text = "较昨日 %s%d 石" % ["+" if delta_val > 0 else "", delta_val]
				else:
					grain_change_text = "较昨日无变化"
			item_data["tooltip"] = "行在太仓储粮：%d 石（%s）" % [
				int(current.get("grain", 0)),
				grain_change_text
			]
		elif item_key == "stability":
			var score: int = int(current.get("stability_score", 70))
			var label_text := "大局初安"
			if score >= 80: label_text = "王道复兴"
			elif score <= 35: label_text = "危机动荡"
			elif score <= 55: label_text = "度支告匮"
			item_data["display"] = "大势 %s" % label_text
			item_data["tooltip"] = "天下大势安定度：%d/100（%s）\n点击查看天下要冲与割据总览" % [score, label_text]
			
		items[item_key] = item_data
	return {"ok": true, "items": items}

## Message coverage only. Scenario supplies identities/links, never live battle values.
func project_front_reports(fronts: Array, node_definitions: Dictionary, known_nodes: Dictionary) -> Array:
	var reports: Array = []
	for front in fronts:
		var front_id := str(front.get("id", ""))
		var region_id := str(front.get("region_id", ""))
		if region_id.is_empty():
			continue
		var evidence: Dictionary = {}
		var source_node_id := ""
		for node_key in node_definitions:
			var node: Dictionary = node_definitions[node_key]
			if region_id != str(node.get("region_id", "")):
				continue
			var node_id := str(node_key)
			var known: Dictionary = known_nodes.get(node_id, {})
			if str(known.get("status", "fog_of_war")) not in ["confirmed", "delayed", "rumor"]:
				continue
			if evidence.is_empty() or int(known.get("latency_days", 99)) < int(evidence.get("latency_days", 99)):
				evidence = known
				source_node_id = node_id
		if evidence.is_empty():
			continue
		reports.append({
			"front_id": front_id, "region": str(front.get("region", "")),
			"status": str(evidence.get("status", "delayed")),
			"latency_days": int(evidence.get("latency_days", 0)),
			"source_node_id": source_node_id,
			"intelligence_note": str(evidence.get("intelligence_note", ""))
		})
	return reports

func project_for_viewer(state, viewer_character_id: String, map_corridors: Array = []) -> Dictionary:
	var base_proj := project(state)
	var control_reports: Dictionary = preload("res://scripts/core/node_control_observation.gd").project(state,viewer_character_id)
	var routes: Dictionary = _dictionary(_read(state, "route_network_state", {}).get("routes", {}))
	var transit_corridors: Dictionary = _dictionary(_read(state, "transit_corridors", {}))
	
	var known_nodes: Dictionary = {}
	var known_corridors: Dictionary = {}
	
	# 依据观察者身份与距离判定时延与可见度
	var is_emperor: bool = (viewer_character_id == "li_heng" or viewer_character_id == "emperor_suzong" or viewer_character_id.is_empty())
	var is_isolated_scout: bool = (not is_emperor and (viewer_character_id.begins_with("probe_") or viewer_character_id.contains("isolated") or viewer_character_id.contains("scout")))
	
	known_nodes = preload("res://scripts/domain/opening_control_knowledge.gd").project(int(_read(state, "current_day", 0)),is_isolated_scout)

	# Explicit delivered observations supersede opening beliefs, keyed by target,
	# with recipient and observation date enforced by the shared report reader.
	known_nodes.merge(control_reports,true)
	# 走廊可见度投影（通畅/承压/受阻/未证实四档）
	var all_corridor_keys := {}
	for k in routes.keys():
		all_corridor_keys[str(k)] = true
	for k in transit_corridors.keys():
		all_corridor_keys[str(k)] = true
	if not all_corridor_keys.has("lingwu_to_guanzhong_relay"):
		all_corridor_keys["lingwu_to_guanzhong_relay"] = true
		
	for r_id in all_corridor_keys.keys():
		var r_data: Dictionary = routes.get(r_id, {})
		var t_data: Dictionary = transit_corridors.get(r_id, {})
		var is_blocked: bool = bool(r_data.get("is_blocked", t_data.get("is_blocked", false)))
		var sec: int = int(r_data.get("security", t_data.get("security", 50)))
		var delay: int = int(r_data.get("message_delay", t_data.get("base_travel_days", 0)))
		var threat: int = int(r_data.get("rebel_pressure", t_data.get("rebel_pressure", 0)))
		var transit_type: String = str(t_data.get("transit_type", "land"))
		
		var corridor_status := "clear"
		if is_blocked:
			corridor_status = "blocked"
		elif threat >= 60 or sec < 35:
			corridor_status = "pressured"
		elif is_isolated_scout and r_id != "lingwu_to_guanzhong_relay" and r_id != "beta07_route_02":
			corridor_status = "unconfirmed"
			
		known_corridors[r_id] = {
			"corridor_id": r_id,
			"is_blocked": is_blocked,
			"security": sec,
			"delay": delay,
			"threat": threat,
			"transit_type": transit_type,
			"status": corridor_status
		}
		
	base_proj["viewer_character_id"] = viewer_character_id
	# Known geography does not imply a current passability report.
	for corridor in map_corridors:
		var id := str(corridor.get("corridor_id", ""))
		if known_corridors.has(id):
			continue
		var from_known: Dictionary = known_nodes.get(str(corridor.get("from_node_id", "")), {})
		var to_known: Dictionary = known_nodes.get(str(corridor.get("to_node_id", "")), {})
		var geometry_known := str(from_known.get("status", "fog_of_war")) != "fog_of_war" and str(to_known.get("status", "fog_of_war")) != "fog_of_war"
		known_corridors[id] = {"corridor_id": id, "status": "unconfirmed", "geometry_known": geometry_known,
			"transit_type": str(corridor.get("transit_type", "land"))}
	base_proj["known_nodes"] = known_nodes
	base_proj["known_corridors"] = known_corridors
	base_proj.merge(preload("res://scripts/core/crossing_observation_projection.gd").project(state, viewer_character_id))
	return base_proj

func _item(label: String, value: int, previous_value: Variant, positive_is_good: bool) -> Dictionary:
	var has_baseline := _is_integer(previous_value)
	var delta: Variant = null
	var changed := false
	var severity := "neutral"
	var display := "%s %d" % [label, value]
	var tooltip := "当前值：%d。尚无昨日基线。" % value
	if has_baseline:
		delta = value - int(previous_value)
		changed = int(delta) != 0
		if changed:
			severity = _severity(int(delta), positive_is_good)
			display = "%s %d %s%d" % [label, value, "↑" if int(delta) > 0 else "↓", absi(int(delta))]
			tooltip = "当前值：%d。本日变化：%s%d。" % [value, "+" if int(delta) > 0 else "", int(delta)]
		else:
			tooltip = "当前值：%d。本日无变化。" % value
	return {
		"value": value,
		"delta": delta,
		"changed": changed,
		"severity": severity,
		"display": display,
		"tooltip": tooltip
	}

func _previous_snapshot(state) -> Dictionary:
	var flags := _dictionary(_read(state, "flags", {}))
	return _dictionary(flags.get(PREVIOUS_KEY, {})).duplicate(true)

func _grain_baseline_comparable(previous: Dictionary) -> bool:
	return str(previous.get("grain_source", "")).strip_edges() == GRAIN_SOURCE_COURT_RESOURCES

func _resource(resources: Dictionary, key: String) -> int:
	return int(resources.get(key, 0))

func _highest(states: Variant, value_key: String) -> int:
	var highest := 0
	var entries: Dictionary = _dictionary(states)
	for state_id in entries:
		var entry: Variant = entries.get(state_id, {})
		if entry is Dictionary:
			highest = maxi(highest, int(entry.get(value_key, 0)))
	return highest

func _severity(delta: int, positive_is_good: bool) -> String:
	if delta == 0:
		return "neutral"
	var improves: bool = delta > 0 if positive_is_good else delta < 0
	return "positive" if improves else "negative"

func _read(state, key: String, fallback: Variant) -> Variant:
	if state is Dictionary:
		return state.get(key, fallback)
	if state == null:
		return fallback
	var value: Variant = state.get(key)
	return fallback if value == null else value

func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _array(value: Variant) -> Array:
	return value if value is Array else []

func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))))
