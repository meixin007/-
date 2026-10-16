extends RefCounted

class_name AccountabilityCaseService

const CaseCatalogScript = preload("res://scripts/domain/beta_1_08_case_catalog.gd")

const LIFECYCLE_ORDER := ["dormant", "open", "investigating", "ready", "decided", "closed"]
const ALLOWED_EVIDENCE_KINDS := ["event_history", "governance_report", "verified_intelligence", "chronicle", "consultation", "office_performance", "transaction", "daily_settlement"]
const INDEPENDENT_EVIDENCE_KINDS := ["event_history", "governance_report", "verified_intelligence", "chronicle", "office_performance", "transaction", "daily_settlement"]
const DERIVED_CASE_POLICIES := {
	"grain_ledger_shortfall": {"verdicts": ["dismiss", "reform", "forced_removal"], "fact_kinds": ["ledger_shortfall"], "minimum_sources": 2},
	"military_grain_delay": {"verdicts": ["dismiss", "reform"], "fact_kinds": ["supply_delay"], "minimum_sources": 2},
	"palace_order_leak": {"verdicts": ["dismiss", "reform", "forced_removal"], "fact_kinds": ["order_leak"], "minimum_sources": 2},
	"edict_legitimacy": {"verdicts": ["dismiss", "reform"], "fact_kinds": ["edict_procedure"], "minimum_sources": 2},
	"uighur_aid_cost": {"verdicts": ["dismiss", "reform"], "fact_kinds": ["aid_cost"], "minimum_sources": 2},
	"final_assessment": {"verdicts": ["dismiss", "reform"], "fact_kinds": ["campaign_assessment"], "minimum_sources": 2}
}

func seed_cases(state, data: Dictionary) -> Dictionary:
	if state == null or not _is_derived_campaign(data):
		return _fail("case seed requires a supported derived campaign", "invalid_campaign")
	_register_scenario_sources(state, data)
	var templates: Dictionary = CaseCatalogScript.build_dormant_cases()
	var next_cases: Dictionary = state.accountability_cases.duplicate(true)
	var added_case := false
	var raw_templates: Array = data.get("accountability_case_templates", []) if data.get("accountability_case_templates", []) is Array else []
	for raw_template in raw_templates:
		if not raw_template is Dictionary:
			continue
		var template: Dictionary = raw_template
		var case_id := str(template.get("case_id", ""))
		if templates.has(case_id) and not next_cases.has(case_id):
			var seeded: Dictionary = templates[case_id].duplicate(true)
			seeded["case_kind"] = "official_accountability"
			for key in ["template_id", "subject_ids", "office_ids"]:
				if template.has(key):
					seeded[key] = template[key].duplicate(true) if template[key] is Array else template[key]
			next_cases[case_id] = seeded
			added_case = true
	for case_id in CaseCatalogScript.ids():
		if not next_cases.has(case_id):
			next_cases[case_id] = templates[case_id].duplicate(true)
			next_cases[case_id]["case_kind"] = "official_accountability"
			added_case = true
	state.accountability_cases = next_cases
	return {"ok": true, "code": "seeded" if added_case else "no_op", "cases": next_cases.duplicate(true)}

func open_case(state, case_id: String, causal_ref: Dictionary = {}, content: Dictionary = {}) -> Dictionary:
	var existing_case: Dictionary = _get_case(state, case_id)
	if existing_case.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if not content.is_empty():
		var content_validation := _validate_seed_content(state, existing_case, content)
		if not bool(content_validation.get("ok", false)):
			return content_validation
	var result: Dictionary = _transition(state, case_id, "open", causal_ref)
	if not bool(result.get("ok", false)) or content.is_empty():
		return result
	var case_record: Dictionary = state.accountability_cases.get(case_id, {}).duplicate(true)
	for key in ["facts", "claims", "evidence"]:
		if content.has(key):
			case_record[key] = content[key].duplicate(true) if content[key] is Array else content[key]
	if content.has("deadline_day"):
		case_record["deadline_day"] = int(content.get("deadline_day", int(state.current_day) + 7))
	elif content.has("deadline_days"):
		case_record["deadline_day"] = int(state.current_day) + maxi(int(content.get("deadline_days", 7)), 1)
	var term_ids: Array = []
	for term in state.office_terms.values():
		if term is Dictionary and str((term as Dictionary).get("office_id", "")) in (case_record.get("office_ids", []) as Array) and int((term as Dictionary).get("end_day", 0)) < 0:
			term_ids.append(str((term as Dictionary).get("term_id", "")))
	term_ids.sort()
	case_record["term_ids"] = term_ids
	state.accountability_cases[case_id] = case_record
	result["case"] = case_record.duplicate(true)
	return result

