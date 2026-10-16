extends RefCounted

class_name RuleEngine
const CashRules = preload("res://scripts/core/resource_rule_settlement.gd")

func apply_decision(state, decisions: Array, decision_id: String) -> Dictionary:
	var validation := validate_decision(state, decisions, decision_id)
	if not validation.get("ok", false):
		return validation
	var decision: Dictionary = validation.decision
	var costs: Array = decision.get("costs", [])
	var effects: Array = decision.get("effects", [])
	var snapshot_result := _capture_snapshot(state)
	if not snapshot_result.get("ok", false):
		return snapshot_result
	var snapshot: Dictionary = snapshot_result.get("snapshot", {}).duplicate(true)
	for cost in costs:
		var paid: Dictionary = state.apply_resource_delta(str(cost.get("resource", "")), int(cost.get("value", 0)), "rule:decision:" + decision_id)
		if not paid.get("ok", false): return _rollback_and_fail(state, snapshot, str(paid.get("error", "费用未能支付")))
	var effect_result := apply_effects(state, effects, "rule:decision:" + decision_id)
	if not effect_result.get("ok", false):
		return _rollback_and_fail(state, snapshot, str(effect_result.get("error", "decision effects failed")))
	return {"ok": true}

func validate_decision(state, decisions: Array, decision_id: String) -> Dictionary:
	var decision := _find_by_id(decisions, decision_id)
	if decision.is_empty():
		return _fail("unknown decision: " + decision_id)
	if state == null:
		return _fail("missing state")
	var requirements: Array = decision.get("requirements", [])
	for requirement in requirements:
		if not (requirement is Dictionary):
			return _fail("invalid decision requirement")
		if requirement.has("resource"):
			var resource_id := str(requirement.get("resource", ""))
			var current := CashRules.available(state, resource_id)
			if current < int(requirement.get("min", 0)):
				return _fail("missing resource: " + resource_id)
	var costs: Array = decision.get("costs", [])
	var cost_validation := _validate_costs(state, costs)
	if not cost_validation.get("ok", false):
		return cost_validation
	var effects: Array = decision.get("effects", [])
	var effect_validation := _validate_effects(state, effects)
	if not effect_validation.get("ok", false):
		return effect_validation
	return {"ok": true, "decision": decision.duplicate(true)}

func apply_effects(state, effects: Array, rule_ref: String = "") -> Dictionary:
	if state == null:
		return _fail("missing state")
	var validation := _validate_effects(state, effects)
	if not validation.get("ok", false):
		return validation
	var snapshot_result := _capture_snapshot(state)
	if not snapshot_result.get("ok", false): return snapshot_result
	var source := rule_ref if not rule_ref.is_empty() else "rule:configured_effects:" + JSON.stringify(effects).sha256_text()
	for effect in effects:
		var result := _apply_effect(state, effect, source)
		if not result.get("ok", false):
			return _rollback_and_fail(state, snapshot_result.snapshot, str(result.get("error", "效果无法结算")))
	return {"ok": true}

func _apply_effect(state, effect: Dictionary, rule_ref: String) -> Dictionary:
	match str(effect.get("type", "")):
		"resource_delta":
			return state.apply_resource_delta(str(effect.get("target", "")), int(effect.get("value", 0)), rule_ref)
		"relationship_delta":
			state.apply_relationship_delta(str(effect.get("target", "")), int(effect.get("value", 0)))
		"faction_delta":
			state.apply_faction_delta(str(effect.get("target", "")), str(effect.get("field", "pressure")), int(effect.get("value", 0)))
		"battlefront_delta":
			state.apply_battlefront_delta(str(effect.get("target", "")), str(effect.get("field", "threat")), int(effect.get("value", 0)))
		"battlefront_reason":
			state.set_battlefront_reason(str(effect.get("target", "")), str(effect.get("value", "")))
		"strategy_route_delta":
			state.apply_strategy_route_delta(str(effect.get("target", "")), int(effect.get("value", 0)))
		"character_memory":
			state.add_character_memory(str(effect.get("target", "")), str(effect.get("value", "")))
		"flag_set":
			state.set_flag(str(effect.get("target", "")), effect.get("value"))
		"character_birth":
			return preload("res://scripts/core/character_birth_service.gd").apply_recorded_birth(state,effect.value)
		"task_create":
			return _fail("task_create effects require EventResolutionService")
		_:
			return _fail("unknown effect type: " + str(effect.get("type", "")))
	return {"ok": true}

