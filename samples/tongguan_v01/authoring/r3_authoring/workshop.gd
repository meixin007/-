extends Control
var host: RefCounted
var canvas: Control
var status: Label
var result_label: Label
var diff_label: Label
var commit_button: Button
var add_button: Button
var move_button: Button
var delete_button: Button
var pin_button: Button
var lock_button: Button
var exclude_button: Button
var preview_button: Button
var undo_button: Button
var redo_button: Button
var save_button: Button
var load_button: Button
var publish_button: Button
var seed: SpinBox
var density: HSlider
var region: OptionButton
var asset: OptionButton
var scroll: ScrollContainer
var publication_path: String
var workspace_path: String
func label(parent: Node,text: String,size:=16)->Label:
	var value=Label.new();value.text=text;value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;value.add_theme_font_size_override("font_size",size);parent.add_child(value);return value
func button(parent: Node,text: String,action: Callable)->Button:
	var value=Button.new();value.text=text;value.custom_minimum_size.y=34;parent.add_child(value);value.pressed.connect(action);return value
func row(parent: Node)->HBoxContainer:
	var value=HBoxContainer.new();parent.add_child(value);return value
func _ready()->void:
	host=preload("res://r3_authoring/resolver.gd").new()
	var folder=OS.get_environment("APPDATA").replace("\\","/").path_join("tongguan_slice_v01_integrity/authoring")
	publication_path=folder.path_join("publication.json");workspace_path=folder.path_join("workspace.json")
	get_window().title="潼关 · R3 人工补丁与完整占地"
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","sans-serif"]);var tv=Theme.new();tv.default_font=font;tv.default_font_size=16;theme=tv
	var background=ColorRect.new();background.color=Color("183039");background.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var title=label(self,"潼关 / 人工补丁、锁区与重生成",27);title.position=Vector2(24,20);title.size=Vector2(1100,40)
	var subtitle=label(self,"制作样本独立保存；发布文件供运行场景读取，制作修改不写战役状态。",16);subtitle.position=Vector2(26,67);subtitle.size=Vector2(1250,28)
	canvas=preload("res://r3_authoring/canvas.gd").new();canvas.host=host;canvas.font=font;canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.offset_left=24;canvas.offset_top=112;canvas.offset_right=-440;canvas.offset_bottom=-36;add_child(canvas);canvas.changed.connect(refresh)
	scroll=ScrollContainer.new();scroll.anchor_left=1;scroll.anchor_right=1;scroll.anchor_bottom=1;scroll.offset_left=-420;scroll.offset_right=-24;scroll.offset_top=112;scroll.offset_bottom=-36;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	var panel=VBoxContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.add_theme_constant_override("separation",7);scroll.add_child(panel)
	var camera_row=row(panel);button(camera_row,"西侧林区",func():canvas.center=Vector2(-2250,900);canvas.zoom=0.7;canvas.queue_redraw());button(camera_row,"关城",func():canvas.center=Vector2(-350,-100);canvas.zoom=1.1;canvas.queue_redraw());button(camera_row,"全范围",func():canvas.center=Vector2.ZERO;canvas.zoom=0.16;canvas.queue_redraw())
	status=label(panel,"");status.custom_minimum_size.y=75
	var edit=row(panel);add_button=button(edit,"新增树林",add);move_button=button(edit,"移选中 +256m",move_selected)
	var edit2=row(panel);delete_button=button(edit2,"删除选中",erase_selected);pin_button=button(edit2,"冻结 / 解冻",toggle_pin)
	button(panel,"更换选中素材版本",func():var id=canvas.selected;show_result(host.update_object(id,{"asset_version":2 if host.state.objects.get(id,{}).get("asset_version")==1 else 1}),"已记录素材更新补丁。"))
	var zones=row(panel);lock_button=button(zones,"光标处建锁区",func():zone("lock"));exclude_button=button(zones,"排除自动生成",func():zone("exclude_generation"))
	button(panel,"移除最后一个区域",func():var keys=host.state.zones.keys();show_result(host.remove_zone(str(keys[-1])) if not keys.is_empty() else host.fail("尚无区域。"),"已移除区域。"))
	button(panel,"微调关后支路",func():var id="tongguan.road.connector";var points=host.state.feature_patches.get(id,{}).get("points_m",host.source.layout.roads[1].points_m).duplicate(true);points[1][0]=-610.0 if float(points[1][0])==-620 else -620.0;show_result(host.update_feature(id,points),"已记录道路补丁，接点保持。"))
	region=OptionButton.new();panel.add_child(region)
	for title_text in ["西侧林区","东侧林区","两侧林区"]:region.add_item(title_text)
	seed=SpinBox.new();seed.min_value=0;seed.max_value=2147483647;seed.value=17001;panel.add_child(seed)
	label(panel,"密度");density=HSlider.new();density.min_value=0;density.max_value=1;density.step=0.05;density.value=0.5;panel.add_child(density)
	asset=OptionButton.new();asset.add_item("已有素材版本1");asset.add_item("已有素材版本2");panel.add_child(asset)
	var generation=row(panel);preview_button=button(generation,"预览差异",preview);commit_button=button(generation,"提交差异",commit);commit_button.disabled=true
	diff_label=label(panel,"先预览，再提交。",15)
	var history=row(panel);undo_button=button(history,"撤销",func():show_result(host.undo(),"已撤销整个制作版本。"));redo_button=button(history,"重做",func():show_result(host.redo(),"已重做整个制作版本。"))
	button(panel,"检查穿过锁区的河岸候选",func():conflict("locked_boundary"));button(panel,"检查生成器ID失配",func():conflict("id_upgrade"))
	var saving=row(panel);save_button=button(saving,"保存制作样本",save);load_button=button(saving,"重读",restore)
	publish_button=button(panel,"发布当前制作样本",publish)
	result_label=label(panel,"点击树林选择，点击空地放置光标。",15);result_label.custom_minimum_size.y=90
	var footprints=CheckBox.new();footprints.text="显示完整绘制占地";footprints.button_pressed=true;panel.add_child(footprints);footprints.toggled.connect(func(value):canvas.show_footprints=value;canvas.queue_redraw())
	refresh()
