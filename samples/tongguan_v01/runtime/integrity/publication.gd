extends RefCounted
## Narrow read-only publication adapter. Never imports editor route logic.
const City=preload("res://runtime/settlement_state.gd")
var layout: Dictionary
var _cache: Dictionary={}
func _init()->void:layout=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/layout.json"))
func fail(message: String)->Dictionary:return {"ok":false,"message":message,"error":message}
func load_publication(path: String)->Dictionary:
	if not FileAccess.file_exists(path):return fail("尚无制作发布文件；请先在制作工具发布样本。")
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>2*1024*1024:return fail("发布文件无法读取或超过2MiB。")
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return fail("制作发布JSON不完整，当前表现保持。")
	var value: Variant=parser.data
	if not value is Dictionary or value.get("schema_version")!=1 or value.get("publication_kind")!="tongguan_r3_authoring" or not value.get("runtime_authoring") is Dictionary:return fail("不是R3制作发布格式。")
	var payload=value.duplicate(true);payload.erase("content_sha256")
	if value.get("content_sha256")!=City.digest(payload):return fail("制作发布文件校验失败。")
	if City.digest(value.get("coordinate_contract"))!=City.digest({"source_origin_m":[15000.0,10000.0],"unit":"meter","anchor_feature_id":"tongguan.gate.main","site_id":"tongguan"}):return fail("发布坐标映射或地点身份不符。")
	if value.get("layout_version")!=layout.layout_version or value.get("fixed_refs_sha256")!=City.digest(layout.fixed_refs) or value.get("layout_slots_sha256")!=City.digest(layout.slots):return fail("发布文件试图替换地块或核心骨架，未读取。")
	var meta={"schema_version":1,"publication_sha256":value.content_sha256,"authoring_sha256":City.digest(value.runtime_authoring),"authoring":value.runtime_authoring.duplicate(true)}
	var issue=validate_meta(meta)
	return fail(issue) if not issue.is_empty() else {"ok":true,"meta":meta}
func validate_meta(value: Variant)->String:
	if not value is Dictionary or value.get("schema_version")!=1 or not value.get("publication_sha256") is String or value.publication_sha256.length()!=64 or not value.get("authoring") is Dictionary:return "运行时制作发布引用无效。"
	var body: Dictionary=value.authoring;var digest=City.digest(body)
	if value.get("authoring_sha256")!=digest:return "发布投影校验失败。"
	if _cache.has(digest):return ""
	if body.get("layout_version")!=layout.layout_version or City.digest(body.get("fixed_refs"))!=City.digest(layout.fixed_refs):return "发布投影核心骨架不符。"
	for field in ["generated","manual_overrides","deleted_ids","slot_pins","region_settings","pinned_tree_ids"]:
		if not body.get(field) is Dictionary:return "发布投影缺少字段："+field
	if not body.get("roads") is Array or body.roads.size()!=layout.roads.size() or body.generated.size()>1000:return "发布道路或对象数量不符。"
	for i in body.roads.size():
		var road: Variant=body.roads[i];var expected: Dictionary=layout.roads[i]
		if not road is Dictionary or road.get("id")!=expected.id or road.get("parent_id")!=expected.parent_id or not road.get("points_m") is Array or road.points_m.size()<2 or road.points_m.size()>8:return "发布支路身份无效。"
		if City.digest(road.points_m[0])!=City.digest(expected.points_m[0]) or City.digest(road.points_m[-1])!=City.digest(expected.points_m[-1]):return "发布支路接点断开。"
		for point in road.points_m:
			if not valid_point(point):return "发布支路坐标无效。"
	for id in body.generated:
		var object: Variant=body.generated[id]
		if not object is Dictionary or object.get("id")!=id or not valid_point(object.get("position_m")) or not City.integer(object.get("asset_version")) or not int(object.asset_version) in [1,2]:return "发布树林身份、坐标或素材版本无效。"
	for id in body.manual_overrides:
		var item: Variant=body.manual_overrides[id]
		if id!="tongguan.slot.rear_storage_01" or not item is Dictionary or not valid_point(item.get("offset_m")) or absf(item.offset_m[0])>9 or absf(item.offset_m[1])>4:return "发布仓库移动超出安全占地。"
		var slot: Dictionary={}
		for candidate in layout.slots:
			if candidate.id==id:slot=candidate
		var polygon=PackedVector2Array();var center=Vector2.ZERO
		for point in slot.polygon_local_m:
			var p=Vector2(point[0],point[1]);polygon.append(p);center+=p
		center/=polygon.size();center+=Vector2(item.offset_m[0],item.offset_m[1])
		for delta in [Vector2(-16,-12),Vector2(16,-12),Vector2(16,10),Vector2(-16,10)]:
			if not Geometry2D.is_point_in_polygon(center+delta,polygon):return "发布仓库完整屋顶或墙体超出地块，当前表现保持。"
	for slot in layout.slots:
		if not body.slot_pins.get(slot.id) is bool:return "发布地块冻结集合无效。"
	if _cache.size()>=8:_cache.erase(_cache.keys()[0])
	_cache[digest]=true;return ""
func valid_point(point: Variant)->bool:
	if not point is Array or point.size()!=2:return false
	for component in point:
		if not (component is int or component is float) or not is_finite(component) or absf(component)>12000:return false
	return true
