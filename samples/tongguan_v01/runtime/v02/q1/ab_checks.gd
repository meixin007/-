extends RefCounted
func run(boot: Node,output: String) -> Dictionary:
	var mode:="new";var seconds:=60.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ab-mode="):mode=arg.substr(10)
		if arg.begins_with("--seconds="):seconds=float(arg.substr(10))
	var tree=boot.get_tree();var failures: Array=[];var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://v02/q1/config.json"))
	var old=tree.root.get_node("Session");var session=load("res://v02/q1/ab_session.gd").new();session.army=old.army;session.state=old.state;tree.root.remove_child(old);old.queue_free();session.name="Session";tree.root.add_child(session)
	var model=load("res://runtime/model.gd").new();var adapter: RefCounted
	if mode=="old":session.visual_service=load("res://v02/map_services.gd").new("legacy");session.cache=session.visual_service.cache
	else:
		adapter=load("res://v02/q1/ab_cache.gd").new();var admitted: Dictionary=adapter.setup(config.packages.ab,model)
		if not admitted.ok:failures.append(admitted)
		session.cache=adapter;session.visual_service=adapter
	for i in 1800:
		if mode=="old":session.cache.tick()
		else:adapter.update(0,-270,.84)
		if session.cache.ready:break
		await tree.process_frame
	var canvas=load("res://review/canvas.gd").new();canvas.model=model;canvas.position=Vector2(20,96);canvas.size=Vector2(1600,940);boot.add_child(canvas)
	if mode!="old":adapter.canvas=canvas
	var raw=FileAccess.open(output.get_base_dir()+"/ab_frames.csv",FileAccess.WRITE);raw.store_string("frame,process_start_usec,interval_ms,phase,track_seconds,x_m,y_m,zoom,update_usec,candidates,submitted,sort_rebuilds,resident_bytes\n")
	var keys: Array=[[0,0,-270,.84],[8,-535,-227.5,2.4],[16,-60,-600,1.4],[24,600,300,.42],[32,-600,800,.105],[40,0,0,.025],[48,-500000,100000,.00014],[56,-600,800,.105],[60,0,-270,.84]]
	var start:=Time.get_ticks_usec();var begin:=start+3000000;var last:=start;var frame:=0;var previous: Array=[];var buffer:="";var captured: Dictionary={};var telemetry: Array=[]
	while true:
		await tree.process_frame
		var now:=Time.get_ticks_usec();var elapsed: float=(now-begin)/1000000.0
		if not previous.is_empty():
			var row: Array=[frame,last,(now-last)/1000.0];row.append_array(previous);var strings=PackedStringArray()
			for value in row:strings.append(str(value))
			buffer+=",".join(strings)+"\n";frame+=1
		last=now
		if elapsed>=seconds:break
		var t:=fposmod(maxf(0,elapsed),60);var camera: Array=[0,-270,.84]
		for i in range(keys.size()-1):
			var a: Array=keys[i];var b: Array=keys[i+1]
			if t>=a[0] and t<=b[0]:
				var weight: float=(t-a[0])/(b[0]-a[0]);weight=weight*weight*(3-2*weight);camera=[lerpf(a[1],b[1],weight),lerpf(a[2],b[2],weight),exp(lerpf(log(a[3]),log(b[3]),weight))];break
		var stamp:=Time.get_ticks_usec();model.camera_x=model.view.world_origin[0]+camera[0];model.camera_y=model.view.world_origin[1]+camera[1];model.set_zoom(camera[2])
		if mode=="old":session.cache.tick()
		else:adapter.update(camera[0],camera[1],camera[2])
		canvas.queue_redraw();var update_usec:=Time.get_ticks_usec()-stamp;var draw: Dictionary=session.visual_service.last_draw
		var bytes:=0
		if mode!="old":bytes=adapter.service.manager.accounting().resident
		previous=["steady" if elapsed>=0 else "warmup",maxf(0,elapsed),camera[0],camera[1],camera[2],update_usec,draw.get("candidates_tested",0),draw.get("submitted_objects",0),session.visual_service.plan_rebuilds,bytes]
		if frame%256==0:raw.store_string(buffer);buffer=""
	raw.store_string(buffer);raw.close()
	# Matching fixed cameras are captured only after sampling, never inside its loop.
	for id in ["composition","courtyard","region","far"]:
		var c: Array={"composition":[0,-270,.84],"courtyard":[-535,-227.5,2.4],"region":[-600,800,.105],"far":[-500000,100000,.00014]}[id]
		model.camera_x=model.view.world_origin[0]+c[0];model.camera_y=model.view.world_origin[1]+c[1];model.set_zoom(c[2])
		for i in 240:
			if mode=="old":session.cache.tick()
			else:adapter.update(c[0],c[1],c[2])
			canvas.queue_redraw();await tree.process_frame
		await RenderingServer.frame_post_draw;var image=tree.root.get_texture().get_image();image.save_png(output.get_base_dir()+"/ab_"+id+".png")
		if image.get_size()!=Vector2i(1920,1080):failures.append("not FHD "+id)
		captured[id]="ab_"+id+".png"
	if mode!="old":adapter.dispose()
	boot.remove_child(canvas);canvas.queue_free();await tree.process_frame;await tree.process_frame
	if mode!="old":
		for i in 900:
			adapter.service.tick()
			if adapter.service.manager.accounting().inflight==0:break
			await tree.process_frame
	return {"checks":4,"failures":failures,"mode":mode,"seconds":seconds,"actual_viewport":[1920,1080],"captures":captured,"unchanged_canvas":"res://review/canvas.gd","single_original_controller":session.army.get_instance_id(),"scope":"matched original-v01 painter, geometry and raw art; original legacy cache/full tree plan vs E3 resources/E2 query compatibility facade. Target C1 timings are separate."}
