extends RefCounted

class_name TangOfficeCatalog

const CATALOG_PATH := "res://data/scenarios/anshi_rebellion/offices_catalog.json"

const CORE_24_OFFICE_IDS := [
	"zhongshu_ling",
	"menxia_shizhong",
	"tong_pingzhangshi",
	"libu_shangshu",
	"hubu_shangshu",
	"libu_rites_shangshu",
	"bingbu_shangshu",
	"xingbu_shangshu",
	"gongbu_shangshu",
	"yushi_zhongcheng",
	"zuo_shiyi",
	"you_shiyi",
	"zuo_buque",
	"you_buque",
	"hanlin_xueshi",
	"inner_court_gatekeeper",
	"duzhi_shi",
	"yantie_zhuanyun_shi",
	"liangliao_shi",
	"xuanwei_zhaotao_shi",
	"shuofang_jiedushi",
	"hedong_jiedushi",
	"jiannan_jiedushi",
	"henan_jiedu_fushi",
	"xingjun_sima"
]

const LEGACY_ALIASES := {
	"zhongshu_drafting": "zhongshu_ling",
	"menxia_review": "menxia_shizhong",
	"shangshu_execution": "tong_pingzhangshi",
	"household_supply": "hubu_shangshu",
	"grain_office": "hubu_shangshu",
	"personnel_affairs": "libu_shangshu",
	"rites_affairs": "libu_rites_shangshu",
	"envoy_negotiator": "libu_rites_shangshu",
	"war_mobilization": "bingbu_shangshu",
	"justice_affairs": "xingbu_shangshu",
	"works_affairs": "gongbu_shangshu",
	"censorate": "yushi_zhongcheng",
	"inner_court_office": "inner_court_gatekeeper",
	"palace_household_controller": "inner_court_gatekeeper",
	"grain_transport_supervisor": "liangliao_shi",
	"shuofang_field_commander": "shuofang_jiedushi",
	"local_node_administrator": "xingjun_sima",
	"court_memorial_reviewer": "hanlin_xueshi",
	"intelligence_coordinator": "hanlin_xueshi"
}

static var _cached_catalog: Dictionary = {}
static var _cached_offices_map: Dictionary = {}
static var _cached_branches: Array = []

static func _ensure_catalog_loaded() -> void:
	if not _cached_offices_map.is_empty():
		return
	if FileAccess.file_exists(CATALOG_PATH):
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_cached_catalog = parsed
				_cached_branches = parsed.get("branches", [])
				for raw_office in parsed.get("offices", []):
					if raw_office is Dictionary and raw_office.has("id"):
						_cached_offices_map[str(raw_office.get("id"))] = raw_office

static func get_all_office_ids() -> Array:
	_ensure_catalog_loaded()
	if not _cached_offices_map.is_empty():
		return _cached_offices_map.keys()
	return CORE_24_OFFICE_IDS.duplicate()

static func get_all_offices() -> Array[Dictionary]:
	_ensure_catalog_loaded()
	var list: Array[Dictionary] = []
	for office in _cached_offices_map.values():
		list.append((office as Dictionary).duplicate(true))
	return list

static func get_all_branches() -> Array:
	_ensure_catalog_loaded()
	return _cached_branches.duplicate(true)

const FALLBACK_OFFICE_NAMES: Dictionary = {
	"zhongshu_ling": "中书令",
	"menxia_shizhong": "侍中",
	"tong_pingzhangshi": "同中书门下平章事",
	"libu_shangshu": "吏部尚书",
	"hubu_shangshu": "户部尚书",
	"libu_rites_shangshu": "礼部尚书",
	"bingbu_shangshu": "兵部尚书",
	"xingbu_shangshu": "刑部尚书",
	"gongbu_shangshu": "工部尚书",
	"yushi_zhongcheng": "御史中丞",
	"zuo_shiyi": "左拾遗",
	"you_shiyi": "右拾遗",
	"zuo_buque": "左补阙",
	"you_buque": "右补阙",
	"hanlin_xueshi": "翰林学士",
	"inner_court_gatekeeper": "内廷宫门使",
	"duzhi_shi": "度支使",
	"yantie_zhuanyun_shi": "盐铁转运使",
	"liangliao_shi": "粮料使",
	"xuanwei_zhaotao_shi": "宣慰招讨使",
	"shuofang_jiedushi": "朔方节度使",
	"hedong_jiedushi": "河东节度使",
	"jiannan_jiedushi": "剑南节度使",
	"henan_jiedu_fushi": "河南节度副使",
	"xingjun_sima": "行军司马"
}

