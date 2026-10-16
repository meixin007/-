extends "res://runtime/canvas_input.gd"
var show_constraints := true
var show_water := true
var show_icon := true
var show_slope := false
var relief: Texture2D
var slope_texture: Texture2D
var gate_texture: Texture2D

func _ready() -> void:
	super._ready()
	var cache=get_node("/root/Session").cache
	relief=cache.fallback
	slope_texture=cache.slope
	gate_texture=cache.gate
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and drag_distance < 5.0:
		model.probe = model.local_from_screen(event.position,size)
		view_changed.emit()

func points_screen(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points: result.append(model.local_to_screen(p,size))
	return result
func gate_detail_alpha()->float:return smoothstep(0.17,0.26,model.zoom)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("263c40"))
	if model == null or font == null or not model.load_error.is_empty():
		if font != null: _label(Vector2(20,35),model.load_error,Color.SALMON)
		return
	model.draw_overview(self,size,font)
	var top_left: Vector2 = model.local_to_screen([-12000,-8000],size)
	var bounds := Rect2(top_left,Vector2(24000,16000)*model.zoom)
	if show_slope: draw_texture_rect(slope_texture,bounds,false)
	else: get_node("/root/Session").cache.draw_terrain(self,bounds)
	if show_water:
		for feature in model.water.features:
			var points := points_screen(feature.points_m)
			if points.size() < 2: continue
			if feature.geometry == "polygon": model.draw_local_polygon(self,feature.points_m,Color("78aeba"),size)
			else: draw_polyline(points,Color("42869d"),maxf(1.0,model.zoom*8),true)
	if show_constraints:
		for constraint in model.recipe.constraints:
			if constraint.has("external_geometry"): continue
			var points := points_screen(constraint.points_m)
			var color := Color("d48b65")
			match constraint.kind:
				"highground": color = Color("85846a")
				"gully": color = Color("9a7670")
				"building_exclusion": color = Color("cc7966")
				"city_allowed": color = Color("78b780")
				"plot":
					color = Color("e3d68d")
					for decision in model.template_checks.plots:
						if decision.id == constraint.id and not decision.allowed: color = Color("d8796b")
				"main_corridor": color = Color("eac879")
				"defense_line": color = Color("da7d66")
			if constraint.geometry == "polygon":
				model.draw_local_polygon(self,constraint.points_m,Color(color,0.19 if constraint.kind != "plot" else 0.5),size)
				points.append(points[0]); draw_polyline(points,Color(color,0.85),1.5,true)
			else:
				draw_polyline(points,Color(color,0.35),maxf(4.0,model.zoom*(100 if constraint.kind=="main_corridor" else 20)),true)
				draw_polyline(points,color,2.0,true)
			if model.zoom > 0.3 and constraint.kind == "plot":
				var suffix := ""
				for decision in model.template_checks.plots:
					if decision.id == constraint.id: suffix = " · 粗筛可用" if decision.allowed else " · 整块拒绝"
				_label(points[0]+Vector2(4,-7),constraint.role+suffix,Color("263a35"),14)
		var anchor: Vector2 = model.site_screen(size)
		var radius: float = model.recipe.anchor.uncertainty_radius_m*model.zoom
		draw_arc(anchor,radius,0,TAU,160,Color(1,0.8,0.4,0.55),1.5,true)
	var site: Vector2 = model.site_screen(size)
	if show_icon and gate_texture != null and gate_detail_alpha()>0:
		var width := clampf(80+model.zoom*50,80,160)
		var art_size := Vector2(width,width*1024.0/1536.0)
		draw_texture_rect(gate_texture,Rect2(site-art_size*Vector2(0.4329427083,0.673828125),art_size),false,Color(1,1,1,gate_detail_alpha()))
	draw_arc(site,13,0,TAU,40,Color("f4d580") if model.selected_site=="tongguan" else Color("e7e5cb"),2,true)
	draw_line(site-Vector2(0,13),site+Vector2(0,13),Color("84cf8e") if model.gate_open() else Color("e77d6a"),3,true)
	_label(site+Vector2(20,25),"潼关 · 756候选锚点",Color("263a35"),16)
	if model.zoom > 0.2: _label(site+Vector2(20,45),"门楼为图标；非测绘尺寸",Color("53605a"),13)
	var probe: Vector2 = model.local_to_screen([model.probe.x,model.probe.y],size)
	draw_line(probe-Vector2(7,0),probe+Vector2(7,0),Color.WHITE,1)
	draw_line(probe-Vector2(0,7),probe+Vector2(0,7),Color.WHITE,1)
	draw_rect(bounds,Color("b4c4b5"),false,1)
	# Readable legend and metric grid bar stay in screen space.
	draw_rect(Rect2(0,0,size.x,33),Color(0.08,0.17,0.19,0.92))
	_label(Vector2(14,23),"蓝：现代水系   黄：通道候选   红：禁建 / 防线   绿：模板范围",Color("d5e0d4"),15)
	var distance := 2000.0 if model.zoom < 0.1 else (500.0 if model.zoom < 0.5 else 100.0)
	var width_px: float = distance*model.zoom
	draw_rect(Rect2(14,size.y-46,width_px+85,31),Color(0.08,0.17,0.19,0.9))
	draw_line(Vector2(24,size.y-25),Vector2(24+width_px,size.y-25),Color.WHITE,3)
	_label(Vector2(32+width_px,size.y-20),"%d m"%distance,Color.WHITE,14)
	draw_rect(Rect2(0,size.y-12,size.x,12),Color("142b33"))
