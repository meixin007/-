extends RefCounted
func run(_boot: Node,_output: String) -> Dictionary:
	var fixtures=load("res://v02/e2/contract_checks.gd").new();var rows: Array=[];var failures: Array=[]
	for count in [1000,10000,100000]:
		var data: Dictionary=fixtures.source(count);var planner=load("res://v02/e2/visibility_planner.gd").new();var start:=Time.get_ticks_usec()
		var admitted: Dictionary=planner.sync_source(fixtures.token(),func():return data)
		var build_usec:=Time.get_ticks_usec()-start
		if not admitted.ok:failures.append("admission "+str(count));continue
		var timings: Array=[];var sort_before: int=planner.stats.sort_calls
		for i in 100:
			var view:=Rect2(i*.01,0,128,128);start=Time.get_ticks_usec();var answer: Dictionary=planner.plan(view);timings.append(Time.get_ticks_usec()-start)
			if answer.visible_ids.size()!=4 or answer.candidate_ids.size()!=4:failures.append("same visible set "+str(count));break
		var scans_before: int=planner.index.stats.reference_record_enumerations
		var reference: Array=planner.full_scan_reference(Rect2(0,0,128,128))
		if fixtures.ids(reference)!=fixtures.ids(planner.plan(Rect2(0,0,128,128)).records):failures.append("reference set "+str(count))
		rows.append({"world_records":count,"resident_records":planner.index.object_count(),"queries":100,"query_usec":timings,"index_build_usec":build_usec,"buckets_visited":planner.index.stats.bucket_lookups,"candidates_tested":planner.index.stats.candidate_tests,"visible_objects":reference.size(),"submitted_objects":reference.size(),"sort_rebuilds":planner.stats.sort_calls-sort_before,"query_full_scans":scans_before,"reference_positive_control_scans":planner.index.stats.reference_record_enumerations-scans_before})
	return {"checks":9,"failures":failures,"profiles":rows,"scope":"E-query metadata; not simultaneous draw capacity"}
