extends RefCounted

# The shared wire catalog describes existing rules; it never calculates a second price.
const PROPERTY_BUSINESS_ADAPTERS := ["offer_land", "withdraw_land_offer", "buy_land", "offer_estate_property", "buy_estate_property", "offer_estate_operation", "buy_estate_operation", "withdraw_estate_offer", "contact_estate_property_buyer", "authorize_business_management", "revoke_business_management", "set_business_budget", "set_business_strategy", "handover_business_management"]
const ADAPTER_REFERENCE_DOMAINS := {"land_id": "assets", "building_id": "assets", "shop_id": "assets", "payee_account_id": "accounts", "funding_account_id": "accounts", "buyer_id": "characters", "candidate_id": "characters", "expected_manager_id": "characters", "expected_authorization_id": "authorizations"}
const PARAMETERS := {
	"authorize_business_management": ["shop_id", "monthly_limit", "loan_limit", "cash_floor"],
	"revoke_business_management": ["shop_id"],
	"set_business_budget": ["shop_id", "monthly_limit", "expected_authorization_id"],
	"set_business_strategy": ["shop_id", "strategy", "expected_authorization_id"],
	"handover_business_management": ["shop_id", "candidate_id", "wage_amount", "expected_manager_id"],
	"offer_estate_property": ["building_id", "amount", "duration_days", "valid_until_day", "payee_account_id"],
	"offer_estate_operation": ["building_id", "amount", "duration_days", "valid_until_day", "payee_account_id"],
	"buy_estate_property": ["building_id", "quote_version", "funding_account_id"],
	"buy_estate_operation": ["building_id", "quote_version", "funding_account_id"],
	"withdraw_estate_offer": ["building_id", "offer_kind"],
	"contact_estate_property_buyer": ["building_id", "quote_version", "buyer_id"],
	"offer_land": ["land_id", "amount", "valid_until_day", "payee_account_id"],
	"withdraw_land_offer": ["land_id"],
	"buy_land": ["land_id", "funding_account_id", "quote_version"],
	"cancel_management_task": ["task_id"],
	"resign_family": ["office_id"],
	"buy_food": ["stall_id", "funding_account_id", "lots"],
	"pay_marriage_dowry": ["match_id", "proposal_id"],
	"open_criminal_case": ["case_id", "fact_id", "jurisdiction_office_id"],
	"issue_criminal_verdict": ["case_id", "verdict"],
	"order_criminal_release": ["case_id"],
	"release_criminal_custody": ["case_id", "release_kind"],
	"petition_criminal_case": ["case_id", "request_text"],
	"visit_region": ["destination_id"],
	"respond_gift_delivery": ["delivery_id", "choice"],
	"cancel_gift_delivery": ["delivery_id"],
	"receive_gift_report": ["delivery_id"],
	"offer_social_agreement": ["agreement_id", "candidate_id", "purpose", "terms"],
	"respond_social_agreement": ["agreement_id", "terms_version", "choice", "counter_terms"],
	"fulfill_social_agreement": ["agreement_id", "terms_version"],
	"decline_official_initiative": ["office_id", "initiative_id"],
	"issue_local_levy": ["office_id", "levy_id", "policy"],
	"remit_local_levy": ["office_id", "levy_id", "person_id"],
	"inquire_marriage": ["match_id", "proposal_id", "offered_gift"],
	"receive_marriage_terms": ["match_id", "proposal_id"],
	"accept_marriage_terms": ["match_id", "proposal_id"],
	"deliver_marriage_gift": ["match_id", "proposal_id"],
	"complete_marriage": ["match_id", "proposal_id"],
	"send_official_envoy": ["journey_id", "person_id", "target_depot_id", "funding_account_id"],
	"receive_official_report": ["journey_id", "person_id", "target_depot_id"],
	"commission_grain_transport": ["order_id", "source_depot_id", "target_depot_id", "grain_amount"],
	"await_grain_report": ["order_id", "source_depot_id", "target_depot_id"],
	"send_exam_candidate": ["school_id", "student_id", "journey_id", "funding_account_id"],
	"receive_exam_arrival_report": ["school_id", "journey_id"],
	"sponsor_school_student": ["school_id", "student_id", "aid_id", "funding_account_id"],
	"commission_school_supply": ["school_id", "supply_id", "order_id", "funding_account_id"],
	"receive_school_supply": ["school_id", "order_id"],
	"open_school_assessment": ["school_id", "assessment_id", "funding_account_id"],
	"register_school_candidate": ["school_id", "assessment_id", "student_id"],
	"hire_school_teacher": ["school_id", "teacher_id", "funding_account_id", "contract_id"],
	"enroll_school_student": ["school_id", "student_id", "enrollment_id"],
	"repay_public_cash": ["case_id", "funding_account_id", "amount"],
	"start_public_work": ["canal_id", "funding_account_id", "order_id"],
	"finish_public_work": ["order_id"],
	"appoint_office": ["office_id", "candidate_id", "mode"],
	"dismiss_office": ["office_id", "holder_id"],
	"force_dismiss_office": ["office_id", "holder_id"],
	"start_character_search": ["search_id", "location_id", "archetype_id", "target_role", "specialty", "duration_days"],
	"finish_character_search": ["search_id"],
	"commission_production": ["workshop_id", "recipe_id", "funding_account_id", "order_id"],
	"collect_production": ["order_id"],
	"equip_item": ["item_id", "equipped"],
	"give_item": ["item_id", "recipient_id"],
	"rent_shop": ["building_id", "shop_id", "funding_account_id", "office_id"],
	"hire_family": ["office_id", "candidate_id"],
	"hire_family_from_pool": ["office_id", "candidate_ids", "wage_amount", "period_days"],
	"dismiss_family": ["office_id"],
	"offer_family_wage": ["office_id", "amount"],
	"pay_employment_debt": ["office_id", "contract_id"],
	"prepare_pawnshop": ["shop_id", "funding_account_id"],
	"fund_pawnshop": ["shop_id", "funding_account_id", "amount"],
	"open_pawnshop": ["shop_id"], "close_pawnshop": ["shop_id"],
	"issue_pawn_loan": ["shop_id", "collateral_id", "borrower_id"],
	"redeem_pawn": ["shop_id", "loan_id"], "dispose_pawn": ["shop_id", "loan_id"],
	"transfer_cash": ["source_account_id", "destination_account_id", "amount"]
}
const DOMAINS := {
	"cancel_management_task": "scripts/core/action_authorization_service.gd",
	"open_criminal_case": "scripts/core/criminal_case_service.gd",
	"issue_criminal_verdict": "scripts/core/criminal_case_service.gd",
	"order_criminal_release": "scripts/core/criminal_case_service.gd",
	"release_criminal_custody": "scripts/core/criminal_case_service.gd",
	"petition_criminal_case": "scripts/core/criminal_case_service.gd",
	"respond_gift_delivery": "scripts/core/gift_delivery_service.gd",
	"cancel_gift_delivery": "scripts/core/gift_delivery_service.gd",
	"receive_gift_report": "scripts/core/gift_delivery_service.gd",
	"offer_social_agreement": "scripts/core/social_agreement_service.gd",
	"respond_social_agreement": "scripts/core/social_agreement_service.gd",
	"fulfill_social_agreement": "scripts/core/social_agreement_service.gd",
	"rent_shop": "scripts/core/pawnshop_service.gd",
	"establish_owned_pawnshop": "scripts/core/pawnshop_service.gd",
	"establish_owned_retail": "scripts/core/pawnshop_service.gd",
	"establish_owned_manufacturing": "scripts/core/pawnshop_service.gd",
	"establish_owned_farm": "scripts/core/pawnshop_service.gd",
	"establish_owned_modeled": "scripts/core/pawnshop_service.gd",
	"prepare_pawnshop": "scripts/core/pawnshop_service.gd",
	"fund_pawnshop": "scripts/core/pawnshop_service.gd",
	"open_pawnshop": "scripts/core/pawnshop_service.gd",
	"close_pawnshop": "scripts/core/pawnshop_service.gd",
	"issue_pawn_loan": "scripts/core/pawnshop_service.gd",
	"redeem_pawn": "scripts/core/pawnshop_service.gd",
	"dispose_pawn": "scripts/core/pawnshop_service.gd",
	"equip_item": "scripts/core/managed_item_service.gd",
	"give_item": "scripts/core/managed_item_service.gd",
	"start_public_work": "scripts/core/public_works_service.gd",
	"finish_public_work": "scripts/core/public_works_service.gd",
	"present_official_initiative": "scripts/core/official_initiative_service.gd",
	"decline_official_initiative": "scripts/core/official_initiative_service.gd",
	"issue_local_levy": "scripts/core/local_fiscal_policy_service.gd",
	"remit_local_levy": "scripts/core/local_fiscal_policy_service.gd",
	"pay_local_levy": "scripts/core/local_fiscal_policy_service.gd",
	"repay_public_cash": "scripts/core/regional_fiscal_service.gd",
	"open_school_assessment": "scripts/core/school_assessment_service.gd",
	"register_school_candidate": "scripts/core/school_assessment_service.gd",
	"commission_school_supply": "scripts/core/school_supply_service.gd",
	"receive_school_supply": "scripts/core/school_supply_service.gd",
	"send_exam_candidate": "scripts/core/exam_journey_service.gd",
	"receive_exam_arrival_report": "scripts/core/exam_journey_service.gd",
	"commission_grain_transport": "scripts/core/regional_grain_service.gd",
	"await_grain_report": "scripts/core/regional_grain_service.gd",
	"continue_as_successor": "scripts/core/player_succession_service.gd",
	"partition_household": "scripts/core/family_partition_service.gd",
	"record_personal_estate": "scripts/core/personal_estate_service.gd",
	"settle_personal_estate": "scripts/core/personal_estate_service.gd",
	"request_estate_settlement": "scripts/core/personal_estate_service.gd",
	"collect_estate_production": "scripts/core/personal_estate_service.gd",
	"handover_clan_head": "scripts/core/clan_succession_service.gd",
	"assume_clan_head": "scripts/core/clan_succession_service.gd",
	"inquire_marriage": "scripts/core/marriage_service.gd",
	"receive_marriage_terms": "scripts/core/marriage_service.gd",
	"accept_marriage_terms": "scripts/core/marriage_service.gd",
	"deliver_marriage_gift": "scripts/core/marriage_service.gd",
	"pay_marriage_dowry": "scripts/core/marriage_service.gd",
	"complete_marriage": "scripts/core/marriage_service.gd",
	"send_official_envoy": "scripts/core/official_journey_service.gd",
	"receive_official_report": "scripts/core/official_journey_service.gd",
	"sponsor_school_student": "scripts/core/school_living_aid_service.gd",
	"hire_school_teacher": "scripts/core/education_service.gd",
	"enroll_school_student": "scripts/core/education_service.gd",
	"commission_production": "scripts/core/production_service.gd",
	"collect_production": "scripts/core/production_service.gd",
	"start_character_search": "scripts/core/character_search_service.gd",
	"finish_character_search": "scripts/core/character_search_service.gd",
	"resolve_character_search": "scripts/core/character_search_service.gd",
	"appoint_office": "scripts/core/official_office_actions.gd",
	"dismiss_office": "scripts/core/official_office_actions.gd",
	"force_dismiss_office": "scripts/core/official_office_actions.gd",
	"start_construction": "scripts/core/estate_construction_service.gd",
	"cancel_construction": "scripts/core/estate_construction_service.gd",
	"resume_construction": "scripts/core/estate_construction_service.gd",
	"expand_estate": "scripts/core/estate_lifecycle_service.gd",
	"demolish_estate": "scripts/core/estate_lifecycle_service.gd",
	"refit_estate": "scripts/core/estate_lifecycle_service.gd",
	"buy_land": "scripts/core/land_property_service.gd",
	"offer_land": "scripts/core/land_property_service.gd",
	"withdraw_land_offer": "scripts/core/land_property_service.gd",
	"offer_land_lease": "scripts/core/land_property_service.gd",
	"lease_land": "scripts/core/land_property_service.gd",
	"end_land_lease": "scripts/core/land_property_service.gd",
	"offer_land_share": "scripts/core/land_property_service.gd",
	"approve_land_share_offer": "scripts/core/land_property_service.gd",
	"buy_land_share": "scripts/core/land_property_service.gd",
	"commission_business_batch": "scripts/core/manufacturing_business_service.gd",
	"sell_business_batch": "scripts/core/manufacturing_business_service.gd",
	"commission_farm_season": "scripts/core/managed_farming_service.gd",
	"sell_farm_product": "scripts/core/managed_farming_service.gd",
	"retail_restock": "scripts/core/retail_trading_service.gd",
	"retail_sale": "scripts/core/retail_trading_service.gd",
	"settle_business_month": "scripts/core/modeled_business_service.gd",
	"send_control_dispatch": "scripts/core/control_dispatch_actions.gd",
	"visit_region": "scripts/core/regional_visit_service.gd",
	"authorize_business_management": "scripts/core/business_management_service.gd",
	"revoke_business_management": "scripts/core/business_management_service.gd",
	"handover_business_management": "scripts/core/business_management_service.gd",
	"appoint_business_deputy": "scripts/core/business_management_service.gd",
	"remove_business_deputy": "scripts/core/business_management_service.gd",
	"set_business_strategy": "scripts/core/business_management_service.gd",
	"set_business_budget": "scripts/core/business_management_service.gd",
	"set_regional_business_budget": "scripts/core/business_management_service.gd",
	"distribute_business_surplus": "scripts/core/business_management_service.gd",
	"allocate_regional_business_budget": "scripts/core/regional_business_budget_service.gd",
	"set_portfolio_business_budget": "scripts/core/business_management_service.gd",
	"set_business_payroll": "scripts/core/business_management_service.gd",
	"renegotiate_business_wage": "scripts/core/business_management_service.gd",
	"set_business_profit_sharing": "scripts/core/business_management_service.gd",
	"coordinate_business_relations": "scripts/core/business_management_service.gd",
	"audit_business": "scripts/core/business_management_service.gd",
	"offer_estate_property": "scripts/core/estate_property_transaction_service.gd",
	"buy_estate_property": "scripts/core/estate_property_transaction_service.gd",
	"offer_estate_operation": "scripts/core/estate_property_transaction_service.gd",
	"buy_estate_operation": "scripts/core/estate_property_transaction_service.gd",
	"withdraw_estate_offer": "scripts/core/estate_property_transaction_service.gd",
	"contact_estate_property_buyer": "scripts/core/estate_property_transaction_service.gd",
	"hire_family": "scripts/core/family_office_rules.gd",
	"hire_family_from_pool": "scripts/core/family_office_rules.gd",
	"dismiss_family": "scripts/core/family_office_rules.gd",
	"resign_family": "scripts/core/family_office_rules.gd",
	"pay_employment_debt": "scripts/core/family_office_rules.gd",
	"offer_family_wage": "scripts/core/family_office_rules.gd",
	"transfer_cash": "scripts/core/resource_account_service.gd",
	"buy_food": "scripts/core/household_subsistence_service.gd"
}

