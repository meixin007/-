extends RefCounted
## Immutable content definitions and observer-scoped development options.
## Existence of a catalog entry never creates a resource, a quote or a business.
const CYCLES := {"agriculture":"seasonal","husbandry":"biological","extraction":"depletion","manufacture":"batch","retail":"turnover","hospitality":"capacity","transport":"contract","custody":"contract","credit":"contract"}
const GROUPS := ["agriculture","husbandry","extraction","food","manufacture","retail","logistics","finance","services"]
const Accounts = preload("res://scripts/core/resource_account_service.gd")

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":"产业目录："+message}

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("version")!=1 or value.get("source_id")!="scenario:tang_industry_catalog_756" or not value.get("content_basis") is String: return _fail("缺少版本与内容来源")
	for key in ["groups","requirements","goods","models","sources","industries"]:
		if not value.get(key) is Dictionary or value[key].is_empty(): return _fail("缺少定义："+key)
	if value.groups.size()!=GROUPS.size(): return _fail("行业组范围不完整")
	for group in GROUPS:
		if not value.groups.get(group) is String or value.groups[group].is_empty(): return _fail("行业组名称无效")
	for table in [value.requirements,value.goods]:
		for id in table:
			if not id is String or id.is_empty() or not table[id] is String or table[id].is_empty(): return _fail("资源与条件须有稳定标识和名称")
	for id in value.models:
		var model: Variant = value.models[id]
		if not model is Dictionary or not CYCLES.has(id) or model.get("cycle")!=CYCLES[id] or not model.get("revenue") is String or not model.get("costs") is String: return _fail("经营分类或结算周期无效")
	for id in value.sources:
		var source: Variant = value.sources[id]
		if not source is Dictionary or source.get("basis") not in ["game_design","primary_text"]: return _fail("史料和游戏设计须区分")
		for key in ["title","url","note"]:
			if not source.get(key) is String: return _fail("来源说明无效")
		if source.basis=="primary_text" and not str(source.url).begins_with("https://"): return _fail("史料来源缺少链接")
	var used_groups := {}
	for id in value.industries:
		var row: Variant = value.industries[id]
		if not row is Dictionary or row.get("industry_id")!=id or not value.groups.has(row.get("group_id")) or not value.models.has(row.get("model")): return _fail("产业标识、行业组或经营分类无效")
		for key in ["name","regulation","risk_notes"]:
			if not row.get(key) is String or row[key].is_empty(): return _fail("缺少名称或风险制度说明")
		if row.get("cycle")!=CYCLES[row.model] or row.get("chronology") not in ["current_scope","later_institution"]: return _fail("产业周期或年代无效")
		for key in ["inputs","outputs","requirements","source_refs"]:
			if not row.get(key) is Array or row[key].is_empty(): return _fail("缺少投入产出、条件或来源")
			var registry: Dictionary = value.goods if key in ["inputs","outputs"] else value.requirements if key=="requirements" else value.sources
			var seen := {}
			for ref in row[key]:
				if not ref is String or not registry.has(ref) or seen.has(ref): return _fail("存在未知或重复引用："+key)
				seen[ref] = true
		var operation: Dictionary = preload("res://scripts/core/modeled_business_service.gd").validate_config(row.get("operation"))
		if not operation.ok: return operation
		used_groups[row.group_id] = true
	if used_groups.size()!=GROUPS.size(): return _fail("行业组没有实际条目")
	return {"ok":true}