func begin_investigation(state, case_id: String, causal_ref: Dictionary = {}) -> Dictionary:
	return _transition(state, case_id, "investigating", causal_ref)

func attach_evidence(state, case_id: String, evidence: Dictionary, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if str(case_record.get("lifecycle", "")) != "investigating":
		return _fail("evidence requires investigation", "invalid_lifecycle")
	if evidence.is_empty() or str(evidence.get("evidence_id", "")).is_empty() or str(evidence.get("kind", "")).is_empty() or str(evidence.get("ref_id", "")).is_empty() or not ALLOWED_EVIDENCE_KINDS.has(str(evidence.get("kind", ""))) or not _is_authoritative_reference(state, case_record, str(evidence.get("ref_id", ""))):
		return _fail("evidence reference is incomplete", "invalid_evidence")
	var next_case := case_record.duplicate(true)
	var evidence_list: Array = next_case.get("evidence", []).duplicate(true)
	for existing in evidence_list:
		if existing is Dictionary and str((existing as Dictionary).get("evidence_id", "")) == str(evidence.get("evidence_id", "")):
			return _fail("evidence id is already attached", "duplicate_evidence")
	evidence_list.append(evidence.duplicate(true))
	next_case["evidence"] = evidence_list
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "evidence_attached", "case": next_case.duplicate(true)}

func attach_fact(state, case_id: String, fact: Dictionary, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty() or str(case_record.get("lifecycle", "")) not in ["open", "investigating"]:
		return _fail("facts require an open case", "invalid_lifecycle")
	if str(fact.get("fact_id", "")).is_empty() or str(fact.get("kind", "")).is_empty() or str(fact.get("source_ref_id", "")).is_empty() or str(fact.get("kind", "")) in ["player_text", "raw_text", "free_input"] or not _is_authoritative_reference(state, case_record, str(fact.get("source_ref_id", ""))):
		return _fail("fact must reference an authoritative source", "invalid_fact")
	var next_case := case_record.duplicate(true)
	var facts: Array = next_case.get("facts", []).duplicate(true)
	for existing in facts:
		if existing is Dictionary and str((existing as Dictionary).get("fact_id", "")) == str(fact.get("fact_id", "")):
			return _fail("fact id is already attached", "duplicate_fact")
	facts.append(fact.duplicate(true))
	next_case["facts"] = facts
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "fact_attached", "case": next_case.duplicate(true)}

func attach_claim(state, case_id: String, claim: Dictionary, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty() or str(case_record.get("lifecycle", "")) not in ["open", "investigating"]:
		return _fail("claims require an open case", "invalid_lifecycle")
	if str(claim.get("claim_id", "")).is_empty() or str(claim.get("character_id", "")).is_empty() or str(claim.get("character_id", "")) not in (case_record.get("subject_ids", []) as Array):
		return _fail("claim identity is incomplete", "invalid_claim")
	var fact_ids: Array = claim.get("fact_ids", []) if claim.get("fact_ids", []) is Array else []
	for fact_id in fact_ids:
		if not _case_has_fact(case_record, str(fact_id)):
			return _fail("claim references an unknown fact", "invalid_claim")
	var next_case := case_record.duplicate(true)
	var claims: Array = next_case.get("claims", []).duplicate(true)
	for existing in claims:
		if existing is Dictionary and str((existing as Dictionary).get("claim_id", "")) == str(claim.get("claim_id", "")):
			return _fail("claim id is already attached", "duplicate_claim")
	claims.append(claim.duplicate(true))
	next_case["claims"] = claims
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "claim_attached", "case": next_case.duplicate(true)}

