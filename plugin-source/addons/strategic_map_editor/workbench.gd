@tool
extends Control
const ArtCatalog = preload("art_catalog.gd")
const Doc = preload("document.gd")
const Canvas = preload("map_canvas.gd")
const Routes = preload("route_preview.gd")
const SettingsPanel = preload("settings_panel.gd")
const WorkspacePanel = preload("workspace_panel.gd")
const DialogShell = preload("dialog_shell.gd")
const Exporter = preload("map_exporter.gd")
const RecoveryStore = preload("recovery_store.gd")
const AuthoringSession = preload("authoring_session.gd")
const ArtVisualAudit = preload("art_visual_audit.gd")
const ArtImporter = preload("art_importer.gd")
const AssetBrowser = preload("asset_browser.gd")
const ThumbnailGrid = preload("art_thumbnail_grid.gd")
const Minimap = preload("minimap.gd")
const ProductionPanel = preload("production_panel.gd")
const GameMapPublisher = preload("game_map_publisher.gd")
const GameMapPreferences = preload("workshop_map_preferences.gd")
const LAYER_NAMES := {"terrain":"山川植被","water":"河流水域","passages":"自然通道","boundaries":"海岸与道界","prefectures":"州界与势力","sites":"城池关隘","notes":"文字注记"}
const RULE_NAMES := ["仅表现 / 不改通行", "普通通行", "崎岖 / 减速", "禁止通行", "水域 / 需渡点"]
var doc = Doc.new()
var canvas
var status: Label
var title_label: Label
var object_list: ItemList
var layer_box: VBoxContainer
var inspector: VBoxContainer
var selected_name: LineEdit
var selected_note: LineEdit
var domain_id: LineEdit
var selected_rule: OptionButton
var selected_width: SpinBox
var river_edit_button: Button
var valley_edit_button: Button
var curve_canvas_button: Button
var curve_width_row: HBoxContainer
var curve_width_spin: SpinBox
var ridge_layout_row: HBoxContainer
var ridge_asset: OptionButton
var ridge_spacing: SpinBox
var art_style: OptionButton
var selected_art: OptionButton
var art_density: SpinBox
var art_seed: SpinBox
var art_preview: TextureRect
var brush_picker: OptionButton
var brush_filter: OptionButton
var brush_preview: TextureRect
var brush_size: SpinBox
var asset_query: LineEdit
var asset_grid: ItemList
var asset_grid_signature: Array=[]
var material_shelf: VBoxContainer
var placement_hint: Label
var view_picker: OptionButton
var recent_art_assets: Array=[]
var brush_bundle_id:=""
var appearance_x: SpinBox
var appearance_y: SpinBox
var label_x: SpinBox
var label_y: SpinBox
var label_size: SpinBox
var width_factor: SpinBox
var appearance_visible: CheckBox
var label_visible: CheckBox
var art_instance_inspector: VBoxContainer
var art_instance_asset: OptionButton
var art_instance_scale: SpinBox
var art_instance_opacity: SpinBox
var art_instance_flip: CheckBox
var art_instance_plane: OptionButton
var art_instance_group: LineEdit
var art_instance_anchor: OptionButton
var site_panel: VBoxContainer
var site_name: LineEdit
var site_domain: LineEdit
var site_x: SpinBox
var site_y: SpinBox
var site_info: Label
var art_group_toggle: CheckBox
var art_pending_label: Label
var placement_panel: VBoxContainer
var placement_depth: SpinBox
var placement_width: SpinBox
var placement_height: SpinBox
var placement_grounding: CheckBox
var placement_overlap: CheckBox
var depth_sort_toggle: CheckBox
var selected_art_id := ""
var pending_label: Label
var refreshing_inspector := false
var selected_scale: SpinBox
var selected_gate: OptionButton
var gate_open: CheckBox
var secret_route: CheckBox
var unit: OptionButton
var revealed: CheckBox
var result_label: Label
var selected_id := ""
var file_dialog: FileDialog
var file_action := ""
var confirm
var pending: Callable
var close_action: Callable
var refresh_queued := false
var autosave_enabled := true
var tool_buttons: Dictionary = {}
var tool_button_group: ButtonGroup
var settings_panel
var coordinate_label: Label
var autosave_signature := ""
var autosave_worker: Thread
var autosave_job_signature := ""
var _editor_saved_revision := -1
var _editor_saved_path := ""
var _editor_saved_input: Dictionary = {}
var _editor_recovery_path := ""
var autosave_timer: Timer
var last_author_input_ms := -3000
var refreshed_layers: Array=[]
var refreshed_features: Array=[]
var refreshed_geometry:=-1
var outer_split: HSplitContainer
var inner_split: HSplitContainer
var floating_layer: Control
var tools_panel
var properties_panel
var layout_persistence_enabled := true
var layout_timer: Timer
var layout_file_path := "user://map_editor_layout.cfg"
# The standalone scene and editor plugin opt in; embedded test workbenches stay isolated.
@export var restore_last_map_on_start := false
var startup_state_path := "user://map_editor_startup.cfg"
var startup_default_map := GameMapPublisher.GAME_MAP_PATH
var game_map_path := GameMapPublisher.GAME_MAP_PATH
var game_preferences_path := GameMapPreferences.DEFAULT_PATH
var game_map_publisher
var game_map_status: Label
var _game_map_label_path := ""
var initial_fit_done := false
var workspace_activation_pending := false
var layout_fit_pending := false
var object_search: LineEdit
var minimap
var rules_toggle: CheckBox
var local_preview: CheckBox
var preview_precision: OptionButton
var export_options := {"longest":4096,"tiled":false,"tile_size":2048,"region":Rect2(),"scope":"whole","layer":"composite","preset":"display","transparent":false,"include_labels":true,"include_auxiliary":false,"label_clip":"allow"}
var exporting := false
var production_panel
var recovery_store = RecoveryStore.new()
var recovery_session_id := "window_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
var water_width_spin: SpinBox
var water_radius_spin: SpinBox
var water_connect_toggle: CheckBox
var water_whole_toggle: CheckBox
var water_start_style: OptionButton
var water_end_style: OptionButton
var faction_name: LineEdit
var faction_color: ColorPickerButton
var faction_panel: VBoxContainer

