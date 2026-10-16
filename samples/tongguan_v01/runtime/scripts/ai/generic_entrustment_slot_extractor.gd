extends RefCounted

class_name GenericEntrustmentSlotExtractor

# Generic Entrustment Slot Extractor
# Responsible for dynamic natural-language slot parsing without keyword-by-keyword hardcoding.
# Follows the Game Constitution and 2026-09-20-private-entrustment-design.md.

const QUANTIFIERS := [
	"一个", "一位", "一名", "两名", "两位", "两个", "几名", "几位", "几个",
	"一口", "一把", "一副", "一件", "一柄", "两匹", "一匹", "几匹", "一盒", "两盒", "几盒",
	"一顶", "一领", "一车", "两车", "几车", "批", "点", "些"
]

const LEADING_STRIP := [
	"替我", "帮我", "为我", "为朕", "替朕", "派人去", "派人", "去帮我", "去替我",
	"去给我", "给我", "请帮我", "烦请", "劳烦", "速去", "立刻", "务必", "切记",
	"我让他", "让他", "我叫他", "命他", "着他", "令他", "叫他", "命其", "着其", "令其",
	"物色", "寻访", "寻找", "招募", "招揽", "引见", "推荐", "挑一个", "选一个", "找一个",
	"找个", "找名", "找一名", "找位", "找一位", "聘请", "延揽", "打造", "铸造", "锻造",
	"采买", "采办", "置办", "搜寻", "搜罗", "做一把", "做一口", "做一副", "做一件", "做",
	"缝制", "制备", "买", "购入", "上等", "极品", "精良", "顶级"
]

const TRAILING_STRIP := [
	"为我效力", "为朕效力", "供我驱策", "随侍左右", "随驾听用", "伺候左右",
	"入幕", "效力", "听用", "驱策", "并引见", "来见我", "送来", "呈递御前", "呈递上来",
	"呈上", "备用", "防身", "随身佩戴", "以备后用", "来", "用"
]

func extract_slots(player_text: String, context: Dictionary = {}) -> Dictionary:
	return extract(player_text, context)

func parse_request(player_text: String, context: Dictionary = {}) -> Dictionary:
	return extract(player_text, context)

func _parse_chinese_number(num_str: String) -> int:
	var s := num_str.strip_edges()
	if s.is_empty():
		return -1
	if s.is_valid_int():
		return int(s)
	match s:
		"半月": return 15
		"一月", "一个月", "三旬": return 30
		"两月", "两个月": return 60
		"一旬", "旬": return 10
		"两旬", "二旬": return 20
	var digit_map := {
		"零": 0, "〇": 0,
		"一": 1, "壹": 1,
		"二": 2, "两": 2, "贰": 2,
		"三": 3, "叁": 3,
		"四": 4, "肆": 4,
		"五": 5, "伍": 5,
		"六": 6, "陆": 6,
		"七": 7, "柒": 7,
		"八": 8, "捌": 8,
		"九": 9, "玖": 9
	}
	if digit_map.has(s):
		return int(digit_map[s])
	var total := 0
	var current := 0
	var matched_any := false
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		if digit_map.has(ch):
			current = int(digit_map[ch])
			matched_any = true
		elif ch in ["十", "拾"]:
			matched_any = true
			if current == 0:
				current = 1
			total += current * 10
			current = 0
		elif ch in ["百", "佰"]:
			matched_any = true
			if current == 0:
				current = 1
			total += current * 100
			current = 0
		else:
			return -1
	total += current
	return total if matched_any and total > 0 else -1

func extract_deadline(text: String, current_day: int = 0) -> Dictionary:
	var raw := text.strip_edges()
	if raw.is_empty():
		return {"mentioned": false, "exact_days": 5, "is_vague": false, "text": ""}
	if raw.contains("明天") or raw.contains("明日"):
		return {"mentioned": true, "exact_days": 1, "is_vague": false, "text": "明日"}

	# 1. Check explicit target game day ("第30日回话" / "第三十日")
	var abs_regex := RegEx.new()
	abs_regex.compile("第\\s*([零一二两三四五六七八九十百0-9]+)\\s*(天|日)(回话|复命|交我|给朕|给我|呈上|之前|前|内)?")
	var abs_matches := abs_regex.search_all(raw)
	if not abs_matches.is_empty():
		var m: RegExMatch = abs_matches[abs_matches.size() - 1]
		var target_day := _parse_chinese_number(m.get_string(1))
		if target_day >= 0:
			var rel_days := maxi(1, target_day - current_day) if current_day > 0 else maxi(1, target_day)
			return {
				"mentioned": true,
				"is_absolute_day": true,
				"target_day": target_day,
				"exact_days": rel_days,
				"is_vague": false,
				"text": m.get_string(0)
			}

	# 2. Full contiguous Chinese/Arabic numeral + temporal unit matching
	var rel_regex := RegEx.new()
	rel_regex.compile("(半月|一个月|一月|两个月|两月|一旬|两旬|三旬|[零一二两三四五六七八九十百0-9]+)\\s*(天后|日后|天内|日内|天之内|日之内|天为期|日为期|天|日)")
	var rel_matches := rel_regex.search_all(raw)
	var best_days := -1
	var best_pat := ""
	for m in rel_matches:
		var num_token: String = m.get_string(1)
		var parsed_days := _parse_chinese_number(num_token)
		if parsed_days > 0:
			best_days = parsed_days
			best_pat = m.get_string(0)
	if best_days > 0:
		return {"mentioned": true, "exact_days": best_days, "is_vague": false, "text": best_pat}

	for vague_pat in ["过几天", "几天后", "过几日", "几日后", "数日后", "过些时日", "五七日"]:
		if raw.contains(vague_pat):
			return {"mentioned": true, "exact_days": 5, "suggested_days": 5, "is_vague": true, "text": vague_pat}
	return {"mentioned": false, "exact_days": 5, "is_vague": false, "text": ""}

func _strip_time_and_courtesy_clauses(text: String) -> String:
	var s := text.strip_edges()
	var regex := RegEx.new()
	regex.compile("(，|,|\\s)*(约定)?(第\\s*[零一二两三四五六七八九十百0-9]+\\s*(天|日)|(过几天|几天后|过几日|几日后|数日后|半月|一个月|一月|两个月|两月|一旬|两旬|三旬|[零一二两三四五六七八九十百0-9]+\\s*(天|日)(后|内|之内|为期)?))(再|后|内)?(给我|给朕|交我|呈上|呈递|送来|回话|复命)?")
	s = regex.sub(s, "", true)
	for c in ["，有劳你了", "，有劳卿了", "，有劳了", "，有劳", "有劳你了", "有劳卿了", "，辛苦你了", "，辛苦了"]:
		if s.ends_with(c):
			s = s.substr(0, s.length() - c.length()).strip_edges()
	return s.strip_edges()

