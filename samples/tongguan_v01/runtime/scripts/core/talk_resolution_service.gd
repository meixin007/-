extends RefCounted

class_name TalkResolutionService

# A free-talk outcome is a proposal, never a direct state mutation.  This
# deliberately small schema is safe to persist and is revalidated at both
# submission and settlement boundaries.
const OUTCOMES := {"approve": true, "reject": true, "defer": true, "compromise": true}
const MAX_SUMMARY_CHARS := 160
const MIN_DELAY_DAYS := 1
const MAX_DELAY_DAYS := 3

func prepare(request: Dictionary, player_text: String, ai_result: Dictionary) -> Dictionary:
	var proposed: Dictionary = ai_result.get("proposal", {}) if bool(ai_result.get("ok", false)) and ai_result.get("proposal", {}) is Dictionary else {}
	var outcome := str(proposed.get("outcome", "")).strip_edges()
	if not OUTCOMES.has(outcome) or not _allowed(request, outcome):
		return _fallback(request, player_text)
	var summary := _safe_summary(proposed.get("summary", ""), request)
	if summary.is_empty():
		return _fallback(request, player_text)
	return {
		"ok": true,
		"used_fallback": false,
		"outcome": outcome,
		"summary": summary,
		"effects": _allowed_effects(request, outcome),
		"delay_days": clampi(int(proposed.get("delay_days", 2)), MIN_DELAY_DAYS, MAX_DELAY_DAYS)
	}

func validate_persisted(request: Dictionary, raw_proposal: Variant) -> Dictionary:
	if not (raw_proposal is Dictionary):
		return _fail("free talk proposal is invalid")
	var proposal: Dictionary = raw_proposal
	var outcome := str(proposal.get("outcome", "")).strip_edges()
	if not OUTCOMES.has(outcome) or not _allowed(request, outcome):
		return _fail("free talk outcome is unavailable")
	var summary := _safe_summary(proposal.get("summary", ""), request)
	if summary.is_empty():
		return _fail("free talk summary is unavailable")
	var delay_days := int(proposal.get("delay_days", 0))
	if delay_days < MIN_DELAY_DAYS or delay_days > MAX_DELAY_DAYS:
		return _fail("free talk delay is unavailable")
	var allowed_effects := _allowed_effects(request, outcome)
	if not _same_effects(proposal.get("effects", []), allowed_effects):
		return _fail("free talk effects are unavailable")
	return {
		"ok": true,
		"used_fallback": bool(proposal.get("used_fallback", false)),
		"outcome": outcome,
		"summary": summary,
		"effects": allowed_effects,
		"delay_days": delay_days
	}

func _allowed(request: Dictionary, outcome: String) -> bool:
	if outcome == "compromise":
		return _has_effects(request, "defer")
	return _has_effects(request, outcome)

func _has_effects(request: Dictionary, outcome: String) -> bool:
	var personal_effects: Variant = request.get("personal_effects", {})
	var effect_key := _effect_key(outcome)
	return personal_effects is Dictionary and (personal_effects as Dictionary).has(effect_key) and (personal_effects as Dictionary).get(effect_key) is Array

func _effect_key(outcome: String) -> String:
	return "defer" if outcome == "compromise" else outcome

func _allowed_effects(request: Dictionary, outcome: String) -> Array:
	var personal_effects: Variant = request.get("personal_effects", {})
	if not (personal_effects is Dictionary):
		return []
	var effects: Variant = (personal_effects as Dictionary).get(_effect_key(outcome), [])
	return effects.duplicate(true) if effects is Array else []

func _fallback(request: Dictionary, player_text: String) -> Dictionary:
	if not _allowed(request, "defer"):
		return _fail("free talk fallback requires explicit deferred effects")
	var fallback_summary := "谈话后各方仍需核议，此事暂缓处置。"
	var trimmed_text := player_text.strip_edges()
	if not trimmed_text.is_empty():
		fallback_summary = "谈话已记入朝议，仍需核议后再作处置。"
	return {
		"ok": true,
		"used_fallback": true,
		"outcome": "defer",
		"summary": fallback_summary,
		"effects": _allowed_effects(request, "defer"),
		"delay_days": 2
	}

func _safe_summary(raw_summary: Variant, request: Dictionary) -> String:
	var summary := str(raw_summary).strip_edges().replace("\n", " ").replace("\r", " ")
	if summary.is_empty():
		return ""
	var requester := str(request.get("requester_name", "")).strip_edges()
	# Model prose is presentation only: cap it, and do not let it be stored as a
	# structured instruction or a raw transport response.
	return (requester + "：" if not requester.is_empty() and not summary.begins_with(requester) else "") + summary.left(MAX_SUMMARY_CHARS)

func _same_effects(raw_effects: Variant, allowed_effects: Array) -> bool:
	return raw_effects is Array and JSON.stringify(raw_effects) == JSON.stringify(allowed_effects)

func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
