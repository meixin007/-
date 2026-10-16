extends RefCounted

class_name PoliticalSeasonRouteService

const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")
const GameStateTransactionScript = preload("res://scripts/core/game_state_transaction.gd")
const CharacterArcServiceScript = preload("res://scripts/core/character_arc_service.gd")

const COMMAND_KIND := "select_political_season_route"
const CAMPAIGN_ID := "anshi_beta_1_10"
const CAMPAIGN_SCHEMA_VERSION := 110
const SEASON_ID := "beta110_political_season"
const ROUTE_SELECTION_KIND := "political_season_route_selection"
const ROUTE_RESULT_REF_PREFIX := "political_season_route|"
const INITIALIZED_FLAG := "beta110_initialized"
const DEFAULT_UNLOCK_DAY := 31
const DEFAULT_END_DAY := 90

var _transaction = GameStateTransactionScript.new()

func project_candidates(state, data: Dictionary) -> Dictionary:
	if state == null:
		return _fail("invalid_state", "political season route projection requires state")
	if not data is Dictionary:
		return _fail("invalid_data", "political season route projection requires scenario data")
	var season := _season_definition(data)
	var routes: Array = _route_definitions(data, season)
	var candidates: Array = []
	for raw_route in routes:
		if not raw_route is Dictionary:
			continue
		var candidate_result := _authoritative_candidate(state, data, season, raw_route as Dictionary)
		if bool(candidate_result.get("ok", false)):
			candidates.append(_public_candidate(candidate_result.get("candidate", {})))
	candidates.sort_custom(func(left: Dictionary, right: Dictionary):
		return str(left.get("route_id", "")) < str(right.get("route_id", ""))
	)
	return {
		"ok": true,
		"code": "",
		"season_id": str(season.get("season_id", SEASON_ID)),
		"campaign_schema_version": CAMPAIGN_SCHEMA_VERSION,
		"current_day": int(state.current_day),
		"state_revision": int(state.state_revision),
		"candidates": candidates
	}

func preview_route(context, route_id: String) -> Dictionary:
	if context == null or context.state == null or not context.scenario_data is Dictionary:
		return _fail("invalid_context", "political season route preview requires a runtime context")
	var season := _season_definition(context.scenario_data)
	var route_result := _find_authoritative_candidate(context.state, context.scenario_data, season, route_id)
	if not bool(route_result.get("ok", false)):
		return route_result
	var candidate: Dictionary = route_result.get("candidate", {})
	var availability: Dictionary = candidate.get("availability", {}) as Dictionary
	if not bool(availability.get("available", false)):
		return _fail(str(availability.get("code", "route_unavailable")), str(availability.get("reason", "route is unavailable")))
	var rule_hash := str(candidate.get("rule_hash", ""))
	if rule_hash.is_empty():
		return _fail("rule_hash_unavailable", "route rule hash is unavailable")
	var input := {"route_id": str(candidate.get("route_id", "")), "rule_hash": rule_hash}
	var preview: Dictionary = _transaction.preview_command(context.state, COMMAND_KIND, input)
	if not bool(preview.get("ok", false)):
		return preview
	var envelope: Dictionary = _transaction.build_command_envelope(COMMAND_KIND, input, preview.get("preview_token", {}))
	return {
		"ok": true,
		"code": "preview_ready",
		"season_id": str(season.get("season_id", SEASON_ID)),
		"route": _public_candidate(candidate),
		"candidate": _public_candidate(candidate),
		"input": input.duplicate(true),
		"input_hash": str(preview.get("input_hash", "")),
		"rule_hash": rule_hash,
		"preview_token": envelope.get("preview_token", {}).duplicate(true),
		"envelope": envelope,
		"state_revision": int(context.state.state_revision)
	}