func mark_ready(state, case_id: String, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if str(case_record.get("lifecycle", "")) != "investigating":
		return _fail("only investigating cases can become ready", "invalid_lifecycle")
	var deadline_day := int(case_record.get("deadline_day", -1))
	if deadline_day >= 0 and int(state.current_day) >= deadline_day:
		return _fail("accountability case deadline has passed", "case_expired")
	var next_case := case_record.duplicate(true)
	var evidence_check := _validate_evidence_threshold(next_case, state)
	if not bool(evidence_check.get("ok", false)):
		return evidence_check
	var verdicts: Array = _eligible_verdicts(next_case, state)
	if verdicts.is_empty():
		return _fail("case has no available verdict", "insufficient_evidence")
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	next_case["lifecycle"] = "ready"
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "case_ready", "case": next_case.duplicate(true), "available_verdicts": verdicts}

func apply_verdict(state, case_id: String, verdict_id: String, decision: Dictionary, transaction_id: String, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if str(case_record.get("lifecycle", "")) != "ready":
		return _fail("only ready cases can be decided", "invalid_lifecycle")
	if verdict_id.is_empty() or project_available_verdicts(case_record, state).find(verdict_id) < 0:
		return _fail("verdict is not available", "invalid_verdict")
	if transaction_id.is_empty():
		return _fail("verdict transaction is required", "invalid_transaction")
	var next_case := case_record.duplicate(true)
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	next_case["lifecycle"] = "decided"
	next_case["decision"] = {"verdict_id": verdict_id, "payload": decision.duplicate(true)}
	next_case["decision_transaction_id"] = transaction_id
	next_case["decided_day"] = int(state.current_day)
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "case_decided", "case": next_case.duplicate(true)}

func close_case(state, case_id: String, causal_ref: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if str(case_record.get("lifecycle", "")) != "decided":
		return _fail("only decided cases can close", "invalid_lifecycle")
	var next_case := case_record.duplicate(true)
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	next_case["lifecycle"] = "closed"
	next_case["closed_day"] = int(state.current_day)
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "case_closed", "case": next_case.duplicate(true)}

func record_causal_ref(state, case_id: String, causal_ref: Dictionary) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	var next_case := case_record.duplicate(true)
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "causal_ref_recorded", "case": next_case.duplicate(true)}

func project_available_verdicts(case_record: Dictionary, state = null) -> Array:
	if str(case_record.get("lifecycle", "")) != "ready":
		return []
	return _eligible_verdicts(case_record, state)

func _eligible_verdicts(case_record: Dictionary, state = null) -> Array:
	var readiness := project_readiness(case_record, state)
	if not bool(readiness.get("satisfied", false)):
		return []
	var policy: Dictionary = _policy_for_case(case_record)
	var verdicts: Array = (policy.get("verdicts", ["dismiss", "reform"]) as Array).duplicate(true)
	if verdicts.has("forced_removal") and (state == null or not _forced_removal_eligible(state, case_record)):
		verdicts.erase("forced_removal")
	return verdicts

