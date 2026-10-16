@tool
extends RefCounted
## Editable water geometry. All mutations are returned for one document transaction.
const G = preload("geometry_ops.gd")
const R = preload("art_ribbon.gd")
const Boolean = preload("polygon_boolean.gd")
const TOOLS := ["river_draw","river_erase","river_move","river_width","lake_paint","lake_erase"]

static func fail(text: String) -> Dictionary:
	return {"ok":false,"error":text,"ids":[]}

static func is_river(f: Dictionary) -> bool:
	return f.get("kind") == "river" or (f.get("kind") == "water" and f.get("visual",{}).has("ribbon"))

static func visible(f: Dictionary) -> bool:
	return f.get("visual",{}).get("visible",true) and not f.get("visual",{}).get("auxiliary",false)

static func bounds(line: PackedVector2Array) -> Rect2:
	if line.is_empty(): return Rect2()
	var box:=Rect2(line[0],Vector2.ZERO)
	for p in line: box=box.expand(p)
	return box

static func crop(f: Dictionary) -> Rect2:
	var value: Array=f.get("visual",{}).get("ribbon_clip_rect",[])
	return Rect2(value[0],value[1],value[2],value[3]) if value.size()==4 else Rect2()

static func visible_lines(f: Dictionary) -> Array:
	var line: PackedVector2Array=sampled(ribbon(f)).points
	var rect:=crop(f)
	if not rect.has_area(): return [line]
	return Geometry2D.intersect_polyline_with_polygon(line,PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))

static func ribbon(f: Dictionary) -> Dictionary:
	if f.get("visual",{}).has("ribbon"): return f.visual.ribbon.duplicate(true)
	var widths: Array = []
	for p in f.points: widths.append(clampf(f.width,6,128))
	return {"points":f.points.duplicate(true),"widths":widths,"render_style":"inked_brush"}

static func closest(line: PackedVector2Array, p: Vector2) -> Dictionary:
	var result := {"distance":INF,"point":p,"index":0,"t":0.0}
	for i in range(line.size()-1):
		var q := Geometry2D.get_closest_point_to_segment(p,line[i],line[i+1])
		var distance := p.distance_to(q)
		if distance < result.distance:
			result = {"distance":distance,"point":q,"index":i,"t":line[i].distance_to(q)/maxf(.001,line[i].distance_to(line[i+1]))}
	return result

