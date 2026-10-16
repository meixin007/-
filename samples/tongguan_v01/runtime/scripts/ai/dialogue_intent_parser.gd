extends RefCounted

class_name DialogueIntentParser

const EntrustmentRequestCompilerScript = preload("res://scripts/core/entrustment_request_compiler.gd")
const GenericEntrustmentSlotExtractorScript = preload("res://scripts/ai/generic_entrustment_slot_extractor.gd")
const MAX_PLAYER_TEXT_CHARS := 4096

func parse_with_candidate(player_text: String, context: Dictionary = {}, data: Dictionary = {}, api_candidate: Dictionary = {}) -> Dictionary:
	return parse(player_text, context, data, api_candidate)

func parse(player_text: String, context: Dictionary = {}, data: Dictionary = {}, api_candidate: Dictionary = {}) -> Dictionary:
	var text := player_text.left(MAX_PLAYER_TEXT_CHARS).strip_edges()
	if text == "" and api_candidate.is_empty():
		return _unknown("empty_player_text", context)

	var extractor = GenericEntrustmentSlotExtractorScript.new()
	var slot_res: Dictionary = extractor.extract(text, context)
	var domain := str(slot_res.get("domain", ""))

	# Explicit negation / non-execution / pure literary inquiry short-circuit
	if domain == "conversation_only":
		var speech_act := str(slot_res.get("speech_act", "chit_chat"))
		var is_info := speech_act == "ask_info"
		var v2_dto := {
			"speech_act": speech_act,
			"evidence_text": text,
			"raw_text": text,
			"proposed_goals": []
		}
		var compiler = EntrustmentRequestCompilerScript.new()
		var comp := compiler.compile_request(v2_dto, context)
		return {
			"ok": true,
			"intent_type": "ask_information" if is_info else "conversation_only",
			"speech_act": speech_act,
			"resolution_class": "conversation_only",
			"entrustment_dto": v2_dto,
			"entrustment_compilation": comp,
			"executor_id": str(context.get("npc_id", "")),
			"confidence": 0.92,
			"requires_confirmation": false,
			"state_changing": false,
			"raw_text": text
		}

	if domain == "modify_terms":
		var mod_deadline: Dictionary = slot_res.get("deadline", {})
		var mod_days := int(slot_res.get("due_days", mod_deadline.get("exact_days", 3)))
		return {
			"ok": true,
			"intent_type": "modify_terms",
			"resolution_class": "supported",
			"executor_id": str(context.get("npc_id", "")),
			"target_role": str(slot_res.get("target_role", "")),
			"delivery_clause": str(slot_res.get("delivery_clause", "")),
			"deadline": mod_deadline,
			"due_days": mod_days,
			"confidence": 0.92,
			"requires_confirmation": false,
			"state_changing": true,
			"raw_text": text
		}

	if domain == "needs_clarification":
		var clar_reason := str(slot_res.get("reason", "请先说明所要寻访或托付的具体事项与人物对象。"))
		return {
			"ok": true,
			"intent_type": "entrustment_fallback",
			"resolution_class": "needs_clarification",
			"clarification_required": true,
			"clarification_questions": [clar_reason],
			"entrustment_compilation": {
				"resolution_class": "needs_clarification",
				"explanation": clar_reason,
				"clarification_questions": [clar_reason]
			},
			"executor_id": str(context.get("npc_id", "")),
			"confidence": 0.92,
			"requires_confirmation": false,
			"state_changing": false,
			"raw_text": text,
			"error": clar_reason
		}

	if domain == "acknowledge_report":
		return {
			"ok": true,
			"intent_type": "acknowledge_report",
			"speech_act": "acknowledge_report",
			"resolution_class": "supported",
			"executor_id": str(context.get("npc_id", "")),
			"confidence": 0.95,
			"requires_confirmation": false,
			"state_changing": true,
			"raw_text": text
		}

	if domain == "continue_search":
		return {
			"ok": true,
			"intent_type": "continue_search",
			"speech_act": "continue_search",
			"resolution_class": "supported",
			"executor_id": str(context.get("npc_id", "")),
			"deadline": slot_res.get("deadline", {}),
			"due_days": int(slot_res.get("due_days", 5)),
			"confidence": 0.95,
			"requires_confirmation": false,
			"state_changing": true,
			"raw_text": text
		}

	if domain == "compile_or_process_work":
		return _intent_from_mapping(text, context, {
			"intent_type": "entrust_compile_work",
			"confidence": 0.94,
			"source_type": "private_talk",
			"political_object_type": "task",
			"state_changing": true,
			"requires_confirmation": true
		}, api_candidate)

	# Merge structured API candidate when present (validated through same slot rules)
	if not api_candidate.is_empty():
		var api_domain := str(api_candidate.get("domain", "")).strip_edges()
		if api_domain in ["compile_or_process_work", "compile_work"] or str(api_candidate.get("target_type", "")) == "manuscript":
			return _intent_from_mapping(text, context, {
				"intent_type": "entrust_compile_work",
				"confidence": float(api_candidate.get("confidence", 0.90)),
				"source_type": "private_talk",
				"political_object_type": "task",
				"state_changing": true,
				"requires_confirmation": true
			}, api_candidate)
		elif api_domain == "procure_item" and domain != "seek_person":
			return _intent_from_mapping(text, context, {
				"intent_type": "entrust_craft_item",
				"confidence": float(api_candidate.get("confidence", 0.88)),
				"source_type": "private_talk",
				"political_object_type": "task",
				"state_changing": true,
				"requires_confirmation": true
			}, api_candidate)
		elif api_domain == "seek_person":
			return _intent_from_mapping(text, context, {
				"intent_type": "entrust_seek_retainer",
				"confidence": float(api_candidate.get("confidence", 0.88)),
				"source_type": "private_talk",
				"political_object_type": "task",
				"state_changing": true,
				"requires_confirmation": true
			}, api_candidate)

	var mappings: Array = []
	_append_mappings_with_priority(mappings, data.get("npc_interactions", {}).get("intent_mappings", []), 0)
	_append_mappings_with_priority(mappings, _beta_0_5_intent_mappings(), 1)
	_append_mappings_with_priority(mappings, _entrustment_intent_mappings(), 2)
	_append_mappings_with_priority(mappings, data.get("dialogue_intents_beta_0_9", []), 3)
	var best_mapping: Dictionary = {}
	var best_score := 0
	var best_priority := -1
	for mapping in mappings:
		var score := _match_score(text, mapping)
		var priority := int(mapping.get("_intent_source_priority", 0))
		if score > best_score or (score == best_score and score > 0 and priority > best_priority):
			best_mapping = mapping
			best_score = score
			best_priority = priority
	if best_score > 0:
		var matching_types: Array = []
		for mapping in mappings:
			if _match_score(text, mapping) == best_score and int(mapping.get("_intent_source_priority", 0)) == best_priority:
				var candidate_type := str(mapping.get("intent_type", ""))
				if candidate_type != "" and not matching_types.has(candidate_type):
					matching_types.append(candidate_type)
		if matching_types.size() > 1:
			return _unknown("ambiguous_intent", context)
	if not best_mapping.is_empty():
		return _intent_from_mapping(text, context, best_mapping, api_candidate)

	# Dynamic slot extraction fallback
	if domain == "seek_person":
		return _intent_from_mapping(text, context, {"intent_type": "entrust_seek_retainer", "confidence": 0.85, "source_type": "private_talk", "state_changing": true, "requires_confirmation": true}, api_candidate)
	elif domain == "procure_item":
		return _intent_from_mapping(text, context, {"intent_type": "entrust_craft_item", "confidence": 0.85, "source_type": "private_talk", "state_changing": true, "requires_confirmation": true}, api_candidate)
	elif domain == "confirm":
		return _intent_from_mapping(text, context, {"intent_type": "confirm_entrustment", "confidence": 0.90, "source_type": "private_talk", "state_changing": true}, api_candidate)
	elif domain == "cancel":
		return _intent_from_mapping(text, context, {"intent_type": "cancel_entrustment", "confidence": 0.90, "source_type": "private_talk", "state_changing": true}, api_candidate)
	elif domain == "query":
		return _intent_from_mapping(text, context, {"intent_type": "query_entrustment", "confidence": 0.90, "source_type": "private_talk", "state_changing": false}, api_candidate)
	elif domain == "accept":
		return _intent_from_mapping(text, context, {"intent_type": "accept_retainer", "confidence": 0.90, "source_type": "private_talk", "state_changing": true}, api_candidate)
	elif domain == "decline":
		return _intent_from_mapping(text, context, {"intent_type": "decline_politely", "confidence": 0.90, "source_type": "private_talk", "state_changing": true}, api_candidate)
	elif domain == "inspect":
		return _intent_from_mapping(text, context, {"intent_type": "view_dossier", "confidence": 0.90, "source_type": "private_talk", "state_changing": false}, api_candidate)

	# Fallback evaluation via EntrustmentRequestCompiler for unsupported, impossible, decree, or clarification requests
	var compiler = EntrustmentRequestCompilerScript.new()
	var is_impossible := compiler._is_impossible_in_world(text, {}) or domain == "impossible_in_world"
	var unsupported_hint := compiler._detect_unsupported_hint(text)
	if unsupported_hint.is_empty() and domain == "unsupported_capability":
		unsupported_hint = str(slot_res.get("reason", "当前玩法暂未支持"))
	var requires_decree := compiler._requires_formal_decree(text) or domain == "formal_decree"
	var clarification := compiler._check_needs_clarification({}, text)
	var is_clarification := bool(clarification.get("needs_clarification", false))

	if is_impossible or not unsupported_hint.is_empty() or requires_decree or is_clarification:
		var fallback_dto := {
			"speech_act": "request_favor",
			"evidence_text": text,
			"raw_text": text,
			"requires_formal_decree": requires_decree,
			"proposed_goals": []
		}
		var test_comp: Dictionary = compiler.compile_request(fallback_dto, context)
		var res_class := str(test_comp.get("resolution_class", ""))
		return {
			"ok": true,
			"intent_type": "entrustment_fallback",
			"resolution_class": res_class,
			"entrustment_compilation": test_comp,
			"entrustment_dto": fallback_dto,
			"confidence": 0.75,
			"safe_rejection": true,
			"requires_confirmation": false,
			"clarification_required": res_class == "needs_clarification",
			"clarification_questions": test_comp.get("clarification_questions", []),
			"executor_id": str(context.get("npc_id", "")),
			"raw_text": text,
			"error": str(test_comp.get("system_boundary_note", test_comp.get("explanation", "")))
		}

	return _unknown("no_structured_intent_detected", context)

