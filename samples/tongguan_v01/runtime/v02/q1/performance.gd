extends Node
## Records every frame interval, including deferred submission/upload/IO spikes.
var output: String
var app: Control
var file: FileAccess
var raw: FileAccess
var started:=0
var last_frame:=0
var sample_start:=0
var duration:=60.0
var warmup:=10.0
var preset:="target"
var complete:=false
var frame:=0
var buffer:=""
var next_flush:=0
var previous: Array=[]
var events: Array=[]
var first_low: Variant=null
var first_details: Variant=null
var first_draw: Variant=null
var errors: Array=[]
var _viewport_verified:=false
var _recording:=false
var _last_memory_second:=-1
var _startup_captured:=false
var keys: Array=[[0,0,-270,.84],[8,-535,-227.5,2.4],[16,-60,-600,1.4],[24,600,300,.42],[32,-600,800,.105],[40,0,0,.025],[48,-500000,100000,.00014],[56,-600,800,.105],[60,0,-270,.84]]
const HEADER="frame,process_start_usec,interval_ms,phase,track_seconds,x_m,y_m,zoom,semantic_lod,terrain_level,app_usec,view_usec,attach_usec,renderer_usec,resident_bytes,reserved_bytes,decoded_bytes,inflight,resources,external_alive_bytes,objects,engine_resources,engine_texture_bytes,engine_buffer_bytes,world_records,candidates,visible,submitted,sorts,snapshot_reads,requests,attaches,drops,reloads,hard_denials,attach_overruns,combined_overruns\n"
func _ready() -> void:
	started=Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):duration=float(arg.substr(10))
		if arg.begins_with("--warmup="):warmup=float(arg.substr(9))
		if arg.begins_with("--preset="):preset=arg.substr(9)
	if duration<=0 or warmup<0 or duration>600:printerr("Q1 invalid timing");get_tree().quit(1);return
	app=load("res://v02/q1/app.gd").new();add_child(app);app.set_process(false)
	app.service.prefetch=true
	file=FileAccess.open(output.get_base_dir()+"/frames.csv",FileAccess.WRITE);file.store_string(HEADER)
	raw=FileAccess.open(output.get_base_dir()+"/resource_events.jsonl",FileAccess.WRITE)
	RenderingServer.frame_post_draw.connect(after_draw)
	last_frame=Time.get_ticks_usec();sample_start=last_frame+int(warmup*1000000);next_flush=last_frame+1000000
	events.append({"event":"app_ready","usec":last_frame,"duration_sec":duration,"warmup_sec":warmup,"preset":preset})
func trajectory(seconds: float) -> Array:
	var t:=fposmod(seconds,60.0)
	for i in range(keys.size()-1):
		var a: Array=keys[i];var b: Array=keys[i+1]
		if t>=a[0] and t<=b[0]:
			var weight: float=(t-a[0])/(b[0]-a[0]);weight=weight*weight*(3-2*weight)
			return [lerpf(a[1],b[1],weight),lerpf(a[2],b[2],weight),exp(lerpf(log(a[3]),log(b[3]),weight))]
	return [0,-270,.84]
func _process(delta: float) -> void:
	if complete or app==null:return
	var now:=Time.get_ticks_usec();var interval_usec:=now-last_frame;var elapsed: float=(now-sample_start)/1000000.0
	if not previous.is_empty():
		var line: Array=[frame,last_frame,(now-last_frame)/1000.0];line.append_array(previous)
		var fields=PackedStringArray()
		for item in line:fields.append(str(item))
		buffer+=",".join(fields)+"\n";frame+=1
	last_frame=now
	if elapsed>=duration:complete=true;call_deferred("finish");return
	var phase:="steady" if elapsed>=0 else "warmup"
	if _viewport_verified and not _recording and elapsed>=0:_recording=true;events.append({"event":"steady_begin","usec":now})
	var camera: Array=trajectory(maxf(0,elapsed))
	var view_start:=Time.get_ticks_usec();app.x=camera[0];app.y=camera[1];app.zoom=camera[2];app.refresh();var view_usec:=Time.get_ticks_usec()-view_start
	var app_start:=Time.get_ticks_usec();app._process(delta);var app_usec:=Time.get_ticks_usec()-app_start
	var manager=app.service.manager;var a: Dictionary=manager.accounting();var m: Dictionary=manager.stats
	var attach_usec: int=int(manager.frames.back().attach_usec) if not manager.frames.is_empty() else 0
	var renderer_usec: int=int(manager.frames.back().get("renderer_plan_usec",0)) if not manager.frames.is_empty() else 0
	previous=[phase,maxf(0,elapsed),app.x,app.y,app.zoom,app.service.semantic_lod,app.service.coverage.selected_level,app_usec,view_usec,attach_usec,renderer_usec,a.resident,a.reserved,a.decoded_reserved,a.inflight,a.resources,a.external_alive_bytes,Performance.get_monitor(Performance.OBJECT_COUNT),Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),app.service.planner.index.object_count(),app.service.pending_plan.get("candidate_ids",[]).size(),app.service.pending_plan.get("visible_ids",[]).size(),app.renderer.submissions.size(),app.service.planner.stats.sort_calls,app.service.planner.stats.snapshot_reads,m.requests,m.attaches,m.drops,m.reloads,m.hard_denials,m.attach_overruns,app.renderer.stats.combined_budget_overruns]
	if first_low==null:
		for id in app.service.coverage.roots:
			if manager.ready(id):first_low=now;events.append({"event":"first_low_ready","usec":now});break
	if first_details==null and app.service.detail_ready:first_details=now;events.append({"event":"first_details_ready","usec":now})
	if now>=next_flush:
		var io_start:=Time.get_ticks_usec();file.store_string(buffer);buffer="";file.flush()
		for row in manager.events:raw.store_string(JSON.stringify(row)+"\n")
		manager.events.clear();raw.flush();next_flush=now+1000000
		events.append({"event":"recorder_flush","usec":io_start,"duration_usec":Time.get_ticks_usec()-io_start})
		var progress=FileAccess.open(output.get_base_dir()+"/progress.json",FileAccess.WRITE);progress.store_string(JSON.stringify({"phase":phase,"seconds":maxf(0,elapsed),"duration":duration,"frames":frame,"resident":a.resident,"requests":m.requests,"last_frame_ms":interval_usec/1000.0}));progress.close()
