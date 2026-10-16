@tool
extends RefCounted
## Display geometry only. Authoring envelopes and traversal data stay untouched.
const R=preload("art_ribbon.gd")
const G=preload("geometry_ops.gd")
const B=preload("polygon_boolean.gd")
const END_STYLES=["auto","source","join","mouth"]

static func samples(ribbon: Dictionary, connected: Array=[false,false],extensions: Array=[]) -> Array:
	var base:=R.sample(ribbon.points,ribbon.widths)
	var styles: Array=ribbon.get("end_styles",["auto","auto"])
	if extensions.size()==2:
		if extensions[0].is_finite() and styles[0]!="source" and extensions[0].distance_to(base[0].position)>.01:
			base.push_front({"position":extensions[0],"width":base[0].width})
		if extensions[1].is_finite() and styles[1]!="source" and extensions[1].distance_to(base[-1].position)>.01:
			base.append({"position":extensions[1],"width":base[-1].width})
	var length:=0.0
	for i in range(base.size()-1): length+=base[i].position.distance_to(base[i+1].position)
	var spacing:=maxf(2.0,length/2048.0)
	var result: Array=[]
	var along:=0.0
	for i in range(base.size()-1):
		var distance: float=base[i].position.distance_to(base[i+1].position)
		if distance<.001: continue
		var count:=maxi(1,ceili(distance/maxf(spacing,minf(8.0,minf(base[i].width,base[i+1].width)*.35))))
		for j in range(count):
			var t:=float(j)/count
			result.append({"position":base[i].position.lerp(base[i+1].position,t),"width":lerpf(base[i].width,base[i+1].width,t),"along":along+distance*t})
		along+=distance
	result.append({"position":base[-1].position,"width":base[-1].width,"along":length})
	for end in range(2):
		if styles[end]!="source" and (styles[end]!="auto" or connected[end]): continue
		var width: float=ribbon.widths[0 if end==0 else -1]
		var transition:=minf(width*4.0,length*.4)
		for sample in result:
			var distance: float=sample.along if end==0 else length-sample.along
			sample.width*=lerpf(.06,1.0,smoothstep(0,maxf(.001,transition),distance))
	return result

static func build(ribbon: Dictionary, connected: Array=[false,false],extensions: Array=[]) -> Dictionary:
	var values:=samples(ribbon,connected,extensions)
	var origin: Vector2=values[0].position
	var outer:=PackedVector2Array()
	var holes: Array=[]
	# Union positive swept pieces. A single offset strip can fold over itself at
	# hairpins, creating negative-winding triangular holes through the channel.
	for i in range(values.size()-1):
		var a: Vector2=values[i].position-origin
		var b: Vector2=values[i+1].position-origin
		if a.distance_squared_to(b)<.000001: continue
		var tangent: Vector2=(b-a).normalized()
		var normal:=tangent.orthogonal()
		var ra: float=values[i].width*.5
		var rb: float=values[i+1].width*.5
		var piece:=PackedVector2Array([a+normal*ra,b+normal*rb])
		cap(piece,b,b+normal*rb,b-normal*rb,tangent)
		piece.append(b-normal*rb);piece.append(a-normal*ra)
		cap(piece,a,a-normal*ra,a+normal*ra,-tangent)
		if outer.is_empty(): outer=piece;continue
		var merged: Array=Geometry2D.merge_polygons(outer,piece)
		if merged.is_empty(): return {"shapes":[],"samples":values}
		merged.sort_custom(func(x,y):return absf(area(x))>absf(area(y)))
		outer=merged[0]
		var next_holes: Array=merged.slice(1)
		for hole in holes: next_holes.append_array(Geometry2D.clip_polygons(hole,piece))
		holes=next_holes
	var rings: Array=[outer]+holes
	var classified:=B.classify(rings,.00001)
	var shapes: Array=[]
	if classified.ok:
		for shape in classified.shapes:
			for ring in [shape.points]+shape.holes:
				for p in ring: p[0]+=origin.x;p[1]+=origin.y
			shapes.append(shape)
	return {"shapes":shapes,"samples":values}

static func area(polygon: PackedVector2Array) -> float:
	var result:=0.0
	for i in range(polygon.size()): result+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return result*.5

static func cap(polygon: PackedVector2Array,center: Vector2,first: Vector2,last: Vector2,outward: Vector2) -> void:
	var angle: float=(first-center).angle()
	var direction:=1.0 if Vector2.from_angle(angle+PI*.5).dot(outward)>0 else -1.0
	for i in range(1,12):
		var t:=i/12.0
		polygon.append(center+Vector2.from_angle(angle+direction*PI*t)*lerpf(center.distance_to(first),center.distance_to(last),t))