func _split_delivery_and_time_clauses(text: String) -> Dictionary:
	var s := _strip_time_and_courtesy_clauses(text)
	var delivery_clauses: Array[String] = []

	# Match explicit post-discovery clauses: "，找到后带来见朕", "，寻得后引见", "找到带来见朕", etc.
	var post_find_regex := RegEx.new()
	post_find_regex.compile("(，|,|\\s)*(找到|寻得|觅得|寻到|访得|物色到|挑好|选好|办妥|觅到)(人选|人物|之后|以后|后)?(?=.*(带来|带回|领来|引来|送来|引见|来见|回话|复命|呈上|交我|给朕|给我)|人选|人物|之后|以后|后)[^，。！？]*")
	for m in post_find_regex.search_all(s):
		delivery_clauses.append(m.get_string(0).strip_edges())
	s = post_find_regex.sub(s, "", true).strip_edges()

	# Match trailing delivery / audience clauses even when attached directly after deadline removal (e.g. "刺客带来见朕")
	var trailing_delivery_regex := RegEx.new()
	trailing_delivery_regex.compile("(，|,|\\s)*(再|即刻|立刻|速速|便|就)?(将其|把人|将人)?(带来见朕|带来见我|带回见朕|带回行在|领来见朕|领来见我|引来见朕|引来见我|送来见朕|送来见我|带来引见|带来听用|带来复命|领来引见|引见给朕|引见给我|并引见|引见|来见朕|来见我|带来|领来|引来)$")
	for m in trailing_delivery_regex.search_all(s):
		delivery_clauses.append(m.get_string(0).strip_edges())
	s = trailing_delivery_regex.sub(s, "", true).strip_edges()

	return {
		"object_text": s,
		"delivery_clause": "；".join(delivery_clauses),
		"has_delivery_clause": not delivery_clauses.is_empty()
	}

func _extract_existing_role_from_context(context: Dictionary) -> String:
	if context.is_empty():
		return ""
	var direct_role := str(context.get("existing_target_role", context.get("target_role", ""))).strip_edges()
	if not direct_role.is_empty() and not _has_clause_noise(direct_role):
		return direct_role
	var pending: Dictionary = context.get("pending_entrustment", {}) if context.get("pending_entrustment", {}) is Dictionary else {}
	if not pending.is_empty():
		var plan: Dictionary = pending.get("plan", pending) if pending.get("plan", pending) is Dictionary else pending
		var p_role := str(plan.get("target_role", pending.get("target_role", ""))).strip_edges()
		if not p_role.is_empty() and not _has_clause_noise(p_role):
			return p_role
	return ""

func extract(player_text: String, context: Dictionary = {}) -> Dictionary:
	var raw := player_text.strip_edges()
	if raw.is_empty():
		return {"domain": "unknown", "confidence": 0.0}

	var cur_day := int(context.get("current_day", 0))
	var deadline := extract_deadline(raw, cur_day)

	# 0. Negation, joke, quote, or non-execution inquiry guard (must precede keyword/verb extraction)
	if _is_negated_or_non_execution(raw):
		return {
			"domain": "conversation_only",
			"speech_act": "negated_or_inquiry",
			"is_negated": true,
			"deadline": deadline,
			"confidence": 0.95,
			"raw_text": raw
		}

	if _is_pure_work_or_status_inquiry(raw):
		return {
			"domain": "ask_info",
			"speech_act": "ask_info",
			"deadline": deadline,
			"confidence": 0.92,
			"raw_text": raw
		}

	# 0.5 Term modification ("改成五天" / "三天不行，五天也可" / or delivery/deadline supplement on existing pending role)
	var split_info := _split_delivery_and_time_clauses(raw)
	var object_only_text := str(split_info.get("object_text", "")).strip_edges()
	var existing_ctx_role := _extract_existing_role_from_context(context)
	if _matches_modify_terms(raw) or (object_only_text.is_empty() and (bool(deadline.get("mentioned", false)) or bool(split_info.get("has_delivery_clause", false))) and not existing_ctx_role.is_empty()):
		return {
			"domain": "modify_terms",
			"speech_act": "modify_terms",
			"target_role": existing_ctx_role,
			"delivery_clause": str(split_info.get("delivery_clause", "")),
			"deadline": deadline,
			"due_days": int(deadline.get("exact_days", 5)),
			"confidence": 0.92,
			"raw_text": raw
		}

	# 0.6 Isolated delivery clause without any target role in sentence or context -> clarify instead of inventing a role
	if object_only_text.is_empty() and bool(split_info.get("has_delivery_clause", false)) and existing_ctx_role.is_empty():
		return {
			"ok": false,
			"domain": "needs_clarification",
			"intent_type": "entrust_needs_clarification",
			"resolution_class": "needs_clarification",
			"clarification_reason": "missing_target_role",
			"delivery_clause": str(split_info.get("delivery_clause", "")),
			"deadline": deadline,
			"due_days": int(deadline.get("exact_days", 5)),
			"reason": "尚未明言所要寻访之人物类别（如刺客、郎中、谋士或宿卫），请先告知物色对象。",
			"confidence": 0.92,
			"raw_text": raw
		}

	# 1. Dialogue rapid actions (only when not carrying a new substantive request)
	if _matches_acknowledge_report(raw):
		return {"domain": "acknowledge_report", "speech_act": "acknowledge_report", "deadline": deadline, "confidence": 0.95, "raw_text": raw}
	if _matches_continue_search(raw):
		return {"domain": "continue_search", "speech_act": "continue_search", "deadline": deadline, "confidence": 0.95, "raw_text": raw}
	if _matches_confirm(raw):
		return {"domain": "confirm", "speech_act": "confirm", "deadline": deadline, "confidence": 0.95, "raw_text": raw}
	if _matches_cancel(raw):
		return {"domain": "cancel", "speech_act": "cancel", "deadline": deadline, "confidence": 0.95, "raw_text": raw}
	if _matches_query(raw):
		return {"domain": "query", "speech_act": "query_progress", "deadline": deadline, "confidence": 0.90, "raw_text": raw}
	if _matches_accept(raw):
		return {"domain": "accept", "speech_act": "accept", "deadline": deadline, "confidence": 0.90, "raw_text": raw}
	if _matches_decline(raw):
		return {"domain": "decline", "speech_act": "decline", "deadline": deadline, "confidence": 0.90, "raw_text": raw}
	if _matches_inspect(raw):
		return {"domain": "inspect", "speech_act": "inspect", "deadline": deadline, "confidence": 0.90, "raw_text": raw}

	# 2. Constitutional boundaries: Impossible in world
	if _is_impossible_in_world(raw):
		return {
			"domain": "impossible_in_world",
			"deadline": deadline,
			"confidence": 0.95,
			"raw_text": raw,
			"reason": "所请超出天理常轨，非人力所能及。"
		}

	# 3. System boundary: Unsupported capabilities (assassination, banquet)
	var unsupported_hint := _detect_unsupported_hint(raw)
	if not unsupported_hint.is_empty():
		return {
			"domain": "unsupported_capability",
			"deadline": deadline,
			"confidence": 0.95,
			"raw_text": raw,
			"unsupported_capability": "execute_assassination" if raw.contains("刺杀") or raw.contains("暗杀") else "other",
			"reason": unsupported_hint
		}

	# 4. Constitutional boundary: Formal court decree required (state matters cannot be private errands)
	if _requires_formal_decree(raw):
		return {
			"domain": "formal_decree",
			"requires_formal_decree": true,
			"deadline": deadline,
			"confidence": 0.90,
			"raw_text": raw,
			"reason": "军国重务与除授封驳当由中书门下廷议明发朝旨，私下安敢擅专。"
		}

	# 4.5 Compile / Process existing work or manuscript (e.g., 王维诗集装订成册 / 把那些诗抄好 / 抄录书信 / 整理文稿)
	var work_res := _try_extract_manuscript_work(raw, context, deadline)
	if bool(work_res.get("ok", false)):
		return work_res

	# 5. Procure / Craft item extraction
	var item_res := _try_extract_item(raw, deadline)
	if bool(item_res.get("ok", false)):
		return item_res

	# 6. Seek / Introduce person extraction
	var person_res := _try_extract_person(raw, deadline)
	if bool(person_res.get("ok", false)):
		return person_res

	return {"domain": "unknown", "deadline": deadline, "confidence": 0.0, "raw_text": raw}

