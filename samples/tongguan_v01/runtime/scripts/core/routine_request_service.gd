extends RefCounted

class_name RoutineRequestService

const REQUEST_CLASS := "routine_request"
const MIN_DEADLINE_DAYS := 15
const MAX_DEADLINE_DAYS := 30
const MIN_DELEGATION_DAYS := 1
const MAX_DELEGATION_DAYS := 3
const RuleEngineScript = preload("res://scripts/core/rule_engine.gd")
const TalkResolutionServiceScript = preload("res://scripts/core/talk_resolution_service.gd")
const Beta109TestScopeScript = preload("res://scripts/core/beta_1_09_test_scope.gd")

# Configured rulings are intentionally narrower than general event effects.  They
# are authored content, but still cross a save-game boundary and must not become
# an unbounded back door into state changes.
const CONFIGURED_EFFECT_VALUE_LIMITS := {
	"resource_delta": 500,
	"relationship_delta": 25,
	"faction_delta": 20,
	"battlefront_delta": 20,
	"strategy_route_delta": 20
}
const MAX_CONFIGURED_TASK_DURATION_DAYS := 7

func create_from_action(state, action: Dictionary) -> Dictionary:
	if state == null or not state.has_method("record_pending_request"):
		return _fail("routine request requires a writable state")
	if str(action.get("request_class", "")) != REQUEST_CLASS:
		return _fail("action is not a routine request")
	var action_id := str(action.get("action_id", "")).strip_edges()
	var title := str(action.get("visible_title", "")).strip_edges()
	var summary := str(action.get("summary", "")).strip_edges()
	var requester_name := str(action.get("character_name", "")).strip_edges()
	var requester_id := str(action.get("character_id", "")).strip_edges()
	var request_type := str(action.get("request_type", action.get("action_type", ""))).strip_edges()
	if action_id.is_empty():
		return _fail("routine request requires an action id")
	if title.is_empty() or summary.is_empty() or requester_name.is_empty():
		return _fail("routine request requires public text")
	var request_id := "routine__" + action_id
	if not get_pending_request(state, request_id).is_empty():
		return _fail("routine request already exists")
	var created_day := int(state.current_day)
	var public_summary := _with_case_context(summary, requester_id, requester_name, request_type)
	var duration := MIN_DEADLINE_DAYS + posmod(
		_seed(created_day, action_id), MAX_DEADLINE_DAYS - MIN_DEADLINE_DAYS + 1
	)
	var request := {
		"request_id": request_id,
		"title": title,
		"summary": public_summary,
		"requester_id": requester_id,
		"requester_name": requester_name,
		"created_day": created_day,
		"due_day": created_day + duration,
		"delegation_candidates": _valid_candidates(action.get("delegation_candidates", [])),
		"request_type": request_type,
		"required_abilities": _numeric_dictionary(action.get("required_abilities", {})),
		"personal_effects": _personal_effects(action.get("personal_effects", {})),
		"requester_faction_id": str(action.get("requester_faction_id", action.get("character_faction_id", ""))).strip_edges(),
		"request_tags": _string_values(action.get("request_tags", [])),
		"status": "pending"
	}
	if action.has("bargain_id"):
		request["bargain_id"] = str(action.get("bargain_id", ""))
		request["bargain_topic"] = str(action.get("bargain_topic", ""))
		request["public_dispute"] = str(action.get("public_dispute", ""))
		request["public_risk"] = str(action.get("public_risk", ""))
		request["counterpart_character_id"] = str(action.get("counterpart_character_id", ""))
		request["counterpart_faction_id"] = str(action.get("counterpart_faction_id", ""))
		request["bargain_outcomes"] = (action.get("bargain_outcomes", {}) as Dictionary).duplicate(true)
	var campaign_id := str(state.flags.get("campaign_id", "")).strip_edges() if state.flags is Dictionary else ""
	if Beta109TestScopeScript.SUPPORTED_CAMPAIGN_IDS.has(campaign_id):
		request["source_campaign_id"] = campaign_id
	state.record_pending_request(request)
	return {"ok": true, "request": request.duplicate(true)}

func get_pending_request(state, request_id: String) -> Dictionary:
	if state == null or request_id.is_empty():
		return {}
	for raw_request in state.pending_requests:
		if raw_request is Dictionary and str(raw_request.get("request_id", "")) == request_id:
			return raw_request.duplicate(true)
	return {}

func get_delegate_candidates(state, request_id: String) -> Array:
	var request := get_pending_request(state, request_id)
	return _valid_candidates(request.get("delegation_candidates", []))