func project_public_dto(state, case_id: String, viewer_context: Dictionary = {}) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	return {
		"case_id": case_id,
		"template_id": str(case_record.get("template_id", "")),
		"lifecycle": str(case_record.get("lifecycle", "dormant")),
		"deadline_day": int(case_record.get("deadline_day", -1)),
		"subject_ids": case_record.get("subject_ids", []).duplicate(true),
		"office_ids": case_record.get("office_ids", []).duplicate(true),
		"facts": _public_records(case_record.get("facts", []), ["fact_id", "kind", "public_summary", "source_ref_id"]),
		"claims": _public_records(case_record.get("claims", []), ["claim_id", "character_id", "fact_ids"]),
		"evidence": _public_records(case_record.get("evidence", []), ["evidence_id", "kind", "ref_id"]),
		"decision": case_record.get("decision", {}).duplicate(true) if case_record.get("decision", {}) is Dictionary else {},
		"decision_transaction_id": str(case_record.get("decision_transaction_id", "")),
		"available_verdicts": project_available_verdicts(case_record, state),
		"causal_refs": _public_records(case_record.get("causal_refs", []), ["kind", "id"])
	}

func settle_daily(state, data: Dictionary, day: int) -> Dictionary:
	if state == null or not _is_derived_campaign(data):
		return {"ok": true, "code": "no_op", "effects": [], "refs": []}
	var refs: Array = []
	var content_map: Dictionary = data.get("beta108_case_content", {}) if data.get("beta108_case_content", {}) is Dictionary else {}
	for case_id in state.accountability_cases.keys():
		var case_record: Dictionary = state.accountability_cases[case_id] if state.accountability_cases[case_id] is Dictionary else {}
		if str(case_record.get("lifecycle", "")) != "dormant":
			continue
		var content: Dictionary = content_map.get(case_id, {}) if content_map.get(case_id, {}) is Dictionary else {}
		if content.is_empty() or day < int(content.get("phase_open_day", 999)):
			continue
		var opened: Dictionary = open_case(state, str(case_id), {"kind": "daily_settlement", "id": "day|%d|%s" % [day, str(case_id)]}, content)
		if not bool(opened.get("ok", false)):
			return opened
		refs.append({"kind": "case", "id": str(case_id), "day": day})
	return {"ok": true, "code": "settled", "effects": [], "refs": refs}

func _is_derived_campaign(data: Dictionary) -> bool:
	return str(data.get("campaign_id", "")) in ["anshi_beta_1_08", "anshi_beta_1_09", "anshi_beta_1_10"]

func _policy_for_case(case_record: Dictionary) -> Dictionary:
	var template_id := str(case_record.get("template_id", ""))
	return (DERIVED_CASE_POLICIES.get(template_id, {}) as Dictionary).duplicate(true)

func project_readiness(case_record: Dictionary, state = null) -> Dictionary:
	var policy: Dictionary = _policy_for_case(case_record)
	var required_fact_kinds: Array = (policy.get("fact_kinds", []) as Array).duplicate(true)
	var present_fact_kinds: Array = []
	for raw_fact in case_record.get("facts", []) if case_record.get("facts", []) is Array else []:
		if raw_fact is Dictionary:
			var kind := str((raw_fact as Dictionary).get("kind", ""))
			if not kind.is_empty() and not present_fact_kinds.has(kind):
				present_fact_kinds.append(kind)
	var missing_fact_kinds: Array = []
	for kind in required_fact_kinds:
		if not present_fact_kinds.has(kind):
			missing_fact_kinds.append(kind)
	var sources: Dictionary = {}
	for raw_evidence in case_record.get("evidence", []) if case_record.get("evidence", []) is Array else []:
		if not raw_evidence is Dictionary:
			continue
		var evidence: Dictionary = raw_evidence
		if INDEPENDENT_EVIDENCE_KINDS.has(str(evidence.get("kind", ""))):
			var ref_id := str(evidence.get("ref_id", ""))
			if not ref_id.is_empty() and (state == null or _is_authoritative_reference(state, case_record, ref_id)):
				sources[ref_id] = true
	var minimum_sources := int(policy.get("minimum_sources", 2))
	return {
		"required_fact_kinds": required_fact_kinds,
		"present_fact_kinds": present_fact_kinds,
		"missing_fact_kinds": missing_fact_kinds,
		"minimum_independent_sources": minimum_sources,
		"present_independent_sources": sources.size(),
		"missing_independent_sources": maxi(0, minimum_sources - sources.size()),
		"satisfied": missing_fact_kinds.is_empty() and sources.size() >= minimum_sources
	}

