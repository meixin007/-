extends RefCounted
## A validation integration kit, injected into the runtime provider interface.
## Production construction is disabled until existing economic/authority rules call it.
const Tx=preload("res://scripts/core/game_state_transaction.gd")
const State=preload("res://runtime/settlement_state.gd")
const Saves=preload("res://scripts/core/save_manager.gd")
const NODE_ID="tongguan_pass_node"
const FIELD="tongguan_settlement_runtime_v1"
var context: RefCounted
var validation_commands:=false
var _pending: Dictionary={}
var _sequence:=0
func _init(owner: RefCounted,allow_validation_commands:=false)->void:context=owner;validation_commands=allow_validation_commands
func digest(value: Variant)->String:return State.digest(value)
func projection()->Dictionary:return context.state.local_node_state.get(NODE_ID,{}).get(FIELD,{}).duplicate(true)
func initialize_site()->Dictionary:
	if not projection().is_empty():return {"ok":true,"code":"already_initialized"}
	return act({"kind":"initialize"})
func preview(operation: Dictionary)->Dictionary:
	if not validation_commands:return {"ok":false,"error":"Validation commands are disabled in the production adapter."}
	var input={"extension":"tongguan_runtime_v1","validation_only":true,"operation":operation.duplicate(true)}
	_sequence+=1;var token="presentation_%d_%d"%[get_instance_id(),_sequence]
	_pending.clear();_pending[token]={"input":input,"state_revision":int(context.state.state_revision),"world_epoch":context.world_epoch}
	return {"ok":true,"token":token,"state_revision":int(context.state.state_revision),"world_epoch":context.world_epoch}
func commit(preview_result: Dictionary)->Dictionary:
	if not validation_commands or not _pending.has(preview_result.get("token","")):return {"ok":false,"error":"Unknown or disabled presentation proposal."}
	var proposal: Dictionary=_pending[preview_result.token];_pending.clear()
	if proposal.world_epoch!=context.world_epoch or proposal.state_revision!=int(context.state.state_revision):return {"ok":false,"error":"Stale host epoch or revision."}
	# Generic transactions are the existing host's API for domain updates.
	# Do not disguise presentation controls as a shared economic game_action.
	return Tx.new().execute(context,func(working):return _apply(working,proposal.input))
func act(operation: Dictionary)->Dictionary:return commit(preview(operation))
func _apply(working: RefCounted,input: Dictionary)->Dictionary:
	if input.get("extension")!="tongguan_runtime_v1" or input.get("validation_only")!=true:return {"ok":false,"error":"Invalid command namespace."}
	var op: Dictionary=input.get("operation",{});var state=State.new();var current: Dictionary=working.state.local_node_state.get(NODE_ID,{}).get(FIELD,{})
	if not current.is_empty():
		var saved={"schema_version":1,"world_id":"tongguan_slice_v01","layout_version":state.layout.layout_version,"runtime":current.duplicate(true)};saved.content_sha256=State.digest(saved)
		var restored=state.restore_save(saved)
		if not restored.ok:return restored
	elif op.get("kind")!="initialize":return {"ok":false,"error":"Site is not initialized."}
	var result: Dictionary
	match op.get("kind",""):
		"initialize":result={"ok":true}
		"construct":result=state.construct(str(op.get("slot_id","")),str(op.get("building_type","")))
		"finish":result=state.finish_construction(str(op.get("slot_id","")))
		"growth":result=state.set_growth(int(op.get("stage",0)))
		"damage":result=state.set_damage(str(op.get("module_id","")),int(op.get("level",-1)))
		"gate":result=state.set_gate_open(bool(op.get("opened",false)))
		"candidate":
			var candidate: Variant=op.get("runtime")
			if not candidate is Dictionary or int(candidate.get("revision",-1))!=int(state.runtime.revision):return {"ok":false,"error":"Stale settlement revision."}
			var issue=state._validate_runtime(candidate)
			if not issue.is_empty():return {"ok":false,"error":issue}
			candidate=candidate.duplicate(true);candidate.revision=int(candidate.revision)+1;state._local=candidate;result={"ok":true}
		_:return {"ok":false,"error":"Unknown validation operation."}
	if not result.ok:return {"ok":false,"error":str(result.get("message",result.get("error","Invalid action.")))}
	var node: Dictionary=working.state.local_node_state.get(NODE_ID,{}).duplicate(true);node[FIELD]=state.runtime;working.state.local_node_state[NODE_ID]=node
	working.state.state_revision+=1
	node[FIELD+"_last_receipt"]={"kind":"presentation_validation","state_revision":int(working.state.state_revision),"settlement_revision":int(state.runtime.revision),"state_hash":digest(state.runtime)}
	return {"ok":true,"receipt":node[FIELD+"_last_receipt"].duplicate(true),"result_ref":"tongguan_runtime_v1:"+str(int(state.runtime.revision)),"validation_only":true}
func adopt_candidate(candidate: Dictionary,action: String)->Dictionary:return act({"kind":"candidate","runtime":candidate,"action":action})
func write_save(path: String)->Dictionary:return Saves.new().write_save(path,context.state)
func read_save(path: String)->Dictionary:
	# Validate a detached candidate before replacing the live host world.
	var candidate=context.state.get_script().new();var read=Saves.new().read_save(path,candidate)
	if not read.ok:return read
	var contract=State.new();var value: Dictionary=candidate.local_node_state.get(NODE_ID,{}).get(FIELD,{})
	var issue=contract._validate_runtime(value)
	if not issue.is_empty():return {"ok":false,"error":issue}
	var replaced=context.replace_state(candidate,true)
	return read if replaced.ok else replaced
