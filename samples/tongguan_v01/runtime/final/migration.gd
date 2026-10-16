extends RefCounted
const Saves=preload("res://scripts/core/save_manager.gd")
const State=preload("res://scripts/core/game_state.gd")
const Store=preload("res://scripts/core/save_file_store.gd")
const MAX_SOURCE_BYTES=64*1024*1024
var _pending: Dictionary={}
var _sequence:=0
func fail(message: String)->Dictionary:return {"ok":false,"message":message,"error":message}
func file_hash(path: String)->String:return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
func _read(path: String)->Dictionary:
	if not FileAccess.file_exists(path):return fail("没有找到选择的存档。")
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return fail("无法读取选择的存档。")
	if file.get_length()>MAX_SOURCE_BYTES:file.close();return fail("存档超过64MiB，未读取或修改。")
	var bytes=file.get_buffer(file.get_length());file.close();var parser=JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK or not parser.data is Dictionary:return fail("选择的文件不是完整JSON存档。")
	var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(bytes)
	return {"ok":true,"data":parser.data,"source_sha256":hashing.finish().hex_encode(),"text":bytes.get_string_from_utf8()}
func preview(source_path: String,destination: String,controller)->Dictionary:
	_pending.clear()
	var permitted=Store.new()._validate_path(destination)
	if not permitted.ok:return fail("导入只能写入本阶段用户存档目录，原文件保留。")
	if ProjectSettings.globalize_path(source_path).simplify_path().to_lower()==ProjectSettings.globalize_path(destination).simplify_path().to_lower():return fail("导入目标不能覆盖原存档。")
	var read=_read(source_path)
	if not read.ok:return read
	var policy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://final/migration_policy.json"))
	var source_id=str(read.data.get("campaign_id",""))
	if source_id not in policy.supported_source_campaigns:return fail("仅支持R3/R4同布局存档。R1/R2或其他战役请用原入口；不会自动补资源或道路。")
	var checked=Saves.new(source_id).repository._validate_text(read.text)
	if not checked.ok:return fail("旧存档校验失败："+str(checked.get("error","未知原因")))
	var candidate: Dictionary=checked.data.duplicate(true)
	var city: Dictionary=candidate.get("local_node_state",{}).get(controller.NODE_ID,{}).get(controller.CITY_FIELD,{})
	if city.get("layout_version")!=policy.layout_migration.from_version or policy.layout_migration.to_version!=controller._city_contract.runtime.layout_version:return fail("布局版本没有经过明确的地块迁移表核对。")
	var ids={}
	for slot in controller._city_contract.layout.slots:ids[slot.id]=true
	if policy.layout_migration.slot_id_map.size()!=ids.size():return fail("地块映射不完整。")
	for id in ids:
		if policy.layout_migration.slot_id_map.get(id)!=id:return fail("此版本只允许同址同ID映射，不能随机重绑建筑。")
	candidate.campaign_id=controller.definition.world_id;candidate.flags.campaign_id=controller.definition.world_id
	var state=State.new();var loaded=state.try_load_dictionary(candidate)
	if not loaded.ok:return fail("旧存档状态无法转换："+str(loaded.get("error","未知原因")))
	var issue=controller._validate(state)
	if not issue.is_empty():return fail("旧存档与当前通道/地块合同不兼容："+issue)
	_sequence+=1;var token="migration:%d:%d"%[_sequence,Time.get_ticks_usec()]
	var source_sha=read.source_sha256
	if file_hash(source_path)!=source_sha:return fail("读取期间原存档已经变化，请重新预览。")
	_pending[token]={"source_path":source_path,"source_sha256":source_sha,"destination":destination,"destination_sha256":file_hash(destination),
		"epoch":controller.context.world_epoch,"state_sha256":controller.digest(controller.context.state.to_dictionary()),"candidate":state}
	var force: Dictionary=state.military_forces[controller.FORCE_ID]
	return {"ok":true,"token":token,"summary":{"source_campaign_id":source_id,"target_campaign_id":controller.definition.world_id,"source_sha256":source_sha,
		"day":int(state.current_day),"growth_stage":int(city.growth_stage),"layout_version":city.layout_version,"slots":ids.size(),"current_corridor_id":force.current_corridor_id,"source_preserved":true}}
func commit(token: String,controller)->Dictionary:
	if not _pending.has(token):return fail("导入预览不存在或已经失效，请重新预览。")
	var entry: Dictionary=_pending[token];_pending.clear()
	if controller.context.world_epoch!=entry.epoch or controller.digest(controller.context.state.to_dictionary())!=entry.state_sha256:return fail("当前游戏状态已经变化，请重新预览导入。")
	if file_hash(entry.source_path)!=entry.source_sha256 or file_hash(entry.destination)!=entry.destination_sha256:return fail("原存档或目标存档已经变化，请重新预览。")
	var issue=controller._validate(entry.candidate)
	if not issue.is_empty():return fail(issue)
	# Native two-generation save writes a complete checked file before adoption.
	# The detached candidate has already passed the same replace_state contract.
	var written=Saves.new(controller.definition.world_id).write_save(entry.destination,entry.candidate)
	if not written.ok:return fail("新存档未写入，当前世界保持："+str(written.get("error","写入失败")))
	var adopted=controller.context.replace_state(entry.candidate,true)
	if not adopted.ok:return fail("新存档已完整保存，但未采用："+str(adopted.get("error","采用失败")))
	controller._pending.clear();controller._build_pending.clear()
	return {"ok":true,"source_sha256":entry.source_sha256,"destination":entry.destination,"source_preserved":true}
