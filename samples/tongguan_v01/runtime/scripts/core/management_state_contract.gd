extends RefCounted

const MAX_AMOUNT := 1000000000
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")
const Commodities = preload("res://scripts/core/resource_commodity_definitions.gd")

static func amount(value: Variant, positive: bool = false) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= (1 if positive else 0) and value <= MAX_AMOUNT

static func validate(raw: Dictionary) -> Dictionary:
	if not raw.get("character_states", {}) is Dictionary or not raw.get("depot_states", {}) is Dictionary:
		return fail("invalid character or depot records")
	if raw.get("campaign_id") == "anshi_beta_1_14":
		for field in ["resource_accounts", "resource_reservations", "resource_journal", "economic_contracts", "management_assets", "player_assistant_assignment", "action_authorizations", "action_receipts", "player_character_id", "flags"]:
			if not raw.has(field):
				return fail("current save is missing " + field)
		if not raw.flags is Dictionary or not raw.character_states.has(raw.player_character_id):
			return fail("current save references missing player")
		var census_valid: Dictionary = preload("res://scripts/core/regional_demography.gd").validate(raw.flags.get("regional_census"))
		if not census_valid.ok: return census_valid
		var baselines_valid: Dictionary=preload("res://scripts/core/regional_economic_baselines.gd").validate_snapshot(raw)
		if not baselines_valid.ok: return baselines_valid
		for field in ["start_profile_id", "player_organization_id", "player_location_id"]:
			if not raw.flags.get(field) is String or str(raw.flags[field]).is_empty():
				return fail("current save is missing " + field)
		if not raw.get("resources") is Dictionary or not raw.resource_accounts is Dictionary or raw.resources.has("silver") or not raw.resource_accounts.has(str(raw.player_character_id) + "_cash") or not raw.resource_accounts.has("court_treasury"):
			return fail("current save lost a cash account or retains duplicate personal cash")
	for field in ["resource_accounts", "resource_reservations", "resource_journal", "economic_contracts", "management_assets", "player_assistant_assignment", "action_authorizations", "action_receipts"]:
		if not raw.get(field, {}) is Dictionary:
			return fail("invalid " + field)
	var dialogue_valid := _validate_pending_production(raw)
	if not dialogue_valid.ok: return dialogue_valid
	var advice_valid := _validate_assistant_advice(raw)
	if not advice_valid.ok: return advice_valid
	var conversation_valid := _validate_assistant_conversation(raw)
	if not conversation_valid.ok: return conversation_valid
	var characters: Dictionary = raw.get("character_states", {})
	if raw.get("campaign_id")=="anshi_beta_1_14":
		for character in characters.values():
			if not character is Dictionary:return fail("invalid original character condition record")
			var personnel_valid: Dictionary=preload("res://scripts/core/business_personnel_conditions.gd").validate_character(character)
			if not personnel_valid.ok:return personnel_valid
	if characters.size() > 256:
		return fail("character capacity exceeds 256; save refused without truncation")
	var accounts: Dictionary = raw.get("resource_accounts", {})
	var depots: Dictionary = raw.get("depot_states", {})
	for key in accounts:
		var account: Variant = accounts[key]
		if not account is Dictionary or account.get("account_id") != key:
			return fail("invalid account identity: " + str(key))
		var owner: Variant = account.get("owner_ref")
		var storage: Variant = account.get("storage_ref")
		if not owner is Dictionary or not storage is Dictionary or storage.get("storage_kind") not in ["depot", "resource_pool"]:
			return fail("invalid account owner/storage: " + str(key))
		if storage.storage_kind == "depot":
			if not depots.get(storage.get("storage_id")) is Dictionary:
				return fail("missing account storage: " + str(key))
			var depot: Dictionary = depots[storage.storage_id]
			if not depot.get("stock") is Dictionary:
				return fail("invalid account stock container: " + str(key))
			if owner.get("entity_kind") == "character":
				if not characters.has(owner.get("entity_id")) or depot.get("owner_character_id") != owner.entity_id:
					return fail("missing or inconsistent account owner: " + str(key))
			elif owner.get("entity_kind") == "clan":
				if depot.get("owner_organization_id") != owner.get("entity_id") or not characters.values().any(func(c): return c is Dictionary and c.get("clan_id") == owner.get("entity_id")):
					return fail("missing or inconsistent clan owner: " + str(key))
			elif owner.get("entity_kind") == "household":
				var households: Variant = raw.get("flags", {}).get("family_households", {})
				if not households is Dictionary: return fail("支户名册类型错误")
				var household: Variant = households.get(owner.get("entity_id"), {})
				if not household is Dictionary or household.is_empty() or depot.get("owner_organization_id") != owner.get("entity_id") or account.get("operator_refs") != [{"entity_kind": "character", "entity_id": household.get("head_id")}]: return fail("支户账户缺少实际立户或经办权")
			elif owner.get("entity_kind") == "office":
				var office: Dictionary = raw.get("office_state", {}).get(owner.get("entity_id"), {})
				var holder := str(office.get("holder_id", ""))
				var operators: Array = [{"entity_kind": "character", "entity_id": holder}] if office.get("status") == "appointed" and not holder.is_empty() else []
				if office.get("office_kind") != "regional" or depot.get("owner_office_id") != owner.get("entity_id") or depot.get("owner_organization_id") != office.get("organization_id") or account.get("organization_id") != office.get("organization_id") or account.get("operator_refs") != operators: return fail("regional public account lost current office authority")
			else:
				return fail("unsupported account owner: " + str(key))
			if Commodities.depot_unit(str(storage.get("resource_key", ""))).is_empty(): return fail("invalid registered depot commodity")
		else:
			if not raw.get("resources") is Dictionary or storage.get("storage_id") != "resources" or storage.get("resource_key") != "treasury" or owner.get("entity_kind") != "office" or not raw.get("office_state", {}).has(owner.get("entity_id")) or not raw.get("local_node_state", {}).has(account.get("location_id")):
				return fail("invalid public pool authority or location: " + str(key))
		var expected_unit := Commodities.depot_unit(str(storage.get("resource_key", ""))) if storage.storage_kind == "depot" else "cash_unit"
		if account.get("resource_key") != storage.get("resource_key") or account.get("unit_id") != expected_unit:
			return fail("invalid account unit: " + str(key))
		if not amount(Storage.raw_balance(raw, storage)):
			return fail("invalid account stock: " + str(key))
		if not account.get("operator_refs") is Array:
			return fail("invalid account operators: " + str(key))
		for operator in account.operator_refs:
			if not operator is Dictionary or operator.get("entity_kind") != "character" or not characters.has(operator.get("entity_id")):
				return fail("missing account operator: " + str(key))
	if raw.get("campaign_id") == "anshi_beta_1_14":
		if not accounts.values().any(func(account): return account.unit_id == "ration_unit"):
			return fail("current save is missing household food sources; older development snapshots require explicit migration")
		var personal: Dictionary = accounts[str(raw.player_character_id) + "_cash"]
		if personal.owner_ref != {"entity_kind": "character", "entity_id": raw.player_character_id} or personal.storage_ref.storage_kind != "depot":
			return fail("player cash account lost personal ownership")
		if accounts.court_treasury.storage_ref != {"storage_kind": "resource_pool", "storage_id": "resources", "resource_key": "treasury"}:
			return fail("public account no longer refers to original treasury")
		for account in accounts.values():
			if account.storage_ref == accounts.court_treasury.storage_ref:
				for field in ["owner_ref", "location_id", "operator_refs", "unit_id"]:
					if account.get(field) != accounts.court_treasury.get(field):
						return fail("public pool alias cannot change ownership or payment authority")
	var reserved := {}
	for key in raw.get("resource_reservations", {}):
		var reservation: Variant = raw.resource_reservations[key]
		if not reservation is Dictionary or reservation.get("reservation_id") != key or not accounts.has(reservation.get("account_id")):
			return fail("invalid reservation identity/account: " + str(key))
		if not amount(reservation.get("amount"), true) or not amount(reservation.get("remaining_amount")) or reservation.remaining_amount > reservation.amount:
			return fail("invalid reservation amount: " + str(key))
		if str(reservation.get("task_id", "")).is_empty() or reservation.get("status") not in ["active", "consumed", "released"]:
			return fail("invalid reservation status/task: " + str(key))
		if reservation.status != "active" and reservation.remaining_amount != 0:
			return fail("inactive reservation retains funds: " + str(key))
		var storage: Dictionary = accounts[reservation.account_id].storage_ref
		var source := Storage.key(storage)
		reserved[source] = int(reserved.get(source, 0)) + int(reservation.remaining_amount)
		if reserved[source] > Storage.balance(raw, storage):
			return fail("reservations exceed stock: " + source)
	if accounts.has("court_treasury"):
		for order in raw.get("governance_state", {}).get("orders", {}).values():
			if not order is Dictionary or not order.get("resources", {}).has("treasury") or order.get("stage") == "draft": continue
			var reservation_id := "governance:" + str(order.get("order_id", "")) + ":treasury"
			var held: Dictionary = raw.resource_reservations.get(reservation_id, {})
			if held.get("account_id") != "court_treasury" or held.get("task_id") != order.get("order_id") or held.get("amount") != order.resources.treasury:
				return fail("governance order lost its public cash reservation: " + str(order.get("order_id")))
			var spent := 0
			for entry in raw.resource_journal.values():
				if entry is Dictionary and entry.get("reservation_id") == reservation_id:
					if entry.get("entry_kind") != "rule_consumption" or entry.get("source_account_id") != "court_treasury" or entry.get("task_id") != order.get("order_id") or not amount(entry.get("amount"), true):
						return fail("invalid governance budget payment")
					spent += int(entry.amount)
			if spent > int(held.amount): return fail("governance payment exceeds budget")
			if order.get("stage") in ["closed", "withdrawn"]:
				if held.status == "active": return fail("terminal governance order retains live budget")
			else:
				if held.status != "active" or spent + int(held.remaining_amount) != int(held.amount): return fail("active governance budget is inconsistent")
	for key in raw.get("resource_journal", {}):
		var entry: Variant = raw.resource_journal[key]
		if not entry is Dictionary or entry.get("entry_id") != key or not amount(entry.get("amount"), true):
			return fail("invalid journal entry: " + str(key))
		if entry.get("entry_kind") == "rule_consumption":
			if not accounts.has(entry.get("source_account_id")) or entry.get("source_ref") != accounts.get(entry.get("source_account_id"), {}).get("owner_ref") or not entry.get("destination_ref") is Dictionary or entry.destination_ref.get("entity_kind") != "rule" or not str(entry.get("reason_ref", "")).begins_with("rule:") or entry.destination_ref.get("rule_id") != entry.reason_ref or entry.get("execution_id") != key or entry.get("unit_id") != accounts.get(entry.get("source_account_id"), {}).get("unit_id") or not amount(entry.get("day")):
				return fail("invalid rule consumption source: " + str(key))
			continue
		if not accounts.has(entry.get("destination_account_id")) or entry.get("unit_id") != accounts.get(entry.get("destination_account_id"), {}).get("unit_id") or str(entry.get("execution_id", "")).is_empty() or str(entry.get("reason_ref", "")).is_empty():
			return fail("missing journal reference: " + str(key))
		if entry.get("entry_kind") == "initial_grant":
			if not entry.get("source_ref") is Dictionary or not str(entry.source_ref.get("rule_id", "")).begins_with("scenario:") or entry.get("destination_ref") != accounts[entry.destination_account_id].owner_ref:
				return fail("invalid initial source: " + str(key))
		elif entry.get("entry_kind") == "rule_income":
			if not entry.get("source_ref") is Dictionary or entry.source_ref.get("entity_kind") != "rule" or not str(entry.get("reason_ref", "")).begins_with("rule:") or entry.source_ref.get("rule_id") != entry.reason_ref or entry.get("destination_ref") != accounts[entry.destination_account_id].owner_ref or not amount(entry.get("day")):
				return fail("invalid rule income source: " + str(key))
		elif entry.get("entry_kind") != "transfer" or not accounts.has(entry.get("source_account_id")):
			return fail("invalid transfer source: " + str(key))
		elif entry.unit_id != accounts[entry.source_account_id].unit_id or entry.get("source_ref") != accounts[entry.source_account_id].owner_ref or entry.get("destination_ref") != accounts[entry.destination_account_id].owner_ref:
			return fail("transfer changes actual commodity or owner: " + str(key))
	var commodity_balances := _validate_trade_commodity_balances(raw)
	if not commodity_balances.ok: return commodity_balances
	var offices: Dictionary = raw.get("office_state", {})
	if raw.get("campaign_id")=="anshi_beta_1_14":
		for character in characters.values():
			var stats: Variant = character.get("stats",{})
			if not stats is Dictionary: return fail("人物经营能力必须是数值表")
			for field in ["finance","governance","diplomacy"]:
				if stats.has(field) and (not amount(stats[field]) or int(stats[field])>100): return fail("人物经营能力超出 0—100 或并非整数")
	var terms: Dictionary = raw.get("office_terms", {})
	if raw.get("campaign_id") == "anshi_beta_1_14":
		var authority_valid: Dictionary = preload("res://scripts/core/office_appointment_authority.gd").validate(offices, characters)
		if not authority_valid.ok: return authority_valid
	for id in offices:
		var office: Variant = offices[id]
		if not office is Dictionary:
			return fail("invalid office record: " + str(id))
		if office.get("office_kind") != "family":
			continue
		var pay: Variant = office.get("remuneration_terms")
		var authority: Variant = office.get("authority_ref")
		var scope: Variant = office.get("scope_ref")
		if office.get("office_id") != id or office.get("role_key") not in ["steward", "estate_head", "shopkeeper", "guard_captain"]:
			return fail("invalid family office identity: " + str(id))
		var schedule: Variant = office.get("work_schedule")
		if not schedule is Dictionary or not schedule.get("days") is Array or schedule.days.is_empty() or not schedule.get("duty_work_kinds") is Array or not str(schedule.get("source_id", "")).begins_with("scenario:"): return fail("family office lost actual duty schedule")
		var seen_days: Array = []
		for day in schedule.days:
			if not amount(day) or int(day) > 6 or seen_days.has(int(day)): return fail("invalid or duplicate office duty day")
			seen_days.append(int(day))
		for kind in schedule.duty_work_kinds:
			if kind not in ["management", "character_search", "pawnshop"]: return fail("office duty has unsupported work kind")
		for other in offices.values():
			if not other is Dictionary: return fail("invalid concurrent office record")
			if office.get("holder_id", "") != "" and other.get("office_kind") == "family" and other.get("office_id") != id and other.get("holder_id") == office.holder_id and preload("res://scripts/core/character_workload_service.gd").overlaps(office, other): return fail("concurrent family offices have overlapping schedules")
		if not pay is Dictionary or not amount(pay.get("amount"), true) or not amount(pay.get("period_days"), true) or pay.get("unit_id") != "cash_unit" or not accounts.has(pay.get("account_id")):
			return fail("invalid family wage offer: " + str(id))
		if accounts[pay.account_id].unit_id != pay.unit_id:
			return fail("family wage currency differs from actual account")
		if not authority is Dictionary or authority.get("entity_kind") != "account_operator" or authority.get("entity_id") != pay.account_id or accounts[pay.account_id].owner_ref.entity_id != office.get("organization_id"):
			return fail("invalid family office authority: " + str(id))
		if not scope is Dictionary or not raw.get("local_node_state", {}).has(scope.get("entity_id")):
			return fail("missing family office location: " + str(id))
		if office.get("holder_id") != "" and not characters.has(office.get("holder_id")):
			return fail("missing family office holder: " + str(id))
		if office.has("recruitment_notice"):
			var notice: Variant = office.recruitment_notice
			if not notice is Dictionary or notice.get("visibility") != "public" or not raw.get("local_node_state", {}).has(notice.get("location_id")) or not str(notice.get("source_id", "")).begins_with("scenario:"):
				return fail("invalid recruitment notice: " + str(id))
	for id in raw.get("economic_contracts", {}):
		var contract: Variant = raw.economic_contracts[id]
		if contract is Dictionary and contract.get("contract_kind") == "gift_delivery":
			if contract.get("contract_id") != id: return fail("invalid gift delivery identity")
			var gift_valid: Dictionary = load("res://scripts/core/gift_delivery_service.gd").validate(raw, contract)
			if not gift_valid.ok: return gift_valid
			continue
		if contract is Dictionary and contract.get("contract_kind") == "social_agreement":
			if contract.get("contract_id") != id: return fail("social agreement identity mismatch")
			var social_valid: Dictionary = load("res://scripts/core/social_agreement_service.gd").validate(raw, contract)
			if not social_valid.ok: return social_valid
			continue
		if not contract is Dictionary or contract.get("contract_id") != id or contract.get("contract_kind") not in ["employment", "lease", "setup", "maintenance", "pawn_loan", "production", "character_search", "food_purchase", "public_work", "cultivation", "public_cash_liability", "school_teaching", "school_enrollment", "school_assessment", "school_candidacy", "school_supply", "school_living_aid", "school_exam_journey", "official_journey", "local_levy", "official_initiative", "marriage", "personal_estate", "family_partition", "land_sale", "land_share_sale", "land_lease", "estate_improvement", "estate_demolition", "estate_construction", "retail_trade", "manufacturing_batch", "manufacturing_sale", "managed_cultivation", "farm_sale", "business_month", "business_profit_policy", "business_profit_distribution", "business_audit", "business_coordination", "estate_property_sale", "estate_operating_right"]:
			return fail("invalid economic contract: " + str(id))
		if contract.contract_kind != "employment":
			continue
		if contract.get("status") not in ["active", "terminated", "ended_unpaid"] or not amount(contract.get("terms_version"), true) or not amount(contract.get("arrears")) or not amount(contract.get("next_due_day")):
			return fail("invalid employment status/amount: " + str(id))
		if not characters.has(contract.get("employee_id")) or not offices.has(contract.get("office_id")) or not terms.has(contract.get("term_id")):
			return fail("missing employment party/office/term: " + str(id))
		var office: Dictionary = offices[contract.office_id]
		var term: Dictionary = terms[contract.term_id]
		if office.get("office_kind") != "family" or contract.get("organization_id") != office.get("organization_id") or contract.get("party_refs") != [contract.organization_id, contract.employee_id] or term.get("office_id") != contract.office_id or term.get("holder_id") != contract.employee_id or term.get("contract_id") != id:
			return fail("inconsistent employment parties or term: " + str(id))
		var remuneration: Variant = contract.get("remuneration_terms")
		if not remuneration is Dictionary or not amount(remuneration.get("amount"), true) or not amount(remuneration.get("period_days"), true) or not accounts.has(remuneration.get("account_id")):
			return fail("invalid employment remuneration: " + str(id))
		if remuneration.get("unit_id") != "cash_unit" or accounts[remuneration.account_id].unit_id != "cash_unit" or accounts[remuneration.account_id].owner_ref.entity_id != contract.organization_id:
			return fail("invalid employment payment source: " + str(id))
		if not contract.get("execution_refs") is Array:
			return fail("invalid employment payment receipts: " + str(id))
		for receipt in contract.execution_refs:
			if not raw.get("resource_journal", {}).has(receipt):
				return fail("missing employment payment receipt: " + str(id))
		if contract.status == "active" and offices[contract.office_id].get("holder_id") != contract.employee_id:
			return fail("employment holder mismatch: " + str(id))
		if (contract.status == "active") != (int(term.get("end_day", 0)) < 0):
			return fail("employment term status mismatch: " + str(id))
	for office in offices.values():
		if office.get("office_kind") == "family" and office.get("holder_id") != "":
			var active: Array = raw.get("economic_contracts", {}).values().filter(func(c): return c.get("office_id") == office.office_id and c.get("status") == "active")
			if active.size() != 1:
				return fail("family office requires exactly one active employment contract: " + str(office.office_id))
	var binding: Dictionary = raw.get("player_assistant_assignment", {})
	if not binding.is_empty():
		if binding.get("principal_id") != raw.get("player_character_id") or not characters.has(binding.get("principal_id")) or not amount(binding.get("binding_revision"), true) or binding.get("status") not in ["active", "vacant", "unavailable"]:
			return fail("invalid player assistant binding")
		if binding.status != "vacant" and not characters.has(binding.get("assistant_id")):
			return fail("assistant references missing character")
		if binding.status == "vacant" and binding.get("assistant_id") != "":
			return fail("vacant assistant binding retains an assignee")
		if str(binding.get("source_office_id", "")) != "" and not offices.has(binding.source_office_id):
			return fail("assistant references missing source office")
	var assets := _validate_assets(raw)
	if not assets.get("ok", false):
		return assets
	var business_staff: Dictionary = load("res://scripts/core/business_staff_service.gd").validate(raw)
	if not business_staff.ok: return business_staff
	var business_offices: Dictionary = load("res://scripts/core/business_manager_office.gd").validate(raw)
	if not business_offices.ok: return business_offices
	var lands: Dictionary = load("res://scripts/core/land_property_service.gd").validate(raw)
	if not lands.ok: return lands
	var retail: Dictionary = load("res://scripts/core/retail_trading_service.gd").validate(raw)
	if not retail.ok: return retail
	var manufacturing: Dictionary = load("res://scripts/core/manufacturing_business_service.gd").validate(raw)
	if not manufacturing.ok: return manufacturing
	var modeled: Dictionary = load("res://scripts/core/modeled_business_service.gd").validate(raw)
	if not modeled.ok: return modeled
	var farming: Dictionary = load("res://scripts/core/managed_farming_service.gd").validate(raw)
	if not farming.ok: return farming
	var business_reports: Dictionary = load("res://scripts/core/business_report_delivery.gd").validate(raw)
	if not business_reports.ok: return business_reports
	var payroll: Dictionary=load("res://scripts/core/business_payroll_service.gd").validate(raw)
	if not payroll.ok:return payroll
	var wage_amendments: Dictionary=load("res://scripts/core/business_wage_service.gd").validate(raw)
	if not wage_amendments.ok:return wage_amendments
	var profit_distributions: Dictionary=load("res://scripts/core/business_profit_sharing_service.gd").validate(raw)
	if not profit_distributions.ok:return profit_distributions
	var reviews: Dictionary=load("res://scripts/core/business_review_service.gd").validate(raw)
	if not reviews.ok:return reviews
	var properties: Dictionary=load("res://scripts/core/estate_property_transaction_service.gd").validate(raw)
	if not properties.ok:return properties
	var land_leases: Dictionary=load("res://scripts/core/land_lease_service.gd").validate(raw)
	if not land_leases.ok:return land_leases
	var construction: Dictionary = load("res://scripts/core/estate_construction_service.gd").validate(raw)
	var lifecycle: Dictionary=load("res://scripts/core/estate_lifecycle_service.gd").validate(raw)
	if not lifecycle.ok:return lifecycle
	if not construction.ok: return construction
	var goals := _validate_life_goals(raw)
	if not goals.get("ok", false):
		return goals
	var execution := _validate_execution(raw)
	if not execution.ok: return execution
	var official: Dictionary = load("res://scripts/core/official_office_actions.gd").validate(raw)
	if not official.get("ok", false): return official
	var regional: Dictionary = load("res://scripts/core/regional_office_rules.gd").validate(raw)
	if not regional.get("ok", false): return regional
	var central: Dictionary = load("res://scripts/core/central_office_rules.gd").validate(raw)
	if not central.get("ok", false): return central
	var works_valid: Dictionary = load("res://scripts/core/public_works_service.gd").validate(raw)
	if not works_valid.ok: return works_valid
	var crops_valid: Dictionary = load("res://scripts/core/farmland_service.gd").validate(raw)
	if not crops_valid.ok: return crops_valid
	var player_succession_valid: Dictionary = load("res://scripts/core/player_succession_service.gd").validate(raw)
	if not player_succession_valid.ok: return player_succession_valid
	var partition_valid: Dictionary = load("res://scripts/core/family_partition_service.gd").validate(raw)
	if not partition_valid.ok: return partition_valid
	var estate_valid: Dictionary = load("res://scripts/core/personal_estate_service.gd").validate(raw)
	if not estate_valid.ok: return estate_valid
	var succession_valid: Dictionary = load("res://scripts/core/clan_succession_service.gd").validate(raw)
	if not succession_valid.ok: return succession_valid
	var marriage_valid: Dictionary = load("res://scripts/core/marriage_service.gd").validate(raw)
	if not marriage_valid.ok: return marriage_valid
	var initiatives_valid: Dictionary = load("res://scripts/core/official_initiative_service.gd").validate(raw)
	if not initiatives_valid.ok: return initiatives_valid
	var local_fiscal_valid: Dictionary = load("res://scripts/core/local_fiscal_policy_service.gd").validate(raw)
	if not local_fiscal_valid.ok: return local_fiscal_valid
	var fiscal_valid: Dictionary = load("res://scripts/core/regional_fiscal_service.gd").validate(raw)
	if not fiscal_valid.ok: return fiscal_valid
	var education_valid: Dictionary = load("res://scripts/core/education_service.gd").validate(raw)
	if not education_valid.ok: return education_valid
	var supply_valid: Dictionary = load("res://scripts/core/school_supply_service.gd").validate(raw)
	if not supply_valid.ok: return supply_valid
	var journey_valid: Dictionary = load("res://scripts/core/exam_journey_service.gd").validate(raw)
	if not journey_valid.ok: return journey_valid
	var envoy_valid: Dictionary = load("res://scripts/core/official_journey_service.gd").validate(raw)
	if not envoy_valid.ok: return envoy_valid
	var military_grain_valid: Dictionary = load("res://scripts/core/military_grain_service.gd").validate(raw)
	if not military_grain_valid.ok: return military_grain_valid
	var grain_valid: Dictionary = load("res://scripts/core/regional_grain_service.gd").validate(raw)
	if not grain_valid.ok: return grain_valid
	var aid_valid: Dictionary = load("res://scripts/core/school_living_aid_service.gd").validate(raw)
	if not aid_valid.ok: return aid_valid
	var assessment_valid: Dictionary = load("res://scripts/core/school_assessment_service.gd").validate(raw)
	if not assessment_valid.ok: return assessment_valid
	return preload("res://scripts/core/character_workload_service.gd").validate(raw)

