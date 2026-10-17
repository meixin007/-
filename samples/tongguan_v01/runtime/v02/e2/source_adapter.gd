extends RefCounted
## Package metadata/payload is read once when a publication revision changes.
func token(loader: RefCounted) -> Dictionary:
	return {"world_id":loader.manifest.compatibility.world_id,"build_id":loader.manifest.build_id,"effective_revision":str(loader.provenance.get("source_snapshot_sha256",loader.manifest.build_id)),"asset_bounds_version":1,"cell_m":512}
func snapshot(loader: RefCounted) -> Dictionary:
	var shard_by_id: Dictionary={}
	for shard in loader.catalog.object_shards:
		if not loader.files.has(shard) or FileAccess.get_sha256(loader.root_path+"/"+str(shard))!=loader.files[shard].sha256:return {"error":{"code":"owner_payload_hash_mismatch"}}
		var parsed: Dictionary=loader.data(loader.root_path+"/"+str(shard))
		if not parsed.ok:return {"error":parsed}
		for record in parsed.value.objects:
			if shard_by_id.has(record.id):return {"error":{"code":"duplicate_id"}}
			shard_by_id[record.id]=shard
	var records: Array=[]
	for id in loader.objects:
		if not shard_by_id.has(id):return {"error":{"code":"missing_owner_payload"}}
		var record: Dictionary=loader.objects[id].duplicate(true);record.payload_shard=shard_by_id[id];records.append(record)
	return {"records":records,"assets":loader.assets.duplicate(true)}
