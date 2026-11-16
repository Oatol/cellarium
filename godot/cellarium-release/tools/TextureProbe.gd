extends SceneTree
## 诊断：guide-icon 的实际不透明边界与纹理中心，判断是否存在内缩留白。

func _initialize() -> void:
	var paths: Array[String] = [
		"res://assets/apk_local/guide-icons/zygocyte.png",
		"res://assets/apk_local/guide-icons/myocyte.png",
		"res://assets/apk_local/guide-icons/photocyte.png"
	]
	for path in paths:
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			print("TextureProbe MISSING ", path)
			continue
		var image: Image = texture.get_image()
		var width: int = image.get_width()
		var height: int = image.get_height()
		var min_x: int = width
		var min_y: int = height
		var max_x: int = -1
		var max_y: int = -1
		for y in range(height):
			for x in range(width):
				if image.get_pixel(x, y).a > 0.03:
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
		print("TextureProbe ", path.get_file(), " size=", width, "x", height,
			" alpha_bbox=(", min_x, ",", min_y, ")-(", max_x, ",", max_y, ")")
	quit(0)
