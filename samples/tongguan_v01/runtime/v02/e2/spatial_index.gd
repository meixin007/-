extends RefCounted
## One immutable record per ID; buckets contain ID references, never record copies.
var identity: Dictionary={}
var cell_m:=512.0
var _records: Dictionary={}
var _buckets: Dictionary={}
var _coverage_by_id: Dictionary={}
var _asset_users: Dictionary={}
var _assets: Dictionary={}
var _versions: Dictionary={}
var _bucket_versions: Dictionary={}
var epoch:=0
var _candidate_signature: Array=[]
var _candidate_cache: Array=[]
var stats: Dictionary={"full_index_builds":0,"source_records_validated":0,"records_reindexed":0,"query_calls":0,"bucket_lookups":0,"candidate_union_builds":0,"candidate_tests":0,"reference_record_enumerations":0,"delta_updates":0}
func fail(code: String,detail: String="") -> Dictionary:return {"ok":false,"code":code,"message":code+": "+detail}
func point(value: Variant) -> bool:
	if not value is Array or value.size()!=2:return false
	for v in value:
		if not (v is int or v is float) or not is_finite(v):return false
	return true
func bounds(value: Variant) -> bool:return value is Array and value.size()==4 and point(value.slice(0,2)) and point(value.slice(2,4)) and value[2]>0 and value[3]>0
func frozen(value: Variant) -> Variant:
	if value is Dictionary:
		for v in value.values():frozen(v)
		value.make_read_only()
	elif value is Array:
		for v in value:frozen(v)
		value.make_read_only()
	return value
func valid_identity(value: Dictionary) -> bool:
	for key in ["world_id","build_id","effective_revision"]:
		if not value.get(key) is String or value[key].is_empty():return false
	return (value.get("asset_bounds_version") is int) and value.asset_bounds_version>=0 and (value.get("cell_m") is int or value.get("cell_m") is float) and value.cell_m>=1 and value.cell_m<=4096
func asset_bounds(record: Dictionary,asset: Dictionary) -> Array:
	if not point(asset.get("anchor_px")) or not bounds(asset.get("rect_px")) or not (asset.get("width_m") is int or asset.get("width_m") is float) or not is_finite(asset.width_m) or asset.width_m<=0:return []
	var s: float=asset.width_m/asset.rect_px[2]
	return [record.position_m[0]-asset.anchor_px[0]*s,record.position_m[1]-asset.anchor_px[1]*s,asset.rect_px[2]*s,asset.rect_px[3]*s]
func prepare(record: Variant,asset_defs: Dictionary,key: String="") -> Dictionary:
	stats.source_records_validated+=1
	if not record is Dictionary or not record.get("id") is String or record.id.is_empty():return fail("invalid_id")
	if not key.is_empty() and record.id!=key:return fail("key_id_mismatch",key)
	if record.get("source_key",record.id)!=record.id:return fail("key_id_mismatch",record.id)
	if not point(record.get("position_m")) or not bounds(record.get("paint_bounds_m")):return fail("invalid_bounds",record.id)
	var owner: Array=[floori(record.position_m[0]/512.0),floori(record.position_m[1]/512.0)]
	if not point(record.get("owner")) or record.owner[0]!=owner[0] or record.owner[1]!=owner[1]:return fail("owner_mismatch",record.id)
	if not (record.get("render_plane") is int or record.get("render_plane") is float) or not is_finite(record.render_plane) or not (record.get("ground_depth") is int or record.get("ground_depth") is float) or not is_finite(record.ground_depth):return fail("invalid_sort_key",record.id)
	if not record.get("payload_shard") is String or record.payload_shard.is_empty() or record.payload_shard.begins_with("/") or ":" in record.payload_shard or "\\" in record.payload_shard or ".." in record.payload_shard:return fail("invalid_payload_shard",record.id)
	if record.get("record_type")=="sprite":
		if not asset_defs.has(record.get("asset_id")):return fail("unknown_asset",record.id)
		var expected: Array=asset_bounds(record,asset_defs[record.asset_id])
		if expected.is_empty():return fail("invalid_asset_bounds",record.id)
		for i in 4:
			if absf(expected[i]-record.paint_bounds_m[i])>.00001:return fail("paint_bounds_mismatch",record.id)
	elif record.get("record_type")!="polyline":return fail("invalid_record_kind",record.id)
	var result: Dictionary=record.duplicate(true)
	result.owner=owner;result.render_plane=float(record.render_plane);result.ground_depth=float(record.ground_depth)
	result.position_m=[float(record.position_m[0]),float(record.position_m[1])]
	result.paint_bounds_m=[]
	for v in record.paint_bounds_m:result.paint_bounds_m.append(float(v))
	result.representation_id=record.get("representation_id","detail")
	result.baked_representation=record.get("baked_representation",false)
	if not result.representation_id is String or result.representation_id.is_empty() or not result.baked_representation is bool:return fail("invalid_representation",record.id)
	return {"ok":true,"record":result}
