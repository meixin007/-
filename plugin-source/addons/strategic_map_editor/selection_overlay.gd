@tool
extends RefCounted
# Screen-space display density never changes document vertices.
var cache_key: Array=[]
var handles: Array=[]
var outlines: Array=[]

func prepare(c, include_handles: bool=false) -> void:
	# Art tools never edit geography. Keep the selection, but do not traverse
	# dense rings or emit vertex handles while placing/moving artwork.
	if c.tool in ["art_stamp","art_place","art_select","art_erase"]:
		cache_key.clear();handles.clear();outlines.clear()
		return
	var key: Array=[c.doc.get_instance_id(),c.doc.revision,c.selection_ids.duplicate(),c.zoom,c.pan,c.size,c.drag_preview_revision,c.tool,include_handles]
	if key==cache_key:return
	cache_key=key
	handles=[];outlines=[]
	var candidates: Array=[]
	var viewport:=Rect2(Vector2.ZERO,c.size).grow(6)
	for id in c.selection_ids:
		var original: Dictionary=c.doc.find_feature(id)
		if original.is_empty() or not c.doc.layer(original.layer).visible:continue
		var f: Dictionary=c._preview_feature(original,true)
		for ring in range(-1,f.holes.size()):
			var points: Array=f.points if ring<0 else f.holes[ring]
			var line:=PackedVector2Array()
			for i in range(points.size()):
				var p: Vector2=Vector2(points[i][0],points[i][1])*c.zoom+c.pan
				line.append(p)
				if include_handles and viewport.has_point(p):candidates.append({"screen":p,"id":id,"ring":ring,"index":i})
			if line.size()>1:
				if f.kind in c.Doc.POLYGONS:line.append(line[0])
				var color: Color=c.BOUNDARY_COLORS.get(f.kind,Color("66a9c0") if f.kind in ["water","river"] else Color("f6c763",.75))
				outlines.append({"points":line,"ring":ring,"color":color})
	# Picking can request the original vertices, but drawing uses only lines.
	if not include_handles:return
	var spacing:=18.0
	while true:
		var cells: Dictionary={}
		handles=[]
		for handle in candidates:
			var cell:=Vector2i(floori(handle.screen.x/spacing),floori(handle.screen.y/spacing))
			if cells.has(cell):continue
			cells[cell]=true;handles.append(handle)
		if handles.size()<=350:break
		spacing*=1.4

func draw(c, surface: CanvasItem) -> void:
	prepare(c)
	if c.tool in ["art_stamp","art_place","art_select","art_erase"]:return
	for line in outlines:
		surface.draw_polyline(line.points,line.color,1.5,true)
	for id in c.selection_ids:
		var f: Dictionary=c.doc.find_feature(id)
		if f.is_empty() or not c.doc.layer(f.layer).visible:continue
		if c.tool!="visual_curve" and f.get("visual",{}).has("ridge_guide"):
			var ridge:=PackedVector2Array()
			for p in f.visual.ridge_guide:ridge.append(Vector2(p[0],p[1])*c.zoom+c.pan)
			if ridge.size()>1:surface.draw_polyline(ridge,Color("b78b4e",.65),2,true)
		if (c.show_rules or c.view_mode=="overlay") and c.has_art() and f.kind in ["city","pass"] and not f.get("visual",{}).get("anchor_only",false):
			var p:=Vector2(f.points[0][0],f.points[0][1])
			var descriptor: Dictionary=c.ArtCatalog.descriptor(c.ArtCatalog.site_variant(f))
			var anchor: Array=descriptor.get("gate_anchor",descriptor.get("anchor",[.5,.78]))
			var footprint: Rect2=c.art.site_rect(f,p)
			var gate: Vector2=(footprint.position+footprint.size*Vector2(anchor[0],anchor[1]))*c.zoom+c.pan
			surface.draw_line(p*c.zoom+c.pan,gate,Color("e0b65d",.85),1.5,true)
