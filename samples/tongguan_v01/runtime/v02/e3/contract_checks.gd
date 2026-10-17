extends RefCounted
const Manager=preload("res://v02/e3/residency_manager.gd")
const Coverage=preload("res://v02/e3/coverage_planner.gd")
var checks:=0
var failures: Array=[]
var observations: Array=[]
class FakeBackend extends RefCounted:
	var tasks: Dictionary={}
	var delayed:=false
	var bad:=false
	var stats: Dictionary={"requests":0,"gets":0,"premature_gets":0}
	func begin(key: String,_row: Dictionary) -> Dictionary:tasks[key]=not delayed;stats.requests+=1;return {"ok":true}
	func status(key: String,_row: Dictionary) -> int:return 3 if tasks[key] else 1
	func take(key: String,row: Dictionary) -> Dictionary:
		if not tasks[key]:stats.premature_gets+=1;return {"ok":false}
		tasks.erase(key);stats.gets+=1
		var image=Image.create(row.pixel_size[0],row.pixel_size[1],false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
		return {"ok":true,"texture":ImageTexture.create_from_image(image)}
	func validate(_texture: Texture2D,_row: Dictionary) -> Dictionary:return {"ok":not bad,"code":"injected_bad_pixels"}
class Fixture extends RefCounted:
	var textures: Dictionary={}
	var root_path:="res://fake"
	var manifest: Dictionary={"build_id":"A","compatibility":{"world_id":"test"}}
	var files: Dictionary={}
	var objects: Dictionary={}
	var assets: Dictionary={}
	var pages: Dictionary={}
	func _init() -> void:
		for i in 6:
			var file:="t%d.png.bin"%i
			files[file]={"path":file,"kind":"texture","resource_path":"t%d.png"%i,"sha256":str(i),"pixel_sha256":str(i),"pixel_size":[8,8]}
			pages[str(i)]={"id":str(i),"build_id":"A","texture_files":[file],"parent_id":"" if i==0 else "0","bounds_m":[i*512,0,512,512],"level":0 if i==0 else 1}
		pages["alias"]=pages["1"].duplicate(true);pages.alias.id="alias"
func expect(value: bool,label: String) -> void:checks+=1;if not value:failures.append(label)
func run() -> Dictionary:
	var m=Manager.new();var fake=FakeBackend.new();m.backend=fake;var f=Fixture.new()
	expect(m.switch_package(f).ok,"admit metadata")
	expect(m.set_budget({"soft":768,"hard":1024,"decoded":512,"grace_usec":0}).ok,"freeze tiny arithmetic profile")
	expect(not m.set_budget({"soft":0}).ok and m.profile.soft==768,"invalid budget atomic")
	m.set_demands({"0":0,"1":2,"alias":2});m.tick(0)
	expect(m.accounting().inflight==2 and m.stats.requests==2,"two requests, shared texture merged")
	expect(m.page_states["1"]=="LOADING","loading state")
	m.tick(1)
	expect(m.ready("1") and m.ready("alias"),"consumers ready together")
	expect(m.accounting().resident==512 and m.accounting().consumers==3,"unique texture bytes and consumer references")
	expect(fake.stats.premature_gets==0,"get only loaded")
	m.set_demands({"alias":2});m.tick(2)
	expect(m.ready("alias") and m.accounting().consumers==1,"last shared consumer remains")
	m.set_demands({});m.tick(3)
	expect(m.accounting().total==0 and m.stats.drops==2,"last reference released")
	var alive:=0
	for row in m.ledger:
		if row.weak.get_ref()!=null:alive+=1
	expect(alive==0,"no manager/backend strong references")
	m.set_demands({"1":2});m.tick(4);m.tick(5)
	expect(m.stats.reloads==1 and m.ready("1"),"same content physically requested again")
	m.clear_demands();fake.delayed=true;m.set_demands({"2":2,"3":3,"4":3});m.tick(6)
	var epoch_before: int=m.epoch
	m.set_demands({"5":2});m.tick(7)
	expect(m.epoch==epoch_before,"camera motion does not increment epoch")
	expect(m.accounting().inflight==2 and m.stats.queued_cancelled>=1,"started tasks retained, queued tasks cancelled")
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(8)
	expect(m.stats.stale_drained==2,"late A tasks drained without adoption")
	fake.delayed=false
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(9)
	expect(m.ready("5"),"B eventually adopted")
	m.clear_demands();fake.delayed=true;m.set_demands({"1":2});m.tick(10);m.set_demands({});m.set_demands({"1":2})
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(11)
	expect(m.ready("1"),"A-B-A identical content current consumer can reclaim")
	m.clear_demands();m.set_demands({"2":2});m.tick(12)
	var other=Fixture.new();other.root_path="res://other";other.manifest.build_id="B"
	for page in other.pages.values():page.build_id="B"
	m.switch_package(other);m.set_demands({"0":0})
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(13)
	expect(m.epoch==epoch_before+1 and m.stats.stale_drained==3,"old package completion never attached")
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(14)
	var c=Coverage.new();c.bind(other)
	expect(c.resolve("1",m).selected=="0","missing child uses ready parent")
	other.pages["0"].build_id="old"
	expect(c.resolve("1",m).code=="page_build_mismatch","incompatible parent rejected")
	other.pages["0"].build_id="B"
	other.pages["0"].bounds_m=[-256,-256,512,512];c.bind(other)
	expect(c.intersecting(0,Rect2(32,32,64,64))==["0"],"unaligned parent covers every crossed lookup bucket")
	expect(c.intersecting(0,Rect2(-200,-200,400,400))==["0"],"coarse page lookup deduplicates bucket memberships")
	m.set_demands({"0":0,"1":2,"2":3});m.tick(15)
	expect(m.set_budget({"soft":256,"hard":256}).ok,"budget reduced below inflight reservations")
	var requests: int=m.stats.requests
	m.tick(16)
	expect(m.stats.requests==requests,"no admission during unavoidable reservation excess")
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(17)
	expect(m.accounting().total<=256 and m.ready("0"),"drain then preserve affordable base")
	m.clear_demands();fake.delayed=false
	for key in fake.tasks:fake.tasks[key]=true
	m.tick(18);fake.bad=true;m.set_demands({"1":2});m.tick(19);m.tick(20)
	expect(m.page_states["1"]=="FAILED" and not m.failures.is_empty(),"pixel failure explicitly reported")
	fake.bad=false;m.retry_failed();m.tick(20);m.tick(21)
	expect(m.ready("1"),"explicit failed retry succeeds")
	m.clear_demands()
	var p=Manager.new();p.backend=FakeBackend.new();p.switch_package(Fixture.new());p.set_budget({"soft":256,"hard":512,"decoded":512,"grace_usec":0})
	p.set_demands({"0":0,"1":3});p.tick(0);p.tick(1)
	expect(p.ready("0") and not p.ready("1") and p.stats.prefetch_denials>0,"prefetch stopped at soft budget before base coverage")
	p.clear_demands()
	var r=Manager.new();var delayed=FakeBackend.new();delayed.delayed=true;r.backend=delayed;var same=Fixture.new();r.switch_package(same);r.set_demands({"1":2});r.tick(0)
	r.switch_package(same);r.set_demands({"1":2})
	for key in delayed.tasks:delayed.tasks[key]=true
	r.tick(1)
	expect(r.ready("1") and r.stats.reclaimed==1,"current package explicitly reclaims matching content under new epoch")
	var pending=Coverage.new();pending.bind(same)
	expect(pending.resolve("2",r).code=="coverage_pending","not-ready parent produces explicit pending coverage")
	r.clear_demands()
	observations.append({"kind":"fake_control_only","stats":m.stats.duplicate(true),"events":m.events.duplicate(true),"accounting":m.accounting()})
	return {"checks":checks,"failures":failures,"observations":observations}
