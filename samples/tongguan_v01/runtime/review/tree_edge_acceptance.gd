extends RefCounted
var tree: SceneTree
var root: Window
var checks:=0
var failures: Array=[]
var output: String
class Model extends RefCounted:
	var zoom:=2.4
	var anchor=Vector2.ZERO
	func local_to_screen(_point: Array,_viewport: Vector2)->Vector2:return anchor
class Probe extends "res://runtime/city_canvas.gd":
	var reference:=false
	var show_tree:=true
	var row={"id":"synthetic.edge","asset_version":1,"position_m":[0,0]}
	func _ready()->void:clip_contents=true
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("182b33"))
		if not show_tree:return
		if reference:
			var art: Dictionary=tree_art["tree_willow" if int(row.asset_version)==1 else "tree_grove"]
			var dims=Vector2(80*model.zoom,80*model.zoom*art.ratio)
			draw_texture_rect(art.texture,Rect2(model.anchor-dims*Vector2(art.anchor[0],art.anchor[1]),dims),false)
		else:_tree(row)
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label)
func frames(n:=2)->void:
	for i in n:await tree.process_frame
func run(boot: Node)->void:
	tree=boot.get_tree();root=tree.root;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;output="user://tests/review_edges.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.substr(9)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	tree.create_timer(130).timeout.connect(func():printerr("EDGE_TIMEOUT");tree.quit(1))
	if OS.get_cmdline_user_args().has("--expect-release"):check(not OS.is_debug_build(),"actual Release edge test")
	var source=root.get_node("Session").cache.tree_art;var ref=Probe.new();var actual=Probe.new()
	for canvas in [ref,actual]:
		canvas.model=Model.new();canvas.size=Vector2(800,800);canvas.position=Vector2(30 if canvas==ref else 940,120);canvas.tree_art=source.duplicate(true);boot.add_child(canvas)
	ref.reference=true
	ref.show_tree=false;actual.show_tree=false;await frames();await RenderingServer.frame_post_draw
	var background=root.get_texture().get_image().get_region(Rect2i(ref.position,ref.size)).get_data()
	var measurements=[];var actual_edge_pixels:=0
	for kind in ["tree_willow","tree_grove","synthetic_tall"]:
		var art=source["tree_grove" if kind=="tree_grove" else "tree_willow"].duplicate(true)
		if kind=="synthetic_tall":
			var image=Image.create(32,128,false,Image.FORMAT_RGBA8);image.fill(Color("64ce74"));art.texture=ImageTexture.create_from_image(image);art.ratio=4.0
		var version=2 if kind=="tree_grove" else 1;var key="tree_grove" if version==2 else "tree_willow"
		for canvas in [ref,actual]:canvas.tree_art[key]=art;canvas.row.asset_version=version;canvas.show_tree=true
		var dims=Vector2(192,192*art.ratio);var anchor=Vector2(art.anchor[0],art.anchor[1])
		for side in ["bottom","top","left","right"]:
			var cases=[]
			for penetration in [-10,0,2,6,20,40,60]:
				var at=Vector2(400,400)
				if side=="bottom":at.y=800+dims.y*anchor.y-penetration
				elif side=="top":at.y=-dims.y*(1-anchor.y)+penetration
				elif side=="left":at.x=-dims.x*(1-anchor.x)+penetration
				else:at.x=800+dims.x*anchor.x-penetration
				ref.model.anchor=at;actual.model.anchor=at;ref.queue_redraw();actual.queue_redraw();await frames();await RenderingServer.frame_post_draw
				var frame=root.get_texture().get_image();var expected=frame.get_region(Rect2i(ref.position,ref.size)).get_data();var got=frame.get_region(Rect2i(actual.position,actual.size)).get_data()
				var visible=expected!=background;var same=expected==got
				check(same,kind+" "+side+" penetration "+str(penetration))
				if side=="bottom" and at.y>900 and visible:actual_edge_pixels+=1
				cases.append({"penetration_px":penetration,"reference_has_pixels":visible,"matches":same})
				if side=="bottom" and penetration==40:frame.save_png(output.get_base_dir()+"/"+kind+"_bottom.png")
			measurements.append({"asset":kind,"edge":side,"samples":cases})
	check(actual_edge_pixels>0,"real or tall asset has visible crown while anchor exceeds old100px cull")
	for canvas in [ref,actual]:boot.remove_child(canvas);canvas.queue_free()
	await frames(4)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"visible_beyond_old_anchor_margin":actual_edge_pixels},"\t"))
	print("REVIEW_EDGES ",JSON.stringify({"checks":checks,"failures":failures}));tree.quit(0 if failures.is_empty() else 1)
