extends "res://r3_authoring/canvas.gd"
func _draw()->void:
	super._draw()
	if host==null or font==null or not host.has_method("layout_record"):return
	var record=host.layout_record();var p=screen([-567.5+float(record.warehouse_offset_m[0]),-227.5+float(record.warehouse_offset_m[1])])
	if not Rect2(-80,-80,size.x+160,size.y+160).has_point(p):return
	var roof=PackedVector2Array([p+Vector2(-14,-3)*zoom,p+Vector2(-7,-10)*zoom,p+Vector2(14,-3)*zoom,p+Vector2(7,1)*zoom])
	draw_colored_polygon(roof,Color("7b8a95"));roof.append(roof[0]);draw_polyline(roof,Color("49534c"),1.5,true)
	label(p+Vector2(-80,25),"仓库制作接地点 · 不产生建筑",Color("496251"))
