@tool
extends RefCounted
## Authoring document only. No GameState, campaign clock, ownership or save authority.

signal changed
const ArtCatalog = preload("art_catalog.gd")
const ArtRibbon = preload("art_ribbon.gd")
const WaterBrush = preload("water_brush.gd")
const Production = preload("production_contract.gd")
const Geometry = preload("geometry_ops.gd")
const Registration = preload("reference_registration.gd")
const Spatial = preload("art_spatial.gd")
const ArtLibrary = preload("art_library.gd")
const SharedBoundaries = preload("shared_boundaries.gd")

const KINDS := ["mountain", "hills", "forest", "basin", "water", "river", "city", "pass", "ford", "label", "valley", "trail", "crossing", "coastline", "country_border", "province_border", "prefecture"]
const POLYGONS := ["mountain", "hills", "forest", "basin", "water", "prefecture"]
const LINES := ["river", "valley", "trail", "crossing", "coastline", "country_border", "province_border"]
const BOUNDARIES := ["coastline", "country_border", "province_border", "prefecture"]
const PASSAGES := ["valley", "trail", "crossing"]
const RULES := ["none", "normal", "rough", "blocked", "water"]
const LAYERS := ["terrain", "water", "passages", "boundaries", "prefectures", "sites", "notes"]
const NAMES := {"mountain":"高山", "hills":"丘陵", "forest":"林地", "basin":"盆地", "water":"水域", "river":"河流", "city":"城池", "pass":"关隘", "ford":"渡口", "label":"文字", "valley":"谷道","prefecture":"州界区域", "trail":"险径", "crossing":"渡河通道", "coastline":"海岸线", "country_border":"国界", "province_border":"道界"}
var data: Dictionary = blank()
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var saved_signature := ""
var current_path := ""
var revision := 0
var _serial := 0
var _saved_revision := -1
var _known_saved_signature := ""
var _validated_features: Dictionary = {}
var _validated_art: Dictionary = {}
var _validation_extent: Array = []
var _catalog_generation := -1
var last_change_art_only := false

func _art_snapshot() -> Dictionary:
	var next := data.duplicate()
	next.presentation = data.presentation.duplicate(true)
	return next

func _history_entry(art_only: bool = false) -> Dictionary:
	return {"art_only":art_only,"revision":revision,"state":data.presentation.duplicate(true) if art_only else snapshot()}

func _commit_art(next: Dictionary) -> bool:
	# Only private art operations use this path; geography is shared, never edited.
	var required := ArtCatalog.required_bundle_id(next.presentation.instances,next.features)
	if required.is_empty(): return false
	if not ArtCatalog.bundle_contains(str(next.presentation.bundle.get("id","")),required):
		next.presentation.bundle=ArtCatalog.bundle_info(required)
	if not validate(next).is_empty() or next.presentation==data.presentation: return false
	undo_stack.append(_history_entry(true))
	if undo_stack.size()>100: undo_stack.pop_front()
	redo_stack.clear()
	data=next
	_serial+=1; revision=_serial; last_change_art_only=true
	changed.emit()
	return true

static func blank() -> Dictionary:
	var layers: Array = []
	for id in LAYERS:
		layers.append({"id":id, "visible":true, "locked":false})
	return {"schema_version":4, "document_type":"strategic_map_authoring", "title":"未命名舆图", "canvas_size":[1600,960], "reference":{"path":"", "position":[0,0], "size":[1600,960], "rotation":0.0, "opacity":0.35, "visible":true, "locked":true, "above_art":true}, "reference_tiles":[], "layers":layers, "features":[], "production":Production.defaults(), "presentation":{"bundle":{}, "instances":[]}}

static func layer_for(kind: String) -> String:
	if kind=="prefecture":return "prefectures"
	if kind in BOUNDARIES: return "boundaries"
	if kind in ["water", "river"]: return "water"
	if kind in PASSAGES: return "passages"
	if kind == "label": return "notes"
	if kind in ["city", "pass", "ford"]: return "sites"
	return "terrain"

static func default_rule(kind: String) -> String:
	if kind == "mountain": return "blocked"
	if kind in ["hills", "forest"]: return "rough"
	if kind in ["water", "river"]: return "water"
	return "none"

static func feature(kind: String, points: Array, title: String, id: String) -> Dictionary:
	return {"id":id, "kind":kind, "name":title, "points":points.duplicate(true), "layer":layer_for(kind), "rule":default_rule(kind), "width":3.0 if kind in BOUNDARIES else (64.0 if kind in PASSAGES else 32.0), "scale":1.0, "gate_id":"", "gate_open":true, "hidden_route":kind == "trail", "domain_id":"", "note":"", "holes":[], "protected":false, "group_id":"", "source":{"citation":"","era":"","status":"unverified"}}

func snapshot() -> Dictionary:
	return data.duplicate(true)

func set_prefecture_faction(ids: Array, faction_name: String, color: String) -> bool:
	if ids.is_empty() or not Color.html_is_valid(color): return false
	var next:=snapshot()
	var groups: Array=[]
	var targets: Array=ids.duplicate()
	for id in ids:
		var old:=find_feature(str(id))
		if old.is_empty() or old.kind!="prefecture" or old.protected or layer(old.layer).locked: return false
		if not old.group_id.is_empty() and old.group_id not in groups:groups.append(old.group_id)
	for f in next.features:
		if f.kind=="prefecture" and f.group_id in groups and f.id not in targets:targets.append(f.id)
	for id in targets:
		var f:=find_feature(str(id))
		if f.protected or layer(f.layer).locked:return false
	for f in next.features:
		if f.id not in targets: continue
		var visual: Dictionary=f.get("visual",{}).duplicate(true)
		if faction_name.strip_edges().is_empty(): visual.erase("faction")
		else: visual.faction={"name":faction_name.strip_edges(),"color":"#"+Color.html(color).to_html(false)}
		f.visual=visual
	return _commit(next)

func water_brush(tool: String, stroke: Array, width: float, radius: float, target: String = "", snap_distance: float = 16.0, whole: bool = false, end_styles: Array=["auto","auto"]) -> Dictionary:
	return WaterBrush.apply(self,tool,stroke,width,radius,target,snap_distance,whole,end_styles)

func fingerprint() -> String:
	return canonical_digest(data)

static func canonical_digest(value: Variant) -> String:
	# JSON parses every number as float. Normalize before hashing so saved batches
	# and their in-memory integer inputs have the same identity.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value))).sha256_text()

func protect_features(ids: Array, value: bool) -> bool:
	var next := snapshot()
	for id in ids:
		var old := find_feature(str(id))
		if old.is_empty() or layer(old.layer).locked: return false
		for f in next.features:
			if f.id == id: f.protected=value
	return _commit(next,true)

func translate_features(ids: Array, offset: Vector2) -> bool:
	var next := snapshot()
	for id in ids:
		var old := find_feature(str(id))
		if old.is_empty() or layer(old.layer).locked: return false
		for f in next.features:
			if f.id != id: continue
			for ring in [f.points]+f.holes:
				for p in ring: p[0]+=offset.x; p[1]+=offset.y
	return _commit(next)

func boolean_features(first: String, second: String, operation: String) -> Dictionary:
	var a := find_feature(first)
	var b := find_feature(second)
	if first == second or a.is_empty() or b.is_empty() or not a.kind in POLYGONS or not b.kind in POLYGONS: return {"ok":false,"error":"请依次选择两个区域，第一项为被修改区域。"}
	if layer(a.layer).locked or layer(b.layer).locked or a.protected or b.protected: return {"ok":false,"error":"区域或图层已锁定。"}
	if operation == "union" and (a.kind != b.kind or a.rule != b.rule): return {"ok":false,"error":"合并要求地形种类和通行性质相同。"}
	var output := Geometry.boolean_shapes(a,b,operation)
	if not output.ok: return output
	var next := snapshot()
	next.features = next.features.filter(func(f): return f.id != second)
	var changed_ids: Array = []
	for i in range(output.shapes.size()):
		var shape: Dictionary = output.shapes[i]
		var copy: Dictionary = a.duplicate(true)
		copy.points = shape.points
		copy.holes = shape.holes
		if i == 0:
			for j in range(next.features.size()):
				if next.features[j].id == first: next.features[j]=copy; break
		else:
			copy.id = first+"_part_"+str(Time.get_ticks_usec())+"_"+str(i)
			copy.domain_id = ""
			next.features.append(copy)
		changed_ids.append(copy.id)
	var error := validate(next)
	if not error.is_empty(): return {"ok":false,"error":error}
	return {"ok":_commit(next),"ids":changed_ids,"error":""}