static func _validate_trade_commodity_balances(raw: Dictionary) -> Dictionary:
	var accounts: Dictionary = raw.get("resource_accounts", {})
	var totals := {}
	var references := {}
	for account in accounts.values():
		if not Commodities.initial_trade_commodity(str(account.get("resource_key", ""))): continue
		var key := Storage.key(account.storage_ref)
		totals[key] = 0
		references[key] = account.storage_ref
	for depot_id in raw.get("depot_states", {}):
		var depot: Variant = raw.depot_states[depot_id]
		if not depot is Dictionary or not depot.get("stock") is Dictionary: continue
		for commodity in depot.stock:
			if Commodities.initial_trade_commodity(str(commodity)) and not totals.has(Storage.key({"storage_kind":"depot", "storage_id":depot_id, "resource_key":commodity})):
				return fail("商品库存缺少实际归属账户")
	for entry in raw.get("resource_journal", {}).values():
		for field in ["source_account_id", "destination_account_id"]:
			var account: Dictionary = accounts.get(entry.get(field, ""), {})
			if not Commodities.initial_trade_commodity(str(account.get("resource_key", ""))): continue
			var key := Storage.key(account.storage_ref)
			totals[key] += int(entry.amount) * (-1 if field == "source_account_id" else 1)
	for key in totals:
		if not amount(totals[key]) or totals[key] != Storage.raw_balance(raw, references[key]): return fail("商品库存与实际来源、交付和消耗流水不符")
	return {"ok":true}

