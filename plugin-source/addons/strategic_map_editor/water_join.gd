@tool
extends RefCounted
## Hide only internal shorelines at junctions involving hand-edited water.
const G=preload("geometry_ops.gd")
const R=preload("art_ribbon.gd")
const W=preload("water_brush.gd")
const Natural=preload("natural_water.gd")
var revision := -1
var waters: Array=[]
var ordered: Array=[]
var shapes: Dictionary={}
var bounds: Dictionary={}
var runs_cache: Dictionary={}
var profiles: Dictionary={}
var connections: Dictionary={}
var containment: Dictionary={}
var previous_waters: Dictionary={}
var mask_cache: Dictionary={}

func prepare(features: Array, current_revision: int) -> void:
	if revision==current_revision: return
	revision=current_revision
	var old_bounds:=bounds.duplicate()
	bounds.clear()
	waters=features.filter(func(f):return f.kind=="water" and W.visible(f))
	var edited: Array=[]
	var next_waters: Dictionary={}
	var changed_areas: Array[Rect2]=[]
	for f in waters:
		bounds[f.id]=W.bounds(G.packed(f.points))
		var clip:=W.crop(f)
		if clip.has_area(): bounds[f.id]=bounds[f.id].intersection(clip)
		next_waters[f.id]=f
		if previous_waters.get(f.id,{})!=f:
			changed_areas.append(bounds[f.id].merge(old_bounds.get(f.id,bounds[f.id])).grow(1024))
		if natural(f) or f.get("visual",{}).get("water_brush",false): edited.append(f)
	for id in previous_waters:
		if not next_waters.has(id): changed_areas.append(old_bounds[id].grow(1024))
	# Keep remote river unions and shoreline clips across local strokes and art moves.
	var affected_ids: Dictionary={}
	for id in previous_waters.keys()+next_waters.keys():
		var box: Rect2=bounds.get(id,old_bounds.get(id,Rect2()))
		if not next_waters.has(id) or changed_areas.any(func(area):return area.intersects(box,true)):
			affected_ids[id]=true
			shapes.erase(id);profiles.erase(id);containment.erase(id);mask_cache.erase(id)
			connections.erase([id,0]);connections.erase([id,1])
	for key in runs_cache.keys():
		if affected_ids.has(key[0]) or changed_areas.any(func(area):return area.intersects(W.bounds(key[1]),true)): runs_cache.erase(key)
	# Old edited coastline polylines carry distinct keys; cap their history.
	if runs_cache.size()>2048: runs_cache.clear()
	previous_waters=next_waters.duplicate(true)
	var last: Array=[]
	for f in waters:
		if W.is_river(f): continue
		for changed in edited:
			if bounds[f.id].intersects(bounds[changed.id],true): last.append(f); break
	ordered=features.filter(func(f):return not f in last)+last

func shape(f: Dictionary) -> Dictionary:
	if shapes.has(f.id): return shapes[f.id].shape
	var result: Dictionary={"points":f.points,"holes":f.holes}
	if natural(f):
		var built:=surface(f)
		if not built.is_empty(): return built[0]
	if W.is_river(f):
		var samples: Array=R.sample(f.visual.ribbon.points,f.visual.ribbon.widths)
		var banks:=R.inked_banks(samples,f.id)
		if f.visual.ribbon.get("render_style","soft")=="soft":
			for i in range(samples.size()):
				var normal: Vector2=(samples[mini(i+1,samples.size()-1)].position-samples[maxi(i-1,0)].position).normalized().orthogonal()
				banks.left[i]=samples[i].position+normal*samples[i].width*.5
				banks.right[i]=samples[i].position-normal*samples[i].width*.5
		var polygon: PackedVector2Array=banks.left.duplicate()
		var reverse: PackedVector2Array=banks.right.duplicate(); reverse.reverse()
		append_cap(polygon,samples[-1].position,banks.left[-1],banks.right[-1],(samples[-1].position-samples[-2].position).normalized())
		polygon.append_array(reverse)
		append_cap(polygon,samples[0].position,banks.right[0],banks.left[0],(samples[0].position-samples[1].position).normalized())
		result={"points":G.unpack(polygon),"holes":[]}
	shapes[f.id]={"signature":f.duplicate(true),"shape":result}
	return result