func set_art_style(style: String) -> bool:
	if style not in ArtCatalog.STYLES: return false
	var next := snapshot()
	next["art_style"] = style
	if style == "tongguan_v1":
		if not next.has("presentation"): next.presentation = {"bundle":{}, "instances":[]}
		var bundle_id := ArtCatalog.required_bundle_id(next.presentation.instances, next.features)
		if ArtCatalog.bundle_info(bundle_id).is_empty(): return false
		next.presentation.bundle = ArtCatalog.bundle_info(bundle_id)
	return _commit(next)

func set_depth_sort(enabled: bool) -> bool:
	var next:=snapshot()
	next.presentation["depth_sort"]=enabled
	return _commit(next)

func update_appearance(id: String, values: Dictionary) -> bool:
	var old := find_feature(id)
	if old.is_empty() or layer(old.layer).locked or values.is_empty(): return false
	for key in values:
		if key not in ["variant", "density", "seed", "offset", "label_offset", "label_size", "label_lod", "width_factor", "visible", "show_label", "scatter", "surface_marks", "water_style", "water_brush", "surface_flow", "ribbon_clip_rect", "shore_masks", "scatter_masks", "scatter_overrides", "auxiliary", "ribbon", "path", "path_style", "ridge_guide", "placement"]: return false
	if values.has("placement") and not Spatial.validate(values.placement).is_empty(): return false
	var next := snapshot()
	for item in next.features:
		if item.id == id:
			var visual: Dictionary = item.get("visual", {}).duplicate(true)
			for key in values: visual[key] = values[key]
			item.visual = visual
			break
	return _commit(next, false, true)

func update_appearances(ids: Array, values: Dictionary) -> bool:
	if ids.is_empty() or ids.size() > 500 or values.is_empty(): return false
	for key in values:
		if key not in ["variant", "density", "seed", "offset", "label_offset", "label_size", "label_lod", "width_factor", "visible", "show_label", "scatter", "surface_marks", "water_style", "surface_flow", "ribbon_clip_rect", "shore_masks", "auxiliary"]: return false
	var selected: Dictionary = {}
	for id in ids:
		var old := find_feature(str(id))
		if old.is_empty() or layer(old.layer).locked or selected.has(str(id)): return false
		selected[str(id)] = true
	var next := snapshot()
	for item in next.features:
		if not selected.has(item.id): continue
		var visual: Dictionary = item.get("visual", {}).duplicate(true)
		for key in values: visual[key] = values[key]
		item.visual = visual
	return _commit(next, false, true)

func find_art_instance(id: String) -> Dictionary:
	for item in data.get("presentation", {}).get("instances", []):
		if item.id == id: return item
	return {}

func create_site_anchor(title: String, kind: String, position: Vector2, domain: String = "", instance_id: String = "") -> String:
	if kind not in ["city","pass","ford"] or title.strip_edges().is_empty() or not position.is_finite() or layer("sites").locked: return ""
	var instance := find_art_instance(instance_id)
	if not instance_id.is_empty() and (instance.is_empty() or instance.locked or not instance.get("anchor_id","").is_empty()): return ""
	var id := "site_%s_%s" % [Time.get_ticks_usec(),randi()]
	var anchor := feature(kind,[[position.x,position.y]],title.strip_edges(),id)
	anchor.domain_id=domain.strip_edges()
	anchor.visual={"anchor_only":true}
	anchor.note="地点定位与外观独立；替换或删除外观不删除地点。"
	var next:=snapshot()
	next.features.append(anchor)
	for item in next.presentation.instances:
		if item.id==instance_id: item.anchor_id=id
	return id if _commit(next) else ""

static func site_art_compatible(asset: String) -> bool:
	var descriptor:=ArtCatalog.descriptor(asset)
	# Imported images can carry an imprecise palette category. Explicit binding
	# declares their role; geographic identity never comes from that category.
	return not descriptor.is_empty() and (descriptor.get("group","") in ["city","pass"] or descriptor.get("manual_only",false))

func attach_site_art(anchor_id: String, asset: String, scale_value: float = .45) -> String:
	var anchor:=find_feature(anchor_id)
	if anchor.is_empty() or not anchor.get("visual",{}).get("anchor_only",false) or layer(anchor.layer).locked: return ""
	if not site_art_compatible(asset): return ""
	var next:=_art_snapshot()
	if next.presentation.bundle.is_empty():next.presentation.bundle=ArtCatalog.bundle_info()
	var id:="art_%s_%s"%[Time.get_ticks_usec(),randi()]
	next.presentation.instances.append({"id":id,"asset":asset,"position":anchor.points[0].duplicate(),"scale":scale_value,"plane":"terrain","locked":false,"group_id":"地点:"+anchor.name,"anchor_id":anchor_id})
	return id if _commit_art(next) else ""

func add_art_instance(asset: String, position: Vector2, scale: float = 1.0, plane: String = "terrain") -> String:
	if ArtCatalog.descriptor(asset).is_empty() or not position.is_finite(): return ""
	var next := _art_snapshot()
	if not next.has("presentation"): next.presentation = {"bundle":{}, "instances":[]}
	if next.presentation.bundle.is_empty(): next.presentation.bundle = ArtCatalog.bundle_info()
	var id := "art_%s_%s" % [Time.get_ticks_usec(), randi()]
	next.presentation.instances.append({"id":id, "asset":asset, "position":[position.x,position.y], "scale":scale, "plane":plane, "locked":false, "group_id":""})
	return id if _commit_art(next) else ""

func update_art_instance(id: String, values: Dictionary) -> bool:
	var old := find_art_instance(id)
	if old.is_empty() or values.is_empty(): return false
	if old.locked and values != {"locked":false}: return false
	for key in values:
		if key not in ["asset", "position", "scale", "opacity", "flip_h", "plane", "locked", "group_id", "placement", "anchor_id"]: return false
	var next := _art_snapshot()
	for item in next.presentation.instances:
		if item.id == id:
			for key in values: item[key] = values[key]
			break
	return _commit_art(next)

func remove_art_instance(id: String) -> bool:
	var old := find_art_instance(id)
	if old.is_empty() or old.locked: return false
	var next := _art_snapshot()
	next.presentation.instances = next.presentation.instances.filter(func(item): return item.id != id)
	return _commit_art(next)

func art_group_ids(id: String, whole_group: bool = false) -> Array:
	var selected:=find_art_instance(id)
	if selected.is_empty(): return []
	if not whole_group or selected.group_id.is_empty(): return [id]
	return data.presentation.instances.filter(func(item): return item.group_id==selected.group_id).map(func(item): return item.id)

func edit_art_group(id: String, whole_group: bool, action: String, delta: Vector2 = Vector2.ZERO) -> Dictionary:
	var ids:=art_group_ids(id,whole_group)
	if ids.is_empty(): return {"ok":false,"error":"请先选择美术部件。"}
	if action not in ["move","duplicate","delete","lock","unlock"] or not delta.is_finite(): return {"ok":false,"error":"美术部件操作或位移无效。"}
	if action not in ["lock","unlock"]:
		for key in ids:
			if find_art_instance(key).locked: return {"ok":false,"error":"所选范围含锁定部件，请先解锁；整组没有修改。"}
	var next:=_art_snapshot()
	var result_ids: Array=ids.duplicate()
	if action=="delete": next.presentation.instances=next.presentation.instances.filter(func(item):return item.id not in ids)
	elif action=="duplicate":
		result_ids.clear()
		var new_group:="copy_%s_%s" % [Time.get_ticks_usec(),randi()]
		for key in ids:
			var item: Dictionary=find_art_instance(key).duplicate(true)
			item.id=new_group+"_"+str(result_ids.size())
			if item.has("anchor_id"):
				item.erase("anchor_id")
				item.erase("site_id")
			item.position=[item.position[0]+delta.x,item.position[1]+delta.y]
			item.group_id=new_group if ids.size()>1 else ""
			next.presentation.instances.append(item); result_ids.append(item.id)
	else:
		for item in next.presentation.instances:
			if item.id not in ids: continue
			if action=="move": item.position=[item.position[0]+delta.x,item.position[1]+delta.y]
			else: item.locked=action=="lock"
	if not _commit_art(next): return {"ok":false,"error":"部件未变化或操作后坐标无效；原地图保留。"}
	return {"ok":true,"ids":result_ids,"count":ids.size()}

