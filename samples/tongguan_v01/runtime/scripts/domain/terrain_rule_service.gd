extends RefCounted

class_name TerrainRuleService

const TERRAIN_CONFIGS: Dictionary = {
	"plains": {
		"name_loc": "平原沃野",
		"defense": 0.0,
		"defense_bonus": 0.0,
		"defense_percent": 0,
		"cavalry": 0.35,
		"cavalry_modifier": 0.35,
		"speed": 1.0,
		"march_speed_mult": 1.0,
		"supply": 1.0,
		"supply_loss": 1.0,
		"supply_attrition_mult": 1.0,
		"historical_typical": "华北平原、河南道、关中盆地"
	},
	"mountains": {
		"name_loc": "险峰峻岭",
		"defense": 0.60,
		"defense_bonus": 0.60,
		"defense_percent": 60,
		"cavalry": -0.50,
		"cavalry_modifier": -0.50,
		"speed": 0.40,
		"march_speed_mult": 0.40,
		"supply": 1.80,
		"supply_loss": 1.80,
		"supply_attrition_mult": 1.80,
		"historical_typical": "秦岭、太行八陉、陇山、剑阁"
	},
	"hills": {
		"name_loc": "丘陵漫岗",
		"defense": 0.25,
		"defense_bonus": 0.25,
		"defense_percent": 25,
		"cavalry": -0.10,
		"cavalry_modifier": -0.10,
		"speed": 0.75,
		"march_speed_mult": 0.75,
		"supply": 1.20,
		"supply_loss": 1.20,
		"supply_attrition_mult": 1.20,
		"historical_typical": "河东丘陵、江南茶山、山东丘陵"
	},
	"marsh_waterway": {
		"name_loc": "水网湿地",
		"defense": 0.15,
		"defense_bonus": 0.15,
		"defense_percent": 15,
		"cavalry": -0.40,
		"cavalry_modifier": -0.40,
		"speed": 0.35,
		"march_speed_mult": 0.35,
		"supply": 2.00,
		"supply_loss": 2.00,
		"supply_attrition_mult": 2.00,
		"historical_typical": "淮南水乡、洞庭鄱阳、太湖流域"
	},
	"marsh": {
		"name_loc": "水网湿地",
		"defense": 0.15,
		"defense_bonus": 0.15,
		"defense_percent": 15,
		"cavalry": -0.40,
		"cavalry_modifier": -0.40,
		"speed": 0.35,
		"march_speed_mult": 0.35,
		"supply": 2.00,
		"supply_loss": 2.00,
		"supply_attrition_mult": 2.00,
		"historical_typical": "淮南水乡、洞庭鄱阳、太湖流域"
	},
	"plateau_alpine": {
		"name_loc": "高寒高原",
		"defense": 0.40,
		"defense_bonus": 0.40,
		"defense_percent": 40,
		"cavalry": -0.30,
		"cavalry_modifier": -0.30,
		"cavalry_native": 0.0,
		"speed": 0.50,
		"march_speed_mult": 0.50,
		"supply": 2.20,
		"supply_loss": 2.20,
		"supply_attrition_mult": 2.20,
		"historical_typical": "青藏高原、日月山、吐蕃腹地"
	},
	"desert_gobi": {
		"name_loc": "戈壁瀚海",
		"defense": -0.10,
		"defense_bonus": -0.10,
		"defense_percent": -10,
		"cavalry": 0.0,
		"cavalry_modifier": 0.0,
		"requires_oasis": true,
		"speed": 0.60,
		"march_speed_mult": 0.60,
		"supply": 2.50,
		"supply_loss": 2.50,
		"supply_attrition_mult": 2.50,
		"historical_typical": "河西走廊边缘、塔克拉玛干、莫贺延碛"
	},
	"forest_valley": {
		"name_loc": "林莽峡谷",
		"defense": 0.35,
		"defense_bonus": 0.35,
		"defense_percent": 35,
		"cavalry": -0.30,
		"cavalry_modifier": -0.30,
		"speed": 0.55,
		"march_speed_mult": 0.55,
		"supply": 1.40,
		"supply_loss": 1.40,
		"supply_attrition_mult": 1.40,
		"historical_typical": "秦巴山区、伏牛山麓、五岭山林"
	},
	"ocean_inlandsea": {
		"name_loc": "江海水域",
		"defense": 0.0,
		"defense_bonus": 0.0,
		"defense_percent": 0,
		"cavalry": 0.0,
		"cavalry_modifier": 0.0,
		"attack_penalty": -0.40,
		"ferry_requires_navy": true,
		"speed": 2.00,
		"march_speed_mult": 2.00,
		"supply": 0.10,
		"supply_loss": 0.10,
		"supply_attrition_mult": 0.10,
		"historical_typical": "大运河主干、长江、黄河天堑"
	}
}

