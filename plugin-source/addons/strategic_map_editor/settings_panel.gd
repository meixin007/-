@tool
extends "dialog_shell.gd"
## Small authoring dialogs; all changes go through the document undo history.
signal reported(text: String)
signal reference_selected(id: String)
signal reference_import_requested
var doc: RefCounted
var fields: Dictionary = {}
var settings_kind := ""
var aspect := 1.0
var adjusting := false
var reference_id := "primary"

func _ready() -> void:
	super._ready()
	confirmed.connect(_apply)
	ok_button_text = "应用设置"
	cancel_button_text = "取消"

func _reset(value: RefCounted, next_mode: String) -> void:
	doc = value
	settings_kind = next_mode
	fields.clear()
	clear_content()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _number(key: String, text: String, value: float, minimum: float, maximum: float, step: float = 1) -> SpinBox:
	var row := HBoxContainer.new()
	content.add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 170
	row.add_child(spin)
	fields[key] = spin
	return spin

func _toggle(key: String, text: String, value: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	content.add_child(box)
	fields[key] = box
	return box

func show_reference(value: RefCounted, id: String = "primary") -> void:
	_reset(value,"reference")
	reference_id = id if not doc.get_reference(id).is_empty() else "primary"
	title = "参考图设置"
	var selector := OptionButton.new()
	content.add_child(selector)
	for item in doc.references():
		var index := selector.item_count
		selector.add_item(("主参考图" if index == 0 else "分图 %d" % index)+" · "+item.path.get_file())
		selector.set_item_metadata(index,item.get("id","primary"))
		if item.get("id","primary") == reference_id: selector.select(index)
	selector.item_selected.connect(func(i):
		var chosen: String = selector.get_item_metadata(i)
		reference_selected.emit(chosen)
		show_reference(doc,chosen))
	var add := Button.new()
	add.text = "添加参考分图…"
	content.add_child(add)
	add.pressed.connect(func(): hide(); reference_import_requested.emit())
	var ref: Dictionary = doc.get_reference(reference_id)
	_label("参考图："+ ("尚未导入，请先使用“导入参考图”" if ref.path.is_empty() else ref.path.get_file()))
	_toggle("visible","显示参考图",ref.visible)
	_toggle("above_art","叠在地形上方，便于描摹",ref.above_art)
	_number("opacity","不透明度（%）",ref.opacity*100,0,100)
	var lock := _toggle("locked","锁定位置与尺寸",ref.locked)
	_number("x","左上角 X",ref.position[0],-65536,65536)
	_number("y","左上角 Y",ref.position[1],-65536,65536)
	_number("w","宽度",ref.size[0],1,65536)
	_number("h","高度",ref.size[1],1,65536)
	_number("rotation","绕中心旋转（度）",ref.rotation,-180,180,0.1)
	aspect = float(ref.size[0])/float(ref.size[1])
	_toggle("aspect","调整尺寸时保持比例",true)
	fields.w.value_changed.connect(func(v): _resize_reference("h",v/aspect))
	fields.h.value_changed.connect(func(v): _resize_reference("w",v*aspect))
	lock.toggled.connect(_lock_reference_fields)
	_lock_reference_fields(ref.locked)
	var fit := Button.new()
	fit.text = "等比适合画布并居中（先解锁）"
	content.add_child(fit)
	fit.pressed.connect(func():
		if fields.locked.button_pressed: return
		var w: float = minf(doc.data.canvas_size[0],doc.data.canvas_size[1]*aspect)
		adjusting = true
		fields.w.value = w
		fields.h.value = w/aspect
		fields.x.value = (doc.data.canvas_size[0]-w)*0.5
		fields.y.value = (doc.data.canvas_size[1]-w/aspect)*0.5
		adjusting = false)
	_label("先应用再切换分图。解锁并应用后，“移动参考图”拖动当前选中的分图。所有分图共用地图坐标；预览按视野加载，原图随工程保存在 .assets 文件夹，不进入导出图片。")
	var clear := Button.new()
	clear.text = "移除参考图（可撤销）"
	content.add_child(clear)
	clear.pressed.connect(func(): doc.remove_reference(reference_id); hide(); reported.emit("已移除参考图，可撤销。"))
	popup_centered(Vector2i(500,590))

func _resize_reference(key: String, value: float) -> void:
	if adjusting or not fields.aspect.button_pressed: return
	adjusting = true
	fields[key].value = value
	adjusting = false

func _lock_reference_fields(locked: bool) -> void:
	for key in ["x","y","w","h","rotation"]: fields[key].editable = not locked

func show_canvas(value: RefCounted) -> void:
	_reset(value,"canvas")
	title = "地图与画布设置"
	_label("地图名称")
	var name_field := LineEdit.new()
	name_field.text = doc.data.title
	content.add_child(name_field)
	fields["title"] = name_field
	_number("w","画布宽度",doc.data.canvas_size[0],320,65536)
	_number("h","画布高度",doc.data.canvas_size[1],320,65536)
	_toggle("scale","同步缩放全部地形、线条与参考图",true)
	_label("取消同步缩放可扩大空白边缘；裁掉已有对象时会拒绝缩小。有旋转参考图时，同步缩放须保持画布比例。单位为图面坐标；导出分辨率另设，未绑定真实公里数。修改可整体撤销。")
	popup_centered(Vector2i(500,320))

func _apply() -> void:
	var changed := false
	if settings_kind == "reference":
		var values := {"visible":fields.visible.button_pressed,"above_art":fields.above_art.button_pressed,"locked":fields.locked.button_pressed,"opacity":fields.opacity.value/100.0}
		# Disabled numerical controls can round their display; never move a locked image as a side effect.
		if not doc.get_reference(reference_id).locked or not values.locked:
			values.position = [fields.x.value,fields.y.value]
			values.size = [fields.w.value,fields.h.value]
			values.rotation = fields.rotation.value
		changed = doc.update_reference(values,reference_id)
	else:
		changed = doc.configure_canvas(fields.title.text,Vector2i(fields.w.value,fields.h.value),fields.scale.button_pressed)
	reported.emit("设置已应用，可撤销。" if changed else "设置未改变，或超出允许范围；请检查尺寸、锁定及越界对象。")
