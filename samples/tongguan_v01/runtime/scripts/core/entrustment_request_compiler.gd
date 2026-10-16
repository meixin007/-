extends RefCounted

class_name EntrustmentRequestCompiler

const EntrustmentCapabilityRegistryScript = preload("res://scripts/core/entrustment_capability_registry.gd")

const RESOLUTION_CLASSES := [
	"supported",
	"composable",
	"partial",
	"needs_clarification",
	"blocked_by_context",
	"impossible_in_world",
	"unsupported_capability",
	"conversation_only"
]

var registry = EntrustmentCapabilityRegistryScript.new()

func compile_request(dto: Dictionary, context: Dictionary = {}, state = null) -> Dictionary:
	var speech_act := str(dto.get("speech_act", "unknown")).strip_edges()
	var raw_text := str(dto.get("evidence_text", dto.get("raw_text", ""))).strip_edges()
	
	# 1. Non-action / conversational speech acts
	if speech_act in ["chit_chat", "joke", "hypothetical", "quote", "greeting"] or _is_joke_or_hypothetical(raw_text):
		return _build_result("conversation_only", {
			"summary": "非执行性闲谈或假设探讨",
			"explanation": "此话为闲聊、引述或假设探讨，无需立案执行。",
			"system_boundary_note": "",
			"suggested_next_steps": ["继续交谈", "提出具体托付", "结束召对"]
		})

	if speech_act == "ask_info" or _is_mere_inquiry(raw_text):
		return _build_result("conversation_only", {
			"summary": "打听门路或询问线索",
			"explanation": "此话仅为打听风声或询问何处有门路，尚未托付对方采取行动。",
			"system_boundary_note": "",
			"suggested_next_steps": ["请对方代为留意物色", "打听其他消息"]
		})

	# 2. Existing task query / cancel / modify
	var existing_ref := str(dto.get("existing_task_ref", "")).strip_edges()
	if speech_act == "cancel" or _is_cancel_request(raw_text):
		return _compile_cancel_request(existing_ref, context, state)
	if speech_act == "query_progress" or _is_progress_inquiry(raw_text):
		return _compile_query_request(existing_ref, context, state)

	# 3. Impossible in world (e.g. pluck moon, resurrect dead)
	if _is_impossible_in_world(raw_text, dto):
		return _build_result("impossible_in_world", {
			"summary": "世间常理不容",
			"explanation": "所请之事超出天理人事常轨，非人力所能及。",
			"system_boundary_note": "该请求违背当前世界常理，不可受理。",
			"suggested_next_steps": ["改议常理可行之事", "暂且作罢"]
		})

	# 4. Check for clarification needs: conflicting hard conditions or empty/ambiguous
	var clarification := _check_needs_clarification(dto, raw_text)
	if bool(clarification.get("needs_clarification", false)):
		return _build_result("needs_clarification", {
			"summary": "条件尚不明确或存在冲突",
			"explanation": str(clarification.get("reason", "所提要求尚待明确。")),
			"clarification_questions": clarification.get("questions", []),
			"system_boundary_note": "",
			"suggested_next_steps": clarification.get("questions", [])
		})

	# 5. Check executor availability and context blocking
	var executor_id := str(context.get("executor_id", context.get("npc_id", "")))
	var context_block := _check_context_block(executor_id, state)
	if bool(context_block.get("blocked", false)):
		return _build_result("blocked_by_context", {
			"summary": "受托人当前处境受阻",
			"explanation": str(context_block.get("reason", "当前时机或受托人处境不谐，无法承揽托付。")),
			"system_boundary_note": "受托人当前条件不足，无法受理托付。",
			"suggested_next_steps": ["待其处境好转再议", "改请他人办理"]
		})

	# 5.5 Check if request requires formal imperial court decree
	if bool(dto.get("requires_formal_decree", false)) or _requires_formal_decree(raw_text):
		return _build_result("unsupported_capability", {
			"summary": "须走朝堂廷议明发朝敕",
			"explanation": "军国重务、兵马调动与官爵除授当由中书门下廷议明发朝旨，私下不敢擅专。",
			"system_boundary_note": "国家政务不可作为私人托付办理，请移驾便殿朝堂拟旨发布。",
			"suggested_next_steps": ["移驾朝堂颁布诏敕", "改议私人微服托付"]
		})

	# 6. Analyze proposed goals against Capability Registry
	var proposed_goals: Array = dto.get("proposed_goals", [])
	if proposed_goals.is_empty():
		# Check if raw text hints at unsupported capabilities (e.g. banquet, assassination)
		var unsupported_hint := _detect_unsupported_hint(raw_text)
		if unsupported_hint != "":
			return _build_result("unsupported_capability", {
				"summary": "当前玩法暂未支持",
				"explanation": "所请之事眼下尚无规章通路承办。",
				"system_boundary_note": unsupported_hint,
				"suggested_next_steps": ["改托打听武勇门客", "改议其他政务"]
			})
		return _build_result("needs_clarification", {
			"summary": "未能明悉所托何事",
			"explanation": "未能辨明具体期望受托人经办何事，请进一步说明期望达成的结果。",
			"clarification_questions": ["您是希望物色可用人才，还是打听消息？"],
			"system_boundary_note": "",
			"suggested_next_steps": ["说明希望寻找的人选", "说明具体请求"]
		})

	var covered_goals: Array = []
	var unsupported_goals: Array = []
	for goal in proposed_goals:
		if not (goal is Dictionary):
			continue
		var cap_hint := str(goal.get("capability_hint", "unknown"))
		if registry.is_capability_enabled(cap_hint):
			var val_res := registry.validate_arguments(cap_hint, goal.get("arguments", {}))
			if bool(val_res.get("ok", false)):
				covered_goals.append(goal)
			else:
				var unsupp_goal: Dictionary = goal.duplicate(true)
				unsupp_goal["reject_reason"] = str(val_res.get("error", "invalid_arguments"))
				unsupported_goals.append(unsupp_goal)
		else:
			unsupported_goals.append(goal)

	# Check unmapped requirements
	var unmapped_reqs: Array = dto.get("unmapped_requirements", []).duplicate(true)
	_detect_unmapped_hard_conditions(raw_text, dto, unmapped_reqs)

	# 7. Classify into partial, unsupported, composable, or supported
	if covered_goals.is_empty():
		var note := "当前版本暂未提供此类事务的规则执行器。"
		if not unsupported_goals.is_empty():
			var first_cap := str(unsupported_goals[0].get("capability_hint", ""))
			var cap_def := registry.get_capability(first_cap)
			if not cap_def.is_empty() and cap_def.has("reason"):
				note = str(cap_def.get("reason"))
		return _build_result("unsupported_capability", {
			"summary": "玩法暂未实现",
			"explanation": "此项事务在当前版本中尚无执行规则支持，无法受理。",
			"system_boundary_note": note,
			"suggested_next_steps": ["改托寻访可用武勇之士", "改商议其他事项"]
		})

	if not unsupported_goals.is_empty() or not unmapped_reqs.is_empty():
		# Partial support
		var first_covered_cap := str(covered_goals[0].get("capability_hint", "")) if not covered_goals.is_empty() else ""
		var partial_explanation := "受托人可代为办理寻访并引见门客，但所附带的部分要求暂无法承接。"
		var partial_steps := ["仅委托寻人引见", "先不办了", "重新说明条件"]
		if first_covered_cap == "compile_or_process_work":
			partial_explanation = "受托人可将既有诗文手稿整理装订为一卷册页交付，但所附带的超出范围要求（如全境传诵或凭空新撰百篇）暂无法承接。"
			partial_steps = ["仅装订既有诗卷一册", "先不办了", "重新说明条件"]
		elif first_covered_cap == "craft_item":
			partial_explanation = "受托人可代为督造采办所需器物，但所附带的部分苛刻要求暂无法承接。"
			partial_steps = ["仅委托打造器物", "先不办了", "重新说明条件"]

		var unmapped_notes: Array = []
		for req in unmapped_reqs:
			if req is Dictionary:
				unmapped_notes.append(str(req.get("label", req.get("field_hint", req.get("evidence_text", "")))))
			elif req is String:
				unmapped_notes.append(req)
		
		var suggested_plan := _build_executable_plan(covered_goals, dto, context)
		return _build_result("partial", {
			"summary": "部分可做，超出范围部分需剥离",
			"explanation": partial_explanation,
			"covered_scope": covered_goals.duplicate(true),
			"uncovered_requirements": unmapped_notes,
			"unmapped_conditions": unmapped_notes,
			"suggested_reduced_scope": suggested_plan,
			"compiled_plan": suggested_plan,
			"plan_hash": _calculate_plan_hash(suggested_plan),
			"terms_version": 1,
			"system_boundary_note": "部分硬条件超出系统能力边界。若同意按精简范围办理，可确认受理。",
			"suggested_next_steps": partial_steps
		})

	# Every supported step is retained; execution advances across days and saves.
	if covered_goals.size() > 1:
		var plan := _build_executable_plan(covered_goals, dto, context)
		return _build_result("composable", {
			"summary": "多步骤组合托付",
			"explanation": "已理清前后经办步骤，谈妥后即可依序办理。",
			"compiled_plan": plan,
			"plan_hash": _calculate_plan_hash(plan),
			"terms_version": 1,
			"system_boundary_note": "",
			"suggested_next_steps": ["那就有劳了", "条件再谈", "先作罢"]
		})

	# Single supported goal
	var single_plan := _build_executable_plan(covered_goals, dto, context)
	var single_cap := str(single_plan.get("capability_id", ""))
	var single_exp := "所托事项范围清晰，受托人可依规承接并访查引见。"
	if single_cap == "compile_or_process_work":
		single_exp = "所托诗文手稿系既有作品，受托人可整理誊录并装订成册，如期呈交。"
	elif single_cap == "craft_item":
		single_exp = "所托器物规制清晰，受托人可寻访良匠督造，待铸成后呈递。"
	return _build_result("supported", {
		"summary": "可受理之私人托付",
		"explanation": single_exp,
		"compiled_plan": single_plan,
		"plan_hash": _calculate_plan_hash(single_plan),
		"terms_version": 1,
		"system_boundary_note": "",
		"suggested_next_steps": ["那就有劳了", "细议条件", "先作罢"]
	})

