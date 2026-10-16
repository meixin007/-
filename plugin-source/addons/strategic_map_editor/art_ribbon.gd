@tool
extends RefCounted
## Non-CK3 presentation carrier. Samples a visual water stroke; source polygon owns rules.

static func sample(points: Array, widths: Array, steps_per_segment: int = 8) -> Array:
	var result: Array = []
	if points.size() < 2 or widths.size() != points.size(): return result
	for i in range(points.size()-1):
		var p0 := Vector2(points[maxi(0,i-1)][0], points[maxi(0,i-1)][1])
		var p1 := Vector2(points[i][0], points[i][1])
		var p2 := Vector2(points[i+1][0], points[i+1][1])
		var p3 := Vector2(points[mini(points.size()-1,i+2)][0], points[mini(points.size()-1,i+2)][1])
		for step in range(steps_per_segment):
			var t := float(step)/steps_per_segment
			var t2 := t*t
			var t3 := t2*t
			var position := 0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t2+(-p0+3*p1-3*p2+p3)*t3)
			result.append({"position":position, "width":lerpf(float(widths[i]),float(widths[i+1]),t)})
	result.append({"position":Vector2(points[-1][0],points[-1][1]), "width":float(widths[-1])})
	return result

static func inked_banks(samples: Array, feature_id: String) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(samples.size()):
		var center: Vector2 = samples[i].position
		var before: Vector2 = samples[maxi(0,i-1)].position
		var after: Vector2 = samples[mini(samples.size()-1,i+1)].position
		var tangent := (after-before).normalized()
		var normal := tangent.orthogonal()
		var width: float = samples[i].width
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(feature_id, ":bank:", i))
		# The authoring contract checks both banks at 0.48 * width.
		# These uneven banks remain inside that envelope.
		left.append(center + normal * width * rng.randf_range(0.415,0.44))
		right.append(center - normal * width * rng.randf_range(0.415,0.44))
	return {"left":left,"right":right}

static func varied_marks(samples: Array, feature_id: String) -> Array:
	# Stable arc-length placement avoids the visible metronome made by one mark
	# every N spline samples. The caller clips each stroke to the source water.
	var marks: Array = []
	if samples.size() < 3: return marks
	var distances: Array[float] = [0.0]
	for i in range(1,samples.size()):
		distances.append(distances[-1] + samples[i].position.distance_to(samples[i-1].position))
	var total: float = distances[-1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(feature_id, ":varied-water-marks:v1"))
	var along := rng.randf_range(5.0,11.0)
	var segment := 0
	while along < total - 4.0 and marks.size() < 512:
		while segment + 1 < distances.size() - 1 and distances[segment+1] < along:
			segment += 1
		var span: float = maxf(0.001,distances[segment+1]-distances[segment])
		var t: float = clampf((along-distances[segment])/span,0,1)
		var center: Vector2 = samples[segment].position.lerp(samples[segment+1].position,t)
		var tangent: Vector2 = (samples[segment+1].position-samples[segment].position).normalized()
		var normal := tangent.orthogonal()
		var width: float = lerpf(float(samples[segment].width),float(samples[segment+1].width),t)
		var count := 2 if rng.randf() < .18 else 1
		for cluster in range(count):
			var local := center + tangent * (cluster * rng.randf_range(1.8,3.5))
			var lateral := rng.randf_range(-.24,.24) * width
			var start := local + normal*lateral
			var length := rng.randf_range(2.8,12.0)
			var end := start + tangent.rotated(rng.randf_range(-.16,.16))*length
			var middle := start.lerp(end,.48) + normal * rng.randf_range(-.45,.45)
			marks.append({"start":start,"middle":middle,"end":end,"opacity":rng.randf_range(.18,.48),"thickness":rng.randf_range(.35,.65),"along":along,"width":width})
		along += rng.randf_range(8.0,23.5)
	return marks

static func brush_marks(samples: Array, feature_id: String) -> Array:
	# A quieter water surface: sparse, uneven sweeps offset across the channel.
	# All placement is deterministic and clipped to the source polygon by the caller.
	var marks: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(feature_id, ":brush-water-marks:v1"))
	for old in varied_marks(samples, feature_id):
		if rng.randf() < 0.53: continue
		var tangent: Vector2 = (old.end - old.start).normalized()
		if tangent.length_squared() < 0.5: continue
		var normal := tangent.orthogonal()
		var shift := normal * rng.randf_range(-0.09, 0.09) * float(old.width)
		var start: Vector2 = old.start + shift
		var length: float = old.start.distance_to(old.end) * rng.randf_range(0.65, 1.35)
		var end: Vector2 = start + tangent.rotated(rng.randf_range(-0.25, 0.25)) * length
		var middle := start.lerp(end, 0.47) + normal * rng.randf_range(-1.2, 1.2)
		marks.append({"start":start,"middle":middle,"end":end,"opacity":rng.randf_range(0.20, 0.49),"thickness":rng.randf_range(0.4, 0.9)})
	return marks
