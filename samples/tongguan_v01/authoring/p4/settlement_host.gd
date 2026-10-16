extends RefCounted
## Single authority for the independent fixture. No campaign accounts, clock or movement.
var error := ""
var _layout: Dictionary={}
var _runtime: Dictionary={}
var _authoring: Dictionary={}
var _pending: Dictionary={}
var _token_counter := 0
var _water_features: Array=[]
var layout: Dictionary:
	get:return _layout.duplicate(true)
var runtime: Dictionary:
	get:return _runtime.duplicate(true)
var authoring: Dictionary:
	get:return _authoring.duplicate(true)

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
func _init()->void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://p4/layout.json"))
	if not parsed is Dictionary or parsed.get("schema_version")!=1 or parsed.get("slots",[]).size()!=8:
		error="P4 布局格式无效。";return
	_layout=parsed.duplicate(true)
	if _layout.geography_recipe_sha256!=FileAccess.get_sha256("res://p3/geography_recipe.json"):
		error="P4 布局与已验收地理配方不符。";return
	var water: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://p3/generated/modern_water.json"))
	if not water is Dictionary or not water.get("features") is Array:error="现代水系参照缺失。";return
	_water_features=water.features.duplicate(true)
	_runtime={"site_id":"tongguan","layout_version":_layout.layout_version,"revision":0,"growth_stage":1,"gate_open":true,"slot_occupancy":{},"module_damage":{"gate":0,"wall_west":0,"wall_east":0}}
	_authoring={"layout_version":_layout.layout_version,"revision":0,"fixed_refs":_layout.fixed_refs.duplicate(true),"roads":_layout.roads.duplicate(true),"slot_pins":{},"manual_overrides":{},"deleted_ids":{},"pinned_tree_ids":{},"generated":{},"region_settings":{}}
	for slot in _layout.slots:
		_runtime.slot_occupancy[slot.id]={"status":"empty" if slot.initial_building=="empty" else "built","building_type":"" if slot.initial_building=="empty" else slot.initial_building,"building_id":slot.id+".building"}
		_runtime.module_damage[slot.id]=0
		_authoring.slot_pins[slot.id]=bool(slot.authoring_pin)
	for region in _layout.decoration_regions:
		var settings={"seed":int(_layout.default_seed),"density":float(_layout.default_density),"asset_version":int(_layout.default_asset_version)}
		_authoring.region_settings[region.id]=settings
		_authoring.generated.merge(_generate_region(region,settings))

func snapshot()->Dictionary:return {"runtime":runtime,"authoring":authoring}
func slot_by_id(id: String)->Dictionary:
	for slot in _layout.slots:
		if slot.id==id:return slot.duplicate(true)
	return {}
func _failure(message: String)->Dictionary:return {"ok":false,"message":message}
func _runtime_commit(candidate: Dictionary,action: String)->Dictionary:
	var issue=_validate_runtime(candidate)
	if not issue.is_empty():return _failure(issue)
	candidate.revision=int(_runtime.revision)+1
	_runtime=candidate.duplicate(true)
	return {"ok":true,"action":action,"revision":_runtime.revision,"scope":"independent_fixture"}
func construct(id: String,kind: String)->Dictionary:
	var slot=slot_by_id(id)
	if slot.is_empty():return _failure("没有选择有效地块。")
	if not slot.get("gameplay_buildable",false):return _failure("该地块不允许游戏建设。")
	if not kind in slot.allowed_buildings:return _failure("此地块不允许该类设施。")
	if int(_runtime.growth_stage)<int(slot.unlock_stage):return _failure("地块尚未随成长开放。")
	if _runtime.slot_occupancy[id].status!="empty":return _failure("地块已有设施或正在施工。")
	var candidate=runtime;candidate.slot_occupancy[id].status="building";candidate.slot_occupancy[id].building_type=kind
	return _runtime_commit(candidate,"construct:"+id)
func finish_construction(id: String)->Dictionary:
	if not _runtime.slot_occupancy.has(id) or _runtime.slot_occupancy[id].status!="building":return _failure("该地块没有待完成施工。")
	var candidate=runtime;candidate.slot_occupancy[id].status="built";return _runtime_commit(candidate,"finish:"+id)
