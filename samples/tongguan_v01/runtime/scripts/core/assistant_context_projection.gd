extends RefCounted

const Family = preload("res://scripts/core/family_office_rules.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Assistant = preload("res://scripts/core/player_assistant_service.gd")
const Agenda = preload("res://scripts/core/character_agenda_service.gd")

# Read-only, explicit player knowledge. Never pass GameState or character truth to AIClient.
static func project(context) -> Dictionary:
	var state = context.state
	var player := str(state.player_character_id)
	var organization := str(state.flags.get("player_organization_id", ""))
	var location := str(state.character_states[player].get("location_id", ""))
	var binding := Assistant.project(state, context.scenario_data)
	var result := {"projection_kind": "assistant_player_visible_v1", "current_day": int(state.current_day), "player": {"character_id": player, "name": str(state.character_states[player].name), "organization_id": organization, "location_id": location}, "assistant": {"character_id": str(binding.get("assistant_id", "")), "name": str(binding.get("name", "空缺")), "status": str(binding.get("status", "vacant")), "binding_revision": int(binding.get("binding_revision", 0))}, "accounts": [], "offices": [], "assets": [], "tasks": [], "applications": []}
	result["local_people"] = preload("res://scripts/core/managed_item_service.gd").local_people(state, location)
	result["official_initiatives"] = preload("res://scripts/core/official_initiative_service.gd").project(state, player)
	result["local_fiscal"] = preload("res://scripts/core/local_fiscal_policy_service.gd").project(state, player)
	result["grain_depots"] = preload("res://scripts/core/regional_grain_service.gd").known_depots(state, player)
	result["grain_orders"] = preload("res://scripts/core/regional_grain_service.gd").project(state, player)
	result["marriages"] = preload("res://scripts/core/marriage_service.gd").project(state, player)
	result["official_journeys"] = preload("res://scripts/core/official_journey_service.gd").project(state, player)
	result["searches"] = []
	result["farmland"] = preload("res://scripts/core/farmland_service.gd").project(state, player)
	result["public_works"] = preload("res://scripts/core/public_works_service.gd").project(state, player)
	result["fiscal_cases"] = preload("res://scripts/core/regional_fiscal_service.gd").project(state, player)
	result["schools"] = preload("res://scripts/core/education_service.gd").project(state, player)
	result["official_offices"] = preload("res://scripts/core/official_office_actions.gd").project(state, context.scenario_data, player)
	result["official_people"] = []
	var public_official_ids: Array = []
	for office in result.official_offices:
		if office.holder_id != "" and not public_official_ids.has(office.holder_id): public_official_ids.append(office.holder_id)
		for candidate in office.candidates:
			if not public_official_ids.has(candidate.character_id): public_official_ids.append(candidate.character_id)
	for id in public_official_ids:
		result.official_people.append({"character_id": id, "name": str(state.character_states.get(id, {}).get("name", id))})
	for account in state.resource_accounts.values():
		if account.unit_id != "cash_unit": continue
		if Accounts.new().can_operate(state, account.account_id, player):
			var name := "家族主账户" if account.owner_ref.entity_kind == "clan" else "个人私款"
			if account.owner_ref.entity_kind == "household": name = "支户公账"
			if account.owner_ref.entity_kind == "office": name = "州库公款" if account.storage_ref.storage_kind == "depot" else "国帑"
			for asset in state.management_assets.values():
				if asset.get("asset_kind") == "pawnshop" and asset.get("account_id") == account.account_id: name = str(asset.name) + "营运款"
			result.accounts.append({"account_id": account.account_id, "name": name, "unit_id": account.unit_id, "balance": Accounts.new().balance(state, account.account_id), "available": Accounts.new().available(state, account.account_id)})
	for office in state.office_state.values():
		if not Family.authority(state, str(office.office_id), player):
			continue
		var candidates: Array = []
		for character in context.scenario_data.characters:
			var preferences: Dictionary = character.get("employment_preferences", {})
			if not preferences.get("roles", []).has(office.get("role_key")) or state.character_states.get(character.id, {}).get("location_id") != location:
				continue
			var assessed := Family.assess(state, context.scenario_data, office.office_id, character.id)
			candidates.append({"character_id": character.id, "name": character.name, "assessment": assessed.grade, "expressed_conditions": assessed.reason})
		result.offices.append({"office_id": office.office_id, "name": office.name, "role_key": office.role_key, "holder_id": office.holder_id, "wage": int(office.remuneration_terms.amount), "period_days": int(office.remuneration_terms.period_days), "account_id": office.remuneration_terms.account_id, "candidates": candidates})
	for asset in state.management_assets.values():
		var owned: bool = asset.owner_ref.entity_id in [organization, player]
		var public_offer: bool = asset.location_id == location and (asset.has("rental_offer") or asset.has("pledge_offer") or asset.get("offer_visibility") == "public")
		if not owned and not public_offer:
			continue
		var item := {"asset_id": asset.asset_id, "asset_kind": asset.asset_kind, "name": asset.name, "status": asset.status, "location_id": asset.location_id}
		if asset.asset_kind == "movable" and asset.owner_ref == {"entity_kind": "character", "entity_id": player}:
			var physical: Dictionary = preload("res://scripts/core/managed_item_service.gd").project(state, asset.asset_id, player)
			for key in ["actions", "can_dispose", "restriction", "equipped", "custodian_ref"]: item[key] = physical[key]
		if asset.asset_kind == "building" and public_offer:
			item["proposed_shop_id"] = "pawnshop:%s:%s" % [organization, asset.asset_id]
			for key in ["rental_offer", "setup_offer", "maintenance_offer"]:
				var offer: Dictionary = asset.get(key, {})
				item[key] = _pick(offer, ["amount", "period_days", "duration_days", "landlord_id", "supplier_id", "payee_account_id", "valid_until_day"])
		elif asset.asset_kind == "pawnshop" and owned:
			for key in ["building_id", "account_id", "office_id", "setup_contract_id"]:
				item[key] = asset.get(key, "")
			var contracts: Array = []
			for contract in state.economic_contracts.values():
				if contract.get("shop_id") == asset.asset_id:
					contracts.append(_pick(contract, ["contract_id", "contract_kind", "status", "borrower_id", "principal", "remaining_debt", "due_day", "disposal_day", "arrears"]))
			item["contracts"] = contracts
		elif asset.has("pledge_offer") and public_offer:
			item["pledge_offer"] = _pick(asset.pledge_offer, ["borrower_id", "principal", "fee", "duration_days", "valuation", "valuation_basis"])
		elif asset.asset_kind == "workshop" and public_offer:
			item["supplier_id"] = asset.supplier_id
			item["recipes"] = []
			for recipe_id in asset.recipes:
				var recipe: Dictionary = asset.recipes[recipe_id]
				item.recipes.append({"recipe_id": recipe_id, "name": recipe.output_definition.name, "price": recipe.price, "duration_days": recipe.duration_days, "source_work_id": recipe.source_work_id})
		result.assets.append(item)
	for order in state.economic_contracts.values():
		if order.get("contract_kind") == "production" and order.get("customer_id") == player:
			result.assets.append(_pick(order, ["contract_id", "workshop_id", "recipe_id", "status", "work_days", "due_day", "output_id", "blocked_reason"]))
		elif order.get("contract_kind") == "character_search" and order.get("principal_id") == player:
			var search := _pick(order, ["contract_id", "executor_id", "location_id", "status", "work_days", "duration_days", "candidate_id", "blocked_reason"])
			search["target_role"] = str(order.original_plan.target_role)
			result.searches.append(search)
	for task in state.active_tasks + state.completed_tasks:
		if task.get("task_kind") != "management" or not preload("res://scripts/core/clan_succession_service.gd").controls_task(state, task, player):
			continue
		var row := _pick(task, ["task_id", "name", "status", "plan_revision", "authorization_version", "executor_id", "parent_task_id"])
		row["feedback"] = task.get("visible_feedback", []).duplicate()
		row["segment_progress"] = preload("res://scripts/core/management_plan_segments.gd").progress(task)
		row["steps"] = []
		for step in task.steps:
			row.steps.append({"step_id": step.step_id, "action_kind": step.action_kind, "status": step.status, "receipt_ref": step.receipt_ref, "target_refs": step.target_refs.duplicate(), "parameters": step.parameters.duplicate(true), "depends_on": step.depends_on.duplicate()})
		var auth: Dictionary = state.action_authorizations.get(task.authorization_id, {})
		row["budgets"] = []
		for account in auth.get("reservation_refs", {}):
			var reserved: Dictionary = state.resource_reservations[auth.reservation_refs[account]]
			var spent := 0
			var seen_payments: Array = []
			for receipt in state.action_receipts.values():
				if receipt.get("authorization_id") != task.authorization_id: continue
				for payment in receipt.journal_refs:
					var entry: Dictionary = state.resource_journal.get(payment, {})
					if entry.get("source_account_id") == account and not seen_payments.has(payment):
						spent += int(entry.amount)
						seen_payments.append(payment)
			row.budgets.append({"account_id": account, "limit": reserved.amount, "spent": spent, "unused": reserved.remaining_amount})
		result.tasks.append(row)
	for application in Agenda.new().livelihood_projection(state, player):
		result.applications.append(_pick(application, ["character_id", "name", "office_id", "requested_wage", "status", "public_expression"]))
	return result

static func _pick(record: Dictionary, keys: Array) -> Dictionary:
	var result := {}
	for key in keys:
		if record.has(key) and typeof(record[key]) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL]:
			result[key] = record[key]
	return result
