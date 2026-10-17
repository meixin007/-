extends "res://v02/e3/coverage_planner.gd"
## Texture LOD has its own hysteresis, independent of settlement semantics.
var selected_level:=0
func bind(loader: RefCounted) -> void:super.bind(loader);selected_level=0
func plan(view: Rect2,zoom: float,prefetch: bool=true) -> Dictionary:
	var levels: Array=grids.keys();levels.sort()
	for candidate in levels:
		if candidate>selected_level and float(grids[candidate].cell)*zoom>180*1.15:selected_level=int(candidate)
	while selected_level>int(levels[0]) and float(grids[selected_level].cell)*zoom<180*.85:selected_level-=1
	var density_zoom: float=180.01/float(grids[selected_level].cell)
	var result: Dictionary=super.plan(view,density_zoom,prefetch)
	selected_level=int(result.level);result.requested_zoom=zoom;return result
