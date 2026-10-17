extends Control
## Each retained command owns explicit resource references; eviction clears both.
const Audit=preload("res://v02/e2/submission_audit.gd")
var presenter: WeakRef
var nodes: Dictionary={}
var audit=Audit.new()
var submissions: Array=[]
var errors: Array=[]
var fade_seconds:=.18
var fades: Dictionary={}
var finished_fades: Dictionary={}
var stats: Dictionary={"command_builds":0,"command_clears":0,"eviction_callbacks":0,"transforms":0,"max_plan_usec":0,"combined_budget_overruns":0,"deferred_plans":0}
var origin: Array=[0.0,0.0]
var root: Node2D
var _plan_key: Array=[]
var _deferred:=false
var _command_start:=0
var _remaining_usec:=2000
class DrawUnit extends Node2D:
	var texture: Texture2D
	var destination:=Rect2()
	var region:=Rect2()
	var opacity:=1.0
	var points:=PackedVector2Array()
	var color:=Color.WHITE
	var width:=1.0
	func _draw() -> void:
		if texture!=null:draw_texture_rect_region(texture,destination,region,Color(1,1,1,opacity),false,false)
		elif points.size()>1:draw_polyline(points,color,width,true)
	func release() -> void:
		RenderingServer.canvas_item_clear(get_canvas_item())
		texture=null;points=PackedVector2Array()
func _ready() -> void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	var paper=ColorRect.new();paper.color=Color("ded8bc");paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);paper.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(paper)
	root=Node2D.new();add_child(root)
func rect(b: Array) -> Rect2:return Rect2(b[0]-origin[0],b[1]-origin[1],b[2],b[3])
func point(p: Array) -> Vector2:return Vector2(p[0]-origin[0],p[1]-origin[1])
func remove_unit(id: String) -> void:
	if not nodes.has(id):return
	var unit: Node2D=nodes[id].node
	unit.release();root.remove_child(unit);unit.queue_free();nodes.erase(id);stats.command_clears+=1
func clear() -> void:
	for id in nodes.keys():remove_unit(id)
	fades={};finished_fades={};_plan_key=[];submissions=[]
func detach_resource(key: String) -> void:
	stats.eviction_callbacks+=1
	for id in nodes.keys():
		if nodes[id].key==key:remove_unit(id)
	fades={};finished_fades={}
	_plan_key=[]
func unit(id: String,key: String,texture: Texture2D,destination: Rect2,region: Rect2,alpha: float,used: Dictionary) -> void:
	used[id]=true
	var signature: Array=[key,destination,region,alpha]
	if nodes.has(id) and nodes[id].signature==signature:root.move_child(nodes[id].node,-1);return
	if Time.get_ticks_usec()-_command_start>=_remaining_usec:_deferred=true;return
	remove_unit(id)
	var node=DrawUnit.new();node.texture=texture;node.destination=destination;node.region=region;node.opacity=alpha;root.add_child(node)
	nodes[id]={"node":node,"key":key,"signature":signature};stats.command_builds+=1
func terrain_unit(id: String,page: Dictionary,target: Array,manager: RefCounted,used: Dictionary,alpha: float=1) -> void:
	var b: Array=page.bounds_m
	for file in page.texture_files:
		var texture: Texture2D=manager.texture(file)
		if texture==null:continue
		var region:=Rect2(page.gutter_px+(target[0]-b[0])/b[2]*page.core_px[0],page.gutter_px+(target[1]-b[1])/b[3]*page.core_px[1],target[2]/b[2]*page.core_px[0],target[3]/b[3]*page.core_px[1])
		unit(id+file,manager.key_for(file),texture,rect(target),region,alpha,used)
