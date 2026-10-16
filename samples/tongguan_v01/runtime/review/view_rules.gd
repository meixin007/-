extends RefCounted
# Pure display calculations. No reference to Session, clock or pathfinding.
func gate_alpha(zoom: float)->float:
	return smoothstep(0.16,0.30,zoom)
func gate_rect(site: Vector2,zoom: float,policy: Dictionary)->Rect2:
	var gate: Dictionary=policy.gate
	var width=lerpf(float(gate.far_width_px),float(gate.near_width_px),smoothstep(0.18,1.1,zoom))
	var dims=Vector2(width,width*float(gate.image_size_px[1])/float(gate.image_size_px[0]))
	var anchor=Vector2(float(gate.anchor_px[0])/float(gate.image_size_px[0]),float(gate.anchor_px[1])/float(gate.image_size_px[1]))
	return Rect2(site-dims*anchor,dims)
func socket(rect: Rect2,pixels: Array,policy: Dictionary)->Vector2:
	return rect.position+rect.size*Vector2(float(pixels[0])/float(policy.gate.image_size_px[0]),float(pixels[1])/float(policy.gate.image_size_px[1]))
func place_labels(candidates: Array,viewport: Rect2)->Array:
	var ordered=candidates.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.priority)>int(b.priority))
	var results=[];var used: Array[Rect2]=[]
	for candidate in ordered:
		var rect=Rect2(candidate.at,candidate.size)
		if not viewport.encloses(rect):continue
		var collides=false
		for other in used:
			if rect.grow(5).intersects(other):collides=true;break
		if not collides:results.append(candidate);used.append(rect)
	return results
