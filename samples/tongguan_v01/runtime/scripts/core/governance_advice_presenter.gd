extends RefCounted

class_name GovernanceAdvicePresenter

const MAX_STATEMENT_CHARS := 480
const MIN_COUNCIL_STATEMENT_CHARS := 32
const COUNCIL_RESPONSE_MAX_TOKENS := 512
const MUTATING_REPLY_FIELDS := [
	"recommended_action", "action_id", "recipient_id", "location_id", "resources",
	"authority_tags", "report_due_day", "governance_state", "office_state", "holder_id",
	"draft_patch", "conflict_output", "settlement"
]
const TECHNICAL_MARKERS := [
	"governance_state", "game_state", "holder_id", "order_id", "action_id",
	"save_version", "gdscript", "json", "api", "system prompt", "系统提示",
	"写入存档", "状态写入", "执行指令", "[", "]", "{", "}", " = "
]

func build_public_packet(council: Dictionary, adviser_id: String) -> Dictionary:
	var opinions: Array = []
	for raw_opinion in council.get("round_one", council.get("opinions", [])):
		if raw_opinion is Dictionary:
			var opinion: Dictionary = raw_opinion
			opinions.append({"adviser_id":str(opinion.get("adviser_id", "")),"position":str(opinion.get("position", "")),"recommended_action":str(opinion.get("recommended_action", "")),"visible_risks":opinion.get("visible_risks", []).duplicate(true),"known_basis":opinion.get("known_basis", []).duplicate(true)})
	return {"topic":str(council.get("topic", "")),"adviser_id":adviser_id,"visible_facts":council.get("visible_facts", []).duplicate(true),"visible_resistance":council.get("visible_resistance", []).duplicate(true),"opinions":opinions,"allowed_actions":council.get("allowed_actions", []).duplicate(true)}

func build_accountability_claim_packet(case_dto: Dictionary, claim_id: String, semantic_slot_hash: String) -> Dictionary:
	return {"request_kind": "accountability_claim_style", "case": case_dto.duplicate(true), "claim_id": claim_id, "semantic_slot_hash": semantic_slot_hash, "allowed_response_fields": ["claim_id", "semantic_slot_hash", "style_id", "emphasis_slot_ids"]}

func fallback_advice(packet: Dictionary) -> Dictionary:
	return {"speaker_name":"朝议记录官","tone":"cautious","text":"已据公开事实整理意见，请由御前依结构化草案裁定。","source":"template"}

func render_offline_consultation(packet: Dictionary) -> Dictionary:
	var adviser := _offline_speaker(packet)
	var basis := _first_public_item(packet.get("known_basis", packet.get("visible_facts", [])), "已呈公开案情")
	var risk := _first_public_item(packet.get("visible_risks", packet.get("visible_resistance", [])), "后续尚待核验")
	return {"ok": true, "source": "offline", "tone": "measured", "text": "%s以为，当先核实%s；同时留意%s，方可定议。" % [adviser, basis, risk]}

func build_consultation_reply_packet(memorial: Dictionary, adviser: Dictionary, turns: Array, player_text: String) -> Dictionary:
	var safe_turns: Array = []
	for raw_turn in turns:
		if safe_turns.size() >= 24 or not raw_turn is Dictionary:
			continue
		var turn: Dictionary = raw_turn
		var text := str(turn.get("text", "")).replace("\n", " ").strip_edges()
		if text.is_empty():
			continue
		safe_turns.append({"turn_id": str(turn.get("turn_id", "")), "speaker": str(turn.get("speaker", "")).left(32), "text": text.left(MAX_STATEMENT_CHARS)})
	return {
		"request_kind": "governance_consultation_reply",
		"memorial_id": str(memorial.get("memorial_id", "")),
		"speaker_id": str(adviser.get("adviser_id", adviser.get("id", ""))),
		"speaker_name": str(adviser.get("display_name", adviser.get("name", "朝臣"))).left(64),
		"speaker_role": str(adviser.get("role", "朝臣")).left(96),
		"topic": str(memorial.get("topic", "")),
		"visible_facts": _public_string_array(memorial.get("visible_facts", [])),
		"visible_resistance": _public_string_array(memorial.get("visible_resistance", [])),
		"request_text": str(memorial.get("request_text", "")).replace("\n", " ").strip_edges().left(MAX_STATEMENT_CHARS),
		"adviser_ability": clampi(int(adviser.get("governance_ability", adviser.get("ability", 0))), 0, 100),
		"public_transcript": safe_turns,
		"player_text": player_text.replace("\n", " ").strip_edges().left(MAX_STATEMENT_CHARS),
		"response_max_tokens": 512,
		"prompt": "你正在与皇帝进行不设轮数上限的政务商议。只能依据奏折公开事实、公开顾虑和对话记录回答；不得执行命令、修改状态或直接生成已生效的政令。请用一段简明但完整的臣下答复回应皇帝当前问题。"
	}