func keys_for(b: Array,size_m: float) -> Array:
	var left:=floori(b[0]/size_m);var top:=floori(b[1]/size_m)
	var right:=ceili((b[0]+b[2])/size_m)-1;var bottom:=ceili((b[1]+b[3])/size_m)-1
	if right-left>65535 or bottom-top>65535 or (right-left+1)*(bottom-top+1)>65536:return []
	var result: Array=[]
	for y in range(top,bottom+1):
		for x in range(left,right+1):result.append(str(x)+":"+str(y))
	return result
func sync(raw: Variant,next_identity: Dictionary,asset_defs: Dictionary) -> Dictionary:
	if not valid_identity(next_identity):return fail("invalid_cache_identity")
	if not raw is Array and not raw is Dictionary:return fail("invalid_snapshot")
	var prepared: Dictionary={};var all_keys: Dictionary={}
	if raw is Dictionary:
		for key in raw:
			if not key is String:return fail("invalid_id")
			var item: Dictionary=prepare(raw[key],asset_defs,key)
			if not item.ok:return item
			prepared[key]=item.record
	else:
		for record in raw:
			if record is Dictionary and prepared.has(record.get("id")):return fail("duplicate_id",str(record.get("id")))
			var item: Dictionary=prepare(record,asset_defs)
			if not item.ok:return item
			prepared[item.record.id]=item.record
	for id in prepared:
		var coverage: Array=keys_for(prepared[id].paint_bounds_m,float(next_identity.cell_m))
		if coverage.is_empty():return fail("bounds_too_large",id)
		all_keys[id]=coverage
	var replacement: bool=identity.is_empty() or identity.world_id!=next_identity.world_id or identity.build_id!=next_identity.build_id or cell_m!=float(next_identity.cell_m)
	var changed: Dictionary={};var removed: Array=[]
	if replacement:
		for id in prepared:changed[id]=prepared[id]
	else:
		for id in prepared:
			if not _records.has(id) or _records[id]!=prepared[id]:changed[id]=prepared[id]
		for id in _records:
			if not prepared.has(id):removed.append(id)
	if replacement:
		_records.clear();_buckets.clear();_coverage_by_id.clear();_asset_users.clear();_versions.clear();_bucket_versions.clear();_candidate_signature=[];_candidate_cache=[]
		stats.full_index_builds+=1
	identity=next_identity.duplicate(true);cell_m=float(identity.cell_m);_assets=asset_defs.duplicate(true);epoch+=1
	for id in removed:erase_record(id)
	for id in changed:
		if _records.has(id):erase_record(id)
		insert_record(changed[id],all_keys[id])
	return {"ok":true,"changed":changed.size(),"removed":removed.size(),"full_replacement":replacement}
func erase_record(id: String) -> void:
	for key in _coverage_by_id.get(id,[]):
		_buckets[key].erase(id)
		if _buckets[key].is_empty():_buckets.erase(key);_bucket_versions.erase(key)
		else:_bucket_versions[key]=epoch
	var asset_id: String=_records[id].get("asset_id","")
	if _asset_users.has(asset_id):
		_asset_users[asset_id].erase(id)
		if _asset_users[asset_id].is_empty():_asset_users.erase(asset_id)
	_records.erase(id);_coverage_by_id.erase(id);_versions.erase(id)