func project_pending(state, scenario_data: Dictionary = {}) -> Array:
	if state == null:
		return []
	var projected: Array = []
	var seen_request_ids: Dictionary = {}
	for raw_request in state.pending_requests:
		if not (raw_request is Dictionary):
			continue
		if str(raw_request.get("status", "")) != "pending":
			continue
		var request: Dictionary = raw_request
		if not Beta109TestScopeScript.is_request_visible(request, state, scenario_data):
			continue
		var request_id := str(request.get("request_id", "")).strip_edges()
		if request_id.is_empty() or seen_request_ids.has(request_id):
			continue
		seen_request_ids[request_id] = true
		projected.append({
			"request_id": request_id,
			"title": str(request.get("title", "")),
			"summary": str(request.get("summary", "")),
			"requester_name": str(request.get("requester_name", "")),
			"created_day": int(request.get("created_day", 0)),
			"due_day": int(request.get("due_day", 0)),
			"days_remaining": maxi(int(request.get("due_day", 0)) - int(state.current_day), 0),
			"delegation_candidates": _valid_candidates(request.get("delegation_candidates", []))
		})
	projected.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("due_day", 0)) < int(right.get("due_day", 0))
	)
	return projected

func get_player_briefing(raw_request: Dictionary) -> Dictionary:
	var request_type := str(raw_request.get("request_type", "")).strip_edges()
	if request_type.is_empty():
		request_type = _request_type_from_id(str(raw_request.get("request_id", "")))
	var requester_id := str(raw_request.get("requester_id", "")).strip_edges()
	var requester_name := str(raw_request.get("requester_name", "请愿人")).strip_edges()
	var title := str(raw_request.get("title", "当前请愿")).strip_edges()
	var summary := str(raw_request.get("summary", "")).strip_edges()
	var briefing := {
		"petitioner": requester_name if not requester_name.is_empty() else "请愿人",
		"request": summary if not summary.is_empty() else title,
		"background": "至德元载，灵武行在初立，军政、供给与奏报都需在战时秩序中重新厘定。",
		"stakes": "此议会影响眼前的供给、军心或朝廷秩序；批准、驳回与暂缓各有代价。",
		"decision_note": "可亲自裁定，或交由已知大臣办理。"
	}
	match request_type:
		"ask_for_grain":
			briefing["request"] = "朔方军请先拨付行在可调粮草，并核定后续转运次序。"
			briefing["background"] = "安史乱中，朔方军是唐廷反攻的重要兵力；灵武行在的仓储与北方军需必须同时维持。"
			briefing["stakes"] = "批准可稳住军粮与军心，但会压缩行在储备；驳回可保留粮食，却可能延误前线；暂缓则先核账与查明粮道。"
		"request_grain_relief":
			briefing["request"] = "请核定灵武仓粮与赈给名册，并决定是否先行发放救济。"
			briefing["background"] = "行在聚集军民与随驾人众，仓粮、转运和难民配给相互牵动；账目不清会放大抢粮与冒领传闻。"
			briefing["stakes"] = "批准赈给能安定人心但消耗库存；驳回可守住仓粮但会加剧怨气；暂缓可先复核名册与粮册。"
		"request_emergency_grain":
			briefing["request"] = "请以紧急名义调拨一批粮草，并决定由军前、行在还是转运仓优先受领。"
			briefing["background"] = "战时粮道常受敌情、天气和转运能力牵制，临时调拨能救急，也会打乱原有配给次序。"
			briefing["stakes"] = "批准可迅速补缺但会挤压其他用粮；驳回可维持原定配给；暂缓可先核实仓储与沿途运力。"
		"request_audience", "request_intelligence_review":
			briefing["request"] = "请准其当面陈述，并决定由谁复核军报、奏报与传递渠道。"
			briefing["background"] = "灵武新朝草创，来自长安、河东与军中的消息常有先后与互相抵牾，需防止单一渠道垄断判断。"
			briefing["stakes"] = "批准可迅速取得意见，但会增加朝堂牵扯；驳回可压低干扰，却可能错失线索；暂缓可令其先具文书。"
		"request_clear_orders", "request_formal_authority":
			briefing["request"] = "请明定军令、节制范围与执行次序，避免将领收到相互抵牾的命令。"
			briefing["background"] = "安史战局下，朔方、河东等军的调度依赖清晰号令；灵武朝廷既要借重将领，也要防止权责失序。"
			briefing["stakes"] = "批准可提升调度效率，但会形成更强的授权先例；驳回可保留朝廷回旋，代价是军令迟滞；暂缓可先限定期限与复核条件。"
		"demand_reward", "request_cavalry_supply":
			briefing["request"] = "请明确援军的给养、赏赐或市易条件，并划定军纪与调度边界。"
			briefing["background"] = "唐廷在平叛中需要外援与骑兵协作，但任何赏赐与供给承诺都会牵动行在财用、民心和后续谈判。"
			briefing["stakes"] = "批准可换取眼前协力；驳回可减少即时成本却可能失去援助；暂缓可争取复核条件与分期履行。"
		"demand_reward_terms":
			briefing["request"] = "请先议定赏赐的数额、交付时点与军功凭据，再决定是否作出承诺。"
			briefing["background"] = "战时盟友与将士重视赏格是否可信；含混的许诺会在军中和市易中留下日后争执。"
			briefing["stakes"] = "批准可稳住合作预期；驳回可保留财用；暂缓可将承诺改为分期、验功后兑现。"
		"lobby_appointment":
			briefing["request"] = "请补授一名转运、市集或值守官，并明确其掌管的文书与钱粮权限。"
			briefing["background"] = "灵武行在官署草创，空缺职位既关系办事效率，也会改变谁能接触账目、门禁和人事。"
			briefing["stakes"] = "批准可尽快补足人手；驳回可避免仓促任用；暂缓可先限定职权并征询其他大臣。"
		"propose_sunset_clause":
			briefing["request"] = "请让临时授权先行生效，同时写明复核日期、适用范围与撤销条件。"
			briefing["background"] = "战时权宜措施常因紧急而扩大；设定期限可保留行动速度，也防止临时军政权力变成常例。"
			briefing["stakes"] = "批准可兼顾效率与制衡；驳回会使授权争论继续；暂缓则可能错过眼前处置窗口。"
		"request_household_protection", "request_succession_assurance":
			briefing["request"] = "请核定随驾家眷的安全、名册与供给，并明确由谁负责值守和传令。"
			briefing["background"] = "行在不稳时，内廷安全与继嗣传闻容易影响朝臣和军中判断；家眷供给也牵连有限的粮食与人手。"
			briefing["stakes"] = "批准可安定内廷与相关人心；驳回可减少特支；暂缓可先清册、分等配给并查验值守。"
		"request_amnesty":
			briefing["request"] = "请决定是否对一批涉事军民从宽处置，并划定可赦与不可赦的范围。"
			briefing["background"] = "战乱中离散、逃亡和临时失序难以尽数按常法追究；宽严失当都会影响军纪与地方归附。"
			briefing["stakes"] = "批准可争取人心但可能削弱震慑；驳回可维护法度却会加深离心；暂缓可先核实首从与情节。"
		"seek_private_advice", "seek_private_audience":
			briefing["request"] = "请准其私下陈述一项不宜在众人前展开的建议，并决定是否留下书面记录。"
			briefing["background"] = "灵武朝廷的军政决定常夹杂派系与信息不对称，私下陈述可补充线索，也容易绕开公开复核。"
			briefing["stakes"] = "批准可获得额外判断；驳回可守住公开程序；暂缓可要求先递密封文书并由可信者复核。"
		_:
			if requester_id == "zhang_liangdi":
				briefing["request"] = "请核定随驾家眷的口粮、名册与值守安排。"
				briefing["background"] = "行在草创时，内廷供给既关乎秩序，也容易引发冒领与偏私的议论。"
				briefing["stakes"] = "批准可安定随驾人心；驳回可节省给养却会加重不安；暂缓可先清点名册并限定口粮。"
	if not summary.is_empty() and not _is_generic_summary(summary):
		briefing["request"] = summary
	var requester_context := _requester_context(requester_id, requester_name)
	if not requester_context.is_empty():
		briefing["background"] = "%s %s" % [briefing["background"], requester_context]
	return briefing.duplicate(true)

