extends RefCounted
## Record-independent sidecar merge. It owns no document, renderer or runtime.
static func canonical(value: Variant)->String:
	if value is Dictionary:
		var keys=value.keys();keys.sort_custom(func(a,b):return str(a)<str(b));var fields: Array[String]=[]
		for key in keys:fields.append(JSON.stringify(str(key))+":"+canonical(value[key]))
		return "{"+",".join(fields)+"}"
	if value is Array:
		var fields: Array[String]=[]
		for item in value:fields.append(canonical(item))
		return "["+",".join(fields)+"]"
	if value is int or value is float:return "%.6f"%float(value)
	return JSON.stringify(value)
static func merge(generated: Dictionary,patches: Dictionary,pins: Dictionary,zone_pins: Dictionary,tombstones: Dictionary)->Dictionary:
	var result=generated.duplicate(true);var protected=pins.duplicate(true);var conflicts=[]
	for id in zone_pins:
		if protected.has(id) and canonical(protected[id])!=canonical(zone_pins[id]):conflicts.append({"code":"protected_content","object_id":id,"message":"对象冻结与区域冻结的旧值冲突。"})
		protected[id]=zone_pins[id].duplicate(true)
	for id in patches:
		var patch: Variant=patches[id]
		if not patch is Dictionary or patch.get("op") not in ["add","update","delete"]:
			conflicts.append({"code":"invalid_patch","object_id":id});continue
		if patch.op=="delete":
			if protected.has(id):conflicts.append({"code":"protected_delete","object_id":id})
			result.erase(id);continue
		if not patch.get("record") is Dictionary or patch.record.get("id")!=id:
			conflicts.append({"code":"id_mismatch","object_id":id});continue
		if protected.has(id) and canonical(protected[id])!=canonical(patch.record):conflicts.append({"code":"protected_update","object_id":id})
		result[id]=patch.record.duplicate(true)
	for id in protected:
		if tombstones.has(id):conflicts.append({"code":"protected_tombstone","object_id":id})
		result[id]=protected[id].duplicate(true)
	for id in tombstones:result.erase(id)
	return {"ok":conflicts.is_empty(),"objects":result if conflicts.is_empty() else generated.duplicate(true),"conflicts":conflicts}
