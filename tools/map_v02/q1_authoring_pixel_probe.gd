extends "res://final/acceptance.gd"
var probe_index:=0
func pixel_hash(app,point: Array) -> String:
	var at: Vector2=app.canvas.global_position+app.canvas.screen(point)
	var image=root.get_texture().get_image()
	var old_rect:=Rect2i(Vector2i(at-Vector2(35,48)),Vector2i(70,65))
	# The legacy guard treated logical Control coordinates as texture pixels.
	# Transform the identical logical crop into the actual stretched buffer.
	var stretch: Transform2D=root.get_stretch_transform()
	var top_left: Vector2=stretch*(at-Vector2(35,48));var bottom_right: Vector2=stretch*(at+Vector2(35,17))
	var rect:=Rect2i(Vector2i(top_left),Vector2i(bottom_right-top_left))
	if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect):return "outside"
	var region=image.get_region(rect);var name:="protected_%02d"%probe_index
	region.save_png(output.get_base_dir()+"/"+name+".png")
	var rows: Array=[]
	for object in app.host.state.objects.values():
		if Vector2(object.position_m[0]-point[0],object.position_m[1]-point[1]).length()<180:rows.append(object)
	var old_hash: Variant=null
	if Rect2i(Vector2i.ZERO,image.get_size()).encloses(old_rect):old_hash=image.get_region(old_rect).get_data().hex_encode().sha256_text()
	var details={"probe":probe_index,"actual_image_size":image.get_size(),"logical_content_size":root.content_scale_size,"stretch":str(stretch),"stretch_scale":[stretch.get_scale().x,stretch.get_scale().y],"tree_world":point,"tree_screen_logical":at,"tree_screen_physical":stretch*at,"canvas_size":app.canvas.size,"canvas_position":app.canvas.global_position,"old_incorrect_crop":old_rect,"old_incorrect_crop_hash":old_hash,"physical_crop":rect,"nearby_objects":rows,"protected_hash":app.host.protected_hash()}
	FileAccess.open(output.get_base_dir()+"/"+name+".json",FileAccess.WRITE).store_string(JSON.stringify(details,"\t"));probe_index+=1
	return region.get_data().hex_encode().sha256_text()
