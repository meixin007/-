extends "res://runtime/geography_canvas.gd"
var show_buildings:=true
var show_trees:=true
var tree_art: Dictionary={}
func _ready()->void:
	super._ready();show_constraints=false
	tree_art=get_node("/root/Session").cache.tree_art
func _gui_input(event: InputEvent)->void:
	super._gui_input(event)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and drag_distance<5.0:
		model.pick_entities(event.position,size);view_changed.emit();queue_redraw()
func _tree(tree: Dictionary,tint:=Color.WHITE)->void:
	var asset="tree_willow" if int(tree.asset_version)==1 else "tree_grove"
	if not tree_art.has(asset):return
	var art: Dictionary=tree_art[asset];var point: Vector2=model.local_to_screen(tree.position_m,size)
	var width=80.0*model.zoom;var dims=Vector2(width,width*art.ratio)
	if not Rect2(-100,-100,size.x+200,size.y+200).has_point(point):return
	draw_texture_rect(art.texture,Rect2(point-dims*Vector2(art.anchor[0],art.anchor[1]),dims),false,tint)
func _building(center: Vector2,kind: String,damage: int,building: bool)->void:
	var p: Vector2=model.local_to_screen([center.x,center.y],size);var scale_value: float=model.zoom
	if not Rect2(-100,-100,size.x+200,size.y+200).has_point(p):return
	if damage==2:
		var rubble=PackedVector2Array([p+Vector2(-13,3)*scale_value,p+Vector2(-7,-3)*scale_value,p+Vector2(-2,1)*scale_value,p+Vector2(4,-4)*scale_value,p+Vector2(13,3)*scale_value])
		draw_colored_polygon(rubble,Color("8d7664"));draw_polyline(rubble,Color("493f35"),1.5,true);return
	var walls=PackedVector2Array([p+Vector2(-12,-2)*scale_value,p+Vector2(12,-2)*scale_value,p+Vector2(12,6)*scale_value,p+Vector2(-12,6)*scale_value])
	draw_colored_polygon(walls,Color("d4c0a0"));var outline=walls.duplicate();outline.append(outline[0]);draw_polyline(outline,Color("493f35"),1.5,true)
	var roof=PackedVector2Array([p+Vector2(-14,-3)*scale_value,p+Vector2(-7,-10)*scale_value,p+Vector2(14,-3)*scale_value,p+Vector2(7,1)*scale_value])
	var color=Color("788493") if kind in ["warehouse","granary"] else Color("9d7f65")
	if building:color=Color("c9b674")
	draw_colored_polygon(roof,color);roof.append(roof[0]);draw_polyline(roof,Color("493f35"),1.5,true)
	if damage==1:draw_line(p+Vector2(-6,-6)*scale_value,p+Vector2(4,3)*scale_value,Color("70443d"),maxf(2,scale_value*2),true)
	if building and model.zoom>1:_label(p+Vector2(-15,16)*scale_value,"在建",Color("544c32"),13)
func _draw()->void:
	super._draw()
	if model==null or not model.load_error.is_empty():return
	if model.lod<2:return
	var state: Dictionary=model.host.runtime;var authored: Dictionary=model.host.authoring;var layout: Dictionary=model.host.layout
	if show_trees:
		var trees: Array=authored.generated.values();trees.sort_custom(func(a: Dictionary,b: Dictionary):return float(a.position_m[1])<float(b.position_m[1]))
		for tree in trees:_tree(tree)
		if not model.preview.is_empty():
			for id in model.preview.added+model.preview.updated:_tree(model.preview.candidate_generated[id],Color(0.65,1,0.65,0.7))
			for id in model.preview.removed:
				if authored.generated.has(id):
					var p: Vector2=model.local_to_screen(authored.generated[id].position_m,size);draw_line(p-Vector2(8,8),p+Vector2(8,8),Color.SALMON,2);draw_line(p-Vector2(8,-8),p+Vector2(8,-8),Color.SALMON,2)
	for road in authored.roads:draw_polyline(points_screen(road.points_m),Color("bfa77c"),maxf(2,model.zoom*4),true)
	for index in range(layout.slots.size()):
		var slot: Dictionary=layout.slots[index];var occupancy: Dictionary=state.slot_occupancy[slot.id]
		var unlocked=int(state.growth_stage)>=int(slot.unlock_stage)
		var points=points_screen(slot.polygon_local_m)
		var selected=slot.id==model.selected_slot
		var color=Color("ceb97c") if unlocked else Color("9b9e8c")
		draw_colored_polygon(points,Color(color,0.25 if occupancy.status=="empty" else 0.15));points.append(points[0]);draw_polyline(points,Color("f9dc87") if selected else color,2.5 if selected else 1.0,true)
		var center: Vector2=model.slot_center(slot.id)
		var socket: Vector2=model.local_to_screen(slot.road_socket_m,size)
		var edge: Vector2=model.local_to_screen([center.x,slot.polygon_local_m[2][1] if index<4 else slot.polygon_local_m[0][1]],size)
		draw_line(socket,edge,Color("bfa77c"),maxf(1,model.zoom*2),true)
		if show_buildings and occupancy.status!="empty":
			var offset: Array=authored.manual_overrides.get(slot.id,{}).get("offset_m",[0,0]);_building(center+Vector2(offset[0],offset[1]),occupancy.building_type,int(state.module_damage[slot.id]),occupancy.status=="building")
		if model.zoom>1.3:
			var at=points[0]+Vector2(3,-5)
			var short_name: String=slot.name if selected or model.zoom>=2.1 else str(slot.name).left(2)
			_label(at,"%d %s"%[index+1,short_name],Color("354539"),13)
	if show_buildings:
		for module in ["wall_west","wall_east"]:
			var y=-65.0 if module=="wall_west" else 65.0
			var a: Vector2=model.local_to_screen([0,y-22],size);var b: Vector2=model.local_to_screen([0,y+22],size)
			var damage=int(state.module_damage[module]);var color=Color("ad9d80") if damage==0 else Color("88675a")
			draw_line(a,b,color,maxf(3,model.zoom*(4+int(state.growth_stage)*2)),true)
			if damage<2:
				for i in range(int(state.growth_stage)+1):draw_circle(a.lerp(b,float(i)/int(state.growth_stage)),maxf(2,model.zoom*2),Color("d5c7a7"))
		var gate: Vector2=model.site_screen(size);var damage=int(state.module_damage.gate)
		if damage>0:
			draw_line(gate-Vector2(5,28),gate+Vector2(12,3),Color("8a5145"),4,true)
			if damage==2:draw_circle(gate+Vector2(10,2),15,Color(0.4,0.25,0.2,0.65))
			if model.zoom>0.5:_label(gate+Vector2(-48,-48),"受损占位" if damage==1 else "严重受损占位",Color("893e32"),14)
	if authored.generated.has(model.selected_tree):
		var selected: Array=authored.generated[model.selected_tree].position_m;draw_arc(model.local_to_screen(selected,size),17,0,TAU,40,Color("f9dc87"),2,true)
	draw_rect(Rect2(0,0,size.x,33),Color(0.08,0.17,0.19,0.95))
	_label(Vector2(12,23),"P5 · 稳定槽位 / 灰色待开放 / 黄框选中　·　建筑与损毁为工程占位",Color("d5e0d4"),14)
