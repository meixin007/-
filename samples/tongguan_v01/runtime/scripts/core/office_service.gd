extends RefCounted

class_name OfficeService

const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")
const GameStateTransactionScript = preload("res://scripts/core/game_state_transaction.gd")
const StructuredMemoryServiceScript = preload("res://scripts/core/structured_memory_service.gd")
const CharacterArcServiceScript = preload("res://scripts/core/character_arc_service.gd")
const OfficeCatalogScript = preload("res://scripts/domain/beta_1_08_office_catalog.gd")
const TangOfficeCatalogScript = preload("res://scripts/domain/tang_office_catalog.gd")
const TangClanServiceScript = preload("res://scripts/core/tang_clan_service.gd")
const PositionClaimStateScript = preload("res://scripts/core/position_claim_state.gd")
const ControlRelationStateScript = preload("res://scripts/core/control_relation_state.gd")
const ObedienceRelationStateScript = preload("res://scripts/core/obedience_relation_state.gd")
const CoreOfficeIds := [
	"zhongshu_drafting", "menxia_review", "shangshu_execution", "household_supply", "war_mobilization", "censorate", "inner_court_gatekeeper", "envoy_negotiator",
	"zhongshu_ling", "menxia_shizhong", "tong_pingzhangshi", "libu_shangshu", "hubu_shangshu", "libu_rites_shangshu", "bingbu_shangshu", "xingbu_shangshu", "gongbu_shangshu", "yushi_zhongcheng", "zuo_shiyi", "you_shiyi", "zuo_buque", "you_buque", "hanlin_xueshi", "duzhi_shi", "yantie_zhuanyun_shi", "liangliao_shi", "xuanwei_zhaotao_shi", "shuofang_jiedushi", "hedong_jiedushi", "jiannan_jiedushi", "henan_jiedu_fushi", "xingjun_sima"
]
const TERMINAL_CHARACTER_STATUSES := ["departed", "exiled", "defected", "irreconcilable", "dead", "executed", "deceased", "missing", "imprisoned", "unreachable"]
const RAPID_REVERSAL_WINDOW_DAYS := 10
const RAPID_REVERSAL_BASE_COST := 1

func validate_actor_authority(state, office_id: String, actor_id: String = "") -> Dictionary:
	if state == null:
		return _fail("任用缺少世界状态。", "invalid_state")
	# Historical fixtures keep their original procedure. Current identities must
	# derive authority from the current office holder, never a character constant.
	if str(state.flags.get("campaign_id", "")) != "anshi_beta_1_14":
		return {"ok": true}
	var actor := actor_id if not actor_id.is_empty() else str(state.player_character_id)
	if not state.character_states.has(actor) or state.character_states[actor].get("status") in TERMINAL_CHARACTER_STATUSES:
		return _fail("任用主体不存在或已无法履职。", "office_authority_required")
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return {"ok": true} if preload("res://scripts/core/family_office_rules.gd").authority(state, office_id, actor) else _fail("当前人物没有该家族职位任免权。", "office_authority_required")
	var authority: Dictionary = preload("res://scripts/core/office_appointment_authority.gd").resolve(state.office_state, state.character_states, office_id)
	if not authority.get("ok", false): return authority
	if actor.is_empty() or actor != authority.authority_holder_id:
		return _fail("当前人物没有该组织职位的任免权；需要有权任命者办理。", "office_authority_required")
	return authority

func _is_ineligible_appointment_candidate(state, data: Dictionary, candidate_id: String) -> Dictionary:
	var character := _find_character_all(data, candidate_id)
	var char_state: Dictionary = state.character_states.get(candidate_id, {}) if state != null and state.character_states.get(candidate_id, {}) is Dictionary else {}
	
	# 1. 叛军将领与反贼首领（交战敌对）
	var rebel_factions := ["rebel_command", "yan_rebels", "rebels", "enemy"]
	var rebel_roles := ["叛军首领", "叛军大将", "叛军", "叛将", "伪燕大将"]
	var rebel_ids := ["an_lushan", "shi_siming", "an_qingxu", "shi_chaoyi", "gao_xiuyan", "cui_qianyou"]
	if candidate_id in rebel_ids or str(character.get("status", "")) == "enemy" or str(char_state.get("status", "")) == "enemy" or str(character.get("faction_id", "")) in rebel_factions or str(char_state.get("faction_id", "")) in rebel_factions or str(character.get("role", "")) in rebel_roles:
		return {"ineligible": true, "reason": "叛逆贼寇，正与王师交战，严禁除授大唐官爵", "code": "rebel_enemy"}
		
	# 2. 外藩使节与番邦使臣
	var envoy_factions := ["uighur", "tibetan", "foreign", "foreign_tribal"]
	var envoy_roles := ["外藩使节", "回纥使者", "吐蕃使者", "使节", "使者", "foreign_envoy", "diplomat"]
	var envoy_ids := ["uighur_envoy", "tibetan_envoy", "tufan_envoy", "foreign_envoy"]
	if candidate_id in envoy_ids or str(character.get("faction_id", "")) in envoy_factions or str(char_state.get("faction_id", "")) in envoy_factions or str(character.get("role", "")) in envoy_roles:
		return {"ineligible": true, "reason": "外藩使节，不入大唐除授官序", "code": "foreign_envoy"}
		
	# 3. 天子君主本人（九五之尊不兼臣职）
	var ruler_id := str(state.player_character_id) if state != null else "li_heng"
	if candidate_id == ruler_id or candidate_id == "li_heng" or str(character.get("role", "")) in ["emperor", "皇帝", "君主"]:
		return {"ineligible": true, "reason": "九五至尊，不兼百官庶务", "code": "ruler_ineligible"}
		
	# 4. 已死亡/离场/流放等终结状态
	if TERMINAL_CHARACTER_STATUSES.has(str(character.get("status", ""))) or TERMINAL_CHARACTER_STATUSES.has(str(char_state.get("status", ""))):
		return {"ineligible": true, "reason": "人物已离场或不可用", "code": "terminal_status"}
	if state != null and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_14":
		for office in state.office_state.values():
			if office.get("office_kind") == "family" and office.get("holder_id") == candidate_id:
				return {"ineligible": true, "reason": "仍有家族任职和雇约，须先办理交接，不能由除授抹除原职责", "code": "employment_handover_required"}
		
	return {"ineligible": false, "reason": "", "code": "ok"}

func assess_candidate(state, data: Dictionary, office_id: String, holder_id: String) -> Dictionary:
	var result := _assess_candidate_rules(state, data, office_id, holder_id)
	if not result.get("ok", false) or result.get("grade") not in ["eligible", "exceptional"]: return result
	if state == null or str(state.flags.get("campaign_id", "")) != "anshi_beta_1_14": return result
	var central: Dictionary = preload("res://scripts/core/central_office_rules.gd").assess(state, office_id, holder_id)
	if not central.get("ok", false): return _assessment_failure(office_id, holder_id, "prohibited", [central.error], "central_office_requirements")
	if central.get("applicable", false):
		result["appointment_entry"] = central.appointment_entry.duplicate(true)
		result.reasons.append(central.reason)
		result.rule_fingerprint = str(CanonicalJSONScript.hash_value({"office_rules": result.rule_fingerprint, "appointment_entry": central.appointment_entry}).get("hash", ""))
	var entry: Dictionary = preload("res://scripts/core/central_appointment_rules.gd").assess(state, office_id, holder_id)
	if not entry.get("ok", false): return _assessment_failure(office_id, holder_id, "prohibited", [entry.error], "central_entry_required")
	if entry.get("applicable", false):
		result["education_ref"] = entry.education_ref
		result["education_entry"] = entry.education_entry.duplicate(true)
		result.reasons.append(entry.reason)
		result.rule_fingerprint = str(CanonicalJSONScript.hash_value({"office_rules": result.rule_fingerprint, "education_ref": entry.education_ref, "entry": entry.education_entry}).get("hash", ""))
	return result

