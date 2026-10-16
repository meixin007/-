extends SceneTree
const Doc=preload("document.gd")
const Canvas=preload("map_canvas.gd")
const Cache=preload("runtime_geometry_cache.gd")
var snapshot_path := ""
var game_path := ""
var result_path := ""
var canvas: Control
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:printerr("CACHE_WORKER_ARGUMENTS");quit(1);return
	snapshot_path=args[0];game_path=args[1];result_path=args[2]
	create_timer(120).timeout.connect(func():finish("error","加速数据准备超时；已保存的地图仍可正常载入。"))
	run.call_deferred()
func run() -> void:
	var initial_signature:=Cache.signature(snapshot_path)
	var doc=Doc.new()
	var error: String=doc.load_file(snapshot_path)
	if not error.is_empty():finish("error",error);return
	canvas=Canvas.new();canvas.export_mode=true;canvas.runtime_mode=true;canvas.show_rules=false
	canvas.size=Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])*.25;canvas.zoom=.25
	root.add_child(canvas);canvas.bind_document(doc)
	canvas.water_join.prepare(doc.data.features,canvas.geometry_revision)
	for f in canvas.water_join.waters:
		if canvas.water_join.natural(f):canvas._prepare_natural_water(f)
	# Headless cache preparation must not rely on _draw being called.
	for i in 4:await process_frame
	if Cache.signature(snapshot_path)!=initial_signature or Cache.signature(game_path)!=initial_signature:
		finish("superseded","");return
	var code: Error=Cache.write(snapshot_path,canvas)
	if code!=OK or Cache.read(snapshot_path).is_empty():finish("error","加速数据写入或复读校验失败；地图仍可正常载入。");return
	# Reject rapid subsequent saves. No cache is ever signed for bytes other than
	# the immutable document from which it was built.
	if Cache.signature(game_path)!=initial_signature:finish("superseded","");return
	code=DirAccess.rename_absolute(Cache.cache_path(snapshot_path),Cache.cache_path(game_path))
	if code!=OK:finish("error","无法替换加速数据；地图仍可正常载入。");return
	finish("ready","")
func finish(status: String,message: String) -> void:
	var result:={"version":1,"status":status,"message":message,"map_sha256":FileAccess.get_sha256(snapshot_path)}
	var file:=FileAccess.open(result_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result));file.close()
	for path in [snapshot_path,Cache.cache_path(snapshot_path)]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	if is_instance_valid(canvas):canvas.queue_free()
	quit(1 if status=="error" else 0)