func refresh()->void:
	status.text="对象 %d · 补丁 %d · 删除记录 %d\n区域 %d · 制作修订 %d\n选中：%s"%[host.state.objects.size(),host.state.patches.size(),host.state.tombstones.size(),host.state.zones.size(),host.state.revision,canvas.selected if not canvas.selected.is_empty() else "空地光标"]
	canvas.queue_redraw()
func show_result(result: Dictionary,success: String)->void:
	result_label.text=(str(result.get("message",success)) if result.get("recovered",false) else success) if result.get("ok",false) else str(result.get("message",result.get("error","操作未执行。")))
	result_label.modulate=Color("d3e8c8") if result.get("ok",false) else Color("efb49d")
	canvas.preview={};commit_button.disabled=true;refresh()
func add()->void:
	var result=host.add_object([canvas.probe.x,canvas.probe.y],asset.selected+1)
	if result.ok:canvas.selected=result.id
	show_result(result,"已新增稳定ID的人工树林。")
func move_selected()->void:
	var object: Dictionary=host.state.objects.get(canvas.selected,{})
	show_result(host.update_object(canvas.selected,{"position_m":[object.position_m[0]+256,object.position_m[1]]}) if not object.is_empty() else host.fail("请先选中树林。"),"已移动；对象ID保持。")
func erase_selected()->void:show_result(host.delete_object(canvas.selected),"已删除并保存删除意图。")
func toggle_pin()->void:show_result(host.pin_object(canvas.selected,not host.state.pins.has(canvas.selected)),"已切换对象冻结。")
func zone(kind: String)->void:show_result(host.add_zone([canvas.probe.x-90,canvas.probe.y-70,180,140],kind),"已按完整占地创建区域。")
func preview()->void:
	var areas=["forest_west"] if region.selected==0 else (["forest_east"] if region.selected==1 else ["forest_west","forest_east"])
	var result=host.preview_regeneration(areas,int(seed.value),density.value,asset.selected+1);canvas.preview=result;commit_button.disabled=not result.ok
	diff_label.text="新增 %d / 更新 %d / 删除 %d\n约束跳过 %d / 冲突 %d"%[result.get("added",[]).size(),result.get("updated",[]).size(),result.get("removed",[]).size(),result.get("skipped",[]).size(),result.get("conflicts",[]).size()]
	result_label.text="预览已就绪，当前制作版本未改变。" if result.ok else str(result.get("message","预览失败。"));refresh()
func commit()->void:show_result(host.commit_regeneration(str(canvas.preview.get("token",""))),"差异已原子提交；可撤销或重做。")
func conflict(kind: String)->void:
	var result=host.preview_conflict(kind);canvas.preview=result;commit_button.disabled=true;diff_label.text="冲突 %d · 整批未提交"%result.get("conflicts",[]).size();result_label.text=result.get("message","");refresh()
func save()->void:show_result(host.write_save(workspace_path),"制作样本与撤销历史已保存。")
func restore()->void:show_result(host.read_save(workspace_path),"已重读完整制作版本。")
func publish()->void:
	var result=host.publish(publication_path);show_result(result,"已发布；运行场景可点“读取制作发布”。\n"+str(result.get("path","")))
func _unhandled_key_input(event: InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:get_tree().quit()
