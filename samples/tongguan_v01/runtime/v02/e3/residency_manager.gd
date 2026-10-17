extends RefCounted
## Owns unique textures, reservations and draining tasks. Holds no gameplay state.
const Backend=preload("res://v02/e3/threaded_backend.gd")
var backend: RefCounted=Backend.new()
var profile: Dictionary={"id":"normal_256_320","soft":268435456,"hard":335544320,"decoded":67108864,"concurrency":2,"attach_usec":2000,"grace_usec":2000000}
var epoch:=0
var revision:=0
var package: RefCounted
var descriptors: Dictionary={}
var page_files: Dictionary={}
var page_states: Dictionary={}
var demands: Dictionary={}
var wanted: Dictionary={}
var entries: Dictionary={}
var events: Array=[]
var failures: Array=[]
var ledger: Array=[]
var frames: Array=[]
var record_full_history:=false
var on_evict: Callable
var _requests: Dictionary={}
var _serial:=0
var _clock:=0
var stats: Dictionary={"requests":0,"attaches":0,"drops":0,"reloads":0,"stale_drained":0,"reclaimed":0,"queued_cancelled":0,"peak_inflight":0,"max_attach_usec":0,"attach_overruns":0,"hard_denials":0,"prefetch_denials":0,"released_observed":0}
func event(kind: String,key: String,extra: Dictionary={}) -> void:
	var row: Dictionary={"event":kind,"key":key,"epoch":epoch,"frame":_serial,"usec":Time.get_ticks_usec()};row.merge(extra);events.append(row)
	if not record_full_history and events.size()>1024:events=events.slice(512)
func fail(code: String,detail: String="") -> Dictionary:return {"ok":false,"code":code,"detail":detail}
func set_budget(next: Dictionary) -> Dictionary:
	var values: Dictionary=profile.duplicate(true);values.merge(next,true)
	for field in ["soft","hard","decoded","concurrency","attach_usec","grace_usec"]:
		if not (values[field] is int or values[field] is float) or not is_finite(values[field]) or values[field]!=floor(values[field]) or values[field]<0:return fail("invalid_budget",field)
	if values.soft<=0 or values.hard<values.soft or values.decoded<=0 or values.concurrency<1 or values.concurrency>2 or values.attach_usec<1:return fail("invalid_budget")
	profile=values;event("budget_changed","",profile.duplicate());return {"ok":true}
func key_for(file: String) -> String:return str(descriptors[file].key) if descriptors.has(file) else ""
func switch_package(source: RefCounted) -> Dictionary:
	# Incoming reader was validated atomically by the shared E1 parser. No E1 textures are loaded.
	if not source.textures.is_empty():return fail("legacy_cache_not_empty")
	clear_demands();epoch+=1
	for key in entries.keys():
		if entries[key].state!="LOADING":drop(key,"package_switch")
	package=source;descriptors={};page_files={};page_states={};wanted={};demands={}
	for file in source.files:
		var row: Dictionary=source.files[file]
		if row.kind!="texture":continue
		var copy: Dictionary=row.duplicate(true);copy.source_path=source.root_path+"/"+file;copy.import_path=source.root_path+"/"+str(row.resource_path)
		copy.key=copy.import_path+"|"+row.sha256
		# RGBA8 conservative logical estimate; includes actual gutter, base-only import contract.
		copy.bytes=int(row.pixel_size[0])*int(row.pixel_size[1])*4;descriptors[file]=copy
	for id in source.pages:page_files[id]=source.pages[id].texture_files.duplicate();page_states[id]="UNLOADED"
	for id in source.objects:
		var object: Dictionary=source.objects[id]
		if object.record_type=="sprite":page_files["object:"+id]=[source.assets[object.asset_id].texture_file];page_states["object:"+id]="UNLOADED"
	revision+=1;event("package",source.manifest.build_id,{"world_id":source.manifest.compatibility.world_id});return {"ok":true}
func set_demands(next: Dictionary) -> Dictionary:
	for id in next:
		if not page_files.has(id) or int(next[id])<0 or int(next[id])>4:return fail("invalid_demand",id)
	# This serial is not an epoch. Current consumers can reclaim identical in-flight content.
	demands=next.duplicate();wanted={}
	for id in demands:
		for file in page_files[id]:
			var key:=key_for(file)
			if not wanted.has(key):wanted[key]={"row":descriptors[file],"consumers":{},"priority":int(demands[id]),"epoch":epoch}
			wanted[key].consumers[id]=true;wanted[key].priority=mini(wanted[key].priority,int(demands[id]))
	for key in entries.keys():
		var entry: Dictionary=entries[key]
		if wanted.has(key):entry.last_use=_clock
		elif entry.state=="QUEUED":stats.queued_cancelled+=1;event("queued_cancelled",key);entries.erase(key)
	for key in wanted:
		if not entries.has(key):entries[key]={"row":wanted[key].row,"state":"QUEUED","texture":null,"request_epoch":epoch,"last_use":_clock,"consumers":{},"weak":null}
	update_page_states();return {"ok":true}
