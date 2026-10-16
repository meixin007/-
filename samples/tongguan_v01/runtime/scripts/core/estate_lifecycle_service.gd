extends RefCounted
## Facility changes retain old buildings, books and obligations in the existing asset system.
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Workload=preload("res://scripts/core/character_workload_service.gd")
const Presence=preload("res://scripts/core/production_service.gd")
const KINDS=["expand_estate","demolish_estate","refit_estate"]

static func working(state, building_id: String) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_improvement" and row.get("building_id")==building_id and row.get("status")=="working":return row
	return {}

static func facility_snapshot(state, shop_id: String, day: int=-1) -> Dictionary:
	if day<0:day=int(state.current_day)
	var building_id: String=str(state.management_assets.get(shop_id,{}).get("building_id",""))
	var refs: Array=[]
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_improvement" and row.get("building_id")==building_id and row.get("status")=="completed" and int(row.get("completed_day",2147483647))<=day:refs.append(row.contract_id)
	refs.sort()
	return {"capacity_factor":1.0+0.25*refs.size(),"improvement_refs":refs}

static func additional_area(state, land_id: String) -> int:
	var result := 0
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_improvement" and row.get("land_id")==land_id and state.management_assets.get(row.get("building_id"),{}).get("status")!="demolished":result+=int(row.area_units)
	return result

