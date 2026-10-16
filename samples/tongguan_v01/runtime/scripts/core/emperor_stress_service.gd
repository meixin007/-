extends RefCounted

class_name EmperorStressService

const DEFAULT_STRESS_EVENTS_PATH := "res://data/scenarios/anshi_rebellion/tang_stress_events.json"

const MAX_STRESS := 300
const TIER_1_THRESHOLD := 100
const TIER_2_THRESHOLD := 200
const TIER_3_THRESHOLD := 300

const DEFAULT_COPING_ACTIONS := [
	{
		"id": "taoist_ritual",
		"name": "行在设醮（崇道祈福）",
		"description": "延请山人李泌于灵武行在设立太清黄箓道场，斋戒沐浴，讲论《道德经》以宁心神。",
		"stress_relief": 40,
		"cost": {"treasury": 30},
		"bonus": {"legitimacy": 5},
		"cooldown_days": 7,
		"flavor_feedback": "道场钟磬悠扬，李泌清谈玄理，陛下焦躁多疑之心渐得抚慰。"
	},
	{
		"id": "confide_in_eunuchs",
		"name": "夜召内侍（密室倾诉）",
		"description": "屏退外廷大臣，密召李辅国等近侍入寝帐，吐露猜忌与隐忧，令其整饬宿卫。",
		"stress_relief": 50,
		"cost": {},
		"bonus": {},
		"penalty": {"inner_court_influence": 15, "authority": -5},
		"cooldown_days": 5,
		"flavor_feedback": "李辅国顿首泣奏誓死效忠，内侍宿卫锁钥加固，陛下心安但内廷权势渐重。"
	},
	{
		"id": "banquet_commanders",
		"name": "巡营犒军（把酒言欢）",
		"description": "亲临郭子仪等大将营寨，赐御用美酒羊炙，与边塞宿将共话平戎大计。",
		"stress_relief": 35,
		"cost": {"grain": 40, "treasury": 20},
		"bonus": {"commander_morale": 10},
		"cooldown_days": 10,
		"flavor_feedback": "营中桴鼓震天，将士欢声雷动，边将感激涕零，陛下暂时忘却朝堂危殆。"
	},
	{
		"id": "penitential_edict",
		"name": "颁下罪己（自抑心神）",
		"description": "避正殿，减膳食，下《引咎责躬诏》，自陈德薄致寇之失，以正天人感应。",
		"stress_relief": 60,
		"cost": {"authority": 10},
		"bonus": {"public_order": 10, "legitimacy": 8},
		"cooldown_days": 15,
		"flavor_feedback": "天下士民闻诏感泣，关陇民心大顺，陛下引咎释怀，心头巨石落地。"
	}
]

var _stress_rules: Dictionary = {}
var _coping_actions: Array = []
var _breakdown_events: Array = []

func _init(custom_config: Dictionary = {}) -> void:
	if not custom_config.is_empty():
		_stress_rules = custom_config.get("stress_rules", {}).duplicate(true)
		_coping_actions = custom_config.get("coping_actions", []).duplicate(true)
		_breakdown_events = custom_config.get("breakdown_events", []).duplicate(true)
	else:
		_load_default_config()