func clear_demands() -> void:
	demands={};wanted={}
	for key in entries.keys():
		if entries[key].state!="LOADING":drop(key,"clear")
func retry_failed() -> void:
	for key in entries.keys():
		if entries[key].state=="FAILED":entries.erase(key)
	set_demands(demands)
func drop(key: String,reason: String) -> void:
	if not entries.has(key):return
	var entry: Dictionary=entries[key]
	if entry.state=="LOADING":return # Physical task must be drained, never forgotten.
	if entry.state=="RESIDENT":
		entry.state="EVICT_PENDING";event("state",key,{"state":"EVICT_PENDING"})
		if on_evict.is_valid():on_evict.call(key)
		var weak: WeakRef=weakref(entry.texture)
		var instance: int=entry.texture.get_instance_id()
		entry.texture=null;entry.consumers={};stats.drops+=1;revision+=1
		ledger.append({"key":key,"weak":weak,"instance_id":instance,"bytes":entry.row.bytes,"frame":_serial,"reason":reason})
		event("last_reference_drop",key,{"reason":reason,"bytes":entry.row.bytes})
	elif entry.state=="READY_CPU":
		var weak: WeakRef=weakref(entry.texture);entry.texture=null
		ledger.append({"key":key,"weak":weak,"bytes":entry.row.bytes,"frame":_serial,"reason":reason})
		event("completion_reference_drop",key,{"reason":reason})
	entries.erase(key);event("state",key,{"state":"UNLOADED"})
func accounting() -> Dictionary:
	var resident:=0;var reserve:=0;var decoded:=0;var inflight:=0;var ready:=0;var consumers:=0
	for key in entries:
		var e: Dictionary=entries[key]
		if e.state=="RESIDENT":resident+=int(e.row.bytes);consumers+=e.consumers.size()
		elif e.state in ["LOADING","READY_CPU","ATTACHING"]:
			reserve+=int(e.row.bytes);decoded+=int(e.row.bytes)
			if e.state=="LOADING":inflight+=1
			else:ready+=1
	var external_alive:=0
	for row in ledger:
		if row.weak.get_ref()!=null:external_alive+=int(row.bytes)
	return {"resident":resident,"reserved":reserve,"total":resident+reserve,"decoded_reserved":decoded,"inflight":inflight,"ready":ready,"resources":entries.size(),"consumers":consumers,"external_alive_bytes":external_alive}
func _priority(key: String) -> int:return int(wanted[key].priority) if wanted.has(key) else 4
func _trim() -> void:
	# Stop prefetch first, then unneeded pages, then lower-priority detail, retaining base if possible.
	var keys: Array=entries.keys()
	keys.sort_custom(func(a,b):
		if _priority(a)!=_priority(b):return _priority(a)>_priority(b)
		return entries[a].last_use<entries[b].last_use)
	for key in keys:
		var e: Dictionary=entries[key]
		if e.state not in ["RESIDENT","READY_CPU"]:continue
		var total: int=accounting().total
		var expired: bool=not wanted.has(key) and _clock-int(e.last_use)>=int(profile.grace_usec)
		if not expired and _priority(key)==0 and int(e.row.bytes)<=int(profile.hard) and int(accounting().resident)<=int(profile.hard):continue
		if expired or total>int(profile.hard) or (total>int(profile.soft) and _priority(key)>0):drop(key,"expired" if expired else "budget")
func _make_room(bytes: int,priority: int) -> bool:
	if bytes>int(profile.hard):return false
	var cap: int=int(profile.soft) if priority>=1 else int(profile.hard)
	if int(accounting().total)+bytes<=cap:return true
	var keys: Array=entries.keys()
	keys.sort_custom(func(a,b):return entries[a].last_use<entries[b].last_use)
	for key in keys:
		if entries[key].state not in ["RESIDENT","READY_CPU"]:continue
		if wanted.has(key) and _priority(key)<=priority:continue
		drop(key,"admission_pressure")
		if int(accounting().total)+bytes<=cap:return true
	return false