func build_consultation_summary_packet(memorial: Dictionary, adviser: Dictionary, selected_turns: Array, adjacent_player_turns: Array) -> Dictionary:
	return {
		"request_kind": "governance_consultation_summary",
		"memorial_id": str(memorial.get("memorial_id", "")),
		"speaker_id": str(adviser.get("adviser_id", adviser.get("id", ""))),
		"speaker_name": str(adviser.get("display_name", adviser.get("name", "朝臣"))).left(64),
		"speaker_role": str(adviser.get("role", "朝臣")).left(96),
		"topic": str(memorial.get("topic", "")),
		"visible_facts": _public_string_array(memorial.get("visible_facts", [])),
		"visible_resistance": _public_string_array(memorial.get("visible_resistance", [])),
		"selected_turns": _sanitize_consultation_turns(selected_turns, true),
		"adjacent_player_turns": _sanitize_consultation_turns(adjacent_player_turns, false),
		"response_max_tokens": 512,
		"prompt": "请仅根据选中的大臣回复及相邻的皇帝问题，结合奏折公开事实，归纳一份可供御前修改的圣旨草稿。只写圣旨正文，不得新增受命人、行动、地点、资源、期限或任何系统字段；这只是草稿，不代表已经下旨或执行。"
	}

func sanitize_consultation_reply(reply: Dictionary) -> Dictionary:
	if not bool(reply.get("used_api", false)):
		return _reply_fail("live_reply_required")
	if _has_mutating_fields(reply):
		return _reply_fail("mutating_reply")
	var text := str(reply.get("reply_text", reply.get("text", ""))).replace("\n", " ").strip_edges()
	if bool(reply.get("truncated", false)) or str(reply.get("finish_reason", "")) == "length":
		return _reply_fail("truncated_reply")
	if text.is_empty() or text.length() > MAX_STATEMENT_CHARS or _contains_technical_or_mutating_text(text):
		return _reply_fail("invalid_reply")
	return {"ok": true, "text": text, "tone": _safe_tone(str(reply.get("tone", "measured"))), "source": "ai"}

func sanitize_consultation_summary(reply: Dictionary) -> Dictionary:
	if not bool(reply.get("used_api", false)):
		return _reply_fail("live_summary_required")
	if _has_mutating_fields(reply):
		return _reply_fail("mutating_reply")
	var text := str(reply.get("reply_text", reply.get("edict_text", reply.get("text", "")))).replace("\n", " ").strip_edges()
	if bool(reply.get("truncated", false)) or str(reply.get("finish_reason", "")) == "length":
		return _reply_fail("truncated_reply")
	if text.is_empty() or text.length() > 1200 or _contains_technical_or_mutating_text(text):
		return _reply_fail("invalid_reply")
	return {"ok": true, "edict_text": text, "source": "ai", "tone": _safe_tone(str(reply.get("tone", "firm")))}

func render_offline_consultation_reply(packet: Dictionary) -> Dictionary:
	var template_text := _offline_consultation_reply_template(str(packet.get("memorial_id", "")).strip_edges())
	if not template_text.is_empty():
		return {"ok": true, "source": "offline", "tone": "measured", "text": template_text}
	var rendered := render_offline_consultation(packet)
	rendered["source"] = "offline"
	return rendered

func render_offline_turn(packet: Dictionary) -> Dictionary:
	var adviser := _offline_speaker(packet)
	var basis := _first_public_item(packet.get("known_basis", packet.get("visible_facts", [])), "已呈公开案情")
	var risk := _first_public_item(packet.get("visible_risks", packet.get("visible_resistance", [])), "后续尚待核验")
	var position := str(packet.get("position", "conditional_support"))
	var proposal := "先行核验后办理" if position == "insufficient_authority" else "依已知依据稳妥办理"
	return {"ok": true, "source": "offline", "tone": "cautious" if position == "insufficient_authority" else "measured", "text": "%s谨陈：%s。所据为%s；但%s，宜留复核余地。" % [adviser, proposal, basis, risk]}

