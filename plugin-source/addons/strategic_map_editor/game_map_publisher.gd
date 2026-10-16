@tool
extends Node
## Explicitly saved master only. Recovery drafts and other samples never publish.
signal reported(message: String)
const GAME_MAP_PATH := "res://data/maps/current_workshop.map.json"
const Cache=preload("runtime_geometry_cache.gd")
var game_path := GAME_MAP_PATH
var worker_script := "res://addons/strategic_map_editor/game_map_cache_worker.gd"
var busy := false
var queued := false
var pid := -1
var job_path := ""
var result_path := ""
var started_ms := 0
var last_result: Dictionary = {}
var _poll_seconds := 0.0

static func validate_master(doc: RefCounted) -> String:
	var error: String=doc.validate(doc.data)
	if not error.is_empty():return error
	if doc.data.production.coordinate_frame!="game_map_east_asia_4380x2400_scaled_4" or Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])!=Vector2(17520,9600):
		return "这份图不是已登记的东亚游戏整图，请先打开游戏主地图；局部样区请另存。"
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/anshi_rebellion/map_strategy_nodes.json"))
	if not source is Dictionary or not source.get("strategic_nodes") is Array:return "无法读取游戏地点定义；未更新主地图。"
	var nodes:={}
	for node in source.strategic_nodes:nodes[node.node_id]=node.coords
	for f in doc.data.features:
		if f.domain_id.is_empty():continue
		if not nodes.has(f.domain_id) or f.points.size()!=1:return "地图含未知游戏地点绑定："+f.domain_id
		var p: Array=nodes[f.domain_id]
		if Vector2(p[0]*14880,p[1]*9600).distance_to(Vector2(f.points[0][0],f.points[0][1]))>.01:return "已绑定游戏地点不能在工坊迁址："+f.name+"。可移动其外观，或解除游戏 ID 后另作规划点。"
	return ""

static func same_path(a: String,b: String) -> bool:
	if a.is_empty() or b.is_empty():return false
	var first:=ProjectSettings.globalize_path(a).simplify_path()
	var second:=ProjectSettings.globalize_path(b).simplify_path()
	return first.to_lower()==second.to_lower() if OS.get_name()=="Windows" else first==second

func _ready() -> void:
	set_process(false)

func queue_build() -> String:
	if busy:
		queued=true
		reported.emit("游戏主地图已保存；将为最后一次保存更新加速数据。")
		return ""
	if not FileAccess.file_exists(game_path):return "游戏主地图不存在，无法更新加速数据。"
	job_path=ProjectSettings.globalize_path(game_path)+".build-%d-%d.map.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	result_path=job_path+".result.json"
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(game_path),job_path)!=OK:return "游戏主地图已保存，但无法创建加速数据任务。"
	var args:=PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script",worker_script,"--",job_path,ProjectSettings.globalize_path(game_path),result_path])
	pid=OS.create_process(OS.get_executable_path(),args,false)
	if pid<=0:
		_cleanup()
		return "游戏主地图已保存，但无法启动加速数据更新；游戏可正常读取，首次载入可能较慢。"
	busy=true;queued=false;started_ms=Time.get_ticks_msec();last_result={};set_process(true)
	reported.emit("游戏主地图已保存，正在后台更新加速数据…")
	return ""

func _process(delta: float) -> void:
	_poll_seconds+=delta
	if _poll_seconds<.25:return
	_poll_seconds=0
	if OS.is_process_running(pid):
		if Time.get_ticks_msec()-started_ms<150000:return
		OS.kill(pid)
		last_result={"status":"error","message":"加速数据更新超时；地图已保存，游戏会使用正常载入。"}
	else:
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
		last_result=value if value is Dictionary else {"status":"error","message":"加速数据更新未完成；地图已保存，游戏会使用正常载入。"}
	busy=false;set_process(false);_cleanup()
	if queued:
		queued=false
		var error:=queue_build()
		if not error.is_empty():reported.emit(error)
		return
	match last_result.get("status",""):
		"ready":reported.emit("游戏主地图及加速数据已更新。运行游戏，或在游戏设置中点“重载地图”。")
		"superseded":reported.emit("地图又有新保存，旧加速任务已跳过；请保存主地图以更新加速数据。")
		_:reported.emit(str(last_result.get("message","加速数据更新失败；地图已保存。")))

func _cleanup() -> void:
	for path in [job_path,Cache.cache_path(job_path),result_path]:
		if not path.is_empty() and FileAccess.file_exists(path):DirAccess.remove_absolute(path)

# A worker can finish and atomically install its matching cache after this
# workbench closes. Never kill it or remove its immutable input on exit.