func layout_ridge_guide(feature_id: String, asset: String, spacing: float) -> Dictionary:
	var f := find_feature(feature_id)
	var descriptor: Dictionary = ArtCatalog.descriptor(asset)
	if f.is_empty() or f.kind not in ["mountain","hills"] or not f.get("visual",{}).has("ridge_guide") or descriptor.get("group","") != "mountain" or spacing < 24 or spacing > 220:
		return {"ok":false,"error":"请选择有引导线的山地、山体素材和 24–220 的间距。"}
	var guide: Array = f.visual.ridge_guide
	var reserved: Array=[]
	var library:=ArtLibrary.new()
	if data.presentation.get("depth_sort",false):
		library.set_bundle(data.presentation.bundle.get("id","tongguan_v1"))
		var load_error:=library.ensure_loaded()
		if not load_error.is_empty(): return {"ok":false,"error":load_error}
		for site in data.features:
			if site.kind!="city" or site.get("visual",{}).get("auxiliary",false): continue
			var placement: Dictionary=site.get("visual",{}).get("placement",{})
			if placement.get("allow_overlap",false): continue
			var key:=ArtCatalog.site_variant(site)
			reserved.append(Spatial.footprint(key,library.body_rect(key,library.site_rect(site,Vector2(site.points[0][0],site.points[0][1]))),placement))
	var group := "ridge_guide:" + feature_id
	var removals: Array = []
	var frozen: Array[Vector2] = []
	for item in data.presentation.instances:
		if item.group_id != group: continue
		if item.locked: frozen.append(Vector2(item.position[0],item.position[1]))
		else: removals.append(item.id)
	var stamps: Array = []
	var distance := 0.0
	var next_at := 0.0
	for i in range(guide.size()-1):
		var a := Vector2(guide[i][0],guide[i][1])
		var b := Vector2(guide[i+1][0],guide[i+1][1])
		var length := a.distance_to(b)
		if length < 0.01: continue
		while next_at <= distance + length and stamps.size() < 100:
			var at := a.lerp(b,(next_at-distance)/length)
			var occupied := false
			for locked_position in frozen:
				if locked_position.distance_to(at) < spacing*0.55: occupied = true; break
			if not occupied and Geometry.contains(f,at):
				for obstacle in data.features:
					if obstacle.kind == "water" and Geometry.contains(obstacle,at): occupied = true; break
					if obstacle.kind in ["valley","trail","crossing"]:
						for j in range(obstacle.points.size()-1):
							var p0 := Vector2(obstacle.points[j][0],obstacle.points[j][1])
							var p1 := Vector2(obstacle.points[j+1][0],obstacle.points[j+1][1])
							if Geometry2D.get_closest_point_to_segment(at,p0,p1).distance_to(at) < obstacle.width*0.5+8: occupied = true; break
					if occupied: break
			if not occupied and not reserved.is_empty():
				var footprint:=Spatial.footprint(asset,library.body_rect(asset,library.instance_rect(asset,at,.8)))
				for city in reserved:
					if Spatial.overlaps(footprint,city): occupied=true; break
			if not occupied and Geometry.contains(f,at): stamps.append({"asset":asset,"position":[at.x,at.y],"scale":0.8})
			next_at += spacing
		distance += length
	if stamps.is_empty() and removals.is_empty(): return {"ok":false,"error":"引导线未产生可放置位置；检查源地形和通道避让。"}
	var result := apply_art_stroke(stamps,removals,group)
	if not result.ok: return result
	return {"ok":true,"count":stamps.size(),"preserved":frozen.size(),"group_id":group}

func apply_art_stroke(stamps: Array, removals: Array = [], group_id: String = "") -> Dictionary:
	if stamps.is_empty() and removals.is_empty(): return {"ok":false,"error":"笔刷没有可提交的修改。"}
	if stamps.size() + removals.size() > 500 or group_id.length() > 100: return {"ok":false,"error":"一次笔刷修改超过 500 件。"}
	var next := _art_snapshot()
	if not next.has("presentation"): next.presentation = {"bundle":{}, "instances":[]}
	if next.presentation.bundle.is_empty(): next.presentation.bundle = ArtCatalog.bundle_info()
	var remove_ids: Dictionary = {}
	for id in removals:
		var old := find_art_instance(str(id))
		if old.is_empty() or old.locked: return {"ok":false,"error":"笔刷擦除包含锁定或不存在的部件。"}
		remove_ids[str(id)] = true
	if not remove_ids.is_empty(): next.presentation.instances = next.presentation.instances.filter(func(item): return not remove_ids.has(item.id))
	var ids: Array[String] = []
	for i in range(stamps.size()):
		var stamp: Variant = stamps[i]
		if not stamp is Dictionary or ArtCatalog.descriptor(str(stamp.get("asset", ""))).is_empty() or not _point(stamp.get("position")) or not _number(stamp.get("scale")): return {"ok":false,"error":"笔刷包含无效素材、位置或比例。"}
		var id := "art_%s_%s" % [Time.get_ticks_usec(), i]
		ids.append(id)
		next.presentation.instances.append({"id":id, "asset":stamp.asset, "position":stamp.position.duplicate(), "scale":stamp.scale, "plane":"terrain", "locked":false, "group_id":group_id})
	if not _commit_art(next): return {"ok":false,"error":"笔刷修改未通过文档检查。"}
	return {"ok":true,"ids":ids}

func freeze_art_region(feature_id: String, region: Rect2, stamps: Array) -> Dictionary:
	var old := find_feature(feature_id)
	if old.is_empty() or old.kind not in ["mountain", "hills", "forest"] or not region.has_area() or stamps.size() > 500: return {"ok":false,"error":"请选择可散布的地形与有效区域；每次最多固定 500 件。"}
	if layer(old.layer).locked: return {"ok":false,"error":"地形图层已锁定。"}
	var next := snapshot()
	var group := "frozen_%s_%s" % [feature_id, Time.get_ticks_usec()]
	for f in next.features:
		if f.id != feature_id: continue
		var visual: Dictionary = f.get("visual", {}).duplicate(true)
		var masks: Array = visual.get("scatter_masks", []).duplicate(true)
		masks.append({"rect":[region.position.x,region.position.y,region.size.x,region.size.y],"group_id":group})
		visual.scatter_masks = masks
		f.visual = visual
		break
	if not next.has("presentation"): next.presentation = {"bundle":{}, "instances":[]}
	if next.presentation.bundle.is_empty(): next.presentation.bundle = ArtCatalog.bundle_info()
	for i in range(stamps.size()):
		var stamp: Variant = stamps[i]
		if not stamp is Dictionary or ArtCatalog.descriptor(str(stamp.get("asset", ""))).is_empty() or not _point(stamp.get("position")) or not _number(stamp.get("scale")): return {"ok":false,"error":"自动素材快照无效。"}
		next.presentation.instances.append({"id":"%s_%s" % [group,i], "asset":stamp.asset, "position":stamp.position.duplicate(), "scale":stamp.scale, "plane":"terrain", "locked":false, "group_id":group})
	if not _commit(next, false, old.protected): return {"ok":false,"error":"固定区域未通过文档检查。"}
	return {"ok":true,"count":stamps.size(),"group_id":group}

func regenerate_art_region(feature_id: String, region: Rect2, seed_value: int) -> Dictionary:
	var old := find_feature(feature_id)
	if old.is_empty() or old.kind not in ["mountain", "hills", "forest"] or not region.has_area() or seed_value < 0 or seed_value > 999999: return {"ok":false,"error":"请选择可散布地形、有效视野与 0–999999 的变化编号。"}
	if layer(old.layer).locked: return {"ok":false,"error":"地形图层已锁定。"}
	var next := snapshot()
	var removed_groups: Dictionary = {}
	for f in next.features:
		if f.id != feature_id: continue
		var visual: Dictionary = f.get("visual", {}).duplicate(true)
		var remaining: Array = []
		for mask in visual.get("scatter_masks", []):
			var rect: Array = mask.get("rect",[]) if mask is Dictionary else mask
			if Rect2(rect[0],rect[1],rect[2],rect[3]).intersects(region):
				if not mask is Dictionary: return {"ok":false,"error":"旧版锁定区缺少实例组，请逐件核对后再重排。"}
				removed_groups[mask.group_id] = true
			else: remaining.append(mask)
		visual.scatter_masks = remaining
		var overrides: Array = visual.get("scatter_overrides", []).duplicate(true)
		overrides.append({"rect":[region.position.x,region.position.y,region.size.x,region.size.y],"seed":seed_value})
		visual.scatter_overrides = overrides
		f.visual = visual
		break
	if not next.has("presentation"): next.presentation = {"bundle":{},"instances":[]}
	if not removed_groups.is_empty(): next.presentation.instances = next.presentation.instances.filter(func(item): return not removed_groups.has(item.group_id))
	if not _commit(next,false,old.protected): return {"ok":false,"error":"局部重新生成未通过文档检查。"}
	return {"ok":true,"removed_groups":removed_groups.size(),"seed":seed_value}