func _ready() -> void:
	set_process(false)
	if not Engine.is_editor_hint() and get_tree().current_scene == self:
		get_tree().auto_accept_quit = false
		close_action = func(): get_tree().quit()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation",6)
	margin.add_child(root)
	var heading := HBoxContainer.new()
	root.add_child(heading)
	var brand := _label("山河形胜  /  二维地图工坊",22)
	heading.add_child(brand)
	title_label = _label("",15)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(title_label)
	var toolbar := HFlowContainer.new()
	root.add_child(toolbar)
	_button(toolbar,"新建",func(): _guard(func(): doc.replace_document(Doc.blank()); canvas.fit_map()))
	_button(toolbar,"潼关示例",func(): _guard(_load_sample))
	_button(toolbar,"样区与历史",_show_art_samples)
	_button(toolbar,"资源对照 / 重载",_show_art_bundle_comparison)
	_button(toolbar,"美术素材",_focus_materials)
	_button(toolbar,"地点与关口",_show_site_anchors)
	art_style = OptionButton.new()
	art_style.add_item("结构示意")
	art_style.add_item("手绘淡彩 · 潼关")
	art_style.item_selected.connect(func(i): doc.set_art_style(ArtCatalog.STYLES[i]))
	toolbar.add_child(art_style)
	view_picker = OptionButton.new()
	for name in ["成图视图", "结构检查", "合成核对"]: view_picker.add_item(name)
	view_picker.item_selected.connect(func(i):
		canvas.view_mode = ["art", "structure", "overlay"][i]
		if canvas.has_art(): canvas.art.ensure_loaded()
		canvas.queue_redraw())
	toolbar.add_child(view_picker)
	_button(toolbar,"打开地图",func(): _guard(func(): _choose_file("open")))
	_button(toolbar,"打开游戏主地图",func(): _guard(func(): _open(game_map_path)))
	_button(toolbar,"设为游戏主地图",func(): _guard_unapplied(_adopt_game_map))
	_button(toolbar,"保存",save_current)
	_button(toolbar,"另存为",save_as)
	_button(toolbar,"命名快照",_show_snapshot_dialog)
	_button(toolbar,"恢复项目",_show_recovery_dialog)
	_button(toolbar,"导入参考图",func(): _choose_file("background"))
	_button(toolbar,"参考图设置",func(): settings_panel.show_reference(doc,canvas.active_reference))
	_button(toolbar,"画布设置",func(): settings_panel.show_canvas(doc))
	_button(toolbar,"导出地图",show_export_options)
	_button(toolbar,"成图检查",_show_art_visual_audit)
	_button(toolbar,"撤销",func(): _request_history(false))
	_button(toolbar,"重做",func(): _request_history(true))
	_button(toolbar,"适合窗口",func(): canvas.fit_map())
	_button(toolbar,"工具面板",func(): tools_panel.show(); _schedule_layout_save())
	_button(toolbar,"属性面板",func(): properties_panel.show(); _schedule_layout_save())
	_button(toolbar,"重置布局",reset_layout)
	_button(toolbar,"操作说明",_show_help)
	if FileAccess.file_exists("user://map_editor_autosave.map.json"):
		_button(toolbar,"恢复旧版草稿",func(): _guard(func():
			_open("user://map_editor_autosave.map.json", false)
			doc.current_path = ""))
	var body := HSplitContainer.new()
	_organize_toolbar(toolbar,root)
	game_map_status=_label("独立地图；使用“打开游戏主地图”继续日常编辑。",14)
	game_map_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	root.add_child(game_map_status)
	game_map_publisher=GameMapPublisher.new()
	game_map_publisher.game_path=game_map_path
	game_map_publisher.reported.connect(func(message):game_map_status.text=message;game_map_status.show())
	add_child(game_map_publisher)
	outer_split = body
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	root.add_child(body)
	tools_panel = WorkspacePanel.new()
	tools_panel.allow_docking = true
	tools_panel.custom_minimum_size.x = 244
	body.add_child(tools_panel)
	tools_panel.set_caption("绘图工具")
	var left: VBoxContainer = tools_panel.content
	inner_split = HSplitContainer.new()
	inner_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_split.add_theme_constant_override("separation",10)
	body.add_child(inner_split)
	tool_button_group = ButtonGroup.new()
	tool_button_group.allow_unpress = true
	left.add_child(_label("水系 · 画河与修岸",15))
	var water_tools := HFlowContainer.new()
	left.add_child(water_tools)
	for pair in [["river_draw","河流画笔"],["river_erase","河流橡皮"],["river_move","拖弯河道"],["river_width","调整河宽"],["lake_paint","湖泊画笔"],["lake_erase","湖泊橡皮"]]:
		var button := _button(water_tools,pair[1],func(): _request_tool_change(pair[0],pair[1]))
		button.toggle_mode=true; button.button_group=tool_button_group
		tool_buttons[pair[0]]=button
	water_width_spin=_spin(left,"河宽",6,128,1)
	water_width_spin.value=24
	water_width_spin.value_changed.connect(func(value): canvas.water_width=value; canvas._redraw_interaction())
	water_radius_spin=_spin(left,"橡皮 / 调整半径",4,600,2)
	water_radius_spin.value=60
	water_radius_spin.value_changed.connect(func(value): canvas.water_radius=value; canvas._redraw_interaction())
	water_connect_toggle=CheckBox.new(); water_connect_toggle.text="河流端点自动连接"; water_connect_toggle.button_pressed=true
	water_connect_toggle.toggled.connect(func(value): canvas.water_connect=value)
	left.add_child(water_connect_toggle)
	water_start_style=_water_endpoint_option(left,"起笔端点")
	water_end_style=_water_endpoint_option(left,"收笔端点")
	water_start_style.item_selected.connect(func(index): canvas.water_end_styles[0]=["auto","source","join","mouth"][index])
	water_end_style.item_selected.connect(func(index): canvas.water_end_styles[1]=["auto","source","join","mouth"][index])
	water_whole_toggle=CheckBox.new(); water_whole_toggle.text="调整河宽作用于整条河段"
	water_whole_toggle.toggled.connect(func(value): canvas.water_whole=value)
	left.add_child(water_whole_toggle)
	var water_help:=_label("自动：自由端渐细，连接端保留河宽\n续画继承端点宽度与方向\n拖画松开应用；Ctrl+Z 撤销一笔\n右键 / Esc 取消；失败笔画 Enter 重试",12)
	water_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	left.add_child(water_help)
	left.add_child(_label("美术部件 · 只改表现", 15))
	for pair in [["art_stamp","单件点放"],["art_select","选择美术部件"],["art_place","美术画笔 / 拖动连续绘制"]]:
		var b := _button(left,pair[1],func(): _request_tool_change(pair[0],pair[1]))
		b.toggle_mode = true; b.button_group = tool_button_group
		tool_buttons[pair[0]] = b
	placement_hint = _label("点下方素材 → 地图左键放置\n右键 / Esc 退出 → 拖动部件", 13)
	placement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(placement_hint)
	_button(left,"导入透明部件",func(): _choose_file("art_png"))
	_button(left,"浏览素材 · 缩略图 / 最近使用",_show_asset_browser)
	_button(left,"查找已放置部件",_show_art_instances)
	_button(left,"地点与关口 · 查找定位",_show_site_anchors)
	_button(left,"新增关口定位（暂无外观）",func(): _guard_unapplied(func(): _create_site_anchor("pass")))
	var anchor_toggle:=CheckBox.new(); anchor_toggle.text="显示地点定位标记"; anchor_toggle.button_pressed=true
	anchor_toggle.toggled.connect(func(value): canvas.show_site_anchors=value; canvas._camera_cache_valid=false; canvas.queue_redraw())
	left.add_child(anchor_toggle)
	brush_filter = OptionButton.new()
	for name in ["全部", "树木", "山体", "城关", "地表"]: brush_filter.add_item(name)
	left.add_child(brush_filter)
	brush_picker = OptionButton.new()
	left.add_child(brush_picker)
	brush_filter.item_selected.connect(func(_i): _fill_brush_picker())
	brush_picker.item_selected.connect(func(_i): _set_brush_asset())
	asset_query = LineEdit.new(); asset_query.placeholder_text = "搜索素材名称 / ID"
	left.add_child(asset_query)
	asset_grid = ThumbnailGrid.new(); asset_grid.custom_minimum_size = Vector2(200,250)
	asset_grid.allow_reselect = true
	asset_grid.max_columns = 2; asset_grid.fixed_column_width = 104
	asset_grid.fixed_icon_size = Vector2i(80,60); asset_grid.icon_mode = ItemList.ICON_MODE_TOP
	asset_grid.max_text_lines = 2
	left.add_child(asset_grid)
	asset_query.text_changed.connect(func(_text): _refresh_asset_grid())
	asset_grid.item_selected.connect(func(i): _choose_browser_asset(str(asset_grid.get_item_metadata(i))))
	brush_preview = TextureRect.new()
	brush_preview.custom_minimum_size = Vector2(130, 60)
	brush_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brush_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(brush_preview)
	brush_preview.hide() # The dock thumbnails already show the selected material.
	brush_size = _spin(left, "部件视觉比例", 0.25, 4, 0.05)
	left.move_child(brush_size.get_parent(), placement_hint.get_index()+1)
	brush_size.value = 1
	brush_size.value_changed.connect(func(v): canvas.brush_scale = v; canvas._redraw_interaction())
	_button(left,"固定视野内自动素材",func():
		var result: Dictionary = canvas.freeze_selected_scatter()
		_status("已固定 %d 件素材；本视野可逐件调整，撤销可回退。" % result.count if result.ok else result.error))
	_button(left,"重新生成视野内散布",func():
		var result: Dictionary = canvas.regenerate_selected_scatter(randi_range(0,999999))
		_status("已局部重新生成；移除 %d 个固定组，其他区域与手工部件保留。" % result.removed_groups if result.ok else result.error))
	for pair in [["select","选择 / 移动"],["art_select","选择美术部件"],["art_place","美术画笔 / 拖动连续绘制"],["art_erase","擦除美术部件"],["hand","抓手 / 拖动画布"],["mountain","高山区域"],["hills","低丘区域"],["forest","林地区域"],["basin","平原 / 盆地"],["water","水域区域"],["river","河流线"],["coastline","海岸线"],["country_border","国界线"],["province_border","道界线"],["city","放置城池"],["pass","放置关隘"],["ford","放置渡口"],["label","文字注记"],["valley","谷道缺口"],["trail","轻装险径"],["crossing","渡河连接"],["hole","在区域内挖孔"],["insert_vertex","添加顶点"],["remove_vertex","删除顶点"],["reference","移动参考图"]]:
		if tool_buttons.has(pair[0]): continue
		var b := _button(left,pair[1],func(): _request_tool_change(pair[0],pair[1]))
		b.toggle_mode = true
		b.button_group = tool_button_group
		b.button_pressed = pair[0] == "select"
		tool_buttons[pair[0]] = b
	var center := VBoxContainer.new()
	var state_button:=_button(left,"绘制州界区域",func(): _request_tool_change("prefecture","州界区域"))
	state_button.toggle_mode=true;state_button.button_group=tool_button_group
	tool_buttons.prefecture=state_button
	_organize_tools(left)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_split.add_child(center)
	var hint := _label("滚轮缩放 · 抓手 / 中键拖动 · Enter 完成 · 右键取消",13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(hint)
	var brush_bar := HFlowContainer.new()
	_section(center,"视图与画笔设置",false).add_child(brush_bar)
	for pair in [["show_country_borders","国界"],["show_dao_borders","道界"],["show_prefectures","州界"],["show_factions","势力颜色"]]:
		var toggle:=CheckBox.new();toggle.text=pair[1];toggle.button_pressed=true
		toggle.toggled.connect(func(value): canvas.set(pair[0],value);canvas.queue_redraw())
		brush_bar.add_child(toggle)
	var stroke_mode := OptionButton.new()
	stroke_mode.add_item("逐点绘制")
	stroke_mode.add_item("自由画笔")
	stroke_mode.item_selected.connect(func(i): canvas.freehand=i==1; canvas.set_tool(canvas.tool))
	brush_bar.add_child(stroke_mode)
	var snapping := OptionButton.new()
	for caption in ["无吸附","网格吸附","顶点吸附"]: snapping.add_item(caption)
	snapping.item_selected.connect(func(i): canvas.snap_mode=i)
	brush_bar.add_child(snapping)
	var grid := CheckBox.new()
	grid.text = "网格"
	grid.toggled.connect(func(v): canvas.show_grid=v; canvas.queue_redraw())
	brush_bar.add_child(grid)
	var step := SpinBox.new()
	step.min_value = 8
	step.max_value = 256
	step.step = 8
	step.value = 32
	step.tooltip_text = "网格间距（图面单位）"
	step.value_changed.connect(func(v): canvas.grid_step=v; canvas.queue_redraw())
	brush_bar.add_child(step)
	brush_bar.add_child(_label("边界笔宽",12))
	var brush := SpinBox.new()
	brush.min_value = 1
	brush.max_value = 64
	brush.value = 3
	brush.value_changed.connect(func(v): canvas.brush_width=v)
	brush_bar.add_child(brush)
	brush_bar.add_child(_label("简化",12))
	var smoothing := SpinBox.new()
	smoothing.min_value = 0.5
	smoothing.max_value = 10
	smoothing.step = 0.5
	smoothing.value = 2
	smoothing.tooltip_text = "自由画笔去除多余点的容差（屏幕像素）"
	smoothing.value_changed.connect(func(v): canvas.simplify_pixels=v)
	brush_bar.add_child(smoothing)
	canvas = Canvas.new()
	canvas.name = "MapCanvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(280,240)
	center.add_child(canvas)
	canvas.bind_document(doc)
	canvas.selection_guard = _request_selection_change
	canvas.tool_changed.connect(_sync_tool_buttons)
	_fill_brush_picker()
	canvas.selection_changed.connect(_select)
	canvas.art_selection_changed.connect(_select_art)
	canvas.message.connect(_status)
	canvas.endpoint_chosen.connect(func(_p,_s): result_label.text="起终点已修改，请重新检查。")
	coordinate_label = _label("图面坐标 · 滚轮缩放",12)
	center.add_child(coordinate_label)
	canvas.pointer_changed.connect(func(p,z): coordinate_label.text="X %.0f  Y %.0f   |   缩放 %.0f%%" % [p.x,p.y,z*100])
	var preview_bar := HFlowContainer.new()
	center.add_child(preview_bar)
	_button(preview_bar,"设起点",func(): _request_tool_change("start"))
	_button(preview_bar,"设终点",func(): _request_tool_change("end"))
	unit = OptionButton.new()
	unit.add_item("大军 / 辎重")
	unit.add_item("轻装小队")
	preview_bar.add_child(unit)
	revealed = CheckBox.new()
	revealed.text = "已发现险径"
	preview_bar.add_child(revealed)
	_button(preview_bar,"检查通行",check_route)
	local_preview = CheckBox.new()
	local_preview.text = "视野精查"
	local_preview.toggled.connect(func(_v): _invalidate_preview())
	preview_bar.add_child(local_preview)
	preview_precision = OptionButton.new()
	for precision in [2,4,8,16]:
		preview_precision.add_item("格距 %d" % precision)
		preview_precision.set_item_metadata(preview_precision.item_count-1,precision)
	preview_precision.select(1)
	preview_precision.tooltip_text = "局部检查的图面单位；每边最多 256 格"
	preview_precision.item_selected.connect(func(_i): _invalidate_preview())
	preview_bar.add_child(preview_precision)
	var rules := CheckBox.new()
	rules_toggle = rules
	rules.text = "通行标注"
	rules.button_pressed = true
	rules.toggled.connect(func(v): canvas.show_rules=v; canvas.queue_redraw())
	preview_bar.add_child(rules)
	depth_sort_toggle=CheckBox.new()
	depth_sort_toggle.text="按落点遮挡"
	depth_sort_toggle.toggled.connect(func(value):
		_guard_unapplied(func(): doc.set_depth_sort(value))
		depth_sort_toggle.set_pressed_no_signal(doc.data.presentation.get("depth_sort",false)))
	preview_bar.add_child(depth_sort_toggle)
	var footprints:=CheckBox.new()
	footprints.text="占地轮廓"
	footprints.toggled.connect(func(value): canvas.show_footprints=value; canvas.queue_redraw())
	preview_bar.add_child(footprints)
	unit.item_selected.connect(func(_i): _invalidate_preview())
	revealed.toggled.connect(func(_v): _invalidate_preview())
	result_label = _label("编辑器离线预览：未接入战役、时间、天气或存档。",13)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(result_label)
	properties_panel = WorkspacePanel.new()
	properties_panel.allow_docking = true
	properties_panel.custom_minimum_size.x = 292
	inner_split.add_child(properties_panel)
	properties_panel.set_caption("图层与属性")
	var right: VBoxContainer = properties_panel.content
	minimap = Minimap.new()
	minimap.canvas = canvas
	right.add_child(minimap)
	_button(right,"制作工具 · 校准 / 几何 / 体检",func(): production_panel.show_tools(self))
	right.add_child(_label("图层  /  显示与锁定",17))
	layer_box = VBoxContainer.new()
	right.add_child(layer_box)
	right.add_child(_label("地图对象",17))
	object_search = LineEdit.new()
	object_search.placeholder_text = "搜索名称、类型或绑定 ID"
	object_search.text_changed.connect(func(_text): _refresh_objects())
	right.add_child(object_search)
	object_list = ItemList.new()
	object_list.select_mode = ItemList.SELECT_MULTI
	object_list.custom_minimum_size.y = 155
	object_list.item_selected.connect(func(index):
		if not canvas.request_select_feature(str(object_list.get_item_metadata(index))): _refresh_objects())
	object_list.multi_selected.connect(func(index,chosen):
		var ids: Array = canvas.selection_ids.duplicate()
		var id: String = object_list.get_item_metadata(index)
		if chosen and not id in ids: ids.append(id)
		elif not chosen: ids.erase(id)
		if not canvas.request_select_many(ids): _refresh_objects())
	object_list.item_activated.connect(func(index):
		var id: String = str(object_list.get_item_metadata(index))
		if canvas.request_select_feature(id): canvas.locate_feature(id))
	right.add_child(object_list)
	_button(right,"定位所选（或双击对象）",func(): canvas.locate_feature(selected_id))
	art_instance_inspector = VBoxContainer.new()
	right.add_child(art_instance_inspector)
	art_instance_inspector.add_child(_label("所选美术部件 · 不改变规则", 16))
	art_instance_asset = OptionButton.new()
	for key in ArtCatalog.library_keys():
		art_instance_asset.add_item(ArtCatalog.label(key))
		art_instance_asset.set_item_metadata(art_instance_asset.item_count-1, key)
	art_instance_inspector.add_child(art_instance_asset)
	art_instance_scale = _spin(art_instance_inspector, "视觉比例", 0.25, 4, 0.05)
	art_instance_opacity = _spin(art_instance_inspector, "透明度", 0.05, 1, 0.05)
	art_instance_flip = CheckBox.new()
	art_instance_flip.text = "左右镜像（仅山树地表）"
	art_instance_inspector.add_child(art_instance_flip)
	art_instance_plane=OptionButton.new()
	for label in ["按落点排列","底层地表","固定前景"]: art_instance_plane.add_item(label)
	art_instance_inspector.add_child(art_instance_plane)
	art_instance_group=_field(art_instance_inspector,"编组名称（相同名称为一组）")
	art_instance_inspector.add_child(_label("所属地点（换素材保留此绑定）",13))
	art_instance_anchor=OptionButton.new(); art_instance_inspector.add_child(art_instance_anchor)
	art_instance_anchor.item_selected.connect(func(_i): _mark_inspector_pending())
	_button(art_instance_inspector,"为此城关建立地点",func(): _guard_unapplied(func(): _create_site_anchor("city",true)))
	_button(art_instance_inspector,"定位所属地点",func():
		var instance: Dictionary=doc.find_art_instance(selected_art_id)
		_guard_unapplied(func(): _focus_site_anchor(str(instance.get("anchor_id","")))))
	art_group_toggle=CheckBox.new(); art_group_toggle.text="拖动与下方操作作用于整组"
	art_group_toggle.toggled.connect(func(value): canvas.art_group_mode=value; canvas.queue_redraw())
	art_instance_inspector.add_child(art_group_toggle)
	var group_actions:=HFlowContainer.new(); art_instance_inspector.add_child(group_actions)
	for pair in [["复制","duplicate"],["锁定","lock"],["解锁","unlock"],["删除","delete"]]:
		_button(group_actions,pair[0],func(): _run_art_group_action(pair[1]))
	var instance_actions := HBoxContainer.new()
	art_instance_inspector.add_child(instance_actions)
	_button(instance_actions, "应用部件外观", _apply_art_instance)
	_button(instance_actions, "擦除此件", func():
		if not doc.remove_art_instance(selected_art_id): _status("美术部件已锁定或未选择。"))
	art_instance_inspector.hide()
	art_pending_label=_label("",12)
	art_pending_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	right.add_child(art_pending_label)
	placement_panel=VBoxContainer.new()
	right.add_child(placement_panel)
	placement_panel.add_child(_label("接地与遮挡 · 仅美术占地",15))
	placement_depth=_spin(placement_panel,"前后微调（正数靠前）",-256,256,1)
	placement_width=_spin(placement_panel,"占地宽度倍率",.25,2,.05)
	placement_height=_spin(placement_panel,"占地深度倍率",.25,2,.05)
	placement_grounding=CheckBox.new(); placement_grounding.text="城市墙脚与地表衔接"
	placement_panel.add_child(placement_grounding)
	placement_overlap=CheckBox.new(); placement_overlap.text="允许占地重叠（山城等特例）"
	placement_panel.add_child(placement_overlap)
	_button(placement_panel,"应用接地与遮挡",_apply_placement)
	placement_panel.hide()
	for spin in [placement_depth,placement_width,placement_height,art_instance_scale,art_instance_opacity]:
		spin.value_changed.connect(func(_value): _mark_inspector_pending())
	for toggle in [placement_grounding,placement_overlap,art_instance_flip]:
		toggle.toggled.connect(func(_value): _mark_inspector_pending())
	for option in [art_instance_asset,art_instance_plane]:
		option.item_selected.connect(func(_i): _mark_inspector_pending())
	art_instance_group.text_changed.connect(func(_text): _mark_inspector_pending())
	inspector = VBoxContainer.new()
	inspector.add_theme_constant_override("separation",6)
	right.add_child(inspector)
	inspector.add_child(_label("所选对象",17))
	selected_name = _field(inspector,"名称")
	var actions := HBoxContainer.new()
	inspector.add_child(actions)
	_button(actions,"应用属性",apply_properties)
	_button(actions,"批量应用外观",_apply_batch_appearance)
	faction_panel=VBoxContainer.new();inspector.add_child(faction_panel)
	faction_panel.add_child(_label("州域势力",15))
	faction_name=_field(faction_panel,"势力名称（留空清除）")
	faction_color=ColorPickerButton.new();faction_color.color=Color("ba6253")
	faction_color.edit_alpha=false;faction_color.custom_minimum_size.y=32
	faction_panel.add_child(faction_color)
	_button(faction_panel,"应用势力到所选州",_apply_faction)
	faction_name.text_changed.connect(func(_text): _mark_inspector_pending())
	faction_color.color_changed.connect(func(_color): _mark_inspector_pending())
	faction_panel.hide()
	river_edit_button = _button(inspector,"编辑河道表现曲线 / 宽度",_show_river_visual_dialog)
	river_edit_button.tooltip_text = "只改水面外观；控制点、分段宽度和岸线样式须留在原水域内。"
	valley_edit_button = _button(inspector,"编辑谷道接近线 / 样式",_show_valley_visual_dialog)
	valley_edit_button.tooltip_text = "只改原谷道内的接近线；不会增加通路或改变门禁。"
	curve_canvas_button = _button(inspector,"在画布新建 / 调整表现线",_start_visual_curve)
	curve_canvas_button.tooltip_text = "水域或谷道不需要预置表现数据。点画水域线，拖控制点；Shift 加点，Alt 删点，Enter 保存，Esc 取消。"
	curve_width_row = HBoxContainer.new()
	inspector.add_child(curve_width_row)
	curve_width_spin = _spin(curve_width_row,"新点 / 当前点宽度",6,128,1)
	curve_width_spin.value = 12
	curve_width_spin.value_changed.connect(func(value):
		if canvas != null:
			canvas.visual_curve_default_width = value
			canvas.queue_redraw())
	_button(curve_width_row,"应用到当前水面点",func():
		if canvas.visual_curve_kind != "ribbon" or canvas.visual_curve_active_index < 0:
			_status("请先在画布选一个水面控制点。")
			return
		if canvas.set_visual_curve_width(canvas.visual_curve_active_index,curve_width_spin.value):
			if not canvas.commit_visual_curve(): _status("宽度未应用；请检查是否越出源水域。"))
	ridge_layout_row = HBoxContainer.new()
	inspector.add_child(ridge_layout_row)
	ridge_asset = OptionButton.new()
	for key in ArtCatalog.scatter_group("mountain"):
		if ArtCatalog.is_library_deleted(key): continue
		ridge_asset.add_item(ArtCatalog.label(key))
		ridge_asset.set_item_metadata(ridge_asset.item_count-1,key)
	ridge_layout_row.add_child(ridge_asset)
	ridge_spacing = _spin(ridge_layout_row,"间距",24,220,1)
	ridge_spacing.value = 65
	_button(ridge_layout_row,"按引导线局部重排",func():
		if ridge_asset.selected < 0: _status("没有可用的山体素材。")
		else:
			var result: Dictionary = doc.layout_ridge_guide(selected_id,str(ridge_asset.get_selected_metadata()),ridge_spacing.value)
			_status("已沿引导线放置 %d 件山体；%d 件手工锁定部件保留。" % [result.count,result.preserved] if result.ok else str(result.error)))
	pending_label = _label("", 12)
	inspector.add_child(pending_label)
	_button(actions,"删除所选",func():
		if not doc.remove_feature(selected_id): _status("无法删除：图层已锁定或关隘仍被通道引用；请先解除绑定。"))
	var order_actions := HBoxContainer.new()
	inspector.add_child(order_actions)
	_button(order_actions,"复制",func():
		var id: String = doc.duplicate_feature(selected_id)
		if not id.is_empty(): canvas.select_feature(id); _status("已复制对象；副本使用新 ID。")
		else: _status("无法复制：没有选择对象或其图层已锁定。"))
	_button(order_actions,"上移一层",func(): _move_selected(1)).tooltip_text = "在所属图层内移到上方"
	_button(order_actions,"下移一层",func(): _move_selected(-1)).tooltip_text = "在所属图层内移到下方"
	gate_open = CheckBox.new()
	gate_open.text = "关隘 / 渡口开放（预览）"
	inspector.add_child(gate_open)
	secret_route = CheckBox.new()
	secret_route.text = "通道需要发现"
	inspector.add_child(secret_route)
	selected_rule = OptionButton.new()
	for n in RULE_NAMES: selected_rule.add_item(n)
	inspector.add_child(selected_rule)
	selected_width = _spin(inspector,"线条 / 通道宽度",1,256,1)
	selected_scale = _spin(inspector,"城关 / 注记比例",0.25,4,0.25)
	inspector.add_child(_label("美术素材（应用属性后生效）",13))
	selected_art = OptionButton.new()
	inspector.add_child(selected_art)
	selected_art.item_selected.connect(func(_i): _refresh_art_preview())
	art_preview = TextureRect.new()
	art_preview.custom_minimum_size = Vector2(140,95)
	art_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	inspector.add_child(art_preview)
	art_density = _spin(inspector,"林木 / 山体密度",0.5,2,0.1)
	art_seed = _spin(inspector,"排列变化编号",0,999999,1)
	appearance_x = _spin(inspector, "图像偏移 X", -1024, 1024, 1)
	appearance_y = _spin(inspector, "图像偏移 Y", -1024, 1024, 1)
	width_factor = _spin(inspector, "图像宽度倍率", 0.5, 2, 0.05)
	label_x = _spin(inspector, "标签偏移 X", -1024, 1024, 1)
	label_y = _spin(inspector, "标签偏移 Y", -1024, 1024, 1)
	label_size = _spin(inspector, "标签字号", 8, 48, 1)
	appearance_visible = CheckBox.new()
	appearance_visible.text = "成图显示此对象"
	inspector.add_child(appearance_visible)
	label_visible = CheckBox.new()
	label_visible.text = "成图显示名称"
	inspector.add_child(label_visible)
	inspector.add_child(_label("通道绑定关隘 / 渡口",13))
	selected_gate = OptionButton.new()
	inspector.add_child(selected_gate)
	selected_note = _field(inspector,"用途 / 史料备注")
	domain_id = _field(inspector,"正式节点 ID（可留空）")
	site_panel=VBoxContainer.new();right.add_child(site_panel)
	site_panel.add_child(_label("地点身份与定位 · 独立于素材",16))
	site_info=_label("",12);site_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;site_panel.add_child(site_info)
	site_name=_field(site_panel,"地点名称")
	site_domain=_field(site_panel,"游戏地点 ID（无对应地点可留空）")
	site_x=_spin(site_panel,"地点 X",0,65536,.01);site_y=_spin(site_panel,"地点 Y",0,65536,.01)
	for field in [site_name,site_domain]:field.text_changed.connect(func(_value):_mark_inspector_pending())
	for spin in [site_x,site_y]:spin.value_changed.connect(func(_value):_mark_inspector_pending())
	_button(site_panel,"应用地点定位",apply_properties)
	_button(site_panel,"选择已绑定外观 / 替换素材",_select_site_art)
	_button(site_panel,"用当前城关素材添加外观",func():_guard_unapplied(_attach_site_art))
	var site_help:=_label("地点迁址在此修改 X/Y；拖动外观只改图像位置。\n暂无素材的关口可先保留定位。删除外观保留地点。",12)
	site_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;site_panel.add_child(site_help)
	for field in [selected_name,selected_note,domain_id]: field.text_changed.connect(func(_value): _mark_inspector_pending())
	for spin in [selected_width,selected_scale,art_density,art_seed,appearance_x,appearance_y,width_factor,label_x,label_y,label_size]: spin.value_changed.connect(func(_value): _mark_inspector_pending())
	for option in [selected_rule,selected_art,selected_gate]: option.item_selected.connect(func(_value): _mark_inspector_pending())
	for toggle in [gate_open,secret_route,appearance_visible,label_visible]: toggle.toggled.connect(func(_value): _mark_inspector_pending())
	var foot := _label("选择模式可拖动对象或顶点。\n图层隐藏只影响显示，不改变通行。\n通道须显式绘制；城池没有阻路光环。",12)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(foot)
	# Context properties precede browsing, layers and the overview.
	right.move_child(inspector,0)
	right.move_child(art_instance_inspector,1)
	right.move_child(site_panel,0)
	right.move_child(art_pending_label,2)
	right.move_child(placement_panel,3)
	var object_heading: Node=right.get_child(object_search.get_index()-1)
	var locate_button: Node=right.get_child(object_list.get_index()+1)
	var browse: Array=[object_heading,object_search,object_list,locate_button]
	for i in range(browse.size()):right.move_child(browse[i],4+i)
	right.move_child(minimap,right.get_child_count()-1)
	var advanced_fields: Array=[]
	for child in inspector.get_children():
		if child.get_index()>=gate_open.get_index(): advanced_fields.append(child)
	var advanced:=_section(inspector,"更多属性 · 外观 / 通行 / 绑定",false)
	for child in advanced_fields: child.reparent(advanced)
	status = _label("准备就绪",13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	floating_layer = Control.new()
	floating_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floating_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floating_layer)
	for panel in [tools_panel,properties_panel]:
		panel.float_requested.connect(func(): _float_panel(panel))
		panel.dock_requested.connect(func(): _dock_panel(panel))
		panel.close_requested.connect(func(): panel.hide(); _schedule_layout_save())
		panel.layout_changed.connect(_schedule_layout_save)
	resized.connect(_constrain_floating_panels)
	layout_timer = Timer.new()
	layout_timer.one_shot = true
	layout_timer.wait_time = 0.4
	layout_timer.timeout.connect(_save_layout)
	add_child(layout_timer)
	outer_split.dragged.connect(func(_offset): _schedule_layout_save())
	inner_split.dragged.connect(func(_offset): _schedule_layout_save())
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.wrap_controls = false
	file_dialog.unresizable = false
	file_dialog.borderless = false
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	confirm = DialogShell.new()
	confirm.title = "当前地图尚未保存"
	confirm.dialog_text = "继续会替换当前编辑内容。请先取消并保存，或确认继续。"
	confirm.confirmed.connect(func():
		var action := pending
		pending = Callable()
		if action.is_valid(): action.call())
	confirm.canceled.connect(func(): pending = Callable())
	add_child(confirm)
	settings_panel = SettingsPanel.new()
	settings_panel.reported.connect(_status)
	settings_panel.reference_selected.connect(func(id): canvas.active_reference=id)
	settings_panel.reference_import_requested.connect(func(): _choose_file("background"))
	add_child(settings_panel)
	production_panel = ProductionPanel.new()
	add_child(production_panel)
	doc.changed.connect(_schedule_refresh)
	if restore_last_map_on_start: _load_startup_map()
	else: _load_sample()
	# Opening an untouched document must not overwrite an earlier recovery draft.
	autosave_signature = JSON.stringify(doc.data)
	autosave_timer = Timer.new()
	autosave_timer.wait_time = 30
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(_autosave)
	add_child(autosave_timer)
	get_tree().process_frame.connect(_finish_ready_layout, CONNECT_ONE_SHOT)

func _finish_ready_layout() -> void:
	if not is_inside_tree(): return
	reset_layout(false)
	_restore_layout()
	get_tree().process_frame.connect(_finish_ready_fit, CONNECT_ONE_SHOT)

func _finish_ready_fit() -> void:
	if not is_inside_tree(): return
	canvas.fit_map()
	if not Engine.is_editor_hint(): initial_fit_done = true

func activate_workspace() -> void:
	if initial_fit_done or workspace_activation_pending or not is_inside_tree(): return
	# The editor's VBox sorts after switching main screens; defer the first fit until it has real space.
	workspace_activation_pending = true
	get_tree().process_frame.connect(_activate_workspace_second_frame, CONNECT_ONE_SHOT)

func _activate_workspace_second_frame() -> void:
	if not is_inside_tree(): return
	get_tree().process_frame.connect(_finish_workspace_activation, CONNECT_ONE_SHOT)

func _finish_workspace_activation() -> void:
	workspace_activation_pending = false
	if not is_visible_in_tree(): return
	canvas.fit_map()
	initial_fit_done = true

const UI_FONT_SIZE := 16

func _build_theme() -> void:
	var skin := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC"])
	skin.default_font = font
	skin.default_font_size = UI_FONT_SIZE
	for key in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("354440") if key == "normal" else Color("526455")
		style.set_corner_radius_all(4)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		skin.set_stylebox(key,"Button",style)
		if key != "focus": skin.set_stylebox(key,"OptionButton",style)
	skin.set_color("font_color","Label",Color("e7dfc8"))
	theme = skin
	var backdrop := ColorRect.new()
	backdrop.color = Color("1c2727")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

func _float_panel(panel) -> void:
	if panel.floating: return
	var origin: Vector2 = panel.global_position-floating_layer.global_position
	var extent: Vector2 = panel.size
	panel.reparent(floating_layer,false)
	panel.parent_bounds = floating_layer
	panel.set_floating(true)
	panel.size = Vector2(maxf(extent.x,230 if panel == tools_panel else 320),minf(extent.y,600))
	panel.position = origin
	panel.fit_inside()
	_schedule_layout_save()

func _dock_panel(panel) -> void:
	if not panel.floating: return
	panel.dragging = false
	panel.resizing = false
	panel.set_floating(false)
	if panel == tools_panel:
		panel.reparent(outer_split,false)
		outer_split.move_child(panel,0)
	else: panel.reparent(inner_split,false)
	panel.parent_bounds = null
	_schedule_layout_save()

func reset_layout(persist: bool = true) -> void:
	if not is_instance_valid(outer_split): return
	for panel in [tools_panel,properties_panel]:
		_dock_panel(panel)
		panel.show()
	outer_split.split_offset = 16
	inner_split.split_offset = -16
	_fit_after_layout()
	if persist: _schedule_layout_save()

func _fit_after_layout() -> void:
	if layout_fit_pending or not is_inside_tree(): return
	layout_fit_pending = true
	get_tree().process_frame.connect(_fit_after_layout_second_frame, CONNECT_ONE_SHOT)

func _fit_after_layout_second_frame() -> void:
	if not is_inside_tree(): return
	get_tree().process_frame.connect(_finish_fit_after_layout, CONNECT_ONE_SHOT)

func _finish_fit_after_layout() -> void:
	layout_fit_pending = false
	if is_inside_tree(): canvas.fit_map()

func _constrain_floating_panels() -> void:
	for panel in [tools_panel,properties_panel]:
		if is_instance_valid(panel) and panel.floating: panel.fit_inside.call_deferred()

func _schedule_layout_save() -> void:
	if layout_persistence_enabled and is_instance_valid(layout_timer): layout_timer.start()

func _save_layout() -> void:
	if not layout_persistence_enabled or not is_instance_valid(outer_split): return
	var config := ConfigFile.new()
	config.set_value("layout","left_split",outer_split.split_offset)
	config.set_value("layout","right_split",inner_split.split_offset)
	for key in ["tools","properties"]:
		var panel = tools_panel if key == "tools" else properties_panel
		config.set_value(key,"floating",panel.floating)
		config.set_value(key,"visible",panel.visible)
		config.set_value(key,"position",panel.position/size.max(Vector2.ONE))
		config.set_value(key,"size",panel.size)
	var error := config.save(layout_file_path)
	if error != OK: _status("工作区布局保存失败；地图内容不受影响。")

func _restore_layout() -> void:
	if not layout_persistence_enabled: return
	var config := ConfigFile.new()
	if config.load(layout_file_path) != OK: return
	for pair in [["left_split",outer_split],["right_split",inner_split]]:
		var offset: Variant = config.get_value("layout",pair[0],0)
		if offset is int: pair[1].split_offset = clampi(offset,-int(size.x),int(size.x))
	for key in ["tools","properties"]:
		var panel = tools_panel if key == "tools" else properties_panel
		if config.get_value(key,"floating",false) == true:
			_float_panel(panel)
			var point: Variant = config.get_value(key,"position",Vector2(0.1,0.1))
			var extent: Variant = config.get_value(key,"size",Vector2(320,500))
			if point is Vector2 and point.is_finite(): panel.position = point*size
			if extent is Vector2 and extent.is_finite(): panel.size = extent
			panel.fit_inside()
		panel.visible = config.get_value(key,"visible",true) != false

func _label(text: String, size_px := UI_FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",maxi(UI_FONT_SIZE,size_px))
	return l

func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _field(parent: Node, caption: String) -> LineEdit:
	parent.add_child(_label(caption,13))
	var line := LineEdit.new()
	parent.add_child(line)
	return line

func _spin(parent: Node, caption: String, minimum: float, maximum: float, increment: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(caption,13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = increment
	row.add_child(spin)
	return spin

func _art_sample_index() -> Dictionary:
	var path := "res://addons/strategic_map_editor/art_samples.json"
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not index is Dictionary or not index.get("samples") is Array:
		_status("样区目录缺失或损坏。")
		return {}
	var ids: Array = []
	for entry in index.samples:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String or not entry.get("path") is String or ids.has(entry.id):
			_status("样区目录项目无效或编号重复。")
			return {}
		ids.append(entry.id)
	if index.get("default_id") not in ids:
		_status("样区目录未指定有效对照底稿。")
		return {}
	return index

func _show_art_samples() -> void:
	var index := _art_sample_index()
	if index.is_empty(): return
	var dialog := DialogShell.new()
	dialog.title = "样区与历史 · 状态以审图结论为准"
	dialog.ok_button_text = "打开制作副本"
	add_child(dialog)
	var heading := _label("源码版只提供空白画布，不包含历史地图或美术样区。打开后首次保存会另存。",13)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.content.add_child(heading)
	var picker := OptionButton.new()
	picker.name = "ArtSamplePicker"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.content.add_child(picker)
	for entry in index.samples:
		picker.add_item(entry.title)
		picker.set_item_metadata(picker.item_count-1, entry)
		if entry.id == index.default_id: picker.select(picker.item_count-1)
	var details := _label("",14)
	details.name = "ArtSampleDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.content.add_child(details)
	var update_details := func(_i = 0):
		var entry: Dictionary = picker.get_selected_metadata()
		details.text = entry.title + "\n\n" + str(entry.get("note",""))
	picker.item_selected.connect(update_details)
	update_details.call()
	dialog.confirmed.connect(func():
		var id: String = picker.get_selected_metadata().id
		dialog.queue_free()
		_guard(func(): _load_art_sample_id(id)))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(660,380))

func _load_art_sample_id(id: String) -> void:
	var index := _art_sample_index()
	if index.is_empty(): return
	for entry in index.samples:
		if entry.id != id: continue
		var error: String = doc.load_file(entry.path)
		if not error.is_empty(): _status(error); return
		# Open a working copy; preserve the bundled source and its resource fingerprint.
		doc.current_path = ""
		if entry.get("status","")=="accepted": doc.configure_canvas(entry.title.replace("（已通过）",""),Vector2i(doc.data.canvas_size[0],doc.data.canvas_size[1]),false)
		canvas.zoom = minf(canvas.size.x/840.0,canvas.size.y/520.0)
		canvas.center_on(Vector2(8947.759765625,4930.599609375))
		rules_toggle.button_pressed = false
		canvas.view_mode = "art"
		canvas.visual_issues.clear()
		canvas.select_art_instance("")
		canvas.select_feature(str(entry.get("selected_feature","")))
		if entry.get("focus_selected",false): canvas.locate_feature(str(entry.get("selected_feature","")))
		if entry.has("selected_instance"): canvas.select_art_instance(entry.selected_instance)
		if entry.get("fit_map",false): canvas.fit_map()
		_status("已打开 " + entry.title + "；首次保存将另存。" + str(entry.get("note","")))
		return
	_status("样区目录中不存在该版本：" + id)

# Keep existing automation entry points while using one catalog and load path.
func _load_art_sample() -> void:
	_load_art_sample_id("v060")

func _load_art_candidate() -> void:
	_load_art_sample_id("v061")

func _load_art_candidate_v063() -> void:
	_load_art_sample_id("v063")

func _load_art_candidate_v064() -> void:
	_load_art_sample_id("v064")

func _load_art_candidate_v065() -> void:
	_load_art_sample_id("v065")

func _load_art_candidate_v072() -> void:
	_load_art_sample_id("v072")

func _load_art_candidate_v074() -> void:
	_load_art_sample_id("v074")

func _load_art_candidate_v075() -> void:
	_load_art_sample_id("v075")

func _load_art_candidate_v077() -> void:
	_load_art_sample_id("v077")

func _load_art_candidate_v081() -> void:
	_load_art_sample_id("v081")

func _show_art_bundle_comparison() -> void:
	var error: String = canvas.art.reload()
	if not error.is_empty(): _status("素材重载失败：" + error); return
	_fill_brush_picker()
	art_instance_asset.clear()
	for key in ArtCatalog.library_keys():
		art_instance_asset.add_item(ArtCatalog.label(key))
		art_instance_asset.set_item_metadata(art_instance_asset.item_count-1,key)
	_refresh()
	canvas.queue_redraw()
	var recorded: Dictionary = doc.data.get("presentation",{}).get("bundle",{})
	var current: Dictionary = ArtCatalog.bundle_info(str(recorded.get("id", "tongguan_v1")))
	var differences: Array = ArtCatalog.bundle_differences(recorded)
	if differences.is_empty():
		_status("素材包已重载；地图记录与当前包一致。" if not recorded.is_empty() else "素材包已重载；此旧地图尚未固定素材版本。")
		return
	var dialog := DialogShell.new()
	dialog.title = "素材包对照 · 地图引用与当前安装"
	dialog.ok_button_text = "使用当前包并记录版本"
	add_child(dialog)
	dialog.content.add_child(_label("原素材图片未随地图归档时无法自动显示旧画面。请核对下列哈希差异及当前缩略图；确认会留下可撤销的文档修改。",13))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(580,170)
	dialog.content.add_child(list)
	for diff in differences:
		var previous: String = str(recorded.get("asset_hashes",{}).get(diff.file,recorded.get("catalog_sha256","")))
		var now: String = str(current.asset_hashes.get(diff.file,current.catalog_sha256))
		list.add_item("%s · %s  %s → %s" % [diff.file,diff.reason,previous.substr(0,10),now.substr(0,10)])
	var shown: Dictionary = {}
	for diff in differences:
		if shown.size() >= 4: break
		for key in ArtCatalog.catalog().get("assets",{}):
			if ArtCatalog.descriptor(key).atlas != diff.file: continue
			if shown.has(diff.file): break
			shown[diff.file] = true
			dialog.content.add_child(_label("当前：" + ArtCatalog.label(key),12))
			var preview := TextureRect.new()
			preview.custom_minimum_size = Vector2(180,85)
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.texture = canvas.art.texture(key)
			dialog.content.add_child(preview)
			break
	dialog.confirmed.connect(func():
		if doc.set_art_style("tongguan_v1"): _status("地图已记录当前素材包版本；可撤销并重新检查导出。")
		else: _status("素材包引用没有变化，或文档更新失败。")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(650,560))

func _show_art_import(path: String) -> void:
	var inspected: Dictionary = ArtImporter.probe(path)
	if not inspected.ok:
		_status("导入未开始：" + str(inspected.error))
		var failure := DialogShell.new()
		failure.title = "透明部件检查未通过"
		failure.ok_button_text = "重新选择 PNG"
		failure.cancel_button_text = "关闭"
		failure.dialog_text = "文件：%s\n\n%s\n\n通过图片检查后才会打开“校验并导入素材包”页面。请检查图片尺寸和透明边缘后重试。" % [path, inspected.error]
		add_child(failure)
		failure.confirmed.connect(func():
			failure.queue_free()
			_choose_file.call_deferred("art_png"))
		failure.canceled.connect(failure.queue_free)
		failure.popup_centered(Vector2i(590,320))
		return
	var dialog := DialogShell.new()
	dialog.title = "导入离线美术部件"
	dialog.ok_button_text = "校验并导入素材包"
	add_child(dialog)
	dialog.content.add_child(_label("仅加入手工放置的表现素材。现有地图会显示资源版本差异，地理和通行不变。",13))
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(270,150)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = ImageTexture.create_from_image(inspected.image)
	dialog.content.add_child(preview)
	dialog.content.add_child(_label("%d × %d 像素 · SHA-256 %s…" % [inspected.width,inspected.height,str(inspected.sha256).substr(0,12)],12))
	var id_field := _field(dialog.content,"资源 ID（英文小写与下划线）")
	id_field.text = ArtImporter.suggest_id(path,ArtCatalog.catalog().get("assets",{}))
	var name_field := _field(dialog.content,"素材名称")
	name_field.text = path.get_file().get_basename()
	dialog.content.add_child(_label("部件类别",13))
	var group_picker := OptionButton.new()
	for pair in [["forest","树木"],["mountain","山体"],["ground","地表"],["city","城池"],["pass","关隘"]]:
		group_picker.add_item(pair[1])
		group_picker.set_item_metadata(group_picker.item_count-1,pair[0])
	dialog.content.add_child(group_picker)
	var visual_width := _spin(dialog.content,"地图上基宽",4,512,1)
	visual_width.value = 80
	var anchor_x := _spin(dialog.content,"落点 X（0–1）",0,1,.05)
	anchor_x.value = .5
	var anchor_y := _spin(dialog.content,"落点 Y（0–1）",0,1,.05)
	anchor_y.value = .78
	var gate_x := _spin(dialog.content,"门口 X（城关，0–1）",0,1,.05)
	gate_x.value = .5
	var gate_y := _spin(dialog.content,"门口 Y（城关，0–1）",0,1,.05)
	gate_y.value = .78
	gate_x.get_parent().hide()
	gate_y.get_parent().hide()
	group_picker.item_selected.connect(func(index):
		var is_site: bool = group_picker.get_item_metadata(index) in ["city","pass"]
		gate_x.get_parent().visible = is_site
		gate_y.get_parent().visible = is_site)
	dialog.confirmed.connect(func():
		var group: String = group_picker.get_item_metadata(group_picker.selected)
		var result: Dictionary = ArtImporter.install(ProjectSettings.globalize_path(ArtCatalog.ROOT),path,id_field.text,name_field.text,group,visual_width.value,Vector2(anchor_x.value,anchor_y.value),Vector2(gate_x.value,gate_y.value))
		if not result.ok:
			_status("导入失败：" + result.error)
			dialog.popup_centered.call_deferred(Vector2i(590,650))
			return
		_status("已导入 %s；请查看素材包差异后再决定地图是否改用新版本。" % result.id)
		dialog.queue_free()
		_show_art_bundle_comparison.call_deferred())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(590,650))

func _refresh_art_preview() -> void:
	if selected_art.selected < 0: return
	if not canvas.has_art(): art_preview.texture = null; return
	var key: String = selected_art.get_item_metadata(selected_art.selected)
	var f: Dictionary = doc.find_feature(selected_id)
	if f.is_empty(): return
	if key == "auto":
		f = f.duplicate(true)
		f.erase("visual")
		key = ArtCatalog.site_variant(f) if f.kind in ["city","pass"] else str(ArtCatalog.group(f.kind).front()) if not ArtCatalog.group(f.kind).is_empty() else ""
	art_preview.texture = canvas.art.texture(key) if not key.is_empty() else null

func _fill_brush_picker() -> void:
	if brush_picker == null: return
	var active: String=canvas.brush_asset if canvas!=null else "mixed_forest"
	if ArtCatalog.is_library_deleted(active):
		active="mixed_forest"
		if canvas!=null:
			canvas.brush_asset=active
			if canvas.tool in ["art_stamp","art_place"]: canvas.set_tool("art_select")
	if canvas!=null:
		brush_bundle_id=canvas.art.bundle_id
		var resource: String="tree_grove" if active=="mixed_forest" else active
		if not ArtCatalog.bundle_contains(brush_bundle_id,ArtCatalog.asset_bundle(resource)):
			active="tree_broad"; canvas.brush_asset=active
			_status("新地图资源包不含上一个画笔，已切回阔冠老树。")
	brush_picker.clear()
	if brush_filter.selected in [0,1]:
		brush_picker.add_item("混合林缘 · 可编辑预设")
		brush_picker.set_item_metadata(brush_picker.item_count-1, "mixed_forest")
	for key in ArtCatalog.library_keys():
		if canvas!=null and not ArtCatalog.bundle_contains(canvas.art.bundle_id,ArtCatalog.asset_bundle(key)): continue
		var item: Dictionary = ArtCatalog.descriptor(key)
		var group: String = item.get("group", "")
		if brush_filter.selected == 1 and group != "forest": continue
		if brush_filter.selected == 2 and group != "mountain": continue
		if brush_filter.selected == 3 and group not in ["city", "pass"]: continue
		if brush_filter.selected == 4 and group != "ground": continue
		brush_picker.add_item(ArtCatalog.label(key))
		brush_picker.set_item_metadata(brush_picker.item_count-1, key)
	brush_picker.select(-1)
	for i in range(brush_picker.item_count):
		if brush_picker.get_item_metadata(i)==active: brush_picker.select(i); break
	if canvas!=null and brush_preview.visible: brush_preview.texture=canvas.art.texture("tree_grove" if active=="mixed_forest" else active)
	_refresh_asset_grid()

func _refresh_asset_grid() -> void:
	if asset_grid == null or canvas == null: return
	asset_grid.library=canvas.art
	var query := asset_query.text.strip_edges().to_lower()
	var rows: Array=[]
	for i in range(brush_picker.item_count):
		var key: String=brush_picker.get_item_metadata(i)
		var label:=brush_picker.get_item_text(i)
		if query.is_empty() or (label+" "+key).to_lower().contains(query): rows.append([key,label])
	var signature: Array=[ArtCatalog.generation,canvas.art.bundle_id,rows]
	if signature != asset_grid_signature:
		asset_grid_signature=signature
		asset_grid.clear()
		for row in rows:
			var index:=asset_grid.add_item(row[1])
			asset_grid.set_item_metadata(index,row[0])
			asset_grid.set_item_tooltip(index,row[1]+"\n单击选中，然后在地图上左键点放。")
		asset_grid.refresh_icons()
	asset_grid.deselect_all()
	for i in asset_grid.item_count:
		if asset_grid.get_item_metadata(i)==canvas.brush_asset: asset_grid.select(i); break

func _set_brush_asset() -> void:
	if brush_picker.selected < 0 or canvas == null: return
	_choose_browser_asset(str(brush_picker.get_item_metadata(brush_picker.selected)))

func _remember_art_asset(key: String) -> void:
	recent_art_assets.erase(key); recent_art_assets.push_front(key)
	if recent_art_assets.size()>12: recent_art_assets.resize(12)

func _choose_browser_asset(key: String, remember: bool = true) -> void:
	if ArtCatalog.is_library_deleted(key):
		_status("该素材已从素材库删除，请先在素材浏览的“已删除”中恢复。"); return
	var resource: String="tree_grove" if key=="mixed_forest" else key
	if ArtCatalog.descriptor(resource).is_empty() or not ArtCatalog.bundle_contains(canvas.art.bundle_id,ArtCatalog.asset_bundle(resource)):
		_status("当前地图资源包不包含该素材，画笔保持不变。"); return
	var apply := func():
		if remember:
			_refresh()
			_prepare_art_placement()
		canvas.brush_asset=key
		var in_filter := false
		for i in range(brush_picker.item_count):
			if brush_picker.get_item_metadata(i)==key: in_filter=true; break
		if not in_filter: brush_filter.select(0)
		_fill_brush_picker()
		if remember:
			_remember_art_asset(key)
			canvas.set_tool("art_stamp")
			_status("已选“"+("混合林缘" if key=="mixed_forest" else ArtCatalog.label(key))+"”：地图左键每次放一件；右键 / Esc 退出后可拖动。")
		canvas.queue_redraw()
	if remember:
		_guard_unapplied(apply)
		# Keep the visible selection truthful if the pending-input guard was canceled.
		_fill_brush_picker()
	else: apply.call()

func _prepare_art_placement() -> void:
	canvas.view_mode = "art"
	view_picker.select(0)
	if doc.data.get("art_style","schematic") != "tongguan_v1": doc.set_art_style("tongguan_v1")
	canvas.art.ensure_loaded()

func _show_asset_browser() -> void:
	var browser:=AssetBrowser.new()
	browser.library=canvas.art; browser.bundle_id=canvas.art.bundle_id
	browser.recent_assets=recent_art_assets.duplicate(); browser.active_asset=canvas.brush_asset
	browser.asset_chosen.connect(_choose_browser_asset)
	browser.library_changed.connect(_library_changed)
	add_child(browser); browser.popup_centered(Vector2i(720,570))

func _library_changed(key: String, deleted: bool) -> void:
	if deleted: recent_art_assets.erase(key)
	_fill_brush_picker()
	# Preserve unapplied inspector values while updating selectable resources.
	_sync_library_options(art_instance_asset, ArtCatalog.library_keys(), str(doc.find_art_instance(selected_art_id).get("asset", "")))
	_sync_library_options(ridge_asset, ArtCatalog.scatter_group("mountain").filter(func(id): return not ArtCatalog.is_library_deleted(id)), "", false)
	var feature: Dictionary = doc.find_feature(selected_id)
	if not feature.is_empty():
		_sync_library_options(selected_art, ArtCatalog.variants(feature.kind).filter(func(id): return not ArtCatalog.is_library_deleted(id)), str(feature.get("visual",{}).get("variant","auto")))
	_status("已从素材库删除；已有地图保留，可在“已删除”中恢复。" if deleted else "素材已恢复到素材库。")

func _sync_library_options(picker: OptionButton, keys: Array, current: String = "", retain_pending: bool = true) -> void:
	var previous: String = str(picker.get_selected_metadata()) if picker.selected>=0 else ""
	var choices: Array = keys.duplicate()
	# An existing or pending reference may be retained but cannot be newly chosen.
	for retained in [current, previous if retain_pending else ""]:
		if not retained.is_empty() and ArtCatalog.is_library_deleted(retained) and retained not in choices: choices.append(retained)
	var signature: Array = [ArtCatalog.generation, choices]
	if picker.get_meta("library_options", []) == signature: return
	picker.set_meta("library_options", signature)
	picker.clear()
	for id in choices:
		picker.add_item(ArtCatalog.label(id)+("（已从素材库删除）" if ArtCatalog.is_library_deleted(id) else ""))
		picker.set_item_metadata(picker.item_count-1,id)
		picker.set_item_disabled(picker.item_count-1,ArtCatalog.is_library_deleted(id))
		if id==previous: picker.select(picker.item_count-1)

func _run_art_group_action(action: String) -> void:
	if _art_inspector_pending() or _placement_pending(): _status("请先应用部件外观和接地输入；本次操作未执行。"); return
	var result: Dictionary=doc.edit_art_group(selected_art_id,art_group_toggle.button_pressed,action,Vector2(20,20))
	if not result.ok: _status(result.error); return
	if action=="duplicate": canvas.select_art_instance(result.ids[0])
	elif action=="delete": canvas.select_art_instance("")
	_status("已处理 %d 件美术部件，可一次撤销。" % result.count)

func _show_art_instances() -> void:
	var dialog:=DialogShell.new(); dialog.title="已放置部件 · 含遮挡与锁定部件"; dialog.ok_button_text="选择并定位"
	add_child(dialog)
	var query:=_field(dialog.content,"搜索名称、组名或 ID")
	var list:=ItemList.new(); list.custom_minimum_size=Vector2(550,330); dialog.content.add_child(list)
	var fill:=func(_text: String = ""):
		list.clear()
		for item in doc.data.presentation.instances:
			var label: String=ArtCatalog.label(item.asset)+(" [锁定]" if item.locked else "")+" · "+item.group_id+" · "+item.id
			if not query.text.strip_edges().is_empty() and not label.to_lower().contains(query.text.strip_edges().to_lower()): continue
			var i:=list.add_item(label); list.set_item_metadata(i,item.id); list.set_item_tooltip(i,label)
			if item.id==selected_art_id: list.select(i)
		if list.get_selected_items().is_empty() and list.item_count>0: list.select(0)
		dialog.get_ok_button().disabled=list.item_count==0
	query.text_changed.connect(fill); fill.call()
	var choose:=func():
		if list.get_selected_items().is_empty(): return
		var id: String=list.get_item_metadata(list.get_selected_items()[0])
		dialog.queue_free()
		_guard_unapplied(func():
			var item: Dictionary=doc.find_art_instance(id)
			if item.is_empty(): _status("该部件已移除。"); return
			canvas.set_tool("art_select"); canvas.select_art_instance(id)
			canvas.zoom=clampf(canvas.zoom,1,3)
			canvas.center_on(Vector2(item.position[0],item.position[1]))
			properties_panel.body_scroll.ensure_control_visible(art_instance_inspector))
	dialog.confirmed.connect(choose); list.item_activated.connect(func(_i): choose.call())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(730,540))

func _focus_site_anchor(id: String) -> void:
	var f: Dictionary=doc.find_feature(id)
	if f.is_empty():_status("当前外观尚未绑定地点。");return
	canvas.show_site_anchors=true;canvas.set_tool("select");canvas.select_feature(id)
	canvas.zoom=clampf(canvas.zoom,.8,2.0);canvas.center_on(Vector2(f.points[0][0],f.points[0][1]))
	properties_panel.body_scroll.ensure_control_visible(site_panel)

func _create_site_anchor(kind: String, from_art: bool=false) -> void:
	var position: Vector2=(canvas.size*.5-canvas.pan)/canvas.zoom
	position=position.clamp(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1]))
	var title:="新关口" if kind=="pass" else "新地点"
	var art_id:=""
	if from_art:
		var item: Dictionary=doc.find_art_instance(selected_art_id)
		if item.is_empty() or not Doc.site_art_compatible(item.asset):_status("请先选中城关素材或手动导入的地点图片。");return
		if not item.get("anchor_id","").is_empty():_focus_site_anchor(item.anchor_id);return
		art_id=item.id;position=Vector2(item.position[0],item.position[1]);title=item.group_id.trim_prefix("州城:")
		if title.is_empty():title="新地点"
		if ArtCatalog.descriptor(item.asset).get("group","")=="pass":kind="pass"
	var id: String=doc.create_site_anchor(title,kind,position,"",art_id)
	if id.is_empty():_status("创建失败：地点图层或部件已锁定。");return
	_focus_site_anchor(id);_status("已建立独立地点；可编辑名称、坐标和游戏 ID，之后再换外观。")

