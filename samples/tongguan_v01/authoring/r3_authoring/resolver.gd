extends RefCounted
## Authoring only. No GameState, clocks, resources or movement services.
const Source=preload("res://p4/settlement_host.gd")
const Document=preload("res://addons/strategic_map_editor/document.gd")
const PatchEngine=preload("res://r3_authoring/patch_engine.gd")
const ORIGIN=[15000.0,10000.0]
const GENERATOR="forest_grid_sha256_v2"
var error: String=""
var source: RefCounted
var state: Dictionary={}
var journal: Array=[]
var undo_stack: Array=[]
var redo_stack: Array=[]
var _pending: Dictionary={}
var _counter:=0
var _sequence:=0
var _input_hash: String=""
var _water_bounds: Array=[]
var _generated_cache: Dictionary={}
var _safe_cache: Dictionary={}
var _validator=Document.new()
func canonical(value: Variant)->String:return PatchEngine.canonical(value)
func digest(value: Variant)->String:return canonical(value).sha256_text()
func fail(message: String)->Dictionary:return {"ok":false,"message":message,"error":message}
func _init()->void:
	source=Source.new();error=source.error
	if not error.is_empty():return
	_input_hash=digest({"layout":source.layout,"water":source._water_features,"generator":GENERATOR})
	for feature in source._water_features:
		var points: Array=feature.points_m;var bounds=Rect2(Vector2(points[0][0],points[0][1]),Vector2.ZERO)
		for p in points:bounds=bounds.expand(Vector2(p[0],p[1]))
		_water_bounds.append(bounds.grow(50))
	state={"schema_version":1,"revision":0,"generator_version":GENERATOR,"region_settings":source.authoring.region_settings,"objects":{},"patches":{},"tombstones":{},"pins":{},"zone_pins":{},"zones":{},"feature_patches":{}}
	state.objects=_assemble(state).objects
	error=_validate(state)
func snapshot()->Dictionary:return state.duplicate(true)
func rect_points(bounds: Array)->Array:
	return [[bounds[0],bounds[1]],[bounds[0]+bounds[2],bounds[1]],[bounds[0]+bounds[2],bounds[1]+bounds[3]],[bounds[0],bounds[1]+bounds[3]]]
func paint_bounds(object: Dictionary)->Array:
	# Existing R1/R2 tree art: width80m, square atlas, anchor(.5,.78).
	# Include complete crown and ten meters of shadow/edge bleed, not just the anchor.
	return [float(object.position_m[0])-50.0,float(object.position_m[1])-72.4,100.0,100.0]
func packed(points: Array)->PackedVector2Array:
	var value=PackedVector2Array()
	for p in points:value.append(Vector2(p[0],p[1]))
	return value
func overlaps(a: Array,b: Array)->bool:
	return not Geometry2D.intersect_polygons(packed(a),packed(b)).is_empty()
func touched(object: Dictionary,zone: Dictionary)->bool:return overlaps(rect_points(paint_bounds(object)),zone.polygon_m)
func chunk_memberships(id: String)->Array:
	if not state.objects.has(id):return []
	var bounds=paint_bounds(state.objects[id]);var result=[]
	for y in range(floori(bounds[1]/512.0),floori((bounds[1]+bounds[3])/512.0)+1):
		for x in range(floori(bounds[0]/512.0),floori((bounds[0]+bounds[2])/512.0)+1):result.append("%d:%d"%[x,y])
	return result
func spatial_query(bounds: Array)->Array:
	var result=[]
	for id in state.objects:
		if overlaps(rect_points(bounds),rect_points(paint_bounds(state.objects[id]))):result.append(id)
	result.sort();return result
func _safe(object: Dictionary)->String:
	var key=str(object.position_m)
	if _safe_cache.has(key):return _safe_cache[key]
	var value=_safe_uncached(object)
	if _safe_cache.size()>2048:_safe_cache.clear()
	_safe_cache[key]=value;return value