func _assess_candidate_rules(state, data: Dictionary, office_id: String, holder_id: String) -> Dictionary:
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return preload("res://scripts/core/family_office_rules.gd").assess(state, data, office_id, holder_id)
	var regional: Dictionary = get_office(state, office_id)
	if regional.get("office_kind") == "regional":
		var candidate: Dictionary = state.character_states.get(holder_id, {})
		if regional.get("holder_id") != holder_id and not _find_character_all(data, holder_id).get("employment_preferences", {}).get("regional_willing", false):
			return _assessment_failure(office_id, holder_id, "prohibited", ["本人尚未表示愿受本州辟召"], "regional_consent_required")
		if not state.resource_accounts.has(holder_id + "_cash") or candidate.get("location_id") != regional.get("scope_ref", {}).get("entity_id"):
			return _assessment_failure(office_id, holder_id, "prohibited", ["须先完成到任与本人俸给收款地点核验"], "regional_arrival_required")
	var ineligibility: Dictionary = _is_ineligible_appointment_candidate(state, data, holder_id)
	if bool(ineligibility.get("ineligible", false)):
		return _assessment_failure(office_id, holder_id, "prohibited", [str(ineligibility.get("reason", "不具备任职资格"))], str(ineligibility.get("code", "ineligible")))
	if regional.has("entry_school_id") or preload("res://scripts/core/school_appointment_rules.gd").ENTRY_POSTS.has(office_id):
		var entry: Dictionary = preload("res://scripts/core/school_appointment_rules.gd").assess(state, data, regional, holder_id)
		if not entry.get("ok", false): return _assessment_failure(office_id, holder_id, "prohibited", [str(entry.error)], "school_entry_required")
		var fingerprint: Dictionary = CanonicalJSONScript.hash_value({"office_id": office_id, "candidate_id": holder_id, "education_ref": entry.education_ref, "required_stats": regional.required_stats})
		return {"ok": true, "office_id": office_id, "candidate_id": holder_id, "grade": "eligible", "reasons": [entry.reason], "conflict_office": "", "cost_effects": [], "rule_fingerprint": str(fingerprint.get("hash", "")), "education_ref": entry.education_ref}
	var matrix: Dictionary = data.get("qualification_matrix", {}) if data.get("qualification_matrix", {}) is Dictionary else {}
	if matrix.is_empty() and data.get("beta108_appointments", {}) is Dictionary:
		var beta_app: Dictionary = data.get("beta108_appointments", {}) as Dictionary
		if beta_app.get("qualification_matrix", {}) is Dictionary:
			matrix = beta_app.get("qualification_matrix", {}) as Dictionary
	if matrix.is_empty():
		return _assess_legacy_candidate(state, data, office_id, holder_id)
	var row: Dictionary = matrix.get(holder_id, {}) if matrix.get(holder_id, {}) is Dictionary else {}
	var cell: Dictionary = row.get(office_id, {}) if row.get(office_id, {}) is Dictionary else {}
	if cell.is_empty():
		var canonical: String = TangOfficeCatalogScript.canonical_id(office_id)
		if row.has(canonical):
			cell = row.get(canonical, {})
		else:
			for alias in TangOfficeCatalogScript.get_legacy_aliases_for(office_id):
				if row.has(alias):
					cell = row.get(alias, {})
					break

	if cell.is_empty():
		var comp: Dictionary = assess_comprehensive_candidate(state, data, office_id, holder_id)
		if not bool(comp.get("ok", false)):
			return _assessment_failure(office_id, holder_id, "prohibited", ["人物暂不适任此官职"], "unknown_candidate")
		var score: int = int(comp.get("fitness_score", 50))
		var fallback_grade: String = "prohibited"
		var fallback_reason: String = "履历与本职政务要求不符"
		if score >= 65:
			fallback_grade = "eligible"
			fallback_reason = "政务资历与才能考核合格"
		elif score >= 45:
			fallback_grade = "exceptional"
			fallback_reason = "方略或才能突出，可破格选用"

		var char_state: Dictionary = state.character_states.get(holder_id, {}) if state != null and state.character_states.get(holder_id, {}) is Dictionary else {}
		if TERMINAL_CHARACTER_STATUSES.has(str(char_state.get("status", ""))):
			fallback_grade = "prohibited"
			fallback_reason = "人物已离场或不可用"

		var conf_office: String = _active_core_office_for_holder(state, holder_id, office_id)
		var comp_reasons: Array = [fallback_reason]
		if not conf_office.is_empty():
			comp_reasons.append("现已担任其他要职")
		var comp_cost_effects: Array = []
		if fallback_grade == "exceptional":
			comp_cost_effects.append({"authority": 2.0, "political_debt": 1.0})
		var comp_rule_input: Dictionary = {"office_id": office_id, "candidate_id": holder_id, "grade": fallback_grade, "reason": fallback_reason, "exception_cost": {"authority": 2.0, "political_debt": 1.0} if fallback_grade == "exceptional" else {}}
		var comp_fingerprint_res: Dictionary = CanonicalJSONScript.hash_value(comp_rule_input)
		return {"ok": true, "office_id": office_id, "candidate_id": holder_id, "grade": fallback_grade, "reasons": comp_reasons, "conflict_office": conf_office, "cost_effects": comp_cost_effects, "rule_fingerprint": str(comp_fingerprint_res.get("hash", ""))}

	var reasons: Array = [str(cell.get("reason", ""))]
	var grade: String = str(cell.get("level", "prohibited"))
	var character_state: Dictionary = state.character_states.get(holder_id, {}) if state != null and state.character_states.get(holder_id, {}) is Dictionary else {}
	if character_state.is_empty():
		return _assessment_failure(office_id, holder_id, "prohibited", ["候选人未在当前局势中"], "unknown_candidate")
	if TERMINAL_CHARACTER_STATUSES.has(str(character_state.get("status", ""))):
		grade = "prohibited"
		reasons.append("人物已离场或不可用")
	var conflict_office: String = _active_core_office_for_holder(state, holder_id, office_id)
	if not conflict_office.is_empty():
		reasons.append("现已担任其他要职")
	var cost_effects: Array = []
	if grade == "exceptional":
		cost_effects.append((cell.get("exception_cost", {}) as Dictionary).duplicate(true) if cell.get("exception_cost", {}) is Dictionary else {})
	var rule_input: Dictionary = {"office_id": office_id, "candidate_id": holder_id, "grade": grade, "reason": str(cell.get("reason", "")), "exception_cost": cell.get("exception_cost", {})}
	var fingerprint_result: Dictionary = CanonicalJSONScript.hash_value(rule_input)
	return {"ok": true, "office_id": office_id, "candidate_id": holder_id, "grade": grade, "reasons": reasons, "conflict_office": conflict_office, "cost_effects": cost_effects, "rule_fingerprint": str(fingerprint_result.get("hash", ""))}

func assess_appointment_candidate(state, data: Dictionary, office_id: String, candidate_id: String, mode: String = "auto") -> Dictionary:
	if mode not in ["auto", "normal", "exceptional"]:
		return _fail("appointment mode is invalid", "invalid_appointment_mode")
	var assessment: Dictionary = assess_candidate(state, data, office_id, candidate_id)
	if not bool(assessment.get("ok", false)):
		return assessment
	var grade := str(assessment.get("grade", "prohibited"))
	var resolved_mode := ("exceptional" if grade == "exceptional" else "normal") if mode == "auto" else mode
	var conflict_office := str(assessment.get("conflict_office", ""))
	var transfer_allowed := _appointment_transfer_allowed(state, data, office_id, candidate_id, conflict_office)
	var grade_matches_mode := (resolved_mode == "normal" and grade == "eligible") or (resolved_mode == "exceptional" and grade == "exceptional")
	assessment["appointment_mode"] = resolved_mode
	assessment["transfer_allowed"] = transfer_allowed
	assessment["appointment_available"] = grade_matches_mode and (conflict_office.is_empty() or transfer_allowed)
	return assessment

func get_office(state, office_id: String) -> Dictionary:
	if state == null:
		return {}
	var canonical := TangOfficeCatalogScript.canonical_id(office_id)
	if state.office_state.has(office_id):
		return state.office_state.get(office_id, {}).duplicate(true)
	if state.office_state.has(canonical):
		return state.office_state.get(canonical, {}).duplicate(true)
	return {}

func get_offices_for_holder(state, holder_id: String) -> Array:
	var result: Array = []
	if state == null:
		return result
	for office_id in state.office_state.keys():
		var office: Dictionary = state.office_state[office_id]
		if str(office.get("holder_id", "")) == holder_id:
			result.append(office.duplicate(true))
	return result

func seed_initial_terms(state, data: Dictionary) -> Dictionary:
	var campaign_id := str(data.get("campaign_id", ""))
	if state == null:
		return _fail("initial terms require valid state", "invalid_state")
	if not state.office_terms.is_empty():
		return {"ok": true, "code": "no_op", "terms": state.office_terms.duplicate(true)}
	var next_terms: Dictionary = {}
	var next_offices: Dictionary = state.office_state.duplicate(true)
	var appointed_count := 0

	# 预先初始化 24 席位空缺档案
	for off_id in TangOfficeCatalogScript.get_all_office_ids():
		if not next_offices.has(off_id):
			next_offices[off_id] = TangOfficeCatalogScript.build_vacant_runtime_record(off_id)

	for raw_overlay in data.get("initial_office_overlay", []):
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		var office_id := OfficeCatalogScript.canonical_id(str(overlay.get("office_id", "")))
		var holder_id := str(overlay.get("holder_id", ""))
		var runtime_record: Dictionary = next_offices.get(office_id, {}).duplicate(true) if next_offices.get(office_id, {}) is Dictionary else TangOfficeCatalogScript.build_vacant_runtime_record(office_id)
		runtime_record.merge(overlay.duplicate(true), true)
		runtime_record["office_id"] = office_id
		runtime_record["runtime_kind"] = "core" if (OfficeCatalogScript.is_core_office(office_id) or TangOfficeCatalogScript.is_core_office(office_id)) else "supplemental"
		if holder_id.is_empty():
			runtime_record["status"] = "vacant"
			runtime_record["vacancy_reason"] = str(runtime_record.get("vacancy_reason", "initial_overlay"))
		else:
			if not state.character_states.has(holder_id):
				return _fail("initial office holder is unknown: " + holder_id, "invalid_initial_overlay")
			runtime_record["status"] = "appointed"
			var term_id := "term|bootstrap|%s|%s" % [office_id, holder_id]
			next_terms[term_id] = {
				"term_id": term_id,
				"office_id": office_id,
				"holder_id": holder_id,
				"start_day": maxi(int(state.current_day), 1),
				"end_day": -1,
				"appointment_mode": "initial",
				"appointment_transaction_id": "bootstrap|%s" % campaign_id,
				"ended_by": "",
				"performance_refs": [],
				"settled_reward_keys": [],
				"political_meaning_id": ""
			}
			var claim_id := "claim|bootstrap|%s|%s" % [office_id, holder_id]
			state.position_claims[claim_id] = {
				"claim_id": claim_id,
				"office_id": office_id,
				"character_id": holder_id,
				"issuer_id": str(state.player_character_id),
				"claim_status": "active",
				"issued_day": maxi(int(state.current_day), 1),
				"effective_day": maxi(int(state.current_day), 1),
				"basis_text": "开局拜授",
				"predecessor_claim_id": ""
			}
			var ctrl_id := "ctrl|office_seal|%s" % office_id
			state.control_relations[ctrl_id] = {
				"control_id": ctrl_id,
				"target_type": "office_seal",
				"target_id": office_id,
				"controller_id": holder_id,
				"strength": 100,
				"control_type": "de_jure"
			}
			var obed_id := "obed|%s|%s|all" % [holder_id, str(state.player_character_id)]
			state.obedience_relations[obed_id] = {
				"obedience_id": obed_id,
				"subordinate_id": holder_id,
				"superior_id": str(state.player_character_id),
				"scope": "all",
				"strength": 80,
				"basis": "formal_mandate"
			}
			appointed_count += 1
		next_offices[office_id] = runtime_record
		# 若为历史席位，同步映射至新官制
		var modern_id := TangOfficeCatalogScript.canonical_id(office_id)
		if modern_id != office_id and not next_offices.has(modern_id):
			next_offices[modern_id] = runtime_record.duplicate(true)
			next_offices[modern_id]["office_id"] = modern_id
	state.office_state = next_offices
	state.office_terms = next_terms
	return {"ok": true, "code": "seeded", "terms": next_terms.duplicate(true), "appointed_count": appointed_count}

