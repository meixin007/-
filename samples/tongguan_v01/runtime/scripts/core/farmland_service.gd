extends RefCounted

const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Numbers = preload("res://scripts/core/public_works_service.gd")
const Season = preload("res://scripts/core/agricultural_season.gd")

static func fail(message: String) -> Dictionary: return {"ok": false, "error": message}
static func month_in(months: Array, month: int) -> bool: return months.any(func(value): return int(value) == month)
static func worker_available(state, field: Dictionary, cycle: String = "") -> bool:
	var person: String = field.owner_ref.entity_id
	return Presence.present(state, person, field.location_id) and Accounts.new().can_operate(state, person + "_rations", person) and not Workload.occupied_today(state, person, cycle, person, "cultivation")

# Called inside the existing daily world transaction, before household food use.
# Landowners act on their own crop and supplies; this grants no prefect ownership.
static func settle_daily(state) -> Dictionary:
	var fields: Array = state.management_assets.values().filter(func(field): return field.get("asset_kind") == "farmland" and field.has("crop_rule"))
	fields.sort_custom(func(a, b): return str(a.asset_id) < str(b.asset_id))
	for field in fields:
		var progress: Dictionary = field.cultivation
		if int(progress.last_update_day) >= int(state.current_day): continue
		progress.last_update_day = int(state.current_day)
		var order: Dictionary = state.economic_contracts.get(progress.get("active_cycle_id", ""), {})
		if order.is_empty() or order.status in ["harvested", "failed"]:
			if not month_in(field.crop_rule.plant_months, int(state.current_date.month)):
				progress.blocked_reason = "尚未到播种月份。"
				continue
			if int(progress.last_season_year) >= Season.season_year(field.crop_rule, state.current_date): continue
			if not worker_available(state, field):
				progress.blocked_reason = "田主离场或今日劳力另有占用，尚未播种。"
				continue
			if Accounts.new().available(state, str(field.owner_ref.entity_id) + "_rations") < int(field.crop_rule.seed_units):
				progress.blocked_reason = "自家实际粮食不足留种，尚未播种。"
				continue
			var started := _plant(state, field)
			if not started.ok: return started
			continue
		if not Season.within(order.recipe, int(order.season_year), state.current_date):
			order.status = "failed"
			order.failure_code = "out_of_season"
			order["ended_day"] = int(state.current_day)
			order.blocked_reason = "已错过本季生长与收割窗口，种粮和已做工日不能返还。"
			progress.blocked_reason = order.blocked_reason
			continue
		if order.growth_log.size() < int(order.recipe.growth_days):
			var water := _water_at(state, field, int(state.current_day))
			order.growth_log.append({"day": int(state.current_day), "date": state.current_date.duplicate(true), "water_supply": water.water_supply, "water_source_contract_id": water.water_source_contract_id})
		if order.growth_log.size() == int(order.recipe.growth_days): order.status = "mature"
		var can_work := worker_available(state, field, order.contract_id)
		if int(order.work_days) < 2 and can_work:
			_record_work(state, order, "tend")
			can_work = false
		if order.status == "mature" and int(order.work_days) < 2:
			order.status = "failed"
			order.failure_code = "untended"
			order["ended_day"] = int(state.current_day)
			order.blocked_reason = "整个生长期缺少实际照料，本季失收；不能在收割日补记此前农活。"
			progress.blocked_reason = order.blocked_reason
			continue
		order.blocked_reason = "等待作物生长。" if order.status == "growing" else "等待收割月份、农户到场和空闲工日。"
		if order.status == "mature" and month_in(order.recipe.harvest_months, int(state.current_date.month)) and int(order.work_days) == 2 and can_work:
			var harvested := _harvest(state, field, order)
			if not harvested.ok: return harvested
		progress.blocked_reason = order.blocked_reason
	return {"ok": true}

static func _record_work(state, order: Dictionary, kind: String) -> void:
	Workload.record_work(state, order)
	order.work_log[-1]["date"] = state.current_date.duplicate(true)
	order.work_log[-1]["kind"] = kind

