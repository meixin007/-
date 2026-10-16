extends RefCounted

const Canonical = preload("res://scripts/core/canonical_json.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const MODES := ["focus_model", "related_rules", "background"]
const STATUSES := ["pending", "adopted", "superseded", "cancelled", "failed"]
const MAX_CONTEXT_PAGES := 3
const READ_FIELDS := ["characters", "accounts", "contracts", "tasks", "cases", "offices", "knowledge", "assets", "locations", "claims", "behavior", "observer_view", "authorizations", "observer_pages"]
const RUNTIME_FIELDS := ["schema_version", "policy_version", "request_sequence", "adoption_sequence", "model_service_sequence", "actors"]
const ACTOR_FIELDS := ["mode", "score", "below_since_day", "last_decision_day", "waiting_since_day", "cooldown_until_day", "pending_request_id", "model_service_order", "recent_failures"]
const RECORD_FIELDS := ["request_id", "slot_id", "actor_id", "player_character_id", "policy_version", "world_epoch", "status", "read_set", "read_fingerprint", "selection", "source", "adoption_order", "result_ref", "opened_day", "resolved_day"]

static func default_runtime() -> Dictionary:
	return {"schema_version": 2, "policy_version": 1, "request_sequence": 0, "adoption_sequence": 0, "model_service_sequence": 0, "actors": {}}

static func default_actor(day: int) -> Dictionary:
	return {"mode": "background", "score": 0, "below_since_day": -1, "last_decision_day": -1, "waiting_since_day": day, "cooldown_until_day": 0, "pending_request_id": "", "model_service_order": 0, "recent_failures": []}

static func validate(raw: Dictionary) -> Dictionary:
	if not raw.has("npc_ai_runtime") and not raw.has("npc_decision_records") and raw.get("campaign_id") != "anshi_beta_1_14":
		return {"ok": true}
	var runtime: Variant = raw.get("npc_ai_runtime")
	var records: Variant = raw.get("npc_decision_records")
	if not exact(runtime, RUNTIME_FIELDS) or not records is Dictionary:
		return fail("invalid NPC runtime fields")
	if runtime.schema_version != 2 or not Contract.amount(runtime.policy_version, true) or not Contract.amount(runtime.request_sequence) or not Contract.amount(runtime.adoption_sequence) or not Contract.amount(runtime.model_service_sequence) or not runtime.actors is Dictionary:
		return fail("invalid NPC runtime version or counters")
	var characters: Dictionary = raw.get("character_states", {})
	var orders: Array = []
	var slots: Array = []
	var opportunity_counts := {}
	var opportunity_pages := {}
	var adopted_slots: Array = []
	for id in records:
		var record: Variant = records[id]
		if not exact(record, RECORD_FIELDS) or not text_id(id) or record.request_id != id or not text_id(record.slot_id) or not text_id(record.world_epoch):
			return fail("invalid NPC decision identity")
		if not characters.has(record.actor_id) or not characters.has(record.player_character_id) or record.status not in STATUSES or record.source not in ["", "model", "rule"]:
			return fail("invalid NPC actor, status or source")
		var sequence: int = int(str(id).get_slice(":", 1))
		if sequence < 1 or sequence > int(runtime.request_sequence) or id != "npc-request:%s:%s" % [sequence, record.actor_id]: return fail("NPC stable request sequence was changed")
		if not Contract.amount(record.policy_version, true) or record.policy_version > runtime.policy_version or not Contract.amount(record.opened_day) or not Contract.amount(record.adoption_order) or not whole(record.resolved_day, -1):
			return fail("invalid NPC decision versions")
		if not record.read_set is Dictionary or not record.selection is Dictionary or not record.result_ref is String or not hash_string(record.read_fingerprint):
			return fail("invalid NPC read set, selection or fingerprint")
		var refs: Dictionary = read_values(raw, record.read_set)
		if not refs.ok: return refs
		if not record.read_set.get("characters", []).has(record.actor_id): return fail("decision must observe own condition")
		if record.read_set.has("observer_view") and record.read_set.observer_view != [record.actor_id]: return fail("decision observer must be its actor")
		var opportunity: String = str(record.actor_id) + "|" + preload("res://scripts/core/npc_decision_opportunity.gd").slot_identity(record.slot_id)
		opportunity_pages[opportunity] = int(opportunity_pages.get(opportunity, 0)) + maxi(0, record.read_set.get("observer_pages", []).size() - 1)
		if opportunity_pages[opportunity] > MAX_CONTEXT_PAGES: return fail("NPC opportunity exceeded page limit")
		opportunity_counts[opportunity] = int(opportunity_counts.get(opportunity, 0)) + 1
		if opportunity_counts[opportunity] > 3: return fail("NPC opportunity exceeded retry limit")
		if record.status == "pending":
			var slot: String = opportunity
			if slots.has(slot) or not record.selection.is_empty() or record.adoption_order != 0 or record.result_ref != "" or record.resolved_day != -1 or record.source != "":
				return fail("invalid or duplicate pending NPC decision")
			slots.append(slot)
			if runtime.actors.get(record.actor_id, {}).get("pending_request_id") != id: return fail("pending decision lost actor backlink")
		elif record.status == "adopted":
			if adopted_slots.has(opportunity): return fail("NPC opportunity was adopted twice")
			adopted_slots.append(opportunity)
			var selection_validation: Dictionary = load("res://scripts/ai/npc_decision_parser.gd").new().parse(record.selection)
			if not selection_validation.ok: return selection_validation
			if record.source == "" or record.adoption_order < 1 or record.adoption_order > runtime.adoption_sequence or orders.has(record.adoption_order) or record.resolved_day < record.opened_day:
				return fail("invalid NPC adoption order")
			orders.append(record.adoption_order)
			var result_found: bool = raw.get("action_receipts", {}).has(record.result_ref) or (raw.get("active_tasks", []) + raw.get("completed_tasks", [])).any(func(task): return task.get("task_id") == record.result_ref)
			if record.selection.get("kind") == "wait": result_found = record.result_ref == id
			if record.selection.is_empty() or not result_found: return fail("adopted decision lost actual result")
			if record.selection.kind == "action":
				var receipt: Dictionary = raw.get("action_receipts", {}).get(record.result_ref, {})
				if record.result_ref != "npc-action:" + str(id) or receipt.get("executor_id") != record.actor_id or receipt.get("request_id") != record.result_ref: return fail("NPC decision references another actor's action")
			elif record.selection.kind == "plan":
				var matching: Array = (raw.get("active_tasks", []) + raw.get("completed_tasks", [])).filter(func(task): return task.get("task_id") == record.result_ref and task.get("principal_id") == record.actor_id and task.get("executor_id") == record.actor_id)
				if matching.size() != 1: return fail("NPC decision references another actor's task")
				if record.selection.plan.has("task_id"):
					var auth: Dictionary = raw.get("action_authorizations", {}).get(matching[0].get("authorization_id"), {})
					if record.result_ref != record.selection.plan.task_id or not record.read_set.get("tasks", []).has(record.result_ref) or auth.get("principal_id") != record.actor_id or auth.get("delegate_id") != record.actor_id or matching[0].get("source_agreement_id", "") != "": return fail("NPC revision lost original self-owned task authority")
				elif matching[0].get("authorization_id") != "npc-auth:" + str(id): return fail("NPC decision references another actor's task")
		elif record.resolved_day < record.opened_day or record.adoption_order != 0 or record.result_ref != "" or not record.selection.is_empty() or record.source != "":
			return fail("invalid terminal NPC computation")
	for slot in slots:
		if adopted_slots.has(slot): return fail("adopted NPC opportunity cannot remain pending")
	for actor in runtime.actors:
		var row: Variant = runtime.actors[actor]
		if not characters.has(actor) or not exact(row, ACTOR_FIELDS) or row.mode not in MODES or not Contract.amount(row.score) or row.score > 100:
			return fail("invalid NPC scheduler actor")
		if not Contract.amount(row.model_service_order) or row.model_service_order > runtime.model_service_sequence: return fail("invalid NPC model service order")
		if not row.recent_failures is Array or row.recent_failures.size() > 8: return fail("invalid NPC failure history")
		for failure in row.recent_failures:
			var failure_fields: Array = ["request_id", "category", "error", "day", "selection_hash", "read_fingerprint", "repeat_count"] + (["attempted_kind", "attempted_kinds"] if failure.has("attempted_kind") or failure.has("attempted_kinds") else [])
			if not exact(failure, failure_fields): return fail("invalid NPC failure fields")
			if failure.has("attempted_kind"):
				if failure.attempted_kind not in ["unknown", "wait", "action", "plan"] or not failure.attempted_kinds is Array or failure.attempted_kinds.size() > 8: return fail("invalid NPC failed attempt summary")
				if failure.attempted_kind in ["unknown", "wait"] and not failure.attempted_kinds.is_empty(): return fail("non-action failure cannot invent attempted actions")
				if failure.attempted_kind == "action" and failure.attempted_kinds.size() != 1 or failure.attempted_kind == "plan" and failure.attempted_kinds.is_empty(): return fail("failed attempt lost actual action kinds")
				var kinds: Array = []
				for kind in failure.attempted_kinds:
					if not text_id(kind) or kinds.has(kind) or load("res://scripts/core/game_action_catalog.gd").description(kind).get("status") != "ready": return fail("invalid or duplicate failed NPC capability")
					kinds.append(kind)
			if not records.has(failure.request_id) or records[failure.request_id].actor_id != actor or failure.category not in ["transport", "protocol", "stale", "domain"] or not text_id(failure.error) or not whole(failure.day, 0) or not whole(failure.repeat_count, 1) or not hash_string(failure.selection_hash) or not hash_string(failure.read_fingerprint): return fail("invalid NPC failure reference")
		for field in ["below_since_day", "last_decision_day", "waiting_since_day"]:
			if not whole(row[field], -1): return fail("invalid NPC scheduler day")
		if not Contract.amount(row.cooldown_until_day) or not row.pending_request_id is String: return fail("invalid NPC cooldown or pending reference")
		if row.pending_request_id != "" and (not records.has(row.pending_request_id) or records[row.pending_request_id].status != "pending" or records[row.pending_request_id].actor_id != actor): return fail("invalid NPC pending reference")
	return {"ok": true}

static func read_values(raw: Dictionary, read_set: Dictionary) -> Dictionary:
	var sources := {"characters": raw.get("character_states", {}), "accounts": raw.get("resource_accounts", {}), "contracts": raw.get("economic_contracts", {}), "cases": raw.get("accountability_cases", {}), "offices": raw.get("office_state", {}), "knowledge": raw.get("observer_character_knowledge", {})}
	sources.observer_view = raw.get("character_states", {})
	sources.authorizations = raw.get("action_authorizations", {})
	var tasks := {}
	for task in raw.get("active_tasks", []) + raw.get("completed_tasks", []):
		if task is Dictionary: tasks[task.get("task_id", "")] = task
	sources.tasks = tasks
	sources.assets = raw.get("management_assets", {})
	sources.locations = raw.get("local_node_state", {})
	sources.claims = raw.get("information_claims", {})
	sources["behavior"] = {}
	var view := _BehaviorView.new(raw)
	for actor in read_set.get("behavior", []):
		if not view.character_states.has(actor): return fail("missing NPC behavior actor")
		sources.behavior[actor] = {"custom_traits":view.flags.get("custom_character_traits", {}).get(actor, {}).duplicate(true), "pressure":raw.get("character_political_states", {}).get(actor, {}).duplicate(true), "memories":load("res://scripts/core/structured_memory_service.gd").new().get_relevant_memories(view,actor,[],8,actor), "opportunities":load("res://scripts/core/npc_social_reaction_service.gd").opportunities(view,actor)}
	var values := {}
	for field in read_set:
		if field not in READ_FIELDS or not read_set[field] is Array: return fail("unknown NPC read domain")
		if field == "observer_pages":
			if not read_set.has("observer_view"): return fail("delivered inputs require an NPC observer")
			var checked: Dictionary = load("res://scripts/core/npc_decision_read_set.gd").validate_manifest(read_set[field])
			if not checked.ok: return checked
			continue
		var ids: Array = []
		values[field] = {}
		for id in read_set[field]:
			if not text_id(id) or ids.has(id) or not sources[field].has(id): return fail("missing or duplicate NPC read reference: " + str(id))
			ids.append(id)
			values[field][id] = sources[field][id].duplicate(true) if sources[field][id] is Dictionary else sources[field][id]
	# Cash is stored in the original depot/pool, not on the account descriptor.
	for id in read_set.get("accounts", []):
		var storage: Dictionary = sources.accounts[id].get("storage_ref", {})
		values.accounts[id]["actual_storage"] = raw.get("depot_states", {}).get(storage.get("storage_id"), {}) if storage.get("storage_kind") == "depot" else raw.get("resources", {})
		values.accounts[id]["reservations"] = raw.get("resource_reservations", {}).values().filter(func(row): return row.get("account_id") == id)
	return {"ok": true, "values": values}

class _BehaviorView extends RefCounted:
	var character_states: Dictionary
	var flags: Dictionary
	var structured_memories: Array
	var information_claims: Dictionary
	var accountability_cases: Dictionary
	func _init(raw: Dictionary) -> void:
		character_states = raw.get("character_states", {})
		flags = raw.get("flags", {})
		structured_memories = raw.get("structured_memories", [])
		information_claims = raw.get("information_claims", {})
		accountability_cases = raw.get("accountability_cases", {})

static func fingerprint(state, read_set: Dictionary, data: Dictionary = {}) -> Dictionary:
	if read_set.has("observer_view"):
		if read_set.observer_view.size() != 1: return fail("invalid NPC observer manifest")
		return load("res://scripts/core/npc_decision_read_set.gd").fingerprint(state, data, read_set.observer_view[0], read_set.get("observer_pages", []))
	var result := read_values(state.to_dictionary(), read_set)
	if not result.ok: return result
	return Canonical.hash_value(result.values)

static func cancel_pending(state) -> void:
	for id in state.npc_decision_records:
		var record: Dictionary = state.npc_decision_records[id]
		if record.status == "pending":
			record.status = "cancelled"
			record.resolved_day = state.current_day
			state.npc_ai_runtime.actors[record.actor_id].pending_request_id = ""

static func exact(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true

static func whole(value: Variant, minimum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and floor(float(value)) == float(value) and value >= minimum and value <= Contract.MAX_AMOUNT

static func text_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 256

static func hash_string(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for char_value in value:
		if char_value not in "0123456789abcdef": return false
	return true

static func fail(message: String) -> Dictionary:
	return {"ok": false, "code": "npc_contract_error", "error": message, "message": message}
