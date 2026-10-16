extends RefCounted

class_name CharacterKnowledgeService

const CLAIM_STATUSES := ["confirmed", "estimated", "rumor"]
const ABILITY_FIELDS := ["military", "governance", "finance", "intrigue", "diplomacy", "prowess"]
const TRAIT_FIELDS := ["traits", "suspected_traits"]
const TEXT_FIELDS := ["hidden_goal", "public_title", "command_style"]
const MAX_ID_LENGTH := 64
const MAX_TEXT_LENGTH := 512
const MAX_TRAIT_LENGTH := 128
const MAX_TRAITS := 16
const MAX_CLAIMS_PER_FIELD := 16
const MAX_GENERIC_DEPTH := 4
const MAX_GENERIC_NODES := 64
const PUBLIC_FATE_REASON_KINDS := ["route", "case", "office", "review", "chronicle"]
const PUBLIC_FATE_TARGET_KINDS := ["case", "office", "review", "chronicle"]
const PUBLIC_FATE_CATEGORIES := ["gained_position", "constrained", "paid_cost"]
const PUBLIC_FATE_GENERIC_REASON := "当前依据不足，需通过调查或复盘确认"
const PUBLIC_FATE_BROKEN_REASON := "相关记录暂不可读取"
const MAX_PUBLIC_FATE_REASONS := 3
const MAX_PUBLIC_FATE_TRANSITIONS := 5

# This adapter references only knowledge and IDs; it owns no world facts.
class ObserverView extends RefCounted:
	var character_states: Dictionary = {}
	var character_knowledge: Dictionary = {}

func record_observer_claim(state, observer_id: String, character_id: String, field_id: String, claim: Dictionary) -> Dictionary:
	if state == null or not state.character_states.has(observer_id): return _fail("unknown observer")
	if observer_id == state.player_character_id: return record_claim(state, character_id, field_id, claim)
	var view := ObserverView.new()
	view.character_states = state.character_states
	view.character_knowledge = state.observer_character_knowledge.get(observer_id, {}).duplicate(true)
	var result := record_claim(view, character_id, field_id, claim)
	if result.get("ok", false): state.observer_character_knowledge[observer_id] = view.character_knowledge.duplicate(true)
	return result

func get_observer_field(state, observer_id: String, character_id: String, field_id: String) -> Dictionary:
	if state == null or not state.character_states.has(observer_id): return _unknown_field()
	if observer_id == state.player_character_id: return get_visible_field(state, character_id, field_id)
	var view := ObserverView.new()
	view.character_states = state.character_states
	view.character_knowledge = state.observer_character_knowledge.get(observer_id, {})
	return get_visible_field(view, character_id, field_id)

static func validate_observers(raw: Dictionary) -> Dictionary:
	var observers: Variant = raw.get("observer_character_knowledge", {})
	if not observers is Dictionary: return _fail_static("invalid observer knowledge")
	var ids: Array = raw.get("character_states", {}).keys()
	for observer in observers:
		if not ids.has(observer) or observer == raw.get("player_character_id") or not observers[observer] is Dictionary: return _fail_static("invalid observer identity or duplicated player knowledge")
		var canonical = load("res://scripts/core/canonical_json.gd")
		var original: Dictionary = canonical.hash_value(observers[observer])
		var normalized: Dictionary = canonical.hash_value(normalize_saved_knowledge(observers[observer], ids))
		if not original.get("ok", false) or not normalized.get("ok", false) or original.hash != normalized.hash: return _fail_static("invalid observer claim; load would discard knowledge")
	return {"ok": true}

func record_claim(state, character_id: Variant, field_id: Variant, claim: Variant) -> Dictionary:
	var request_error := _validate_state_request(state, character_id, field_id)
	if request_error != "":
		return _fail(request_error)
	var normalized_result := normalize_claim(field_id, claim)
	if not normalized_result.get("ok", false):
		return normalized_result
	var current_character = state.character_knowledge.get(character_id, {})
	if not (current_character is Dictionary):
		return _fail("character knowledge entry must be a dictionary")
	var current_field = current_character.get(field_id, {})
	if not (current_field is Dictionary):
		return _fail("field knowledge entry must be a dictionary")
	var current_claims = current_field.get("claims", [])
	if not (current_claims is Array):
		return _fail("field claims must be an array")
	var normalized_existing := _normalize_claim_list(field_id, current_claims, true)
	if not normalized_existing.get("ok", false):
		return _fail("existing claims must be valid safe claims")
	var claims: Array = normalized_existing.get("claims", [])
	var copied_claim: Dictionary = normalized_result.get("claim", {}).duplicate(true)
	var existing_index := _find_source_index(claims, copied_claim.source_id)
	if existing_index >= 0 and int(copied_claim.acquired_day) < int(claims[existing_index].get("acquired_day", 0)):
		return _fail("older same-source claim cannot replace newer knowledge")
	if existing_index < 0 and claims.size() >= MAX_CLAIMS_PER_FIELD:
		return _fail("field claim source limit reached")
	if existing_index >= 0:
		claims[existing_index] = copied_claim
	else:
		claims.append(copied_claim)
	claims.sort_custom(_claim_source_less)
	var field_entry := {"claims": claims, "visible": derive_visible(claims)}
	var next_knowledge: Dictionary = state.character_knowledge.duplicate(false)
	var next_character: Dictionary = current_character.duplicate(false)
	next_character[field_id] = field_entry
	next_knowledge[character_id] = next_character
	state.character_knowledge = next_knowledge
	return {"ok": true, "field": field_entry.visible.duplicate(true)}

