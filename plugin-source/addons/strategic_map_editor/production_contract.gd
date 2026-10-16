@tool
extends RefCounted
static func defaults() -> Dictionary:
	return {"coordinate_frame":"authoring_units","source_note":"","regions":[],"checks":[],"calibrations":{},"receipts":{},"audit_reviews":{}}
static func enrich_feature(f: Dictionary) -> void:
	for pair in [["holes",[]],["protected",false],["group_id",""],["source",{"citation":"","era":"","status":"unverified"}]]:
		if not f.has(pair[0]): f[pair[0]] = pair[1].duplicate(true) if pair[1] is Dictionary or pair[1] is Array else pair[1]
static func validate(p: Variant) -> String:
	if not p is Dictionary: return "缺少制作元数据。"
	var reviews: Variant=p.get("audit_reviews",{})
	if not reviews is Dictionary or reviews.size()>2000: return "问题处理记录最多 2000 条。"
	for id in reviews:
		var review: Variant=reviews[id]
		if not id is String or id.is_empty() or not review is Dictionary: return "问题处理记录格式无效。"
		if not review.get("status") in ["todo","reviewing","deferred"] or not review.get("note") is String or not review.get("evidence") is String or review.evidence.length()!=64: return "问题处理状态、备注或依据无效。"
		if review.note.length()>4000 or (review.status != "todo" and review.note.strip_edges().is_empty()): return "核对 / 暂缓须填写原因，备注最多 4000 字。"
	for key in ["coordinate_frame","source_note"]:
		if not p.get(key) is String: return "制作坐标与来源格式错误。"
	for key in ["calibrations","receipts"]:
		if not p.get(key) is Dictionary or p[key].size() > 1000: return "制作记录格式错误或超过 1000 条。"
	for id in p.receipts:
		if not id is String or id.is_empty() or not p.receipts[id] is String or p.receipts[id].length() != 64: return "批次回执格式错误。"
	for id in p.calibrations:
		var c: Variant=p.calibrations[id]
		if not id is String or not c is Dictionary: return "校准记录格式错误。"
		if not c.get("source_points") is Array or not c.get("world_points") is Array or c.source_points.size() != c.world_points.size() or c.source_points.size() < 2 or c.source_points.size() > 64: return "校准控制点数量错误。"
		for point in c.source_points+c.world_points:
			if not point_valid(point): return "校准控制点无效。"
		for key in ["position","size","image_size"]:
			if not point_valid(c.get(key)): return "校准尺寸或位置无效。"
		for key in ["rms","max_error","rotation"]:
			if not numeric(c.get(key)): return "校准误差或旋转无效。"
		for key in ["citation","era"]:
			if not c.get(key) is String: return "校准来源格式无效。"
	for key in ["regions","checks"]:
		if not p.get(key) is Array or p[key].size() > 256: return "区域 / 场景最多 256 条。"
	var ids: Array = []
	for region in p.regions:
		if not region is Dictionary or not region.get("id") is String or region.id.is_empty() or region.id in ids or not region.get("name") is String or not rect_valid(region.get("rect")): return "区域书签格式错误。"
		ids.append(region.id)
	ids.clear()
	for scenario in p.checks:
		if not scenario is Dictionary or not scenario.get("id") is String or scenario.id.is_empty() or scenario.id in ids or not scenario.get("name") is String or not point_valid(scenario.get("start")) or not point_valid(scenario.get("finish")): return "检查场景的名称、ID 或起终点错误。"
		if not scenario.get("unit") in ["army","light"] or not scenario.get("revealed") is bool or not scenario.get("expected") is bool or not scenario.get("gates") is Dictionary: return "检查场景的条件不完整。"
		for value in scenario.gates.values():
			if not value is bool: return "检查场景关隘条件应为布尔值。"
		if not rect_valid(scenario.get("rect")) or not numeric(scenario.get("step")) or scenario.step < 1 or scenario.step > 256: return "检查场景范围或格距错误。"
		ids.append(scenario.id)
	return ""
static func numeric(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))
static func point_valid(v: Variant) -> bool: return v is Array and v.size() == 2 and numeric(v[0]) and numeric(v[1])
static func rect_valid(v: Variant) -> bool:
	return v is Array and v.size() == 4 and point_valid([v[0],v[1]]) and point_valid([v[2],v[3]]) and v[2] > 0 and v[3] > 0
