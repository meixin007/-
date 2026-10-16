@tool
extends RefCounted
## Rebuildable broad phase; exact geometry remains the final authority.
const CELL := 256.0
var cells: Dictionary = {}
var rectangles: Array[Rect2] = []
var oversized: Array[int] = []
func build(bounds: Array) -> void:
	cells.clear(); oversized.clear(); rectangles.assign(bounds)
	for i in range(rectangles.size()):
		var r := rectangles[i]
		var first: Vector2i=Vector2i((r.position/CELL).floor())
		var last: Vector2i=Vector2i((r.end/CELL).floor())
		# Long edges and large ground art must not allocate a national grid
		# per object. Query these few broad bounds directly instead.
		if (last.x-first.x+1)*(last.y-first.y+1)>256:
			oversized.append(i)
			continue
		for y in range(int(floor(r.position.y/CELL)),int(floor(r.end.y/CELL))+1):
			for x in range(int(floor(r.position.x/CELL)),int(floor(r.end.x/CELL))+1):
				var key := Vector2i(x,y)
				if not cells.has(key): cells[key]=[]
				cells[key].append(i)
func query(rect: Rect2) -> Array:
	if rect.get_area() > CELL*CELL*256:
		var result: Array=[]
		for i in range(rectangles.size()):
			if rectangles[i].intersects(rect,true): result.append(i)
		return result
	var found: Dictionary = {}
	for i in oversized:
		if rectangles[i].intersects(rect,true): found[i]=true
	for y in range(int(floor(rect.position.y/CELL)),int(floor(rect.end.y/CELL))+1):
		for x in range(int(floor(rect.position.x/CELL)),int(floor(rect.end.x/CELL))+1):
			for i in cells.get(Vector2i(x,y),[]):
				if rectangles[i].intersects(rect,true): found[i]=true
	var result:=found.keys()
	result.sort()
	return result
