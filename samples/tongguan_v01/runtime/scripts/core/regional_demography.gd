extends RefCounted
## Persistent opening census estimates. Reading never invents current observations.
const FIELDS := ["population", "households", "farmland_mu"]
const LABELS := {"population":"人口", "households":"户数", "farmland_mu":"耕地田亩"}
const UNITS := {"population":"人", "households":"户", "farmland_mu":"唐亩"}

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 2000000000

static func _counts(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in FIELDS:
		if not _number(value.get(field)): return false
	return value.households <= value.population and value.population <= value.households * 12

static func _bounds(bounds: Variant, counts: Dictionary) -> bool:
	if not bounds is Dictionary: return false
	for field in FIELDS:
		var pair: Variant = bounds.get(field)
		if not pair is Array or pair.size() != 2 or not _number(pair[0]) or not _number(pair[1]): return false
		if pair[0] > counts[field] or pair[1] < counts[field]: return false
	return true

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":"地区户口田亩资料无效：" + message}

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary: return _fail("缺少开局统计")
	var data: Dictionary = value
	if not _number(data.get("version")) or not _number(data.get("observation_day")) or not _number(data.get("basis_year")): return _fail("年代字段类型")
	if data.get("version") != 1 or data.get("source_id") != "scenario:regional_census_756" or data.get("country_id") != "country:唐" or data.get("basis_year") != 756 or data.get("basis") != "opening_estimate" or data.get("observation_day") != 0: return _fail("统计版本或年代")
	for field in ["content_basis", "method", "map_sha256"]:
		if not data.get(field) is String or str(data[field]).is_empty(): return _fail("缺少 " + field)
	for field in ["sources", "regions", "prefectures"]:
		if not data.get(field) is Dictionary or data[field].is_empty(): return _fail("缺少 " + field)
	if data.regions.size() > 64 or data.prefectures.size() > 1000: return _fail("统计规模超限")
	for sid in data.sources:
		var source: Variant = data.sources[sid]
		if not sid is String or not source is Dictionary: return _fail("来源类型")
		for field in ["title", "period", "scope", "note", "kind", "url"]:
			if not source.get(field) is String: return _fail("来源字段 " + field)
		if source.kind not in ["historical_register", "historical_entitlement", "game_estimate"]: return _fail("来源类别")
		if source.kind == "historical_register" and (not _number(source.get("population")) or not _number(source.get("households"))): return _fail("历史户口数字")
	if data.sources.get("game_census_756_v1", {}).get("kind") != "game_estimate": return _fail("缺少估算说明")
	for sid in ["jiutangshu_38_national_740", "jiutangshu_38_land_entitlement"]:
		if not data.sources.has(sid): return _fail("缺少全国史料及土地口径")
	var seen := {}
	var cities := {}
	var domains := {}
	var national := {"population":0,"households":0,"farmland_mu":0}
	for region_id in data.regions:
		var region: Variant = data.regions[region_id]
		if not region_id is String or not region_id.begins_with("region:唐:") or not region is Dictionary: return _fail("道身份")
		if not region.get("name") is String or region_id != "region:唐:" + str(region.name) or not region.get("scope_note") is String: return _fail("道名称或范围")
		if not region.get("prefecture_ids") is Array or region.prefecture_ids.is_empty() or not _counts(region.get("totals")) or not _counts(region.get("unmapped")) or not _bounds(region.get("bounds"), region.totals): return _fail("道合计或未细分余量")
		var totals: Dictionary = region.unmapped.duplicate(true)
		for pid in region.prefecture_ids:
			if not pid is String or seen.has(pid) or not data.prefectures.has(pid): return _fail("州重复或缺失")
			seen[pid] = true
			var row: Variant = data.prefectures[pid]
			if not row is Dictionary or row.get("place_id") != pid or row.get("region_id") != region_id or not pid.begins_with("v02:唐:" + str(region.name) + ":"): return _fail("州归属")
			if not row.get("name") is String or not row.get("scope_note") is String or not _counts(row) or not _bounds(row.get("bounds"), row): return _fail("州数字或范围")
			if not row.get("source_ids") is Array or not row.source_ids.has("game_census_756_v1"): return _fail("州估算来源")
			for sid in row.source_ids:
				if not sid is String or not data.sources.has(sid): return _fail("未知来源")
			var historical_id: Variant = row.get("historical_source_id")
			if not historical_id is String or (historical_id != "" and (not row.source_ids.has(historical_id) or data.sources[historical_id].kind != "historical_register")): return _fail("历史锚点")
			if not _number(row.get("anchor_adjustment_percent")) or row.anchor_adjustment_percent < 50 or row.anchor_adjustment_percent > 150: return _fail("开局调整系数")
			if historical_id != "":
				for field in ["population", "households"]:
					var expected: int = int(data.sources[historical_id][field]) * int(row.anchor_adjustment_percent) / 10000 * 100
					if row[field] != expected: return _fail("史料锚点与调整结果不符")
			if not _number(row.get("city_share_percent")) or row.city_share_percent < 1 or row.city_share_percent > 50: return _fail("城市分摊比例")
			var city: Variant = row.get("city")
			if not city is Dictionary or city.get("place_id") != "city:" + pid.get_slice(":",3) or cities.has(city.get("place_id")): return _fail("城市身份")
			cities[city.place_id] = true
			if city.has("domain_id"):
				if not city.domain_id is String: return _fail("城市经营地点绑定类型")
				if not city.domain_id.is_empty():
					if domains.has(city.domain_id): return _fail("城市经营地点重复绑定")
					domains[city.domain_id]=true
			for field in ["population", "households"]:
				if not _number(city.get(field)) or city[field] != int(row[field]) * int(row.city_share_percent) / 100: return _fail("城市超出州或分摊不符")
			for field in FIELDS: totals[field] += int(row[field])
		for field in FIELDS:
			if totals[field] != region.totals[field]: return _fail("州与余量不等于道合计")
			national[field] += int(totals[field])
	if seen.size() != data.prefectures.size(): return _fail("存在游离州")
	if national.population < 45000000 or national.population > 55000000 or national.farmland_mu < 600000000 or national.farmland_mu > 1000000000: return _fail("超出全国设计范围")
	return {"ok":true}

static func project(state, place: Dictionary) -> Dictionary:
	var data: Dictionary = state.flags.get("regional_census", {})
	if data.is_empty(): return {}
	var id := str(place.get("id", ""))
	var kind := str(place.get("kind", ""))
	var counts := {"population":0,"households":0,"farmland_mu":0}
	var ranges := {"population":[0,0],"households":[0,0],"farmland_mu":[0,0]}
	var sources: Array = ["game_census_756_v1"]
	var notes: Array = ["756年开局估算 · 第0日资料，未随战况更新。"]
	var unmapped := {"population":0,"households":0,"farmland_mu":0}
	var is_city := kind == "city"
	if kind == "prefecture" or is_city:
		var pid := str(place.get("parent_id", "")) if is_city else id
		var row: Dictionary = data.prefectures.get(pid, {})
		if row.is_empty() or (is_city and row.city.place_id != id): return {}
		counts = row.city.duplicate(true) if is_city else row.duplicate(true)
		ranges = row.bounds.duplicate(true)
		if is_city:
			counts["farmland_mu"] = null
			for field in ["population", "households"]:
				ranges[field] = [int(ranges[field][0]) * int(row.city_share_percent) / 100, int(ranges[field][1]) * int(row.city_share_percent) / 100]
			notes.append("城市按所属州的 %d%% 分摊，已计入州总数；城市耕地未单列。" % int(row.city_share_percent))
		else:
			notes.append(row.scope_note)
		sources = row.source_ids.duplicate()
		if row.historical_source_id != "":
			var source: Dictionary = data.sources[row.historical_source_id]
			notes.append("史料参考：%s，%s；辖县合计 %d 人、%d 户。开局采用 %d%%（游戏参数）。" % [source.title, source.period, int(source.population), int(source.households), int(row.anchor_adjustment_percent)])
	elif (kind == "country" and id == data.country_id) or (kind == "region" and data.regions.has(id)):
		var ids: Array = data.regions.keys() if kind == "country" else [id]
		for rid in ids:
			var region: Dictionary = data.regions[rid]
			for field in FIELDS:
				counts[field] += int(region.totals[field])
				unmapped[field] += int(region.unmapped[field])
				ranges[field][0] += int(region.bounds[field][0])
				ranges[field][1] += int(region.bounds[field][1])
		notes.append("按地图展示分组汇总，含未细分地区；城市已计入州，不再重复累加。")
		notes.append("其中未细分地区：%d 人、%d 户、%d 唐亩（游戏估算）。" % [unmapped.population, unmapped.households, unmapped.farmland_mu])
		if kind == "country":
			var reference: Dictionary = data.sources.get("jiutangshu_38_national_740", {})
			if not reference.is_empty():
				sources.append("jiutangshu_38_national_740")
				notes.append("史料参考：%s，%d 人、%d 户；%s。与756年开局估算的年代及地域范围不同。" % [reference.title, int(reference.population), int(reference.households), reference.scope])
	else: return {}
	if not is_city: notes.append("田亩为实有耕地的游戏估算；史料应受田不作实垦田。唐亩不直接换算现代亩或地产面积单位。")
	var result := {"metrics":{}, "notes":notes, "unmapped":unmapped}
	for field in FIELDS:
		var refs: Array = ["game_census_756_v1"] if field == "farmland_mu" else sources.duplicate()
		result.metrics[field] = {"metric_id":field,"label":LABELS[field],"unit_id":UNITS[field],"value":counts[field],"knowledge_status":"unknown" if counts[field] == null else "estimated","observed_at":0,"period":"756年开局估算","source_refs":refs,"estimate_range":ranges[field] if counts[field] != null else [],"source_labels":refs.map(func(sid): return data.sources[sid].title)}
	return result.duplicate(true)