static func _validate_life_goals(raw: Dictionary) -> Dictionary:
	var characters: Dictionary = raw.get("character_states", {})
	var offices: Dictionary = raw.get("office_state", {})
	var contracts: Dictionary = raw.get("economic_contracts", {})
	for entry in raw.get("resource_journal", {}).values():
		if entry.get("entry_kind") == "rule_consumption" and entry.get("reason_ref") == "rule:household_rations":
			var owner_id := str(entry.get("source_ref", {}).get("entity_id", ""))
			var person: Variant = characters.get(owner_id, {})
			if not person is Dictionary or not person.get("life_goal") is Dictionary or not person.life_goal.get("subsistence") is Dictionary or not person.life_goal.subsistence.get("consumption_refs") is Array or not person.life_goal.subsistence.consumption_refs.has(entry.entry_id):
				return fail("household consumption lost its settlement cursor or history")
	for id in characters:
		if not characters[id] is Dictionary:
			return fail("invalid character record: " + str(id))
		if not characters[id].has("life_goal"):
			continue
		var goal: Variant = characters[id].life_goal
		if not goal is Dictionary or goal.get("character_id") != id or goal.get("goal_kind") not in ["secure_food", "secure_livelihood", "household_service", "support_family", "build_reputation", "learn_trade"] or goal.get("goal_stage") not in ["seeking", "awaiting_employer", "working_to_build_reserve", "stable", "employed", "tending_fields"]:
			return fail("invalid livelihood goal: " + str(id))
		var food_valid: Dictionary = load("res://scripts/core/household_subsistence_service.gd").validate_household(raw, str(id), goal.get("subsistence"))
		if not food_valid.ok: return food_valid
		for field in ["next_review_day", "last_review_day"]:
			if not amount(goal.get(field)):
				return fail("invalid livelihood review time: " + str(id))
		for field in ["last_input_hash", "public_expression"]:
			if not goal.get(field) is String:
				return fail("invalid livelihood expression/hash: " + str(id))
		for field in ["application", "rejected_offices", "private_priorities"]:
			if not goal.get(field) is Dictionary:
				return fail("invalid livelihood " + field + ": " + str(id))
		for field in ["evidence_refs", "opportunity_refs", "history"]:
			if not goal.get(field) is Array:
				return fail("invalid livelihood " + field + ": " + str(id))
		for ref in goal.evidence_refs:
			if not ref is Dictionary or ref.get("entity_kind") not in ["account", "character"]:
				return fail("invalid livelihood evidence: " + str(id))
			var records: Dictionary = raw.resource_accounts if ref.entity_kind == "account" else characters
			if not records.has(ref.get("entity_id")):
				return fail("missing livelihood evidence: " + str(id))
		for office in goal.opportunity_refs:
			if not offices.has(office):
				return fail("missing livelihood opportunity: " + str(id))
		for office in goal.rejected_offices:
			if not offices.has(office) or not amount(goal.rejected_offices[office]):
				return fail("invalid declined opportunity: " + str(id))
		var application: Dictionary = goal.application
		if not application.is_empty():
			if not offices.has(application.get("office_id")) or not characters.has(application.get("employer_id")) or not amount(application.get("requested_wage"), true) or not amount(application.get("requested_period_days"), true) or application.get("status") not in ["waiting", "hired", "withdrawn", "closed", "expired", "declined"]:
				return fail("invalid employment application: " + str(id))
			if not amount(application.get("applied_day")) or not amount(application.get("response_due_day")) or application.response_due_day < application.applied_day or not application.get("contract_ref") is String:
				return fail("invalid employment application timing/reference: " + str(id))
			if application.status == "hired" and application.contract_ref == "":
				return fail("accepted application lost employment contract: " + str(id))
			var office: Dictionary = offices[application.office_id]
			var operators: Array = raw.resource_accounts.get(office.get("remuneration_terms", {}).get("account_id", ""), {}).get("operator_refs", [])
			if office.get("office_kind") != "family" or (not operators.any(func(operator): return operator.get("entity_id") == application.employer_id) and not load("res://scripts/core/clan_succession_service.gd").had_authority(raw, str(office.get("organization_id", "")), application.employer_id)):
				return fail("application has no employer authority: " + str(id))
			if application.contract_ref != "":
				var contract: Dictionary = contracts.get(application.contract_ref, {})
				if contract.get("contract_kind") != "employment" or contract.get("employee_id") != id or contract.get("office_id") != application.office_id or contract.get("remuneration_terms", {}).get("period_days") != application.requested_period_days:
					return fail("application references missing or unrelated employment: " + str(id))
		for event in goal.history:
			if not event is Dictionary or event.get("kind") not in ["applied", "hired", "declined", "no_response", "resigned_unpaid"] or not offices.has(event.get("office_id")) or not amount(event.get("day")):
				return fail("invalid livelihood history: " + str(id))
			if event.has("contract_ref") and (not contracts.has(event.contract_ref) or contracts[event.contract_ref].get("employee_id") != id):
				return fail("livelihood history lost employment reference: " + str(id))
	return {"ok": true}