const WEATHER_MODIFIERS: Dictionary = {
	"drought": {
		"name_loc": "旱灾",
		"agriculture": -0.10,
		"supply": 0.15,
		"combat": {"fire_attack_vulnerable": true}
	},
	"flood_autumn": {
		"name_loc": "洪涝/秋霖",
		"agriculture": -0.08,
		"movement": -0.25,
		"caoyun_risk": 0.8,
		"combat": {"bow_dampened": true, "fire_attack_disabled": true}
	},
	"locust_swarm": {
		"name_loc": "蝗灾",
		"agriculture": -0.25,
		"supply": 0.10
	},
	"frost_winter": {
		"name_loc": "霜冻/寒冬",
		"agriculture": -0.15,
		"movement_hebei_mobei": -0.20,
		"frostbite_attrition_up": true,
		"morale": -0.10
	},
	"plague": {
		"name_loc": "瘟疫",
		"garrison_casualty_weekly": 0.03,
		"corvee_casualty_up": true,
		"morale_hit": true
	},
	"wildfire": {
		"name_loc": "野火",
		"agriculture": -0.05,
		"relay_road_interrupted": true,
		"combat": {"arson_available": true}
	},
	"hailstone": {
		"name_loc": "冰雹",
		"agriculture": -0.15
	},
	"earthquake": {
		"name_loc": "地震",
		"infrastructure_damaged": true
	},
	"river_burst": {
		"name_loc": "水患河决",
		"agriculture": -0.10,
		"caoyun_disconnected": true,
		"camp_setup_difficult": true
	},
	"fair_weather": {
		"name_loc": "风调雨顺",
		"agriculture": 0.12,
		"supply": -0.05
	},
	"sunny": {
		"name_loc": "日照和煦",
		"agriculture": 0.08
	},
	"flower_wind": {
		"name_loc": "花信风",
		"sericulture_cotton": 0.10,
		"agriculture": 0.05
	},
	"sea_storm": {
		"name_loc": "海上风暴",
		"sea_loss": 0.20,
		"naval_combat": -0.25
	},
	"sea_fog": {
		"name_loc": "海雾",
		"sea_speed": -0.30,
		"naval_concealment": true
	},
	"sea_ice": {
		"name_loc": "冰封",
		"sea_route_blocked": true
	},
	"sea_swell": {
		"name_loc": "惊涛",
		"sea_loss": 0.10,
		"sea_speed": -0.15
	},
	"sea_tide": {
		"name_loc": "潮汐",
		"sea_speed": 0.10
	}
}

const RIVER_CROSSING_ATTACK_PENALTY: float = -0.40
const GRAND_CANAL_SPEED_MULT: float = 2.0
const GRAND_CANAL_LOGISTICS_LOSS_MULT: float = 0.1


func get_terrain(type_key: String) -> Dictionary:
	return TERRAIN_CONFIGS.get(type_key, TERRAIN_CONFIGS["plains"])


func combine_multi(terrain_mult: float, weather_mult: float) -> float:
	return terrain_mult * weather_mult


static func get_terrain_data(type_key: String) -> Dictionary:
	return TERRAIN_CONFIGS.get(type_key, TERRAIN_CONFIGS["plains"])


static func get_terrain_config(terrain_type: String) -> Dictionary:
	return TERRAIN_CONFIGS.get(terrain_type, TERRAIN_CONFIGS["plains"])


static func get_terrain_defense_modifier(terrain_type: String) -> float:
	var cfg: Dictionary = get_terrain_config(terrain_type)
	return float(cfg.get("defense_bonus", 0.0))


static func get_cavalry_combat_modifier(terrain_type: String, is_native_adapted: bool = false) -> float:
	if terrain_type == "plateau_alpine" and is_native_adapted:
		return 0.0
	var cfg: Dictionary = get_terrain_config(terrain_type)
	return float(cfg.get("cavalry_modifier", 0.0))


static func get_march_speed_multiplier(terrain_type: String, is_grand_canal: bool = false) -> float:
	if is_grand_canal:
		return GRAND_CANAL_SPEED_MULT
	var cfg: Dictionary = get_terrain_config(terrain_type)
	return float(cfg.get("march_speed_mult", 1.0))


static func get_supply_attrition_multiplier(terrain_type: String, is_grand_canal: bool = false) -> float:
	if is_grand_canal:
		return GRAND_CANAL_LOGISTICS_LOSS_MULT
	var cfg: Dictionary = get_terrain_config(terrain_type)
	return float(cfg.get("supply_attrition_mult", 1.0))


static func get_river_crossing_attack_penalty(river_type: Variant) -> float:
	if river_type == null or str(river_type).is_empty():
		return 0.0
	return RIVER_CROSSING_ATTACK_PENALTY


static func get_weather_modifier(weather_id: String) -> Dictionary:
	return WEATHER_MODIFIERS.get(weather_id, {})


static func calculate_combat_terrain_factors(
	terrain_type: String,
	is_cross_river: bool = false,
	is_defender_in_pass: bool = false,
	is_attacker_cavalry: bool = false,
	is_attacker_native_adapted: bool = false
) -> Dictionary:
	var def_bonus: float = get_terrain_defense_modifier(terrain_type)
	if is_defender_in_pass:
		def_bonus += 0.35
	
	var atk_penalty: float = 0.0
	if is_cross_river:
		atk_penalty += RIVER_CROSSING_ATTACK_PENALTY
	if terrain_type == "ocean_inlandsea":
		atk_penalty += -0.40
	
	var cav_mod: float = 0.0
	if is_attacker_cavalry:
		cav_mod = get_cavalry_combat_modifier(terrain_type, is_attacker_native_adapted)
	
	return {
		"terrain_type": terrain_type,
		"defense_bonus": def_bonus,
		"defender_bonus": def_bonus,
		"attack_penalty": atk_penalty,
		"attacker_modifier": cav_mod,
		"cavalry_modifier": cav_mod,
		"speed_multiplier": get_march_speed_multiplier(terrain_type),
		"supply_loss_multiplier": get_supply_attrition_multiplier(terrain_type)
	}
