extends RefCounted

class_name MapConversationRouter

const CONTEXT_KEY_BY_KIND := {
	"node": "selected_node_id",
	"route": "selected_route_id",
	"report": "selected_report_id",
	"task": "selected_task_id"
}

func get_recommended_npcs(state, data: Dictionary, context_kind: String, context_id: String) -> Array:
	if state == null:
		return []
	var route := _find_route(data, context_kind, context_id)
	if route.is_empty():
		return []
	var topic_id := _resolve_topic_id(data, "")
	var result: Array = []
	for npc_id in route.get("recommended_npc_ids", []):
		var resolved_npc_id := str(npc_id)
		result.append({
			"npc_id": resolved_npc_id,
			"topic_id": _resolve_topic_id(data, resolved_npc_id),
			"source_context": {
				"context_kind": context_kind,
				"context_id": context_id
			},
			"summary": str(route.get("summary", "")),
			"suggested_intents": route.get("suggested_intents", []).duplicate(true)
		})
		if topic_id == "":
			topic_id = _resolve_topic_id(data, resolved_npc_id)
	return result.duplicate(true)

func build_audience_entry(state, data: Dictionary, context_kind: String, context_id: String, npc_id: String) -> Dictionary:
	if state == null:
		return _fail("missing state")
	var route := _find_route(data, context_kind, context_id)
	if route.is_empty():
		return _fail("unknown map conversation context: " + context_kind + "/" + context_id)
	if not route.get("recommended_npc_ids", []).has(npc_id):
		return _fail("npc is not recommended for context: " + npc_id)
	var topic_id := _resolve_topic_id(data, npc_id)
	if topic_id == "":
		return _fail("missing topic for npc: " + npc_id)

	var context_key := str(CONTEXT_KEY_BY_KIND.get(context_kind, ""))
	if context_key != "":
		state.court_workbench_state[context_key] = context_id
	state.court_workbench_state["selected_character_id"] = npc_id
	state.court_workbench_state["right_context_kind"] = "map_conversation"
	state.court_workbench_state["right_context_payload"] = {
		"context_kind": context_kind,
		"context_id": context_id,
		"npc_id": npc_id,
		"topic_id": topic_id
	}

	return {
		"ok": true,
		"npc_id": npc_id,
		"topic_id": topic_id,
		"source_context": {
			"context_kind": context_kind,
			"context_id": context_id
		},
		"summary": str(route.get("summary", "")),
		"suggested_intents": route.get("suggested_intents", []).duplicate(true)
	}

func _find_route(data: Dictionary, context_kind: String, context_id: String) -> Dictionary:
	for route in data.get("map_conversation_routes", []):
		var route_data: Dictionary = route
		match context_kind:
			"node":
				if str(route_data.get("node_id", "")) == context_id:
					return route_data.duplicate(true)
			"route":
				if route_data.get("route_ids", []).has(context_id):
					return route_data.duplicate(true)
			"report":
				if str(route_data.get("report_id", "")) == context_id or route_data.get("report_ids", []).has(context_id):
					return route_data.duplicate(true)
			"task":
				if str(route_data.get("task_id", "")) == context_id or route_data.get("task_ids", []).has(context_id):
					return route_data.duplicate(true)
	return {}

func _resolve_topic_id(data: Dictionary, npc_id: String) -> String:
	for topic in data.get("dialogue_topics", []):
		var topic_data: Dictionary = topic
		if npc_id == "" or str(topic_data.get("npc_id", "")) == npc_id:
			return str(topic_data.get("topic_id", ""))
	return ""

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
