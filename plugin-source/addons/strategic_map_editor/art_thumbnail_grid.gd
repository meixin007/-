@tool
extends ItemList
## Decode/hash on one CPU worker; upload at most one small icon per frame.
const Loader = preload("art_image_loader.gd")
const Catalog = preload("art_catalog.gd")
var library: RefCounted
var worker: Thread
var job_key := ""
var job_generation := -1
var job_bundle := ""
var job_library: RefCounted
var rejected: Dictionary = {}
var cache_generation := -1
var placeholder: Texture2D

func _ready() -> void:
	var blank := Image.create(1,1,false,Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	placeholder=ImageTexture.create_from_image(blank)
	get_v_scroll_bar().value_changed.connect(func(_v): set_process(true))
	resized.connect(func(): set_process(true))
	visibility_changed.connect(func(): set_process(true))
	set_process(false)

func refresh_icons() -> void:
	if cache_generation != Catalog.generation:
		rejected.clear(); cache_generation=Catalog.generation
	for i in item_count:
		var key:=_key(i)
		set_item_icon(i,library.thumbnails.get(key,placeholder))
	set_process(true)

func _key(index: int) -> String:
	var key:=str(get_item_metadata(index))
	return "tree_grove" if key=="mixed_forest" else key

func _process(_delta: float) -> void:
	if worker != null:
		if worker.is_alive(): return
		var result: Dictionary=worker.wait_to_finish()
		worker=null
		if job_generation==Catalog.generation and job_library==library and job_bundle==library.bundle_id:
			if not result.error.is_empty(): rejected[job_key]=true
			var icon: Texture2D=library.accept_thumbnail(job_key,result)
			for i in item_count:
				if _key(i)==job_key: set_item_icon(i,icon)
		job_library=null
	if not is_visible_in_tree() or library==null:
		set_process(false)
		return
	# Item rectangles are in the list's content coordinates, before scrolling.
	var visible_area:=Rect2(Vector2(0,get_v_scroll_bar().value),size)
	for i in item_count:
		var key:=_key(i)
		if library.thumbnails.has(key):
			if get_item_icon(i)!=library.thumbnails[key]: set_item_icon(i,library.thumbnails[key])
			continue
		if rejected.has(key): continue
		if not get_item_rect(i).intersects(visible_area): continue
		var job: Dictionary=library.image_job(key)
		if job.is_empty(): rejected[key]=true; continue
		job_key=key; job_generation=Catalog.generation; job_bundle=library.bundle_id; job_library=library
		worker=Thread.new()
		if worker.start(Loader.thumbnail.bind(job))!=OK:
			worker=null; rejected[key]=true
			library.load_failed.emit("无法启动素材缩略图加载线程。")
		return
	set_process(false)

func _exit_tree() -> void:
	# A worker owns immutable copies and never touches Controls; join before release.
	if worker!=null:
		worker.wait_to_finish()
		worker=null
	job_library=null
