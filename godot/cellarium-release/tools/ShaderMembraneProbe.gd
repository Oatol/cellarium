extends SceneTree
## v0.52.0 渲染第二步原型闸门：验证 Godot 4 canvas_item shader 能用
## MultiMesh 的 INSTANCE_CUSTOM 索引一张 RGBA32F 参数纹理，从单个 quad 里
## 画出「被接触弦切平的膜 + 外轮廓 + 内膜环 + 核 + 细胞器」。
##
## 这是把 Cell Lab「每对象固定 6 顶点 + fragment 造形」搬到本项目的可行性前提。
## 需要真实窗口（headless 无渲染），像素断言全部程序化，不截图、不动鼠标。
## 运行：Godot_v4.7.2-stable_win64_console.exe --path <project> --resolution 400x300 \
##        --script res://tools/ShaderMembraneProbe.gd

const SHADER_PATH: String = "res://shaders/cell_membrane.gdshader"
const PARAM_TEXELS: int = 16
const CELL_RADIUS: float = 40.0

var _failures: int = 0
var _checks: int = 0

const BG: Color = Color(0.05, 0.05, 0.08, 1.0)
const BODY: Color = Color(1.0, 0.2, 0.2, 0.6)
const OUTLINE: Color = Color(0.1, 0.05, 0.05, 1.0)

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("ShaderMembraneProbe: " + message)

