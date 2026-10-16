@tool
extends RefCounted
## Least-squares similarity transform. Input coordinates must share a declared map frame.
static func fit(source: Array, target: Array, image_size: Vector2i) -> Dictionary:
	if source.size() != target.size() or source.size() < 2 or source.size() > 64 or image_size.x <= 0 or image_size.y <= 0: return {"ok":false,"error":"需要 2–64 对控制点和有效图片原始尺寸。"}
	var s := Vector2.ZERO
	var t := Vector2.ZERO
	for i in range(source.size()):
		for point in [source[i],target[i]]:
			if not point is Array or point.size() != 2: return {"ok":false,"error":"控制点必须是 [x,y]。"}
			for number in point:
				if not (number is float or number is int) or not is_finite(float(number)): return {"ok":false,"error":"控制点必须是有限数值。"}
		if source[i][0] < 0 or source[i][1] < 0 or source[i][0] > image_size.x or source[i][1] > image_size.y: return {"ok":false,"error":"原图控制点超出图片边界。"}
		s += Vector2(source[i][0],source[i][1])
		t += Vector2(target[i][0],target[i][1])
	s /= source.size()
	t /= target.size()
	var denominator := 0.0
	var a := 0.0
	var b := 0.0
	for i in range(source.size()):
		var p := Vector2(source[i][0],source[i][1])-s
		var q := Vector2(target[i][0],target[i][1])-t
		denominator += p.length_squared()
		a += p.dot(q)
		b += p.cross(q)
	if denominator < 0.00001: return {"ok":false,"error":"原图控制点重合，无法校准。"}
	a /= denominator
	b /= denominator
	var scale := Vector2(a,b).length()
	if scale < 0.00001: return {"ok":false,"error":"地图控制点重合，无法校准。"}
	var angle := atan2(b,a)
	var translation := t-s.rotated(angle)*scale
	var extent := Vector2(image_size)*scale
	var position := translation+(Vector2(image_size)*0.5).rotated(angle)*scale-extent*0.5
	var sum := 0.0
	var largest := 0.0
	for i in range(source.size()):
		var predicted := Vector2(source[i][0],source[i][1]).rotated(angle)*scale+translation
		var error := predicted.distance_to(Vector2(target[i][0],target[i][1]))
		sum += error*error
		largest = maxf(largest,error)
	return {"ok":true,"position":[position.x,position.y],"size":[extent.x,extent.y],"rotation":rad_to_deg(angle),"rms":sqrt(sum/source.size()),"max_error":largest,"source_points":source.duplicate(true),"world_points":target.duplicate(true),"image_size":[image_size.x,image_size.y]}