static func _validate_assets(raw: Dictionary) -> Dictionary:
	var assets: Dictionary = raw.get("management_assets", {})
	var contracts: Dictionary = raw.get("economic_contracts", {})
	var accounts: Dictionary = raw.get("resource_accounts", {})
	var characters: Dictionary = raw.get("character_states", {})
	if raw.get("campaign_id") == "anshi_beta_1_14":
		if raw.get("flags", {}).get("managed_inventory_initialized") != true or not raw.get("inventory") is Array: return fail("current inventory lost physical asset registry")
		var inventory_ids := {}
		for ref in raw.inventory:
			if not ref is Dictionary or ref.size() != 2 or ref.get("id") != ref.get("asset_ref") or not assets.has(ref.get("asset_ref")) or inventory_ids.has(ref.get("id")): return fail("inventory has missing, duplicated or noncanonical asset reference")
			inventory_ids[ref.id] = true
			var item: Dictionary = assets[ref.asset_ref]
			if item.get("asset_kind") != "movable" or item.get("owner_ref") != {"entity_kind": "character", "entity_id": raw.player_character_id}: return fail("inventory references property the player does not own")
	for id in assets:
		var asset: Variant = assets[id]
		var registered_location: bool = asset is Dictionary and (raw.get("local_node_state", {}).has(asset.get("location_id")) or (asset.get("asset_kind") == "movable" and load("res://scripts/core/gift_delivery_service.gd").custody_valid(raw, asset)))
		if not asset is Dictionary or asset.get("asset_id") != id or asset.get("asset_kind") not in ["land", "estate_building", "building", "movable", "pawnshop", "retail_shop", "manufacturing_shop", "managed_farm", "modeled_business", "workshop", "material_stock", "food_stall", "irrigation_canal", "farmland", "school", "examination_hall"] or not registered_location:
			return fail("invalid asset identity/type/location: " + str(id))
		var owner: Variant = asset.get("owner_ref")
		if not owner is Dictionary or not asset.get("source_ref") is Dictionary or not asset.get("rights") is Array or not asset.get("contract_refs") is Array:
			return fail("asset lost ownership/source/rights: " + str(id))
		if owner.get("entity_kind") == "character":
			if not characters.has(owner.get("entity_id")):
				return fail("asset owner is missing")
		elif owner.get("entity_kind")=="coownership":
			if asset.asset_kind!="land" or owner.get("entity_id")!=asset.asset_id or not asset.get("ownership_shares") is Array:return fail("共有产权须有该地实际份额来源")
		elif owner.get("entity_kind") not in ["clan", "household", "office"] or not accounts.values().any(func(a): return a.owner_ref == owner):
			return fail("asset organization is missing")
		for ref in asset.contract_refs:
			if not contracts.has(ref):
				return fail("asset lost economic contract")
		if asset.source_ref.get("entity_kind") == "contract":
			if not contracts.has(asset.source_ref.get("entity_id")):
				return fail("asset lost acquisition contract")
		elif asset.source_ref.get("entity_kind") != "rule" or not str(asset.source_ref.get("rule_id", "")).begins_with("scenario:"):
			return fail("asset lacks registered source")
		if asset.asset_kind == "food_stall":
			var food_valid: Dictionary = load("res://scripts/core/household_subsistence_service.gd").validate_stall(raw, asset)
			if not food_valid.ok: return food_valid
		elif asset.asset_kind in ["workshop", "material_stock"]:
			var production_valid := _validate_production_asset(asset, raw)
			if not production_valid.ok: return production_valid
		elif asset.asset_kind == "building":
			if asset.get("status") not in ["available", "rented"] or not asset.get("rental_offer") is Dictionary or not asset.get("setup_offer") is Dictionary or not asset.get("maintenance_offer") is Dictionary:
				return fail("building lost status or offers")
			for offer in [asset.rental_offer, asset.setup_offer, asset.maintenance_offer]:
				if not amount(offer.get("amount"), true) or not accounts.has(offer.get("payee_account_id")):
					return fail("invalid building quotation")
			if not characters.has(asset.rental_offer.get("landlord_id")) or asset.owner_ref.entity_id != asset.rental_offer.landlord_id or not amount(asset.rental_offer.get("period_days"), true) or not amount(asset.rental_offer.get("valid_until_day")) or not asset.rental_offer.get("organization_ids") is Array or not characters.has(asset.setup_offer.get("supplier_id")) or not amount(asset.setup_offer.get("duration_days"), true):
				return fail("invalid building offer parties or duration")
			if not characters.has(asset.maintenance_offer.get("supplier_id")) or not amount(asset.maintenance_offer.get("period_days"), true):
				return fail("invalid maintenance supplier or period")
		elif asset.asset_kind in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]:
			var owned: bool = asset.get("premises_kind","") == "owned"
			var separate: bool=asset.get("premises_kind") in ["retired","operating_right"]
			if asset.get("status") not in ["preparing", "open", "closed"] or not assets.has(asset.get("building_id")) or not raw.get("office_state", {}).has(asset.get("office_id")) or not accounts.has(asset.get("account_id")) or (not owned and not separate and not contracts.has(asset.get("lease_id"))):
				return fail("pawnshop lost building/office/account/lease")
			if accounts[asset.account_id].owner_ref != asset.owner_ref:
				return fail("pawnshop ownership or lease mismatch")
			if asset.get("premises_kind")=="retired":
				var retired: Dictionary=contracts.get(asset.get("retirement_contract_id"),{})
				if asset.status!="closed" or retired.get("contract_kind") not in ["estate_property_sale","estate_operating_right"] or not retired.get("source_shops",[]).has(id) or retired.get("building_id")!=asset.building_id:return fail("原经营单位丢失明确场所移交或旧账户")
			elif asset.get("premises_kind")=="operating_right":
				var right: Dictionary=contracts.get(asset.get("operating_right_id"),{})
				if asset.get("lease_id")!="" or right.get("contract_kind")!="estate_operating_right" or right.get("building_id")!=asset.building_id or right.get("operating_shop_id")!=id or right.get("operator_ref")!=asset.owner_ref or assets[asset.building_id].get("asset_kind")!="estate_building":return fail("经营权须保留真实房产、主体和原交割")
			elif owned:
				var building: Dictionary = assets[asset.building_id]
				if asset.get("lease_id") != "" or building.get("asset_kind") != "estate_building" or building.get("industry_kind") != (asset.get("industry_kind") if asset.asset_kind in ["managed_farm","modeled_business"] else "smithy" if asset.asset_kind=="manufacturing_shop" else "cloth_shop" if asset.asset_kind=="retail_shop" else "pawnshop") or building.get("owner_ref") != asset.owner_ref or (building.get("status") != "in_use" and not (building.get("status")=="demolished" and asset.status=="closed")): return fail("owned pawnshop lost actual title or invented a lease")
			elif contracts[asset.lease_id].get("shop_id") != id or contracts[asset.lease_id].get("building_id") != asset.building_id: return fail("pawnshop lease mismatch")
			if asset.get("setup_contract_id", "") != "" and (not contracts.has(asset.setup_contract_id) or contracts[asset.setup_contract_id].get("shop_id") != id):
				return fail("pawnshop lost setup contract")
		elif asset.asset_kind == "movable":
			if asset.get("status") not in ["available", "pledged", "awaiting_delivery"] or not amount(asset.get("condition")) or int(asset.condition) > 100 or not asset.get("custodian_ref") is Dictionary or not asset.get("lien_contract_id") is String:
				return fail("invalid movable condition/custody/lien")
			if asset.status == "pledged":
				var loan: Dictionary = contracts.get(asset.lien_contract_id, {})
				if loan.get("contract_kind") != "pawn_loan" or loan.get("collateral_id") != id or loan.get("status") not in ["outstanding", "overdue"] or asset.custodian_ref.get("entity_kind") != "asset" or asset.custodian_ref.get("entity_id") != loan.get("shop_id") or asset.owner_ref.get("entity_id") != loan.get("borrower_id"):
					return fail("pledged asset lost lender/collateral contract")
			elif asset.status == "awaiting_delivery":
				var production: Dictionary = contracts.get(asset.source_ref.get("entity_id"), {})
				if production.get("contract_kind") != "production" or production.get("status") != "ready" or production.get("output_id") != id or asset.owner_ref != {"entity_kind": "character", "entity_id": production.get("customer_id")} or asset.custodian_ref != {"entity_kind": "character", "entity_id": production.get("supplier_id")} or asset.lien_contract_id != "": return fail("unfinished delivery lost actual production custody")
			elif asset.lien_contract_id != "" or (asset.custodian_ref != asset.owner_ref and not load("res://scripts/core/estate_production_continuation.gd").custody_valid(raw, asset) and not load("res://scripts/core/gift_delivery_service.gd").custody_valid(raw, asset)):
				return fail("available asset has inconsistent lien/custody")
			if (raw.get("inventory", []) as Array).any(func(item): return item is Dictionary and item.get("id") == id and item.get("asset_ref") != id):
				return fail("managed asset duplicated in disposable inventory")
			if asset.has("item_definition"):
				if not asset.item_definition is Dictionary or asset.item_definition.has("owner_id") or asset.item_definition.has("equipped") or not asset.get("equipped_by") is String: return fail("item presentation duplicates authoritative rights")
			if asset.get("equipped_by", "") != "" and (asset.status != "available" or asset.owner_ref != {"entity_kind": "character", "entity_id": asset.equipped_by} or asset.custodian_ref != asset.owner_ref): return fail("equipped item is not in its owner's free possession")
			if asset.has("transfer_history"):
				if not asset.transfer_history is Array or asset.transfer_history.is_empty(): return fail("invalid item transfer history")
				var previous := {}
				for delivery in asset.transfer_history:
					if not delivery is Dictionary or not delivery.get("from_ref") is Dictionary or not delivery.get("to_ref") is Dictionary or delivery.from_ref.get("entity_kind") != "character" or delivery.to_ref.get("entity_kind") != "character" or not characters.has(delivery.from_ref.get("entity_id")) or not characters.has(delivery.to_ref.get("entity_id")) or not amount(delivery.get("day")) or delivery.get("consent_rule") not in ["unconditional_gift_relationship", "pawn_default_sale", "estate_distribution", "gift_agreement"]: return fail("invalid item delivery parties or consent")
					var receipt: Dictionary = raw.get("action_receipts", {}).get(delivery.get("execution_id"), {})
					var effect := str(id)
					if delivery.consent_rule == "gift_agreement":
						var gift: Dictionary = contracts.get(delivery.get("contract_id"), {})
						if gift.get("contract_kind") != "gift_delivery" or gift.get("status") != "received" or gift.get("item_id") != id or gift.get("sender_id") != delivery.from_ref.entity_id or gift.get("recipient_id") != delivery.to_ref.entity_id or gift.get("resolution_receipt") != delivery.execution_id: return fail("gift transfer lost independent reception")
					if delivery.consent_rule == "estate_distribution":
						effect = str(delivery.get("estate_id", ""))
						var estate: Dictionary = contracts.get(effect, {})
						if estate.get("status") != "settled" or estate.get("owner_id") != delivery.from_ref.entity_id or estate.get("settlement_receipt") != delivery.execution_id or not estate.get("items", []).any(func(item): return item.get("asset_id") == id and item.get("heir_id") == delivery.to_ref.entity_id): return fail("遗赠缺少实际遗产分配记录")
					if delivery.consent_rule == "pawn_default_sale":
						var loan: Dictionary = contracts.get(delivery.get("contract_id"), {})
						effect = str(delivery.get("contract_id", ""))
						var paid: Dictionary = raw.get("resource_journal", {}).get(delivery.get("execution_id"), {})
						if loan.get("collateral_id") != id or loan.get("borrower_id") != delivery.from_ref.entity_id or loan.get("status") not in ["disposed", "disposed_with_debt"] or not loan.get("execution_refs", []).has(delivery.get("execution_id")) or not accounts.get(paid.get("source_account_id"), {}).get("operator_refs", []).has(delivery.to_ref) or paid.get("reason_ref") != loan.get("contract_id") or paid.get("destination_account_id") != assets.get(loan.get("shop_id"), {}).get("account_id"): return fail("item default sale lost actual loan or buyer payment")
					if not receipt.get("effect_refs", []).has(effect) or (not previous.is_empty() and previous != delivery.from_ref): return fail("item delivery lost committed receipt or ownership chain")
					previous = delivery.to_ref
				if previous != asset.owner_ref: return fail("item delivery history does not reach current owner")
			if asset.has("pledge_offer"):
				var offer: Variant = asset.pledge_offer
				if not offer is Dictionary or not characters.has(offer.get("borrower_id")) or not accounts.has(offer.get("borrower_account_id")) or not offer.get("organization_ids") is Array or not offer.get("allow_redemption_collection") is bool or not offer.get("recourse") is bool:
					return fail("pledge offer lost borrower or consent terms")
				for field in ["principal", "duration_days", "valuation"]:
					if not amount(offer.get(field), true):
						return fail("invalid pledge offer " + field)
				if not amount(offer.get("fee")) or not amount(offer.get("disposal_grace_days")) or not offer.get("valuation_basis") is String:
					return fail("invalid pledge offer fee/disposal/valuation basis")
			if asset.has("purchase_offer"):
				var offer: Variant = asset.purchase_offer
				if not offer is Dictionary or not characters.has(offer.get("buyer_id")) or not accounts.has(offer.get("account_id")) or not amount(offer.get("price"), true) or not amount(offer.get("minimum_condition")) or not amount(offer.get("valid_until_day")):
					return fail("invalid actual buyer offer")
	for id in contracts:
		var contract: Dictionary = contracts[id]
		if contract.contract_kind in ["social_agreement", "gift_delivery"]: continue
		if contract.contract_kind == "food_purchase":
			var food_valid: Dictionary = load("res://scripts/core/household_subsistence_service.gd").validate_purchase(raw, contract)
			if not food_valid.ok: return food_valid
			continue
		if contract.contract_kind == "character_search":
			var search_valid := _validate_character_search(contract, raw)
			if not search_valid.ok: return search_valid
			continue
		if contract.contract_kind in ["public_work", "cultivation", "public_cash_liability", "school_teaching", "school_enrollment", "school_assessment", "school_candidacy", "school_supply", "school_living_aid", "school_exam_journey", "official_journey", "local_levy", "official_initiative", "marriage", "personal_estate", "family_partition", "land_sale", "land_share_sale", "land_lease", "estate_improvement", "estate_demolition", "estate_construction", "retail_trade", "manufacturing_batch", "manufacturing_sale", "managed_cultivation", "farm_sale", "business_month", "business_profit_policy", "business_profit_distribution", "business_audit", "business_coordination", "estate_property_sale", "estate_operating_right"]: continue
		if contract.contract_kind == "production":
			var production_valid := _validate_production_contract(contract, raw)
			if not production_valid.ok: return production_valid
			continue
		if contract.contract_kind == "employment":
			continue
		if not contract.get("party_refs") is Array or not amount(contract.get("terms_version"), true) or not contract.get("execution_refs") is Array or (contract.execution_refs.is_empty() and contract.contract_kind != "maintenance") or not assets.has(contract.get("shop_id")):
			return fail("economic contract lost parties/version/payments/shop")
		for receipt in contract.execution_refs:
			if not raw.get("resource_journal", {}).has(receipt):
				return fail("economic contract lost committed payment")
			if raw.resource_journal[receipt].get("reason_ref") != id:
				return fail("economic contract references another contract's payment")
		if contract.contract_kind == "lease":
			if contract.get("status") not in ["active", "terminated"] or not assets.has(contract.get("building_id")) or not accounts.has(contract.get("funding_account_id")) or not accounts.has(contract.get("payee_account_id")) or not characters.has(contract.get("landlord_id")) or not amount(contract.get("amount"), true) or not amount(contract.get("period_days"), true) or not amount(contract.get("arrears")) or not amount(contract.get("next_due_day")):
				return fail("invalid lease terms or parties")
		elif contract.contract_kind == "setup":
			if contract.get("status") not in ["working", "delivered"] or not characters.has(contract.get("supplier_id")) or not amount(contract.get("amount"), true) or not amount(contract.get("due_day")):
				return fail("invalid setup terms or supplier")
			for field in ["created_day", "last_work_day", "work_days"]:
				if not amount(contract.get(field)): return fail("setup lost actual work dates")
			if not amount(contract.get("duration_days"), true) or int(contract.work_days) > int(contract.duration_days) or int(contract.last_work_day) > int(raw.current_day) or int(contract.last_work_day) < int(contract.created_day) or (contract.status == "delivered") != (int(contract.work_days) == int(contract.duration_days)): return fail("setup delivery has no completed work process")
		elif contract.contract_kind == "maintenance":
			if contract.get("status") not in ["active","terminated"] or not characters.has(contract.get("supplier_id")) or not accounts.has(contract.get("funding_account_id")) or not accounts.has(contract.get("payee_account_id")) or not amount(contract.get("amount"), true) or not amount(contract.get("period_days"), true) or not amount(contract.get("next_due_day")) or not amount(contract.get("arrears")):
				return fail("invalid maintenance terms or payment source")
		elif contract.contract_kind == "pawn_loan":
			if contract.get("status") not in ["outstanding", "overdue", "redeemed", "disposed", "disposed_with_debt"] or not accounts.has(contract.get("lender_account_id")) or not accounts.has(contract.get("borrower_account_id")) or not characters.has(contract.get("borrower_id")) or not assets.has(contract.get("collateral_id")) or not contract.get("allow_redemption_collection") is bool or not contract.get("recourse") is bool:
				return fail("loan lost lender/borrower/collateral/terms")
			for field in ["principal", "fee", "due_day", "disposal_day", "valuation", "principal_repaid", "fee_received", "principal_written_off", "fee_written_off", "remaining_debt", "surplus_returned"]:
				if not amount(contract.get(field)):
					return fail("loan lost amount or date: " + field)
			if int(contract.principal) <= 0 or int(contract.principal_repaid) + int(contract.principal_written_off) > int(contract.principal) or int(contract.fee_received) > int(contract.fee) or int(contract.disposal_day) < int(contract.due_day):
				return fail("loan recovery amounts or dates are inconsistent")
			if int(contract.remaining_debt) != int(contract.principal) + int(contract.fee) - int(contract.principal_repaid) - int(contract.principal_written_off) - int(contract.fee_received) - int(contract.fee_written_off):
				return fail("loan debt was silently erased or duplicated")
			if accounts[contract.borrower_account_id].owner_ref.get("entity_id") != contract.borrower_id or assets[contract.shop_id].get("account_id") != contract.lender_account_id or contract.party_refs != [assets[contract.shop_id].owner_ref.entity_id, contract.borrower_id]:
				return fail("loan payment accounts or parties mismatch")
			var disbursement: Dictionary = raw.resource_journal[contract.execution_refs[0]]
			if disbursement.get("amount") != contract.principal or disbursement.get("source_account_id") != contract.lender_account_id or disbursement.get("destination_account_id") != contract.borrower_account_id:
				return fail("loan lacks actual principal disbursement")
			var recovered := 0
			var seen_payments := {}
			for ref in contract.execution_refs:
				if seen_payments.has(ref): return fail("loan repeats a payment receipt")
				seen_payments[ref] = true
				var payment: Dictionary = raw.resource_journal[ref]
				if payment.get("destination_account_id") == contract.lender_account_id: recovered += int(payment.amount)
			if recovered != int(contract.principal_repaid)+int(contract.fee_received) or int(contract.principal_repaid) != mini(recovered,int(contract.principal)):
				return fail("loan recovery differs from actual payments")
			if int(contract.principal_written_off)>0 and (contract.status != "disposed" or contract.recourse or int(contract.principal_written_off) != int(contract.principal)-int(contract.principal_repaid)):
				return fail("loan write-off lacks a nonrecourse disposal")
			if contract.status in ["outstanding", "overdue"] and assets[contract.collateral_id].get("lien_contract_id") != id:
				return fail("unsettled loan lost collateral lien")
	return {"ok": true}

