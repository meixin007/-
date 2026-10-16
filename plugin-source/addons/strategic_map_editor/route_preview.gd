@tool
extends RefCounted
## Non-CK3 editor-only raster diagnostic; never imports or writes campaign state.
## Conservative blocked-cell sampling. This grid is an authoring aid, not movement authority.
const Doc = preload("document.gd")
const Geometry = preload("geometry_ops.gd")
var grid: AStarGrid2D
var step := 16.0

func solve(data: Dictionary, start: Vector2, finish: Vector2, unit: String, revealed: bool, region: Rect2 = Rect2(), precision: float = 4.0) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var extent := Vector2(data.canvas_size[0], data.canvas_size[1])
	if not Rect2(Vector2.ZERO, extent).has_point(start) or not Rect2(Vector2.ZERO, extent).has_point(finish): return {"ok":false,"reason":"起终点必须在地图内。", "path":PackedVector2Array()}
	step = maxf(16.0, maxf(extent.x, extent.y) / 128.0)
	var local := region.has_area()
	var scope := Rect2(Vector2.ZERO,extent)
	if local:
		scope = scope.intersection(region)
		if not scope.has_area() or not scope.has_point(start) or not scope.has_point(finish): return {"ok":false,"reason":"局部检查要求起终点都在当前视野内。","path":PackedVector2Array()}
		if not is_finite(precision) or precision < 1: return {"ok":false,"reason":"精度必须大于或等于 1。","path":PackedVector2Array()}
		step = precision
		if ceili(scope.size.x/step) > 256 or ceili(scope.size.y/step) > 256: return {"ok":false,"reason":"局部检查最多 256 × 256 格，请放大视图缩小范围，或调大格距。","path":PackedVector2Array()}
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0,0,ceili(scope.size.x/step),ceili(scope.size.y/step))
	grid.cell_size = Vector2.ONE * step
	grid.offset = scope.position + Vector2.ONE * step * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var prepared: Array = []
	var gates: Dictionary = {}
	for f in data.features:
		gates[f.id] = f
		if f.kind in Doc.BOUNDARIES: continue
		if f.kind in Doc.POLYGONS or f.kind in Doc.LINES:
			var pts := Doc.packed(f.points)
			var bounds := Rect2(pts[0], Vector2.ZERO)
			for p in pts: bounds = bounds.expand(p)
			if not bounds.grow(f.width*0.5 + step).intersects(scope): continue
			var outlines: Array = [pts] if f.kind in Doc.POLYGONS else Array(Geometry2D.offset_polyline(pts,f.width*0.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND))
			for hole in f.get("holes",[]): outlines.append(Doc.packed(hole))
			var local_rings: Array=[]
			if f.kind in Doc.POLYGONS:
				for outline in outlines: local_rings.append({"points":Geometry.local_points(outline),"origin":outline[0]})
			prepared.append({"f":f,"points":pts,"local_rings":local_rings,"outlines":outlines,"bounds":bounds.grow(f.width*0.5 + step)})
	var offsets := [Vector2.ZERO, Vector2(-0.45,-0.45)*step, Vector2(0.45,-0.45)*step, Vector2(-0.45,0.45)*step, Vector2(0.45,0.45)*step]
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var id := Vector2i(x,y)
			var p := scope.position + (Vector2(id)+Vector2.ONE*0.5)*step
			var cost := 1.0
			var blocked := not scope.has_point(p)
			for offset in offsets:
				var c := _cost(p+offset, prepared, gates, unit, revealed)
				if c < 0: blocked = true; break
				cost = maxf(cost,c)
			grid.set_point_solid(id, blocked)
			grid.set_point_weight_scale(id,cost)
	var a := Vector2i(((start-scope.position)/step).floor())
	var b := Vector2i(((finish-scope.position)/step).floor())
	if grid.is_point_solid(a) or grid.is_point_solid(b):
		var certain := _cost(start,prepared,gates,unit,revealed) < 0 or _cost(finish,prepared,gates,unit,revealed) < 0
		return {"ok":false,"diagnostic":"blocked" if certain else "resolution","reason":"起点或终点确定位于禁行地形。" if certain else "通道窄于检查精度，不能确定。", "path":PackedVector2Array()}
	var path := grid.get_point_path(a,b)
	if not path.is_empty():
		path.insert(0,start)
		path.append(finish)
	# Grid cells can miss a very thin barrier. Validate path segments against vector
	# boundary intervals before reporting success; never report an unsafe shortcut.
	for i in range(path.size()-1):
		if not _segment_clear(path[i],path[i+1],prepared,gates,unit,revealed):
			return {"ok":false,"reason":"当前栅格精度不足：候选路径触及禁行边界。请调整通道宽度后重检。","path":PackedVector2Array(),"step":step}
	var elapsed := (Time.get_ticks_usec()-begin)/1000.0
	return {"ok":not path.is_empty(), "diagnostic":"path" if not path.is_empty() else "no_path", "path":path, "step":step, "scope":scope, "elapsed_ms":elapsed, "reason":("当前视野内可以通行" if local else "全图粗查可以通行")+"（离线预览）" if not path.is_empty() else ("当前视野内未找到路径；不代表全图无路。" if local else "粗查未找到路径；请用局部精查检查窄谷与关隘。")}

func _cost(p: Vector2, prepared: Array, gates: Dictionary, unit: String, revealed: bool) -> float:
	var blocked := false
	var water := false
	var rough := 1.0
	var land_pass := false
	var water_pass := false
	for item in prepared:
		if not item.bounds.has_point(p): continue
		var f: Dictionary = item.f
		if not _contains(p,item): continue
		if f.kind in Doc.PASSAGES:
			if (f.hidden_route and not revealed) or (f.kind == "trail" and unit != "light"): continue
			if not f.gate_id.is_empty() and not gates[f.gate_id].gate_open: continue
			if f.kind == "crossing": water_pass = true
			else: land_pass = true
			continue
		if f.rule == "blocked": blocked = true
		if f.rule == "water": water = true
		if f.rule == "rough": rough = maxf(rough, 2.0 if unit == "army" else 1.5)
	if (blocked and not land_pass) or (water and not water_pass): return -1
	return rough

func _segment_clear(a: Vector2, b: Vector2, prepared: Array, gates: Dictionary, unit: String, revealed: bool) -> bool:
	var fractions: Array[float] = [0.0,1.0]
	var length := a.distance_to(b)
	if length <= 0: return true
	var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(0.01)
	for item in prepared:
		if not bounds.intersects(item.bounds): continue
		for poly in item.outlines:
			for i in range(poly.size()):
				var hit: Variant = Geometry2D.segment_intersects_segment(a,b,poly[i],poly[(i+1)%poly.size()])
				if hit != null: fractions.append(a.distance_to(hit)/length)
	fractions.sort()
	for i in range(fractions.size()-1):
		if _cost(a.lerp(b,(fractions[i]+fractions[i+1])*0.5),prepared,gates,unit,revealed) < 0: return false
	return true

static func _contains(p: Vector2, item: Dictionary) -> bool:
	if item.f.kind in Doc.POLYGONS:
		var outer: Dictionary=item.local_rings[0]
		if not preload("polygon_math.gd").contains(p-outer.origin,outer.points): return false
		for i in range(1,item.local_rings.size()):
			var hole: Dictionary=item.local_rings[i]
			if preload("polygon_math.gd").contains(p-hole.origin,hole.points): return false
		return true
	for i in range(item.points.size()-1):
		if Geometry2D.get_closest_point_to_segment(p,item.points[i],item.points[i+1]).distance_to(p) <= item.f.width*0.5: return true
	return false