static func sampled(r: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
	var widths: Array = []
	for sample in R.sample(r.points,r.widths):
		if not points.is_empty() and points[-1].distance_to(sample.position)<.01: continue
		points.append(sample.position); widths.append(sample.width)
	return {"points":points,"widths":widths}

static func dense(r: Dictionary, spacing: float) -> Dictionary:
	var base:=sampled(r)
	var length:=0.0
	for i in range(base.points.size()-1): length+=base.points[i].distance_to(base.points[i+1])
	spacing=maxf(spacing,length/2048.0)
	var points:=PackedVector2Array(); var widths: Array=[]
	for i in range(base.points.size()-1):
		var count:=maxi(1,ceili(base.points[i].distance_to(base.points[i+1])/spacing))
		for j in range(count):
			var t:=float(j)/count
			points.append(base.points[i].lerp(base.points[i+1],t))
			widths.append(lerpf(base.widths[i],base.widths[i+1],t))
	points.append(base.points[-1]); widths.append(base.widths[-1])
	return {"points":points,"widths":widths}

static func hit(features: Array, point: Vector2, radius: float) -> String:
	var best := radius
	var id := ""
	for f in features:
		if not is_river(f) or not visible(f): continue
		if not bounds(G.packed(f.points)).grow(radius+128).has_point(point): continue
		var r := ribbon(f)
		for path in visible_lines(f):
			var match := closest(path,point)
			var distance: float = maxf(0,match.distance-float(r.widths.max())*.5)
			if distance < best: best=distance; id=f.id
	return id

static func envelope(line: PackedVector2Array, radius: float) -> Array:
	if line.is_empty(): return []
	var origin := line[0]
	var local := PackedVector2Array()
	for p in line: local.append(p-origin)
	if local.size()==1: local.append(Vector2(.01,0))
	var rings: Array = []
	for polygon in Geometry2D.offset_polyline(local,radius,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
		for i in range(polygon.size()): polygon[i]+=origin
		# Translation to a large map can collapse nearby Clipper vertices.
		rings.append(Boolean.simplify(polygon,.02))
	return rings

static func simplified(doc, line: PackedVector2Array, tolerance: float = 1.0) -> PackedVector2Array:
	var result: PackedVector2Array = doc.simplify_stroke(line,tolerance)
	while result.size()>128:
		tolerance*=1.6
		result=doc.simplify_stroke(line,tolerance)
	return result

static func make_river(doc, old: Dictionary, line: PackedVector2Array, widths: Array) -> Dictionary:
	if line.size()<2 or widths.size()!=line.size(): return {}
	var tolerance:=.5
	var indices:=profile_indices(line,widths,tolerance)
	while indices.size()>128:
		tolerance*=1.6
		indices=profile_indices(line,widths,tolerance)
	var reduced:=PackedVector2Array()
	var kept_widths: Array = []
	for i in indices:
		reduced.append(line[i]); kept_widths.append(widths[i])
	var f: Dictionary = old.duplicate(true)
	f.kind="water"; f.layer="water"
	if not f.has("visual"): f.visual={}
	f.visual.water_brush=true
	f.visual.ribbon={"points":G.unpack(reduced),"widths":kept_widths,"render_style":old.get("visual",{}).get("ribbon",{}).get("render_style","inked_brush")}
	if old.get("visual",{}).get("ribbon",{}).has("end_styles"):
		f.visual.ribbon.end_styles=old.visual.ribbon.end_styles.duplicate()
	var full := sampled(f.visual.ribbon)
	var rings := envelope(full.points,float(kept_widths.max())*.58+2)
	if rings.is_empty(): return {}
	var classified := Boolean.classify(rings,.00001)
	if not classified.ok or classified.shapes.size()!=1: return {}
	f.points=classified.shapes[0].points
	f.holes=classified.shapes[0].holes
	return f

static func profile_indices(line: PackedVector2Array, widths: Array, tolerance: float) -> Array:
	var keep: Array=[0,line.size()-1]
	var pending: Array=[[0,line.size()-1]]
	while not pending.is_empty():
		var pair: Array=pending.pop_back()
		var a: int=pair[0]; var b: int=pair[1]
		var best:=tolerance; var at:=-1
		for i in range(a+1,b):
			var q:=Geometry2D.get_closest_point_to_segment(line[i],line[a],line[b])
			var t:=clampf(line[a].distance_to(q)/maxf(.001,line[a].distance_to(line[b])),0,1)
			var error:=maxf(line[i].distance_to(q),absf(widths[i]-lerpf(widths[a],widths[b],t)))
			if error>best: best=error; at=i
		if at>=0:
			keep.append(at); pending.append([a,at]); pending.append([at,b])
	keep.sort()
	return keep

static func new_id() -> String:
	return "water_brush_%s_%s" % [Time.get_ticks_usec(),randi()]

static func connect_profile(features: Array,line: PackedVector2Array,width: float,snap_distance: float) -> Dictionary:
	var widths: Array=[]
	for p in line: widths.append(width)
	var connected:=false
	for end in range(2):
		if end==1: line.reverse();widths.reverse()
		var best:=snap_distance
		var connection: Dictionary={}
		for f in features:
			if not is_river(f) or not visible(f): continue
			var data:=sampled(ribbon(f))
			for path in visible_lines(f):
				var match:=closest(path,line[0])
				if match.distance>=best: continue
				best=match.distance
				var source:=closest(data.points,match.point)
				var w:=lerpf(data.widths[source.index],data.widths[source.index+1],source.t)
				var tangent: Vector2=(data.points[source.index+1]-data.points[source.index]).normalized()
				var direction: Vector2=(line[1]-match.point).normalized()
				if tangent.dot(direction)<0: tangent=-tangent
				var near_end: bool=match.point.distance_to(data.points[0])<w or match.point.distance_to(data.points[-1])<w
				var continuation: bool=near_end and tangent.dot(direction)>.5
				connection={"point":match.point,"width":w if continuation else minf(width,w),"tangent":tangent if continuation else (direction*.7+tangent*.3).normalized()}
		if not connection.is_empty():
			connected=true;line[0]=connection.point
			var full:=dense({"points":G.unpack(line),"widths":widths},maxf(2,width*.25))
			line=full.points;widths=full.widths
			var distances: Array=[0.0]
			for i in range(1,line.size()): distances.append(distances[-1]+line[i].distance_to(line[i-1]))
			var span:=minf(maxf(width,connection.width)*3.0,distances[-1]*.4)
			var at:=1
			while at<line.size()-1 and distances[at]<span: at+=1
			span=distances[at]
			var finish: Vector2=line[at]
			var exit_tangent: Vector2=(line[mini(at+1,line.size()-1)]-line[at-1]).normalized()
			var handle:=line[0].distance_to(finish)
			for i in range(at):
				var t: float=distances[i]/maxf(.001,span)
				line[i]=(2*t*t*t-3*t*t+1)*connection.point+(t*t*t-2*t*t+t)*connection.tangent*handle+(-2*t*t*t+3*t*t)*finish+(t*t*t-t*t)*exit_tangent*handle
				widths[i]=lerpf(connection.width,widths[i],smoothstep(0,1,t))
		if end==1: line.reverse();widths.reverse()
	return {"points":line,"widths":widths,"connected":connected}

static func apply(doc, tool: String, stroke: Array, width: float, radius: float, target: String = "", snap_distance: float = 16.0, whole: bool = false, end_styles: Array=["auto","auto"]) -> Dictionary:
	if tool not in TOOLS or stroke.is_empty() or stroke.size()>4096: return fail("请选择水系工具并在地图内画一笔。")
	if not is_finite(width) or width<6 or width>128 or not is_finite(radius) or radius<1 or radius>2048 or not is_finite(snap_distance) or snap_distance<0: return fail("河宽或笔刷范围无效。")
	if end_styles.size()!=2: return fail("起笔与收笔各需要一种端点样式。")
	for style in end_styles:
		if style not in preload("natural_water.gd").END_STYLES: return fail("河流端点样式无效。")
	if doc.layer("water").locked or not doc.layer("water").visible: return fail("河流水域图层已锁定或隐藏。")
	for p in stroke:
		if not doc._point(p) or p[0]<0 or p[1]<0 or p[0]>doc.data.canvas_size[0] or p[1]>doc.data.canvas_size[1]: return fail("笔画超出画布；请在画布内绘制。")
	var line := G.packed(stroke)
	var next: Dictionary = doc.data.duplicate()
	next.features=doc.data.features.duplicate()
	var ids: Array = []
	var connected := false
	if tool=="river_draw":
		line=simplified(doc,line,maxf(.5,width*.05))
		if line.size()<2 or line[0].distance_to(line[-1])<1: return fail("请拖出一段河道。")
		var profile:=connect_profile(doc.data.features,line,width,snap_distance)
		line=profile.points;connected=profile.connected
		var widths: Array=profile.widths
		var fresh: Dictionary=doc.feature("water",[],"手绘河流",new_id())
		fresh.visual={"show_label":false,"ribbon":{"end_styles":end_styles.duplicate()}}
		var f:=make_river(doc,fresh,line,widths)
		if f.is_empty(): return fail("笔画过于曲折，无法形成有效河道；请分段绘制。")
		next.features.append(f); ids.append(f.id)
	elif tool in ["river_move","river_width"]:
		if target.is_empty(): target=hit(doc.data.features,line[0],radius)
		var old: Dictionary=doc.find_feature(target)
		if old.is_empty() or not is_river(old): return fail("请在河道上按住拖动。")
		if old.protected: return fail("这条河流已保护；本次没有修改。")
		var data:=dense(ribbon(old),maxf(1,radius*.2))
		var points: PackedVector2Array=data.points
		var widths: Array=data.widths
		var delta:=line[-1]-line[0]
		if tool=="river_move" and delta.length()<.01: return fail("没有移动河道；原地图保持不变。")
		for i in range(points.size()):
			var distance: float=points[i].distance_to(line[0]) if tool=="river_move" or line.size()==1 else closest(line,points[i]).distance
			var weight:=1.0 if whole else smoothstep(radius,0,distance)
			if tool=="river_move": points[i]+=delta*weight
			else: widths[i]=lerpf(widths[i],width,weight)
		var f:=make_river(doc,old,points,widths)
		if f.is_empty(): return fail("调整后河道无法闭合；请减小拖动距离。")
		for i in range(next.features.size()):
			if next.features[i].id==target: next.features[i]=f
		ids.append(target)
	elif tool=="river_erase":
		for old in doc.data.features:
			if not is_river(old) or not visible(old): continue
			if not bounds(G.packed(old.points)).grow(128).intersects(bounds(line).grow(radius),true): continue
			var clip:=crop(old)
			if clip.has_area() and not clip.intersects(bounds(line).grow(radius),true): continue
			var data:=sampled(ribbon(old))
			var cutters:=envelope(line,radius+float(data.widths.max())*.5)
			var classified:=Boolean.classify(cutters,.00001)
			if not classified.ok: return fail("橡皮笔画无法计算，请分段擦除。")
			var pieces: Array=[data.points]
			for shape in classified.shapes:
				var remaining: Array=[]
				for piece in pieces:
					remaining.append_array(Geometry2D.clip_polyline_with_polygon(piece,G.packed(shape.points)))
					for hole in shape.holes: remaining.append_array(Geometry2D.intersect_polyline_with_polygon(piece,G.packed(hole)))
				pieces=remaining
			if pieces.size()==1 and pieces[0]==data.points: continue
			if old.protected: return fail("笔画碰到受保护河流；整笔未应用。")
			next.features=next.features.filter(func(f):return f.id!=old.id)
			var ordinal:=0
			for piece in pieces:
				if piece.size()<2 or piece[0].distance_to(piece[-1])<1: continue
				var widths: Array=[]
				for p in piece:
					var match:=closest(data.points,p)
					widths.append(lerpf(data.widths[match.index],data.widths[match.index+1],match.t))
				var f:=make_river(doc,old,piece,widths)
				if f.is_empty(): return fail("擦除后的河段无效；原河道已保留。")
				if f.visual.ribbon.has("end_styles"):
					if piece[0].distance_to(data.points[0])>.1: f.visual.ribbon.end_styles[0]="auto"
					if piece[-1].distance_to(data.points[-1])>.1: f.visual.ribbon.end_styles[1]="auto"
				if ordinal>0: f.id=new_id(); f.name=old.name+" · 河段"+str(ordinal+1)
				next.features.append(f); ids.append(f.id); ordinal+=1
	else:
		var rings:=envelope(simplified(doc,line,maxf(1,radius*.06)),radius)
		if rings.is_empty(): return fail("没有有效湖泊笔画。")
		var classified:=Boolean.classify(rings,.00001)
		if not classified.ok or classified.shapes.size()!=1: return fail("湖泊笔画无法闭合，请分成较短笔画。")
		var brush: Dictionary=classified.shapes[0]
		var touched:=false
		for old in doc.data.features:
			if old.kind!="water" or is_river(old) or not visible(old): continue
			if Geometry2D.intersect_polygons(G.packed(old.points),G.packed(brush.points)).is_empty(): continue
			if old.protected: return fail("笔画碰到受保护水域；整笔未应用。")
			var result:=G.boolean_shapes(old,brush,"union" if tool=="lake_paint" else "subtract")
			if not result.ok:
				if tool=="lake_erase" and Geometry2D.clip_polygons(G.packed(old.points),G.packed(brush.points)).is_empty(): result={"ok":true,"shapes":[]}
				else: return fail(result.error)
			next.features=next.features.filter(func(f):return f.id!=old.id)
			var ordinal:=0
			for shape in result.shapes:
				var f: Dictionary=old.duplicate(true)
				f.points=shape.points; f.holes=shape.holes
				if not f.has("visual"): f.visual={}
				f.visual.water_brush=true
				if ordinal>0: f.id=new_id()
				next.features.append(f); ids.append(f.id); ordinal+=1
			touched=true
			if tool=="lake_paint": break
		if not touched and tool=="lake_paint":
			var f: Dictionary=doc.feature("water",brush.points,"手绘湖泊",new_id())
			f.holes=brush.holes; f.visual={"water_brush":true,"water_style":"inked","show_label":false}
			next.features.append(f); ids.append(f.id)
	var error: String=doc.validate(next)
	if not error.is_empty(): return fail(error+" 原地图保持不变。")
	if not doc._commit(next): return fail("笔画没有改变水面，或对象受到保护。")
	return {"ok":true,"ids":ids,"connected":connected}