func _attach_site_art() -> void:
	var id: String=doc.attach_site_art(selected_id,canvas.brush_asset,canvas.brush_scale)
	if id.is_empty():_status("请先选一件城池 / 关口素材，再选中地点添加外观。");return
	canvas.set_tool("art_select");canvas.select_art_instance(id)
	_status("外观已放在地点位置；更换素材和删除外观都保留地点。")

func _select_site_art() -> void:
	var anchor_id:=selected_id
	_guard_unapplied(func():
		for item in doc.data.presentation.instances:
			if item.get("anchor_id","")==anchor_id:
				canvas.set_tool("art_select");canvas.select_art_instance(item.id)
				canvas.center_on(Vector2(item.position[0],item.position[1]));return
		_status("此地点暂无外观；选择城关素材后可在地点面板添加。"))

func _show_site_anchors() -> void:
	var dialog:=DialogShell.new();dialog.title="地点与关口 · 身份独立于外观";dialog.ok_button_text="选择并定位";add_child(dialog)
	var query:=_field(dialog.content,"搜索名称、地点 ID 或游戏 ID")
	var list:=ItemList.new();list.custom_minimum_size=Vector2(550,330);dialog.content.add_child(list)
	var fill:=func(_text: String=""):
		list.clear()
		for f in doc.data.features:
			if not f.get("visual",{}).get("anchor_only",false):continue
			var count:=0
			for item in doc.data.presentation.instances:
				if item.get("anchor_id","")==f.id:count+=1
			var label: String=f.name+" · "+Doc.NAMES[f.kind]+(" · 暂无外观" if count==0 else " · %d 件外观"%count)+" · "+(f.domain_id if not f.domain_id.is_empty() else "待接入游戏")
			if not query.text.strip_edges().is_empty() and not (label+f.id).to_lower().contains(query.text.strip_edges().to_lower()):continue
			var index:=list.add_item(label);list.set_item_metadata(index,f.id)
		if list.item_count>0:list.select(0)
		dialog.get_ok_button().disabled=list.item_count==0
	query.text_changed.connect(fill);fill.call()
	var choose:=func():
		if list.get_selected_items().is_empty():return
		var id: String=list.get_item_metadata(list.get_selected_items()[0]);dialog.queue_free()
		_guard_unapplied(func():_focus_site_anchor(id))
	dialog.confirmed.connect(choose);list.item_activated.connect(func(_i):choose.call())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(750,530))