static func _validate_execution(raw: Dictionary) -> Dictionary:
	var authorizations: Dictionary = raw.get("action_authorizations", {})
	var receipts: Dictionary = raw.get("action_receipts", {})
	var characters: Dictionary = raw.get("character_states", {})
	var accounts: Dictionary = raw.get("resource_accounts", {})
	var tasks := {}
	if not raw.get("active_tasks", []) is Array or not raw.get("completed_tasks", []) is Array:
		return fail("invalid task lists")
	for task in raw.get("active_tasks", []) + raw.get("completed_tasks", []):
		if not task is Dictionary:
			return fail("invalid task record")
		if task.get("task_kind") == "private_entrustment" and task.has("serial_plan"):
			var serial_valid := _validate_serial_entrustment(task, raw)
			if not serial_valid.ok: return serial_valid
		if task.get("task_kind") != "management":
			continue
		if not task.get("task_id") is String or task.get("task_id") != task.get("id") or tasks.has(task.task_id):
			return fail("duplicate or invalid management task identity")
		if not authorizations.has(task.get("authorization_id")) or not characters.has(task.get("principal_id")) or not characters.has(task.get("executor_id")) or not amount(task.get("plan_revision"), true) or not amount(task.get("authorization_version"), true):
			return fail("management task references missing authorization or character")
		if task.get("status") not in ["reserved", "running", "blocked", "completed", "cancelled"] or not task.get("steps") is Array or (task.steps.is_empty() and not authorizations[task.authorization_id].has("business_policy")) or not task.get("delegation_chain") is Array or task.delegation_chain.is_empty():
			return fail("invalid management task status/steps/chain")
		tasks[task.task_id] = task
		if task.delegation_chain.back() != task.executor_id:
			return fail("delegation chain does not reach executor")
		var seen: Array = []
		for id in task.delegation_chain:
			if seen.has(id) or not characters.has(id):
				return fail("cyclic or missing delegation character")
			seen.append(id)
		var ids: Array = []
		for step in task.steps:
			if not step is Dictionary or not step.get("step_id") is String or ids.has(step.step_id) or not step.get("depends_on") is Array or not step.get("parameters") is Dictionary or not step.get("target_refs") is Array or step.get("status") not in ["planned", "delegated", "completed"] or str(step.get("execution_id", "")).is_empty():
				return fail("invalid saved management step")
			if step.get("action_kind") == "hire_family_from_pool":
				var pool: Dictionary = preload("res://scripts/core/family_office_rules.gd").pool_cost(raw, step.parameters)
				if not pool.ok or not step.parameters.candidate_ids.all(func(person): return step.target_refs.has(person)): return fail("saved candidate pool lost agreed people or terms")
			for dependency in step.depends_on:
				if not ids.has(dependency):
					return fail("missing or cyclic step dependency")
			ids.append(step.step_id)
			if step.status == "completed" and str(step.get("child_task_id", "")).is_empty() and not receipts.has(step.get("receipt_ref")):
				return fail("completed step lost its execution receipt")
			tasks[task.task_id] = task
		var segments_valid := preload("res://scripts/core/management_plan_segments.gd").validate(task)
		if not segments_valid.ok: return segments_valid
	for id in authorizations:
		var auth: Variant = authorizations[id]
		if not auth is Dictionary or auth.get("authorization_id") != id or not characters.has(auth.get("principal_id")) or not characters.has(auth.get("delegate_id")) or not amount(auth.get("version"), true) or auth.get("status") not in ["active", "completed", "revoked"]:
			return fail("invalid saved authorization identity/status")
		if not auth.get("scope") is Dictionary or not auth.scope.get("action_kinds") is Array or not auth.scope.get("target_refs") is Array or not auth.scope.get("allow_subdelegation") is bool or not auth.get("resource_limits") is Array or not auth.get("reservation_refs") is Dictionary or not auth.get("delegate_ids") is Array:
			return fail("authorization lost scope or cumulative budget")
		if not auth.has("valid_until_day") or (auth.valid_until_day != null and not amount(auth.valid_until_day)) or not tasks.has(auth.get("root_task_id")):
			return fail("authorization lost deadline or root task")
		if auth.has("business_policy"):
			var policy_valid: Dictionary = load("res://scripts/core/business_management_service.gd").validate(raw,auth,tasks[auth.root_task_id])
			if not policy_valid.ok: return policy_valid
		if auth.has("consent_source") and auth.consent_source is Dictionary and auth.consent_source.get("kind") == "social_agreement":
			var consent_valid: Dictionary = load("res://scripts/core/npc_mandate_service.gd").validate_consent(raw, auth, tasks[auth.root_task_id])
			if not consent_valid.ok: return consent_valid
		elif auth.has("consent_source"):
			var consent: Variant = auth.consent_source
			if not consent is Dictionary or consent.get("kind") != "private_dialogue" or not consent.get("session_id") is String or str(consent.session_id).is_empty() or not amount(consent.get("terms_version"), true) or not amount(consent.get("accepted_day")) or int(consent.accepted_day) > int(raw.current_day) or consent.get("principal_id") != auth.principal_id or consent.get("delegate_id") != auth.delegate_id or not consent.get("agreement") is Dictionary: return fail("authorization lost actual dialogue consent")
			var agreement: Dictionary = consent.agreement
			if consent.get("agreement_hash") != preload("res://scripts/core/canonical_json.gd").hash_value(agreement).get("hash") or not agreement.get("authority_terms") is Dictionary or not agreement.get("plan") is Dictionary or not agreement.get("quotes") is Array or not agreement.get("searches", []) is Array or (agreement.quotes.is_empty() and agreement.get("searches", []).is_empty()) or not agreement.get("summary") is String: return fail("dialogue agreement changed after acceptance")
			if agreement.authority_terms.get("authorization_id") != id or agreement.authority_terms.get("principal_id") != auth.principal_id or agreement.authority_terms.get("delegate_id") != auth.delegate_id or agreement.plan.get("task_id") != auth.root_task_id: return fail("dialogue agreement belongs to another authorization")
			var root: Dictionary = tasks[auth.root_task_id]
			if root.get("source_type") != "private_talk" or root.get("source_session_id") != consent.session_id or root.get("terms_version") != consent.terms_version: return fail("dialogue task lost agreed source")
		for character_id in auth.delegate_ids:
			if not characters.has(character_id):
				return fail("authorization references missing delegate")
		var source_refs: Array = []
		for limit in auth.resource_limits:
			if not limit is Dictionary or not accounts.has(limit.get("account_id")) or not amount(limit.get("amount"), true) or limit.get("unit_id") != "cash_unit":
				return fail("invalid saved cumulative resource limit")
			if accounts[limit.account_id].unit_id != limit.unit_id:
				return fail("saved cumulative limit currency does not match actual source")
			if source_refs.has(accounts[limit.account_id].storage_ref):
				return fail("authorization duplicates one funding source")
			source_refs.append(accounts[limit.account_id].storage_ref)
			var reservation: Dictionary = raw.get("resource_reservations", {}).get(auth.reservation_refs.get(limit.account_id, ""), {})
			if reservation.get("account_id") != limit.account_id or reservation.get("task_id") != auth.root_task_id or reservation.get("amount") != limit.amount:
				return fail("authorization lost its root budget reservation")
			var spent := 0
			var journal_ids: Array = []
			for receipt in receipts.values():
				if not receipt is Dictionary or receipt.get("authorization_id") != id:
					continue
				if not receipt.get("journal_refs") is Array:
					return fail("action lost payment references")
				for journal_id in receipt.journal_refs:
					var journal: Dictionary = raw.get("resource_journal", {}).get(journal_id, {})
					if journal.get("source_account_id") == limit.account_id:
						if journal_ids.has(journal_id):
							return fail("two action receipts reuse one payment")
						journal_ids.append(journal_id)
						spent += int(journal.amount)
			if spent > int(limit.amount) or spent + int(reservation.remaining_amount) > int(limit.amount):
				return fail("authorization cumulative budget exceeded")
			if auth.status == "active" and spent + int(reservation.remaining_amount) != int(limit.amount):
				return fail("active authorization lost spent or reserved funds")
	for id in receipts:
		var receipt: Variant = receipts[id]
		if not receipt is Dictionary or receipt.get("execution_id") != id or receipt.get("status") != "committed" or not receipt.get("effect_refs") is Array or not receipt.get("journal_refs") is Array or not amount(receipt.get("state_revision_after"), true) or str(receipt.get("input_hash", "")).is_empty():
			return fail("invalid action receipt")
		if receipt.get("authorization_id", "") != "" and not authorizations.has(receipt.authorization_id):
			return fail("action receipt lost authorization")
		if receipt.get("task_id", "") != "" and not tasks.has(receipt.task_id):
			return fail("action receipt lost task")
		for journal_id in receipt.journal_refs:
			if not raw.get("resource_journal", {}).has(journal_id):
				return fail("action receipt lost payment")
	for task in tasks.values():
		var auth: Dictionary = authorizations[task.authorization_id]
		if task.principal_id != auth.principal_id or not auth.delegate_ids.has(task.executor_id):
			return fail("task authority mismatch")
		var parent := str(task.get("parent_task_id", ""))
		if not parent.is_empty() and (not tasks.has(parent) or tasks[parent].authorization_id != task.authorization_id or task.delegation_chain.size() != tasks[parent].delegation_chain.size() + 1):
			return fail("child task lost parent authorization")
		for step in task.steps:
			if step.get("child_task_id", "") != "" and (not tasks.has(step.child_task_id) or tasks[step.child_task_id].get("parent_task_id") != task.task_id):
				return fail("delegated step lost its child task")
			if step.status == "completed" and not str(step.get("child_task_id", "")).is_empty() and (not tasks.has(step.get("child_task_id")) or tasks[step.child_task_id].status != "completed" or step.receipt_ref != "task:" + str(step.child_task_id)):
				return fail("delegated completion lacks completed child")
	return {"ok": true}