func preview_appointment(context, office_id: String, candidate_id: String, mode: String = "normal") -> Dictionary:
	if context == null or context.state == null:
		return _fail("appointment context is invalid", "invalid_context")
	if preload("res://scripts/core/family_office_rules.gd").is_family(context.state, office_id):
		return preload("res://scripts/core/family_office_rules.gd").preview(context, office_id, candidate_id)
	if mode not in ["normal", "exceptional"]:
		return _fail("appointment mode is invalid", "invalid_appointment_mode")
	var window_validation: Dictionary = _validate_appointment_window(context.state, context.scenario_data, office_id)
	if not bool(window_validation.get("ok", false)):
		return window_validation
	var office: Dictionary = get_office(context.state, office_id)
	if office.is_empty():
		return _fail("unknown office: " + office_id, "unknown_office")
	var legacy_rules := _qualification_matrix_is_empty(context.scenario_data)
	var office_holder := str(office.get("holder_id", ""))
	var office_status := str(office.get("status", ""))
	if legacy_rules and (not office_holder.is_empty() or (not office_status.is_empty() and office_status != "vacant")):
		return _fail("office is not vacant", "office_not_vacant")
	if office_holder == candidate_id and not candidate_id.is_empty():
		return {"ok": true, "code": "no_op", "office_id": office_id, "candidate_id": candidate_id}
	var assessment: Dictionary = assess_appointment_candidate(context.state, context.scenario_data, office_id, candidate_id, mode)
	if not bool(assessment.get("ok", false)):
		return assessment
	var conflict_office := str(assessment.get("conflict_office", ""))
	var transfer_allowed := bool(assessment.get("transfer_allowed", false))
	if not bool(assessment.get("appointment_available", false)):
		return _fail("candidate is not eligible for this appointment mode", "candidate_prohibited")
	var meaning_result: Dictionary = _resolve_political_meaning(context.scenario_data, office_id, candidate_id)
	if not bool(meaning_result.get("ok", false)):
		return meaning_result
	var political_meaning_id := str(meaning_result.get("political_meaning_id", ""))
	var input := {"office_id": office_id, "candidate_id": candidate_id, "mode": mode, "qualification": assessment.duplicate(true), "political_meaning_id": political_meaning_id, "transfer_from_office_id": conflict_office if transfer_allowed else ""}
	var reversal_preview: Dictionary = preview_rapid_reversal(context.state, office_id, int(context.state.current_day), RAPID_REVERSAL_BASE_COST)
	var cost_lines: Array[String] = []
	if office.get("office_kind") == "regional" and office.has("remuneration_terms"):
		cost_lines.append("州库承担任期每日 %d 俸给，每 %d 日后付；离任按实际天数结算" % [int(office.remuneration_terms.daily_amount), int(office.remuneration_terms.period_days)])
	if mode == "exceptional" and not assessment.get("cost_effects", []).is_empty():
		var cost: Dictionary = assessment.cost_effects[0]
		cost_lines.append("破格任用：朝廷权威 -%d，政治人情代价 %d" % [int(cost.get("authority", 0)), int(cost.get("political_debt", 0))])
	if reversal_preview.get("rapid_reversal", false): cost_lines.append("短期反复任免：朝廷权威 -%d" % int(reversal_preview.cost))
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "appoint_office", input, office_id, "")
	if not bool(preview.get("ok", false)):
		return preview
	var envelope := transaction.build_command_envelope("appoint_office", input, preview.get("preview_token", {}))
	return {
		"ok": true,
		"code": "preview_ready",
		"office_id": office_id,
		"candidate_id": candidate_id,
		"mode": mode,
		"qualification": assessment.duplicate(true),
		"political_meaning_id": political_meaning_id,
		"transfer_from_office_id": conflict_office if transfer_allowed else "",
		"rapid_reversal": reversal_preview.duplicate(true),
		"public_costs_text": "；".join(cost_lines) if not cost_lines.is_empty() else "无额外任命政治代价",
		"public_risks_text": "；".join(assessment.get("reasons", [])),
		"public_operation_text": "任命%s为%s" % [str(context.state.character_states.get(candidate_id, {}).get("name", candidate_id)), str(TangOfficeCatalogScript.get_office_definition(office_id).get("name", office.get("name", office_id)))],
		"preview_token": preview.get("preview_token", {}).duplicate(true),
		"envelope": envelope
	}

func confirm_appointment(context, envelope: Dictionary) -> Dictionary:
	var transaction := GameStateTransactionScript.new()
	var operation := Callable(self, "_apply_appointment_transaction").bind(envelope.get("input", {}), str(envelope.get("transaction_id", "")))
	return transaction.execute_command(context, envelope, operation)

func preview_removal(context, office_id: String, force: bool = false) -> Dictionary:
	if context == null or context.state == null:
		return _fail("removal context is invalid", "invalid_context")
	var authority := validate_actor_authority(context.state, office_id)
	if not authority.get("ok", false):
		return authority
	var office: Dictionary = get_office(context.state, office_id)
	var holder_id := str(office.get("holder_id", ""))
	if office.is_empty() or holder_id.is_empty() or str(office.get("status", "")) != "appointed":
		return _fail("office has no removable holder", "office_not_appointed")
	var input := {"office_id": office_id, "holder_id": holder_id, "force": force}
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "force_dismiss_office" if force else "dismiss_office", input, office_id, "")
	if not bool(preview.get("ok", false)):
		return preview
	var kind := "force_dismiss_office" if force else "dismiss_office"
	return {"ok": true, "code": "preview_ready", "envelope": transaction.build_command_envelope(kind, input, preview.get("preview_token", {})), "preview_token": preview.get("preview_token", {}).duplicate(true), "public_costs_text": "强制免职：政治人情代价 1" if force else "无额外免职政治代价", "public_risks_text": "结束本职任期，保留实际履职和离任记录。", "public_operation_text": "%s%s的%s职务" % ["强制免去" if force else "免去", str(context.state.character_states.get(holder_id, {}).get("name", holder_id)), str(TangOfficeCatalogScript.get_office_definition(office_id).get("name", office.get("name", office_id)))]}

func confirm_removal(context, envelope: Dictionary) -> Dictionary:
	var transaction := GameStateTransactionScript.new()
	var operation := Callable(self, "_apply_removal_transaction").bind(envelope.get("input", {}), str(envelope.get("transaction_id", "")))
	return transaction.execute_command(context, envelope, operation)

func _apply_removal_transaction(working_context, raw_input: Variant, transaction_id: String) -> Dictionary:
	if not raw_input is Dictionary:
		return _fail("removal input is invalid", "invalid_command_payload")
	var input: Dictionary = raw_input
	if str(working_context.state.flags.get("campaign_id", "")) == "anshi_beta_1_14" and not preload("res://scripts/core/family_office_rules.gd").is_family(working_context.state, str(input.get("office_id", ""))):
		return load("res://scripts/core/official_office_actions.gd").manual(working_context, "force_dismiss_office" if input.get("force", false) else "dismiss_office", {"office_id": input.get("office_id", ""), "holder_id": input.get("holder_id", "")}, transaction_id)
	var result: Dictionary = apply_removal(working_context.state, str(input.get("office_id", "")), transaction_id, bool(input.get("force", false)))
	if not bool(result.get("ok", false)) or str(result.get("code", "")) == "no_op":
		return result
	var fate_result: Dictionary = _reconcile_office_characters(working_context, [str(result.get("holder_id", ""))])
	if not bool(fate_result.get("ok", false)):
		return fate_result
	result["character_fate"] = fate_result.duplicate(true)
	return result

func apply_removal(state, office_id: String, transaction_id: String, force: bool = false, actor_id: String = "") -> Dictionary:
	var authority := validate_actor_authority(state, office_id, actor_id)
	if not authority.get("ok", false):
		return authority
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return preload("res://scripts/core/family_office_rules.gd").dismiss(state, office_id, transaction_id)
	var office: Dictionary = get_office(state, office_id)
	var holder_id := str(office.get("holder_id", ""))
	if office.is_empty() or holder_id.is_empty() or str(office.get("status", "")) != "appointed":
		return _fail("office has no removable holder", "office_not_appointed")
	var day := int(state.current_day)
	var next_office := office.duplicate(true)
	next_office["holder_id"] = ""
	next_office["status"] = "vacant"
	next_office["vacancy_reason"] = "forced_removal" if force else "dismissed"
	next_office["last_changed_day"] = day
	next_office["last_change_source"] = "accountability_verdict"
	state.office_state[office_id] = next_office
	var canonical := TangOfficeCatalogScript.canonical_id(office_id)
	for linked_id in [canonical] + TangOfficeCatalogScript.get_legacy_aliases_for(canonical):
		if linked_id == office_id: continue
		var linked: Dictionary = next_office.duplicate(true)
		linked["office_id"] = linked_id
		state.office_state[linked_id] = linked
	for raw_term_id in state.office_terms.keys():
		var term: Dictionary = state.office_terms[raw_term_id] if state.office_terms[raw_term_id] is Dictionary else {}
		if not term.is_empty() and TangOfficeCatalogScript.canonical_id(str(term.get("office_id", ""))) == canonical and int(term.get("end_day", 0)) < 0:
			var closed := term.duplicate(true)
			closed["end_day"] = day
			closed["ended_by"] = transaction_id
			state.office_terms[raw_term_id] = closed
	var character_state: Dictionary = state.character_states.get(holder_id, {}).duplicate(true)
	if force:
		character_state["status"] = "disgraced"
		state.character_states[holder_id] = character_state
	state.office_history.append({"office_id": office_id, "previous_holder_id": holder_id, "holder_id": "", "day": day, "source": "accountability_verdict", "transaction_id": transaction_id, "forced": force})
	state.chronicle_causal_references.append({"kind": "office_removal", "id": office_id, "holder_id": holder_id, "day": day, "transaction_id": transaction_id, "forced": force})
	if force:
		_apply_forced_removal_debt(state, office_id, holder_id, transaction_id)
	return {"ok": true, "code": "removed", "office_id": office_id, "holder_id": holder_id, "forced": force}

func settle_daily_performance(state, data: Dictionary, day: int) -> Dictionary:
	if state == null or str(data.get("campaign_id", "")) not in ["anshi_beta_1_08", "anshi_beta_1_09", "anshi_beta_1_10"]:
		return {"ok": true, "code": "no_op", "effects": [], "refs": []}
	var refs: Array = []
	var effects: Array = []
	var reports: Array = state.battlefront_reports if state.battlefront_reports is Array else []
	for raw_term_id in state.office_terms.keys():
		var term: Dictionary = state.office_terms[raw_term_id] if state.office_terms[raw_term_id] is Dictionary else {}
		if term.is_empty() or int(term.get("end_day", 0)) >= 0:
			continue
		var updated := term.duplicate(true)
		var performance_refs: Array = updated.get("performance_refs", []).duplicate(true)
		var settled_rewards: Array = updated.get("settled_reward_keys", []).duplicate(true)
		for raw_report in reports:
			if not raw_report is Dictionary:
				continue
			var report: Dictionary = raw_report
			var report_day := int(report.get("day", report.get("created_day", -1)))
			var matches_term := str(report.get("term_id", "")) == str(term.get("term_id", "")) or str(report.get("office_id", "")) == str(term.get("office_id", ""))
			var report_id := str(report.get("report_id", report.get("id", "")))
			if not matches_term or report_day != day or report_id.is_empty() or performance_refs.has(report_id):
				continue
			performance_refs.append(report_id)
			refs.append({"kind": "office_performance", "id": report_id, "term_id": str(term.get("term_id", ""))})
			var reward_key := str(report.get("reward_key", ""))
			if not reward_key.is_empty() and not settled_rewards.has(reward_key):
				settled_rewards.append(reward_key)
				var reward_effects: Array = report.get("reward_effects", []) if report.get("reward_effects", []) is Array else []
				for effect in reward_effects:
					if effect is Dictionary and str((effect as Dictionary).get("type", "")) == "resource_delta":
						var target := str((effect as Dictionary).get("target", ""))
						if state.resources.has(target):
							var settled: Dictionary = state.apply_resource_delta(target, int((effect as Dictionary).get("value", 0)), "rule:office_performance:" + reward_key)
							if not settled.get("ok", false): return settled
					effects.append(effect.duplicate(true) if effect is Dictionary else {})
		updated["performance_refs"] = performance_refs
		updated["settled_reward_keys"] = settled_rewards
		state.office_terms[raw_term_id] = updated
	return {"ok": true, "code": "settled", "effects": effects, "refs": refs}