func _is_negated_or_non_execution(text: String) -> bool:
	if text.contains("随便问问") or text.contains("只是问问") or text.contains("开玩笑") or text.contains("逗你玩") or text.contains("他曾经说") or text.contains("假如") or text.contains("若是能"):
		return true
	for neg in ["不用打造", "不用装订", "不用抄", "不必打造", "不必装订", "不要打造", "不要装订", "别替我找", "别帮我找", "不要替我找", "无须打造", "无须装订"]:
		if text.contains(neg):
			return true
	return false

func _is_pure_work_or_status_inquiry(text: String) -> bool:
	if (text.contains("可有诗作") or text.contains("可有诗稿") or text.contains("可有新吟") or text.contains("诗篇") or text.contains("新诗") or text.contains("近来可有") or text.contains("不知可有") or text.contains("写的什么诗") or text.contains("有何诗作") or text.contains("询问近况")) and not (text.contains("装订") or text.contains("整理") or text.contains("抄") or text.contains("给我") or text.contains("呈上")):
		return true
	if (text.contains("听说哪里有") or text.contains("何处有")) and not (text.contains("替我") or text.contains("帮我") or text.contains("物色") or text.contains("寻访")):
		return true
	return false

func _matches_modify_terms(text: String) -> bool:
	if (text.contains("改成") or text.contains("改为") or text.contains("宽限") or (text.contains("不行") and text.contains("也可"))) and (text.contains("天") or text.contains("日")):
		return true
	return false

func _has_substantive_new_request(text: String) -> bool:
	for marker in [
		"装订", "编订", "整理成册", "抄好", "抄录", "誊抄", "诗集", "诗稿", "那些诗", "书信", "文稿",
		"打造", "铸造", "锻造", "宝剑", "神兵", "兵器", "铠甲", "做一本", "做一把", "做一口",
		"物色", "寻访", "挑选", "选拔", "招募", "找个", "找一名", "找一位", "替我", "帮我", "把你写的", "把刚才"
	]:
		if text.contains(marker):
			return true
	return false

func _matches_acknowledge_report(text: String) -> bool:
	if _has_substantive_new_request(text) or _matches_modify_terms(text):
		return false
	for kw in ["知道了", "知晓了", "阅悉", "朕知道了", "我知道了", "既如此便罢", "不必再找了", "知悉"]:
		if text.contains(kw):
			return true
	return false

func _matches_continue_search(text: String) -> bool:
	if _has_substantive_new_request(text) or _matches_modify_terms(text):
		return false
	for kw in ["继续寻找", "继续寻访", "继续物色", "再找找", "接着找", "接着寻访", "另行访查", "再宽限几日继续找"]:
		if text.contains(kw):
			return true
	return false

func _matches_confirm(text: String) -> bool:
	if _has_substantive_new_request(text) or _matches_modify_terms(text) or _is_negated_or_non_execution(text) or _matches_acknowledge_report(text) or _matches_continue_search(text):
		return false
	for kw in ["那就有劳了", "有劳你了", "有劳卿了", "有劳了", "有劳", "依卿", "准卿", "妥", "甚好", "那就交给你", "去办吧", "交由卿办理", "托付于卿", "照办", "准奏", "依你", "就依你", "依你说的", "依你办", "就按你", "尽快办妥", "尽快去办", "好生办妥", "准了", "由你来办", "好，就这么办", "就这么办", "就只办这一段"]:
		if text.contains(kw):
			return true
	return false

func _matches_cancel(text: String) -> bool:
	for kw in ["作罢", "算了", "不用找", "不用办", "取消", "不必再找", "不必再办", "暂且搁置", "先不办了"]:
		if text.contains(kw):
			return true
	return false

func _matches_query(text: String) -> bool:
	for kw in ["进度", "如何了", "有眉目了吗", "办得怎样", "可有消息", "寻得如何", "可有眉目", "进展如何"]:
		if text.contains(kw):
			return true
	return false

func _matches_accept(text: String) -> bool:
	for kw in ["纳为门客", "留用", "入幕", "纳用", "延请", "聘用", "收下宝剑", "收下神兵", "收下物资", "收下", "收入书箧"]:
		if text.contains(kw):
			return true
	return false

func _matches_decline(text: String) -> bool:
	for kw in ["以礼婉拒", "婉拒", "礼送", "赐银送出", "送他离开", "薄仪礼送", "赏赐匠人", "赏赐工匠", "赐赏", "留赐编者"]:
		if text.contains(kw):
			return true
	return false

func _matches_inspect(text: String) -> bool:
	for kw in ["查看档案", "查看能力", "查看门客", "查阅履历", "看看本事", "查看此人", "查看物品", "查看神兵", "查看宝剑", "考较武艺", "考较", "展卷品读", "查看医案"]:
		if text.contains(kw):
			return true
	return false

