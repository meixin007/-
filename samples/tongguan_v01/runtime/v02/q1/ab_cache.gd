extends RefCounted
## Compatibility facade only. Loading, byte accounting and tasks belong to E3.
var service=preload("res://v02/e3/map_service.gd").new()
var fallback: Texture2D
var slope: Texture2D
var gate: Texture2D
var tree_art: Dictionary={}
var tiles: Array=[]
var tile_textures: Dictionary={}
var ready:=false
var detail_blend:=1.0
var canvas: Control
var model: RefCounted
var mapping: Dictionary={}
var plan_rebuilds:=0
var last_draw: Dictionary={}
var current_x:=0.0
var current_y:=0.0
var current_zoom:=1.0
func setup(entry: Dictionary,host_model: RefCounted) -> Dictionary:
	model=host_model;var result: Dictionary=service.open(entry)
	if not result.ok:return result
	service.prefetch=false;service.manager.on_evict=detach
	tiles=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/terrain_tiles.json")).tiles;mapping=service.loader.provenance.old_tile_mapping
	return result
func update(x: float,y: float,zoom: float) -> void:
	current_x=x;current_y=y;current_zoom=zoom
	var view:=Rect2(x-800/zoom,y-470/zoom,1600/zoom,940/zoom).intersection(Rect2(-12000,-8000,24000,16000))
	if view.has_area():service.set_view(view,zoom)
	var demands: Dictionary=service.manager.demands.duplicate();demands["root"]=0;demands["object:ab_gate"]=0;demands["object:ab_slope"]=0
	# The unchanged old painter uses the shared tree atlas at every detailed view.
	for id in service.loader.objects:
		if service.loader.objects[id].asset_id.begins_with("tree_"):demands["object:"+id]=0;break
	service.manager.set_demands(demands);service.tick()
	fallback=service.manager.texture(service.loader.pages.root.texture_files[0]);slope=service.manager.texture(service.loader.assets.ab_slope.texture_file);gate=service.manager.texture(service.loader.assets.ab_gate.texture_file)
	for id in ["tree_willow","tree_grove"]:
		var asset: Dictionary=service.loader.assets[id];var texture: Texture2D=service.manager.texture(asset.texture_file)
		if texture!=null and not tree_art.has(id):
			var atlas=AtlasTexture.new();atlas.atlas=texture;atlas.region=Rect2(asset.rect_px[0],asset.rect_px[1],asset.rect_px[2],asset.rect_px[3]);atlas.filter_clip=true
			tree_art[id]={"texture":atlas,"anchor":[.5,.78],"ratio":1.0}
	for path in mapping:
		var page: Dictionary=service.loader.pages[mapping[path]];var texture: Texture2D=service.manager.texture(page.texture_files[0])
		if texture!=null:tile_textures[path]=texture
	ready=fallback!=null and slope!=null and gate!=null and tree_art.size()==2
func detach(key: String) -> void:
	if canvas!=null:RenderingServer.canvas_item_clear(canvas.get_canvas_item());canvas.queue_redraw()
	for path in tile_textures.keys():
		if service.manager.key_for(service.loader.pages[mapping[path]].texture_files[0])==key:tile_textures.erase(path)
func begin_draw() -> void:last_draw={"candidates_tested":0,"submitted_objects":0,"plan_rebuilds":0,"plan_usec":0}
func plan_instances(_records: Array) -> Dictionary:
	var start:=Time.get_ticks_usec();var p: Dictionary=service.planner.plan(Rect2(current_x-800/current_zoom,current_y-470/current_zoom,1600/current_zoom,940/current_zoom).intersection(Rect2(-12000,-8000,24000,16000)))
	var entries: Array=[]
	for item in p.get("records",[]):
		if item.get("source_record",{}).has("asset_version"):entries.append({"record":item.source_record})
	last_draw.candidates_tested=p.get("candidate_ids",[]).size();last_draw.plan_usec=Time.get_ticks_usec()-start
	plan_rebuilds=service.planner.stats.sort_calls
	return {"ok":true,"entries":entries}
func tree_submitted() -> void:last_draw.submitted_objects+=1
func draw_terrain(target: CanvasItem,bounds: Rect2) -> void:
	target.draw_texture_rect(fallback,bounds,false)
	for tile in tiles:
		if not tile_textures.has(tile.path):continue
		var page: Dictionary=service.loader.pages[mapping[tile.path]];var core: Array=tile.core_px
		var dest:=Rect2(bounds.position+Vector2(core[0]/600.0,core[1]/400.0)*bounds.size,Vector2(core[2]/600.0,core[3]/400.0)*bounds.size)
		target.draw_texture_rect_region(tile_textures[tile.path],dest,Rect2(8,8,core[2],core[3]),Color.WHITE,false,false)
func dispose() -> void:
	if canvas!=null:RenderingServer.canvas_item_clear(canvas.get_canvas_item());canvas.relief=null;canvas.slope_texture=null;canvas.gate_texture=null;canvas.tree_art.clear()
	fallback=null;slope=null;gate=null;tree_art.clear();tile_textures.clear();service.dispose()
