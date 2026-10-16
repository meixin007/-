extends RefCounted
## Rule-only crossing dependencies. Geometry remains in the production candidates.
## Conditions live in GameState.flags; current_day is the sole clock.
const CROSSINGS := {
	"wei_chencang_ferry": {"river_id":"wei", "design_id":"wei_chencang_shared_ferry_art", "name":"陈仓渭水渡口"},
	"liangzhou_han_ferry": {"river_id":"han", "design_id":"liangzhou_han_ferry_art", "name":"梁州汉水渡口"},
}
const ROUTES := {"c_fengxiang_liangzhou":"wei_chencang_ferry", "c_liangzhou_jianmen":"liangzhou_han_ferry"}
const STATE_KEY := "river_surface_conditions"

static func record_high_water(state, river_id: String, condition_id: String, starts_day: int, ends_day: int, recovers_day: int) -> Dictionary:
	# An explicit domain event, never inferred from month, shader or visibility.
	if state == null or river_id not in ["wei", "han"] or condition_id not in ["flood_autumn", "river_burst"] or starts_day < 0 or ends_day <= starts_day or recovers_day < ends_day:
		return {"ok":false, "error":"Invalid river condition or day interval"}
	var existing: Variant = state.flags.get(STATE_KEY, {})
	if not existing is Dictionary:
		return {"ok":false, "error":"Invalid persistent river conditions"}
	var records: Dictionary = existing.duplicate(true)
	var events: Variant = records.get(river_id, [])
	if not events is Array:
		return {"ok":false, "error":"Invalid river condition events"}
	var event := {"condition_id":condition_id, "starts_day":starts_day, "ends_day":ends_day, "recovers_day":recovers_day}
	# Retain overlapping events: a later short shower cannot clear an earlier flood.
	if not events.has(event): events.append(event)
	records[river_id] = events
	state.flags[STATE_KEY] = records
	return {"ok":true}

static func passage(state, route: Dictionary) -> Dictionary:
	var required: Variant = route.get("required_crossings", [])
	if not required is Array:
		return _closed("invalid_crossing", "渡河依赖数据无效")
	var route_id: String = str(route.get("corridor_id", route.get("id", "")))
	if route.get("activation_status", "") == "active" and ROUTES.has(route_id) and required != [ROUTES[route_id]]:
		return _closed("missing_crossing", "道路缺少已登记的渡河依赖")
	for crossing_id: Variant in required:
		if not CROSSINGS.has(crossing_id): return _closed("missing_crossing", "渡河依赖尚未登记")
		var crossing: Dictionary = CROSSINGS[crossing_id]
		var records: Variant = state.flags.get(STATE_KEY, {})
		if not records is Dictionary: return _closed("invalid_surface_condition", "河流水位状态无效")
		var events: Variant = records.get(crossing.river_id, [])
		if not events is Array: return _closed("invalid_surface_condition", "河流水位记录无效")
		for event: Variant in events:
			if not event is Dictionary: return _closed("invalid_surface_condition", "河流水位事件无效")
			for field in ["starts_day", "ends_day", "recovers_day"]:
				if not event.get(field) is int and not event.get(field) is float:
					return _closed("invalid_surface_condition", "河流水位日期无效")
				if not is_finite(float(event[field])) or float(event[field]) != floor(float(event[field])):
					return _closed("invalid_surface_condition", "河流水位日期必须是完整游戏日")
			if event.get("condition_id", "") not in ["flood_autumn", "river_burst"] or event.starts_day < 0 or event.ends_day <= event.starts_day or event.recovers_day < event.ends_day:
				return _closed("invalid_surface_condition", "河流水位事件无效")
			if int(state.current_day) >= int(event.starts_day) and int(state.current_day) < int(event.recovers_day):
				var result := _closed("high_water", "%s水位过高，候水退后再渡" % crossing.name)
				result["crossing_id"] = crossing_id
				return result
	return {"is_passable":true, "reason":"", "reason_code":""}

static func _closed(code: String, reason: String) -> Dictionary:
	return {"is_passable":false, "reason_code":code, "reason":reason}
