extends RefCounted

class_name Beta108OfficeCatalog

const OFFICE_IDS := [
	"zhongshu_drafting",
	"menxia_review",
	"shangshu_execution",
	"household_supply",
	"war_mobilization",
	"censorate",
	"inner_court_gatekeeper",
	"envoy_negotiator"
]

const OFFICE_ALIASES := {
	"grain_office": "household_supply",
	"inner_court_office": "inner_court_gatekeeper"
}

const INITIAL_PRIORITY := [
	"zhongshu_drafting",
	"shangshu_execution",
	"household_supply",
	"war_mobilization",
	"inner_court_gatekeeper",
	"menxia_review",
	"censorate",
	"envoy_negotiator"
]

static func ids() -> Array:
	return OFFICE_IDS.duplicate()

static func is_core_office(office_id: String) -> bool:
	return OFFICE_IDS.has(office_id)

static func canonical_id(office_id: String) -> String:
	return str(OFFICE_ALIASES.get(office_id, office_id))

static func build_vacant_runtime_record(office_id: String, reason: String = "initial_overlay") -> Dictionary:
	return {
		"office_id": office_id,
		"holder_id": "",
		"status": "vacant",
		"runtime_kind": "core",
		"vacancy_reason": reason
	}

static func build_initial_overlay() -> Array:
	return [
		{"office_id": "zhongshu_drafting", "holder_id": "li_bi", "status": "appointed"},
		build_vacant_runtime_record("menxia_review"),
		{"office_id": "shangshu_execution", "holder_id": "li_chu", "status": "appointed"},
		{"office_id": "household_supply", "holder_id": "grain_official_lingwu", "status": "appointed"},
		{"office_id": "war_mobilization", "holder_id": "guo_ziyi", "status": "appointed"},
		build_vacant_runtime_record("censorate"),
		{"office_id": "inner_court_gatekeeper", "holder_id": "li_fuguo", "status": "appointed"},
		build_vacant_runtime_record("envoy_negotiator")
	]
