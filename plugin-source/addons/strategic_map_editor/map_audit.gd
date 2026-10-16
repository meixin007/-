@tool
extends RefCounted
const Doc = preload("document.gd")
const Routes = preload("route_preview.gd")
const Geometry = preload("geometry_ops.gd")
static func inspect(doc: RefCounted) -> Array:
	var issues: Array = []
	var error: String = doc.validate(doc.data)
	if not error.is_empty(): return [{"id":"document","code":"document","severity":"error","feature_id":"","related_ids":[],"message":error,"evidence":Doc.canonical_digest(doc.data)}]
	var domains := {}
	var used_gates := {}
	var meshes := {}
	for f in doc.data.features:
		if f.kind in Doc.POLYGONS and f.rule in ["blocked","water"]: meshes[f.id]=Geometry.triangles(f)
	for f in doc.data.features:
		if not f.domain_id.is_empty():
			if domains.has(f.domain_id): issues.append(_issue("error",f,"重复绑定地点 ID："+f.domain_id,"duplicate_domain",[domains[f.domain_id]]))
			domains[f.domain_id]=f.id
		if f.source.status in ["candidate","unverified"] and f.source.citation.is_empty(): issues.append(_issue("warning",f,"尚未记录资料来源。","missing_source"))
		if f.kind in Doc.PASSAGES:
			if not f.gate_id.is_empty():
				used_gates[f.gate_id]=true
				var gate: Dictionary = doc.find_feature(f.gate_id)
				if _distance_to_line(Vector2(gate.points[0][0],gate.points[0][1]),f) > f.width*0.5: issues.append(_issue("warning",f,"绑定关隘未落在通道范围内，请检查关联。","gate_outside_passage",[gate.id]))
			var touches := false
			var line:=Doc.packed(f.points)
			var origin:=line[0]
			var outlines := Geometry2D.offset_polyline(Geometry.local_points(line),f.width*0.5)
			for barrier in doc.data.features:
				if not barrier.kind in Doc.POLYGONS or barrier.rule != ("water" if f.kind == "crossing" else "blocked"): continue
				for outline in outlines:
					for triangle in meshes[barrier.id]:
						var local: PackedVector2Array=triangle.duplicate()
						for i in range(local.size()): local[i]-=origin
						if not Geometry2D.intersect_polygons(outline,local).is_empty(): touches=true; break
					if touches: break
				if touches: break
			if not touches: issues.append(_issue("warning",f,"通道未与对应障碍区域相交；若穿越的是线状河流，请复核过河场景。","passage_misses_barrier"))
		if f.kind in ["city","pass","ford"]:
			var p := Vector2(f.points[0][0],f.points[0][1])
			for barrier in doc.data.features:
				if barrier.kind not in Doc.POLYGONS or barrier.rule not in ["blocked","water"] or not Geometry.contains(barrier,p): continue
				var entrance := false
				for corridor in doc.data.features:
					if corridor.kind not in Doc.PASSAGES: continue
					if (corridor.kind == "crossing") != (barrier.rule == "water"): continue
					if _distance_to_line(p,corridor) <= corridor.width*0.5: entrance=true; break
				if not entrance: issues.append(_issue("warning",f,"地点落在障碍区域，附近没有相应通道；可能无法抵达。","site_in_barrier",[barrier.id]))
	for f in doc.data.features:
		if f.kind in ["pass","ford"] and not used_gates.has(f.id): issues.append(_issue("warning",f,"此关隘 / 渡口尚未绑定通道，仅有图标。","unbound_gate"))
	for issue in issues:
		issue.evidence=evidence(doc,issue)
	return issues
static func _issue(severity: String, f: Dictionary, message: String, code: String, related: Array=[]) -> Dictionary:
	return {"id":code+":"+f.id+":"+",".join(related),"code":code,"severity":severity,"feature_id":f.id,"related_ids":related,"message":f.name+"："+message}
static func evidence(doc: RefCounted,issue: Dictionary) -> String:
	var features: Array=[]
	var primary: Dictionary=doc.find_feature(issue.feature_id)
	var ids: Array=[issue.feature_id]+issue.get("related_ids",[])
	# Absence checks also depend on potential matching geometry, not only the
	# named object. A moved barrier/corridor must invalidate its old review.
	for f in doc.data.features:
		var relevant:=false
		match issue.get("code",""):
			"passage_misses_barrier": relevant=f.kind in Doc.POLYGONS and f.rule==("water" if primary.get("kind")=="crossing" else "blocked")
			"site_in_barrier": relevant=f.kind in Doc.PASSAGES
			"unbound_gate": relevant=f.kind in Doc.PASSAGES and f.gate_id==issue.feature_id
			"duplicate_domain": relevant=not primary.is_empty() and f.domain_id==primary.domain_id
		if relevant and f.id not in ids: ids.append(f.id)
	ids.sort()
	for id in ids: features.append(doc.find_feature(id))
	return Doc.canonical_digest(features)
static func in_region(doc: RefCounted,issue: Dictionary,region: Rect2) -> bool:
	var f: Dictionary=doc.find_feature(issue.feature_id)
	if f.is_empty(): return false
	var points:=Doc.packed(f.points); var bounds:=Rect2(points[0],Vector2.ZERO)
	for p in points: bounds=bounds.expand(p)
	return region.intersects(bounds.grow(0.001))
static func _distance_to_line(p: Vector2, f: Dictionary) -> float:
	var closest := INF
	var pts := Doc.packed(f.points)
	for i in range(pts.size()-1): closest=minf(closest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,pts[i],pts[i+1])))
	return closest
static func run_case(doc: RefCounted, scenario: Dictionary) -> Dictionary:
	var copy: Dictionary = doc.snapshot()
	for f in copy.features:
		if scenario.gates.has(f.id): f.gate_open=scenario.gates[f.id]
	var r: Array = scenario.rect
	var result := Routes.new().solve(copy,Vector2(scenario.start[0],scenario.start[1]),Vector2(scenario.finish[0],scenario.finish[1]),scenario.unit,scenario.revealed,Rect2(r[0],r[1],r[2],r[3]),scenario.step)
	var unresolved: bool = result.get("diagnostic","") not in ["path","no_path","blocked"]
	return {"id":scenario.id,"name":scenario.name,"status":"UNRESOLVED" if unresolved else ("PASS" if result.ok == scenario.expected else "FAIL"),"expected":scenario.expected,"actual":result.ok,"reason":result.reason,"step":scenario.step,"path":result.path,"rect":scenario.rect}