func insert_record(record: Dictionary,coverage: Array) -> void:
	var id: String=record.id
	_records[id]=frozen(record);_versions[id]=epoch;_coverage_by_id[id]=coverage
	for key in coverage:
		if not _buckets.has(key):_buckets[key]={}
		_buckets[key][id]=true;_bucket_versions[key]=epoch
	if record.has("asset_id"):
		if not _asset_users.has(record.asset_id):_asset_users[record.asset_id]={}
		_asset_users[record.asset_id][id]=true
	stats.records_reindexed+=1
func apply_delta(upserts: Array,removals: Array,next_revision: String) -> Dictionary:
	if identity.is_empty() or next_revision.is_empty():return fail("invalid_revision")
	var changed: Dictionary={};var coverage: Dictionary={};var deleted: Dictionary={}
	for id in removals:
		if not id is String or deleted.has(id) or not _records.has(id):return fail("invalid_removal")
		deleted[id]=true
	for raw in upserts:
		var item: Dictionary=prepare(raw,_assets)
		if not item.ok:return item
		var id: String=item.record.id
		if changed.has(id) or deleted.has(id):return fail("conflicting_delta",id)
		changed[id]=item.record;coverage[id]=keys_for(item.record.paint_bounds_m,cell_m)
		if coverage[id].is_empty():return fail("bounds_too_large",id)
	epoch+=1;identity.effective_revision=next_revision
	for id in deleted:erase_record(id)
	for id in changed:
		if _records.has(id):erase_record(id)
		insert_record(changed[id],coverage[id])
	stats.delta_updates+=1
	return {"ok":true,"changed":changed.size(),"removed":deleted.size()}
func update_asset(id: String,descriptor: Dictionary,bounds_version: int) -> Dictionary:
	if not _assets.has(id) or bounds_version<=int(identity.get("asset_bounds_version",-1)):return fail("stale_asset_bounds_version")
	var changed: Dictionary={};var coverage: Dictionary={};var next_assets: Dictionary=_assets.duplicate(true);next_assets[id]=descriptor.duplicate(true)
	for object_id in _asset_users.get(id,{}):
		var record: Dictionary=_records[object_id].duplicate(true)
		record.paint_bounds_m=asset_bounds(record,descriptor)
		var item: Dictionary=prepare(record,next_assets)
		if not item.ok:return item
		changed[object_id]=item.record;coverage[object_id]=keys_for(item.record.paint_bounds_m,cell_m)
		if coverage[object_id].is_empty():return fail("bounds_too_large",object_id)
	epoch+=1;identity.asset_bounds_version=bounds_version;_assets=next_assets
	for object_id in changed:
		erase_record(object_id);insert_record(changed[object_id],coverage[object_id])
	return {"ok":true,"changed":changed.size()}
func intersects(b: Array,view: Rect2) -> bool:
	return b[0]<view.end.x and view.position.x<b[0]+b[2] and b[1]<view.end.y and view.position.y<b[1]+b[3]
func query(view: Rect2) -> Dictionary:
	if view.size.x<=0 or view.size.y<=0 or not view.is_finite():return fail("invalid_view")
	stats.query_calls+=1
	var keys: Array=keys_for([view.position.x,view.position.y,view.size.x,view.size.y],cell_m)
	if keys.is_empty():return fail("view_too_large")
	var signature: Array=[]
	for key in keys:signature.append([key,_bucket_versions.get(key,0)])
	stats.bucket_lookups+=keys.size()
	if signature!=_candidate_signature:
		var ids: Dictionary={}
		for key in keys:
			for id in _buckets.get(key,{}):ids[id]=true
		_candidate_cache=ids.keys();_candidate_signature=signature;stats.candidate_union_builds+=1
	var visible: Array=[];var payloads: Dictionary={}
	for id in _candidate_cache:
		stats.candidate_tests+=1
		if intersects(_records[id].paint_bounds_m,view):
			visible.append(id);payloads[_records[id].payload_shard]=true
	return {"ok":true,"candidate_ids":_candidate_cache.duplicate(),"visible_ids":visible,"required_shards":payloads.keys(),"cache_identity":identity.duplicate(true)}
func record(id: String) -> Dictionary:return _records.get(id,{})
func version(id: String) -> int:return int(_versions.get(id,-1))
func object_count() -> int:return _records.size()
func bucket_members(key: String) -> Array:return _buckets.get(key,{}).keys()
func reference_records() -> Array:
	stats.reference_record_enumerations+=1
	return _records.values()