func _safe_uncached(object: Dictionary)->String:
	var footprint=rect_points(paint_bounds(object))
	var object_rect=Rect2(Vector2(footprint[0][0],footprint[0][1]),Vector2(100,100))
	for slot in source.layout.slots:
		if overlaps(footprint,slot.polygon_local_m):return "reserved_building_footprint"
	for index in source._water_features.size():
		if not object_rect.intersects(_water_bounds[index]):continue
		var feature: Dictionary=source._water_features[index]
		if feature.geometry=="polygon" and overlaps(footprint,feature.points_m):return "water_footprint"
		for p in footprint:
			if source._distance_to_line(Vector2(p[0],p[1]),feature.points_m)<(15.0 if feature.geometry=="polygon" else 45.0):return "water_buffer"
	for p in footprint:
		if source._distance_to_line(Vector2(p[0],p[1]),source.layout.fixed_refs.main_corridor)<40:return "main_corridor_footprint"
	return ""
func _generate(region: Dictionary,settings: Dictionary)->Dictionary:
	var key=str(region.id)+digest(settings)
	if not _generated_cache.has(key):
		if _generated_cache.size()>=8:_generated_cache.erase(_generated_cache.keys()[0])
		_generated_cache[key]=source._generate_region(region,settings)
	return _generated_cache[key].duplicate(true)
func _assemble(candidate: Dictionary)->Dictionary:
	var objects={};var skipped=[]
	var manual={}
	for id in candidate.patches:
		if candidate.patches[id].op in ["add","update"]:manual[id]=candidate.patches[id].record
	var retained=candidate.pins.duplicate(true);retained.merge(candidate.zone_pins,true);retained.merge(manual,true)
	for region in source.layout.decoration_regions:
		var generated=_generate(region,candidate.region_settings[region.id])
		for id in generated:
			var object: Dictionary=generated[id]
			if candidate.tombstones.has(id) or retained.has(id):continue
			var reason=_safe(object)
			for zone in candidate.zones.values():
				if touched(object,zone):reason="zone_"+zone.kind;break
			if reason.is_empty():
				for other in retained.values():
					if overlaps(rect_points(paint_bounds(object)),rect_points(paint_bounds(other))):reason="manual_or_pinned_footprint";break
			if reason.is_empty():objects[id]=object
			else:skipped.append({"id":id,"reason":reason,"footprint_m":rect_points(paint_bounds(object))})
	var merged=PatchEngine.merge(objects,candidate.patches,candidate.pins,candidate.zone_pins,candidate.tombstones)
	return {"objects":merged.objects,"skipped":skipped,"conflicts":merged.conflicts}
func _validate(value: Variant)->String:
	if not value is Dictionary or value.get("schema_version")!=1 or value.get("generator_version")!=GENERATOR or not Source.integer(value.get("revision")) or value.revision<0:return "制作版本或生成器身份无效。"
	for field in ["region_settings","objects","patches","tombstones","pins","zone_pins","zones","feature_patches"]:
		if not value.get(field) is Dictionary:return "制作字段缺失："+field
	if value.objects.size()>1000 or value.patches.size()>1000 or value.zones.size()>100:return "制作样本容量超出限定范围。"
	for region in source.layout.decoration_regions:
		var setting: Variant=value.region_settings.get(region.id)
		if not setting is Dictionary or not Source.integer(setting.get("seed")) or setting.seed<0 or setting.seed>2147483647 or not (setting.get("density") is int or setting.get("density") is float) or not is_finite(setting.density) or setting.density<0 or setting.density>1 or not int(setting.get("asset_version",0)) in [1,2]:return "生成配方无效。"
	for id in value.zones:
		var zone: Variant=value.zones[id]
		if not zone is Dictionary or zone.get("id")!=id or zone.get("kind") not in ["lock","exclude_generation"] or not zone.get("polygon_m") is Array or zone.polygon_m.size()!=4:return "锁区或排除区格式无效。"
		for point in zone.polygon_m:
			if not _point_valid(point):return "区域占地坐标无效。"
		if Geometry2D.triangulate_polygon(packed(zone.polygon_m)).is_empty():return "区域占地无有效面积。"
	for id in value.patches:
		var patch: Variant=value.patches[id]
		if not patch is Dictionary or patch.get("op") not in ["add","update","delete"] or patch.get("generator_version")!=GENERATOR:return "补丁种类或来源不符。"
		if patch.op in ["add","update"] and (not patch.get("record") is Dictionary or patch.record.get("id")!=id):return "补丁丢失稳定对象身份。"
		if patch.op in ["add","update"] and not _object_issue(patch.record,id).is_empty():return "补丁对象字段无效。"
	for id in value.tombstones:
		if value.tombstones[id]!=true or value.objects.has(id):return "删除记录被丢弃或对象复活。"
	for id in value.objects:
		var object: Variant=value.objects[id]
		if not _object_issue(object,id).is_empty():return "制作对象格式或坐标无效。"
		if not _safe(object).is_empty():return "对象完整占地侵入水域、建设地块或主通道。"
	for field in ["pins","zone_pins"]:
		for id in value[field]:
			if not _object_issue(value[field][id],id).is_empty() or value.tombstones.has(id) or digest(value[field][id])!=digest(value.objects.get(id)):return "冻结记录无效或与对象不符。"
	for id in value.feature_patches:
		var patch: Variant=value.feature_patches[id]
		if not patch is Dictionary or not patch.get("points_m") is Array or not _feature_issue(id,patch.points_m).is_empty():return "人工道路补丁无效或断开接点。"
	if digest(_assemble(value).objects)!=digest(value.objects):return "生成结果与人工补丁、锁区或删除意图不符。"
	return ""