func _load_sample() -> void:
	doc.replace_document(Doc.tongguan_sample())
	canvas.start_point = Vector2(250,430)
	canvas.end_point = Vector2(1330,430)
	canvas.select_feature("tongguan")
	canvas.fit_map()
	_status("已载入潼关结构示例。关闭右侧“关隘开放”并应用，然后检查通行。")

func _select(id: String) -> void:
	if id != selected_id and _inspector_pending(): _status("上一对象有未应用的属性输入；切换选择后已丢弃。")
	selected_id = id
	if not id.is_empty() and not selected_art_id.is_empty(): canvas.select_art_instance("")
	_refresh()

func _select_art(id: String) -> void:
	if not id.is_empty() and _inspector_pending(): _status("上一对象有未应用的属性输入；切换选择后已丢弃。")
	selected_art_id = id
	if not id.is_empty() and not selected_id.is_empty(): canvas.select_feature("")
	_refresh()

func _schedule_refresh() -> void:
	_invalidate_preview()
	if refresh_queued: return
	refresh_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	refresh_queued = false
	if not is_instance_valid(title_label): return
	refreshing_inspector = true
	if canvas.art.bundle_id!=brush_bundle_id: _fill_brush_picker()
	depth_sort_toggle.set_pressed_no_signal(doc.data.presentation.get("depth_sort",false))
	art_style.select(ArtCatalog.STYLES.find(doc.data.get("art_style","schematic")))
	title_label.text = ("● " if doc.is_dirty() else "") + ("游戏主地图 · " if GameMapPublisher.same_path(doc.current_path,game_map_path) else "") + doc.data.title
	if game_map_status!=null and _game_map_label_path!=doc.current_path:
		_game_map_label_path=doc.current_path
		if not game_map_publisher.busy:
			game_map_status.text="正在编辑游戏主地图；保存后自动更新游戏，加速数据在后台生成。" if GameMapPublisher.same_path(doc.current_path,game_map_path) else "独立样区；若要用于游戏，在“更多工具”中选择“设为游戏主地图”。"
	if refreshed_layers != doc.data.layers:
		refreshed_layers=doc.data.layers.duplicate(true)
		for child in layer_box.get_children():
			layer_box.remove_child(child)
			child.queue_free()
		var ordered_layers: Array = doc.data.layers.duplicate()
		ordered_layers.reverse()
		for layer in ordered_layers:
			var row := HBoxContainer.new()
			layer_box.add_child(row)
			var show := CheckBox.new()
			show.text = LAYER_NAMES[layer.id]
			show.button_pressed = layer.visible
			show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			show.toggled.connect(func(v): doc.set_layer(layer.id,"visible",v))
			row.add_child(show)
			var lock := CheckBox.new()
			lock.text = "锁"
			lock.button_pressed = layer.locked
			lock.toggled.connect(func(v): doc.set_layer(layer.id,"locked",v))
			row.add_child(lock)
			_button(row,"↑",func(): doc.move_layer(layer.id,1)).tooltip_text = "图层移到上方；列表上方覆盖下方"
			_button(row,"↓",func(): doc.move_layer(layer.id,-1)).tooltip_text = "图层移到下方"
	if refreshed_geometry!=canvas.geometry_revision:
		refreshed_geometry=canvas.geometry_revision
		refreshed_features=doc.data.features
		_refresh_objects()
	else:
		object_list.deselect_all()
		for i in range(object_list.item_count):
			if object_list.get_item_metadata(i) in canvas.selection_ids: object_list.select(i,false)
	minimap.queue_redraw()
	var f: Dictionary = doc.find_feature(selected_id)
	var instance: Dictionary = doc.find_art_instance(selected_art_id)
	var is_anchor: bool=f.get("visual",{}).get("anchor_only",false)
	site_panel.visible=is_anchor
	if is_anchor:
		site_name.text=f.name;site_domain.text=f.domain_id;site_x.value=f.points[0][0];site_y.value=f.points[0][1]
		site_info.text="地点 ID："+f.id+"\n"+str(f.get("note",""))
	placement_panel.visible=not instance.is_empty() or (not is_anchor and f.get("kind","") in ["city","pass"])
	var placement: Dictionary=instance.get("placement",{}) if not instance.is_empty() else f.get("visual",{}).get("placement",{})
	placement_depth.value=placement.get("depth_offset",0)
	placement_width.value=placement.get("footprint_scale",[1,1])[0]
	placement_height.value=placement.get("footprint_scale",[1,1])[1]
	placement_grounding.set_pressed_no_signal(placement.get("grounding",true))
	placement_overlap.set_pressed_no_signal(placement.get("allow_overlap",false))
	art_instance_inspector.visible = not instance.is_empty()
	_sync_library_options(art_instance_asset, ArtCatalog.library_keys(), str(instance.get("asset","")))
	art_instance_anchor.clear();art_instance_anchor.add_item("无地点绑定");art_instance_anchor.set_item_metadata(0,"")
	for anchor in doc.data.features:
		if not anchor.get("visual",{}).get("anchor_only",false):continue
		art_instance_anchor.add_item(anchor.name+" · "+anchor.id)
		var index:=art_instance_anchor.item_count-1;art_instance_anchor.set_item_metadata(index,anchor.id)
		if anchor.id==instance.get("anchor_id",""):art_instance_anchor.select(index)
	if not instance.is_empty():
		art_instance_scale.value = instance.scale
		art_instance_opacity.value = instance.get("opacity",1.0)
		art_instance_flip.button_pressed = instance.get("flip_h",false)
		art_instance_flip.disabled = ArtCatalog.descriptor(instance.asset).get("group","") not in ["forest","mountain","ground"]
		art_instance_plane.select(["terrain","ground","foreground"].find(instance.plane))
		art_instance_group.text=instance.group_id
		art_group_toggle.tooltip_text="当前操作范围：%d 件；%s" % [doc.art_group_ids(instance.id,art_group_toggle.button_pressed).size(),"所选部件已锁定" if instance.locked else "所选部件未锁定"]
		for i in range(art_instance_asset.item_count):
			if art_instance_asset.get_item_metadata(i) == instance.asset: art_instance_asset.select(i); break
	inspector.visible = not f.is_empty() and not is_anchor
	faction_panel.visible=f.get("kind","")=="prefecture"
	var faction: Dictionary=f.get("visual",{}).get("faction",{})
	faction_name.text=faction.get("name","")
	faction_color.color=Color.html(faction.get("color","#ba6253"))
	if f.is_empty():
		river_edit_button.hide()
		valley_edit_button.hide()
		curve_canvas_button.hide()
		curve_width_row.hide()
		ridge_layout_row.hide()
		refreshing_inspector = false
		pending_label.text = ""
		art_pending_label.text=""
		return
	selected_name.text = f.name
	selected_note.text = f.note
	domain_id.text = f.domain_id
	selected_rule.select(Doc.RULES.find(f.rule))
	selected_rule.disabled = f.kind in Doc.PASSAGES+Doc.BOUNDARIES or f.kind in ["city","pass","ford","label"]
	selected_width.min_value = 1 if f.kind in Doc.BOUNDARIES else 8
	selected_width.value = f.width
	var editable_river: bool=canvas.view_mode!="structure" and f.kind=="water" and f.get("visual",{}).has("ribbon")
	river_edit_button.visible = editable_river
	valley_edit_button.visible = canvas.has_art() and f.kind == "valley" and f.get("visual",{}).has("path")
	curve_canvas_button.visible = editable_river or (canvas.has_art() and f.kind in ["water","valley","mountain","hills"])
	curve_canvas_button.text = "在画布新建 / 调整山脊引导" if f.kind in ["mountain","hills"] else "在画布新建 / 调整表现线"
	curve_width_row.visible = editable_river or (canvas.has_art() and f.kind == "water")
	ridge_layout_row.visible = canvas.has_art() and f.kind in ["mountain","hills"]
	selected_scale.value = f.scale
	selected_art.clear()
	for key in ArtCatalog.variants(f.kind):
		if ArtCatalog.is_library_deleted(key) and key!=f.get("visual",{}).get("variant","auto"): continue
		selected_art.add_item(ArtCatalog.label(key))
		selected_art.set_item_metadata(selected_art.item_count-1,key)
		selected_art.set_item_disabled(selected_art.item_count-1,ArtCatalog.is_library_deleted(key))
		if key == f.get("visual",{}).get("variant","auto"): selected_art.select(selected_art.item_count-1)
	selected_art.disabled = not canvas.has_art() or doc.layer(f.layer).locked
	art_density.value = f.get("visual",{}).get("density",1.0)
	art_seed.value = f.get("visual",{}).get("seed",0)
	art_density.editable = not selected_art.disabled and f.kind in ["forest","mountain","hills"]
	art_seed.editable = art_density.editable
	var visual: Dictionary = f.get("visual", {})
	appearance_x.value = visual.get("offset", [0,0])[0]
	appearance_y.value = visual.get("offset", [0,0])[1]
	width_factor.value = visual.get("width_factor", 1)
	label_x.value = visual.get("label_offset", [0,0])[0]
	label_y.value = visual.get("label_offset", [0,0])[1]
	label_size.value = visual.get("label_size", 22*f.scale if f.kind in ["city", "pass"] else 34*f.scale)
	appearance_visible.button_pressed = visual.get("visible", true)
	label_visible.button_pressed = visual.get("show_label", true)
	_refresh_art_preview()
	gate_open.button_pressed = f.gate_open
	gate_open.visible = f.kind in ["pass","ford"]
	secret_route.button_pressed = f.hidden_route
	secret_route.visible = f.kind in Doc.PASSAGES
	selected_gate.clear()
	selected_gate.add_item("不绑定")
	selected_gate.set_item_metadata(0,"")
	for candidate in doc.data.features:
		if candidate.kind not in ["pass","ford"]: continue
		selected_gate.add_item(candidate.name)
		var index := selected_gate.item_count-1
		selected_gate.set_item_metadata(index,candidate.id)
		if candidate.id == f.gate_id: selected_gate.select(index)
	selected_gate.disabled = f.kind not in Doc.PASSAGES
	refreshing_inspector = false
	pending_label.text = ""
	art_pending_label.text=""