func _build_result(resolution_class: String, payload: Dictionary) -> Dictionary:
	var result := {
		"ok": true,
		"schema_version": EntrustmentCapabilityRegistryScript.SCHEMA_VERSION,
		"resolution_class": resolution_class,
		"summary": str(payload.get("summary", "")),
		"explanation": str(payload.get("explanation", "")),
		"system_boundary_note": str(payload.get("system_boundary_note", "")),
		"suggested_next_steps": payload.get("suggested_next_steps", []).duplicate(true)
	}
	for key in [
		"compiled_plan",
		"plan_hash",
		"terms_version",
		"covered_scope",
		"uncovered_requirements",
		"unmapped_conditions",
		"suggested_reduced_scope",
		"clarification_questions"
	]:
		if payload.has(key):
			result[key] = payload[key]
	return result

func _build_executable_plan(goals: Array, dto: Dictionary, context: Dictionary) -> Dictionary:
	var steps: Array = []
	for i in range(goals.size()):
		var goal: Dictionary = goals[i]
		steps.append({
			"step_id": "step_%d" % (i + 1),
			"capability_id": str(goal.get("capability_hint", "find_person_and_introduce")),
			"arguments": goal.get("arguments", {}).duplicate(true),
			"requirements": goal.get("requirements", []).duplicate(true),
			"status": "pending"
		})
	
	var budget_info: Dictionary = dto.get("budget", {})
	var deadline_info: Dictionary = dto.get("deadline", {})
	
	var plan_args: Dictionary = goals[0].get("arguments", {}) if not goals.is_empty() and goals[0] is Dictionary else {}
	var cap_id := str(goals[0].get("capability_hint", "find_person_and_introduce")) if not goals.is_empty() and goals[0] is Dictionary else "find_person_and_introduce"
	var target_role := str(plan_args.get("target_role", dto.get("target_role", "")))
	var target_item := str(plan_args.get("target_item", dto.get("target_item", "")))
	var target_name := str(plan_args.get("target_name", dto.get("target_name", target_item if not target_item.is_empty() else target_role)))
	var target_type := str(plan_args.get("target_type", dto.get("target_type", "manuscript" if cap_id == "compile_or_process_work" else ("item" if cap_id == "craft_item" else "character"))))
	var task_name := str(plan_args.get("task_name", dto.get("task_name", "")))
	var specialty := str(plan_args.get("specialty", dto.get("specialty", "")))
	var semantic_stat := str(plan_args.get("semantic_stat", dto.get("semantic_stat", "governance")))
	var key_stat_name := str(plan_args.get("key_stat_name", dto.get("key_stat_name", "才干")))
	var default_archetype := "manuscript_book" if target_type == "manuscript" else ("generic_retainer" if target_type == "character" else "generic_item")
	var target_archetype := str(plan_args.get("archetype_id", plan_args.get("target_archetype", default_archetype)))
	var criterion := "manuscript_delivered" if target_type == "manuscript" else ("candidate_introduced" if target_type == "character" else "item_delivered")

	var due_days := int(deadline_info.get("exact_days", plan_args.get("due_days", dto.get("due_days", 3 if target_type == "manuscript" else 5))))
	if due_days <= 0:
		due_days = 3 if target_type == "manuscript" else 5

	return {
		"capability_id": cap_id,
		"target_archetype": target_archetype,
		"target_type": target_type,
		"target_name": target_name,
		"target_role": target_role,
		"target_item": target_item,
		"item_name": str(plan_args.get("item_name", dto.get("item_name", target_name))),
		"item_category": str(plan_args.get("item_category", dto.get("item_category", "BOOK" if target_type == "manuscript" else ""))),
		"work_subtype": str(plan_args.get("work_subtype", dto.get("work_subtype", "poetry_anthology" if target_type == "manuscript" else ""))),
		"source_work_id": str(plan_args.get("source_work_id", dto.get("source_work_id", ""))),
		"source_summary": str(plan_args.get("source_summary", dto.get("source_summary", ""))),
		"author_id": str(plan_args.get("author_id", dto.get("author_id", str(context.get("executor_id", context.get("npc_id", "")))))),
		"author_name": str(plan_args.get("author_name", dto.get("author_name", ""))),
		"editor_id": str(plan_args.get("editor_id", dto.get("editor_id", str(context.get("executor_id", context.get("npc_id", "")))))),
		"volume_count": int(plan_args.get("volume_count", dto.get("volume_count", 1))),
		"task_name": task_name,
		"specialty": specialty,
		"semantic_stat": semantic_stat,
		"key_stat_name": key_stat_name,
		"quantity": int(plan_args.get("quantity", 1)),
		"executor_id": str(context.get("executor_id", context.get("npc_id", ""))),
		"requester_id": str(context.get("requester_id", context.get("player_character_id", "li_heng"))),
		"steps": steps,
		"completion_criterion": criterion,
		"budget": budget_info.duplicate(true),
		"deadline": deadline_info.duplicate(true),
		"normalized_terms": {
			"cost_mode": "none",
			"target_scope": "local_connections",
			"initial_due_days": due_days
		}
	}