func _point_valid(point: Variant)->bool:
	if not point is Array or point.size()!=2:return false
	for component in point:
		if not (component is int or component is float) or not is_finite(component) or absf(component)>8000:return false
	return true
func _object_issue(object: Variant,id: String)->String:
	if not object is Dictionary or object.get("id")!=id or not _point_valid(object.get("position_m")) or not Source.integer(object.get("asset_version")) or not int(object.asset_version) in [1,2] or object.get("kind")!="forest":return "制作对象身份或素材无效。"
	if id.length()>128 or (not id.begins_with("manual.") and not id.begins_with("tongguan.decor.")):return "制作对象ID来源无效。"
	return ""
func _feature_issue(id: String,points_m: Array)->String:
	var matches=source.layout.roads.filter(func(road):return road.id==id)
	if matches.size()!=1 or points_m.size()<2 or points_m.size()>8:return "仅修改已登记支路，端点必须保持。"
	var original: Array=matches[0].points_m
	if digest(points_m[0])!=digest(original[0]) or digest(points_m[-1])!=digest(original[-1]):return "支路接点不可断开。"
	var bounds=Rect2(Vector2(original[0][0],original[0][1]),Vector2.ZERO)
	for point in original:bounds=bounds.expand(Vector2(point[0],point[1]))
	bounds=bounds.grow(20)
	for point in points_m:
		if not _point_valid(point) or not bounds.has_point(Vector2(point[0],point[1])):return "支路编辑超出预留走廊。"
	return ""
func _normal(value: Dictionary)->String:
	var copy=value.duplicate(true);copy.erase("revision");return digest(copy)
func _adopt(candidate: Dictionary,action: String,details: Dictionary={},history:=true)->Dictionary:
	var issue=_validate(candidate)
	if not issue.is_empty():return fail(issue)
	if not _validator.validate(_v4(candidate)).is_empty():return fail("候选不能通过原v4文档校验。")
	var before=snapshot();candidate.revision=int(state.revision)+1;state=candidate.duplicate(true);_pending.clear()
	if history:
		undo_stack.append({"before":before,"after":snapshot()});redo_stack.clear()
		if undo_stack.size()>100:undo_stack.pop_front()
	journal.append({"revision":state.revision,"action":action,"details":details.duplicate(true),"after_sha256":digest(state)})
	if journal.size()>500:journal.pop_front()
	return {"ok":true,"revision":state.revision,"action":action}
func _locked(id: String)->bool:return state.pins.has(id) or state.zone_pins.has(id)
func _rebuild(candidate: Dictionary)->Dictionary:
	candidate.objects=_assemble(candidate).objects;return candidate