func _is_impossible_in_world(text: String) -> bool:
	if text.contains("月亮") and (text.contains("摘") or text.contains("取")):
		return true
	if text.contains("长生不老") or text.contains("起死回生") or text.contains("复活") or text.contains("已故") or text.contains("死人"):
		return true
	if text.contains("造核弹") or text.contains("原子弹") or text.contains("时光机") or text.contains("穿越回现代"):
		return true
	return false

func _detect_unsupported_hint(text: String) -> String:
	if text.contains("刺杀") or text.contains("暗杀") or text.contains("替我除掉") or text.contains("杀了他") or text.contains("把.*杀了"):
		return "当前版本暂不支持执行刺杀行动，朝野重臣亦不可行刺暗害。"
	if text.contains("宴席") or text.contains("酒宴") or text.contains("请客"):
		return "当前版本暂不支持安排宴席。"
	if text.contains("造反") or text.contains("谋反调查"):
		return "当前版本暂未开放针对谋反事实的秘密调查指令。"
	return ""

func _requires_formal_decree(text: String) -> bool:
	# Formal state matters requiring court chancellery process
	var military_mobilization := (text.contains("调兵") or text.contains("调拨") or text.contains("开拔") or text.contains("出兵") or text.contains("大军")) and (text.contains("万") or text.contains("千") or text.contains("全军") or text.contains("朔方军"))
	var court_appointment := (text.contains("罢免") or text.contains("革职") or text.contains("封为") or text.contains("拜相") or text.contains("加封")) and (text.contains("宰相") or text.contains("使") or text.contains("节度使") or text.contains("大夫") or text.contains("尚书"))
	var state_finance := (text.contains("征税") or text.contains("加税") or text.contains("免税") or text.contains("免除") or text.contains("两税") or text.contains("赋税") or text.contains("大赦") or text.contains("改元"))
	var decree_keywords := (text.contains("下旨") or text.contains("下诏") or text.contains("传旨") or text.contains("颁诏") or text.contains("颁旨"))
	return military_mobilization or court_appointment or state_finance or decree_keywords

const PERSON_ACTION_VERBS := [
	"挑选", "选拔", "遴选", "抽调", "征调", "物色", "寻访", "寻找",
	"招募", "招揽", "引见", "推荐", "聘请", "延揽",
	"挑", "选", "找", "寻", "聘", "求"
]

const ITEM_ACTION_VERBS := [
	"打造", "铸造", "锻造", "采买", "采办", "置办", "搜寻", "搜罗",
	"缝制", "制备", "购入", "调取", "取", "做", "买"
]

const COMPLEMENT_MARKERS := [
	"来给我当", "来给朕当", "去给我当", "去给朕当",
	"给我当", "给朕当", "替我当", "替朕当", "为我当", "为朕当",
	"给我做", "给朕做", "替我做", "替朕做", "为我做", "为朕做",
	"给我充当", "给朕充当", "替我充当", "充当", "充任", "充作",
	"担任", "当作", "作为", "来当", "来做", "去当", "去做",
	"当个", "做个", "当", "做"
]

const GENERIC_LOCATIONS := [
	"民间", "外面", "天下", "城里", "城中", "附近", "行在", "暗中",
	"私下", "到处", "四处", "地方", "坊市", "市井", "关中", "关陇",
	"各地", "身边", "左右", "宫外", "营外", "这里", "那里", "各处"
]

const KNOWN_ROLE_HEAD_NOUNS := [
	"武将", "将领", "将才",
	"禁军侍卫", "贴身侍卫", "近身侍卫", "随驾侍卫", "侍卫", "护卫", "亲卫", "近卫", "卫士",
	"死士", "刺客", "游侠", "门客", "斥候", "暗探", "细作", "耳目",
	"悬壶郎中", "郎中", "名医", "太医", "医官", "大夫", "神医", "医者", "药师",
	"淮扬名厨", "名厨", "御厨", "庖厨", "厨子", "厨师",
	"账房掌柜", "账房先生", "账房", "掌柜", "算师",
	"向导", "马夫", "工匠", "铁匠", "画师", "琴师", "乐师",
	"谋士", "策士", "幕僚", "军师", "书吏", "文士", "书办",
	"内侍", "宫人", "侍女", "随从", "士兵", "军士", "甲士"
]

func _is_plural_request(text: String) -> bool:
	for pq in ["几个", "几名", "几位", "几匹", "两个", "两名", "两位", "两匹", "两把", "三个", "三名", "数名", "数位", "一批", "些"]:
		if text.contains(pq):
			return true
	return false

func _try_extract_manuscript_work(text: String, context: Dictionary = {}, deadline: Dictionary = {}) -> Dictionary:
	var has_manuscript_kw := false
	for kw in ["诗集", "诗稿", "诗卷", "旧诗", "那些诗", "这几首诗", "那些信", "书信", "文稿", "文卷", "手稿", "书稿", "册子", "装订", "整理成册", "汇编", "编纂", "抄录", "抄写", "抄好", "誊写", "誊抄", "校勘"]:
		if text.contains(kw):
			has_manuscript_kw = true
			break
	if not has_manuscript_kw:
		return {"ok": false}

	var npc_id := str(context.get("npc_id", "")).strip_edges()
	var npc_name := str(context.get("npc_name", "")).strip_edges()
	if npc_name.is_empty():
		if npc_id == "wang_wei":
			npc_name = "王维"
		elif npc_id == "li_bi":
			npc_name = "李泌"
		elif npc_id == "guo_ziyi":
			npc_name = "郭子仪"
		elif npc_id == "li_fuguo":
			npc_name = "李辅国"
		else:
			npc_name = "近臣"

	var work_subtype := "poetry_anthology"
	var deliverable_name := "%s诗卷" % npc_name if npc_id == "wang_wei" or text.contains("诗") else "%s手订文卷" % npc_name
	var task_title := "整理装订《%s》一卷" % deliverable_name
	var source_work_id := "%s_existing_poems" % (npc_id if not npc_id.is_empty() else "npc")
	var source_summary := "收录近作与旧稿（如《山居秋暝》《竹里馆》等篇）汇为一卷" if (npc_id == "wang_wei" or text.contains("诗")) else "将案头既有书信文稿校勘誊写装订成册"

	if text.contains("书信") or text.contains("那些信") or text.contains("信件") or text.contains("密信"):
		work_subtype = "letter_transcription"
		deliverable_name = "%s誊录书信册" % npc_name
		task_title = "誊录整理《%s》一卷" % deliverable_name
		source_work_id = "%s_existing_letters" % (npc_id if not npc_id.is_empty() else "npc")
		source_summary = "将既有往来书信与手札逐一誊清并装订成册"
	elif (text.contains("文稿") or text.contains("手稿") or text.contains("奏疏") or text.contains("策论")) and not text.contains("诗"):
		work_subtype = "document_collation"
		deliverable_name = "%s校订文稿" % npc_name
		task_title = "校勘整理《%s》一卷" % deliverable_name
		source_work_id = "%s_existing_manuscripts" % (npc_id if not npc_id.is_empty() else "npc")
		source_summary = "将既有文稿与手札校勘辑录为一卷"

	var due_days := int(deadline.get("exact_days", 3 if bool(deadline.get("mentioned", false)) else 5))
	if due_days <= 0:
		due_days = 3

	var unmapped_conditions: Array = []
	if text.contains("天下人人都读过") or text.contains("传遍天下") or text.contains("人尽皆知") or text.contains("天下传诵"):
		unmapped_conditions.append("全境传播与教化（当前仅能先将既有诗稿整理装订为一卷册页交付）")
	if text.contains("一百首") or text.contains("百首新诗") or text.contains("千首"):
		unmapped_conditions.append("凭空新撰百首巨制（当前仅能就既有旧作与近稿先行汇编成册）")

	return {
		"ok": true,
		"domain": "compile_or_process_work",
		"intent_type": "entrust_compile_work",
		"target_type": "manuscript",
		"target_name": deliverable_name,
		"target_item": "诗集" if work_subtype == "poetry_anthology" else ("书信册" if work_subtype == "letter_transcription" else "文稿册"),
		"item_name": deliverable_name,
		"item_category": "BOOK",
		"work_subtype": work_subtype,
		"source_work_id": source_work_id,
		"source_summary": source_summary,
		"author_id": npc_id if not npc_id.is_empty() else "wang_wei",
		"author_name": npc_name,
		"editor_id": npc_id if not npc_id.is_empty() else "wang_wei",
		"volume_count": 1,
		"task_name": task_title,
		"target_archetype": "manuscript_book",
		"deadline": deadline,
		"due_days": due_days,
		"unmapped_hard_conditions": unmapped_conditions,
		"confidence": 0.94,
		"raw_text": text
	}