func _calculate_plan_hash(plan: Dictionary) -> String:
	return JSON.stringify(plan).sha256_text().substr(0, 16)

func plan_for_step(root_plan: Dictionary, index: int) -> Dictionary:
	var step: Dictionary = root_plan.steps[index]
	var goal := {"capability_hint": step.capability_id, "arguments": step.arguments.duplicate(true), "requirements": step.get("requirements", []).duplicate(true)}
	var dto := {"budget": root_plan.get("budget", {}), "deadline": root_plan.get("deadline", {}), "due_days": int(root_plan.get("normalized_terms", {}).get("initial_due_days", 5))}
	var result := _build_executable_plan([goal], dto, root_plan)
	result.erase("steps")
	for key in ["request_id", "source_session_id", "agreed_turn_summary", "plan_hash", "terms_version", "guaranteed_lead"]:
		if root_plan.has(key): result[key] = root_plan[key]
	return result

func _is_joke_or_hypothetical(text: String) -> bool:
	var lower := text.to_lower()
	if text.contains("不用") or text.contains("不必") or text.contains("随便问问") or text.contains("只是问问") or text.contains("随口问"):
		return true
	return text.contains("开玩笑") or text.contains("逗你玩") or text.contains("若是") or text.contains("如果让你") or text.contains("假如") or lower.contains("just kidding") or lower.contains("what if")

