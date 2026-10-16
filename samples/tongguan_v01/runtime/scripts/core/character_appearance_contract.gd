extends RefCounted
## Appearance lives inside the existing character state. The exact DNA envelope is
## the sole genome truth; ordinary character projections never expose its provenance.
const Io = preload("res://tang_dna_v3_2/scripts/data_io.gd")
const Dna = preload("res://tang_dna_v3_2/scripts/dna_core.gd")
const Exact = preload("res://tang_dna_v3_2/scripts/dna_exact_record.gd")
const Character = preload("res://tang_dna_v3_2/scripts/character_contract.gd")
const VERSION = "character-appearance-1.0"
const FIELDS = ["version","portrait_family","dna_record","age_anchor_days","anchor_day","age_basis","style","condition","public_parents"]
static var _decoded: Dictionary = {}
static var _decode_order: Array = []

static func schema() -> Dictionary:
	return Io.read_cached_dictionary("res://tang_dna_v3_2/data/dna_schema.json")

static func founder(character_id: String, family: String, age_days: int, day: int, seed: String, age_basis: String = "generation_rule") -> Dictionary:
	if not _id(character_id) or family not in ["male","female"] or age_days<0 or age_days>120*365 or day<0 or seed.is_empty() or seed.length()>256:
		return fail("invalid_founder_profile")
	var definition: Dictionary = schema()
	var templates: Dictionary = Io.read_cached_dictionary("res://tang_dna_v3_2/data/bone_templates.json")
	if definition.is_empty() or templates.is_empty(): return fail("appearance_definitions_unavailable")
	return from_dna(character_id,family,age_days,day,Dna.create_founder(character_id,seed,definition,templates),age_basis)

static func from_dna(character_id: String, family: String, age_days: int, day: int, dna: Dictionary, age_basis: String, public_parents: Dictionary = {}) -> Dictionary:
	var encoded: Dictionary = Exact.encode(dna,schema())
	if not encoded.ok: return fail(str(encoded.get("reason","invalid_dna")))
	var profile := {"version":VERSION,"portrait_family":family,"dna_record":encoded.record,"age_anchor_days":age_days,"anchor_day":day,"age_basis":age_basis,"style":{},"condition":{},"public_parents":public_parents.duplicate(true)}
	var valid: Dictionary = validate_profile(profile,character_id)
	if not valid.ok: return valid
	return {"ok":true,"appearance":profile}

static func validate_snapshot(raw: Dictionary) -> Dictionary:
	var people: Variant = raw.get("character_states",{})
	if not people is Dictionary: return fail("invalid_character_states")
	for id in people:
		var person: Variant = people[id]
		if not person is Dictionary or not person.has("appearance"): continue
		var valid: Dictionary = validate_profile(person.appearance,str(id))
		if not valid.ok: return valid
		if int(person.appearance.anchor_day)>int(raw.get("current_day",0)): return fail("appearance_anchor_in_future")
	return {"ok":true}

static func validate_profile(value: Variant, character_id: String) -> Dictionary:
	if not value is Dictionary or value.size()!=FIELDS.size(): return fail("invalid_appearance_shape")
	for key in value:
		if key not in FIELDS: return fail("unknown_appearance_field")
	if value.get("version")!=VERSION: return fail("appearance_version_mismatch")
	if not _id(character_id) or value.get("portrait_family") not in ["male","female"]: return fail("invalid_portrait_family")
	if not _integer(value.get("age_anchor_days"),0,120*365) or not _integer(value.get("anchor_day"),0,10000000): return fail("invalid_age_anchor")
	if value.get("age_basis") not in ["authored_portrait_setting","generation_rule","recorded_birth"]: return fail("invalid_age_basis")
	if not value.get("style") is Dictionary or value.style.size()>3: return fail("invalid_appearance_style")
	for key in value.style:
		if key not in ["hair_asset_id","beard_asset_id","robe_asset_id"] or not value.style[key] is String or value.style[key].length()>128: return fail("invalid_appearance_style")
		if key=="robe_asset_id" and not str(value.style[key]).is_empty() and str(value.style[key]) not in [str(value.portrait_family)+"_robe_0",str(value.portrait_family)+"_robe_1"]: return fail("invalid_appearance_robe")
	if not value.get("condition") is Dictionary: return fail("invalid_appearance_condition")
	for key in value.condition:
		if key not in ["weight_delta","fatigue","sun_exposure","hair_grey_fraction"]: return fail("invalid_appearance_condition")
		var amount: Variant = value.condition[key]
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount)<-1.0 or float(amount)>1.0: return fail("invalid_appearance_condition")
		if key!="weight_delta" and float(amount)<0.0: return fail("invalid_appearance_condition")
	if not value.get("public_parents") is Dictionary: return fail("invalid_public_parents")
	for key in value.public_parents:
		if key not in ["father_id","mother_id"] or not _id(value.public_parents[key]) or value.public_parents[key]==character_id: return fail("invalid_public_parents")
	if not value.get("dna_record") is Dictionary or value.dna_record.get("character_id")!=character_id: return fail("dna_identity_mismatch")
	var decoded: Dictionary = _decode(value.dna_record)
	if not decoded.ok: return decoded
	var errors: Array = Character.validate({"id":character_id,"dna":decoded.dna,"appearance_state":{"age_years":float(value.age_anchor_days)/365.0},"style":value.style,"social":{}},schema())
	if not errors.is_empty(): return fail("invalid_dna_provenance")
	return {"ok":true}

