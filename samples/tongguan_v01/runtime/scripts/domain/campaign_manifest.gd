extends RefCounted

class_name CampaignManifest

var campaign_id: String = ""
var campaign_days: int = 0
var phases: Array[Dictionary] = []
var content_files: Dictionary = {}
var character_ids: PackedStringArray = PackedStringArray()
var important_event_ids: PackedStringArray = PackedStringArray()

static func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing campaign manifest: " + path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return _fail("invalid campaign manifest: " + path)
	return _from_dictionary(parsed)

static func _from_dictionary(raw: Dictionary) -> Dictionary:
	for key in ["campaign_id", "campaign_days", "phases", "content_files", "character_ids", "important_event_ids"]:
		if not raw.has(key):
			return _fail("campaign manifest missing key: " + key)
	if not (raw.campaign_id is String) or str(raw.campaign_id).is_empty():
		return _fail("campaign manifest campaign_id")
	if not _is_integer(raw.campaign_days) or int(raw.campaign_days) != 90:
		return _fail("campaign manifest campaign_days")
	if not (raw.phases is Array) or raw.phases.size() != 3:
		return _fail("campaign manifest phases")
	if not (raw.content_files is Dictionary):
		return _fail("campaign manifest content_files")
	var campaign_id_value := str(raw.campaign_id)
	var campaign_days_value := int(raw.campaign_days)
	var phases_value := _copy_phases(raw.phases)
	if not _has_valid_phase_windows(phases_value):
		return _fail("campaign manifest phase windows")
	var content_files_value: Dictionary = raw.content_files.duplicate(true)
	var character_ids_value := _string_array(raw.character_ids)
	var important_event_ids_value := _string_array(raw.important_event_ids)
	if character_ids_value.size() != 12 or important_event_ids_value.size() != 36:
		return _fail("campaign manifest production content counts")
	if _has_duplicates(character_ids_value) or _has_duplicates(important_event_ids_value):
		return _fail("campaign manifest duplicate content id")
	return {"ok": true, "data": {
		"campaign_id": campaign_id_value,
		"campaign_days": campaign_days_value,
		"phases": phases_value,
		"content_files": content_files_value,
		"character_ids": character_ids_value,
		"important_event_ids": important_event_ids_value
	}}

func files_for(kind: String) -> PackedStringArray:
	return PackedStringArray(content_files.get(kind, PackedStringArray())).duplicate()

func to_dictionary() -> Dictionary:
	return {
		"campaign_id": campaign_id,
		"campaign_days": campaign_days,
		"phases": phases.duplicate(true),
		"content_files": content_files.duplicate(true),
		"character_ids": character_ids.duplicate(),
		"important_event_ids": important_event_ids.duplicate()
	}

static func _copy_phases(raw_phases: Array) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for raw_phase in raw_phases:
		if raw_phase is Dictionary:
			copied.append((raw_phase as Dictionary).duplicate(true))
	return copied

static func _has_valid_phase_windows(value: Array[Dictionary]) -> bool:
	var expected := [[1, 30], [31, 60], [61, 90]]
	for index in range(expected.size()):
		var phase := value[index]
		if int(phase.get("start_day", 0)) != expected[index][0] or int(phase.get("end_day", 0)) != expected[index][1]:
			return false
	return true

static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not (value is Array):
		return result
	for item in value:
		if item is String and not item.is_empty():
			result.append(item)
	return result

static func _has_duplicates(values: PackedStringArray) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false

static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))))

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
