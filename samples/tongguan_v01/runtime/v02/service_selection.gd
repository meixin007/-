extends RefCounted
## Pure selection, called by the autoload before any visual cache exists.
static func choose(engine_args: Array, user_args: Array) -> Dictionary:
	var mode := "legacy"
	for arg in engine_args:
		if str(arg).replace("\\", "/").ends_with("/v02/main.tscn"): mode = "v02"
	var explicit := false
	for arg in user_args:
		if not str(arg).begins_with("--map-service="): continue
		if explicit: return {"ok":false, "message":"Repeated --map-service option."}
		explicit = true
		mode = str(arg).substr(14)
	if mode not in ["legacy", "v02"]:
		return {"ok":false, "message":"Unsupported visual service: " + mode}
	return {"ok":true, "mode":mode, "explicit":explicit}
