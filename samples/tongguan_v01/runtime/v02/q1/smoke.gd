extends RefCounted
func run(boot: Node,output: String) -> Dictionary:
	var app=load("res://v02/q1/app.gd").new();boot.add_child(app)
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline and not app.service.detail_ready:await boot.get_tree().process_frame
	await boot.get_tree().create_timer(.4).timeout;await RenderingServer.frame_post_draw
	var image=boot.get_tree().root.get_texture().get_image();var failures: Array=[]
	if image.get_size()!=Vector2i(1920,1080):failures.append("actual FHD")
	if not app.service.detail_ready:failures.append("details not ready")
	if not app.service.loader.textures.is_empty():failures.append("eager cache")
	if image.save_png(output.get_base_dir()+"/smoke.png")!=OK:failures.append("capture")
	var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(image.get_region(Rect2i(20,96,1600,940)).get_data());var pixels=h.finish().hex_encode()
	var state: Dictionary=app.army().snapshot();app.service.dispose()
	for i in 1200:
		app.service.tick()
		if app.service.manager.accounting().inflight==0:break
		await boot.get_tree().process_frame
	await boot.get_tree().process_frame
	return {"checks":4,"failures":failures,"actual_viewport":[image.get_width(),image.get_height()],"map_pixel_sha256":pixels,"state":state,"engine":Engine.get_version_info(),"release":app.service.manager.accounting()}