func get_visible_field(state, character_id: Variant, field_id: Variant) -> Dictionary:
	if _validate_state_request(state, character_id, field_id) != "":
		return _unknown_field()
	var character_entry = state.character_knowledge.get(character_id, {})
	if not (character_entry is Dictionary):
		return _unknown_field()
	var field_entry = character_entry.get(field_id, {})
	if not (field_entry is Dictionary):
		return _unknown_field()
	var claims = field_entry.get("claims", [])
	if not (claims is Array):
		return _unknown_field()
	var normalized := _normalize_claim_list(field_id, claims, false)
	if normalized.get("claims", []).is_empty():
		return _unknown_field()
	return derive_visible(normalized.claims).duplicate(true)

func get_conflicts(state, character_id: Variant, field_id: Variant) -> Array:
	if _validate_state_request(state, character_id, field_id) != "":
		return []
	var character_entry = state.character_knowledge.get(character_id, {})
	if not (character_entry is Dictionary):
		return []
	var field_entry = character_entry.get(field_id, {})
	if not (field_entry is Dictionary) or not (field_entry.get("claims", []) is Array):
		return []
	var normalized := _normalize_claim_list(field_id, field_entry.get("claims", []), false)
	return _build_conflicts(normalized.get("claims", [])).duplicate(true)

func suggest_discovery_routes(state, character_id: Variant, field_id: Variant) -> Array:
	var visible := get_visible_field(state, character_id, field_id)
	var status := str(visible.get("status", "unknown"))
	if status == "conflicting":
		return ["direct_dialogue", "ask_third_party", "intelligence_report", "long_observation"]
	if status == "unknown":
		if _is_ability_field(field_id) or field_id in TRAIT_FIELDS:
			return ["direct_dialogue", "ask_third_party", "long_observation"]
		return ["direct_dialogue", "ask_third_party", "intelligence_report"]
	if status == "rumor":
		return ["ask_third_party", "intelligence_report", "long_observation"]
	if status == "estimated":
		return ["direct_dialogue", "intelligence_report", "long_observation"]
	return ["long_observation"]

func project_public_fate_reasons(state, data: Dictionary, character_id: String, fate_record: Variant) -> Dictionary:
	var raw_reason_refs: Variant = fate_record.get("reason_refs", []) if fate_record is Dictionary else []
	var reason_refs: Array = raw_reason_refs if raw_reason_refs is Array else []
	var reasons: Array = []
	var saw_hidden_or_unknown := false
	var saw_broken := false
	for raw_reason_ref in reason_refs:
		if reasons.size() >= MAX_PUBLIC_FATE_REASONS:
			break
		if not raw_reason_ref is Dictionary:
			saw_hidden_or_unknown = true
			continue
		var reason_ref: Dictionary = raw_reason_ref as Dictionary
		var kind := str(reason_ref.get("kind", "")).strip_edges()
		var reason_id := str(reason_ref.get("id", "")).strip_edges()
		if not PUBLIC_FATE_TARGET_KINDS.has(kind) and kind != "route":
			saw_hidden_or_unknown = true
			continue
		if reason_id.is_empty() or _is_hidden_public_record(reason_ref):
			saw_hidden_or_unknown = true
			continue
		var resolved: Dictionary = _resolve_public_fate_reason(state, data, character_id, kind, reason_id)
		var status := str(resolved.get("status", "broken"))
		if status == "resolved":
			var projected: Dictionary = resolved.get("reason", {}) if resolved.get("reason", {}) is Dictionary else {}
			var target: Dictionary = projected.get("target", {}) if projected.get("target", {}) is Dictionary else {}
			var identity := str(target.get("kind", "")) + "|" + str(target.get("id", ""))
			var duplicate := false
			for existing in reasons:
				if existing is Dictionary:
					var existing_target: Dictionary = (existing as Dictionary).get("target", {}) if (existing as Dictionary).get("target", {}) is Dictionary else {}
					if str(existing_target.get("kind", "")) + "|" + str(existing_target.get("id", "")) == identity:
						duplicate = true
						break
			if not duplicate and not projected.is_empty():
				reasons.append(projected.duplicate(true))
		elif status == "hidden":
			saw_hidden_or_unknown = true
		else:
			saw_broken = true
	if reasons.is_empty():
		var fallback := PUBLIC_FATE_GENERIC_REASON if saw_hidden_or_unknown or not saw_broken else PUBLIC_FATE_BROKEN_REASON
		return {"ok": true, "reasons": [{"summary": fallback}], "has_public_evidence": false}
	return {"ok": true, "reasons": reasons.slice(0, MAX_PUBLIC_FATE_REASONS), "has_public_evidence": true}