func _is_mere_inquiry(text: String) -> bool:
	return (text.contains("听说哪里") or text.contains("何处有") or text.contains("打听一下何处") or text.contains("何处可寻")) and not (text.contains("替我") or text.contains("帮我") or text.contains("去寻") or text.contains("留意"))

func _is_cancel_request(text: String) -> bool:
	return text.contains("别替我找") or text.contains("不要找了") or text.contains("取消托付") or text.contains("作罢") or text.contains("算了")

func _is_progress_inquiry(text: String) -> bool:
	return text.contains("怎么样了") or text.contains("有消息吗") or text.contains("可有眉目") or text.contains("寻得如何") or text.contains("进展如何")

func _is_impossible_in_world(text: String, dto: Dictionary) -> bool:
	return (text.contains("月亮") and (text.contains("摘") or text.contains("取"))) or text.contains("长生不老") or text.contains("起死回生") or text.contains("复活") or text.contains("已故") or text.contains("死去的人") or text.contains("死人")

func _check_needs_clarification(dto: Dictionary, text: String) -> Dictionary:
	var lower := text.to_lower()
	# Conflicting conditions: zero budget + 0/1 day deadline + 100 quality
	if (text.contains("不许花钱") or text.contains("一分钱不花") or text.contains("不给钱")) and (text.contains("天下第一") or text.contains("绝对忠诚") or text.contains("明天必须") or text.contains("一天内")):
		return {
			"needs_clarification": true,
			"reason": "既要求不费分文，又限期极苛、要求绝顶高手，两者难以兼顾。",
			"questions": [
				"可否稍宽限期？",
				"是否愿出适度盘缠用度？"
			]
		}
	
	# Ambiguous multiple targets without separation
	if (text.contains("找刺客") or text.contains("找宫人")) and (text.contains("再买宝物") or text.contains("再办宴席")) and not text.contains("先"):
		return {
			"needs_clarification": true,
			"reason": "所提多项目标并行，首批托付需明确优先经办的首要目标。",
			"questions": [
				"请问先以物色刺客门客为先，还是办理其他事项？"
			]
		}

	return {"needs_clarification": false}

