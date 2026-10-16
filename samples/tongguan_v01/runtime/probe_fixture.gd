extends SceneTree
func _initialize():
	var context=load("res://scripts/core/game_runtime_context.gd").new()
	context.state=load("res://scripts/core/game_state.gd").new()
	context.scenario_data={"campaign_id":"tongguan_movement_validation_v1","scenario":{"start_phase":"tongguan_validation"},"resources":{},"characters":[],"factions":[]}
	context.state.initialize_from_data(context.scenario_data)
	print("MINIMAL_VALIDATION ",context.state.try_load_dictionary(context.state.to_dictionary()))
	print("MINIMAL_TX ",load("res://scripts/core/game_state_transaction.gd").new().execute(context,func(working):working.state.state_revision+=1;return {"ok":true}))
	context=null;quit()