func _request_type_from_id(request_id: String) -> String:
	var normalized := request_id.to_lower()
	for known_type in [
		"request_intelligence_review", "request_household_protection", "request_succession_assurance",
		"request_formal_authority", "request_emergency_grain", "request_cavalry_supply",
		"request_grain_relief", "request_clear_orders", "request_audience", "request_amnesty",
		"seek_private_audience", "seek_private_advice", "propose_sunset_clause",
		"lobby_appointment", "demand_reward_terms", "demand_reward", "ask_for_grain"
	]:
		if normalized.contains(known_type):
			return known_type
	return ""

func _requester_context(requester_id: String, requester_name: String) -> String:
	match requester_id:
		"guo_ziyi": return "%s所部承担北方军务，他的陈情首先牵动前线调度与军心。" % requester_name
		"li_bi": return "%s熟悉朝中消息与谋划，他的说法应与军报、奏报交叉核对。" % requester_name
		"li_fuguo": return "%s经手内廷与文书通道，此议会影响门禁、传令与人事秩序。" % requester_name
		"zhang_liangdi": return "%s关注随驾内廷的安危，此事会直接影响家眷名册和日常供给。" % requester_name
		"uighur_envoy": return "%s代表外援提出条件，任何承诺都将影响后续协作与财用。" % requester_name
		_: return "此议由%s提出，仍应结合其职责、既有承诺与当前证据裁量。" % requester_name

func _with_case_context(summary: String, requester_id: String, requester_name: String, request_type: String) -> String:
	var context := _case_context(requester_id, requester_name, request_type)
	if context.is_empty() or summary.contains(context):
		return summary
	return "%s %s" % [summary, context]

func _case_context(requester_id: String, requester_name: String, request_type: String) -> String:
	match requester_id:
		"guo_ziyi": return "郭子仪请以朔方军前营的粮道与号令为凭，限期回报。"
		"li_bi": return "李泌请先比对军报、奏疏与使者口供，再决定是否施行。"
		"li_fuguo": return "李辅国称宫门登记和中书传递已有脱节，须先厘清经手人。"
		"zhang_liangdi": return "张良娣指出随驾家眷的名册与口粮发生争议，望先安定内廷。"
		"uighur_envoy": return "回纥使者要求将供给、赏赐和出兵时点写入可核验的约定。"
		"li_yu": return "李俶主张先稳住朝臣与军中观望者，再以公开程序给出答复。"
		_: return "%s请就此事给出可执行的书面处置。" % requester_name if not requester_name.is_empty() and not request_type.is_empty() else ""

