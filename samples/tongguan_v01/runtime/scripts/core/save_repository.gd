extends RefCounted

class_name SaveRepository

const CurrentCampaignScript = preload("res://scripts/domain/current_campaign.gd")
const SAVE_VERSION := CurrentCampaignScript.SAVE_VERSION
const CURRENT_CAMPAIGN_ID := CurrentCampaignScript.CAMPAIGN_ID
const SAVE_ROOT := CurrentCampaignScript.SAVE_ROOT
const SLOT_NAMES := ["manual_1", "manual_2", "manual_3", "autosave"]
const SENSITIVE_KEYS := {"api_key": true, "authorization": true, "player_text": true, "free_input": true, "raw_text": true, "original_text": true, "user_text": true}
const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")
const SaveFileStoreScript = preload("res://scripts/core/save_file_store.gd")

var file_store
var _expected_campaign_id: String = CURRENT_CAMPAIGN_ID

func _init(injected_file_store = null, expected_campaign_id: String = "") -> void:
	if not expected_campaign_id.is_empty(): _expected_campaign_id = expected_campaign_id
	file_store = injected_file_store if injected_file_store != null else SaveFileStoreScript.new()

func expected_campaign_id() -> String:
	return _expected_campaign_id

func slot_paths() -> Array[String]:
	var paths: Array[String] = []
	for slot in SLOT_NAMES:
		paths.append(path_for_slot(slot))
	return paths

func path_for_slot(slot: String) -> String:
	if slot == "autosave": return SAVE_ROOT + "/autosave.json"
	if slot in ["manual_1", "manual_2", "manual_3"]: return SAVE_ROOT + "/" + slot + ".json"
	return ""

func backup_path_for(path: String) -> String:
	return path + ".bak"

func write_slot(slot: String, state) -> Dictionary:
	var path := path_for_slot(slot)
	if path.is_empty(): return _fail("unknown save slot")
	return write_path(path, state)

func write_path(path: String, state, _backup_autosave: bool = false) -> Dictionary:
	if state == null or not state.has_method("to_dictionary"): return _fail("save state is invalid")
	var built: Dictionary = _build_snapshot(state.to_dictionary())
	if not bool(built.get("ok", false)): return built
	return _commit_two_generation(path, JSON.stringify(built.get("data", {}), "", true, true))

func read_slot(slot: String, state) -> Dictionary:
	var path := path_for_slot(slot)
	if path.is_empty(): return _fail("unknown save slot")
	return read_path(path, state)

func read_path(path: String, state) -> Dictionary:
	if state == null: return _fail("save state is invalid")
	var parsed_result := read_snapshot(path)
	if not bool(parsed_result.get("ok", false)): return parsed_result
	var loaded: Dictionary = state.try_load_dictionary(parsed_result.get("data", {})) if state.has_method("try_load_dictionary") else {"ok": state.has_method("load_dictionary")}
	if not bool(loaded.get("ok", false)): return _fail("save state is invalid")
	if not state.has_method("try_load_dictionary"): state.load_dictionary((parsed_result.get("data", {}) as Dictionary).duplicate(true))
	return {"ok": true, "path": path}

func read_snapshot(path: String) -> Dictionary:
	return _read_validated(path)

func read_raw_payload(path: String) -> Dictionary:
	var read: Dictionary = file_store.read_text(path)
	if not bool(read.get("ok", false)): return _fail(str(read.get("error", "missing save")))
	var parser := JSON.new()
	if parser.parse(str(read.get("text", ""))) != OK or not (parser.data is Dictionary):
		return _fail("invalid save json")
	return {"ok": true, "data": (parser.data as Dictionary).duplicate(true)}

func has_valid_backup(path: String) -> bool:
	return bool(_read_validated(backup_path_for(path)).get("ok", false))

func commit_validated_snapshot(path: String, data: Dictionary) -> Dictionary:
	var snapshot: Dictionary = data.duplicate(true)
	snapshot.erase("checksum")
	var checksum_result := _checksum_for(snapshot)
	if not bool(checksum_result.get("ok", false)):
		return _fail("cannot canonicalize save at " + str(checksum_result.get("path", "$")))
	snapshot["checksum"] = str(checksum_result.get("checksum", ""))
	var validation := _validate_text(JSON.stringify(snapshot, "", true, true))
	if not bool(validation.get("ok", false)): return validation
	return _commit_two_generation(path, JSON.stringify(snapshot, "", true, true))

func restore_path_backup(path: String, state) -> Dictionary:
	var backup := _read_validated(backup_path_for(path))
	if not bool(backup.get("ok", false)): return backup
	var commit := commit_validated_snapshot(path, backup.get("data", {}))
	if not bool(commit.get("ok", false)): return commit
	return read_path(path, state)

func restore_autosave_backup(state) -> Dictionary:
	return restore_path_backup(path_for_slot("autosave"), state)