func _load_default_config() -> void:
	if FileAccess.file_exists(DEFAULT_STRESS_EVENTS_PATH):
		var file := FileAccess.open(DEFAULT_STRESS_EVENTS_PATH, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				_stress_rules = (parsed as Dictionary).get("stress_rules", {}).duplicate(true)
				_coping_actions = (parsed as Dictionary).get("coping_actions", []).duplicate(true)
				_breakdown_events = (parsed as Dictionary).get("breakdown_events", []).duplicate(true)
				return
	_coping_actions = DEFAULT_COPING_ACTIONS.duplicate(true)

## 确保 state 中皇帝心神压力状态初始化
func ensure_stress_state(state) -> Dictionary:
	var raw_stress = state.flags.get("emperor_stress_state", {})
	if not (raw_stress is Dictionary) or raw_stress.is_empty():
		var initial_state := {
			"stress_level": 30,
			"tier": 0,
			"tier_label": "神清气定",
			"coping_cooldowns": {},
			"active_habits": [],
			"breakdown_pending": {},
			"stress_history": []
		}
		state.flags["emperor_stress_state"] = initial_state
		return initial_state
	return raw_stress

## 获取皇帝心神与压力公开档案（供 UI 与顶栏调用）
func get_stress_profile(state) -> Dictionary:
	var s_state := ensure_stress_state(state)
	var current_stress: int = clampi(int(s_state.get("stress_level", 30)), 0, MAX_STRESS)
	var tier := _calculate_tier(current_stress)
	var tier_label := _get_tier_label(tier)
	var severity := _get_tier_severity(tier)

	var current_day := int(state.current_day)
	var cooldowns: Dictionary = s_state.get("coping_cooldowns", {})
	var available_coping: Array = []
	for raw_action in _coping_actions:
		var action: Dictionary = (raw_action as Dictionary).duplicate(true)
		var act_id := str(action.get("id", ""))
		var ready_day := int(cooldowns.get(act_id, 0))
		var is_ready := current_day >= ready_day
		action["is_ready"] = is_ready
		action["cooldown_remaining"] = maxi(0, ready_day - current_day)
		# 检查资源是否满足
		action["can_afford"] = _can_afford_cost(state, action.get("cost", {}))
		available_coping.append(action)

	return {
		"stress_level": current_stress,
		"max_stress": MAX_STRESS,
		"tier": tier,
		"tier_label": tier_label,
		"severity": severity,
		"active_habits": s_state.get("active_habits", []).duplicate(true),
		"available_coping_actions": available_coping,
		"breakdown_pending": s_state.get("breakdown_pending", {}).duplicate(true),
		"display_text": "天子心神: %s (%d/%d)" % [tier_label, current_stress, MAX_STRESS]
	}

## 增加心智压力（例如违背猜忌/崇道性格做出妥协决策）
func add_stress(state, amount: int, reason: String, source_action: String = "") -> Dictionary:
	var s_state := ensure_stress_state(state)
	var old_stress := int(s_state.get("stress_level", 30))
	var old_tier := _calculate_tier(old_stress)
	var new_stress := clampi(old_stress + amount, 0, MAX_STRESS)
	var new_tier := _calculate_tier(new_stress)

	s_state["stress_level"] = new_stress
	s_state["tier"] = new_tier
	s_state["tier_label"] = _get_tier_label(new_tier)

	var history_entry := {
		"day": int(state.current_day),
		"delta": amount,
		"before": old_stress,
		"after": new_stress,
		"reason": reason,
		"source_action": source_action
	}
	var history: Array = s_state.get("stress_history", []).duplicate(true)
	history.append(history_entry)
	s_state["stress_history"] = history

	# 检查是否突破新的警戒阈值触发崩溃抉择
	var breakdown_triggered := false
	var triggered_event: Dictionary = {}
	if new_tier > old_tier and new_tier >= 1:
		triggered_event = _find_breakdown_event(new_tier)
		if not triggered_event.is_empty():
			s_state["breakdown_pending"] = triggered_event.duplicate(true)
			breakdown_triggered = true

	state.flags["emperor_stress_state"] = s_state

	return {
		"ok": true,
		"old_stress": old_stress,
		"new_stress": new_stress,
		"delta": amount,
		"tier": new_tier,
		"tier_label": _get_tier_label(new_tier),
		"breakdown_triggered": breakdown_triggered,
		"breakdown_event": triggered_event
	}

## 平复排解心智压力
func relieve_stress(state, amount: int, reason: String) -> Dictionary:
	var s_state := ensure_stress_state(state)
	var old_stress := int(s_state.get("stress_level", 30))
	var new_stress := clampi(old_stress - amount, 0, MAX_STRESS)
	var new_tier := _calculate_tier(new_stress)

	s_state["stress_level"] = new_stress
	s_state["tier"] = new_tier
	s_state["tier_label"] = _get_tier_label(new_tier)

	var history_entry := {
		"day": int(state.current_day),
		"delta": -amount,
		"before": old_stress,
		"after": new_stress,
		"reason": reason
	}
	var history: Array = s_state.get("stress_history", []).duplicate(true)
	history.append(history_entry)
	s_state["stress_history"] = history

	state.flags["emperor_stress_state"] = s_state

	return {
		"ok": true,
		"old_stress": old_stress,
		"new_stress": new_stress,
		"delta": -amount,
		"tier": new_tier,
		"tier_label": _get_tier_label(new_tier)
	}

## 执行唐代排解行动（如设醮、密召、犒军、罪己）
func execute_coping_action(state, action_id: String, execution_id: String = "") -> Dictionary:
	if state is Object and (not state.resource_accounts.is_empty() or state.flags.get("campaign_id") == "anshi_beta_1_14"):
		return _execute_current_action(state, "coping", action_id, execution_id)
	return _apply_coping_action(state, action_id)

func _apply_coping_action(state, action_id: String) -> Dictionary:
	var s_state := ensure_stress_state(state)
	var target_action: Dictionary = {}
	for act in _coping_actions:
		if str(act.get("id", "")) == action_id:
			target_action = (act as Dictionary).duplicate(true)
			break
	if target_action.is_empty():
		return {"ok": false, "error": "未知排解行动: " + action_id}

	var current_day := int(state.current_day)
	var cooldowns: Dictionary = s_state.get("coping_cooldowns", {}).duplicate(true)
	var ready_day := int(cooldowns.get(action_id, 0))
	if current_day < ready_day:
		return {"ok": false, "error": "该排解行动尚在冷却中，需至第 %d 日" % ready_day}

	# 检查并扣除消耗
	var cost: Dictionary = target_action.get("cost", {})
	if not _can_afford_cost(state, cost):
		return {"ok": false, "error": "资源不足以施行该排解"}

	var paid := _apply_cost(state, cost, "rule:coping:" + action_id)
	if not paid.get("ok", false): return paid

	# 扣除压力
	var relief := int(target_action.get("stress_relief", 30))
	var relief_res := relieve_stress(state, relief, "施行" + str(target_action.get("name", "")))

	# 施加奖惩
	var bonus: Dictionary = target_action.get("bonus", {})
	for b_key in bonus.keys():
		var applied := _apply_resource_delta(state, str(b_key), int(bonus[b_key]), "rule:coping:" + action_id)
		if not applied.get("ok", false): return applied

	var penalty: Dictionary = target_action.get("penalty", {})
	for p_key in penalty.keys():
		var applied := _apply_resource_delta(state, str(p_key), -abs(int(penalty[p_key])), "rule:coping:" + action_id)
		if not applied.get("ok", false): return applied

	# 记录冷却
	var cd_days := int(target_action.get("cooldown_days", 7))
	cooldowns[action_id] = current_day + cd_days
	s_state["coping_cooldowns"] = cooldowns
	state.flags["emperor_stress_state"] = s_state

	return {
		"ok": true,
		"action_id": action_id,
		"action_name": str(target_action.get("name", "")),
		"stress_relief": relief,
		"flavor_feedback": str(target_action.get("flavor_feedback", "心神暂得抚平。")),
		"new_stress": relief_res.get("new_stress", 0),
		"tier_label": relief_res.get("tier_label", "神清气定")
	}

## 解决崩溃抉择
func resolve_breakdown_choice(state, choice_id: String, execution_id: String = "") -> Dictionary:
	if state is Object and (not state.resource_accounts.is_empty() or state.flags.get("campaign_id") == "anshi_beta_1_14"):
		return _execute_current_action(state, "breakdown", choice_id, execution_id)
	return _apply_breakdown_choice(state, choice_id)

func _apply_breakdown_choice(state, choice_id: String) -> Dictionary:
	var s_state := ensure_stress_state(state)
	var pending: Dictionary = s_state.get("breakdown_pending", {})
	if pending.is_empty():
		return {"ok": false, "error": "当前没有待处理的心理崩溃抉择"}

	var selected_choice: Dictionary = {}
	for c in pending.get("choices", []):
		if str(c.get("choice_id", "")) == choice_id:
			selected_choice = (c as Dictionary).duplicate(true)
			break
	if selected_choice.is_empty():
		return {"ok": false, "error": "无效的崩溃抉择项: " + choice_id}
	var rule := "rule:breakdown:%s:%s" % [str(pending.get("id", "")), choice_id]
	var cost: Dictionary = selected_choice.get("cost", {})
	var paid := _apply_cost(state, cost, rule)
	if not paid.get("ok", false): return paid

	# 释放压力
	var relief := int(selected_choice.get("stress_relief", 40))
	if relief > 0:
		relieve_stress(state, relief, "处置心神崩溃: " + str(selected_choice.get("text", "")))

	# 施加惩罚
	var penalty: Dictionary = selected_choice.get("penalty", {})
	for p_key in penalty.keys():
		var applied := _apply_resource_delta(state, str(p_key), -abs(int(penalty[p_key])), rule)
		if not applied.get("ok", false): return applied

	# 动态赋予习气特质
	var gained_trait := str(selected_choice.get("gained_trait", "")).strip_edges()
	var trait_gained_info: Dictionary = {}
	if not gained_trait.is_empty():
		var trait_service := TangCharacterTraitService.new()
		trait_gained_info = trait_service.add_character_trait(state, {}, "li_heng", gained_trait)

	# 清理 pending
	s_state["breakdown_pending"] = {}
	state.flags["emperor_stress_state"] = s_state

	return {
		"ok": true,
		"choice_id": choice_id,
		"choice_text": str(selected_choice.get("text", "")),
		"stress_relief": relief,
		"gained_trait": gained_trait,
		"trait_info": trait_gained_info
	}

## 每日推进结算中的心神微调
func process_daily_settlement(state) -> Dictionary:
	var s_state := ensure_stress_state(state)
	var current_stress := int(s_state.get("stress_level", 30))
	# 若处于低压状态且无战乱冲击，每日自然平复 1 点压力
	if current_stress > 20 and s_state.get("breakdown_pending", {}).is_empty():
		relieve_stress(state, 1, "行在晨省微宁")
	return {"ok": true}

func _calculate_tier(stress: int) -> int:
	if stress >= TIER_3_THRESHOLD:
		return 3
	elif stress >= TIER_2_THRESHOLD:
		return 2
	elif stress >= TIER_1_THRESHOLD:
		return 1
	return 0

func _get_tier_label(tier: int) -> String:
	match tier:
		3: return "精神崩解"
		2: return "疑惧惊梦"
		1: return "心神恍惚"
		_: return "神清气定"

func _get_tier_severity(tier: int) -> String:
	match tier:
		3: return "critical"
		2: return "danger"
		1: return "warning"
		_: return "normal"

func _find_breakdown_event(tier: int) -> Dictionary:
	for ev in _breakdown_events:
		if int(ev.get("tier", 0)) == tier:
			return (ev as Dictionary).duplicate(true)
	return {
		"id": "generic_breakdown_tier_%d" % tier,
		"tier": tier,
		"title": "心神震荡：局势惊心",
		"text": "大势压顶，陛下心神大乱，急需妥善排解。",
		"choices": [
			{"choice_id": "endure", "text": "隐忍静思", "stress_relief": 20}
		]
	}

func _get_res_dict(state) -> Dictionary:
	if state == null:
		return {}
	if state is Dictionary:
		return state.get("resources", {}) if state.get("resources") is Dictionary else {}
	if state.get("resources") is Dictionary:
		return state.resources
	return {}

func _can_afford_cost(state, cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	var res_dict := _get_res_dict(state)
	for key in cost.keys():
		var required := int(cost[key])
		var current := int(res_dict.get(key, 0))
		if state is Object and not state.resource_accounts.is_empty(): current = preload("res://scripts/core/resource_rule_settlement.gd").available(state, str(key))
		if required < 0 or current < required:
			return false
	return true

func _apply_cost(state, cost: Dictionary, rule: String) -> Dictionary:
	if not _can_afford_cost(state, cost): return {"ok": false, "error": "实际可用资源不足，不能占用已预留款项。"}
	for key in cost.keys():
		var amount := int(cost[key])
		var paid := _apply_resource_delta(state, str(key), -amount, rule)
		if not paid.get("ok", false): return paid
	return {"ok": true}

func _apply_resource_delta(state, key: String, delta: int, rule: String) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "缺少当前状态"}
	if state is Object and not preload("res://scripts/core/resource_rule_settlement.gd").account_for(state, key).is_empty():
		return state.apply_resource_delta(key, delta, rule)
	if state is Dictionary:
		if not state.has("resources") or not (state.resources is Dictionary):
			state["resources"] = {}
		var cur := int(state.resources.get(key, 0))
		state.resources[key] = cur + delta
	elif state.get("resources") is Dictionary:
		var cur := int(state.resources.get(key, 0))
		state.resources[key] = clampi(cur + delta, 0, 1000000)
	else:
		state.flags[key] = int(state.flags.get(key, 0)) + delta
	return {"ok": true}

func _execute_current_action(state, kind: String, choice: String, execution_id: String) -> Dictionary:
	if state.player_character_id != "li_heng": return {"ok": false, "error": "当前身份无权办理天子排解或恩命。"}
	var context = load("res://scripts/core/game_runtime_context.gd").new()
	context.state = state
	var id := execution_id if not execution_id.is_empty() else "stress:%s:%s:%d" % [kind, choice, int(state.current_day)]
	var input := {"execution_id": id, "kind": kind, "choice": choice, "actor_id": state.player_character_id}
	var transaction = load("res://scripts/core/game_state_transaction.gd").new()
	var preview: Dictionary = transaction.preview_command(state, "emperor_coping", input)
	if not preview.get("ok", false): return preview
	return transaction.execute_command(context, transaction.build_command_envelope("emperor_coping", input, preview.preview_token), func(working):
		var result: Dictionary = _apply_coping_action(working.state, choice) if kind == "coping" else _apply_breakdown_choice(working.state, choice)
		if result.get("ok", false): result["result_ref"] = id
		return result
	)
