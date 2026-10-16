extends RefCounted
## Derived display ownership only: never mutates records, IDs, saves or v4.
static func owner(point: Array)->String:return "%d:%d"%[floori(float(point[0])/512.0),floori(float(point[1])/512.0)]
static func raw_ids(records: Array)->Dictionary:
	var ids={}
	for record in records:
		if not record is Dictionary or not record.get("id") is String or record.id.is_empty() or ids.has(record.id):return {"ok":false,"message":"原始实例缺少ID或包含重复ID。","ids":ids}
		ids[record.id]=true
	return {"ok":true,"ids":ids}
static func plan(records: Array)->Dictionary:
	var identities=raw_ids(records)
	if not identities.ok:return {"ok":false,"entries":[],"memberships":{},"message":identities.message}
	var entries=[];var memberships={}
	for record in records:
		var point=record.get("position_m")
		if not point is Array or point.size()!=2:return {"ok":false,"entries":[],"memberships":{},"message":"实例接地点无效。"}
		var bounds=Rect2(float(point[0])-50,float(point[1])-72.4,100,100);var chunks=[]
		for y in range(floori(bounds.position.y/512),floori(bounds.end.y/512)+1):
			for x in range(floori(bounds.position.x/512),floori(bounds.end.x/512)+1):chunks.append("%d:%d"%[x,y])
		memberships[record.id]=chunks
		entries.append({"id":record.id,"owning_chunk":owner(point),"record":record})
	entries.sort_custom(func(a,b):return float(a.record.position_m[1])<float(b.record.position_m[1]))
	return {"ok":true,"entries":entries,"memberships":memberships}
static func select_chunks(index: Dictionary,chunks: Array)->Array:
	var rows=[]
	for row in index.entries:
		if index.memberships[row.id].any(func(chunk):return chunks.has(chunk)):rows.append(row)
	return rows
static func audit(entries: Array)->Dictionary:
	var seen={};var errors=[]
	for row in entries:
		if seen.has(row.id):errors.append("duplicate:"+str(row.id))
		seen[row.id]=true
		if row.owning_chunk!=owner(row.record.position_m) or row.record.id!=row.id:errors.append("owner_or_record:"+str(row.id))
	return {"ok":errors.is_empty(),"errors":errors,"count":seen.size()}