func _section(parent: Control, caption: String, expanded: bool) -> VBoxContainer:
	var button:=Button.new();button.text=("▾ " if expanded else "▸ ")+caption
	button.toggle_mode=true;button.button_pressed=expanded;button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	var content:=VBoxContainer.new();content.visible=expanded;parent.add_child(content)
	button.toggled.connect(func(value): content.visible=value;button.text=("▾ " if value else "▸ ")+caption)
	return content

func _organize_toolbar(toolbar: Control, root: Control) -> void:
	var frequent: Array=[]
	for caption in ["打开游戏主地图","打开地图","保存","另存为","撤销","重做","美术素材","地点与关口","适合窗口","导出地图"]:
		for child in toolbar.get_children():
			if child is Button and child.text==caption: frequent.append(child)
	frequent.append(view_picker)
	var rare: Array=toolbar.get_children().filter(func(child):return child not in frequent)
	for i in range(frequent.size()):toolbar.move_child(frequent[i],i)
	var more:=_section(root,"更多工具 · 参考图 / 检查 / 恢复 / 布局",false)
	var flow:=HFlowContainer.new();more.add_child(flow)
	for child in rare:child.reparent(flow)

func _organize_tools(left: VBoxContainer) -> void:
	var old:=left.get_children()
	var frequent:=HFlowContainer.new();left.add_child(frequent)
	left.move_child(frequent,0)
	for key in ["select","hand","art_stamp","art_select","art_erase","river_draw","river_move","river_erase","city","prefecture"]:
		tool_buttons[key].reparent(frequent)
	var art_group:=_section(left,"美术素材 · 点击后放置",true)
	var water_group:=_section(left,"河流与湖泊 · 画笔设置",false)
	var other_group:=_section(left,"地形 / 道界 / 顶点等工具",false)
	var mode:="water"
	for child in old:
		if child is Label and child.text.begins_with("美术部件"):mode="art"
		if child==tool_buttons.mountain:mode="other"
		if child.get_parent()!=left:continue
		child.reparent(water_group if mode=="water" else (art_group if mode=="art" else other_group))

	material_shelf=VBoxContainer.new()
	material_shelf.name="MaterialShelf"
	left.add_child(material_shelf); left.move_child(material_shelf,0)
	material_shelf.add_child(_label("美术素材",16))
	for control in [asset_query,brush_filter]: control.reparent(material_shelf)
	var modes:=HFlowContainer.new();material_shelf.add_child(modes)
	for pair in [["art_stamp","点放"],["art_select","选择"],["art_place","连续画笔"]]:
		tool_buttons[pair[0]].reparent(modes); tool_buttons[pair[0]].text=pair[1]
	for control in [asset_grid,brush_size.get_parent()]: control.reparent(material_shelf)
	brush_picker.hide()
	placement_hint.text="点选素材 → 地图左键放置\n右键 / Esc 退出"
	placement_hint.reparent(material_shelf)
	_button(material_shelf,"展开素材浏览",_show_asset_browser)

func _focus_materials() -> void:
	tools_panel.show()
	tools_panel.body_scroll.scroll_vertical=0
	asset_query.grab_focus()
	asset_grid.set_process(true)


func _faction_pending() -> bool:
	var f: Dictionary=doc.find_feature(selected_id)
	if f.get("kind","")!="prefecture":return false
	var faction: Dictionary=f.get("visual",{}).get("faction",{})
	return faction_name.text!=faction.get("name","") or faction_color.color.to_html(false)!=Color.html(faction.get("color","#ba6253")).to_html(false)

func _apply_faction() -> void:
	var ids: Array=canvas.selection_ids.filter(func(id):return doc.find_feature(id).get("kind","")=="prefecture")
	if ids.is_empty() and not selected_id.is_empty():ids=[selected_id]
	if doc.set_prefecture_faction(ids,faction_name.text,"#"+faction_color.color.to_html(false)):
		_status("已更新所选州及其分区的势力颜色；可撤销。")
	else:_status("请选择州域；图层锁定、受保护或内容未变化时不能应用。")

