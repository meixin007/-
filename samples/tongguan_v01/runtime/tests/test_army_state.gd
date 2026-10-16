extends SceneTree
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize()->void:
	create_timer(60).timeout.connect(func():printerr("ARMY_STATE_TIMEOUT");quit(1));run.call_deferred()
func run()->void:
	if not ResourceLoader.exists("res://army/controller.gd"):
		check(false,"controlled army runtime exists");quit(1);return
	var script=load("res://army/controller.gd");var army=script.new()
	check(army.error.is_empty(),"minimal actual host initializes")
	if not army.error.is_empty():printerr(army.error);quit(1);return
	check(army.context.state.get_script().resource_path=="res://scripts/core/game_state.gd","original GameState holds force")
	check(army.snapshot().force.current_node_id=="tg_fore","starts east of gate")
	check(army.context.state.route_network_state.routes.is_empty() and army.context.state.transit_corridors.size()==3,"one authoritative corridor set")
	var original_troops=army.digest(army.snapshot().force.troop_tiers)
	var resources=army.digest(army.context.state.resources);var accounts=army.digest(army.context.state.resource_accounts)
	var immutable=army.snapshot();immutable.force.current_node_id="river_north"
	check(army.snapshot().force.current_node_id=="tg_fore","projection cannot move force")
	var before=army.digest(army.snapshot())
	check(not army.order("river_north").ok and army.digest(army.snapshot())==before,"no crossing means no river command or teleport")
	check(not army.order("unknown").ok and army.digest(army.snapshot())==before,"unknown destination rejected atomically")
	var preview=army.preview_order("tg_rear");check(preview.ok and army.digest(army.snapshot())==before,"order preview is non-mutating")
	army.set_gate_open(false)
	check(not army.commit_order(preview.token).ok,"gate change invalidates old order preview")
	check(army.order("tg_rear").ok,"closed gate still permits ordered approach to hold point")
	for i in range(2):check(army.advance_step().ok,"approach step "+str(i))
	check(army.snapshot().force.current_node_id=="tg_east_hold","army reaches east hold node")
	var pos=army.position_local();var block=army.advance_step()
	check(block.ok and block.movement.blocked and army.position_local()==pos,"existing movement service blocks at closed main gate")
	check(army.snapshot().order.status=="waiting" and army.snapshot().force.corridor_progress_days==0,"wait state contains no forward progress")
	check(army.projection().gate_open==false,"gate state has one host authority")
	check(army.set_gate_open(true).ok and army.advance_step().ok,"reopen resumes current order")
	check(army.snapshot().force.current_corridor_id=="tg_main_gate" and army.snapshot().force.corridor_progress_days==1,"mid-gate progress is native force state")
	check(absf(army.position_local()[0])<0.001,"native midpoint projects to gate anchor")
	check(army.set_gate_open(false).ok,"close while on controlled edge")
	pos=army.position_local();block=army.advance_step()
	check(block.ok and block.movement.blocked and army.position_local()==pos,"mid-edge closure does not cross or reset progress")
	var city=army.projection();city.module_damage.gate=2
	check(army.adopt_candidate(city,"damage_gate").ok and not army.projection().gate_open,"severe gate damage does not grant passage")
	check(army.set_paused(true).ok,"pause actual host clock")
	before=army.digest(army.snapshot());check(not army.advance_step().ok and army.digest(army.snapshot())==before,"paused clock cannot advance army or date")
	check(army.set_paused(false).ok and army.set_gate_open(true).ok,"resume through existing clock")
	for i in range(3):check(army.advance_step().ok,"complete remaining path "+str(i))
	check(army.snapshot().force.current_node_id=="tg_rear" and army.snapshot().force.current_corridor_id=="" and army.snapshot().order.status=="arrived","arrives at west endpoint with no duplicated force")
	check(army.context.state.military_forces.size()==1,"one stable force after arrival")
	check(army.order("tg_fore").ok,"return order uses same edges in reverse")
	for i in range(6):check(army.advance_step().ok,"reverse step "+str(i))
	check(army.snapshot().force.current_node_id=="tg_fore" and army.position_local()[0]>0,"reverse ends at original east position")
	check(army.digest(army.snapshot().force.troop_tiers)==original_troops and army.digest(army.context.state.resources)==resources and army.digest(army.context.state.resource_accounts)==accounts,"movement cannot invent troops or accounts")
	check(army.order("tg_rear").ok,"new serial order")
	for i in range(3):army.advance_step()
	check(not army.order("tg_fore").ok,"mid-edge retarget rejected without teleport")
	army.set_gate_open(false);army.set_paused(true)
	var saved=army.snapshot();var written=army.write_save("user://tests/army_save.json")
	if not written.ok:printerr("SAVE_FAILURE ",written)
	check(written.ok,"actual SaveManager writes mid-edge paused order")
	army.set_paused(false);army.set_gate_open(true);army.advance_step()
	check(army.read_save("user://tests/army_save.json").ok and army.digest(army.snapshot())==army.digest(saved),"reload restores position/order/gate/clock/damage exactly")
	var reopened=script.new();check(reopened.read_save("user://tests/army_save.json").ok and reopened.digest(reopened.snapshot())==army.digest(saved),"fresh host reload restores same authority")
	before=army.digest(army.snapshot());check(not army.read_save("user://tests/missing_army.json").ok and army.digest(army.snapshot())==before,"failed read leaves live host untouched")
	var invalid=army.context.state.get_script().new();invalid.try_load_dictionary(army.context.state.to_dictionary());invalid.military_forces[army.FORCE_ID].corridor_progress_days=999
	var bad_written=load("res://scripts/core/save_manager.gd").new(army.definition.world_id).write_save("user://tests/invalid_army.json",invalid)
	if not bad_written.ok:printerr("BAD_SAVE_FAILURE ",bad_written)
	check(bad_written.ok,"generic host save can carry invalid extension progress")
	check(not load("res://scripts/core/save_manager.gd").new().read_save("user://tests/army_save.json",invalid).ok,"default production save contract still rejects fixture campaign identity")
	check(not army.read_save("user://tests/invalid_army.json").ok and army.digest(army.snapshot())==before,"army contract rejects invalid progress before replacing host")
	invalid=null
	army.set_paused(false);army.set_gate_open(true);army.advance_step()
	check(army.snapshot().force.current_node_id=="tg_west_hold","native progress survives restore and resumes")
	army.set_gate_open(false)
	for i in range(2):army.advance_step()
	check(army.snapshot().force.current_node_id=="tg_rear","closing after crossing does not block unrelated west egress")
	check(army.context.state.local_node_state[army.NODE_ID][army.FIELD].receipts.size()>0,"host contains movement receipts")
	var result={"checks":checks,"failures":failures,"clock":"original TimeController and GameState.current_day","movement":"original MilitaryCampaignService","authority":"one isolated GameRuntimeContext","source_scope":"explicit movement fixture, not deployed main campaign"}
	var output="user://tests/state_result.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("P6_ARMY_STATE: "+JSON.stringify(result))
	reopened=null;army=null;await process_frame;quit(0 if failures.is_empty() else 1)