static func quote(state, kind: String, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	var building: Dictionary=state.management_assets.get(shop.get("building_id"),{})
	var land: Dictionary=state.management_assets.get(building.get("land_id"),{})
	var origin: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	if shop.get("premises_kind")!="owned":return Contract.fail("只有当前自有场所的经营主体可扩建、改建或拆除；已交割旧店及仅有经营权的主体不可处分房产")
	if kind not in KINDS or building.get("asset_kind")!="estate_building" or building.get("status")!="in_use" or shop.get("status")!="closed" or origin.get("contract_kind")!="estate_construction":return Contract.fail("请先停业；只有实际建成且未拆除的自有设施可办理此项处置")
	if not working(state,str(building.asset_id)).is_empty():return Contract.fail("本设施已有未完扩建，不能重叠处置")
	var recipe: Dictionary=origin.recipe
	if kind=="expand_estate":
		if not facility_snapshot(state,str(shop.asset_id)).improvement_refs.is_empty():return Contract.fail("当前简明规则只开放一次扩建，请按已有规模经营或另选地筹建")
		var area: int=maxi(1,int(recipe.area_units)/2)
		if int(land.used_area_units)+area>int(land.area_units):return Contract.fail("土地剩余面积不足，不能侵占其他工程")
		return {"ok":true,"amount":maxi(1,ceili(float(recipe.price)*0.4)),"account_id":str(params.get("funding_account_id","")),"area_units":area,"duration_days":maxi(1,ceili(float(recipe.duration_days)*0.5)),"supplier_id":recipe.supplier_id,"payee_account_id":recipe.payee_account_id}
	var statement: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(state,str(shop.asset_id),0,int(state.current_day))
	if int(statement.principal_outstanding)>0 or int(statement.inventory_quantity)>0 or int(statement.work_in_progress_value)>0 or int(statement.current_arrears)>0:return Contract.fail("须先清理未收借款、存货、在制品或欠款；这些义务不能随拆除消失")
	for row in state.economic_contracts.values():
		if row.get("shop_id")==shop.asset_id and row.get("contract_kind") in ["managed_cultivation","manufacturing_batch"] and row.get("status") in ["working","ready","growing"]:return Contract.fail("生产或农季尚未结束，不能丢弃在制义务")
	for reservation in state.resource_reservations.values():
		if reservation.get("account_id")==shop.account_id and reservation.get("status")=="active":return Contract.fail("本店仍有预留款，请先撤回相关委托再处置")
	if kind=="refit_estate":
		var next: Dictionary=land.development_offers.get(params.get("blueprint_id"),{})
		if next.is_empty() or next.get("version")!=params.get("quote_version") or next.industry_kind==building.industry_kind:return Contract.fail("请选择另一种当地可建用途并重新核对报价")
		var free: int=int(land.area_units)-int(land.used_area_units)+int(building.area_units)
		for row in state.economic_contracts.values():
			if row.get("contract_kind")=="estate_improvement" and row.get("building_id")==building.asset_id:free+=int(row.area_units)
		if free<int(next.area_units):return Contract.fail("用途转换后的实际占地超过可用面积")
		return {"ok":true,"account_id":str(params.get("funding_account_id","")),"amount":int(next.price)}
	return {"ok":true,"account_id":"","amount":0}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	return quote(state,kind,params)

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String="") -> Dictionary:
	var checked := quote(state,kind,params)
	if not checked.ok:return checked
	var shop: Dictionary=state.management_assets[params.shop_id]
	var building: Dictionary=state.management_assets[shop.building_id]
	var land: Dictionary=state.management_assets[building.land_id]
	if not Accounts.new().can_operate(state,shop.account_id,principal) or not preload("res://scripts/core/land_lease_service.gd").building_access(state,building) or preload("res://scripts/core/land_lease_service.gd").permission(state,land,building.owner_ref,principal).is_empty():return Contract.fail("缺少房产及店款的处置权，或土地建设租约、抵押和争议尚未处理")
	if kind!="demolish_estate":
		var fund: Dictionary=state.resource_accounts.get(params.get("funding_account_id"),{})
		if fund.get("owner_ref")!=building.owner_ref or fund.get("unit_id")!="cash_unit" or not Accounts.new().can_operate(state,str(params.funding_account_id),principal):return Contract.fail("工程费用须由同一房产权利主体的有权账户支付")
	if kind=="expand_estate":
		if not Presence.present(state,checked.supplier_id,land.location_id) or not Workload.can_schedule(state,checked.supplier_id,"estate_construction",principal):return Contract.fail("原工匠不在场或无可用工日")
		if int(state.character_states[checked.supplier_id].get("relationships",{}).get(principal,0)) < -15:return Contract.fail("工匠目前不愿承接扩建")
		if state.economic_contracts.values().any(func(row):return row.get("supplier_id")==checked.supplier_id and row.get("status")=="working"):return Contract.fail("工匠已有未完工程，请待其完成")
		var id: String="improvement:"+execution
		var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":checked.payee_account_id,"amount":checked.amount,"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
		if not paid.ok:return paid
		land.used_area_units+=int(checked.area_units)
		building.contract_refs.append(id)
		state.economic_contracts[id]={"contract_id":id,"contract_kind":"estate_improvement","status":"working","shop_id":shop.asset_id,"building_id":building.asset_id,"land_id":land.asset_id,"owner_ref":building.owner_ref.duplicate(true),"principal_id":principal,"funding_account_id":params.funding_account_id,"quote":checked.duplicate(true),"amount":checked.amount,"area_units":checked.area_units,"duration_days":checked.duration_days,"supplier_id":checked.supplier_id,"created_day":int(state.current_day),"last_update_day":int(state.current_day),"last_work_day":int(state.current_day),"work_days":0,"work_log":[],"blocked_reason":"","receipt_id":execution,"party_refs":[building.owner_ref.entity_id,checked.supplier_id],"terms_version":1,"execution_refs":[execution]}
		return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"已付扩建工程款并预留新增用地；停业期间工资与既有合同继续，竣工后分类产能提高25%，原资金授权不增加。"}
	if kind=="refit_estate":
		var next: Dictionary=land.development_offers[params.blueprint_id]
		if not Presence.present(state,next.supplier_id,land.location_id) or not Workload.can_schedule(state,next.supplier_id,"estate_construction",principal) or state.economic_contracts.values().any(func(row):return row.get("supplier_id")==next.supplier_id and row.get("status")=="working"):return {"ok":false,"code":"awaiting_delivery","error":"原工匠缺位或已有未完工程，等待后再改建；旧设施与款项保留。"}
	var consent: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,str(shop.asset_id))
	if not consent.is_empty():
		var revoked: Dictionary=load("res://scripts/core/business_management_service.gd").apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution+":revoke")
		if not revoked.ok:return revoked
	var id: String="demolition:"+execution
	var area: int=int(building.area_units)
	var writeoff: int=int(state.economic_contracts[building.source_ref.entity_id].recipe.price)
	var setup: Dictionary=state.economic_contracts.get(shop.get("setup_contract_id"),{})
	writeoff+=int(setup.get("amount",0))
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_improvement" and row.get("building_id")==building.asset_id:area+=int(row.area_units);writeoff+=int(row.amount)
	land.used_area_units-=area
	land.status="developed" if int(land.used_area_units)>0 else "vacant"
	building.status="demolished"
	building["demolition_id"]=id
	building.contract_refs.append(id)
	state.economic_contracts[id]={"contract_id":id,"contract_kind":"estate_demolition","status":"settled","shop_id":shop.asset_id,"building_id":building.asset_id,"land_id":land.asset_id,"owner_ref":building.owner_ref.duplicate(true),"area_units":area,"day":int(state.current_day),"receipt_id":execution,"execution_refs":[execution],"party_refs":[building.owner_ref.entity_id],"terms_version":1,"salvage_amount":0,"consequence":"原工程、扩建和筹办投入无退款；土地保留；原店款与雇约仍归原主体并按原约处理。"}
	state.economic_contracts[id]["writeoff_amount"]=writeoff
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="maintenance" and row.get("shop_id")==shop.asset_id:
			row.status="terminated";row["ended_day"]=int(state.current_day);row["termination_ref"]=id
	if kind=="refit_estate":
		var rebuilt: Dictionary=load("res://scripts/core/estate_construction_service.gd").apply(state,"start_construction",{"land_id":land.asset_id,"blueprint_id":params.blueprint_id,"quote_version":params.quote_version,"funding_account_id":params.funding_account_id},principal,execution,reservation)
		if not rebuilt.ok:rebuilt["rollback_required"]=true;return rebuilt
		rebuilt["effect_refs"]=[id,rebuilt.result_ref]
		rebuilt["visible_summary"]="用途转换已拆旧并重新施工；旧投入无退款，旧款项和雇约保留，新设施须另行筹办开业。"
		return rebuilt
	return {"ok":true,"result_ref":id,"visible_summary":"已拆除并释放本设施用地；没有退款或新增利润，土地、原店款、雇约与历史账目保留。"}

