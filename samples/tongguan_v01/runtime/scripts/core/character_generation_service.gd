extends RefCounted

class_name CharacterGenerationService

const SURNAMES: Array[String] = [
	"燕", "柳", "陆", "封", "荆", "裴", "白", "聂", "凌", "顾",
	"楚", "冷", "卫", "霍", "司马", "独孤", "尉迟", "公孙"
]

const GIVEN_NAMES: Array[String] = [
	"承武", "千仞", "绝影", "青锋", "守拙", "玄策", "怀瑾", "无咎",
	"凌云", "归藏", "惊鸿", "残照", "逐风", "藏锋", "霜刃", "长风"
]

const ORIGINS: Array[String] = [
	"关中游侠", "朔方侦骑", "河东剑客", "蜀地隐者", "西域商旅近卫", "坊市落魄异人", "前边军前锋卒"
]

const BACKGROUNDS: Array[String] = [
	"少时学剑于边塞，性孤傲，身法如电，曾随商队往来于萧关塞外，精于近战搏击与潜行匿迹。",
	"曾为州府巡捕，因触怒豪强弃职流落江湖，沉稳冷静，机警敏锐，熟谙暗行追击之法。",
	"关中豪侠遗民，少言寡语，行止沉稳，刀法狠辣果决，常于险地独来独往，极重信诺。",
	"原为边军斥候，精熟地形探查与短刃袭杀，身手矫捷，察觉险兆先于常人，历经百战而存。"
]

const ASSASSIN_TRAIT_CANDIDATES: Array[String] = [
	"果断", "沉稳", "机敏", "刚毅", "冷峻", "忠勇", "好义", "自重"
]

const PHYSICIAN_GIVEN_NAMES: Array[String] = [
	"思邈", "怀民", "仁济", "知微", "守素", "景澄", "安道", "元礼",
	"伯玉", "存义", "济生", "文通", "守常", "和甫", "德润", "玄明"
]

const PHYSICIAN_ORIGINS: Array[String] = [
	"两京太医署旧医", "关中悬壶药肆", "终南山采药隐士", "陇右军旅行医名宿", "河东伤科草泽名医", "岐黄世家遗贤"
]

const PHYSICIAN_BACKGROUNDS: Array[String] = [
	"少通本草脉理，曾随师行医于陇西塞上，精通金疮敷裹与温热诸症，治病审慎仁和，深得军民信重。",
	"曾充两京太医署医工，丧乱播迁流落关陇，精于汤液针砭之术，察脉断症分毫不爽，立志悬壶济困。",
	"终南隐士高足，熟谙百草奇方与行军瘴疠解毒，性情温润宁和，不求富贵闻达，愿以医道活人。",
	"家传世代行医，擅调治内伤虚损与金石汤散，随逃难流民流转至灵武，悬壶济世，声名流布关中。"
]

const PHYSICIAN_TRAITS: Array[String] = [
	"仁心", "审慎", "精细", "慈悲", "温厚", "敏悟", "自重", "清心"
]

const GUARD_ORIGINS: Array[String] = [
	"灵武宿卫禁军", "朔方随驾精锐", "六军宿卫行伍", "北衙禁军百骑", "飞龙禁军旧部"
]

const GUARD_BACKGROUNDS: Array[String] = [
	"原为随驾北上之禁军宿卫精卒，弓马娴熟，悍勇绝伦，历经战阵而忠谨不渝，经统领遴选拔擢以充近侍。",
	"出身朔方良家子，入禁军宿卫多年，披坚执锐，治军严整，性情忠直刚毅，熟谙行在宿卫戒备之法。",
	"六军精锐甲士，力能挽强，精于长兵格斗与贴身护卫，素以忠勇勤勉闻于营伍，特选入值宿卫。"
]

const GenericEntrustmentSlotExtractorScript = preload("res://scripts/ai/generic_entrustment_slot_extractor.gd")

