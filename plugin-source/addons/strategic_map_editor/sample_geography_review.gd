@tool
extends RefCounted
## Presentation corrections for the bounded authoring sample only.
## The campaign's is_pass/node_type/coordinates are not changed.
const Doc=preload("document.gd")
const Geometry=preload("geometry_ops.gd")
const REVIEW="docs/map-production/STRATEGIC_MAP_EDITOR_SAMPLE_REVIEW_2026-09-23.md"
const CITY_NODES={
	"suiyang_hub_node":"睢阳城",
	"zhou_yuanzhou":"原州州治",
	"zhou_shanzhou":"陕州州治",
	"zhou_puzhou_hedong":"蒲州城；城西的蒲津渡应另作设施",
	"zhou_daizhou":"代州州治；不把州城替作雁门关址",
	"zhou_weizhou_hedong":"蔚州州治",
	"zhou_yangzhou_west":"洋州州治",
	"zhou_mianzhou":"绵州州治",
	"zhou_lanzhou":"兰州州治；渡河设施不等同城点",
}
static func marker_kind(node: Dictionary) -> String:
	if CITY_NODES.has(node.node_id): return "city"
	return "pass" if node.get("is_pass",false) else "city"
static func annotate_anchor(f: Dictionary,node: Dictionary) -> void:
	if not CITY_NODES.has(node.node_id): return
	f.note="图面对象为"+CITY_NODES[node.node_id]+"。原战略节点仍保留 node_type=%s / is_pass=%s；本标记不代表已定位的实体关隘。依据：%s" % [str(node.get("node_type","")),str(node.get("is_pass",false)),REVIEW]
	f.source.citation+="；图面分类复核："+REVIEW
static func local_point(anchors: Dictionary,id: String,origin: Vector2,scale: float,fallback: Vector2) -> Vector2:
	if not anchors.has(id): return fallback
	var p: Array=anchors[id].points[0]
	return (Vector2(p[0],p[1])-origin)/scale
static func placed(f: Dictionary,origin: Vector2,scale: float) -> Dictionary:
	for p in f.points: p[0]=origin.x+p[0]*scale; p[1]=origin.y+p[1]*scale
	f.group_id="tongguan"; f.scale=scale; f.width=16
	f.source={"citation":REVIEW,"era":"宏观岸别与谷地关系有出处；边界为项目固定锚点下的结构示意","status":"schematic"}
	return f
static func refine(data: Dictionary,anchors: Dictionary,origin: Vector2,scale: float) -> bool:
	var river: Dictionary={}; var mountain: Dictionary={}
	for f in data.features:
		if f.id=="tg_yellow_river": river=f
		if f.id=="tg_qinling": mountain=f
	if river.is_empty() or mountain.is_empty(): return false
	# North-south trunk separates Tongzhou (west) from Puzhou (east), then
	# turns east north of Tongguan/Shanzhou. Width is a readable schematic.
	var centerline:=Doc.packed([[735,-80],[735,280],[735,310],[785,350],[930,350],[1040,248],[1640,248]])
	var outlines:=Geometry2D.offset_polyline(centerline,24,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE)
	if outlines.size()!=1: push_error("样区黄河轮廓生成失败。"); return false
	var revised:=placed(Doc.feature("water",Geometry.unpack(outlines[0]),river.name,river.id),origin,scale)
	river.points=revised.points; river.source=revised.source
	river.note="同州在西侧陆地、蒲州在东岸、陕州在东流段南岸；不是唐代精确河道复原。"
	var city:=local_point(anchors,"refugee_market_node",origin,scale,Vector2(640,756))
	# Carve an open valley toward the south-east; do not put an isolated
	# circular hole under the city or open a north-south shortcut through the ridge.
	var clearing:=Doc.feature("basin",[
		[city.x-60,city.y-65],[city.x+30,city.y-65],[city.x+90,city.y-10],
		[city.x+160,city.y+65],[city.x+250,960],[city.x+300,1040],
		[city.x+90,1040],[city.x+35,960],[city.x-15,city.y+95],[city.x-75,city.y+35]
	],"商洛—商丹谷地（结构示意）","tg_shangluo_basin")
	clearing=placed(clearing,origin,scale)
	clearing.note="保留商洛既有节点，补出可落脚并向东南开口的谷地；不据此新增正式跨秦岭行军路线。"
	var cut:=Geometry.boolean_shapes(mountain,clearing,"subtract")
	if not cut.ok or cut.shapes.size()!=1: push_error("样区商洛谷地扣除失败："+cut.get("error","轮廓数量异常")); return false
	mountain.points=cut.shapes[0].points; mountain.holes=cut.shapes[0].holes
	mountain.source=revised.source.duplicate(true)
	mountain.note="秦岭主体仍禁行；仅按商丹谷地宏观关系为商洛保留东南开口。"
	data.features.append(clearing)
	for f in data.features:
		if f.id=="tg_water_label": f.points=[[origin.x+1260*scale,origin.y+235*scale]]
	data.production.regions.append({"id":"shangluo","name":"商洛谷地复核","rect":[origin.x+(city.x-180)*scale,origin.y+(city.y-160)*scale,560*scale,500*scale]})
	return true
static func add_checks(data: Dictionary,anchors: Dictionary,origin: Vector2,scale: float) -> void:
	var city:=local_point(anchors,"refugee_market_node",origin,scale,Vector2(640,756))
	var tong:=local_point(anchors,"zhou_tongzhou",origin,scale,Vector2(635,317))
	var pu:=local_point(anchors,"zhou_puzhou_hedong",origin,scale,Vector2(823,298))
	var shan:=local_point(anchors,"zhou_shanzhou",origin,scale,Vector2(1213,317))
	var rows: Array=[
		["tg_tongzhou_bank","同州沿西侧陆地接近关中",tong,Vector2(250,430),[0,140,700,500],true],
		["tg_puzhou_bank","蒲州可向东岸腹地离开",pu,Vector2(1160,100),[700,0,800,400],true],
		["tg_shanzhou_bank","陕州沿黄河南岸接近崤函",shan,Vector2(1330,430),[1050,200,500,350],true],
		["tg_opposite_banks","同州至蒲州不能无渡点步行越河",tong,pu,[400,0,1200,500],false],
		["tg_shangluo_exit","商洛谷地有东南出口",city,Vector2(city.x+150,1010),[city.x-180,city.y-160,560,500],true],
		["tg_shangluo_ridge","商洛谷地不授予直穿秦岭捷径",city,Vector2(250,430),[0,0,1600,1040],false],
	]
	for row in rows:
		var a: Vector2=origin+row[2]*scale; var b: Vector2=origin+row[3]*scale; var r: Array=row[4]
		var step:=maxf(3.0,ceil(maxf(r[2],r[3])*scale/255.0))
		data.production.checks.append({"id":row[0],"name":row[1],"start":[a.x,a.y],"finish":[b.x,b.y],"rect":[origin.x+r[0]*scale,origin.y+r[1]*scale,r[2]*scale,r[3]*scale],"step":step,"unit":"army","revealed":false,"expected":row[5],"gates":{}})