func _apply_appointment_transaction(working_context, raw_input: Variant, transaction_id: String) -> Dictionary:
	if not raw_input is Dictionary:
		return _fail("appointment input is invalid", "invalid_command_payload")
	var input: Dictionary = raw_input
	if str(working_context.state.flags.get("campaign_id", "")) == "anshi_beta_1_14" and not preload("res://scripts/core/family_office_rules.gd").is_family(working_context.state, str(input.get("office_id", ""))):
		return load("res://scripts/core/official_office_actions.gd").manual(working_context, "appoint_office", {"office_id": input.get("office_id", ""), "candidate_id": input.get("candidate_id", ""), "mode": input.get("mode", "")}, transaction_id)
	var result: Dictionary = apply_appointment(working_context.state, working_context.scenario_data, input, transaction_id)
	if not bool(result.get("ok", false)) or str(result.get("code", "")) == "no_op":
		return result
	var affected: Array = [str(result.get("candidate_id", "")), str(result.get("previous_holder_id", ""))]
	var fate_result: Dictionary = _reconcile_office_characters(working_context, affected)
	if not bool(fate_result.get("ok", false)):
		return fate_result
	result["character_fate"] = fate_result.duplicate(true)
	return result

func _reconcile_office_characters(working_context, candidates: Array) -> Dictionary:
	var service := CharacterArcServiceScript.new()
	var affected: Array = service.supported_character_ids(working_context.scenario_data, candidates)
	return service.reconcile_characters(working_context.state, working_context.scenario_data, affected, int(working_context.state.current_day))

func apply_appointment(state, data: Dictionary, input: Dictionary, transaction_id: String) -> Dictionary:
	var office_id := str(input.get("office_id", ""))
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return preload("res://scripts/core/family_office_rules.gd").appoint(state, data, input, transaction_id)
	var candidate_id := str(input.get("candidate_id", ""))
	var mode := str(input.get("mode", ""))
	if office_id.is_empty() or candidate_id.is_empty() or mode not in ["normal", "exceptional"]:
		return _fail("appointment input is incomplete", "invalid_command_payload")
	var window_validation: Dictionary = _validate_appointment_window(state, data, office_id, str(input.get("actor_id", state.player_character_id)))
	if not bool(window_validation.get("ok", false)):
		return window_validation
	var meaning_result: Dictionary = _resolve_political_meaning(data, office_id, candidate_id)
	if not bool(meaning_result.get("ok", false)):
		return meaning_result
	var political_meaning_id := str(meaning_result.get("political_meaning_id", ""))
	var requested_meaning := str(input.get("political_meaning_id", ""))
	if not requested_meaning.is_empty() and requested_meaning != political_meaning_id:
		return _fail("political meaning does not match the candidate declaration", "political_meaning_mismatch")
	var office: Dictionary = get_office(state, office_id)
	if office.is_empty():
		return _fail("unknown office: " + office_id, "unknown_office")
	var legacy_rules := _qualification_matrix_is_empty(data)
	var office_holder := str(office.get("holder_id", ""))
	var office_status := str(office.get("status", ""))
	if legacy_rules and (not office_holder.is_empty() or (not office_status.is_empty() and office_status != "vacant")):
		return _fail("office is not vacant", "office_not_vacant")
	if office_holder == candidate_id:
		return {"ok": true, "code": "no_op", "office_id": office_id, "candidate_id": candidate_id}
	var assessment: Dictionary = assess_candidate(state, data, office_id, candidate_id)
	var grade := str(assessment.get("grade", "prohibited"))
	var conflict_office := str(assessment.get("conflict_office", ""))
	var transfer_allowed := _appointment_transfer_allowed(state, data, office_id, candidate_id, conflict_office)
	var requested_transfer := str(input.get("transfer_from_office_id", ""))
	if transfer_allowed and not requested_transfer.is_empty() and requested_transfer != conflict_office:
		return _fail("appointment transfer source is stale", "stale_appointment_transfer")
	if not bool(assessment.get("ok", false)) or grade == "prohibited" or (not conflict_office.is_empty() and not transfer_allowed) or (mode == "normal" and grade != "eligible") or (mode == "exceptional" and grade != "exceptional"):
		return _fail("candidate is prohibited by the qualification matrix", "candidate_prohibited")
	var day := int(state.current_day)
	var previous_holder := str(office.get("holder_id", ""))
	var reversal_preview: Dictionary = preview_rapid_reversal(state, office_id, day, RAPID_REVERSAL_BASE_COST)
	var next_terms: Dictionary = state.office_terms.duplicate(true)
	for raw_term_id in next_terms.keys():
		var term: Dictionary = next_terms[raw_term_id] if next_terms[raw_term_id] is Dictionary else {}
		if term.is_empty() or int(term.get("end_day", 0)) >= 0:
			continue
		if TangOfficeCatalogScript.canonical_id(str(term.get("office_id", ""))) == TangOfficeCatalogScript.canonical_id(office_id) or str(term.get("holder_id", "")) == candidate_id:
			var closed := term.duplicate(true)
			closed["end_day"] = day
			closed["ended_by"] = transaction_id
			next_terms[raw_term_id] = closed
	var term_id := "term|%s" % transaction_id
	next_terms[term_id] = {
		"term_id": term_id,
		"office_id": office_id,
		"holder_id": candidate_id,
		"start_day": day,
		"end_day": -1,
		"appointment_mode": mode,
		"appointment_transaction_id": transaction_id,
		"political_meaning_id": political_meaning_id,
		"ended_by": "",
		"performance_refs": [],
		"settled_reward_keys": []
	}
	if assessment.has("education_ref"): next_terms[term_id]["education_ref"] = assessment.education_ref
	if assessment.has("education_entry"): next_terms[term_id]["education_entry"] = assessment.education_entry.duplicate(true)
	if assessment.has("appointment_entry"): next_terms[term_id]["appointment_entry"] = assessment.appointment_entry.duplicate(true)
	var next_office := office.duplicate(true)
	next_office["holder_id"] = candidate_id
	next_office["status"] = "appointed"
	next_office["last_changed_day"] = day
	next_office["last_change_source"] = "appointment_transaction"
	state.office_terms = next_terms
	state.office_state[office_id] = next_office
	var canonical_id: String = TangOfficeCatalogScript.canonical_id(office_id)
	if canonical_id != office_id:
		var c_office: Dictionary = next_office.duplicate(true)
		c_office["office_id"] = canonical_id
		state.office_state[canonical_id] = c_office
	for alias_id in TangOfficeCatalogScript.get_legacy_aliases_for(canonical_id):
		if alias_id != office_id:
			var a_office: Dictionary = next_office.duplicate(true)
			a_office["office_id"] = alias_id
			state.office_state[alias_id] = a_office
	if transfer_allowed:
		var previous_office: Dictionary = state.office_state.get(conflict_office, {}).duplicate(true)
		if previous_office.is_empty() or str(previous_office.get("holder_id", "")) != candidate_id:
			return _fail("appointment transfer source is no longer held by candidate", "stale_appointment_transfer")
		previous_office["holder_id"] = ""
		previous_office["status"] = "vacant"
		previous_office["vacancy_reason"] = "transferred_to_%s" % office_id
		previous_office["last_changed_day"] = day
		previous_office["last_change_source"] = "appointment_transfer"
		state.office_state[conflict_office] = previous_office
		var conf_canonical: String = TangOfficeCatalogScript.canonical_id(conflict_office)
		if conf_canonical != conflict_office:
			var c_conf: Dictionary = previous_office.duplicate(true)
			c_conf["office_id"] = conf_canonical
			state.office_state[conf_canonical] = c_conf
		for alias_id in TangOfficeCatalogScript.get_legacy_aliases_for(conf_canonical):
			if alias_id != conflict_office:
				var a_conf: Dictionary = previous_office.duplicate(true)
				a_conf["office_id"] = alias_id
				state.office_state[alias_id] = a_conf
	var history_entry := {"office_id": office_id, "previous_holder_id": previous_holder, "holder_id": candidate_id, "day": day, "source": "appointment_transaction", "transaction_id": transaction_id, "political_meaning_id": political_meaning_id, "transfer_from_office_id": conflict_office if transfer_allowed else "", "rapid_reversal_streak": int(reversal_preview.get("streak", 1)), "rapid_reversal_cost": int(reversal_preview.get("cost", 0))}
	state.office_history.append(history_entry)
	if transfer_allowed:
		state.office_history.append({"office_id": conflict_office, "previous_holder_id": candidate_id, "holder_id": "", "day": day, "source": "appointment_transfer", "transaction_id": transaction_id, "transfer_to_office_id": office_id, "political_meaning_id": political_meaning_id})
	if bool(reversal_preview.get("rapid_reversal", false)):
		_apply_rapid_reversal_debt(state, office_id, candidate_id, transaction_id, reversal_preview)
	if mode == "exceptional":
		_apply_exceptional_appointment_debt(state, office_id, candidate_id, transaction_id, assessment)
	var memory_id := "memory|office_appointment|%s" % transaction_id
	var memory_tags: Array = ["office", office_id, mode]
	if not political_meaning_id.is_empty():
		memory_tags.append(political_meaning_id)
	var memory_result: Dictionary = StructuredMemoryServiceScript.new().create_memory(state, {
		"id": memory_id,
		"type": "office_appointment",
		"memory_type": "office_appointment",
		"participants": [str(input.get("actor_id", state.player_character_id)), candidate_id],
		"source_id": str(input.get("actor_id", state.player_character_id)),
		"target_id": candidate_id,
		"created_day": day,
		"summary": "Office %s assigned through an accountable appointment (%s)" % [office_id, political_meaning_id],
		"tags": memory_tags,
		"visibility": "court",
		"secrecy": "court",
		"original_evidence": {"office_id": office_id, "transaction_id": transaction_id, "political_meaning_id": political_meaning_id},
		"source_context": {"office_id": office_id, "transaction_id": transaction_id, "political_meaning_id": political_meaning_id}
	})
	if not bool(memory_result.get("ok", false)):
		return _fail(str(memory_result.get("error", "appointment memory creation failed")), "memory_creation_failed")
	var memory_index: int = state.structured_memories.size() - 1
	if memory_index >= 0:
		var memory_entry: Dictionary = state.structured_memories[memory_index].duplicate(true)
		memory_entry["political_meaning_id"] = political_meaning_id
		state.replace_structured_memory(memory_index, memory_entry)
	var chronicle_id := "office_appointment|%s" % transaction_id
	state.chronicle_causal_references.append({"kind": "office_appointment", "id": chronicle_id, "office_id": office_id, "holder_id": candidate_id, "day": day, "transaction_id": transaction_id, "political_meaning_id": political_meaning_id, "transfer_from_office_id": conflict_office if transfer_allowed else ""})
	if transfer_allowed:
		state.chronicle_causal_references.append({"kind": "office_transfer", "id": "office_transfer|%s" % transaction_id, "from_office_id": conflict_office, "to_office_id": office_id, "holder_id": candidate_id, "day": day, "transaction_id": transaction_id, "political_meaning_id": political_meaning_id})
	return {"ok": true, "code": "committed", "office_id": office_id, "candidate_id": candidate_id, "term_id": term_id, "previous_holder_id": previous_holder, "political_meaning_id": political_meaning_id, "qualification": assessment.duplicate(true)}

