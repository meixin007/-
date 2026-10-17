extends RefCounted
## Only imported Texture2D resources use the engine worker API. JSON stays FileAccess.
var holds: Dictionary={}
var faults: Dictionary={}
var stats: Dictionary={"requests":0,"gets":0,"premature_gets":0}
func begin(key: String,row: Dictionary) -> Dictionary:
	var fault: String=str(faults.get(row.path,""))
	if fault=="missing":return {"ok":false,"code":"missing_texture"}
	if not FileAccess.file_exists(row.source_path):return {"ok":false,"code":"missing_texture"}
	if fault=="hash" or FileAccess.get_sha256(row.source_path)!=row.sha256:return {"ok":false,"code":"hash_mismatch"}
	if not ResourceLoader.exists(row.import_path,"Texture2D"):return {"ok":false,"code":"missing_imported_texture"}
	var error:=ResourceLoader.load_threaded_request(row.import_path,"Texture2D",false,ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if error!=OK:return {"ok":false,"code":"thread_request_failed","error":error}
	stats.requests+=1
	if fault=="delay":holds[key]=true
	return {"ok":true}
func status(key: String,row: Dictionary) -> int:
	if holds.has(key):return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return ResourceLoader.load_threaded_get_status(row.import_path)
func take(key: String,row: Dictionary) -> Dictionary:
	if status(key,row)!=ResourceLoader.THREAD_LOAD_LOADED:stats.premature_gets+=1;return {"ok":false,"code":"not_loaded"}
	stats.gets+=1
	var texture=ResourceLoader.load_threaded_get(row.import_path) as Texture2D
	if texture==null:return {"ok":false,"code":"invalid_texture"}
	return {"ok":true,"texture":texture}
func validate(texture: Texture2D,row: Dictionary) -> Dictionary:
	if texture.get_width()!=int(row.pixel_size[0]) or texture.get_height()!=int(row.pixel_size[1]):return {"ok":false,"code":"imported_size_mismatch"}
	# No GPU readback in production adoption. Immutable build/import identity is
	# sealed; native acceptance separately verifies actual pixels outside this budget.
	return {"ok":true}