static func settle_daily(state) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind")!="estate_improvement" or row.get("status")!="working" or int(row.last_update_day)>=int(state.current_day):continue
		row.last_update_day=int(state.current_day)
		var building: Dictionary=state.management_assets[row.building_id]
		if not preload("res://scripts/core/land_lease_service.gd").building_access(state,building):row.blocked_reason="土地建设权已失效，工程及已付费用保留。";continue
		if not Presence.present(state,row.supplier_id,building.location_id) or Workload.occupied_today(state,row.supplier_id,row.contract_id,row.principal_id,"estate_construction"):row.blocked_reason="原工匠缺位或今日已有其他工时。";continue
		row.blocked_reason=""
		Workload.record_work(state,row)
		if int(row.work_days)==int(row.duration_days):row.status="completed";row["completed_day"]=int(state.current_day)
	return {"ok":true}

static func validate(raw: Dictionary) -> Dictionary:
	var improved := {}
	for row in raw.economic_contracts.values():
		if row.get("contract_kind") not in ["estate_improvement","estate_demolition"]:continue
		var building: Dictionary=raw.management_assets.get(row.get("building_id"),{})
		var shop: Dictionary=raw.management_assets.get(row.get("shop_id"),{})
		var origin: Dictionary=raw.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
		var receipt: Dictionary=raw.action_receipts.get(row.get("receipt_id"),{})
		if origin.get("contract_kind")!="estate_construction" or building.get("land_id")!=row.get("land_id") or load("res://scripts/core/estate_property_transaction_service.gd").owner_before_receipt(raw,building,str(row.get("receipt_id","")))!=row.get("owner_ref") or shop.get("building_id")!=building.get("asset_id") or not building.get("contract_refs",[]).has(row.contract_id) or not receipt.get("effect_refs",[]).has(row.contract_id):return Contract.fail("设施处置缺少原房产、权利或提交回执")
		if row.contract_kind=="estate_improvement":
			var recipe: Dictionary=origin.recipe
			var paid: Dictionary=raw.resource_journal.get(row.receipt_id,{})
			if improved.has(building.asset_id) or row.get("status") not in ["working","completed"] or int(row.get("amount",0))!=maxi(1,ceili(float(recipe.price)*0.4)) or int(row.get("area_units",0))!=maxi(1,int(recipe.area_units)/2) or int(row.get("duration_days",0))!=maxi(1,ceili(float(recipe.duration_days)*0.5)) or row.get("supplier_id")!=recipe.supplier_id or not row.get("work_log") is Array or int(row.get("work_days",-1))!=row.work_log.size() or int(row.work_days)>int(row.duration_days) or (row.status=="completed")!=(int(row.work_days)==int(row.duration_days)):return Contract.fail("扩建规模、报价或实际工日不符")
			if paid.get("amount")!=row.amount or paid.get("reason_ref")!=row.contract_id or paid.get("source_account_id")!=row.get("funding_account_id") or paid.get("destination_account_id")!=recipe.payee_account_id or raw.resource_accounts.get(row.funding_account_id,{}).get("owner_ref")!=row.owner_ref:return Contract.fail("扩建缺少实际工程款")
			if not Contract.amount(row.get("created_day")) or paid.get("day")!=row.get("created_day") or int(row.created_day)>int(raw.current_day) or (row.status=="completed" and (row.get("completed_day")!=row.get("last_work_day") or int(row.get("completed_day",2147483647))>int(raw.current_day))):return Contract.fail("扩建创建或竣工时间与实际付款、工日不符")
			improved[building.asset_id]=true
		else:
			var area: int=int(building.area_units)
			var writeoff: int=int(origin.recipe.price)+int(raw.economic_contracts.get(shop.get("setup_contract_id"),{}).get("amount",0))
			for other in raw.economic_contracts.values():
				if other.get("contract_kind")=="estate_improvement" and other.get("building_id")==building.asset_id:area+=int(other.area_units);writeoff+=int(other.amount)
			if int(row.get("writeoff_amount",-1))!=writeoff:return Contract.fail("设施核销损失与原建设、筹办和扩建投入不符")
			if building.get("status")!="demolished" or building.get("demolition_id")!=row.contract_id or shop.get("status")!="closed" or row.get("status")!="settled" or not Contract.amount(row.get("day")) or int(row.day)>int(raw.current_day) or row.get("salvage_amount")!=0 or int(row.get("area_units",0))!=area:return Contract.fail("拆除及释放土地缺少对应处置来源")
	for building in raw.management_assets.values():
		if building.get("asset_kind")=="estate_building" and building.get("status")=="demolished" and raw.economic_contracts.get(building.get("demolition_id"),{}).get("contract_kind")!="estate_demolition":return Contract.fail("不能无回执抹去既有房产")
	for row in raw.economic_contracts.values():
		if row.get("contract_kind")=="maintenance" and row.get("status")=="terminated":
			var ended: Dictionary=raw.economic_contracts.get(row.get("termination_ref"),{})
			var handed: Dictionary=raw.economic_contracts.get(row.get("property_termination_ref"),{})
			var valid_handover: bool=handed.get("contract_kind") in ["estate_property_sale","estate_operating_right"] and handed.get("source_shops",[]).has(row.get("shop_id")) and handed.get("day")==row.get("ended_day")
			if ((ended.get("contract_kind")!="estate_demolition" or ended.get("shop_id")!=row.get("shop_id") or ended.get("day")!=row.get("ended_day")) and not valid_handover) or int(row.get("arrears",-1))!=0:return Contract.fail("维护停止缺少实际拆除或场所移交依据，或仍有欠款")
	return {"ok":true}

static func validate_facility(raw: Dictionary, shop_id: String, day: int, value: Variant) -> Dictionary:
	if not value is Dictionary or value!=facility_snapshot(raw,shop_id,day):return Contract.fail("设施能力与当日实际竣工扩建不符")
	return {"ok":true}
