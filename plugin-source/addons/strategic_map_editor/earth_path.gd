@tool
extends RefCounted
## Presentation geometry only; never changes the authoring corridor or rules.
static func build(line: PackedVector2Array, width: float, identity: String) -> Dictionary:
	var centers := PackedVector2Array()
	if line.size()<2:return {"polygon":PackedVector2Array(),"marks":[]}
	centers.append(line[0])
	var carry := 0.0
	for i in range(1,line.size()):
		var a := line[i-1]
		var segment := line[i]-a
		var length := segment.length()
		if length<.001:continue
		var along := 1.2-carry
		while along<length:
			centers.append(a+segment*(along/length));along+=1.2
		carry=fposmod(carry+length,1.2)
	centers.append(line[-1])
	var rng := RandomNumberGenerator.new();rng.seed=hash(identity+":earth-v1")
	var left := PackedVector2Array();var right := PackedVector2Array();var marks: Array=[]
	var phase := rng.randf_range(0,TAU)
	for i in range(centers.size()):
		var tangent := (centers[mini(i+1,centers.size()-1)]-centers[maxi(0,i-1)]).normalized()
		var normal := tangent.orthogonal()
		var variation := 1.0+.14*sin(i*.17+phase)+.07*sin(i*.57+phase)
		var half := width*.5*variation
		left.append(centers[i]+normal*(half+rng.randf_range(-.18,.18)))
		right.append(centers[i]-normal*(half+rng.randf_range(-.18,.18)))
		# Unequal, separated earth marks avoid a continuous pair of border rails.
		if i>1 and i<centers.size()-3 and rng.randf()<.17:
			var side := -1.0 if rng.randf()<.5 else 1.0
			var start := centers[i]+normal*half*side*.78
			marks.append({"start":start,"end":start+tangent*rng.randf_range(1.2,3.8),"alpha":rng.randf_range(.12,.23),"width":rng.randf_range(.18,.34)})
	var polygon := left.duplicate()
	for i in range(right.size()-1,-1,-1):polygon.append(right[i])
	return {"polygon":polygon,"marks":marks}
