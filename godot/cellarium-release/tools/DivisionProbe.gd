extends SceneTree
## v0.20.0 分裂倍增诊断：单模式 M1->M1+M1、无限个体、能量只补起始细胞。
## 程序化、无鼠标、ASCII 输出。用法：godot --headless --path <proj> --script res://tools/DivisionProbe.gd

const SAMPLE_TICKS: int = 240

func _initialize() -> void:
	await process_frame
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
	genome.set("transfer_rate", 0.5)
	genome.set("child_types", PackedByteArray([0, 0, 0, 0]))
	genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"name": "M1", "cell_type": 0,
		"child1_type": 0, "child2_type": 0,
		"child1_mode": 0, "child2_mode": 0,
		"child1_glue": true, "child2_glue": true, "make_glue": true,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.5,
	}, 0)
	genome.call("set_modes", [mode])
	var org_id: int = int(manager.call("register_zygote", 99, 99, -1, genome, Vector2(250, 250), 8.0, 0))
	var seen_sizes: Dictionary = {}
	for tick in range(SAMPLE_TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		var current_size: int = int(cells.call("size"))
		if not seen_sizes.has(current_size):
			seen_sizes[current_size] = true
			var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
			var alive: PackedByteArray = cells.get("cell_alive") as PackedByteArray
			var e_sum: float = 0.0
			for i in range(energies.size()):
				if alive[i] != 0:
					e_sum += energies[i]
			print("DivisionProbe tick=", tick, " cells=", current_size, " energy_sum=", snappedf(e_sum, 2))
		if current_size >= 32:
			break
	instance.queue_free()
	quit(0)
