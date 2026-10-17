extends "res://v02/c1/app.gd"
## The accepted C1 map and rules are unchanged; only release status text differs.
func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is Label and child.position.y==58:child.text="C1 已通过　·　滚轮连续缩放 / 拖动平移 / 点击地点　·　v0.2 潼关样板"
func _process(delta: float) -> void:
	super._process(delta)
	if errors.is_empty() and note!=null:note.text="C1 已通过 · 本地 v0.2 样板"