func render_offline_edict(packet: Dictionary) -> Dictionary:
	var template_text := _offline_consultation_edict_template(str(packet.get("memorial_id", "")).strip_edges())
	if not template_text.is_empty():
		return {"ok": true, "source": "offline", "tone": "firm", "text": template_text}
	var basis := "依公开案情办理"
	for raw_basis in packet.get("included_basis", []):
		if raw_basis is Dictionary and not str((raw_basis as Dictionary).get("display_text", "")).strip_edges().is_empty():
			basis = str((raw_basis as Dictionary).get("display_text", ""))
			break
		if raw_basis is String and not str(raw_basis).strip_edges().is_empty():
			basis = str(raw_basis)
			break
	return {"ok": true, "source": "offline", "tone": "firm", "text": "敕：%s。受命者依期核办，具报施行经过。" % basis}

func render_offline_report(packet: Dictionary) -> Dictionary:
	var topic := _topic_label(str(packet.get("topic", "")))
	return {"ok": true, "source": "offline", "tone": "measured", "text": "%s一事已按既定命令登记，后续进展将依日程回报。" % topic}

func _offline_consultation_reply_template(memorial_id: String) -> String:
	match memorial_id:
		"memorial_shuofang_grain_001":
			return "臣请先核验粮道转运与沿线仓储，再据军情安排军粮次序；急运可救军前，但应留下账册与回报期限。"
		"memorial_lingwu_ration_001":
			return "臣请先核对仓粮与军民名册，分明军需与民赈后定配给次序；仓籍应留复核副本，以便后续查验。"
		"memorial_gate_review_001":
			return "臣请先核验宫门传令与中书留档，分清授权边界后再行发布；急令可行，但应留下双签与回报期限。"
		_:
			return ""

func _offline_consultation_edict_template(memorial_id: String) -> String:
	match memorial_id:
		"memorial_shuofang_grain_001":
			return "奉旨：先核验粮道转运账册与沿线仓储，按军情安排军粮次序，限期具报。"
		"memorial_lingwu_ration_001":
			return "奉旨：先核对仓粮与军民名册，分明军需与民赈后定配给次序，留下复核副本。"
		"memorial_gate_review_001":
			return "奉旨：先核验宫门传令与中书留档，依授权边界办理，限期回报。"
		"memorial_beta110_supply_completed":
			return "奉旨：核验粮册结果与仓籍副本，公开核账凭据，限期具报。"
		"memorial_beta110_supply_partial":
			return "奉旨：准补交粮册缺页凭据，复核差额与责任，限期具报。"
		"memorial_beta110_supply_delayed":
			return "奉旨：裁定粮册补核期限，先核迟延对军期的影响，限期具报。"
		"memorial_beta110_supply_blocked":
			return "奉旨：核实朔方前营粮道受阻，确认备用转运与收讫凭据，限期具报。"
		"memorial_beta110_palace_completed":
			return "奉旨：核验宫门副本与传令记录，公开留痕范围，限期复核具报。"
		"memorial_beta110_palace_partial":
			return "奉旨：补录传令缺项，复核中书留档与责任，限期具报。"
		"memorial_beta110_palace_delayed":
			return "奉旨：就旧制先例与传令迟延作公开说明，复核程序后具报。"
		"memorial_beta110_palace_blocked":
			return "奉旨：暂缓执行受阻诏令，保存异议与复核记录，限期具报。"
		"memorial_beta110_alliance_completed":
			return "奉旨：核定援助交换条款，登记付款凭据与履约期限，限期具报。"
		"memorial_beta110_alliance_partial":
			return "奉旨：核定未完援助的前线代价，登记已付款项与补付期限，限期具报。"
		"memorial_beta110_alliance_delayed":
			return "奉旨：复核援助迟延造成的盟约影响，决定续约或补偿期限，具报。"
		"memorial_beta110_alliance_blocked":
			return "奉旨：先保存终局证据链与异议记录，再行结算援助责任，限期具报。"
		_:
			return ""

func _offline_speaker(packet: Dictionary) -> String:
	var name := str(packet.get("speaker_name", packet.get("speaker_id", "朝臣"))).strip_edges()
	return name if not name.is_empty() else "朝臣"

