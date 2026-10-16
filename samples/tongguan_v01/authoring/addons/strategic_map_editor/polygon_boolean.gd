@tool
extends RefCounted
## Non-CK3 planar boundary arrangement. Filled space is outer minus holes.
## Edges are split at crossings, classified on both sides and stitched as rings.
## Refuse ambiguous subpixel topology; callers keep the original transaction.
const MAX_EDGES:=512
const Math=preload("polygon_math.gd")
static func run(a: Dictionary,b: Dictionary,operation: String) -> Dictionary:
	# Work near zero to keep Vector2 precision independent of a 64K canvas offset.
	var origin:=Vector2(a.points[0][0],a.points[0][1])
	var local_a:=local_shape(a,origin); var local_b:=local_shape(b,origin)
	var result:=run_local(local_a,local_b,operation)
	if result.ok:
		for shape in result.shapes:
			for ring in [shape.points]+shape.holes:
				for p in ring: p[0]+=origin.x; p[1]+=origin.y
	return result
static func local_shape(f: Dictionary,origin: Vector2) -> Dictionary:
	var result:=f.duplicate(true)
	for ring in [result.points]+result.get("holes",[]):
		for p in ring: p[0]-=origin.x; p[1]-=origin.y
	return result
static func run_local(a: Dictionary,b: Dictionary,operation: String) -> Dictionary:
	if operation not in ["union","subtract","intersect"]: return fail("未知几何操作。")
	var began:=Time.get_ticks_msec()
	var ar:=rings(a); var br:=rings(b); var segments: Array=[]
	var maximum:=1.0
	for ring in ar+br:
		for i in range(ring.size()):
			var p: Vector2=ring[i]; var q: Vector2=ring[(i+1)%ring.size()]
			maximum=maxf(maximum,maxf(absf(p.x),absf(p.y)))
			segments.append({"a":p,"b":q,"cuts":[[0.0,p],[1.0,q]]})
	if segments.size()>MAX_EDGES: return fail("一次布尔操作最多合计 512 个轮廓顶点；请先简化区域。")
	var epsilon:=maxf(0.00001,maximum*0.0000008)
	for i in range(segments.size()):
		if Time.get_ticks_msec()-began>2000: return fail("布尔操作超过 2 秒交互预算；请简化轮廓后重试。")
		for j in range(i+1,segments.size()):
			var s: Dictionary=segments[i]; var t: Dictionary=segments[j]
			var hit: Variant=Geometry2D.segment_intersects_segment(s.a,s.b,t.a,t.b)
			if hit != null: cut(s,hit,epsilon); cut(t,hit,epsilon)
			# Also split shared/collinear boundaries at endpoints.
			for p in [t.a,t.b]:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,s.a,s.b))<=epsilon: cut(s,p,epsilon)
			for p in [s.a,s.b]:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,t.a,t.b))<=epsilon: cut(t,p,epsilon)
	var nodes: Array[Vector2]=[]; var edges: Array=[]; var keys: Dictionary={}
	for s in segments:
		if Time.get_ticks_msec()-began>2000 or edges.size()>4096: return fail("布尔操作超过交互预算；请简化轮廓后重试。")
		s.cuts.sort_custom(func(x,y): return x[0]<y[0])
		var points: Array[Vector2]=[]
		for item in s.cuts:
			if points.is_empty() or points[-1].distance_to(item[1])>epsilon: points.append(item[1])
		for i in range(points.size()-1):
			var p:=points[i]; var q:=points[i+1]; var middle: Vector2=(p+q)*0.5
			var normal:=Vector2(-(q-p).y,(q-p).x).normalized()
			var clearance:=p.distance_to(q)*0.5
			for other in segments:
				var distance: float=middle.distance_to(Geometry2D.get_closest_point_to_segment(middle,other.a,other.b))
				if distance>epsilon*2: clearance=minf(clearance,distance)
			# A full-width 64K shape needs a larger probe than a small local shape;
			# keep it above numerical noise, still below nearby edge clearance.
			var probe:=minf(maxf(0.05,epsilon*8),clearance*0.2)
			if probe<epsilon*2: return fail("边界过于接近，超出本次布尔运算精度；原对象保留。")
			var left:=evaluate(inside(ar,middle+normal*probe),inside(br,middle+normal*probe),operation)
			var right:=evaluate(inside(ar,middle-normal*probe),inside(br,middle-normal*probe),operation)
			if left==right: continue
			var start:=node_id(nodes,p if left else q,epsilon)
			var finish:=node_id(nodes,q if left else p,epsilon)
			if start==finish: continue
			var key:=str(start)+":"+str(finish)
			if keys.has(key): continue
			if keys.has(str(finish)+":"+str(start)): return fail("边界方向存在精度冲突；原对象保留。")
			keys[key]=true; edges.append([start,finish])
	if edges.is_empty(): return fail("结果为空；没有修改原区域。")
	var outgoing: Dictionary={}
	for i in range(edges.size()):
		if not outgoing.has(edges[i][0]): outgoing[edges[i][0]]=[]
		outgoing[edges[i][0]].append(i)
	var used: Dictionary={}; var contours: Array=[]
	for seed in range(edges.size()):
		if used.has(seed): continue
		var start: int=edges[seed][0]; var current:=seed; var contour:=PackedVector2Array()
		var closed:=false
		for guard in range(edges.size()+1):
			if used.has(current): return fail("边界无法闭合；原对象保留。")
			used[current]=true
			var u: int=edges[current][0]; var v: int=edges[current][1]
			contour.append(nodes[u])
			if v==start: closed=true; break
			var direction:=nodes[v]-nodes[u]; var best:=-1; var angle:=-INF
			for candidate in outgoing.get(v,[]):
				if used.has(candidate): continue
				var next:=nodes[edges[candidate][1]]-nodes[v]
				var turn:=atan2(direction.cross(next),direction.dot(next))
				if turn>angle: angle=turn; best=candidate
			if best<0: return fail("边界存在断点；原对象保留。")
			current=best
		if not closed: return fail("边界追踪超出预算；原对象保留。")
		contour=simplify(contour,epsilon)
		if contour.size()<3 or Geometry2D.triangulate_polygon(contour).is_empty(): return fail("运算产生退化轮廓；原对象保留。")
		contours.append(contour)
	return classify(contours,epsilon)