static func project(state, data: Dictionary, scope: Dictionary, visible_assets: Array) -> Dictionary:
	var definition: Dictionary = data.get("industry_catalog",{})
	if definition.is_empty() or scope.get("kind") not in ["prefecture","city"]: return {}
	var result := {"groups":definition.groups.duplicate(true),"entries":[],"basis":definition.content_basis,"coverage":"已知数量仅计可见产业登记，不保证均在营业；零登记不构成禁建。具体选址仍须取得土地、人员、资源和许可。"}
	for id in definition.industries:
		var spec: Dictionary = definition.industries[id]
		var model: Dictionary = definition.models[spec.model]
		var row := {"industry_id":id,"name":spec.name,"group_id":spec.group_id,"model":spec.model,"cycle":spec.cycle,"known_count":0,"inputs":[],"outputs":[],"site_requirements":[],"income_basis":model.revenue,"cost_basis":model.costs,"regulation":spec.regulation,"risk_notes":spec.risk_notes,"sources":[],"sites":[],"actions":[],"status":"conditions_required","readiness":"已配置分类经营规则；须核对当地地块、资源、人选和预算。","missing":[]}
		for ref in spec.inputs: row.inputs.append(definition.goods[ref])
		for ref in spec.outputs: row.outputs.append(definition.goods[ref])
		for ref in spec.requirements: row.site_requirements.append(definition.requirements[ref])
		for ref in spec.source_refs: row.sources.append(definition.sources[ref].duplicate(true))
		row["operation_summary"]="按月合并经营，基础规模 %d；参考营造 %d 钱款单位、%d 工日、%d 面积单位。实际金额以地块报价为准。" % [spec.operation.capacity,spec.operation.build_cost,spec.operation.build_days,spec.operation.area_units]
		if int(spec.operation.maturity_days)>0: row.operation_summary+=" 成熟等待 %d 游戏日。" % int(spec.operation.maturity_days)
		if spec.operation.model=="farm": row.operation_summary+=" 采收月份：%s。" % str(spec.operation.harvest_months)
		for asset in visible_assets:
			if asset.asset_kind not in ["land","building","estate_building"] and asset.get("industry_id",asset.asset_kind)==id: row.known_count += 1
			if asset.asset_kind!="land": continue
			if not asset.get("current_details_available",true): continue
			var land: Dictionary = state.management_assets[asset.asset_id]
			# Only existing, visible, supplier-backed offers can appear as sites.
			if not land.development_offers.values().any(func(offer):return offer.industry_kind==id): continue
			var readiness := "有房屋方案；须核对产权与人员、预算。"
			var startup_actions: Array = asset.actions.filter(func(action):return action.kind=="commission_estate_startup" and action.parameters.blueprint_id==id)
			var can_commission := false
			if not startup_actions.is_empty():
				var terms: Dictionary = startup_actions[0].parameters
				can_commission = Accounts.new().available(state,terms.funding_account_id)>=int(terms.budget)
				readiness = "可进入地块核对筹办人、掌柜和预算。" if can_commission else "具备筹建方案；当前可用资金不足默认总预算，可进入地块调整。"
			elif not preload("res://scripts/core/land_property_service.gd").authority(state,land,state.player_character_id): readiness = "须先取得产权；公开报价不等于已有建设权。"
			else:
				readiness = "尚不能提交完整筹建：请在地块查看现有工程、可用面积、当地人员与资金来源。"
			row.sites.append({"asset_id":asset.asset_id,"name":asset.name,"can_commission":can_commission,"readiness":readiness})
		if spec.has("operation"):
			row.status = "conditions_required"
			row.readiness = "已接通自有空地委派筹建；仍需实际地块、人选和预算。"
			if row.sites.any(func(site):return site.can_commission): row.status = "available_plan"; row.readiness = "有可提交的筹建方案，进入地块核对后批准。"
			if row.sites.is_empty(): row.missing.append("当前可见地块尚无满足资源、许可及用地条件的对应报价；可以取得合适地块后筹建。")
			if visible_assets.any(func(asset):return asset.asset_kind=="land" and not asset.get("current_details_available",true)):
				row.missing.append("远地地块的可用面积与施工报价尚待回报；该行业仍可发展。")
		else:
			row.missing.append("经营规则待实施；下列为必要条件，不代表已经满足。")
			if row.sites.is_empty(): row.missing.append("尚无已知、具名供应方的本地施工报价。")
		if spec.chronology=="later_institution": row.status = "chronology_locked"; row.readiness = "当前开局尚未开放该制度。"
		result.entries.append(row)
	return result.duplicate(true)