# Legacy statement helpers remain available to non-council callers. The sequential
# council flow must use build_turn_packet() and sanitize_turn_reply() instead.
func build_statement_packet(council: Dictionary, opinion: Dictionary, adviser: Dictionary, round: int = 1) -> Dictionary:
	var topic := str(council.get("topic", ""))
	return {
		"speaker_id": str(opinion.get("adviser_id", "")),
		"speaker_name": str(adviser.get("name", "大臣")),
		"speaker_role": str(adviser.get("role", "朝臣")),
		"topic": topic,
		"position": str(opinion.get("position", "conditional_support")),
		"known_basis": _public_string_array(opinion.get("known_basis", [])),
		"visible_risks": _public_string_array(opinion.get("visible_risks", [])),
		"round": clampi(round, 1, 2),
		"prompt": "御前问：此事关乎%s，诸卿以为何如？" % _topic_label(topic)
	}

func fallback_statement(packet: Dictionary) -> Dictionary:
	var speaker_name := str(packet.get("speaker_name", "朝议记录官")).strip_edges()
	if speaker_name.is_empty():
		speaker_name = "朝议记录官"
	var fact := _first_public_item(packet.get("known_basis", []), "事有可核")
	var risk := _first_public_item(packet.get("visible_risks", []), "未可轻忽")
	var position := str(packet.get("position", "conditional_support"))
	var assessment := "宜暂缓施行" if position == "insufficient_authority" else "宜先核验情形"
	return {
		"speaker_name": speaker_name,
		"tone": "cautious" if position == "insufficient_authority" else "measured",
		"text": "臣闻%s；今据%s，又恐%s。%s，再候御前裁定。" % [_topic_label(str(packet.get("topic", ""))), fact, risk, assessment],
		"source": "template"
	}

func sanitize_statement_reply(reply: Dictionary, packet: Dictionary) -> Dictionary:
	if reply.has("used_api") and not bool(reply.get("used_api", false)):
		return fallback_statement(packet)
	for raw_key in reply.keys():
		if MUTATING_REPLY_FIELDS.has(str(raw_key)):
			return fallback_statement(packet)
	var text := str(reply.get("reply_text", reply.get("text", ""))).replace("\n", " ").strip_edges()
	if text.is_empty() or text.length() > MAX_STATEMENT_CHARS or _contains_technical_or_mutating_text(text):
		return fallback_statement(packet)
	var speaker_name := str(packet.get("speaker_name", "朝议记录官")).strip_edges()
	if speaker_name.is_empty():
		speaker_name = "朝议记录官"
	return {
		"speaker_name": speaker_name,
		"tone": _safe_tone(str(reply.get("tone", "measured"))),
		"text": text,
		"source": "ai"
	}

func build_turn_packet(council: Dictionary, turn: Dictionary, public_transcript: Array, player_intervention: String) -> Dictionary:
	var safe_opening_question := str(council.get("opening_question", "")).replace("\n", " ").strip_edges().left(MAX_STATEMENT_CHARS)
	var reply_to_turn_ids := _public_string_array(turn.get("reply_to_turn_ids", []))
	var safe_transcript := _sanitize_public_transcript(public_transcript)
	var clean_intervention := player_intervention.replace("\n", " ").strip_edges()
	return {
		"speaker_id": str(turn.get("speaker_id", "")),
		"topic": str(council.get("topic", "")),
		"visible_facts": _public_string_array(council.get("visible_facts", [])),
		"visible_resistance": _public_string_array(council.get("visible_resistance", [])),
		"position": str(turn.get("position", "")),
		"reply_mode": str(turn.get("reply_mode", "")),
		"turn_purpose": _turn_purpose(str(turn.get("phase", "")), safe_opening_question),
		"reply_to_turn_ids": reply_to_turn_ids,
		"public_transcript": safe_transcript,
		"imperial_opening_question": safe_opening_question,
		"player_intervention": clean_intervention,
		"response_max_tokens": COUNCIL_RESPONSE_MAX_TOKENS,
		"prompt": _turn_prompt(turn, reply_to_turn_ids, safe_transcript, clean_intervention, safe_opening_question)
	}