func render(service: RefCounted,x: float,y: float,zoom: float) -> void:
	var next_origin: Array=[floor(x/8192)*8192,floor(y/8192)*8192]
	if next_origin!=origin:clear();origin=next_origin
	root.position=size*.5-Vector2(x-origin[0],y-origin[1])*zoom;root.scale=Vector2(zoom,zoom);stats.transforms+=1
	var now:=Time.get_ticks_msec()/1000.0;var key: Array=[service.revision,service.manager.revision,origin]
	if key==_plan_key and fades.is_empty() and not _deferred:return
	_command_start=Time.get_ticks_usec();_deferred=false
	var adopted: int=int(service.manager.frames.back().attach_usec) if not service.manager.frames.is_empty() else 0
	_remaining_usec=maxi(0,int(service.manager.profile.attach_usec)-adopted)
	var used: Dictionary={};submissions=[];audit.begin_frame()
	# Sparse detailed coverage never erases the base outside its existing leaves.
	for id in service.coverage.roots:
		if service.manager.ready(id):terrain_unit("base:"+id,service.loader.pages[id],service.loader.pages[id].bounds_m,service.manager,used)
	for id in service.coverage.requests:
		var resolved: Dictionary=service.coverage.resolve(id,service.manager)
		if not resolved.ok:continue
		var selected: String=resolved.selected;var requested: Dictionary=service.loader.pages[id];var page: Dictionary=service.loader.pages[selected]
		var alpha:=1.0
		if selected==id and not finished_fades.has(id) and not page.parent_id.is_empty() and service.manager.ready(page.parent_id) and fade_seconds>0:
			if not fades.has(id):fades[id]=now
			alpha=clampf((now-float(fades[id]))/fade_seconds,0,1)
			if alpha<1:terrain_unit("old:"+id,service.loader.pages[page.parent_id],requested.bounds_m,service.manager,used)
		terrain_unit("page:"+id,page,requested.bounds_m,service.manager,used,alpha)
		if alpha>=1 and fades.has(id):fades.erase(id);finished_fades[id]=true
	for item in service.object_plan.get("records",[]):
		var submitted: Dictionary=audit.submit(item.id,"detail")
		if not submitted.ok:errors.append(submitted);continue
		var id: String="object:"+item.id
		if item.record_type=="sprite":
			var asset: Dictionary=service.loader.assets[item.asset_id];var texture: Texture2D=service.manager.texture(asset.texture_file)
			if texture==null:continue
			unit(id,service.manager.key_for(asset.texture_file),texture,rect(item.paint_bounds_m),Rect2(asset.rect_px[0],asset.rect_px[1],asset.rect_px[2],asset.rect_px[3]),1,used)
		else:
			used[id]=true
			if not nodes.has(id):
				if Time.get_ticks_usec()-_command_start>=_remaining_usec:_deferred=true;continue
				var node=DrawUnit.new();node.color=Color(item.color);node.width=item.width_m
				for p in item.points_m:node.points.append(point(p))
				root.add_child(node);nodes[id]={"node":node,"key":"","signature":[]};stats.command_builds+=1
			root.move_child(nodes[id].node,-1)
		submissions.append(item.id)
	for id in nodes.keys():
		if not used.has(id):remove_unit(id)
	for id in fades.keys():
		if id not in service.coverage.requests:fades.erase(id)
	for id in finished_fades.keys():
		if id not in service.coverage.requests:finished_fades.erase(id)
	_plan_key=key
	var elapsed:=Time.get_ticks_usec()-_command_start
	stats.max_plan_usec=maxi(stats.max_plan_usec,elapsed)
	if elapsed+adopted>int(service.manager.profile.attach_usec):stats.combined_budget_overruns+=1
	if _deferred:stats.deferred_plans+=1
	if not service.manager.frames.is_empty():service.manager.frames.back().renderer_plan_usec=elapsed;service.manager.frames.back().adopt_plus_plan_usec=elapsed+adopted
func _gui_input(event: InputEvent) -> void:
	if presenter==null or presenter.get_ref()==null:return
	var app=presenter.get_ref()
	if event is InputEventMouseMotion and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:app.pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:app.change_zoom(1.15)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:app.change_zoom(1/1.15)
