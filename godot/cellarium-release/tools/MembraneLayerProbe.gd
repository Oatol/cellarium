extends SceneTree
## v0.52.0 渲染第二步闸门：真实场景走 CellMembrane（MultiMesh + fragment shader）路径。
##
## 断言三件事：
##   1. 生产路径选中 shader 层，三角批与逐实例档都隐藏；
##   2. 原生 CellRenderCache 的 build_geometry=false 路径确实产出了细胞参数；
##   3. 细胞在屏幕上真的画出来了（像素与邻近背景有差异），且 shader 没有编译错误。
##
## 需要真实窗口；像素断言全部程序化，不截图、不动鼠标。
## 运行：Godot_v4.7.2-stable_win64_console.exe --path <project> --script res://tools/MembraneLayerProbe.gd

const CELL_A: Vector2 = Vector2(240.0, 250.0)
const CELL_B: Vector2 = Vector2(260.0, 250.0)
const CELL_C: Vector2 = Vector2(250.0, 232.0)
## 远离三枚细胞的对照点（仍在皿内）。
const REFERENCE: Vector2 = Vector2(250.0, 268.0)

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("MembraneLayerProbe: " + message)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("MembraneLayerProbe: main.tscn missing")
		print("MembraneLayerProbe: checks=0 failures=1")
		quit(1)
		return
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	await process_frame

	var bus: Node = instance.get_node_or_null("Simulation/CommandBus")
	var tick_core: Node = instance.get_node_or_null("Simulation/TickCore")
	var membrane: Node = instance.get_node_or_null("DishView/CellMembrane")
	var polygon: Node = instance.get_node_or_null("DishView/CellBatchPoly")
	var multimesh_layer: Node = instance.get_node_or_null("DishView/CellBatch")
	if bus == null or tick_core == null or membrane == null or polygon == null or multimesh_layer == null:
		push_error("MembraneLayerProbe: scene nodes missing")
		print("MembraneLayerProbe: checks=0 failures=1")
		quit(1)
		return

	tick_core.set("running", false)
	for position in [CELL_A, CELL_B, CELL_C]:
		bus.call("enqueue", {"type": "SPAWN", "position": position, "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	await process_frame
	membrane.call("mark_dirty")
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

	# 1) 路径选择
	_check(bool(membrane.get("visible")), "CellMembrane must be the production path")
	_check(not bool(polygon.get("visible")), "CellBatchPoly must be hidden on the shader path")
	_check(not bool(multimesh_layer.get("visible")), "legacy MultiMesh layer must stay hidden")

	# 2) 参数确实产出
	var active: int = int(membrane.call("get_active_count"))
	print("MembraneLayerProbe: active=%d" % active)
	_check(active >= 3, "shader layer must receive >= 3 cells (got %d)" % active)

	# 3) 像素
	var captured: Image = root.get_texture().get_image()
	if captured == null:
		_check(false, "viewport readback failed")
		print("MembraneLayerProbe: checks=%d failures=%d" % [_checks, _failures])
		quit(1)
		return
	var canvas: Transform2D = root.get_canvas_transform()
	var cell_px: Vector2 = canvas * CELL_A
	var ref_px: Vector2 = canvas * REFERENCE
	var width: int = captured.get_width()
	var height: int = captured.get_height()
	_check(cell_px.x >= 0.0 and cell_px.y >= 0.0 and cell_px.x < width and cell_px.y < height,
		"cell must project inside the viewport (%.1f,%.1f)" % [cell_px.x, cell_px.y])
	var cell_color: Color = captured.get_pixel(int(cell_px.x), int(cell_px.y))
	var ref_color: Color = captured.get_pixel(int(ref_px.x), int(ref_px.y))
	var difference: float = absf(cell_color.r - ref_color.r) + absf(cell_color.g - ref_color.g) \
		+ absf(cell_color.b - ref_color.b)
	print("MembraneLayerProbe: cell=(%.3f,%.3f,%.3f) ref=(%.3f,%.3f,%.3f) diff=%.3f" % [
		cell_color.r, cell_color.g, cell_color.b, ref_color.r, ref_color.g, ref_color.b, difference
	])
	_check(difference > 0.15, "cell pixel must differ from background (diff=%.3f)" % difference)

	# shader 失败时通常会整片染成纯色或纯黑，这里顺带排除。
	_check(not (cell_color.r > 0.95 and cell_color.g < 0.05 and cell_color.b > 0.95),
		"magenta pixels indicate a shader compile failure")

	print("MembraneLayerProbe: checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