func _is_generic_summary(summary: String) -> bool:
	return summary.contains("就当前局势提出了一项可核查的请求")

func delegate(state, request_id: String, delegate_id: String) -> Dictionary:
	if state == null:
		return _fail("routine request requires a writable state")
	var index := _pending_index(state, request_id)
	if index < 0:
		return _fail("pending request not found")
	var request: Dictionary = state.pending_requests[index].duplicate(true)
	if str(request.get("status", "")) != "pending":
		return _fail("request is unavailable")
	if not _valid_candidates(request.get("delegation_candidates", [])).has(delegate_id):
		return _fail("delegate is unavailable")
	var resolve_day := int(state.current_day) + MIN_DELEGATION_DAYS + posmod(
		_seed(int(request.get("created_day", state.current_day)), request_id + delegate_id),
		MAX_DELEGATION_DAYS - MIN_DELEGATION_DAYS + 1
	)
	request["status"] = "delegated"
	request["delegate_id"] = delegate_id
	request["resolve_day"] = resolve_day
	_replace_pending(state, index, request)
	return {"ok": true, "request": request.duplicate(true)}

func begin_personal_resolution(state, request_id: String) -> Dictionary:
	var request := get_pending_request(state, request_id)
	if request.is_empty() or str(request.get("status", "")) != "pending":
		return _fail("request is unavailable")
	return {
		"ok": true,
		"request": request.duplicate(true),
		"decision_context": {"request_id": request_id}
	}

func begin_free_talk(state, request_id: String, raw_proposal: Dictionary) -> Dictionary:
	if state == null:
		return _fail("routine request requires a writable state")
	var index := _pending_index(state, request_id)
	if index < 0:
		return _fail("pending request not found")
	var request: Dictionary = state.pending_requests[index].duplicate(true)
	if str(request.get("status", "")) != "pending":
		return _fail("request is unavailable")
	var validation := TalkResolutionServiceScript.new().validate_persisted(request, raw_proposal)
	if not bool(validation.get("ok", false)):
		return validation
	var proposal: Dictionary = validation.duplicate(true)
	request["status"] = "personal_talk_pending"
	request["talk_proposal"] = proposal
	request["resolve_day"] = int(state.current_day) + int(proposal.get("delay_days", 2))
	_replace_pending(state, index, request)
	return {"ok": true, "request": request.duplicate(true)}

func resolve_personal(state, request_id: String, decision_id: String) -> Dictionary:
	if state == null or not state.has_method("record_resolved_request"):
		return _fail("routine request requires a writable state")
	if not ["approve", "reject", "defer"].has(decision_id):
		return _fail("personal decision is unavailable")
	var index := _pending_index(state, request_id)
	if index < 0:
		return _fail("pending request not found")
	var request: Dictionary = state.pending_requests[index].duplicate(true)
	if str(request.get("status", "")) != "pending":
		return _fail("request is unavailable")
	var plan: Dictionary = _plan_personal_effects(state, request, decision_id)
	if not plan.get("ok", false):
		return plan
	var snapshot: Dictionary = state.to_dictionary().duplicate(true)
	var effect_result: Dictionary = RuleEngineScript.new().apply_effects(state, plan.get("immediate_effects", []))
	if not effect_result.get("ok", false):
		_restore_state(state, snapshot)
		return effect_result
	for task in plan.get("tasks", []):
		state.active_tasks.append((task as Dictionary).duplicate(true))
	_remove_pending(state, index)
	var result := _personal_result(request, decision_id, int(state.current_day))
	state.record_resolved_request(result)
	return {"ok": true, "result": result.duplicate(true), "tasks": plan.get("tasks", []).duplicate(true)}

func settle(state, scenario_data: Dictionary = {}) -> Dictionary:
	if state == null or not state.has_method("record_resolved_request"):
		return _fail("routine request requires a writable state")
	var remaining: Array = []
	var resolved: Array = []
	for raw_request in state.pending_requests:
		if not (raw_request is Dictionary):
			continue
		var request: Dictionary = raw_request.duplicate(true)
		var status := str(request.get("status", ""))
		if status == "delegated" and int(state.current_day) >= int(request.get("resolve_day", 0)):
			resolved.append(_resolve_delegation(state, request, scenario_data))
		elif status == "personal_talk_pending" and int(state.current_day) >= int(request.get("resolve_day", 0)):
			var talk_resolution := _resolve_talk(state, request)
			if bool(talk_resolution.get("ok", false)):
				resolved.append(talk_resolution.get("result", {}).duplicate(true))
			else:
				# A corrupted persisted proposal must not remain pending and retry forever.
				resolved.append(_talk_settlement_fallback(request))
		elif status == "pending" and int(state.current_day) >= int(request.get("due_day", 0)):
			resolved.append(_resolve_expired(state, request))
		else:
			remaining.append(request)
	state.pending_requests = remaining
	for item in resolved:
		state.record_resolved_request(item)
	return {"ok": true, "resolved": resolved.duplicate(true)}