func sanitize_turn_reply(reply: Dictionary, minimum_statement_chars: int = 0) -> Dictionary:
	if not bool(reply.get("used_api", false)):
		return _reply_fail("live_reply_required")
	if _has_mutating_fields(reply):
		return _reply_fail("mutating_reply")
	if bool(reply.get("truncated", false)) or str(reply.get("finish_reason", "")) == "length":
		return _reply_fail("truncated_reply")
	var text := str(reply.get("reply_text", "")).replace("\n", " ").strip_edges()
	if text.is_empty() or _contains_technical_or_mutating_text(text):
		return _reply_fail("invalid_reply")
	if minimum_statement_chars > 0 and (text.length() < minimum_statement_chars or not _has_complete_sentence_ending(text)):
		return _reply_fail("incomplete_reply")
	return {"ok": true, "text": text, "tone": _safe_tone(str(reply.get("tone", "measured"))), "source": "ai"}

func build_edict_packet(council: Dictionary, drafter_turns: Array, basis: Array) -> Dictionary:
	var nominated_drafter_id := _valid_nominated_drafter_id(council)
	var safe_basis := _sanitize_clause_basis(basis)
	return {
		"council_id": str(council.get("council_id", "")),
		"topic": str(council.get("topic", "")),
		"nominated_drafter_id": nominated_drafter_id,
		"drafter_public_turns": _nominated_public_turns(drafter_turns, nominated_drafter_id),
		"public_transcript": _edict_public_turns(drafter_turns, safe_basis, nominated_drafter_id),
		"included_basis": safe_basis,
		"prompt": "由点名大臣代拟圣旨；已纳入意见的发言人可以与拟旨者不同，均须作为依据。请依这些公开进言代拟一份供御前修改的圣旨正文；不得新增行动、受命人、资源、期限或任何系统指令。"
	}

func sanitize_edict_reply(reply: Dictionary, _packet: Dictionary) -> Dictionary:
	var clean := sanitize_turn_reply(reply)
	if not bool(clean.get("ok", false)):
		return clean
	clean["edict_text"] = str(clean.get("text", ""))
	clean.erase("text")
	return clean

func _topic_label(topic: String) -> String:
	match topic:
		"inner_court_oversight": return "内廷传令"
		"military_supply": return "军中粮道"
		"border_defense": return "边防军情"
		"office_appointment": return "朝廷用人"
		_: return "朝廷政务"

