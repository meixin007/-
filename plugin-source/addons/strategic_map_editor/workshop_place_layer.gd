extends Node2D
## Rebuildable presentation index. Identity comes from explicit authoring links;
## this layer never creates campaign nodes or infers current political control.
const Geometry = preload("res://addons/strategic_map_editor/geometry_ops.gd")
const SpatialIndex = preload("res://addons/strategic_map_editor/spatial_index.gd")
signal place_clicked(place_id: String)
var places: Dictionary = {}
var anchors: Dictionary = {}
var anchor_places: Dictionary = {}
var domain_places: Dictionary = {}
var regions: Array = []
var region_index = SpatialIndex.new()
var city_images: Array = []
var bare_anchors: Array = []
var selected_id := ""
var hovered_id := ""
var outlines: Dictionary = {}
var _press := Vector2.INF
var _zoom := 1.0
var _show_sites := false
var canvas: Node2D
var art_canvas: Control
var government_lines: Dictionary = {}
var label_places: Dictionary = {}
var country_regions: Array = []
var country_index = SpatialIndex.new()

func configure(data: Dictionary, art: Control, map_canvas: Node2D) -> void:
	canvas = map_canvas
	art_canvas = art
	var visible_layers := {}
	for layer in data.layers: visible_layers[layer.id] = layer.visible
	for f in data.features:
		if f.kind in ["city","pass"] and f.points.size() == 1 and visible_layers.get(f.layer,true) and f.get("visual",{}).get("visible",true):
			anchors[f.id] = f
	var bounds: Array = []
	for f in data.features:
		if f.kind != "prefecture" or not visible_layers.get(f.layer,true) or not f.get("visual",{}).get("visible",true): continue
		var group := str(f.get("group_id",""))
		var key := group if not group.is_empty() else str(f.id)
		var parts := group.split(":")
		var anchor_id := ""
		if parts.size() == 4 and parts[0] == "v02": anchor_id = parts[3]
		elif parts.size() == 3 and parts[0] == "neighbor_v07": anchor_id = "neighbor_anchor_"+parts[2]
		# Unknown authoring groups remain selectable geography, without guessing a city.
		if not anchors.has(anchor_id): anchor_id = ""
		if not places.has(key):
			var anchor: Dictionary = anchors.get(anchor_id,{})
			places[key] = {"id":key,"name":str(f.name).trim_suffix("州域"),"kind":"prefecture",
				"country":str(parts[1]) if parts.size() >= 3 else "",
				"region":str(parts[2]) if parts.size() == 4 else "",
				"anchor_id":anchor_id,"city_name":anchor.get("name",""),"domain_id":anchor.get("domain_id","")}
			outlines[key] = []
			if not anchor_id.is_empty(): anchor_places[anchor_id] = key
			if not str(anchor.get("domain_id","")).is_empty(): domain_places[anchor.domain_id] = key
		var rings := Geometry.prepare_containment(f)
		regions.append({"place_id":key,"rings":rings})
		bounds.append(Rect2(rings[0].bounds.position+rings[0].origin,rings[0].bounds.size).grow(.01))
		for ring in [f.points]+f.get("holes",[]):
			var points := Geometry.packed(ring)
			if points.is_empty(): continue
			points.append(points[0])
			outlines[key].append(points)
	region_index.build(bounds)
	for id in anchors:
		var f: Dictionary = anchors[id]
		var parent_id := str(anchor_places.get(id,""))
		var parent: Dictionary = places.get(parent_id,{})
		var site_id := "city:"+str(id) if f.kind == "city" else str(id)
		places[site_id] = {"id":site_id,"name":f.name,"kind":f.kind,
			"parent_id":parent_id,"country":parent.get("country",""),"region":parent.get("region",""),
			"anchor_id":id,"city_name":f.name,"domain_id":f.get("domain_id","")}
		anchor_places[id] = site_id
		if not str(f.get("domain_id","")).is_empty() and not domain_places.has(f.domain_id): domain_places[f.domain_id] = site_id
	var illustrated := {}
	for instance in data.presentation.get("instances",[]):
		var anchor_id := str(instance.get("anchor_id",""))
		if not anchors.has(anchor_id) or float(instance.get("opacity",1.0)) <= .01: continue
		var at := Vector2(instance.position[0],instance.position[1])
		var rect: Rect2 = art.art.instance_rect(instance.asset,at,instance.scale)
		city_images.append({"rect":rect,"place_id":anchor_places[anchor_id]})
		illustrated[anchor_id] = true
	for id in anchors:
		if not illustrated.has(id): bare_anchors.append(id)
	_build_government_groups(data,visible_layers)
	for place in places.values():
		if place.kind not in ["city","pass"]: continue
		var parent: Dictionary = places.get(place.get("parent_id",""),{})
		for key in ["country_id","region_id"]:
			if parent.has(key): place[key] = parent[key]
	queue_redraw()