static func description(kind: String) -> Dictionary:
	return {"action_kind": kind, "domain_service": DOMAINS.get(kind, ""), "status": "ready" if PARAMETERS.has(kind) else ("adapter_gap" if DOMAINS.has(kind) else "domain_gap"), "required_parameters": PARAMETERS.get(kind, []).duplicate(), "parameter_contract": parameter_contract(kind), "preview_entry": "game_action_dispatcher.validate_request", "execution_entry": "game_action_dispatcher.apply", "cost_entry": "game_action_dispatcher.cost_for", "result_contract": "action_receipts", "authority": "current actor and domain control; delegated actions require recorded consent", "process": "domain immediate result or existing task/contract"}

static func parameter_contract(kind: String) -> Dictionary:
	if kind not in PROPERTY_BUSINESS_ADAPTERS: return {}
	var result := {}
	for key in PARAMETERS[kind]:
		if ADAPTER_REFERENCE_DOMAINS.has(key):
			result[key] = {"type": "string", "reference_domain": ADAPTER_REFERENCE_DOMAINS[key], "reference_kind": "existing", "max_length": 256}
		elif key == "offer_kind": result[key] = {"type": "string", "enum": ["property", "operation"]}
		elif key == "strategy": result[key] = {"type": "string", "enum": load("res://scripts/core/business_strategy_rules.gd").MODES.keys()}
		else:
			var units := {"monthly_limit": "cash_unit_per_month", "duration_days": "days", "valid_until_day": "absolute_world_day", "quote_version": "version"}
			result[key] = {"type": "integer", "minimum": 0 if key in ["cash_floor", "valid_until_day"] else 1, "maximum": load("res://scripts/core/management_state_contract.gd").MAX_AMOUNT, "unit": units.get(key, "cash_unit")}
	return result