func demolish(id: String)->Dictionary:
	if not _runtime.slot_occupancy.has(id) or _runtime.slot_occupancy[id].status=="empty":return _failure("该地块为空。")
	var candidate=runtime;candidate.slot_occupancy[id].status="empty";candidate.slot_occupancy[id].building_type="";candidate.module_damage[id]=0
	return _runtime_commit(candidate,"demolish:"+id)
func set_growth(stage: int)->Dictionary:
	if stage<1 or stage>3:return _failure("成长仅有三档。")
	var candidate=runtime;candidate.growth_stage=stage;return _runtime_commit(candidate,"growth")
func set_damage(module: String,level: int)->Dictionary:
	if not _runtime.module_damage.has(module) or level<0 or level>2:return _failure("损毁目标或档位无效。")
	if _runtime.slot_occupancy.has(module) and _runtime.slot_occupancy[module].status=="empty":return _failure("空地没有可损毁的建筑。")
	var candidate=runtime;candidate.module_damage[module]=level;return _runtime_commit(candidate,"damage:"+module)
func set_gate_open(opened: bool)->Dictionary:
	var candidate=runtime;candidate.gate_open=opened;return _runtime_commit(candidate,"gate_open")
func _authoring_commit(candidate: Dictionary,action: String)->Dictionary:
	var issue=_validate_authoring(candidate)
	if not issue.is_empty():return _failure(issue)
	candidate.revision=int(_authoring.revision)+1;_authoring=candidate.duplicate(true)
	return {"ok":true,"action":action,"revision":_authoring.revision,"scope":"authoring_only"}
func move_warehouse(delta: Vector2)->Dictionary:
	var id="tongguan.slot.rear_storage_01"
	if _runtime.slot_occupancy[id].status!="built":return _failure("先在仓储地块完成设施，再移动其制作表现。")
	var candidate=authoring
	var offset: Array=candidate.manual_overrides.get(id,{}).get("offset_m",[0.0,0.0])
	candidate.manual_overrides[id]={"offset_m":[float(offset[0])+delta.x,float(offset[1])+delta.y],"authoring_pin":true}
	return _authoring_commit(candidate,"move_warehouse")
func edit_rear_road()->Dictionary:
	var candidate=authoring
	candidate.roads[1].points_m[1]=[-610.0,-140.0] if float(candidate.roads[1].points_m[1][0])==-620 else [-620.0,-140.0]
	return _authoring_commit(candidate,"edit_rear_road")
func set_slot_pin(id: String,pinned: bool)->Dictionary:
	if not _authoring.slot_pins.has(id):return _failure("地块不存在。")
	var candidate=authoring;candidate.slot_pins[id]=pinned;return _authoring_commit(candidate,"slot_pin")
func delete_tree(id: String)->Dictionary:
	if not _authoring.generated.has(id):return _failure("请先选择一簇树林。")
	if _authoring.pinned_tree_ids.get(id,false):return _failure("这簇树林已冻结；请先解除冻结。")
	var candidate=authoring;candidate.generated.erase(id);candidate.deleted_ids[id]=true;return _authoring_commit(candidate,"delete_tree")
func pin_tree(id: String)->Dictionary:
	if not _authoring.generated.has(id):return _failure("树林不存在。")
	var candidate=authoring;candidate.pinned_tree_ids[id]=not bool(candidate.pinned_tree_ids.get(id,false));return _authoring_commit(candidate,"pin_tree")
func protected_hash()->String:
	var pins={}
	for id in _authoring.pinned_tree_ids:
		if _authoring.pinned_tree_ids[id] and _authoring.generated.has(id):pins[id]=_authoring.generated[id]
	return digest({"fixed_refs":_authoring.fixed_refs,"slots":_layout.slots,"slot_pins":_authoring.slot_pins,"roads":_authoring.roads,"overrides":_authoring.manual_overrides,"deleted_ids":_authoring.deleted_ids,"pinned_trees":pins})
