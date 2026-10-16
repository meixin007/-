extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")

func can_operate(state, account_id: String, actor: String) -> bool:
	if state == null or actor.is_empty() or not state.resource_accounts.has(account_id) or not state.character_states.has(actor): return false
	var account: Dictionary = state.resource_accounts[account_id]
	if account.owner_ref.get("entity_kind") == "office" and account.storage_ref.get("storage_kind") == "depot":
		var office: Dictionary = state.office_state.get(account.owner_ref.entity_id, {})
		if office.get("status") != "appointed" or office.get("holder_id") != actor: return false
	return state.character_states[actor].get("status") not in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable", "defected", "irreconcilable"] and state.resource_accounts[account_id].operator_refs.any(func(ref): return ref.get("entity_kind") == "character" and ref.get("entity_id") == actor)

func balance(state, account_id: String) -> int:
	if not state.resource_accounts.has(account_id):
		return -1
	var ref: Dictionary = state.resource_accounts[account_id].storage_ref
	return Storage.balance(state, ref)

func location(state, account_id: String) -> String:
	return Storage.location(state, state.resource_accounts[account_id]) if state.resource_accounts.has(account_id) else ""

func available(state, account_id: String, reservation_id: String = "") -> int:
	if not state.resource_accounts.has(account_id):
		return -1
	var ref: Dictionary = state.resource_accounts[account_id].storage_ref
	var value := balance(state, account_id)
	for reservation in state.resource_reservations.values():
		if reservation.status == "active" and reservation.reservation_id != reservation_id and state.resource_accounts[reservation.account_id].storage_ref == ref:
			value -= int(reservation.remaining_amount)
	return value

func reserve(context, request: Dictionary) -> Dictionary:
	return _execute(context, "reserve", request)

func transfer(context, request: Dictionary) -> Dictionary:
	return _execute(context, "transfer", request)

func release(context, request: Dictionary) -> Dictionary:
	return _execute(context, "release", request)

func consume(context, request: Dictionary) -> Dictionary:
	return _execute(context, "consume", request)

func _execute(context, action: String, request: Dictionary) -> Dictionary:
	if context == null or context.state == null or not request.get("execution_id") is String or str(request.execution_id).is_empty():
		return Contract.fail("resource action requires a stable execution_id")
	var input := request.duplicate(true)
	input["resource_action"] = action
	var transaction = Transaction.new()
	var preview: Dictionary = transaction.preview_command(context.state, "resource_action", input)
	if not preview.get("ok", false):
		return preview
	return transaction.execute_command(context, transaction.build_command_envelope("resource_action", input, preview.preview_token), func(working):
		var result: Dictionary = apply(working.state, action, input)
		if result.get("ok", false): load("res://scripts/core/regional_fiscal_service.gd").reconcile(working.state)
		return result
	)

