# scripts/core/military_campaign_service.gd
extends RefCounted

class_name MilitaryCampaignService

const TIER_COMBAT_WEIGHTS := {
	"elite_retinue": 2.0,
	"foreign_cavalry": 1.8,
	"regular_field": 1.2,
	"local_militia": 0.6
}

func _get_val(obj: Variant, field: String, default_val: Variant = null) -> Variant:
	if obj == null:
		return default_val
	if obj is Dictionary:
		return obj.get(field, default_val)
	if obj is Object:
		var val = obj.get(field)
		return val if val != null else default_val
	return default_val

func _set_val(obj: Variant, field: String, val: Variant) -> void:
	if obj == null:
		return
	if obj is Dictionary:
		obj[field] = val
	elif obj is Object:
		obj.set(field, val)

func advance_force_movement(force: Variant, corridor: Variant, days: int) -> Dictionary:
	if force == null or corridor == null:
		return {"ok": false, "error": "invalid arguments"}
	if bool(_get_val(corridor, "is_blocked", false)):
		return {
			"ok": true,
			"arrived": false,
			"blocked": true,
			"reason": str(_get_val(corridor, "blocking_reason", "")),
			"progress_days": int(_get_val(force, "corridor_progress_days", 0))
		}
	
	_set_val(force, "current_corridor_id", str(_get_val(corridor, "corridor_id", "")))
	var new_progress: int = int(_get_val(force, "corridor_progress_days", 0)) + days
	_set_val(force, "corridor_progress_days", new_progress)
	
	var base_days: int = int(_get_val(corridor, "base_travel_days", 5))
	if new_progress >= base_days:
		var from_id: String = str(_get_val(corridor, "from_node_id", ""))
		var to_id: String = str(_get_val(corridor, "to_node_id", ""))
		var cur_id: String = str(_get_val(force, "current_node_id", ""))
		var target: String = to_id if cur_id == from_id else from_id
		
		_set_val(force, "current_node_id", target)
		_set_val(force, "target_node_id", "")
		_set_val(force, "current_corridor_id", "")
		_set_val(force, "corridor_progress_days", 0)
		return {
			"ok": true,
			"arrived": true,
			"node_id": target,
			"blocked": false
		}
	
	return {
		"ok": true,
		"arrived": false,
		"blocked": false,
		"progress_days": new_progress,
		"total_days": base_days
	}

func settle_daily_logistics(force: Variant, depot: Variant, corridor: Variant, daily_consumption: int = 50) -> Dictionary:
	if _get_val(force, "source_id", "") == "scenario:military_grain_756": return {"ok": false, "error": "实际军粮由共同日结从随军实粮扣除，不能补写口粮天数。"}
	if force == null:
		return {"ok": false, "error": "missing force"}
	
	var loss_rate: float = float(_get_val(corridor, "loss_rate_per_day", 0.002)) if corridor != null else 0.002
	var required_grain := int(ceil(float(daily_consumption) * (1.0 + loss_rate)))
	var supplied := false
	var loss_amount := 0
	
	var supply_active: bool = bool(_get_val(force, "supply_line_active", true))
	if supply_active and depot != null:
		if depot is Object and (depot as Object).has_method("consume_stock") and (depot as Object).call("consume_stock", "grain", required_grain):
			supplied = true
			loss_amount = int(ceil(float(daily_consumption) * loss_rate))
			var cur_rations: int = int(_get_val(force, "rations_on_hand_days", 0))
			_set_val(force, "rations_on_hand_days", maxi(cur_rations, 15))
	
	if not supplied:
		var cur_rations: int = int(_get_val(force, "rations_on_hand_days", 0))
		var new_rations: int = maxi(0, cur_rations - 1)
		_set_val(force, "rations_on_hand_days", new_rations)
		if new_rations <= 0:
			var cur_morale: int = int(_get_val(force, "morale", 80))
			var new_morale: int = maxi(0, cur_morale - 10)
			_set_val(force, "morale", new_morale)
			
			var tiers: Dictionary = _get_val(force, "troop_tiers", {})
			for tier in tiers.keys():
				var count := int(tiers[tier])
				if count > 0:
					var desertion := maxi(1, int(float(count) * 0.05))
					tiers[tier] = maxi(0, count - desertion)
			_set_val(force, "troop_tiers", tiers)
			
			return {
				"ok": true,
				"supplied": false,
				"starving": true,
				"morale": new_morale,
				"rations_left": 0
			}
	
	return {
		"ok": true,
		"supplied": supplied,
		"starving": false,
		"morale": int(_get_val(force, "morale", 80)),
		"grain_consumed": daily_consumption,
		"grain_lost_in_transit": loss_amount,
		"rations_left": int(_get_val(force, "rations_on_hand_days", 0))
	}