func confirm_route(context, envelope: Dictionary) -> Dictionary:
	if context == null or context.state == null or not context.scenario_data is Dictionary:
		return _fail("invalid_context", "political season route confirmation requires a runtime context")
	if not envelope is Dictionary:
		return _fail("invalid_envelope", "political season route confirmation requires an envelope")
	if str(envelope.get("kind", "")) != COMMAND_KIND:
		return _fail("unknown_command_kind", "route confirmation command kind is invalid")
	var input: Variant = envelope.get("input", null)
	if not input is Dictionary:
		return _fail("invalid_command_payload", "route confirmation input is invalid")
	var route_id := str((input as Dictionary).get("route_id", "")).strip_edges()
	var rule_hash := str((input as Dictionary).get("rule_hash", "")).strip_edges()
	if route_id.is_empty():
		return _fail("invalid_route_id", "route confirmation route ID is required")
	if rule_hash.is_empty():
		return _fail("invalid_rule_hash", "route confirmation rule hash is required")
	var selected_route_id := _selected_route_id(context.state)
	if not selected_route_id.is_empty() and selected_route_id != route_id:
		return _fail("route_already_committed", "a different political season route is already committed")
	var preview_token: Variant = envelope.get("preview_token", {})
	var transaction_id := str(envelope.get("transaction_id", ""))
	var is_known_replay: bool = context.state.processed_transactions is Dictionary and context.state.processed_transactions.has(transaction_id)
	if not is_known_replay and preview_token is Dictionary and preview_token.has("expected_state_revision") and int((preview_token as Dictionary).get("expected_state_revision", -1)) != int(context.state.state_revision):
		return _fail("stale_preview", "route preview is stale")
	if selected_route_id.is_empty():
		var current_candidate_result := _find_authoritative_candidate(context.state, context.scenario_data, _season_definition(context.scenario_data), route_id)
		if not bool(current_candidate_result.get("ok", false)):
			return current_candidate_result
		var current_candidate: Dictionary = current_candidate_result.get("candidate", {})
		var current_availability: Dictionary = current_candidate.get("availability", {}) as Dictionary
		if not bool(current_availability.get("available", false)):
			return _fail(str(current_availability.get("code", "route_unavailable")), str(current_availability.get("reason", "route is unavailable")))
		if str(current_candidate.get("rule_hash", "")) != rule_hash:
			return _fail("rule_hash_mismatch", "route rule hash does not match the authoritative definition")
	var operation := Callable(self, "_commit_route").bind(route_id, rule_hash)
	return _transaction.execute_command(context, envelope, operation)

func _commit_route(working_context, route_id: String, expected_rule_hash: String) -> Dictionary:
	var season := _season_definition(working_context.scenario_data)
	var route_result := _find_authoritative_candidate(working_context.state, working_context.scenario_data, season, route_id)
	if not bool(route_result.get("ok", false)):
		return route_result
	var candidate: Dictionary = route_result.get("candidate", {})
	var availability: Dictionary = candidate.get("availability", {}) as Dictionary
	if not bool(availability.get("available", false)):
		return _fail(str(availability.get("code", "route_unavailable")), str(availability.get("reason", "route is unavailable")))
	var actual_rule_hash := str(candidate.get("rule_hash", ""))
	if actual_rule_hash.is_empty() or actual_rule_hash != expected_rule_hash:
		return _fail("rule_hash_mismatch", "route rule hash does not match the authoritative definition")
	var current_route_id := _selected_route_id(working_context.state)
	if not current_route_id.is_empty():
		if current_route_id != route_id:
			return _fail("route_already_committed", "a different political season route is already committed")
		return {"ok": true, "code": "no_op", "result_ref": ROUTE_RESULT_REF_PREFIX + route_id}
	var next_flags: Dictionary = working_context.state.flags.duplicate(true)
	next_flags["beta110_route_id"] = route_id
	next_flags["beta110_public_route_id"] = str(candidate.get("public_route_id", route_id))
	next_flags["beta110_route_selected_day"] = int(working_context.state.current_day)
	next_flags["beta110_route_source_refs"] = (candidate.get("source_refs", []) as Array).duplicate(true)
	next_flags["beta110_route_rule_hash"] = actual_rule_hash
	working_context.state.flags = next_flags
	var next_references: Array = working_context.state.chronicle_causal_references.duplicate(true)
	for raw_reference in next_references:
		if raw_reference is Dictionary and str((raw_reference as Dictionary).get("kind", "")) == ROUTE_SELECTION_KIND:
			return _fail("route_already_committed", "a political season route selection already exists")
	next_references.append({
		"kind": ROUTE_SELECTION_KIND,
		"id": route_id,
		"route_id": route_id,
		"public_route_id": str(candidate.get("public_route_id", route_id)),
		"day": int(working_context.state.current_day),
		"source_refs": (candidate.get("source_refs", []) as Array).duplicate(true),
		"rule_hash": actual_rule_hash
	})
	working_context.state.chronicle_causal_references = next_references
	var fate_result: Dictionary = _reconcile_route_characters(working_context, route_id)
	if not bool(fate_result.get("ok", false)):
		return fate_result
	return {"ok": true, "code": "committed", "result_ref": ROUTE_RESULT_REF_PREFIX + route_id, "character_fate": fate_result.duplicate(true)}

