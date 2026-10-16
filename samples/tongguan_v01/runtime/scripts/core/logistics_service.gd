# scripts/core/logistics_service.gd
extends RefCounted

class_name LogisticsService

const CorridorReader = preload("res://scripts/core/runtime_corridor_reader.gd")

const DepotStateScript = preload("res://scripts/core/depot_state.gd")
const TransitCorridorStateScript = preload("res://scripts/core/transit_corridor_state.gd")
const ControlRelationStateScript = preload("res://scripts/core/control_relation_state.gd")
const ObedienceRelationStateScript = preload("res://scripts/core/obedience_relation_state.gd")
const TerrainRuleServiceScript = preload("res://scripts/domain/terrain_rule_service.gd")

func _is_account_storage(state, depot_id: String, commodity: String = "") -> bool:
	if state.depot_states.get(depot_id, {}).get("source_id") == "scenario:regional_grain_756": return true
	for account in state.resource_accounts.values():
		var ref: Dictionary = account.get("storage_ref", {})
		if ref.get("storage_id") == depot_id and (commodity.is_empty() or ref.get("resource_key") == commodity):
			return true
	return false

func _account_storage_error() -> Dictionary:
	return {"ok": false, "code": "account_transaction_required", "error": "账户库存必须通过带来源与预留校验的账户事务办理。"}

func get_depot(state, depot_id: String) -> Dictionary:
	if state == null or not state.depot_states.has(depot_id):
		return {}
	return state.depot_states[depot_id]