func get_supported_intent_types(data: Dictionary) -> Array:
	var types: Array = []
	for mapping in data.get("npc_interactions", {}).get("intent_mappings", []):
		var intent_type := str(mapping.get("intent_type", ""))
		if intent_type != "" and not types.has(intent_type):
			types.append(intent_type)
	for mapping in _beta_0_5_intent_mappings():
		var intent_type := str(mapping.get("intent_type", ""))
		if intent_type != "" and not types.has(intent_type):
			types.append(intent_type)
	for mapping in _entrustment_intent_mappings():
		var intent_type := str(mapping.get("intent_type", ""))
		if intent_type != "" and not types.has(intent_type):
			types.append(intent_type)
	for mapping in data.get("dialogue_intents_beta_0_9", []):
		var intent_type := str(mapping.get("intent_type", ""))
		if intent_type != "" and not types.has(intent_type):
			types.append(intent_type)
	types.append("unknown")
	return types

func _matches_mapping(text: String, mapping: Dictionary) -> bool:
	return _match_score(text, mapping) > 0

func _append_mappings_with_priority(target: Array, source: Array, priority: int) -> void:
	for mapping in source:
		var prioritized_mapping: Dictionary = mapping.duplicate(true)
		prioritized_mapping["_intent_source_priority"] = priority
		target.append(prioritized_mapping)

