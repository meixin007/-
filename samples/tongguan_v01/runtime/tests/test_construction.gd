extends SceneTree
var checks := 0
var failures: Array[String] = []
const Controller = preload("res://army/controller.gd")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _initialize() -> void:
	create_timer(55).timeout.connect(func(): printerr("R2_STATE_TIMEOUT"); quit(1))
	run.call_deferred()
func run() -> void:
	var host = Controller.new()
	check(host.has_method("preview_construction"), "construction preview must use actual host rules")
	if not host.has_method("preview_construction"): finish(); return
	check(host.error.is_empty(), "host initializes: " + host.error)
	if not host.error.is_empty(): finish(); return
	var slot = "tongguan.slot.rear_storage_01"
	var before = host.digest(host.context.state.to_dictionary())
	var quote = host.preview_construction(slot, "warehouse")
	check(quote.ok, "warehouse quote accepted: " + str(quote))
	check(host.digest(host.context.state.to_dictionary()) == before, "preview never mutates world")
	if not quote.ok: finish(); return
	check(quote.price == 120 and quote.duration_days == 3 and quote.material_quantity == 20, "explicit fixture quote, materials and real work days")
	var started = host.commit_construction(quote.token)
	check(started.ok, "one transaction commissions native construction: " + str(started))
	if not started.ok: finish(); return
	check(host.economy().cash == 120 and host.economy().artisan_cash == 120 and host.economy().timber == 60, "payment transfers existing cash; material stock consumed")
	var order = host.construction_for(slot)
	check(order.status == "working" and order.work_days == 0, "payment is not instant completion")
	check(host.projection().slot_occupancy[slot].status == "building", "map derives in-progress module from native contract")
	var charged = host.digest(host.context.state.to_dictionary())
	check(not host.commit_construction(quote.token).ok and host.digest(host.context.state.to_dictionary()) == charged, "same preview cannot charge twice")
	check(not host.preview_construction(slot, "warehouse").ok, "occupied slot rejects second project")
	check(not host.preview_construction(slot, "barracks").ok, "wrong facility rejected")
	check(not host.preview_construction("main_road", "warehouse").ok, "permanent road is not a buildable plot")
	check(not host.preview_construction("tongguan.slot.expansion_01", "warehouse").ok, "growth locked plot rejected")
	var frozen = host.digest(host.context.state.to_dictionary())
	check(not host.advance_step().ok and host.digest(host.context.state.to_dictionary()) == frozen, "paused clock advances neither work nor army")
	check(host.set_paused(false).ok and host.advance_step().ok, "construction advances without an army order")
	check(host.construction_for(slot).work_days == 1, "exactly one work day on same native clock")
	var same_day = host.context.state.to_dictionary()
	preload("res://scripts/core/estate_construction_service.gd").settle_daily(host.context.state)
	check(host.digest(host.context.state.to_dictionary()) == host.digest(same_day), "same-day settlement cannot double count")
	check(host.order("tg_rear").ok and host.set_gate_open(false).ok and host.advance_step().ok, "army and construction share a daily transaction")
	check(host.construction_for(slot).work_days == 2 and host.snapshot().force.corridor_progress_days == 1, "both systems advance on same second day")
	check(host.set_paused(true).ok and host.write_save("user://tests/r2_mid.json").ok, "save paused construction and moving army together")
	var saved = host.digest(host.context.state.to_dictionary())
	check(host.set_paused(false).ok and host.advance_step().ok, "third construction day")
	check(host.construction_for(slot).status == "completed" and host.projection().slot_occupancy[slot].status == "built", "work creates one native building and projected module")
	check(host.read_save("user://tests/r2_mid.json").ok and host.digest(host.context.state.to_dictionary()) == saved, "mid-work restore exact authoritative snapshot")
	check(host.set_paused(false).ok and host.advance_step().ok and host.advance_step().ok, "resume construction and closed-gate approach")
	check(host.snapshot().order.status == "waiting" and host.construction_for(slot).status == "completed", "closed gate blocks army while independent construction completes")
	check(host.economy().cash == 120 and host.economy().timber == 60 and host.context.state.economic_contracts.size() == 1, "completion never pays again or duplicates contract")
	check(host.set_gate_open(true).ok, "reopen same gate")
	for i in 4: check(host.advance_step().ok, "army continues day " + str(i))
	check(host.snapshot().order.status == "arrived", "construction does not obstruct original controlled corridor")
	var poor = host.preview_construction("tongguan.slot.expansion_01", "granary")
	check(not poor.ok, "locked or unaffordable construction rejected")
	var city = host.projection(); city.slot_occupancy[slot].status = "empty"; city.slot_occupancy[slot].building_type = ""
	check(not host.adopt_candidate(city, "finish").ok, "old presentation buttons cannot rewrite construction authority")
	check(host.write_save("user://tests/r2_complete.json").ok, "completed construction saves")
	check(host.read_save("user://tests/r2_complete.json").ok, "completed native building restores")
	var facade=preload("res://runtime/settlement_state.gd").new(host)
	check(facade._local.is_empty() and facade.set_growth(3).ok, "city provider has no second state and growth unlocks reserved land")
	var insufficient=host.digest(host.context.state.to_dictionary())
	var too_expensive=host.preview_construction("tongguan.slot.expansion_01", "granary")
	check(not too_expensive.ok and str(too_expensive.get("message","")).contains("建设款不足") and host.digest(host.context.state.to_dictionary())==insufficient, "insufficient actual cash refuses atomically with clear reason")
	var test_host=Controller.new()
	var stale=test_host.preview_construction(slot,"warehouse")
	test_host.set_gate_open(false)
	var stale_before=test_host.digest(test_host.context.state.to_dictionary())
	check(not test_host.commit_construction(stale.token).ok and test_host.digest(test_host.context.state.to_dictionary())==stale_before, "gate/state change invalidates quote without charge")
	stale=test_host.preview_construction(slot,"warehouse")
	test_host.write_save("user://tests/r2_quote_epoch.json")
	test_host.read_save("user://tests/r2_quote_epoch.json")
	check(not test_host.commit_construction(stale.token).ok, "world replacement invalidates construction preview")
	# Source tests vary legitimate initial stocks to exercise native refusal rules.
	var dry=test_host.context.state.get_script().new(); dry.try_load_dictionary(test_host.context.state.to_dictionary())
	dry.management_assets.tongguan_fixture_timber.initial_quantity=1; dry.management_assets.tongguan_fixture_timber.remaining_quantity=1
	var native_request=test_host._economy.request(dry,slot,"warehouse")
	var dry_before=test_host.digest(dry.to_dictionary())
	var no_material=preload("res://scripts/core/game_action_dispatcher.gd").apply(dry,{},native_request)
	check(not no_material.ok and str(no_material.get("error","")).contains("材料不足") and test_host.digest(dry.to_dictionary())==dry_before, "native material rule rejects unavailable stock before charging")
	var preview=test_host.preview_construction(slot,"warehouse"); test_host.commit_construction(preview.token)
	var busy=test_host.preview_construction("tongguan.slot.rear_workshop_01","workshop")
	check(not busy.ok and str(busy.get("error","")).contains("工匠"), "one actual artisan cannot promise overlapping contracts")
	var bad_state=host.context.state.get_script().new(); bad_state.try_load_dictionary(host.context.state.to_dictionary())
	bad_state.local_node_state[host.NODE_ID][host.CITY_FIELD].slot_occupancy[slot].status="built"
	bad_state.local_node_state[host.NODE_ID][host.CITY_FIELD].slot_occupancy[slot].building_type="warehouse"
	var manager=preload("res://scripts/core/save_manager.gd").new(host.definition.world_id)
	check(manager.write_save("user://tests/r2_bad_projection.json",bad_state).ok, "generic host save can carry invalid extension; adapter must validate")
	var read_before=host.digest(host.context.state.to_dictionary()); var epoch=host.context.world_epoch
	check(not host.read_save("user://tests/r2_bad_projection.json").ok and host.digest(host.context.state.to_dictionary())==read_before and host.context.world_epoch==epoch, "bad extension read rejected without world replacement")
	check(not preload("res://scripts/core/save_manager.gd").new().read_save("user://tests/r2_complete.json",bad_state).ok, "default production reader rejects isolated R2 world")
	check(facade.set_damage(slot,2).ok and host.set_gate_open(false).ok, "damage and gate use same authoritative city state")
	var completed_id: String=host.construction_for(slot).building_id
	check(facade.set_damage(slot,0).ok and host.construction_for(slot).building_id==completed_id and host.economy().cash==120, "visual repair preserves same facility and paid amounts")
	check(host.digest(host.context.state.route_network_state.routes)==host.digest({}), "editor RoutePreview never authorizes movement")
	check(host.context.state.try_load_dictionary(host.context.state.to_dictionary()).ok, "complete native host contract validates final snapshot")
	var empty_host=Controller.new()
	var missing=empty_host.context.state.get_script().new(); missing.try_load_dictionary(empty_host.context.state.to_dictionary()); missing.management_assets.clear()
	check(manager.write_save("user://tests/r2_missing_assets.json",missing).ok, "generic save permits empty isolated economic assets")
	var intact=empty_host.digest(empty_host.context.state.to_dictionary())
	check(not empty_host.read_save("user://tests/r2_missing_assets.json").ok and empty_host.digest(empty_host.context.state.to_dictionary())==intact, "missing required stocks or lands fail safely before replacing live world")
	empty_host=null; missing=null
	facade=null; test_host=null; dry=null; bad_state=null; manager=null
	host = null
	finish()
func finish() -> void:
	var result = {"checks": checks, "failures": failures}
	var output = "user://tests/r2_state.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("R2_STATE: " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