func _resolve_talk(state, request: Dictionary) -> Dictionary:
	# Settlement never contacts an AI service.  It only consumes the proposal that
	# was validated and persisted when the player submitted the conversation.
	var validation := TalkResolutionServiceScript.new().validate_persisted(request, request.get("talk_proposal", {}))
	if not bool(validation.get("ok", false)):
		return validation
	var proposal: Dictionary = validation
	var effect_key := "defer" if str(proposal.get("outcome", "")) == "compromise" else str(proposal.get("outcome", ""))
	var effect_request := request.duplicate(true)
	effect_request["personal_effects"] = {effect_key: proposal.get("effects", []).duplicate(true)}
	var plan: Dictionary = _plan_personal_effects(state, effect_request, effect_key)
	if not bool(plan.get("ok", false)):
		return plan
	var snapshot: Dictionary = state.to_dictionary().duplicate(true)
	var effect_result: Dictionary = RuleEngineScript.new().apply_effects(state, plan.get("immediate_effects", []))
	if not bool(effect_result.get("ok", false)):
		_restore_state(state, snapshot)
		return effect_result
	for task in plan.get("tasks", []):
		state.active_tasks.append((task as Dictionary).duplicate(true))
	var result := {
		"visible_title": "谈话回报：%s" % str(request.get("title", "请愿")),
		"visible_summary": str(proposal.get("summary", "谈话已结算。")),
		"outcome": str(proposal.get("outcome", "defer")),
		"day": int(state.current_day),
		"source_label": "谈话回报",
		"confidence": 1.0,
		"severity": "ordinary",
		"used_fallback": false
	}
	return {
		"ok": true,
		"result": result
	}

func _talk_settlement_fallback(request: Dictionary) -> Dictionary:
	return {
		"visible_title": "Talk report: %s" % str(request.get("title", "request")),
		"visible_summary": "The stored talk result failed validation. No effects were applied; the request is deferred for review.",
		"outcome": "defer",
		"day": int(request.get("resolve_day", 0)),
		"source_label": "谈话回报",
		"confidence": 1.0,
		"severity": "ordinary",
		"used_fallback": true
	}

func _valid_candidates(raw_candidates: Variant) -> Array:
	if not (raw_candidates is Array):
		return []
	var candidates: Array = []
	for raw_candidate in raw_candidates:
		var candidate_id := str(raw_candidate).strip_edges()
		if not candidate_id.is_empty() and not candidates.has(candidate_id):
			candidates.append(candidate_id)
	return candidates

func _pending_index(state, request_id: String) -> int:
	if request_id.is_empty():
		return -1
	for index in state.pending_requests.size():
		var raw_request: Variant = state.pending_requests[index]
		if raw_request is Dictionary and str(raw_request.get("request_id", "")) == request_id:
			return index
	return -1

func _replace_pending(state, index: int, request: Dictionary) -> void:
	var replacement: Array = state.pending_requests.duplicate(true)
	replacement[index] = request.duplicate(true)
	state.pending_requests = replacement

func _remove_pending(state, index: int) -> void:
	var remaining: Array = state.pending_requests.duplicate(true)
	remaining.remove_at(index)
	state.pending_requests = remaining

func _resolve_delegation(state, request: Dictionary, scenario_data: Dictionary) -> Dictionary:
	var delegate_id := str(request.get("delegate_id", ""))
	var delegate_name := _character_name(state, delegate_id, "Delegate")
	var factors := _delegation_score(state, request, _scenario_character(scenario_data, delegate_id), scenario_data)
	var score := int(factors.get("score", 0))
	var outcome := "failure"
	var confidence := 0.48
	if score >= 70:
		outcome = "success"
		confidence = 0.86
	elif score >= 45:
		outcome = "compromise"
		confidence = 0.68
	var title := "%s completed %s" % [delegate_name, str(request.get("title", ""))]
	var summary := _delegation_summary(delegate_name, str(request.get("requester_name", "requester")), outcome)
	return {
		"visible_title": title,
		"visible_summary": summary,
		"outcome": outcome,
		"day": int(state.current_day),
		"source_label": "Delegation report",
		"confidence": confidence,
		"outcome_basis": _coarse_outcome_basis(score)
	}

func _coarse_outcome_basis(score: int) -> String:
	if score >= 70:
		return "favorable"
	if score >= 45:
		return "mixed"
	return "unfavorable"

