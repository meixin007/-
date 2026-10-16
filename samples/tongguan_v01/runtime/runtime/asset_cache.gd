extends RefCounted
var fallback: Texture2D
var slope: Texture2D
var gate: Texture2D
var tree_art: Dictionary={}
var tiles: Array=[]
var tile_textures: Dictionary={}
var ready:=false
var detail_blend:=0.0
const BLEND_USEC=250000.0
var attach_ms: Array=[]
var started_usec:=0
var ready_usec:=0
var suspended:=false
var draw_reference:=false
var reference: Texture2D
var fallback_draw_count:=0
func png(path: String)->Texture2D:return load(path) as Texture2D
func _init()->void:
	started_usec=Time.get_ticks_usec();fallback=png("res://bundle/terrain_fallback.png");slope=png("res://bundle/slope.png");gate=png("res://bundle/art/gate_eastwest.png")
	var descriptors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/art_descriptors.json"));var textures={}
	for id in descriptors:
		var d: Dictionary=descriptors[id]
		if not textures.has(d.path):textures[d.path]=png(d.path)
		var atlas=AtlasTexture.new();atlas.atlas=textures[d.path];atlas.region=Rect2(d.rect[0],d.rect[1],d.rect[2],d.rect[3]);atlas.filter_clip=true
		tree_art[id]={"texture":atlas,"anchor":d.anchor,"ratio":float(d.rect[3])/float(d.rect[2])}
	tiles=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/terrain_tiles.json")).tiles
	for tile in tiles:ResourceLoader.load_threaded_request(tile.path,"Texture2D",false,ResourceLoader.CACHE_MODE_REUSE)
func tick()->void:
	if suspended:return
	if ready:
		detail_blend=clampf(float(Time.get_ticks_usec()-ready_usec)/BLEND_USEC,0,1);return
	var frame_start=Time.get_ticks_usec()
	for tile in tiles:
		if tile_textures.has(tile.path):continue
		if ResourceLoader.load_threaded_get_status(tile.path)!=ResourceLoader.THREAD_LOAD_LOADED:continue
		var start=Time.get_ticks_usec();tile_textures[tile.path]=ResourceLoader.load_threaded_get(tile.path);attach_ms.append((Time.get_ticks_usec()-start)/1000.0)
		if Time.get_ticks_usec()-frame_start>=2000:break
	if tile_textures.size()==tiles.size():ready=true;ready_usec=Time.get_ticks_usec()
func draw_terrain(canvas: CanvasItem,bounds: Rect2)->void:
	if draw_reference:
		if reference==null:reference=png("res://bundle/terrain_reference.png")
		canvas.draw_texture_rect(reference,bounds,false);return
	if not ready:
		fallback_draw_count+=1;canvas.draw_texture_rect(fallback,bounds,false);return
	if detail_blend<1.0:canvas.draw_texture_rect(fallback,bounds,false)
	for tile in tiles:
		var core: Array=tile.core_px;var region: Array=tile.source_region_px
		var dest=Rect2(bounds.position+Vector2(core[0]/600.0,core[1]/400.0)*bounds.size,Vector2(core[2]/600.0,core[3]/400.0)*bounds.size)
		# Bleed pixels are valid neighbors. UV clipping would clamp at each core
		# and create a one-pixel interpolation seam despite identical edge data.
		canvas.draw_texture_rect_region(tile_textures[tile.path],dest,Rect2(region[0],region[1],region[2],region[3]),Color(1,1,1,detail_blend),false,false)
