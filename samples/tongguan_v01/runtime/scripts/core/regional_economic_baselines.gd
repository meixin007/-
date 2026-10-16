extends RefCounted
const SOURCE="scenario:regional_economic_baselines_756"
const KEY="regional_economic_baselines"
const VALUES=["control","public_order","security","supply","prosperity"]
const IDENTITY=["source_id","census_prefecture_id","economic_basis","economic_basis_day","content_basis"]

static func _number(value: Variant, maximum: int=100) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=0 and value<=maximum and float(value)==floor(float(value))

static func _fail(reason: String) -> Dictionary: return {"ok":false,"error":"地区经营基准无效："+reason}

static func validate(pack: Variant, census: Dictionary) -> Dictionary:
	if not pack is Dictionary or not _number(pack.get("version"),1) or pack.version!=1 or pack.get("source_id")!=SOURCE or not pack.get("content_basis") is String or pack.content_basis.is_empty() or not pack.get("nodes") is Array: return _fail("缺少版本、来源或条目")
	var seen := {}
	for row in pack.nodes:
		if not row is Dictionary or not row.get("node_id") is String or row.node_id.is_empty() or seen.has(row.node_id): return _fail("地点重复或无效")
		seen[row.node_id]=true
		var prefecture: Dictionary=census.get("prefectures",{}).get(row.get("census_prefecture_id"),{})
		if prefecture.is_empty() or prefecture.get("city",{}).get("domain_id")!=row.node_id: return _fail("地点没有原人口统计与地图绑定来源")
		if row.get("source_id")!=SOURCE or row.get("economic_basis")!="opening_estimate" or not _number(row.get("economic_basis_day"),0) or row.get("content_basis")!=pack.content_basis: return _fail("条目来源或估算性质不符")
		for field in ["name","display_name","dominant_faction","active_office_holder"]:
			if not row.get(field) is String: return _fail("条目文本字段缺失")
		if row.dominant_faction!="" or row.active_office_holder!="": return _fail("开局基准不能补造实控者或官员")
		for field in VALUES:
			if not _number(row.get(field)): return _fail("基准参数越界")
		if not _number(row.get("communication_delay"),365): return _fail("通信参数越界")
		for field in ["recent_orders","linked_events","linked_fronts","rumors_or_uncertainty"]:
			if not row.get(field) is Array: return _fail("地方动态字段缺失")
	return {"ok":true}

static func merge_definitions(data: Dictionary, pack: Dictionary) -> Dictionary:
	var checked := validate(pack,data.get("regional_census",{}))
	if not checked.ok: return checked
	var inserted: Dictionary=pack.duplicate(true)
	inserted.nodes=[]
	for row in pack.nodes:
		if data.local_nodes.any(func(existing):return existing.get("node_id",existing.get("id"))==row.node_id): continue
		data.local_nodes.append(row.duplicate(true))
		inserted.nodes.append(row.duplicate(true))
	data[KEY]=inserted
	return {"ok":true}

static func validate_snapshot(raw: Dictionary) -> Dictionary:
	var pack: Variant=raw.get("flags",{}).get(KEY)
	if not raw.get("local_node_state",{}) is Dictionary: return _fail("地方状态类型无效")
	var nodes: Dictionary=raw.get("local_node_state",{})
	for node in nodes.values():
		if not node is Dictionary: return _fail("地方条目类型无效")
	if pack==null:
		# Earlier saves without this content remain valid; reading never injects it.
		return _fail("条目丢失来源注册表") if nodes.values().any(func(row):return row.get("source_id")==SOURCE) else {"ok":true}
	var checked := validate(pack,raw.get("flags",{}).get("regional_census",{}))
	if not checked.ok: return checked
	var registered := {}
	for row in pack.nodes:
		registered[row.node_id]=true
		var actual: Dictionary=nodes.get(row.node_id,{})
		if actual.get("node_id")!=row.node_id: return _fail("已初始化地点丢失")
		for field in IDENTITY:
			if actual.get(field)!=row[field]: return _fail("运行地点来源与注册记录不符")
		for field in VALUES:
			if not _number(actual.get(field)): return _fail("运行经营参数越界")
	for id in nodes:
		if nodes[id].get("source_id")==SOURCE and not registered.has(id): return _fail("运行地点没有对应来源条目")
	return {"ok":true}
