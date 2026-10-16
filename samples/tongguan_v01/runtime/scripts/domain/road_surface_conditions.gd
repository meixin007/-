extends RefCounted
## Pure reconstruction from saved authored inputs and the existing current_day.
## No second weather state or clock. Rates are explicit M3 design parameters.
const KEY="road_surface_events"
const SOURCE="res://data/scenarios/anshi_rebellion/road_surface_events.json"
const ROUTE="c_fengxiang_liangzhou"
static func seed_new_campaign(state) -> Dictionary:
	if state.flags.has(KEY):return validate(state)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not data is Dictionary:return {"ok":false,"error":"Invalid road surface source"}
	var candidate: Dictionary={"flags":{KEY:data.get("events")}}
	var result: Dictionary=validate(candidate)
	if result.ok:state.flags[KEY]=data.events.duplicate(true)
	return result

static func validate(state) -> Dictionary:
	var events: Variant=state.flags.get(KEY,[])
	if not events is Array:return {"ok":false,"error":"Road surface events must be an array"}
	var ids: Dictionary={}
	for event: Variant in events:
		if not event is Dictionary:return {"ok":false,"error":"Invalid road surface event"}
		var id: Variant=event.get("event_id")
		if not id is String or id.is_empty() or ids.has(id):return {"ok":false,"error":"Missing or duplicate road event ID"}
		ids[id]=true
		if event.get("corridor_id")!=ROUTE or event.get("condition_id") not in ["rain","snowfall"]:
			return {"ok":false,"error":"Unsupported road surface event"}
		for field in ["starts_day","ends_day","recovers_day"]:
			var value: Variant=event.get(field)
			if not (value is int or value is float):return {"ok":false,"error":"Missing road event day"}
			if not is_finite(float(value)) or float(value)!=floor(float(value)):return {"ok":false,"error":"Invalid road event day"}
		if event.starts_day<1 or event.ends_day<=event.starts_day or event.recovers_day<event.ends_day:
			return {"ok":false,"error":"Invalid road event interval"}
	return {"ok":true}

static func effect(state, route: Dictionary) -> Dictionary:
	var result: Dictionary={"is_passable":true,"reason_code":"","reason":"","speed_quarters":4,"surface_state":"dry"}
	if str(route.get("corridor_id",route.get("id","")))!=ROUTE:return result
	if state==null:return result
	if not validate(state).ok:return {"is_passable":false,"reason_code":"invalid_surface","reason":"道路地表数据无效","speed_quarters":0,"surface_state":"unknown"}
	for event: Dictionary in state.flags.get(KEY,[]):
		if int(state.current_day)<int(event.starts_day) or int(state.current_day)>=int(event.recovers_day):continue
		if event.condition_id=="snowfall":
			if str(route.get("transit_type","")) not in ["mountain_pass","pass"]:
				return {"is_passable":false,"reason_code":"invalid_surface","reason":"雪阻场景需要已登记山路","speed_quarters":0,"surface_state":"unknown"}
			return {"is_passable":false,"reason_code":"snow_blocked","reason":"秦岭山口积雪，候通路恢复","speed_quarters":0,"surface_state":"snow"}
		result={"is_passable":true,"reason_code":"wet_road","reason":"雨后路面湿滑，行程放缓","speed_quarters":3,"surface_state":"wet"}
	return result
