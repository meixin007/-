extends "res://v02/e3/map_renderer.gd"
## E3 retained commands and eviction callbacks, with independent semantic overlays.
var app: WeakRef
var overlay: Control
var coarse: Control
var label_plan: Array=[]
var factions:=false
var faction_revision:=0
var faction_swapped:=false
var terrain_only:=false
var guides:=false
var detail_alpha:=0.0
var transition_msec:=180
var _detail_started:=0
var _was_ready:=false
var _overlay_key: Array=[]
var _press:=Vector2.ZERO
var _dragged:=false
class Layer extends Control:
	var owner_ref: WeakRef
	var is_coarse:=false
	func _draw() -> void:
		if owner_ref==null or owner_ref.get_ref()==null:return
		if is_coarse:owner_ref.get_ref().paint_coarse(self)
		else:owner_ref.get_ref().paint_overlay(self)
func _ready() -> void:
	super._ready();texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	coarse=Layer.new();coarse.is_coarse=true;coarse.owner_ref=weakref(self);coarse.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(coarse);move_child(coarse,1)
	overlay=Layer.new();overlay.owner_ref=weakref(self);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay)
func terrain_unit(id: String,page: Dictionary,target: Array,manager: RefCounted,used: Dictionary,alpha: float=1) -> void:
	if page.parent_id.is_empty() and not id.begins_with("base:"):return
	super.terrain_unit(id,page,target,manager,used,alpha)
func detach_resource(key: String) -> void:
	# E3's generic callback resets all transition records. In C1 a distant tree
	# expiring must not restart the fade of unrelated, already-resident terrain.
	var active_fades: Dictionary=fades.duplicate();var completed: Dictionary=finished_fades.duplicate()
	if app!=null and app.get_ref()!=null and app.get_ref().service.loader!=null:
		var service=app.get_ref().service
		for id in service.loader.pages:
			for file in service.loader.pages[id].texture_files:
				if service.manager.key_for(file)==key:active_fades.erase(id);completed.erase(id)
	super.detach_resource(key);fades=active_fades;finished_fades=completed
func render(service: RefCounted,x: float,y: float,zoom: float) -> void:
	super.render(service,x,y,zoom)
	if service.detail_ready and not _was_ready:_detail_started=Time.get_ticks_msec()
	_was_ready=service.detail_ready
	detail_alpha=clampf((Time.get_ticks_msec()-_detail_started)/float(maxi(1,transition_msec)),0,1) if service.detail_ready else 0
	for id in nodes:
		if id.begins_with("object:"):nodes[id].node.modulate.a=0 if terrain_only else detail_alpha
	var key: Array=[x,y,zoom,service.revision,service.semantic_lod,service.detail_ready,service.suspended,faction_revision,factions,guides,terrain_only,service.selected_site,detail_alpha]
	if key==_overlay_key:return
	_overlay_key=key
	label_plan=service.policy.labels(service.loader.sites,service.view,zoom,size,service.selected_site)
	coarse.queue_redraw();overlay.queue_redraw()
func screen(p: Array) -> Vector2:
	var host=app.get_ref();return size*.5+Vector2((p[0]-host.x)*host.zoom,(p[1]-host.y)*host.zoom)
func paint_coarse(target: CanvasItem) -> void:
	if app==null or app.get_ref()==null:return
	var host=app.get_ref()
	if host.active=="tongguan":host.model.draw_overview(target,size,host.theme.default_font)
func paint_overlay(target: CanvasItem) -> void:
	if app==null or app.get_ref()==null:return
	var host=app.get_ref();var service=host.service;var font: Font=host.theme.default_font
	if factions:
		var extent: float=240000 if host.active=="tongguan" else 8000
		for side in 2:
			var p:=PackedVector2Array()
			for q in [[-extent if side==0 else 0,-extent],[0 if side==0 else extent,-extent],[0 if side==0 else extent,extent],[-extent if side==0 else 0,extent]]:p.append(screen(q))
			var color: Color=Color("b56849",.15) if (side==0)!=faction_swapped else Color("527d8c",.15)
			target.draw_colored_polygon(p,color)
		# One shared source for the boundary; ownership only changes the colors.
		target.draw_line(screen([0,-extent]),screen([0,extent]),Color("796753",.6),1.5,true)
	if not terrain_only:
		for row in service.loader.sites:
			var p: Vector2=screen(row.position_m)
			if not Rect2(Vector2(-24,-24),size+Vector2(48,48)).has_point(p):continue
			var actual: bool=row.site_id=="tongguan"
			var alpha: float=1-detail_alpha if actual else 1
			if alpha<=0:continue
			var ink:=Color("6b5c47",alpha);var fill:=Color("d8c89b",alpha)
			if service.semantic_lod==0 or service.suspended:
				var polygon:=PackedVector2Array([p+Vector2(0,-9),p+Vector2(9,0),p+Vector2(0,9),p+Vector2(-9,0)])
				target.draw_colored_polygon(polygon,fill);polygon.append(polygon[0]);target.draw_polyline(polygon,ink,1.5,true)
			else:
				# A single schematic gate silhouette, registered at the same anchor.
				var width: float=clampf(330*host.zoom,16,120);var height: float=width*.30
				var poly:=PackedVector2Array([p+Vector2(-width*.5,0),p+Vector2(-width*.5,-height),p+Vector2(-width*.28,-height),p+Vector2(-width*.2,-height*1.6),p+Vector2(width*.2,-height*1.6),p+Vector2(width*.28,-height),p+Vector2(width*.5,-height),p+Vector2(width*.5,0)])
				target.draw_colored_polygon(poly,fill);poly.append(poly[0]);target.draw_polyline(poly,ink,1.1,true)
			if row.site_id==service.selected_site:target.draw_arc(p,15,0,TAU,32,Color("ad6844",alpha),1.4,true)
		if host.active=="tongguan" and not service.city.is_empty():
			for item in service.city.records:
				if item.construction_state!="building" or service.semantic_lod<2 or service.suspended:continue
				var slot: Dictionary=host.model.host.slot_by_id(item.slot_id);var poly:=PackedVector2Array()
				for p in slot.polygon_local_m:poly.append(screen(p))
				target.draw_colored_polygon(poly,Color("b5a27d",.65));poly.append(poly[0]);target.draw_polyline(poly,Color("796d52"),1.2,true)
			var force: Array=host.army().position_local();var at: Vector2=screen(force)
			target.draw_line(at,at-Vector2(0,17),Color("5a5245"),1.2,true);target.draw_colored_polygon(PackedVector2Array([at-Vector2(0,17),at+Vector2(13,-13),at-Vector2(0,9)]),Color("b57649"))
	for label in label_plan:
		target.draw_style_box(host.label_style,label.rect)
		target.draw_string(font,label.rect.position+Vector2(7,20),label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("4e493c"))
	if guides and host.active=="tongguan":
		for slot in host.model.host.layout.slots:
			var poly:=PackedVector2Array()
			for p in slot.polygon_local_m:poly.append(screen(p))
			poly.append(poly[0]);target.draw_polyline(poly,Color("54867c"),1,true)
		for x in range(-1024,1025,512):target.draw_line(screen([x,-1024]),screen([x,512]),Color("54867c",.45),1,true)
		for y in range(-1024,513,512):target.draw_line(screen([-1024,y]),screen([1024,y]),Color("54867c",.45),1,true)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		app.get_ref().change_zoom(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.15,event.position);return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:_press=event.position;_dragged=false
		elif not _dragged and app!=null and app.get_ref()!=null:app.get_ref().pick(event.position)
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(_press)>5:_dragged=true
	super._gui_input(event)