func _personal_result(request: Dictionary, decision_id: String, day: int) -> Dictionary:
	var title := str(request.get("title", "request"))
	var outcome := "success" if decision_id == "approve" else ("failure" if decision_id == "reject" else "compromise")
	var action_label: String = str({"approve": "Approved", "reject": "Rejected", "defer": "Deferred"}.get(decision_id, "Resolved"))
	var bargain_outcomes: Dictionary = request.get("bargain_outcomes", {})
	var bargain_outcome: Dictionary = bargain_outcomes.get(decision_id, {})
	var summary := str(bargain_outcome.get("public_text", "")).strip_edges()
	if summary.is_empty():
		summary = _personal_summary(str(request.get("requester_name", "requester")), decision_id)
	var result := {
		"visible_title": "%s: %s" % [action_label, title],
		"visible_summary": summary,
		"outcome": outcome,
		"day": day,
		"source_label": "Personal ruling",
		"confidence": 1.0
	}
	if request.has("bargain_id"):
		result["bargain_id"] = str(request.get("bargain_id", ""))
		result["counterpart_character_id"] = str(request.get("counterpart_character_id", ""))
	return result

func _personal_summary(requester_name: String, decision_id: String) -> String:
	match decision_id:
		"approve": return "%s's request has been approved and will be carried out." % requester_name
		"reject": return "%s's request has been denied." % requester_name
		_: return "%s's request has been deferred for further review." % requester_name

func _delegation_score(state, request: Dictionary, delegate: Dictionary, scenario_data: Dictionary) -> Dictionary:
	var requester_id := str(request.get("requester_id", ""))
	var relationships: Dictionary = delegate.get("relationships", {}) if delegate.get("relationships", {}) is Dictionary else {}
	var requester_relationship := int(relationships.get(requester_id, 0))
	var player_relationship := int(relationships.get(_player_id(scenario_data), _relationship_to_player(state, str(delegate.get("id", "")))))
	var capability := _capability_match(delegate.get("stats", {}), request.get("required_abilities", {}))
	var faction := _faction_alignment(state, delegate, request)
	var agenda := _agenda_alignment(delegate, request)
	var total := 50 + capability + requester_relationship / 2 + player_relationship / 3 + faction + agenda
	var tiebreak_seed := posmod(_seed(int(request.get("created_day", 0)), str(request.get("request_id", "")) + str(delegate.get("id", ""))), 100)
	return {
		"score": clampi(total, 0, 100),
		"capability": capability,
		"requester_relationship": requester_relationship,
		"player_relationship": player_relationship,
		"faction_pressure": faction,
		"core_goals": agenda,
		"tiebreak_seed": tiebreak_seed
	}

func _capability_match(raw_stats: Variant, raw_required: Variant) -> int:
	if not (raw_stats is Dictionary) or not (raw_required is Dictionary) or (raw_required as Dictionary).is_empty():
		return 0
	var total := 0
	var count := 0
	for ability_id in (raw_required as Dictionary).keys():
		var required := int((raw_required as Dictionary).get(ability_id, 0))
		var actual := int((raw_stats as Dictionary).get(ability_id, 0))
		total += clampi((actual - required) / 2, -20, 20)
		count += 1
	return total / count if count > 0 else 0

func _faction_alignment(state, delegate: Dictionary, request: Dictionary) -> int:
	var delegate_faction := str(delegate.get("faction_id", ""))
	var requester_faction := str(request.get("requester_faction_id", ""))
	if delegate_faction.is_empty() or requester_faction.is_empty():
		return 0
	var pressure := 0
	if state != null and state.faction_states is Dictionary:
		var faction_state: Variant = state.faction_states.get(delegate_faction, {})
		if faction_state is Dictionary:
			pressure = int(faction_state.get("pressure", faction_state.get("current_pressure", 0)))
	var alignment := 8 if delegate_faction == requester_faction else -8
	return alignment - clampi(pressure / 20, 0, 5)

func _agenda_alignment(delegate: Dictionary, request: Dictionary) -> int:
	var goals: Variant = delegate.get("core_goals", delegate.get("public_goal", ""))
	var goal_text := " ".join(_string_values(goals)).to_lower()
	var score := 0
	for tag in _string_values(request.get("request_tags", [])):
		if not tag.is_empty() and goal_text.contains(tag.to_lower()):
			score += 4
	return clampi(score, -12, 12)

func _scenario_character(scenario_data: Dictionary, character_id: String) -> Dictionary:
	for raw_character in scenario_data.get("characters", []):
		if raw_character is Dictionary and str((raw_character as Dictionary).get("id", "")) == character_id:
			return (raw_character as Dictionary).duplicate(true)
	return {}

func _player_id(scenario_data: Dictionary) -> String:
	var scenario: Variant = scenario_data.get("scenario", {})
	return str((scenario as Dictionary).get("player_character_id", "li_heng")) if scenario is Dictionary else "li_heng"

func _effects_for(request: Dictionary, decision_id: String) -> Array:
	var personal_effects: Variant = request.get("personal_effects", {})
	if not (personal_effects is Dictionary):
		return []
	var effects: Variant = (personal_effects as Dictionary).get(decision_id, [])
	return effects.duplicate(true) if effects is Array else []