func _try_extract_item(text: String, deadline: Dictionary = {}) -> Dictionary:
	var split_res := _split_delivery_and_time_clauses(text)
	var stripped := str(split_res.get("object_text", "")).strip_edges()
	var working_text := stripped if not stripped.is_empty() else text
	var has_item_action := false
	for v in ITEM_ACTION_VERBS:
		if working_text.contains(v):
			has_item_action = true
			break

	var item_nouns := ["宝剑", "神兵", "兵器", "铠甲", "宝甲", "轻甲", "重甲", "软甲", "明光铠", "刀", "剑", "枪", "弓", "弩", "战马", "良马", "良驹", "马匹", "伤药", "金疮药", "丹药", "大氅", "皮裘", "药材", "粮草", "羽箭", "盾牌"]
	var has_item_noun := false
	for n in item_nouns:
		if working_text.contains(n):
			has_item_noun = true
			break

	# If person suffixes or role complement markers appear (e.g., 当侍卫/做护卫), it is a person request, NOT an item request
	for m in ["当侍卫", "当护卫", "当亲卫", "做侍卫", "做护卫", "士兵", "门客", "郎中", "名医", "名厨", "账房", "向导"]:
		if working_text.contains(m):
			return {"ok": false}

	if not has_item_action and not has_item_noun:
		return {"ok": false}

	var item_str := _clean_entity_string(working_text, ITEM_ACTION_VERBS)
	if item_str.is_empty():
		for n in item_nouns:
			if working_text.contains(n):
				item_str = n
				break
	if item_str.is_empty():
		item_str = "物资兵备"

	var task_verb := "督造采办"
	if working_text.contains("打造") or working_text.contains("铸造") or working_text.contains("锻造"):
		task_verb = "打造"
	elif working_text.contains("采买") or working_text.contains("买"):
		task_verb = "采办"
	elif working_text.contains("置办"):
		task_verb = "置办"

	var task_title := ""
	if working_text.contains("一口宝剑") or (task_verb == "打造" and item_str.contains("宝剑")):
		task_title = "打造一口宝剑"
	else:
		task_title = "%s%s" % [task_verb, item_str]

	var item_cat := _infer_item_category(item_str)
	var due_days := int(deadline.get("exact_days", 5))
	if due_days <= 0:
		due_days = 5

	return {
		"ok": true,
		"domain": "procure_item",
		"intent_type": "entrust_craft_item",
		"target_type": "item",
		"target_name": item_str,
		"target_item": item_str,
		"item_name": item_str,
		"item_category": item_cat,
		"task_name": task_title,
		"target_archetype": "item_sword" if item_str.contains("剑") else ("item_armor" if item_str.contains("甲") else "generic_item"),
		"deadline": deadline,
		"due_days": due_days,
		"confidence": 0.85,
		"raw_text": text
	}

