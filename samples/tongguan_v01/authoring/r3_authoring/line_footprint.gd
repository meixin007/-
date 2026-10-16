extends RefCounted
## Exact closed-rectangle / finite-segment clearance in local meters.
## Rounded endpoint semantics, strict half-width threshold; 0.1mm tolerance.
const EPSILON_M=0.0001
static func point_distance(point: Vector2,box: Rect2)->float:
	return point.distance_to(point.clamp(box.position,box.end))
static func segment_distance(box: Rect2,a: Vector2,b: Vector2)->float:
	var delta=b-a;var enter=0.0;var leave=1.0
	for axis in 2:
		if absf(delta[axis])<0.0000001:
			if a[axis]<box.position[axis] or a[axis]>box.end[axis]:enter=2.0;break
		else:
			var u=(box.position[axis]-a[axis])/delta[axis];var v=(box.end[axis]-a[axis])/delta[axis]
			enter=maxf(enter,minf(u,v));leave=minf(leave,maxf(u,v))
	if enter<=leave:return 0.0
	var distance=minf(point_distance(a,box),point_distance(b,box))
	for corner in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
		var weight=clampf((corner-a).dot(delta)/delta.length_squared(),0,1) if delta.length_squared()>0 else 0.0
		distance=minf(distance,corner.distance_to(a+delta*weight))
	return distance
static func prepare(points: Array,half_width: float,closed:=false)->Array:
	var segments=[]
	for i in maxi(1,points.size()-1+(1 if closed else 0)):
		if points.is_empty():break
		var p=points[mini(i,points.size()-1)];var q=points[(i+1)%points.size()]
		var a=Vector2(p[0],p[1]);var b=Vector2(q[0],q[1])
		segments.append({"a":a,"b":b,"bounds":Rect2(a,Vector2.ZERO).expand(b).grow(half_width)})
	return segments
static func intersects(box: Rect2,segments: Array,half_width: float)->bool:
	for segment in segments:
		if box.intersects(segment.bounds) and segment_distance(box,segment.a,segment.b)<half_width-EPSILON_M:return true
	return false
