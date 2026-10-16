@tool
extends RefCounted
const Catalog = preload("art_catalog.gd")
const Loader = preload("art_image_loader.gd")
signal load_failed(message: String)
var textures: Dictionary = {}
var thumbnails: Dictionary = {}
var body_profiles: Dictionary = {}
var hit_images: Dictionary = {}
var error := ""
var loaded := false
var bundle_id := "tongguan_v1"
var _generation := -1
var _expected: Dictionary = {}
var _failed: Dictionary = {}
# Only the last decoded atlas is retained, never the entire bundle chain.
var _source_path := ""
var _source: Image

func _clear() -> void:
	textures.clear(); thumbnails.clear(); body_profiles.clear(); hit_images.clear()
	_expected.clear(); _failed.clear(); _source_path=""; _source=null
	error=""; loaded=false; _generation=Catalog.generation

func set_bundle(id: String) -> void:
	var selected := id if not id.is_empty() else "tongguan_v1"
	if selected == bundle_id: return
	bundle_id=selected
	_clear()

func reload() -> String:
	Catalog.invalidate_cache()
	_clear()
	return ensure_loaded()

func ensure_loaded() -> String:
	if _generation != Catalog.generation: _clear()
	if loaded: return error
	loaded=true
	error=Catalog.error()
	if not error.is_empty(): return error
	var chain: Array=Catalog.bundle_chain(bundle_id)
	if chain.is_empty():
		error="缺少所需美术素材包："+bundle_id
		return error
	for id in chain:
		var root: String=Catalog.bundle_root(id)
		var path:=root+"manifest.json"
		var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not manifest is Dictionary or manifest.get("bundle_id")!=id or not manifest.get("assets") is Array:
			error="扩展素材清单缺失或损坏："+path
			return error
		for item in manifest.assets:
			if item is Dictionary: _expected[root+str(item.get("file",""))]=item
	for key in Catalog.catalog().assets:
		if not Catalog.bundle_contains(bundle_id,Catalog.asset_bundle(key)): continue
		error=Catalog.validate_descriptor(key)
		if not error.is_empty(): return error
		var path: String=Catalog.asset_root(key)+str(Catalog.descriptor(key).atlas)
		if not _expected.has(path) or not FileAccess.file_exists(path):
			error="缺少美术素材："+path
			return error
	return error

func image_job(key: String) -> Dictionary:
	if not ensure_loaded().is_empty() or _failed.has(key): return {}
	if not Catalog.bundle_contains(bundle_id,Catalog.asset_bundle(key)): return {}
	var descriptor: Dictionary=Catalog.descriptor(key)
	if descriptor.is_empty(): return {}
	var path: String=Catalog.asset_root(key)+str(descriptor.atlas)
	return {"key":key,"path":path,"expected":_expected[path].duplicate(true),"descriptor":descriptor.duplicate(true)}

func accept_thumbnail(key: String, result: Dictionary) -> Texture2D:
	if not result.error.is_empty():
		_fail(key,result.error)
		return null
	if not thumbnails.has(key): thumbnails[key]=ImageTexture.create_from_image(result.image)
	return thumbnails[key]

func thumbnail(key: String) -> Texture2D:
	ensure_loaded()
	if thumbnails.has(key): return thumbnails[key]
	var job:=image_job(key)
	if job.is_empty(): return null
	return accept_thumbnail(key,Loader.thumbnail(job))

func _fail(key: String, issue: String) -> void:
	error=issue; _failed[key]=issue
	load_failed.emit(issue)

func texture(key: String) -> Texture2D:
	ensure_loaded()
	if textures.has(key): return textures[key]
	var job:=image_job(key)
	if job.is_empty(): return null
	var result:=Loader.read_cell(job,_source if _source_path==job.path else null)
	if not result.error.is_empty():
		_fail(key,result.error)
		return null
	_source_path=job.path; _source=result.source
	var cell: Image=result.cell
	cell.generate_mipmaps()
	textures[key]=ImageTexture.create_from_image(cell)
	return textures[key]

func hit_image(key: String) -> Image:
	if not hit_images.has(key):
		var tex:=texture(key)
		if tex==null: return null
		hit_images[key]=tex.get_image()
	return hit_images[key]
func site_rect(f: Dictionary, point: Vector2) -> Rect2:
	var key := Catalog.site_variant(f)
	var visual: Dictionary = f.get("visual", {})
	var offset: Array = visual.get("offset", [0,0])
	return instance_rect(key, point + Vector2(offset[0], offset[1]), float(f.scale) * float(visual.get("width_factor", 1.0)))

func instance_rect(key: String, point: Vector2, scale: float = 1.0) -> Rect2:
	var tex := texture(key)
	var item: Dictionary = Catalog.descriptor(key)
	if tex == null or item.is_empty(): return Rect2()
	var width := float(item.width) * scale
	var extent := Vector2(width, width * tex.get_height() / tex.get_width())
	var anchor: Array = item.anchor
	return Rect2(point - extent * Vector2(anchor[0], anchor[1]), extent)

func body_rect(key: String, rect: Rect2) -> Rect2:
	# Ignore the transparent halo and sparse pale brush marks below a sprite.
	# This reads source pixels for geometry metadata; it does not edit the bitmap.
	if not body_profiles.has(key):
		var tex:=texture(key)
		if tex==null: return rect
		var img:=tex.get_image()
		var top:=img.get_height(); var bottom:=-1
		for y in range(img.get_height()):
			var count:=0
			for x in range(img.get_width()):
				var color:=img.get_pixel(x,y)
				if color.a>.8 and minf(color.r,minf(color.g,color.b))<.45: count+=1
			if count>maxi(2,int(img.get_width()*.015)): top=mini(top,y); bottom=maxi(bottom,y)
		body_profiles[key]=Rect2(0,float(top)/img.get_height(),1,float(bottom-top+1)/img.get_height()) if bottom>top else Rect2(0,0,1,1)
	var profile: Rect2=body_profiles[key]
	return Rect2(rect.position+profile.position*rect.size,profile.size*rect.size)

