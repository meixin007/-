@tool
extends "dialog_shell.gd"
const Doc = preload("document.gd")
const Audit = preload("map_audit.gd")
const Samples = preload("production_samples.gd")
const Registration = preload("reference_registration.gd")
var bench
var page := 0
var body: VBoxContainer
var feedback: Label
var audit_running := false
var last_results: Array = []
var last_fingerprint := ""
func show_tools(host: Control, selected_page: int = 0) -> void:
	bench=host
	page=selected_page
	title="地图制作工具"
	cancel_button_text="关闭"
	_rebuild()
	popup_centered(Vector2i(760,620))
	get_ok_button().hide()
func _rebuild() -> void:
	clear_content()
	var tabs := OptionButton.new()
	for caption in ["多选与几何","参考图校准","区域与保护","地图体检与场景","批量制作入口"]: tabs.add_item(caption)
	tabs.select(page)
	tabs.item_selected.connect(func(i): page=i; _rebuild())
	content.add_child(tabs)
	body=VBoxContainer.new()
	content.add_child(body)
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(feedback)
	match page:
		0: _geometry_page()
		1: _calibration_page()
		2: _regions_page()
		3: _audit_page()
		4: _batch_page()
func _label(text: String) -> Label:
	var label := Label.new()
	label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text=text; button.pressed.connect(action)
	body.add_child(button)
	return button
func _text(caption: String, value: String = "") -> LineEdit:
	_label(caption)
	var line := LineEdit.new()
	line.text=value
	body.add_child(line)
	return line