func set_production(key: String, value: Variant) -> bool:
	if key not in ["regions","checks","coordinate_frame","source_note"]: return false
	var next := snapshot()
	next.production[key] = value
	return _commit(next)

func set_issue_review(id: String, review: Dictionary) -> bool:
	var next:=snapshot()
	if not next.production.has("audit_reviews"): next.production.audit_reviews={}
	next.production.audit_reviews[id]=review.duplicate(true)
	return _commit(next)

func calibrate_reference(id: String, controls: Dictionary) -> Dictionary:
	var ref := get_reference(id)
	if ref.is_empty() or ref.locked: return {"ok":false,"error":"请先解锁所选参考图。"}
	if not controls.get("source_points") is Array or not controls.get("world_points") is Array or not _point(controls.get("image_size")): return {"ok":false,"error":"缺少控制点或图片尺寸。"}
	var result := Registration.fit(controls.source_points,controls.world_points,Vector2i(controls.image_size[0],controls.image_size[1]))
	if not result.ok: return result
	if not _number(controls.get("tolerance",8)) or controls.get("tolerance",8) < 0: return {"ok":false,"error":"误差容限无效。"}
	if result.max_error > controls.get("tolerance",8): return {"ok":false,"error":"最大配准误差 %.2f 超过容限；请检查控制点。" % result.max_error,"rms":result.rms}
	var next := snapshot()
	var target: Dictionary = next.reference
	if id != "primary":
		for item in next.reference_tiles:
			if item.id == id: target=item; break
	for key in ["position","size","rotation"]: target[key]=result[key]
	result["citation"] = str(controls.get("citation",""))
	result["era"] = str(controls.get("era",""))
	next.production.calibrations[id] = result.duplicate(true)
	var error := validate(next)
	if not error.is_empty(): return {"ok":false,"error":error}
	result.ok = _commit(next)
	return result

func apply_batch(request: Dictionary) -> Dictionary:
	if not request.get("batch_id") is String or request.batch_id.is_empty() or not request.get("expected_fingerprint") is String or not request.get("operations") is Array or request.operations.is_empty() or request.operations.size() > 5000: return {"ok":false,"error":"批次需要 ID、基线指纹和 1–5000 条操作。"}
	var digest := canonical_digest(request.operations)
	if data.production.receipts.has(request.batch_id):
		if data.production.receipts[request.batch_id] != digest: return {"ok":false,"error":"批次 ID 已被其他内容使用。"}
		return {"ok":true,"replayed":true,"fingerprint":fingerprint()}
	if request.expected_fingerprint != fingerprint(): return {"ok":false,"error":"地图已被修改，请重新读取基线后再应用。"}
	var working = get_script().new()
	working.replace_document(snapshot())
	for index in range(request.operations.size()):
		var op: Variant = request.operations[index]
		if not op is Dictionary: return {"ok":false,"error":"操作必须是字典。","operation":index}
		var ok := false
		match op.get("op",""):
			"create":
				if op.get("feature") is Dictionary:
					var f: Dictionary = op.feature.duplicate(true)
					Production.enrich_feature(f)
					if f.get("kind") in KINDS and working.find_feature(str(f.get("id",""))).is_empty() and not working.layer(layer_for(f.kind)).locked:
						var next: Dictionary = working.snapshot()
						next.features.append(f)
						ok = working._commit(next)
			"update":
				if op.get("values") is Dictionary: ok=working.update_feature(str(op.get("id","")),op.values)
			"appearance":
				if op.get("values") is Dictionary: ok=working.update_appearance(str(op.get("id","")),op.values)
			"delete": ok=working.remove_feature(str(op.get("id","")))
			"translate":
				if op.get("ids") is Array and _point(op.get("offset")): ok=working.translate_features(op.ids,Vector2(op.offset[0],op.offset[1]))
			"protect":
				if op.get("ids") is Array and op.get("value") is bool: ok=working.protect_features(op.ids,op.value)
			"production": ok=working.set_production(str(op.get("key","")),op.get("value"))
			"review":
				if op.get("review") is Dictionary: ok=working.set_issue_review(str(op.get("id","")),op.review)
			"boolean": ok=working.boolean_features(str(op.get("first","")),str(op.get("second","")),str(op.get("operation",""))).ok
			"calibrate":
				if op.get("controls") is Dictionary: ok=working.calibrate_reference(str(op.get("id","primary")),op.controls).ok
		if not ok: return {"ok":false,"error":"操作无效、没有变化或目标受保护；整批未应用。","operation":index}
		working.undo_stack.clear()
	var next: Dictionary = working.snapshot()
	if next.production.receipts.size() >= 1000: return {"ok":false,"error":"批次日志已达 1000 条，请建立新的制作版本。"}
	next.production.receipts[request.batch_id] = digest
	# Protected content cannot be changed by an implicit unlock in a batch.
	for old in data.features:
		if old.protected and working.find_feature(old.id) != old: return {"ok":false,"error":"批量操作不能解锁或覆盖受保护内容；请在界面单独解锁。"}
	return {"ok":_commit(next),"replayed":false,"fingerprint":fingerprint()}

func layer(id: String) -> Dictionary:
	for item in data.layers:
		if item.id == id: return item
	return {}

func find_feature(id: String) -> Dictionary:
	for item in data.features:
		if item.id == id: return item
	return {}

