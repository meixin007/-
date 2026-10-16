extends RefCounted
## Trusted engine cosmetic assignment. Adds no NPC action, equipment or possession.
const Appearance = preload("character_appearance_contract.gd")
const Transaction = preload("game_state_transaction.gd")
const Styles = preload("res://tang_dna_v3_2/scripts/portrait_style_catalog.gd")
const Io = preload("res://tang_dna_v3_2/scripts/data_io.gd")
func preview(context, event: Dictionary) -> Dictionary:
	if context==null or context.state==null: return Appearance.fail("missing_style_context")
	var valid: Dictionary = validate_event(context.state,event)
	if not valid.ok: return valid
	var tx = Transaction.new()
	var checked: Dictionary = tx.preview_command(context.state,"character_appearance_style",event)
	if not checked.ok: return checked
	checked.preview_token["world_epoch"]=str(context.world_epoch)
	return {"ok":true,"envelope":tx.build_command_envelope("character_appearance_style",event,checked.preview_token)}
func commit(context, envelope: Dictionary) -> Dictionary:
	if context==null or context.state==null or envelope.get("kind")!="character_appearance_style": return Appearance.fail("invalid_style_command")
	var token: Variant = envelope.get("preview_token",{})
	if not token is Dictionary: return Appearance.fail("invalid_style_preview")
	if not context.state.processed_transactions.has(str(envelope.get("transaction_id",""))) and token.get("world_epoch")!=str(context.world_epoch): return Appearance.fail("stale_style_world")
	return Transaction.new().execute_command(context,envelope,func(working): return _apply(working.state,envelope.input))
static func validate_event(state, event: Dictionary) -> Dictionary:
	if event.size()!=3 or not event.get("character_id") is String or not event.get("event_ref") is String or str(event.event_ref).is_empty() or str(event.event_ref).length()>160 or not event.get("style") is Dictionary:
		return Appearance.fail("invalid_style_event")
	var person: Dictionary = Appearance.decode_character(state,event.character_id)
	if not person.ok: return person
	if not event.style.is_empty() and float(person.character.appearance_state.age_years)<float(Appearance.schema().adult_rig_min_age): return Appearance.fail("adult_style_on_child")
	var resolved: Dictionary = Styles.resolve(person.character.portrait_family,event.style,Io.read_cached_dictionary("res://tang_dna_v3_2/data/ink_style_parts_v1.json"))
	if not resolved.ok: return Appearance.fail(resolved.reason)
	return {"ok":true}
static func _apply(state, event: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_event(state,event)
	if not valid.ok: return valid
	state.character_states[event.character_id].appearance.style=event.style.duplicate(true)
	return {"ok":true,"character_id":event.character_id,"result_ref":"portrait_style|"+event.character_id+"|"+event.event_ref}