func natural(f: Dictionary) -> bool:
	return f.kind=="water" and f.get("visual",{}).has("ribbon") and (f.visual.get("water_brush",false) or f.visual.ribbon.has("end_styles"))

func profile(f: Dictionary) -> Dictionary:
	if not profiles.has(f.id): profiles[f.id]=W.sampled(W.ribbon(f))
	return profiles[f.id]

func endpoint_connected(f: Dictionary,end: int) -> bool:
	return endpoint_connection(f,end).connected

func endpoint_connection(f: Dictionary,end: int) -> Dictionary:
	var key: Array=[f.id,end]
	if connections.has(key):return connections[key]
	var data:=profile(f)
	var point: Vector2=data.points[0 if end==0 else -1]
	var own_width: float=data.widths[0 if end==0 else -1]
	var outward: Vector2=(point-data.points[1 if end==0 else -2]).normalized()
	var result: Dictionary={"connected":false,"extension":Vector2.INF}
	for other in waters:
		if other.id==f.id or not bounds[other.id].grow(own_width*.58+2).has_point(point): continue
		var clip:=W.crop(other)
		if clip.has_area() and not clip.has_point(point): continue
		if not W.is_river(other):
			var inside:=_contains(other,point)
			var nearest: Dictionary={"distance":INF,"point":point}
			for ring in [other.points]+other.holes:
				var shore:=G.packed(ring);shore.append(shore[0])
				var match:=W.closest(shore,point)
				if match.distance<nearest.distance:nearest=match
			if not inside and (nearest.distance>own_width*.58+2 or not _contains(f,nearest.point)): continue
			var inward: Vector2=(point-nearest.point).normalized() if inside else (nearest.point-point).normalized()
			if inward.is_zero_approx():inward=outward
			var extension: Vector2=point
			if nearest.distance<own_width*.75 or not inside:
				# Continue the river's direction through the shore first. Moving only
				# along the shore normal can leave a round elbow on the land side.
				var alignment:=outward.dot(inward)
				var along:=minf(own_width*3.0,(own_width*.75+(0.0 if inside else nearest.distance))/maxf(.2,alignment))
				var straight: Vector2=point+outward*along
				if alignment>.15 and _submerged_cap(other,straight,own_width*.52):
					extension=straight
				for depth in [own_width*.75,own_width*.5,own_width*.25,1.0]:
					if extension!=point:break
					var candidate: Vector2=nearest.point+inward*depth
					if _contains(other,candidate):extension=candidate;break
			result={"connected":true,"extension":extension}
			break
		else:
			var receiving:=profile(other)
			var match:=W.closest(receiving.points,point)
			var width:=lerpf(receiving.widths[match.index],receiving.widths[match.index+1],match.t)
			if match.distance<=width*.5+own_width*.5:
				result={"connected":true,"extension":match.point if match.distance>width*.25 else Vector2.INF}
				break
	connections[key]=result
	return result

func _contains(f: Dictionary, point: Vector2) -> bool:
	if not containment.has(f.id): containment[f.id]=G.prepare_containment(f)
	return G.contains_prepared(containment[f.id],point)

func _submerged_cap(water: Dictionary,center: Vector2,radius: float) -> bool:
	if not _contains(water,center):return false
	for i in range(12):
		if not _contains(water,center+Vector2.from_angle(TAU*i/12.0)*radius):return false
	return true