static func _plant(state, field: Dictionary) -> Dictionary:
	var year := Season.season_year(field.crop_rule, state.current_date)
	var id := "cultivation:%s:%d" % [field.asset_id, year]
	if state.economic_contracts.has(id): return fail("同一田地同季作物记录已存在")
	var person: String = field.owner_ref.entity_id
	var rule: Dictionary = field.crop_rule
	var seed := Accounts.new().apply(state, "consume", {"execution_id": "seed:" + id, "account_id": person + "_rations", "actor_id": person, "amount": int(rule.seed_units), "reason_ref": "rule:crop_seed:" + id})
	if not seed.ok: return seed
	var order := {"contract_id": id, "contract_kind": "cultivation", "terms_version": 1, "status": "growing", "field_id": field.asset_id, "supplier_id": person, "owner_id": person, "recipe": rule.duplicate(true), "created_day": int(state.current_day), "created_date": state.current_date.duplicate(true), "season_year": year, "seed_receipt": seed.result_ref, "harvest_receipt": "", "harvest_units": 0, "growth_log": [], "work_log": [], "work_days": 0, "last_work_day": int(state.current_day), "blocked_reason": "等待作物生长。"}
	order["failure_code"] = ""
	_record_work(state, order, "plant")
	state.economic_contracts[id] = order
	field.contract_refs.append(id)
	field.cultivation.cycle_refs.append(id)
	field.cultivation.active_cycle_id = id
	field.cultivation.last_season_year = int(order.season_year)
	field.cultivation.blocked_reason = order.blocked_reason
	return {"ok": true}

static func yield_units(field: Dictionary, order: Dictionary) -> int:
	if order.growth_log.size() != int(order.recipe.growth_days): return 0
	var water := 0
	for row in order.growth_log: water += int(row.water_supply)
	return int(field.area_units) * int(order.recipe.units_per_area) * water / (100 * int(order.recipe.growth_days))

static func _harvest(state, field: Dictionary, order: Dictionary) -> Dictionary:
	var amount := yield_units(field, order)
	var account_id := str(order.owner_id) + "_rations"
	var account: Dictionary = state.resource_accounts[account_id]
	var balance := Accounts.new().balance(state, account_id)
	if balance > 1000000000 - amount: return fail("收粮超过实际粮仓记账容量，本日日结未提交")
	var receipt := "harvest:" + str(order.contract_id)
	if state.resource_journal.has(receipt): return fail("收获凭据已存在，不能重复入粮")
	_record_work(state, order, "harvest")
	if amount > 0:
		Storage.write_balance(state, account.storage_ref, balance + amount)
		var rule := "rule:crop_harvest:" + str(order.contract_id)
		state.resource_journal[receipt] = {"entry_id": receipt, "execution_id": receipt, "entry_kind": "rule_income", "source_ref": {"entity_kind": "rule", "entity_id": rule, "rule_id": rule}, "destination_account_id": account_id, "destination_ref": account.owner_ref.duplicate(true), "amount": amount, "unit_id": "ration_unit", "reason_ref": rule, "day": int(state.current_day)}
	order.status = "harvested"
	order.harvest_units = amount
	order.harvest_receipt = receipt if amount > 0 else ""
	order["ended_day"] = int(state.current_day)
	order["harvest_date"] = state.current_date.duplicate(true)
	order.blocked_reason = "本季已收割，收粮归农户；下季仍需实际种粮与劳力。"
	return {"ok": true}

static func project(state, person: String) -> Array:
	var result: Array = []
	for field in state.management_assets.values():
		if field.get("asset_kind") != "farmland" or not field.has("crop_rule"): continue
		var office: Dictionary = state.office_state.get(field.get("administration_office_id"), {})
		if person != field.owner_ref.entity_id and (office.get("status") != "appointed" or office.get("holder_id") != person or not Presence.present(state, person, field.location_id)): continue
		var order: Dictionary = state.economic_contracts.get(field.cultivation.active_cycle_id, {})
		var farmer: Dictionary = state.character_states[field.owner_ref.entity_id]
		result.append({"asset_id": field.asset_id, "name": field.name, "owner_id": field.owner_ref.entity_id, "owner_name": farmer.name, "area_units": field.area_units, "water_supply": field.water_supply, "crop_name": field.crop_rule.name, "growth_days": field.crop_rule.growth_days, "seed_units": field.crop_rule.seed_units, "status": order.get("status", "unplanted"), "observed_growth_days": order.get("growth_log", []).size(), "work_days": order.get("work_days", 0), "harvest_units": order.get("harvest_units", 0), "harvest_day": order.get("ended_day", null) if order.get("status") == "harvested" else null, "blocked_reason": field.cultivation.blocked_reason, "public_expression": farmer.get("life_goal", {}).get("public_expression", "") if Presence.present(state, field.owner_ref.entity_id, field.location_id) else "农户未在场，生活近况待核实。", "source_refs": [field.asset_id] + field.cultivation.cycle_refs.duplicate()})
		result[-1]["plant_months"] = field.crop_rule.plant_months.duplicate()
		result[-1]["harvest_months"] = field.crop_rule.harvest_months.duplicate()
		result[-1]["growth_observations"] = order.get("growth_log", []).duplicate(true)
		result[-1]["work_records"] = order.get("work_log", []).duplicate(true)
	return result