func add_object(at: Array,asset_version: int)->Dictionary:
	if at.size()!=2 or not asset_version in [1,2]:return fail("添加参数无效。")
	_counter+=1;var id="manual.%d"%_counter
	var object={"id":id,"region_id":"manual","grid":[],"position_m":at.duplicate(),"source_seed":0,"asset_version":asset_version,"kind":"forest"}
	for zone in state.zones.values():
		if zone.kind=="lock" and touched(object,zone):return fail("完整绘制占地进入锁区，未添加。")
	var candidate=snapshot();candidate.patches[id]={"op":"add","record":object,"generator_version":GENERATOR};_rebuild(candidate)
	var result=_adopt(candidate,"add",{"id":id,"footprint_m":rect_points(paint_bounds(object))});result.id=id;return result
func update_object(id: String,values: Dictionary)->Dictionary:
	if not state.objects.has(id) or _locked(id):return fail("对象不存在或已冻结；请先解锁。")
	for key in values:
		if key not in ["position_m","asset_version"]:return fail("本接口只修改对象位置或素材版本。")
	var record: Dictionary=state.objects[id].duplicate(true);record.merge(values,true)
	for zone in state.zones.values():
		if zone.kind=="lock" and touched(record,zone):return fail("对象完整占地将进入锁区。")
	var candidate=snapshot();var op="add" if id.begins_with("manual.") else "update"
	candidate.patches[id]={"op":op,"record":record,"generator_version":GENERATOR};_rebuild(candidate)
	return _adopt(candidate,"update",{"id":id,"before_footprint_m":rect_points(paint_bounds(state.objects[id])),"after_footprint_m":rect_points(paint_bounds(record))})
func delete_object(id: String)->Dictionary:
	if not state.objects.has(id) or _locked(id):return fail("对象不存在或已冻结。")
	var candidate=snapshot();candidate.tombstones[id]=true;candidate.patches[id]={"op":"delete","generator_version":GENERATOR};_rebuild(candidate)
	return _adopt(candidate,"delete",{"id":id,"footprint_m":rect_points(paint_bounds(state.objects[id]))})
func pin_object(id: String,pinned: bool)->Dictionary:
	if not state.objects.has(id):return fail("对象不存在。")
	var candidate=snapshot()
	if pinned:candidate.pins[id]=candidate.objects[id].duplicate(true)
	else:candidate.pins.erase(id)
	_rebuild(candidate);return _adopt(candidate,"pin",{"id":id,"pinned":pinned})
func add_zone(bounds: Array,kind: String)->Dictionary:
	if bounds.size()!=4 or bounds[2]<=0 or bounds[3]<=0 or not kind in ["lock","exclude_generation"]:return fail("区域参数无效。")
	_counter+=1;var id="zone.%d"%_counter;var zone={"id":id,"kind":kind,"polygon_m":rect_points(bounds)};var candidate=snapshot();candidate.zones[id]=zone
	if kind=="lock":
		for object in state.objects.values():
			if touched(object,zone):candidate.zone_pins[object.id]=object.duplicate(true)
	_rebuild(candidate);var result=_adopt(candidate,"zone",zone);result.id=id;return result
func remove_zone(id: String)->Dictionary:
	if not state.zones.has(id):return fail("区域不存在。")
	var candidate=snapshot();candidate.zones.erase(id);candidate.zone_pins.clear()
	for object in state.objects.values():
		for zone in candidate.zones.values():
			if zone.kind=="lock" and touched(object,zone):candidate.zone_pins[object.id]=object.duplicate(true)
	_rebuild(candidate);return _adopt(candidate,"remove_zone",{"id":id})