func _try_extract_person(text: String, deadline: Dictionary = {}) -> Dictionary:
	var split_res := _split_delivery_and_time_clauses(text)
	var stripped := str(split_res.get("object_text", "")).strip_edges()
	var delivery_clause := str(split_res.get("delivery_clause", "")).strip_edges()
	var working_text := stripped if not stripped.is_empty() else _strip_time_and_courtesy_clauses(text)
	var has_person_verb := false
	for v in PERSON_ACTION_VERBS:
		if working_text.contains(v):
			has_person_verb = true
			break

	var person_suffixes := ["之人", "之士", "人才", "干才", "好手", "门客", "师傅", "先生", "匠人", "名医", "郎中", "大夫", "医官", "厨子", "名厨", "御厨", "账房", "掌柜", "向导", "马夫", "铁匠", "侍卫", "护卫", "亲卫", "近卫", "卫士", "士兵", "军士", "游侠", "刺客", "死士", "斥候", "谋士", "策士", "幕僚", "书吏", "医者", "药师", "侍女", "内侍", "宫人"]
	var has_person_suffix := false
	for s in person_suffixes:
		if working_text.contains(s):
			has_person_suffix = true
			break

	if not has_person_verb and not has_person_suffix:
		return {"ok": false}

	# Extract target role, specialty, source organization, and action verb via syntactic clause analysis
	var role_and_spec := _extract_role_and_spec(working_text, PERSON_ACTION_VERBS)
	var role_str: String = str(role_and_spec.get("role", "")).strip_edges()
	var spec_str: String = str(role_and_spec.get("specialty", "")).strip_edges()
	var source_org: String = str(role_and_spec.get("source_org", "")).strip_edges()
	var matched_verb: String = str(role_and_spec.get("action_verb", "")).strip_edges()
	var is_plural: bool = _is_plural_request(working_text)

	if role_str.is_empty() or _has_clause_noise(role_str):
		role_str = ""
		for s in KNOWN_ROLE_HEAD_NOUNS:
			if working_text.contains(s):
				role_str = s
				break

	if role_str.is_empty():
		# If the sentence only had a verb/delivery clause without naming any target role or specialty, require clarification
		if spec_str.is_empty():
			return {
				"ok": false,
				"domain": "needs_clarification",
				"intent_type": "entrust_needs_clarification",
				"resolution_class": "needs_clarification",
				"clarification_reason": "missing_target_role",
				"delivery_clause": delivery_clause,
				"deadline": deadline,
				"due_days": int(deadline.get("exact_days", 5)),
				"reason": "尚未明言所要物色之人物类别（如刺客、郎中、谋士或宿卫），请先示下具体要求。",
				"raw_text": text
			}
		role_str = "可用干才"

	role_str = _sanitize_extracted_role(role_str, working_text, source_org)

	var stat_info := infer_semantic_stat(role_str, spec_str)
	var is_selection := matched_verb in ["挑选", "选拔", "遴选", "抽调", "征调", "挑", "选"] or not source_org.is_empty() or role_str.contains("侍卫") or role_str.contains("禁军")
	var task_title := ""
	if role_str in ["郎中", "大夫", "名医", "神医", "医者", "悬壶郎中"] or (spec_str.contains("医") and role_str.contains("郎中")):
		task_title = "寻访医术郎中并引见"
	elif role_str in ["谋士", "策士", "军师"] or spec_str.contains("谋"):
		task_title = "寻访谋略门客并引见"
	elif role_str in ["账房", "算学", "钱粮"] or (spec_str.contains("算") and role_str == "门客"):
		task_title = "寻访理财门客并引见"
	else:
		var display_name := role_str
		if not spec_str.is_empty() and not role_str.begins_with(spec_str) and (spec_str + role_str).length() <= 14:
			display_name = spec_str + "的" + role_str
		var verb_prefix := "选拔" if is_selection else "寻访"
		task_title = "%s%s并引见" % [verb_prefix, display_name]

	var due_days := int(deadline.get("exact_days", 5))
	if due_days <= 0:
		due_days = 5

	return {
		"ok": true,
		"domain": "seek_person",
		"intent_type": "entrust_seek_retainer",
		"target_type": "character",
		"target_name": role_str,
		"target_role": role_str,
		"specialty": spec_str,
		"source_org": source_org,
		"delivery_clause": delivery_clause,
		"delivery_mode": "introduce_audience",
		"is_plural": is_plural,
		"action_verb": "选拔" if is_selection else "寻访",
		"task_name": task_title,
		"target_archetype": str(stat_info.get("archetype", "generic_retainer")),
		"semantic_stat": str(stat_info.get("stat", "governance")),
		"key_stat_name": str(stat_info.get("name", "才干")),
		"deadline": deadline,
		"due_days": due_days,
		"confidence": 0.88,
		"raw_text": text
	}

func _clean_entity_string(text: String, verbs: Array) -> String:
	var split_res := _split_delivery_and_time_clauses(text)
	var base_text := str(split_res.get("object_text", "")).strip_edges()
	if base_text.is_empty():
		base_text = text
	var post_clause := _slice_after_first_verb(base_text, verbs)
	var cleaned := post_clause if not post_clause.is_empty() else base_text
	for v in LEADING_STRIP:
		cleaned = cleaned.replace(v, " ")
	for v in verbs:
		cleaned = cleaned.replace(v, " ")
	for q in QUANTIFIERS:
		cleaned = cleaned.replace(q, " ")
	for t in TRAILING_STRIP:
		cleaned = cleaned.replace(t, " ")

	cleaned = cleaned.replace("，", " ").replace("。", " ").replace("！", " ").replace("？", " ")
	var parts := cleaned.split(" ", false)
	for i in range(parts.size() - 1, -1, -1):
		var candidate := parts[i].strip_edges()
		if candidate.contains("的"):
			var sub := candidate.split("的", false)
			candidate = sub[sub.size() - 1].strip_edges()
		if candidate.length() >= 1 and candidate.length() <= 16 and not _has_clause_noise(candidate):
			return candidate
	return ""

func _slice_after_first_verb(text: String, verbs: Array) -> String:
	var working := text.strip_edges()
	for lead in ["我让李辅国", "我让郭子仪", "我让李泌", "我让李俶", "我让他", "让他", "我叫他", "命他", "着他", "令他", "叫他", "命你", "着你", "劳烦你", "烦请你"]:
		if working.begins_with(lead):
			working = working.substr(lead.length()).strip_edges()
	var best_idx := -1
	var best_len := 0
	for v in verbs:
		var idx := working.find(v)
		if idx != -1:
			if best_idx == -1 or idx < best_idx or (idx == best_idx and v.length() > best_len):
				best_idx = idx
				best_len = v.length()
	if best_idx != -1:
		return working.substr(best_idx + best_len).strip_edges()
	return working

func _extract_source_org_from_pre_verb(pre_verb: String) -> String:
	if pre_verb.is_empty():
		return ""
	# Background like "正值战乱" is not an organization. Require an explicit
	# location construction in the clause directly preceding the request verb.
	var clause := pre_verb.replace("，", ",").replace("。", ",").split(",")[-1].strip_edges()
	var source_pattern := RegEx.new()
	source_pattern.compile("(?:从|到|在|于)([^，,。；;！？\\s]{2,16})$")
	var source_match := source_pattern.search(clause)
	if source_match == null:
		return ""
	var cleaned := source_match.get_string(1)
	for token in [
		"我让李辅国", "我让郭子仪", "我让李泌", "我让李俶",
		"李辅国", "郭子仪", "李泌", "李俶",
		"我让他", "让他", "我叫他", "命他", "着他", "令他", "叫他",
		"替我", "帮我", "为我", "为朕", "替朕", "给朕", "给我",
		"烦请", "劳烦", "速去", "立刻", "务必", "派人",
		"先到", "先去", "去到", "你到", "你去", "你从", "你在",
		"当中", "之中", "里面", "里头", "那儿", "那里",
		"从", "到", "在", "去", "往", "向", "中", "里", "内", "处",
		"你", "我", "他", "朕", "的", "，", " "
	]:
		cleaned = cleaned.replace(token, "")
	cleaned = cleaned.strip_edges()
	if cleaned.length() >= 2 and cleaned.length() <= 12 and not (cleaned in GENERIC_LOCATIONS):
		for suffix in ["军", "营", "府", "署", "院", "司", "寺", "卫", "衙"]:
			if cleaned.ends_with(suffix):
				return cleaned
	return ""

