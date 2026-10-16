@tool
extends Node
## Offline images only. All tiles share one coordinate system and one immutable snapshot.
signal progress(done: int, total: int)
const Doc = preload("document.gd")
const Canvas = preload("map_canvas.gd")
const ArtCatalog = preload("art_catalog.gd")
const VisualAudit = preload("art_visual_audit.gd")
var cancelled := false
const BLEED := 4

static func plan(world: Vector2, longest: int, tile_size: int = 2048) -> Dictionary:
	if not world.is_finite() or world.x < 1 or world.y < 1 or longest < 1 or longest > 65536 or tile_size < 64 or tile_size > 2048:
		return {"error":"输出最长边应为 1–65536，分块边长应为 64–2048。"}
	var ratio := float(longest)/maxf(world.x,world.y)
	var extent := Vector2i(ceili(world.x*ratio),ceili(world.y*ratio))
	var parts: Array = []
	for y in range(0,extent.y,tile_size):
		for x in range(0,extent.x,tile_size):
			var pixels := Rect2i(x,y,mini(tile_size,extent.x-x),mini(tile_size,extent.y-y))
			parts.append({"pixels":pixels,"world":Rect2(Vector2(pixels.position)/ratio,Vector2(pixels.size)/ratio)})
	return {"error":"","size":extent,"ratio":ratio,"tiles":parts}

static func _publish(temp: String, path: String) -> String:
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path,path+".bak") != OK: return "无法备份原文件；新内容保留在 .tmp。"
	if DirAccess.rename_absolute(temp,path) != OK: return "无法替换目标文件；新内容保留在 .tmp。"
	return ""

static func _atomic_json(value: Dictionary, path: String) -> String:
	var temp := path + ".tmp"
	var error := _stage_json(value,temp)
	if not error.is_empty(): return error
	return _publish(temp, path)

static func _stage_json(value: Dictionary, temp: String) -> String:
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return "无法写入导出清单。"
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var code := file.get_error()
	file.close()
	if code != OK: return "导出清单写入失败。"
	return ""

static func _atomic_image_and_index(image: Image, value: Dictionary, png_path: String, json_path: String) -> String:
	if DirAccess.dir_exists_absolute(png_path) or DirAccess.dir_exists_absolute(json_path): return "图片或来源索引路径已被目录占用，原交付保留。"
	var png_temp := png_path + ".tmp"
	var json_temp := json_path + ".tmp"
	if image.save_png(png_temp) != OK: return "写入 PNG 临时文件失败，原交付保留。"
	var error := _stage_json(value,json_temp)
	if not error.is_empty():
		DirAccess.remove_absolute(png_temp)
		DirAccess.remove_absolute(json_temp)
		return error + " 原交付保留。"
	var had_png := FileAccess.file_exists(png_path)
	var had_json := FileAccess.file_exists(json_path)
	if (had_png and DirAccess.copy_absolute(png_path,png_path+".bak") != OK) or (had_json and DirAccess.copy_absolute(json_path,json_path+".bak") != OK):
		DirAccess.remove_absolute(png_temp)
		DirAccess.remove_absolute(json_temp)
		return "无法备份旧图片或来源索引，原交付保留。"
	if DirAccess.rename_absolute(png_temp,png_path) != OK:
		DirAccess.remove_absolute(json_temp)
		return "无法发布 PNG，原交付保留；临时图片待检查。"
	if DirAccess.rename_absolute(json_temp,json_path) != OK:
		var restored := DirAccess.copy_absolute(png_path+".bak",png_path) == OK if had_png else DirAccess.remove_absolute(png_path) == OK
		return "无法发布来源索引；%s。" % ("旧图片已恢复" if restored else "图片回退失败，请检查 .bak")
	return ""

