extends "res://runtime/city_canvas.gd"
const Motion=preload("res://integrity/polyline.gd")
var _visual_path:=PackedVector2Array()
var show_route:=true
var _from:=Vector2.ZERO
var _to:=Vector2.ZERO
var _elapsed:=1.0
var _duration:=1.0
func army():return get_node("/root/Session").army
func _ready()->void:
	super._ready();var p: Array=army().position_local();_from=Vector2(p[0],p[1]);_to=_from
func animate_to(position: Array,duration: float)->void:
	_visual_path.clear();_from=visual_position();_to=Vector2(position[0],position[1]);_elapsed=0.0;_duration=maxf(0.05,duration);queue_redraw()
func animate_path(points: Array,duration: float)->void:
	if points.size()<2:finish_animation();return
	_visual_path=Motion.points(points);_from=_visual_path[0];_to=_visual_path[-1];_elapsed=0.0;_duration=maxf(0.05,duration);queue_redraw()
func finish_animation()->void:
	_visual_path.clear()
	var p: Array=army().position_local();_from=Vector2(p[0],p[1]);_to=_from;_elapsed=_duration;queue_redraw()
func visual_position()->Vector2:return Motion.sample(_visual_path,clampf(_elapsed/_duration,0,1)) if _visual_path.size()>1 else _from.lerp(_to,clampf(_elapsed/_duration,0,1))
func _label(at: Vector2,text: String,color: Color=Color("354951"),font_size:=16)->void:
	if text.begins_with("潼关 · 756候选锚点") or text.begins_with("门楼为图标"):return
	super._label(at,text,color,font_size)
func _process(delta: float)->void:
	if _elapsed<_duration:_elapsed=minf(_duration,_elapsed+delta);queue_redraw()
func _draw()->void:
	super._draw()
	if model==null or not model.load_error.is_empty():return
	draw_rect(Rect2(0,0,size.x,33),Color("193238"));_label(Vector2(12,23),"受控移动 · 蓝旗为测试部队 · 主关红 / 绿仅表示道路许可",Color("d5e0d4"),15)
	var runtime=army();var state=runtime.snapshot();var routes=runtime.effective_corridors()
	if show_route and model.lod>0:
		for route in routes.values():
			var p=points_screen(route.points_m)
			if route.corridor_id=="tg_synthetic_trail":
				for i in range(p.size()-1):draw_dashed_line(p[i],p[i+1],Color("b88782") if route.is_blocked else Color("80d9da"),2,8,true)
				if model.zoom>1:_label(p[1]+Vector2(10,25),"合成险径 · 非历史道路",Color("395d65"),14)
			else:draw_polyline(p,Color("9b4246") if route.is_blocked else Color("efce88"),5,true)
			if route.corridor_id=="tg_main_gate":draw_polyline(p,Color("ef8b7d") if route.is_blocked else Color("8ee2b3"),2,true)
		for id in ["tg_fore","tg_rear"]:
			var node: Dictionary=runtime.context.state.strategic_nodes[id];var at: Vector2=model.local_to_screen(node.position_m,size)
			draw_circle(at,7,Color("edd38c"));_label(at+Vector2(-29,31),node.name,Color("23373a"),15)
	var local=visual_position();var at: Vector2=model.local_to_screen([local.x,local.y],size)
	if not Rect2(-50,-70,size.x+100,size.y+140).has_point(at):return
	var waiting=state.order.status=="waiting";var tint=Color("f2b76b") if waiting else Color("83dbef")
	draw_circle(at,10,Color("183d4b"));draw_arc(at,12,0,TAU,30,tint,2,true)
	if model.lod>=1:
		draw_line(at+Vector2(0,-5),at+Vector2(0,-43),Color("263941"),3,true)
		var flag=PackedVector2Array([at+Vector2(1,-43),at+Vector2(27,-39),at+Vector2(1,-26)])
		draw_colored_polygon(flag,tint)
		for x in [-7,1,9]:
			draw_circle(at+Vector2(x,-15),3,Color("ece4cc"));draw_line(at+Vector2(x,-11),at+Vector2(x,-4),Color("415766"),3,true)
	var text=("轻装验收队" if runtime.snapshot().force.movement_profile=="light" else "验收队")+" · 100人"+(" · 候行" if waiting else "")
	draw_rect(Rect2(at+Vector2(-65,-71),Vector2(180 if waiting else 145,26)),Color(0.06,0.14,0.18,0.92))
	_label(at+Vector2(-59,-52),text,tint,15)