func _commit_two_generation(path: String, serialized: String, preserve_existing_main: bool = false) -> Dictionary:
	var tmp_path := path + ".tmp"
	var backup_path := backup_path_for(path)
	var cleanup: Dictionary = file_store.remove_file(tmp_path)
	if not bool(cleanup.get("ok", false)): return _commit_fail(cleanup, backup_path)
	var ensured: Dictionary = file_store.ensure_directory(path)
	if not bool(ensured.get("ok", false)): return _commit_fail(ensured, backup_path)
	var written: Dictionary = file_store.write_text_and_flush(tmp_path, serialized)
	if not bool(written.get("ok", false)): return _commit_fail(written, backup_path)
	var tmp_validation := _read_validated(tmp_path)
	if not bool(tmp_validation.get("ok", false)): return _commit_fail(tmp_validation, backup_path)
	var main_exists: bool = file_store.exists(path)
	var main_validation := _read_validated(path) if main_exists else {"ok": false}
	if main_exists and (bool(main_validation.get("ok", false)) or preserve_existing_main):
		var remove_backup: Dictionary = file_store.remove_file(backup_path)
		if not bool(remove_backup.get("ok", false)): return _commit_fail(remove_backup, backup_path)
		var rotate: Dictionary = file_store.move_file(path, backup_path)
		if not bool(rotate.get("ok", false)): return _commit_fail(rotate, backup_path)
	elif main_exists:
		var backup_validation := _read_validated(backup_path)
		var remove_invalid: Dictionary = file_store.remove_file(path)
		if not bool(remove_invalid.get("ok", false)): return _commit_fail(remove_invalid, backup_path)
	var committed: Dictionary = file_store.move_file(tmp_path, path)
	if not bool(committed.get("ok", false)): return _commit_fail(committed, backup_path)
	var committed_validation := _read_validated(path)
	if not bool(committed_validation.get("ok", false)): return _commit_fail(committed_validation, backup_path)
	return {"ok": true, "path": path, "backup_path": backup_path, "generation": "main"}

func _commit_fail(result: Dictionary, backup_path: String) -> Dictionary:
	return {"ok": false, "code": "two_generation_commit_failed", "error": str(result.get("error", "save commit failed")), "message": str(result.get("message", result.get("error", "save commit failed"))), "recoverable": true, "backup_path": backup_path}

func _build_snapshot(raw: Dictionary) -> Dictionary:
	var validated := preload("res://scripts/core/game_state.gd").new().try_load_dictionary(raw)
	if not validated.get("ok", false):
		return _fail(str(validated.get("error", "invalid save state")))
	var snapshot: Dictionary = (_without_sensitive_values(raw) as Dictionary).duplicate(true)
	snapshot["save_version"] = SAVE_VERSION
	var campaign_id := str(snapshot.get("campaign_id", _expected_campaign_id))
	var flags_campaign_id := str((snapshot.get("flags", {}) as Dictionary).get("campaign_id", "")) if snapshot.get("flags", {}) is Dictionary else ""
	if campaign_id.is_empty() or (flags_campaign_id.is_empty() and campaign_id == "anshi_beta_1_07"):
		campaign_id = _expected_campaign_id
	if campaign_id != _expected_campaign_id: return _fail("save belongs to an incompatible campaign")
	snapshot["campaign_id"] = campaign_id
	snapshot.erase("checksum")
	var checksum_result := _checksum_for(snapshot)
	if not bool(checksum_result.get("ok", false)): return _fail("cannot canonicalize save at " + str(checksum_result.get("path", "$")))
	snapshot["checksum"] = str(checksum_result.get("checksum", ""))
	return {"ok": true, "data": snapshot.duplicate(true)}

func _read_validated(path: String) -> Dictionary:
	var read: Dictionary = file_store.read_text(path)
	if not bool(read.get("ok", false)): return _fail(str(read.get("error", "missing save")))
	return _validate_text(str(read.get("text", "")))

func _validate_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return _fail("invalid save json")
	var parsed: Variant = parser.data
	if not (parsed is Dictionary): return _fail("invalid save json")
	var data: Dictionary = parsed
	if int(data.get("save_version", 0)) != SAVE_VERSION: return _fail("unexpected save version")
	var save_camp_id := str(data.get("campaign_id", ""))
	if save_camp_id != _expected_campaign_id: return _fail("unexpected campaign id")
	var checksum := str(data.get("checksum", ""))
	data.erase("checksum")
	var calculated := _checksum_for(data)
	if not bool(calculated.get("ok", false)): return _fail("cannot canonicalize save at " + str(calculated.get("path", "$")))
	if checksum.is_empty() or str(calculated.get("checksum", "")) != checksum:
		return _fail("save checksum mismatch expected=" + checksum + " actual=" + str(calculated.get("checksum", "")))
	var validated := preload("res://scripts/core/game_state.gd").new().try_load_dictionary(data)
	if not validated.get("ok", false):
		return _fail(str(validated.get("error", "invalid save state")))
	return {"ok": true, "data": data.duplicate(true)}

func _without_sensitive_values(value: Variant, path: Array = []) -> Variant:
	if value is Dictionary:
		var clean: Dictionary = {}
		for key in value.keys():
			# Only the validated assistant journal stores a resumable instruction.
			# Other raw input, credentials and transport fields keep the original filter.
			var saved_instruction: bool = path.size() == 3 and path[0] == "assistant_conversation_state" and path[1] == "records" and str(key) == "original_text"
			if saved_instruction or not SENSITIVE_KEYS.has(str(key).to_lower()): clean[key] = _without_sensitive_values(value[key], path + [str(key)])
		return clean
	if value is Array:
		var clean_array: Array = []
		for item in value: clean_array.append(_without_sensitive_values(item, path + ["[]"]))
		return clean_array
	return value

func _checksum_for(data: Dictionary) -> Dictionary:
	var canonical: Dictionary = CanonicalJSONScript.encode(data)
	if not bool(canonical.get("ok", false)): return canonical
	return {"ok": true, "checksum": str(canonical.get("text", "")).sha256_text()}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "save_repository_failed", "error": message, "message": message}