static func validate_scoped_parameters(action: Dictionary, read_set: Dictionary) -> Dictionary:
	for key in parameter_contract(str(action.get("action_kind", ""))):
		if not ADAPTER_REFERENCE_DOMAINS.has(key): continue
		var domain: String = ADAPTER_REFERENCE_DOMAINS[key]
		if not read_set.get(domain, []).has(action.get("parameters", {}).get(key)):
			return {"ok": false, "code": "npc_contract_error", "error": "NPC parameter requires a disclosed " + domain + " reference: " + key}
	return {"ok": true}

static func discover(offset: int = 0, limit: int = 256, domain: String = "") -> Array:
	var ids: Array = DOMAINS.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		if domain == "" or str(DOMAINS[id]).contains(domain): result.append(description(id))
	return result.slice(maxi(0, offset), maxi(0, offset) + clampi(limit, 0, 256))

static func produced_refs(action: Dictionary) -> Array:
	var fields: Array = {"offer_social_agreement": ["agreement_id"], "open_criminal_case": ["case_id"], "commission_production": ["order_id"], "inquire_marriage": ["proposal_id"], "send_official_envoy": ["journey_id"], "commission_grain_transport": ["order_id"], "send_exam_candidate": ["journey_id"], "sponsor_school_student": ["aid_id"], "commission_school_supply": ["order_id"], "open_school_assessment": ["assessment_id"], "hire_school_teacher": ["contract_id"], "enroll_school_student": ["enrollment_id"], "start_public_work": ["order_id"], "start_character_search": ["search_id"], "rent_shop": ["shop_id"]}.get(action.action_kind, [])
	return fields.map(func(field): return action.parameters.get(field, ""))