func _check_context_block(executor_id: String, state) -> Dictionary:
	if executor_id.is_empty():
		return {"blocked": true, "reason": "未指定受托人。"}
	if state != null and state.get("character_states") is Dictionary:
		var char_state: Dictionary = state.character_states.get(executor_id, {})
		var status := str(char_state.get("status", ""))
		if status in ["dead", "imprisoned", "missing", "rebel"]:
			return {"blocked": true, "reason": "受托人已不可委派事务（当前状态：%s）。" % status}
	return {"blocked": false}

func _detect_unsupported_hint(text: String) -> String:
	if text.contains("宴席") or text.contains("酒宴") or text.contains("请客"):
		return "当前版本暂不支持安排宴席。"
	if text.contains("刺杀") or text.contains("暗杀") or text.contains("替我除掉") or text.contains("杀了他"):
		return "当前版本暂不支持执行刺杀行动。"
	if text.contains("造反") or text.contains("谋反调查"):
		return "当前版本暂未开放针对谋反事实的秘密调查指令。"
	if text.contains("喜欢我") or text.contains("爱戴我") or text.contains("好感直接"):
		return "人物情感倾向需经真实交往与政治互动演变，无法直接凭命令达成。"
	if text.contains("每一天都替我办") or text.contains("无限"):
		return "系统不支持无限循环或永久委派承诺。"
	return ""