func update_feature(id: String,points_m: Array)->Dictionary:
	var issue=_feature_issue(id,points_m)
	if not issue.is_empty():return fail(issue)
	var footprints=[]
	for i in range(points_m.size()-1):
		var a=Vector2(points_m[i][0],points_m[i][1]);var b=Vector2(points_m[i+1][0],points_m[i+1][1]);var direction=(b-a).normalized()*8;var normal=Vector2(-direction.y,direction.x)
		var polygon=[]
		for point in [a-direction+normal,b+direction+normal,b+direction-normal,a-direction-normal]:polygon.append([point.x,point.y])
		footprints.append({"id":id,"paint_footprint_m":polygon})
	var conflicts=_conflicts({"generator_version":GENERATOR,"objects":state.objects,"features":footprints})
	if not conflicts.is_empty():return {"ok":false,"message":"支路完整占地进入锁区，未修改。","conflicts":conflicts}
	var candidate=snapshot();candidate.feature_patches[id]={"points_m":points_m.duplicate(true)}
	return _adopt(candidate,"update_feature",{"id":id,"points_m":points_m})
func protected_hash()->String:return digest({"patches":state.patches,"tombstones":state.tombstones,"pins":state.pins,"zone_pins":state.zone_pins,"zones":state.zones,"feature_patches":state.feature_patches,"fixed_refs":source.layout.fixed_refs,"slots":source.layout.slots})
func exclusion_violations()->Array:
	var result=[]
	for id in state.objects:
		if state.patches.has(id) or _locked(id):continue
		for zone in state.zones.values():
			if touched(state.objects[id],zone):result.append(id)
	return result
func preview_regeneration(regions: Array,seed: int,density: float,asset_version: int)->Dictionary:
	if regions.is_empty() or seed<0 or seed>2147483647 or not is_finite(density) or density<0 or density>1 or not asset_version in [1,2]:return fail("生成参数无效。")
	var candidate=snapshot();var unique={}
	for region in regions:
		if not candidate.region_settings.has(region) or unique.has(region):return fail("只能选择有效且不重复的区域。")
		unique[region]=true;candidate.region_settings[region]={"seed":seed,"density":density,"asset_version":asset_version}
	var assembled=_assemble(candidate);candidate.objects=assembled.objects
	var issue=_validate(candidate)
	if not issue.is_empty():return fail(issue)
	var conflicts=_conflicts({"generator_version":GENERATOR,"objects":candidate.objects,"features":[]})
	if not conflicts.is_empty():return {"ok":false,"message":"候选与人工内容冲突，整批未提交。","conflicts":conflicts}
	var added=[];var updated=[];var removed=[]
	for id in candidate.objects:
		if not state.objects.has(id):added.append(id)
		elif digest(candidate.objects[id])!=digest(state.objects[id]):updated.append(id)
	for id in state.objects:
		if not candidate.objects.has(id):removed.append(id)
	_sequence+=1;var token="authoring_%d_%d"%[get_instance_id(),_sequence];_pending.clear();_pending[token]={"input_sha256":digest(state),"candidate":candidate}
	return {"ok":true,"token":token,"added":added,"updated":updated,"removed":removed,"skipped":assembled.skipped,"conflicts":[],"candidate_objects":candidate.objects.duplicate(true)}
func commit_regeneration(token: String)->Dictionary:
	if not _pending.has(token):return fail("预览不存在或已过期。")
	var proposal: Dictionary=_pending[token];_pending.clear()
	if proposal.input_sha256!=digest(state):return fail("制作状态已改变，请重新预览。")
	return _adopt(proposal.candidate,"regenerate",{"input_sha256":proposal.input_sha256})
