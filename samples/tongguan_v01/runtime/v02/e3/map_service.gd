extends RefCounted
## One presentation service shared by the actual snapshot and synthetic worlds.
const Loader=preload("res://v02/e1/package_loader.gd")
const Planner=preload("res://v02/e2/visibility_planner.gd")
const Adapter=preload("res://v02/e2/source_adapter.gd")
const Manager=preload("res://v02/e3/residency_manager.gd")
const Coverage=preload("res://v02/e3/coverage_planner.gd")
var loader: RefCounted
var planner=Planner.new()
var manager=Manager.new()
var coverage=Coverage.new()
var renderer: WeakRef
var object_plan: Dictionary={}
var revision:=0
var view:=Rect2()
var zoom:=1.0
var prefetch:=true
var _view_key: Array=[]
func bind_renderer(target: Control) -> void:
	renderer=weakref(target);manager.on_evict=target.detach_resource
func open(entry: Dictionary) -> Dictionary:
	var candidate=Loader.new();var admitted: Dictionary=candidate.admit(entry.path,entry.expected,entry.build_id)
	if not admitted.ok:return admitted
	var adapter=Adapter.new();var snapshot: Dictionary=adapter.snapshot(candidate)
	var result: Dictionary=planner.sync_source(adapter.token(candidate),func():return snapshot)
	if not result.ok:return result
	if renderer!=null and renderer.get_ref()!=null:renderer.get_ref().clear()
	manager.switch_package(candidate);loader=candidate;coverage.bind(loader);_view_key=[];object_plan={};revision+=1
	return {"ok":true}
func set_view(next: Rect2,next_zoom: float) -> Dictionary:
	if loader==null:return {"ok":false,"code":"no_package"}
	var key: Array=[next,next_zoom,prefetch,planner.index.epoch]
	if key==_view_key:return {"ok":true,"changed":false}
	view=next;zoom=next_zoom
	object_plan=planner.plan(view)
	if not object_plan.ok:return object_plan
	var plan: Dictionary=coverage.plan(view,zoom,prefetch)
	var demands: Dictionary=plan.demands.duplicate()
	for item in object_plan.records:
		if item.record_type=="sprite":demands["object:"+item.id]=2
	var result: Dictionary=manager.set_demands(demands)
	if result.ok:_view_key=key;revision+=1
	return result
func tick() -> void:manager.tick()
func release_all() -> void:
	if renderer!=null and renderer.get_ref()!=null:renderer.get_ref().clear()
	manager.clear_demands();_view_key=[];revision+=1
func dispose() -> void:
	release_all();manager.on_evict=Callable();renderer=null
func telemetry() -> Dictionary:return {"residency":manager.telemetry(),"coverage":coverage.stats.duplicate(),"query":planner.telemetry(),"visible_pages":coverage.requests.duplicate(),"object_count":object_plan.get("records",[]).size()}
