@tool
extends RefCounted
const Doc = preload("document.gd")
const Review = preload("sample_geography_review.gd")
const WORLD := Vector2(14880,9600)
## Structural authoring sample at existing project anchors, NOT historical survey or campaign rules.
static func make(project_nodes: Array = []) -> Dictionary:
	var data := Doc.blank()
	data.title = "潼关与剑门—四川盆地 · 连续结构样区（待史料复核）"
	data.canvas_size = [int(WORLD.x),int(WORLD.y)]
	data.production.coordinate_frame = "game_map_3720x2400_scaled_4"
	data.production.source_note = "地点使用项目现有归一化定义；地形是结构示意，不授予正式通行许可。"
	var anchors := {}
	for node in project_nodes:
		if not node is Dictionary or not node.get("node_id") is String or not Doc._point(node.get("coords")): continue
		var p := Vector2(node.coords[0],node.coords[1])*WORLD
		var f := Doc.feature(Review.marker_kind(node),[[p.x,p.y]],str(node.get("display_name",node.node_id)),"anchor_"+node.node_id)
		f.domain_id=node.node_id
		f.protected=true
		f.group_id="project_anchors"
		f.scale=0.5
		f.source={"citation":"data/scenarios/anshi_rebellion/map_strategy_nodes.json","era":"项目当前剧本定义；未新增历史考证","status":"candidate"}
		Review.annotate_anchor(f,node)
		data.features.append(f)
		anchors[node.node_id]=f
	var tongguan := Vector2(0.602,0.511)*WORLD
	var jianmen := Vector2(0.524,0.573)*WORLD
	for pair in [["tongguan_pass_node","潼关",tongguan],["jianmen_pass_node","剑门",jianmen]]:
		if not anchors.has(pair[0]):
			var f := Doc.feature("pass",[[pair[2].x,pair[2].y]],pair[1],"anchor_"+pair[0])
			f.scale=0.5; f.domain_id=pair[0]; f.protected=true
			f.source={"citation":"项目既有样区锚点；导入时应与当前节点表复核","era":"结构样例","status":"schematic"}
			data.features.append(f)
			anchors[pair[0]]=f
	tongguan=Vector2(anchors.tongguan_pass_node.points[0][0],anchors.tongguan_pass_node.points[0][1])
	jianmen=Vector2(anchors.jianmen_pass_node.points[0][0],anchors.jianmen_pass_node.points[0][1])
	var scale := 0.5
	var origin := tongguan-Vector2(820,430)*scale
	var sample := Doc.tongguan_sample()
	for f in sample.features:
		if f.id == "tongguan": continue
		f.id="tg_"+f.id
		if not f.gate_id.is_empty(): f.gate_id="anchor_tongguan_pass_node"
		_place(data,f,origin,scale,"tongguan")
	if not Review.refine(data,anchors,origin,scale): return {}
	data.production.regions.append({"id":"tongguan","name":"潼关结构样区","rect":[origin.x,origin.y,800,480]})
	for mode in [["open","开放关口 · 大军通过",true,"army",false,true],["closed","关闭关口 · 大军受阻",false,"army",false,false],["unknown_trail","未发现险径 · 小队受阻",false,"light",false,false],["known_trail","发现险径 · 小队绕行",false,"light",true,true],["army_trail","发现险径 · 大军仍受阻",false,"army",true,false]]:
		_case(data,"tg_"+mode[0],mode[1],origin,scale,[250,430],[1330,430],[0,0,1600,960],4,mode[3],mode[4],mode[5],{"anchor_tongguan_pass_node":mode[2]})
	_case(data,"tg_water","两岸均可落脚，但无渡点不能步行越河",origin,scale,[630,317],[880,240],[400,0,1200,500],4,"army",false,false,{})
	Review.add_checks(data,anchors,origin,scale)
	scale=0.6
	origin=jianmen-Vector2(800,230)*scale
	var ring := Doc.feature("mountain",[[100,180],[750,100],[1350,230],[1520,500],[1420,1220],[200,1300],[40,700]],"盆地外围山系（结构示意）","shu_mountains")
	ring.holes=[[[200,500],[800,380],[1180,450],[1260,700],[1100,1060],[500,1100],[160,850]]]
	_place(data,ring,origin,scale,"sichuan")
	_place(data,Doc.feature("basin",[[215,515],[800,400],[1160,465],[1230,690],[1080,1040],[510,1080],[180,840]],"四川盆地内部","shu_basin"),origin,scale,"sichuan")
	_place(data,Doc.feature("hills",[[790,630],[1080,560],[1160,850],[800,1030]],"盆地内低丘 · 可以穿行","shu_hills"),origin,scale,"sichuan")
	var north := Doc.feature("valley",[[800,40],[800,470]],"剑门北向谷口","shu_north")
	north.gate_id="anchor_jianmen_pass_node"; north.width=96
	_place(data,north,origin,scale,"sichuan")
	var trail := Doc.feature("trail",[[660,100],[650,240],[660,360],[720,490]],"北缘轻装险径（候选）","shu_trail")
	trail.width=48
	_place(data,trail,origin,scale,"sichuan")
	var east := Doc.feature("valley",[[1150,650],[1600,650]],"东侧另一路出口（结构保留）","shu_east")
	east.width=96
	_place(data,east,origin,scale,"sichuan")
	_place(data,Doc.feature("river",[[700,800],[960,900],[1300,850],[1600,750]],"盆地水系示意","shu_river"),origin,scale,"sichuan")
	_place(data,Doc.feature("forest",[[400,730],[600,700],[640,970],[480,960]],"低丘林地 · 遮蔽条件示意","shu_forest"),origin,scale,"sichuan")
	_place(data,Doc.feature("label",[[650,610]],"四川盆地","shu_label"),origin,scale,"sichuan")
	data.production.regions.append({"id":"sichuan","name":"剑门—四川盆地结构样区","rect":[origin.x,origin.y,960,840]})
	for mode in [["open",true,"army",false,true],["closed",false,"army",false,false],["trail",false,"light",true,true]]:
		_case(data,"shu_"+mode[0],"剑门北口 · "+mode[0],origin,scale,[800,60],[800,520],[560,0,500,580],3,mode[2],mode[3],mode[4],{"anchor_jianmen_pass_node":mode[1]})
	_case(data,"shu_east","关闭剑门不封死盆地东侧出口",origin,scale,[1100,650],[1550,650],[950,480,680,350],3,"army",false,true,{"anchor_jianmen_pass_node":false})
	_case(data,"shu_mountain","大军不能从西侧直穿高山",origin,scale,[390,650],[20,650],[0,500,460,330],3,"army",false,false,{})
	if anchors.has("chengdou_rear_hub_node"):
		var city: Array=anchors.chengdou_rear_hub_node.points[0]
		_case(data,"shu_chengdu","剑门开放后可进入成都所在盆地",origin,scale,[800,60],[(city[0]-origin.x)/scale,(city[1]-origin.y)/scale],[100,0,950,1150],3,"army",false,true,{"anchor_jianmen_pass_node":true})
	return data
