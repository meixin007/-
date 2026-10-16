extends RefCounted
const Context=preload("res://scripts/core/game_runtime_context.gd")
const GameState=preload("res://scripts/core/game_state.gd")
const Tx=preload("res://scripts/core/game_state_transaction.gd")
const Military=preload("res://scripts/core/military_campaign_service.gd")
const Clock=preload("res://scripts/core/time_controller.gd")
const Routes=preload("res://scripts/core/route_network_service.gd")
const Reader=preload("res://scripts/core/runtime_corridor_reader.gd")
const Saves=preload("res://scripts/core/save_manager.gd")
const City=preload("res://runtime/settlement_state.gd")
const Publication=preload("res://integrity/publication.gd")
const PRESENTATION_FIELD="tongguan_presentation_v1"
var _publication_service: RefCounted
const Motion=preload("res://integrity/polyline.gd")
const Economy=preload("res://construction/economy.gd")
const Dispatcher=preload("res://scripts/core/game_action_dispatcher.gd")
const Construction=preload("res://scripts/core/estate_construction_service.gd")
var _economy: RefCounted
var _build_pending: Dictionary={}
const NODE_ID="tongguan_pass_node"
const FORCE_ID="tongguan_validation_force_01"
const FIELD="tongguan_movement_v1"
const CITY_FIELD="tongguan_settlement_runtime_v1"
var context: RefCounted
var error: String=""
var definition: Dictionary={}
var _city_contract: RefCounted
var _graph_hash: String=""
var _pending: Dictionary={}
var _sequence:=0
class CorridorProjection extends RefCounted:
	var owner: WeakRef
	func _init(controller):owner=weakref(controller)
	func get_all_corridors()->Dictionary:return owner.get_ref().effective_corridors()
	func get_corridor(id: String)->Dictionary:return get_all_corridors().get(id,{}).duplicate(true)
	func get_node(id: String)->Dictionary:return owner.get_ref().context.state.strategic_nodes.get(id,{}).duplicate(true)
func digest(value: Variant)->String:return City.digest(value)
func _fail(message: String)->Dictionary:return {"ok":false,"message":message,"error":message}
func _init()->void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://army/fixture.json"))
	if not parsed is Dictionary or parsed.get("schema_version")!=1:error="移动场景定义无效。";return
	definition=parsed;_publication_service=Publication.new();_economy=Economy.new();_city_contract=City.new();context=Context.new();context.state=GameState.new()
	context.scenario_data={"campaign_id":definition.world_id,"scenario":{"start_phase":"tongguan_movement_validation"},"resources":{},"characters":[],"factions":[],"strategic_nodes":definition.nodes,"transit_corridors":definition.corridors,"military_forces":[definition.force]}
	context.state.initialize_from_data(context.scenario_data)
	context.state.flags["campaign_id"]=definition.world_id
	context.state.flags["tongguan_graph_version"]=definition.graph_version
	_graph_hash=digest(context.state.transit_corridors)
	context.state.local_node_state[NODE_ID]={"node_id":NODE_ID,CITY_FIELD:_city_contract.runtime,FIELD:{"schema_version":1,"graph_version":definition.graph_version,"status":"idle","path_known":false,"route_mode":"main","goal":"","path_nodes":[],"path_edges":[],"edge_index":0,"receipts":[]}}
	var publication=_publication_service.load_publication("res://bundle/authoring_publication.json")
	if not publication.ok:error=str(publication.get("message","制作发布初始化失败。"));return
	context.state.local_node_state[NODE_ID][PRESENTATION_FIELD]=publication.meta
	_economy.seed(context.state)
	Clock.new().pause(context.state,"construction_review_pause")
	var validation=context.state.try_load_dictionary(context.state.to_dictionary())
	if not validation.ok:error=str(validation.get("error","主机初始化失败。"));return
	error=_validate(context.state)