func validate(value: Variant) -> String:
	if not value is Dictionary: return "地图必须是 JSON 对象。"
	if value.get("schema_version") != 4 or value.get("document_type") != "strategic_map_authoring": return "不是受支持的地图格式（需要版本 4；打开时可迁移版本 1 / 2 / 3）。"
	if value.get("art_style","schematic") not in ArtCatalog.STYLES: return "未知美术样式。"
	if not _point(value.get("canvas_size")): return "画布尺寸无效。"
	if _validation_extent != value.canvas_size or _catalog_generation != ArtCatalog.generation:
		_validated_features.clear()
		_validated_art.clear()
		_validation_extent=value.canvas_size.duplicate()
		_catalog_generation=ArtCatalog.generation
	if not value.get("features") is Array: return "地图对象列表无效。"
	if _validated_features.size()>10000: _validated_features.clear()
	if _validated_art.size()>5000: _validated_art.clear()
	var domains: Dictionary={}
	var anchors: Dictionary={}
	for feature in value.features:
		if feature is Dictionary and feature.get("domain_id") is String:
			domains[feature.domain_id]=domains.get(feature.domain_id,0)+1
		if feature is Dictionary and feature.get("visual",{}) is Dictionary and feature.get("visual",{}).get("anchor_only",false) is bool and feature.get("visual",{}).get("anchor_only",false):
			anchors[feature.get("id","")]=feature
	for anchor in anchors.values():
		if not str(anchor.get("domain_id","")).is_empty() and domains.get(anchor.domain_id,0)!=1:return "地点绑定的正式节点 ID 重复。"
	if value.has("presentation"):
		var presentation: Variant = value.presentation
		if not presentation is Dictionary or not presentation.get("bundle") is Dictionary or not presentation.get("instances") is Array: return "美术表现层格式错误。"
		if presentation.has("depth_sort") and not presentation.depth_sort is bool: return "落点遮挡开关无效。"
		if not presentation.bundle.is_empty():
			if not presentation.bundle.get("id") is String or not _number(presentation.bundle.get("version")) or presentation.bundle.version < 1 or presentation.bundle.version != floorf(presentation.bundle.version) or not presentation.bundle.get("catalog_sha256") is String: return "美术素材包版本格式错误。"
			if ArtCatalog.bundle_chain(str(presentation.bundle.id)).is_empty():
				var registry_error := ArtCatalog.error()
				return "缺少地图记录的美术素材包：" + str(presentation.bundle.id) + "。请恢复该素材包后再打开地图。" + (" " + registry_error if not registry_error.is_empty() else "")
		var required_bundle_id := ArtCatalog.required_bundle_id(presentation.instances, value.get("features", []))
		if required_bundle_id.is_empty(): return "美术对象引用了互不兼容的素材包。"
		if required_bundle_id != "tongguan_v1" and not ArtCatalog.bundle_contains(str(presentation.bundle.get("id", "")),required_bundle_id): return "扩展美术对象需要记录对应素材包。"
		if presentation.instances.size() > 5000: return "美术实例超过 5000 件。"
		var art_ids := {}
		for instance in presentation.instances:
			if not instance is Dictionary or not instance.get("id") is String or instance.id.is_empty() or art_ids.has(instance.id): return "美术实例 ID 缺失或重复。"
			if not instance.get("asset") is String or ArtCatalog.descriptor(instance.asset).is_empty(): return "美术实例引用了未知素材。"
			if instance.has("anchor_id"):
				if not instance.anchor_id is String:return "地点锚点引用必须为文字。"
				if not instance.anchor_id.is_empty():
					if not anchors.has(instance.anchor_id):return "美术部件引用了不存在的地点锚点；请先解除绑定。"
					if not site_art_compatible(instance.asset):return "地点外观需要城关素材或手动导入的图片。"
					if not str(instance.get("site_id","")).is_empty() and instance.site_id!=anchors[instance.anchor_id].get("domain_id",""):return "新旧地点绑定不一致。"
			if instance.has("site_id"):
				if not instance.site_id is String: return "美术部件地点绑定格式错误。"
				if not instance.site_id.is_empty() and domains.get(instance.site_id,0) != 1: return "美术部件绑定了未知或不唯一的地点。"
			if _validated_art.get(instance.id,{})==instance:
				art_ids[instance.id]=true
				continue
			if not _point(instance.get("position")) or instance.position[0] < 0 or instance.position[1] < 0 or instance.position[0] > value.canvas_size[0] or instance.position[1] > value.canvas_size[1]: return "美术实例坐标超出画布。"
			if not _number(instance.get("scale")) or instance.scale < 0.25 or instance.scale > 4: return "美术实例比例应为 0.25–4。"
			if not _number(instance.get("opacity",1.0)) or instance.get("opacity",1.0) < 0.05 or instance.get("opacity",1.0) > 1: return "美术实例透明度应为 0.05–1。"
			if not instance.get("flip_h",false) is bool: return "美术部件方向变体无效。"
			if instance.get("flip_h",false) and ArtCatalog.descriptor(instance.asset).get("group","") not in ["forest","mountain","ground"]: return "城池与关隘不能左右镜像。"
			if instance.get("plane") not in ["ground", "terrain", "foreground"] or not instance.get("locked") is bool or not instance.get("group_id") is String: return "美术实例层级或保护状态无效。"
			if not Spatial.validate(instance.get("placement",{})).is_empty(): return Spatial.validate(instance.get("placement",{}))
			_validated_art[instance.id]=instance.duplicate(true)
			art_ids[instance.id] = true
	var production_error := Production.validate(value.get("production"))
	if not production_error.is_empty(): return production_error
	if not value.get("title") is String: return "缺少地图名称。"
	var dimensions: Variant = value.get("canvas_size")
	if not _point(dimensions) or dimensions[0] < 320 or dimensions[1] < 320 or dimensions[0] > 65536 or dimensions[1] > 65536: return "画布尺寸应为 320–65536 图面单位。"
	if not value.get("layers") is Array or value.layers.size() not in [6,7]: return "图层定义不完整。"
	var layer_ids: Array = []
	for item in value.layers:
		if not item is Dictionary or not item.get("id") in LAYERS or item.id in layer_ids or not item.get("visible") is bool or not item.get("locked") is bool: return "图层格式错误。"
		layer_ids.append(item.id)
	for required in LAYERS:
		if required!="prefectures" and required not in layer_ids:return "图层定义不完整。"
	if not value.get("reference_tiles") is Array or value.reference_tiles.size() > 63: return "最多支持 64 张参考图。"
	var reference_ids := ["primary"]
	for ref in [value.get("reference")] + value.reference_tiles:
		if not ref is Dictionary or not ref.get("path") is String or not _point(ref.get("position")) or not _point(ref.get("size")): return "参考图设置无效。"
		if ref.size[0] < 1 or ref.size[1] < 1 or ref.size[0] > 65536 or ref.size[1] > 65536 or absf(ref.position[0]) > 65536 or absf(ref.position[1]) > 65536: return "参考图位置或尺寸超出范围。"
		if not _number(ref.get("opacity")) or ref.opacity < 0 or ref.opacity > 1: return "参考图透明度无效。"
		if not _number(ref.get("rotation")) or absf(ref.rotation) > 180: return "参考图旋转应为 -180 至 180 度。"
		for key in ["visible","locked","above_art"]:
			if not ref.get(key) is bool: return "参考图开关格式无效。"
	for ref in value.reference_tiles:
		if not ref.get("id") is String or ref.id.is_empty() or ref.id in reference_ids: return "参考图 ID 缺失或重复。"
		reference_ids.append(ref.id)
	if not value.get("features") is Array or value.features.size() > 10000: return "地图对象列表无效或超过 10000 个。"
	var ids: Dictionary = {}
	var total_points := 0
	for item in value.features:
		if not item is Dictionary: return "对象必须为字典。"
		if not item.get("id") is String or item.id.is_empty() or ids.has(item.id): return "对象 ID 缺失或重复。"
		if item.get("layer") not in layer_ids:return "对象所在图层缺失。"
		if _validated_features.get(item.id,{})==item:
			total_points+=item.points.size()
			for hole in item.holes: total_points+=hole.size()
			if total_points>100000: return "坐标总量超过当前编辑器限制。"
			ids[item.id]=item
			continue
		if not item.get("kind") in KINDS or not item.get("name") is String or item.get("layer") != layer_for(item.kind): return "对象类型、名称或图层不正确。"
		if item.layer not in layer_ids:return "对象所在图层缺失。"
		var visual_error := ArtCatalog.validate(item.kind,item.get("visual",{}))
		if not visual_error.is_empty(): return visual_error
		if not item.get("rule") in RULES: return "通行性质不正确。"
		if not Spatial.validate(item.get("visual",{}).get("placement",{})).is_empty(): return Spatial.validate(item.get("visual",{}).get("placement",{}))
		if item.kind in BOUNDARIES and item.rule != "none": return "海岸线和行政界线仅作标注；通行请使用水域和地形区域。"
		if not item.get("points") is Array: return "缺少坐标。"
		if not item.get("holes") is Array or not item.get("protected") is bool or not item.get("group_id") is String or not item.get("source") is Dictionary: return "对象制作信息不完整。"
		for key in ["citation","era","status"]:
			if not item.source.get(key) is String: return "史料来源必须为文字。"
		if not item.source.status in ["unverified","candidate","reviewed","schematic"]: return "未知资料审核状态。"
		if not item.holes.is_empty() and not item.kind in POLYGONS: return "只有区域支持孔洞。"
		var count: int = item.points.size()
		total_points += count
		if total_points > 100000: return "坐标总量超过当前编辑器限制。"
		if (item.kind in POLYGONS and count < 3) or (item.kind in LINES and count < 2) or (not item.kind in POLYGONS and not item.kind in LINES and count != 1): return "几何顶点数量不足。"
		for p in item.points:
			if not _point(p) or p[0] < 0 or p[1] < 0 or p[0] > dimensions[0] or p[1] > dimensions[1]: return "坐标无效或超出画布。"
		if item.kind in PASSAGES and item.get("visual",{}).has("path"):
			var source_line := packed(item.points)
			var path: Array = item.visual.path
			if Vector2(path[0][0],path[0][1]).distance_to(source_line[0]) > 2 or Vector2(path[-1][0],path[-1][1]).distance_to(source_line[-1]) > 2: return "通道表现线起终点必须留在源通道。"
			for p in path:
				var point := Vector2(p[0],p[1])
				var nearest := INF
				for i in range(source_line.size()-1): nearest = minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,source_line[i],source_line[i+1])))
				if nearest > item.width*.45: return "通道表现线越出源通道宽度。"
		if item.kind in ["mountain","hills"] and item.get("visual",{}).has("ridge_guide"):
			for p in item.visual.ridge_guide:
				if not Geometry.contains(item,Vector2(p[0],p[1])): return "山脊引导线须留在源山地内。"
		if item.kind in POLYGONS:
			var poly := packed(item.points)
			if Geometry.triangulate(poly).is_empty() or _self_intersects(poly): return "区域边界自交或面积为零。"
			var outer_query=preload("polygon_query.gd").new()
			if not item.holes.is_empty(): outer_query.prepare(poly)
			var outer_edges: RefCounted=Geometry.ring_edge_index(poly) if not item.holes.is_empty() else null
			var prior: Array = []
			for hole in item.holes:
				if not hole is Array or hole.size() < 3: return "孔洞至少需要 3 点。"
				total_points += hole.size()
				if total_points > 100000: return "坐标总量超过限制。"
				for p in hole:
					if not _point(p) or not outer_query.contains(Vector2(p[0],p[1])): return "孔洞必须在外边界内部。"
				var ring := packed(hole)
				if _self_intersects(ring) or Geometry.triangulate(ring).is_empty() or Geometry.rings_intersect_indexed(poly,ring,outer_edges): return "孔洞自交或触及外边界。"
				var box:=Rect2(ring[0],Vector2.ZERO)
				for p in ring: box=box.expand(p)
				for other in prior:
					if not box.grow(.0001).intersects(other.bounds,true): continue
					if Geometry.rings_intersect(other.ring,ring) or Geometry.point_in_ring(ring[0],other.ring) or Geometry.point_in_ring(other.ring[0],ring): return "孔洞不能重叠或嵌套。"
				prior.append({"ring":ring,"bounds":box})
			if item.kind == "water" and item.get("visual", {}).has("ribbon"):
				var ribbon: Dictionary = item.visual.ribbon
				if ribbon.has("render_style") and (not ribbon.render_style is String or ribbon.render_style not in ["soft","inked","inked_varied","inked_brush"]): return "水面表现样式无效。"
				var samples: Array = ArtRibbon.sample(ribbon.points, ribbon.widths)
				var containment:=Geometry.prepare_containment(item)
				for i in range(samples.size()):
					var center: Vector2 = samples[i].position
					var before: Vector2 = samples[maxi(0,i-1)].position
					var after: Vector2 = samples[mini(samples.size()-1,i+1)].position
					var tangent := (after-before).normalized()
					if tangent.is_zero_approx(): return "水面表现曲线出现重合点。"
					var across: Vector2 = tangent.orthogonal() * float(samples[i].width) * 0.48
					for point in [center, center+across, center-across]:
						if not Geometry.contains_prepared(containment, point): return "水面表现曲线越过源水域边界。"
		if not _number(item.get("width")) or item.width < (1 if item.kind in BOUNDARIES else 8) or item.width > 256: return "线宽超出范围（边界 1–256，其他 8–256）。"
		if not _number(item.get("scale")) or item.scale < 0.25 or item.scale > 4: return "符号比例必须为 0.25–4。"
		if not item.get("gate_id") is String or not item.get("gate_open") is bool or not item.get("hidden_route") is bool or not item.get("domain_id") is String or not item.get("note") is String: return "对象属性类型不完整。"
		_validated_features[item.id]=item.duplicate(true)
		ids[item.id] = item
	for item in value.features:
		if not item.gate_id.is_empty():
			if not item.kind in PASSAGES or not ids.has(item.gate_id) or not ids[item.gate_id].kind in ["pass", "ford"]: return "通道绑定的关隘 / 渡口不存在。"
	for scenario in value.production.checks:
		for id in scenario.gates:
			if not ids.has(id) or not ids[id].kind in ["pass","ford"]: return "检查场景引用了不存在的关隘 / 渡口。"
	return ""