func _match_score(text: String, mapping: Dictionary) -> int:
	var intent_type := str(mapping.get("intent_type", ""))
	var extractor = GenericEntrustmentSlotExtractorScript.new()
	if extractor._is_negated_or_non_execution(text):
		return 0
	if intent_type == "confirm_entrustment" and extractor._has_substantive_new_request(text):
		return 0
	var lower := text.to_lower()
	var score := 0
	for keyword in mapping.get("keywords", []):
		var key := str(keyword).strip_edges().to_lower()
		if key != "" and lower.contains(key):
			score = maxi(score, key.length())
	score = maxi(score, _semantic_match_score(text, mapping))
	return score

func _intent_from_mapping(player_text: String, context: Dictionary, mapping: Dictionary, api_candidate: Dictionary = {}) -> Dictionary:
	var intent_type := str(mapping.get("intent_type", "unknown"))
	var political_object_type := _political_object_type_from_mapping(mapping)
	var state_changing := bool(mapping.get("state_changing", _default_state_changing_for_political_object(political_object_type)))
	var source_type := _source_type_from_text(player_text, str(mapping.get("source_type", "private_talk")))
	var executor_id := str(mapping.get("default_executor_id", ""))
	if executor_id == "":
		executor_id = str(context.get("npc_id", ""))
	var requires_formal_decree := bool(mapping.get("requires_formal_decree", false))
	if intent_type == "draft_decree":
		requires_formal_decree = false
	var intent_dict := {
		"ok": true,
		"intent_type": intent_type,
		"decision_id": str(mapping.get("decision_id", "")),
		"executor_id": executor_id,
		"target_id": str(mapping.get("target_id", "")),
		"target": str(mapping.get("target_id", "")),
		"source_type": source_type,
		"confidence": float(mapping.get("confidence", 0.65)),
		"requires_confirmation": state_changing or bool(mapping.get("requires_confirmation", false)),
		"requires_formal_decree": requires_formal_decree,
		"leverage_type": str(mapping.get("leverage_type", "")),
		"related_topic_id": str(context.get("active_topic_id", "")),
		"political_object_type": political_object_type,
		"related_context_id": str(context.get("context_id", context.get("selected_context_id", ""))),
		"related_context_kind": str(context.get("context_kind", "")),
		"affected_entities": _affected_entities_from_mapping(context, mapping, executor_id),
		"target_character_id": _target_character_from_text(player_text, mapping, context),
		"risk_tags": mapping.get("risk_tags", []).duplicate(true),
		"state_changing": state_changing,
		"raw_text": player_text.left(MAX_PLAYER_TEXT_CHARS)
	}

	if ["entrust_seek_retainer", "entrust_craft_item", "entrust_compile_work", "query_entrustment", "cancel_entrustment", "confirm_entrustment"].has(intent_type):
		var v2_dto: Dictionary = _build_entrustment_v2_dto(intent_type, player_text, context, api_candidate)
		var compiler = EntrustmentRequestCompilerScript.new()
		var compilation: Dictionary = compiler.compile_request(v2_dto, context)
		intent_dict["entrustment_dto"] = v2_dto
		intent_dict["entrustment_compilation"] = compilation
		if intent_type in ["confirm_entrustment", "cancel_entrustment", "query_entrustment"]:
			intent_dict["resolution_class"] = "supported"
		else:
			intent_dict["resolution_class"] = str(compilation.get("resolution_class", "supported"))
		intent_dict["plan_hash"] = str(compilation.get("plan_hash", ""))
		var extractor = GenericEntrustmentSlotExtractorScript.new()
		var slot_res: Dictionary = extractor.extract(player_text, context)
		var deadline_dict: Dictionary = v2_dto.get("deadline", slot_res.get("deadline", {}))
		var due_days := int(v2_dto.get("due_days", slot_res.get("due_days", deadline_dict.get("exact_days", 5))))
		intent_dict["deadline"] = deadline_dict
		intent_dict["due_days"] = due_days

		if intent_type == "entrust_compile_work" or slot_res.get("domain") == "compile_or_process_work":
			var work_name := str(slot_res.get("item_name", slot_res.get("target_name", "王维诗卷")))
			var task_title := str(slot_res.get("task_name", "整理装订《" + work_name + "》一卷"))
			intent_dict["target_type"] = "manuscript"
			intent_dict["target_archetype"] = "manuscript_book"
			intent_dict["target_name"] = work_name
			intent_dict["target_item"] = str(slot_res.get("target_item", "诗集"))
			intent_dict["item_name"] = work_name
			intent_dict["item_category"] = "BOOK"
			intent_dict["work_subtype"] = str(slot_res.get("work_subtype", "poetry_anthology"))
			intent_dict["source_work_id"] = str(slot_res.get("source_work_id", ""))
			intent_dict["source_summary"] = str(slot_res.get("source_summary", ""))
			intent_dict["author_id"] = str(slot_res.get("author_id", executor_id))
			intent_dict["author_name"] = str(slot_res.get("author_name", ""))
			intent_dict["editor_id"] = str(slot_res.get("editor_id", executor_id))
			intent_dict["volume_count"] = int(slot_res.get("volume_count", 1))
			intent_dict["task_name"] = task_title
		elif intent_type == "entrust_craft_item" or slot_res.get("domain") == "procure_item":
			var item_name := str(slot_res.get("target_item", "百炼宝剑"))
			var task_title := str(slot_res.get("task_name", "督造采办【" + item_name + "】"))
			var item_cat := str(slot_res.get("item_category", "EQUIPMENT"))
			intent_dict["target_type"] = "item"
			intent_dict["target_archetype"] = "generic_item"
			intent_dict["target_item"] = item_name
			intent_dict["item_name"] = item_name
			intent_dict["item_category"] = item_cat
			intent_dict["task_name"] = task_title
		elif intent_type == "entrust_seek_retainer" or slot_res.get("domain") == "seek_person":
			var role_name := str(slot_res.get("target_role", "武勇门客"))
			var spec_name := str(slot_res.get("specialty", ""))
			var task_title := str(slot_res.get("task_name", "寻访【" + role_name + "】并引见"))
			var sem_stat := str(slot_res.get("semantic_stat", "governance"))
			var key_name := str(slot_res.get("key_stat_name", "才干"))
			var arch := str(slot_res.get("target_archetype", "generic_retainer"))

			intent_dict["target_type"] = "character"
			intent_dict["target_archetype"] = arch
			intent_dict["target_role"] = role_name
			intent_dict["specialty"] = spec_name
			intent_dict["source_org"] = str(slot_res.get("source_org", ""))
			intent_dict["is_plural"] = bool(slot_res.get("is_plural", false))
			intent_dict["semantic_stat"] = sem_stat
			intent_dict["key_stat_name"] = key_name
			intent_dict["task_name"] = task_title
		if intent_dict["resolution_class"] in ["impossible_in_world", "unsupported_capability"]:
			intent_dict["safe_rejection"] = true
			intent_dict["requires_confirmation"] = false
		elif intent_dict["resolution_class"] == "needs_clarification":
			intent_dict["clarification_required"] = true
			intent_dict["clarification_questions"] = compilation.get("clarification_questions", [])

	return intent_dict

