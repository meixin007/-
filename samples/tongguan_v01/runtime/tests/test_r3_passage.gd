extends SceneTree
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:
	create_timer(60).timeout.connect(func():printerr("R3_PASSAGE_TIMEOUT");quit(1));run.call_deferred()
func finish()->void:
	var out="user://tests/r3_passage.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir());var result={"checks":checks,"failures":failures}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R3_PASSAGE: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func run()->void:
	var host=load("res://army/controller.gd").new()
	check(host.has_method("set_movement_profile"),"runtime has force-bound light path conditions")
	if not host.has_method("set_movement_profile"):finish();return
	check(host.error.is_empty(),"R3 host initializes: "+host.error)
	if not host.error.is_empty():finish();return
	host.set_gate_open(false)
	check(not host.order("tg_rear","trail").ok,"ordinary army cannot borrow synthetic path")
	check(host.set_movement_profile("light").ok,"stationary fixture can choose explicit light force profile")
	check(not host.order("tg_rear","trail").ok,"light force requires known path")
	check(host.set_path_known(true).ok and host.order("tg_rear","trail").ok,"known path admits bound light force while main gate is closed")
	check(host.set_paused(false).ok and host.advance_step().ok,"first shared day")
	check(not host.set_movement_profile("ordinary").ok,"cannot switch force capability during active march")
	host.advance_step();host.advance_step()
	check(host.snapshot().force.current_corridor_id=="tg_synthetic_trail","actual native force enters registered synthetic edge")
	check(host.position_local()[1]>50,"rendered position follows the bent route, not straight through gate")
	host.set_path_known(false);var stopped=host.digest(host.snapshot().force);host.advance_step()
	check(host.snapshot().order.status=="waiting" and host.digest(host.snapshot().force)==stopped,"revoked condition holds actual in-edge progress")
	check(host.write_save("user://tests/r3_mid.json").ok,"condition and in-edge progress save with native state")
	host.set_path_known(true);host.advance_step()
	check(host.read_save("user://tests/r3_mid.json").ok and not host.path_known() and host.digest(host.snapshot().force)==stopped,"save restore exact force capability, knowledge and progress")
	host.set_path_known(true)
	for i in 5:check(host.advance_step().ok,"remaining controlled daily step "+str(i))
	check(host.snapshot().order.status=="arrived" and host.snapshot().force.current_node_id=="tg_rear","light force actually reaches west endpoint via synthetic test edge")
	check(not host.order("river_north").ok,"no crossing edge remains forbidden")
	check(host.context.state.route_network_state.routes.is_empty(),"editor preview is absent from campaign movement authority")
	check(host.set_movement_profile("ordinary").ok,"at endpoint ordinary profile can be restored without changing troops")
	check(host.order("tg_fore").ok,"ordinary force can issue main-road return")
	for i in 3:host.advance_step()
	check(host.snapshot().order.status=="waiting","ordinary return still obeys closed main gate")
	check(host.set_gate_open(true).ok,"same authoritative gate reopens")
	for i in 4:host.advance_step()
	check(host.snapshot().order.status=="arrived","ordinary force crosses after reopening")
	check(host.context.state.try_load_dictionary(host.context.state.to_dictionary()).ok,"full native save contract validates R3 state")
	var logic_before=host.digest({"force":host.snapshot().force,"city":host.projection(),"money":host.economy(),"day":host.snapshot().day,"graph":host.context.state.transit_corridors})
	var old_art=host.digest(host.authoring_projection())
	check(host.import_publication("res://bundle/authoring_alternate_fixture.json").ok and host.digest(host.authoring_projection())!=old_art,"publication bridge imports a different actual presentation bundle")
	check(logic_before==host.digest({"force":host.snapshot().force,"city":host.projection(),"money":host.economy(),"day":host.snapshot().day,"graph":host.context.state.transit_corridors}),"publication bridge changes no force, money, date, city or corridor")
	var saved_host=host.digest(host.context.state.to_dictionary())
	check(host.write_save("user://tests/r3_publication.json").ok,"chosen presentation reference saves with native state")
	host.import_publication("res://bundle/authoring_publication.json")
	check(host.read_save("user://tests/r3_publication.json").ok and host.digest(host.context.state.to_dictionary())==saved_host,"native restore uses exact saved presentation and runtime state")
	var invalid=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring_publication.json"));invalid.runtime_authoring.fixed_refs.gate[0]+=1;invalid.erase("content_sha256");invalid.content_sha256=host.digest(invalid)
	FileAccess.open("user://tests/r3_bad_publication.json",FileAccess.WRITE).store_string(JSON.stringify(invalid))
	var before_invalid=host.digest(host.context.state.to_dictionary());var epoch=host.context.world_epoch
	check(not host.import_publication("user://tests/r3_bad_publication.json").ok and host.digest(host.context.state.to_dictionary())==before_invalid and host.context.world_epoch==epoch,"even correctly checksummed publication cannot replace core geography or live state")
	var partial=host.get_script().new();partial.order("tg_rear");partial.set_paused(false);partial.advance_step();partial.advance_step()
	check(partial.order("tg_fore").ok,"at intermediate node one-edge return order is valid")
	check(partial.advance_step().ok and partial.advance_step().ok and partial.snapshot().order.status=="arrived","one-edge order never assumes a three-edge chain")
	partial=null
	host=null;finish()