func tick(now_usec: int=-1) -> void:
	_serial+=1;_clock=Time.get_ticks_usec() if now_usec<0 else now_usec
	for i in range(ledger.size()-1,-1,-1):
		var row: Dictionary=ledger[i]
		if row.weak.get_ref()==null:
			stats.released_observed+=1;event("released_observed",row.key,{"instance_id":row.get("instance_id"),"drop_frame":row.frame,"bytes":row.bytes});ledger.remove_at(i)
	_trim()
	# Poll once per frame. Get only after LOADED, including logically cancelled requests.
	var start:=Time.get_ticks_usec();var operations:=0
	for key in entries.keys():
		var e: Dictionary=entries[key]
		if e.state!="LOADING":continue
		var status: int=backend.status(key,e.row)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
		if status!=ResourceLoader.THREAD_LOAD_LOADED:
			e.state="FAILED";var error: Dictionary=fail("thread_load_failed",e.row.path);failures.append(error);event("failed",key,error);continue
		if operations>0 and Time.get_ticks_usec()-start>=int(profile.attach_usec):break
		var taken: Dictionary=backend.take(key,e.row)
		operations+=1
		if not taken.ok:e.state="FAILED";failures.append(taken);event("failed",key,taken);continue
		e.texture=taken.texture;taken.clear();e.state="READY_CPU";event("state",key,{"state":"READY_CPU"})
		if not wanted.has(key):stats.stale_drained+=1;drop(key,"stale_completion");continue
		if e.request_epoch!=epoch:stats.reclaimed+=1;event("reclaimed_current_content",key,{"request_epoch":e.request_epoch})
	# Validation + adoption share the measured, non-preemptible 2ms budget.
	var order: Array=entries.keys();order.sort_custom(func(a,b):return _priority(a)<_priority(b))
	for key in order:
		if not entries.has(key):continue
		var e: Dictionary=entries[key]
		if e.state!="READY_CPU":continue
		if not wanted.has(key):drop(key,"no_current_consumer");continue
		if int(accounting().total)>int(profile.hard):drop(key,"reduced_hard_budget");continue
		if operations>0 and Time.get_ticks_usec()-start>=int(profile.attach_usec):break
		e.state="ATTACHING";event("state",key,{"state":"ATTACHING"})
		var valid: Dictionary=backend.validate(e.texture,e.row);operations+=1
		if not valid.ok:
			e.texture=null;e.state="FAILED";failures.append(valid);event("failed",key,valid);continue
		e.state="RESIDENT";e.consumers=wanted[key].consumers.duplicate();e.last_use=_clock;stats.attaches+=1;revision+=1
		event("attach",key,{"request_epoch":e.request_epoch,"consumer_epoch":epoch,"consumers":e.consumers.keys(),"bytes":e.row.bytes})
	var elapsed:=Time.get_ticks_usec()-start
	if operations>0:
		stats.max_attach_usec=maxi(stats.max_attach_usec,elapsed)
		if elapsed>int(profile.attach_usec):stats.attach_overruns+=1
	_trim()
	order=wanted.keys();order.sort_custom(func(a,b):return _priority(a)<_priority(b))
	for key in order:
		if not entries.has(key):entries[key]={"row":wanted[key].row,"state":"QUEUED","texture":null,"request_epoch":epoch,"last_use":_clock,"consumers":{},"weak":null}
		var e: Dictionary=entries[key]
		if e.state=="RESIDENT":e.consumers=wanted[key].consumers.duplicate();continue
		if e.state!="QUEUED":continue
		var counts: Dictionary=accounting()
		if counts.inflight>=int(profile.concurrency):break
		if counts.decoded_reserved+int(e.row.bytes)>int(profile.decoded):continue
		if not _make_room(int(e.row.bytes),_priority(key)):
			if _priority(key)>=3:stats.prefetch_denials+=1
			else:stats.hard_denials+=1
			continue
		var result: Dictionary=backend.begin(key,e.row)
		if not result.ok:e.state="FAILED";failures.append(result);event("failed",key,result);continue
		e.state="LOADING";e.request_epoch=epoch;stats.requests+=1
		_requests[key]=int(_requests.get(key,0))+1
		if _requests[key]>1:stats.reloads+=1;event("reload",key)
		event("request",key,{"request_epoch":epoch,"bytes":e.row.bytes,"consumers":wanted[key].consumers.keys()})
		stats.peak_inflight=maxi(stats.peak_inflight,int(accounting().inflight))
	update_page_states()
	var frame: Dictionary=accounting();frame.merge({"frame":_serial,"epoch":epoch,"soft":profile.soft,"hard":profile.hard,"attach_usec":elapsed if operations>0 else 0,"attach_operations":operations,"pressure_over_hard":int(frame.total)>int(profile.hard)})
	frames.append(frame)
	if not record_full_history and frames.size()>256:frames=frames.slice(128)
func update_page_states() -> void:
	for id in page_states:
		var state:="UNLOADED"
		if demands.has(id) or ready(id):
			state="RESIDENT"
			for file in page_files[id]:
				var key:=key_for(file);var s: String=str(entries[key].state) if entries.has(key) else "QUEUED"
				if s=="FAILED":state="FAILED";break
				if s!="RESIDENT":state=s
		if page_states[id]!=state:event("page_state",id,{"state":state});page_states[id]=state
func ready(id: String) -> bool:
	if not page_files.has(id):return false
	if package.pages.has(id) and package.pages[id].build_id!=package.manifest.build_id:return false
	for file in page_files[id]:
		var key:=key_for(file)
		if not entries.has(key) or entries[key].state!="RESIDENT":return false
	return true
func texture(file: String) -> Texture2D:
	var key:=key_for(file)
	return entries[key].texture if entries.has(key) and entries[key].state=="RESIDENT" else null
func telemetry() -> Dictionary:return {"epoch":epoch,"revision":revision,"profile":profile.duplicate(true),"stats":stats.duplicate(true),"accounting":accounting(),"states":page_states.duplicate(),"failures":failures.duplicate(true)}