func _spin_matches(field: SpinBox, value: float) -> bool:
	# Loading a value rounds/clamps its display; that is not an author edit.
	var displayed := snappedf(value,field.step)
	if not field.allow_lesser: displayed = maxf(displayed,field.min_value)
	if not field.allow_greater: displayed = minf(displayed,field.max_value)
	return is_equal_approx(field.value,displayed)

func _kept_spin_value(field: SpinBox, original: float) -> float:
	return original if _spin_matches(field,original) else field.value

func _inspector_pending() -> bool:
	if refreshing_inspector or pending_label == null or selected_id.is_empty(): return false
	var f: Dictionary = doc.find_feature(selected_id)
	if f.is_empty(): return false
	if f.get("visual",{}).get("anchor_only",false):
		return site_name.text!=f.name or site_domain.text!=f.domain_id or not _spin_matches(site_x,f.points[0][0]) or not _spin_matches(site_y,f.points[0][1])
	if _faction_pending(): return true
	if selected_name.text != f.name or selected_note.text != f.note or domain_id.text != f.domain_id: return true
	if selected_rule.selected != Doc.RULES.find(f.rule) or not _spin_matches(selected_width,float(f.width)) or not _spin_matches(selected_scale,float(f.scale)): return true
	if gate_open.button_pressed != f.gate_open or secret_route.button_pressed != f.hidden_route: return true
	if f.kind in Doc.PASSAGES and selected_gate.get_selected_metadata() != f.gate_id: return true
	var visual: Dictionary = f.get("visual", {})
	if not _spin_matches(appearance_x,float(visual.get("offset",[0,0])[0])) or not _spin_matches(appearance_y,float(visual.get("offset",[0,0])[1])): return true
	if not _spin_matches(width_factor,float(visual.get("width_factor",1.0))): return true
	if not _spin_matches(label_x,float(visual.get("label_offset",[0,0])[0])) or not _spin_matches(label_y,float(visual.get("label_offset",[0,0])[1])): return true
	if not _spin_matches(label_size,float(visual.get("label_size",22*f.scale if f.kind in ["city","pass"] else 34*f.scale))): return true
	if appearance_visible.button_pressed != visual.get("visible",true) or label_visible.button_pressed != visual.get("show_label",true): return true
	if canvas.has_art() and f.kind in ["forest","mountain","hills","city","pass"]:
		if selected_art.selected >= 0 and selected_art.get_item_metadata(selected_art.selected) != visual.get("variant","auto"): return true
		if not _spin_matches(art_density,float(visual.get("density",1.0))) or not _spin_matches(art_seed,float(visual.get("seed",0))): return true
	return false

func _mark_inspector_pending() -> void:
	if refreshing_inspector or pending_label == null: return
	pending_label.text = "● 属性尚未应用；保存或切换前会提示，取消可保留输入。" if _inspector_pending() else ""
	art_pending_label.text="● 部件 / 接地输入尚未应用；可应用或保存在制作快照中。" if _art_inspector_pending() or _placement_pending() else ""

func apply_properties() -> void:
	var f: Dictionary = doc.find_feature(selected_id)
	if f.is_empty(): return
	if f.get("visual",{}).get("anchor_only",false):
		if site_name.text.strip_edges().is_empty():_status("请填写地点名称。");return
		var values:={"name":site_name.text.strip_edges(),"domain_id":site_domain.text.strip_edges(),"points":[[_kept_spin_value(site_x,f.points[0][0]),_kept_spin_value(site_y,f.points[0][1])]]}
		if doc.update_feature(selected_id,values):_status("地点定位已更新；外观位置独立保留，可撤销。")
		else:_status("地点未变化，或 ID 重复、坐标越界、地点 / 图层锁定。")
		return
	var visual: Dictionary = f.get("visual", {}).duplicate(true)
	if f.kind=="prefecture":
		if faction_name.text.strip_edges().is_empty(): visual.erase("faction")
		else: visual.faction={"name":faction_name.text.strip_edges(),"color":"#"+faction_color.color.to_html(false)}
	visual.offset = [_kept_spin_value(appearance_x,visual.get("offset",[0,0])[0]), _kept_spin_value(appearance_y,visual.get("offset",[0,0])[1])]
	visual.width_factor = _kept_spin_value(width_factor,visual.get("width_factor",1))
	visual.label_offset = [_kept_spin_value(label_x,visual.get("label_offset",[0,0])[0]), _kept_spin_value(label_y,visual.get("label_offset",[0,0])[1])]
	var original_label_size: float = visual.get("label_size",22*f.scale if f.kind in ["city","pass"] else 34*f.scale)
	# Preserve an implicit label size, including defaults outside the UI range.
	if visual.has("label_size") or not _spin_matches(label_size,original_label_size):
		visual.label_size = _kept_spin_value(label_size,original_label_size)
	visual.visible = appearance_visible.button_pressed
	visual.show_label = label_visible.button_pressed
	if f.kind in ["city","pass"]: visual.placement=_placement_values()
	if canvas.has_art() and f.kind in ["forest", "mountain", "hills", "city", "pass"]:
		visual.variant = selected_art.get_item_metadata(selected_art.selected)
		visual.density = _kept_spin_value(art_density,visual.get("density",1))
		visual.seed = int(_kept_spin_value(art_seed,visual.get("seed",0)))
	if f.protected:
		if doc.update_appearance(selected_id, visual): _status("受保护地点的外观已更新；坐标、绑定与通行未改。")
		else: _status("外观未变化，或图层已锁定 / 参数无效。")
		return
	var values := {"name":selected_name.text,"note":selected_note.text,"domain_id":domain_id.text,"rule":Doc.RULES[selected_rule.selected],"width":_kept_spin_value(selected_width,f.width),"scale":_kept_spin_value(selected_scale,f.scale),"gate_open":gate_open.button_pressed,"hidden_route":secret_route.button_pressed}
	if canvas.has_art() or f.kind=="prefecture": values.visual = visual
	if f.kind in Doc.PASSAGES: values.gate_id = selected_gate.get_item_metadata(selected_gate.selected)
	if doc.update_feature(selected_id,values): _status("属性已应用；请重新检查通行。")
	else: _status("属性未变化，或对象受保护 / 图层已锁定。")

func _apply_batch_appearance() -> void:
	var ids: Array = canvas.selection_ids.duplicate()
	if ids.size() < 2:
		_status("请先在对象列表或画布上选择至少两个同类型对象。")
		return
	var first: Dictionary = doc.find_feature(str(ids[0]))
	for id in ids:
		if doc.find_feature(str(id)).get("kind","") != first.kind:
			_status("批量外观只接受同类型对象；位置与通行不会改变。")
			return
	var values := {"offset":[appearance_x.value,appearance_y.value],"width_factor":width_factor.value,"label_offset":[label_x.value,label_y.value],"label_size":int(label_size.value),"visible":appearance_visible.button_pressed,"show_label":label_visible.button_pressed}
	if canvas.has_art() and first.kind in ["forest","mountain","hills","city","pass"]:
		values.variant = selected_art.get_item_metadata(selected_art.selected)
		values.density = art_density.value
		values.seed = int(art_seed.value)
	if doc.update_appearances(ids,values): _status("已为 %d 个同类型对象一次应用外观，可整体撤销；坐标、绑定与通行不变。" % ids.size())
	else: _status("批量外观未变化，或含锁定图层 / 参数无效。")

func _placement_values() -> Dictionary:
	var old:=_selected_placement()
	var scale: Array=old.get("footprint_scale",[1,1])
	return {"depth_offset":_kept_spin_value(placement_depth,old.get("depth_offset",0)),"footprint_scale":[_kept_spin_value(placement_width,scale[0]),_kept_spin_value(placement_height,scale[1])],"grounding":placement_grounding.button_pressed,"allow_overlap":placement_overlap.button_pressed}

func _selected_placement() -> Dictionary:
	var instance: Dictionary=doc.find_art_instance(selected_art_id)
	return instance.get("placement",{}) if not instance.is_empty() else doc.find_feature(selected_id).get("visual",{}).get("placement",{})

func _placement_pending() -> bool:
	if refreshing_inspector or placement_panel==null or not placement_panel.visible: return false
	var old:=_selected_placement()
	return not _spin_matches(placement_depth,old.get("depth_offset",0)) or not _spin_matches(placement_width,old.get("footprint_scale",[1,1])[0]) or not _spin_matches(placement_height,old.get("footprint_scale",[1,1])[1]) or placement_grounding.button_pressed!=old.get("grounding",true) or placement_overlap.button_pressed!=old.get("allow_overlap",false)

func _apply_placement() -> void:
	if _inspector_pending() or _art_inspector_pending():
		_status("请先应用其他外观输入，再应用接地与遮挡；当前输入已保留。")
		return
	var ok: bool=doc.update_art_instance(selected_art_id,{"placement":_placement_values()}) if not selected_art_id.is_empty() else doc.update_appearance(selected_id,{"placement":_placement_values()})
	_status("接地与遮挡已保存，可撤销；打开‘按落点遮挡’查看。" if ok else "接地设置未变化，或对象 / 图层锁定。")
	if ok and canvas.depth_enabled():
		var issues: Array=Canvas.Spatial.conflict_pairs(canvas.spatial_entries())
		canvas.visual_issues=issues
		if not issues.is_empty(): _status(issues[0].message)

func _apply_art_instance() -> void:
	if selected_art_id.is_empty() or art_instance_asset.selected < 0: return
	var asset: String = art_instance_asset.get_item_metadata(art_instance_asset.selected)
	var old: Dictionary=doc.find_art_instance(selected_art_id)
	var values:={"asset":asset,"scale":_kept_spin_value(art_instance_scale,old.get("scale",1)),"opacity":_kept_spin_value(art_instance_opacity,old.get("opacity",1)),"flip_h":art_instance_flip.button_pressed and ArtCatalog.descriptor(asset).get("group","") in ["forest","mountain","ground"],"plane":["terrain","ground","foreground"][art_instance_plane.selected],"group_id":art_instance_group.text.strip_edges(),"placement":_placement_values()}
	var anchor_id:=str(art_instance_anchor.get_selected_metadata())
	if old.has("anchor_id") or not anchor_id.is_empty():values.anchor_id=anchor_id
	if doc.update_art_instance(selected_art_id,values): _status("美术部件已更新；地点身份与定位保留，可撤销。")
	else:_status("外观未变化，或部件锁定 / 素材与地点绑定不兼容。")

func _refresh_objects() -> void:
	if not is_instance_valid(object_list): return
	object_list.clear()
	var query := object_search.text.strip_edges().to_lower()
	for f in doc.data.features:
		if not query.is_empty() and not (f.name+" "+Doc.NAMES[f.kind]+" "+f.domain_id+" "+f.id).to_lower().contains(query): continue
		var index := object_list.add_item(Doc.NAMES[f.kind]+" · "+f.name)
		object_list.set_item_metadata(index,f.id)
		if f.id in canvas.selection_ids: object_list.select(index,false)

func _move_selected(direction: int) -> void:
	if doc.move_feature_order(selected_id,direction): _status("已调整所选对象在图层内的覆盖顺序。")
	else: _status("已到同层对象的最前 / 最后，或图层已锁定。")

func _invalidate_preview() -> void:
	if is_instance_valid(canvas): canvas.route.clear(); canvas.check_scope=Rect2(); canvas.queue_redraw()
	if is_instance_valid(result_label): result_label.text = "条件已改变，旧路径已清除。点击“检查通行”重新计算。"

func check_route() -> Dictionary:
	var scope: Rect2 = canvas.visible_world_rect() if local_preview.button_pressed else Rect2()
	var result: Dictionary
	if local_preview.button_pressed and not scope.has_area(): result = {"ok":false,"reason":"当前视野没有地图，请先回到地图内。","path":PackedVector2Array()}
	else: result = Routes.new().solve(doc.data,canvas.start_point,canvas.end_point,"army" if unit.selected == 0 else "light",revealed.button_pressed,scope,float(preview_precision.get_selected_metadata()))
	canvas.route = result.path
	canvas.check_scope = scope
	canvas.queue_redraw()
	result_label.text = ("✓ " if result.ok else "× ") + result.reason
	if result.has("step"): result_label.text += "  格距 %.0f 图面单位 / %.0f ms" % [result.step,result.get("elapsed_ms",0)]
	return result

func _discard_canvas_input_then(action: Callable) -> void:
	if canvas.tool == "visual_curve" or not canvas.draft.is_empty(): canvas.set_tool("select")
	action.call()

func _sync_tool_buttons(_value: String = "") -> void:
	for key in tool_buttons:
		tool_buttons[key].set_pressed_no_signal(key == canvas.tool)
	if placement_hint != null:
		placement_hint.text = "正在点放：%s\n左键放一件 · 右键 / Esc 退出" % ("混合林缘" if canvas.brush_asset=="mixed_forest" else ArtCatalog.label(canvas.brush_asset)) if canvas.tool=="art_stamp" else "点下方素材 → 地图左键放置\n右键 / Esc 退出 → 拖动部件"

func _request_tool_change(value: String, label: String = "") -> void:
	var action := func():
		if value in Canvas.WaterBrush.TOOLS:
			rules_toggle.button_pressed=false
		if value in ["art_stamp","art_place"]:
			_refresh()
			_prepare_art_placement()
		canvas.set_tool(value)
		if not label.is_empty(): _status("已选择“%s”。" % label)
	if canvas.has_uncommitted_canvas_input() or (value in ["art_stamp","art_place"] and (_inspector_pending() or _art_inspector_pending() or _placement_pending())):
		_guard_unapplied(action)
		_sync_tool_buttons()
		return
	action.call()

func _guard(action: Callable) -> void:
	var unapplied: bool = _inspector_pending() or _art_inspector_pending() or _placement_pending() or canvas.has_uncommitted_canvas_input()
	if not doc.is_dirty() and not unapplied: action.call(); return
	pending = func(): _discard_canvas_input_then(action)
	confirm.title = "当前地图有未应用的输入" if unapplied else "当前地图尚未保存"
	confirm.dialog_text = "属性面板或画布仍有未应用输入。继续会替换当前地图并丢弃未保存修改与这些输入。请取消后应用并保存，或确认继续。" if unapplied else "继续会替换当前编辑内容。请先取消并保存，或确认继续。"
	confirm.popup_centered(Vector2i(520,220))

func _guard_unapplied(action: Callable) -> void:
	if not _inspector_pending() and not _art_inspector_pending() and not _placement_pending() and not canvas.has_uncommitted_canvas_input():
		action.call()
		return
	pending = func(): _discard_canvas_input_then(action)
	confirm.title = "编辑输入尚未应用"
	confirm.dialog_text = "右侧属性或画布笔画还没有写入地图。继续会丢弃这些输入；取消后可先应用。"
	confirm.popup_centered(Vector2i(520,220))

func _request_history(redo_action: bool) -> void:
	_guard_unapplied(func():
		_refresh()
		var changed: bool=doc.redo() if redo_action else doc.undo()
		if not changed: _status("没有可重做的修改。" if redo_action else "没有可撤销的修改。"))

func request_close() -> void:
	if not close_action.is_valid(): return
	var unapplied: bool = _inspector_pending() or _art_inspector_pending() or _placement_pending() or canvas.has_uncommitted_canvas_input()
	if not doc.is_dirty() and not unapplied:
		close_action.call()
		return
	pending = func(): _discard_canvas_input_then(close_action)
	confirm.title = "关闭地图工坊"
	confirm.dialog_text = "关闭会丢弃未应用的属性或画布笔画，以及未保存的地图修改。请取消后应用并保存，或确认关闭。" if unapplied else "当前地图尚未保存。请取消后保存，或确认关闭。"
	confirm.popup_centered(Vector2i(520,220))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree() and not Engine.is_editor_hint() and get_tree().current_scene == self:
		request_close()

func _request_selection_change(kind: String, target: Variant) -> bool:
	if not _inspector_pending() and not _art_inspector_pending() and not _placement_pending() and not canvas.has_uncommitted_canvas_input(): return true
	_guard_unapplied(func(): _apply_requested_selection(kind,target))
	return false

func _apply_requested_selection(kind: String, target: Variant) -> void:
	match kind:
		"feature": canvas.select_feature(str(target))
		"art": canvas.select_art_instance(str(target))
		"many": canvas.select_many(target)
		"canvas_edit":
			_refresh()
			_status("未应用输入已放弃，请重新拖动或绘制。")

