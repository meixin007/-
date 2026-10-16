@tool
extends RefCounted
## Scalar GDScript floats are doubles. Avoid Vector2 cross-products and the
## native point test when a contour spans most of a 64K authoring canvas.
static func contains(point: Vector2,ring: PackedVector2Array) -> bool:
	if ring.size()<3: return false
	var px: float=point.x; var py: float=point.y
	var a:=ring[-1]; var inside:=false
	for b in ring:
		var ax: float=a.x; var ay: float=a.y
		var bx: float=b.x; var by: float=b.y
		var dx: float=bx-ax; var dy: float=by-ay
		var cross: float=dx*(py-ay)-dy*(px-ax)
		if absf(cross)<=0.00001*maxf(1.0,absf(dx)+absf(dy)) and px>=minf(ax,bx)-0.00001 and px<=maxf(ax,bx)+0.00001 and py>=minf(ay,by)-0.00001 and py<=maxf(ay,by)+0.00001: return true
		if (ay>py)!=(by>py) and px<ax+(py-ay)*dx/dy: inside=not inside
		a=b
	return inside