func _semantic_match_score(text: String, mapping: Dictionary) -> int:
	var intent_type := str(mapping.get("intent_type", ""))
	var lower := text.to_lower()
	var extractor = GenericEntrustmentSlotExtractorScript.new()
	var slot_res: Dictionary = extractor.extract(text)
	var domain := str(slot_res.get("domain", ""))

	if domain == "conversation_only":
		return 0
	if intent_type == "cancel_entrustment" and (domain == "cancel" or text.contains("作罢") or text.contains("不用找") or text.contains("不用办") or text.contains("取消") or text.contains("不必再找")):
		return 35
	if intent_type == "query_entrustment" and (domain == "query" or text.contains("进度") or text.contains("如何了") or text.contains("着落") or text.contains("可有消息")):
		return 35
	if intent_type == "confirm_entrustment":
		if extractor._has_substantive_new_request(text):
			return 0
		if domain == "confirm" or text.contains("有劳") or text.contains("依卿") or text.contains("准卿") or text.contains("托付于卿"):
			return 35
	if intent_type == "accept_retainer" and (domain == "accept" or text.contains("纳为门客") or text.contains("留用") or text.contains("入幕") or text.contains("收下") or text.contains("纳用") or text.contains("延请") or text.contains("收入内府") or text.contains("展卷")):
		return 40
	if (intent_type == "view_dossier" or intent_type == "inquire_test") and (domain == "inspect" or text.contains("档案") or text.contains("能力") or text.contains("履历") or text.contains("本事") or text.contains("查看") or text.contains("查阅") or text.contains("考较") or text.contains("比试") or text.contains("品读")):
		return 35
	if intent_type == "decline_politely" and (domain == "decline" or text.contains("婉拒") or text.contains("礼送") or text.contains("赐银") or text.contains("送其出") or text.contains("赏赐匠人") or text.contains("留赐")):
		return 35
	if intent_type == "entrust_compile_work" and domain == "compile_or_process_work":
		return 42
	if intent_type == "entrust_craft_item" and (domain == "procure_item" or text.contains("打造") or text.contains("宝剑") or text.contains("铸剑") or text.contains("铸造") or text.contains("锻造") or text.contains("神兵") or text.contains("兵器") or text.contains("采买") or text.contains("置办")):
		if domain in ["cancel", "query", "accept", "decline", "inspect", "compile_or_process_work"]:
			return 5
		return 35
	if intent_type == "entrust_seek_retainer" and (domain == "seek_person" or text.contains("死士") or text.contains("刺客") or text.contains("门客") or text.contains("游侠") or text.contains("护卫") or text.contains("物色") or text.contains("寻访") or text.contains("郎中") or text.contains("谋士") or text.contains("账房")):
		if domain in ["cancel", "query", "accept", "decline", "inspect", "compile_or_process_work"]:
			return 5
		return 35
	if intent_type == "offer_office_promise" and text.contains("许") and (text.contains("军权") or text.contains("名分") or text.contains("正式")):
		return 8
	if intent_type == "ask_map_pressure" and text.contains("压力") and (text.contains("路") or text.contains("粮道") or text.contains("节点")):
		return 8
	if intent_type == "delay_request" and lower.contains("delay") and lower.contains("uighur") and lower.contains("terms"):
		return 18
	if intent_type == "ask_support_against_npc" and lower.contains("support me against") and lower.contains("li fuguo"):
		return 24
	if intent_type == "offer_office_promise" and lower.contains("grant guo formal authority"):
		return 30
	if intent_type == "bargain_private_access" and lower.contains("recognize li fuguo channel"):
		return 30
	if intent_type == "start_negotiation" and lower.contains("negotiate uighur terms"):
		return 30
	if intent_type == "ask_supply_delay" and lower.contains("why is grain delayed"):
		return 30
	return 0

