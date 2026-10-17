extends RefCounted
## Sparse page lookup built once; no per-frame walk of detailed objects/pages.
var source: RefCounted
var grids: Dictionary={}
var roots: Array=[]
var requests: Array=[]
var revision:=0
var last: Dictionary={}
var stats: Dictionary={"catalog_builds":0,"bucket_visits":0,"plans":0}
func bind(loader: RefCounted) -> void:
	source=loader;grids={};roots=[];last={};revision+=1;stats.catalog_builds+=1
	for id in source.pages:
		var page: Dictionary=source.pages[id]
		if page.parent_id.is_empty():roots.append(id)
		var b: Array=page.bounds_m;var level: int=int(page.level)
		if not grids.has(level):grids[level]={"cell":float(b[2]),"buckets":{}}
		var grid: Dictionary=grids[level]
		for y in range(floori(b[1]/grid.cell),ceili((b[1]+b[3])/grid.cell)):
			for x in range(floori(b[0]/grid.cell),ceili((b[0]+b[2])/grid.cell)):
				var key:=Vector2i(x,y)
				if not grid.buckets.has(key):grid.buckets[key]=[]
				grid.buckets[key].append(id)
func intersecting(level: int,view: Rect2) -> Array:
	var found: Array=[];var seen: Dictionary={}
	if not grids.has(level):return found
	var grid: Dictionary=grids[level];var cell: float=grid.cell
	for y in range(floori(view.position.y/cell),ceili(view.end.y/cell)):
		for x in range(floori(view.position.x/cell),ceili(view.end.x/cell)):
			stats.bucket_visits+=1
			for id in grid.buckets.get(Vector2i(x,y),[]):
				var b: Array=source.pages[id].bounds_m
				if not seen.has(id) and Rect2(b[0],b[1],b[2],b[3]).intersects(view):found.append(id);seen[id]=true
	return found
func plan(view: Rect2,zoom: float,prefetch: bool=true) -> Dictionary:
	var levels: Array=grids.keys();levels.sort();var level: int=int(levels[0])
	for candidate in levels:
		var cell: float=grids[candidate].cell
		if cell*zoom>=180:level=int(candidate)
	# Large views select coarser coverage rather than asking for every fine page.
	while level>int(levels[0]) and view.size.x/grids[level].cell*view.size.y/grids[level].cell>48:level-=1
	var visible: Array=intersecting(level,view);var demands: Dictionary={}
	for root in roots:
		var b: Array=source.pages[root].bounds_m
		if Rect2(b[0],b[1],b[2],b[3]).intersects(view):demands[root]=0
	for id in visible:
		demands[id]=2;var parent: String=source.pages[id].parent_id
		while not parent.is_empty():demands[parent]=0 if source.pages[parent].parent_id.is_empty() else 1;parent=source.pages[parent].parent_id
	if prefetch:
		var cell: float=grids[level].cell;var added:=0
		for id in intersecting(level,view.grow(cell)):
			if not demands.has(id):demands[id]=3;added+=1
			if added>=4:break
	requests=visible;last={"demands":demands,"visible":visible,"level":level,"view":[view.position.x,view.position.y,view.size.x,view.size.y]};stats.plans+=1;return last
func resolve(id: String,manager: RefCounted) -> Dictionary:
	var cursor:=id;var errors: Array=[]
	while not cursor.is_empty():
		var page: Dictionary=source.pages[cursor]
		if page.build_id!=source.manifest.build_id:return {"ok":false,"code":"page_build_mismatch","requested":id,"selected":""}
		if manager.ready(cursor):return {"ok":true,"detail_ok":cursor==id,"requested":id,"selected":cursor,"failures":errors}
		if manager.page_states.get(cursor)=="FAILED":errors.append(cursor)
		cursor=page.parent_id
	return {"ok":false,"code":"coverage_pending","requested":id,"selected":"","failures":errors}