func _government_place(id: String, kind: String, country: String, region: String = "") -> void:
	if places.has(id): return
	places[id] = {"id":id,"name":country if kind == "country" else region,"kind":kind,
		"country":country,"region":region,"anchor_id":"","domain_id":"","city_name":"","node_ids":[]}

func _build_government_groups(data: Dictionary, visible_layers: Dictionary) -> void:
	var edges := {}
	# The atlas group hierarchy provides geography, never current ownership.
	for id in places.keys():
		var place: Dictionary = places[id]
		if place.kind != "prefecture" or str(place.country).is_empty(): continue
		var country_id := "country:"+str(place.country)
		var region_name := str(place.region) if not str(place.region).is_empty() else str(place.name)
		var region_id := "region:"+str(place.country)+":"+region_name
		_government_place(country_id,"country",place.country)
		_government_place(region_id,"region",place.country,region_name)
		place["country_id"] = country_id
		place["region_id"] = region_id
		place["parent_id"] = region_id
		places[region_id]["parent_id"] = country_id
		for parent in [country_id,region_id]:
			if not str(place.domain_id).is_empty() and not places[parent].node_ids.has(place.domain_id):
				places[parent].node_ids.append(place.domain_id)
			if not edges.has(parent): edges[parent] = {}
			for ring in outlines.get(id,[]):
				for i in range(ring.size()-1):
					var a: Vector2 = ring[i]; var b: Vector2 = ring[i+1]
					var a_key := "%.3f,%.3f" % [a.x,a.y]
					var b_key := "%.3f,%.3f" % [b.x,b.y]
					var key := a_key+"/"+b_key if a_key < b_key else b_key+"/"+a_key
					if edges[parent].has(key): edges[parent].erase(key)
					else: edges[parent][key] = [a*.25,b*.25]
	for id in edges:
		var lines := PackedVector2Array()
		for edge in edges[id].values(): lines.append(edge[0]); lines.append(edge[1])
		government_lines[id] = lines
	# Country outlines already include small islands and coastal gaps. Never
	# close an open border segment to create an invented territory polygon.
	var country_lines := {}
	var bounds: Array = []
	for f in data.features:
		if not visible_layers.get(f.layer,true) or not f.get("visual",{}).get("visible",true): continue
		var id := str(f.get("group_id",""))
		if f.kind == "country_border" and places.has(id) and f.points.size() >= 2:
			var points := Geometry.packed(f.points)
			if not country_lines.has(id): country_lines[id] = PackedVector2Array()
			var lines: PackedVector2Array = country_lines[id]
			for i in range(points.size()-1): lines.append(points[i]*.25); lines.append(points[i+1]*.25)
			country_lines[id] = lines
			if points.size() > 3 and points[0].distance_to(points[-1]) < .01:
				var rings := Geometry.prepare_containment(f)
				country_regions.append({"place_id":id,"rings":rings})
				bounds.append(Rect2(rings[0].bounds.position+rings[0].origin,rings[0].bounds.size).grow(.01))
		if f.kind == "label" and f.get("group_id","") == "atlas_labels":
			var matches: Array = []
			for key in government_lines:
				if places[key].name == f.name: matches.append(key)
			if matches.size() == 1: label_places[f.id] = matches[0]
	for id in country_lines: government_lines[id] = country_lines[id]
	country_index.build(bounds)