static func validate_selection(selection: Dictionary) -> Dictionary:
	var contract = load("res://scripts/core/npc_ai_state_contract.gd")
	if not contract.exact(selection, ["action_kind", "parameters", "target_refs"]) or not selection.action_kind is String:
		return contract.fail("selection may contain only action, parameters and target refs")
	var row := description(selection.action_kind)
	if row.status != "ready":
		return {"ok": false, "code": "unsupported_capability" if row.status == "domain_gap" else "adapter_gap", "error": "Action capability unavailable: " + selection.action_kind}
	if not contract.exact(selection.parameters, PARAMETERS[selection.action_kind]) or not selection.target_refs is Array or selection.target_refs.is_empty(): return contract.fail("action parameters do not match common catalog")
	if selection.action_kind in ["offer_land", "withdraw_land_offer", "buy_land"]:
		var params: Dictionary = selection.parameters
		if not contract.text_id(params.land_id): return contract.fail("invalid land identity")
		if selection.action_kind == "offer_land" and (not contract.whole(params.amount, 1) or not contract.whole(params.valid_until_day, 0) or not contract.text_id(params.payee_account_id)): return contract.fail("invalid land offer amount, expiry or payee")
		if selection.action_kind == "buy_land" and (not contract.whole(params.quote_version, 1) or not contract.text_id(params.funding_account_id)): return contract.fail("invalid land quote version or funding account")
	if selection.action_kind in ["offer_estate_property", "offer_estate_operation", "buy_estate_property", "buy_estate_operation", "withdraw_estate_offer", "contact_estate_property_buyer"]:
		var params: Dictionary = selection.parameters
		if not contract.text_id(params.building_id): return contract.fail("invalid estate identity")
		if selection.action_kind.begins_with("offer_") and (not contract.whole(params.amount, 1) or not contract.whole(params.duration_days, 1) or not contract.whole(params.valid_until_day, 0) or not contract.text_id(params.payee_account_id)): return contract.fail("invalid estate amount, duration, expiry or payee")
		if selection.action_kind.begins_with("buy_") and (not contract.whole(params.quote_version, 1) or not contract.text_id(params.funding_account_id)): return contract.fail("invalid estate quote or funding account")
		if selection.action_kind == "withdraw_estate_offer" and params.offer_kind not in ["property", "operation"]: return contract.fail("invalid estate offer kind")
		if selection.action_kind == "contact_estate_property_buyer" and (not contract.whole(params.quote_version, 1) or not contract.text_id(params.buyer_id)): return contract.fail("invalid estate buyer or quote")
	if selection.action_kind in ["authorize_business_management", "revoke_business_management", "set_business_budget", "set_business_strategy", "handover_business_management"]:
		var params: Dictionary = selection.parameters
		if not contract.text_id(params.shop_id): return contract.fail("invalid business identity")
		if selection.action_kind == "authorize_business_management" and (not contract.whole(params.monthly_limit, 1) or not contract.whole(params.loan_limit, 1) or not contract.whole(params.cash_floor, 0) or params.loan_limit > params.monthly_limit): return contract.fail("invalid business cash limits")
		if selection.action_kind in ["set_business_budget", "set_business_strategy"] and not contract.text_id(params.expected_authorization_id): return contract.fail("invalid current authorization")
		if selection.action_kind == "set_business_budget" and not contract.whole(params.monthly_limit, 1): return contract.fail("invalid monthly limit")
		if selection.action_kind == "set_business_strategy" and not load("res://scripts/core/business_strategy_rules.gd").valid(params.strategy): return contract.fail("invalid business strategy")
		if selection.action_kind == "handover_business_management" and (not contract.text_id(params.candidate_id) or not contract.text_id(params.expected_manager_id) or not contract.whole(params.wage_amount, 1)): return contract.fail("invalid manager handover or wage")
	for ref in selection.target_refs:
		if not contract.text_id(ref): return contract.fail("invalid action target reference")
	return {"ok": true}

static func preview(state, selection: Dictionary) -> Dictionary:
	var valid := validate_selection(selection)
	if not valid.ok: return valid
	return load("res://scripts/core/game_action_dispatcher.gd").cost_for(state, selection.action_kind, selection.parameters)
