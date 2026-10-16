@tool
extends VBoxContainer
const Audit=preload("map_audit.gd")
const STATUS_KEYS: Array[String]=["todo","reviewing","deferred"]
const STATUS_NAMES: Array[String]=["待处理","核对中","暂缓（仍有问题）"]
var doc: RefCounted
var canvas: Control
var close_tools: Callable
var region: OptionButton
var severity: OptionButton
var summary: Label
var list: ItemList
var detail: Label
var state: OptionButton
var note: TextEdit
var links: HBoxContainer
var feedback: Label
var issues: Array=[]
var visible_issues: Array=[]
var chosen: Dictionary={}
var scan_signature:=""
func setup(document: RefCounted,view: Control,close: Callable) -> void:
	doc=document; canvas=view; close_tools=close
	doc.changed.connect(_document_changed)
	var row:=HBoxContainer.new(); add_child(row)
	region=OptionButton.new(); region.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(region)
	region.add_item("全图问题"); region.set_item_metadata(0,"")
	for r in doc.data.production.regions:
		region.add_item(r.name); region.set_item_metadata(region.item_count-1,r.id)
	region.item_selected.connect(func(_i): _rebuild_list())
	severity=OptionButton.new(); row.add_child(severity)
	for name in ["全部级别","错误","警告"]: severity.add_item(name)
	severity.item_selected.connect(func(_i): _rebuild_list())
	var refresh:=Button.new(); refresh.text="重新扫描问题"; refresh.pressed.connect(scan); row.add_child(refresh)
	summary=label("")
	list=ItemList.new(); list.custom_minimum_size.y=135; list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(list)
	list.item_selected.connect(func(index): _select(visible_issues[index]))
	detail=label("选中问题可定位相关对象，并记录处理依据。")
	links=HBoxContainer.new(); add_child(links)
	state=OptionButton.new(); add_child(state)
	for name in STATUS_NAMES: state.add_item(name)
	note=TextEdit.new(); note.custom_minimum_size.y=90; note.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	note.placeholder_text="记录资料出处、待核原因或修改计划；暂缓不会消除警告。"; add_child(note)
	var save:=Button.new(); save.text="保存处理备注"; save.pressed.connect(save_review); add_child(save)
	feedback=label("")
	scan()
func label(text: String) -> Label:
	var value:=Label.new(); value.text=text; value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(value); return value
func _document_changed() -> void:
	if scan_signature != doc.fingerprint(): summary.text="文档已修改，列表可能过期；请重新扫描。"
func scan() -> void:
	issues=Audit.inspect(doc); scan_signature=doc.fingerprint(); _rebuild_list()
func _rebuild_list() -> void:
	var prior: String=chosen.get("id","")
	visible_issues.clear(); list.clear(); chosen={}
	var scope:=Rect2(); var id: String=region.get_selected_metadata()
	for r in doc.data.production.regions:
		if r.id == id: scope=Rect2(r.rect[0],r.rect[1],r.rect[2],r.rect[3])
	var errors:=0
	for issue in issues:
		if issue.severity == "error": errors+=1
		if scope.has_area() and not Audit.in_region(doc,issue,scope): continue
		if severity.selected>0 and issue.severity != ("error" if severity.selected==1 else "warning"): continue
		visible_issues.append(issue)
		var review: Dictionary=doc.data.production.get("audit_reviews",{}).get(issue.id,{})
		var status: String=review.get("status","todo")
		var badge: String=STATUS_NAMES[STATUS_KEYS.find(status)]
		if not review.is_empty() and review.evidence != issue.evidence: badge="依据已变，需复核"
		list.add_item("[%s] %s" % [badge,issue.message])
		list.set_item_tooltip(list.item_count-1,issue.message)
	summary.text="全图 %d 项：%d 错误 / %d 警告。当前筛选显示 %d 项，备注不会隐藏问题。" % [issues.size(),errors,issues.size()-errors,visible_issues.size()]
	if scan_signature != doc.fingerprint(): summary.text+=" 文档已有修改，请重扫。"
	var selected_index:=0
	for i in range(visible_issues.size()):
		if visible_issues[i].id==prior: selected_index=i
	if not visible_issues.is_empty(): list.select(selected_index); _select(visible_issues[selected_index])
	else:
		detail.text="当前筛选没有问题；这不代表历史地理或正式通行已验收。"; note.text=""; state.select(0); _clear_links()
func _clear_links() -> void:
	for child in links.get_children(): links.remove_child(child); child.queue_free()
func _select(issue: Dictionary) -> void:
	chosen=issue
	detail.text=issue.message
	_clear_links()
	for id in [issue.feature_id]+issue.get("related_ids",[]):
		var f: Dictionary=doc.find_feature(id)
		if f.is_empty(): continue
		var button:=Button.new(); button.text="定位："+f.name; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; links.add_child(button)
		button.pressed.connect(func(): canvas.locate_feature(id); close_tools.call())
	var review: Dictionary=doc.data.production.get("audit_reviews",{}).get(issue.id,{})
	state.select(STATUS_KEYS.find(review.get("status","todo"))); note.text=review.get("note","")
	feedback.text=""
	if not review.is_empty() and review.evidence != issue.evidence: feedback.text="关联对象已经改变，旧备注仅供参考；请重新核对后保存。"
func save_review() -> void:
	if chosen.is_empty(): feedback.text="请先选择问题。"; return
	if chosen.evidence != Audit.evidence(doc,chosen): feedback.text="问题依据已改变，请重新扫描后再记录。"; return
	var review: Dictionary={"status":STATUS_KEYS[state.selected],"note":note.text.strip_edges(),"evidence":chosen.evidence}
	if not doc.set_issue_review(chosen.id,review): feedback.text="未保存：核对 / 暂缓必须填写原因，最多 4000 字；或内容未变化。"; return
	scan(); feedback.text="处理备注已保存，可撤销；问题仍保留，实际修正后重新扫描确认。"
