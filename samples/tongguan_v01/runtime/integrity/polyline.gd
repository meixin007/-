extends RefCounted
## Display projection of native daily corridor progress; stores no movement state.
static func points(value: Array)->PackedVector2Array:
	var result=PackedVector2Array()
	for p in value:result.append(Vector2(p[0],p[1]))
	return result
static func length(value: PackedVector2Array)->float:
	var total:=0.0
	for i in range(value.size()-1):total+=value[i].distance_to(value[i+1])
	return total
static func sample(value: PackedVector2Array,ratio: float)->Vector2:
	if value.is_empty():return Vector2.ZERO
	var target=clampf(ratio,0,1)*length(value)
	for i in range(value.size()-1):
		var segment=value[i].distance_to(value[i+1])
		if target<=segment:return value[i].lerp(value[i+1],target/maxf(segment,0.00001))
		target-=segment
	return value[-1]
static func section(value: PackedVector2Array,start: float,end: float)->Array:
	var result=[];var first=sample(value,start);result.append([first.x,first.y]);var total=length(value);var distance:=0.0
	for i in range(value.size()-1):
		distance+=value[i].distance_to(value[i+1]);var ratio=distance/maxf(total,0.00001)
		if ratio>start and ratio<end:result.append([value[i+1].x,value[i+1].y])
	var last=sample(value,end);result.append([last.x,last.y]);return result
