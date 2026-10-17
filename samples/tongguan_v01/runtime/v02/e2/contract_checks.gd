extends RefCounted
const Index=preload("res://v02/e2/spatial_index.gd")
const Planner=preload("res://v02/e2/visibility_planner.gd")
const Audit=preload("res://v02/e2/submission_audit.gd")
var checks:=0
var failures: Array=[]
var observations: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func assets(width: float=80) -> Dictionary:
	return {"tree_grove":{"asset_id":"tree_grove","rect_px":[512,512,512,512],"anchor_px":[256,399.36],"width_m":width}}
func token(revision: String="1",world: String="stream_lab_v02",build: String="e2_contract") -> Dictionary:
	return {"world_id":world,"build_id":build,"effective_revision":revision,"asset_bounds_version":1,"cell_m":512}
func item(id: String,x: float,y: float,width: float=80) -> Dictionary:
	var scale: float=width/512.0
	return {"id":id,"source_key":id,"record_type":"sprite","asset_id":"tree_grove","position_m":[x,y],"owner":[floori(x/512),floori(y/512)],"paint_bounds_m":[x-256*scale,y-399.36*scale,width,width],"ground_footprint_m":[[-10,-5],[10,-5],[10,5],[-10,5]],"protection_envelope_m":[-50,-50,100,100],"payload_shard":"instances/owner_"+str(floori(x/512))+"_"+str(floori(y/512))+".json","render_plane":2,"ground_depth":y}
func source(count: int=4) -> Dictionary:
	var rows: Array=[item("cross",-5,-5),item("visible_a",20,80),item("visible_b",90,90),item("visible_c",130,100)]
	for i in range(4,count):rows.append(item("offscreen_%06d"%i,100000+(i%1000)*600,100000+floori(i/1000.0)*600))
	return {"records":rows,"assets":assets()}
func ids(records: Array) -> Array:
	var result: Array=[]
	for record in records:result.append(record.id)
	return result
