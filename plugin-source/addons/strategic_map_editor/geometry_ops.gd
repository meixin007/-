@tool
extends RefCounted
## Non-CK3 planar authoring geometry; no game movement authority.
static func packed(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points: result.append(Vector2(p[0],p[1]))
	return result
static func unpack(points: PackedVector2Array) -> Array:
	var result: Array = []
	for p in points: result.append([p.x,p.y])
	return result
static func contains(f: Dictionary, p: Vector2) -> bool:
	if not point_in_ring(p,packed(f.points)): return false
	for hole in f.get("holes",[]):
		if point_in_ring(p,packed(hole)): return false
	return true
static func prepare_containment(f: Dictionary) -> Array:
	var queries: Array=[]
	for ring in [f.points]+f.get("holes",[]):
		var query=preload("polygon_query.gd").new()
		query.prepare(packed(ring));queries.append(query)
	if queries.size()>8:
		var bounds: Array=[]
		for i in range(1,queries.size()):
			# Broad phase is deliberately padded; exact ring tests still decide.
			bounds.append(Rect2(queries[i].bounds.position+queries[i].origin,queries[i].bounds.size).grow(.01))
		queries[0].holes_index=preload("spatial_index.gd").new()
		queries[0].holes_index.build(bounds)
	return queries
static func contains_prepared(queries: Array, point: Vector2) -> bool:
	if queries.is_empty() or not queries[0].contains(point): return false
	if queries[0].holes_index!=null:
		for i in queries[0].holes_index.query(Rect2(point,Vector2.ZERO)):
			if queries[i+1].contains(point):return false
		return true
	for i in range(1,queries.size()):
		if queries[i].contains(point): return false
	return true
static func local_points(points: PackedVector2Array) -> PackedVector2Array:
	var result:=points.duplicate()
	if result.is_empty(): return result
	var origin:=result[0]
	for i in range(result.size()): result[i]-=origin
	return result
static func point_in_ring(point: Vector2,points: PackedVector2Array) -> bool:
	return not points.is_empty() and preload("polygon_math.gd").contains(point-points[0],local_points(points))
static func triangulate(points: PackedVector2Array) -> PackedInt32Array:
	return Geometry2D.triangulate_polygon(local_points(points))
static func rings_intersect(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size()*b.size()>4096:
		# Prune only disjoint edge bounds; the exact segment test is unchanged.
		var first_is_indexed:=a.size()>b.size()
		var indexed:=a if first_is_indexed else b
		var queried:=b if first_is_indexed else a
		var bounds: Array=[]
		for i in range(indexed.size()):bounds.append(Rect2(indexed[i],Vector2.ZERO).expand(indexed[(i+1)%indexed.size()]).grow(.0001))
		var index=preload("spatial_index.gd").new();index.build(bounds)
		for i in range(queried.size()):
			var box:=Rect2(queried[i],Vector2.ZERO).expand(queried[(i+1)%queried.size()]).grow(.0001)
			for j in index.query(box):
				# Preserve the original operand order, including near-touching edges.
				var ai: int=j if first_is_indexed else i
				var bi: int=i if first_is_indexed else j
				if Geometry2D.segment_intersects_segment(a[ai],a[(ai+1)%a.size()],b[bi],b[(bi+1)%b.size()])!=null:return true
		return false
	for i in range(a.size()):
		for j in range(b.size()):
			if Geometry2D.segment_intersects_segment(a[i],a[(i+1)%a.size()],b[j],b[(j+1)%b.size()]) != null: return true
	return false
static func ring_edge_index(ring: PackedVector2Array) -> RefCounted:
	var rectangles: Array=[]
	for i in ring.size(): rectangles.append(Rect2(ring[i],Vector2.ZERO).expand(ring[(i+1)%ring.size()]).grow(.0001))
	var index=preload("spatial_index.gd").new()
	index.build(rectangles)
	return index
static func rings_intersect_indexed(a: PackedVector2Array, b: PackedVector2Array, index: RefCounted) -> bool:
	for i in b.size():
		var box:=Rect2(b[i],Vector2.ZERO).expand(b[(i+1)%b.size()]).grow(.0001)
		for j in index.query(box):
			if Geometry2D.segment_intersects_segment(a[j],a[(j+1)%a.size()],b[i],b[(i+1)%b.size()])!=null: return true
	return false
static func triangles(f: Dictionary) -> Array:
	var origin:=Vector2(f.points[0][0],f.points[0][1])
	var local:=preload("polygon_boolean.gd").local_shape(f,origin)
	var result:=_local_triangles(local)
	for triangle in result:
		for i in range(triangle.size()): triangle[i]+=origin
	return result
static func _local_triangles(f: Dictionary) -> Array:
	var result: Array = []
	var outer := packed(f.points)
	if f.get("holes",[]).is_empty():
		var indices := Geometry2D.triangulate_polygon(outer)
		for i in range(0,indices.size(),3): result.append(PackedVector2Array([outer[indices[i]],outer[indices[i+1]],outer[indices[i+2]]]))
		return result
	# Sweep at every vertex X. Each open slab has a fixed edge ordering;
	# even/odd interval pairs become trapezoids, including concave outer rings and holes.
	var edges: Array = []
	var xs: Array[float] = []
	for ring in [f.points] + f.holes:
		var points := packed(ring)
		for i in range(points.size()):
			xs.append(points[i].x)
			var a := points[i]
			var b := points[(i+1)%points.size()]
			if absf(a.x-b.x)>0.000001: edges.append([a,b,minf(a.x,b.x),maxf(a.x,b.x)])
	xs.sort()
	# Maintain only edges crossing this slab instead of scanning every edge for
	# every vertex X. Keep the same slabs, ordering and output triangles.
	var starts: Array=range(edges.size())
	starts.sort_custom(func(a,b):return edges[a][2]<edges[b][2])
	var cursor:=0
	var active: Dictionary={}
	for i in range(xs.size()-1):
		var left := xs[i]
		var right := xs[i+1]
		if right-left < 0.00001: continue
		var middle := (left+right)*0.5
		while cursor<starts.size() and edges[starts[cursor]][2]<middle:
			active[starts[cursor]]=edges[starts[cursor]]
			cursor+=1
		var crossing: Array = []
		for id in active.keys():
			var edge: Array=active[id]
			if edge[3]<=middle:active.erase(id)
			else:crossing.append(edge)
		crossing.sort_custom(func(a,b): return _edge_y(a,middle) < _edge_y(b,middle))
		for j in range(0,crossing.size()-1,2):
			var a := Vector2(left,_edge_y(crossing[j],left))
			var b := Vector2(right,_edge_y(crossing[j],right))
			var c := Vector2(right,_edge_y(crossing[j+1],right))
			var d := Vector2(left,_edge_y(crossing[j+1],left))
			if absf((b-a).cross(c-a)) > 0.00001: result.append(PackedVector2Array([a,b,c]))
			if absf((c-a).cross(d-a)) > 0.00001: result.append(PackedVector2Array([a,c,d]))
	return result
static func _edge_y(edge: Array, x: float) -> float:
	return edge[0].y+(edge[1].y-edge[0].y)*(x-edge[0].x)/(edge[1].x-edge[0].x)
static func boolean_shapes(a: Dictionary, b: Dictionary, operation: String) -> Dictionary:
	return preload("polygon_boolean.gd").run(a,b,operation)
