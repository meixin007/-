extends RefCounted

class_name CurrentCampaign

const CAMPAIGN_ID := "anshi_beta_1_14"
const MANIFEST_PATH := "res://data/scenarios/anshi_rebellion/campaign_beta_1_14.json"
const DISPLAY_VERSION := "Beta 1.14 经营、职位与助手"
const PROJECT_VERSION := "1.14.0-beta"
const SAVE_VERSION := 22
const SAVE_ROOT := "user://saves/anshi_beta_1_14"
const EXPORT_PRESET := "Beta 1.14 Windows x86_64"

static func descriptor() -> Dictionary:
	return {
		"campaign_id": CAMPAIGN_ID,
		"manifest_path": MANIFEST_PATH,
		"display_version": DISPLAY_VERSION,
		"project_version": PROJECT_VERSION,
		"save_version": SAVE_VERSION,
		"save_root": SAVE_ROOT,
		"export_preset": EXPORT_PRESET
	}
