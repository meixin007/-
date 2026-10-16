extends "res://army/controller.gd"
const Migration=preload("res://final/migration.gd")
var _migration=Migration.new()
func preview_import(path: String,destination: String="user://final/session.json")->Dictionary:
	return _migration.preview(path,destination,self)
func commit_import(token: String)->Dictionary:return _migration.commit(token,self)
func restore_previous_save(path: String)->Dictionary:
	var saves=Saves.new(definition.world_id)
	var read=saves.repository.read_snapshot(path+".bak")
	if not read.ok:return _fail("没有完整可用的上一代备份："+str(read.get("error","未知原因")))
	var candidate=GameState.new();var loaded=candidate.try_load_dictionary(read.data)
	if not loaded.ok:return _fail(str(loaded.get("error","备份状态无效。")))
	var issue=_validate(candidate)
	if not issue.is_empty():return _fail("备份与当前场景不兼容："+issue)
	var restored=saves.restore_backup_path(path,candidate)
	if not restored.ok:return _fail(str(restored.get("error","备份恢复未执行。")))
	var adopted=context.replace_state(candidate,true)
	if adopted.ok:_pending.clear();_build_pending.clear()
	return adopted