func _plan_personal_effects(state, request: Dictionary, decision_id: String) -> Dictionary:
	var effects := _effects_for(request, decision_id)
	var validation: Dictionary = RuleEngineScript.new()._validate_effects(state, effects)
	if not validation.get("ok", false):
		return validation
	var immediate_effects: Array = []
	var tasks: Array = []
	for raw_effect in effects:
		if not (raw_effect is Dictionary):
			return _fail("invalid configured effect")
		var effect: Dictionary = raw_effect.duplicate(true)
		var effect_type := str(effect.get("type", ""))
		var bound_validation := _validate_configured_effect_bounds(effect)
		if not bound_validation.get("ok", false):
			return bound_validation
		if effect_type == "task_create":
			if tasks.size() >= 1:
				return _fail("a personal ruling may create at most one task")
			var task_plan := _plan_personal_task(state, request, decision_id, effect)
			if not task_plan.get("ok", false):
				return task_plan
			tasks.append(task_plan.get("task", {}).duplicate(true))
		else:
			immediate_effects.append(effect)
	return {"ok": true, "immediate_effects": immediate_effects, "tasks": tasks}

func _validate_configured_effect_bounds(effect: Dictionary) -> Dictionary:
	var effect_type := str(effect.get("type", ""))
	if CONFIGURED_EFFECT_VALUE_LIMITS.has(effect_type):
		var limit := int(CONFIGURED_EFFECT_VALUE_LIMITS[effect_type])
		if absi(int(effect.get("value", 0))) > limit:
			return _fail("configured %s exceeds allowed magnitude" % effect_type)
	if effect_type == "task_create" and int(effect.get("duration_days", 0)) > MAX_CONFIGURED_TASK_DURATION_DAYS:
		return _fail("configured task duration exceeds allowed range")
	return {"ok": true}

func _plan_personal_task(state, request: Dictionary, decision_id: String, effect: Dictionary) -> Dictionary:
	var task_id := "routine_request__%s__%s__%d" % [str(request.get("request_id", "")), decision_id, int(state.current_day)]
	for collection in [state.active_tasks, state.completed_tasks]:
		for raw_task in collection:
			if raw_task is Dictionary and str((raw_task as Dictionary).get("id", "")) == task_id:
				return _fail("personal ruling task already exists")
	var executor_id := str(effect.get("executor_id", ""))
	if not state.character_states.has(executor_id):
		return _fail("unknown task executor")
	var duration_days := int(effect.get("duration_days", 0))
	if duration_days < 1 or duration_days > MAX_CONFIGURED_TASK_DURATION_DAYS:
		return _fail("configured task duration exceeds allowed range")
	return {"ok": true, "task": {
		"id": task_id,
		"name": str(request.get("title", "personal ruling")),
		"decision_id": "",
		"source_event_id": "",
		"source_request_id": str(request.get("request_id", "")),
		"source_event_title": str(request.get("title", "")),
		"executor_id": executor_id,
		"source_type": str(effect.get("source_type", "oral_order")),
		"target": str(effect.get("target", "")),
		"status": "in_progress",
		"risk": str(effect.get("risk", "normal")),
		"created_day": int(state.current_day),
		"due_day": int(state.current_day) + duration_days,
		"resolution_applied": true
	}}

func _restore_state(state, snapshot: Dictionary) -> void:
	state.load_dictionary(snapshot.duplicate(true))
	for key in snapshot.keys():
		var value: Variant = snapshot[key]
		state.set(str(key), value.duplicate(true) if value is Dictionary or value is Array else value)

func _personal_effects(raw_effects: Variant) -> Dictionary:
	if not (raw_effects is Dictionary):
		return {}
	var copied: Dictionary = {}
	for decision_id in ["approve", "reject", "defer"]:
		var effects: Variant = (raw_effects as Dictionary).get(decision_id, [])
		if effects is Array:
			copied[decision_id] = effects.duplicate(true)
	return copied

func _numeric_dictionary(raw_values: Variant) -> Dictionary:
	if not (raw_values is Dictionary):
		return {}
	var values: Dictionary = {}
	for key in (raw_values as Dictionary).keys():
		if typeof((raw_values as Dictionary)[key]) in [TYPE_INT, TYPE_FLOAT]:
			values[str(key)] = int((raw_values as Dictionary)[key])
	return values

func _string_values(raw_values: Variant) -> Array:
	var values: Array = []
	if raw_values is String:
		var value := str(raw_values).strip_edges()
		if not value.is_empty(): values.append(value)
	elif raw_values is Array:
		for raw_value in raw_values:
			var value := str(raw_value).strip_edges()
			if not value.is_empty() and not values.has(value): values.append(value)
	return values