func projection()->Dictionary:return _economy.project(context.state,context.state.local_node_state[NODE_ID][CITY_FIELD])
func authoring_projection()->Dictionary:return context.state.local_node_state[NODE_ID][PRESENTATION_FIELD].authoring.duplicate(true)
func import_publication(path: String)->Dictionary:
	var candidate=_publication_service.load_publication(path)
	if not candidate.ok:return candidate
	return _transaction("presentation_import",func(state):state.local_node_state[NODE_ID][PRESENTATION_FIELD]=candidate.meta.duplicate(true);return {"ok":true,"publication_sha256":candidate.meta.publication_sha256})
func _order(state)->Dictionary:return state.local_node_state[NODE_ID][FIELD]
func snapshot()->Dictionary:
	return {"force":context.state.military_forces[FORCE_ID].duplicate(true),"order":_order(context.state).duplicate(true),"city":projection(),"day":int(context.state.current_day),"paused":bool(context.state.is_time_paused),"revision":int(context.state.state_revision)}
func effective_corridors(state=null)->Dictionary:
	if state==null:state=context.state
	var result: Dictionary=state.transit_corridors.duplicate(true)
	var opened=bool(state.local_node_state[NODE_ID][CITY_FIELD].gate_open)
	result.tg_main_gate.is_blocked=bool(result.tg_main_gate.is_blocked) or not opened
	if not opened:result.tg_main_gate.blocking_reason="潼关主关关闭，候行。"
	var trail: Dictionary=result.tg_synthetic_trail
	if state.military_forces[FORCE_ID].get("movement_profile")!="light":
		trail.is_blocked=true;trail.blocking_reason="合成险径仅允许轻装配置，普通军队禁行。"
	elif not bool(_order(state).path_known):
		trail.is_blocked=true;trail.blocking_reason="合成险径尚未为该验证部队所知。"
	return result
func passage(id: String)->Dictionary:
	var route: Dictionary=effective_corridors().get(id,{})
	return Reader.passage(context.state,route) if not route.is_empty() else {"is_passable":false,"reason":"没有登记的逻辑道路。"}
func _transaction(action: String,operation: Callable)->Dictionary:
	if not error.is_empty():return _fail(error)
	var original_issue=_validate(context.state)
	if not original_issue.is_empty():return _fail(original_issue)
	return Tx.new().execute(context,func(working):
		var result: Dictionary=operation.call(working.state)
		if not result.get("ok",false):return result
		var issue=_validate(working.state)
		if not issue.is_empty():return _fail(issue)
		working.state.state_revision=int(working.state.state_revision)+1
		var receipt={"action":action,"day":int(working.state.current_day),"revision":int(working.state.state_revision),"gate_open":bool(working.state.local_node_state[NODE_ID][CITY_FIELD].gate_open)}
		var records: Array=_order(working.state).receipts;records.append(receipt)
		if records.size()>128:records.pop_front()
		result.receipt=receipt;return result)
func preview_order(goal: String,route_mode: String="main")->Dictionary:
	var state=context.state;var force: Dictionary=state.military_forces[FORCE_ID]
	if goal=="river_north":
		var denied=Routes.new(CorridorProjection.new(self)).find_shortest_path(state,str(force.current_node_id),goal)
		if denied.ok:return _fail("场景错误：河面不应有过河边。")
		return _fail("没有显式渡河逻辑边，普通陆军不能进入河面。")
	if route_mode not in ["main","trail"]:return _fail("未登记的路线选择。")
	if route_mode=="trail" and not passage("tg_synthetic_trail").is_passable:return _fail(str(passage("tg_synthetic_trail").reason))
	if goal not in ["tg_fore","tg_rear"]:return _fail("只能向关前或关后下达行军命令。")
	if not str(force.current_corridor_id).is_empty():return _fail("部队正在道路日步中；抵达接点后再改令。")
	if force.current_node_id==goal:return _fail("部队已在目标端点。")
	var chain: Array=definition.node_chain;var start=chain.find(force.current_node_id);var end=chain.find(goal)
	if start<0:return _fail("部队不在已登记的测试通道。")
	var nodes=[];var edges=[];var direction=1 if end>start else -1;var cursor=start
	nodes.append(chain[cursor])
	while cursor!=end:
		edges.append(definition.edge_chain[mini(cursor,cursor+direction)]);cursor+=direction;nodes.append(chain[cursor])
	if route_mode=="trail":
		var controlled_index=edges.find("tg_main_gate")
		if controlled_index>=0:edges[controlled_index]="tg_synthetic_trail"
	_sequence+=1;var token="army_%d_%d"%[get_instance_id(),_sequence]
	_pending.clear();_pending[token]={"epoch":context.world_epoch,"revision":int(state.state_revision),"goal":goal,"nodes":nodes,"edges":edges,"route_mode":route_mode}
	return {"ok":true,"token":token,"path_nodes":nodes.duplicate(),"path_edges":edges.duplicate(),"gate_open":projection().gate_open}
