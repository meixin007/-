@tool
extends "dialog_shell.gd"
## A visual picker over the current resource bundle; browsing never paints the map.
const Catalog=preload("art_catalog.gd")
signal asset_chosen(asset: String)
signal library_changed(asset: String, deleted: bool)
var library: RefCounted
var bundle_id:="tongguan_v1"
var recent_assets: Array=[]
var active_asset:=""
var query: LineEdit
var category: OptionButton
var grid: ItemList
var detail: Label
var delete_button: Button
var restore_button: Button
var delete_confirmation: Control

func _ready() -> void:
	super._ready()
	title="素材浏览 · 双击素材后在地图点放"
	ok_button_text="选中并开始点放"
	var row:=HBoxContainer.new(); content.add_child(row)
	query=LineEdit.new(); query.placeholder_text="搜索名称或素材 ID"; query.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(query)
	category=OptionButton.new()
	for label in ["全部","最近使用","树木","山体","城关","地表","已删除"]: category.add_item(label)
	row.add_child(category)
	grid=preload("art_thumbnail_grid.gd").new(); grid.library=library; grid.custom_minimum_size=Vector2(520,320); grid.max_columns=4
	grid.fixed_column_width=130; grid.fixed_icon_size=Vector2i(104,80); grid.icon_mode=ItemList.ICON_MODE_TOP
	grid.max_text_lines=2; content.add_child(grid)
	detail=Label.new(); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; content.add_child(detail)
	var actions := HBoxContainer.new(); content.add_child(actions)
	delete_button = Button.new(); delete_button.text = "从素材库删除"; actions.add_child(delete_button)
	delete_button.pressed.connect(_request_delete)
	restore_button = Button.new(); restore_button.text = "恢复到素材库"; actions.add_child(restore_button)
	restore_button.pressed.connect(func(): _set_deleted(_selected_key(), false))
	query.text_changed.connect(func(_v): refresh())
	category.item_selected.connect(func(_i): refresh())
	grid.item_selected.connect(_selection_changed)
	grid.item_activated.connect(func(_i): _choose())
	confirmed.connect(_choose); canceled.connect(queue_free)
	refresh()

func available_keys(deleted: bool = false) -> Array:
	var keys: Array=[] if deleted else ["mixed_forest"]
	for key in Catalog.library_keys(deleted):
		if Catalog.bundle_contains(bundle_id,Catalog.asset_bundle(key)): keys.append(key)
	return keys

func refresh() -> void:
	grid.clear()
	var allowed:=available_keys(category.selected == 6)
	var candidates: Array=recent_assets if category.selected==1 else allowed
	var groups: Array=["","","forest","mountain","sites","ground"]
	for key in candidates:
		if key not in allowed: continue
		var descriptor: Dictionary=Catalog.descriptor("tree_grove" if key=="mixed_forest" else key)
		var label: String="混合林缘" if key=="mixed_forest" else Catalog.label(key)
		var group: String=descriptor.get("group","")
		if category.selected>=2 and category.selected<6 and not (group==groups[category.selected] or (category.selected==4 and group in ["city","pass"])): continue
		if not query.text.strip_edges().is_empty() and not (label+" "+key).to_lower().contains(query.text.strip_edges().to_lower()): continue
		var i:=grid.add_item(label)
		grid.set_item_metadata(i,key); grid.set_item_tooltip(i,label+"\n"+key)
		if key==active_asset: grid.select(i)
	if grid.get_selected_items().is_empty() and grid.item_count>0: grid.select(0)
	grid.refresh_icons()
	_selection_changed(-1)

func _selection_changed(_index: int) -> void:
	var selection:=grid.get_selected_items()
	get_ok_button().disabled=selection.is_empty() or category.selected==6
	delete_button.visible=category.selected!=6
	restore_button.visible=category.selected==6
	delete_button.disabled=selection.is_empty() or _selected_key()=="mixed_forest" or not Catalog.library_error().is_empty()
	restore_button.disabled=selection.is_empty() or not Catalog.library_error().is_empty()
	detail.text="没有匹配素材。当前画笔保持不变。" if selection.is_empty() else grid.get_item_text(selection[0])+" · "+str(grid.get_item_metadata(selection[0]))
	if not Catalog.library_error().is_empty(): detail.text=Catalog.library_error()
	elif category.selected==6: detail.text += "\n已从可选素材中移除；旧地图仍可显示，恢复后可再次使用。"

func _selected_key() -> String:
	var selection := grid.get_selected_items()
	return "" if selection.is_empty() else str(grid.get_item_metadata(selection[0]))

func _request_delete() -> void:
	var key := _selected_key()
	if key.is_empty() or key=="mixed_forest": return
	var dialog = preload("dialog_shell.gd").new()
	delete_confirmation = dialog
	dialog.title = "从素材库删除"
	dialog.ok_button_text = "删除素材"
	dialog.dialog_text = "删除“%s”？\n\n删除后不再出现在可选素材中，可在“已删除”中恢复。\n已有地图和自动生成的山树林仍保留原样；原图片文件会保留。" % Catalog.label(key)
	add_child(dialog)
	dialog.confirmed.connect(func(): _set_deleted(key, true); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(520,280))

func _set_deleted(key: String, deleted: bool) -> void:
	var result: Dictionary = Catalog.set_library_deleted(key, deleted)
	if not result.ok: detail.text=result.error; return
	if deleted: recent_assets.erase(key)
	library_changed.emit(key, deleted)
	refresh()
	detail.text=("已从素材库删除，可在“已删除”中恢复：" if deleted else "已恢复到素材库：") + Catalog.label(key)

func _choose() -> void:
	var selection:=grid.get_selected_items()
	if selection.is_empty() or category.selected==6: return
	asset_chosen.emit(str(grid.get_item_metadata(selection[0])))
	queue_free()