func _resolve_delegation_legacy(state, request: Dictionary) -> Dictionary:
	var delegate_id := str(request.get("delegate_id", ""))
	var delegate_name := _character_name(state, delegate_id, "受托官员")
	var relationship := _relationship_to_player(state, delegate_id)
	var pressure := _average_faction_pressure(state)
	var score := posmod(_seed(int(request.get("created_day", 0)), str(request.get("request_id", "")) + delegate_id), 100)
	score += relationship
	score -= int(pressure / 4)
	var outcome := "failure"
	var confidence := 0.48
	if score >= 75:
		outcome = "success"
		confidence = 0.86
	elif score >= 38:
		outcome = "compromise"
		confidence = 0.68
	var title := "%s办结%s" % [delegate_name, str(request.get("title", ""))]
	var summary := _delegation_summary(delegate_name, str(request.get("requester_name", "请求方")), outcome)
	return {
		"visible_title": title,
		"visible_summary": summary,
		"outcome": outcome,
		"day": int(state.current_day),
		"source_label": "委派回报",
		"confidence": confidence
	}

func _resolve_expired(state, request: Dictionary) -> Dictionary:
	var requester_name := str(request.get("requester_name", "请求方")).strip_edges()
	var bargain_outcomes: Dictionary = request.get("bargain_outcomes", {})
	var bargain_outcome: Dictionary = bargain_outcomes.get("expire", {})
	if not bargain_outcome.is_empty():
		var petitioner_id := str(request.get("requester_id", ""))
		var counterpart_id := str(request.get("counterpart_character_id", ""))
		var effects: Array = []
		var pet_delta := int(bargain_outcome.get("petitioner_relationship", 0))
		if pet_delta != 0 and !petitioner_id.is_empty():
			effects.append({"type": "relationship_delta", "target": petitioner_id, "value": pet_delta})
		var pet_mem := str(bargain_outcome.get("petitioner_memory", "")).strip_edges()
		if !pet_mem.is_empty() and !petitioner_id.is_empty():
			effects.append({"type": "character_memory", "target": petitioner_id, "value": pet_mem})
		var cou_delta := int(bargain_outcome.get("counterpart_relationship", 0))
		if cou_delta != 0 and !counterpart_id.is_empty():
			effects.append({"type": "relationship_delta", "target": counterpart_id, "value": cou_delta})
		var cou_mem := str(bargain_outcome.get("counterpart_memory", "")).strip_edges()
		if !cou_mem.is_empty() and !counterpart_id.is_empty():
			effects.append({"type": "character_memory", "target": counterpart_id, "value": cou_mem})
		var faction_pressures: Dictionary = bargain_outcome.get("faction_pressures", {})
		for f_id in faction_pressures.keys():
			effects.append({"type": "faction_delta", "target": str(f_id), "field": "pressure", "value": int(faction_pressures[f_id])})
		RuleEngineScript.new().apply_effects(state, effects)
		var public_text := str(bargain_outcome.get("public_text", ""))
		return {
			"visible_title": "%s的请求已逾期" % requester_name,
			"visible_summary": public_text if !public_text.is_empty() else "此事在期限内未获处置，相关安排暂未落实。",
			"outcome": "failure",
			"day": int(state.current_day),
			"source_label": "待办结算",
			"confidence": 1.0,
			"bargain_id": str(request.get("bargain_id", "")),
			"counterpart_character_id": counterpart_id
		}
	return {
		"visible_title": "%s的请求已逾期" % requester_name,
		"visible_summary": "此事在期限内未获处置，相关安排暂未落实。",
		"outcome": "failure",
		"day": int(state.current_day),
		"source_label": "待办结算",
		"confidence": 1.0
	}

func _delegation_summary(delegate_name: String, requester_name: String, outcome: String) -> String:
	match outcome:
		"success":
			return "%s已妥善协调此事，%s的主要诉求得到落实。" % [delegate_name, requester_name]
		"compromise":
			return "%s提出折中安排，%s的部分诉求得到满足。" % [delegate_name, requester_name]
		_:
			return "%s未能按原意办妥此事，%s的诉求暂告落空。" % [delegate_name, requester_name]

func _character_name(state, character_id: String, fallback: String) -> String:
	if state == null or not (state.character_states is Dictionary):
		return fallback
	var character: Variant = state.character_states.get(character_id, {})
	if character is Dictionary:
		var display_name := str(character.get("name", "")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return fallback

func _relationship_to_player(state, character_id: String) -> int:
	if state == null or not (state.character_states is Dictionary):
		return 0
	var character: Variant = state.character_states.get(character_id, {})
	if character is Dictionary:
		var relationships: Variant = character.get("relationships", {})
		if relationships is Dictionary:
			return int(relationships.get("li_heng", 0))
	return 0

func _average_faction_pressure(state) -> int:
	if state == null or not (state.faction_states is Dictionary) or state.faction_states.is_empty():
		return 0
	var total := 0
	var count := 0
	for raw_faction in state.faction_states.values():
		if raw_faction is Dictionary:
			total += int(raw_faction.get("pressure", raw_faction.get("current_pressure", 0)))
			count += 1
	return total / count if count > 0 else 0

func _seed(day: int, value: String) -> int:
	var seed: int = abs(day) * 131
	for index in value.length():
		seed = (seed * 31 + value.unicode_at(index)) % 2147483647
	return seed

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
