extends SceneTree
## v0.50.0 分裂几何闸门：验证两件事
##   1) 分裂轴相对母细胞朝向（Cell Lab d7 = cell.k + Gene.d）：Gene.d=0 时应长成一条**长带**，
##      沿分裂轴的跨度远大于垂直方向跨度。
##   2) 黏附以 Gene.l（生成黏附素）为准：make_glue=false 且未开额外子代开关时，分裂后**零连接**。
## 程序化、无鼠标、ASCII 输出。用法：
##   godot --headless --path <proj> --script res://tools/SplitBandProbe.gd

const SAMPLE_TICKS: int = 240
const TARGET_CELLS: int = 32

func _initialize() -> void:
	await process_frame
	await _run_case("glue_on_d0", true, 0.0, false)
	await _run_case("glue_off_d0", false, 0.0, false)
	await _run_case("glue_on_d90", true, 0.25, false)
	# 链式分化：子代 1 继续 M1、子代 2 进终末模式 M2（不分裂）→ 线性长链。
	await _run_case("chain_glue_on", true, 0.0, true)
	quit(0)

func _run_case(label: String, make_glue: bool, child2_angle: float, chain: bool) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	manager.set("heterotrophic_intake_rate", 0.0)
	manager.set("photosynthetic_intake_rate", 0.0)
	manager.set("chemotrophic_intake_rate", 0.0)
	manager.set("autonomous_division_cooldown", 1)
	manager.set("default_transfer_rate", 0.0)
	var cells: RefCounted = manager.get("cells")

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
	genome.set("division_mass", 0.05)
	genome.set("split_ratio", 0.5)
	genome.set("max_divisions", 8)
	genome.set("max_cells_per_organism", -1)
	genome.set("transfer_rate", 0.0)
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"name": "M1", "cell_type": 0,
		"child1_mode": 0, "child2_mode": 1 if chain else 0,
		"make_glue": make_glue,
		"child1_glue": false, "child2_glue": false,
		"child1_angle": 0.0, "child2_angle": child2_angle,
		"split_angle": 0.0, "split_angle2": 0.0,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 0)
	var terminal: Dictionary = genome_script.call("normalized_mode", {
		"name": "M2", "cell_type": 4,
		"child1_mode": 1, "child2_mode": 1,
		"make_glue": make_glue,
		"division_mass": 100.0,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 1)
	genome.call("set_modes", [mode, terminal])
	# 母细胞朝向固定为 0（+X），这样「沿轴跨度」就是 X 方向跨度。
	manager.call("register_zygote", 99, 99, -1, genome, Vector2(250, 250), 8.0, 0)
	var alive: PackedByteArray = cells.get("cell_alive")
	for index in range(alive.size()):
		if alive[index] != 0:
			cells.call("set_orientation", index, 0.0)
			break

	for tick in range(SAMPLE_TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells.call("size")) >= TARGET_CELLS:
			break

	alive = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var min_x: float = 1e9
	var max_x: float = -1e9
	var min_y: float = 1e9
	var max_y: float = -1e9
	var live: int = 0
	for index in range(alive.size()):
		if alive[index] == 0:
			continue
		live += 1
		min_x = minf(min_x, pos_x[index])
		max_x = maxf(max_x, pos_x[index])
		min_y = minf(min_y, pos_y[index])
		max_y = maxf(max_y, pos_y[index])
	var links: int = 0
	for index in range(link_a.size()):
		if link_a[index] >= 0 and link_b[index] >= 0:
			links += 1
	var span_x: float = maxf(0.0, max_x - min_x)
	var span_y: float = maxf(0.0, max_y - min_y)
	var elongation: float = span_x / maxf(1.0, span_y)
	print("SPLIT_BAND case=%s cells=%d links=%d span_x=%.1f span_y=%.1f elongation=%.2f" % [
		label, live, links, span_x, span_y, elongation,
	])
	instance.queue_free()
	await process_frame
