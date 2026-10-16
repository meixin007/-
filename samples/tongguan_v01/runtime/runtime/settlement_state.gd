extends RefCounted
## Runtime-only state. Authoring is a frozen publication; generators are absent.
var error: String=""
var _layout: Dictionary={}
var _local: Dictionary={}
var _published: Dictionary={}
var _provider: RefCounted
var layout: Dictionary:
	get:return _layout.duplicate(true)
var runtime: Dictionary:
	get:return _provider.projection() if _provider!=null else _local.duplicate(true)
var authoring: Dictionary:
	get:return _provider.authoring_projection() if _provider!=null and _provider.has_method("authoring_projection") else _published.duplicate(true)
func _init(provider: RefCounted=null)->void:
	_layout=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/layout.json"))
	_published=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/authoring.json"))
	_provider=provider
	if provider==null:_local=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/initial_runtime.json"))
	error=_validate_runtime(runtime)
func snapshot()->Dictionary:return {"runtime":runtime}
func _runtime_commit(candidate: Dictionary,action: String)->Dictionary:
	var issue=_validate_runtime(candidate)
	if not issue.is_empty():return _failure(issue)
	if _provider!=null:return _provider.adopt_candidate(candidate,action)
	candidate.revision=int(_local.revision)+1;_local=candidate.duplicate(true)
	return {"ok":true,"action":action,"scope":"standalone_validation"}

static func canonical(value: Variant)->String:
	if value is Dictionary:
		var keys=value.keys();keys.sort();var fields: Array[String]=[]
		for key in keys:fields.append(JSON.stringify(str(key))+":"+canonical(value[key]))
		return "{"+",".join(fields)+"}"
	if value is Array:
		var values: Array[String]=[]
		for v in value:values.append(canonical(v))
		return "["+",".join(values)+"]"
	if value is int or value is float:return "%.6f"%float(value)
	return JSON.stringify(value)

static func digest(value: Variant)->String:return canonical(value).sha256_text()

static func integer(value: Variant)->bool:return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))

func slot_by_id(id: String)->Dictionary:
	for slot in _layout.slots:
		if slot.id==id:return slot.duplicate(true)
	return {}

func _failure(message: String)->Dictionary:return {"ok":false,"message":message}

func construct(id: String,kind: String)->Dictionary:
	var slot=slot_by_id(id)
	if slot.is_empty():return _failure("没有选择有效地块。")
	if not slot.get("gameplay_buildable",false):return _failure("该地块不允许游戏建设。")
	if not kind in slot.allowed_buildings:return _failure("此地块不允许该类设施。")
	if int(runtime.growth_stage)<int(slot.unlock_stage):return _failure("地块尚未随成长开放。")
	if runtime.slot_occupancy[id].status!="empty":return _failure("地块已有设施或正在施工。")
	var candidate=runtime;candidate.slot_occupancy[id].status="building";candidate.slot_occupancy[id].building_type=kind
	return _runtime_commit(candidate,"construct:"+id)

func finish_construction(id: String)->Dictionary:
	if not runtime.slot_occupancy.has(id) or runtime.slot_occupancy[id].status!="building":return _failure("该地块没有待完成施工。")
	var candidate=runtime;candidate.slot_occupancy[id].status="built";return _runtime_commit(candidate,"finish:"+id)

func demolish(id: String)->Dictionary:
	if not runtime.slot_occupancy.has(id) or runtime.slot_occupancy[id].status=="empty":return _failure("该地块为空。")
	var candidate=runtime;candidate.slot_occupancy[id].status="empty";candidate.slot_occupancy[id].building_type="";candidate.module_damage[id]=0
	return _runtime_commit(candidate,"demolish:"+id)

func set_growth(stage: int)->Dictionary:
	if stage<1 or stage>3:return _failure("成长仅有三档。")
	var candidate=runtime;candidate.growth_stage=stage;return _runtime_commit(candidate,"growth")

func set_damage(module: String,level: int)->Dictionary:
	if not runtime.module_damage.has(module) or level<0 or level>2:return _failure("损毁目标或档位无效。")
	if runtime.slot_occupancy.has(module) and runtime.slot_occupancy[module].status=="empty":return _failure("空地没有可损毁的建筑。")
	var candidate=runtime;candidate.module_damage[module]=level;return _runtime_commit(candidate,"damage:"+module)