static func _validate_character_search(order: Dictionary, raw: Dictionary) -> Dictionary:
	if order.get("status") not in ["working", "awaiting_choice", "resolved", "completed", "failed", "cancelled"] or not raw.character_states.has(order.get("principal_id")) or not raw.character_states.has(order.get("executor_id")) or order.get("party_refs") != [order.get("principal_id"), order.get("executor_id")] or not raw.local_node_state.has(order.get("location_id")) or not amount(order.get("terms_version"), true): return fail("search lost actual parties, location or status")
	for field in ["created_day", "last_work_day", "work_days", "attempt", "seed"]:
		if not amount(order.get(field)): return fail("search lost work or attempt provenance")
	if not amount(order.get("duration_days"), true) or int(order.work_days) > int(order.duration_days) or int(order.last_work_day) > int(raw.current_day) or not order.get("blocked_reason") is String or not order.get("original_plan") is Dictionary or not order.get("search_state") is Dictionary or not order.get("failure_history") is Array or order.failure_history.size() != int(order.attempt): return fail("search work or retry history is invalid")
	var work: Dictionary = order.search_state
	if work.get("requester_id") != order.principal_id or work.get("executor_id") != order.executor_id or work.get("id") != order.contract_id or work.get("target_type") != "character" or work.get("rule_seed") != int(order.seed) + int(order.attempt) * 37: return fail("search process does not match actual agreement")
	if not amount(work.get("created_day")) or int(work.created_day) < int(order.created_day) or int(order.last_work_day) < int(work.created_day) + int(order.work_days) or not amount(work.get("due_day")) or not work.get("outcome_settled") is bool or not work.get("candidate_character_id") is String or not work.get("visible_feedback") is Array: return fail("search work is outside actual attempt time")
	if order.original_plan.get("capability_id") != "find_person_and_introduce" or order.original_plan.get("target_type") != "character" or order.original_plan.get("due_days") != order.duration_days or work.get("archetype_id") != order.original_plan.get("target_archetype") or work.get("target_role") != order.original_plan.get("target_role") or work.get("specialty") != order.original_plan.get("specialty") or work.get("guaranteed_lead", false) or order.original_plan.get("guaranteed_lead", false): return fail("search changed actual target or promised a guaranteed result")
	if order.status == "failed" and (int(order.work_days) != int(order.duration_days) or not work.outcome_settled or work.get("execution_status") != "failed" or work.candidate_character_id != ""): return fail("search failure has no actual completed attempt")
	for index in order.failure_history.size():
		var prior: Variant = order.failure_history[index]
		if not prior is Dictionary or prior.get("attempt") != index or not amount(prior.get("day")) or int(prior.day) > int(raw.current_day) or not prior.get("outcome_code") is String or str(prior.outcome_code).is_empty() or not prior.get("feedback") is Array: return fail("search retry lost prior failure evidence")
	if not order.get("authorization_id") is String or (order.authorization_id != "" and not raw.action_authorizations.has(order.authorization_id)): return fail("search lost actual authority")
	if not raw.action_receipts.get(order.get("start_receipt"), {}).get("effect_refs", []).has(order.contract_id) or not order.get("resolution_receipts") is Array or not order.get("finish_receipt") is String or not order.get("candidate_id") is String: return fail("search lost shared action receipts")
	for receipt in order.resolution_receipts:
		if not raw.action_receipts.get(receipt, {}).get("effect_refs", []).has(order.contract_id): return fail("search disposition lost actual receipt")
	if order.status in ["awaiting_choice", "resolved", "completed"]:
		if int(order.work_days) != int(order.duration_days) or order.candidate_id == "" or work.get("candidate_character_id") != order.candidate_id or raw.character_states.get(order.candidate_id, {}).get("search_source_ref") != order.contract_id: return fail("search claims a person without actual completed work")
	elif order.candidate_id != "": return fail("unsuccessful search contains an unregistered result")
	if order.status in ["resolved", "completed"] and (order.resolution_receipts.is_empty() or work.get("outcome_code") not in ["accepted_as_retainer", "declined_politely"]): return fail("search disposition was not actually resolved")
	if order.status == "completed" and not raw.action_receipts.get(order.finish_receipt, {}).get("effect_refs", []).has(order.contract_id): return fail("search completion lost action receipt")
	return {"ok": true}

static func _validate_pending_production(raw: Dictionary) -> Dictionary:
	var sessions: Variant = raw.get("active_dialogue_sessions", {})
	if not sessions is Dictionary: return fail("invalid saved dialogue sessions")
	for session in sessions.values():
		if not session is Dictionary: return fail("invalid saved dialogue session")
		var pending: Variant = session.get("pending_entrustment", {})
		if not pending is Dictionary: return fail("invalid pending dialogue terms")
		var plan: Variant = pending.get("plan", {})
		if not plan is Dictionary: return fail("invalid pending dialogue plan")
		if not plan.has("management_proposal"): continue
		var proposal: Variant = plan.management_proposal
		if not proposal is Dictionary or not proposal.get("authority_terms") is Dictionary or not proposal.get("plan") is Dictionary or not proposal.get("quotes") is Array or not proposal.get("searches", []) is Array or (proposal.quotes.is_empty() and proposal.get("searches", []).is_empty()) or not proposal.get("summary") is String: return fail("pending production lost agreed authority, quote or plan")
		var auth: Dictionary = proposal.authority_terms
		var executable: Dictionary = proposal.plan
		if auth.get("principal_id") != raw.player_character_id or auth.get("delegate_id") != session.get("npc_id") or not raw.character_states.has(auth.get("delegate_id")) or auth.get("status") != "active" or not amount(auth.get("version"), true) or not auth.get("resource_limits") is Array or not auth.get("scope") is Dictionary or not auth.has("valid_until_day") or (auth.valid_until_day != null and not amount(auth.valid_until_day)): return fail("pending production lost actual parties or authority")
		if not auth.get("authorization_id") is String or str(auth.authorization_id).is_empty() or not executable.get("task_id") is String or str(executable.task_id).is_empty() or executable.get("executor_id") != auth.delegate_id or not executable.get("steps") is Array or executable.steps.size() != (proposal.quotes.size() + proposal.get("searches", []).size()) * 2: return fail("pending production lost complete sequence")
		for quote in proposal.quotes:
			if not quote is Dictionary or not quote.get("workshop_id") is String or not quote.get("recipe_id") is String or not quote.get("recipe") is Dictionary or not amount(quote.recipe.get("price"), true) or not amount(quote.recipe.get("duration_days"), true): return fail("pending production quote is incomplete")
		for search in proposal.get("searches", []):
			if not search is Dictionary or not search.get("search_id") is String or not raw.local_node_state.has(search.get("location_id")) or not search.get("archetype_id") is String or not search.get("target_role") is String or not search.get("specialty") is String or not amount(search.get("duration_days"), true): return fail("pending search lost actual location, target or work terms")
		for step in executable.steps:
			if not step is Dictionary or step.get("action_kind") not in ["commission_production", "collect_production", "start_character_search", "finish_character_search"] or not step.get("parameters") is Dictionary or not step.get("depends_on") is Array or not step.get("target_refs") is Array or not step.get("step_id") is String: return fail("pending production step is incomplete")
		var digest := preload("res://scripts/core/canonical_json.gd").hash_value(proposal)
		if not digest.get("ok", false) or digest.get("hash") != pending.get("plan_hash") or pending.get("plan_hash") != plan.get("plan_hash"): return fail("pending production differs from quoted terms")
	return {"ok": true}