static func _number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))

static func _point(v: Variant) -> bool:
	return v is Array and v.size() == 2 and _number(v[0]) and _number(v[1])

static func packed(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points: result.append(Vector2(p[0],p[1]))
	return result

static func _self_intersects(p: PackedVector2Array) -> bool:
	p=Geometry.local_points(p)
	if p.size()>=128:
		# Only prune disjoint edge bounds; the original exact intersection test
		# and adjacency exclusions remain the acceptance authority.
		var bounds: Array=[]
		for i in range(p.size()): bounds.append(Rect2(p[i],Vector2.ZERO).expand(p[(i+1)%p.size()]).grow(.0001))
		var index=preload("spatial_index.gd").new();index.build(bounds)
		for a in range(p.size()):
			for b in index.query(bounds[a]):
				if b<=a+1 or (a==0 and b==p.size()-1):continue
				if Geometry2D.segment_intersects_segment(p[a],p[(a+1)%p.size()],p[b],p[(b+1)%p.size()])!=null:return true
		return false
	for a in range(p.size()):
		for b in range(a + 1, p.size()):
			if b == a + 1 or (a == 0 and b == p.size()-1): continue
			if Geometry2D.segment_intersects_segment(p[a], p[(a+1)%p.size()], p[b], p[(b+1)%p.size()]) != null: return true
	return false

func _commit(next: Dictionary, protection_change: bool = false, appearance_change: bool = false) -> bool:
	var required_bundle := ArtCatalog.required_bundle_id(next.get("presentation", {}).get("instances", []), next.get("features", []))
	if required_bundle.is_empty(): return false
	if next.has("presentation") and required_bundle != "tongguan_v1" and not ArtCatalog.bundle_contains(str(next.presentation.get("bundle", {}).get("id", "")),required_bundle):
		var extended_bundle := ArtCatalog.bundle_info(required_bundle)
		if extended_bundle.is_empty(): return false
		next.presentation.bundle = extended_bundle
	if not validate(next).is_empty() or next == data: return false
	for old in data.features:
		if not old.protected: continue
		var retained := false
		for f in next.features:
			if f.id != old.id: continue
			var compared: Dictionary = f.duplicate(true)
			var baseline: Dictionary = old.duplicate(true)
			if protection_change: compared.protected = old.protected
			if appearance_change:
				compared.erase("visual")
				baseline.erase("visual")
			retained = compared == baseline
			break
		if not retained: return false
	undo_stack.append(_history_entry())
	if undo_stack.size() > 100: undo_stack.pop_front()
	redo_stack.clear()
	data = next.duplicate(true)
	_serial+=1; revision=_serial; last_change_art_only=false
	changed.emit()
	return true

func replace_document(next: Dictionary) -> String:
	var error := validate(next)
	if not error.is_empty(): return error
	data = next.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()
	current_path = ""
	saved_signature = ""
	_serial+=1; revision=_serial; _saved_revision=-1; last_change_art_only=false
	changed.emit()
	return ""

func add_feature(kind: String, points: Array, title: String, line_width: float = -1) -> String:
	var needs_state_layer: bool=kind=="prefecture" and not data.layers.any(func(item):return item.id=="prefectures")
	if not kind in KINDS or (not needs_state_layer and layer(layer_for(kind)).locked): return ""
	var id := "f_%s_%s" % [Time.get_ticks_usec(), randi()]
	var next := snapshot()
	if needs_state_layer:next.layers.insert(mini(4,next.layers.size()),{"id":"prefectures","visible":true,"locked":false})
	next.features.append(feature(kind, points, title if not title.is_empty() else NAMES[kind], id))
	if line_width > 0 and kind in LINES: next.features[-1].width = line_width
	return id if _commit(next) else ""

func update_feature(id: String, values: Dictionary) -> bool:
	var old := find_feature(id)
	if old.is_empty() or layer(old.layer).locked: return false
	if values.has("kind") and (not values.kind is String or not values.kind in KINDS): return false
	if values.has("points"):
		if not values.points is Array or values.points.is_empty(): return false
		for p in values.points:
			if not _point(p): return false
	var next := snapshot()
	for item in next.features:
		if item.id == id:
			if values.has("points") and not values.has("holes") and not item.holes.is_empty() and values.points is Array and values.points.size() == old.points.size():
				var offset := Vector2(values.points[0][0]-old.points[0][0],values.points[0][1]-old.points[0][1])
				var translation := true
				for i in range(old.points.size()):
					if not _point(values.points[i]) or not Vector2(values.points[i][0]-old.points[i][0],values.points[i][1]-old.points[i][1]).is_equal_approx(offset): translation=false; break
				if translation:
					for hole in item.holes:
						for p in hole: p[0]+=offset.x; p[1]+=offset.y
			for key in values:
				if (key in item or key == "visual") and key != "id": item[key] = values[key]
			item.layer = layer_for(item.kind)
			if layer(item.layer).locked: return false
	if values.has("points") or values.has("holes"):
		var edited: Dictionary={}
		for item in next.features:
			if item.id==id:edited=item;break
		var locked_layers: Array=[]
		for item in next.layers:
			if item.locked:locked_layers.append(item.id)
		if not SharedBoundaries.apply(next.features,old,edited,locked_layers):return false
	return _commit(next)

func remove_feature(id: String) -> bool:
	var old := find_feature(id)
	if old.is_empty() or layer(old.layer).locked: return false
	# A missing gate must never silently turn a controlled corridor into free passage.
	for item in data.features:
		if item.gate_id == id: return false
	var next := snapshot()
	next.features = next.features.filter(func(f): return f.id != id)
	return _commit(next)

func set_layer(id: String, field: String, value: bool) -> bool:
	if field not in ["visible", "locked"]: return false
	var next := snapshot()
	for l in next.layers:
		if l.id == id: l[field] = value
	return _commit(next)

func set_background(path: String) -> bool:
	return update_reference({"path":path})

func references() -> Array:
	return [data.reference] + data.reference_tiles

func get_reference(id: String = "primary") -> Dictionary:
	if id == "primary": return data.reference
	for ref in data.reference_tiles:
		if ref.id == id: return ref
	return {}

func add_reference(path: String, dimensions: Vector2i) -> String:
	if dimensions.x < 1 or dimensions.y < 1 or data.reference_tiles.size() >= 63: return ""
	var next := snapshot()
	var ref: Dictionary = blank().reference
	ref.id = "ref_%s_%s" % [Time.get_ticks_usec(),randi()]
	ref.path = path
	ref.size = [dimensions.x,dimensions.y]
	ref.opacity = 0.5
	next.reference_tiles.append(ref)
	return ref.id if _commit(next) else ""

func remove_reference(id: String = "primary") -> bool:
	if id == "primary": return update_reference({"path":""})
	var next := snapshot()
	next.reference_tiles = next.reference_tiles.filter(func(r): return r.id != id)
	return _commit(next)

func update_reference(values: Dictionary, id: String = "primary") -> bool:
	var old := get_reference(id)
	if old.is_empty(): return false
	var next := snapshot()
	if old.locked and values.get("locked", true):
		for key in ["position","size","rotation"]:
			if values.has(key) and values[key] != old[key]: return false
	var target: Dictionary = next.reference
	if id != "primary":
		for ref in next.reference_tiles:
			if ref.id == id: target = ref; break
	for key in values:
		if target.has(key) and key != "id": target[key] = values[key]
	return _commit(next)

func import_reference(path: String, dimensions: Vector2i) -> bool:
	if dimensions.x < 1 or dimensions.y < 1: return false
	var next := snapshot()
	var ratio := minf(float(data.canvas_size[0])/dimensions.x,float(data.canvas_size[1])/dimensions.y)
	next.reference = {"path":path,"position":[(data.canvas_size[0]-dimensions.x*ratio)*0.5,(data.canvas_size[1]-dimensions.y*ratio)*0.5],"size":[dimensions.x*ratio,dimensions.y*ratio],"rotation":0.0,"opacity":0.5,"visible":true,"locked":true,"above_art":true}
	return _commit(next)

func update_ring(id: String, hole_index: int, points: Array) -> bool:
	var f:=find_feature(id)
	if f.is_empty() or hole_index < -1 or hole_index >= f.holes.size(): return false
	if hole_index == -1: return update_feature(id,{"points":points})
	var holes: Array=f.holes.duplicate(true)
	holes[hole_index]=points.duplicate(true)
	return update_feature(id,{"holes":holes})

func add_hole(id: String, points: Array) -> bool:
	var f:=find_feature(id)
	if f.is_empty() or not f.kind in POLYGONS: return false
	var holes: Array=f.holes.duplicate(true); holes.append(points.duplicate(true))
	return update_feature(id,{"holes":holes})

func remove_hole(id: String, hole_index: int) -> bool:
	var f:=find_feature(id)
	if f.is_empty() or hole_index < 0 or hole_index >= f.holes.size(): return false
	var holes: Array=f.holes.duplicate(true); holes.remove_at(hole_index)
	return update_feature(id,{"holes":holes})

func insert_vertex(id: String, at: int, point: Vector2, hole_index: int = -1) -> bool:
	var f := find_feature(id)
	if f.is_empty() or not f.kind in POLYGONS+LINES or hole_index < -1 or hole_index >= f.holes.size(): return false
	var points: Array = (f.points if hole_index == -1 else f.holes[hole_index]).duplicate(true)
	if at < 0 or at > points.size(): return false
	points.insert(at,[point.x,point.y])
	return update_ring(id,hole_index,points)

func remove_vertex(id: String, at: int, hole_index: int = -1) -> bool:
	var f := find_feature(id)
	if f.is_empty() or not f.kind in POLYGONS+LINES or hole_index < -1 or hole_index >= f.holes.size(): return false
	var points: Array = (f.points if hole_index == -1 else f.holes[hole_index]).duplicate(true)
	if at < 0 or at >= points.size(): return false
	points.remove_at(at)
	return update_ring(id,hole_index,points)

func duplicate_feature(id: String) -> String:
	var f := find_feature(id)
	if f.is_empty() or layer(f.layer).locked: return ""
	var next := snapshot()
	var copy: Dictionary = f.duplicate(true)
	copy.id = "f_%s_%s" % [Time.get_ticks_usec(),randi()]
	copy.name += " 副本"
	copy.domain_id = ""
	var shift := Vector2(24,24)
	for p in f.points:
		shift.x = minf(shift.x,data.canvas_size[0]-p[0])
		shift.y = minf(shift.y,data.canvas_size[1]-p[1])
	for p in copy.points:
		p[0] += shift.x
		p[1] += shift.y
	for hole in copy.holes:
		for p in hole: p[0]+=shift.x; p[1]+=shift.y
	copy.protected = false
	next.features.append(copy)
	return copy.id if _commit(next) else ""

func move_feature_order(id: String, direction: int) -> bool:
	if direction == 0: return false
	var f := find_feature(id)
	if f.is_empty() or layer(f.layer).locked: return false
	var next := snapshot()
	var at: int = data.features.find(f)
	var to := at + signi(direction)
	while to >= 0 and to < next.features.size():
		if next.features[to].layer == f.layer:
			var item: Dictionary = next.features.pop_at(at)
			next.features.insert(to,item)
			return _commit(next)
		to += signi(direction)
	return false

func move_layer(id: String, direction: int) -> bool:
	if direction == 0: return false
	var next := snapshot()
	for i in range(next.layers.size()):
		if next.layers[i].id != id: continue
		var to := i + signi(direction)
		if to < 0 or to >= next.layers.size(): return false
		var item: Dictionary = next.layers.pop_at(i)
		next.layers.insert(to,item)
		return _commit(next)
	return false

func configure_canvas(title: String, dimensions: Vector2i, scale_contents: bool) -> bool:
	var next := snapshot()
	var ratio := Vector2(dimensions)/Vector2(data.canvas_size[0],data.canvas_size[1])
	next.title = title.strip_edges()
	if next.title.is_empty(): return false
	next.canvas_size = [dimensions.x,dimensions.y]
	if scale_contents:
		for f in next.features:
			for p in f.points:
				p[0] *= ratio.x
				p[1] *= ratio.y
			for hole in f.holes:
				for p in hole: p[0]*=ratio.x; p[1]*=ratio.y
			if f.kind in LINES: f.width = clampf(f.width*minf(ratio.x,ratio.y),1 if f.kind in BOUNDARIES else 8,256)
			if f.get("visual", {}).has("ribbon"):
				for point in f.visual.ribbon.points:
					point[0] *= ratio.x
					point[1] *= ratio.y
				for i in range(f.visual.ribbon.widths.size()): f.visual.ribbon.widths[i] *= minf(ratio.x,ratio.y)
		for instance in next.get("presentation", {}).get("instances", []):
			instance.position[0] *= ratio.x
			instance.position[1] *= ratio.y
		for ref in [next.reference] + next.reference_tiles:
			# Nonuniform scaling of a rotated rectangle would require shear.
			if not is_zero_approx(ref.rotation) and not is_equal_approx(ratio.x,ratio.y): return false
			for key in ["position","size"]:
				ref[key][0] *= ratio.x
				ref[key][1] *= ratio.y
		for region in next.production.regions:
			region.rect[0]*=ratio.x; region.rect[1]*=ratio.y
			region.rect[2]*=ratio.x; region.rect[3]*=ratio.y
		for scenario in next.production.checks:
			for key in ["start","finish"]: scenario[key][0]*=ratio.x; scenario[key][1]*=ratio.y
			scenario.rect[0]*=ratio.x; scenario.rect[1]*=ratio.y
			scenario.rect[2]*=ratio.x; scenario.rect[3]*=ratio.y
		# Registration reports describe the previous coordinate frame and must be redone.
		next.production.calibrations.clear()
	return _commit(next)

static func simplify_stroke(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	# Ramer-Douglas-Peucker, iterative to avoid recursive stack exhaustion.
	if points.size() < 3: return points
	var keep := {0:true,points.size()-1:true}
	var pending: Array = [Vector2i(0,points.size()-1)]
	while not pending.is_empty():
		var segment: Vector2i = pending.pop_back()
		var best := tolerance
		var split := -1
		for i in range(segment.x+1,segment.y):
			var distance := points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i],points[segment.x],points[segment.y]))
			if distance > best: best=distance; split=i
		if split >= 0:
			keep[split] = true
			pending.append(Vector2i(segment.x,split))
			pending.append(Vector2i(split,segment.y))
	var result := PackedVector2Array()
	for i in range(points.size()):
		if keep.has(i): result.append(points[i])
	return result

