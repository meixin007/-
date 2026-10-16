@tool
extends RefCounted
## Same double-precision inclusive test as polygon_math, indexed by edge Y.
## Reuse for repeated points; no simplification or tolerance change.
const EPS := .00001
var origin := Vector2.ZERO
var ring := PackedVector2Array()
var buckets: Array = []
var low := 0.0
var step := 1.0
var bounds := Rect2()
var holes_index: RefCounted
func prepare(points: PackedVector2Array) -> void:
	ring=points.duplicate();buckets.clear();holes_index=null
	if ring.is_empty(): return
	origin=ring[0]
	for i in ring.size(): ring[i]-=origin
	bounds=Rect2(ring[0],Vector2.ZERO)
	for p in ring: bounds=bounds.expand(p)
	low=bounds.position.y-EPS*2
	var bucket_count:=clampi(ring.size()/4,16,512)
	step=maxf(.0001,(bounds.size.y+EPS*4)/float(bucket_count))
	for i in bucket_count: buckets.append([])
	for i in ring.size():
		var a:=ring[i-1];var b:=ring[i]
		var first:=clampi(floori((minf(a.y,b.y)-EPS-low)/step),0,buckets.size()-1)
		var last:=clampi(floori((maxf(a.y,b.y)+EPS-low)/step),0,buckets.size()-1)
		for slot in range(first,last+1): buckets[slot].append(i)
func contains(world_point: Vector2) -> bool:
	if ring.size()<3: return false
	var point:=world_point-origin
	# Rect2 stores float32 endpoints; use a conservative broad-phase pad so
	# rounded maximum edges still reach the inclusive exact predicate below.
	if not bounds.grow(.1).has_point(point):return false
	var px: float=point.x;var py: float=point.y;var inside:=false
	for i in buckets[clampi(floori((py-low)/step),0,buckets.size()-1)]:
		var a:=ring[i-1];var b:=ring[i]
		var ax: float=a.x;var ay: float=a.y;var bx: float=b.x;var by: float=b.y
		var dx: float=bx-ax;var dy: float=by-ay
		var cross: float=dx*(py-ay)-dy*(px-ax)
		if absf(cross)<=EPS*maxf(1.0,absf(dx)+absf(dy)) and px>=minf(ax,bx)-EPS and px<=maxf(ax,bx)+EPS and py>=minf(ay,by)-EPS and py<=maxf(ay,by)+EPS: return true
		if (ay>py)!=(by>py) and px<ax+(py-ay)*dx/dy: inside=not inside
	return inside