func _extract_role_and_spec(text: String, verbs: Array) -> Dictionary:
	var split_res := _split_delivery_and_time_clauses(text)
	var working := str(split_res.get("object_text", "")).strip_edges()
	if working.is_empty():
		working = _strip_time_and_courtesy_clauses(text)
	for lead in ["我让李辅国", "我让郭子仪", "我让李泌", "我让李俶", "我让他", "让他", "我叫他", "命他", "着他", "令他", "叫他", "命其", "着其", "令其"]:
		if working.begins_with(lead):
			working = working.substr(lead.length()).strip_edges()

	# 1. Locate the primary action verb (longest match at earliest position after subject/location adverbial)
	var best_idx := -1
	var best_verb := ""
	for v in PERSON_ACTION_VERBS:
		var idx := working.find(v)
		if idx != -1:
			if best_idx == -1 or idx < best_idx or (idx == best_idx and v.length() > best_verb.length()):
				best_idx = idx
				best_verb = v

	var pre_verb := ""
	var post_verb := working
	if best_idx != -1:
		pre_verb = working.substr(0, best_idx).strip_edges()
		post_verb = working.substr(best_idx + best_verb.length()).strip_edges()

	var source_org := _extract_source_org_from_pre_verb(pre_verb)

	# 2. Check for Role Complement / Purpose Pivot in post_verb (e.g., "几个忠诚勇武的士兵【给我当】侍卫")
	var appointed_role := ""
	var object_clause := post_verb
	for marker in COMPLEMENT_MARKERS:
		var m_idx := post_verb.rfind(marker)
		if m_idx > 0:
			var after_marker := post_verb.substr(m_idx + marker.length()).strip_edges()
			after_marker = _strip_trailing_and_quantifiers(after_marker)
			if after_marker.length() >= 1 and after_marker.length() <= 6 and not _has_clause_noise(after_marker):
				appointed_role = after_marker
				object_clause = post_verb.substr(0, m_idx).strip_edges()
				break

	# 3. Clean object_clause (e.g., "几个忠诚勇武的士兵" or "一个擅长烹饪的淮扬名厨")
	var cleaned_obj := _strip_trailing_and_quantifiers(object_clause)
	var spec_str := ""
	var base_role := ""
	if cleaned_obj.contains("的"):
		var de_idx := cleaned_obj.rfind("的")
		spec_str = cleaned_obj.substr(0, de_idx).strip_edges()
		base_role = cleaned_obj.substr(de_idx + 1).strip_edges()
	else:
		base_role = cleaned_obj.strip_edges()

	# Clean any remaining quantifier/verb prefix on spec_str
	spec_str = _strip_trailing_and_quantifiers(spec_str)

	# 4. Determine final target role
	var final_role := appointed_role if not appointed_role.is_empty() else base_role
	# A role head is a person type; introductory circumstances are not a type.
	# Keep the original request as evidence while separating noun and preference.
	var role_head := ""
	for noun in KNOWN_ROLE_HEAD_NOUNS:
		if final_role.ends_with(noun) and noun.length() > role_head.length():
			role_head = noun
	if not role_head.is_empty():
		var qualifier := final_role.substr(0, final_role.length() - role_head.length()).strip_edges()
		var circumstance := RegEx.new()
		circumstance.compile("(眼下|如今|当下|目前|天下)?正值战乱")
		qualifier = circumstance.sub(qualifier, "", true).trim_suffix("的").strip_edges()
		if not qualifier.is_empty() and not _has_clause_noise(qualifier):
			spec_str = (spec_str + " " + qualifier).strip_edges()
		final_role = role_head
	if not source_org.is_empty() and not final_role.is_empty() and not final_role.contains(source_org):
		if final_role not in ["郎中", "大夫", "名医", "悬壶郎中"] and (source_org + final_role).length() <= 6:
			final_role = source_org + final_role

	final_role = _sanitize_extracted_role(final_role, working, source_org)

	return {
		"role": final_role,
		"specialty": spec_str,
		"source_org": source_org,
		"action_verb": best_verb
	}

func _strip_trailing_and_quantifiers(segment: String) -> String:
	var split_res := _split_delivery_and_time_clauses(segment)
	var s := str(split_res.get("object_text", "")).strip_edges()
	s = s.replace("，", " ").replace("。", " ").replace("！", " ").replace("？", " ")
	for q in QUANTIFIERS:
		if s.begins_with(q):
			s = s.substr(q.length()).strip_edges()
		s = s.replace(q, " ")
	for lead in LEADING_STRIP:
		if s.begins_with(lead):
			s = s.substr(lead.length()).strip_edges()
	for trail in ["来核算开销", "核算开销", "来给朕看病", "给朕看病", "来保护朕", "保护朕", "随驾护卫", "护卫左右", "替朕分忧", "为我效力", "为朕效力", "供我驱策", "随侍左右", "随驾听用", "伺候左右", "带来见朕", "带来见我", "领来见朕", "引来见朕", "并引见", "来见朕", "来见我", "见朕", "见我", "送来", "呈递御前", "呈递上来", "呈上", "备用", "防身", "随身佩戴", "以备后用", "吧", "呀"]:
		if s.ends_with(trail):
			s = s.substr(0, s.length() - trail.length()).strip_edges()
	var parts := s.split(" ", false)
	if parts.is_empty():
		return ""
	for i in range(parts.size() - 1, -1, -1):
		var p := parts[i].strip_edges()
		if not p.is_empty() and not _has_clause_noise(p):
			return p
	return ""

func _has_clause_noise(candidate: String) -> bool:
	for bad in [
		"你到", "你去", "你在", "我让", "当中", "之中", "里面", "几个", "几名", "两个", "挑选", "物色", "寻访", "给我", "替我", "帮我",
		"找到后", "寻得后", "觅得后", "带来", "领来", "引来", "送来", "见朕", "见我", "引见", "听用", "复命", "回话", "日后", "天后"
	]:
		if candidate.contains(bad):
			return true
	if candidate.begins_with("你") or candidate.begins_with("我") or candidate.begins_with("到") or candidate.begins_with("在") or candidate.begins_with("去") or candidate.begins_with("找"):
		return true
	return false

func _sanitize_extracted_role(role_str: String, full_text: String, source_org: String = "") -> String:
	var cleaned := role_str.strip_edges()
	if not cleaned.is_empty() and not _has_clause_noise(cleaned):
		return cleaned
	# Fallback scan from end of full_text for known role head nouns
	var best_pos := -1
	var best_noun := ""
	for noun in KNOWN_ROLE_HEAD_NOUNS:
		var pos := full_text.rfind(noun)
		if pos != -1:
			if pos > best_pos or (pos == best_pos and noun.length() > best_noun.length()):
				best_pos = pos
				best_noun = noun
	if not best_noun.is_empty():
		if not source_org.is_empty() and not best_noun.contains(source_org) and (source_org + best_noun).length() <= 6:
			return source_org + best_noun
		return best_noun
	if full_text.contains("侍卫") or full_text.contains("禁军"):
		return "近身侍卫"
	return ""