func surface(f: Dictionary) -> Array:
	if not natural(f): return [shape(f)]
	if not shapes.has(f.id):
		var start:=endpoint_connection(f,0);var finish:=endpoint_connection(f,1)
		var built:=Natural.build(f.visual.ribbon,[start.connected,finish.connected],[start.extension,finish.extension])
		if built.shapes.is_empty():
			push_error("无法生成河流显示轮廓，保留原水域轮廓："+str(f.id))
			built.shapes=[{"points":f.points,"holes":f.holes}]
		shapes[f.id]={"signature":f.duplicate(true),"surface":built.shapes,"shape":built.shapes[0]}
	return shapes[f.id].surface

func append_cap(polygon: PackedVector2Array, center: Vector2, first: Vector2, last: Vector2, outward: Vector2) -> void:
	var angle: float=(first-center).angle()
	var direction:=1.0 if Vector2.from_angle(angle+PI*.5).dot(outward)>0 else -1.0
	for i in range(1,12):
		var t:=i/12.0
		polygon.append(center+Vector2.from_angle(angle+direction*PI*t)*lerpf(center.distance_to(first),center.distance_to(last),t))

func affected(f: Dictionary) -> bool:
	if f.get("visual",{}).get("water_brush",false): return true
	for other in waters:
		if other.id!=f.id and other.get("visual",{}).get("water_brush",false) and bounds.get(f.id,Rect2()).intersects(bounds[other.id],true): return true
	return false

func runs(f: Dictionary, line: PackedVector2Array,coast: bool=false) -> Array:
	var key: Array=[f.id,line,coast]
	if runs_cache.has(key): return runs_cache[key]
	var result: Array=[line]
	var box:=W.bounds(line).grow(.1)
	for other in waters:
		if other.id==f.id or not bounds[other.id].intersects(box,true): continue
		if coast and not natural(other): continue
		if not coast and not natural(f) and not natural(other) and not f.get("visual",{}).get("water_brush",false) and not other.get("visual",{}).get("water_brush",false): continue
		for mask in _masks(other):
			var origin:=line[0]
			var polygon: PackedVector2Array=mask.points.duplicate()
			for i in range(polygon.size()): polygon[i]-=origin
			var polygons: Array=[polygon]
			var clip:=W.crop(other)
			if clip.has_area(): polygons=Geometry2D.intersect_polygons(polygon,PackedVector2Array([clip.position-origin,Vector2(clip.end.x,clip.position.y)-origin,clip.end-origin,Vector2(clip.position.x,clip.end.y)-origin]))
			for piece in polygons:
				var remaining: Array=[]
				for run in result:
					var local: PackedVector2Array=run.duplicate()
					for i in range(local.size()): local[i]-=origin
					var clipped: Array=Geometry2D.clip_polyline_with_polygon(local,piece)
					for hole in mask.holes:
						# National seas have hundreds of islands. Only holes touching
						# this shoreline can restore a visible part of the clipped run.
						if not hole.bounds.intersects(box,true):continue
						var inner: PackedVector2Array=hole.points.duplicate()
						for i in range(inner.size()): inner[i]-=origin
						# Valid shape holes are already contained by their outer ring.
						# Intersect again only when an explicit crop split that ring.
						var visible_holes: Array=Geometry2D.intersect_polygons(inner,piece) if clip.has_area() else [inner]
						for visible_hole in visible_holes:
							clipped.append_array(Geometry2D.intersect_polyline_with_polygon(local,visible_hole))
					for part in clipped:
						for i in range(part.size()): part[i]+=origin
						if part.size()>1: remaining.append(part)
				result=remaining
	runs_cache[key]=result
	return result

func _masks(f: Dictionary) -> Array:
	if not mask_cache.has(f.id):
		var result: Array=[]
		for shape in surface(f):
			var holes: Array=[]
			for ring in shape.holes:
				var points:=G.packed(ring)
				holes.append({"points":points,"bounds":W.bounds(points).grow(.1)})
			result.append({"points":G.packed(shape.points),"holes":holes})
		mask_cache[f.id]=result
	return mask_cache[f.id]
