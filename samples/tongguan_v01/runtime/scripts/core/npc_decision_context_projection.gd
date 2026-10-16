extends RefCounted

const Profile = preload("res://scripts/core/npc_behavior_profile_service.gd")
const Knowledge = preload("res://scripts/core/character_knowledge_service.gd")
const Memory = preload("res://scripts/core/structured_memory_service.gd")
const Catalog = preload("res://scripts/core/game_action_catalog.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")

func build(state, data: Dictionary, actor_id: String, offset: int = 0, limit: int = 32) -> Dictionary:
	var self_profile: Dictionary = Profile.new().build(state, data, actor_id)
	if not self_profile.ok: return self_profile
	var known := {}
	var ids: Array = [actor_id]
	for id in state.character_states[actor_id].get("relationships", {}):
		if state.character_states.has(id) and not ids.has(id): ids.append(id)
	var observer: Dictionary = state.character_knowledge if actor_id == state.player_character_id else state.observer_character_knowledge.get(actor_id, {})
	for id in observer:
		if not ids.has(id): ids.append(id)
	for row in state.economic_contracts.values():
		if row.get("contract_kind") == "social_agreement" and row.participant_ids.has(actor_id):
			var received: Dictionary = load("res://scripts/core/social_agreement_service.gd").project(state, row, actor_id)
			if not received.is_empty():
				for person in received.participant_ids:
					if not ids.has(person): ids.append(person)
	var location: String = state.character_states[actor_id].get("location_id", "")
	for id in state.character_states:
		if location != "" and state.character_states[id].get("location_id") == location and not ids.has(id): ids.append(id)
	var claims := {}
	for fact in state.information_claims:
		var claim: Dictionary = state.information_claims[fact].get(actor_id, {})
		if not claim.is_empty(): claims[fact] = {"payload": claim.get("payload", {}).duplicate(true), "acquired_day": claim.get("acquired_day", claim.get("day", 0)), "channel": claim.get("channel", ""), "source_context": claim.get("source_context", {}).duplicate(true)}
	ids.sort()
	for id in ids.slice(maxi(0, offset), ids.size() if limit == -1 else maxi(0, offset) + clampi(limit, 0, 64)):
		if not state.character_states.has(id): continue
		var fields := {}
		for field in observer.get(id, {}): fields[field] = Knowledge.new().get_observer_field(state, actor_id, id, field)
		if state.character_states[id].get("location_id") == location: fields["observed_location"] = location
		known[id] = {"character_id": id, "name": state.character_states[id].get("name", id), "known_fields": fields}
	var accounts := {}
	for id in state.resource_accounts:
		if Accounts.new().can_operate(state, id, actor_id): accounts[id] = {"account_id": id, "available": Accounts.new().available(state, id), "unit_id": state.resource_accounts[id].unit_id, "location_id": Accounts.new().location(state, id)}
	var tasks: Array = (state.active_tasks + state.completed_tasks).filter(func(task): return task.get("principal_id") == actor_id or task.get("executor_id") == actor_id)
	var contracts := {}
	for id in state.economic_contracts:
		var contract: Dictionary = state.economic_contracts[id]
		if contract.get("contract_kind") == "social_agreement":
			var visible: Dictionary = load("res://scripts/core/social_agreement_service.gd").project(state, contract, actor_id)
			if not visible.is_empty(): contracts[id] = visible
		elif contract.get("contract_kind") == "gift_delivery":
			var visible: Dictionary = load("res://scripts/core/gift_delivery_service.gd").project(state, contract, actor_id)
			if not visible.is_empty(): contracts[id] = visible
		elif contract.get("contract_kind") == "food_purchase" and actor_id in [contract.get("buyer_id"), contract.get("seller_id")]: contracts[id] = contract.duplicate(true)
		elif contract.get("employee_id") == actor_id or contract.get("principal_id") == actor_id or contract.get("participants", []).has(actor_id): contracts[id] = contract.duplicate(true)
	var offices := {}
	for id in state.office_state:
		if state.office_state[id].get("holder_id") == actor_id or load("res://scripts/core/family_office_rules.gd").authority(state, id, actor_id): offices[id] = state.office_state[id].duplicate(true)
	var assets := {}
	var authorizations := {}
	for id in state.action_authorizations:
		var auth: Dictionary = state.action_authorizations[id]
		if auth.get("principal_id") == actor_id or auth.get("delegate_id") == actor_id or auth.get("delegate_ids", []).has(actor_id): authorizations[id] = auth.duplicate(true)
	var public_assets := {}
	for id in state.management_assets:
		var asset: Dictionary = state.management_assets[id]
		if asset.get("owner_ref") == {"entity_kind": "character", "entity_id": actor_id} or asset.get("custodian_ref") == {"entity_kind": "character", "entity_id": actor_id}: assets[id] = asset.duplicate(true)
		if asset.get("asset_kind") in ["land", "estate_building"] and load("res://scripts/core/land_property_service.gd").authority(state, asset, actor_id): assets[id] = asset.duplicate(true)
		if asset.get("asset_kind") in ["pawnshop", "retail_shop", "manufacturing_shop", "managed_farm", "modeled_business"] and Accounts.new().can_operate(state, str(asset.get("account_id", "")), actor_id): assets[id] = asset.duplicate(true)
		var posted_land: bool = asset.get("asset_kind") == "land" and asset.get("sale_offer", {}).get("active", false) and asset.get("sale_offer", {}).get("seller_consent", false)
		if asset.get("location_id") != location or not (asset.get("offer_visibility") == "public" or asset.has("rental_offer") or asset.has("pledge_offer") or posted_land): continue
		var offer := {"asset_id": id, "asset_kind": asset.asset_kind, "name": asset.name, "status": asset.status, "location_id": location}
		if posted_land:
			offer["sale_offer"] = {}
			for field in ["amount", "version", "valid_until_day", "seller_ref", "seller_consent", "payee_account_id"]:
				if asset.sale_offer.has(field): offer.sale_offer[field] = asset.sale_offer[field].duplicate(true) if asset.sale_offer[field] is Dictionary else asset.sale_offer[field]
			offer["disposition_obstacles"] = {"disputed": asset.get("disputed", false), "has_lien": asset.get("lien_contract_id", "") != "", "has_usage_rights": not asset.get("rights", []).is_empty(), "occupied_area_units": asset.get("used_area_units", 0)}
		if asset.get("asset_kind") == "estate_building":
			for key in ["property_offer", "operation_offer"]:
				var quote: Dictionary = asset.get(key, {})
				if not quote.get("active", false): continue
				offer[key] = {}
				for field in ["amount", "version", "duration_days", "use_until_day", "valid_until_day", "seller_ref", "payee_account_id", "kind"]:
					if quote.has(field): offer[key][field] = quote[field].duplicate(true) if quote[field] is Dictionary else quote[field]
			var ground: Dictionary = state.management_assets.get(asset.get("land_id"), {})
			offer["disposition_obstacles"] = {"disputed": ground.get("disputed", false), "has_lien": ground.get("lien_contract_id", "") != "" or asset.get("lien_contract_id", "") != "", "has_operating_right": not load("res://scripts/core/estate_property_transaction_service.gd").operation(state, asset).is_empty()}
		for key in ["rental_offer", "setup_offer", "maintenance_offer", "pledge_offer", "food_offer"]:
			if asset.has(key):
				offer[key] = {}
				var fields: Array = ["price", "lot_units"] if key == "food_offer" else (["borrower_id", "principal", "fee", "duration_days", "valuation", "valuation_basis"] if key == "pledge_offer" else ["amount", "period_days", "duration_days", "landlord_id", "supplier_id", "payee_account_id", "valid_until_day"])
				for field in fields:
					if asset[key].has(field): offer[key][field] = asset[key][field]
		if asset.asset_kind == "workshop":
			offer["supplier_id"] = asset.supplier_id
			offer["recipes"] = {}
			for recipe_id in asset.get("recipes", {}):
				var recipe: Dictionary = asset.recipes[recipe_id]
				offer.recipes[recipe_id] = {"name": recipe.output_definition.name, "price": recipe.price, "duration_days": recipe.duration_days, "source_work_id": recipe.source_work_id}
		public_assets[id] = offer
	var destinations: Dictionary = load("res://scripts/core/regional_visit_service.gd").destinations(state)
	var travel := {}
	var nodes: Array = destinations.keys()
	nodes.sort()
	for node in nodes.slice(maxi(0, offset), nodes.size() if limit == -1 else maxi(0, offset) + clampi(limit, 0, 64)): travel[node] = destinations[node]
	for office in offices.values():
		var node: String = office.get("scope_ref", {}).get("entity_id", "")
		if destinations.has(node): travel[node] = destinations[node]
	for contract in contracts.values():
		if contract.get("contract_kind") == "social_agreement" and contract.terms.has("office_id"):
			var node: String = load("res://scripts/core/npc_opportunity_projection.gd").observed_office(state, contract, actor_id).get("scope_ref", {}).get("entity_id", "")
			if destinations.has(node): travel[node] = destinations[node]
		if contract.get("contract_kind") == "social_agreement" and destinations.has(contract.terms.get("destination_id", "")): travel[contract.terms.destination_id] = destinations[contract.terms.destination_id]
	if destinations.has(location): travel[location] = destinations[location]
	var actions: Array = []
	for row in Catalog.discover():
		var action := {"action_kind": row.action_kind, "status": row.status, "required_parameters": row.required_parameters}
		if not row.parameter_contract.is_empty(): action["parameter_contract"] = row.parameter_contract
		actions.append(action)
	var result := {"ok": true, "context": {"actor_id": actor_id, "day": state.current_day, "self_profile": self_profile.profile, "known_characters": known, "information_claims": claims, "memories": Memory.new().get_relevant_memories(state, actor_id, [], 8, actor_id), "controlled_accounts": accounts, "own_tasks": tasks.duplicate(true), "own_contracts": contracts, "own_authorizations": authorizations, "recent_results": load("res://scripts/core/npc_recent_result_projection.gd").build(state, actor_id, tasks, contracts), "response_guidance": response_guidance(contracts, actor_id), "purchase_guidance": purchase_guidance(state, public_assets, accounts, actor_id), "survival_guidance": load("res://scripts/core/household_subsistence_service.gd").decision_need(state, data, actor_id), "own_offices": offices, "controlled_assets": assets, "public_assets": public_assets, "travel_destinations": travel, "action_catalog": actions, "paging": {"character_count": ids.size(), "next_offset": offset + limit if offset + limit < ids.size() else -1, "destination_count": nodes.size()}}}

	var opportunity = load("res://scripts/core/npc_opportunity_projection.gd")
	result.context["employment_guidance"] = opportunity.employment(state, data, result.context)
	result.context["public_work_guidance"] = opportunity.public_work(state, data, result.context)
	result.context["decision_guidance"] = opportunity.goals(result.context)
	return result

