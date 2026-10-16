extends RefCounted
## Applies an already recorded birth event. Fertility/pregnancy scheduling is not
## inferred from portraits. This is an engine event API, never an NPC action tool.
const Appearance = preload("res://scripts/core/character_appearance_contract.gd")
const Dna = preload("res://tang_dna_v3_2/scripts/dna_core.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Contract = preload("res://scripts/core/character_birth_contract.gd")

func preview(context, event: Dictionary) -> Dictionary:
	if context==null or context.state==null: return Appearance.fail("missing_birth_context")
	var valid: Dictionary = validate_event(context.state,event)
	if not valid.ok: return valid
	var tx = Transaction.new()
	var checked: Dictionary = tx.preview_command(context.state,"character_birth",event)
	if not checked.ok: return checked
	checked.preview_token["world_epoch"]=str(context.world_epoch)
	return {"ok":true,"envelope":tx.build_command_envelope("character_birth",event,checked.preview_token)}

func commit(context, envelope: Dictionary) -> Dictionary:
	if envelope.get("kind")!="character_birth": return Appearance.fail("invalid_birth_command")
	if context==null or context.state==null: return Appearance.fail("missing_birth_context")
	var token: Variant = envelope.get("preview_token",{})
	if not token is Dictionary: return Appearance.fail("invalid_birth_preview")
	# A persisted completed receipt may replay across restore. An uncommitted
	# preview from the previous world may not create a new person after restore.
	if not context.state.processed_transactions.has(str(envelope.get("transaction_id",""))) and token.get("world_epoch")!=str(context.world_epoch): return Appearance.fail("stale_birth_world")
	return Transaction.new().execute_command(context,envelope,func(working): return apply_recorded_birth(working.state,envelope.input))

static func validate_event(state, event: Dictionary) -> Dictionary:
	if state==null: return Appearance.fail("missing_birth_context")
	var shape: Dictionary = Contract.validate(event)
	if not shape.ok: return shape
	if state.character_states.has(event.child_id): return Appearance.fail("character_already_exists")
	if not state.can_register_dynamic_character(): return Appearance.fail("character_capacity_reached")
	if event.biological_father_id==event.biological_mother_id or event.child_id in [event.biological_father_id,event.biological_mother_id]: return Appearance.fail("invalid_birth_parents")
	for key in ["biological_father_id","biological_mother_id","public_father_id","public_mother_id"]:
		if not state.character_states.has(event[key]) or event[key]==event.child_id: return Appearance.fail("missing_birth_parent")
	for key in ["biological_father_id","biological_mother_id"]:
		var source: Dictionary = Appearance.decode_character(state,event[key])
		if not source.ok: return source
		if float(source.character.appearance_state.age_years)<float(Appearance.schema().adult_rig_min_age): return Appearance.fail("birth_parent_underage")
	return {"ok":true}

static func apply_recorded_birth(state, event: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_event(state,event)
	if not valid.ok: return valid
	var father: Dictionary = Appearance.decode_character(state,event.biological_father_id)
	var mother: Dictionary = Appearance.decode_character(state,event.biological_mother_id)
	var seed: String = ("recorded-birth-1|"+str(state.flags.get("rule_seed",0))+"|"+event.event_ref+"|"+event.child_id).sha256_text()
	var dna: Dictionary = Dna.inherit_child(event.child_id,father.character.dna,mother.character.dna,seed,Appearance.schema())
	var made: Dictionary = Appearance.from_dna(event.child_id,event.portrait_family,0,int(state.current_day),dna,"recorded_birth",{"father_id":event.public_father_id,"mother_id":event.public_mother_id})
	if not made.ok: return made
	var registered: Dictionary = state.register_dynamic_character({"id":event.child_id,"name":event.name,"is_dynamic":true,"archetype_id":"recorded_child","role":"幼童","status":"alive","summonable":false,"stats":{"military":0,"governance":0,"finance":0,"intrigue":0,"diplomacy":0,"prowess":0,"medicine":0,"scholarship":0},"tang_traits":[],"relationships":{},"memory_summary":[],"appearance":made.appearance})
	if not registered.ok: return registered
	return {"ok":true,"character_id":event.child_id,"result_ref":"character_birth|"+event.child_id}
