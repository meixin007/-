extends RefCounted

class_name Beta108CaseCatalog

const OfficeCatalogScript = preload("res://scripts/domain/beta_1_08_office_catalog.gd")

const CASE_IDS := [
	"beta108_case_grain_ledger_shortfall",
	"beta108_case_military_grain_delay",
	"beta108_case_palace_order_leak",
	"beta108_case_edict_legitimacy",
	"beta108_case_uighur_aid_cost",
	"beta108_case_final_assessment"
]

const TEMPLATE_IDS := [
	"grain_ledger_shortfall",
	"military_grain_delay",
	"palace_order_leak",
	"edict_legitimacy",
	"uighur_aid_cost",
	"final_assessment"
]

static func ids() -> Array:
	return CASE_IDS.duplicate()

static func template_ids() -> Array:
	return TEMPLATE_IDS.duplicate()

static func build_dormant_cases() -> Dictionary:
	var cases: Dictionary = {}
	var skeletons := [
		[CASE_IDS[0], TEMPLATE_IDS[0], ["grain_official_lingwu", "lingwu_merchant_refugee", "li_bi", "li_fuguo"], ["household_supply", "shangshu_execution"]],
		[CASE_IDS[1], TEMPLATE_IDS[1], ["guo_ziyi", "li_guangbi", "pugu_huaien", "regional_jiedushi_rep"], ["war_mobilization", "shangshu_execution"]],
		[CASE_IDS[2], TEMPLATE_IDS[2], ["li_fuguo", "eunuch_deputy_gate", "li_chu", "hardline_old_court_official"], ["inner_court_gatekeeper", "censorate"]],
		[CASE_IDS[3], TEMPLATE_IDS[3], ["li_bi", "li_chu", "hardline_old_court_official", "li_fuguo"], ["zhongshu_drafting", "menxia_review"]],
		[CASE_IDS[4], TEMPLATE_IDS[4], ["uighur_envoy", "pugu_huaien", "li_bi", "li_guangbi", "regional_jiedushi_rep"], ["envoy_negotiator", "war_mobilization"]],
		[CASE_IDS[5], TEMPLATE_IDS[5], ["guo_ziyi", "li_bi", "li_fuguo", "li_guangbi", "pugu_huaien", "li_chu", "uighur_envoy", "hardline_old_court_official", "grain_official_lingwu", "lingwu_merchant_refugee", "regional_jiedushi_rep", "eunuch_deputy_gate"], OfficeCatalogScript.ids()]
	]
	for skeleton in skeletons:
		var case_id := str(skeleton[0])
		cases[case_id] = {
			"case_id": case_id,
			"template_id": str(skeleton[1]),
			"lifecycle": "dormant",
			"subject_ids": (skeleton[2] as Array).duplicate(),
			"office_ids": (skeleton[3] as Array).duplicate(),
			"term_ids": [],
			"causal_refs": [],
			"facts": [],
			"claims": [],
			"evidence": [],
			"decision": {},
			"decision_transaction_id": "",
			"opened_day": 0,
			"decided_day": 0,
			"closed_day": 0
		}
	return cases