func resolve_engagement(
	attacker_force: Variant,
	attacker_profile: Dictionary,
	attacker_directive: Variant,
	defender_force: Variant,
	defender_profile: Dictionary,
	defender_directive: Variant,
	node: Variant,
	rng_seed: int = 42
) -> Dictionary:
	if attacker_force == null or defender_force == null:
		return {"ok": false, "error": "missing combat forces"}
	
	var attacker_power := _calc_combat_power(attacker_force, attacker_profile, attacker_directive, false, node)
	var defender_power := _calc_combat_power(defender_force, defender_profile, defender_directive, true, node)
	
	# 战术事件生成
	var tactical_events: Array[String] = []
	var attacker_mil := int(attacker_profile.get("military", 50))
	var defender_mil := int(defender_profile.get("military", 50))
	var attacker_boldness := int(attacker_profile.get("boldness", 0))
	
	if attacker_mil >= 80:
		tactical_events.append("进攻方主帅调度得当，前军阵型严整。")
	if defender_mil >= 80 and node != null and bool(_get_val(node, "is_pass", false)):
		tactical_events.append("防守方依托险隘深沟高垒，箭石齐发封锁要道。")
	if attacker_boldness >= 50:
		tactical_events.append("进攻方悍然发起决死冲锋，前锋精锐突入敌阵。")
	elif attacker_boldness <= -30:
		tactical_events.append("进攻方主帅持重谨慎，先以弓弩压制，未急于合围。")

	var total_power := attacker_power + defender_power
	if total_power <= 0:
		total_power = 1.0
	
	var attacker_win_prob := attacker_power / total_power
	var pseudo_rand := _deterministic_ratio(rng_seed, 100) / 100.0
	var attacker_won := pseudo_rand < attacker_win_prob
	
	var attacker_loss_ratio := 0.15 if attacker_won else 0.35
	var defender_loss_ratio := 0.35 if attacker_won else 0.15
	
	if node != null and bool(_get_val(node, "is_pass", false)):
		attacker_loss_ratio += 0.10
		defender_loss_ratio -= 0.05
	
	var attacker_casualties := _apply_casualties(attacker_force, attacker_loss_ratio)
	var defender_casualties := _apply_casualties(defender_force, defender_loss_ratio)
	
	var att_morale: int = int(_get_val(attacker_force, "morale", 80))
	var def_morale: int = int(_get_val(defender_force, "morale", 80))
	
	if attacker_won:
		_set_val(attacker_force, "morale", mini(100, att_morale + 10))
		_set_val(defender_force, "morale", maxi(0, def_morale - 25))
		if node != null:
			# Current campaign local nodes own dominant_faction; legacy strategic
			# nodes own control_faction_id. Update their existing authority field.
			var control_field := "dominant_faction" if node is Dictionary and node.has("dominant_faction") else "control_faction_id"
			_set_val(node, control_field, str(_get_val(attacker_force, "faction_id", "")))
	else:
		_set_val(attacker_force, "morale", maxi(0, att_morale - 25))
		_set_val(defender_force, "morale", mini(100, def_morale + 10))
	
	var att_total: int = _get_force_total(attacker_force)
	var def_total: int = _get_force_total(defender_force)
	
	var receipt := {
		"ok": true,
		"winner_force_id": str(_get_val(attacker_force, "force_id", "")) if attacker_won else str(_get_val(defender_force, "force_id", "")),
		"loser_force_id": str(_get_val(defender_force, "force_id", "")) if attacker_won else str(_get_val(attacker_force, "force_id", "")),
		"attacker_casualties": attacker_casualties,
		"defender_casualties": defender_casualties,
		"attacker_total_remaining": att_total,
		"defender_total_remaining": def_total,
		"tactical_events": tactical_events,
		"node_captured": attacker_won and node != null,
		"node_id": str(_get_val(node, "node_id", "")) if node != null else ""
	}
	return receipt

func _calc_combat_power(force: Variant, profile: Dictionary, directive: Variant, is_defender: bool, node: Variant) -> float:
	var base_power := 0.0
	var tiers: Dictionary = _get_val(force, "troop_tiers", {})
	for tier in tiers.keys():
		var count := int(tiers[tier])
		var weight := float(TIER_COMBAT_WEIGHTS.get(tier, 1.0))
		base_power += float(count) * weight
	
	var military_skill := float(profile.get("military", 50))
	var prowess_skill := float(profile.get("prowess", 50))
	var skill_multiplier := 0.5 + (military_skill * 0.007) + (prowess_skill * 0.003)
	
	var morale_val: int = int(_get_val(force, "morale", 80))
	var morale_multiplier := float(morale_val) / 80.0
	
	var directive_bonus := 1.0
	if directive != null:
		var dtype := str(_get_val(directive, "directive_type", ""))
		if dtype == "defend_pass" and is_defender and node != null and bool(_get_val(node, "is_pass", false)):
			directive_bonus = 1.45
		elif dtype == "decisive_assault" and not is_defender:
			directive_bonus = 1.25
		elif dtype == "flank_harass":
			directive_bonus = 1.10
	
	var terrain_bonus := 1.0
	if is_defender and node != null:
		var def_level: int = int(_get_val(node, "defense_level", 50))
		terrain_bonus += float(def_level) * 0.005
		if bool(_get_val(node, "is_pass", false)):
			terrain_bonus += 0.35
	
	return base_power * skill_multiplier * morale_multiplier * directive_bonus * terrain_bonus

