extends RefCounted

class_name PrivateEntrustmentService

const CharacterGenerationServiceScript = preload("res://scripts/core/character_generation_service.gd")
const CharacterKnowledgeServiceScript = preload("res://scripts/core/character_knowledge_service.gd")
const CharacterDossierServiceScript = preload("res://scripts/core/character_dossier_service.gd")

# Q Control Points for Linear Interpolation:
# [P_common, P_good, P_outstanding, P_rare]
const Q_POINTS: Dictionary = {
	0.0: [0.75, 0.20, 0.045, 0.005],
	0.5: [0.45, 0.37, 0.160, 0.020],
	1.0: [0.20, 0.45, 0.300, 0.050]
}

func evaluate_npc_willingness(state, data: Dictionary, executor_id: String, plan: Dictionary = {}) -> Dictionary:
	var relationship := 0
	if state != null:
		relationship = int(state.character_states.get(executor_id, {}).get("relationships", {}).get(state.player_character_id, 0))
	
	# Negative relationship: refusal or delay
	if relationship < -15:
		return {
			"willingness": "refuse",
			"reason": "彼此心存嫌隙，不愿代办私事。",
			"effort_level": "perfunctory",
			"effective_effort": 0.25,
			"strategy": "perfunctory_delay"
		}
	elif relationship < 0:
		return {
			"willingness": "delay",
			"reason": "近来案牍劳形，恐难分身，先缓数日为宜。",
			"effort_level": "perfunctory",
			"effective_effort": 0.25,
			"strategy": "perfunctory_delay"
		}

	# High relationship / positive
	var effort_level := "normal"
	var effective_effort := 0.60
	var strategy := "sincere"

	if relationship >= 25:
		effort_level = "dedicated"
		effective_effort = 1.00
		strategy = "sincere"
	elif relationship < 10:
		strategy = "seeking_reward"

	return {
		"willingness": "accept",
		"reason": "感念信任，愿代为主持留心访查。",
		"effort_level": effort_level,
		"effective_effort": effective_effort,
		"strategy": strategy
	}

func calculate_quality_probabilities(executor_stats: Dictionary, channel_access: float = 0.5, effective_effort: float = 0.60) -> Dictionary:
	var intrigue_val := float(executor_stats.get("intrigue", 50)) / 100.0
	var diplomacy_val := float(executor_stats.get("diplomacy", 50)) / 100.0
	var prowess_val := float(executor_stats.get("prowess", 50)) / 100.0

	# A = 0.55 * intrigue + 0.45 * diplomacy
	var A := 0.55 * intrigue_val + 0.45 * diplomacy_val
	# Q = clamp(0.65 * A + 0.20 * channel_access + 0.15 * effective_effort, 0, 1)
	var Q := clampf(0.65 * A + 0.20 * channel_access + 0.15 * effective_effort, 0.0, 1.0)

	var p_com: float = 0.0
	var p_good: float = 0.0
	var p_out: float = 0.0
	var p_rare: float = 0.0

	if Q <= 0.5:
		var t := Q / 0.5
		p_com = lerpf(Q_POINTS[0.0][0], Q_POINTS[0.5][0], t)
		p_good = lerpf(Q_POINTS[0.0][1], Q_POINTS[0.5][1], t)
		p_out = lerpf(Q_POINTS[0.0][2], Q_POINTS[0.5][2], t)
		p_rare = lerpf(Q_POINTS[0.0][3], Q_POINTS[0.5][3], t)
	else:
		var t := (Q - 0.5) / 0.5
		p_com = lerpf(Q_POINTS[0.5][0], Q_POINTS[1.0][0], t)
		p_good = lerpf(Q_POINTS[0.5][1], Q_POINTS[1.0][1], t)
		p_out = lerpf(Q_POINTS[0.5][2], Q_POINTS[1.0][2], t)
		p_rare = lerpf(Q_POINTS[0.5][3], Q_POINTS[1.0][3], t)

	var sum := p_com + p_good + p_out + p_rare
	if sum > 0.0:
		p_com /= sum
		p_good /= sum
		p_out /= sum
		p_rare /= sum

	return {
		"A": A,
		"Q": Q,
		"probabilities": {
			"common": p_com,
			"good": p_good,
			"outstanding": p_out,
			"rare": p_rare
		}
	}