func commit_order(token: String)->Dictionary:
	if not _pending.has(token):return _fail("行军预览不存在或已失效。")
	var proposal: Dictionary=_pending[token];_pending.clear()
	if proposal.epoch!=context.world_epoch or proposal.revision!=int(context.state.state_revision):return _fail("主机状态已改变，请重新下令。")
	return _transaction("order",func(state):
		var order=_order(state);order.route_mode=proposal.route_mode;order.goal=proposal.goal;order.path_nodes=proposal.nodes;order.path_edges=proposal.edges;order.edge_index=0;order.status="marching"
		state.military_forces[FORCE_ID].target_node_id=proposal.goal
		return {"ok":true})
func order(goal: String,route_mode: String="main")->Dictionary:
	var preview=preview_order(goal,route_mode)
	return commit_order(preview.token) if preview.ok else preview
func adopt_candidate(candidate: Dictionary,_action: String)->Dictionary:
	var issue=_city_contract._validate_runtime(candidate)
	if not issue.is_empty():return _fail(issue)
	if int(candidate.revision)!=int(projection().revision):return _fail("城市修订已过期。")
	return _transaction("city",func(state):
		if candidate.slot_occupancy!=projection().slot_occupancy:return _fail("施工占用由真实工程控制，不能手动完成或清除。")
		var value=candidate.duplicate(true);value.slot_occupancy=state.local_node_state[NODE_ID][CITY_FIELD].slot_occupancy.duplicate(true);value.revision=int(value.revision)+1;state.local_node_state[NODE_ID][CITY_FIELD]=value;return {"ok":true})
func set_gate_open(opened: bool)->Dictionary:
	var city=projection();city.gate_open=opened;return adopt_candidate(city,"gate")
func set_paused(paused: bool)->Dictionary:
	return _transaction("pause" if paused else "resume",func(state):return Clock.new().pause(state,"army_review_pause") if paused else Clock.new().resume(state))
func advance_step()->Dictionary:
	return _transaction("shared_day",func(state):
		var previous: Dictionary=state.military_forces[FORCE_ID].duplicate(true)
		var step_result={}
		var advanced=Clock.new().advance_one_day(state,[func(current):
			var construction=Construction.settle_daily(current)
			if not construction.ok:return construction
			var order=_order(current)
			if order.status not in ["marching","waiting"]:return {"ok":true}
			var force: Dictionary=current.military_forces[FORCE_ID];var index=int(order.edge_index);var edge_id: String=order.path_edges[index]
			var route: Dictionary=effective_corridors(current)[edge_id]
			var allowed=Reader.passage(current,route)
			route.is_blocked=not allowed.is_passable;route.blocking_reason=allowed.get("reason","")
			var movement=Military.new().advance_force_movement(force,route,1)
			if not movement.ok:return movement
			step_result.merge(movement);step_result.edge_id=edge_id;step_result.force_id=FORCE_ID
			if movement.get("blocked",false):order.status="waiting"
			elif movement.get("arrived",false):
				order.edge_index=index+1
				order.status="arrived" if order.edge_index==order.path_edges.size() else "marching"
				if order.status!="arrived":force.target_node_id=order.goal
			else:order.status="marching"
			return {"ok":true}])
		if not advanced.ok:return advanced
		var visual_points=[]
		if step_result.has("edge_id") and not step_result.get("blocked",false):
			var edge: Dictionary=state.transit_corridors[step_result.edge_id];var path=Motion.points(edge.points_m)
			if previous.current_node_id==edge.to_node_id:path.reverse()
			var start=float(previous.corridor_progress_days)/float(edge.base_travel_days)
			visual_points=Motion.section(path,start,minf(1.0,start+1.0/float(edge.base_travel_days)))
		return {"ok":true,"movement":step_result,"visual_points":visual_points})