func _region(id: String)->Dictionary:
	for region in _layout.decoration_regions:
		if region.id==id:return region
	return {}
func _tree(region: Dictionary,gx: int,gy: int,settings: Dictionary)->Dictionary:
	if float(settings.density)<=0.0:return {}
	var id="tongguan.decor.%s.%d.%d"%[region.id,gx,gy]
	var hash_value=("%s|%d|%s"%[_layout.generator_version,int(settings.seed),id]).sha256_text()
	var rank=float(hash_value.substr(0,6).hex_to_int())/16777215.0
	if rank>float(settings.density):return {}
	var cell=float(_layout.grid_cell_m);var bounds: Array=region.bounds_m
	var x=float(bounds[0])+gx*cell+cell*(0.25+0.5*float(hash_value.substr(6,4).hex_to_int())/65535.0)
	var y=float(bounds[1])+gy*cell+cell*(0.25+0.5*float(hash_value.substr(10,4).hex_to_int())/65535.0)
	var point=Vector2(x,y)
	if x>=float(bounds[0])+float(bounds[2]) or y>=float(bounds[1])+float(bounds[3]):return {}
	# Forest regions are outside the city. Keep corridors and known water clear.
	if _distance_to_line(point,_layout.fixed_refs.main_corridor)<100:return {}
	for feature in _water_features:
		if feature.geometry=="polygon" and _inside(point,feature.points_m):return {}
		var boundary: Array=feature.points_m.duplicate()
		if feature.geometry=="polygon":boundary.append(boundary[0])
		if _distance_to_line(point,boundary)<(25.0 if feature.geometry=="polygon" else 45.0):return {}
	return {"id":id,"region_id":region.id,"grid":[gx,gy],"position_m":[snappedf(x,0.001),snappedf(y,0.001)],"source_seed":int(settings.seed),"asset_version":int(settings.asset_version),"kind":"forest"}
func _generate_region(region: Dictionary,settings: Dictionary)->Dictionary:
	var result={};var bounds: Array=region.bounds_m;var cell=float(_layout.grid_cell_m)
	for gy in range(int(ceil(float(bounds[3])/cell))):
		for gx in range(int(ceil(float(bounds[2])/cell))):
			var tree=_tree(region,gx,gy,settings)
			if not tree.is_empty():result[tree.id]=tree
	return result
func preview_regeneration(regions: Array,seed: int,density: float,asset_version: int)->Dictionary:
	if regions.is_empty() or seed<0 or seed>2147483647 or not is_finite(density) or density<0 or density>1 or not asset_version in [1,2]:return _failure("种子、密度或素材版本无效。")
	var unique={}
	for region_id in regions:
		if not region_id is String or _region(region_id).is_empty() or unique.has(region_id):return _failure("仅能重生成选定且不重复的树林区域。")
		unique[region_id]=true
	var candidate=authoring;var settings={"seed":seed,"density":density,"asset_version":asset_version}
	for region_id in regions:
		for id in candidate.generated.keys():
			if candidate.generated[id].region_id==region_id and not candidate.pinned_tree_ids.get(id,false):candidate.generated.erase(id)
		var generated=_generate_region(_region(region_id),settings)
		for id in generated:
			if candidate.deleted_ids.has(id) or candidate.pinned_tree_ids.get(id,false):continue
			candidate.generated[id]=generated[id]
		candidate.region_settings[region_id]=settings.duplicate(true)
	var added=[];var removed=[];var updated=[]
	for id in candidate.generated:
		if not _authoring.generated.has(id):added.append(id)
		elif digest(candidate.generated[id])!=digest(_authoring.generated[id]):updated.append(id)
	for id in _authoring.generated:
		if not candidate.generated.has(id):removed.append(id)
	added.sort();removed.sort();updated.sort()
	_token_counter+=1;var token="preview_%d_%d"%[get_instance_id(),_token_counter]
	_pending.clear();_pending[token]={"candidate":candidate,"runtime_revision":int(_runtime.revision),"authoring_revision":int(_authoring.revision),"protected_hash":protected_hash()}
	return {"ok":true,"token":token,"added":added,"removed":removed,"updated":updated,"protected_hash":protected_hash(),"candidate_generated":candidate.generated.duplicate(true)}
