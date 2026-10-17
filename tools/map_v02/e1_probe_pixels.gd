extends SceneTree
func _initialize() -> void:
	create_timer(30).timeout.connect(func():printerr("E1_PIXEL_PROBE_TIMEOUT");quit(1))
	call_deferred("run")
func run() -> void:
	for name in ["trees.png","gate_eastwest.png"]:
		var path: String="res://v02/e1/packages/lab/assets/"+str(name)
		var texture=load(path) as Texture2D
		var imported=texture.get_image();imported.clear_mipmaps();imported.convert(Image.FORMAT_RGBA8)
		var source=Image.new();source.load_png_from_buffer(FileAccess.get_file_as_bytes(path+".bin"));source.convert(Image.FORMAT_RGBA8)
		var a=imported.get_data();var b=source.get_data();var differences:=0;var first: Array=[]
		for i in a.size():
			if a[i]!=b[i]:
				differences+=1
				if first.size()<12:first.append([i,a[i],b[i]])
		print("E1_PIXELS ",JSON.stringify({"name":name,"different_bytes":differences,"first":first}))
	quit(0)
