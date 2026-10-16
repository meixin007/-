extends SceneTree
const Context=preload("res://scripts/core/game_runtime_context.gd")
const Saves=preload("res://scripts/core/save_manager.gd")
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize()->void:
	create_timer(45).timeout.connect(func():printerr("INTEGRATION_TIMEOUT");quit(1))
	_run.call_deferred()
func _run()->void:
	var result=Context.create_new("res://data/scenarios/anshi_rebellion/campaign_beta_1_14.json","",false)
	if not result.ok:check(false,"real context initializes: "+str(result));quit(1);return
	var context=result.context
	check(context.state.get_script().resource_path=="res://scripts/core/game_state.gd","actual GameState")
	var adapter_script=load("res://integration/campaign_adapter.gd")
	if adapter_script==null:check(false,"campaign adapter exists");context=null;quit(1);return
	var production=adapter_script.new(context)
	check(not production.initialize_site().ok and production.projection().is_empty(),"production validation commands are disabled by default")
	production=null
	var adapter=adapter_script.new(context,true)
	var initialized=adapter.initialize_site()
	check(initialized.ok,"transactional site state initialization: "+str(initialized))
	if not initialized.ok:adapter=null;context=null;quit(1);return
	var snapshot=adapter.projection()
	check(adapter.initialize_site().ok and adapter.projection()==snapshot,"initialization is idempotent")
	var resources=context.state.resource_accounts.duplicate(true)
	var routes=context.state.route_network_state.duplicate(true)
	var operation={"kind":"construct","slot_id":"tongguan.slot.rear_storage_01","building_type":"warehouse"}
	var preview=adapter.preview(operation)
	check(preview.ok and adapter.projection()==snapshot,"preview uses actual context without mutation")
	check(adapter.commit(preview).ok,"existing GameStateTransaction adopts construction fixture command")
	check(adapter.projection().slot_occupancy[operation.slot_id].status=="building","state projection is authoritative")
	check(adapter.act({"kind":"finish","slot_id":operation.slot_id}).ok,"finish fixture")
	check(adapter.act({"kind":"growth","stage":3}).ok,"growth")
	check(adapter.act({"kind":"damage","module_id":"gate","level":2}).ok,"damage")
	var before=adapter.projection()
	var stale=adapter.preview({"kind":"growth","stage":2});adapter.act({"kind":"gate","opened":false})
	check(not adapter.commit(stale).ok,"stale transaction rejected")
	check(adapter.projection().growth_stage==3,"stale command atomic")
	var bad=adapter.act({"kind":"construct","slot_id":"tongguan.slot.rear_storage_01","building_type":"barracks"})
	check(not bad.ok,"type mismatch rejected")
	var saved=adapter.projection();var manager=Saves.new()
	check(manager.write_save("user://p5_integration/campaign.json",context.state).ok,"actual SaveManager writes")
	adapter.act({"kind":"growth","stage":1});adapter.act({"kind":"damage","module_id":"gate","level":0})
	check(manager.read_save("user://p5_integration/campaign.json",context.state).ok,"actual SaveManager reads")
	check(adapter.digest(adapter.projection())==adapter.digest(saved),"SAVE-01 exact normalized city state")
	check(adapter.digest(context.state.resource_accounts)==adapter.digest(resources),"no economic resource creation or duplicate ledger")
	check(adapter.digest(context.state.route_network_state)==adapter.digest(routes),"editor diagnostics never replace campaign routes")
	check(context.state.local_node_state[adapter.NODE_ID][adapter.FIELD+"_last_receipt"].kind=="presentation_validation","presentation domain receipt persisted in actual GameState")
	var frontend=load("res://runtime/settlement_state.gd").new(adapter)
	check(frontend.error.is_empty() and frontend._local.is_empty(),"provider injection has no parallel local runtime authority")
	check(frontend.set_growth(2).ok and adapter.projection().growth_stage==2,"runtime controls adopt through actual host transaction")
	var readonly=frontend.runtime;readonly.growth_stage=99
	check(adapter.projection().growth_stage==2,"runtime projection is a detached copy")
	var stale_epoch=adapter.preview({"kind":"growth","stage":1});context.replace_state(context.state,true)
	var epoch_before=adapter.projection()
	check(not adapter.commit(stale_epoch).ok and adapter.projection()==epoch_before,"host epoch replacement rejects old proposals atomically")
	check(frontend.write_save("user://p5_integration/provider_campaign.json").ok,"injected provider writes actual campaign save")
	var provider_saved=frontend.digest(frontend.runtime);frontend.set_growth(1)
	check(frontend.read_save("user://p5_integration/provider_campaign.json").ok and frontend.digest(frontend.runtime)==provider_saved,"injected provider restores actual campaign save")
	var unchanged=adapter.digest(context.state.to_dictionary());var epoch=context.world_epoch
	check(not frontend.read_save("user://p5_integration/missing_campaign.json").ok and adapter.digest(context.state.to_dictionary())==unchanged and context.world_epoch==epoch,"failed host read leaves state and world epoch untouched")
	var corrupt=context.state.get_script().new();corrupt.try_load_dictionary(context.state.to_dictionary())
	corrupt.local_node_state[adapter.NODE_ID][adapter.FIELD].growth_stage=99
	check(manager.write_save("user://p5_integration/invalid_city_campaign.json",corrupt).ok,"host-valid save can carry semantically invalid extension data")
	check(not frontend.read_save("user://p5_integration/invalid_city_campaign.json").ok and adapter.digest(context.state.to_dictionary())==unchanged and context.world_epoch==epoch,"invalid city payload is rejected before any host replacement")
	corrupt=null
	check(adapter.digest(context.state.resource_accounts)==adapter.digest(resources) and adapter.digest(context.state.route_network_state)==adapter.digest(routes),"provider route and resource authority unchanged")
	var final_result={"checks":checks,"failures":failures,"save_version":context.state.SAVE_VERSION,"authority":"copied real GameRuntimeContext and GameStateTransaction / SaveManager","original_project_modified":false,"construction_economics":"not implemented; validation commands only"}
	FileAccess.open("res://integration_result.json",FileAccess.WRITE).store_string(JSON.stringify(final_result,"\t"))
	frontend=null;adapter=null;context=null;manager=null
	print("P5_INTEGRATION: "+JSON.stringify(final_result));quit(0 if failures.is_empty() else 1)