static func _water_at(raw, field: Dictionary, day: int) -> Dictionary:
	var canal: Dictionary = raw.management_assets.get(field.get("irrigation_canal_id"), {})
	var work: Dictionary = raw.economic_contracts.get(canal.get("active_contract_id"), {})
	# A full growing day uses the canal accepted before that day, independent of
	# whether today's manual/queued acceptance happens before or after settlement.
	if work.get("status") == "accepted" and int(work.get("accepted_day", 1000000000)) < day:
		return {"water_supply": int(canal.repaired_water_supply), "water_source_contract_id": str(work.contract_id)}
	return {"water_supply": int(field.base_water_supply), "water_source_contract_id": ""}

static func validate(raw: Dictionary) -> Dictionary:
	for field in raw.management_assets.values():
		if field.get("asset_kind") != "farmland" or not field.has("crop_rule"): continue
		var rule: Variant = field.crop_rule
		var progress: Variant = field.get("cultivation")
		if not rule is Dictionary or not progress is Dictionary or not rule.get("name") is String or not str(rule.get("source_id", "")).begins_with("scenario:") or field.owner_ref.get("entity_kind") != "character": return fail("农田作物规则缺少农户或来源")
		for key in ["seed_units", "growth_days", "units_per_area"]:
			if not Numbers.number(rule.get(key), 1, 1000): return fail("农田投入、工期或单产单位无效")
		if int(field.area_units) > 1000000 or int(field.area_units) * int(rule.units_per_area) > 1000000000: return fail("田地面积或作物上限越界")
		var calendar := Season.validate(rule)
		if not calendar.ok: return calendar
		if raw.resource_accounts.get(str(field.owner_ref.entity_id) + "_rations", {}).get("owner_ref") != field.owner_ref or Accounts.new().location(raw, str(field.owner_ref.entity_id) + "_rations") != field.location_id: return fail("田地没有农户在场粮仓")
		var office: Dictionary = raw.office_state.get(field.get("administration_office_id"), {})
		if office.get("office_kind") != "regional" or office.get("scope_ref", {}).get("entity_id") != field.location_id: return fail("农田登记缺少实际地方辖权")
		if not progress.get("cycle_refs") is Array or not progress.get("active_cycle_id") is String or not progress.get("blocked_reason") is String or not Numbers.number(progress.get("last_update_day")) or int(progress.last_update_day) > int(raw.current_day) or not Numbers.number(progress.get("last_season_year")): return fail("农田日结游标无效")
		var season := 0
		for id in progress.cycle_refs:
			var cycle: Dictionary = raw.economic_contracts.get(id, {})
			if cycle.get("contract_kind") != "cultivation" or cycle.get("field_id") != field.asset_id or not Numbers.number(cycle.get("season_year"), 1) or int(cycle.season_year) <= season or not field.contract_refs.has(id): return fail("农田重复记季或丢失种植记录")
			season = int(cycle.season_year)
		if season != int(progress.last_season_year) or progress.active_cycle_id != ("" if progress.cycle_refs.is_empty() else progress.cycle_refs.back()): return fail("农田生长游标与真实季次不符")
	for order in raw.economic_contracts.values():
		if order.get("contract_kind") != "cultivation": continue
		var valid := _validate_cycle(raw, order)
		if not valid.ok: return valid
	for entry in raw.resource_journal.values():
		var reason := str(entry.get("reason_ref", ""))
		if reason.begins_with("rule:crop_seed:") or reason.begins_with("rule:crop_harvest:"):
			var id := reason.trim_prefix("rule:crop_seed:").trim_prefix("rule:crop_harvest:")
			var order: Dictionary = raw.economic_contracts.get(id, {})
			if order.get("contract_kind") != "cultivation" or entry.entry_id not in [order.get("seed_receipt"), order.get("harvest_receipt")]: return fail("农田收支失去真实作物记录")
	return {"ok": true}