func _validate_evidence_threshold(case_record: Dictionary, state = null) -> Dictionary:
	var evidence: Array = case_record.get("evidence", []) if case_record.get("evidence", []) is Array else []
	for raw_evidence in evidence:
		if not raw_evidence is Dictionary:
			return _fail("evidence record is invalid", "invalid_evidence")
		var record: Dictionary = raw_evidence
		var kind := str(record.get("kind", ""))
		var ref_id := str(record.get("ref_id", ""))
		if str(record.get("evidence_id", "")).is_empty() or not ALLOWED_EVIDENCE_KINDS.has(kind) or ref_id.is_empty() or (state != null and not _is_authoritative_reference(state, case_record, ref_id)):
			return _fail("evidence record is invalid", "invalid_evidence")
	var readiness := project_readiness(case_record, state)
	if int(readiness.get("present_independent_sources", 0)) < int(readiness.get("minimum_independent_sources", 2)):
		return _fail("case requires independent evidence sources", "insufficient_evidence")
	if not (readiness.get("missing_fact_kinds", []) as Array).is_empty():
		return _fail("case is missing a required fact", "insufficient_facts")
	return {"ok": true}

func _case_has_fact(case_record: Dictionary, fact_id: String) -> bool:
	for raw_fact in case_record.get("facts", []) if case_record.get("facts", []) is Array else []:
		if raw_fact is Dictionary and str((raw_fact as Dictionary).get("fact_id", "")) == fact_id:
			return true
	return false

func _forced_removal_eligible(state, case_record: Dictionary) -> bool:
	var subject_ids: Array = case_record.get("subject_ids", []) if case_record.get("subject_ids", []) is Array else []
	var office_ids: Array = case_record.get("office_ids", []) if case_record.get("office_ids", []) is Array else []
	for raw_office_id in office_ids:
		var office_id := str(raw_office_id)
		var office: Dictionary = state.office_state.get(office_id, {}) if state.office_state.get(office_id, {}) is Dictionary else {}
		var holder_id := str(office.get("holder_id", ""))
		if str(office.get("status", "")) == "appointed" and not holder_id.is_empty() and subject_ids.has(holder_id):
			return true
	return false

func _is_authoritative_reference(state, case_record: Dictionary, reference_id: String) -> bool:
	if reference_id.is_empty() or reference_id.length() > 128 or reference_id.contains(" "):
		return false
	if state == null:
		return false
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("id", "")) == reference_id:
			return true
	for collection in [state.event_history, state.active_events, state.resolved_events, state.battlefront_reports]:
		if not collection is Array:
			continue
		for raw_record in collection:
			if raw_record is Dictionary and str((raw_record as Dictionary).get("id", (raw_record as Dictionary).get("event_id", (raw_record as Dictionary).get("report_id", "")))) == reference_id:
				return true
	var governance: Dictionary = state.governance_state if state != null and state.governance_state is Dictionary else {}
	for container_name in ["reports", "orders", "memorials", "consultations"]:
		var container: Variant = governance.get(container_name, [])
		if container is Array:
			for raw_record in container:
				if raw_record is Dictionary and str((raw_record as Dictionary).get("id", (raw_record as Dictionary).get("report_id", (raw_record as Dictionary).get("order_id", "")))) == reference_id:
					return true
		elif container is Dictionary and (container as Dictionary).has(reference_id):
			return true
	return false