static func migrate(value: Variant) -> Variant:
	if not value is Dictionary: return value
	var next: Dictionary = value.duplicate(true)
	if next.get("schema_version") == 1:
		if not next.get("layers") is Array or not _point(next.get("canvas_size")): return next
		next.schema_version = 2
		next.reference = {"path":next.get("background_path",""),"position":[0,0],"size":next.canvas_size.duplicate(),"opacity":next.get("background_opacity",0.35),"visible":true,"locked":true,"above_art":false}
		next.erase("background_path")
		next.erase("background_opacity")
		next.layers.insert(mini(3,next.layers.size()),{"id":"boundaries","visible":true,"locked":false})
	if next.get("schema_version") == 2 and next.get("reference") is Dictionary:
		next.schema_version = 3
		next.reference.rotation = 0.0
		next.reference_tiles = []
	if next.get("schema_version") == 3 and next.get("features") is Array:
		next.schema_version = 4
		next.production = Production.defaults()
		for f in next.features:
			if f is Dictionary: Production.enrich_feature(f)
	return next

func resolve_reference_path(id: String = "primary") -> String:
	return _resolve_path(get_reference(id).get("path",""),current_path)

static func _resolve_path(path: String, document_path: String) -> String:
	if path.is_empty(): return ""
	if path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"): return ProjectSettings.globalize_path(path)
	return ProjectSettings.globalize_path(document_path.get_base_dir().path_join(path))

