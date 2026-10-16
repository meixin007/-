@tool
extends RefCounted
const Water = preload("water_brush.gd")
const G = preload("geometry_ops.gd")
var active := false
var preview_key: Array=[]
var preview_data: Dictionary={}

func cancel(c) -> void:
	active=false; c.draft.clear(); c._redraw_interaction()

func commit(c) -> void:
	active=false
	if c.draft.is_empty(): return
	var began:=Time.get_ticks_usec()
	var result: Dictionary=c.doc.water_brush(c.tool,c.draft,c.water_width,c.water_radius,"",minf(128,12.0/c.zoom) if c.water_connect else 0.0,c.water_whole and c.tool=="river_width",c.water_end_styles)
	c.water_last_commit_ms=(Time.get_ticks_usec()-began)/1000.0
	if result.ok:
		c.draft.clear()
		c.message.emit("水系笔画已应用，Ctrl+Z 撤销整笔。"+(" 已连接河道。" if result.connected else ""))
		c.queue_redraw()
	else:
		c.message.emit(result.error+"；Enter 重试，Esc 取消笔画。")
	c._redraw_interaction()

func input(c, event: InputEvent) -> bool:
	if c.tool not in Water.TOOLS: return false
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: cancel(c); c.accept_event(); return true
		if event.keycode==KEY_ENTER: commit(c); c.accept_event(); return true
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and active:
			cancel(c); c.message.emit("已取消当前笔画，开始移动视野。")
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			cancel(c); c.accept_event(); return true
		if event.button_index!=MOUSE_BUTTON_LEFT: return false
		if event.pressed and (c.panning or Input.is_key_pressed(KEY_SPACE)): return false
		if not event.pressed and not active: return false
		c.pointer=c.world_at(event.position)
		if event.pressed:
			if not c._inside(c.pointer): return true
			if c.selection_guard.is_valid() and not c.selection_guard.call("canvas_edit",c.tool): c.accept_event(); return true
			c.grab_focus()
			c.select_art_instance(""); c.select_feature("")
			c.draft=[[c.pointer.x,c.pointer.y]]
			active=true
		else:
			append(c,c.pointer)
			commit(c)
		c._redraw_interaction(); c.accept_event(); return true
	if event is InputEventMouseMotion and not c.panning:
		c.pointer=c.world_at(event.position)
		c.pointer_changed.emit(c.pointer,c.zoom)
		if active: append(c,c.pointer)
		c._redraw_interaction(); return true
	return false

func append(c, point: Vector2) -> void:
	point=point.clamp(Vector2.ZERO,Vector2(c.doc.data.canvas_size[0],c.doc.data.canvas_size[1]))
	if c.tool=="river_move":
		if c.draft.size()==1: c.draft.append([point.x,point.y])
		else: c.draft[-1]=[point.x,point.y]
	elif c.draft.size()<4096 and Vector2(c.draft[-1][0],c.draft[-1][1]).distance_to(point)*c.zoom>=2:
		c.draft.append([point.x,point.y])

func draw(c, overlay: Control) -> void:
	if c.tool not in Water.TOOLS or c.export_mode: return
	overlay.draw_set_transform(c.pan,0,Vector2.ONE*c.zoom)
	var erase: bool=c.tool in ["river_erase","lake_erase"]
	var color:=Color(.85,.3,.2,.65) if erase else Color(.25,.65,.85,.65)
	var radius: float=c.water_width*.5 if c.tool=="river_draw" else c.water_radius
	if c.pointer_over_canvas and not c.panning:
		overlay.draw_arc(c.pointer,radius,0,TAU,48,color,1.5/c.zoom,true)
	if c.draft.is_empty(): return
	var points:=G.packed(c.draft)
	if points.size()>1: overlay.draw_polyline(points,color,c.water_width if c.tool=="river_draw" else 2/c.zoom,true)
	if c.tool=="lake_paint":
		for p in points: overlay.draw_circle(p,radius,Color(.25,.65,.85,.18))
	elif c.tool=="river_move" and points.size()>1:
		var key: Array=[c.doc.revision,points[0],radius]
		if preview_key!=key:
			preview_key=key
			var id:=Water.hit(c.doc.data.features,points[0],radius)
			preview_data={} if id.is_empty() else Water.dense(Water.ribbon(c.doc.find_feature(id)),maxf(1,radius*.2))
		if preview_data.is_empty(): return
		var preview: PackedVector2Array=preview_data.points.duplicate()
		for i in range(preview.size()): preview[i]+=(points[-1]-points[0])*smoothstep(radius,0,preview[i].distance_to(points[0]))
		overlay.draw_polyline(preview,color,3/c.zoom,true)