func _detect_unmapped_hard_conditions(text: String, dto: Dictionary, unmapped_out: Array) -> void:
	if text.contains("左撇子"):
		unmapped_out.append({"label": "习惯用左手（左撇子）", "kind": "unsupported_physical_trait", "evidence_text": "左撇子"})
	if text.contains("善用短兵") or text.contains("短兵器"):
		# Supported via combat / prowess preference, no unmapped flag needed
		pass
	if text.contains("天下第一") or text.contains("武力一百"):
		unmapped_out.append({"label": "保证天下第一/武力满额", "kind": "unsupported_perfection_guarantee", "evidence_text": "天下第一"})
	if text.contains("绝对忠诚"):
		unmapped_out.append({"label": "保证绝对忠诚/绝不背叛", "kind": "unsupported_loyalty_guarantee", "evidence_text": "绝对忠诚"})
	if text.contains("不要让对方知道是我出面") or text.contains("隐去委托"):
		unmapped_out.append({"label": "绝对保密委托来源", "kind": "unsupported_strict_anonymity", "evidence_text": "不要让对方知道是我出面"})
	if text.contains("天下人人都读过") or text.contains("传遍天下") or text.contains("人尽皆知") or text.contains("天下传诵"):
		unmapped_out.append({"label": "全境传播与教化（仅可先整理装订诗卷一册，无法立即令天下人人皆读）", "kind": "unsupported_realm_fame", "evidence_text": "让天下人人都读过"})
	if text.contains("一百首") or text.contains("百首新诗") or text.contains("千首"):
		unmapped_out.append({"label": "凭空新撰百首巨制（仅可先就既有旧诗与近作汇编成册）", "kind": "unsupported_mass_composition", "evidence_text": "写一百首新诗"})

func _compile_cancel_request(existing_ref: String, context: Dictionary, state) -> Dictionary:
	return _build_result("supported", {
		"summary": "取消现存私人托付",
		"explanation": "受托人将终止寻访，停止后续开销与接洽。",
		"compiled_plan": {
			"operation": "cancel_entrustment",
			"target_task_id": existing_ref,
			"executor_id": str(context.get("executor_id", context.get("npc_id", "")))
		},
		"system_boundary_note": "",
		"suggested_next_steps": ["确认取消", "保留托付继续寻找"]
	})

func _compile_query_request(existing_ref: String, context: Dictionary, state) -> Dictionary:
	return _build_result("supported", {
		"summary": "查问托付进展",
		"explanation": "受托人据实禀告当前寻访阶段、已走访门路与预计回话时日。",
		"compiled_plan": {
			"operation": "query_progress",
			"target_task_id": existing_ref,
			"executor_id": str(context.get("executor_id", context.get("npc_id", "")))
		},
		"system_boundary_note": "",
		"suggested_next_steps": ["静候回音", "催促加紧办理", "作罢取消"]
	})

func compile(raw_text_or_dto, executor_id = "", context: Dictionary = {}, state = null) -> Dictionary:
	var ctx := context.duplicate(true)
	if str(executor_id) != "" and not ctx.has("executor_id"):
		ctx["executor_id"] = str(executor_id)
	if raw_text_or_dto is Dictionary:
		return compile_request(raw_text_or_dto, ctx, state)
	elif raw_text_or_dto is String:
		var raw_text: String = raw_text_or_dto
		var parser = load("res://scripts/ai/dialogue_intent_parser.gd").new()
		var dto: Dictionary = parser._build_entrustment_v2_dto("", raw_text)
		return compile_request(dto, ctx, state)
	return {"ok": false, "resolution_class": "unsupported_capability"}

func _requires_formal_decree(text: String) -> bool:
	var military_mobilization := (text.contains("调兵") or text.contains("调拨") or text.contains("开拔") or text.contains("出兵") or text.contains("大军")) and (text.contains("万") or text.contains("千") or text.contains("全军") or text.contains("朔方军"))
	var court_appointment := (text.contains("罢免") or text.contains("革职") or text.contains("封为") or text.contains("拜相") or text.contains("加封")) and (text.contains("宰相") or text.contains("使") or text.contains("节度使") or text.contains("大夫") or text.contains("尚书"))
	var state_finance := (text.contains("征税") or text.contains("加税") or text.contains("免税") or text.contains("免除") or text.contains("两税") or text.contains("赋税") or text.contains("大赦") or text.contains("改元"))
	var decree_keywords := (text.contains("下旨") or text.contains("下诏") or text.contains("传旨") or text.contains("颁诏") or text.contains("颁旨"))
	return military_mobilization or court_appointment or state_finance or decree_keywords


