extends SceneTree
## v0.22 诊断：真实代谢条件下（保留基础耗能/光合产能/场采样）的细胞分裂判定与增长曲线。
## 逐 tick 打印：细胞数、每个细胞能量、depth、是否>=阈值。程序化、无鼠标、ASCII 输出。
## 用法：godot --headless --path <proj> --script res://tools/GrowthProbe.gd

const SAMPLE_TICKS: int = 120
const LOG_EVERY: int = 10

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	tick_core.set("running", false)
	# 保留真实代谢：不关 base_metabolic_cost、不关光合、不关场采样。
	# 唯一调整：光源设为全皿均匀（mode=0），模拟"理想光合带"——每个光合细胞都能稳定产能。
	env.set("light_source_mode", 0)
	env.set("light_intensity", 0.6)
	env.call("apply_light_settings")
	manager.set("autonomous_division_cooldown", 1)
	manager.set("default_transfer_rate", 0.0)
	print("GrowthProbe base_cost=", manager.get("base_metabolic_cost"),
		" photo_rate=", manager.get("photosynthetic_intake_rate"))
	var cells: RefCounted = manager.get("cells")

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([4, 0, 0, 0, 0, 0, 0, 0]))  # trait 0 = PHOTOCYTE
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
	genome.set("division_mass", 0.05)
	genome.set("split_ratio", 0.5)
	genome.set("max_divisions", 8)
	genome.set("max_cells_per_organism", -1)
	genome.set("transfer_rate", 0.0)
	genome.set("child_types", PackedByteArray([4, 4, 4, 4]))
	genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"name": "M1", "cell_type": 4,
		"child1_type": 4, "child2_type": 4,
		"child1_mode": 0, "child2_mode": 0,
		"child1_glue": false, "child2_glue": false, "make_glue": false,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 0)
	genome.call("set_modes", [mode])
	# 初始能量给到阈值附近（真实：不是 8.0 的过剩值）
	manager.call("register_zygote", 99, 99, -1, genome, Vector2(250, 250), 0.12, 0)
	var threshold: float = 0.05
	for tick in range(SAMPLE_TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if tick % LOG_EVERY == 0 or tick < 6:
			var size: int = int(cells.call("size"))
			var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
			var depths: PackedByteArray = cells.get("cell_mode_depth") as PackedByteArray
			var alive: PackedByteArray = cells.get("cell_alive") as PackedByteArray
			var eligible: int = 0
			var e_list: String = ""
			for i in range(size):
				if alive[i] == 0:
					continue
				if energies[i] >= threshold:
					eligible += 1
				if i < 8:
					e_list += " e%d=%.3f/d%d" % [i, energies[i], depths[i]]
			print("GrowthProbe tick=", tick, " cells=", size, " eligible=", eligible, e_list)
	instance.queue_free()
	quit(0)
