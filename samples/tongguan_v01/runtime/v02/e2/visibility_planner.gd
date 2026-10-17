extends RefCounted
const Index=preload("res://v02/e2/spatial_index.gd")
var index=Index.new()
var stats: Dictionary={"snapshot_reads":0,"visible_plan_builds":0,"sort_calls":0,"plan_reuses":0,"reference_full_scans":0}
var _source_token: Dictionary={}
var _last_epoch:=-1
var _last_view:=Rect2()
var _last_display:=""
var _last_lod:=""
var _visible_versions: Dictionary={}
var _draw_records: Array=[]
var _query: Dictionary={}
func sync_source(token: Dictionary,provider: Callable) -> Dictionary:
	if token==_source_token:return {"ok":true,"changed":false}
	stats.snapshot_reads+=1
	var snapshot: Variant=provider.call()
	if not snapshot is Dictionary or not snapshot.get("records") is Array and not snapshot.get("records") is Dictionary or not snapshot.get("assets") is Dictionary:return index.fail("invalid_snapshot")
	var result: Dictionary=index.sync(snapshot.records,token,snapshot.assets)
	if result.ok:
		_source_token=token.duplicate(true)
		if result.full_replacement:_visible_versions={};_draw_records=[];_last_epoch=-1;_last_view=Rect2()
	return result
func sorted_records(records: Array) -> Array:
	records.sort_custom(func(a,b):
		if a.render_plane!=b.render_plane:return a.render_plane<b.render_plane
		if a.ground_depth!=b.ground_depth:return a.ground_depth<b.ground_depth
		return a.id<b.id)
	return records
func plan(view: Rect2,display_revision: String="1",lod: String="detail") -> Dictionary:
	if view!=_last_view or _last_epoch!=index.epoch or _query.is_empty():
		_query=index.query(view)
		if not _query.ok:return _query
		_last_view=view;_last_epoch=index.epoch
	var versions: Dictionary={}
	for id in _query.visible_ids:versions[id]=index.version(id)
	if versions!=_visible_versions or display_revision!=_last_display or lod!=_last_lod:
		var records: Array=[]
		for id in _query.visible_ids:
			var item: Dictionary=index.record(id)
			if not item.baked_representation:records.append(item)
		_draw_records=sorted_records(records);_draw_records.make_read_only()
		_visible_versions=versions;_last_display=display_revision;_last_lod=lod
		stats.visible_plan_builds+=1;stats.sort_calls+=1
	else:stats.plan_reuses+=1
	return {"ok":true,"records":_draw_records,"candidate_ids":_query.candidate_ids.duplicate(),"visible_ids":_query.visible_ids.duplicate(),"required_shards":_query.required_shards.duplicate(),"cache_identity":index.identity.duplicate(true)}
func full_scan_reference(view: Rect2) -> Array:
	stats.reference_full_scans+=1
	var result: Array=[]
	for item in index.reference_records():
		var b: Array=item.paint_bounds_m
		if Rect2(b[0],b[1],b[2],b[3]).intersects(view) and not item.baked_representation:result.append(item)
	return sorted_records(result)
func telemetry() -> Dictionary:return {"planner":stats.duplicate(true),"index":index.stats.duplicate(true),"objects":index.object_count(),"identity":index.identity.duplicate(true)}
