extends RefCounted
const Adapter=preload("res://v02/v2/adapter.gd")
var checks:=0
var failures: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func run() -> Dictionary:
	var session=Engine.get_main_loop().root.get_node("Session");var army: RefCounted=session.army;var facade: RefCounted=session.state;var adapter=Adapter.new()
	var before: String=army.digest(army.context.state.to_dictionary());var layout_hash: String=army.digest(facade.layout);var authored: String=army.digest(facade.authoring)
	var a: Dictionary=adapter.project(army,facade)
	check(army.digest(army.context.state.to_dictionary())==before,"presentation read cannot mutate authority")
	check(facade._local.is_empty(),"facade delegates to sole existing authority")
	check(a.records[0].position_m==[-567.5,-227.5] and a.records[1].position_m==[-507.5,-227.5],"original frozen slot anchors")
	check(a.records[0].asset_id.is_empty() and a.records[1].asset_id=="barracks","empty storage and existing garrison")
	check(not facade.set_damage(Adapter.STORAGE,2).ok,"empty building damage rejected")
	var q: Dictionary=army.preview_construction(Adapter.STORAGE,"warehouse");check(q.ok,"existing quote accepted")
	check(army.commit_construction(q.token).ok,"existing dispatcher commits real construction")
	check(army.economy().cash==120 and army.economy().timber==60,"existing account and material effects")
	var identity: String=army.projection().slot_occupancy[Adapter.STORAGE].building_id
	check(adapter.project(army,facade).records[0].construction_state=="building","pending construction not a finished sprite")
	check(not army.commit_construction(q.token).ok,"construction quote single use")
	check(army.set_paused(false).ok,"resume original clock")
	for day in 3:check(army.advance_step().ok,"existing daily construction step "+str(day))
	army.set_paused(true);var built: Dictionary=adapter.project(army,facade)
	check(built.records[0].asset_id=="warehouse" and built.records[0].construction_state=="built","paid contract completes into intact asset")
	var economics: String=army.digest(army.economy());var contract: String=army.digest(army.construction_for(Adapter.STORAGE))
	check(facade.set_damage(Adapter.STORAGE,2).ok and facade.set_damage("wall_east",2).ok,"existing damage commits")
	var damage: Dictionary=adapter.project(army,facade)
	check(damage.records[0].asset_id=="warehouse_damaged" and damage.wall_asset=="wall_damaged","real damage variants selected")
	check(damage.records[0].position_m==built.records[0].position_m and damage.records[0].building_id==identity,"damage preserves anchor and building ID")
	check(facade.set_damage(Adapter.STORAGE,0).ok and facade.set_damage("wall_east",0).ok,"existing repair state commits")
	check(adapter.project(army,facade).records[0].asset_id=="warehouse","repair restores original asset")
	check(army.digest(army.economy())==economics and army.digest(army.construction_for(Adapter.STORAGE))==contract,"repair changes neither contract nor paid resources")
	check(facade.set_growth(3).ok and facade.set_growth(1).ok and army.projection().slot_occupancy[Adapter.STORAGE].building_id==identity,"growth preserves completed building")
	check(army.digest(facade.layout)==layout_hash and army.digest(facade.authoring)==authored,"all actions preserve eight slots and authored content")
	return {"checks":checks,"failures":failures,"building_id":identity,"economy":army.economy(),"authority":"original final/controller + bound settlement facade"}
