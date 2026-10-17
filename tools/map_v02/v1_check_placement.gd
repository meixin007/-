extends SceneTree
func _initialize() -> void:
	create_timer(60).timeout.connect(func():printerr("V1_PLACEMENT_TIMEOUT");quit(1))
	call_deferred("run")
func run() -> void:
	var style_path:="H:/tongguan_reviewfix_20261015/samples/tongguan_v01/runtime/v02/v1/style.json"
	var report:="H:/tongguan_reviewfix_20261015/review-work/map_v02/v1_boundary/placement.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.substr(9)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(style_path))
	var resolver=load("res://final/resolver.gd").new()
	var before: String=resolver.digest(resolver.snapshot())
	var rows: Array=[];var failures: Array=[]
	for i in data.sample_trees_m.size():
		var record:={"id":"v1.preview.tree.%02d"%i,"position_m":data.sample_trees_m[i],"asset_version":1,"kind":"forest","region_id":"manual","grid":[],"source_seed":0}
		var reason: String=resolver._safe_uncached(record)
		rows.append({"id":record.id,"position_m":record.position_m,"reason":reason})
		if not reason.is_empty():failures.append(record.id+":"+reason)
	var slot: Dictionary=resolver.source.layout.slots[0]
	var polygon:=PackedVector2Array()
	for p in slot.polygon_local_m:polygon.append(Vector2(p[0],p[1]))
	for point in data.assets.warehouse.ground_polygon_m:
		if not Geometry2D.is_point_in_polygon(Vector2(-567.5+point[0],-227.5+point[1]),polygon):
			failures.append("warehouse outside old slot")
	if before!=resolver.digest(resolver.snapshot()):failures.append("source state changed")
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"failures":failures,"original_resolver_unchanged":before==resolver.digest(resolver.snapshot())},"\t"))
	print("V1_PLACEMENT ",JSON.stringify({"failures":failures}));quit(0 if failures.is_empty() else 1)