static func purchase_guidance(state, posted: Dictionary, accounts: Dictionary, actor: String) -> Array:
	var result: Array = []
	var funding := actor + "_cash"
	if not accounts.has(funding): return result
	for id in posted:
		if result.size() >= 8: break
		if posted[id].get("asset_kind") != "food_stall" or not posted[id].has("food_offer"): continue
		var params := {"stall_id": id, "funding_account_id": funding, "lots": 1}
		# This rule reads the public price/lot and buyer's currency unit, never
		# the seller's private balance. Stock is rechecked at actual adoption.
		var quote: Dictionary = load("res://scripts/core/household_subsistence_service.gd").cost_for(state, params)
		if not quote.ok: continue
		result.append({"action": {"action_kind": "buy_food", "parameters": params, "target_refs": [id, funding]}, "quoted_cost": {"account_id": quote.account_id, "amount": quote.amount}, "can_afford": accounts[funding].available >= quote.amount, "ration_units": posted[id].food_offer.lot_units, "requires_world_recheck": true, "effect": "Optional purchase of one posted lot into your own ration account, using your own cash. You may choose other positive lot quantities; actual seller stock and funds are checked, never created."})
	return result

static func response_guidance(visible: Dictionary, actor: String) -> Array:
	var result: Array = []
	var quoted_state := _VisibleCosts.new(visible)
	for id in visible:
		if result.size() >= 16: break
		var row: Dictionary = visible[id]
		if row.get("contract_kind") == "social_agreement" and row.participant_ids.has(actor) and row.status in ["proposed", "countered"] and row.accepted_versions.get(actor) != row.terms_version:
			for choice in ["accept", "reject", "counter", "withdraw"]:
				var params := {"agreement_id": id, "terms_version": row.terms_version, "choice": choice, "counter_terms": row.terms.duplicate(true) if choice == "counter" else {}}
				var quote: Dictionary = load("res://scripts/core/social_agreement_service.gd").cost_for(quoted_state, "respond_social_agreement", params)
				if quote.ok: result.append({"action": {"action_kind": "respond_social_agreement", "parameters": params, "target_refs": [id]}, "quoted_cost": {"account_id": quote.account_id, "amount": quote.amount}, "requires_world_recheck": true, "effect": "Record your own signed response only; acceptance does not itself pay wages, transfer gifts or execute promises. For counter, change the desired price in the complete counter_terms while retaining the same objects."})
		elif row.get("contract_kind") == "gift_delivery" and row.get("recipient_id") == actor and row.status == "awaiting_response":
			for choice in ["accept", "reject"]:
				var params := {"delivery_id": id, "choice": choice}
				var quote: Dictionary = load("res://scripts/core/gift_delivery_service.gd").cost_for(quoted_state, "respond_gift_delivery", params)
				if quote.ok: result.append({"action": {"action_kind": "respond_gift_delivery", "parameters": params, "target_refs": [id]}, "quoted_cost": {"account_id": quote.account_id, "amount": quote.amount}, "requires_world_recheck": true, "effect": "Independent reception choice for the presented gift; actual location, custody and consent are checked by the engine."})
	return result

class _VisibleCosts extends RefCounted:
	var economic_contracts: Dictionary
	func _init(visible: Dictionary) -> void:
		# Price the observed version, not hidden current-world changes. The real
		# dispatcher rechecks the world on adoption; no effects execute here.
		economic_contracts = visible

func expression_context(state, _data: Dictionary, actor_id: String, viewer_id: String) -> Dictionary:
	if not state.character_states.has(actor_id) or not state.character_states.has(viewer_id): return {}
	var fields := {}
	var observer: Dictionary = state.character_knowledge if viewer_id == state.player_character_id else state.observer_character_knowledge.get(viewer_id, {})
	for field in observer.get(actor_id, {}): fields[field] = Knowledge.new().get_observer_field(state, viewer_id, actor_id, field)
	var memories: Array = Memory.new().get_relevant_memories(state, actor_id, [], 5, viewer_id)
	return {"speaker_id": actor_id, "viewer_id": viewer_id, "known_fields": fields, "shared_memories": memories.map(func(memory): return {"id": memory.id, "summary": memory.get("summary", ""), "day": memory.day})}
