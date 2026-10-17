extends RefCounted
## Compiler input adapter, composing the existing validator without state writes.
const Publication=preload("res://integrity/publication.gd")
func capture(path: String) -> Dictionary:
	var validator=Publication.new()
	var result: Dictionary=validator.load_publication(path)
	if not result.ok:return {"ok":false,"code":"invalid_publication","message":result.message}
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var body: Dictionary=result.meta.authoring
	var raw_ids: Array=[]
	for item in original.source_v4.presentation.instances:raw_ids.append(item.id)
	var objects: Array=[]
	var ids: Array=body.generated.keys();ids.sort()
	for id in ids:
		var record: Dictionary=body.generated[id].duplicate(true)
		record.source_key=id;objects.append(record)
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://army/fixture.json"))
	var geography: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bundle/geography_metadata.json"))
	var coordinates={"publication":original.coordinate_contract.duplicate(true),"projection_wkt":geography.projection_wkt,"origin_albers_m":geography.origin_albers_m.duplicate(),"screen_axis":geography.screen_axis}
	var compatibility={"world_id":definition.world_id,"site_id":original.coordinate_contract.site_id,"layout_version":original.layout_version,"layout_slots_sha256":original.layout_slots_sha256,"fixed_refs_sha256":original.fixed_refs_sha256,"graph_version":definition.graph_version,"coordinate_sha256":validator.City.digest(coordinates)}
	var inputs: Array=[]
	for input in [path,"res://bundle/layout.json","res://bundle/geography_metadata.json","res://army/fixture.json"]:
		inputs.append({"path":input,"sha256":FileAccess.get_sha256(input)})
	return {"ok":true,"snapshot":{"schema_id":"tongguan.effective_map","schema_version":1,"compatibility":compatibility,"coordinates":coordinates,"objects":objects,"raw_instance_ids":raw_ids,"authoring":body.duplicate(true),"patch_sidecar":original.patch_sidecar.duplicate(true),"slots":validator.layout.slots.duplicate(true),"source_inputs":inputs,"publication_content_sha256":original.content_sha256,"source_v4_sha256":validator.City.digest(original.source_v4),"effective_patch_sha256":validator.City.digest(original.patch_sidecar),"generator_version":original.generator_version,"revision":body.revision,"source_format_versions":{"v4":original.source_v4.schema_version,"save":22}}}