func after_draw() -> void:
	if app==null:return
	if not _viewport_verified:
		# Size readback is outside steady sampling, with no screenshot in the loop.
		var size: Vector2i=get_tree().root.get_texture().get_size()
		_viewport_verified=size==Vector2i(1920,1080)
		if not _viewport_verified:errors.append("actual viewport is "+str(size))
	if first_draw==null and first_low!=null:first_draw=Time.get_ticks_usec();events.append({"event":"first_low_frame_post_draw_upper_bound","usec":first_draw})
	if not _startup_captured and first_details!=null and Time.get_ticks_usec()<sample_start-1000000:
		_startup_captured=true
		var image=get_tree().root.get_texture().get_image()
		image.save_png(output.get_base_dir()+"/startup_outside_sample.png")
		events.append({"event":"startup_capture_outside_sampling","usec":Time.get_ticks_usec(),"actual_size":[image.get_width(),image.get_height()]})
func finish() -> void:
	set_process(false);file.store_string(buffer);file.flush();file.close()
	await RenderingServer.frame_post_draw
	var final_image=get_tree().root.get_texture().get_image();final_image.save_png(output.get_base_dir()+"/after_sampling.png")
	for row in app.service.manager.events:raw.store_string(JSON.stringify(row)+"\n")
	app.service.manager.events.clear();raw.flush();raw.close()
	var final: Dictionary=app.service.telemetry();var state: Dictionary=app.army().snapshot()
	if not app.errors.is_empty():errors.append_array(app.errors)
	if not app.renderer.errors.is_empty():errors.append_array(app.renderer.errors)
	if not app.service.manager.failures.is_empty():errors.append_array(app.service.manager.failures)
	app.service.dispose()
	for i in 1200:
		app.service.tick()
		if app.service.manager.accounting().inflight==0:break
		await get_tree().process_frame
	await get_tree().process_frame;await get_tree().process_frame
	var release: Dictionary=app.service.manager.accounting()
	if release.total!=0 or release.external_alive_bytes!=0 or release.inflight!=0:errors.append("end-of-run references not released")
	var report={"checks":4,"failures":errors,"duration_sec":duration,"warmup_sec":warmup,"frames_written":frame,"actual_viewport":[get_tree().root.get_texture().get_width(),get_tree().root.get_texture().get_height()],"window_size":DisplayServer.window_get_size(),"content_scale":get_tree().root.content_scale_size,"display_scale":DisplayServer.screen_get_scale(),"screen_dpi":DisplayServer.screen_get_dpi(),"engine":Engine.get_version_info(),"rendering_method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"adapter_vendor":RenderingServer.get_video_adapter_vendor(),"engine_started_to_app_ready_usec":started,"first_low_ready_usec":first_low,"first_low_frame_post_draw_upper_bound_usec":first_draw,"first_details_ready_usec":first_details,"gpu_first_presented_usec":null,"first_presented_note":"not observable from these APIs; frame_post_draw is an engine-side upper-bound event, not a GPU presentation timestamp","startup":events,"telemetry":final,"release_after_run":release,"authority_final":state,"settings":{"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"low_processor_usage_mode":OS.low_processor_usage_mode},"trajectory":keys,"no_screenshot_readback_in_sample_loop":true,"raw_frame_policy":"every interval retained; no outlier trimming"}
	var result=FileAccess.open(output,FileAccess.WRITE);result.store_string(JSON.stringify(report,"\t"));result.close();print("Q1_PERF_COMPLETE ",frame," frames ",duration," seconds");get_tree().quit(0 if errors.is_empty() else 1)