func _public_string_array(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for raw_item in value:
		if raw_item is String and not str(raw_item).strip_edges().is_empty():
			result.append(str(raw_item))
	return result

func _sanitize_consultation_turns(turns: Array, adviser_reply: bool) -> Array:
	var result: Array = []
	for raw_turn in turns:
		if result.size() >= 24 or not raw_turn is Dictionary:
			continue
		var turn: Dictionary = raw_turn
		var text := str(turn.get("text", "")).replace("\n", " ").strip_edges()
		if text.is_empty():
			continue
		result.append({"turn_id": str(turn.get("turn_id", "")).left(128), "speaker": "adviser" if adviser_reply else "player", "text": text.left(MAX_STATEMENT_CHARS)})
	return result

func _first_public_item(value: Variant, fallback: String) -> String:
	var items := _public_string_array(value)
	return str(items[0]) if not items.is_empty() else fallback

func _sanitize_public_transcript(transcript: Array) -> Array:
	var result: Array = []
	for raw_turn in transcript:
		if not raw_turn is Dictionary:
			continue
		var turn: Dictionary = raw_turn
		var source := str(turn.get("source", "")).strip_edges()
		var turn_id := str(turn.get("turn_id", "")).strip_edges()
		var text := str(turn.get("text", "")).replace("\n", " ").strip_edges()
		if source == "emperor":
			if turn_id == "opening_question" and not text.is_empty():
				result.append({"source": "emperor", "turn_id": "opening_question", "text": text.left(MAX_STATEMENT_CHARS)})
			continue
		var speaker_id := str(turn.get("speaker_id", "")).strip_edges()
		if turn_id.is_empty() or speaker_id.is_empty() or text.is_empty():
			continue
		result.append({
			"turn_id": turn_id,
			"speaker_id": speaker_id,
			"phase": str(turn.get("phase", "")).strip_edges(),
			"text": text.left(MAX_STATEMENT_CHARS)
		})
	return result

func _sanitize_clause_basis(basis: Array) -> Array:
	var result: Array = []
	for raw_clause in basis:
		if not raw_clause is Dictionary:
			continue
		var clause: Dictionary = raw_clause
		var clause_id := str(clause.get("clause_id", "")).strip_edges()
		var display_text := str(clause.get("display_text", "")).replace("\n", " ").strip_edges()
		if clause_id.is_empty() or display_text.is_empty():
			continue
		result.append({
			"clause_id": clause_id,
			"adviser_id": str(clause.get("adviser_id", "")).strip_edges(),
			"label": str(clause.get("label", "")).replace("\n", " ").strip_edges(),
			"display_text": display_text.left(MAX_STATEMENT_CHARS)
		})
	return result

func _valid_nominated_drafter_id(council: Dictionary) -> String:
	var nominated_drafter_id := str(council.get("nominated_drafter_id", "")).strip_edges()
	if nominated_drafter_id.is_empty():
		return ""
	var raw_seat_ids: Variant = council.get("seat_ids", [])
	if raw_seat_ids is Array:
		var seat_ids: Array = raw_seat_ids
		if not seat_ids.is_empty() and not seat_ids.has(nominated_drafter_id):
			return ""
	return nominated_drafter_id

func _nominated_public_turns(turns: Array, nominated_drafter_id: String) -> Array:
	if nominated_drafter_id.is_empty():
		return []
	var nominated_turns: Array = []
	for raw_turn in turns:
		if raw_turn is Dictionary and str((raw_turn as Dictionary).get("speaker_id", "")).strip_edges() == nominated_drafter_id:
			nominated_turns.append((raw_turn as Dictionary).duplicate(true))
	return _sanitize_public_transcript(nominated_turns)

func _edict_public_turns(turns: Array, basis: Array, nominated_drafter_id: String) -> Array:
	var source_ids: Array[String] = []
	if not nominated_drafter_id.is_empty():
		source_ids.append(nominated_drafter_id)
	for raw_clause in basis:
		if raw_clause is Dictionary:
			var adviser_id := str((raw_clause as Dictionary).get("adviser_id", "")).strip_edges()
			if not adviser_id.is_empty() and not source_ids.has(adviser_id):
				source_ids.append(adviser_id)
	var relevant_turns: Array = []
	for raw_turn in turns:
		if raw_turn is Dictionary and source_ids.has(str((raw_turn as Dictionary).get("speaker_id", "")).strip_edges()):
			relevant_turns.append((raw_turn as Dictionary).duplicate(true))
	return _sanitize_public_transcript(relevant_turns)

func _turn_prompt(turn: Dictionary, reply_to_turn_ids: Array, safe_transcript: Array, player_intervention: String, safe_opening_question: String) -> String:
	var purpose := _turn_purpose(str(turn.get("phase", "")), safe_opening_question)
	var reply_mode := str(turn.get("reply_mode", "")).strip_edges()
	var response := "先陈明本席主张"
	if not reply_to_turn_ids.is_empty():
		match reply_mode:
			"rebut": response = "须先反驳所指定的前席进言，再陈述本席主张"
			"support", "align": response = "须先迎合或补强所指定的前席进言，再陈述本席主张"
			_: response = "须先权衡所指定的前席进言，再陈述本席主张"
	var transcript_note := "已有公开进言可供回应" if not safe_transcript.is_empty() else "尚无前席进言"
	var intervention_note := "御前诘问：%s" % player_intervention if not player_intervention.is_empty() else "御前未另加诘问"
	return "御前命卿作%s。%s；%s。%s。只可依据公开事实、公开转录与御前诘问发言，不得声称执行命令、修改人物、资源、官职、存档或结算。请以纯正文作答，约八十至一百四十字，直陈理由、处置与一项顾虑，务必以完整句收束。" % [purpose, response, transcript_note, intervention_note]

func _turn_purpose(phase: String, safe_opening_question: String = "") -> String:
	if phase == "opening" and not safe_opening_question.is_empty():
		return "开陈，须先回应御前所问"
	match phase:
		"opening": return "开陈"
		"cross_examination": return "辨难"
		"final_position": return "定议"
		_: return "陈词"

func _has_mutating_fields(reply: Dictionary) -> bool:
	for raw_key in reply.keys():
		if MUTATING_REPLY_FIELDS.has(str(raw_key)):
			return true
	return false

func _reply_fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

func _contains_technical_or_mutating_text(text: String) -> bool:
	var lowered := text.to_lower()
	for marker in TECHNICAL_MARKERS:
		if lowered.contains(str(marker).to_lower()):
			return true
	return false

func _has_complete_sentence_ending(text: String) -> bool:
	return text.ends_with("。") or text.ends_with("！") or text.ends_with("？") or text.ends_with(".") or text.ends_with("!") or text.ends_with("?")

func _safe_tone(value: String) -> String:
	return value if value in ["cautious", "measured", "firm", "supportive"] else "measured"