func _validate_costs(state, costs: Array) -> Dictionary:
	for cost in costs:
		if not (cost is Dictionary):
			return _fail("invalid decision cost")
		if not cost.has("resource") or str(cost.get("resource", "")).is_empty():
			return _fail("decision cost resource is required")
		if not state.resources.has(str(cost.get("resource", ""))) and CashRules.account_for(state, str(cost.resource)).is_empty():
			return _fail("unknown decision cost resource: " + str(cost.get("resource", "")))
		if not cost.has("value") or not _is_integer_number(cost.get("value")):
			return _fail("decision cost value must be an integer")
	return {"ok": true}

func _validate_effects(state, effects: Array) -> Dictionary:
	for effect in effects:
		if not (effect is Dictionary):
			return _fail("invalid effect")
		var effect_type := str(effect.get("type", ""))
		if not ["resource_delta", "relationship_delta", "faction_delta", "battlefront_delta", "battlefront_reason", "strategy_route_delta", "character_memory", "flag_set", "task_create", "character_birth"].has(effect_type):
			return _fail("unknown effect type: " + effect_type)
		var target := str(effect.get("target", ""))
		if target.is_empty():
			return _fail("effect target is required: " + effect_type)
		if effect_type in ["resource_delta", "relationship_delta", "faction_delta", "battlefront_delta", "strategy_route_delta"] and (not effect.has("value") or not _is_integer_number(effect.get("value"))):
			return _fail("effect value must be an integer: " + effect_type)
		if effect_type in ["battlefront_reason", "character_memory"] and (not effect.has("value") or typeof(effect.get("value")) != TYPE_STRING):
			return _fail("effect value must be a string: " + effect_type)
		if effect_type == "task_create":
			if not state.character_states.has(str(effect.get("executor_id", ""))): return _fail("unknown task executor")
			if not effect.has("duration_days") or not _is_integer_number(effect.get("duration_days")) or int(effect.get("duration_days")) < 1: return _fail("task duration_days must be a positive integer")
			if str(effect.get("source_type", "")).is_empty() or str(effect.get("risk", "")).is_empty(): return _fail("task source_type and risk are required")
		if effect_type == "character_birth":
			if not effect.get("value") is Dictionary or effect.value.get("child_id")!=target: return _fail("birth effect target must match child identity")
			var birth_validation: Dictionary = preload("res://scripts/core/character_birth_service.gd").validate_event(state,effect.value)
			if not birth_validation.ok: return birth_validation
		var target_validation := _validate_effect_target(state, effect_type, target, effect)
		if not target_validation.get("ok", false):
			return target_validation
	return {"ok": true}

func _validate_effect_target(state, effect_type: String, target: String, effect: Dictionary) -> Dictionary:
	match effect_type:
		"resource_delta":
			if not state.resources.has(target) and CashRules.account_for(state, target).is_empty(): return _fail("unknown resource target: " + target)
		"relationship_delta", "character_memory":
			if not state.character_states.has(target): return _fail("unknown character target: " + target)
		"faction_delta":
			if not state.faction_states.has(target): return _fail("unknown faction target: " + target)
			if not _has_existing_field(state.faction_states[target], str(effect.get("field", ""))): return _fail("unknown faction field")
		"battlefront_delta":
			if not state.battlefront_states.has(target): return _fail("unknown battlefront target: " + target)
			if not _has_existing_field(state.battlefront_states[target], str(effect.get("field", ""))): return _fail("unknown battlefront field")
		"battlefront_reason":
			if not state.battlefront_states.has(target): return _fail("unknown battlefront target: " + target)
		"strategy_route_delta":
			if not state.strategic_routes.has(target): return _fail("unknown strategy route target: " + target)
		"flag_set":
			if not effect.has("value"): return _fail("flag value is required")
		"task_create":
			if target.is_empty(): return _fail("task target is required")
	return {"ok": true}

func _has_existing_field(value: Variant, field: String) -> bool:
	return value is Dictionary and not field.is_empty() and value.has(field)

func _is_integer_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))))

func _capture_snapshot(state) -> Dictionary:
	if not state.has_method("to_dictionary") or not state.has_method("load_dictionary"):
		return _fail("state must support serialization")
	var serialized: Variant = state.to_transaction_dictionary() if state.has_method("to_transaction_dictionary") else state.to_dictionary()
	if not (serialized is Dictionary):
		return _fail("state serialization must return a Dictionary")
	return {"ok": true, "snapshot": serialized.duplicate(true)}

func _rollback_and_fail(state, snapshot: Dictionary, error_message: String) -> Dictionary:
	if snapshot.has("persistent") and state.has_method("load_transaction_dictionary"):
		state.load_transaction_dictionary(snapshot.duplicate(true))
	else:
		state.load_dictionary(snapshot.duplicate(true))
	return _fail(error_message)

func _find_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if item.get("id", "") == item_id:
			return item
	return {}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