static func _validate_cycle(raw: Dictionary, order: Dictionary) -> Dictionary:
	var field: Dictionary = raw.management_assets.get(order.get("field_id"), {})
	if field.get("asset_kind") != "farmland" or not field.has("crop_rule") or order.get("recipe") != field.crop_rule or not field.cultivation.cycle_refs.has(order.contract_id) or order.get("owner_id") != field.owner_ref.entity_id or order.get("supplier_id") != order.owner_id or order.get("terms_version") != 1 or order.get("status") not in ["growing", "mature", "harvested", "failed"]: return fail("作物季次失去实际田地、农户、规则或状态")
	for key in ["created_day", "work_days", "last_work_day", "harvest_units"]:
		if not Numbers.number(order.get(key)): return fail("作物工日或产量无效")
	var origin := Numbers.date_serial(order.get("created_date"))
	if origin < 0 or Numbers.date_serial(raw.current_date) != origin + int(raw.current_day) - int(order.created_day) or not Season.within(order.recipe, int(order.season_year), order.created_date) or not month_in(order.recipe.plant_months, int(order.created_date.month)): return fail("播种日、季次或实际日历不一致")
	if order.contract_id != "cultivation:%s:%d" % [field.asset_id, int(order.season_year)]: return fail("作物编号与田地实际生产季不符")
	if not order.get("growth_log") is Array or order.growth_log.size() > int(order.recipe.growth_days) or not order.get("work_log") is Array or order.work_log.size() != int(order.work_days) or int(order.work_days) not in [1, 2, 3] or not order.get("blocked_reason") is String: return fail("生长或劳力记录缺失或越界")
	var previous := int(order.created_day)
	for row in order.growth_log:
		if not row is Dictionary or not Numbers.number(row.get("day")) or int(row.day) <= previous or int(row.day) > int(raw.current_day) or Numbers.date_serial(row.get("date")) < 0 or Numbers.date_serial(row.get("date")) != origin + int(row.day) - int(order.created_day) or not Season.within(order.recipe, int(order.season_year), row.date): return fail("生长日序或生长季无效")
		var water := _water_at(raw, field, int(row.day))
		if row.get("water_supply") != water.water_supply or row.get("water_source_contract_id") != water.water_source_contract_id: return fail("作物供水回填了未验收或事后水利")
		previous = int(row.day)
	var kinds := ["plant", "tend", "harvest"]
	for index in order.work_log.size():
		var row: Variant = order.work_log[index]
		if not row is Dictionary or row.get("kind") != kinds[index] or not Numbers.number(row.get("day")) or Numbers.date_serial(row.get("date")) < 0 or Numbers.date_serial(row.date) != origin + int(row.day) - int(order.created_day): return fail("农户工序与实际日历不一致")
	if order.work_log[0].day != order.created_day or order.last_work_day != order.work_log.back().day: return fail("播种或最后农活缺少当日工时")
	var seed: Dictionary = raw.resource_journal.get(order.get("seed_receipt"), {})
	if seed.get("entry_kind") != "rule_consumption" or seed.get("source_account_id") != str(order.owner_id) + "_rations" or seed.get("amount") != order.recipe.seed_units or seed.get("reason_ref") != "rule:crop_seed:" + str(order.contract_id) or seed.get("day") != order.created_day: return fail("种粮没有从实际农户库存扣除")
	if order.status == "growing" and order.growth_log.size() >= int(order.recipe.growth_days): return fail("生长阶段与累计天数不一致")
	if order.status in ["mature", "harvested"] and order.growth_log.size() != int(order.recipe.growth_days): return fail("收割缺少实际生长期")
	if order.status != "harvested":
		if order.harvest_units != 0 or order.get("harvest_receipt") != "" or int(order.work_days) == 3: return fail("未收割作物提前入粮")
		if order.status == "failed" and (not Numbers.number(order.get("ended_day")) or int(order.ended_day) < previous or int(order.ended_day) > int(raw.current_day)): return fail("绝收记录缺少实际日期")
		if order.status == "failed":
			var ended_serial := origin + int(order.ended_day) - int(order.created_day)
			if order.get("failure_code") == "out_of_season":
				if Season.within(order.recipe, int(order.season_year), Season.at_serial(ended_serial)): return fail("未超出生长季却声称错过农时")
			elif order.get("failure_code") == "untended":
				if int(order.work_days) != 1 or order.growth_log.size() != int(order.recipe.growth_days) or order.ended_day != order.growth_log.back().day: return fail("失收缺少实际生长期或劳力依据")
			else: return fail("作物失收原因未知")
	else:
		if int(order.work_days) != 3 or order.get("ended_day") != order.last_work_day or int(order.ended_day) < previous or Numbers.date_serial(order.get("harvest_date")) < 0 or Numbers.date_serial(order.harvest_date) != origin + int(order.ended_day) - int(order.created_day) or not Season.within(order.recipe, int(order.season_year), order.harvest_date) or not month_in(order.recipe.harvest_months, int(order.harvest_date.month)) or order.harvest_units != yield_units(field, order): return fail("收获缺少工序、农时或实际供水依据")
		if int(order.harvest_units) > 0:
			var harvested: Dictionary = raw.resource_journal.get(order.get("harvest_receipt"), {})
			if harvested.get("entry_kind") != "rule_income" or harvested.get("destination_account_id") != str(order.owner_id) + "_rations" or harvested.get("amount") != order.harvest_units or harvested.get("reason_ref") != "rule:crop_harvest:" + str(order.contract_id) or harvested.get("day") != order.ended_day: return fail("收获没有进入实际农户粮仓")
		elif order.get("harvest_receipt") != "": return fail("零收获不能伪造入粮凭据")
	if order.status != "failed" and order.get("failure_code") != "": return fail("非失收作物存在矛盾的失败原因")
	if order.work_log.size() > 1 and (order.growth_log.is_empty() or int(order.work_log[1].day) > int(order.growth_log.back().day)): return fail("作物照料不能补记在生长期以后")
	return {"ok": true}