func roll_quality_tier(probs: Dictionary, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cum := 0.0
	cum += float(probs.get("common", 0.45))
	if roll < cum:
		return "common"
	cum += float(probs.get("good", 0.35))
	if roll < cum:
		return "good"
	cum += float(probs.get("outstanding", 0.15))
	if roll < cum:
		return "outstanding"
	return "rare"

func create_entrustment_task(state, plan: Dictionary, executor_id: String, requester_id: String = "li_heng", custom_seed: int = -1, register_task: bool = true) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing_state"}
	if executor_id.is_empty():
		return {"ok": false, "error": "executor_id_required"}
	if not state.character_states.has(executor_id) or not state.character_states.has(requester_id):
		return {"ok": false, "error": "托付必须引用实际委托人和经办人。"}
	var has_production: bool = plan.get("capability_id") in ["craft_item", "compile_or_process_work"] or plan.get("target_type") in ["item", "manuscript"] or plan.get("steps", []).any(func(step): return step.get("capability_id") in ["craft_item", "compile_or_process_work"])
	if state.flags.get("managed_inventory_initialized", false) and has_production:
		return {"ok": false, "error": "生产须先商定真实工坊报价与共同授权，不能从旧托付描述直接造物。"}
	var serial_plan := {}
	if plan.get("steps", []).size() > 1:
		var seen: Array = []
		var registry = preload("res://scripts/core/entrustment_capability_registry.gd").new()
		for step in plan.steps:
			if not step is Dictionary or not step.get("step_id") is String or str(step.step_id).is_empty() or seen.has(step.step_id) or step.get("capability_id") not in ["find_person_and_introduce", "craft_item", "compile_or_process_work"] or not step.get("arguments") is Dictionary:
				return {"ok": false, "error": "串行托付含重复标识或尚无执行器的步骤"}
			var valid: Dictionary = registry.validate_arguments(step.capability_id, step.arguments)
			if not valid.get("ok", false): return valid
			seen.append(step.step_id)
		serial_plan = plan.duplicate(true)
		serial_plan["executor_id"] = executor_id
		serial_plan["requester_id"] = requester_id
		plan = preload("res://scripts/core/entrustment_request_compiler.gd").new().plan_for_step(serial_plan, 0)

	var current_day := int(state.current_day)
	var seq := 1
	if state.get("flags") is Dictionary:
		seq = int(state.flags.get("private_entrustment_seq", 0)) + 1
		if register_task: state.flags["private_entrustment_seq"] = seq
	else:
		seq = state.active_tasks.size() + (state.completed_tasks.size() if state.get("completed_tasks") is Array else 0) + 1
	var task_id := "task__private_entrustment__%s__%d__%d" % [executor_id, current_day, seq]
	
	# Determine duration
	var duration := 5
	var norm_terms: Dictionary = plan.get("normalized_terms", {})
	if norm_terms.has("initial_due_days"):
		duration = int(norm_terms.get("initial_due_days", 5))
	elif plan.has("due_days"):
		duration = int(plan.get("due_days", 5))
	elif plan.get("deadline") is Dictionary and (plan.get("deadline") as Dictionary).has("exact_days"):
		duration = int((plan.get("deadline") as Dictionary).get("exact_days", 5))
	if duration <= 0:
		duration = 3

	var rule_seed := custom_seed
	if rule_seed < 0:
		rule_seed = (int(state.flags.get("rule_seed", 107)) + current_day * 31 + seq * 17) & 0x7FFFFFFF

	var willingness_info := evaluate_npc_willingness(state, {}, executor_id, plan)

	var target_type := str(plan.get("target_type", "")).strip_edges()
	if target_type.is_empty():
		if str(plan.get("capability_id", "")) == "compile_or_process_work" or str(plan.get("item_category", "")) == "BOOK":
			target_type = "manuscript"
		elif str(plan.get("target_archetype", "")).begins_with("item") or str(plan.get("intent_type", "")).contains("craft"):
			target_type = "item"
		else:
			target_type = "character"

	var executor_name := _get_character_name(state, executor_id)
	var default_task_name := "整理装订《%s诗卷》一卷" % executor_name if target_type == "manuscript" else ("打造一口宝剑" if target_type == "item" else "寻访武勇门客并引见")
	var task_name := str(plan.get("task_name", default_task_name))
	var default_archetype := "manuscript_book" if target_type == "manuscript" else ("item_sword" if target_type == "item" else "assassin_retainer")
	var archetype_id := str(plan.get("target_archetype", default_archetype))

	var target_role := str(plan.get("target_role", ""))
	var target_item := str(plan.get("target_item", ""))
	var target_name := str(plan.get("target_name", plan.get("item_name", target_item if not target_item.is_empty() else target_role)))
	var item_name := str(plan.get("item_name", target_name))
	var item_category := str(plan.get("item_category", "BOOK" if target_type == "manuscript" else ""))
	var work_subtype := str(plan.get("work_subtype", "poetry_anthology" if target_type == "manuscript" else ""))
	var source_work_id := str(plan.get("source_work_id", "%s_existing_poems" % executor_id if target_type == "manuscript" else ""))
	var source_summary := str(plan.get("source_summary", "收录既有诗作与手稿汇为一卷" if target_type == "manuscript" else ""))
	var author_id := str(plan.get("author_id", executor_id))
	var author_name := str(plan.get("author_name", executor_name))
	var editor_id := str(plan.get("editor_id", executor_id))
	var volume_count := int(plan.get("volume_count", 1))
	var specialty := str(plan.get("specialty", ""))
	var source_org := str(plan.get("source_org", ""))
	var is_plural := bool(plan.get("is_plural", false))
	var default_sem_stat := "prowess" if archetype_id in ["assassin_retainer", "prowess", "guard_retainer"] else ("medicine" if archetype_id in ["physician_retainer", "physician", "doctor"] else "governance")
	var default_key_stat := "武艺" if default_sem_stat == "prowess" else ("医术" if default_sem_stat == "medicine" else "才干")
	var semantic_stat := str(plan.get("semantic_stat", default_sem_stat))
	var key_stat_name := str(plan.get("key_stat_name", default_key_stat))
	var due_day := current_day + duration
	var date_summary := "第 %d 日托付；约定第 %d 日回话；尚余 %d 日" % [current_day, due_day, duration]

	var feedback: Array = []
	if target_type == "manuscript":
		var display_book := item_name if not item_name.is_empty() else (target_item if not target_item.is_empty() else "诗文手卷")
		feedback = [
			"正在校勘誊写与装订卷册（%s）" % date_summary,
			"%s已着手将案头既有稿本逐篇誊清，装订为《%s》一卷，约定第 %d 日呈递。" % [executor_name, display_book, due_day]
		]
	elif target_type == "item":
		var display_item := target_item if not target_item.is_empty() else task_name
		feedback = [
			"采办备料正在加紧办理（%s）" % date_summary,
			"%s已派心腹寻访匠肆良工，加紧督造采办【%s】，约定第 %d 日复命。" % [executor_name, display_item, due_day]
		]
	else:
		var display_role := target_role if not target_role.is_empty() else "可用门客"
		if not specialty.is_empty() and (specialty + display_role).length() <= 12:
			display_role = specialty + "的" + display_role
		var is_guard_sel := target_role.contains("侍卫") or target_role.contains("禁军") or target_role.contains("亲卫") or source_org.contains("禁军")
		if is_guard_sel:
			feedback = [
				"托付已定，正在军中遴选（%s）" % date_summary,
				"%s已奉命于宿卫营伍中遴选【%s】，约定第 %d 日回话。" % [executor_name, display_role, due_day]
			]
		else:
			feedback = [
				"托付已定，正在留心寻访（%s）" % date_summary,
				"%s已着手代为主持物色【%s】，约定第 %d 日回话。" % [executor_name, display_role, due_day]
			]

	var task := {
		"id": task_id,
		"task_id": task_id,
		"task_kind": "private_entrustment",
		"name": task_name,
		"target_type": target_type,
		"target_name": target_name,
		"target_role": target_role,
		"target_item": target_item,
		"item_name": item_name,
		"item_category": item_category,
		"work_subtype": work_subtype,
		"source_work_id": source_work_id,
		"source_summary": source_summary,
		"author_id": author_id,
		"author_name": author_name,
		"editor_id": editor_id,
		"volume_count": volume_count,
		"specialty": specialty,
		"source_org": source_org,
		"is_plural": is_plural,
		"semantic_stat": semantic_stat,
		"key_stat_name": key_stat_name,
		"executor_id": executor_id,
		"requester_id": requester_id,
		"source_type": "private_talk",
		"status": "in_progress",
		"execution_status": "in_progress",
		"report_status": "none",
		"outcome_code": "",
		"outcome_settled": false,
		"stage": "compiling" if target_type == "manuscript" else ("crafting" if target_type == "item" else "searching"),
		"created_day": current_day,
		"due_day": due_day,
		"remaining_days": duration,
		"date_summary": date_summary,
		"next_report_day": due_day,
		"rule_seed": rule_seed,
		"effort_level": str(willingness_info.get("effort_level", "normal")),
		"effective_effort": float(willingness_info.get("effective_effort", 0.60)),
		"strategy": str(willingness_info.get("strategy", "sincere")),
		"archetype_id": archetype_id,
		"candidate_character_id": "",
		"item_result": {},
		"guaranteed_lead": bool(plan.get("guaranteed_lead", false)),
		"request_id": str(plan.get("request_id", "")),
		"source_session_id": str(plan.get("source_session_id", "")),
		"previous_task_id": str(plan.get("previous_task_id", "")),
		"agreed_turn_summary": (plan.get("agreed_turn_summary", {}) as Dictionary).duplicate(true) if plan.get("agreed_turn_summary") is Dictionary else {},
		"plan_hash": str(plan.get("plan_hash", "")),
		"terms_version": int(plan.get("terms_version", 1)),
		"visible_feedback": feedback
	}

	if not serial_plan.is_empty():
		task["serial_plan"] = serial_plan
		task["serial_cursor"] = 0
		task["serial_results"] = []
		task["serial_created_day"] = current_day
		task["serial_seed"] = rule_seed
		task.visible_feedback.push_front("多步托付：正在办理第 1 / %d 步。" % serial_plan.steps.size())
	if register_task: state.active_tasks.append(task)
	return {"ok": true, "task": task.duplicate(true)}

func _complete_current_step(state, task: Dictionary, task_index: int) -> void:
	if task.has("serial_plan"):
		var cursor := int(task.serial_cursor)
		var results: Array = task.serial_results.duplicate(true)
		results.append({"step_id": task.serial_plan.steps[cursor].step_id, "outcome_code": str(task.outcome_code), "candidate_character_id": str(task.get("candidate_character_id", "")), "item_id": str(task.get("item_result", {}).get("id", "")), "completed_day": int(state.current_day), "feedback": task.visible_feedback.duplicate(true)})
		task.serial_results = results
		if cursor + 1 < task.serial_plan.steps.size():
			var next_plan: Dictionary = preload("res://scripts/core/entrustment_request_compiler.gd").new().plan_for_step(task.serial_plan, cursor + 1)
			var next: Dictionary = create_entrustment_task(state, next_plan, task.executor_id, task.requester_id, int(task.serial_seed) + (cursor + 1) * 997, false).task
			for key in ["id", "task_id", "serial_plan", "serial_results", "serial_created_day", "serial_seed"]: next[key] = task[key]
			if task.has("prior_failure_reports"): next["prior_failure_reports"] = task.prior_failure_reports.duplicate(true)
			next["serial_cursor"] = cursor + 1
			next.visible_feedback.push_front("前一步已交割，继续第 %d / %d 步。" % [cursor + 2, task.serial_plan.steps.size()])
			state.active_tasks[task_index] = next
			return
	state.active_tasks.remove_at(task_index)
	state.completed_tasks.append(task.duplicate(true))

func settle_task(state, task: Dictionary) -> Dictionary:
	var current_day := int(state.current_day)
	var due_day := int(task.get("due_day", 0))
	var created_day := int(task.get("created_day", 0))
	var stage := str(task.get("stage", "searching"))
	var executor_id := str(task.get("executor_id", ""))
	var executor_name := _get_character_name(state, executor_id)

	# Idempotency guard: if already settled and awaiting player disposition/report, do not re-roll
	if stage in ["awaiting_introduction", "awaiting_report"] or bool(task.get("outcome_settled", false)):
		return {"ok": true, "status": str(task.get("status", "awaiting_player")), "task": task}

	# Check executor availability (deceased or unreachable)
	var exec_state: Dictionary = state.character_states.get(executor_id, {}) if (state != null and state.get("character_states") is Dictionary and state.character_states.get(executor_id, {}) is Dictionary) else {}
	var exec_status := str(exec_state.get("status", "active")).to_lower()
	var is_exec_dead := (exec_status in ["dead", "deceased"] or bool(exec_state.get("is_dead", false)) or (exec_state.has("alive") and not bool(exec_state.get("alive", true))))
	var is_exec_unreachable := exec_status in ["missing", "imprisoned", "rebel", "hostile", "unreachable"]
	if is_exec_dead or is_exec_unreachable:
		task["status"] = "awaiting_player"
		task["stage"] = "awaiting_report"
		task["execution_status"] = "failed"
		task["report_status"] = "unread_report"
		task["outcome_code"] = "executor_deceased" if is_exec_dead else "executor_unreachable"
		task["outcome_settled"] = true
		task["reported_day"] = current_day
		var t_label := str(task.get("name", "所托事项"))
		if is_exec_dead:
			task["visible_feedback"] = [
				"受托人已身故，差遣中辍",
				"近侍据实禀报：%s已不幸身故，此前所托【%s】无从继续办理，请陛下定夺善后。" % [executor_name, t_label]
			]
		else:
			task["visible_feedback"] = [
				"受托人失联，差遣中辍",
				"近侍据实禀报：%s现已失联或下狱，此前所托【%s】暂无法按期回报，请陛下定夺。" % [executor_name, t_label]
			]
		return {"ok": true, "status": "awaiting_player", "task": task}

	if current_day < due_day:
		var rem := maxi(1, due_day - current_day)
		task["remaining_days"] = rem
		task["date_summary"] = "第 %d 日托付；约定第 %d 日回话；尚余 %d 日" % [created_day, due_day, rem]
		return {"ok": true, "status": "in_progress", "task": task}

	# Due day reached for manuscript / BOOK compilation stage
	if stage == "compiling" or str(task.get("target_type", "")) == "manuscript" or str(task.get("item_category", "")) == "BOOK":
		var p_id_book: String = str(state.player_character_id) if not str(state.player_character_id).is_empty() else "li_heng"
		var p_name_book: String = "天子李亨" if p_id_book == "li_heng" else "当前主公"
		var book_name: String = str(task.get("item_name", task.get("target_name", "")))
		if book_name.is_empty():
			book_name = "%s诗卷" % executor_name if executor_id == "wang_wei" else "%s手订文卷" % executor_name
		var author_id := str(task.get("author_id", executor_id))
		var author_name := str(task.get("author_name", executor_name))
		var editor_id := str(task.get("editor_id", executor_id))
		var source_work_id := str(task.get("source_work_id", "%s_existing_poems" % author_id))
		var source_summary := str(task.get("source_summary", "收录%s既有诗作与手稿校勘汇编为一卷" % author_name))
		var book_id := "item_book_%s_%d_%d" % [author_id, current_day, state.active_tasks.size()]
		var book_dict := {
			"id": book_id,
			"name": book_name,
			"category": "BOOK",
			"tier": 3,
			"tier_name": "手订善本",
			"owner_id": p_id_book,
			"holder_name": p_name_book,
			"author_id": author_id,
			"author_name": author_name,
			"editor_id": editor_id,
			"source_work_id": source_work_id,
			"source_summary": source_summary,
			"volume_count": int(task.get("volume_count", 1)),
			"equippable": false,
			"equipped": false,
			"lore": "由%s亲手将既有旧稿与近作（%s）逐一校勘誊清、装潢成册，墨迹清雅，卷帙端严。" % [author_name, source_summary],
			"effects_summary": "内府雅集典藏善本，可供展卷品读、收入书箧或转赐臣僚（不可作为兵器披挂装备）。",
			"effects": {},
			"actions": ["inspect", "collect", "bestow"]
		}
		task["item_result"] = book_dict
		task["result_item"] = book_dict
		task["stage"] = "awaiting_introduction"
		task["status"] = "awaiting_player"
		task["execution_status"] = "succeeded"
		task["report_status"] = "awaiting_disposition"
		task["outcome_code"] = "manuscript_ready"
		task["outcome_settled"] = true
		task["reported_day"] = current_day
		task["remaining_days"] = 0
		task["date_summary"] = "第 %d 日托付；第 %d 日已回话待呈览" % [created_day, current_day]
		task["visible_feedback"] = [
			"诗文卷册已装订完备，正待呈览",
			"%s已将《%s》一卷校勘装订妥当，捧卷候旨呈览。" % [executor_name, book_name]
		]
		return {"ok": true, "status": "awaiting_player", "item": book_dict, "task": task}

	# Due day reached for crafting stage
	if stage == "crafting" or str(task.get("target_type", "")) == "item" or str(task.get("archetype_id", "")).begins_with("item") or str(task.get("archetype_id", "")) == "generic_item":
		var p_id: String = str(state.player_character_id) if not str(state.player_character_id).is_empty() else "li_heng"
		var p_name: String = "天子李亨" if p_id == "li_heng" else "当前主公"
		var task_name: String = str(task.get("name", "采办物资"))
		var target_item: String = str(task.get("target_item", ""))
		var item_name := target_item
		if item_name.is_empty() or item_name == "宝剑":
			if task_name.contains("宝剑") or task_name.contains("剑") or item_name == "宝剑":
				item_name = "精铸百炼宝剑"
			elif task_name.contains("甲") or task_name.contains("铠"):
				item_name = "精制锁子金甲"
			elif task_name.contains("神兵") or task_name.contains("兵器"):
				item_name = "百炼神兵"
			else:
				item_name = "上等物资"

		var item_id := "item_crafted_%s_%d_%d" % [str(task.get("archetype_id", "item")), current_day, state.active_tasks.size()]
		var item_cat := "EQUIPMENT"
		if item_name.contains("马") or item_name.contains("驹"):
			item_cat = "MOUNT"
		elif item_name.contains("药") or item_name.contains("散") or item_name.contains("丹"):
			item_cat = "MEDICINE"
		elif item_name.contains("甲") or item_name.contains("铠"):
			item_cat = "ARMOR"

		var item_dict := {
			"id": item_id,
			"name": item_name,
			"category": item_cat,
			"tier": 3,
			"tier_name": "上品佳物",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": false,
			"lore": "灵武行在精巧工匠与能吏依圣意采办督造完备，质地精良，足备随驾听用与随身威仪。",
			"effects_summary": "随身武威与护卫戒备提升。",
			"effects": {"prowess": 6, "security": 6},
			"actions": ["equip", "inspect", "bestow"]
		}
		task["item_result"] = item_dict
		task["result_item"] = item_dict
		task["stage"] = "awaiting_introduction"
		task["status"] = "awaiting_player"
		task["execution_status"] = "succeeded"
		task["report_status"] = "awaiting_disposition"
		task["outcome_code"] = "item_ready"
		task["outcome_settled"] = true
		task["reported_day"] = current_day
		task["remaining_days"] = 0
		task["date_summary"] = "第 %d 日托付；第 %d 日已回话待呈递" % [created_day, current_day]
		task["visible_feedback"] = [
			"物品已备齐，正待呈递御前",
			"%s已携办妥之【%s】至行在复命，恭候陛下御览验视。" % [executor_name, item_name]
		]
		return {"ok": true, "status": "awaiting_player", "item": item_dict, "task": task}

	# Due day reached in searching stage: roll outcome
	if stage == "searching":
		var rule_seed := int(task.get("rule_seed", 107))
		var rng := RandomNumberGenerator.new()
		rng.seed = rule_seed + current_day

		var stats := _get_executor_stats(state, executor_id)
		var effort := float(task.get("effective_effort", 0.60))
		var q_calc := calculate_quality_probabilities(stats, 0.5, effort)
		var A: float = q_calc.A
		var clue_prob: float = clampf(0.20 + 0.30 * A + 0.20 * 0.5 + 0.20 * effort + 0.05, 0.05, 0.95)

		var guaranteed: bool = bool(task.get("guaranteed_lead", false))
		if guaranteed or rng.randf() <= clue_prob:
			# Found candidate!
			var tier := roll_quality_tier(q_calc.probabilities, rng)
			var gen = CharacterGenerationServiceScript.new()
			var gen_ctx := {
				"current_day": current_day,
				"executor_id": executor_id,
				"target_role": str(task.get("target_role", "")),
				"source_org": str(task.get("source_org", "")),
				"is_plural": bool(task.get("is_plural", false)),
				"specialties": str(task.get("specialty", "")),
				"dominant_ability": str(task.get("semantic_stat", ""))
			}
			var candidate: Dictionary = gen.generate_character(
				str(task.get("archetype_id", "generic_retainer")),
				tier,
				rule_seed + 999,
				gen_ctx
			)
			
			# Register candidate into GameState
			var reg_res: Dictionary = state.register_dynamic_character(candidate)
			if not bool(reg_res.get("ok", false)):
				# If capacity reached, enter awaiting_report rather than vanishing
				task["status"] = "awaiting_player"
				task["stage"] = "awaiting_report"
				task["execution_status"] = "failed"
				task["report_status"] = "unread_report"
				task["outcome_code"] = "capacity_reached"
				task["outcome_settled"] = true
				task["reported_day"] = current_day
				task["remaining_days"] = 0
				task["date_summary"] = "第 %d 日托付；第 %d 日回话待阅" % [created_day, current_day]
				task["visible_feedback"] = [
					"寻得线索，但行在人物已满",
					"%s于第 %d 日回话：虽觅得人选，但行在随从门客容量已满，未能携之归营，请陛下发落。" % [executor_name, current_day]
				]
				return {"ok": true, "status": "awaiting_player", "task": task}

			var cid: String = str(candidate.get("id", ""))
			var cand_name: String = str(candidate.get("name", cid))
			var cand_role: String = str(candidate.get("role", "可用门客"))
			task["candidate_character_id"] = cid
			task["stage"] = "awaiting_introduction"
			task["status"] = "awaiting_player"
			task["execution_status"] = "succeeded"
			task["report_status"] = "awaiting_disposition"
			task["outcome_code"] = "candidate_ready"
			task["outcome_settled"] = true
			task["reported_day"] = current_day
			task["remaining_days"] = 0
			task["date_summary"] = "第 %d 日托付；第 %d 日已回话待引见" % [created_day, current_day]

			var is_plural := bool(task.get("is_plural", false))
			var is_guard := cand_role.contains("侍卫") or cand_role.contains("禁军") or cand_role.contains("亲卫") or str(task.get("source_org", "")).contains("禁军")
			var name_display := (cand_name + "等") if is_plural else cand_name
			if is_guard:
				task["visible_feedback"] = [
					"已选得精锐人选，正待引见",
					"%s携所选【%s】%s至行在候见。" % [executor_name, cand_role, name_display]
				]
			else:
				task["visible_feedback"] = [
					"已寻得可用之人，正待引见",
					"%s携%s【%s】%s至行在候见。" % [executor_name, ("所选" if is_plural else ""), cand_role, name_display]
				]

			# Record initial knowledge claim for candidate key stat
			var cand_stats: Dictionary = candidate.get("stats", {})
			var claim_field := str(candidate.get("dominant_ability", task.get("semantic_stat", "governance")))
			var real_val: int = int(cand_stats.get(claim_field, 50))

			var knowledge_svc := CharacterKnowledgeServiceScript.new()
			var est_min := clampi(int(floor(float(real_val - 5) / 10.0)) * 10, 0, 100)
			var est_max := clampi(int(ceil(float(real_val + 5) / 10.0)) * 10, 0, 100)
			if est_max <= est_min: est_max = mini(100, est_min + 15)
			knowledge_svc.record_claim(state, cid, claim_field, {
				"status": "estimated",
				"min": est_min,
				"max": est_max,
				"confidence": 0.85,
				"source_id": "introducer_recommendation",
				"acquired_day": current_day
			})
			return {"ok": true, "status": "awaiting_player", "candidate": candidate, "task": task}
		else:
			# Honest failure: enter awaiting_report instead of silently archiving so player can read/dispose
			task["status"] = "awaiting_player"
			task["stage"] = "awaiting_report"
			task["execution_status"] = "failed"
			task["report_status"] = "unread_report"
			task["outcome_code"] = "honest_failure"
			task["outcome_settled"] = true
			task["reported_day"] = current_day
			task["remaining_days"] = 0
			task["date_summary"] = "第 %d 日托付；第 %d 日回话待阅" % [created_day, current_day]
			var target_desc := str(task.get("target_role", "合适门客"))
			if target_desc.is_empty():
				target_desc = "合适门客"
			task["visible_feedback"] = [
				"走访数日，未逢合适之人",
				"%s于第 %d 日据实回话：遍访附近门路，暂未寻得合宜之【%s】，特来复命请示。" % [executor_name, current_day, target_desc]
			]
			state.add_character_memory(
				executor_id,
				"%s代为访查【%s】数日，未遇合宜之人，据实复命。" % [executor_name, target_desc]
			)
			return {"ok": true, "status": "awaiting_player", "task": task}

	return {"ok": true, "status": str(task.get("status", "in_progress")), "task": task}

func resolve_introduction(state, scenario_data: Dictionary, task_id: String, choice: String, options: Dictionary = {}) -> Dictionary:
	return resolve_introduction_choice(state, task_id, choice, options)

func resolve_introduction_choice(state, task_id: String, choice: String, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing_state"}

	var found_task: Dictionary = {}
	var task_index := -1
	for i in range(state.active_tasks.size()):
		var t: Dictionary = state.active_tasks[i]
		var tid := str(t.get("id", t.get("task_id", "")))
		if tid == task_id or (task_id.is_empty() and str(t.get("stage", "")) in ["awaiting_report", "awaiting_introduction"]):
			found_task = t
			task_index = i
			break

	if found_task.is_empty():
		return {"ok": false, "error": "task_not_found"}
	if found_task.has("serial_plan") and not str(options.get("expected_step_id", "")).is_empty() and options.expected_step_id != found_task.serial_plan.steps[int(found_task.serial_cursor)].step_id:
		return {"ok": false, "error": "托付已推进到另一步，请重新查看当前回报。"}

	# Handle report disposition choices for failed/unfulfilled entrustment reports
	if choice in ["acknowledge_report", "dismiss_report"]:
		var exec_id_ack := str(found_task.get("executor_id", ""))
		var target_desc_ack := str(found_task.get("target_role", found_task.get("name", "所托事项")))
		state.add_character_memory(exec_id_ack, "向主公禀明寻访【%s】未果之情由，已获主公批阅知悉。" % target_desc_ack)
		found_task["status"] = "completed"
		found_task["stage"] = "failed_archived"
		found_task["report_status"] = "read_and_archived"
		found_task["completed_day"] = int(state.current_day)
		found_task["visible_feedback"] = [
			"已批阅知悉并归档",
			"主公已知悉【%s】寻访未果之回报，事项归入旧档。" % str(found_task.get("name", target_desc_ack))
		]
		state.active_tasks.remove_at(task_index)
		state.completed_tasks.append(found_task.duplicate(true))
		return {"ok": true, "action": "acknowledged_report", "task": found_task.duplicate(true)}

	if choice in ["continue_search", "re_entrust"]:
		if found_task.has("serial_plan"):
			if found_task.get("stage") != "awaiting_report" or found_task.get("execution_status") != "failed": return {"ok": false, "error": "当前步骤尚无可重试的失败回报。"}
			var retry_plan: Dictionary = preload("res://scripts/core/entrustment_request_compiler.gd").new().plan_for_step(found_task.serial_plan, int(found_task.serial_cursor))
			if int(options.get("due_days", 0)) > 0: retry_plan.normalized_terms.initial_due_days = int(options.due_days)
			var attempts := int(found_task.get("serial_retry_count", 0)) + 1
			var retried: Dictionary = create_entrustment_task(state, retry_plan, found_task.executor_id, found_task.requester_id, int(found_task.serial_seed) + int(found_task.serial_cursor) * 997 + attempts * 37, false).task
			for key in ["id", "task_id", "serial_plan", "serial_results", "serial_cursor", "serial_created_day", "serial_seed"]: retried[key] = found_task[key]
			retried["serial_retry_count"] = attempts
			retried["prior_failure_reports"] = found_task.get("prior_failure_reports", []).duplicate(true)
			retried.prior_failure_reports.append({"step_id": found_task.serial_plan.steps[int(found_task.serial_cursor)].step_id, "outcome_code": found_task.outcome_code, "reported_day": int(found_task.get("reported_day", state.current_day)), "feedback": found_task.visible_feedback.duplicate(true)})
			state.active_tasks[task_index] = retried
			return {"ok": true, "action": "re_entrusted", "new_task": retried.duplicate(true)}
		var exec_id_cont := str(found_task.get("executor_id", ""))
		var req_id_cont := str(found_task.get("requester_id", "li_heng"))
		var orig_duration := maxi(3, int(found_task.get("due_day", 5)) - int(found_task.get("created_day", 0)))
		var new_duration := int(options.get("due_days", 0))
		if new_duration <= 0:
			new_duration = orig_duration
		found_task["status"] = "completed"
		found_task["stage"] = "failed_archived"
		found_task["report_status"] = "read_and_archived"
		found_task["completed_day"] = int(state.current_day)
		found_task["visible_feedback"] = [
			"已批阅回报并责令继续寻访",
			"前次寻访未果已归档，主公命继续扩充门路寻访。"
		]
		var archived_copy: Dictionary = found_task.duplicate(true)
		state.active_tasks.remove_at(task_index)
		state.completed_tasks.append(archived_copy)
		var new_seed := (int(archived_copy.get("rule_seed", 107)) + int(state.current_day) * 53 + 19) & 0x7FFFFFFF
		var new_plan := {
			"task_name": str(archived_copy.get("name", "寻访可用之人并引见")),
			"target_type": str(archived_copy.get("target_type", "character")),
			"target_archetype": str(archived_copy.get("archetype_id", "assassin_retainer")),
			"target_role": str(archived_copy.get("target_role", "")),
			"target_item": str(archived_copy.get("target_item", "")),
			"specialty": str(archived_copy.get("specialty", "")),
			"source_org": str(archived_copy.get("source_org", "")),
			"is_plural": bool(archived_copy.get("is_plural", false)),
			"semantic_stat": str(archived_copy.get("semantic_stat", "prowess")),
			"key_stat_name": str(archived_copy.get("key_stat_name", "武艺")),
			"due_days": new_duration,
			"previous_task_id": str(archived_copy.get("id", "")),
			"terms_version": int(archived_copy.get("terms_version", 1)) + 1
		}
		var created_res := create_entrustment_task(state, new_plan, exec_id_cont, req_id_cont, new_seed)
		return {
			"ok": bool(created_res.get("ok", false)),
			"action": "continued_search",
			"archived_task": archived_copy,
			"new_task": created_res.get("task", {})
		}

	if found_task.has("item_result") and not (found_task.get("item_result") as Dictionary).is_empty():
		var task_item: Dictionary = found_task.get("item_result", {})
		var item_name := str(task_item.get("name", "百炼宝剑"))
		var item_cat := str(task_item.get("category", found_task.get("item_category", "EQUIPMENT")))
		var is_book := (item_cat == "BOOK" or str(found_task.get("target_type", "")) == "manuscript")
		var executor_id_item := str(found_task.get("executor_id", ""))
		if state.flags.get("managed_inventory_initialized", false) and not state.management_assets.has(task_item.get("id")):
			return {"ok": false, "error": "此托付尚无可交割的实物及生产来源记录，不能收取或赠予。"}
		if choice in ["accept_retainer", "accept_item", "collect"]:
			var already_in_inv := false
			if state.has_method("get_inventory"):
				for existing in state.get_inventory():
					if existing is Dictionary and str(existing.get("id", "")) == str(task_item.get("id", "")):
						already_in_inv = true
						break
			if not already_in_inv:
				var received: Dictionary = state.add_inventory_item(task_item)
				if not received.get("ok", false): return received
			if is_book:
				state.add_character_memory(executor_id_item, "奉旨整理装订《%s》一卷呈递御前，已蒙收入内府书箧珍藏。" % item_name)
				found_task["visible_feedback"] = [
					"已收入内府书箧",
					"《%s》已正式收入行在内府书箧珍藏。" % item_name
				]
			else:
				state.add_character_memory(executor_id_item, "奉旨督造【%s】完工呈递御前，主公龙颜甚悦，收纳内库随身。" % item_name)
				found_task["visible_feedback"] = [
					"已收下器物",
					"【%s】已正式纳入行在内库，可供随身佩戴。" % item_name
				]
			found_task["status"] = "completed"
			found_task["stage"] = "delivered"
			found_task["outcome_code"] = "manuscript_delivered" if is_book else "item_delivered"
			found_task["completed_day"] = int(state.current_day)
			_complete_current_step(state, found_task, task_index)
			return {"ok": true, "action": "accepted_book" if is_book else "accepted_item", "item": task_item, "item_name": item_name}
		elif choice in ["decline_politely", "bestow"]:
			if state.flags.get("managed_inventory_initialized", false):
				var context = load("res://scripts/core/game_runtime_context.gd").new()
				context.state = state
				context.scenario_data = {}
				var execution := "entrustment-gift:" + str(found_task.get("id", ""))
				var player: String = state.player_character_id
				var item_id: String = task_item.id
				var delivered: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").new().execute(context, {"execution_id": execution, "request_id": execution, "actor_id": player, "principal_id": player, "executor_id": player, "action_kind": "give_item", "parameters": {"item_id": item_id, "recipient_id": executor_id_item}, "target_refs": [item_id, executor_id_item], "expected_state_revision": int(state.state_revision)})
				if not delivered.get("ok", false): return delivered
			if is_book:
				state.add_character_memory(executor_id_item, "整理装订《%s》一卷呈递御前，主公温言嘉勉并将副册留赐编者珍藏。" % item_name)
				found_task["visible_feedback"] = [
					"已留赐编者",
					"主公展卷嘉勉后，将《%s》留赐受托人珍藏。" % item_name
				]
			else:
				state.add_character_memory(executor_id_item, "督造【%s】呈递御前，主公厚赏匠人并赐给近臣。" % item_name)
				found_task["visible_feedback"] = [
					"已赐赏匠人",
					"主公将所铸【%s】赏赐劳苦工匠。" % item_name
				]
			found_task["status"] = "completed"
			found_task["stage"] = "delivered"
			found_task["outcome_code"] = "book_bestowed" if is_book else "item_declined_gifted"
			found_task["completed_day"] = int(state.current_day)
			_complete_current_step(state, found_task, task_index)
			return {"ok": true, "action": "bestowed_book" if is_book else "declined_item", "item": task_item, "item_name": item_name}
		elif choice in ["view_dossier", "inquire_test", "inspect"]:
			return {
				"ok": true,
				"action": "view_book" if is_book else "view_item",
				"item": task_item,
				"item_name": item_name,
				"revealed_key_stat": "善本品相" if is_book else "器物品质",
				"revealed_value": 92 if is_book else 85
			}

	var disposition := apply_candidate_choice(state, found_task, choice)
	if disposition.get("ok", false) and found_task.get("status") == "completed": _complete_current_step(state, found_task, task_index)
	return disposition

# Shared business rule; queue ownership stays with the caller.
func apply_candidate_choice(state, found_task: Dictionary, choice: String) -> Dictionary:
	var cid := str(found_task.get("candidate_character_id", ""))
	if cid.is_empty() or not state.character_states.has(cid):
		return {"ok": false, "error": "candidate_not_found"}

	var cand: Dictionary = state.character_states[cid]
	var executor_id := str(found_task.get("executor_id", ""))
	var cand_name := str(cand.get("name", cid))
	var executor_name := _get_character_name(state, executor_id)

	if choice == "accept_retainer":
		var cand_role := str(cand.get("role", found_task.get("target_role", "武勇门客")))
		if cand_role.is_empty():
			cand_role = "可用之士"
		cand["allegiance"] = {
			"target_id": str(found_task.get("requester_id", state.player_character_id)),
			"kind": "retainer",
			"day": int(state.current_day)
		}
		cand["summonable"] = true
		cand["status"] = "court_retainer"
		cand["patron_id"] = str(found_task.get("requester_id", state.player_character_id))
		cand["role"] = cand_role
		state.character_states[cid] = cand

		if cand_role in ["悬壶郎中", "名医", "郎中"] or str(found_task.get("archetype_id", "")) == "physician_retainer":
			state.add_character_memory(executor_id, "为主公引见%s【%s】，已蒙延请入幕留在身边诊视医治。" % [cand_name, cand_role])
			state.add_character_memory(cid, "蒙主公延请作为【%s】入幕，应邀入幕，于行在专司诊视医治之责。" % cand_role)
		else:
			state.add_character_memory(executor_id, "为主公引见门客%s【%s】，已蒙纳用留在身边。" % [cand_name, cand_role])
			state.add_character_memory(cid, "蒙主公接纳为【%s】，应邀入幕，随侍行在驱策。" % cand_role)
		found_task["visible_feedback"] = [
			"已纳为门客",
			"%s已正式入幕为【%s】。" % [cand_name, cand_role]
		]

		found_task["status"] = "completed"
		found_task["stage"] = "introduced"
		found_task["outcome_code"] = "accepted_as_retainer"
		found_task["completed_day"] = int(state.current_day)

		return {"ok": true, "action": "accepted_as_retainer", "candidate_id": cid}

	elif choice == "decline_politely":
		cand["status"] = "unaligned"
		state.character_states[cid] = cand

		state.add_character_memory(executor_id, "引见门客%s，主公以礼婉拒，请其自择去留。" % cand_name)
		found_task["status"] = "completed"
		found_task["stage"] = "introduced"
		found_task["outcome_code"] = "declined_politely"
		found_task["completed_day"] = int(state.current_day)
		found_task["visible_feedback"] = [
			"已婉拒礼送",
			"主公以礼婉拒，%s已辞出行在。" % cand_name
		]

		return {"ok": true, "action": "declined_politely", "candidate_id": cid}

	elif choice in ["view_dossier", "inquire_test"]:
		var knowledge_svc := CharacterKnowledgeServiceScript.new()
		var cand_stats: Dictionary = cand.get("stats", {})
		var archetype := str(cand.get("archetype_id", found_task.get("archetype_id", "assassin_retainer")))
		var key_stat_name := "武艺"
		var real_stat_val := int(cand_stats.get("prowess", 50))
		var claim_field := "prowess"
		
		if archetype in ["physician_retainer", "physician", "doctor"]:
			key_stat_name = "医术"
			real_stat_val = int(cand_stats.get("medicine", 50))
			claim_field = "medicine"
		elif archetype in ["strategist", "strategist_retainer"]:
			key_stat_name = "谋略"
			real_stat_val = int(cand_stats.get("intrigue", 50))
			claim_field = "intrigue"
		elif archetype in ["governance", "governance_retainer", "court_maid"]:
			key_stat_name = "治理"
			real_stat_val = int(cand_stats.get("governance", 50))
			claim_field = "governance"
		elif archetype in ["finance", "finance_retainer", "merchant"]:
			key_stat_name = "理财"
			real_stat_val = int(cand_stats.get("finance", 50))
			claim_field = "finance"
		else:
			key_stat_name = "武艺"
			real_stat_val = int(cand_stats.get("prowess", 50))
			claim_field = "prowess"

		knowledge_svc.record_claim(state, cid, claim_field, {
			"status": "confirmed",
			"value": real_stat_val,
			"confidence": 1.0,
			"source_id": "dossier_inspection",
			"acquired_day": int(state.current_day)
		})
		return {
			"ok": true,
			"action": "view_dossier",
			"revealed_key_stat": key_stat_name,
			"revealed_value": real_stat_val,
			"revealed_prowess": real_stat_val,
			"candidate_id": cid
		}

	return {"ok": false, "error": "unknown_choice"}

func start_entrustment(state, data: Dictionary, executor_id: String, plan: Dictionary, requester_id: String = "li_heng") -> Dictionary:
	return create_entrustment_task(state, plan, executor_id, requester_id)

func get_active_entrustment(state, executor_id: String = "") -> Dictionary:
	if state == null:
		return {}
	for task in state.active_tasks:
		if str(task.get("task_kind", "")) == "private_entrustment" or (task.get("task_kind") == "management" and task.get("source_type") == "private_talk"):
			if executor_id.is_empty() or str(task.get("executor_id", "")) == executor_id:
				return (task as Dictionary).duplicate(true)
	return {}

func cancel_entrustment(state, executor_id: String = "", task_id: String = "") -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing_state"}
	for i in range(state.active_tasks.size()):
		var task: Dictionary = state.active_tasks[i]
		if str(task.get("task_kind", "")) == "private_entrustment":
			if (not task_id.is_empty() and str(task.get("id", "")) == task_id) or (task_id.is_empty() and (executor_id.is_empty() or str(task.get("executor_id", "")) == executor_id)):
				task["status"] = "cancelled"
				task["outcome_code"] = "cancelled_by_player"
				task["completed_day"] = int(state.current_day)
				task["visible_feedback"] = ["托付已取消", "主公命此事作罢。"]
				var eid := str(task.get("executor_id", ""))
				if not eid.is_empty() and state.has_method("add_character_memory"):
					state.add_character_memory(eid, "托付寻访门客之事，主公已命作罢。")
				state.active_tasks.remove_at(i)
				state.completed_tasks.append(task.duplicate(true))
				return {"ok": true, "cancelled_task": task.duplicate(true)}
	return {"ok": false, "error": "no_active_entrustment_found"}

func _get_character_name(state, character_id: String) -> String:
	if state != null and state.get("character_states") is Dictionary:
		var c = state.character_states.get(character_id, {})
		if c is Dictionary and c.has("name"):
			return str(c.get("name"))
	return character_id

func _get_executor_stats(state, executor_id: String) -> Dictionary:
	if state != null and state.get("character_states") is Dictionary:
		var c = state.character_states.get(executor_id, {})
		if c is Dictionary and c.has("stats"):
			return (c.get("stats") as Dictionary).duplicate(true)
	# Fallback default values
	return {"intrigue": 60, "diplomacy": 55, "prowess": 50}