func _apply_casualties(force: Variant, ratio: float) -> int:
	var total_lost := 0
	var tiers: Dictionary = _get_val(force, "troop_tiers", {})
	for tier in tiers.keys():
		var current_count := int(tiers[tier])
		if current_count > 0:
			var lost := int(ceil(float(current_count) * ratio))
			lost = mini(current_count, lost)
			tiers[tier] = current_count - lost
			total_lost += lost
	_set_val(force, "troop_tiers", tiers)
	return total_lost

func _get_force_total(force: Variant) -> int:
	if force is Object and (force as Object).has_method("get_total_troops"):
		return int((force as Object).call("get_total_troops"))
	var total := 0
	var tiers: Dictionary = _get_val(force, "troop_tiers", {})
	for count in tiers.values():
		total += int(count)
	return total

func _deterministic_ratio(seed_val: int, modulo: int) -> int:
	var val := (seed_val * 1103515245 + 12345) & 0x7fffffff
	return val % modulo

func issue_strategic_directive(state, directive_data: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	var target_force_id := str(directive_data.get("target_force_id", "")).strip_edges()
	if target_force_id.is_empty() or not state.military_forces.has(target_force_id):
		return {"ok": false, "error": "target force not found: " + target_force_id}
		
	var force: Dictionary = (state.military_forces[target_force_id] as Dictionary).duplicate(true)
	var commander_id: String = str(force.get("commander_id", ""))
	var issuer_id: String = str(directive_data.get("issuer_id", state.player_character_id))
	var directive_type: String = str(directive_data.get("directive_type", "defend_pass"))
	
	# 检查将领服从度
	var obed_id := "obed|%s|%s|military" % [commander_id, issuer_id]
	var all_obed_id := "obed|%s|%s|all" % [commander_id, issuer_id]
	var obed_strength := 80
	if state.obedience_relations.has(obed_id):
		obed_strength = int(state.obedience_relations[obed_id].get("strength", 80))
	elif state.obedience_relations.has(all_obed_id):
		obed_strength = int(state.obedience_relations[all_obed_id].get("strength", 80))
		
	var directive_id := str(directive_data.get("directive_id", ""))
	if directive_id.is_empty():
		directive_id = "dir|%s|%s|%d" % [issuer_id, target_force_id, int(state.current_day)]
		
	if obed_strength < 40 and directive_type == "decisive_assault":
		state.chronicle_causal_references.append({
			"kind": "directive_defied",
			"directive_id": directive_id,
			"commander_id": commander_id,
			"issuer_id": issuer_id,
			"day": int(state.current_day)
		})
		return {
			"ok": false,
			"code": "directive_defied",
			"reason": "将帅以孤军深入势危为由抗辩，不奉躁进决战之命",
			"commander_id": commander_id,
			"obedience_strength": obed_strength
		}
		
	var directive_dict := {
		"directive_id": directive_id,
		"issuer_id": issuer_id,
		"target_force_id": target_force_id,
		"directive_type": directive_type,
		"primary_target_node_id": str(directive_data.get("primary_target_node_id", "")),
		"discretion_level": str(directive_data.get("discretion_level", "strict")),
		"allocated_rations": int(directive_data.get("allocated_rations", 0)),
		"allocated_horses": int(directive_data.get("allocated_horses", 0)),
		"is_active": true,
		"issued_day": int(state.current_day)
	}
	if not state.get("strategic_directives") is Dictionary:
		state.strategic_directives = {}
	state.strategic_directives[directive_id] = directive_dict
	
	force["active_directive_id"] = directive_id
	state.military_forces[target_force_id] = force
	
	state.chronicle_causal_references.append({
		"kind": "directive_issued",
		"directive_id": directive_id,
		"target_force_id": target_force_id,
		"directive_type": directive_type,
		"day": int(state.current_day)
	})
	return {"ok": true, "directive_id": directive_id, "directive": directive_dict}

func get_active_directive(state, force_id: String) -> Dictionary:
	if state == null or not state.military_forces.has(force_id):
		return {}
	var force: Dictionary = state.military_forces[force_id]
	var dir_id: String = str(force.get("active_directive_id", ""))
	if dir_id.is_empty() or not state.get("strategic_directives") is Dictionary or not state.strategic_directives.has(dir_id):
		return {}
	return state.strategic_directives[dir_id]

func cancel_directive(state, directive_id: String) -> Dictionary:
	if state == null or not state.get("strategic_directives") is Dictionary or not state.strategic_directives.has(directive_id):
		return {"ok": false, "error": "directive not found: " + directive_id}
	var dir: Dictionary = (state.strategic_directives[directive_id] as Dictionary).duplicate(true)
	dir["is_active"] = false
	state.strategic_directives[directive_id] = dir
	
	var target_force_id: String = str(dir.get("target_force_id", ""))
	if state.military_forces.has(target_force_id):
		var force: Dictionary = (state.military_forces[target_force_id] as Dictionary).duplicate(true)
		if str(force.get("active_directive_id", "")) == directive_id:
			force["active_directive_id"] = ""
			state.military_forces[target_force_id] = force
			
	return {"ok": true, "directive_id": directive_id, "status": "cancelled"}