func _conflicts(proposal: Dictionary)->Array:
	var conflicts=[];var version=str(proposal.get("generator_version",""));var objects: Dictionary=proposal.get("objects",{})
	if version!=GENERATOR:
		var references=state.patches.keys()+state.tombstones.keys()+state.pins.keys()+state.zone_pins.keys()
		for id in references:
			if not str(id).begins_with("manual.") and not objects.has(id):conflicts.append({"code":"id_mismatch","object_id":id,"message":"新生成器丢失被人工引用的稳定ID，需显式迁移。"})
		if conflicts.is_empty():conflicts.append({"code":"generator_version_mismatch","object_id":version,"message":"不支持的生成器版本，未自动猜测迁移。"})
	var protected=state.pins.duplicate(true);protected.merge(state.zone_pins,true)
	for id in state.patches:
		if state.patches[id].op in ["add","update"]:protected[id]=state.patches[id].record
	for id in objects:
		if state.tombstones.has(id):conflicts.append({"code":"tombstone_revived","object_id":id,"message":"候选复活了已删除对象。"});continue
		if protected.has(id) and digest(objects[id])!=digest(protected[id]):conflicts.append({"code":"protected_content","object_id":id,"message":"候选改动冻结或人工内容。"})
		if not protected.has(id) and _object_issue(objects[id],id).is_empty():
			for zone in state.zones.values():
				if touched(objects[id],zone):conflicts.append({"code":"protected_footprint" if zone.kind=="lock" else "generation_excluded","object_id":id,"zone_id":zone.id,"footprint_m":rect_points(paint_bounds(objects[id])),"message":"未经约束的生成候选占地进入保护区域。"})
	for feature in proposal.get("features",[]):
		var footprint: Array=feature.get("paint_footprint_m",[])
		for zone in state.zones.values():
			if zone.kind=="lock" and footprint.size()>2 and overlaps(footprint,zone.polygon_m):conflicts.append({"code":"protected_footprint","object_id":feature.id,"zone_id":zone.id,"footprint_m":footprint.duplicate(true),"message":"候选边界完整占地穿过锁区。"})
	return conflicts
func preview_candidate(proposal: Dictionary)->Dictionary:
	if not proposal.get("objects") is Dictionary or not proposal.get("features",[]) is Array:return fail("外部候选格式无效。")
	for feature in proposal.get("features",[]):
		if not feature is Dictionary or not feature.get("id") is String or not feature.get("paint_footprint_m") is Array or feature.paint_footprint_m.size()<3:return fail("候选边界完整占地无效。")
		for point in feature.paint_footprint_m:
			if not _point_valid(point):return fail("候选边界坐标无效。")
	var conflicts=_conflicts(proposal)
	if conflicts.is_empty():
		for id in proposal.objects:
			if not _object_issue(proposal.objects[id],id).is_empty() or not _safe(proposal.objects[id]).is_empty():return fail("候选对象格式或完整占地无效。")
	return {"ok":conflicts.is_empty(),"message":"外部候选检查通过。" if conflicts.is_empty() else "候选冲突，整批未提交。","conflicts":conflicts,"candidate_objects":proposal.objects.duplicate(true)}
func preview_conflict(kind: String)->Dictionary:
	var proposal={"generator_version":GENERATOR,"objects":state.objects.duplicate(true),"features":[]}
	if kind=="id_upgrade":
		proposal.generator_version="forest_grid_v3_unmapped";var renamed={}
		for id in proposal.objects:
			var object: Dictionary=proposal.objects[id].duplicate(true);object.id="v3."+id;renamed[object.id]=object
		proposal.objects=renamed
	else:
		var locked=state.zones.values().filter(func(zone):return zone.kind=="lock")
		if locked.is_empty():return fail("请先创建一个锁区再检查穿越候选。")
		var polygon: Array=locked[0].polygon_m
		# A real candidate paint polygon crossing the selected zone; same generic
		# validator also accepts non-intersecting candidates (covered by tests).
		proposal.features=[{"id":"river_boundary_candidate","paint_footprint_m":polygon.duplicate(true)}]
	return preview_candidate(proposal)
func _step(undoing: bool)->Dictionary:
	var stack=undo_stack if undoing else redo_stack;var other=redo_stack if undoing else undo_stack
	if stack.is_empty():return fail("没有可恢复的制作历史。")
	var entry: Dictionary=stack.back();var expected: Dictionary=entry.after if undoing else entry.before
	if _normal(state)!=_normal(expected):return fail("制作分支已变化，未覆盖当前版本。")
	var result=_adopt((entry.before if undoing else entry.after).duplicate(true),"undo" if undoing else "redo",{},false)
	if result.ok:other.append(stack.pop_back())
	return result