static func _validate_production_asset(asset: Dictionary, raw: Dictionary) -> Dictionary:
	if asset.asset_kind == "material_stock":
		if not amount(asset.get("initial_quantity"), true) or not amount(asset.get("remaining_quantity")) or not asset.get("consumptions") is Dictionary or not asset.get("material_key") is String or asset.get("unit_id") != "material_unit": return fail("invalid physical material stock")
		var used := 0
		for id in asset.consumptions:
			if not amount(asset.consumptions[id], true): return fail("invalid material consumption quantity")
			var order: Dictionary = raw.economic_contracts.get(id, {})
			if not order.get("recipe") is Dictionary or not order.recipe.get("inputs") is Array: return fail("material consumption lost recipe")
			var inputs: Array = order.recipe.inputs.filter(func(input): return input is Dictionary and input.get("stock_id") == asset.asset_id and input.get("quantity") == asset.consumptions[id])
			if order.get("contract_kind") not in ["production", "public_work", "school_supply", "estate_construction", "retail_trade", "manufacturing_batch", "manufacturing_sale", "managed_cultivation", "farm_sale", "business_month"] or inputs.size() != 1: return fail("material consumption lost production source")
			used += int(asset.consumptions[id])
		if used + int(asset.remaining_quantity) != int(asset.initial_quantity): return fail("material stock no longer conserves actual inputs")
		return {"ok": true}
	if asset.get("status") not in ["available", "closed"] or asset.owner_ref != {"entity_kind": "character", "entity_id": asset.get("supplier_id")} or not raw.resource_accounts.has(asset.get("payee_account_id")) or raw.resource_accounts[asset.payee_account_id].owner_ref != asset.owner_ref or asset.get("offer_visibility") != "public" or not asset.get("recipes") is Dictionary or asset.recipes.is_empty(): return fail("workshop lost supplier, payment account or public offer")
	for recipe in asset.recipes.values():
		if not recipe is Dictionary or not amount(recipe.get("price"), true) or not amount(recipe.get("duration_days"), true) or not recipe.get("inputs") is Array or recipe.inputs.is_empty() or not recipe.get("output_definition") is Dictionary or not recipe.output_definition.get("name") is String or not recipe.get("source_work_id") is String: return fail("workshop recipe lost input, time, price or actual product")
		var definition: Dictionary = recipe.output_definition
		if str(definition.name).strip_edges().is_empty() or not definition.get("actions") is Array or definition.actions.is_empty(): return fail("production quote lost product name or uses")
		for field in ["id", "owner_id", "owner_ref", "holder_name", "custodian_ref", "equipped", "equipped_by", "condition", "lien_contract_id", "location_id", "source_ref"]:
			if definition.has(field): return fail("production presentation duplicates authoritative rights")
		if definition.actions.any(func(action): return not action is String or action not in ["inspect", "equip", "bestow"]): return fail("production quote contains unsupported item use")
		var inputs: Array = []
		for input in recipe.inputs:
			if not input is Dictionary or not amount(input.get("quantity"), true) or inputs.has(input.get("stock_id")): return fail("production inputs missing or repeated")
			var stock: Dictionary = raw.management_assets.get(input.get("stock_id"), {})
			if stock.get("asset_kind") != "material_stock" or stock.get("owner_ref") != asset.owner_ref or stock.get("location_id") != asset.location_id: return fail("workshop has no actual local material stock")
			inputs.append(input.stock_id)
		if recipe.source_work_id != "" and raw.management_assets.get(recipe.source_work_id, {}).get("asset_kind") != "movable": return fail("production recipe lost existing source manuscript")
	return {"ok": true}

static func _validate_production_contract(order: Dictionary, raw: Dictionary) -> Dictionary:
	var workshop: Dictionary = raw.management_assets.get(order.get("workshop_id"), {})
	if workshop.get("asset_kind") != "workshop" or order.get("supplier_id") != workshop.get("supplier_id") or not raw.character_states.has(order.get("customer_id")) or order.get("party_refs") != [order.get("customer_id"), order.get("supplier_id")] or order.get("status") not in ["working", "ready", "delivered"] or not amount(order.get("terms_version"), true): return fail("production contract lost actual parties or status")
	if not order.get("recipe") is Dictionary or order.recipe != workshop.recipes.get(order.get("recipe_id")) or not order.get("execution_refs") is Array or order.execution_refs != [order.get("commission_receipt")]: return fail("production contract changed agreed recipe or payment")
	for field in ["created_day", "due_day", "work_days", "last_work_day"]:
		if not amount(order.get(field)): return fail("invalid production work or day")
	if not order.get("blocked_reason") is String or int(order.work_days) > int(order.recipe.duration_days) or int(order.last_work_day) < int(order.created_day) + int(order.work_days) or int(order.last_work_day) > int(raw.current_day) or int(order.due_day) < int(order.created_day) + int(order.recipe.duration_days): return fail("production work exceeds actual process")
	var paid: Dictionary = raw.resource_journal.get(order.commission_receipt, {})
	var commission: Dictionary = raw.action_receipts.get(order.commission_receipt, {})
	if paid.get("entry_kind") != "transfer" or paid.get("source_account_id") != order.get("funding_account_id") or order.get("payee_account_id") != workshop.payee_account_id or paid.get("destination_account_id") != workshop.payee_account_id or paid.get("amount") != order.recipe.price or paid.get("reason_ref") != order.contract_id or not commission.get("effect_refs", []).has(order.contract_id) or commission.get("day") != order.created_day: return fail("production has no actual committed payment")
	for input in order.recipe.inputs:
		if raw.management_assets.get(input.stock_id, {}).get("consumptions", {}).get(order.contract_id) != input.quantity: return fail("production did not consume its actual inputs")
	if not order.get("output_id") is String or order.output_id != "product:" + str(order.contract_id) or not order.get("collection_receipt") is String: return fail("production lost stable output or collection identity")
	var output: Dictionary = raw.management_assets.get(order.output_id, {})
	if order.status == "working":
		if int(order.work_days) >= int(order.recipe.duration_days) or not output.is_empty() or order.collection_receipt != "": return fail("unfinished production already claims an output")
	else:
		if int(order.work_days) != int(order.recipe.duration_days) or output.get("source_ref") != {"entity_kind": "contract", "entity_id": order.contract_id} or output.get("item_definition") != order.recipe.output_definition or output.get("name") != order.recipe.output_definition.name or not output.get("contract_refs", []).has(order.contract_id) or not amount(order.get("completed_day")) or order.completed_day != order.last_work_day: return fail("production output lost its completed process")
		if order.status == "ready" and (output.get("status") != "awaiting_delivery" or order.collection_receipt != ""): return fail("ready production lost custody before collection")
		if order.status == "delivered":
			var delivery: Dictionary = raw.action_receipts.get(order.collection_receipt, {})
			if not delivery.get("effect_refs", []).has(order.contract_id) or not amount(order.get("delivered_day")) or int(order.delivered_day) < int(order.completed_day) or int(order.delivered_day) > int(raw.current_day) or delivery.get("day") != order.delivered_day: return fail("production delivery lost actual receipt")
			if delivery.has("estate_continuation") or delivery.has("estate_collection"):
				var custody_record: Dictionary = delivery.get("estate_continuation", delivery.get("estate_collection", {}))
				var estate: Dictionary = raw.economic_contracts.get(custody_record.get("estate_id"), {})
				if order.get("estate_custody") != {"estate_id": estate.get("contract_id"), "custodian_id": estate.get("executor_id"), "execution_id": order.collection_receipt} or estate.get("owner_id") != order.customer_id: return fail("production lost entrusted estate custody")
			elif order.has("estate_custody"): return fail("estate custody has no original mandate receipt")
	if order.status != "delivered" and order.has("estate_custody"): return fail("unfinished production already claims estate custody")
	return {"ok": true}

static func _validate_serial_entrustment(task: Dictionary, raw: Dictionary) -> Dictionary:
	if not task.serial_plan is Dictionary or not task.serial_plan.get("steps") is Array or task.serial_plan.steps.size() < 2 or not amount(task.get("serial_cursor")) or int(task.serial_cursor) >= task.serial_plan.steps.size() or not task.get("serial_results") is Array or not amount(task.get("serial_created_day")) or not amount(task.get("serial_seed")):
		return fail("serial entrustment lost plan, cursor or durable results")
	if not raw.character_states.has(task.get("requester_id")) or not raw.character_states.has(task.get("executor_id")) or task.serial_plan.get("requester_id") != task.requester_id or task.serial_plan.get("executor_id") != task.executor_id:
		return fail("serial entrustment lost actual principal or executor")
	var ids: Array = []
	for step in task.serial_plan.steps:
		if not step is Dictionary or not step.get("step_id") is String or str(step.step_id).is_empty() or ids.has(step.step_id) or not step.get("arguments") is Dictionary or step.get("capability_id") not in ["find_person_and_introduce", "craft_item", "compile_or_process_work"]: return fail("invalid serial entrustment step")
		ids.append(step.step_id)
	var expected := int(task.serial_cursor)
	if task.status == "completed" and task.get("stage") in ["introduced", "delivered"]: expected += 1
	if task.serial_results.size() != expected: return fail("serial entrustment cursor does not follow committed results")
	for index in task.serial_results.size():
		var result: Variant = task.serial_results[index]
		if not result is Dictionary or result.get("step_id") != ids[index] or not amount(result.get("completed_day")) or not result.get("outcome_code") is String: return fail("serial entrustment result is missing or out of order")
		var candidate := str(result.get("candidate_character_id", ""))
		var item := str(result.get("item_id", ""))
		if candidate.is_empty() and item.is_empty(): return fail("serial step has no actual delivered result")
		if not candidate.is_empty() and not raw.character_states.has(candidate): return fail("serial step lost introduced person")
		if not item.is_empty() and raw.flags.get("managed_inventory_initialized", false) and not raw.management_assets.has(item): return fail("serial step lost actual physical delivery")
	return {"ok": true}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "code": "management_contract_error", "error": message, "message": message}

