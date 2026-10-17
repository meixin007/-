extends "res://v02/e3/map_service.gd"
## E1 admission, E2 index/deltas and E3 residency; no gameplay state is owned here.
const Policy=preload("res://v02/c1/display_policy.gd")
const City=preload("res://v02/v2/adapter.gd")
var policy=Policy.new()
var authority: WeakRef
var facade: WeakRef
var city: Dictionary={}
var semantic_lod:=0
var detail_ready:=false
var suspended:=false
var selected_site:="tongguan"
var pending_plan: Dictionary={}
var dynamic_ids: Dictionary={}
var _authority_token: Array=[]
var _publication_token: Array=[]
var _publish_key: Array=[]
var integration_stats: Dictionary={"authority_reads":0,"state_deltas":0,"semantic_switches":0,"package_opens":0,"reloads":0}
func _init() -> void:coverage=load("res://v02/c1/coverage_planner.gd").new()
func bind_authority(controller: RefCounted,host: RefCounted) -> void:authority=weakref(controller);facade=weakref(host)
func open(entry: Dictionary) -> Dictionary:
	var result: Dictionary=super.open(entry)
	if not result.ok:return result
	city={};dynamic_ids={};pending_plan={};_authority_token=[];_publication_token=[];_publish_key=[];suspended=false;detail_ready=false;semantic_lod=0
	integration_stats.package_opens+=1
	return sync_authority()
func sync_authority() -> Dictionary:
	if loader==null or loader.manifest.compatibility.site_id!="tongguan" or authority==null or authority.get_ref()==null:return {"ok":true}
	var controller=authority.get_ref();var token: Array=[controller.context.get_instance_id(),controller.context.world_epoch,controller.context.state.get_instance_id(),controller.context.state.state_revision]
	if token==_authority_token:return {"ok":true,"changed":false}
	# Saved authoring remains an input, never silently replaced by the latest art package.
	var publication_token: Array=[controller.context.world_epoch,controller.context.state.get_instance_id(),controller.context.state.state_revision]
	if publication_token!=_publication_token:
		var compatible: Dictionary=validate_authoring(controller.authoring_projection())
		if not compatible.ok:suspend_display();return compatible
		_publication_token=publication_token
	city=City.new().project(controller,facade.get_ref());integration_stats.authority_reads+=1
	var updates: Array=[];var next_ids: Dictionary={}
	for item in city.records:
		if item.asset_id.is_empty():continue
		var raw: Dictionary=make_sprite(item.slot_id,item.position_m,item.asset_id)
		raw.site_id=item.site_id;raw.slot_id=item.slot_id;raw.building_id=item.building_id;raw.construction_state=item.construction_state;raw.damage_level=item.damage_level
		updates.append(raw);next_ids[raw.id]=true
	updates.append(make_sprite("wall_east",[84.8125,55.1484375],city.wall_asset));next_ids.wall_east=true
	var removals: Array=[]
	for id in dynamic_ids:
		if not next_ids.has(id):removals.append(id)
	var result: Dictionary=planner.index.apply_delta(updates,removals,str(token))
	if not result.ok:return result
	for item in updates:
		manager.page_files["object:"+item.id]=[loader.assets[item.asset_id].texture_file]
		manager.page_states["object:"+item.id]="UNLOADED"
	dynamic_ids=next_ids;_authority_token=token;_view_key=[];integration_stats.state_deltas+=1
	return {"ok":true,"changed":true}
func validate_authoring(effective: Dictionary) -> Dictionary:
	if loader.canonical_fixed6(effective).sha256_text()!=loader.provenance.get("effective_authoring_sha256",""):return {"ok":false,"code":"incompatible_saved_authoring","message":"当前制作或存档表现与本候选包不符；已保留原状态并卸载候选显示，请使用匹配的表现包。"}
	return {"ok":true}
func make_sprite(id: String,p: Array,asset_id: String) -> Dictionary:
	var asset: Dictionary=loader.assets[asset_id];var s: float=asset.width_m/asset.rect_px[2]
	return {"id":id,"source_key":id,"record_type":"sprite","position_m":p.duplicate(),"owner":[floori(p[0]/512),floori(p[1]/512)],"asset_id":asset_id,"paint_bounds_m":[p[0]-asset.anchor_px[0]*s,p[1]-asset.anchor_px[1]*s,asset.rect_px[2]*s,asset.rect_px[3]*s],"render_plane":2,"ground_depth":p[1],"payload_shard":"instances/objects.json"}
func set_view(next: Rect2,next_zoom: float) -> Dictionary:
	if loader==null:return {"ok":false,"code":"no_package"}
	var synced: Dictionary=sync_authority()
	if not synced.ok:return synced
	var chosen: int=policy.choose(semantic_lod,next_zoom,1200)
	if chosen!=semantic_lod:semantic_lod=chosen;integration_stats.semantic_switches+=1
	var key: Array=[next,next_zoom,prefetch,planner.index.epoch,semantic_lod,suspended]
	if key==_view_key:return {"ok":true,"changed":false}
	view=next;zoom=next_zoom;pending_plan={"ok":true,"records":[],"candidate_ids":[],"visible_ids":[]}
	var b: Array=loader.catalog.bounds_m;var bounded:=next.intersection(Rect2(b[0],b[1],b[2],b[3]))
	var demands: Dictionary={}
	if not suspended and bounded.has_area():
		var pages: Dictionary=coverage.plan(bounded,zoom,prefetch);demands=pages.demands.duplicate()
		if semantic_lod>=2:
			pending_plan=planner.plan(bounded,"1",str(semantic_lod))
			if not pending_plan.ok:return pending_plan
			var filtered: Array=[]
			for item in pending_plan.records:
				if semantic_lod==2 and item.get("asset_id","").begins_with("tree_"):continue
				if semantic_lod==2 and item.id.begins_with("v1.preview."):continue
				filtered.append(item)
				if item.record_type=="sprite":demands["object:"+item.id]=1 if selected_site=="tongguan" else 2
			pending_plan=pending_plan.duplicate();pending_plan.records=filtered
	else:coverage.requests=[]
	var result: Dictionary=manager.set_demands(demands)
	if not result.ok:return result
	_view_key=key;revision+=1;publish_ready();return {"ok":true,"changed":true}
func publish_ready() -> void:
	var ready: bool=not suspended and semantic_lod>=2 and not pending_plan.is_empty()
	for item in pending_plan.get("records",[]):
		if item.record_type=="sprite" and not manager.ready("object:"+item.id):ready=false;break
	var key: Array=[ready,planner.index.epoch,semantic_lod,suspended,pending_plan.get("visible_ids",[])]
	if key==_publish_key:return
	detail_ready=ready;object_plan=pending_plan.duplicate()
	if not ready:
		object_plan.records=[]
		for item in pending_plan.get("records",[]):
			if item.record_type=="polyline":object_plan.records.append(item)
	_publish_key=key;revision+=1
func tick() -> void:super.tick();publish_ready()
func suspend_display() -> void:
	suspended=true;super.release_all();pending_plan={};object_plan={"records":[],"candidate_ids":[],"visible_ids":[]};detail_ready=false;_publish_key=[]
func resume_display() -> Dictionary:
	suspended=false;_view_key=[];integration_stats.reloads+=1;return set_view(view,zoom)