func commit_regeneration(token: String)->Dictionary:
	if not _pending.has(token):return _failure("请先生成差异预览。")
	var proposal: Dictionary=_pending[token];_pending.erase(token)
	if proposal.runtime_revision!=int(_runtime.revision) or proposal.authoring_revision!=int(_authoring.revision) or proposal.protected_hash!=protected_hash():return _failure("预览已过期；请重新预览。")
	return _authoring_commit(proposal.candidate,"commit_regeneration")
func discard_preview()->void:_pending.clear()

func _inside(point: Vector2,points: Array)->bool:
	var polygon=PackedVector2Array()
	for p in points:polygon.append(Vector2(p[0],p[1]))
	return Geometry2D.is_point_in_polygon(point,polygon)
func _distance_to_line(point: Vector2,points: Array)->float:
	var best=INF
	for i in range(points.size()-1):best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,Vector2(points[i][0],points[i][1]),Vector2(points[i+1][0],points[i+1][1]))))
	return best
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
func _validate_authoring(value: Dictionary)->String:
	if value.get("layout_version")!=_layout.layout_version or not integer(value.get("revision")) or value.revision<0:return "制作布局版本或修订号无效。"
	if digest(value.get("fixed_refs"))!=digest(_layout.fixed_refs):return "关门或核心骨架被改动。"
	for key in ["slot_pins","manual_overrides","deleted_ids","pinned_tree_ids","generated","region_settings"]:
		if not value.get(key) is Dictionary:return "制作字段缺失："+key
	if value.slot_pins.size()!=8:return "地块冻结集合不符。"
	for slot in _layout.slots:
		if not value.slot_pins.get(slot.id) is bool:return "地块冻结标记无效。"
	for id in value.manual_overrides:
		var entry: Variant=value.manual_overrides[id]
		if id!="tongguan.slot.rear_storage_01" or not entry is Dictionary or entry.get("authoring_pin")!=true:return "人工表现覆盖无效。"
		var offset: Variant=entry.get("offset_m")
		if not offset is Array or offset.size()!=2 or not (offset[0] is int or offset[0] is float) or not (offset[1] is int or offset[1] is float):return "人工移动坐标无效。"
		if not is_finite(float(offset[0])) or not is_finite(float(offset[1])) or absf(float(offset[0]))>9 or absf(float(offset[1]))>4:return "移动将使仓库超出地块安全占地。"
	var roads: Variant=value.get("roads")
	if not roads is Array or roads.size()!=2 or digest(roads[0])!=digest(_layout.roads[0]):return "主支路接口被改动。"
	if not roads[1] is Dictionary or roads[1].get("id")!=_layout.roads[1].id or roads[1].get("parent_id")!="main_corridor_candidate":return "道路身份无效。"
	var points: Variant=roads[1].get("points_m")
	if not points is Array or points.size()!=3 or digest(points[0])!=digest(_layout.roads[1].points_m[0]) or digest(points[2])!=digest(_layout.roads[1].points_m[2]):return "道路接点断开。"
	if not points[1] is Array or points[1].size()!=2 or not (points[1][0] is int or points[1][0] is float) or not (points[1][1] is int or points[1][1] is float):return "道路控制点无效。"
	if not float(points[1][0]) in [-620.0,-610.0] or float(points[1][1])!=-140.0:return "支路微调超出已验证区域。"
	var expected={}
	for region in _layout.decoration_regions:
		var settings: Variant=value.region_settings.get(region.id)
		if not settings is Dictionary or not integer(settings.get("seed")) or settings.seed<0 or settings.seed>2147483647 or not (settings.get("density") is int or settings.get("density") is float) or not is_finite(float(settings.density)) or settings.density<0 or settings.density>1 or not integer(settings.get("asset_version")) or not int(settings.asset_version) in [1,2]:return "树林区域配方无效。"
		expected.merge(_generate_region(region,settings))
	for id in value.deleted_ids:
		if value.deleted_ids[id]!=true or not str(id).begins_with("tongguan.decor."):return "删除记录无效。"
		expected.erase(id)
	for id in value.pinned_tree_ids:
		if not value.pinned_tree_ids[id] is bool:return "树林冻结标记无效。"
		if not value.pinned_tree_ids[id]:continue
		var tree: Variant=value.generated.get(id)
		if not tree is Dictionary or value.deleted_ids.has(id) or not tree.get("grid") is Array or tree.grid.size()!=2 or not integer(tree.get("source_seed")) or not integer(tree.get("asset_version")):return "冻结树林记录无效。"
		if tree.source_seed<0 or tree.source_seed>2147483647 or not int(tree.asset_version) in [1,2]:return "冻结树林种子或素材版本无效。"
		var region=_region(str(tree.get("region_id","")))
		if region.is_empty() or not integer(tree.grid[0]) or not integer(tree.grid[1]) or tree.grid[0]<0 or tree.grid[1]<0:return "冻结树林格网无效。"
		var original=_tree(region,int(tree.grid[0]),int(tree.grid[1]),{"seed":int(tree.source_seed),"density":1.0,"asset_version":int(tree.asset_version)})
		if original.is_empty() or digest(original)!=digest(tree):return "冻结树林的来源或位置不符。"
		expected[id]=tree
	if digest(expected)!=digest(value.generated):return "树林结果不符合区域配方、冻结或删除记录。"
	return ""