func undo()->Dictionary:return _step(true)
func redo()->Dictionary:return _step(false)
func _v4(candidate: Dictionary)->Dictionary:
	var doc=Document.blank();doc.title="潼关 R3 制作保护样本";doc.canvas_size=[30000,20000]
	var main=Document.feature("valley",[],"主通道（制作参照）","tongguan.corridor.main")
	for p in source.layout.fixed_refs.main_corridor:main.points.append([p[0]+ORIGIN[0],p[1]+ORIGIN[1]])
	main.protected=true;doc.features.append(main)
	var gate=Document.feature("pass",[[ORIGIN[0],ORIGIN[1]]],"潼关","tongguan.gate.main");gate.domain_id="tongguan";gate.visual={"anchor_only":true};gate.protected=true;doc.features.append(gate)
	for road in source.layout.roads:
		var record=Document.feature("valley",[],"关后支路",road.id)
		var points: Array=candidate.feature_patches.get(road.id,{}).get("points_m",road.points_m)
		for p in points:record.points.append([p[0]+ORIGIN[0],p[1]+ORIGIN[1]])
		record.width=8;record.protected=true;doc.features.append(record)
	for id in candidate.objects:
		var object: Dictionary=candidate.objects[id]
		doc.presentation.instances.append({"id":id,"asset":"art_01" if int(object.asset_version)==1 else "art_02","position":[object.position_m[0]+ORIGIN[0],object.position_m[1]+ORIGIN[1]],"scale":0.25,"plane":"terrain","locked":candidate.pins.has(id) or candidate.zone_pins.has(id),"group_id":str(object.region_id)})
	return doc
func export_v4()->Dictionary:return _v4(state)
func v4_validate()->String:return _validator.validate(export_v4())
func write_save(path: String)->Dictionary:
	var value={"schema_version":1,"input_sha256":_input_hash,"state":snapshot(),"journal":journal.duplicate(true),"undo":undo_stack.duplicate(true),"redo":redo_stack.duplicate(true),"id_counter":_counter};value.content_sha256=digest(value)
	return _atomic_write(path,value)
func _atomic_write(path: String,value: Dictionary,max_bytes: int=16*1024*1024)->Dictionary:
	var shared=OS.get_environment("APPDATA").replace("\\","/").path_join("tongguan_slice_v01_integrity/authoring/")
	if path.contains("..") or (not path.begins_with("user://") and not path.replace("\\","/").begins_with(shared)):return fail("仅写入本工具独立用户目录。")
	var encoded=JSON.stringify(value,"\t",true,true)
	if encoded.to_utf8_buffer().size()>max_bytes:return fail("样本超过保存容量，旧文件保持；请减少历史或对象规模。")
	var absolute=ProjectSettings.globalize_path(path);DirAccess.make_dir_recursive_absolute(absolute.get_base_dir());var file=FileAccess.open(path+".pending",FileAccess.WRITE)
	if file==null:return fail("无法写入候选版本。")
	file.store_string(encoded);file.flush();file.close()
	if FileAccess.file_exists(path) and FileAccess.file_exists(path+".previous"):DirAccess.remove_absolute(absolute+".previous")
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(absolute,absolute+".previous")!=OK:return fail("无法保留旧版。")
	if DirAccess.rename_absolute(absolute+".pending",absolute)!=OK:
		if FileAccess.file_exists(path+".previous"):DirAccess.rename_absolute(absolute+".previous",absolute)
		return fail("新版本未提交，旧版保留。")
	return {"ok":true,"path":absolute}
func _read_candidate(path: String)->Dictionary:
	if not FileAccess.file_exists(path):return fail("制作样本尚不存在。")
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>16*1024*1024:return fail("制作样本无法读取或超过16MiB。")
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return fail("制作样本JSON不完整，尝试完整备用版本。")
	var value: Variant=parser.data
	if not value is Dictionary or value.get("schema_version")!=1 or value.get("input_sha256")!=_input_hash:return fail("制作输入版本不符。")
	var payload=value.duplicate(true);payload.erase("content_sha256")
	if value.get("content_sha256")!=digest(payload):return fail("制作样本校验失败。")
	var issue=_validate(value.get("state"))
	if not issue.is_empty():return fail(issue)
	if not value.get("journal") is Array or not value.get("undo") is Array or not value.get("redo") is Array or not Source.integer(value.get("id_counter")):return fail("历史或ID序号无效。")
	if value.journal.size()>500 or value.undo.size()>100 or value.redo.size()>100 or value.id_counter<0:return fail("制作历史容量或ID序号无效。")
	var identifiers=value.state.patches.keys()+value.state.zones.keys()
	for entry in value.undo+value.redo:
		if not entry is Dictionary or not _validate(entry.get("before")).is_empty() or not _validate(entry.get("after")).is_empty():return fail("历史包含不完整或无效制作版本。")
		identifiers.append_array(entry.before.patches.keys()+entry.after.patches.keys()+entry.before.zones.keys()+entry.after.zones.keys())
	for id in identifiers:
		if str(id).begins_with("manual.") or str(id).begins_with("zone."):
			if str(id).get_slice(".",1).to_int()>int(value.id_counter):return fail("制作ID序号倒退，可能覆盖已有对象。")
	return {"ok":true,"value":value}
