@tool
extends RefCounted
## Visual ground footprints, never navigation or campaign geometry.
const Catalog = preload("art_catalog.gd")
static func validate(value: Variant) -> String:
	if not value is Dictionary: return "占地设置必须是对象。"
	for key in value:
		if key not in ["grounding","depth_offset","footprint_scale","allow_overlap"]: return "未知占地设置："+str(key)
	for key in ["grounding","allow_overlap"]:
		if value.has(key) and not value[key] is bool: return "接地 / 占地例外必须为开关。"
	var depth: Variant=value.get("depth_offset",0.0)
	if not (depth is int or depth is float) or not is_finite(float(depth)) or absf(depth)>256: return "遮挡前后微调应为 -256–256。"
	var size: Variant=value.get("footprint_scale",[1.0,1.0])
	if not size is Array or size.size()!=2: return "占地宽深需要两个比例。"
	for component in size:
		if not (component is int or component is float) or not is_finite(float(component)) or component<0.25 or component>2: return "占地宽深比例应为 0.25–2。"
	return ""
static func footprint(asset: String, rect: Rect2, placement: Dictionary = {}, flipped: bool = false) -> PackedVector2Array:
	var group: String=Catalog.descriptor(asset).get("group","")
	var points: Array=[]
	match group:
		"city": points=[[.09,.76],[.28,.56],[.73,.57],[.94,.78],[.77,.96],[.3,.96]]
		"mountain": points=[[.07,.89],[.23,.74],[.70,.76],[.94,.91],[.67,.98],[.26,.97]]
		"forest": points=[[.40,.91],[.50,.84],[.61,.91],[.52,.99]]
		_: return PackedVector2Array()
	var scale: Array=placement.get("footprint_scale",[1.0,1.0])
	var center:=Vector2(.5,.88)
	var output:=PackedVector2Array()
	for point in points:
		var local:=Vector2(point[0],point[1])
		if flipped: local.x=1.0-local.x
		output.append(rect.position+(center+(local-center)*Vector2(scale[0],scale[1]))*rect.size)
	return output
static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var rect:=Rect2(points[0],Vector2.ZERO)
	for point in points: rect=rect.expand(point)
	return rect
static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return a.size()>2 and b.size()>2 and bounds(a).intersects(bounds(b)) and not Geometry2D.intersect_polygons(a,b).is_empty()
static func depth(_asset: String, rect: Rect2, placement: Dictionary = {}) -> float:
	return rect.position.y+rect.size.y*.96+float(placement.get("depth_offset",0))
static func before(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(a.depth,b.depth): return a.depth<b.depth
	return str(a.id)<str(b.id)
static func conflict_pairs(entries: Array) -> Array:
	var result: Array=[]
	var index=preload("spatial_index.gd").new()
	index.build(entries.map(func(e): return bounds(e.footprint)))
	for city in entries:
		if city.group!="city" or city.placement.get("allow_overlap",false): continue
		for i in index.query(bounds(city.footprint)):
			var other: Dictionary=entries[i]
			if other.id==city.id or other.group not in ["mountain","forest","city"] or other.placement.get("allow_overlap",false): continue
			if other.group=="city" and str(other.id)<str(city.id): continue
			if overlaps(city.footprint,other.footprint):
				result.append({"code":"ART_FOOTPRINT","feature_id":city.get("feature_id",""),"instance_id":other.get("instance_id",""),"message":"“%s”占地与 %s 重叠；调整部件，或明确设置占地例外。" % [city.get("name",city.id),other.get("name",other.id)],"rect":bounds(city.footprint).merge(bounds(other.footprint)),"city_id":city.id,"other_id":other.id})
	return result