func _art_inspector_pending() -> bool:
	if refreshing_inspector or selected_art_id.is_empty() or art_instance_asset == null: return false
	var instance: Dictionary = doc.find_art_instance(selected_art_id)
	if instance.is_empty(): return false
	return (art_instance_asset.get_selected_metadata() != instance.asset
		or not _spin_matches(art_instance_scale, float(instance.scale))
		or not _spin_matches(art_instance_opacity, float(instance.get("opacity",1.0)))
		or ["terrain","ground","foreground"][art_instance_plane.selected]!=instance.plane
		or art_instance_group.text.strip_edges()!=instance.group_id
		or art_instance_anchor.get_selected_metadata()!=instance.get("anchor_id","")
		or art_instance_flip.button_pressed != instance.get("flip_h",false))

func _choose_file(action: String) -> void:
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action in ["save","png","tiles"] else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.json ; 地图工程 / 操作 JSON"]) if action in ["save","open","tiles","batch"] else PackedStringArray(["*.png ; PNG 图片"])
	if action == "background": file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 参考底图"])
	if action == "save": file_dialog.current_file="山河地图.map.json"
	if action == "png": file_dialog.current_file="山河地图.png"
	if action == "tiles": file_dialog.current_file="山河地图.tiles.json"
	file_dialog.title = {"save":"保存地图工程","open":"打开地图工程","background":"添加参考图（仅作参照，不生成规则）","art_png":"导入透明美术部件 PNG","png":"导出完整地图图片","tiles":"保存分块图集索引（旁边自动建立图片目录）","batch":"选择批量操作文件"}[action]
	# FileDialog keeps Godot's native file picker controls, with a bounded client area.
	var available := get_viewport().get_visible_rect().size
	file_dialog.min_size = Vector2i(420,280)
	file_dialog.max_size = Vector2i((available-Vector2(48,80)).max(Vector2(420,280)))
	file_dialog.popup_centered(Vector2i(Vector2(900,600).min(available-Vector2(80,120))))

func _file_selected(path: String) -> void:
	match file_action:
		"art_png": _show_art_import(path)
		"batch":
			var file := FileAccess.open(path,FileAccess.READ)
			if file == null or file.get_length() > 32*1024*1024: _status("操作文件不存在或超过 32 MiB。"); return
			var request: Variant = JSON.parse_string(file.get_as_text())
			if not request is Dictionary: _status("操作文件 JSON 格式错误。"); return
			var response: Dictionary = doc.apply_batch(request)
			_status("批量操作已应用（重复批次会自动跳过），可整体撤销。" if response.ok else response.get("error","批次未应用。"))
		"open": _open(path)
		"save":
			var error: String = _save_map_path(path)
			_status("已保存："+path if error.is_empty() else error)
			_refresh()
			if error.is_empty(): _after_map_saved()
		"background":
			var img := Image.new()
			if img.load(path) != OK or img.get_width() > 8192 or img.get_height() > 8192: _status("无法读取底图，或尺寸超过 8192 像素。")
			else:
				var id := "primary"
				if doc.data.reference.path.is_empty(): doc.import_reference(path,img.get_size())
				else: id = doc.add_reference(path,img.get_size())
				if id.is_empty(): _status("参考图数量已达上限（64 张）。"); return
				canvas.active_reference = id
				_status("已添加并锁定参考图；可在设置中切换分图、解锁、调整尺寸和旋转。")
				settings_panel.show_reference(doc,id)
		"png", "tiles":
			var error: String = await export_map(path,export_options.longest,file_action == "tiles",export_options.tile_size)
			_status("已导出："+path if error.is_empty() else error)

func _load_startup_map() -> void:
	var config := ConfigFile.new()
	var last_map := ""
	if config.load(startup_state_path) == OK:
		var recorded: Variant = config.get_value("startup", "last_map", "")
		if recorded is String: last_map = recorded
	var errors: Array[String] = []
	if not last_map.is_empty():
		if _open(last_map, false): return
		errors.append("上次地图无法打开：%s（%s）" % [last_map,status.text])
	if _open(startup_default_map, false):
		if not errors.is_empty(): _status("%s；已打开默认大地图。" % "；".join(errors))
		return
	errors.append("默认大地图无法打开：" + status.text)
	doc.replace_document(Doc.blank())
	canvas.select_feature("")
	canvas.fit_map()
	_status("%s；已新建空白地图，可用‘打开地图’选择文件。" % "；".join(errors))

func _remember_current_map() -> void:
	if not restore_last_map_on_start or doc.current_path.is_empty(): return
	var config := ConfigFile.new()
	config.load(startup_state_path)
	config.set_value("startup", "last_map", ProjectSettings.globalize_path(doc.current_path))
	if config.save(startup_state_path) != OK:
		_status("地图操作已完成，但未能记住启动地图路径；下次可能需要手动打开。")

func _open(path: String, remember: bool = true) -> bool:
	var error: String = doc.load_file(path)
	if not error.is_empty(): _status(error); return false
	canvas.select_feature("")
	canvas.fit_map()
	_status("已打开："+path)
	if game_map_status!=null and not game_map_publisher.busy:
		game_map_status.text="正在编辑游戏主地图；保存后自动更新游戏，加速数据在后台生成。" if GameMapPublisher.same_path(path,game_map_path) else "独立样区；若要用于游戏，在“更多工具”中选择“设为游戏主地图”。"
	if remember: _remember_current_map()
	return true

func save_current() -> void:
	if _inspector_pending() or _art_inspector_pending() or _placement_pending() or canvas.has_uncommitted_canvas_input():
		_guard_unapplied(_save_current_unchecked)
		return
	_save_current_unchecked()

func save_as() -> void:
	_guard_unapplied(func(): _choose_file("save"))

func _save_current_unchecked() -> void:
	if doc.current_path.is_empty(): _choose_file("save"); return
	var error: String = _save_map_path(doc.current_path)
	_status("地图已保存。" if error.is_empty() else error)
	_refresh()
	if error.is_empty(): _after_map_saved()

func _save_map_path(path: String) -> String:
	if GameMapPublisher.same_path(path,game_map_path):
		var error: String=GameMapPublisher.validate_master(doc)
		if not error.is_empty():return error
	return doc.save_file(path)

func _after_map_saved() -> void:
	_remember_current_map()
	if GameMapPublisher.same_path(doc.current_path,game_map_path):
		var error: String=game_map_publisher.queue_build()
		if not error.is_empty():game_map_status.text=error
	elif not game_map_publisher.busy:
		game_map_status.text="已保存独立地图；游戏主地图保持原样。"

func _adopt_game_map() -> void:
	var error: String=_save_map_path(game_map_path)
	if not error.is_empty():_status(error);return
	# Changing the working document path makes later Save operations update the
	# same master. Historical samples retain their original files.
	var preference_error: String=GameMapPreferences.new(game_preferences_path).write(true,game_map_path,"")
	_after_map_saved();_refresh()
	_status("已设为游戏主地图；以后直接点保存即可。" if preference_error.is_empty() else "主地图已保存；"+preference_error)

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventMouse and get_global_rect().has_point(event.position):
		last_author_input_ms=Time.get_ticks_msec()
	elif is_visible_in_tree() and event is InputEventKey:
		last_author_input_ms=Time.get_ticks_msec()

func _process(_delta: float) -> void:
	_finish_autosave()

func _finish_autosave(wait: bool=false) -> void:
	if autosave_worker==null:return
	if not wait and autosave_worker.is_alive():return
	var result: Dictionary=autosave_worker.wait_to_finish()
	autosave_worker=null
	set_process(false)
	if result.ok:autosave_signature=autosave_job_signature
	else:_status("自动恢复草稿保存失败："+str(result.error))

func _autosave(force: bool = false) -> void:
	_finish_autosave(force)
	if autosave_worker!=null:return
	if not autosave_enabled or not has_unsaved_authoring(): return
	# Coalesce the latest draft after input settles; explicit save and close
	# still flush immediately, including pending inspector/canvas input.
	if not force and (Time.get_ticks_msec()-last_author_input_ms<2000 or canvas.panning or canvas.art_dragging or canvas.dragging or canvas.art_stroke_active or canvas.stroke_active or canvas.water_input.active):
		if is_instance_valid(autosave_timer): autosave_timer.start(2.0)
		return
	if not force and is_instance_valid(autosave_timer): autosave_timer.start(30.0)
	var editing := AuthoringSession.capture(self)
	var signature := str(doc.revision)+str(doc.current_path)+JSON.stringify(editing)
	if signature == autosave_signature: return
	if not force:
		# Validate and detach on the owner thread. JSON serialization, portable
		# reference copying and atomic disk/index writes never touch live UI/data.
		var prepared: Dictionary=recovery_store.prepare_save(doc,recovery_session_id,"自动草稿","draft",editing)
		if not prepared.ok:_status("自动恢复草稿保存失败："+str(prepared.error));return
		autosave_job_signature=signature
		autosave_worker=Thread.new()
		if autosave_worker.start(recovery_store.save_prepared.bind(prepared))!=OK:
			autosave_worker=null
			_status("自动恢复草稿保存失败：无法启动保存线程。")
		else:set_process(true)
		return
	var result: Dictionary = recovery_store.save_draft(doc, recovery_session_id, editing)
	if not result.ok: _status("自动恢复草稿保存失败：" + result.error)
	else: autosave_signature = signature

func has_unsaved_authoring() -> bool:
	return doc.is_dirty() or (canvas != null and (_inspector_pending() or _art_inspector_pending() or _placement_pending() or canvas.has_uncommitted_canvas_input()))

func has_unsaved_editor_session() -> bool:
	if not has_unsaved_authoring(): return false
	# A recovery save satisfies the host exit guard, but must not mark the map
	# file clean or discard unapplied controls. Any subsequent edit needs saving.
	if doc.revision != _editor_saved_revision or doc.current_path != _editor_saved_path: return true
	if _editor_recovery_path.is_empty() or not FileAccess.file_exists(_editor_recovery_path): return true
	return AuthoringSession.capture(self) != _editor_saved_input

func save_editor_session() -> Dictionary:
	_finish_autosave(true)
	var editing := AuthoringSession.capture(self)
	var result: Dictionary = recovery_store.save_draft(doc,recovery_session_id,editing)
	if result.ok:
		_editor_saved_revision = doc.revision
		_editor_saved_path = doc.current_path
		_editor_saved_input = editing.duplicate(true)
		_editor_recovery_path = result.path
	else:
		_status("退出保存失败：" + str(result.error) + "；当前编辑仍未保存。")
		push_error(str(result.error))
	return result

