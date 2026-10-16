@tool
extends RefCounted
## Per-window authoring recovery. Drafts and snapshots never touch campaign saves.
const Doc = preload("document.gd")
const AuthoringSession = preload("authoring_session.gd")
const MAX_SNAPSHOTS_PER_MAP := 8
var root_path := ""
var last_error := ""

func _init(folder: String = "user://map_editor_recovery") -> void:
	root_path = ProjectSettings.globalize_path(folder)

func _index_path() -> String:
	return root_path.path_join("index.json")

func _ensure_root() -> bool:
	if DirAccess.dir_exists_absolute(root_path): return true
	if DirAccess.make_dir_recursive_absolute(root_path) == OK: return true
	last_error = "无法创建地图恢复目录：" + root_path
	return false

func _read() -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(_index_path()): return {"ok":true, "items":[]}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	if not parsed is Dictionary or not parsed.get("items") is Array:
		last_error = "地图恢复索引损坏；原文件保留，请先检查恢复目录。"
		return {"ok":false, "items":[]}
	for item in parsed.items:
		if not item is Dictionary or not item.get("id") is String or not item.get("file") is String or not _safe_name(item.file) or not item.get("kind") in ["draft", "snapshot"]:
			last_error = "地图恢复索引含无效条目；原文件保留。"
			return {"ok":false, "items":[]}
	return {"ok":true, "items":parsed.items}

func _safe_name(name: String) -> bool:
	return not name.is_empty() and name.get_file() == name and not name.contains("..") and (name.begins_with("draft_") or name.begins_with("snap_")) and (name.ends_with(".map.json") or name.ends_with(".png"))

func _write(items: Array) -> bool:
	if not _ensure_root(): return false
	var target := _index_path()
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入恢复索引临时文件。"
		return false
	file.store_string(JSON.stringify({"version":1, "items":items}, "\t"))
	file.flush()
	var code := file.get_error()
	file.close()
	if code != OK:
		last_error = "恢复索引写入失败；旧索引保留。"
		return false
	if FileAccess.file_exists(target) and DirAccess.copy_absolute(target, target + ".bak") != OK:
		last_error = "恢复索引备份失败；旧索引保留。"
		return false
	if DirAccess.rename_absolute(temp, target) != OK:
		last_error = "恢复索引替换失败；旧索引保留。"
		return false
	return true

func _map_key(doc: RefCounted, session_id: String) -> String:
	var origin: String = doc.current_path if not doc.current_path.is_empty() else "unsaved:" + session_id
	return origin.sha256_text().substr(0, 16)

static var write_mutex:=Mutex.new()

func prepare_save(doc: RefCounted,session_id: String,name: String,kind: String,editing_state: Dictionary={}) -> Dictionary:
	if session_id.is_empty() or session_id.length() > 128 or kind not in ["draft", "snapshot"] or name.length() > 80:
		return {"ok":false, "error":"恢复记录名称或窗口 ID 无效。"}
	if not editing_state.is_empty():
		var state_error:=AuthoringSession.validate(editing_state)
		if not state_error.is_empty(): return {"ok":false,"error":state_error}
	var error: String=doc.validate(doc.data)
	if not error.is_empty():return {"ok":false,"error":error}
	return {"ok":true,"data":doc.snapshot(),"source_path":doc.current_path,"session_id":session_id,"name":name,"kind":kind,"editing_state":editing_state.duplicate(true)}

func _save(doc: RefCounted, session_id: String, name: String, kind: String, editing_state: Dictionary = {}) -> Dictionary:
	var prepared:=prepare_save(doc,session_id,name,kind,editing_state)
	return save_prepared(prepared) if prepared.ok else prepared

func save_prepared(prepared: Dictionary) -> Dictionary:
	write_mutex.lock()
	var result:=_write_prepared(prepared)
	write_mutex.unlock()
	return result

