extends RefCounted
## Read-only projection of the existing host. No authority or construction rules.
const STORAGE="tongguan.slot.rear_storage_01"
const MILITARY="tongguan.slot.rear_military_01"
func center(slot: Dictionary) -> Array:
	var p: Array=[0.0,0.0]
	for point in slot.polygon_local_m:p[0]+=point[0];p[1]+=point[1]
	return [p[0]/slot.polygon_local_m.size(),p[1]/slot.polygon_local_m.size()]
func project(army: RefCounted,facade: RefCounted) -> Dictionary:
	var state: Dictionary=army.projection();var records: Array=[]
	for id in [STORAGE,MILITARY]:
		var occupied: Dictionary=state.slot_occupancy[id];var damage: int=int(state.module_damage[id]);var asset:=""
		if occupied.status=="built":
			if id==STORAGE:asset="warehouse_damaged" if damage>0 else "warehouse"
			else:asset="barracks"
		records.append({"site_id":state.site_id,"slot_id":id,"building_id":occupied.building_id,"building_type":occupied.building_type,"construction_state":occupied.status,"damage_level":damage,"asset_id":asset,"position_m":center(facade.slot_by_id(id)),"order":army.construction_for(id)})
	return {"records":records,"wall_asset":"wall_damaged" if int(state.module_damage.wall_east)>0 else "wall_ns","wall_id":"wall_east","growth_stage":int(state.growth_stage),"day":int(army.context.state.current_day),"economy":army.economy(),"projection":state}
