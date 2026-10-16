extends RefCounted
## Authored inputs are snapshotted into the existing GameState, never reloaded
## during settlement. current_day remains the only clock.
const SOURCE="res://data/scenarios/anshi_rebellion/river_weather_events.json"
const KEY="river_weather_events"
const Conditions=preload("res://scripts/domain/river_crossing_conditions.gd")
static func seed_new_campaign(state) -> Dictionary:
	if state.flags.has(KEY):return {"ok":true}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not data is Dictionary:return {"ok":false,"error":"Invalid river weather source"}
	var valid: Dictionary=_validate(data.get("events"))
	if not valid.ok:return valid
	state.flags[KEY]=data.events.duplicate(true)
	return {"ok":true}

static func settle_daily(state) -> Dictionary:
	if not state.flags.has(KEY):return {"ok":true}
	var events: Variant=state.flags[KEY]
	var valid: Dictionary=_validate(events)
	if not valid.ok:return valid
	# Validate/apply the complete batch on a copy before exposing any mutation.
	var working: Dictionary={"flags":state.flags.duplicate(true)}
	for event: Dictionary in events:
		if int(state.current_day)<int(event.starts_day) or int(state.current_day)>=int(event.recovers_day):continue
		var applied: Dictionary=Conditions.record_high_water(working,event.river_id,event.condition_id,int(event.starts_day),int(event.ends_day),int(event.recovers_day))
		if not applied.ok:return applied
	state.flags=working.flags
	return {"ok":true}

static func _validate(events: Variant) -> Dictionary:
	if not events is Array:return {"ok":false,"error":"River weather events must be an array"}
	var seen: Dictionary={}
	for event: Variant in events:
		if not event is Dictionary:return {"ok":false,"error":"Invalid river weather event"}
		var id: Variant=event.get("event_id")
		if not id is String or id.is_empty() or seen.has(id):return {"ok":false,"error":"Missing or duplicate weather event ID"}
		seen[id]=true
		if event.get("river_id") not in ["wei","han"] or event.get("condition_id") not in ["flood_autumn","river_burst"]:
			return {"ok":false,"error":"Unsupported river weather event"}
		for field in ["starts_day","ends_day","recovers_day"]:
			var value: Variant=event.get(field)
			if not (value is int or value is float):return {"ok":false,"error":"Missing weather event day"}
			if not is_finite(float(value)) or float(value)!=floor(float(value)):return {"ok":false,"error":"Weather event days must be finite integers"}
		if event.starts_day<1 or event.ends_day<=event.starts_day or event.recovers_day<event.ends_day:
			return {"ok":false,"error":"Invalid weather event day interval"}
	return {"ok":true}
