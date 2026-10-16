extends SceneTree
var checks:=0
var failures: Array[String]=[]
var output:="user://tests/r4_view.json"
func check(ok: bool,message: String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:
	create_timer(60).timeout.connect(func():printerr("R4_VIEW_TIMEOUT");quit(1))
	call_deferred("run")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	var script=load("res://review/view_rules.gd")
	check(script!=null,"R4 view rules exist")
	if script!=null:
		var rules=script.new();var policy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://review/policy.json"))
		var site=Vector2(530,310)
		for z in [0.00014,0.052,0.17,0.3,0.5,0.64,1.3,2.4]:
			var rect: Rect2=rules.gate_rect(site,z,policy)
			var anchor=Vector2(665.0/1536.0,690.0/1024.0)
			check((rect.position+rect.size*anchor).distance_to(site)<0.0001,"gate anchor unchanged at "+str(z))
			check(rect.size.x>0 and rect.size.x<=policy.gate.near_width_px,"bounded gate scale at "+str(z))
			check(rules.gate_alpha(z)>=0 and rules.gate_alpha(z)<=1,"bounded detail alpha at "+str(z))
		var labels=rules.place_labels([
			{"id":"secondary","priority":1,"at":Vector2(5,5),"size":Vector2(60,20)},
			{"id":"selected","priority":100,"at":Vector2(5,5),"size":Vector2(60,20)},
			{"id":"outside","priority":200,"at":Vector2(1400,5),"size":Vector2(60,20)}],Rect2(0,0,1000,600))
		check(labels.size()==1 and labels[0].id=="selected","selected label survives collision; offscreen label excluded")
		var logic=get_root().get_node("Session").army
		check(logic.error.is_empty(),"inherited actual game state initializes")
		check(logic.definition.world_id=="tongguan_final_validation_v1","R5 isolated world identity")
		var before=logic.digest(logic.snapshot());var model=load("res://runtime/model.gd").new()
		for id in policy.bookmarks:
			model.view.bookmarks=policy.bookmarks.duplicate(true);model.recall_bookmark(id)
			var p=model.site_screen(Vector2(1400,900));check(model.pick_site(p,Vector2(1400,900))=="tongguan","same site picked at "+id)
		for previous in [0,3]:
			for i in 4:
				model.lod=previous;var id=["east_asia","guanzhong_east","tongguan_context","gate_close"][i]
				model.recall_bookmark(id);check(model.lod==i,"bookmark selects its reproducible LOD from "+str(previous)+": "+id)
		check(before==logic.digest(logic.snapshot()),"all presentation calculations leave authority unchanged")
	var result={"checks":checks,"failures":failures};DirAccess.make_dir_recursive_absolute(output.get_base_dir());FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("R4_VIEW: "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