func undo() -> bool:
	if undo_stack.is_empty(): return false
	var entry: Dictionary=undo_stack.pop_back()
	redo_stack.append(_history_entry(entry.art_only))
	_restore_history(entry)
	changed.emit()
	return true

func redo() -> bool:
	if redo_stack.is_empty(): return false
	var entry: Dictionary=redo_stack.pop_back()
	undo_stack.append(_history_entry(entry.art_only))
	_restore_history(entry)
	changed.emit()
	return true

func is_dirty() -> bool:
	# Legacy callers may explicitly mark a document saved using saved_signature.
	if saved_signature != _known_saved_signature:
		_known_saved_signature=saved_signature
		_saved_revision=revision if JSON.stringify(data)==saved_signature else -1
	return revision != _saved_revision

func _restore_history(entry: Dictionary) -> void:
	if entry.art_only:
		data=data.duplicate()
		data.presentation=entry.state
	else: data=entry.state
	revision=entry.revision
	last_change_art_only=entry.art_only

func load_text(text: String) -> String:
	var json := JSON.new()
	if json.parse(text) != OK: return "JSON 损坏：" + json.get_error_message()
	var error := replace_document(migrate(json.data)) if json.data is Dictionary else "地图根节点必须为对象。"
	if error.is_empty():
		saved_signature = JSON.stringify(data)
		_known_saved_signature=saved_signature; _saved_revision=revision
	return error

func load_file(path: String) -> String:
	if not FileAccess.file_exists(path): return "文件不存在。"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "无法打开文件。"
	if file.get_length() > 32 * 1024 * 1024: return "地图文件超过 32 MiB。"
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return "JSON 损坏："+json.get_error_message()
	var next: Variant = migrate(json.data)
	var error := validate(next)
	if not error.is_empty(): return error
	data = next.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()
	current_path = path
	saved_signature = JSON.stringify(data)
	_serial+=1; revision=_serial; _saved_revision=revision
	_known_saved_signature=saved_signature; last_change_art_only=false
	changed.emit()
	return ""

func save_file(path: String) -> String:
	var error := validate(data)
	if not error.is_empty(): return error
	var next := snapshot()
	error=write_snapshot(next,path,current_path)
	if not error.is_empty():return error
	for stack in [undo_stack,redo_stack]:
		for entry in stack:
			if entry.art_only: continue
			var state: Dictionary=entry.state
			for ref in [state.reference] + state.reference_tiles:
				if not ref.path.is_empty(): ref.path = _resolve_path(ref.path,current_path)
	data = next
	current_path = path
	saved_signature = JSON.stringify(data)
	_known_saved_signature=saved_signature; _saved_revision=revision
	last_change_art_only=false
	changed.emit()
	return ""

# Pure snapshot/file operation; safe for recovery workers. Validation stays
# on the owner thread before a detached snapshot is submitted.
static func write_snapshot(next: Dictionary,path: String,source_path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	for ref in [next.reference] + next.reference_tiles:
		if ref.path.is_empty(): continue
		var original := _resolve_path(ref.path,source_path)
		if not FileAccess.file_exists(original): return "参考图缺失，请重新指定原图后保存。"
		var folder := absolute.get_file().get_basename()+".assets"
		var name := "reference_"+FileAccess.get_sha256(original).substr(0,16)+"."+original.get_extension().to_lower()
		var destination := absolute.get_base_dir().path_join(folder).path_join(name)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK: return "无法创建地图参考图目录。"
		if original.simplify_path() != destination.simplify_path() and not FileAccess.file_exists(destination):
			if DirAccess.copy_absolute(original,destination) != OK: return "参考图复制失败；未覆盖工程。"
		ref.path = folder.path_join(name)
	var temp := absolute + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return "无法写入保存目录。"
	file.store_string(JSON.stringify(next, "\t"))
	file.flush()
	var code := file.get_error()
	file.close()
	if code != OK: return "临时文件写入失败，原文件保留。"
	if FileAccess.file_exists(absolute) and DirAccess.copy_absolute(absolute, absolute + ".bak") != OK: return "无法备份原文件，停止保存。"
	if DirAccess.rename_absolute(temp, absolute) != OK: return "替换文件失败，临时文件和原文件保留。"
	return ""

static func tongguan_sample() -> Dictionary:
	var result := blank()
	result.title = "潼关 · 山河夹峙（结构示意，非历史测绘）"
	var f: Array = result.features
	f.append(feature("basin", [[0,340],[670,340],[610,550],[0,660]], "关中平原", "guanzhong"))
	f.append(feature("water", [[0,0],[1600,0],[1600,340],[1060,350],[860,330],[620,350],[0,340]], "黄河 · 无渡点不可步行跨越", "yellow_river"))
	f.append(feature("mountain", [[0,680],[540,560],[720,340],[920,340],[1080,580],[1600,680],[1600,960],[0,960]], "华山 · 秦岭屏障", "qinling"))
	f.append(feature("hills", [[1050,490],[1450,480],[1540,630],[1130,630]], "崤函低丘 · 可通行 / 易设伏", "xiaohan"))
	f.append(feature("forest", [[200,490],[440,480],[510,560],[260,620]], "林地 · 可通行 / 较慢", "woods"))
	f.append(feature("valley", [[600,430],[1050,430]], "沿河谷道", "main_valley"))
	f[-1].width = 96
	f[-1].gate_id = "tongguan"
	f.append(feature("trail", [[520,470],[620,560],[720,680],[1000,680],[1120,510],[1180,470]], "山间险径 · 仅轻装 / 需发现", "secret_trail"))
	f[-1].width = 48
	f.append(feature("pass", [[820,430]], "潼关", "tongguan"))
	f.append(feature("city", [[250,430]], "关中一侧", "west_city"))
	f.append(feature("city", [[1330,430]], "崤函一侧", "east_city"))
	f.append(feature("label", [[800,130]], "黄  河", "water_label"))
	return result

func copy_for_save() -> RefCounted:
	# Cache entries are immutable validated snapshots. The copy still validates
	# every changed value and every cross-reference before writing a draft.
	var copy: RefCounted=get_script().new()
	copy._validated_features=_validated_features.duplicate()
	copy._validated_art=_validated_art.duplicate()
	copy._validation_extent=_validation_extent.duplicate()
	copy._catalog_generation=_catalog_generation
	copy.current_path=current_path
	return copy
