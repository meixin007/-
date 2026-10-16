extends RefCounted

class_name EntrustmentCapabilityRegistry

const SCHEMA_VERSION := 2

const CAPABILITIES: Dictionary = {
	"find_person_and_introduce": {
		"capability_id": "find_person_and_introduce",
		"status": "enabled",
		"label": "寻访可用之人并引见",
		"target_type": "person",
		"supported_archetypes": [
			"assassin_retainer",
			"physician_retainer",
			"strategist_retainer",
			"governance_retainer",
			"finance_retainer",
			"generic_retainer",
			"custom"
		],
		"max_quantity": 1,
		"supported_requirement_fields": [
			"prowess",
			"intrigue",
			"combat",
			"origin_local",
			"loyalty_preference",
			"medicine",
			"governance",
			"finance"
		],
		"unsupported_hard_conditions": [
			"absolute_loyalty",
			"rank_100_guarantee",
			"zero_day_deadline"
		],
		"cost_modes": ["none", "private_funds"],
		"allowed_combination_templates": [
			"find_and_introduce_serial"
		],
		"requires_executor": true,
		"default_duration_min_days": 3,
		"default_duration_max_days": 7,
		"completion_criterion": "candidate_introduced",
		"stages": [
			"searching",
			"found_lead",
			"contacting",
			"awaiting_introduction",
			"introduced"
		],
		"failure_reasons": [
			"no_lead_found",
			"contact_lost",
			"candidate_rejected_approach",
			"executor_unavailable",
			"cancelled_by_player"
		]
	},
	"query_progress": {
		"capability_id": "query_progress",
		"status": "enabled",
		"label": "询问托付进展",
		"target_type": "entrustment_task",
		"requires_executor": true,
		"stages": ["completed"]
	},
	"modify_terms": {
		"capability_id": "modify_terms",
		"status": "enabled",
		"label": "修改托付条件",
		"target_type": "entrustment_task",
		"requires_executor": true,
		"stages": ["negotiating"]
	},
	"cancel_entrustment": {
		"capability_id": "cancel_entrustment",
		"status": "enabled",
		"label": "取消托付",
		"target_type": "entrustment_task",
		"requires_executor": true,
		"stages": ["cancelled"]
	},
	"negotiate_retainer_service": {
		"capability_id": "negotiate_retainer_service",
		"status": "enabled",
		"label": "商谈门客效力约定",
		"target_type": "candidate_person",
		"requires_executor": false,
		"stages": ["completed", "rejected"]
	},
	"craft_item": {
		"capability_id": "craft_item",
		"status": "enabled",
		"label": "派人打造兵器神兵并呈递",
		"target_type": "item",
		"supported_archetypes": ["item_sword", "item_armor", "item_weapon", "item_mount", "item_medicine", "item_supply", "generic_item"],
		"max_quantity": 1,
		"supported_requirement_fields": [
			"prowess",
			"quality"
		],
		"unsupported_hard_conditions": [
			"zero_day_deadline"
		],
		"cost_modes": ["none", "private_funds"],
		"requires_executor": true,
		"default_duration_min_days": 3,
		"default_duration_max_days": 7,
		"completion_criterion": "item_delivered",
		"stages": [
			"crafting",
			"awaiting_introduction",
			"delivered"
		],
		"failure_reasons": [
			"crafting_failed",
			"executor_unavailable",
			"cancelled_by_player"
		]
	},
	"compile_or_process_work": {
		"capability_id": "compile_or_process_work",
		"status": "enabled",
		"label": "整理、誊写或装订既有作品成册",
		"target_type": "manuscript",
		"supported_archetypes": [
			"manuscript_book",
			"poetry_anthology",
			"letter_transcription",
			"document_collation"
		],
		"max_quantity": 1,
		"supported_requirement_fields": [
			"quality",
			"diplomacy",
			"governance"
		],
		"unsupported_hard_conditions": [
			"zero_day_deadline",
			"realm_wide_fame",
			"hundred_new_poems"
		],
		"cost_modes": ["none", "private_funds"],
		"requires_executor": true,
		"default_duration_min_days": 1,
		"default_duration_max_days": 5,
		"completion_criterion": "manuscript_delivered",
		"stages": [
			"compiling",
			"awaiting_introduction",
			"delivered"
		],
		"failure_reasons": [
			"executor_unavailable",
			"cancelled_by_player"
		]
	}
}