func _show_art_visual_audit() -> void:
	var issues: Array = ArtVisualAudit.inspect(doc,canvas,canvas.visible_world_rect(),true)
	canvas.visual_issues = issues
	canvas.view_mode = "overlay"
	canvas.queue_redraw()
	var dialog := DialogShell.new()
	dialog.title = "当前视野成图检查"
	dialog.ok_button_text = "定位所选问题"
	add_child(dialog)
	dialog.content.add_child(_label("检查标注碰撞、城关遮挡、水域、边框及素材版本。结果仅供人工审图，不评判历史精度或风格。",13))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(590,250)
	dialog.content.add_child(list)
	for issue in issues: list.add_item(str(issue.code) + " · " + str(issue.message))
	if issues.is_empty(): list.add_item("当前视野没有检测到上述结构性成图问题；仍需人工比较 v5 风格。")
	else: list.select(0)
	dialog.confirmed.connect(func():
		if not issues.is_empty() and list.get_selected_items().size() > 0:
			var issue: Dictionary = issues[list.get_selected_items()[0]]
			if not issue.feature_id.is_empty():
				var feature: Dictionary = doc.find_feature(issue.feature_id)
				if not feature.is_empty():
					canvas.center_on(Vector2(feature.points[0][0],feature.points[0][1]))
					canvas.select_feature(issue.feature_id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(660,360))
	_status("当前视野检查：%d 项提示；请逐项定位并人工复核。" % issues.size())

func _water_endpoint_option(parent: Node,label: String) -> OptionButton:
	var row:=HBoxContainer.new();parent.add_child(row)
	row.add_child(_label(label,12))
	var option:=OptionButton.new()
	for text in ["自动识别连接 / 自由端渐细","河源渐细","续接河段（保持河宽）","汇入水域（保持开口）"]: option.add_item(text)
	option.tooltip_text="按笔画顺序区分两端，不代表水流方向。自动模式仅对未接入水体的自由端收细。"
	row.add_child(option)
	return option

func _show_river_visual_dialog() -> void:
	var feature: Dictionary = doc.find_feature(selected_id)
	if feature.is_empty() or feature.kind != "water" or not feature.get("visual",{}).has("ribbon"):
		_status("请先选择带表现曲线的水域对象。")
		return
	var feature_id: String = feature.id
	var ribbon: Dictionary = feature.visual.ribbon
	if ribbon.points.size() != ribbon.widths.size():
		_status("水面表现数据不完整，请先检查地图文件。")
		return
	var dialog := DialogShell.new()
	dialog.title = "河道表现曲线 · 仅改外观"
	dialog.ok_button_text = "校验并应用"
	add_child(dialog)
	dialog.content.add_child(_label("坐标与宽度属于显示层。应用时逐点校验源水域，失败则保持当前地图不变；可撤销。",13))
	var style := OptionButton.new()
	style.add_item("柔和淡彩岸线")
	style.add_item("细墨岸线与顺流笔触")
	style.add_item("细墨岸线与疏密水纹")
	style.add_item("细墨岸线与断续水彩笔触")
	style.select(["soft", "inked", "inked_varied", "inked_brush"].find(ribbon.get("render_style","soft")))
	dialog.content.add_child(style)
	var start_style:=_water_endpoint_option(dialog.content,"首个控制点")
	var end_style:=_water_endpoint_option(dialog.content,"最后控制点")
	var endpoints: Array=ribbon.get("end_styles",["auto","auto"])
	start_style.select(["auto","source","join","mouth"].find(endpoints[0]))
	end_style.select(["auto","source","join","mouth"].find(endpoints[1]))
	var controls: Array = []
	for i in range(ribbon.points.size()):
		var row := HBoxContainer.new()
		dialog.content.add_child(row)
		row.add_child(_label("%02d" % (i+1),13))
		var x := _spin(row,"X",0,float(doc.data.canvas_size[0]),0.001)
		var y := _spin(row,"Y",0,float(doc.data.canvas_size[1]),0.001)
		var width := _spin(row,"宽",2,256,0.5)
		x.value = ribbon.points[i][0]
		y.value = ribbon.points[i][1]
		width.value = ribbon.widths[i]
		controls.append({"x":x,"y":y,"width":width})
	dialog.confirmed.connect(func():
		var current: Dictionary = doc.find_feature(feature_id)
		if current.is_empty():
			_status("水域对象已不存在；没有应用。")
			dialog.queue_free()
			return
		var edited: Dictionary = current.visual.ribbon.duplicate(true)
		edited.points = []
		edited.widths = []
		for row in controls:
			edited.points.append([row.x.value,row.y.value])
			edited.widths.append(row.width.value)
		edited.render_style = ["soft", "inked", "inked_varied", "inked_brush"][style.selected]
		edited.end_styles=[["auto","source","join","mouth"][start_style.selected],["auto","source","join","mouth"][end_style.selected]]
		if doc.update_appearance(feature_id,{"ribbon":edited}):
			_status("水面表现已更新；源水域、通行与地点坐标未改。")
		else:
			_status("水面表现未应用：没有变化，或曲线 / 宽度越过源水域。")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(780,680))

func _start_visual_curve() -> void:
	if _inspector_pending() or _art_inspector_pending() or _placement_pending():
		_status("请先应用或撤销右侧未提交的属性，再进入画布表现线编辑。")
		return
	if canvas.has_uncommitted_canvas_input():
		_status("画布已有未提交笔画，请先按 Enter 应用或 Esc 放弃。")
		return
	if not canvas.begin_visual_curve(selected_id):
		_status("请选择河流，或美术视图中的谷道 / 山脊；图层不能锁定。")
		return
	canvas.visual_curve_default_width = curve_width_spin.value
	var f: Dictionary = doc.find_feature(selected_id)
	var label := "水域" if f.kind == "water" else ("谷道" if f.kind == "valley" else "山脊")
	_status("正在画布编辑%s表现线：逐点点击并拖点；Shift 加点、Alt 删点，Enter 保存，Esc 取消。谷道已取源线端点。" % label)

func _show_valley_visual_dialog() -> void:
	var feature: Dictionary = doc.find_feature(selected_id)
	if feature.is_empty() or feature.kind != "valley" or not feature.get("visual",{}).has("path"):
		_status("请先选择带表现线的谷道对象。")
		return
	var feature_id: String = feature.id
	var path: Array = feature.visual.path
	var dialog := DialogShell.new()
	dialog.title = "谷道接近线 · 仅改外观"
	dialog.ok_button_text = "校验并应用"
	add_child(dialog)
	dialog.content.add_child(_label("起终点及全部控制点必须留在源谷道内；样式不改变通行或关门状态。",13))
	var style := OptionButton.new()
	style.add_item("淡色引导")
	style.add_item("浅绘接近线")
	style.add_item("土路")
	style.select(["subtle","painted","earth"].find(feature.visual.get("path_style", "subtle")))
	dialog.content.add_child(style)
	var controls: Array = []
	for i in range(path.size()):
		var row := HBoxContainer.new()
		dialog.content.add_child(row)
		row.add_child(_label("%02d" % (i+1),13))
		var x := _spin(row,"X",0,float(doc.data.canvas_size[0]),0.001)
		var y := _spin(row,"Y",0,float(doc.data.canvas_size[1]),0.001)
		x.value = path[i][0]
		y.value = path[i][1]
		controls.append({"x":x,"y":y})
	dialog.confirmed.connect(func():
		if doc.find_feature(feature_id).is_empty():
			_status("谷道对象已不存在；没有应用。")
			dialog.queue_free()
			return
		var edited: Array = []
		for row in controls: edited.append([row.x.value,row.y.value])
		if doc.update_appearance(feature_id,{"path":edited,"path_style":["subtle","painted","earth"][style.selected]}):
			_status("谷道接近线已更新；源谷道、通行与门禁未改。")
		else:
			_status("接近线未应用：没有变化，或控制点越过源谷道。")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(760,600))

func _show_snapshot_dialog() -> void:
	var dialog := DialogShell.new()
	dialog.title = "保存制作快照"
	dialog.ok_button_text = "保存快照"
	add_child(dialog)
	var name := _field(dialog.content, "快照名称")
	name.text = "潼关局部修整"
	dialog.confirmed.connect(func():
		var result: Dictionary = _save_named_snapshot(name.text)
		if not result.ok:
			_status(result.error)
		else:
			_status("制作快照已保存（含未应用输入）：" + name.text)
			var preview_path: String = recovery_store.preview_path(result.id)
			if not preview_path.is_empty() and DisplayServer.get_name() != "headless":
				var worker = Exporter.new()
				add_child(worker)
				var error: String = await worker.run(doc, preview_path, 320, false, 2048, canvas.visible_world_rect())
				worker.queue_free()
				if error.is_empty(): recovery_store.set_preview(result.id)
				else: _status("快照已保存；缩略图失败：" + error)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(480, 230))

func _save_named_snapshot(name: String) -> Dictionary:
	_finish_autosave(true)
	return recovery_store.save_snapshot(doc,recovery_session_id,name,AuthoringSession.capture(self))

func _show_recovery_dialog() -> void:
	var entries: Array = recovery_store.entries()
	if entries.is_empty():
		_status("暂无恢复记录。" if recovery_store.last_error.is_empty() else recovery_store.last_error)
		return
	var dialog := DialogShell.new()
	dialog.title = "恢复地图制作项目"
	dialog.ok_button_text = "载入副本"
	add_child(dialog)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(520, 210)
	dialog.content.add_child(list)
	for item in entries:
		list.add_item(("草稿" if item.kind == "draft" else "快照") + " · " + str(item.name) + " · " + str(item.title) + " · " + Time.get_datetime_string_from_unix_time(int(item.saved_at)))
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(320, 175)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dialog.content.add_child(preview)
	var update_preview := func(index: int):
		preview.texture = null
		var item: Dictionary = entries[index]
		var filename: String = item.get("preview_file", "")
		if not filename.is_empty():
			var image := Image.load_from_file(recovery_store.root_path.path_join(filename))
			if image != null and not image.is_empty(): preview.texture = ImageTexture.create_from_image(image)
	list.item_selected.connect(update_preview)
	list.select(0)
	update_preview.call(0)
	dialog.confirmed.connect(func():
		if list.get_selected_items().is_empty(): dialog.queue_free(); return
		var id: String = entries[list.get_selected_items()[0]].id
		_guard(func():
			var result: Dictionary = recovery_store.restore(doc, id)
			if result.ok:
				canvas.select_feature("")
				canvas.select_art_instance("")
				canvas.fit_map()
				if result.entry.get("editing_state") is Dictionary:
					AuthoringSession.restore.call_deferred(self,result.entry.editing_state)
				_status("已载入恢复副本；请选择另存为路径。")
			else: _status(result.error))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(630, 520))

func _exit_tree() -> void:
	if doc != null: _autosave(true)
	_save_layout()
	for button in tool_buttons.values():
		if is_instance_valid(button): button.button_group = null
	tool_buttons.clear()
	tool_button_group = null

func export_png(path: String) -> String:
	return await export_map(path,mini(4096,maxi(doc.data.canvas_size[0],doc.data.canvas_size[1])),false)

func show_export_options() -> void:
	var dialog := DialogShell.new()
	dialog.title = "导出地图图片"
	dialog.ok_button_text = "选择保存位置"
	add_child(dialog)
	var mode := OptionButton.new()
	mode.add_item("单张 PNG（最长边 8192）")
	mode.add_item("分块图集（最长边 65536）")
	mode.select(1 if export_options.tiled else 0)
	dialog.content.add_child(mode)
	var scope := OptionButton.new()
	scope.add_item("范围：全图")
	scope.add_item("范围：当前视野")
	scope.add_item("范围：固定导出框")
	for region in doc.data.production.regions: scope.add_item("书签：" + region.name)
	scope.select(1 if export_options.scope == "current" else (2 if export_options.scope == "fixed" else 0))
	dialog.content.add_child(scope)
	var fixed: Rect2 = export_options.region if export_options.region.has_area() else canvas.visible_world_rect()
	var fixed_x := _spin(dialog.content, "固定框 X", 0, doc.data.canvas_size[0], 0.1)
	var fixed_y := _spin(dialog.content, "固定框 Y", 0, doc.data.canvas_size[1], 0.1)
	var fixed_w := _spin(dialog.content, "固定框宽", 1, doc.data.canvas_size[0], 0.1)
	var fixed_h := _spin(dialog.content, "固定框高", 1, doc.data.canvas_size[1], 0.1)
	fixed_x.value = fixed.position.x; fixed_y.value = fixed.position.y
	fixed_w.value = fixed.size.x; fixed_h.value = fixed.size.y
	var fixed_fields := [fixed_x, fixed_y, fixed_w, fixed_h]
	var longest := _spin(dialog.content,"输出最长边（像素）",320,65536,1)
	longest.value = export_options.longest
	var tile := OptionButton.new()
	tile.add_item("每块 1024 × 1024")
	tile.add_item("每块 2048 × 2048")
	tile.select(1 if export_options.tile_size == 2048 else 0)
	dialog.content.add_child(tile)
	var layer_mode := OptionButton.new()
	for name in ["合成图", "透明地形层", "透明城关层", "透明标注层"]: layer_mode.add_item(name)
	layer_mode.select(["composite", "terrain", "sites", "labels"].find(export_options.layer))
	dialog.content.add_child(layer_mode)
	if canvas.depth_enabled():
		var depth_note:=_label("已按落点遮挡：请用合成图保留树与城市的交错关系；单独图层用于后期编辑，直接叠放不能还原该关系。",13)
		depth_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		dialog.content.add_child(depth_note)
	var preset := OptionButton.new()
	preset.add_item("展示预设（干净成图）")
	preset.add_item("结构调试预设")
	preset.select(1 if export_options.preset == "debug" else 0)
	dialog.content.add_child(preset)
	var labels := CheckBox.new(); labels.text = "包含地名"; labels.button_pressed = export_options.include_labels; dialog.content.add_child(labels)
	var auxiliaries := CheckBox.new(); auxiliaries.text = "包含作者辅助对象"; auxiliaries.button_pressed = export_options.include_auxiliary; dialog.content.add_child(auxiliaries)
	var transparent := CheckBox.new(); transparent.text = "透明底图"; transparent.button_pressed = export_options.transparent; dialog.content.add_child(transparent)
	var strict_labels := CheckBox.new(); strict_labels.text = "标注触及导出框时阻止导出"; strict_labels.button_pressed = export_options.get("label_clip","allow") == "block"; dialog.content.add_child(strict_labels)
	var detail := _label("",14)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.content.add_child(detail)
	var refresh := func():
		for field in fixed_fields: field.visible = scope.selected == 2
		var region := Rect2(Vector2.ZERO, Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1]))
		if scope.selected == 1: region = canvas.visible_world_rect()
		elif scope.selected == 2: region = Rect2(fixed_x.value,fixed_y.value,fixed_w.value,fixed_h.value)
		elif scope.selected >= 3:
			var bookmark: Dictionary = doc.data.production.regions[scope.selected-3]
			region = Rect2(bookmark.rect[0],bookmark.rect[1],bookmark.rect[2],bookmark.rect[3])
		var layout := Exporter.plan(region.size,int(longest.value),1024 if tile.selected == 0 else 2048)
		var valid: bool = layout.error.is_empty() and Rect2(Vector2.ZERO,Vector2(doc.data.canvas_size[0],doc.data.canvas_size[1])).encloses(region) and (mode.selected == 1 or longest.value <= 8192)
		dialog.get_ok_button().disabled = not valid
		detail.text = ("预计 %d × %d 像素，共 %d 块。\n" % [layout.size.x,layout.size.y,layout.tiles.size()] if layout.error.is_empty() else layout.error)+"所有分块共享连续地图坐标；单图附 JSON 来源索引。参考图、网格和起终点不导出。"+("\n范围无效或单图超过 8192。" if not valid else "")
	scope.item_selected.connect(func(_i): refresh.call())
	mode.item_selected.connect(func(_i): refresh.call())
	longest.value_changed.connect(func(_v): refresh.call())
	tile.item_selected.connect(func(_i): refresh.call())
	for field in fixed_fields: field.value_changed.connect(func(_v): refresh.call())
	layer_mode.item_selected.connect(func(i):
		if i != 0: transparent.button_pressed = true
		refresh.call())
	dialog.confirmed.connect(func():
		var region := Rect2()
		if scope.selected == 1: region = canvas.visible_world_rect()
		elif scope.selected == 2: region = Rect2(fixed_x.value,fixed_y.value,fixed_w.value,fixed_h.value)
		elif scope.selected >= 3:
			var bookmark: Dictionary = doc.data.production.regions[scope.selected-3]
			region = Rect2(bookmark.rect[0],bookmark.rect[1],bookmark.rect[2],bookmark.rect[3])
		export_options = {"longest":int(longest.value),"tiled":mode.selected == 1,"tile_size":1024 if tile.selected == 0 else 2048,"region":region,"scope":"whole" if scope.selected == 0 else ("current" if scope.selected == 1 else ("fixed" if scope.selected == 2 else "bookmark")),"layer":["composite","terrain","sites","labels"][layer_mode.selected],"preset":"debug" if preset.selected == 1 else "display","transparent":transparent.button_pressed,"include_labels":labels.button_pressed,"include_auxiliary":auxiliaries.button_pressed,"label_clip":"block" if strict_labels.button_pressed else "allow"}
		_choose_file("tiles" if export_options.tiled else "png")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(600,650))
	refresh.call()

func export_map(path: String, longest: int, tiled: bool, tile_size: int = 2048) -> String:
	if DisplayServer.get_name() == "headless": return "PNG 导出需要图形模式。"
	if exporting: return "已有导出正在进行。"
	exporting = true
	var worker = Exporter.new()
	add_child(worker)
	var dialog := DialogShell.new()
	dialog.title = "正在导出"
	dialog.dialog_text = "准备图片…"
	add_child(dialog)
	dialog.canceled.connect(func(): worker.cancelled = true; dialog.show())
	worker.progress.connect(func(done,total):
		var label := dialog.content.get_child(0) as Label
		label.text = "正在导出 %d / %d 块。可取消；完成后才发布索引。" % [done,total])
	dialog.popup_centered(Vector2i(500,200))
	dialog.get_ok_button().hide()
	var error: String = await worker.run(doc,path,longest,tiled,tile_size,export_options.region,export_options)
	worker.queue_free()
	dialog.queue_free()
	exporting = false
	return error

func _status(text: String) -> void:
	if is_instance_valid(status): status.text = text

func _show_help() -> void:
	var help := DialogShell.new()
	help.title = "山河工坊 · 基础操作"
	help.ok_button_text = "关闭"
	help.cancel_button_text = "返回"
	help.dialog_text = "手工搭地图：\n1. 左侧搜索 / 分类后，单击素材缩略图，自动进入单件点放。\n2. 鼠标移到地图会显示半透明预览；左键每次放一件。拖动不会连刷。部件视觉比例决定大小，预览同步更新。\n3. 右键 / Esc 退出点放，进入选择美术部件；左键拖动调整位置，Delete 删除，Ctrl+Z 撤销。\n4. 铺树林等需要连刷时，另选“美术画笔 / 拖动连续绘制”。\n5. 中键 / 空格＋左键移动画布，滚轮缩放。先另存为自己的 .map.json，之后 Ctrl+S 保存。\n\n"
	help.dialog_text += "工作区：拖左右面板之间的竖向分隔线调整宽度；拖面板标题栏浮动，点“收回”归位。面板关闭后，可从顶部“工具面板 / 属性面板”恢复，“重置布局”恢复默认。\n弹窗：拖标题栏移动，拖右下角调整大小；× / 取消 / Esc 关闭。长内容单独滚动，底部操作一直可见。\n画布：选择“抓手”后左键拖动，也可用中键或空格＋左键；滚轮缩放。\n\n1. 导入参考图 → 设置不透明度、位置、大小与旋转；再次导入添加分图，设置页顶部切换。先解锁才能移动。\n2. 选择高山、水域或边界线 → 逐点点击并按 Enter，或切换自由画笔拖画。\n3. 选择 / 移动：拖动对象，或拖黄色顶点；增删顶点使用对应工具。\n4. 网格 / 顶点吸附帮助对齐；右侧可搜索、双击定位、命名、复制、调整层次和锁层；点小地图定位。\n5. 海岸线只是线条；要定义海面，请另绘水域区域。国界、道界不改变归属。\n6. 修改地形后点检查通行。窄谷可放大到起终点都在视野内，勾选“视野精查”并设置格距；每边最多 256 格。局部无路不代表全图无路。关隘须绑定通道。\n7. Ctrl+S 保存；Ctrl+Z / Ctrl+Y 撤销重做；右键 / Esc 取消当前笔画。\n8. 搬迁地图时一起复制 .map.json 和旁边的 .assets 文件夹。导出地图：单图最长边 8192；更大选分块图集（JSON 索引与图片目录一起带走）。导出不含参考图。\n\n当前是作者工具和离线通行预览；未改动正式战役规则。"
	help.dialog_text+="\n\n制作补充：\n• 浏览素材：缩略图、搜索、分类和最近使用；弹窗中双击或确认后直接点放，左侧常驻缩略图单击即可点放。可选中素材后“从素材库删除”，在“已删除”分类中恢复；旧地图与原图片保留。\n• 查找已放置部件：可定位被遮挡或锁定的山树。相同编组名称可整组拖动、复制、锁定、解锁和删除，整组操作一次撤销。\n• 命名快照：保存已应用地图和未应用属性、表现线、画笔与视角；恢复后仍需明确应用并另存。\n• 未应用输入遇到拖动、撤销、切图或保存会提示，取消保留输入。\n• 按落点遮挡使用美术占地，不修改行军；请用合成导出保留树城交错关系。"
	help.dialog_text+="\n\n水系工具（左侧顶部）：\n• 河流画笔：设定河宽后拖画，松开应用；端点可吸附到其他河道。\n• 河流橡皮：调整半径后拖擦，擦中间会分成独立河段。\n• 拖弯河道：直接按住河道拖动，半径控制受影响范围。\n• 调整河宽：设定目标河宽后在河道上涂抹；勾选整条河段可统一改宽。\n• 湖泊画笔 / 橡皮：涂出湖面、扩展岸线、擦出缺口或岛屿。\n• 松开鼠标提交一笔，Ctrl+Z 撤销；右键 / Esc 取消。失败笔画保留，可调参数后 Enter 重试。中键或滚轮导航会取消正在画的笔画。\n• 原有裁切范围继续保留；隐藏或受保护水域不会被橡皮误擦。水系工具会隐藏通行标注，需要时可重新开启。"
	help.confirmed.connect(help.queue_free)
	help.canceled.connect(help.queue_free)
	add_child(help)
	help.popup_centered(Vector2i(720,500))

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	for child in get_children():
		if child is DialogShell and child.visible: return
	if event.ctrl_pressed:
		if event.keycode == KEY_S: save_current(); get_viewport().set_input_as_handled()
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if event.keycode == KEY_Z:
			_request_history(event.shift_pressed)
			get_viewport().set_input_as_handled()
		if event.keycode == KEY_Y: _request_history(true); get_viewport().set_input_as_handled()