func _validate_appointment_window(state, data: Dictionary, office_id: String, actor_id: String = "") -> Dictionary:
	var authority := validate_actor_authority(state, office_id, actor_id)
	if not authority.get("ok", false):
		return authority
	var campaign_id := str(data.get("campaign_id", state.flags.get("campaign_id", "")) if state != null else data.get("campaign_id", ""))
	if campaign_id not in ["anshi_beta_1_09", "anshi_beta_1_10"] or office_id != "menxia_review":
		return {"ok": true}
	var start_day := 12
	var end_day := 20
	var configured: Variant = data.get("appointment_window", null)
	if configured is Dictionary:
		var window: Dictionary = configured
		if window.has(office_id) and window.get(office_id) is Dictionary:
			window = window.get(office_id)
		start_day = int(window.get("start_day", window.get("day_min", start_day)))
		end_day = int(window.get("end_day", window.get("day_max", end_day)))
	var season: Variant = data.get("political_season", data.get("political_season_beta_1_09", data.get("political_season_beta_1_10", {})))
	if season is Dictionary:
		var season_data: Dictionary = season
		if season_data.get("appointment_window", {}) is Dictionary:
			var season_window: Dictionary = season_data.get("appointment_window", {})
			start_day = int(season_window.get("start_day", season_window.get("day_min", start_day)))
			end_day = int(season_window.get("end_day", season_window.get("day_max", end_day)))
		var appointment: Variant = season_data.get("appointment", {})
		if appointment is Dictionary and (appointment as Dictionary).get("window", {}) is Dictionary:
			var appointment_window: Dictionary = (appointment as Dictionary).get("window", {})
			start_day = int(appointment_window.get("start_day", appointment_window.get("day_min", start_day)))
			end_day = int(appointment_window.get("end_day", appointment_window.get("day_max", end_day)))
	var day := int(state.current_day) if state != null else 0
	if day < start_day or day > end_day:
		return _fail("menxia_review appointment is only available from day %d to day %d" % [start_day, end_day], "appointment_window_closed")
	return {"ok": true, "start_day": start_day, "end_day": end_day, "day": day}

func _resolve_political_meaning(data: Dictionary, office_id: String, candidate_id: String) -> Dictionary:
	var campaign_id := str(data.get("campaign_id", ""))
	if campaign_id not in ["anshi_beta_1_09", "anshi_beta_1_10"]:
		return {"ok": true, "political_meaning_id": ""}
	var containers: Array = [
		data.get("appointment_political_meanings", {}),
		data.get("candidate_political_meanings", {}),
		data.get("political_meanings", {})
	]
	var season: Variant = data.get("political_season", data.get("political_season_beta_1_09", data.get("political_season_beta_1_10", {})))
	if season is Dictionary:
		containers.append((season as Dictionary).get("appointment_meanings", []))
		var appointment: Variant = (season as Dictionary).get("appointment", {})
		if appointment is Dictionary:
			containers.append((appointment as Dictionary).get("political_meanings", {}))
			containers.append((appointment as Dictionary).get("candidate_meanings", {}))
	for raw_container in containers:
		var meaning := _meaning_from_container(raw_container, office_id, candidate_id)
		if not meaning.is_empty():
			return {"ok": true, "political_meaning_id": meaning}
	for raw_character in data.get("characters", []) if data.get("characters", []) is Array else []:
		if raw_character is Dictionary and str((raw_character as Dictionary).get("id", "")) == candidate_id:
			var declared := str((raw_character as Dictionary).get("political_meaning_id", ""))
			if not declared.is_empty():
				return {"ok": true, "political_meaning_id": declared}
	var defaults := {"li_bi": "li_bi_procedural_legitimacy", "hardline_old_court_official": "hardline_old_court_continuity"}
	if defaults.has(candidate_id):
		return {"ok": true, "political_meaning_id": str(defaults.get(candidate_id, ""))}
	return _fail("candidate has no declared political meaning", "missing_political_meaning_id")

func _meaning_from_container(raw_container: Variant, office_id: String, candidate_id: String) -> String:
	if raw_container is Array:
		for raw_entry in raw_container:
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			if str(entry.get("office_id", "")) not in ["", office_id] or str(entry.get("candidate_id", "")) != candidate_id:
				continue
			var declared := str(entry.get("political_meaning_id", entry.get("meaning_id", "")))
			if not declared.is_empty():
				return declared
		return ""
	if not raw_container is Dictionary:
		return ""
	var container: Dictionary = raw_container
	var scopes: Array = []
	if container.has(office_id) and container.get(office_id) is Dictionary:
		scopes.append(container.get(office_id))
	scopes.append(container)
	for raw_scope in scopes:
		if not raw_scope is Dictionary:
			continue
		var value: Variant = (raw_scope as Dictionary).get(candidate_id, null)
		if value is Dictionary:
			var meaning := str((value as Dictionary).get("political_meaning_id", (value as Dictionary).get("meaning_id", "")))
			if not meaning.is_empty():
				return meaning
		elif value is String and not str(value).is_empty():
			return str(value)
	return ""

func _appointment_transfer_allowed(state, data: Dictionary, office_id: String, candidate_id: String, conflict_office: String) -> bool:
	if state == null or str(data.get("campaign_id", state.flags.get("campaign_id", ""))) not in ["anshi_beta_1_09", "anshi_beta_1_10"]:
		return false
	var canonical_target := TangOfficeCatalogScript.canonical_id(office_id)
	var canonical_conflict := TangOfficeCatalogScript.canonical_id(conflict_office)
	var is_menxia := (office_id == "menxia_review" or canonical_target == "menxia_shizhong")
	var is_zhongshu := (conflict_office == "zhongshu_drafting" or canonical_conflict == "zhongshu_ling")
	if not is_menxia or not is_zhongshu:
		return false
	var source_office: Dictionary = state.office_state.get(conflict_office, {}).duplicate(true) if state.office_state.get(conflict_office, {}) is Dictionary else {}
	if source_office.is_empty():
		source_office = state.office_state.get(canonical_conflict, {}).duplicate(true) if state.office_state.get(canonical_conflict, {}) is Dictionary else {}
	return str(source_office.get("holder_id", "")) == candidate_id and str(source_office.get("status", "")) == "appointed"

func preview_rapid_reversal(state, office_id: String, day: int = -1, base_cost: int = RAPID_REVERSAL_BASE_COST, history_override: Array = []) -> Dictionary:
	if state == null or not state.office_state.has(office_id):
		return _fail("unknown office: " + office_id, "unknown_office")
	var effective_day := int(state.current_day) if day < 0 and state != null else day
	var history: Array = history_override.duplicate(true) if not history_override.is_empty() else (state.office_history.duplicate(true) if state != null else [])
	var latest: Dictionary = {}
	var latest_day := -1
	for raw_entry in history:
		if not raw_entry is Dictionary or TangOfficeCatalogScript.canonical_id(str((raw_entry as Dictionary).get("office_id", ""))) != TangOfficeCatalogScript.canonical_id(office_id):
			continue
		var entry_day := int((raw_entry as Dictionary).get("day", -1))
		if entry_day > latest_day:
			latest = (raw_entry as Dictionary).duplicate(true)
			latest_day = entry_day
	var streak := 1
	var rapid := false
	if not latest.is_empty():
		var delta := effective_day - latest_day
		rapid = delta >= 0 and delta <= RAPID_REVERSAL_WINDOW_DAYS
		if rapid:
			streak = maxi(int(latest.get("rapid_reversal_streak", 1)) + 1, 2)
	var normalized_base := maxi(base_cost, 0)
	var cost := normalized_base * int(pow(2.0, float(streak - 1)))
	return {"ok": true, "office_id": office_id, "day": effective_day, "rapid_reversal": rapid, "streak": streak, "base_cost": normalized_base, "cost": cost, "effects": [{"type": "resource_delta", "target": "court_authority", "value": -cost}] if rapid else []}

func _apply_rapid_reversal_debt(state, office_id: String, candidate_id: String, transaction_id: String, preview: Dictionary) -> void:
	var debt_id := "debt|%s|rapid_reversal" % transaction_id
	if state.political_debts.has(debt_id):
		return
	var effects: Array = preview.get("effects", []).duplicate(true)
	for effect in effects:
		if effect is Dictionary and str((effect as Dictionary).get("type", "")) == "resource_delta":
			var target := str((effect as Dictionary).get("target", ""))
			if state.resources.has(target):
				state.resources[target] = int(state.resources.get(target, 0)) + int((effect as Dictionary).get("value", 0))
	state.political_debts[debt_id] = {
			"debt_id": debt_id,
			"kind": "rapid_reversal",
			"office_id": office_id,
			"character_id": candidate_id,
			"created_day": int(state.current_day),
			"streak": int(preview.get("streak", 1)),
			"effects": effects,
			"source_transaction_id": transaction_id,
			"status": "active",
			"effects_applied": true
		}

func _apply_exceptional_appointment_debt(state, office_id: String, candidate_id: String, transaction_id: String, assessment: Dictionary) -> void:
	var costs: Array = assessment.get("cost_effects", [])
	if costs.is_empty() or not costs[0] is Dictionary:
		return
	var cost_record: Dictionary = costs[0]
	var authority_cost := int(cost_record.get("authority", 0))
	if authority_cost > 0 and state.resources.has("court_authority"):
		state.resources["court_authority"] = int(state.resources.get("court_authority", 0)) - authority_cost
	var debt_id := "debt|%s|exceptional_appointment" % transaction_id
	state.political_debts[debt_id] = {
		"debt_id": debt_id,
		"kind": "exceptional_appointment",
		"office_id": office_id,
		"character_id": candidate_id,
		"created_day": int(state.current_day),
		"streak": 1,
		"effects": [{"type": "resource_delta", "target": "court_authority", "value": -authority_cost}] if authority_cost > 0 else [],
		"relationship_cost": int(cost_record.get("political_debt", 0)),
		"source_transaction_id": transaction_id,
		"status": "active",
		"effects_applied": true
	}