func _register_scenario_sources(state, data: Dictionary) -> void:
	var refs: Array = state.chronicle_causal_references.duplicate(true) if state.chronicle_causal_references is Array else []
	var known: Dictionary = {}
	for raw_ref in refs:
		if raw_ref is Dictionary:
			known[str((raw_ref as Dictionary).get("id", ""))] = true
	var content_map: Dictionary = data.get("beta108_case_content", {}) if data.get("beta108_case_content", {}) is Dictionary else {}
	for raw_content in content_map.values():
		if not raw_content is Dictionary:
			continue
		var content: Dictionary = raw_content
		for raw_fact in content.get("facts", []) if content.get("facts", []) is Array else []:
			if raw_fact is Dictionary:
				_add_scenario_source_ref(refs, known, str((raw_fact as Dictionary).get("source_ref_id", "")))
		for raw_evidence in content.get("evidence", []) if content.get("evidence", []) is Array else []:
			if raw_evidence is Dictionary:
				_add_scenario_source_ref(refs, known, str((raw_evidence as Dictionary).get("ref_id", "")))
	state.chronicle_causal_references = refs

func _add_scenario_source_ref(refs: Array, known: Dictionary, reference_id: String) -> void:
	if reference_id.is_empty() or known.has(reference_id):
		return
	known[reference_id] = true
	refs.append({"kind": "scenario_source", "id": reference_id})

func _validate_seed_content(state, case_record: Dictionary, content: Dictionary) -> Dictionary:
	var facts: Array = content.get("facts", []) if content.get("facts", []) is Array else []
	var fact_ids: Dictionary = {}
	for raw_fact in facts:
		if not raw_fact is Dictionary:
			return _fail("seed fact is invalid", "invalid_fact")
		var fact: Dictionary = raw_fact
		var fact_id := str(fact.get("fact_id", ""))
		if fact_ids.has(fact_id) or not bool(_validate_fact_record(state, case_record, fact).get("ok", false)):
			return _fail("seed fact is invalid", "invalid_fact")
		fact_ids[fact_id] = true
	var evidence_ids: Dictionary = {}
	for raw_evidence in content.get("evidence", []) if content.get("evidence", []) is Array else []:
		if not raw_evidence is Dictionary:
			return _fail("seed evidence is invalid", "invalid_evidence")
		var evidence: Dictionary = raw_evidence
		var evidence_id := str(evidence.get("evidence_id", ""))
		if evidence_ids.has(evidence_id) or not bool(_validate_evidence_record(state, case_record, evidence).get("ok", false)):
			return _fail("seed evidence is invalid", "invalid_evidence")
		evidence_ids[evidence_id] = true
	var existing_facts: Array = case_record.get("facts", []) if case_record.get("facts", []) is Array else []
	var all_fact_ids: Dictionary = fact_ids.duplicate(true)
	for raw_fact in existing_facts:
		if raw_fact is Dictionary:
			all_fact_ids[str((raw_fact as Dictionary).get("fact_id", ""))] = true
	for raw_claim in content.get("claims", []) if content.get("claims", []) is Array else []:
		if not raw_claim is Dictionary:
			return _fail("seed claim is invalid", "invalid_claim")
		var claim: Dictionary = raw_claim
		if str(claim.get("claim_id", "")).is_empty() or not (case_record.get("subject_ids", []) as Array).has(str(claim.get("character_id", ""))):
			return _fail("seed claim is invalid", "invalid_claim")
		for fact_id in claim.get("fact_ids", []) if claim.get("fact_ids", []) is Array else []:
			if not all_fact_ids.has(str(fact_id)):
				return _fail("seed claim references an unknown fact", "invalid_claim")
	return {"ok": true}

func _validate_fact_record(state, case_record: Dictionary, fact: Dictionary) -> Dictionary:
	var kind := str(fact.get("kind", ""))
	var source_ref_id := str(fact.get("source_ref_id", ""))
	if str(fact.get("fact_id", "")).is_empty() or kind.is_empty() or source_ref_id.is_empty() or ["player_text", "raw_text", "free_input"].has(kind) or not _is_authoritative_reference(state, case_record, source_ref_id):
		return _fail("fact must reference an authoritative source", "invalid_fact")
	return {"ok": true}