func pick_for_tier(source_point: Vector2, tier: String, site_radius: float = 0.0) -> String:
	if tier not in ["country","region"]: return pick(source_point,site_radius)
	var id := pick(source_point)
	if not id.is_empty(): return str(places[id].get("country_id" if tier == "country" else "region_id",""))
	if tier == "country":
		for i in country_index.query(Rect2(source_point,Vector2.ZERO)):
			if Geometry.contains_prepared(country_regions[i].rings,source_point): return country_regions[i].place_id
	return ""

func pick(source_point: Vector2, site_radius: float = 0.0) -> String:
	if site_radius > 0:
		# Artwork uses its current rectangle, independent of category or asset name.
		for i in range(city_images.size()-1,-1,-1):
			if city_images[i].rect.has_point(source_point): return city_images[i].place_id
		for id in bare_anchors:
			var p: Array = anchors[id].points[0]
			if Vector2(p[0],p[1]).distance_to(source_point) <= site_radius: return anchor_places[id]
	for i in region_index.query(Rect2(source_point,Vector2.ZERO)):
		if Geometry.contains_prepared(regions[i].rings,source_point): return regions[i].place_id
	return ""

func select(place_id: String) -> void:
	selected_id = place_id if places.has(place_id) else ""
	hovered_id = ""
	queue_redraw()

func _process(_delta: float) -> void:
	if canvas == null: return
	var zoom_value: float = canvas.get_camera().zoom.x
	var show_sites: bool = canvas.workshop_label_tier in ["prefecture","close"]
	if not is_equal_approx(zoom_value,_zoom) or show_sites != _show_sites:
		_zoom = zoom_value; _show_sites = show_sites; queue_redraw()

func at_screen(screen_point: Vector2) -> String:
	var camera: Camera2D = canvas.get_camera()
	var world := camera.get_screen_center_position()+(screen_point-camera.get_viewport_rect().size*.5)/camera.zoom.x
	var tier: String = canvas.workshop_label_tier
	# Match the rectangles actually drawn, including label avoidance offsets.
	if tier in ["country","region"] and is_instance_valid(art_canvas):
		for record in art_canvas.label_draw_records:
			if not record.get("drawn",false) or record.get("tier","") != tier or not label_places.has(record.id): continue
			var r: Array = record.rect
			if Rect2(r[0],r[1],r[2],r[3]).has_point(world*4.0): return label_places[record.id]
	return pick_for_tier(world*4.0,tier,28.0/camera.zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _press = event.position
		else:
			if _press.distance_to(event.position) <= 5.0:
				place_clicked.emit(at_screen(event.position))
				get_viewport().set_input_as_handled()
			_press = Vector2.INF
	elif event is InputEventMouseMotion and event.button_mask == 0:
		var id := at_screen(event.position)
		if hovered_id != id: hovered_id = id; queue_redraw()

func _draw() -> void:
	var width := 1.0/maxf(_zoom,.01)
	for entry in [[hovered_id,Color(0.35,0.29,0.12,.65),1.3],[selected_id,Color("ba672b"),2.5]]:
		if str(entry[0]).is_empty(): continue
		if government_lines.has(entry[0]):
			draw_multiline(government_lines[entry[0]],entry[1],entry[2]*width,true)
		for points in outlines.get(entry[0],[]):
			var line := PackedVector2Array()
			for p in points: line.append(p*.25)
			draw_polyline(line,entry[1],entry[2]*width,true)
	if _show_sites:
		for id in bare_anchors:
			var f: Dictionary = anchors[id]
			var p := Vector2(f.points[0][0],f.points[0][1])*.25
			draw_circle(p,4.0*width,Color("f5e7bd"))
			draw_arc(p,4.0*width,0,TAU,16,Color("77573e"),1.5*width,true)
	if not selected_id.is_empty():
		var anchor: Dictionary = anchors.get(places[selected_id].anchor_id,{})
		if not anchor.is_empty():
			var p := Vector2(anchor.points[0][0],anchor.points[0][1])*.25
			draw_arc(p,9.0*width,0,TAU,32,Color("ba672b"),2.0*width,true)