func _apply_forced_removal_debt(state, office_id: String, holder_id: String, transaction_id: String) -> void:
	var debt_id := "debt|%s|forced_removal" % transaction_id
	if state.political_debts.has(debt_id):
		return
	state.political_debts[debt_id] = {
		"debt_id": debt_id,
		"kind": "forced_removal",
		"office_id": office_id,
		"character_id": holder_id,
		"created_day": int(state.current_day),
		"streak": 1,
		"effects": [],
		"relationship_cost": 1,
		"source_transaction_id": transaction_id,
		"status": "active",
		"effects_applied": true
	}

func assign_office(state, data: Dictionary, office_id: String, holder_id: String, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return _fail("家族聘用须预览工资并确认合同，请使用职位页聘用入口", "employment_contract_required")
	var authority := validate_actor_authority(state, office_id, str(options.get("actor_id", state.player_character_id)))
	if not authority.get("ok", false):
		return authority
	if not state.office_state.has(office_id):
		var template := _find_office_template(data, office_id)
		if template.is_empty():
			return _fail("unknown office: " + office_id)
		state.office_state[office_id] = template.duplicate(true)
	if holder_id != "" and not state.character_states.has(holder_id):
		return _fail("unknown holder: " + holder_id)
	var office: Dictionary = state.office_state[office_id].duplicate(true)
	var previous_holder := str(office.get("holder_id", ""))
	office["holder_id"] = holder_id
	office["last_changed_day"] = int(state.current_day)
	office["last_change_source"] = str(options.get("source", "appointment"))
	state.office_state[office_id] = office
	var history_entry := {
		"office_id": office_id,
		"previous_holder_id": previous_holder,
		"holder_id": holder_id,
		"day": int(state.current_day),
		"source": str(options.get("source", "appointment"))
	}
	state.office_history.append(history_entry)
	state.structured_memories.append({
		"memory_type": "office_appointment",
		"source_id": str(options.get("actor_id", state.player_character_id)),
		"target_id": holder_id,
		"summary": "Office " + office_id + " assigned to " + holder_id,
		"tags": ["office", office_id],
		"day": int(state.current_day)
	})
	state.chronicle_causal_references.append({
		"kind": "office",
		"id": office_id,
		"holder_id": holder_id,
		"day": int(state.current_day)
	})
	return {"ok": true, "office": office.duplicate(true), "history": history_entry.duplicate(true)}

func appoint_vacancy(state, data: Dictionary, office_id: String, holder_id: String, options: Dictionary = {}) -> Dictionary:
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return _fail("家族聘用须预览工资并确认合同", "employment_contract_required")
	var authority := validate_actor_authority(state, office_id)
	if not authority.get("ok", false):
		return authority
	var office := get_office(state, office_id)
	if office.is_empty(): return _fail("unknown office: " + office_id, "unknown_office")
	if str(office.get("holder_id", "")) != "" or str(office.get("status", "vacant")) != "vacant": return _fail("office is not vacant", "office_not_vacant")
	var mode := str(options.get("mode", "normal"))
	var meaning_res := _resolve_political_meaning(data, office_id, holder_id)
	var input := {
		"office_id": office_id,
		"candidate_id": holder_id,
		"mode": mode,
		"political_meaning_id": str(meaning_res.get("political_meaning_id", ""))
	}
	var tx_id := "appoint|%s|%s|%d" % [office_id, holder_id, int(state.current_day if state != null else 1)]
	return apply_appointment(state, data, input, tx_id)

func candidate_eligibility(state, data: Dictionary, office_id: String, holder_id: String) -> Dictionary:
	var assessed := assess_candidate(state, data, office_id, holder_id)
	if str(assessed.get("grade", "")) == "prohibited":
		return _fail(str((assessed.get("reasons", ["candidate is prohibited"]) as Array)[0]), "candidate_prohibited")
	return {"ok": true, "office_id": office_id, "holder_id": holder_id, "grade": assessed.get("grade", "eligible"), "reasons": assessed.get("reasons", []).duplicate(true), "cost_effects": assessed.get("cost_effects", []).duplicate(true), "rule_fingerprint": str(assessed.get("rule_fingerprint", ""))}

func remove_with_condition(state, office_id: String, condition_id: String) -> Dictionary:
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return _fail("家族卸任须结清任期并保留欠薪，请使用卸任交接入口", "employment_contract_required")
	if state == null or not (state.flags.get("governance_removal_conditions", []) as Array).has(condition_id):
		return _fail("removal condition is not available", "removal_not_authorized")
	var office := get_office(state, office_id)
	if office.is_empty():
		return _fail("unknown office", "unknown_office")
	office["holder_id"] = ""
	office["status"] = "vacant"
	state.office_state[office_id] = office
	return {"ok": true, "office": office.duplicate(true)}

func _active_core_office_for_holder(state, holder_id: String, requested_office_id: String) -> String:
	if state == null:
		return ""
	if str(state.flags.get("campaign_id", "")) == "anshi_beta_1_14":
		for office in state.office_state.values():
			if office is Dictionary and office.get("status") == "appointed" and office.get("holder_id") == holder_id and TangOfficeCatalogScript.canonical_id(str(office.get("office_id", ""))) != TangOfficeCatalogScript.canonical_id(requested_office_id):
				return str(office.office_id)
	if state.office_terms is Dictionary:
		for term in state.office_terms.values():
			if term is Dictionary and int((term as Dictionary).get("end_day", 0)) < 0 and str((term as Dictionary).get("holder_id", "")) == holder_id and str((term as Dictionary).get("office_id", "")) != requested_office_id and CoreOfficeIds.has(str((term as Dictionary).get("office_id", ""))):
				return str((term as Dictionary).get("office_id", ""))
	return ""

func _assessment_failure(office_id: String, holder_id: String, grade: String, reasons: Array, code: String) -> Dictionary:
	var fingerprint_result: Dictionary = CanonicalJSONScript.hash_value({"office_id": office_id, "candidate_id": holder_id, "grade": grade, "reasons": reasons})
	return {"ok": code == "", "office_id": office_id, "candidate_id": holder_id, "grade": grade, "reasons": reasons.duplicate(true), "cost_effects": [], "rule_fingerprint": str(fingerprint_result.get("hash", "")), "code": code}

func _qualification_matrix_is_empty(data: Dictionary) -> bool:
	var matrix: Variant = data.get("qualification_matrix", {})
	return not matrix is Dictionary or (matrix as Dictionary).is_empty()

func _assess_legacy_candidate(state, data: Dictionary, office_id: String, holder_id: String) -> Dictionary:
	var office := get_office(state, office_id)
	var character := _find_character(data, holder_id)
	if office.is_empty() or character.is_empty():
		return _assessment_failure(office_id, holder_id, "prohibited", ["unknown office or candidate"], "unknown_candidate")
	var appointment: Dictionary = office.get("appointment", {}) if office.get("appointment", {}) is Dictionary else {}
	var reasons: Array = []
	var grade := "eligible"
	if not bool(appointment.get("player_may_appoint_if_vacant", false)):
		grade = "prohibited"
		reasons.append("该官职不开放君主任命")
	var known_tags: Array = character.get("governance_tags", character.get("tags", [])) if character.get("governance_tags", character.get("tags", [])) is Array else []
	for raw_tag in appointment.get("candidate_tags", []) if appointment.get("candidate_tags", []) is Array else []:
		var tag := str(raw_tag)
		if not known_tags.has(tag):
			grade = "prohibited"
			reasons.append("缺少任职标签：" + tag)
	var ability := int(character.get("governance_ability", 0))
	var minimum_ability := int(appointment.get("minimum_known_ability", 0))
	if ability < minimum_ability:
		grade = "prohibited"
		reasons.append("治理能力不足（%d/%d）" % [ability, minimum_ability])
	var character_state: Dictionary = state.character_states.get(holder_id, {}) if state != null and state.character_states.get(holder_id, {}) is Dictionary else {}
	var status := str(character_state.get("status", character.get("status", "")))
	if TERMINAL_CHARACTER_STATUSES.has(status):
		grade = "prohibited"
		reasons.append("人物已离场，不能任用")
	var relationship := int(character_state.get("relationships", {}).get("li_heng", 0)) if character_state.get("relationships", {}) is Dictionary else 0
	if relationship < -50:
		grade = "prohibited"
		reasons.append("与君主关系过于敌对")
	if reasons.is_empty():
		reasons.append("符合该官职的公开任职条件")
	var fingerprint_result: Dictionary = CanonicalJSONScript.hash_value({"office_id": office_id, "candidate_id": holder_id, "grade": grade, "reasons": reasons})
	return {"ok": grade != "prohibited", "office_id": office_id, "candidate_id": holder_id, "grade": grade, "reasons": reasons, "cost_effects": [], "rule_fingerprint": str(fingerprint_result.get("hash", "")), "code": "" if grade != "prohibited" else "candidate_prohibited"}

func get_office_effects(state, office_id: String) -> Array:
	var office := get_office(state, office_id)
	var result: Array = []
	for effect in office.get("effects", []):
		result.append(effect.duplicate(true))
	return result

func _find_office_template(data: Dictionary, office_id: String) -> Dictionary:
	for office in data.get("offices", []):
		if str(office.get("office_id", office.get("id", ""))) == office_id:
			return office.duplicate(true)
	return {}

func _find_character(data: Dictionary, character_id: String) -> Dictionary:
	return _find_character_all(data, character_id)

func _find_character_all(data: Dictionary, character_id: String) -> Dictionary:
	for raw_character in data.get("characters", []):
		if raw_character is Dictionary and str((raw_character as Dictionary).get("id", "")) == character_id:
			return (raw_character as Dictionary).duplicate(true)
	# 检查世家扩展库
	var clan_service = TangClanServiceScript.new()
	var elite: Dictionary = clan_service.get_tier_2_elite(character_id)
	if not elite.is_empty():
		return elite
	var scion: Dictionary = clan_service.get_tier_3_scion(character_id)
	if not scion.is_empty():
		return scion
	return {}

func _get_character_stats(character: Dictionary) -> Dictionary:
	var stats: Dictionary = character.get("stats", {}) if character.get("stats", {}) is Dictionary else {}
	if not stats.is_empty():
		return stats
	# 容错降级
	return {
		"governance": int(character.get("governance_ability", 50)),
		"finance": int(character.get("finance_ability", 50)),
		"command": int(character.get("command_ability", 50)),
		"martial": int(character.get("martial_ability", 50)),
		"intrigue": int(character.get("intrigue_ability", 50)),
		"diplomacy": int(character.get("diplomacy_ability", 50)),
		"morality": int(character.get("morality_ability", 50))
	}

# ==============================================================================
# 大唐行政权能与产出引擎 (Administrative Output Engine)
# ==============================================================================

func calculate_administrative_outputs(state, data: Dictionary) -> Dictionary:
	var hubu_holder := _get_office_holder_id(state, "hubu_shangshu")
	var duzhi_holder := _get_office_holder_id(state, "duzhi_shi")
	var yantie_holder := _get_office_holder_id(state, "yantie_zhuanyun_shi")
	var gongbu_holder := _get_office_holder_id(state, "gongbu_shangshu")
	var liangliao_holder := _get_office_holder_id(state, "liangliao_shi")
	var bingbu_holder := _get_office_holder_id(state, "bingbu_shangshu")
	var shuofang_holder := _get_office_holder_id(state, "shuofang_jiedushi")
	var hedong_holder := _get_office_holder_id(state, "hedong_jiedushi")
	var yushi_holder := _get_office_holder_id(state, "yushi_zhongcheng")
	var zuo_shiyi_holder := _get_office_holder_id(state, "zuo_shiyi")
	var you_shiyi_holder := _get_office_holder_id(state, "you_shiyi")
	var zhongshu_holder := _get_office_holder_id(state, "zhongshu_ling")
	var menxia_holder := _get_office_holder_id(state, "menxia_shizhong")
	var pingzhang_holder := _get_office_holder_id(state, "tong_pingzhangshi")

	var hubu_stats := _get_character_stats(_find_character_all(data, hubu_holder))
	var duzhi_stats := _get_character_stats(_find_character_all(data, duzhi_holder))
	var yantie_stats := _get_character_stats(_find_character_all(data, yantie_holder))
	var gongbu_stats := _get_character_stats(_find_character_all(data, gongbu_holder))
	var liangliao_stats := _get_character_stats(_find_character_all(data, liangliao_holder))
	var bingbu_stats := _get_character_stats(_find_character_all(data, bingbu_holder))
	var shuofang_stats := _get_character_stats(_find_character_all(data, shuofang_holder))
	var hedong_stats := _get_character_stats(_find_character_all(data, hedong_holder))
	var yushi_stats := _get_character_stats(_find_character_all(data, yushi_holder))
	var zuo_shiyi_stats := _get_character_stats(_find_character_all(data, zuo_shiyi_holder))
	var you_shiyi_stats := _get_character_stats(_find_character_all(data, you_shiyi_holder))
	var zhongshu_stats := _get_character_stats(_find_character_all(data, zhongshu_holder))
	var menxia_stats := _get_character_stats(_find_character_all(data, menxia_holder))
	var pingzhang_stats := _get_character_stats(_find_character_all(data, pingzhang_holder))

	# 公式一：每日金帛税收与度支
	var hubu_fin := int(hubu_stats.get("finance", 40)) if not hubu_holder.is_empty() else 30
	var yantie_fin := int(yantie_stats.get("finance", 40)) if not yantie_holder.is_empty() else 30
	var duzhi_fin := int(duzhi_stats.get("finance", 40)) if not duzhi_holder.is_empty() else 30
	var tax_bonus := (hubu_fin - 50) / 100.0
	var salt_bonus := yantie_fin / 80.0
	var net_income_multiplier := snappedf(1.0 + tax_bonus + (salt_bonus * 0.3), 0.01)
	if hubu_holder.is_empty():
		net_income_multiplier = 0.6

	# 公式二：军粮征发与漕运损耗
	var gongbu_gov := int(gongbu_stats.get("governance", 40)) if not gongbu_holder.is_empty() else 30
	var liangliao_fin := int(liangliao_stats.get("finance", 40)) if not liangliao_holder.is_empty() else 30
	var transport_loss := clampf(0.40 - ((gongbu_gov * 0.2 + liangliao_fin * 0.2) / 100.0), 0.15, 0.50)
	var grain_delivered_rate := snappedf(1.0 - transport_loss, 0.01)

	# 公式三：部队战备与士气恢复
	var bingbu_cmd := int(bingbu_stats.get("command", 40)) if not bingbu_holder.is_empty() else 30
	var shuofang_cmd := int(shuofang_stats.get("command", 50)) if not shuofang_holder.is_empty() else 35
	var shuofang_mar := int(shuofang_stats.get("martial", 50)) if not shuofang_holder.is_empty() else 35
	var readiness_multiplier := snappedf(0.70 + (bingbu_cmd / 100.0) * 0.60, 0.01)
	var shuofang_morale_bonus := snappedf((shuofang_cmd * 0.5 + shuofang_mar * 0.3) / 100.0, 0.01)

	# 公式四：言路监察与贪腐暴雷概率
	var yushi_int := int(yushi_stats.get("intrigue", 40)) if not yushi_holder.is_empty() else 20
	var shiyi_mor := maxi(int(zuo_shiyi_stats.get("morality", 0)), int(you_shiyi_stats.get("morality", 0)))
	var corruption_rate := clampf(yushi_int * 0.6 + shiyi_mor * 0.4, 10.0, 95.0)

	# 缺位心神压力
	var stress_data := get_vacant_penalties(state)

	return {
		"revenue": {
			"net_income_multiplier": net_income_multiplier,
			"tax_bonus": tax_bonus,
			"salt_bonus": salt_bonus,
			"hubu_holder": hubu_holder,
			"duzhi_holder": duzhi_holder
		},
		"logistics": {
			"transport_loss_rate": transport_loss,
			"grain_delivered_rate": grain_delivered_rate,
			"gongbu_holder": gongbu_holder,
			"liangliao_holder": liangliao_holder
		},
		"military": {
			"readiness_multiplier": readiness_multiplier,
			"shuofang_morale_bonus": shuofang_morale_bonus,
			"bingbu_holder": bingbu_holder,
			"shuofang_holder": shuofang_holder
		},
		"censorate": {
			"corruption_detection_rate": corruption_rate,
			"yushi_holder": yushi_holder,
			"shiyi_morality_lead": shiyi_mor
		},
		"stress": stress_data
	}

func _get_office_holder_id(state, office_id: String) -> String:
	var office := get_office(state, office_id)
	return str(office.get("holder_id", ""))

func get_vacant_penalties(state) -> Dictionary:
	var total_stress := 0
	var vacant_cores: Array[String] = []
	var all_ids := TangOfficeCatalogScript.get_all_office_ids()
	for off_id in all_ids:
		var office := get_office(state, off_id)
		var is_vacant: bool = office.is_empty() or str(office.get("status", "")) == "vacant" or str(office.get("holder_id", "")).is_empty()
		if is_vacant:
			var def := TangOfficeCatalogScript.get_office_definition(off_id)
			var penalties: Dictionary = def.get("vacant_penalties", {})
			var stress_add := int(penalties.get("daily_emperor_stress", 0))
			total_stress += stress_add
			if TangOfficeCatalogScript.is_core_office(off_id):
				vacant_cores.append(off_id)
	return {
		"daily_vacancy_stress": total_stress,
		"vacant_core_count": vacant_cores.size(),
		"vacant_core_offices": vacant_cores
	}

# ==============================================================================
# 适任人才智能评估引擎 (Comprehensive Candidate Evaluation)
# ==============================================================================

func assess_comprehensive_candidate(state, data: Dictionary, office_id: String, candidate_id: String) -> Dictionary:
	var ineligibility: Dictionary = _is_ineligible_appointment_candidate(state, data, candidate_id)
	if bool(ineligibility.get("ineligible", false)):
		return {
			"ok": false,
			"code": str(ineligibility.get("code", "ineligible")),
			"fitness_score": 0,
			"suitability_rank": "丁·禁绝",
			"reasons": [str(ineligibility.get("reason", "不具备任职资格"))]
		}
	var def := TangOfficeCatalogScript.get_office_definition(office_id)
	if def.is_empty() and state != null and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_14":
		var local: Dictionary = get_office(state, office_id)
		if local.has("authority_ref") and local.get("required_stats") is Dictionary and local.get("preferred_traits", []) is Array:
			def = local
	if def.is_empty():
		return _fail("unknown office definition: " + office_id, "unknown_office")
	var character := _find_character_all(data, candidate_id)
	if character.is_empty() or state == null or not state.character_states.has(candidate_id):
		return _fail("unknown candidate: " + candidate_id, "unknown_candidate")
	
	var char_stats := _get_character_stats(character)
	var required_stats: Dictionary = def.get("required_stats", {})
	var preferred_traits: Array = def.get("preferred_traits", [])
	var char_traits: Array = character.get("traits", [])

	var total_stat_score := 0.0
	var stat_keys := required_stats.keys()
	if stat_keys.is_empty():
		total_stat_score = 70.0
	else:
		var stat_sum := 0.0
		for key in stat_keys:
			var req_val := int(required_stats[key])
			var actual_val := int(char_stats.get(key, 50))
			var ratio := clampf(float(actual_val) / float(maxi(req_val, 1)), 0.4, 1.3)
			stat_sum += ratio * 75.0
		total_stat_score = stat_sum / float(stat_keys.size())

	var trait_bonus := 0.0
	for p_trait in preferred_traits:
		if char_traits.has(p_trait):
			trait_bonus += 12.0
	
	# 状态惩罚
	var char_state: Dictionary = state.character_states.get(candidate_id, {}) if state != null and state.character_states.get(candidate_id, {}) is Dictionary else {}
	if TERMINAL_CHARACTER_STATUSES.has(str(char_state.get("status", ""))):
		return {
			"ok": false,
			"code": "candidate_prohibited",
			"fitness_score": 0,
			"suitability_rank": "丁·离场",
			"reasons": ["人物已离场或不可用"]
		}

	var raw_score := clampf(total_stat_score + trait_bonus, 20.0, 100.0)
	var final_score := int(round(raw_score))
	var rank := "丁·不适"
	if final_score >= 85:
		rank = "甲上·精明"
	elif final_score >= 70:
		rank = "乙中·适任"
	elif final_score >= 50:
		rank = "丙下·平庸"

	var reasons: Array[String] = []
	if final_score >= 85:
		reasons.append("六维才能与官职高度契合")
	elif final_score >= 70:
		reasons.append("能力可胜任该职")
	else:
		reasons.append("履职才能略显吃力")

	if trait_bonus > 0:
		reasons.append("具备契合的政务/军事特质")

	return {
		"ok": true,
		"office_id": office_id,
		"candidate_id": candidate_id,
		"fitness_score": final_score,
		"suitability_rank": rank,
		"reasons": reasons,
		"character_name": str(character.get("name", candidate_id)),
		"traits": char_traits
	}

# ==============================================================================
# 朝堂席位图谱结构树生成 (Court Hierarchy Tree)
# ==============================================================================

func get_court_hierarchy_structure(state, data: Dictionary) -> Array:
	var branches := TangOfficeCatalogScript.get_all_branches()
	var all_offices := TangOfficeCatalogScript.get_all_offices()
	var result: Array = []

	for branch_def in branches:
		var branch_id := str(branch_def.get("id", ""))
		var branch_name := str(branch_def.get("name", ""))
		var branch_desc := str(branch_def.get("description", ""))
		var branch_node := {
			"id": branch_id,
			"name": branch_name,
			"description": branch_desc,
			"offices": []
		}

		for off_def in all_offices:
			if str(off_def.get("branch", "")) == branch_id:
				var off_id := str(off_def.get("id", ""))
				var runtime := get_office(state, off_id)
				var holder_id := str(runtime.get("holder_id", ""))
				var status := str(runtime.get("status", "vacant"))
				if holder_id.is_empty():
					status = "vacant"
				
				var holder_profile := {}
				var fitness := {}
				if not holder_id.is_empty():
					holder_profile = _find_character_all(data, holder_id)
					fitness = assess_comprehensive_candidate(state, data, off_id, holder_id)

				var office_card := {
					"id": off_id,
					"name": str(off_def.get("name", off_id)),
					"rank": str(off_def.get("rank", "")),
					"department": str(off_def.get("department", "")),
					"is_core": bool(off_def.get("is_core_cabinet", false)),
					"responsibility_text": str(off_def.get("responsibility_text", "")),
					"status": status,
					"holder_id": holder_id,
					"holder_profile": holder_profile,
					"fitness": fitness,
					"penalties": off_def.get("vacant_penalties", {})
				}
				branch_node["offices"].append(office_card)

		result.append(branch_node)
	return result

func create_position_claim(state, office_id: String, candidate_id: String, issuer_id: String = "", basis_text: String = "诏敕特授", predecessor_claim_id: String = "") -> Dictionary:
	if state == null:
		return _fail("create_position_claim requires valid state", "invalid_state")
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, office_id):
		return _fail("家族雇用以双方合同生效，请使用聘用入口", "employment_contract_required")
	var canonical_id := TangOfficeCatalogScript.canonical_id(office_id)
	var actor: String = issuer_id if not issuer_id.is_empty() else str(state.player_character_id)
	var authority := validate_actor_authority(state, office_id, actor)
	if not authority.get("ok", false):
		return authority
	var claim_id := "claim|%s|%s|%d" % [canonical_id, candidate_id, int(state.current_day)]
	var claim := PositionClaimStateScript.new()
	claim.claim_id = claim_id
	claim.office_id = canonical_id
	claim.character_id = candidate_id
	claim.issuer_id = actor
	claim.claim_status = "issued"
	claim.issued_day = int(state.current_day)
	claim.effective_day = -1
	claim.basis_text = basis_text
	claim.predecessor_claim_id = predecessor_claim_id
	state.position_claims[claim_id] = claim.to_dict()
	return {"ok": true, "claim_id": claim_id, "claim": claim.to_dict()}