static func normalize_claim(field_id: Variant, claim: Variant) -> Dictionary:
	var field_error := _validate_id(field_id, "field_id")
	if field_error != "":
		return _fail_static(field_error)
	if not (claim is Dictionary):
		return _fail_static("claim must be a dictionary")
	var status_value = claim.get("status")
	if typeof(status_value) != TYPE_STRING or not CLAIM_STATUSES.has(status_value):
		return _fail_static("unsupported claim status")
	var source_error := _validate_id(claim.get("source_id"), "source_id")
	if source_error != "":
		return _fail_static(source_error)
	var acquired_day: Variant = claim.get("acquired_day")
	# JSON numbers are floats. Accept exact integral days, not fractions,
	# booleans, strings, infinities or values outside signed integer range.
	if typeof(acquired_day)==TYPE_FLOAT and is_finite(acquired_day) and acquired_day>=0.0 and acquired_day<9223372036854775808.0 and acquired_day==floor(acquired_day):
		acquired_day = int(acquired_day)
	if typeof(acquired_day) != TYPE_INT or acquired_day < 0:
		return _fail_static("acquired_day must be a non-negative integer")
	var confidence_value = claim.get("confidence")
	if typeof(confidence_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail_static("confidence must be numeric")
	var confidence := float(confidence_value)
	if not is_finite(confidence) or confidence < 0.0 or confidence > 1.0:
		return _fail_static("confidence must be finite and within 0..1")
	var payload_result: Dictionary
	if _is_ability_field(field_id):
		payload_result = _normalize_ability_payload(status_value, claim)
	elif field_id in TRAIT_FIELDS:
		payload_result = _normalize_trait_payload(status_value, claim)
	elif field_id in TEXT_FIELDS:
		payload_result = _normalize_text_payload(status_value, claim)
	else:
		payload_result = _normalize_generic_payload(status_value, claim)
	if not payload_result.get("ok", false):
		return payload_result
	var normalized := {
		"status": status_value,
		"source_id": claim.get("source_id"),
		"acquired_day": acquired_day,
		"confidence": confidence
	}
	for key in payload_result.get("payload", {}).keys():
		normalized[key] = payload_result.payload[key]
	return {"ok": true, "claim": normalized}

static func normalize_saved_knowledge(value: Variant, valid_character_ids: Array) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var normalized: Dictionary = {}
	var character_keys: Array = []
	for raw_character_id in value.keys():
		if typeof(raw_character_id) == TYPE_STRING:
			character_keys.append(raw_character_id)
	character_keys.sort()
	for character_id in character_keys:
		if _validate_id(character_id, "character_id") != "" or not valid_character_ids.has(character_id):
			continue
		var character_value = value.get(character_id)
		if not (character_value is Dictionary):
			continue
		var normalized_character: Dictionary = {}
		var field_keys: Array = []
		for raw_field_id in character_value.keys():
			if typeof(raw_field_id) == TYPE_STRING:
				field_keys.append(raw_field_id)
		field_keys.sort()
		for field_id in field_keys:
			if _validate_id(field_id, "field_id") != "":
				continue
			var field_value = character_value.get(field_id)
			if not (field_value is Dictionary) or not (field_value.get("claims", []) is Array):
				continue
			var normalized_claims := _normalize_claim_list(field_id, field_value.get("claims", []), false)
			var claims: Array = normalized_claims.get("claims", [])
			if claims.is_empty():
				continue
			normalized_character[field_id] = {"claims": claims, "visible": derive_visible(claims)}
		if not normalized_character.is_empty():
			normalized[character_id] = normalized_character
	return normalized

static func derive_visible(claims: Array) -> Dictionary:
	if claims.is_empty():
		return _unknown_field_static()
	var source_ids: Array = []
	var rumor_source_ids: Array = []
	var confirmed: Array = []
	var estimated: Array = []
	var rumors: Array = []
	var latest_day := 0
	for claim_value in claims:
		if not (claim_value is Dictionary):
			continue
		var claim: Dictionary = claim_value
		var source_id := str(claim.get("source_id", ""))
		if source_id != "" and not source_ids.has(source_id):
			source_ids.append(source_id)
		latest_day = maxi(latest_day, int(claim.get("acquired_day", 0)))
		match str(claim.get("status", "")):
			"confirmed": confirmed.append(claim)
			"estimated": estimated.append(claim)
			"rumor":
				rumors.append(claim)
				if source_id != "" and not rumor_source_ids.has(source_id):
					rumor_source_ids.append(source_id)
	source_ids.sort()
	rumor_source_ids.sort()
	var conflicts := _build_conflicts(claims)
	var primary: Array = rumors
	var status := "rumor"
	if not confirmed.is_empty():
		primary = confirmed
		status = "conflicting" if not conflicts.is_empty() else "confirmed"
	elif not estimated.is_empty():
		primary = estimated
		status = "conflicting" if not conflicts.is_empty() else "estimated"
	var summary := {
		"status": status,
		"source_ids": source_ids,
		"confidence": _mean_confidence(primary),
		"latest_acquired_day": latest_day
	}
	if not rumors.is_empty() and status != "rumor":
		summary["caveat_source_ids"] = rumor_source_ids
	if not confirmed.is_empty():
		summary["value"] = _copy_safe_value(confirmed[0].get("value"))
	elif not estimated.is_empty():
		_add_range_summary(summary, estimated)
	elif not rumors.is_empty():
		var range_rumors: Array = []
		for rumor in rumors:
			if rumor.has("min") and rumor.has("max"):
				range_rumors.append(rumor)
		if not range_rumors.is_empty():
			_add_range_summary(summary, range_rumors)
		else:
			var latest_rumor: Dictionary = _latest_claim(rumors)
			if latest_rumor.has("value"):
				summary["value"] = _copy_safe_value(latest_rumor.get("value"))
	return summary

static func _normalize_ability_payload(status: String, claim: Dictionary) -> Dictionary:
	if status == "confirmed":
		var allowed_error := _validate_claim_keys(claim, ["status", "source_id", "acquired_day", "confidence", "value"])
		if allowed_error != "":
			return _fail_static(allowed_error)
		var value = claim.get("value")
		if not _is_finite_number(value) or float(value) < 0.0 or float(value) > 100.0:
			return _fail_static("confirmed ability requires a finite numeric value within 0..100")
		return {"ok": true, "payload": {"value": _clean_number(float(value))}}
	var range_error := _validate_claim_keys(claim, ["status", "source_id", "acquired_day", "confidence", "min", "max"])
	if range_error != "":
		return _fail_static(range_error)
	return _normalize_range_payload(claim, true)

static func _normalize_trait_payload(status: String, claim: Dictionary) -> Dictionary:
	if status == "estimated":
		return _fail_static("trait estimates are unsupported")
	var allowed_error := _validate_claim_keys(claim, ["status", "source_id", "acquired_day", "confidence", "value"])
	if allowed_error != "":
		return _fail_static(allowed_error)
	var raw_value = claim.get("value")
	var traits: Array = []
	if typeof(raw_value) == TYPE_STRING:
		traits = [raw_value]
	elif raw_value is Array:
		if raw_value.is_empty() or raw_value.size() > MAX_TRAITS:
			return _fail_static("trait list must contain 1..16 strings")
		for trait_value in raw_value:
			if typeof(trait_value) != TYPE_STRING:
				return _fail_static("trait list values must be strings")
			traits.append(trait_value)
	else:
		return _fail_static("trait claim requires a string or string array")
	var normalized_traits: Array = []
	for trait_value in traits:
		var trait_text := str(trait_value)
		if trait_text.strip_edges() == "" or trait_text.length() > MAX_TRAIT_LENGTH:
			return _fail_static("trait values must be non-empty bounded strings")
		if not normalized_traits.has(trait_text):
			normalized_traits.append(trait_text)
	if normalized_traits.is_empty():
		return _fail_static("trait claim must contain a value")
	return {"ok": true, "payload": {"value": normalized_traits}}

static func _normalize_text_payload(status: String, claim: Dictionary) -> Dictionary:
	if status == "estimated":
		return _fail_static("text estimates are unsupported")
	var allowed_keys := ["status", "source_id", "acquired_day", "confidence", "value"]
	if status == "rumor":
		allowed_keys.append("text")
	var allowed_error := _validate_claim_keys(claim, allowed_keys)
	if allowed_error != "":
		return _fail_static(allowed_error)
	var value = claim.get("value", claim.get("text"))
	if typeof(value) != TYPE_STRING or str(value).strip_edges() == "" or str(value).length() > MAX_TEXT_LENGTH:
		return _fail_static("text claim requires a non-empty bounded string")
	return {"ok": true, "payload": {"value": str(value)}}

static func _normalize_generic_payload(status: String, claim: Dictionary) -> Dictionary:
	if status == "estimated":
		var range_keys_error := _validate_claim_keys(claim, ["status", "source_id", "acquired_day", "confidence", "min", "max"])
		if range_keys_error != "":
			return _fail_static(range_keys_error)
		return _normalize_range_payload(claim, false)
	if status == "rumor" and (claim.has("min") or claim.has("max")):
		var rumor_range_error := _validate_claim_keys(claim, ["status", "source_id", "acquired_day", "confidence", "min", "max"])
		if rumor_range_error != "":
			return _fail_static(rumor_range_error)
		return _normalize_range_payload(claim, false)
	var allowed_keys := ["status", "source_id", "acquired_day", "confidence", "value"]
	var allowed_error := _validate_claim_keys(claim, allowed_keys)
	if allowed_error != "":
		return _fail_static(allowed_error)
	var value = claim.get("value")
	var budget := {"count": 0}
	if not _is_safe_generic_value(value, 0, budget):
		return _fail_static("generic claim value must be bounded JSON-safe scalar/array data")
	return {"ok": true, "payload": {"value": _copy_safe_value(value)}}

static func _normalize_range_payload(claim: Dictionary, clamp_ability: bool) -> Dictionary:
	if not claim.has("min") or not claim.has("max"):
		return _fail_static("numeric claim requires min and max")
	var minimum = claim.get("min")
	var maximum = claim.get("max")
	if not _is_finite_number(minimum) or not _is_finite_number(maximum):
		return _fail_static("claim range must be finite numeric data")
	var min_value := float(minimum)
	var max_value := float(maximum)
	if min_value > max_value:
		return _fail_static("claim range must be ordered")
	if clamp_ability and (min_value < 0.0 or max_value > 100.0):
		return _fail_static("ability range must stay within 0..100")
	return {"ok": true, "payload": {"min": _clean_number(min_value), "max": _clean_number(max_value)}}

static func _normalize_claim_list(field_id: Variant, raw_claims: Array, reject_invalid: bool) -> Dictionary:
	var claims_by_source: Dictionary = {}
	for raw_claim in raw_claims:
		var result := normalize_claim(field_id, raw_claim)
		if not result.get("ok", false):
			if reject_invalid:
				return {"ok": false, "claims": []}
			continue
		var claim: Dictionary = result.claim
		var source_id := str(claim.source_id)
		if reject_invalid and claims_by_source.has(source_id):
			return {"ok": false, "claims": []}
		if not claims_by_source.has(source_id) or _claim_is_preferred(claim, claims_by_source[source_id]):
			claims_by_source[source_id] = claim
	if reject_invalid and claims_by_source.size() > MAX_CLAIMS_PER_FIELD:
		return {"ok": false, "claims": []}
	var candidates: Array = claims_by_source.values()
	candidates.sort_custom(_claim_recency_less)
	if candidates.size() > MAX_CLAIMS_PER_FIELD:
		candidates = candidates.slice(0, MAX_CLAIMS_PER_FIELD)
	var claims: Array = candidates
	claims.sort_custom(_claim_source_less)
	return {"ok": true, "claims": claims}

func _resolve_public_fate_reason(state, data: Dictionary, character_id: String, kind: String, reason_id: String) -> Dictionary:
	match kind:
		"route":
			var route_ref := _find_chronicle_reference(state, reason_id, ["political_season_route_selection"])
			if route_ref.is_empty():
				return {"status": "hidden" if _public_fate_catalog_contains(data, kind, reason_id) else "broken"}
			if _is_hidden_public_record(route_ref):
				return {"status": "hidden"}
			var route := _find_route_definition(data, reason_id)
			var route_summary := _safe_public_summary(route.get("public_summary", route.get("summary", route.get("label", ""))), "政治季路线已形成公开记录")
			if route_summary.contains(reason_id):
				route_summary = "政治季路线已形成公开记录"
			return {"status": "resolved", "reason": {"summary": route_summary, "target": {"kind": "chronicle", "id": str(route_ref.get("id", reason_id))}}}
		"case":
			var cases_value: Variant = _public_state_value(state, "accountability_cases", {})
			var cases: Dictionary = cases_value if cases_value is Dictionary else {}
			var case_record: Dictionary = cases.get(reason_id, {}) if cases.get(reason_id, {}) is Dictionary else {}
			if case_record.is_empty():
				return {"status": "hidden" if _public_fate_catalog_contains(data, kind, reason_id) else "broken"}
			if str(case_record.get("lifecycle", "")) not in ["decided", "closed"]:
				return {"status": "hidden"}
			if _is_hidden_public_record(case_record):
				return {"status": "hidden"}
			var decision: Dictionary = case_record.get("decision", {}) if case_record.get("decision", {}) is Dictionary else {}
			var verdict_id := str(decision.get("verdict_id", case_record.get("verdict_id", "")))
			var summary := _case_public_summary(data, reason_id, verdict_id)
			return {"status": "resolved", "reason": {"summary": summary, "target": {"kind": "case", "id": reason_id}}}
		"office":
			var office_found := false
			var offices_value: Variant = _public_state_value(state, "office_state", {})
			var offices: Dictionary = offices_value if offices_value is Dictionary else {}
			var office_record: Dictionary = offices.get(reason_id, {}) if offices.get(reason_id, {}) is Dictionary else {}
			if not office_record.is_empty():
				office_found = true
			if not office_found:
				var office_history_value: Variant = _public_state_value(state, "office_history", [])
				for raw_history in office_history_value if office_history_value is Array else []:
					if raw_history is Dictionary and str((raw_history as Dictionary).get("office_id", "")) == reason_id:
						office_found = true
						break
			if not office_found:
				return {"status": "hidden" if _public_fate_catalog_contains(data, kind, reason_id) else "broken"}
			if _is_hidden_public_record(office_record):
				return {"status": "hidden"}
			var office_label := _office_public_label(data, reason_id)
			var office_status := str(office_record.get("status", ""))
			var office_summary := office_label + ("当前仍在任，任职记录可供复核" if office_status == "appointed" else "的任职记录已公开更新")
			return {"status": "resolved", "reason": {"summary": office_summary, "target": {"kind": "office", "id": reason_id}}}
		"review":
			var review_record := _find_public_review(state, reason_id)
			if review_record.is_empty():
				return {"status": "hidden" if _public_fate_catalog_contains(data, kind, reason_id) else "broken"}
			if _is_hidden_public_record(review_record):
				return {"status": "hidden"}
			var review_summary := _safe_public_summary(review_record.get("public_text", review_record.get("public_summary", review_record.get("summary", ""))), "政治季复核已形成公开记录")
			return {"status": "resolved", "reason": {"summary": review_summary, "target": {"kind": "review", "id": reason_id}}}
		"chronicle":
			var chronicle_ref := _find_chronicle_reference(state, reason_id, [])
			if chronicle_ref.is_empty():
				return {"status": "hidden" if _public_fate_catalog_contains(data, kind, reason_id) else "broken"}
			if _is_hidden_public_record(chronicle_ref):
				return {"status": "hidden"}
			var chronicle_summary := _chronicle_public_summary(chronicle_ref)
			if chronicle_summary.is_empty():
				return {"status": "hidden"}
			if chronicle_summary.contains(reason_id):
				chronicle_summary = "相关政治回响已写入公开纪事，影响可以继续追溯。"
			return {"status": "resolved", "reason": {"summary": chronicle_summary, "target": {"kind": "chronicle", "id": reason_id}}}
	return {"status": "unknown"}

func _public_fate_catalog_contains(data: Dictionary, kind: String, reference_id: String) -> bool:
	var containers: Array = []
	match kind:
		"case": containers = [data.get("accountability_case_templates", []), data.get("accountability_effects", {})]
		"office": containers = [data.get("offices", [])]
		"review": containers = [data.get("political_season_reviews", []), data.get("political_season_review", {}), data.get("political_season_beta_1_10", {})]
		"chronicle": containers = [data.get("beta110_echoes", []), data.get("political_echoes", []), data.get("political_echoes_beta_1_10", {})]
		"route": containers = [data.get("beta110_routes", []), data.get("political_season", {}), data.get("political_season_beta_1_10", {}), data.get("route_network", {})]
	for container in containers:
		if _public_catalog_value_contains(container, reference_id, 0):
			return true
	return false

func _public_catalog_value_contains(value: Variant, reference_id: String, depth: int) -> bool:
	if depth > 5:
		return false
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key in ["id", "case_id", "office_id", "review_id", "echo_id", "route_id"]:
			if str(dictionary.get(key, "")) == reference_id:
				return true
		for child in dictionary.values():
			if _public_catalog_value_contains(child, reference_id, depth + 1):
				return true
	elif value is Array:
		for child in value as Array:
			if _public_catalog_value_contains(child, reference_id, depth + 1):
				return true
	return false

func _find_chronicle_reference(state, reason_id: String, allowed_kinds: Array) -> Dictionary:
	var chronicle_value: Variant = _public_state_value(state, "chronicle_causal_references", [])
	if not chronicle_value is Array:
		return {}
	for raw_reference in chronicle_value as Array:
		if not raw_reference is Dictionary:
			continue
		var reference: Dictionary = raw_reference as Dictionary
		var reference_id := str(reference.get("id", ""))
		var route_id := str(reference.get("route_id", ""))
		if reference_id != reason_id and route_id != reason_id:
			continue
		if not allowed_kinds.is_empty() and not allowed_kinds.has(str(reference.get("kind", ""))):
			continue
		return reference.duplicate(true)
	return {}

func _find_route_definition(data: Dictionary, route_id: String) -> Dictionary:
	var containers: Array = [data.get("beta110_routes", [])]
	for key in ["political_season", "political_season_beta_1_10"]:
		var season: Variant = data.get(key, {})
		if season is Dictionary:
			containers.append((season as Dictionary).get("routes", []))
	for raw_container in containers:
		if not raw_container is Array:
			continue
		for raw_route in raw_container as Array:
			if raw_route is Dictionary and str((raw_route as Dictionary).get("route_id", "")) == route_id:
				return (raw_route as Dictionary).duplicate(true)
	return {}

func _case_public_summary(data: Dictionary, case_id: String, verdict_id: String) -> String:
	var effects_container: Variant = data.get("accountability_effects", {})
	var effects: Array = effects_container.get("case_effects", []) if effects_container is Dictionary and effects_container.get("case_effects", []) is Array else data.get("beta110_accountability_effects", [])
	for raw_effect in effects if effects is Array else []:
		if not raw_effect is Dictionary or str((raw_effect as Dictionary).get("case_id", "")) != case_id:
			continue
		var verdicts: Dictionary = (raw_effect as Dictionary).get("verdict_effects", {}) if (raw_effect as Dictionary).get("verdict_effects", {}) is Dictionary else {}
		var effect: Dictionary = verdicts.get(verdict_id, {}) if verdicts.get(verdict_id, {}) is Dictionary else {}
		var chronicle: Dictionary = effect.get("chronicle", {}) if effect.get("chronicle", {}) is Dictionary else {}
		var authored := _safe_public_summary(chronicle.get("summary", ""), "")
		if not authored.is_empty():
			return authored
	var verdict_label: String = str({"reform": "改革结案", "dismiss": "暂缓定责", "forced_removal": "强制免职"}.get(verdict_id, "公开裁决"))
	return "案件已通过公开裁决收束：" + verdict_label

func _office_public_label(data: Dictionary, office_id: String) -> String:
	for raw_office in data.get("offices", []) if data.get("offices", []) is Array else []:
		if raw_office is Dictionary and str((raw_office as Dictionary).get("office_id", "")) == office_id:
			var authored := str((raw_office as Dictionary).get("display_name", (raw_office as Dictionary).get("title", ""))).strip_edges()
			if not authored.is_empty() and authored.length() <= 128 and not authored.contains("<") and not authored.contains(">"):
				return authored
	var defaults := {"war_mobilization": "前线军职", "inner_court_gatekeeper": "宫门传令", "menxia_review": "门下复核", "censorate": "御史监察", "household_supply": "钱粮调度"}
	return str(defaults.get(office_id, "相关官职"))

func _find_public_review(state, review_id: String) -> Dictionary:
	var workbench: Variant = _public_state_value(state, "court_workbench_state", {})
	var acknowledged: Dictionary = workbench.get("political_season_reviews_acknowledged", {}) if workbench is Dictionary and workbench.get("political_season_reviews_acknowledged", {}) is Dictionary else {}
	var governance: Variant = _public_state_value(state, "governance_state", {})
	var reports: Array = governance.get("reports", []) if governance is Dictionary and governance.get("reports", []) is Array else []
	for raw_report in reports:
		if not raw_report is Dictionary or str((raw_report as Dictionary).get("review_id", "")) != review_id:
			continue
		var report: Dictionary = raw_report as Dictionary
		if int(report.get("delivered_day", -1)) >= 0 or str(report.get("status", "")) in ["delivered", "read", "acknowledged"] or bool(acknowledged.get(review_id, false)):
			return report.duplicate(true)
	if bool(acknowledged.get(review_id, false)):
		return {"review_id": review_id, "public_summary": "政治季复核已形成公开记录"}
	return {}

func _chronicle_public_summary(reference: Dictionary) -> String:
	var summary := _safe_public_summary(reference.get("public_summary", reference.get("summary", "")), "")
	if not summary.is_empty():
		return summary
	var kind := str(reference.get("kind", ""))
	return {"political_season_route_selection": "政治季路线已公开确认", "accountability_verdict": "案件裁决已形成公开记录", "office_appointment": "官职任命已形成公开记录", "office_removal": "官职变动已形成公开记录", "character_fate": "人物走向已形成公开记录"}.get(kind, "")

func _safe_public_summary(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING:
		return fallback
	var text := str(value).strip_edges()
	if text.is_empty() or text.length() > MAX_TEXT_LENGTH or text.contains("<") or text.contains(">"):
		return fallback
	return text

func _is_hidden_public_record(record: Dictionary) -> bool:
	for key in ["visibility", "visibility_state", "secrecy"]:
		var value := str(record.get(key, "")).strip_edges()
		if value in ["hidden", "secret", "private"]:
			return true
	return false

func _public_state_value(state, property_name: String, fallback: Variant) -> Variant:
	if state == null:
		return fallback
	if state is Dictionary:
		return (state as Dictionary).get(property_name, fallback)
	var value: Variant = state.get(property_name)
	return fallback if value == null else value

static func _build_conflicts(claims: Array) -> Array:
	var primary: Array = []
	var has_confirmed := false
	for claim in claims:
		if str(claim.get("status", "")) == "confirmed":
			has_confirmed = true
			primary.append(claim)
	if not has_confirmed:
		for claim in claims:
			if str(claim.get("status", "")) == "estimated":
				primary.append(claim)
	var conflicts: Array = []
	for left_index in range(primary.size()):
		for right_index in range(left_index + 1, primary.size()):
			var left: Dictionary = primary[left_index]
			var right: Dictionary = primary[right_index]
			var conflicting := false
			if has_confirmed:
				conflicting = JSON.stringify(left.get("value")) != JSON.stringify(right.get("value"))
			else:
				conflicting = float(left.get("max")) < float(right.get("min")) or float(right.get("max")) < float(left.get("min"))
			if conflicting:
				var source_ids := [str(left.get("source_id", "")), str(right.get("source_id", ""))]
				source_ids.sort()
				conflicts.append({"source_ids": source_ids, "evidence": [left.duplicate(true), right.duplicate(true)]})
	return conflicts

static func _validate_state_request(state, character_id: Variant, field_id: Variant) -> String:
	if state == null or not (state.get("character_knowledge") is Dictionary) or not (state.get("character_states") is Dictionary):
		return "state must expose character knowledge and character dictionaries"
	var character_error := _validate_id(character_id, "character_id")
	if character_error != "":
		return character_error
	var field_error := _validate_id(field_id, "field_id")
	if field_error != "":
		return field_error
	if not state.character_states.has(character_id) or not (state.character_states.get(character_id) is Dictionary):
		return "unknown character_id"
	return ""

static func _validate_id(value: Variant, label: String) -> String:
	if typeof(value) != TYPE_STRING:
		return label + " must be a string"
	var text := str(value)
	if text.strip_edges() == "" or text.length() > MAX_ID_LENGTH:
		return label + " must be non-empty and at most 64 characters"
	return ""

static func _validate_claim_keys(claim: Dictionary, allowed_keys: Array) -> String:
	for key in claim.keys():
		if typeof(key) != TYPE_STRING or not allowed_keys.has(key):
			return "unsupported claim key"
	return ""

static func _is_ability_field(field_id: Variant) -> bool:
	return typeof(field_id) == TYPE_STRING and (ABILITY_FIELDS.has(field_id) or str(field_id).begins_with("ability."))

static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _is_safe_generic_value(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth > MAX_GENERIC_DEPTH:
		return false
	budget["count"] = int(budget.get("count", 0)) + 1
	if int(budget.count) > MAX_GENERIC_NODES:
		return false
	match typeof(value):
		TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_STRING:
			return str(value).length() <= MAX_TEXT_LENGTH
		TYPE_ARRAY:
			for child in value:
				if not _is_safe_generic_value(child, depth + 1, budget):
					return false
			return true
	return false

static func _find_source_index(claims: Array, source_id: String) -> int:
	for index in range(claims.size()):
		if str(claims[index].get("source_id", "")) == source_id:
			return index
	return -1

static func _claim_source_less(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("source_id", "")) < str(right.get("source_id", ""))

static func _claim_recency_less(left: Dictionary, right: Dictionary) -> bool:
	var left_day := int(left.get("acquired_day", 0))
	var right_day := int(right.get("acquired_day", 0))
	if left_day != right_day:
		return left_day > right_day
	return str(left.get("source_id", "")) < str(right.get("source_id", ""))

static func _claim_is_preferred(candidate: Dictionary, existing: Dictionary) -> bool:
	var candidate_day := int(candidate.get("acquired_day", 0))
	var existing_day := int(existing.get("acquired_day", 0))
	if candidate_day != existing_day:
		return candidate_day > existing_day
	var candidate_confidence := float(candidate.get("confidence", 0.0))
	var existing_confidence := float(existing.get("confidence", 0.0))
	if not is_equal_approx(candidate_confidence, existing_confidence):
		return candidate_confidence > existing_confidence
	return JSON.stringify(candidate) > JSON.stringify(existing)

static func _mean_confidence(claims: Array) -> float:
	if claims.is_empty():
		return 0.0
	var total := 0.0
	for claim in claims:
		total += float(claim.get("confidence", 0.0))
	return total / float(claims.size())

static func _add_range_summary(summary: Dictionary, claims: Array) -> void:
	var minimum := float(claims[0].get("min"))
	var maximum := float(claims[0].get("max"))
	for claim in claims:
		minimum = minf(minimum, float(claim.get("min")))
		maximum = maxf(maximum, float(claim.get("max")))
	summary["min"] = _clean_number(minimum)
	summary["max"] = _clean_number(maximum)

static func _latest_claim(claims: Array) -> Dictionary:
	var latest: Dictionary = claims[0]
	for claim in claims:
		var claim_day := int(claim.get("acquired_day", 0))
		var latest_day := int(latest.get("acquired_day", 0))
		if claim_day > latest_day or (claim_day == latest_day and str(claim.get("source_id", "")) > str(latest.get("source_id", ""))):
			latest = claim
	return latest

static func _copy_safe_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array else value

static func _clean_number(value: float) -> Variant:
	return int(value) if is_equal_approx(value, round(value)) else value

func _unknown_field() -> Dictionary:
	return _unknown_field_static()

static func _unknown_field_static() -> Dictionary:
	return {"status": "unknown", "source_ids": [], "confidence": 0.0}

func _fail(message: String) -> Dictionary:
	return _fail_static(message)

static func _fail_static(message: String) -> Dictionary:
	return {"ok": false, "error": message}
