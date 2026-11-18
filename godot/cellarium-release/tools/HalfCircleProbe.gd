extends SceneTree
## v0.21.0 分裂半圆探针：验证分裂当帧母子中心距≈0.2r（高度重叠→半圆），
## 下一 tick 被接触排斥拉开。程序化、无鼠标、ASCII 输出。
## 用法：godot --headless --path <proj> --script res://tools/HalfCircleProbe.gd

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
	genome.set("max_cells_per_organism", 2)
	genome.set("transfer_rate", 0.0)
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"name": "M1", "cell_type": 0,
		"child1_type": 0, "child2_type": 0,
		"child1_mode": 0, "child2_mode": 0,
		"child1_glue": false, "child2_glue": false, "make_glue": false,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 0)
	genome.call("set_modes", [mode])
	manager.call("register_zygote", 99, 99, -1, genome, Vector2(250, 250), 2.0, 0)

	var shadow_size: int = 1
	var cell_radius: float = float(manager.get("cell_radius"))
	for tick in range(30):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		var current_size: int = int(cells.call("size"))
		if current_size == 2 and shadow_size == 1:
			var px: PackedFloat32Array = cells.get("cell_pos_x") as PackedFloat32Array
			var py: PackedFloat32Array = cells.get("cell_pos_y") as PackedFloat32Array
			var scales: PackedFloat32Array = cells.get("cell_radius_scale") as PackedFloat32Array
			var d: float = Vector2(px[1] - px[0], py[1] - py[0]).length()
			var contact: float = cell_radius * (scales[0] + scales[1])
			print("HalfCircleProbe BIRTH_FRAME dist=", snappedf(d, 0.001),
				" contact_dist=", snappedf(contact, 0.001),
				" ratio=", snappedf(d / contact, 0.0001),
				" r0=", snappedf(scales[0], 0.001), " r1=", snappedf(scales[1], 0.001))
			# 下一 tick 后测量排斥效果
			manager.call("advance_physics_tick", 1.0 / 60.0)
			px = cells.get("cell_pos_x") as PackedFloat32Array
			py = cells.get("cell_pos_y") as PackedFloat32Array
			var d2: float = Vector2(px[1] - px[0], py[1] - py[0]).length()
			print("HalfCircleProbe NEXT_TICK dist=", snappedf(d2, 0.001),
				" pushed_apart=", (d2 > d))
			break
		shadow_size = current_size
	instance.queue_free()
	quit(0)
