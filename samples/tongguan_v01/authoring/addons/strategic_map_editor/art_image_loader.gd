@tool
extends RefCounted
## Pure CPU work, safe on a thumbnail worker. No scene tree or GPU calls.
static func read_cell(job: Dictionary, source: Image = null) -> Dictionary:
	var path: String = job.path
	var expected: Dictionary = job.expected
	if source == null:
		var bytes := FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
		if hash.finish().hex_encode() != str(expected.get("sha256", "")).to_lower():
			return {"error":"美术素材包哈希不匹配：" + path}
		source = Image.new()
		if source.load_png_from_buffer(bytes) != OK or source.is_empty():
			return {"error":"无法加载美术素材：" + path}
	if source.get_width() != expected.get("width", -1) or source.get_height() != expected.get("height", -1):
		return {"error":"美术素材尺寸与清单不符：" + path}
	var r: Array = job.descriptor.rect
	var region := Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))
	if not Rect2i(Vector2i.ZERO,source.get_size()).encloses(region):
		return {"error":"素材裁切区域超出图集：" + str(job.key)}
	var cell := source.get_region(region)
	for x in cell.get_width():
		if cell.get_pixel(x,0).a > .1 or cell.get_pixel(x,cell.get_height()-1).a > .1:
			return {"error":"素材触及图集上下边界：" + str(job.key)}
	for y in cell.get_height():
		if cell.get_pixel(0,y).a > .1 or cell.get_pixel(cell.get_width()-1,y).a > .1:
			return {"error":"素材触及图集左右边界：" + str(job.key)}
	var used := cell.get_used_rect()
	if not used.has_area(): return {"error":"空白美术素材：" + str(job.key)}
	return {"error":"","cell":cell.get_region(used),"source":source}

static func thumbnail(job: Dictionary) -> Dictionary:
	var result := read_cell(job)
	if not result.error.is_empty(): return result
	var cell: Image = result.cell
	var ratio := minf(1.0,128.0/maxi(cell.get_width(),cell.get_height()))
	cell.resize(maxi(1,roundi(cell.get_width()*ratio)),maxi(1,roundi(cell.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	return {"error":"","image":cell}
