extends RefCounted

class_name SaveFileStore

func exists(path: String) -> bool:
	return _validate_path(path).get("ok", false) and FileAccess.file_exists(path)

func ensure_directory(path: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return _fail("cannot create save directory")
	return {"ok": true}

func read_text(path: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	if not FileAccess.file_exists(path): return _fail("missing save")
	return {"ok": true, "text": FileAccess.get_file_as_string(path)}

func file_size(path: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	if not FileAccess.file_exists(path): return _fail("missing save")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("cannot open save")
	var size := int(file.get_length())
	file.close()
	return {"ok": true, "size": size}

func read_bytes(path: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	if not FileAccess.file_exists(path): return _fail("missing save")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("cannot open save")
	var bytes := file.get_buffer(int(file.get_length()))
	file.close()
	return {"ok": true, "bytes": bytes}

func write_text_and_flush(path: String, text: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _fail("cannot open temporary save")
	file.store_string(text)
	file.flush()
	file.close()
	return {"ok": true}

func move_file(from_path: String, to_path: String) -> Dictionary:
	var source_validation := _validate_path(from_path)
	var target_validation := _validate_path(to_path)
	if not source_validation.get("ok", false): return source_validation
	if not target_validation.get("ok", false): return target_validation
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)) != OK:
		return _fail("cannot replace save file")
	return {"ok": true}

func remove_file(path: String) -> Dictionary:
	var validation := _validate_path(path)
	if not validation.get("ok", false): return validation
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		return _fail("cannot remove save file")
	return {"ok": true}

func _validate_path(path: String) -> Dictionary:
	if not path.begins_with("user://") or path.contains("\\") or path.contains(".."):
		return _fail("invalid save path")
	var normalized := path
	if normalized.ends_with("/") or normalized.get_file().is_empty(): return _fail("invalid save path")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/") + "/"
	var global_path := ProjectSettings.globalize_path(normalized).replace("\\", "/")
	if not global_path.begins_with(user_root): return _fail("invalid save path")
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "save_file_store_failed", "error": message, "message": message}