func read_save(path: String)->Dictionary:
	var last_error="制作样本尚不存在。"
	for candidate in [path,path+".previous",path+".pending"]:
		var result=_read_candidate(candidate)
		if not result.ok:last_error=result.get("message",last_error);continue
		var value: Dictionary=result.value
		state=value.state.duplicate(true);journal=value.journal.duplicate(true);undo_stack=value.undo.duplicate(true);redo_stack=value.redo.duplicate(true);_counter=int(value.id_counter);_pending.clear()
		return {"ok":true,"recovered":candidate!=path,"message":"已恢复完整备用制作版本："+candidate if candidate!=path else "已重读完整制作版本。"}
	return fail(last_error)
func publication()->Dictionary:
	var runtime=source.authoring;runtime.generated=state.objects.duplicate(true);runtime.deleted_ids=state.tombstones.duplicate(true)
	runtime.region_settings=state.region_settings.duplicate(true);runtime.pinned_tree_ids.clear()
	for id in state.pins:runtime.pinned_tree_ids[id]=true
	for id in state.zone_pins:runtime.pinned_tree_ids[id]=true
	runtime.generator_version=GENERATOR
	runtime.r3_provenance={"patch_sha256":digest(state.patches),"zones_sha256":digest(state.zones),"footprint_version":"square80_anchor078_edge10_v1","source_v4_sha256":digest(export_v4())}
	for road in runtime.roads:
		if state.feature_patches.has(road.id):road.points_m=state.feature_patches[road.id].points_m.duplicate(true)
	var value={"schema_version":1,"publication_kind":"tongguan_r3_authoring","layout_version":source.layout.layout_version,"generator_version":GENERATOR,"source_input_sha256":_input_hash,"coordinate_contract":{"source_origin_m":ORIGIN.duplicate(),"unit":"meter","anchor_feature_id":"tongguan.gate.main","site_id":"tongguan"},"source_v4":export_v4(),"patch_sidecar":snapshot(),"runtime_authoring":runtime,"fixed_refs_sha256":digest(source.layout.fixed_refs),"layout_slots_sha256":digest(source.layout.slots),"logic_authority":"unchanged_native_runtime","source_asset_mapping":{"art_01":"tree_willow","art_02":"tree_grove"}};value.content_sha256=digest(value);return value
func publish(path: String)->Dictionary:
	var issue=_validate(state)
	if not issue.is_empty():return fail(issue)
	var value=publication();var folder=path.get_base_dir().path_join("publications/"+str(value.content_sha256).left(20))
	for entry in [["source.map.json",value.source_v4],["overrides.json",value.patch_sidecar],["recipe.json",{"generator_version":GENERATOR,"source_input_sha256":_input_hash,"region_settings":state.region_settings}]]:
		var destination=folder.path_join(entry[0])
		if FileAccess.file_exists(destination):
			if digest(JSON.parse_string(FileAccess.get_file_as_string(destination)))!=digest(entry[1]):return fail("内容寻址发布目录已有不同文件，未覆盖。")
		else:
			var written=_atomic_write(destination,entry[1])
			if not written.ok:return written
	var result=_atomic_write(path,value,2*1024*1024);result.source_map_path=ProjectSettings.globalize_path(folder.path_join("source.map.json"));return result
