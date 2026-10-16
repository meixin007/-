extends RefCounted

class_name SaveManager

const SaveRepositoryScript = preload("res://scripts/core/save_repository.gd")

var repository = SaveRepositoryScript.new()

func _init(expected_campaign_id: String = "") -> void:
	repository = SaveRepositoryScript.new(null, expected_campaign_id)

func write_slot(slot: String, state) -> Dictionary:
	return repository.write_slot(slot, state)

func read_slot(slot: String, state) -> Dictionary:
	var path := repository.path_for_slot(slot)
	if path.is_empty():
		return _fail("unknown save slot")
	return read_save(path, state)

func write_save(path: String, state) -> Dictionary:
	return repository.write_path(path, state)

func read_save(path: String, state) -> Dictionary:
	if state == null or not state.has_method("try_load_dictionary"):
		return _fail("save state is invalid")
	var raw_result: Dictionary = repository.read_raw_payload(path)
	if not bool(raw_result.get("ok", false)):
		return _fail(str(raw_result.get("error", "missing save")))
	var raw: Dictionary = raw_result.get("data", {})
	var save_camp_id := str(raw.get("campaign_id", ""))
	if int(raw.get("save_version", 0)) != SaveRepositoryScript.SAVE_VERSION \
		or save_camp_id != repository.expected_campaign_id():
		return _fail("存档不属于当前战役格式，请开始新战役。", "incompatible_save")
	var current: Dictionary = repository.read_snapshot(path)
	if not bool(current.get("ok", false)):
		return _with_backup_notice(path, current)
	var loaded: Dictionary = state.try_load_dictionary((current.get("data", {}) as Dictionary).duplicate(true))
	if not bool(loaded.get("ok", false)):
		return _fail(str(loaded.get("error", "当前存档无法载入。")), "incompatible_save")
	return loaded

func restore_slot_backup(slot: String, state) -> Dictionary:
	var path := repository.path_for_slot(slot)
	if path.is_empty(): return _fail("unknown save slot")
	return repository.restore_path_backup(path, state)

func restore_backup_path(path: String, state) -> Dictionary:
	return repository.restore_path_backup(path, state)

func _with_backup_notice(path: String, result: Dictionary) -> Dictionary:
	var copy: Dictionary = result.duplicate(true)
	copy["backup_available"] = repository.has_valid_backup(path)
	return copy

func _fail(message: String, code: String = "save_manager_failed") -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