static func decode_character(state, character_id: String) -> Dictionary:
	if state==null or not state.character_states.get(character_id) is Dictionary: return fail("unknown_character")
	var person: Dictionary = state.character_states[character_id]
	if not person.has("appearance"): return fail("appearance_not_assigned")
	var valid: Dictionary = validate_profile(person.appearance,character_id)
	if not valid.ok: return valid
	var profile: Dictionary = person.appearance
	if int(state.current_day)<int(profile.anchor_day): return fail("appearance_anchor_in_future")
	var decoded: Dictionary = _decode(profile.dna_record)
	var condition: Dictionary = profile.condition.duplicate(true)
	condition["age_years"] = float(int(profile.age_anchor_days)+int(state.current_day)-int(profile.anchor_day))/365.0
	condition["is_captive"] = str(person.get("status","")) in ["captive","imprisoned"]
	return {"ok":true,"character":{"id":character_id,"dna":decoded.dna.duplicate(true),"portrait_family":profile.portrait_family,"appearance_state":condition,"style":profile.style.duplicate(true),"social":{}}}

static func seed_new_game(state, data: Dictionary) -> Dictionary:
	var registry: Dictionary = Io.read_cached_dictionary("res://data/scenarios/anshi_rebellion/character_appearance_profiles.json")
	if registry.get("version")!=VERSION or not registry.get("profiles") is Dictionary: return fail("appearance_profiles_unavailable")
	var next: Dictionary = state.character_states.duplicate(true)
	for id in registry.profiles:
		if not next.has(id): continue
		if next[id].has("appearance"):
			var existing: Dictionary = validate_profile(next[id].appearance,str(id))
			if not existing.ok: return existing
			continue
		var spec: Variant = registry.profiles[id]
		if not spec is Dictionary or not _integer(spec.get("display_age_years"),16,120): return fail("invalid_authored_appearance")
		var made: Dictionary = founder(str(id),str(spec.get("portrait_family","")),int(spec.display_age_years)*365,int(state.current_day),"campaign-appearance-1|"+str(data.get("campaign_id",""))+"|"+str(id),"authored_portrait_setting")
		if not made.ok: return made
		next[id]["appearance"] = made.appearance
	state.character_states=next
	return {"ok":true}

static func visual_stamp(context, character_id: String) -> String:
	if context==null or context.state==null: return "no_context"
	var person: Dictionary = context.state.character_states.get(character_id,{})
	return (str(context.get_instance_id())+"|"+str(context.world_epoch)+"|"+str(context.state.current_day)+"|"+character_id+"|"+str(person.get("status",""))+"|"+JSON.stringify(person.get("appearance",{}),"",true,true)).sha256_text()

static func _decode(record: Dictionary) -> Dictionary:
	var key: String = var_to_bytes(record).hex_encode().sha256_text()
	if _decoded.has(key):
		_decode_order.erase(key)
		_decode_order.append(key)
		return {"ok":true,"dna":_decoded[key].duplicate(true)}
	var result: Dictionary = Exact.decode(record,schema())
	if result.ok:
		_decoded[key]=result.dna.duplicate(true)
		_decode_order.append(key)
		if _decode_order.size()>256: _decoded.erase(_decode_order.pop_front())
	return result

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=64 and not value.contains(" ")

static func fail(code: String) -> Dictionary:
	return {"ok":false,"code":code,"error":"角色外观记录无效："+code}