func _political_object_type_from_mapping(mapping: Dictionary) -> String:
	var explicit_type := str(mapping.get("political_object_type", ""))
	if explicit_type != "":
		return explicit_type
	var object_types: Array = mapping.get("object_types", [])
	if object_types.size() > 0:
		return str(object_types[0])
	return ""

func _default_state_changing_for_political_object(political_object_type: String) -> bool:
	return ["promise", "decree", "task", "regional_operation", "memory", "rumor"].has(political_object_type)

func _affected_entities_from_mapping(context: Dictionary, mapping: Dictionary, executor_id: String) -> Array:
	var entities: Array = []
	for entity in mapping.get("affected_entities", []):
		_append_unique_non_empty(entities, str(entity))
	_append_unique_non_empty(entities, executor_id)
	_append_unique_non_empty(entities, str(context.get("target_character_id", "")))
	return entities

func _append_unique_non_empty(items: Array, value: String) -> void:
	if value == "" or items.has(value):
		return
	items.append(value)

func _target_character_from_text(player_text: String, mapping: Dictionary, context: Dictionary) -> String:
	var explicit_target := str(mapping.get("target_character_id", ""))
	if explicit_target != "":
		return explicit_target
	var lower := player_text.to_lower()
	var known := {
		"li fuguo": "li_fuguo",
		"guo ziyi": "guo_ziyi",
		"li bi": "li_bi",
		"uighur envoy": "uighur_envoy",
		"li guangbi": "li_guangbi",
		"pugu huaien": "pugu_huaien",
		"li chu": "li_chu",
		"old court": "hardline_old_court_official",
		"merchant": "lingwu_merchant_refugee",
		"jiedushi": "regional_jiedushi_rep",
		"李辅国": "li_fuguo",
		"郭子仪": "guo_ziyi",
		"李泌": "li_bi",
		"回纥": "uighur_envoy",
		"李光弼": "li_guangbi",
		"仆固怀恩": "pugu_huaien",
		"李俶": "li_chu",
		"旧臣": "hardline_old_court_official",
		"旧朝": "hardline_old_court_official",
		"粮官": "grain_official_lingwu",
		"粮草官": "grain_official_lingwu"
	}
	for key in known.keys():
		if lower.contains(str(key)):
			return str(known[key])
	return str(context.get("target_character_id", ""))

func _source_type_from_text(player_text: String, fallback: String) -> String:
	var lower := player_text.to_lower()
	if lower.contains("formal") or lower.contains("decree") or lower.contains("edict") or player_text.contains("诏") or player_text.contains("敕"):
		return "formal_decree"
	if lower.contains("private") or player_text.contains("密"):
		return "private_instruction"
	if lower.contains("negotiate") or player_text.contains("谈"):
		return "negotiation"
	return fallback

func _unknown(reason: String, context: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"intent_type": "unknown",
		"decision_id": "",
		"executor_id": str(context.get("npc_id", "")),
		"target_id": "",
		"target": "",
		"source_type": "private_talk",
		"confidence": 0.0,
		"requires_confirmation": false,
		"requires_formal_decree": false,
		"leverage_type": "",
		"related_topic_id": str(context.get("active_topic_id", "")),
		"target_character_id": "",
		"risk_tags": [],
		"state_changing": false,
		"safe_rejection": true,
		"clarification_required": reason in ["ambiguous_intent", "empty_player_text", "no_structured_intent_detected"],
		"error": reason
	}