func _validate_evidence_record(state, case_record: Dictionary, evidence: Dictionary) -> Dictionary:
	var kind := str(evidence.get("kind", ""))
	var ref_id := str(evidence.get("ref_id", ""))
	if str(evidence.get("evidence_id", "")).is_empty() or ref_id.is_empty() or not ALLOWED_EVIDENCE_KINDS.has(kind) or not _is_authoritative_reference(state, case_record, ref_id):
		return _fail("evidence reference is incomplete", "invalid_evidence")
	return {"ok": true}

func _public_records(value: Variant, allowed_keys: Array) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for raw_record in value:
		if not raw_record is Dictionary:
			continue
		var public_record: Dictionary = {}
		for key in allowed_keys:
			if (raw_record as Dictionary).has(key):
				var item: Variant = (raw_record as Dictionary)[key]
				public_record[key] = item.duplicate(true) if item is Dictionary or item is Array else item
		result.append(public_record)
	return result

func _transition(state, case_id: String, target_lifecycle: String, causal_ref: Dictionary) -> Dictionary:
	var case_record: Dictionary = _get_case(state, case_id)
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	var current_index := LIFECYCLE_ORDER.find(str(case_record.get("lifecycle", "")))
	var target_index := LIFECYCLE_ORDER.find(target_lifecycle)
	if current_index < 0 or target_index != current_index + 1:
		return _fail("accountability lifecycle transition is invalid", "invalid_lifecycle")
	var next_case := case_record.duplicate(true)
	var ref_result := _append_causal_ref(next_case, causal_ref)
	if not bool(ref_result.get("ok", false)):
		return ref_result
	next_case["lifecycle"] = target_lifecycle
	if target_lifecycle == "open":
		next_case["opened_day"] = int(state.current_day)
		if not next_case.has("deadline_day"):
			next_case["deadline_day"] = int(state.current_day) + 7
	state.accountability_cases[case_id] = next_case
	return {"ok": true, "code": "case_" + target_lifecycle, "case": next_case.duplicate(true)}

func _append_causal_ref(case_record: Dictionary, causal_ref: Dictionary) -> Dictionary:
	if causal_ref.is_empty():
		return {"ok": true}
	if str(causal_ref.get("kind", "")).is_empty() or str(causal_ref.get("id", "")).is_empty():
		return _fail("causal reference is incomplete", "invalid_causal_ref")
	var refs: Array = case_record.get("causal_refs", []).duplicate(true)
	refs.append(causal_ref.duplicate(true))
	case_record["causal_refs"] = refs
	return {"ok": true}

func _get_case(state, case_id: String) -> Dictionary:
	if state == null or not state.accountability_cases.has(case_id):
		return {}
	var record: Variant = state.accountability_cases.get(case_id, {})
	return record.duplicate(true) if record is Dictionary else {}

func _fail(message: String, code: String) -> Dictionary:
	var impact := "权威案件状态未改变。"
	var next_step := "返回案卷并按提示补充公开依据后重试。"
	match code:
		"insufficient_evidence", "insufficient_facts":
			impact = "案件仍停留在调查阶段，尚未进入裁决。"
			next_step = "补充可核验的独立来源与必要事实后，再提交调查。"
		"case_expired":
			impact = "案件已过处理期限，未产生裁决、资源或关系变化。"
			next_step = "查看过期案卷记录，转处理仍在期限内的案件。"
		"duplicate_evidence", "duplicate_fact", "duplicate_claim":
			impact = "已有记录保持不变，没有重复写入。"
			next_step = "回到案卷检查现有记录，继续下一项调查动作。"
		"invalid_lifecycle":
			impact = "当前阶段没有发生状态变化。"
			next_step = "按案卷显示的阶段动作继续，不要重复当前操作。"
		"unknown_case":
			impact = "没有找到可写入的案件记录。"
			next_step = "从问责六案导航重新选择一个可见案卷。"
	return {"ok": false, "code": code, "reason_code": code, "error": message, "message": message, "summary": message, "impact": impact, "next_step": next_step}
