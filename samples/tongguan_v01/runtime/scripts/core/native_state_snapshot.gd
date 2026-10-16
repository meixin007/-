extends RefCounted
const BASELINE_KEYS := ["regional_census", "regional_economic_baselines"]
const HISTORY_FIELDS := ["resource_journal", "processed_transactions", "npc_decision_records"]
const HOUSEHOLD_PERIODS := "character_subsistence_periods"
# Runtime-only ownership and exact comparison helpers. These are not a save
# schema, validator, alternative world, or persistent cache.
static func reference_view(state) -> Dictionary:
	var view := {}
	for property in state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var name: String = str(property.name)
			view[name] = state.get(name)
	return view
static func owned_fields(state, shared_baselines: Dictionary = {}, shared_history: Dictionary = {}, prepared_masks: Dictionary = {}) -> Dictionary:
	var source: Dictionary = reference_view(state)
	if shared_baselines.is_empty() and shared_history.is_empty(): return source.duplicate(true)
	var owned: Dictionary = _masked_fields(source, shared_baselines.keys(), history_keys(shared_history), prepared_masks).duplicate(true)
	for key in shared_baselines: owned.flags[key] = shared_baselines[key]
	for field in shared_history:
		if field == HOUSEHOLD_PERIODS:
			var household_rows: Dictionary = shared_history[field]
			for actor in household_rows:
				var periods: Array = _household_periods(owned, actor)
				var actor_rows: Dictionary = household_rows[actor]
				for index in actor_rows: periods[index] = actor_rows[index]
		else:
			var rows: Dictionary = shared_history[field]
			var owned_rows: Dictionary = owned[field]
			for key in rows: owned_rows[key] = rows[key]
	return owned

static func _masked_fields(fields: Dictionary, excluded_baselines: Array, excluded_history: Dictionary, prepared_masks: Dictionary = {}) -> Dictionary:
	var projected: Dictionary = fields.duplicate(false)
	var flags: Dictionary = fields.flags.duplicate(false)
	# Keep dictionary insertion order: exact native bytes also distinguish
	# layout/representation changes, so removing and re-appending keys would
	# make an otherwise unchanged source fail its own guard.
	for key in excluded_baselines: flags[key] = null
	projected.flags = flags
	for field in excluded_history:
		if field == HOUSEHOLD_PERIODS:
			var characters: Dictionary = fields.character_states.duplicate(false)
			for actor in excluded_history[field]:
				var character: Dictionary = characters[actor].duplicate(false)
				var goal: Dictionary = character.life_goal.duplicate(false)
				var needs: Dictionary = goal.subsistence.duplicate(false)
				var periods: Array = needs.periods.duplicate(false)
				var indices: Array = excluded_history[field][actor]
				# The native fill avoids one script assignment per completed day.
				# Compare the entire index sequence so duplicate/partial/reordered
				# caller masks retain the exact previous representation semantics.
				if indices == range(periods.size()): periods.fill(null)
				else:
					for index in indices: periods[index] = null
				needs.periods = periods
				goal.subsistence = needs
				character.life_goal = goal
				characters[actor] = character
			projected.character_states = characters
		else:
			var rows: Dictionary = fields[field].duplicate(false)
			if prepared_masks.has(field): rows.merge(prepared_masks[field], true)
			else:
				for key in excluded_history[field]: rows[key] = null
			projected[field] = rows
	return projected
static func install_owned_fields(state, owned: Dictionary) -> void:
	for field in owned: state.set(field, owned[field])
static func exact_bytes(state, excluded_baselines: Array = [], excluded_history: Dictionary = {}) -> PackedByteArray:
	return exact_owned_bytes(reference_view(state), excluded_baselines, excluded_history)
static func exact_owned_bytes(fields: Dictionary, excluded_baselines: Array = [], excluded_history: Dictionary = {}) -> PackedByteArray:
	if excluded_baselines.is_empty() and excluded_history.is_empty(): return var_to_bytes(fields)
	return var_to_bytes(_masked_fields(fields, excluded_baselines, excluded_history))

static func exact_field_bytes(state, excluded_baselines: Array = [], excluded_history: Dictionary = {}) -> Array:
	return exact_owned_field_bytes(reference_view(state), excluded_baselines, excluded_history)
static func exact_owned_field_bytes(fields: Dictionary, excluded_baselines: Array = [], excluded_history: Dictionary = {}) -> Array:
	# A complete lossless comparison, without hashing or skipping any field.
	# Preserve root container typing and key order separately; every value
	# retains its entire native representation, including nested types.
	var projected: Dictionary = fields if excluded_baselines.is_empty() and excluded_history.is_empty() else _masked_fields(fields, excluded_baselines, excluded_history)
	var container: Dictionary = projected.duplicate(false)
	container.clear()
	var parts: Array = [var_to_bytes(container), var_to_bytes(projected.keys())]
	for value in projected.values(): parts.append(var_to_bytes(value))
	return parts

static func exact_fields_match(state, expected: Array, excluded_baselines: Array = [], excluded_history: Dictionary = {}, prepared_masks: Dictionary = {}) -> bool:
	return exact_owned_fields_match(reference_view(state), expected, excluded_baselines, excluded_history, prepared_masks)