func _beta_0_5_intent_mappings() -> Array:
	return [
		{"intent_type": "ask_stance", "keywords": ["stance", "position", "support route", "what do you support", "立场"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.72},
		{"intent_type": "ask_about_npc", "keywords": ["about li fuguo", "about guo ziyi", "about li bi", "about uighur envoy", "ask guo about li fuguo", "opinion of", "怎么看", "评价"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.78},
		{"intent_type": "ask_acceptable_terms", "keywords": ["acceptable terms", "acceptable bargain", "what terms", "conditions", "条件"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.74},
		{"intent_type": "ask_recent_memory", "keywords": ["recent memory", "remember", "what happened before", "记得", "旧事"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.68},
		{"intent_type": "ask_red_line", "keywords": ["red line", "cannot accept", "底线", "不能接受"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.72},
		{"intent_type": "ask_relationship", "keywords": ["relationship", "trusts", "distrusts", "关系"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.7},
		{"intent_type": "offer_promise", "keywords": ["promise", "offer promise", "formal commander authority", "office authority", "promise formal commander authority", "许诺", "承诺"], "state_changing": true, "requires_confirmation": true, "source_type": "private_instruction", "leverage_type": "office_or_command_authority", "risk_tags": ["promise_debt"], "confidence": 0.82},
		{"intent_type": "threaten_consequence", "keywords": ["threaten", "consequence", "investigate", "punishment if", "威胁", "后果"], "state_changing": true, "requires_confirmation": true, "source_type": "public_audience", "leverage_type": "threat_of_punishment", "risk_tags": ["threat"], "confidence": 0.78},
		{"intent_type": "request_formal_memorial", "keywords": ["formal memorial", "write memorial", "memorial requirement", "奏章", "表文"], "state_changing": true, "requires_confirmation": true, "source_type": "formal_decree", "leverage_type": "formal_decree", "risk_tags": ["paperwork_delay"], "confidence": 0.76},
		{"intent_type": "convert_to_decree", "keywords": ["convert to decree", "make decree", "issue edict", "成诏", "诏令"], "state_changing": true, "requires_confirmation": true, "source_type": "formal_decree", "leverage_type": "formal_decree", "risk_tags": ["legitimacy"], "confidence": 0.8},
		{"intent_type": "private_instruction", "keywords": ["private instruction", "privately order", "secret instruction", "密令", "私下"], "state_changing": true, "requires_confirmation": true, "source_type": "private_instruction", "leverage_type": "private_protection", "risk_tags": ["secret_debt"], "confidence": 0.76},
		{"intent_type": "public_commitment", "keywords": ["public commitment", "public reassure", "announce commitment", "公开承诺", "安民"], "state_changing": true, "requires_confirmation": true, "source_type": "public_audience", "leverage_type": "public_reassurance", "risk_tags": ["public_expectation"], "confidence": 0.76},
		{"intent_type": "offer_resource_backing", "keywords": ["resource backing", "grain backing", "treasury backing", "粮草支持", "府库"], "state_changing": true, "requires_confirmation": true, "source_type": "private_instruction", "leverage_type": "resource_allocation", "risk_tags": ["resource_pressure"], "confidence": 0.8},
		{"intent_type": "appeal_to_loyalty", "keywords": ["appeal to loyalty", "loyalty", "忠义", "大义"], "state_changing": true, "requires_confirmation": true, "source_type": "public_audience", "leverage_type": "appeal_to_loyalty", "risk_tags": ["honor_pressure"], "confidence": 0.7},
		{"intent_type": "appeal_to_legitimacy", "keywords": ["appeal to legitimacy", "legitimacy", "正统", "名分"], "state_changing": true, "requires_confirmation": true, "source_type": "formal_decree", "leverage_type": "appeal_to_legitimacy", "risk_tags": ["legitimacy"], "confidence": 0.72},
		{"intent_type": "request_support_against_npc", "keywords": ["support against", "support me against", "牵制", "支持我对付"], "state_changing": true, "requires_confirmation": true, "source_type": "private_instruction", "leverage_type": "request_support_against_another_npc", "risk_tags": ["relationship_risk"], "confidence": 0.8},
		{"intent_type": "close_audience", "keywords": ["close audience", "end audience", "dismiss", "退下", "结束召对"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.64},
		{"intent_type": "change_topic", "keywords": ["change topic", "another matter", "switch topic", "另议", "换个话题"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.66},
		{"intent_type": "request_terms", "keywords": ["name your terms", "terms would satisfy", "开条件", "要什么"], "state_changing": false, "requires_confirmation": false, "source_type": "private_talk", "confidence": 0.68},
		{"intent_type": "record_refusal", "keywords": ["record refusal", "note refusal", "记下拒绝", "拒不奉诏"], "state_changing": true, "requires_confirmation": true, "source_type": "public_audience", "leverage_type": "formal_record", "risk_tags": ["relationship_loss"], "confidence": 0.72}
	]

func _entrustment_intent_mappings() -> Array:
	return [
		{
			"intent_type": "entrust_compile_work",
			"keywords": [
				"诗集", "诗稿", "诗卷", "那些诗", "这几首诗", "整理成册",
				"装订成册", "装订", "抄好", "抄录", "誊写", "誊抄",
				"书信册", "那些信", "文稿", "手稿", "编纂诗集", "做一本诗集",
				"compile work", "compile poems", "transcribe letters"
			],
			"state_changing": true,
			"requires_confirmation": true,
			"source_type": "private_talk",
			"political_object_type": "task",
			"confidence": 0.94
		},
		{
			"intent_type": "entrust_craft_item",
			"keywords": [
				"打造一口宝剑", "打造宝剑", "派人打造", "打造神兵", "打造兵器",
				"铸剑", "铸造", "锻造", "打造", "宝剑", "神兵", "兵器",
				"采买", "置办", "做一把", "配一把", "找口剑", "帮我造",
				"替我造", "替朕造", "找人打造", "定制宝剑", "铸一口剑",
				"craft sword", "forge weapon", "craft item"
			],
			"state_changing": true,
			"requires_confirmation": true,
			"source_type": "private_talk",
			"political_object_type": "task",
			"confidence": 0.88
		},
		{
			"intent_type": "entrust_seek_retainer",
			"keywords": [
				"寻访死士", "找个护卫", "物色刺客", "推荐壮士", "寻访游侠", "托付寻人",
				"物色", "寻访", "找个刺客", "找一名高手", "寻个死士", "找刺客",
				"寻访刺客", "死士", "刺客", "门客", "游侠", "护卫",
				"找郎中", "寻访郎中", "找大夫", "寻个名医", "找个神医", "物色郎中",
				"医术高明的郎中", "找一名郎中", "寻医问药", "找个医者", "请名医",
				"找名医", "寻访名医", "郎中", "大夫", "名医", "神医", "医者",
				"seek retainer", "find assassin", "recruit retainer"
			],
			"state_changing": true,
			"requires_confirmation": true,
			"source_type": "private_talk",
			"political_object_type": "task",
			"confidence": 0.85
		},
		{
			"intent_type": "query_entrustment",
			"keywords": [
				"之前托付的事如何了", "死士有着落了吗", "寻访进度", "托付进展", "如何了",
				"寻访得如何", "打听得如何", "可有消息", "进展如何", "进度如何",
				"郎中有着落了吗", "可有寻得名医", "诗集装订得如何",
				"query entrustment", "retainer progress"
			],
			"state_changing": false,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		},
		{
			"intent_type": "cancel_entrustment",
			"keywords": [
				"此事作罢", "不用找了", "取消托付", "不用办了", "罢了", "暂且作罢",
				"就此作罢", "不必再找", "取消寻访", "cancel entrustment"
			],
			"state_changing": true,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		},
		{
			"intent_type": "confirm_entrustment",
			"keywords": [
				"那就有劳了", "就依卿所言", "准卿所请", "托付于卿", "有劳了", "有劳",
				"辛苦卿了", "全赖卿了", "依卿之见", "confirm entrustment"
			],
			"state_changing": true,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		},
		{
			"intent_type": "accept_retainer",
			"keywords": [
				"纳为门客", "留用", "收归幕下", "准其入幕", "收下", "纳用", "收下宝剑", "收下神兵", "收纳", "延请入幕", "延请", "请入幕府", "收入内府书箧", "收入书箧", "收入书箱", "收下书卷", "收下诗集", "收入内府", "accept retainer", "accept item"
			],
			"state_changing": true,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		},
		{
			"intent_type": "view_dossier",
			"keywords": [
				"查看档案", "查看能力", "查看门客", "查阅履历", "看看本事", "查看此人", "查看物品", "查看神兵", "查看宝剑", "考较武艺", "考较", "展卷品读", "品读诗卷", "查看书卷", "view dossier", "inquire test"
			],
			"state_changing": false,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		},
		{
			"intent_type": "decline_politely",
			"keywords": [
				"以礼婉拒", "婉拒", "礼送", "赐银送出", "送他离开", "薄仪礼送", "赏赐匠人", "赏赐工匠", "留赐编者", "decline politely"
			],
			"state_changing": true,
			"requires_confirmation": false,
			"source_type": "private_talk",
			"confidence": 0.85
		}
	]

func _build_entrustment_v2_dto(intent_type: String, text: String, context: Dictionary = {}, api_candidate: Dictionary = {}) -> Dictionary:
	var speech_act := "request_favor"
	var goals: Array = []
	var unmapped: Array = []
	var extractor = GenericEntrustmentSlotExtractorScript.new()
	var slot_res: Dictionary = extractor.extract(text, context)
	var deadline_dict: Dictionary = slot_res.get("deadline", {})
	if api_candidate.get("deadline") is Dictionary and not (api_candidate.get("deadline") as Dictionary).is_empty():
		deadline_dict = (api_candidate.get("deadline") as Dictionary).duplicate(true)
	elif int(api_candidate.get("due_days", 0)) > 0:
		deadline_dict = {"mentioned": true, "exact_days": int(api_candidate.get("due_days", 0))}
	var due_days := int(deadline_dict.get("exact_days", slot_res.get("due_days", 5)))
	if due_days <= 0:
		due_days = 5

	if intent_type == "entrust_compile_work" or slot_res.get("domain") == "compile_or_process_work":
		speech_act = "request_favor"
		var work_subtype := str(slot_res.get("work_subtype", api_candidate.get("work_subtype", "poetry_anthology")))
		var deliverable_name := str(slot_res.get("item_name", slot_res.get("target_name", api_candidate.get("item_name", "王维诗卷"))))
		var task_title := str(slot_res.get("task_name", api_candidate.get("task_name", "整理装订《" + deliverable_name + "》一卷")))
		var target_item := str(slot_res.get("target_item", "诗集"))
		var npc_id := str(context.get("npc_id", context.get("executor_id", "wang_wei")))
		var author_id := str(slot_res.get("author_id", npc_id))
		var author_name := str(slot_res.get("author_name", "王维" if author_id == "wang_wei" else "近臣"))
		var source_work_id := str(slot_res.get("source_work_id", "%s_existing_poems" % author_id))
		var source_summary := str(slot_res.get("source_summary", "收录近作与旧稿汇为一卷"))
		if int(deadline_dict.get("exact_days", 0)) <= 0:
			due_days = int(slot_res.get("due_days", 3))
		goals.append({
			"capability_hint": "compile_or_process_work",
			"arguments": {
				"archetype_id": work_subtype,
				"quantity": 1,
				"task_name": task_title,
				"target_name": deliverable_name,
				"target_item": target_item,
				"item_name": deliverable_name,
				"target_type": "manuscript",
				"item_category": "BOOK",
				"work_subtype": work_subtype,
				"source_work_id": source_work_id,
				"source_summary": source_summary,
				"author_id": author_id,
				"author_name": author_name,
				"editor_id": str(slot_res.get("editor_id", npc_id)),
				"volume_count": 1,
				"due_days": due_days
			},
			"requirements": [{"field_hint": "quality", "value_hint": "high"}]
		})
		for cond in slot_res.get("unmapped_hard_conditions", []):
			if not unmapped.has(cond):
				unmapped.append(cond)
	elif intent_type == "entrust_craft_item" or slot_res.get("domain") == "procure_item":
		speech_act = "request_favor"
		var item_name := str(slot_res.get("target_item", api_candidate.get("target_item", "百炼宝剑")))
		item_name = extractor._strip_time_and_courtesy_clauses(item_name)
		if item_name.is_empty():
			item_name = str(slot_res.get("target_item", "百炼宝剑"))
		var task_title := str(slot_res.get("task_name", "督造采办【" + item_name + "】"))
		var item_cat := str(slot_res.get("item_category", "EQUIPMENT"))
		var item_arch := "generic_item"
		if text.contains("剑") or item_name.contains("剑"):
			item_arch = "item_sword"
		elif text.contains("甲") or text.contains("铠"):
			item_arch = "item_armor"
		goals.append({
			"capability_hint": "craft_item",
			"arguments": {
				"archetype_id": item_arch,
				"quantity": 1,
				"task_name": task_title,
				"target_item": item_name,
				"target_type": "item",
				"item_category": item_cat,
				"due_days": due_days
			},
			"requirements": [{"field_hint": "prowess", "value_hint": "high"}]
		})
	elif intent_type == "entrust_seek_retainer" or slot_res.get("domain") == "seek_person":
		speech_act = "request_favor"
		var role_name := str(slot_res.get("target_role", api_candidate.get("target_role", "武勇门客")))
		var spec_name := str(slot_res.get("specialty", api_candidate.get("specialty", "")))
		var task_title := str(slot_res.get("task_name", "寻访【" + role_name + "】并引见"))
		var sem_stat := str(slot_res.get("semantic_stat", "governance"))
		var arch_id := str(slot_res.get("target_archetype", "generic_retainer"))
		var key_name := str(slot_res.get("key_stat_name", "才干"))

		var reqs: Array = []
		reqs.append({"field_hint": sem_stat, "value_hint": "high"})
		if text.contains("本地") or text.contains("同乡") or text.contains("灵武") or text.contains("朔方"):
			reqs.append({"field_hint": "origin_local", "value_hint": "local"})

		goals.append({
			"capability_hint": "find_person_and_introduce",
			"arguments": {
				"archetype_id": arch_id,
				"target_role": role_name,
				"specialty": spec_name,
				"task_name": task_title,
				"semantic_stat": sem_stat,
				"key_stat_name": key_name,
				"target_type": "character",
				"quantity": 1,
				"due_days": due_days
			},
			"requirements": reqs
		})
		if text.contains("左撇子"):
			unmapped.append("左撇子特质")
		if text.contains("吟诗") or text.contains("诗赋"):
			unmapped.append("文采特质")
		if text.contains("绝对忠诚") or text.contains("永不背叛"):
			unmapped.append("绝对忠诚保证")
	elif intent_type == "query_entrustment":
		speech_act = "query_progress"
		goals.append({
			"capability_hint": "query_progress",
			"arguments": {},
			"requirements": []
		})
	elif intent_type == "cancel_entrustment":
		speech_act = "cancel"
		goals.append({
			"capability_hint": "cancel_entrustment",
			"arguments": {},
			"requirements": []
		})
	elif intent_type == "confirm_entrustment":
		speech_act = "confirm"

	return {
		"speech_act": speech_act,
		"evidence_text": text,
		"raw_text": text,
		"deadline": deadline_dict,
		"due_days": due_days,
		"proposed_goals": goals,
		"unmapped_requirements": unmapped
	}