func export_save()->Dictionary:
	var envelope={"schema_version":1,"scope":"tongguan_p4_independent_fixture","runtime":runtime,"authoring":authoring}
	envelope.content_sha256=digest(envelope);return envelope
func restore_save(envelope: Variant)->Dictionary:
	if not envelope is Dictionary or envelope.get("schema_version")!=1 or envelope.get("scope")!="tongguan_p4_independent_fixture":return _failure("存档版本或用途不符。")
	var payload: Dictionary=envelope.duplicate(true);var checksum=payload.get("content_sha256","");payload.erase("content_sha256")
	if checksum!=digest(payload):return _failure("存档校验和不符。")
	if not envelope.get("runtime") is Dictionary or not envelope.get("authoring") is Dictionary:return _failure("存档状态不完整。")
	var runtime_issue=_validate_runtime(envelope.runtime)
	if not runtime_issue.is_empty():return _failure(runtime_issue)
	var authoring_issue=_validate_authoring(envelope.authoring)
	if not authoring_issue.is_empty():return _failure(authoring_issue)
	_runtime=envelope.runtime.duplicate(true);_authoring=envelope.authoring.duplicate(true)
	_runtime.revision=int(_runtime.revision);_runtime.growth_stage=int(_runtime.growth_stage);_authoring.revision=int(_authoring.revision)
	for id in _runtime.module_damage:_runtime.module_damage[id]=int(_runtime.module_damage[id])
	_pending.clear()
	return {"ok":true,"action":"restore","scope":"independent_fixture"}
func write_save(path: String)->Dictionary:
	var absolute=ProjectSettings.globalize_path(path);var parent=absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent)!=OK:return _failure("无法创建存档目录。")
	var temp=absolute+".pending";var backup=absolute+".previous"
	var file=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return _failure("无法写入临时存档。")
	file.store_string(JSON.stringify(export_save(),"\t",true,true));file.flush();file.close()
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK:return _failure("无法更新上一份备份。")
	var had_original=FileAccess.file_exists(absolute)
	if had_original and DirAccess.rename_absolute(absolute,backup)!=OK:return _failure("无法保留上一份存档。")
	if DirAccess.rename_absolute(temp,absolute)!=OK:
		if had_original:DirAccess.rename_absolute(backup,absolute)
		return _failure("无法提交新存档；已尝试恢复旧文件。")
	return {"ok":true,"action":"save","path":absolute}
func read_save(path: String)->Dictionary:
	if not FileAccess.file_exists(path):return _failure("还没有保存记录。")
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return restore_save(parsed)
