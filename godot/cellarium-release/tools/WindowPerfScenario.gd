extends Node
## v0.39 C 路线诊断场景：在真实 Vulkan 窗口里复现用户场景（M1 光合自分裂 × 无限分裂 × 黏附）。
## 不写模拟状态以外的产物；仅用正常 register_zygote API 铺细胞，然后让 main.tscn 自己跑。
## 用 project_run(mode="custom", scene="res://tools/WindowPerfScenario.tscn") 启动。

const TARGET_CELLS: int = 1024
const SPEED_SCALE: float = 3.0

var _manager: Node = null
var _tick_core: Node = null
var _frozen: bool = false

func _process(_delta: float) -> void:
	## 到达目标规模后冻结模拟，保证 A/B 两轮在同一个 1024 细胞场景下对比渲染/合成成本。
	if _frozen or _manager == null or _tick_core == null:
		return
	if int((_manager.get("cells") as RefCounted).call("size")) >= TARGET_CELLS:
		_tick_core.set("running", false)
		_frozen = true
		print("WINDOW_PERF_FROZEN cells=%d tick=%d" % [
			(_manager.get("cells") as RefCounted).call("size"), _tick_core.get("tick_index"),
		])

func _build_toggle_ui() -> void:
	## 诊断按钮（纯视图开关），用于真实窗口逐层定位 draw call；不写模拟状态。
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(620.0, 180.0)
	canvas.add_child(box)
	var specs: Array = [
		["POST", "Main/UI/Postprocess"],
		["LINKS", "Main/DishView/LinkLayer"],
		["SCENE", "Main/DishView/CellSceneLayer"],
		["CELLS", "Main/DishView/CellLayer"],
		["POLY", "Main/DishView/CellBatchPoly"],
		["BATCH", "Main/DishView/CellBatch"],
	]
	for spec in specs:
		var button: Button = Button.new()
		button.name = "Toggle" + str(spec[0])
		button.text = str(spec[0]) + " toggle"
		button.custom_minimum_size = Vector2(120.0, 24.0)
		box.add_child(button)
		button.pressed.connect(_on_toggle_pressed.bind(str(spec[1])))

func _on_toggle_pressed(node_path: String) -> void:
	var node: Node = get_node_or_null(node_path)
	if node == null:
		print("WINDOW_TOGGLE missing ", node_path)
		return
	node.visible = not node.visible
	print("WINDOW_TOGGLE ", node_path, " -> ", node.visible)

func _ready() -> void:
	_build_toggle_ui()
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("WindowPerfScenario: main.tscn load failed")
		return
	var main: Node = packed.instantiate()
	add_child(main)
	await get_tree().process_frame

	var manager: Node = main.get_node_or_null("Simulation/OrganismManager")
	if manager == null:
		push_error("WindowPerfScenario: OrganismManager not found")
		return
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))

	var center: Vector2 = manager.get("dish_center")
	var radius: float = maxf(32.0, float(manager.get("dish_radius")) - 24.0)
	var spacing: float = 16.0
	var spawned: int = 0
	var row: int = -24
	while spawned < TARGET_CELLS and row <= 24:
		var y: float = float(row) * spacing * 0.866
		var col: int = -24
		while col <= 24 and spawned < TARGET_CELLS:
			var x: float = float(col) * spacing + (float(absi(row) % 2) * spacing * 0.5)
			if x * x + y * y <= radius * radius:
				manager.call("register_zygote", 10000 + spawned, 0, -1, genome, center + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1

	_manager = manager
	_tick_core = main.get_node_or_null("Simulation/TickCore")
	if _tick_core != null:
		_tick_core.set("speed_scale", SPEED_SCALE)
	print("WINDOW_PERF_READY spawned=%d total=%d speed=%s" % [spawned, manager.get("cells").call("size"), str(SPEED_SCALE)])