# Internal rule operation, used only inside a shared world transaction.
func apply(state, action: String, request: Dictionary) -> Dictionary:
	var actor := str(request.get("actor_id", ""))
	var account_id := str(request.get("source_account_id", request.get("account_id", "")))
	var reservation_id := str(request.get("reservation_id", ""))
	if action == "release":
		if not state.resource_reservations.has(reservation_id):
			return Contract.fail("reservation does not exist")
		account_id = state.resource_reservations[reservation_id].account_id
	if not state.resource_accounts.has(account_id) or not state.character_states.has(actor):
		return Contract.fail("missing resource account or actor")
	var account: Dictionary = state.resource_accounts[account_id]
	if not can_operate(state, account_id, actor) and not load("res://scripts/core/personal_estate_service.gd").permits_payment(state, action, request):
		return Contract.fail("actor has no authority over account: " + account_id)
	if action == "release":
		state.resource_reservations[reservation_id].remaining_amount = 0
		state.resource_reservations[reservation_id].status = "released"
		return {"ok": true, "result_ref": reservation_id}
	if not Contract.amount(request.get("amount"), true):
		return Contract.fail("amount must be a positive bounded integer")
	var value := int(request.amount)
	if action == "consume":
		var execution := str(request.get("execution_id", ""))
		var rule := str(request.get("reason_ref", ""))
		if execution.is_empty() or not rule.begins_with("rule:") or rule.length() <= 5:
			return Contract.fail("资源消耗必须引用具体规则及执行标识")
		if state.resource_journal.has(execution):
			var prior: Dictionary = state.resource_journal[execution]
			return {"ok": true, "result_ref": execution, "code": "idempotent_replay"} if prior.get("entry_kind") == "rule_consumption" and prior.get("source_account_id") == account_id and prior.get("amount") == value and prior.get("reason_ref") == rule else Contract.fail("同一执行标识不能改写消费")
		if not reservation_id.is_empty():
			var held: Dictionary = state.resource_reservations.get(reservation_id, {})
			if held.get("account_id") != account_id or held.get("status") != "active" or held.get("task_id") != request.get("task_id") or int(held.get("remaining_amount", 0)) < value:
				return Contract.fail("规则消费不能占用其他任务或已经耗尽的预留")
		if available(state, account_id, reservation_id) < value:
			return Contract.fail("实际可用款不足；其他事务已预留的款项不能挪作本次消费")
		Storage.write_balance(state, account.storage_ref, balance(state, account_id) - value)
		if not reservation_id.is_empty():
			state.resource_reservations[reservation_id].remaining_amount -= value
			if state.resource_reservations[reservation_id].remaining_amount == 0:
				state.resource_reservations[reservation_id].status = "consumed"
		state.resource_journal[execution] = {"entry_id": execution, "execution_id": execution, "entry_kind": "rule_consumption", "source_account_id": account_id, "source_ref": account.owner_ref.duplicate(true), "destination_ref": {"entity_kind": "rule", "entity_id": rule, "rule_id": rule}, "amount": value, "unit_id": account.unit_id, "reason_ref": rule, "day": int(state.current_day)}
		if not reservation_id.is_empty():
			state.resource_journal[execution]["reservation_id"] = reservation_id
			state.resource_journal[execution]["task_id"] = request.task_id
		return {"ok": true, "result_ref": execution}
	if action == "resize":
		var reservation: Dictionary = state.resource_reservations.get(reservation_id, {})
		if reservation.get("account_id") != account_id or reservation.get("status") not in ["active", "consumed"]:
			return Contract.fail("只能调整尚未释放的同源预留")
		var spent: int = int(reservation.amount) - int(reservation.remaining_amount)
		if value < spent or available(state, account_id, reservation_id) < value - spent:
			return Contract.fail("新限额不能低于已花金额，也不能超过实际可用资金")
		reservation.amount = value
		reservation.remaining_amount = value - spent
		reservation.status = "active" if value > spent else "consumed"
		return {"ok": true, "result_ref": reservation_id}
	if action == "reserve":
		if str(request.get("task_id", "")).is_empty() or state.resource_reservations.has(request.execution_id):
			return Contract.fail("missing task or duplicate reservation")
		if available(state, account_id) < value:
			return Contract.fail("insufficient available funds; existing tasks reserve this account")
		state.resource_reservations[request.execution_id] = {"reservation_id": request.execution_id, "task_id": request.task_id, "account_id": account_id, "amount": value, "remaining_amount": value, "status": "active"}
		return {"ok": true, "result_ref": request.execution_id}
	if action != "transfer":
		return Contract.fail("unknown resource action")
	var target_id := str(request.get("destination_account_id", ""))
	if not state.resource_accounts.has(target_id) or str(request.get("reason_ref", "")).is_empty():
		return Contract.fail("payment requires a destination and rule/contract reason")
	var target: Dictionary = state.resource_accounts[target_id]
	if target.unit_id != account.unit_id or target.storage_ref == account.storage_ref:
		return Contract.fail("payment requires distinct storage and equal units")
	if Storage.location(state, account).is_empty() or Storage.location(state, account) != Storage.location(state, target):
		return Contract.fail("remote payment requires a transport and delivery contract")
	if not reservation_id.is_empty():
		var reservation: Dictionary = state.resource_reservations.get(reservation_id, {})
		if reservation.get("account_id") != account_id or reservation.get("status") != "active" or int(reservation.get("remaining_amount", 0)) < value:
			return Contract.fail("reservation is missing, exhausted or belongs to another account")
	if available(state, account_id, reservation_id) < value or balance(state, target_id) > Contract.MAX_AMOUNT - value:
		return Contract.fail("insufficient funds or destination amount overflow")
	Storage.write_balance(state, account.storage_ref, balance(state, account_id) - value)
	Storage.write_balance(state, target.storage_ref, balance(state, target_id) + value)
	if not reservation_id.is_empty():
		state.resource_reservations[reservation_id].remaining_amount -= value
		if state.resource_reservations[reservation_id].remaining_amount == 0:
			state.resource_reservations[reservation_id].status = "consumed"
	state.resource_journal[request.execution_id] = {"entry_id": request.execution_id, "execution_id": request.execution_id, "entry_kind": "transfer", "source_account_id": account_id, "destination_account_id": target_id, "source_ref": account.owner_ref.duplicate(true), "destination_ref": target.owner_ref.duplicate(true), "amount": value, "unit_id": account.unit_id, "reason_ref": request.reason_ref, "day": state.current_day}
	state.resource_journal[request.execution_id]["actor_id"] = str(request.actor_id)
	return {"ok": true, "result_ref": request.execution_id}