func _reconcile_route_characters(working_context, route_id: String) -> Dictionary:
	var affected_ids := _affected_character_ids(working_context.state, working_context.scenario_data, route_id)
	if affected_ids.is_empty():
		return {"ok": true, "code": "no_op", "changed": false, "character_ids": [], "results": [], "refs": []}
	return CharacterArcServiceScript.new().reconcile_characters(working_context.state, working_context.scenario_data, affected_ids, int(working_context.state.current_day))

func _affected_character_ids(state, data: Dictionary, route_id: String) -> Array:
	var affected: Array = []
	var echoes: Variant = data.get("beta110_echoes", [])
	if echoes is Array:
		for raw_echo in echoes as Array:
			if not raw_echo is Dictionary:
				continue
			var echo: Dictionary = raw_echo as Dictionary
			var route_ids: Variant = echo.get("route_ids", [])
			if route_ids is Array and (route_ids as Array).has(route_id):
				var target_id := str(echo.get("target_character_id", "")).strip_edges()
				if not target_id.is_empty() and state.character_states.has(target_id) and not affected.has(target_id):
					affected.append(target_id)
	if affected.is_empty():
		for raw_character_id in data.get("core_character_ids", []) if data.get("core_character_ids", []) is Array else []:
			var character_id := str(raw_character_id).strip_edges()
			if not character_id.is_empty() and state.character_states.has(character_id):
				affected.append(character_id)
	affected.sort()
	return affected

func _find_authoritative_candidate(state, data: Dictionary, season: Dictionary, route_id: String) -> Dictionary:
	var normalized_route_id := route_id.strip_edges()
	if normalized_route_id.is_empty():
		return _fail("invalid_route_id", "route ID is required")
	for raw_route in _route_definitions(data, season):
		if raw_route is Dictionary and str((raw_route as Dictionary).get("route_id", "")).strip_edges() == normalized_route_id:
			return _authoritative_candidate(state, data, season, raw_route as Dictionary)
	return _fail("unknown_route", "political season route is unknown")

func _authoritative_candidate(state, data: Dictionary, season: Dictionary, route: Dictionary) -> Dictionary:
	var route_id := str(route.get("route_id", "")).strip_edges()
	if route_id.is_empty():
		return _fail("invalid_route_definition", "authored route is missing a stable route ID")
	var public_route_id := str(route.get("public_route_id", route_id)).strip_edges()
	if public_route_id.is_empty():
		public_route_id = route_id
	var authored_route := route.duplicate(true)
	authored_route["campaign_schema_version"] = CAMPAIGN_SCHEMA_VERSION
	authored_route["season_id"] = str(season.get("season_id", SEASON_ID))
	var source_refs := _source_refs(authored_route)
	var gains := _dictionary_value(authored_route.get("public_gains", authored_route.get("gains", {})))
	var costs := _dictionary_value(authored_route.get("public_costs", authored_route.get("costs", {})))
	var base_route_ids := _string_array(authored_route.get("base_route_ids", []))
	var prerequisites := {
		"campaign_id": CAMPAIGN_ID,
		"initialized_flag": INITIALIZED_FLAG,
		"base_route_ids": base_route_ids.duplicate(true)
	}
	var availability := _availability(state, data, season, route_id, prerequisites)
	var steps: Array = authored_route.get("steps", []) as Array if authored_route.get("steps", []) is Array else []
	var settlement_inputs := {
		"route_id": route_id,
		"public_route_id": public_route_id,
		"gains": gains.duplicate(true),
		"costs": costs.duplicate(true),
		"base_route_ids": base_route_ids.duplicate(true),
		"steps": steps.duplicate(true),
		"outcome_weights": _dictionary_value(authored_route.get("outcome_weights", {}))
	}
	var rule_payload := {
		"campaign_schema_version": CAMPAIGN_SCHEMA_VERSION,
		"season_id": str(season.get("season_id", SEASON_ID)),
		"route_definition": authored_route.duplicate(true),
		"evaluated_prerequisites": availability.duplicate(true),
		"source_refs": source_refs.duplicate(true),
		"settlement_inputs": settlement_inputs.duplicate(true)
	}
	var hash_result: Dictionary = CanonicalJSONScript.hash_value(rule_payload)
	if not bool(hash_result.get("ok", false)):
		return _fail("rule_hash_unavailable", "authoritative route rule payload is not canonical")
	var candidate := {
		"route_id": route_id,
		"public_route_id": public_route_id,
		"label": str(authored_route.get("label", public_route_id)),
		"public_summary": str(authored_route.get("public_summary", authored_route.get("summary", ""))),
		"gains": gains.duplicate(true),
		"costs": costs.duplicate(true),
		"prerequisites": prerequisites.duplicate(true),
		"availability": availability.duplicate(true),
		"source_refs": source_refs.duplicate(true),
		"rule_hash": str(hash_result.get("hash", "")),
		"authoritative_definition": authored_route.duplicate(true),
		"settlement_inputs": settlement_inputs.duplicate(true)
	}
	return {"ok": true, "candidate": candidate}