func confirm_position_claim(state, claim_id: String, confirmed_by_id: String = "") -> Dictionary:
	if state == null or not state.position_claims.has(claim_id):
		return _fail("claim not found: " + claim_id, "claim_not_found")
	var claim_dict: Dictionary = (state.position_claims[claim_id] as Dictionary).duplicate(true)
	if preload("res://scripts/core/family_office_rules.gd").is_family(state, str(claim_dict.get("office_id", ""))):
		return _fail("家族雇用不能通过诏敕主张绕过工资合同", "employment_contract_required")
	var authority := validate_actor_authority(state, str(claim_dict.get("office_id", "")), confirmed_by_id)
	if not authority.get("ok", false):
		return authority
	claim_dict["claim_status"] = "active"
	claim_dict["effective_day"] = int(state.current_day)
	state.position_claims[claim_id] = claim_dict
	var off_id: String = str(claim_dict.get("office_id", ""))
	var char_id: String = str(claim_dict.get("character_id", ""))
	if not off_id.is_empty() and state.office_state.has(off_id):
		var off: Dictionary = (state.office_state[off_id] as Dictionary).duplicate(true)
		off["holder_id"] = char_id
		off["status"] = "appointed"
		off["last_changed_day"] = int(state.current_day)
		off["last_change_source"] = "claim_confirmed"
		state.office_state[off_id] = off
	set_control_relation(state, "office_seal", off_id, char_id, 100, "de_jure")
	return {"ok": true, "claim_id": claim_id, "claim": claim_dict}

