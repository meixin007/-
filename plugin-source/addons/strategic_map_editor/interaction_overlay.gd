@tool
extends Control
# Draw-command cache for the map stays intact while the placement cursor moves.
var canvas: Control
func _draw() -> void:
	if canvas == null or canvas.doc == null or canvas.export_mode: return
	var c:=canvas
	if c.tool in c.WaterBrush.TOOLS:
		c.water_input.draw(c,self)
		return
	c.selection_overlay.draw(c,self)
	if c.tool != "art_stamp" or not c.has_art() or not c.pointer_over_canvas or c.panning or not c._inside(c.pointer): return
	draw_set_transform(c.pan,0,Vector2.ONE*c.zoom)
	var point: Vector2=c.snap_point(c.pointer)
	var key: String=c._stamp_asset(point)
	var tex: Texture2D=c.art.texture(key)
	var rect: Rect2=c.art.instance_rect(key,point,c.brush_scale)
	var blocked: bool=c.depth_enabled() and not c.placement_conflicts(key,rect).is_empty()
	var tint:=Color(1,.35,.3,.6) if blocked else Color(1,1,1,.65)
	if tex != null: draw_texture_rect(tex,rect,false,tint)
	draw_arc(point,5/c.zoom,0,TAU,20,Color("d95843") if blocked else Color("327f63"),1.5/c.zoom,true)