func economy()->Dictionary:return _economy.summary(context.state)
func construction_for(slot_id: String)->Dictionary:return _economy.order_for(context.state,slot_id)
func preview_construction(slot_id: String,kind: String)->Dictionary:
	if not error.is_empty():return _fail(error)
	var issue=_validate(context.state)
	if not issue.is_empty():return _fail(issue)
	var result=_economy.inspect(context.state,context.state.local_node_state[NODE_ID][CITY_FIELD],slot_id,kind)
	if not result.ok:return result
	_sequence+=1
	var token="construction_%d_%d"%[get_instance_id(),_sequence]
	_build_pending.clear();_build_pending[token]={"epoch":context.world_epoch,"revision":int(context.state.state_revision),"request":result.request.duplicate(true)}
	result.erase("request");result.token=token
	return result
func commit_construction(token: String)->Dictionary:
	if not _build_pending.has(token):return _fail("施工预览不存在或已使用，请重新查看报价。")
	var preview: Dictionary=_build_pending[token];_build_pending.clear()
	if preview.epoch!=context.world_epoch or preview.revision!=int(context.state.state_revision):return _fail("日期或主机状态已改变，请重新查看施工报价。")
	return _transaction("construction",func(state):return Dispatcher.apply(state,context.scenario_data,preview.request))
func path_known()->bool:return bool(_order(context.state).path_known)
func set_path_known(known: bool)->Dictionary:
	return _transaction("path_knowledge",func(state):_order(state).path_known=known;return {"ok":true})
func set_movement_profile(profile: String)->Dictionary:
	if profile not in ["ordinary","light"]:return _fail("未登记的测试部队配置。")
	if _order(context.state).status in ["marching","waiting"]:return _fail("行军命令尚未结束，不能途中改变部队配置。")
	return _transaction("movement_profile",func(state):state.military_forces[FORCE_ID].movement_profile=profile;return {"ok":true})
func position_local()->Array:
	var force: Dictionary=context.state.military_forces[FORCE_ID]
	if str(force.current_corridor_id).is_empty():return context.state.strategic_nodes[force.current_node_id].position_m.duplicate()
	var edge: Dictionary=context.state.transit_corridors[force.current_corridor_id];var points=Motion.points(edge.points_m)
	if force.current_node_id==edge.to_node_id:points.reverse()
	var point=Motion.sample(points,float(force.corridor_progress_days)/float(edge.base_travel_days))
	return [point.x,point.y]
