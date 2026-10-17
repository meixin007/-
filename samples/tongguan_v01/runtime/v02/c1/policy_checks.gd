extends RefCounted
var checks:=0
var failures: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func run() -> Dictionary:
	var policy=load("res://v02/c1/display_policy.gd").new()
	check(policy.choose(0,1.0,1200)==3,"large jump to detail")
	check(policy.choose(3,.00014,1200)==0,"large jump to icon")
	for tier in 3:
		var threshold: float=policy.thresholds[tier]
		var lod:=tier;var transitions:=0
		for i in 20:
			for pixels in [threshold*.99,threshold*1.01]:
				var next: int=policy.choose(lod,pixels/1200.0,1200)
				if next!=lod:transitions+=1
				lod=next
		check(transitions==0,"20 threshold oscillations no toggling tier %d"%tier)
		check(policy.choose(tier,threshold*1.16/1200,1200)==tier+1,"enter threshold %d"%tier)
		check(policy.choose(tier+1,threshold*.84/1200,1200)==tier,"exit threshold %d"%tier)
	var rows: Array=[]
	for i in 100:rows.append({"site_id":"lab.%03d"%i,"position_m":[i*.2,0],"label":"LAB %03d"%i,"importance":i})
	rows.append({"site_id":"tongguan","position_m":[0,0],"label":"潼关","importance":0})
	var labels: Array=policy.labels(rows,Rect2(-800,-470,1600,940),1,Vector2(1600,940),"tongguan")
	check(labels.size()<=64,"bounded labels")
	check(not labels.is_empty() and labels[0].site_id=="tongguan","selected label wins overlap")
	for a in labels.size():
		for b in range(a+1,labels.size()):check(not labels[a].rect.intersects(labels[b].rect),"label non-overlap")
	check(policy.labels(rows,Rect2(5000,5000,1600,940),1,Vector2(1600,940),"tongguan").is_empty(),"spatial filter excludes offscreen labels")
	return {"checks":checks,"failures":failures}