func _write_prepared(prepared: Dictionary) -> Dictionary:
	var session_id: String=prepared.session_id
	var name: String=prepared.name
	var kind: String=prepared.kind
	var editing_state: Dictionary=prepared.editing_state
	var source_path: String=prepared.source_path
	if not _ensure_root(): return {"ok":false, "error":last_error}
	var index := _read()
	if not index.ok: return {"ok":false, "error":last_error}
	var key := session_id.sha256_text().substr(0, 16)
	var map_key: String=(source_path if not source_path.is_empty() else "unsaved:"+session_id).sha256_text().substr(0,16)
	var id := "draft_" + key + "_" + map_key if kind == "draft" else "snap_" + key + "_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
	var filename := id + ".map.json"
	var path := root_path.path_join(filename)
	var error: String=preload("document.gd").write_snapshot(prepared.data,path,source_path)
	if not error.is_empty(): return {"ok":false, "error":error}
	var items: Array = index.items
	items = items.filter(func(item): return item.id != id)
	var entry := {"id":id, "kind":kind, "name":name, "session_id":session_id, "map_key":map_key, "source_path":source_path, "file":filename, "preview_file":"", "saved_at":Time.get_unix_time_from_system(), "title":str(prepared.data.title)}
	if not editing_state.is_empty(): entry.editing_state = editing_state.duplicate(true)
	items.append(entry)
	var removed: Array = []
	if kind == "snapshot":
		var same: Array = items.filter(func(item): return item.kind == "snapshot" and item.map_key == entry.map_key)
		same.sort_custom(func(a,b): return a.saved_at < b.saved_at)
		while same.size() > MAX_SNAPSHOTS_PER_MAP:
			var oldest: Dictionary = same.pop_front()
			items.erase(oldest)
			removed.append(oldest)
	if not _write(items): return {"ok":false, "error":last_error, "path":path}
	for old in removed:
		for file_name in [old.file, old.get("preview_file", "")]:
			if _safe_name(file_name): DirAccess.remove_absolute(root_path.path_join(file_name))
	return {"ok":true, "id":id, "path":path, "entry":entry}

func save_draft(doc: RefCounted, session_id: String, editing_state: Dictionary = {}) -> Dictionary:
	return _save(doc, session_id, "自动草稿", "draft", editing_state)

func save_snapshot(doc: RefCounted, session_id: String, name: String, editing_state: Dictionary = {}) -> Dictionary:
	if name.strip_edges().is_empty(): return {"ok":false, "error":"快照需要名称。"}
	return _save(doc, session_id, name.strip_edges(), "snapshot", editing_state)

func entries() -> Array:
	write_mutex.lock()
	var result:=_entries_unlocked()
	write_mutex.unlock()
	return result

func _entries_unlocked() -> Array:
	var index := _read()
	if not index.ok: return []
	var result: Array = index.items.duplicate(true)
	result.sort_custom(func(a,b): return a.saved_at > b.saved_at)
	return result

func preview_path(id: String) -> String:
	for item in entries():
		if item.id == id and item.kind == "snapshot": return root_path.path_join(id + ".png")
	return ""

func set_preview(id: String) -> bool:
	write_mutex.lock()
	var result:=_set_preview_unlocked(id)
	write_mutex.unlock()
	return result

func _set_preview_unlocked(id: String) -> bool:
	var path := ""
	for item in _entries_unlocked():
		if item.id==id and item.kind=="snapshot":path=root_path.path_join(id+".png");break
	if path.is_empty() or not FileAccess.file_exists(path): return false
	var index := _read()
	if not index.ok: return false
	for item in index.items:
		if item.id == id:
			item.preview_file = id + ".png"
			return _write(index.items)
	return false

func restore(doc: RefCounted, id: String) -> Dictionary:
	for item in entries():
		if item.id != id: continue
		if not _safe_name(item.file): return {"ok":false, "error":"恢复文件名无效。"}
		if item.has("editing_state"):
			var session_error := AuthoringSession.validate(item.editing_state)
			if not session_error.is_empty(): return {"ok":false,"error":session_error+" 当前地图未替换。"}
		var error: String = doc.load_file(root_path.path_join(item.file))
		if not error.is_empty(): return {"ok":false, "error":error}
		# A recovered draft is an editable copy. Saving requires an explicit target.
		doc.current_path = ""
		return {"ok":true, "entry":item}
	return {"ok":false, "error":"未找到恢复记录。" if last_error.is_empty() else last_error}
