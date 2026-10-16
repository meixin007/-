extends "res://r3_authoring/resolver.gd"
const WAREHOUSE_SLOT="tongguan.slot.rear_storage_01"
func _init()->void:
	super()
	if error.is_empty():state.manual_layout=layout_record()
func layout_record(value: Dictionary={})->Dictionary:
	var candidate=state if value.is_empty() else value
	return candidate.get("manual_layout",{"warehouse_offset_m":[0,0],"slot_pins":source.authoring.slot_pins}).duplicate(true)
func _layout_issue(record: Variant)->String:
	if not record is Dictionary or not _point_valid(record.get("warehouse_offset_m")) or not record.get("slot_pins") is Dictionary:return "仓库表现或地块冻结字段无效。"
	var offset: Array=record.warehouse_offset_m
	# Full R4 visual footprint including roof, walls/rubble and edge allowance.
	var slot: Dictionary=source.slot_by_id(WAREHOUSE_SLOT);var center=Vector2.ZERO
	for p in slot.polygon_local_m:center+=Vector2(p[0],p[1])
	center/=slot.polygon_local_m.size();center+=Vector2(offset[0],offset[1])
	for delta in [Vector2(-16,-12),Vector2(16,-12),Vector2(16,10),Vector2(-16,10)]:
		if not Geometry2D.is_point_in_polygon(center+delta,packed(slot.polygon_local_m)):return "仓库完整屋顶、墙体或边缘会超出地块，未移动。"
	if record.slot_pins.size()!=source.layout.slots.size():return "地块冻结集合不完整。"
	for current in source.layout.slots:
		if not record.slot_pins.get(current.id) is bool:return "地块冻结身份不符。"
	return ""
func _validate(value: Variant)->String:
	var issue=super._validate(value)
	if not issue.is_empty():return issue
	return _layout_issue(layout_record(value))
func move_warehouse(offset_m: Array)->Dictionary:
	var candidate=snapshot();candidate.manual_layout=layout_record();candidate.manual_layout.warehouse_offset_m=offset_m.duplicate()
	return _adopt(candidate,"warehouse_display_override",{"slot_id":WAREHOUSE_SLOT,"offset_m":offset_m.duplicate()})
func pin_layout_slot(id: String,pinned: bool)->Dictionary:
	if source.slot_by_id(id).is_empty():return fail("地块身份无效。")
	var candidate=snapshot();candidate.manual_layout=layout_record();candidate.manual_layout.slot_pins[id]=pinned
	return _adopt(candidate,"layout_slot_pin",{"slot_id":id,"pinned":pinned})
func protected_hash()->String:return digest({"base":super.protected_hash(),"manual_layout":layout_record()})
func publication()->Dictionary:
	var value=super.publication();var record=layout_record()
	value.runtime_authoring.manual_overrides[WAREHOUSE_SLOT]={"offset_m":record.warehouse_offset_m.duplicate(),"authoring_pin":true}
	value.runtime_authoring.slot_pins=record.slot_pins.duplicate(true)
	value.runtime_authoring.r3_provenance.manual_layout_sha256=digest(record)
	value.erase("content_sha256");value.content_sha256=digest(value)
	return value