func generate_character(archetype_id: String, tier: String, rule_seed: int, context: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rule_seed
	
	var target_role := str(context.get("target_role", "")).strip_edges()
	var source_org := str(context.get("source_org", "")).strip_edges()
	var specialties := str(context.get("specialties", context.get("specialty", ""))).strip_edges()
	var dominant_stat := str(context.get("dominant_ability", context.get("semantic_stat", ""))).strip_edges()

	if target_role.is_empty() or target_role in ["郎中", "医术郎中"]:
		if archetype_id in ["physician_retainer", "physician"] or target_role in ["郎中", "医术郎中"]:
			target_role = "悬壶郎中"
		elif archetype_id in ["strategist_retainer", "strategist"]:
			target_role = "随行谋士"
		elif archetype_id in ["finance_retainer", "finance"]:
			target_role = "算学账房"
		else:
			target_role = "武勇门客"

	if dominant_stat.is_empty():
		if archetype_id in ["physician_retainer", "physician"]:
			dominant_stat = "medicine"
		elif archetype_id in ["strategist_retainer", "strategist"]:
			dominant_stat = "intrigue"
		elif archetype_id in ["finance_retainer", "finance"]:
			dominant_stat = "finance"
		else:
			var slot_ext = GenericEntrustmentSlotExtractorScript.new()
			dominant_stat = str(slot_ext.infer_semantic_stat(target_role, specialties).get("stat", "governance"))

	var is_physician := dominant_stat == "medicine" or target_role.contains("郎中") or target_role.contains("医")
	var is_guard := target_role.contains("侍卫") or target_role.contains("禁军") or target_role.contains("亲卫") or target_role.contains("近卫") or target_role.contains("卫士") or source_org.contains("禁军")
	var role_name := target_role
	var surname := SURNAMES[rng.randi() % SURNAMES.size()]
	var given_name := PHYSICIAN_GIVEN_NAMES[rng.randi() % PHYSICIAN_GIVEN_NAMES.size()] if is_physician else GIVEN_NAMES[rng.randi() % GIVEN_NAMES.size()]
	var full_name := surname + given_name
	
	var day := int(context.get("current_day", 1))
	var executor_id := str(context.get("executor_id", "guo_ziyi"))
	var char_id := "dyn_char__%s__%d__%d" % [archetype_id, day, abs(rule_seed) % 100000]
	
	var origin := "关中名宿"
	if is_physician:
		origin = PHYSICIAN_ORIGINS[rng.randi() % PHYSICIAN_ORIGINS.size()]
	elif is_guard:
		origin = GUARD_ORIGINS[rng.randi() % GUARD_ORIGINS.size()]
	elif dominant_stat == "prowess":
		origin = ORIGINS[rng.randi() % ORIGINS.size()]
	else:
		var place_pool := ["关中", "河东", "陇右", "蜀中", "两京", "朔方"]
		origin = "%s%s" % [place_pool[rng.randi() % place_pool.size()], target_role]

	var background := ""
	if is_physician:
		background = PHYSICIAN_BACKGROUNDS[rng.randi() % PHYSICIAN_BACKGROUNDS.size()]
	elif is_guard:
		background = GUARD_BACKGROUNDS[rng.randi() % GUARD_BACKGROUNDS.size()]
	elif dominant_stat == "prowess":
		background = BACKGROUNDS[rng.randi() % BACKGROUNDS.size()]
	else:
		background = "曾随流民与商旅寓居关陇，身怀【%s】之长，行事练达沉稳，深明大体，经引荐以备差遣。" % (target_role if specialties.is_empty() else (specialties + "的" + target_role))
	
	# Key attributes calculation
	# common: 35–54, good: 55–69, outstanding: 70–84, rare: 85–94
	var military := rng.randi_range(15, 45)
	var governance := rng.randi_range(20, 50)
	var finance := rng.randi_range(20, 50)
	var intrigue := rng.randi_range(20, 50)
	var diplomacy := rng.randi_range(20, 50)
	var prowess := rng.randi_range(20, 50)
	var medicine := rng.randi_range(15, 45)

	var dom_val := 0
	match tier:
		"rare":
			dom_val = rng.randi_range(85, 94)
		"outstanding":
			dom_val = rng.randi_range(70, 84)
		"good":
			dom_val = rng.randi_range(55, 69)
		_:
			dom_val = rng.randi_range(35, 54)

	match dominant_stat:
		"medicine":
			medicine = dom_val
		"finance":
			finance = dom_val
		"intrigue":
			intrigue = dom_val
		"prowess":
			prowess = dom_val
		"military":
			military = dom_val
		"diplomacy":
			diplomacy = dom_val
		"governance", _:
			governance = dom_val
			dominant_stat = "governance"

	var stats := {
		"military": military,
		"governance": governance,
		"finance": finance,
		"intrigue": intrigue,
		"diplomacy": diplomacy,
		"prowess": prowess
	}
	if dominant_stat == "medicine" or is_physician:
		stats["medicine"] = medicine

	# Select 2 distinct traits
	var traits: Array[String] = []
	var pool: Array = (PHYSICIAN_TRAITS if is_physician else ASSASSIN_TRAIT_CANDIDATES).duplicate()
	for i in range(2):
		if pool.is_empty():
			break
		var idx := rng.randi() % pool.size()
		traits.append(str(pool[idx]))
		pool.remove_at(idx)
		
	var public_goals: Array = ["行医济世以全仁道", "在行在设立军医药肆", "随侍明主以全岐黄之志"] if is_physician else ["寻明主立身效命", "以平生所学求取安身之地", "求功名以脱草莽"]
	var hidden_goals: Array = ["收集天下罕见本草医案", "避兵祸求立安民医馆", "著书立说传续医道"] if is_physician else ["求财以赡家室", "避祸安身", "待机扬名立万"]
	
	var public_goal: String = public_goals[rng.randi() % public_goals.size()]
	var hidden_goal: String = hidden_goals[rng.randi() % hidden_goals.size()]
	
	var char_record := {
		"id": char_id,
		"name": full_name,
		"is_dynamic": true,
		"archetype_id": archetype_id,
		"role": role_name,
		"dominant_ability": dominant_stat,
		"status": "available",
		"stats": stats,
		"tang_traits": traits,
		"background": background,
		"origin": origin,
		"introduced_by": executor_id,
		"public_goal": public_goal,
		"hidden_goal": hidden_goal,
		"summonable": false,
		"relationships": {
			"li_heng": 0,
			executor_id: 15
		},
		"memory_summary": [
			"经%s引荐，初至行在。" % executor_id
		],
		"allegiance": {
			"target_id": "",
			"kind": "unaligned",
			"day": day
		}
	}
	
	# Explicit generation defaults; do not infer the art family from a name/role.
	# Independent stable DNA sampling leaves the existing gameplay RNG unchanged.
	var appearance: Dictionary = preload("res://scripts/core/character_appearance_contract.gd").founder(char_id,str(context.get("portrait_family","male")),int(context.get("display_age_years",35))*365,day,"generated-appearance-1|"+str(rule_seed)+"|"+char_id)
	if not appearance.ok: return {}
	char_record["appearance"] = appearance.appearance
	return char_record