static func _place(data: Dictionary, f: Dictionary, origin: Vector2, scale: float, group: String) -> void:
	for ring in [f.points]+f.holes:
		for p in ring: p[0]=origin.x+p[0]*scale; p[1]=origin.y+p[1]*scale
	f.width=clampf(f.width*scale,1 if f.kind in Doc.BOUNDARIES else 8,256)
	f.scale=scale
	f.group_id=group
	f.source={"citation":"docs/map-production/STRATEGIC_TERRAIN_DESIGN_DRAFT_2026-09-23.md","era":"战略空间结构示意，非历史测绘","status":"schematic"}
	data.features.append(f)
static func _case(data: Dictionary, id: String, name: String, origin: Vector2, scale: float, start: Array, finish: Array, rect: Array, step: float, unit: String, revealed: bool, expected: bool, gates: Dictionary) -> void:
	data.production.checks.append({"id":id,"name":name,"start":[origin.x+start[0]*scale,origin.y+start[1]*scale],"finish":[origin.x+finish[0]*scale,origin.y+finish[1]*scale],"rect":[origin.x+rect[0]*scale,origin.y+rect[1]*scale,rect[2]*scale,rect[3]*scale],"step":step,"unit":unit,"revealed":revealed,"expected":expected,"gates":gates})
