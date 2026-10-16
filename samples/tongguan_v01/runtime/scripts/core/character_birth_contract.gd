extends RefCounted
## Data-only recorded-birth shape, shared by authored content and runtime rules.
const REQUIRED = ["child_id","name","biological_father_id","biological_mother_id","public_father_id","public_mother_id","portrait_family","event_ref"]

static func validate(event: Variant) -> Dictionary:
	if not event is Dictionary or event.size()!=REQUIRED.size(): return _fail("invalid_birth_event")
	for key in event:
		if key not in REQUIRED or not event[key] is String or event[key].strip_edges().is_empty(): return _fail("invalid_birth_event")
	for key in ["child_id","biological_father_id","biological_mother_id","public_father_id","public_mother_id"]:
		if event[key].length()>64 or event[key].contains(" "): return _fail("invalid_birth_identity")
	if event.name.length()>128 or event.event_ref.length()>256 or event.portrait_family not in ["male","female"]: return _fail("invalid_birth_identity")
	if event.biological_father_id==event.biological_mother_id or event.public_father_id==event.public_mother_id or event.child_id in [event.biological_father_id,event.biological_mother_id,event.public_father_id,event.public_mother_id]: return _fail("invalid_birth_parents")
	return {"ok":true}

static func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code,"error":"出生事件无效："+code}