func run(document: RefCounted, path: String, longest: int = 4096, tiled: bool = false, tile_size: int = 2048, region: Rect2 = Rect2(), options: Dictionary = {}) -> String:
	cancelled = false
	if not ArtCatalog.bundle_differences(document.data.get("presentation",{}).get("bundle",{})).is_empty(): return "地图引用的美术素材包已变化；请在工坊对照并确认资源版本后再导出。"
	var layer: String = options.get("layer", "composite")
	var preset: String = options.get("preset", "display")
	if layer not in ["composite", "terrain", "sites", "labels"] or preset not in ["display", "debug"]: return "未知导出图层或预设。"
	var transparent: bool = options.get("transparent", layer != "composite")
	var include_labels: bool = options.get("include_labels", layer in ["composite", "labels"])
	var include_auxiliary: bool = options.get("include_auxiliary", preset == "debug")
	var label_clip: String = options.get("label_clip", "allow")
	if label_clip not in ["allow","block"]: return "未知标注裁切策略。"
	var world := Vector2i(document.data.canvas_size[0],document.data.canvas_size[1])
	var whole := Rect2(Vector2.ZERO,Vector2(world))
	if region == Rect2(): region = whole
	if not region.has_area() or not whole.encloses(region): return "导出范围必须在画布内。"
	var layout := plan(region.size,longest,tile_size)
	if not layout.error.is_empty(): return layout.error
	if not tiled and longest > 8192: return "单张 PNG 最长边上限 8192；更大输出请选择分块图集。"
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()): return "导出目录不存在。"
	var copy = Doc.new()
	var error: String = copy.replace_document(document.snapshot())
	if not error.is_empty(): return error
	var folder := ""
	var created: Array[String] = []
	if tiled:
		folder = absolute.get_file().get_basename()+"_tiles_"+str(Time.get_ticks_usec())
		if DirAccess.make_dir_absolute(absolute.get_base_dir().path_join(folder)) != OK: return "无法创建分块目录。"
	var merged: Image
	if not tiled: merged = Image.create_empty(layout.size.x,layout.size.y,false,Image.FORMAT_RGBA8)
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var painter = Canvas.new()
	painter.export_mode = true
	painter.show_rules = false
	painter.export_layer = layer
	painter.transparent_page = transparent
	painter.include_labels = include_labels
	painter.include_auxiliary = include_auxiliary
	painter.view_mode = "structure" if preset == "debug" else "art"
	painter.export_debug = preset == "debug"
	viewport.add_child(painter)
	painter.zoom = layout.ratio
	painter.bind_document(copy)
	if painter.has_art() and not painter.art.error.is_empty():
		viewport.queue_free()
		if tiled: DirAccess.remove_absolute(absolute.get_base_dir().path_join(folder))
		return painter.art.error
	if include_labels and label_clip == "block":
		var clipped: Array = VisualAudit.inspect(copy,painter,region,true).filter(func(issue): return issue.code == "LABEL_EXPORT_EDGE")
		if not clipped.is_empty():
			viewport.queue_free()
			if tiled: DirAccess.remove_absolute(absolute.get_base_dir().path_join(folder))
			return "有 %d 处标注触及输出范围边缘；请调整范围或选择允许裁切。" % clipped.size()
	var manifest := {"schema_version":2,"document_type":"strategic_map_image_tiles" if tiled else "strategic_map_image","authoring_only":true,"title":copy.data.title,"source_fingerprint":document.fingerprint(),"coordinate_frame":copy.data.production.coordinate_frame,"world_size":[world.x,world.y],"region":[region.position.x,region.position.y,region.size.x,region.size.y],"art_style":copy.data.get("art_style","schematic"),"art_bundle":copy.data.get("presentation",{}).get("bundle",{}),"export_options":{"preset":preset,"layer":layer,"transparent":transparent,"include_labels":include_labels,"include_auxiliary":include_auxiliary,"label_clip":label_clip},"pixel_size":[layout.size.x,layout.size.y],"pixels_per_world_unit":layout.ratio,"tiles":[]}
	var index := 0
	manifest["depth_sort"]=painter.depth_enabled()
	manifest["layer_compositing"]="depth_interleaved_composite_required" if painter.depth_enabled() else "legacy_layer_order"
	for part in layout.tiles:
		if cancelled: error = "导出已取消，未完成内容已清理。"; break
		var pixels: Rect2i = part.pixels
		viewport.size = pixels.size+Vector2i.ONE*BLEED*2
		painter.size = Vector2(viewport.size)
		painter.pan = Vector2.ONE*BLEED-Vector2(pixels.position)-region.position*layout.ratio
		painter.queue_redraw()
		await get_tree().process_frame
		# Editor low-processor mode may not emit frame_post_draw while waiting on it.
		RenderingServer.force_draw()
		await get_tree().process_frame
		RenderingServer.force_draw()
		if painter.has_art() and not painter.art.error.is_empty(): error=painter.art.error; break
		var source := viewport.get_texture().get_image()
		if source == null or source.is_empty(): error = "无法取得渲染图片。"; break
		var tile := source.get_region(Rect2i(Vector2i.ONE*BLEED,pixels.size))
		tile.convert(Image.FORMAT_RGBA8)
		if tiled:
			var name := folder.path_join("tile_%d_%d.png" % [pixels.position.x,pixels.position.y])
			var destination := absolute.get_base_dir().path_join(name)
			created.append(destination)
			if tile.save_png(destination) != OK: error = "分块 PNG 写入失败。"; break
			var tile_region: Rect2 = part.world
			tile_region.position += region.position
			manifest.tiles.append({"file":name,"pixel_rect":[pixels.position.x,pixels.position.y,pixels.size.x,pixels.size.y],"world_rect":[tile_region.position.x,tile_region.position.y,tile_region.size.x,tile_region.size.y]})
		else: merged.blit_rect(tile,Rect2i(Vector2i.ZERO,pixels.size),pixels.position)
		index += 1
		progress.emit(index,layout.tiles.size())
	viewport.queue_free()
	if cancelled and error.is_empty(): error = "导出已取消，未完成内容已清理。"
	if error.is_empty():
		if tiled:
			manifest["outputs"] = manifest.tiles.map(func(item): return item.file)
			error = _atomic_json(manifest, absolute)
		else:
			manifest["outputs"] = [absolute.get_file()]
			error = _atomic_image_and_index(merged,manifest,absolute,absolute.get_basename()+".json")
	if not error.is_empty() and tiled:
		# Delete only paths created by this invocation; never recursively delete user folders.
		for own_file in created: DirAccess.remove_absolute(own_file)
		DirAccess.remove_absolute(absolute.get_base_dir().path_join(folder))
	return error
