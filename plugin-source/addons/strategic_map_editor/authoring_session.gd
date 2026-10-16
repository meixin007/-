@tool
extends RefCounted
## Unapplied UI input belongs to recovery, never map or campaign authority.
const FIELDS := ["selected_name","selected_note","domain_id","selected_rule","selected_width","selected_scale","selected_gate","gate_open","secret_route","selected_art","art_density","art_seed","appearance_x","appearance_y","label_x","label_y","label_size","width_factor","appearance_visible","label_visible","art_instance_asset","art_instance_scale","art_instance_opacity","art_instance_flip","art_instance_plane","art_instance_group","art_instance_anchor","site_name","site_domain","site_x","site_y","art_group_toggle","curve_width_spin","placement_depth","placement_width","placement_height","placement_grounding","placement_overlap"]
const WATER_FIELDS := ["water_width_spin","water_radius_spin","water_connect_toggle","water_whole_toggle","water_start_style","water_end_style","faction_name","faction_color"]
const ARRAYS := ["draft","visual_curve_points","visual_curve_widths","art_erase_ids"]
const VALUES := ["tool","visual_curve_feature_id","visual_curve_kind","visual_curve_style","visual_curve_default_width","visual_curve_active_index","brush_asset","brush_scale"]
static func validate(state: Variant) -> String:
	if not state is Dictionary or state.get("version") != 1: return "未应用输入恢复记录版本无效。"
	var recent: Variant=state.get("recent_art_assets",[])
	if not recent is Array or recent.size()>12: return "最近素材恢复记录无效。"
	for key in recent:
		if not key is String or key.length()>128: return "最近素材恢复记录无效。"
	if not state.get("fields") is Dictionary or not state.get("canvas") is Dictionary: return "未应用输入恢复记录损坏。"
	if not state.get("selected") is String or not state.get("selected_art") is String: return "恢复记录对象标识无效。"
	for key in ["zoom"]:
		if not (state.get(key) is float or state.get(key) is int) or not is_finite(float(state[key])): return "恢复视图数值无效。"
	if not _point(state.get("pan")): return "恢复视图坐标无效。"
	for key in ARRAYS:
		if not state.canvas.get(key) is Array or state.canvas[key].size() > 8192: return "恢复画布输入无效。"
	for key in ["draft","visual_curve_points"]:
		for p in state.canvas[key]:
			if not _point(p): return "恢复表现线坐标无效。"
	for n in state.canvas.visual_curve_widths:
		if not (n is float or n is int) or not is_finite(float(n)): return "恢复水面宽度无效。"
	if state.canvas.get("visual_curve_kind") == "ribbon" and state.canvas.visual_curve_widths.size() != state.canvas.visual_curve_points.size():
		return "恢复水面宽度与控制点数量不一致。"
	for id in state.canvas.art_erase_ids:
		if not id is String: return "恢复擦除对象无效。"
	for key in VALUES:
		if key in ["visual_curve_default_width","visual_curve_active_index","brush_scale"]:
			if not (state.canvas.get(key) is float or state.canvas.get(key) is int) or not is_finite(float(state.canvas[key])): return "恢复画笔参数无效。"
		elif not state.canvas.get(key) is String: return "恢复工具参数无效。"
	if not state.get("art_stroke_points") is Array or state.art_stroke_points.size()>8192: return "恢复美术笔画无效。"
	for p in state.art_stroke_points:
		if not _point(p): return "恢复美术笔画坐标无效。"
	return ""
static func _point(p: Variant) -> bool:
	return p is Array and p.size()==2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float) and is_finite(float(p[0])) and is_finite(float(p[1]))
static func capture(bench: Control) -> Dictionary:
	var c: Control = bench.canvas
	var result := {"version":1,"selected":bench.selected_id,"selected_art":bench.selected_art_id,"zoom":c.zoom,"pan":[c.pan.x,c.pan.y],"fields":{},"canvas":{},"art_stroke_points":[],"recent_art_assets":bench.recent_art_assets.duplicate()}
	for key in FIELDS + WATER_FIELDS:
		var field: Control = bench.get(key)
		if field is LineEdit: result.fields[key] = field.text
		elif field is SpinBox: result.fields[key] = field.value
		elif field is OptionButton: result.fields[key] = field.selected
		elif field is CheckBox: result.fields[key] = field.button_pressed
		elif field is ColorPickerButton: result.fields[key] = "#"+field.color.to_html(false)
	for key in ARRAYS: result.canvas[key] = c.get(key).duplicate(true)
	for key in VALUES: result.canvas[key] = c.get(key)
	for p in c.art_stroke_points: result.art_stroke_points.append([p.x,p.y])
	return result
static func restore(bench: Control, state: Dictionary) -> void:
	if not validate(state).is_empty(): return
	var c: Control = bench.canvas
	c.select_feature(str(state.get("selected","")))
	c.select_art_instance(str(state.get("selected_art","")))
	bench._refresh()
	if not state.fields.has("water_start_style"): bench.water_start_style.select(0)
	if not state.fields.has("water_end_style"): bench.water_end_style.select(0)
	for key in FIELDS + WATER_FIELDS:
		if not state.get("fields",{}).has(key): continue
		var field: Control = bench.get(key)
		var value: Variant = state.fields[key]
		if field is LineEdit and value is String: field.text = value
		elif field is SpinBox and (value is float or value is int): field.value = value
		elif field is OptionButton and (value is float or value is int) and value >= 0 and value < field.item_count: field.select(int(value))
		elif field is CheckBox and value is bool: field.button_pressed = value
		elif field is ColorPickerButton and value is String and Color.html_is_valid(value):field.color=Color.html(value)
	c.water_end_styles=[["auto","source","join","mouth"][bench.water_start_style.selected],["auto","source","join","mouth"][bench.water_end_style.selected]]
	c.set_tool(str(state.get("canvas",{}).get("tool","select")))
	for key in ARRAYS:
		if state.get("canvas",{}).get(key) is Array:
			if key == "art_erase_ids": c.art_erase_ids.assign(state.canvas[key])
			else: c.set(key,state.canvas[key].duplicate(true))
	for key in VALUES:
		if state.get("canvas",{}).has(key): c.set(key,state.canvas[key])
	bench.recent_art_assets=state.get("recent_art_assets",[]).duplicate()
	bench._choose_browser_asset(c.brush_asset,false)
	bench.brush_size.set_value_no_signal(c.brush_scale)
	c.art_stroke_points.clear()
	for p in state.get("art_stroke_points",[]):
		if p is Array and p.size() == 2: c.art_stroke_points.append(Vector2(p[0],p[1]))
	c.zoom = clampf(float(state.get("zoom",c.zoom)),0.002,3.0)
	var pan: Array = state.get("pan",[0,0])
	c.pan = Vector2(pan[0],pan[1])
	c.queue_redraw()
	bench._sync_tool_buttons()
	bench._mark_inspector_pending()