func _run() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("ShaderMembraneProbe: shader missing " + SHADER_PATH)
		print("ShaderMembraneProbe: checks=0 failures=1")
		quit(1)
		return

	# 背景板：给像素断言一个确定底色。
	var bg: ColorRect = ColorRect.new()
	bg.color = BG
	bg.size = Vector2(400, 300)
	root.add_child(bg)

	# 三个细胞：A 与 B 重叠（产生一条共享弦），C 独立。
	var centers: Array[Vector2] = [Vector2(100, 100), Vector2(140, 100), Vector2(300, 200)]
	var chords: Array = [
		# A 的弦：radical line x=120 → 局部归一化 (0.5, ±0.866)
		[[Vector2(0.5, -0.866), Vector2(0.5, 0.866)]],
		# B 的弦：镜像
		[[Vector2(-0.5, 0.866), Vector2(-0.5, -0.866)]],
		[],
	]
	var params: PackedFloat32Array = PackedFloat32Array()
	params.resize(centers.size() * PARAM_TEXELS * 4)
	for i in range(centers.size()):
		var base: int = i * PARAM_TEXELS * 4
		params[base + 0] = BODY.r
		params[base + 1] = BODY.g
		params[base + 2] = BODY.b
		params[base + 3] = BODY.a
		params[base + 4] = OUTLINE.r
		params[base + 5] = OUTLINE.g
		params[base + 6] = OUTLINE.b
		params[base + 7] = OUTLINE.a
		# 核与细胞器关闭：本闸门只验证膜裁剪与轮廓，避免与中心像素断言冲突。
		params[base + 8] = 0.0
		params[base + 9] = 0.0
		params[base + 10] = 0.0
		params[base + 11] = 0.0
		params[base + 12] = 0.0
		params[base + 13] = 0.0
		params[base + 14] = 0.0
		params[base + 15] = 0.0
		for chord_index in range(chords[i].size()):
			var pair: Array = chords[i][chord_index]
			var offset: int = base + (4 + chord_index / 2) * 4
			var a: Vector2 = pair[0]
			var b: Vector2 = pair[1]
			if chord_index % 2 == 0:
				params[offset + 0] = a.x
				params[offset + 1] = a.y
				params[offset + 2] = b.x
				params[offset + 3] = b.y
			else:
				params[offset + 0] = b.x
				params[offset + 1] = b.y
				params[offset + 2] = a.x
				params[offset + 3] = a.y

	var image: Image = Image.create(centers.size() * PARAM_TEXELS, 1, false, Image.FORMAT_RGBAF)
	for texel in range(centers.size() * PARAM_TEXELS):
		var o: int = texel * 4
		image.set_pixel(texel, 0, Color(params[o], params[o + 1], params[o + 2], params[o + 3]))
	var param_texture: ImageTexture = ImageTexture.create_from_image(image)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = centers.size()
	for i in range(centers.size()):
		var xform: Transform2D = Transform2D(
			Vector2(CELL_RADIUS * 2.0, 0.0), Vector2(0.0, CELL_RADIUS * 2.0), centers[i]
		)
		multimesh.set_instance_transform_2d(i, xform)
		multimesh.set_instance_custom_data(i, Color(float(i), 0.0, 0.0, 0.0))

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cell_params", param_texture)
	material.set_shader_parameter("cell_count", centers.size())
	material.set_shader_parameter("tex_width", float(centers.size() * PARAM_TEXELS))

	var layer: MultiMeshInstance2D = MultiMeshInstance2D.new()
	layer.multimesh = multimesh
	layer.material = material
	root.add_child(layer)

	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

	var captured: Image = root.get_texture().get_image()
	if captured == null:
		push_error("ShaderMembraneProbe: viewport readback failed")
		print("ShaderMembraneProbe: checks=%d failures=%d" % [_checks, _failures + 1])
		quit(1)
		return

	var width: int = captured.get_width()
	var height: int = captured.get_height()
	print("ShaderMembraneProbe: viewport=%dx%d" % [width, height])

	_check(width >= 400 and height >= 300, "viewport smaller than expected")

	# 1) 细胞 A 体内：应读到 body 色叠在背景上（r 高、g 低）。
	var body_pixel: Color = captured.get_pixel(100, 100)
	print("ShaderMembraneProbe: body=(%.3f,%.3f,%.3f,%.3f)" % [
		body_pixel.r, body_pixel.g, body_pixel.b, body_pixel.a
	])
	_check(body_pixel.r > 0.5, "cell body must be visible at center (r=%.3f)" % body_pixel.r)
	_check(body_pixel.g < 0.3, "cell body must not be background (g=%.3f)" % body_pixel.g)

	# 2) 背景：远离所有细胞处必须是背景色。
	var bg_pixel: Color = captured.get_pixel(360, 40)
	_check(absf(bg_pixel.r - BG.r) < 0.06 and absf(bg_pixel.g - BG.g) < 0.06,
		"far pixel must stay background (%.3f,%.3f)" % [bg_pixel.r, bg_pixel.g])

	# 3) 弦裁剪：A 的右侧被切平在 x=120。x=118 落在切面上 → 必须是外轮廓色（暗）。
	var clip_pixel: Color = captured.get_pixel(118, 100)
	print("ShaderMembraneProbe: clip=(%.3f,%.3f,%.3f,%.3f)" % [
		clip_pixel.r, clip_pixel.g, clip_pixel.b, clip_pixel.a
	])
	_check(clip_pixel.r < 0.35 and clip_pixel.g < 0.35,
		"chord face must be drawn as outline (r=%.3f g=%.3f)" % [clip_pixel.r, clip_pixel.g])

	# 4) 弦外侧（A 的 x=124 已在圆外或被切掉）不得再有 A 的红色。
	var outside_pixel: Color = captured.get_pixel(124, 100)
	print("ShaderMembraneProbe: outside=(%.3f,%.3f,%.3f,%.3f)" % [
		outside_pixel.r, outside_pixel.g, outside_pixel.b, outside_pixel.a
	])
	_check(outside_pixel.r < 0.95, "clipped region must not keep full body color")

	# 5) 独立细胞 C 完整：中心是 body 色。
	var solo_pixel: Color = captured.get_pixel(300, 200)
	_check(solo_pixel.r > 0.5, "standalone cell body must be visible (r=%.3f)" % solo_pixel.r)

	print("ShaderMembraneProbe: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
