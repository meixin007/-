extends RefCounted
## Initial fixture resources are registered once; commands never mint supplies.
const PLAYER = "tongguan_fixture_owner"
const ARTISAN = "tongguan_fixture_artisan"
const ACCOUNT = "tongguan_fixture_owner_cash"
const PAYEE = "tongguan_fixture_artisan_cash"
const STOCK = "tongguan_fixture_timber"
const Construction = preload("res://scripts/core/estate_construction_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Dispatcher = preload("res://scripts/core/game_action_dispatcher.gd")
const City = preload("res://runtime/settlement_state.gd")
const NODE = "tongguan_pass_node"
var catalog: Dictionary
var layout: Dictionary
var land_contracts: Dictionary = {}
var account_contracts: Dictionary = {}
var depot_contracts: Dictionary = {}
func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://construction/catalog.json"))
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://bundle/layout.json"))
func owner(id: String) -> Dictionary: return {"entity_kind":"character", "entity_id":id}
func seed(state) -> void:
	state.player_character_id = PLAYER
	for pair in [[PLAYER,"潼关建设验收人"],[ARTISAN,"驻关营造工匠"]]:
		state.character_states[pair[0]] = {"id":pair[0], "name":pair[1], "status":"alive", "location_id":NODE, "relationships":{}, "memory_summary":[]}
	for pair in [[PLAYER,ACCOUNT,int(catalog.initial_cash)],[ARTISAN,PAYEE,0]]:
		var depot_id: String = pair[0]+"_depot"
		state.depot_states[depot_id] = {"depot_id":depot_id, "owner_character_id":pair[0], "location_node_id":NODE, "stock":{"silk_cash":pair[2]}}
		state.resource_accounts[pair[1]] = {"account_id":pair[1], "owner_ref":owner(pair[0]), "storage_ref":{"storage_kind":"depot","storage_id":depot_id,"resource_key":"silk_cash"}, "resource_key":"silk_cash", "unit_id":"cash_unit", "location_id":NODE, "operator_refs":[owner(pair[0])]}
		account_contracts[pair[1]]=state.resource_accounts[pair[1]].duplicate(true)
		depot_contracts[depot_id]={"owner_character_id":pair[0],"location_node_id":NODE}
	state.management_assets[STOCK] = {"asset_id":STOCK,"asset_kind":"material_stock","name":"工匠自有营造木料","location_id":NODE,"owner_ref":owner(ARTISAN),"source_ref":{"entity_kind":"rule","rule_id":"scenario:tongguan_r2_initial_stock"},"rights":[],"contract_refs":[],"material_key":"timber","unit_id":"material_unit","initial_quantity":int(catalog.initial_timber),"remaining_quantity":int(catalog.initial_timber),"consumptions":{}}
	for slot in layout.slots:
		# The pre-existing barracks remains an explicit imported presentation seed.
		if slot.initial_building != "empty": continue
		var area := 0
		var polygon: Array = slot.polygon_local_m
		var twice_area := 0.0
		for i in polygon.size(): twice_area += float(polygon[i][0])*float(polygon[(i+1)%polygon.size()][1])-float(polygon[(i+1)%polygon.size()][0])*float(polygon[i][1])
		area = maxi(1, floori(abs(twice_area)*0.5))
		var offers := {}
		for kind in slot.allowed_buildings:
			var rule: Dictionary = catalog.facilities[kind]
			offers[kind] = {"industry_kind":kind,"name":rule.name,"price":int(rule.price),"duration_days":int(rule.days),"area_units":area,"version":1,"supplier_id":ARTISAN,"payee_account_id":PAYEE,"inputs":[{"stock_id":STOCK,"quantity":int(rule.timber)}],"setup_offer":{"amount":1,"supplier_id":ARTISAN,"payee_account_id":PAYEE},"maintenance_offer":{"amount":1,"supplier_id":ARTISAN,"payee_account_id":PAYEE}}
		state.management_assets[slot.id] = {"asset_id":slot.id,"asset_kind":"land","name":slot.name,"location_id":NODE,"owner_ref":owner(PLAYER),"initial_owner_ref":owner(PLAYER),"source_ref":{"entity_kind":"rule","rule_id":"scenario:tongguan_r2_reserved_land"},"rights":[],"contract_refs":[],"transfer_history":[],"sale_offer":{"active":false,"version":1},"area_units":area,"used_area_units":0,"development_offers":offers,"disputed":false,"lien_contract_id":"","status":"vacant"}
		land_contracts[slot.id] = {"area_units":area,"development_offers":offers.duplicate(true)}
func summary(state) -> Dictionary:
	return {"cash":Accounts.new().available(state,ACCOUNT),"artisan_cash":Accounts.new().balance(state,PAYEE),"timber":int(state.management_assets[STOCK].remaining_quantity)}
func order_for(state, slot_id: String) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind")=="estate_construction" and order.get("land_id")==slot_id: return order.duplicate(true)
	return {}
func project(state, city: Dictionary) -> Dictionary:
	var value = city.duplicate(true)
	for slot in layout.slots:
		var order = order_for(state, slot.id)
		if order.is_empty(): continue
		value.slot_occupancy[slot.id].building_type = order.blueprint_id
		value.slot_occupancy[slot.id].status = "built" if order.status=="completed" else "building"
	return value
func request(state, slot_id: String, kind: String) -> Dictionary:
	var execution = "tongguan-r2-build:"+slot_id
	return {"execution_id":execution,"request_id":execution,"actor_id":PLAYER,"principal_id":PLAYER,"executor_id":PLAYER,"action_kind":"start_construction","parameters":{"land_id":slot_id,"blueprint_id":kind,"funding_account_id":ACCOUNT,"quote_version":1},"target_refs":[slot_id],"expected_state_revision":int(state.state_revision)}
func inspect(state, city: Dictionary, slot_id: String, kind: String) -> Dictionary:
	var slot = {}
	for item in layout.slots:
		if item.id==slot_id: slot=item; break
	if slot.is_empty() or not slot.get("gameplay_buildable",false): return {"ok":false,"message":"这里是主路、留白或未登记地块，不能建设。"}
	if not kind in slot.allowed_buildings: return {"ok":false,"message":"此地块不允许该类设施。"}
	if int(city.growth_stage)<int(slot.unlock_stage): return {"ok":false,"message":"该地块尚未随成长开放。"}
	if project(state,city).slot_occupancy[slot_id].status!="empty": return {"ok":false,"message":"地块已有建筑或工程。"}
	var proposal = request(state,slot_id,kind)
	var rule: Dictionary = state.management_assets[slot_id].development_offers[kind]
	if Accounts.new().available(state,ACCOUNT)<int(rule.price): return {"ok":false,"message":"建设款不足：需要%d，当前可用%d。"%[rule.price,Accounts.new().available(state,ACCOUNT)]}
	# Run the complete native dispatcher on an independently validated trial state.
	var trial = state.get_script().new()
	var loaded = trial.try_load_dictionary(state.to_dictionary())
	if not loaded.ok: return loaded
	var allowed = Dispatcher.apply(trial,{},proposal)
	if not allowed.ok: return allowed
	return {"ok":true,"request":proposal,"price":rule.price,"duration_days":rule.duration_days,"material_quantity":rule.inputs[0].quantity,"name":rule.name,"slot_id":slot_id,"building_type":kind}
func validate(state, stored_city: Dictionary, initial_city: Dictionary) -> String:
	if stored_city.slot_occupancy != initial_city.slot_occupancy: return "城市占用由实际工程投影，不能用表现按钮改写。"
	if state.player_character_id!=PLAYER or state.resource_accounts.size()!=2 or state.character_states.size()!=2: return "建设主体或账户集合不符。"
	if City.digest(state.resource_accounts)!=City.digest(account_contracts): return "账户权源、仓储或经办人被改动。"
	for id in depot_contracts:
		var depot: Dictionary=state.depot_states.get(id,{})
		if depot.get("owner_character_id")!=depot_contracts[id].owner_character_id or depot.get("location_node_id")!=NODE: return "资金存放地点或所有者被改动。"
	var stock: Variant=state.management_assets.get(STOCK)
	if not stock is Dictionary or stock.get("asset_kind")!="material_stock" or stock.get("owner_ref")!=owner(ARTISAN) or stock.get("location_id")!=NODE or stock.get("material_key")!="timber": return "材料库存或其真实来源缺失。"
	var data = summary(state)
	if data.cash+data.artisan_cash!=int(catalog.initial_cash): return "建设款未在同一账户链中守恒。"
	if int(state.management_assets[STOCK].initial_quantity)!=int(catalog.initial_timber): return "初始材料来源被改动。"
	var counts := {}
	for order in state.economic_contracts.values():
		if order.get("contract_kind")!="estate_construction" or not land_contracts.has(order.get("land_id")): return "存档引用了场景外工程。"
		counts[order.land_id]=int(counts.get(order.land_id,0))+1
		if counts[order.land_id]>1: return "同一预留地块不能重复建设。"
	var completed=state.economic_contracts.values().filter(func(order):return order.status=="completed").size()
	if state.management_assets.size()!=land_contracts.size()+1+completed or state.depot_states.size()!=2: return "建设存档的地块、库存或房屋集合不符。"
	for slot in layout.slots:
		if slot.initial_building!="empty": continue
		var land: Dictionary = state.management_assets.get(slot.id,{})
		if land.get("asset_kind")!="land" or land.get("location_id")!=NODE or land.get("owner_ref")!=owner(PLAYER): return "建设地块权源无效。"
		if land.get("area_units")!=land_contracts[slot.id].area_units or City.digest(land.get("development_offers"))!=City.digest(land_contracts[slot.id].development_offers): return "建设占地或完整报价契约被改动。"
		for kind in slot.allowed_buildings:
			var offer: Dictionary = land.development_offers.get(kind,{})
			var rule: Dictionary = catalog.facilities[kind]
			if offer.get("price")!=rule.price or offer.get("duration_days")!=rule.days or offer.get("industry_kind")!=kind or City.digest(offer.get("inputs"))!=City.digest([{"stock_id":STOCK,"quantity":rule.timber}]): return "施工报价或材料来源被改动。"
	return ""