static func get_office_definition(office_id: String) -> Dictionary:
	_ensure_catalog_loaded()
	var canonical := canonical_id(office_id)
	if _cached_offices_map.has(canonical):
		return (_cached_offices_map[canonical] as Dictionary).duplicate(true)
	if _cached_offices_map.has(office_id):
		return (_cached_offices_map[office_id] as Dictionary).duplicate(true)
	return {}

static func get_office_name(office_id: String) -> String:
	_ensure_catalog_loaded()
	var canonical := canonical_id(office_id)
	var def := get_office_definition(canonical)
	if not def.is_empty() and def.has("name"):
		var name_str := str(def.get("name", "")).strip_edges()
		if not name_str.is_empty():
			return name_str
	if FALLBACK_OFFICE_NAMES.has(canonical):
		return str(FALLBACK_OFFICE_NAMES[canonical])
	if FALLBACK_OFFICE_NAMES.has(office_id):
		return str(FALLBACK_OFFICE_NAMES[office_id])
	return office_id

static func is_valid_office(office_id: String) -> bool:
	_ensure_catalog_loaded()
	var canonical := canonical_id(office_id)
	return _cached_offices_map.has(canonical) or _cached_offices_map.has(office_id) or CORE_24_OFFICE_IDS.has(canonical)

static func is_core_office(office_id: String) -> bool:
	var def := get_office_definition(office_id)
	if not def.is_empty():
		return bool(def.get("is_core_cabinet", false))
	return true

static func canonical_id(office_id: String) -> String:
	return str(LEGACY_ALIASES.get(office_id, office_id))

static func get_legacy_aliases_for(canonical_id: String) -> Array[String]:
	var result: Array[String] = []
	for legacy_id in LEGACY_ALIASES.keys():
		if LEGACY_ALIASES[legacy_id] == canonical_id:
			result.append(legacy_id)
	return result

static func build_vacant_runtime_record(office_id: String, reason: String = "initial_overlay") -> Dictionary:
	var def := get_office_definition(office_id)
	var rank := str(def.get("rank", "从五品"))
	var branch := str(def.get("branch", "central_executive"))
	var name := str(def.get("name", office_id))
	return {
		"office_id": office_id,
		"holder_id": "",
		"status": "vacant",
		"rank": rank,
		"branch": branch,
		"name": name,
		"runtime_kind": "core" if is_core_office(office_id) else "supplemental",
		"vacancy_reason": reason,
		"appointment": {"player_may_appoint_if_vacant": true}
	}

static func build_initial_24_overlay() -> Array:
	return [
		{"office_id": "zhongshu_ling", "holder_id": "", "status": "vacant"},
		{"office_id": "menxia_shizhong", "holder_id": "", "status": "vacant"},
		{"office_id": "tong_pingzhangshi", "holder_id": "li_chu", "status": "appointed"},
		{"office_id": "libu_shangshu", "holder_id": "", "status": "vacant"},
		{"office_id": "hubu_shangshu", "holder_id": "grain_official_lingwu", "status": "appointed"},
		{"office_id": "libu_rites_shangshu", "holder_id": "", "status": "vacant"},
		{"office_id": "bingbu_shangshu", "holder_id": "guo_ziyi", "status": "appointed"},
		{"office_id": "xingbu_shangshu", "holder_id": "", "status": "vacant"},
		{"office_id": "gongbu_shangshu", "holder_id": "", "status": "vacant"},
		{"office_id": "yushi_zhongcheng", "holder_id": "", "status": "vacant"},
		{"office_id": "zuo_shiyi", "holder_id": "", "status": "vacant"},
		{"office_id": "you_shiyi", "holder_id": "", "status": "vacant"},
		{"office_id": "zuo_buque", "holder_id": "", "status": "vacant"},
		{"office_id": "you_buque", "holder_id": "", "status": "vacant"},
		{"office_id": "hanlin_xueshi", "holder_id": "li_bi", "status": "appointed"},
		{"office_id": "inner_court_gatekeeper", "holder_id": "li_fuguo", "status": "appointed"},
		{"office_id": "duzhi_shi", "holder_id": "", "status": "vacant"},
		{"office_id": "yantie_zhuanyun_shi", "holder_id": "", "status": "vacant"},
		{"office_id": "liangliao_shi", "holder_id": "grain_official_lingwu", "status": "appointed"},
		{"office_id": "xuanwei_zhaotao_shi", "holder_id": "", "status": "vacant"},
		{"office_id": "shuofang_jiedushi", "holder_id": "guo_ziyi", "status": "appointed"},
		{"office_id": "hedong_jiedushi", "holder_id": "", "status": "vacant"},
		{"office_id": "jiannan_jiedushi", "holder_id": "", "status": "vacant"},
		{"office_id": "henan_jiedu_fushi", "holder_id": "", "status": "vacant"},
		{"office_id": "xingjun_sima", "holder_id": "", "status": "vacant"}
	]