func _validate(state)->String:
	if state.flags.get("campaign_id")!=definition.world_id or state.flags.get("tongguan_graph_version")!=definition.graph_version:return "存档不属于当前军队验证场景。"
	if digest(state.transit_corridors)!=_graph_hash or not state.route_network_state.routes.is_empty():return "存档中的通道定义被改动。"
	var expected={}
	for node in definition.nodes:expected[node.node_id]=node
	if digest(state.strategic_nodes)!=digest(expected):return "局部端点被改动。"
	if state.military_forces.size()!=1 or not state.military_forces.get(FORCE_ID) is Dictionary:return "军队稳定身份不符。"
	var force: Dictionary=state.military_forces[FORCE_ID]
	if force.get("movement_profile") not in ["ordinary","light"]:return "部队配置无效。"
	if force.get("force_id")!=FORCE_ID or force.get("source_id")!=definition.force.source_id or digest(force.get("troop_tiers"))!=digest(definition.force.troop_tiers):return "测试部队来源或兵额不符。"
	if not force.get("current_node_id") in definition.node_chain or not City.integer(force.get("corridor_progress_days")) or force.corridor_progress_days<0:return "行军地点或进度无效。"
	var edge_id: String=str(force.get("current_corridor_id",""))
	if edge_id.is_empty():
		if force.corridor_progress_days!=0:return "驻止部队不能携带道路进度。"
	else:
		if not state.transit_corridors.has(edge_id):return "部队道路不存在。"
		var edge: Dictionary=state.transit_corridors[edge_id]
		if force.current_node_id not in [edge.from_node_id,edge.to_node_id] or force.corridor_progress_days>=edge.base_travel_days:return "道路进度超界或接点断开。"
	var node: Variant=state.local_node_state.get(NODE_ID)
	if not node is Dictionary or not node.get(FIELD) is Dictionary or not node.get(CITY_FIELD) is Dictionary:return "城市或行军状态缺失。"
	var city_issue=_city_contract._validate_runtime(node[CITY_FIELD])
	if not city_issue.is_empty():return city_issue
	var order: Dictionary=node[FIELD]
	if not order.get("path_known") is bool or order.get("route_mode") not in ["main","trail"]:return "运行时险径条件无效。"
	if order.get("schema_version")!=1 or order.get("graph_version")!=definition.graph_version or not order.get("status") in ["idle","marching","waiting","arrived"]:return "行军状态版本无效。"
	if not order.get("path_nodes") is Array or not order.get("path_edges") is Array or not City.integer(order.get("edge_index")) or order.edge_index<0 or not order.get("receipts") is Array or order.receipts.size()>128:return "行军命令格式无效。"
	if order.status=="idle":
		if order.path_nodes.size()!=0 or order.path_edges.size()!=0 or order.edge_index!=0 or force.target_node_id!="" or edge_id!="":return "待命状态携带行军内容。"
	else:
		if order.goal not in ["tg_fore","tg_rear"] or order.path_nodes.size()!=order.path_edges.size()+1 or order.path_edges.is_empty() or order.path_edges.size()>3 or order.path_nodes[-1]!=order.goal:return "行军目标或道路链无效。"
		for edge in order.path_edges:
			if edge in ["tg_main_gate","tg_synthetic_trail"] and edge!=("tg_synthetic_trail" if order.route_mode=="trail" else "tg_main_gate"):return "路线选择与逻辑边不符。"
		for i in range(order.path_edges.size()):
			if not state.transit_corridors.has(order.path_edges[i]):return "命令引用未知道路。"
			var edge: Dictionary=state.transit_corridors[order.path_edges[i]]
			if [order.path_nodes[i],order.path_nodes[i+1]] not in [[edge.from_node_id,edge.to_node_id],[edge.to_node_id,edge.from_node_id]]:return "命令道路接点不连续。"
		if order.status=="arrived":
			if order.edge_index!=order.path_edges.size() or force.current_node_id!=order.goal or edge_id!="" or force.target_node_id!="":return "到达状态与军队位置不一致。"
		else:
			if order.edge_index>=order.path_edges.size() or force.current_node_id!=order.path_nodes[int(order.edge_index)] or force.target_node_id!=order.goal:return "行军命令与当前位置不一致。"
			if edge_id!="" and edge_id!=order.path_edges[int(order.edge_index)]:return "军队不在命令指定道路上。"
	var publication_issue=_publication_service.validate_meta(node.get(PRESENTATION_FIELD))
	if not publication_issue.is_empty():return publication_issue
	var economy_issue=_economy.validate(state,node[CITY_FIELD],_city_contract.runtime)
	if not economy_issue.is_empty():return economy_issue
	return ""
func write_save(path: String)->Dictionary:
	var issue=_validate(context.state)
	return _fail(issue) if not issue.is_empty() else Saves.new(definition.world_id).write_save(path,context.state)
func read_save(path: String)->Dictionary:
	var candidate=GameState.new();var result=Saves.new(definition.world_id).read_save(path,candidate)
	if not result.ok:return _fail(str(result.get("error","无法读取行军存档。")))
	var issue=_validate(candidate)
	if not issue.is_empty():return _fail(issue)
	var adopted=context.replace_state(candidate,true)
	if adopted.ok:_pending.clear();_build_pending.clear()
	return adopted