static func exact_owned_fields_match(fields: Dictionary, expected: Array, excluded_baselines: Array = [], excluded_history: Dictionary = {}, prepared_masks: Dictionary = {}) -> bool:
	# Compare the same complete representation as exact_owned_field_bytes.
	# Only one newly encoded field stays live at a time. This reduces temporary
	# allocation and disposal during publication; it grants no cached permission
	# and skips no field, nested type, dictionary layout or mutable history.
	if expected.size() != fields.size() + 2: return false
	var projected: Dictionary = fields if excluded_baselines.is_empty() and excluded_history.is_empty() else _masked_fields(fields, excluded_baselines, excluded_history, prepared_masks)
	var container: Dictionary = projected.duplicate(false)
	container.clear()
	if var_to_bytes(container) != expected[0] or var_to_bytes(projected.keys()) != expected[1]: return false
	var index := 2
	for value in projected.values():
		if var_to_bytes(value) != expected[index]: return false
		index += 1
	return true

static func freeze_publication_history(fields: Dictionary) -> void:
	for field in HISTORY_FIELDS:
		for row in fields.get(field, {}).values():
			if row is Dictionary and _terminal_history(field, row): freeze_owned(row)
	# Each period is a completed consumption fact checked against its original
	# resource receipts. The service only appends subsequent periods; totals,
	# current needs and the containing arrays remain mutable.
	for actor in fields.get("character_states", {}):
		var periods: Variant = _household_periods(fields, actor)
		if periods is Array:
			for row in periods:
				if row is Dictionary: freeze_owned(row)

static func frozen_history_rows(state) -> Dictionary:
	return frozen_history_fields(reference_view(state))

static func frozen_history_fields(fields: Dictionary) -> Dictionary:
	var seals := {}
	for field in HISTORY_FIELDS:
		var rows := {}
		var table: Dictionary = fields.get(field, {})
		for key in table:
			var row: Variant = table[key]
			if row is Dictionary and row.is_read_only() and _terminal_history(field, row): rows[key] = row
		if not rows.is_empty(): seals[field] = rows
	var households := {}
	for actor in fields.get("character_states", {}):
		var periods: Variant = _household_periods(fields, actor)
		if not periods is Array: continue
		var rows := {}
		for index in periods.size():
			var row: Variant = periods[index]
			if row is Dictionary and row.is_read_only(): rows[index] = row
		if not rows.is_empty(): households[actor] = rows
	if not households.is_empty(): seals[HOUSEHOLD_PERIODS] = households
	return seals

static func history_keys(seals: Dictionary) -> Dictionary:
	var result := {}
	for field in seals:
		if field == HOUSEHOLD_PERIODS:
			var households := {}
			for actor in seals[field]: households[actor] = seals[field][actor].keys()
			result[field] = households
		else: result[field] = seals[field].keys()
	return result

static func history_masks(keys: Dictionary) -> Dictionary:
	# Per-job native merge operands only. They contain nulls, no world rows or
	# validation permission, and are derived from the same sealed-row key set.
	var result := {}
	for field in keys:
		if field == HOUSEHOLD_PERIODS: continue
		var mask := {}
		for key in keys[field]: mask[key] = null
		mask.make_read_only()
		result[field] = mask
	result.make_read_only()
	return result

static func history_seals_match(state, seals: Dictionary) -> bool:
	for field in seals:
		if field == HOUSEHOLD_PERIODS:
			var fields := {"character_states": state.character_states}
			var households: Dictionary = seals[field]
			for actor in households:
				var periods: Variant = _household_periods(fields, actor)
				if not periods is Array: return false
				var actor_rows: Dictionary = households[actor]
				var count: int = periods.size()
				if actor_rows.size() == count and actor_rows.keys() == range(count):
					var values: Array = actor_rows.values()
					for index in count:
						if not is_same(periods[index], values[index]): return false
				else:
					for index in actor_rows:
						if index >= count or not is_same(periods[index], actor_rows[index]): return false
		else:
			var rows: Variant = state.get(field)
			if not rows is Dictionary: return false
			var sealed_rows: Dictionary = seals[field]
			if rows.size() == sealed_rows.size() and rows.keys() == sealed_rows.keys():
				var live_values: Array = rows.values()
				var sealed_values: Array = sealed_rows.values()
				for index in sealed_values.size():
					if not is_same(live_values[index], sealed_values[index]): return false
			else:
				for key in sealed_rows:
					if not is_same(rows.get(key), sealed_rows[key]): return false
	return true

static func _household_periods(fields: Dictionary, actor: String) -> Variant:
	var character: Variant = fields.get("character_states", {}).get(actor)
	if not character is Dictionary: return null
	var goal: Variant = character.get("life_goal")
	if not goal is Dictionary: return null
	var needs: Variant = goal.get("subsistence")
	return needs.get("periods") if needs is Dictionary else null

static func _terminal_history(field: String, row: Dictionary) -> bool:
	if field == "npc_decision_records": return row.get("status") in ["adopted", "cancelled", "superseded", "failed"]
	if field == "processed_transactions": return row.get("status") == "committed"
	return true
static func frozen_baselines(state) -> Dictionary:
	var seals := {}
	for key in BASELINE_KEYS:
		var value: Variant = state.flags.get(key)
		if value is Dictionary and value.is_read_only(): seals[key] = value
	return seals
static func seals_match(state, seals: Dictionary) -> bool:
	for key in seals:
		if not is_same(state.flags.get(key), seals[key]): return false
	return true
static func freeze_publication_baselines(fields: Dictionary) -> void:
	for key in BASELINE_KEYS:
		var value: Variant = fields.get("flags", {}).get(key)
		if value is Dictionary: freeze_owned(value)
static func freeze_owned(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values():
			if child is Dictionary or child is Array: freeze_owned(child)
		value.make_read_only()
	elif value is Array:
		for child in value:
			if child is Dictionary or child is Array: freeze_owned(child)
		value.make_read_only()
