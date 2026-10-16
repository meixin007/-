extends RefCounted
## Local display preference; never part of a campaign save or rule state.
const DEFAULT_PATH := "user://workshop_map_display.cfg"
const GAME_MAP_PATH := "res://data/maps/current_workshop.map.json"
const SAMPLE_PATH := "res://addons/strategic_map_editor/art/tongguan_reference_20260925/tongguan-grounded.map.json"
const REGION_ID := "tongguan"
var path: String
func _init(config_path: String = DEFAULT_PATH) -> void: path = config_path
func read() -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"enabled":true,"map_path":GAME_MAP_PATH,"region_id":"","message":""}
	var config := ConfigFile.new()
	if config.load(path) != OK: return {"ok":false,"enabled":false,"message":"地图显示设置无法读取，已保留原地图。"}
	var version: Variant = config.get_value("workshop_map","version",null)
	var enabled: Variant = config.get_value("workshop_map","enabled",null)
	if version not in [1,2] or not enabled is bool:
		return {"ok":false,"enabled":false,"message":"地图显示设置格式无效，已保留原地图。"}
	if version == 1: return {"ok":true,"enabled":enabled,"map_path":SAMPLE_PATH,"region_id":REGION_ID,"message":""}
	var map_path: Variant = config.get_value("workshop_map","map_path",null)
	var region_id: Variant = config.get_value("workshop_map","region_id",null)
	if not map_path is String or map_path.is_empty() or not region_id is String:
		return {"ok":false,"enabled":false,"message":"地图显示设置格式无效，已保留原地图。"}
	return {"ok":true,"enabled":enabled,"map_path":map_path,"region_id":region_id,"message":""}
func write(enabled: bool, map_path: String = "", region_id: String = "") -> String:
	if map_path.is_empty():
		var previous := read()
		map_path = previous.get("map_path",GAME_MAP_PATH)
		region_id = previous.get("region_id","")
	var config := ConfigFile.new()
	config.set_value("workshop_map","version",2)
	config.set_value("workshop_map","enabled",enabled)
	config.set_value("workshop_map","map_path",map_path)
	config.set_value("workshop_map","region_id",region_id)
	return "" if config.save(path) == OK else "本次显示已切换，但无法保存偏好；下次启动不会记住这次选择。"