func dispute_position_claim(state, claim_id: String, challenger_id: String, reason: String = "不奉诏") -> Dictionary:
	if state == null or not state.position_claims.has(claim_id):
		return _fail("claim not found: " + claim_id, "claim_not_found")
	var claim_dict: Dictionary = (state.position_claims[claim_id] as Dictionary).duplicate(true)
	claim_dict["claim_status"] = "disputed"
	state.position_claims[claim_id] = claim_dict
	var off_id: String = str(claim_dict.get("office_id", ""))
	state.chronicle_causal_references.append({
		"kind": "position_dispute",
		"claim_id": claim_id,
		"office_id": off_id,
		"challenger_id": challenger_id,
		"reason": reason,
		"day": int(state.current_day)
	})
	return {"ok": true, "claim_id": claim_id, "claim": claim_dict, "challenger_id": challenger_id, "reason": reason}

func revoke_position_claim(state, claim_id: String, revoked_by_id: String = "") -> Dictionary:
	if state == null or not state.position_claims.has(claim_id):
		return _fail("claim not found: " + claim_id, "claim_not_found")
	var claim_dict: Dictionary = (state.position_claims[claim_id] as Dictionary).duplicate(true)
	claim_dict["claim_status"] = "revoked"
	state.position_claims[claim_id] = claim_dict
	return {"ok": true, "claim_id": claim_id, "claim": claim_dict}

func record_position_handover(state, claim_id: String, handover_status: String = "completed", day: int = -1) -> Dictionary:
	if state == null or not state.position_claims.has(claim_id):
		return _fail("claim not found: " + claim_id, "claim_not_found")
	var curr_day := day if day >= 0 else int(state.current_day)
	var claim_dict: Dictionary = (state.position_claims[claim_id] as Dictionary).duplicate(true)
	var off_id: String = str(claim_dict.get("office_id", ""))
	var char_id: String = str(claim_dict.get("character_id", ""))
	if handover_status == "completed":
		claim_dict["claim_status"] = "active"
		claim_dict["effective_day"] = curr_day
		state.position_claims[claim_id] = claim_dict
		if state.office_state.has(off_id):
			var off: Dictionary = (state.office_state[off_id] as Dictionary).duplicate(true)
			off["holder_id"] = char_id
			off["status"] = "appointed"
			off["last_changed_day"] = curr_day
			off["last_change_source"] = "handover_completed"
			state.office_state[off_id] = off
		set_control_relation(state, "office_seal", off_id, char_id, 100, "de_jure")
		return {"ok": true, "code": "handover_completed", "claim_id": claim_id, "office_id": off_id, "holder_id": char_id}
	elif handover_status == "resisted":
		claim_dict["claim_status"] = "disputed"
		state.position_claims[claim_id] = claim_dict
		return {"ok": true, "code": "handover_resisted", "claim_id": claim_id, "office_id": off_id, "claimant_id": char_id}
	return _fail("invalid handover status: " + handover_status, "invalid_handover_status")

func set_control_relation(state, target_type: String, target_id: String, controller_id: String, strength: int = 100, control_type: String = "de_jure") -> Dictionary:
	if state == null:
		return _fail("set_control_relation requires valid state", "invalid_state")
	var ctrl_id := "ctrl|%s|%s" % [target_type, target_id]
	var ctrl := ControlRelationStateScript.new()
	ctrl.control_id = ctrl_id
	ctrl.target_type = target_type
	ctrl.target_id = target_id
	ctrl.controller_id = controller_id
	ctrl.strength = strength
	ctrl.control_type = control_type
	state.control_relations[ctrl_id] = ctrl.to_dict()
	return {"ok": true, "control_id": ctrl_id, "control": ctrl.to_dict()}

func query_de_facto_controller(state, target_type: String, target_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "controller_id": "", "strength": 0, "control_type": "none"}
	var ctrl_id := "ctrl|%s|%s" % [target_type, target_id]
	if state.control_relations.has(ctrl_id):
		var c: Dictionary = state.control_relations[ctrl_id]
		return {"ok": true, "controller_id": str(c.get("controller_id", "")), "strength": int(c.get("strength", 100)), "control_type": str(c.get("control_type", "de_jure"))}
	if target_type == "office_seal" and state.office_state.has(target_id):
		var off: Dictionary = state.office_state[target_id]
		var holder := str(off.get("holder_id", ""))
		if not holder.is_empty():
			return {"ok": true, "controller_id": holder, "strength": 100, "control_type": "de_jure"}
	return {"ok": false, "controller_id": "", "strength": 0, "control_type": "none"}

func set_obedience_relation(state, subordinate_id: String, superior_id: String, scope: String = "all", strength: int = 80, basis: String = "formal_mandate") -> Dictionary:
	if state == null:
		return _fail("set_obedience_relation requires valid state", "invalid_state")
	var obed_id := "obed|%s|%s|%s" % [subordinate_id, superior_id, scope]
	var obed := ObedienceRelationStateScript.new()
	obed.obedience_id = obed_id
	obed.subordinate_id = subordinate_id
	obed.superior_id = superior_id
	obed.scope = scope
	obed.strength = strength
	obed.basis = basis
	state.obedience_relations[obed_id] = obed.to_dict()
	return {"ok": true, "obedience_id": obed_id, "obedience": obed.to_dict()}

func query_obedience(state, subordinate_id: String, superior_id: String, scope: String = "all") -> Dictionary:
	if state == null:
		return {"ok": false, "strength": 0, "basis": "unknown"}
	var obed_id := "obed|%s|%s|%s" % [subordinate_id, superior_id, scope]
	if state.obedience_relations.has(obed_id):
		var o: Dictionary = state.obedience_relations[obed_id]
		return {"ok": true, "strength": int(o.get("strength", 80)), "basis": str(o.get("basis", "formal_mandate"))}
	var all_id := "obed|%s|%s|all" % [subordinate_id, superior_id]
	if state.obedience_relations.has(all_id):
		var o: Dictionary = state.obedience_relations[all_id]
		return {"ok": true, "strength": int(o.get("strength", 80)), "basis": str(o.get("basis", "formal_mandate"))}
	return {"ok": false, "strength": 50, "basis": "default"}

func _fail(message: String, code: String = "office_service_failed") -> Dictionary:
	return {"ok": false, "code": code, "error": message}