func run() -> Dictionary:
	var view:=Rect2(0,0,128,128)
	var data: Dictionary=source(16);var planner=Planner.new()
	var provider_calls: Array=[0]
	var provider: Callable=func():provider_calls[0]+=1;return data
	check(planner.sync_source(token(),provider).ok,"valid raw list accepted")
	var first: Dictionary=planner.plan(view)
	check(first.ok and first.visible_ids.size()==4 and "cross" in first.visible_ids,"owner offscreen but crown visible")
	check("instances/owner_-1_-1.json" in first.required_shards,"visible crown requests offscreen owner's payload")
	check(planner.index.record("cross").is_read_only() and planner.index.record("cross").paint_bounds_m.is_read_only(),"shared records deeply read-only")
	var reads: int=planner.stats.snapshot_reads;var builds: int=planner.index.stats.full_index_builds;var sorts: int=planner.stats.sort_calls
	var query_count: int=planner.index.stats.query_calls
	var source_validations: int=planner.index.stats.source_records_validated
	for i in 30:
		check(planner.sync_source(token(),provider).ok,"unchanged revision synchronizes")
		planner.plan(view)
	check(planner.stats.snapshot_reads==reads,"ordinary redraw never calls snapshot provider")
	check(provider_calls[0]==1,"actual snapshot provider called once across ordinary frames")
	check(planner.index.stats.query_calls==query_count,"ordinary redraw reuses query")
	for i in 40:planner.plan(Rect2(i*.1,i*.05,128,128))
	check(planner.index.stats.full_index_builds==builds and planner.index.stats.source_records_validated==source_validations,"camera never rebuilds or revalidates full source index")
	check(planner.stats.sort_calls==sorts,"pixel pans with same visible set reuse sorted plan")
	check(planner.index.stats.candidate_union_builds==1,"same viewport buckets reuse candidate union")
	check(planner.index.stats.reference_record_enumerations==0,"normal query never asks for full record enumeration")
	var display_sorts: int=planner.stats.sort_calls
	planner.plan(view,"new_display","overview")
	check(planner.stats.sort_calls==display_sorts+1,"display or LOD revision invalidates visible plan")
	planner.plan(view,"new_display","overview")
	check(planner.stats.sort_calls==display_sorts+1,"unchanged display revision reuses plan")
	var previous_count: int=planner.index.object_count()
	var duplicate: Array=data.records.duplicate(true);duplicate.append(duplicate[0].duplicate(true))
	var refused: Dictionary=planner.index.sync(duplicate,token("bad"),assets())
	check(not refused.ok and refused.code=="duplicate_id" and planner.index.object_count()==previous_count,"raw duplicate refused before adoption")
	var bad: Dictionary={"wrong_key":data.records[0]}
	refused=planner.index.sync(bad,token("bad"),assets())
	check(not refused.ok and refused.code=="key_id_mismatch","dictionary key and record ID mismatch refused")
	var wrong_owner: Dictionary=data.records[0].duplicate(true);wrong_owner.owner=[0,0]
	refused=planner.index.apply_delta([wrong_owner],[],"bad")
	check(not refused.ok and refused.code=="owner_mismatch","incorrect owner refused")
	var bad_epoch: int=planner.index.epoch
	var valid_upsert: Dictionary=data.records[1].duplicate(true);valid_upsert.ground_depth=200
	refused=planner.index.apply_delta([valid_upsert,wrong_owner],[],"invalid_batch")
	check(not refused.ok and planner.index.epoch==bad_epoch and planner.index.record("visible_a").ground_depth==80,"invalid delta batch adopts nothing")
	var half=Index.new();var half_item: Dictionary=item("half",-256,-112.64,512)
	# Override only the synthetic asset's source anchor so the bounds are exactly
	# [-512,-512,512,512], exercising half-open edges without an epsilon guess.
	var half_assets: Dictionary=assets(512);half_assets.tree_grove.anchor_px=[256,399.36]
	half_item.position_m=[-256,-112.64];half_item.owner=[-1,-1];half_item.paint_bounds_m=[-512,-512,512,512]
	check(half.sync([half_item],token(),half_assets).ok,"negative half-open fixture accepted")
	check(half.bucket_members("-1:-1")==["half"] and half.bucket_members("0:0").is_empty(),"negative coordinate uses floor and exclusive right edge")
	check(half.query(Rect2(0,0,1,1)).visible_ids.is_empty(),"touching half-open edge does not intersect")
	var giant=Index.new();var big: Dictionary=item("giant",400,800,800)
	check(giant.sync([big],token(),assets(800)).ok,"giant accepted")
	var membership:=0
	for key in ["0:0","1:0","0:1","1:1"]:
		if "giant" in giant.bucket_members(key):membership+=1
	check(membership==4,"full giant crown references all four buckets")
	var giant_query: Dictionary=giant.query(Rect2(700,200,80,80))
	check(giant_query.visible_ids==["giant"] and giant_query.candidate_ids.size()==1,"four-bucket giant returned once when owner bucket outside view")
	var grow=Index.new();var small: Dictionary=item("resize",600,0)
	check(grow.sync([small],token(),assets()).ok,"resize baseline")
	var grow_view:=Rect2(5,-50,30,100)
	check(grow.query(grow_view).visible_ids.is_empty(),"old crown cannot reach view")
	var ground: Array=grow.record("resize").ground_footprint_m.duplicate(true)
	var changed: Dictionary=grow.update_asset("tree_grove",assets(1200).tree_grove,2)
	check(changed.ok and changed.changed==1 and grow.query(grow_view).visible_ids==["resize"],"larger asset rebuilds newly covered old-empty buckets")
	check(grow.record("resize").position_m==[600.0,0.0] and grow.record("resize").ground_footprint_m==ground,"asset reindex preserves anchor and ground footprint")
	check(grow.update_asset("tree_grove",assets().tree_grove,3).ok and grow.query(grow_view).visible_ids.is_empty(),"shrinking removes stale bucket references")
	check(not grow.update_asset("tree_grove",assets().tree_grove,2).ok,"stale asset bounds version rejected")
	var single=Index.new();var old_single: Dictionary=item("old_single",600,0)
	check(single.sync([old_single],token(),assets()).ok,"single bucket fixture")
	single.query(Rect2(550,-100,100,200))
	single.apply_delta([], ["old_single"],"2");single.apply_delta([item("new_single",610,0)],[],"3")
	check(single.query(Rect2(550,-100,100,200)).candidate_ids==["new_single"],"empty bucket removed and recreated without stale candidate cache")
	var moved: Dictionary=planner.index.record("cross").duplicate(true);moved.position_m=[1025,-5];moved.owner=[2,-1];moved.paint_bounds_m=[985,-67.4,80,80];moved.payload_shard="instances/moved.json"
	var before_reindexed: int=planner.index.stats.records_reindexed
	check(planner.index.apply_delta([moved],[],"2").ok,"move one stable ID across pages")
	check(planner.index.stats.records_reindexed==before_reindexed+1,"move reindexes one object only")
	check("cross" not in planner.plan(view).visible_ids and "cross" in planner.plan(Rect2(1000,0,128,128)).visible_ids,"old bucket reference removed and new bucket visible")
	check(planner.index.record("cross").id=="cross" and planner.index.record("cross").owner[0]==2,"move preserves ID and derives owner")
	check(planner.index.apply_delta([], ["cross"],"3").ok and "cross" not in planner.plan(Rect2(1000,0,128,128)).visible_ids,"removed shard/object invalidates visible plan")
	check(planner.index.apply_delta([data.records[0]],[],"4").ok and "cross" in planner.plan(view).visible_ids,"reinsert cannot reuse stale per-ID version")
	var same: Dictionary=source(16);same.records[1].ground_depth=999
	var reindexed_before: int=planner.index.stats.records_reindexed
	check(planner.sync_source(token("next"),func():return same).ok,"new revision reads a fresh snapshot")
	check(planner.index.stats.full_index_builds==1 and planner.index.stats.records_reindexed==reindexed_before+1,"snapshot revision updates affected record rather than rebuilding index")
	var ordered: Array=ids(planner.plan(view).records)
	check(ordered[-1]=="visible_a","stable global ground-depth sorting crosses owner pages")
	var sort_before: int=planner.stats.sort_calls
	var off: Dictionary=planner.index.record("offscreen_000004").duplicate(true);off.ground_depth+=1
	check(planner.index.apply_delta([off],[],"offscreen_update").ok,"offscreen update accepted")
	planner.plan(view)
	check(planner.stats.sort_calls==sort_before,"unrelated offscreen revision does not invalidate visible sort")
	var world_data: Dictionary=source()
	check(planner.sync_source(token("1","another_engineering_world","same_local_origin"),func():return world_data).ok,"different world and build accepted as replacement")
	check(planner.index.stats.full_index_builds==2 and planner.index.identity.world_id=="another_engineering_world","world/build context invalidates old local-zero cache")
	var tie=Planner.new();var tie_rows: Array=[item("z",0,0),item("a",0,0),item("plane",0,0)]
	tie_rows[2].render_plane=1
	check(tie.sync_source(token(),func():return {"records":tie_rows,"assets":assets()}).ok,"tie fixture")
	check(ids(tie.plan(Rect2(-40,-70,100,100)).records)==["plane","a","z"],"stable sort uses plane then depth then stable ID")
	var baked: Dictionary=item("baked",0,0);baked.baked_representation=true
	check(tie.index.apply_delta([baked],[],"baked").ok,"baked metadata accepted")
	check("baked" in tie.plan(Rect2(-40,-70,100,100)).visible_ids and "baked" not in ids(tie.plan(Rect2(-40,-70,100,100)).records),"baked representation not drawn a second time")
	var audit=Audit.new();audit.begin_frame()
	check(audit.submit("tree").ok and not audit.submit("tree").ok,"real submission audit rejects same representation twice")
	audit.begin_frame();check(audit.submit("tree","old").ok and not audit.submit("tree","new","invented").ok,"unregistered second representation rejected")
	audit.begin_frame();check(audit.register_pair("tree","old","new","fade1"),"explicit transition pair registered")
	check(audit.submit("tree","old","fade1").ok and audit.submit("tree","new","fade1").ok and not audit.submit("tree","third","fade1").ok,"only registered pair allowed and capped at two")
	for count in [1000,10000,100000]:
		var started:=Time.get_ticks_msec();var fixture: Dictionary=source(count);var stress=Planner.new()
		check(stress.sync_source(token(),func():return fixture).ok,"metadata fixture "+str(count))
		var before_tests: int=stress.index.stats.candidate_tests
		var answer: Dictionary=stress.plan(view)
		check(answer.ok and answer.visible_ids.size()==4 and answer.candidate_ids.size()==4,"same visible and candidate count "+str(count))
		var normal_enumerations: int=stress.index.stats.reference_record_enumerations
		check(stress.index.stats.candidate_tests-before_tests==4 and normal_enumerations==0,"query visits four candidates regardless of offscreen total "+str(count))
		check(ids(answer.records)==ids(stress.full_scan_reference(view)),"independent full-scan reference agrees "+str(count))
		check(stress.index.stats.reference_record_enumerations==normal_enumerations+1,"full enumeration counter has a measured positive control "+str(count))
		observations.append({"total_objects":count,"visible":answer.visible_ids.size(),"candidates":answer.candidate_ids.size(),"query_candidate_tests":stress.index.stats.candidate_tests-before_tests,"query_full_record_enumerations":normal_enumerations,"reference_full_record_enumerations":stress.index.stats.reference_record_enumerations,"build_and_check_ms":Time.get_ticks_msec()-started,"telemetry":stress.telemetry()})
		print("E2_QUERY_SCALE ",count," visible=",answer.visible_ids.size()," candidates=",answer.candidate_ids.size())
	return {"checks":checks,"failures":failures,"observations":observations,"small_fixture_telemetry":planner.telemetry(),"scope":"E2 metadata query/cache correctness; not E3 residency or nationwide frame-time acceptance"}
