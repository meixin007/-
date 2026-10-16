@tool
extends RefCounted
## Presentation diagnostics. Warnings guide human review and never alter rules.
const Catalog = preload("art_catalog.gd")
const Geometry = preload("geometry_ops.gd")
const Spatial = preload("art_spatial.gd")

static func inspect(doc: RefCounted, canvas: Control, scope: Rect2 = Rect2(), check_scope_edge: bool = false) -> Array:
	var issues: Array = []
	if doc.data.get("art_style", "schematic") != "tongguan_v1": return issues
	if canvas.depth_enabled():
		for issue in Spatial.conflict_pairs(canvas.spatial_entries()):
			if not scope.has_area() or issue.rect.intersects(scope): issues.append(issue)
	var expected: Dictionary = doc.data.get("presentation", {}).get("bundle", {})
	for difference in Catalog.bundle_differences(expected):
		issues.append({"code":"RESOURCE_VERSION", "feature_id":"", "message":"%s：%s 请先比较素材再决定是否更新。" % [difference.file,difference.reason], "rect":Rect2()})
	if not canvas.art.error.is_empty():
		issues.append({"code":"RESOURCE_LOAD", "feature_id":"", "message":canvas.art.error, "rect":Rect2()})
	var labels: Array = []
	var site_rects: Array = []
	var terrain_parts: Array = []
	var water_features: Array = []
	var ink_images: Dictionary = {}
	for item in doc.data.get("presentation",{}).get("instances",[]):
		var group: String = Catalog.descriptor(item.asset).get("group","")
		if (group not in ["mountain","forest"] and not Catalog.descriptor(item.asset).get("occludes_labels",false)) or item.get("opacity",1.0) < .4: continue
		terrain_parts.append({"id":item.id,"asset":item.asset,"rect":canvas.art.instance_rect(item.asset,Vector2(item.position[0],item.position[1]),item.scale)})
	for f in doc.data.features:
		if f.kind == "water": water_features.append(f)
		if not doc.layer(f.layer).visible or f.get("visual", {}).get("auxiliary", false) or not f.get("visual", {}).get("visible", true): continue
		var point := Vector2(f.points[0][0], f.points[0][1])
		if f.kind in ["city", "pass"]:
			var sprite_rect: Rect2 = canvas.art.site_rect(f, point)
			site_rects.append({"id":f.id,"name":f.name,"asset":Catalog.site_variant(f),"rect":sprite_rect})
			if not f.get("visual", {}).get("show_label", true): continue
			var visual: Dictionary = f.get("visual", {})
			var size_px := int(visual.get("label_size", maxf(10,22*f.scale)))
			var width: float = canvas.ink_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
			var offset: Array = visual.get("label_offset", [0,0])
			var baseline := Vector2(point.x-width*.5+offset[0],sprite_rect.end.y+13*f.scale+offset[1])
			labels.append({"id":f.id,"name":f.name,"kind":f.kind,"rect":Rect2(baseline-Vector2(2,size_px),Vector2(width+4,size_px+4))})
		elif f.kind == "label" and f.get("visual", {}).get("show_label", true):
			var visual: Dictionary = f.get("visual", {})
			var size_px := int(visual.get("label_size",34*f.scale))
			var width: float = canvas.ink_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_CENTER,-1,size_px).x
			var offset: Array = visual.get("label_offset", [0,0])
			var baseline := point+Vector2(offset[0],offset[1])
			labels.append({"id":f.id,"name":f.name,"kind":f.kind,"rect":Rect2(baseline-Vector2(width*.5+2,size_px),Vector2(width+4,size_px+4))})
	var page := Rect2(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])).grow(-12)
	for i in range(labels.size()):
		var label: Dictionary = labels[i]
		var rect: Rect2 = label.rect
		if scope.has_area() and not rect.intersects(scope): continue
		if check_scope_edge and scope.has_area() and not scope.grow(-6).encloses(rect):
			issues.append({"code":"LABEL_EXPORT_EDGE","feature_id":label.id,"message":"“%s”触及当前输出范围边缘。" % label.name,"rect":rect})
		if not page.encloses(rect):
			issues.append({"code":"LABEL_EDGE","feature_id":label.id,"message":"“%s”靠近地图边缘或被截断。" % label.name,"rect":rect})
		for j in range(i+1,labels.size()):
			var other: Dictionary = labels[j]
			if rect.grow(3).intersects(other.rect):
				issues.append({"code":"LABEL_COLLISION","feature_id":label.id,"message":"“%s”和“%s”标注相碰。" % [label.name,other.name],"rect":rect.merge(other.rect)})
		for site in site_rects:
			if site.id == label.id and _opaque_overlap(canvas,site.asset,site.rect,rect,ink_images) > .2:
				issues.append({"code":"LABEL_SELF","feature_id":label.id,"message":"“%s”标注压到自己的城关图像。" % label.name,"rect":rect})
				continue
			if site.id != label.id and _opaque_overlap(canvas,site.asset,site.rect,rect.grow(2),ink_images) > .1:
				issues.append({"code":"LABEL_SITE","feature_id":label.id,"message":"“%s”标注压到“%s”的城关图像。" % [label.name,site.name],"rect":rect})
				break
		for part in terrain_parts:
			if _opaque_overlap(canvas,part.asset,part.rect,rect,ink_images) > .25:
				issues.append({"code":"LABEL_ART","feature_id":label.id,"message":"“%s”标注压到美术部件 %s。" % [label.name,part.id],"rect":rect})
				break
		if label.kind in ["city","pass"]:
			for water in water_features:
				if Geometry.contains(water,rect.get_center()) or Geometry.contains(water,rect.position) or Geometry.contains(water,rect.end):
					issues.append({"code":"LABEL_WATER","feature_id":label.id,"message":"“%s”标注进入源水域，请人工核对。" % label.name,"rect":rect})
					break
	return issues

static func _opaque_overlap(canvas: Control, asset: String, art_rect: Rect2, label_rect: Rect2, images: Dictionary) -> float:
	if not art_rect.has_area() or not art_rect.intersects(label_rect): return 0.0
	var intersection := art_rect.intersection(label_rect)
	if not images.has(asset):
		var texture: Texture2D = canvas.art.texture(asset)
		images[asset] = texture.get_image() if texture != null else null
	var img: Image = images[asset]
	if img == null or img.is_empty(): return 0.0
	# A sprite's rectangular crop includes transparent sky and tapered ends.
	# Sample actual alpha so these margins do not become false label warnings.
	var samples_x := maxi(2, int(ceil(intersection.size.x / 2.0)))
	var samples_y := maxi(2, int(ceil(intersection.size.y / 2.0)))
	var opaque := 0
	for y in range(samples_y):
		for x in range(samples_x):
			var point := intersection.position + Vector2((x + .5) / samples_x * intersection.size.x, (y + .5) / samples_y * intersection.size.y)
			var texel := (point - art_rect.position) / art_rect.size * Vector2(img.get_size())
			if img.get_pixel(clampi(int(texel.x),0,img.get_width()-1),clampi(int(texel.y),0,img.get_height()-1)).a > .15:
				opaque += 1
	return float(opaque) / float(samples_x * samples_y) * intersection.get_area() / label_rect.get_area()