func _spin(parent: Node, value: float = 0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value=-65536; spin.max_value=65536; spin.step=0.01; spin.value=value
	spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin
func _result(ok: bool, error: String = "") -> void:
	feedback.text="已应用，可撤销。" if ok else (error if not error.is_empty() else "未修改：目标受保护、图层锁定、内容未变化或几何无效。")
func _geometry_page() -> void:
	var ids: Array = bench.canvas.selection_ids.duplicate()
	_label("先在画布 Ctrl+点击，或在对象列表 Ctrl / Shift 多选，再打开此页。已选 %d 项。" % ids.size())
	var names: Array[String] = []
	for id in ids: names.append(bench.doc.find_feature(id).name)
	_label("、".join(names))
	_label("整组平移（图面单位 X / Y）")
	var row := HBoxContainer.new(); body.add_child(row)
	var x := _spin(row); var y := _spin(row)
	_button("平移全部所选",func(): _result(bench.doc.translate_features(ids,Vector2(x.value,y.value))))
	var group := _text("组名 / 组合 ID")
	_button("将所选设为同一组",func():
		var ops: Array = []
		for id in ids:
			if bench.doc.find_feature(id).group_id != group.text.strip_edges(): ops.append({"op":"update","id":id,"values":{"group_id":group.text.strip_edges()}})
		var response: Dictionary = bench.doc.apply_batch({"batch_id":"group_"+str(Time.get_ticks_usec()),"expected_fingerprint":bench.doc.fingerprint(),"operations":ops})
		_result(response.ok,response.get("error","")))
	var groups := OptionButton.new(); body.add_child(groups)
	var known: Array = []
	for f in bench.doc.data.features:
		if not f.group_id.is_empty() and not f.group_id in known: known.append(f.group_id); groups.add_item(f.group_id)
	_button("选择该组全部对象",func():
		if groups.selected < 0: return
		var members: Array = []
		for f in bench.doc.data.features:
			if f.group_id == groups.get_item_text(groups.selected): members.append(f.id)
		bench.canvas.select_many(members); _rebuild())
	if ids.size() == 2:
		_label("几何操作：第一项“%s”保留，第二项“%s”作为工具形状并移除。结果可整体撤销。" % [names[0],names[1]])
		for pair in [["union","合并两个同类区域"],["subtract","从第一项扣除第二项（可挖洞）"],["intersect","只保留两者交集"]]:
			_button(pair[1],func():
				var response: Dictionary = bench.doc.boolean_features(ids[0],ids[1],pair[0])
				if response.ok: bench.canvas.select_many(response.ids); _rebuild()
				_result(response.ok,response.get("error","")))
	else: _label("合并 / 扣除 / 交集需要恰好选中两个区域；支持已有孔洞。合计最多 512 个顶点，精度或预算不足时保留原稿。")
	if ids.size()==1:
		var f: Dictionary=bench.doc.find_feature(ids[0])
		if f.kind in Doc.POLYGONS:
			_label("孔洞顶点为蓝色，可在选择工具下直接拖动；添加 / 删除顶点也支持孔洞边线。")
			_button("在所选区域内画孔洞",func(): bench.canvas.set_tool("hole"); hide())
			if not f.holes.is_empty():
				var holes:=OptionButton.new(); body.add_child(holes)
				for i in range(f.holes.size()): holes.add_item("孔洞 %d（%d 点）" % [i+1,f.holes[i].size()])
				_button("定位所选孔洞",func():
					var points:=Doc.packed(bench.doc.find_feature(ids[0]).holes[holes.selected])
					var bounds:=Rect2(points[0],Vector2.ZERO)
					for p in points: bounds=bounds.expand(p)
					bounds=bounds.grow(30); focus_rect([bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y])
					bench.canvas.active_ring=holes.selected; bench.canvas.set_tool("select"); hide())
				_button("填回所选孔洞（可撤销）",func():
					var ok: bool=bench.doc.remove_hole(ids[0],holes.selected)
					_rebuild(); _result(ok))
	_button("保护所选对象",func(): _result(bench.doc.protect_features(ids,true)))
	_button("解除所选对象保护",func(): _result(bench.doc.protect_features(ids,false)))
func _calibration_page() -> void:
	var id: String = bench.canvas.active_reference
	var selector := OptionButton.new(); body.add_child(selector)
	for ref in bench.doc.references():
		selector.add_item(ref.path.get_file() if not ref.path.is_empty() else "主参考图（空）")
		selector.set_item_metadata(selector.item_count-1,ref.get("id","primary"))
		if ref.get("id","primary") == id: selector.select(selector.item_count-1)
	selector.item_selected.connect(func(i): bench.canvas.active_reference=selector.get_item_metadata(i); _rebuild())
	var ref: Dictionary = bench.doc.get_reference(id)
	if ref.path.is_empty(): _label("先导入参考图。"); return
	if ref.locked:
		_label("此参考图已锁定。先在参考图设置中解锁，再使用控制点校准。")
		_button("打开参考图设置",func(): hide(); bench.settings_panel.show_reference(bench.doc,id))
		return
	var img := Image.load_from_file(bench.doc.resolve_reference_path(id))
	if img == null or img.is_empty(): _label("参考图缺失，请重新导入。"); return
	var dimensions := img.get_size()
	_label("输入三对控制点：原图像素 X / Y → 当前地图图面 X / Y。图片原始尺寸 %d × %d。保持比例拟合，不做透视或经纬度投影转换。" % [dimensions.x,dimensions.y])
	var controls: Array = []
	var initial := [[0,0],[dimensions.x,0],[0,dimensions.y]]
	var previous: Dictionary = bench.doc.data.production.calibrations.get(id,{})
	for i in range(3):
		_label("控制点 %d" % (i+1))
		var row := HBoxContainer.new(); body.add_child(row)
		var p := Vector2(initial[i][0],initial[i][1])
		var scale := Vector2(ref.size[0],ref.size[1])/Vector2(dimensions)
		var target := Vector2(ref.position[0],ref.position[1])+Vector2(ref.size[0],ref.size[1])*0.5+((p-Vector2(dimensions)*0.5)*scale).rotated(deg_to_rad(ref.rotation))
		var source_point: Array = previous.get("source_points",initial)[i] if previous.get("source_points",[]).size() >= 3 else initial[i]
		var world_point: Array = previous.world_points[i] if previous.get("world_points",[]).size() >= 3 else [target.x,target.y]
		var fields := [_spin(row,source_point[0]),_spin(row,source_point[1]),_spin(row,world_point[0]),_spin(row,world_point[1])]
		controls.append(fields)
		var anchor := OptionButton.new(); body.add_child(anchor)
		anchor.add_item("从已有城关填入图面坐标…")
		for f in bench.doc.data.features:
			if f.points.size() == 1:
				anchor.add_item(f.name); anchor.set_item_metadata(anchor.item_count-1,f.points[0])
		anchor.item_selected.connect(func(index):
			if index > 0:
				var point: Array=anchor.get_item_metadata(index)
				fields[2].value=point[0]; fields[3].value=point[1])
	var citation := _text("资料来源",previous.get("citation",ref.path))
	var era := _text("资料时代 / 说明",previous.get("era","未指定；历史地理待核"))
	_label("最大允许误差（图面单位）")
	var tolerance := _spin(body,8); tolerance.min_value=0
	var request := func():
		var source: Array=[]; var target: Array=[]
		for row in controls: source.append([row[0].value,row[1].value]); target.append([row[2].value,row[3].value])
		return {"source_points":source,"world_points":target,"image_size":[dimensions.x,dimensions.y],"tolerance":tolerance.value,"citation":citation.text,"era":era.text}
	_button("计算误差（不修改）",func():
		var inputs: Dictionary=request.call()
		var fit := Registration.fit(inputs.source_points,inputs.world_points,dimensions)
		feedback.text="平均误差 %.3f；最大误差 %.3f 图面单位。" % [fit.rms,fit.max_error] if fit.ok else fit.error)
	_button("应用校准",func():
		var response: Dictionary=bench.doc.calibrate_reference(id,request.call())
		_result(response.ok,response.get("error","")))
func _regions_page() -> void:
	_label("区域书签只定位同一地图，不生成另一张地图。")
	var name := _text("书签名称")
	_button("把当前视野存为区域",func():
		var rect: Rect2=bench.canvas.visible_world_rect()
		if not rect.has_area() or name.text.strip_edges().is_empty(): feedback.text="请填写名称，并让视野包含地图。"; return
		var regions: Array=bench.doc.data.production.regions.duplicate(true)
		regions.append({"id":"region_"+str(Time.get_ticks_usec()),"name":name.text.strip_edges(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
		_result(bench.doc.set_production("regions",regions)); _rebuild())
	for region in bench.doc.data.production.regions:
		_label(region.name)
		_button("定位此区域",func(): focus_rect(region.rect); hide())
		_button("保护与此区域相交的对象",func():
			var r: Array=region.rect
			var area := Rect2(r[0],r[1],r[2],r[3])
			var ids: Array=[]
			for f in bench.doc.data.features:
				var pts := Doc.packed(f.points); var bounds := Rect2(pts[0],Vector2.ZERO)
				for p in pts: bounds=bounds.expand(p)
				if area.intersects(bounds.grow(0.001)) and not f.protected: ids.append(f.id)
			_result(bench.doc.protect_features(ids,true)))
		_button("删除此书签",func():
			var regions: Array=bench.doc.data.production.regions.filter(func(r): return r.id != region.id)
			bench.doc.set_production("regions",regions); _rebuild())
func focus_rect(value: Array) -> void:
	var rect := Rect2(value[0],value[1],value[2],value[3])
	bench.canvas.zoom=clampf(minf((bench.canvas.size.x-40)/rect.size.x,(bench.canvas.size.y-40)/rect.size.y),0.002,6)
	bench.canvas.center_on(rect.get_center())
func _audit_page() -> void:
	_label("检查地形关联与保存的通行情景。结果仅针对所设范围和精度，不代表正式战役规则已接入。")
	var review=preload("audit_review_panel.gd").new()
	body.add_child(review)
	review.setup(bench.doc,bench.canvas,hide)
	_button("运行全部通行场景",run_scenarios)
	var name := _text("新场景名称（使用当前起终点、视野、单位和关隘开关）")
	var expected := CheckBox.new(); expected.text="预期可以通行"; expected.button_pressed=true; body.add_child(expected)
	_button("保存当前检查条件为场景",func():
		var r: Rect2=bench.canvas.visible_world_rect()
		if name.text.strip_edges().is_empty() or not r.has_area(): feedback.text="请填写名称并让视野包含起终点。"; return
		var gates := {}
		for f in bench.doc.data.features:
			if f.kind in ["pass","ford"]: gates[f.id]=f.gate_open
		var cases: Array=bench.doc.data.production.checks.duplicate(true)
		cases.append({"id":"check_"+str(Time.get_ticks_usec()),"name":name.text.strip_edges(),"start":[bench.canvas.start_point.x,bench.canvas.start_point.y],"finish":[bench.canvas.end_point.x,bench.canvas.end_point.y],"rect":[r.position.x,r.position.y,r.size.x,r.size.y],"step":float(bench.preview_precision.get_selected_metadata()),"unit":"army" if bench.unit.selected == 0 else "light","revealed":bench.revealed.button_pressed,"expected":expected.button_pressed,"gates":gates})
		_result(bench.doc.set_production("checks",cases)); _rebuild())
	if last_fingerprint != bench.doc.fingerprint() and not last_results.is_empty(): _label("旧检查结果已过期，请重新运行。")
	for scenario in bench.doc.data.production.checks:
		var label: String=scenario.name
		for result in last_results:
			if result.id == scenario.id: label="[%s] %s" % [result.status,label]
		_button(label,func():
			focus_rect(scenario.rect)
			bench.canvas.start_point=Vector2(scenario.start[0],scenario.start[1]); bench.canvas.end_point=Vector2(scenario.finish[0],scenario.finish[1])
			var result:=Audit.run_case(bench.doc,scenario)
			bench.canvas.route=result.path
			bench.result_label.text="[%s] %s：%s" % [result.status,scenario.name,result.reason]
			hide())
		_button("删除此场景",func():
			bench.doc.set_production("checks",bench.doc.data.production.checks.filter(func(c): return c.id != scenario.id)); _rebuild())
func run_scenarios() -> void:
	if audit_running: return
	audit_running=true
	var copy=Doc.new(); copy.replace_document(bench.doc.snapshot())
	var fingerprint: String=bench.doc.fingerprint()
	var results: Array=[]
	for scenario in copy.data.production.checks:
		results.append(Audit.run_case(copy,scenario))
		if is_instance_valid(feedback): feedback.text="已检查 %d / %d" % [results.size(),copy.data.production.checks.size()]
		await get_tree().process_frame
	last_results=results; last_fingerprint=fingerprint; audit_running=false
	if page == 3: _rebuild()
	var failed:=0
	for result in results:
		if result.status != "PASS": failed+=1
	feedback.text="检查完成：%d 个场景，%d 个未通过 / 未确定。" % [results.size(),failed]
func _batch_page() -> void:
	_label("批量操作使用地图指纹防止覆盖较新的手工修改；同一批次重试不会重复创建。所有操作成功才一起应用。")
	var fingerprint:=_text("当前地图指纹",bench.doc.fingerprint()); fingerprint.editable=false
	_button("导入批量操作 JSON…",func(): hide(); bench._choose_file("batch"))
	_button("加载潼关与剑门连续结构样区",func():
		hide()
		bench._guard(func():
			var nodes: Array=project_nodes()
			var error: String=bench.doc.replace_document(Samples.make(nodes))
			bench._status("已载入 0.5.1 修订样区：城关分类与四处占地冲突已处理；边界仍为结构示意。" if error.is_empty() else error)
			bench.canvas.fit_map()))
	_button("在现有游戏地图中预览（独立新局）",_launch_game_preview)
	_label("脚本入口：prototypes/strategic_map_editor/tools/authoring_cli.gd。可查询、应用批次、体检、导出报告、按区域截图。UI 和脚本共用同一文档与校验方法。")

func _launch_game_preview() -> void:
	if bench.doc.data.production.coordinate_frame != "game_map_3720x2400_scaled_4":
		feedback.text="此预览需要与项目坐标一致的地图。可先加载连续结构样区；普通画布请继续使用工坊预览。"; return
	var project := ""
	for candidate in ["res://","res://../../"]:
		if FileAccess.file_exists(candidate+"scenes/ui/title_screen.tscn"): project=ProjectSettings.globalize_path(candidate).simplify_path(); break
	if project.is_empty(): feedback.text="找不到主游戏工程；可将地图文件带回主项目预览。"; return
	var folder:=ProjectSettings.globalize_path("user://authoring_previews")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: feedback.text="无法创建预览快照目录。"; return
	var copy=Doc.new(); copy.replace_document(bench.doc.snapshot()); copy.current_path=bench.doc.current_path
	var path:=folder.path_join("preview_"+str(Time.get_ticks_usec())+".map.json")
	var error: String=copy.save_file(path)
	if not error.is_empty(): feedback.text=error; return
	var pid:=OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",project,"--rendering-method","gl_compatibility","--script","res://prototypes/strategic_map_editor/tools/game_preview.gd","--",path]))
	feedback.text="已在独立新局打开候选；城关采用工坊外观，复用原地点、情报、点击与相机，未接入地形通行规则。" if pid>=0 else "启动失败；快照已保存到 "+path
static func project_nodes() -> Array:
	for path in ["res://data/scenarios/anshi_rebellion/map_strategy_nodes.json","res://../../data/scenarios/anshi_rebellion/map_strategy_nodes.json"]:
		if not FileAccess.file_exists(path): continue
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("strategic_nodes") is Array: return parsed.strategic_nodes
	return []