func set_gate_open(opened: bool)->Dictionary:
	var candidate=runtime;candidate.gate_open=opened;return _runtime_commit(candidate,"gate_open")

func _validate_runtime(value: Dictionary)->String:
	if value.get("site_id")!="tongguan" or value.get("layout_version")!=_layout.layout_version:return "存档地点或布局版本不符。"
	if not integer(value.get("revision")) or value.revision<0 or not integer(value.get("growth_stage")) or not int(value.growth_stage) in [1,2,3] or not value.get("gate_open") is bool:return "运行状态字段无效。"
	if not value.get("slot_occupancy") is Dictionary or not value.get("module_damage") is Dictionary:return "地块或损毁状态缺失。"
	if value.slot_occupancy.size()!=8 or value.module_damage.size()!=11:return "运行状态的稳定对象集合不符。"
	for slot in _layout.slots:
		var occupancy: Variant=value.slot_occupancy.get(slot.id)
		if not occupancy is Dictionary or occupancy.get("building_id")!=slot.id+".building" or not occupancy.get("status") in ["empty","building","built"]:return "建筑身份或施工状态无效。"
		if occupancy.status=="empty" and occupancy.get("building_type")!="":return "空地不能携带建筑类型。"
		if occupancy.status!="empty" and not occupancy.get("building_type") in slot.allowed_buildings:return "建筑类型不在地块允许清单。"
	for id in ["gate","wall_west","wall_east"]+value.slot_occupancy.keys():
		var damage: Variant=value.module_damage.get(id)
		if not integer(damage) or not int(damage) in [0,1,2]:return "损毁字段无效。"
	return ""

func export_save()->Dictionary:
	var data={"schema_version":1,"world_id":"tongguan_slice_v01","layout_version":_layout.layout_version,"runtime":runtime}
	data.content_sha256=digest(data);return data
func restore_save(value: Variant)->Dictionary:
	if not value is Dictionary or value.get("schema_version")!=1 or value.get("world_id")!="tongguan_slice_v01" or value.get("layout_version")!=_layout.layout_version:return _failure("存档世界或布局版本不符。")
	var payload=value.duplicate(true);var checksum=payload.get("content_sha256","");payload.erase("content_sha256")
	if checksum!=digest(payload) or not value.get("runtime") is Dictionary:return _failure("存档校验失败。")
	var issue=_validate_runtime(value.runtime)
	if not issue.is_empty():return _failure(issue)
	if _provider!=null:return _failure("已绑定主机时由主游戏保存系统恢复。")
	_local=value.runtime.duplicate(true);_local.revision=int(_local.revision);_local.growth_stage=int(_local.growth_stage)
	for id in _local.module_damage:_local.module_damage[id]=int(_local.module_damage[id])
	return {"ok":true}
func write_save(path: String)->Dictionary:
	if _provider!=null:return _provider.write_save(path)
	if not path.begins_with("user://") or path.contains(".."):return _failure("存档路径无效。")
	var absolute=ProjectSettings.globalize_path(path);DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file=FileAccess.open(path+".pending",FileAccess.WRITE)
	if file==null:return _failure("无法写入存档。")
	file.store_string(JSON.stringify(export_save(),"\t",true,true));file.flush();file.close()
	if FileAccess.file_exists(path+".previous"):DirAccess.remove_absolute(absolute+".previous")
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(absolute,absolute+".previous")!=OK:return _failure("无法保留旧存档。")
	if DirAccess.rename_absolute(absolute+".pending",absolute)!=OK:
		if FileAccess.file_exists(path+".previous"):DirAccess.rename_absolute(absolute+".previous",absolute)
		return _failure("无法提交存档。")
	return {"ok":true}
func read_save(path: String)->Dictionary:
	if _provider!=null:return _provider.read_save(path)
	if not FileAccess.file_exists(path):return _failure("还没有运行包存档。")
	return restore_save(JSON.parse_string(FileAccess.get_file_as_string(path)))
