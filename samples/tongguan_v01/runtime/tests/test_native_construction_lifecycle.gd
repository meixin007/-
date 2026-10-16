extends SceneTree
const Context = preload("res://scripts/core/game_runtime_context.gd")
const Dispatcher = preload("res://scripts/core/game_action_dispatcher.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr(message)
func _initialize() -> void:
	create_timer(45).timeout.connect(func(): printerr("CONSTRUCTION_TEST_TIMEOUT"); quit(1))
	call_deferred("run")
func action(context, kind: String, params: Dictionary, id: String) -> Dictionary:
	var person: String = context.state.player_character_id
	return Dispatcher.new().execute(context,{"execution_id":id,"request_id":id,"actor_id":person,"principal_id":person,"executor_id":person,"action_kind":kind,"parameters":params,"target_refs":[params.get("land_id",params.get("building_id",params.get("shop_id",params.get("office_id",""))))],"expected_state_revision":context.state.state_revision})
func run() -> void:
	if not FileAccess.file_exists("res://scripts/core/estate_construction_service.gd"):
		printerr("FAIL: construction lifecycle missing"); quit(1); return
	var service = load("res://scripts/core/estate_construction_service.gd")
	# Preserve the native economic lifecycle assertions. The isolated slice does
	# not ship portrait definitions, so appearance seeding is explicitly disabled.
	var created: Dictionary = Context.create_new("res://data/scenarios/anshi_rebellion/campaign_beta_1_14.json", "qinghe_patriarch", false)
	if not created.ok: printerr(created); quit(1); return
	var context = created.context
	var result := action(context,"buy_land",{"land_id":"market_north_land","funding_account_id":"clan_cui_qinghe_cash","quote_version":1},"construction-buy")
	check(result.ok,"acquire real land")
	var params := {"land_id":"market_north_land","blueprint_id":"pawnshop","funding_account_id":"clan_cui_qinghe_cash","quote_version":1}
	result = action(context,"start_construction",params,"construction-start")
	check(result.ok,"commission actual builder: "+str(result.get("error","")))
	if not result.ok: quit(1); return
	var order_id: String = context.state.action_receipts["construction-start"].effect_refs[0]
	var order: Dictionary = context.state.economic_contracts[order_id]
	check(order.status=="working" and order.work_days==0,"payment does not complete construction")
	check(context.state.management_assets.market_north_land.used_area_units==order.recipe.area_units,"land reserved once")
	var stock: Dictionary = context.state.management_assets[order.recipe.inputs[0].stock_id]
	check(stock.consumptions[order_id]==order.recipe.inputs[0].quantity,"actual timber consumed against same contract")
	var before: String = context.state.rule_payload_hash_without_revision()
	check(not action(context,"start_construction",params,"construction-conflict").ok,"busy builder cannot promise overlapping project")
	check(before==context.state.rule_payload_hash_without_revision(),"conflicting build does not consume extra materials")
	var control := {"land_id":"market_north_land","order_id":order_id}
	check(action(context,"cancel_construction",control,"construction-cancel").ok,"owner can suspend paid construction")
	order = context.state.economic_contracts[order_id]
	context.state.current_day += 1
	service.settle_daily(context.state)
	check(order.status=="cancelled" and order.work_days==0,"suspended construction performs no work")
	check(Context.create_from_snapshot(JSON.parse_string(JSON.stringify(context.state.to_dictionary()))).ok,"suspended construction restores with paid inputs and occupied area")
	var paid_balance: int = preload("res://scripts/core/resource_account_service.gd").new().balance(context.state,"clan_cui_qinghe_cash")
	check(action(context,"resume_construction",control,"construction-resume").ok,"owner can resume retained work")
	check(preload("res://scripts/core/resource_account_service.gd").new().balance(context.state,"clan_cui_qinghe_cash")==paid_balance,"resume does not charge construction price twice")
	order = context.state.economic_contracts[order_id]
	context.state.current_day += 1
	context.state.character_states[order.supplier_id].location_id = "lingwu_court_node"
	service.settle_daily(context.state)
	check(order.work_days==0 and not order.blocked_reason.is_empty(),"absent builder blocks actual progress")
	context.state.character_states[order.supplier_id].location_id = "refugee_market_node"
	for i in int(order.recipe.duration_days):
		context.state.current_day += 1
		service.settle_daily(context.state)
		var progress: int = int(order.work_days)
		service.settle_daily(context.state)
		check(order.work_days==progress,"same day cannot count twice")
	check(order.status=="completed" and context.state.management_assets.has(order.building_id),"work creates one building")
	check(context.state.management_assets[order.building_id].status=="completed","completion does not open business or generate income")
	var restored: Dictionary = Context.create_from_snapshot(JSON.parse_string(JSON.stringify(context.state.to_dictionary())))
	check(restored.ok,"construction and materials roundtrip: "+str(restored.get("error","")))
	var damaged: Dictionary = context.state.to_dictionary()
	damaged.management_assets.market_north_land.used_area_units = 0
	check(not Context.create_from_snapshot(damaged).ok,"cannot erase occupied land in snapshot")
	result = action(context,"establish_owned_pawnshop",{"building_id":order.building_id,"shop_id":"owned-pawn","office_id":"family_qinghe_shopkeeper","funding_account_id":"clan_cui_qinghe_cash"},"owned-start")
	check(result.ok,"establish on actual owned premises: "+str(result.get("error","")))
	if result.ok:
		check(context.state.management_assets["owned-pawn"].lease_id=="","owned business does not fabricate rent contract")
		check(not action(context,"open_pawnshop",{"shop_id":"owned-pawn"},"early-open").ok,"building alone is insufficient for opening")
		check(action(context,"hire_family",{"office_id":"family_qinghe_shopkeeper","candidate_id":"market_zhou_liang"},"owned-hire").ok,"actual manager employment")
		check(action(context,"prepare_pawnshop",{"shop_id":"owned-pawn","funding_account_id":"clan_cui_qinghe_cash"},"owned-prepare").ok,"actual paid setup")
		check(action(context,"fund_pawnshop",{"shop_id":"owned-pawn","funding_account_id":"clan_cui_qinghe_cash","amount":100},"owned-fund").ok,"real operating capital")
		for i in 2:
			context.state.current_day += 1
			load("res://scripts/core/pawnshop_service.gd").settle_daily(context.state)
		result = action(context,"open_pawnshop",{"shop_id":"owned-pawn"},"owned-open")
		check(result.ok,"prepared staffed funded business opens: "+str(result.get("error","")))
		check(Context.create_from_snapshot(JSON.parse_string(JSON.stringify(context.state.to_dictionary()))).ok,"owned business roundtrips without fake lease")
	print("ESTATE_CONSTRUCTION_LIFECYCLE: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