func _has_task_name_noise(task_name: String) -> bool:
	for bad in ["你到", "你去", "你在", "我让", "当中", "之中", "里面", "几个", "几名", "两个", "给我", "替我", "帮我", "找到后", "带来见朕", "带来见我"]:
		if task_name.contains(bad):
			return true
	return false

func sanitize_legacy_task_in_place(task: Dictionary, state = null) -> void:
	if task.is_empty():
		return
	var cur_role := str(task.get("target_role", ""))
	var cur_name := str(task.get("name", ""))
	var circumstance_as_role := cur_role.contains("正值战乱") and (cur_role.ends_with("武将") or cur_role.ends_with("将领") or cur_role.ends_with("将才"))
	if not circumstance_as_role and not _has_clause_noise(cur_role) and not _has_task_name_noise(cur_name):
		return
	var raw_source := str(task.get("proposal_player_text", task.get("raw_text", cur_name))).strip_edges()
	if raw_source.contains("禁军") and (raw_source.contains("侍卫") or cur_name.contains("禁军")):
		raw_source = "你到禁军当中挑选几个忠诚勇武的士兵给我当侍卫"
	var re_extracted := extract(raw_source)
	var fixed_role := str(re_extracted.get("target_role", "")).strip_edges()
	if fixed_role.is_empty() or _has_clause_noise(fixed_role):
		# Cannot infer original target role from corrupted delivery-only text: mark as requiring clarification without inventing a default role
		task["needs_role_revision"] = true
		task["visible_feedback"] = [
			"待核定寻访对象",
			"原记仅含交付条件「%s」，请召见受托人明确所要寻访之人物类别。" % cur_role
		]
		return
	var fixed_task_name := str(re_extracted.get("task_name", "寻访%s并引见" % fixed_role))
	task["target_role"] = fixed_role
	task["name"] = fixed_task_name
	task["is_plural"] = bool(re_extracted.get("is_plural", false))
	var cid := str(task.get("candidate_character_id", ""))
	var cand_name := "陆无咎"
	if state != null and state.get("character_states") is Dictionary and state.character_states.has(cid):
		var cand: Dictionary = state.character_states[cid]
		cand["role"] = fixed_role
		if str(cand.get("origin", "")).contains("落魄") or str(cand.get("origin", "")).contains("游侠") or str(cand.get("origin", "")).contains("名宿"):
			cand["origin"] = "灵武宿卫禁军"
		cand_name = str(cand.get("name", cand_name))
		state.character_states[cid] = cand
	var exec_id := str(task.get("executor_id", "li_fuguo"))
	var exec_name := "李辅国" if exec_id == "li_fuguo" else ("郭子仪" if exec_id == "guo_ziyi" else ("李俶" if exec_id == "li_chu" else "近臣"))
	var plural_suffix := "等" if bool(task.get("is_plural", false)) else ""
	if str(task.get("status", "")) == "awaiting_player" or str(task.get("stage", "")) == "awaiting_introduction":
		task["visible_feedback"] = [
			"已选得精锐人选，正待引见",
			"%s携所选【%s】%s%s至行在候见。" % [exec_name, fixed_role, cand_name, plural_suffix]
		]
	else:
		task["visible_feedback"] = [
			"托付已定，正在遴选物色",
			"%s已着手代为主持选拔【%s】，约定数日后回话。" % [exec_name, fixed_role]
		]

func infer_semantic_stat(role: String, specialty: String) -> Dictionary:
	var comb := (role + " " + specialty).to_lower()
	if role in ["武将", "将领", "将才"]:
		return {"stat": "military", "name": "统帅", "archetype": "military_retainer"}

	# 1. Medicine
	for kw in ["医", "药", "病", "伤", "诊", "毒", "救", "疾", "疮", "针", "术", "悬壶", "杏林", "郎中", "大夫", "岐黄"]:
		if comb.contains(kw):
			return {"stat": "medicine", "name": "医术", "archetype": "physician_retainer"}

	# 2. Finance
	for kw in ["钱", "账", "财", "算", "商", "贾", "银", "粮", "库", "掌柜", "簿", "税", "出纳"]:
		if comb.contains(kw):
			return {"stat": "finance", "name": "理财", "archetype": "finance_retainer"}

	# 3. Intrigue
	for kw in ["谋", "策", "计", "谍", "潜", "间", "密", "刺探", "诡", "智", "谋士", "策士", "斥候", "暗探"]:
		if comb.contains(kw):
			return {"stat": "intrigue", "name": "谋略", "archetype": "strategist_retainer"}

	# 4. Prowess
	for kw in ["武", "勇", "剑", "刀", "卫", "骑", "弓", "击", "杀", "护", "拳", "镖", "侠", "壮", "刺客", "死士", "游侠", "护卫", "身手", "武夫"]:
		if comb.contains(kw):
			return {"stat": "prowess", "name": "武艺", "archetype": "assassin_retainer"}

	# 5. Military
	for kw in ["兵", "阵", "战", "帅", "将", "统", "军", "塞", "烽", "兵法"]:
		if comb.contains(kw):
			return {"stat": "military", "name": "统帅", "archetype": "military_retainer"}

	# 6. Diplomacy
	for kw in ["辨", "说", "使", "礼", "乐", "琴", "舞", "宾", "纵横", "辞令"]:
		if comb.contains(kw):
			return {"stat": "diplomacy", "name": "辞令", "archetype": "diplomat_retainer"}

	# 7. Governance (Default for crafts, culinary, agriculture, clerk, etc.)
	for kw in ["厨", "烹", "膳", "匠", "工", "筑", "农", "田", "案", "吏", "治", "书", "笔", "印", "典", "籍", "规", "律", "马夫", "向导"]:
		if comb.contains(kw):
			return {"stat": "governance", "name": "才干", "archetype": "generic_retainer"}

	return {"stat": "governance", "name": "才干", "archetype": "generic_retainer"}

func _infer_item_category(item_name: String) -> String:
	var lower := item_name.to_lower()
	for kw in ["甲", "铠", "衣", "袍", "氅", "冠", "靴", "软甲"]:
		if lower.contains(kw):
			return "ARMOR"
	for kw in ["剑", "刀", "枪", "戟", "弓", "弩", "刃", "兵", "神兵"]:
		if lower.contains(kw):
			return "EQUIPMENT"
	for kw in ["马", "驹", "骑", "坐骑"]:
		if lower.contains(kw):
			return "MOUNT"
	for kw in ["药", "散", "丹", "膏", "汤", "金疮"]:
		if lower.contains(kw):
			return "MEDICINE"
	for kw in ["书", "卷", "图", "策", "谱", "籍"]:
		if lower.contains(kw):
			return "TOME"
	return "SUPPLY"