static func _validate_assistant_conversation(raw: Dictionary) -> Dictionary:
	if raw.get("campaign_id") == "anshi_beta_1_14" and not raw.has("assistant_conversation_state"): return fail("current save lost assistant conversation state")
	var journal: Variant = raw.get("assistant_conversation_state", {})
	if not journal is Dictionary: return fail("invalid assistant conversation state")
	if journal.is_empty(): return {"ok": true}
	if journal.keys().size() != 3 or journal.get("principal_id") != raw.get("player_character_id") or not journal.get("records") is Dictionary or not journal.records.has(journal.get("latest_id")): return fail("assistant conversation lost owner or latest request")
	var sequences: Array = []
	var fields := ["execution_id", "binding", "task_versions", "original_text", "created_day", "instruction_day", "sequence", "revision", "status", "dto", "feedback", "error", "used_api", "request_id", "task_id", "decision", "metrics", "planning"]
	for id in journal.records:
		var row: Variant = journal.records[id]
		if not row is Dictionary: return fail("invalid assistant request record type")
		if row.size() != fields.size(): return fail("invalid assistant request record shape: " + str(row.keys()))
		for key in fields:
			if not row.has(key): return fail("assistant request lost " + key)
		for key in ["execution_id", "original_text", "feedback", "error", "request_id", "task_id"]:
			if not row[key] is String: return fail("invalid assistant request text: " + key)
		if row.execution_id != id or not str(id).begins_with("assistant:") or row.original_text.is_empty() or row.original_text.length() > 8000 or not row.used_api is bool or row.status not in ["requesting", "failed", "interrupted", "pending", "answered", "adopted", "dismissed", "superseded"]: return fail("invalid assistant request identity or lifecycle")
		if not amount(row.created_day) or int(row.created_day) > int(raw.current_day) or not amount(row.sequence, true) or sequences.has(row.sequence) or not amount(row.revision): return fail("invalid assistant request sequence or time")
		if not amount(row.instruction_day) or int(row.instruction_day) > int(row.created_day): return fail("assistant instruction has invalid original day")
		sequences.append(row.sequence)
		if not row.binding is Dictionary or row.binding.size() != 3 or row.binding.get("principal_id") != journal.principal_id or not raw.character_states.has(row.binding.get("assistant_id")) or not amount(row.binding.get("binding_revision"), true) or not row.task_versions is Dictionary: return fail("assistant request lost binding or task versions")
		for task_id in row.task_versions:
			var versions: Variant = row.task_versions[task_id]
			if not task_id is String or not versions is Array or versions.size() != 2 or not amount(versions[0], true) or not amount(versions[1], true): return fail("invalid assistant request task version")
		if not row.dto is Dictionary: return fail("invalid stored assistant response")
		if row.has("planning"):
			var staged: Variant = row.planning
			if not staged is Dictionary or staged.size() != 3 or not staged.get("attempts") is Array or not staged.get("resume_source") is String: return fail("invalid saved assistant planning parts")
			var assembly = load("res://scripts/core/assistant_plan_assembly.gd")
			var parts_valid: Dictionary = assembly.validate(staged.get("parts"))
			if not parts_valid.get("ok", false): return parts_valid
			if staged.resume_source != "":
				if not journal.records.get(staged.resume_source) is Dictionary: return fail("continued plan lost original request record")
				var source: Dictionary = journal.records[staged.resume_source]
				if not source.get("planning") is Dictionary or not source.planning.get("parts") is Array: return fail("continued plan lost original draft")
				var source_parts: Array = source.get("planning", {}).get("parts", [])
				if source.get("original_text") != row.original_text or source.get("instruction_day") != row.instruction_day or int(source.get("sequence", row.sequence)) >= int(row.sequence) or source_parts.is_empty() or staged.parts.size() < source_parts.size() or preload("res://scripts/core/canonical_json.gd").hash_value(staged.parts.slice(0, source_parts.size())) != preload("res://scripts/core/canonical_json.gd").hash_value(source_parts): return fail("continued plan lost its original received parts")
			for attempt in staged.attempts:
				if not attempt is Dictionary or attempt.size() != 4 or not attempt.get("used_api") is bool or not attempt.get("request_id") is String: return fail("invalid planning transport evidence")
				for field in ["attempt_count", "latency_ms"]:
					if not attempt.has(field) or (attempt[field] != null and not amount(attempt[field])): return fail("invalid planning transport measurement")
			if not staged.parts.is_empty() and not row.dto.is_empty():
				var joined: Dictionary = assembly.assemble(staged.parts)
				if not joined.get("ok", false) or preload("res://scripts/core/canonical_json.gd").hash_value(joined.dto) != preload("res://scripts/core/canonical_json.gd").hash_value(row.dto): return fail("stored assistant proposal differs from complete received parts")
		var metric: Variant = row.metrics
		if not metric is Dictionary or metric.size() != 5: return fail("assistant request lost metrics shape")
		for key in ["route", "outcome", "elapsed_ms", "transport_elapsed_ms", "attempt_count"]:
			if not metric.has(key): return fail("assistant request lost metric: " + key)
		if metric.route not in ["planner", "local_control"] or metric.outcome not in ["waiting", "valid_result", "invalid_result", "transport_error", "request_error", "cancelled", "interrupted"]: return fail("invalid assistant metric outcome or route")
		for key in ["elapsed_ms", "transport_elapsed_ms", "attempt_count"]:
			if metric[key] != null and not amount(metric[key]): return fail("invalid assistant measurement: " + key)
		if (metric.outcome == "waiting") != (row.status == "requesting"): return fail("assistant metric differs from actual waiting state")
		if metric.outcome == "waiting" and (metric.elapsed_ms != null or metric.transport_elapsed_ms != null or metric.attempt_count != null): return fail("in-flight assistant request claims completed measurements")
		if metric.outcome == "valid_result" and (row.dto.is_empty() or row.status in ["requesting", "failed", "interrupted"]): return fail("assistant metric claims valid reply without actual result")
		if row.status in ["pending", "adopted", "answered"] and metric.outcome != "valid_result": return fail("assistant proposal lost validated result measurement")
		if metric.route == "local_control" and not row.dto.is_empty() and row.dto.get("kind") != "cancel": return fail("assistant planner reply incorrectly claims local control")
		if not row.decision is Dictionary or row.decision.size() != 3 or row.decision.get("source") not in ["none", "button", "instruction"] or not row.decision.get("instruction") is String or str(row.decision.instruction).length() > 8000: return fail("assistant request lost decision source")
		if row.status in ["adopted", "dismissed"]:
			if row.decision.source == "none" or not amount(row.decision.get("day")) or int(row.decision.day) < int(row.created_day) or int(row.decision.day) > int(raw.current_day) or (row.decision.source == "instruction" and row.decision.instruction.is_empty()): return fail("assistant decision lacks actual instruction or time")
		elif row.decision.source != "none" or row.decision.instruction != "" or row.decision.get("day") != -1: return fail("unadopted request claims a decision")
		if not row.dto.is_empty():
			var parsed: Dictionary = load("res://scripts/ai/assistant_plan_parser.gd").new().parse(row.dto)
			if not parsed.get("ok", false): return fail("invalid stored assistant structured response")
		if (row.status in ["pending", "adopted"] or (row.status == "dismissed" and not row.dto.is_empty())) and row.dto.get("kind") not in ["proposal", "revise", "cancel"]: return fail("assistant request lost its actionable proposal")
		if row.status == "answered" and row.dto.get("kind") not in ["advice", "clarification"]: return fail("assistant answer lost its reply")
		if row.status == "requesting" and not row.dto.is_empty(): return fail("in-flight assistant request already contains response")
		if row.status in ["pending", "requesting"] and id != journal.latest_id: return fail("more than one current assistant request")
		if row.status == "adopted":
			var expected: String = "assistant-task:" + str(id) if row.dto.kind == "proposal" else str(row.dto.task_id)
			if row.task_id != expected or not (raw.get("active_tasks", []) + raw.get("completed_tasks", [])).any(func(task): return task.get("task_kind") == "management" and task.get("task_id") == row.task_id and (task.get("principal_id") == journal.principal_id or (row.dto.kind == "cancel" and load("res://scripts/core/clan_succession_service.gd").held_task_control(raw, task, journal.principal_id, int(row.decision.day))))): return fail("adopted assistant request lost actual task")
		elif not row.task_id.is_empty(): return fail("unadopted assistant request claims an executed task")
	if int(journal.records[journal.latest_id].sequence) != journal.records.size(): return fail("assistant latest request differs from sequence")
	return {"ok": true}

static func _validate_assistant_advice(raw: Dictionary) -> Dictionary:
	var memory: Variant = raw.get("assistant_advice_state", {})
	if not memory is Dictionary: return fail("invalid assistant advice state")
	if memory.is_empty():
		return fail("current save lost assistant advice state") if raw.get("campaign_id") == "anshi_beta_1_14" else {"ok": true}
	if memory.get("principal_id") != raw.get("player_character_id") or not amount(memory.get("summary_days"), true) or not amount(memory.get("last_summary_day")) or int(memory.last_summary_day) > int(raw.current_day) or not memory.get("frequencies") is Dictionary or not memory.get("last_issued_days") is Dictionary or not memory.get("suggestions") is Dictionary: return fail("assistant advice lost owner, preferences or schedule")
	for category in ["business", "hiring", "task_risk"]:
		if memory.frequencies.get(category) not in ["regular", "less", "off"]: return fail("invalid assistant advice frequency")
	for category in memory.last_issued_days:
		if not memory.frequencies.has(category) or not amount(memory.last_issued_days[category]) or int(memory.last_issued_days[category]) > int(raw.current_day): return fail("invalid advice publication time")
	for id in memory.suggestions:
		var record: Variant = memory.suggestions[id]
		if not record is Dictionary or record.get("suggestion_id") != id or record.get("category") not in ["business", "hiring", "task_risk"] or record.get("status") not in ["pending", "deferred", "dismissed", "expired", "accepted"] or not raw.character_states.has(record.get("assistant_id")) or not amount(record.get("binding_revision"), true): return fail("invalid assistant suggestion identity or status")
		for field in ["target_id", "reason_key", "fingerprint", "basis_text", "benefit", "task_id"]:
			if not record.get(field) is String: return fail("assistant suggestion lost evidence")
		if not amount(record.get("created_day")) or int(record.created_day) > int(raw.current_day) or not amount(record.get("defer_until_day")) or not amount(record.get("priority")) or not record.get("dto") is Dictionary: return fail("assistant suggestion lost timing or proposal")
		var parsed: Dictionary = load("res://scripts/ai/assistant_plan_parser.gd").new().parse(record.dto)
		if not parsed.get("ok", false) or record.dto.kind != ("advice" if record.category == "task_risk" else "proposal") or (record.status == "deferred" and int(record.defer_until_day) <= int(record.created_day)): return fail("assistant suggestion lost its structured proposal or deferral")
		var evidence: Dictionary = record.duplicate(true)
		for field in ["suggestion_id", "fingerprint", "status", "created_day", "defer_until_day", "task_id"]: evidence.erase(field)
		var digest := preload("res://scripts/core/canonical_json.gd").hash_value(evidence)
		if not digest.get("ok", false) or digest.hash != record.fingerprint or id != "advice:" + str(record.fingerprint): return fail("assistant suggestion differs from recorded evidence")
		if record.status == "accepted":
			if record.task_id != "assistant-task:adopt:" + str(record.suggestion_id) or not (raw.get("active_tasks", []) + raw.get("completed_tasks", [])).any(func(task): return task.get("task_kind") == "management" and task.get("task_id") == record.task_id and task.get("principal_id") == memory.principal_id): return fail("accepted suggestion lost actual task")
		elif record.task_id != "": return fail("unaccepted suggestion claims an executed task")
	return {"ok": true}