func _public_candidate(candidate: Variant) -> Dictionary:
	if not candidate is Dictionary:
		return {}
	var public_candidate: Dictionary = (candidate as Dictionary).duplicate(true)
	for key in ["authoritative_definition", "settlement_inputs"]:
		public_candidate.erase(key)
	return public_candidate

func _availability(state, data: Dictionary, season: Dictionary, route_id: String, prerequisites: Dictionary) -> Dictionary:
	var day := int(state.current_day) if state != null else -1
	var unlock_day := int(season.get("freeze_before_day", DEFAULT_UNLOCK_DAY))
	var end_day := int(season.get("end_day", DEFAULT_END_DAY))
	var flags: Dictionary = state.flags if state != null and state.flags is Dictionary else {}
	var campaign_matches := str(flags.get("campaign_id", data.get("campaign_id", ""))) == CAMPAIGN_ID
	var initialized := bool(flags.get(INITIALIZED_FLAG, false))
	var selected_route_id := str(flags.get("beta110_route_id", "")).strip_edges()
	var available := true
	var code := "available"
	var reason := "route is available"
	if not campaign_matches or not initialized:
		available = false
		code = "prerequisite_missing"
		reason = "BETA 1.10 campaign prerequisites are not satisfied"
	elif not selected_route_id.is_empty():
		available = false
		code = "route_already_committed"
		reason = "a political season route is already committed"
	elif day < unlock_day:
		available = false
		code = "route_unavailable"
		reason = "political season routes unlock on day %d" % unlock_day
	elif day > end_day:
		available = false
		code = "route_expired"
		reason = "political season route selection has expired"
	return {
		"available": available,
		"code": code,
		"reason": reason,
		"current_day": day,
		"unlock_day": unlock_day,
		"end_day": end_day,
		"campaign_id": CAMPAIGN_ID,
		"prerequisites": prerequisites.duplicate(true)
	}

func _season_definition(data: Dictionary) -> Dictionary:
	var raw_season: Variant = data.get("political_season", {})
	if raw_season is Dictionary:
		var season: Dictionary = (raw_season as Dictionary).duplicate(true)
		if not season.has("season_id"):
			season["season_id"] = SEASON_ID
		return season
	return {
		"season_id": SEASON_ID,
		"schema_version": CAMPAIGN_SCHEMA_VERSION,
		"freeze_before_day": DEFAULT_UNLOCK_DAY,
		"end_day": DEFAULT_END_DAY,
		"routes": (data.get("beta110_routes", []) as Array).duplicate(true) if data.get("beta110_routes", []) is Array else []
	}

func _route_definitions(data: Dictionary, season: Dictionary) -> Array:
	var routes: Variant = season.get("routes", null)
	if routes is Array:
		return (routes as Array).duplicate(true)
	if data.get("beta110_routes", []) is Array:
		return (data.get("beta110_routes", []) as Array).duplicate(true)
	return []

func _source_refs(route: Dictionary) -> Array:
	var refs: Array = []
	for key in ["source_refs", "source_paths"]:
		for raw_ref in _string_array(route.get(key, [])):
			if not refs.has(raw_ref):
				refs.append(raw_ref)
	var steps: Variant = route.get("steps", [])
	if steps is Array:
		for raw_step in steps as Array:
			if not raw_step is Dictionary:
				continue
			for key in ["source_refs", "source_paths"]:
				for raw_ref in _string_array((raw_step as Dictionary).get(key, [])):
					if not refs.has(raw_ref):
						refs.append(raw_ref)
	refs.sort()
	return refs

func _selected_route_id(state) -> String:
	if state == null or not state.flags is Dictionary:
		return ""
	return str(state.flags.get("beta110_route_id", "")).strip_edges()

func _dictionary_value(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _string_array(value: Variant) -> Array:
	var result: Array = []
	if value is String:
		if not str(value).strip_edges().is_empty():
			result.append(str(value).strip_edges())
		return result
	if not value is Array:
		return result
	for raw_value in value as Array:
		var normalized := str(raw_value).strip_edges()
		if not normalized.is_empty() and not result.has(normalized):
			result.append(normalized)
	return result

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