# Future capabilities (unimplemented / disabled in first milestone)
const DISABLED_CAPABILITIES: Dictionary = {
	"find_treasure": {
		"capability_id": "find_treasure",
		"status": "disabled",
		"label": "寻访宝物",
		"reason": "宝物与个人产权系统尚未接入当前版本"
	},
	"find_court_maid": {
		"capability_id": "find_court_maid",
		"status": "disabled",
		"label": "寻访宫人",
		"reason": "宫人职事专长模板待下一阶段接入"
	},
	"find_palace_candidate": {
		"capability_id": "find_palace_candidate",
		"status": "disabled",
		"label": "寻访宫廷候选女子",
		"reason": "宫廷交往与候选模板待下一阶段接入"
	},
	"execute_assassination": {
		"capability_id": "execute_assassination",
		"status": "disabled",
		"label": "刺杀指定人物",
		"reason": "当前版本不提供刺杀行动执行机制"
	},
	"host_banquet": {
		"capability_id": "host_banquet",
		"status": "disabled",
		"label": "举办宴席",
		"reason": "当前版本暂不支持安排宴席"
	},
	"infinite_delegation": {
		"capability_id": "infinite_delegation",
		"status": "disabled",
		"label": "无限转托寻访",
		"reason": "首批仅支持受托人同地人脉寻访，不支持递归再委托"
	}
}

func get_schema_version() -> int:
	return SCHEMA_VERSION

func get_capability(capability_id: String) -> Dictionary:
	var id := capability_id.strip_edges()
	if CAPABILITIES.has(id):
		return (CAPABILITIES[id] as Dictionary).duplicate(true)
	if DISABLED_CAPABILITIES.has(id):
		return (DISABLED_CAPABILITIES[id] as Dictionary).duplicate(true)
	return {}

func is_capability_enabled(capability_id: String) -> bool:
	var cap := get_capability(capability_id)
	return str(cap.get("status", "")) == "enabled"

func get_enabled_capabilities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in CAPABILITIES.keys():
		var entry: Dictionary = CAPABILITIES[id]
		if str(entry.get("status", "")) == "enabled":
			result.append(entry.duplicate(true))
	return result

func validate_arguments(capability_id: String, args: Dictionary) -> Dictionary:
	var cap := get_capability(capability_id)
	if cap.is_empty():
		return {"ok": false, "error": "unknown_capability"}
	if str(cap.get("status", "")) != "enabled":
		return {"ok": false, "error": "capability_not_enabled", "reason": str(cap.get("reason", "未启用"))}

	if capability_id == "find_person_and_introduce":
		var archetype := str(args.get("archetype_id", ""))
		var supported_archetypes: Array = cap.get("supported_archetypes", [])
		var is_allowed := supported_archetypes.has(archetype) or archetype.ends_with("_retainer") or archetype == "generic_retainer" or archetype.begins_with("dyn_") or archetype == "custom"
		if not is_allowed:
			return {
				"ok": false,
				"error": "unsupported_archetype",
				"archetype_id": archetype,
				"allowed": supported_archetypes.duplicate()
			}
		var qty := int(args.get("quantity", 1))
		var max_qty := int(cap.get("max_quantity", 1))
		if qty < 1 or qty > max_qty:
			return {
				"ok": false,
				"error": "quantity_exceeded",
				"quantity": qty,
				"max_quantity": max_qty
			}
		return {"ok": true, "validated_args": args.duplicate(true)}

	if capability_id == "craft_item":
		var archetype := str(args.get("archetype_id", ""))
		var supported_archetypes: Array = cap.get("supported_archetypes", [])
		var is_allowed := supported_archetypes.has(archetype) or archetype.begins_with("item_") or archetype == "generic_item"
		if not is_allowed:
			return {
				"ok": false,
				"error": "unsupported_archetype",
				"archetype_id": archetype,
				"allowed": supported_archetypes.duplicate()
			}
		var qty := int(args.get("quantity", 1))
		var max_qty := int(cap.get("max_quantity", 1))
		if qty < 1 or qty > max_qty:
			return {
				"ok": false,
				"error": "quantity_exceeded",
				"quantity": qty,
				"max_quantity": max_qty
			}
		return {"ok": true, "validated_args": args.duplicate(true)}

	if capability_id == "compile_or_process_work":
		var qty := int(args.get("quantity", 1))
		var max_qty := int(cap.get("max_quantity", 1))
		if qty < 1 or qty > max_qty:
			return {
				"ok": false,
				"error": "quantity_exceeded",
				"quantity": qty,
				"max_quantity": max_qty
			}
		return {"ok": true, "validated_args": args.duplicate(true)}

	return {"ok": true, "validated_args": args.duplicate(true)}
