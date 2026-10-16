extends RefCounted
## Logical opportunities come from delivered world messages or actual personal
## income, never polling or transport results. Decision records are the history.
const MAX_DAILY_OPPORTUNITIES := 4
const MAX_ATTEMPTS := 3

static func slot_identity(slot: String) -> String:
	var parts := slot.split(":")
	# Read the previous baseline spelling without treating policy invalidation
	# as a new world event or a new budget. Existing record IDs stay intact.
	if parts.size() == 4 and parts[0] == "day" and parts[2] == "policy" and parts[1].is_valid_int() and parts[3].is_valid_int(): return "day:" + parts[1]
	return slot

static func next_slot(state, actor: String) -> String:
	var row: Dictionary = state.npc_ai_runtime.actors.get(actor, {})
	if row.get("pending_request_id", "") != "": return ""
	var day: int = state.current_day
	var attempts := {}
	var adopted := {}
	for record in state.npc_decision_records.values():
		if record.actor_id != actor or int(record.opened_day) != day: continue
		var logical_slot: String = slot_identity(record.slot_id)
		attempts[logical_slot] = int(attempts.get(logical_slot, 0)) + 1
		if record.status == "adopted": adopted[logical_slot] = true
	var events: Array[String] = []
	# Receipt of personal cash can make a previously impossible meal feasible.
	# Own transfers and private changes to someone else's accounts do not.
	for entry in state.resource_journal.values():
		if entry.get("entry_kind") == "transfer" and int(entry.get("day", -1)) == day and entry.get("destination_account_id") == actor + "_cash" and entry.get("actor_id", actor) != actor and int(entry.get("amount", 0)) > 0:
			events.append("income:%s:%s" % [day, str(entry.execution_id).sha256_text()])
	for agreement in state.economic_contracts.values():
		if agreement.get("contract_kind") != "social_agreement" or not agreement.get("participant_ids", []).has(actor): continue
		# Latest RECEIVED foreign response. Signing one's own response cannot
		# erase an unspent message opportunity when another offer was prioritized.
		# A remote counteroffer cannot open an opportunity before delivery.
		var responses: Array = agreement.responses
		for index in range(responses.size() - 1, -1, -1):
			var response: Dictionary = responses[index]
			var fact: String = "social-message:" + str(response.execution_id)
			var claim: Dictionary = state.information_claims.get(fact, {}).get(actor, {})
			if claim.is_empty() or response.actor_id == actor: continue
			if int(claim.get("known_day", -1)) == day and claim.get("payload", {}).get("status") in ["proposed", "countered", "accepted"]:
				events.append("message:%s:%s" % [day, fact.sha256_text()])
			break
	events.sort()
	for slot in events:
		if adopted.has(slot) or int(attempts.get(slot, 0)) >= MAX_ATTEMPTS: continue
		if attempts.has(slot) or attempts.size() < MAX_DAILY_OPPORTUNITIES: return slot
	if row.get("last_decision_day", -1) >= day: return ""
	# An exhausted delivered opportunity cannot evade its retry limit by
	# turning into an unrelated baseline opportunity in the same day.
	if not events.is_empty(): return ""
	var baseline := "day:%s" % day
	if adopted.has(baseline) or int(attempts.get(baseline, 0)) >= MAX_ATTEMPTS: return ""
	return baseline if attempts.has(baseline) or attempts.size() < MAX_DAILY_OPPORTUNITIES else ""