func create_or_update_depot(state, depot_data: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	var depot_id := str(depot_data.get("depot_id", "")).strip_edges()
	if depot_id.is_empty():
		return {"ok": false, "error": "missing depot_id"}
	if _is_account_storage(state, depot_id):
		return _account_storage_error()
	var depot_obj = DepotStateScript.from_dict(depot_data)
	state.depot_states[depot_id] = depot_obj.to_dict()
	
	var owner_id := str(depot_data.get("owner_character_id", ""))
	if not owner_id.is_empty():
		set_depot_control(state, depot_id, owner_id, "de_jure", 100)
	return {"ok": true, "depot_id": depot_id, "depot": state.depot_states[depot_id]}

func set_depot_control(state, depot_id: String, controller_id: String, control_type: String = "de_jure", strength: int = 100) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	if _is_account_storage(state, depot_id):
		return _account_storage_error()
	var ctrl_id := "ctrl|depot|%s" % depot_id
	var ctrl := ControlRelationStateScript.new()
	ctrl.control_id = ctrl_id
	ctrl.target_type = "depot"
	ctrl.target_id = depot_id
	ctrl.controller_id = controller_id
	ctrl.strength = strength
	ctrl.control_type = control_type
	state.control_relations[ctrl_id] = ctrl.to_dict()
	
	if state.depot_states.has(depot_id):
		var d: Dictionary = (state.depot_states[depot_id] as Dictionary).duplicate(true)
		d["owner_character_id"] = controller_id
		state.depot_states[depot_id] = d
	return {"ok": true, "control_id": ctrl_id, "control": ctrl.to_dict()}

func set_depot_stock(state, depot_id: String, commodity: String, amount: int) -> Dictionary:
	if state == null or not state.depot_states.has(depot_id):
		return {"ok": false, "error": "depot not found: " + depot_id}
	if _is_account_storage(state, depot_id, commodity):
		return _account_storage_error()
	var depot_dict: Dictionary = (state.depot_states[depot_id] as Dictionary).duplicate(true)
	var stock: Dictionary = (depot_dict.get("stock", {}) as Dictionary).duplicate(true)
	var new_val := maxi(0, amount)
	stock[commodity] = new_val
	depot_dict["stock"] = stock
	state.depot_states[depot_id] = depot_dict
	return {"ok": true, "depot_id": depot_id, "commodity": commodity, "new_amount": new_val}

func add_depot_stock(state, depot_id: String, commodity: String, amount: int) -> Dictionary:
	if state == null or not state.depot_states.has(depot_id):
		return {"ok": false, "error": "depot not found: " + depot_id}
	if _is_account_storage(state, depot_id, commodity):
		return _account_storage_error()
	var depot_dict: Dictionary = (state.depot_states[depot_id] as Dictionary).duplicate(true)
	var stock: Dictionary = (depot_dict.get("stock", {}) as Dictionary).duplicate(true)
	var cur_val: int = int(stock.get(commodity, 0))
	var new_val := maxi(0, cur_val + amount)
	stock[commodity] = new_val
	depot_dict["stock"] = stock
	state.depot_states[depot_id] = depot_dict
	return {"ok": true, "depot_id": depot_id, "commodity": commodity, "new_amount": new_val, "delta": amount}

func consume_depot_stock(state, depot_id: String, commodity: String, amount: int) -> Dictionary:
	if state == null or not state.depot_states.has(depot_id):
		return {"ok": false, "error": "depot not found: " + depot_id}
	if _is_account_storage(state, depot_id, commodity):
		return _account_storage_error()
	var depot_dict: Dictionary = (state.depot_states[depot_id] as Dictionary).duplicate(true)
	var stock: Dictionary = (depot_dict.get("stock", {}) as Dictionary).duplicate(true)
	var cur_val: int = int(stock.get(commodity, 0))
	if cur_val < amount:
		return {"ok": false, "code": "insufficient_stock", "available": cur_val, "requested": amount}
	var new_val := cur_val - amount
	stock[commodity] = new_val
	depot_dict["stock"] = stock
	state.depot_states[depot_id] = depot_dict
	return {"ok": true, "depot_id": depot_id, "commodity": commodity, "new_amount": new_val, "consumed": amount}

func can_requisition(state, depot_id: String, actor_id: String) -> Dictionary:
	if state == null or not state.depot_states.has(depot_id):
		return {"ok": false, "can_requisition": false, "reason": "府库不存在"}
	if actor_id.is_empty():
		return {"ok": false, "can_requisition": false, "reason": "调拨主体未知"}
	if state.depot_states[depot_id].get("source_id") == "scenario:regional_grain_756":
		var permitted: bool = load("res://scripts/core/regional_grain_service.gd").authority(state, depot_id, actor_id)
		return {"ok": permitted, "can_requisition": permitted, "reason": "按地方仓廪实控与当前御前权源核验", "basis": "actual_depot_authority"}
		
	var ctrl_id := "ctrl|depot|%s" % depot_id
	var controller_id := ""
	var raw_controller: Variant = null
	var control_type := "de_jure"
	var strength := 100
	if state.control_relations.has(ctrl_id):
		var ctrl: Dictionary = state.control_relations[ctrl_id]
		raw_controller = ctrl.get("controller_id", "")
		control_type = str(ctrl.get("control_type", "de_jure"))
		strength = int(ctrl.get("strength", 100))
	else:
		var d: Dictionary = state.depot_states[depot_id]
		raw_controller = d.get("owner_character_id", "")
	controller_id = raw_controller.strip_edges() if raw_controller is String else ""
	if controller_id.is_empty():
		return {"ok": false, "can_requisition": false, "reason": "该仓实控人不明，不能征调。"}
	
	# 1. 直接实控人
	if controller_id == actor_id:
		return {"ok": true, "can_requisition": true, "basis": "direct_controller", "authority_level": "absolute"}
	
	# 2. 玩家为君主/主政者时的法定征调
	var sovereign: bool = actor_id == str(state.player_character_id) or actor_id == "li_heng"
	if state.flags.get("campaign_id") == "anshi_beta_1_14":
		var court: Dictionary = state.office_state.get("imperial_court", {})
		sovereign = court.get("status") == "appointed" and court.get("holder_id") == actor_id
	if sovereign:
		if control_type == "usurped" or control_type == "disputed":
			return {"ok": false, "can_requisition": false, "reason": "该仓已为藩镇或叛军实控僭据，朝命难达"}
		# 检查管库官吏服从度
		var obed_id := "obed|%s|%s|all" % [controller_id, actor_id]
		if state.obedience_relations.has(obed_id):
			var o: Dictionary = state.obedience_relations[obed_id]
			if int(o.get("strength", 80)) < 40:
				return {"ok": false, "can_requisition": false, "reason": "守库官员阳奉阴违，抗拒调拨"}
		return {"ok": true, "can_requisition": true, "basis": "imperial_mandate", "authority_level": "sovereign"}
	
	# 3. 组织服从链征调
	var sub_obed_id := "obed|%s|%s|military" % [controller_id, actor_id]
	var all_obed_id := "obed|%s|%s|all" % [controller_id, actor_id]
	if state.obedience_relations.has(sub_obed_id):
		var o: Dictionary = state.obedience_relations[sub_obed_id]
		if int(o.get("strength", 0)) >= 50:
			return {"ok": true, "can_requisition": true, "basis": "military_subordination", "authority_level": "command"}
	elif state.obedience_relations.has(all_obed_id):
		var o: Dictionary = state.obedience_relations[all_obed_id]
		if int(o.get("strength", 0)) >= 50:
			return {"ok": true, "can_requisition": true, "basis": "general_subordination", "authority_level": "command"}
	
	return {"ok": false, "can_requisition": false, "reason": "调拨者对该府库无直接实控权或下属服从关系"}

func requisition_stock(state, depot_id: String, actor_id: String, requested_stock: Dictionary) -> Dictionary:
	var check := can_requisition(state, depot_id, actor_id)
	if not bool(check.get("can_requisition", false)):
		return {"ok": false, "code": "requisition_denied", "reason": check.get("reason", "权限不足")}
	
	var depot: Dictionary = (state.depot_states[depot_id] as Dictionary).duplicate(true)
	var stock: Dictionary = (depot.get("stock", {}) as Dictionary).duplicate(true)
	
	var actual_obtained := {}
	for commodity in requested_stock.keys():
		if _is_account_storage(state, depot_id, str(commodity)):
			return _account_storage_error()
		var req := int(requested_stock[commodity])
		var avail := int(stock.get(commodity, 0))
		if avail < req:
			return {"ok": false, "code": "insufficient_stock", "commodity": commodity, "available": avail, "requested": req}
	
	for commodity in requested_stock.keys():
		var req := int(requested_stock[commodity])
		stock[commodity] = int(stock.get(commodity, 0)) - req
		actual_obtained[commodity] = req
		
	depot["stock"] = stock
	state.depot_states[depot_id] = depot
	
	state.chronicle_causal_references.append({
		"kind": "depot_requisition",
		"depot_id": depot_id,
		"actor_id": actor_id,
		"obtained": actual_obtained.duplicate(true),
		"day": int(state.current_day)
	})
	return {"ok": true, "depot_id": depot_id, "actor_id": actor_id, "obtained": actual_obtained}

## Transport reads only the existing same-world transit_corridors collection.
func get_corridor(state, corridor_id: String) -> Dictionary:
	return CorridorReader.transport_route(state, corridor_id)

func is_corridor_passable(state, corridor_id: String, viewer_faction: String = "") -> Dictionary:
	if state == null or not state.transit_corridors.has(corridor_id):
		return {"ok": false, "is_passable": false, "reason": "走廊不存在"}
	var corr: Dictionary = get_corridor(state, corridor_id)
	var passage: Dictionary = CorridorReader.passage(state, corr)
	if not passage.is_passable:
		passage["ok"] = true
		return passage
		
	var from_id: String = str(corr.get("from_node_id", ""))
	var to_id: String = str(corr.get("to_node_id", ""))
	
	# 检查端点节点是否被敌对阵营控制
	if not viewer_faction.is_empty():
		if state.strategic_nodes.has(from_id):
			var n_from: Dictionary = state.strategic_nodes[from_id]
			var f_from := str(n_from.get("control_faction_id", ""))
			if f_from != "" and f_from != viewer_faction:
				return {"ok": true, "is_passable": false, "reason": "节点 %s 处于敌对阵营控制下" % from_id}
		if state.strategic_nodes.has(to_id):
			var n_to: Dictionary = state.strategic_nodes[to_id]
			var f_to := str(n_to.get("control_faction_id", ""))
			if f_to != "" and f_to != viewer_faction:
				return {"ok": true, "is_passable": false, "reason": "节点 %s 处于敌对阵营控制下" % to_id}
				
	if passage.get("reason_code", "") == "wet_road":
		passage["ok"] = true
		return passage
	return {"ok": true, "is_passable": true, "reason": "粮道通畅"}

func find_supply_route(state, from_node_id: String, to_node_id: String, faction_id: String = "") -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	if from_node_id == to_node_id:
		return {"ok": true, "corridor_ids": [], "total_days": 0, "total_loss_rate": 0.0}
		
	var queue: Array[Dictionary] = [{"node": from_node_id, "path": [], "days": 0, "loss": 0.0}]
	var visited := {from_node_id: true}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var curr_node: String = current["node"]
		var curr_path: Array = current["path"]
		var curr_days: int = current["days"]
		var curr_loss: float = current["loss"]
		
		if curr_node == to_node_id:
			return {
				"ok": true,
				"corridor_ids": curr_path,
				"total_days": curr_days,
				"total_loss_rate": curr_loss
			}
			
		for c_id in state.transit_corridors.keys():
			var corr: Dictionary = get_corridor(state, c_id)
			var from_id: String = str(corr.get("from_node_id", ""))
			var to_id: String = str(corr.get("to_node_id", ""))
			
			var next_node := ""
			if from_id == curr_node:
				next_node = to_id
			elif to_id == curr_node:
				next_node = from_id
				
			if next_node != "" and not visited.has(next_node):
				var pass_check := is_corridor_passable(state, c_id, faction_id)
				if bool(pass_check.get("is_passable", false)):
					visited[next_node] = true
					var next_path = curr_path.duplicate()
					next_path.append(c_id)
					var b_days := CorridorReader.current_condition_travel_days(state, corr, 5)
					var l_rate := float(corr.get("loss_rate_per_day", 0.002)) * float(b_days)
					queue.append({
						"node": next_node,
						"path": next_path,
						"days": curr_days + b_days,
						"loss": curr_loss + l_rate
					})
					
	return {"ok": false, "error": "no_passable_route"}

## Public transfer intent: caller supplies actor and faction explicitly.
func plan_depot_transfer(state, source_id: String, target_id: String, actor_id: String, faction_id: String) -> Dictionary:
	if state == null or not state.depot_states.has(source_id):
		return {"ok": false, "error": "暂无可调拨仓廪。"}
	if not state.depot_states.has(target_id):
		return {"ok": false, "error": "请选择已有接收仓廪，地点本身不能入库。"}
	if actor_id.is_empty() or faction_id.is_empty():
		return {"ok": false, "error": "调拨主体与所属阵营尚不明确。"}
	for depot_id in [source_id, target_id]:
		var authority := can_requisition(state, depot_id, actor_id)
		if not bool(authority.get("can_requisition", false)):
			return {"ok": false, "error": "无权调拨所选仓廪：" + str(authority.get("reason", "权限不足"))}
	var source_node := str(state.depot_states[source_id].get("location_node_id", ""))
	var target_node := str(state.depot_states[target_id].get("location_node_id", ""))
	if source_node.is_empty() or target_node.is_empty():
		return {"ok": false, "error": "仓廪位置尚不明确，暂不能签发调拨。"}
	if source_node == target_node:
		return {"ok": false, "error": "两仓位于同一地点，无需发遣运输队。"}
	var route := find_supply_route(state, source_node, target_node, faction_id)
	if not bool(route.get("ok", false)):
		return {"ok": false, "error": "尚未找到可用粮道，暂不能签发调拨。"}
	var ids: Array = route.get("corridor_ids", [])
	if ids.size() != 1:
		return {"ok": false, "error": "该目的地需要中转，暂不能签发直达调拨；请选择有直达粮道的仓廪。"}
	return {"ok": true, "source_id": source_id, "target_id": target_id, "corridor_id": str(ids[0]), "route": route}

func dispatch_depot_transfer(state, source_id: String, target_id: String, actor_id: String, faction_id: String, grain_amount: int) -> Dictionary:
	var plan := plan_depot_transfer(state, source_id, target_id, actor_id, faction_id)
	if not bool(plan.get("ok", false)):
		return plan
	return dispatch_grain_transport(state, source_id, target_id, "depot", str(plan.corridor_id), grain_amount)

## Low-level rule operation; player/NPC intents use dispatch_depot_transfer for authority.
func dispatch_grain_transport(state, from_depot_id: String, target_id: String, target_type: String, corridor_id: String, grain_amount: int, escort_force_id: String = "") -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	if not state.depot_states.has(from_depot_id):
		return {"ok": false, "error": "source depot not found: " + from_depot_id}
	if not state.transit_corridors.has(corridor_id):
		return {"ok": false, "error": "corridor not found: " + corridor_id}
	if grain_amount <= 0:
		return {"ok": false, "error": "grain amount must be positive"}
		
	var endpoint_check := _validate_transport_endpoints(state, from_depot_id, target_id, target_type, corridor_id)
	if not bool(endpoint_check.get("ok", false)):
		return endpoint_check
	var passage := is_corridor_passable(state, corridor_id)
	if not bool(passage.get("is_passable", false)):
		return {"ok": false, "error": str(passage.get("reason", "粮道当前不可通行。"))}

	var consume_res := consume_depot_stock(state, from_depot_id, "grain", grain_amount)
	if not bool(consume_res.get("ok", false)):
		return consume_res
		
	var corr: Dictionary = get_corridor(state, corridor_id)
	var base_days: int = int(corr.get("base_travel_days", 5))
	var loss_rate: float = float(corr.get("loss_rate_per_day", 0.002))
	
	var transport_id := "transport|%s|%s|%d" % [from_depot_id, target_id, int(state.current_day)]
	var transport_rec := {
		"transport_id": transport_id,
		"from_depot_id": from_depot_id,
		"target_id": target_id,
		"target_type": target_type,
		"corridor_id": corridor_id,
		"initial_grain": grain_amount,
		"current_grain": grain_amount,
		"remaining_days": base_days,
		"total_days": base_days,
		"loss_rate_per_day": loss_rate,
		"escort_force_id": escort_force_id,
		"status": "in_transit",
		"start_day": int(state.current_day)
	}
	state.grain_transports.append(transport_rec)
	return {"ok": true, "transport_id": transport_id, "transport": transport_rec}

func _validate_transport_endpoints(state, source_id: String, target_id: String, target_type: String, corridor_id: String) -> Dictionary:
	if target_type == "force" and state.military_forces.get(target_id, {}).get("source_id") == "scenario:military_grain_756": return {"ok": false, "error": "实际军粮须通过共同调令送达随军粮库存，不能补写口粮天数。"}
	if not state.depot_states.has(source_id):
		return {"ok": false, "error": "出库仓廪已不存在。"}
	var corridor := get_corridor(state, corridor_id)
	if corridor.is_empty():
		return {"ok": false, "error": "在途粮道记录缺失，不能继续结算。"}
	var target_node := ""
	if target_type == "depot" and state.depot_states.has(target_id):
		target_node = str(state.depot_states[target_id].get("location_node_id", ""))
	elif target_type == "force" and state.military_forces.has(target_id):
		target_node = str(state.military_forces[target_id].get("current_node_id", ""))
	else:
		return {"ok": false, "error": "缺少明确的收粮对象；请选择已有接收仓廪。"}
	var source_node := str(state.depot_states[source_id].get("location_node_id", ""))
	var from_node := str(corridor.get("from_node_id", ""))
	var to_node := str(corridor.get("to_node_id", ""))
	if source_node.is_empty() or target_node.is_empty() or source_node == target_node or not ((source_node == from_node and target_node == to_node) or (source_node == to_node and target_node == from_node)):
		return {"ok": false, "error": "所选粮道不能从出库仓廪直达收粮对象。"}
	return {"ok": true}

func _existing_force_left_corridor(state, source_id: String, target_id: String, target_type: String, corridor_id: String) -> bool:
	if target_type != "force":
		return false
	if state == null or not state.military_forces.has(target_id) or not state.depot_states.has(source_id):
		return false
	var corridor := get_corridor(state, corridor_id)
	if corridor.is_empty():
		return false
	var source_node := str(state.depot_states[source_id].get("location_node_id", ""))
	var force_node := str(state.military_forces[target_id].get("current_node_id", ""))
	var from_node := str(corridor.get("from_node_id", ""))
	var to_node := str(corridor.get("to_node_id", ""))
	if source_node.is_empty() or force_node.is_empty() or from_node.is_empty() or to_node.is_empty() or from_node == to_node:
		return false
	var source_on_from := source_node == from_node
	var source_on_to := source_node == to_node
	if not source_on_from and not source_on_to:
		return false
	var opposite := to_node if source_on_from else from_node
	return force_node != opposite

## The formal coordinator already advanced the shared date. Never advance time here.
func settle_daily_transports(state) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	return advance_grain_transports_daily(state, 1, int(state.current_day))

func _transport_due(transport: Dictionary, settlement_day: int) -> bool:
	if transport.get("transport_kind") == "regional_grain": return false
	if str(transport.get("status", "")) not in ["in_transit", "waiting_crossing", "waiting_snow"]:
		return false
	return settlement_day < 0 or int(transport.get("last_advanced_day", transport.get("start_day", -1))) < settlement_day

func advance_grain_transports_daily(state, days: int = 1, settlement_day: int = -1) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	if days <= 0 or (settlement_day >= 0 and days != 1):
		return {"ok": false, "error": "transport day count must be positive; formal settlement advances one day"}
	# Validate the complete due batch before any stock, convoy or marker mutation.
	for raw in state.grain_transports:
		if not (raw is Dictionary):
			return {"ok": false, "error": "invalid transport record"}
		if not _transport_due(raw, settlement_day):
			continue
		var progress: Variant = raw.get("surface_progress_quarters", 0)
		if not (progress is int or progress is float) or not is_finite(float(progress)) or float(progress)!=floor(float(progress)) or progress<0 or progress>3:
			return {"ok":false,"error":"invalid fractional transport progress"}
		if days != 1 and state.flags.has("road_surface_events") and str(raw.get("corridor_id","")) == "c_fengxiang_liangzhou":
			return {"ok":false,"error":"weather-dependent trips require daily settlement"}
		var validated := _validate_transport_endpoints(state, str(raw.get("from_depot_id", "")), str(raw.get("target_id", "")), str(raw.get("target_type", "depot")), str(raw.get("corridor_id", "")))
		if not bool(validated.get("ok", false)):
			if not _existing_force_left_corridor(state, str(raw.get("from_depot_id", "")), str(raw.get("target_id", "")), str(raw.get("target_type", "depot")), str(raw.get("corridor_id", ""))):
				return validated
		if int(raw.get("current_grain", 0)) < 0 or float(raw.get("loss_rate_per_day", 0.002)) < 0.0:
			return {"ok": false, "error": "invalid transport grain or loss"}
	var active_transports: Array = []
	var completed_transports: Array = []
	var intercepted_transports: Array = []
	var waiting_transports: Array = []
	
	for raw_t in state.grain_transports:
		var t: Dictionary = (raw_t as Dictionary).duplicate(true)
		if not _transport_due(t, settlement_day):
			active_transports.append(t)
			continue
			
		var corr_id: String = str(t.get("corridor_id", ""))
		var corr: Dictionary = get_corridor(state, corr_id)
		
		if settlement_day >= 0:
			t["last_advanced_day"] = settlement_day

		# 检查走廊是否在途被阻断或伏击
		var passage: Dictionary = CorridorReader.passage(state, corr)
		if not passage.is_passable:
			t["status"] = "waiting_crossing" if passage.reason_code == "high_water" else "blocked"
			if passage.reason_code == "snow_blocked":t["status"] = "waiting_snow"
			t["blocking_reason"] = passage.reason
			if passage.reason_code in ["high_water", "snow_blocked"]:
				waiting_transports.append(t)
			else:
				intercepted_transports.append(t)
			active_transports.append(t)
			continue
		if str(t.get("status", "")) in ["waiting_crossing", "waiting_snow"]:
			t["status"] = "in_transit"
			t.erase("blocking_reason")
		# 签发后仍存在的部队离开对岸端点：保留余粮并停止推进，不改道、不另选接收者。
		if _existing_force_left_corridor(state, str(t.get("from_depot_id", "")), str(t.get("target_id", "")), str(t.get("target_type", "depot")), corr_id):
			t["status"] = "blocked"
			intercepted_transports.append(t)
			active_transports.append(t)
			continue
			
		var cur_grain: int = int(t.get("current_grain", 0))
		var l_rate: float = float(t.get("loss_rate_per_day", 0.002))
		var ttype: String = str(corr.get("transit_type", "land"))
		var terrain_type := "plains"
		if ttype == "mountain_pass" or ttype == "pass":
			terrain_type = "mountains"
		elif ttype == "desert":
			terrain_type = "desert_gobi"
		elif ttype == "river":
			terrain_type = "marsh_waterway"
		var terrain_mult: float = float(TerrainRuleServiceScript.TERRAIN_CONFIGS.get(terrain_type, {}).get("supply_attrition_mult", 1.0))
		var daily_loss := int(ceil(float(cur_grain) * l_rate * terrain_mult * float(days)))
		cur_grain = maxi(0, cur_grain - daily_loss)
		t["current_grain"] = cur_grain
		
		var quarters: int = int(t.get("surface_progress_quarters",0)) + int(passage.get("speed_quarters",4))*days
		var advanced_days: int = quarters / 4
		if quarters%4 != 0:t["surface_progress_quarters"] = quarters%4
		else:t.erase("surface_progress_quarters")
		var rem_days: int = int(t.get("remaining_days", 0)) - advanced_days
		t["remaining_days"] = rem_days
		
		if rem_days <= 0:
			t["status"] = "delivered"
			t["remaining_days"] = 0
			t.erase("surface_progress_quarters")
			var tgt_type: String = str(t.get("target_type", "depot"))
			var tgt_id: String = str(t.get("target_id", ""))
			
			if tgt_type == "depot" and state.depot_states.has(tgt_id):
				add_depot_stock(state, tgt_id, "grain", cur_grain)
			elif tgt_type == "force" and state.military_forces.has(tgt_id):
				var force_dict: Dictionary = (state.military_forces[tgt_id] as Dictionary).duplicate(true)
				var cur_r: int = int(force_dict.get("rations_on_hand_days", 0))
				force_dict["rations_on_hand_days"] = maxi(cur_r, 25)
				force_dict["supply_line_active"] = true
				state.military_forces[tgt_id] = force_dict
				
			completed_transports.append(t)
		active_transports.append(t)
		
	state.grain_transports = active_transports
	return {
		"ok": true,
		"completed_count": completed_transports.size(),
		"completed": completed_transports,
		"waiting_count": waiting_transports.size(),
		"waiting": waiting_transports,
		"intercepted_count": intercepted_transports.size(),
		"intercepted": intercepted_transports
	}

func settle_daily_force_logistics(state, days: int = 1) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
		
	var reports: Array[Dictionary] = []
	var starving_forces: Array[String] = []
	var routed_forces: Array[String] = []
	
	for force_id in state.military_forces.keys():
		var force: Dictionary = (state.military_forces[force_id] as Dictionary).duplicate(true)
		if force.get("source_id") == "scenario:military_grain_756": continue
		var faction_id: String = str(force.get("faction_id", ""))
		var cur_node: String = str(force.get("current_node_id", ""))
		var cur_corr: String = str(force.get("current_corridor_id", ""))
		
		# 寻找就近或连通府库
		var supplied := false
		var grain_consumed := 0
		var daily_burn := 50 * days
		
		# 1. 优先本地府库
		var local_depot_id := ""
		for d_id in state.depot_states.keys():
			var d: Dictionary = state.depot_states[d_id]
			if str(d.get("location_node_id", "")) == cur_node:
				local_depot_id = d_id
				break
				
		if not local_depot_id.is_empty():
			var req_res := can_requisition(state, local_depot_id, str(force.get("commander_id", "")))
			if bool(req_res.get("can_requisition", false)):
				var consume_res := consume_depot_stock(state, local_depot_id, "grain", daily_burn)
				if bool(consume_res.get("ok", false)):
					supplied = true
					grain_consumed = daily_burn
					force["rations_on_hand_days"] = maxi(int(force.get("rations_on_hand_days", 0)), 20)
					force["supply_line_active"] = true
					
		# 2. 若本地无仓，尝试粮道连通后方仓廪
		if not supplied and cur_corr.is_empty() and not cur_node.is_empty():
			for d_id in state.depot_states.keys():
				var d: Dictionary = state.depot_states[d_id]
				var d_node := str(d.get("location_node_id", ""))
				var route := find_supply_route(state, d_node, cur_node, faction_id)
				if bool(route.get("ok", false)):
					var loss_rate: float = float(route.get("total_loss_rate", 0.0))
					var total_needed := int(ceil(float(daily_burn) * (1.0 + loss_rate)))
					var consume_res := consume_depot_stock(state, d_id, "grain", total_needed)
					if bool(consume_res.get("ok", false)):
						supplied = true
						grain_consumed = total_needed
						force["rations_on_hand_days"] = maxi(int(force.get("rations_on_hand_days", 0)), 15)
						force["supply_line_active"] = true
						break
						
		# 3. 粮道断绝，消耗随军干粮
		if not supplied:
			force["supply_line_active"] = false
			var cur_rations: int = int(force.get("rations_on_hand_days", 0))
			var new_rations := maxi(0, cur_rations - days)
			force["rations_on_hand_days"] = new_rations
			
			if new_rations == 0:
				starving_forces.append(force_id)
				var cur_morale: int = int(force.get("morale", 80))
				var new_morale := maxi(0, cur_morale - 10 * days)
				force["morale"] = new_morale
				
				# 阶层化逃兵：乡勇团练逃亡最快，亲军牙兵最具韧性
				var tiers: Dictionary = (force.get("troop_tiers", {}) as Dictionary).duplicate(true)
				var desertion_rates := {
					"local_militia": 0.08 * float(days),
					"regular_field": 0.05 * float(days),
					"foreign_cavalry": 0.04 * float(days),
					"elite_retinue": 0.02 * float(days)
				}
				for t_key in tiers.keys():
					var cnt: int = int(tiers[t_key])
					if cnt > 0:
						var lost := int(ceil(float(cnt) * float(desertion_rates.get(t_key, 0.05))))
						tiers[t_key] = maxi(0, cnt - lost)
				force["troop_tiers"] = tiers
				
				if new_morale < 20:
					routed_forces.append(force_id)
					force["is_routed"] = true
					reports.append({
						"force_id": force_id,
						"display_name": str(force.get("display_name", force_id)),
						"status": "routed",
						"text": "%s 粮尽兵哗，军心瓦解溃散！" % str(force.get("display_name", force_id))
					})
				else:
					reports.append({
						"force_id": force_id,
						"display_name": str(force.get("display_name", force_id)),
						"status": "starving",
						"text": "%s 断粮缺饷，发生逃亡减员，士气跌至 %d。" % [str(force.get("display_name", force_id)), new_morale]
					})
					
		state.military_forces[force_id] = force
		
	return {
		"ok": true,
		"starving_count": starving_forces.size(),
		"starving_forces": starving_forces,
		"routed_count": routed_forces.size(),
		"routed_forces": routed_forces,
		"reports": reports
	}