static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}
static func rings(f: Dictionary) -> Array:
	var result: Array=[]
	for values in [f.points]+f.get("holes",[]):
		var ring:=PackedVector2Array()
		for p in values: ring.append(Vector2(p[0],p[1]))
		result.append(ring)
	return result
static func inside(contours: Array,p: Vector2) -> bool:
	if not Math.contains(p,contours[0]): return false
	for i in range(1,contours.size()):
		if Math.contains(p,contours[i]): return false
	return true
static func evaluate(a: bool,b: bool,operation: String) -> bool:
	if operation=="union": return a or b
	if operation=="intersect": return a and b
	return a and not b
static func cut(s: Dictionary,p: Vector2,epsilon: float) -> void:
	var direction: Vector2=s.b-s.a
	if direction.length_squared()<=epsilon*epsilon: return
	var t: float=(p-s.a).dot(direction)/direction.length_squared()
	if t>=-0.000001 and t<=1.000001: s.cuts.append([clampf(t,0,1),p])
static func node_id(nodes: Array[Vector2],point: Vector2,epsilon: float) -> int:
	for i in range(nodes.size()):
		if nodes[i].distance_to(point)<=epsilon*2: return i
	nodes.append(point); return nodes.size()-1
static func simplify(points: PackedVector2Array,epsilon: float) -> PackedVector2Array:
	var result:=points.duplicate()
	var changed:=true
	while changed and result.size()>3:
		changed=false
		for i in range(result.size()):
			var p:=result[(i-1+result.size())%result.size()]; var q:=result[(i+1)%result.size()]
			if result[i].distance_to(Geometry2D.get_closest_point_to_segment(result[i],p,q))<=epsilon:
				result.remove_at(i); changed=true; break
	return result
static func sample_inside(ring: PackedVector2Array,epsilon: float) -> Vector2:
	for i in range(ring.size()):
		var a:=ring[i]; var b:=ring[(i+1)%ring.size()]
		var normal:=Vector2(-(b-a).y,(b-a).x).normalized()*epsilon*4
		for p in [(a+b)*0.5+normal,(a+b)*0.5-normal]:
			if Math.contains(p,ring): return p
	return Vector2.INF
static func unpack(ring: PackedVector2Array) -> Array:
	var result: Array=[]
	for p in ring: result.append([p.x,p.y])
	return result
static func classify(contours: Array,epsilon: float) -> Dictionary:
	var depths: Array[int]=[]; var probes: Array[Vector2]=[]
	for i in range(contours.size()):
		var p:=sample_inside(contours[i],epsilon)
		if not p.is_finite(): return fail("无法确定轮廓内部；原对象保留。")
		probes.append(p); var depth:=0
		for j in range(contours.size()):
			if i!=j and Math.contains(p,contours[j]): depth+=1
		depths.append(depth)
	var shapes: Array=[]
	for i in range(contours.size()):
		if depths[i]%2==0: shapes.append({"points":unpack(contours[i]),"holes":[],"ring_index":i})
	for i in range(contours.size()):
		if depths[i]%2==0: continue
		var owned:=false
		for shape in shapes:
			if depths[shape.ring_index]==depths[i]-1 and Math.contains(probes[i],contours[shape.ring_index]):
				shape.holes.append(unpack(contours[i])); owned=true; break
		if not owned: return fail("孔洞归属不明确；原对象保留。")
	return {"ok":true,"shapes":shapes}
