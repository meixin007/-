extends RefCounted
## Fixed-layout projected width; independent of texture-page LOD and icon size.
var thresholds: Array=[32.0,128.0,384.0]
var hysteresis:=.15
func choose(current: int,zoom: float,width_m: float) -> int:
	var pixels:=zoom*width_m;var result:=clampi(current,0,3)
	while result<3 and pixels>float(thresholds[result])*(1+hysteresis):result+=1
	while result>0 and pixels<float(thresholds[result-1])*(1-hysteresis):result-=1
	return result
func labels(rows: Array,view: Rect2,zoom: float,viewport: Vector2,selected: String,target: String="") -> Array:
	var candidates: Array=[]
	for row in rows:
		var p:=Vector2(row.position_m[0],row.position_m[1])
		if view.has_point(p):candidates.append(row)
	candidates.sort_custom(func(a,b):
		var pa: int=3 if a.site_id==selected else (2 if a.site_id==target else 0)
		var pb: int=3 if b.site_id==selected else (2 if b.site_id==target else 0)
		if pa!=pb:return pa>pb
		if a.get("importance",0)!=b.get("importance",0):return a.get("importance",0)>b.get("importance",0)
		return a.site_id<b.site_id)
	var result: Array=[]
	for row in candidates:
		var screen: Vector2=(Vector2(row.position_m[0],row.position_m[1])-view.position)*zoom
		var extent:=Vector2(clampf(row.label.length()*17+14,48,260),27)
		var box:=Rect2(screen+Vector2(12,-31),extent)
		box.position=box.position.clamp(Vector2.ZERO,(viewport-extent).max(Vector2.ZERO))
		var overlaps:=false
		for old in result:
			if box.grow(3).intersects(old.rect):overlaps=true;break
		if not overlaps:result.append({"site_id":row.site_id,"text":row.label,"rect":box,"selected":row.site_id==selected})
		if result.size()>=64:break
	return result
