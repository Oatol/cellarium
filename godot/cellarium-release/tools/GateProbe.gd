extends SceneTree
## v0.22 闸门诊断：复刻 _apply_autonomous_lifecycle 候选筛选，
## 对每个高能量细胞报告它被哪个闸门挡住。程序化、无鼠标、ASCII 输出。
## 用法：godot --headless --path <proj> --script res://tools/GateProbe.gd

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
	env.set("light_source_mode", 0)
	env.set("light_intensity", 0.6)
	env.call("apply_light_settings")
	manager.set("autonomous_division_cooldown", 1)
	manager.set("default_transfer_rate", 0.0)
	var cells: RefCounted = manager.get("cells")
	var organisms: RefCounted = manager.get("organisms")

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var store_script: Script = load("res://scripts/core/data/OrganismStore.gd") as Script
	var state_map: Dictionary = store_script.get_script_constant_map()
	var mature_state: int = int(state_map["STATE_MATURE"])
	var developing_state: int = int(state_map.get("STATE_DEVELOPING", 0))
	print("GateProbe mature_state=", mature_state, " developing_state=", developing_state)

	# M1->M1+M1 纯增殖链：两个子代都回自身，max_divisions 用两种值测。
	for max_div_in in [1, 8]:
		var genome: RefCounted = genome_script.new() as RefCounted
		genome.set("traits", PackedByteArray([4, 0, 0, 0, 0, 0, 0, 0]))
		genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
		genome.set("division_mass", 0.05)
		genome.set("split_ratio", 0.5)
		genome.set("max_divisions", 3)
		genome.set("max_cells_per_organism", -1)
		genome.set("transfer_rate", 0.0)
		var mode: Dictionary = genome_script.call("normalized_mode", {
			"name": "M1", "cell_type": 4,
			"child1_type": 4, "child2_type": 4,
			"child1_mode": 0, "child2_mode": 0,
			"child1_glue": true, "child2_glue": true, "make_glue": true,
			"division_mass": 0.05, "max_divisions": max_div_in,
			"link_division_limit": -1, "telomere": -1,
			"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
		}, 0)
		genome.call("set_modes", [mode])
		manager.call("register_zygote", 100 + max_div_in, 100, -1, genome, Vector2(250, 250), 2.0, 4)
		print("GateProbe registered max_div=", max_div_in, " cells=", cells.call("size"),
			" org_count=", manager.call("get_organism_count"))
		for tick in range(60):
			manager.call("advance_physics_tick", 1.0 / 60.0)
			if tick == 3 or tick == 55:
				print("GateProbe tick=", tick, " cells=", cells.call("size"))
				_report_gates(manager, cells, organisms, genome, mature_state)
		# 清理本轮个体避免干扰下一轮
		var org_alive: PackedByteArray = organisms.get("org_alive")
		for oid in range(org_alive.size()):
			if org_alive[oid] != 0:
				manager.call("remove_organism", oid)
	instance.queue_free()
	quit(0)

func _report_gates(manager: Node, cells: RefCounted, organisms: RefCounted, genome: RefCounted, mature_state: int) -> void:
	var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
	var alive: PackedByteArray = cells.get("cell_alive") as PackedByteArray
	var org_ids: PackedInt32Array = cells.get("cell_org_id") as PackedInt32Array
	var depths: PackedByteArray = cells.get("cell_mode_depth") as PackedByteArray
	var div_ticks: PackedInt32Array = cells.get("cell_division_tick") as PackedInt32Array
	var link_counts: PackedByteArray = cells.get("cell_link_count") as PackedByteArray
	var telomeres: PackedInt32Array = cells.get("cell_telomere") as PackedInt32Array
	var org_alive: PackedByteArray = organisms.get("org_alive") as PackedByteArray
	var org_state: PackedByteArray = organisms.get("org_state") as PackedByteArray
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var threshold: float = 0.05
	var sim_tick: int = int(manager.get("_sim_tick"))
	var cooldown: int = int(manager.get("autonomous_division_cooldown"))
	for i in range(energies.size()):
		if alive[i] == 0:
			continue
		var oid: int = org_ids[i]
		var gate: String = "PASS"
		if oid < 0 or oid >= org_alive.size() or org_alive[oid] == 0:
			gate = "org_dead"
		elif org_state[oid] != mature_state:
			gate = "org_state=%d!=mature" % org_state[oid]
		elif energies[i] < threshold:
			gate = "energy<%.2f" % threshold
		elif depths[i] >= 1:
			gate = "depth=%d>=1" % depths[i]
		elif int(telomeres[i]) == 0:
			gate = "telomere=0"
		elif div_ticks[i] >= 0 and sim_tick - div_ticks[i] < cooldown:
			gate = "cooldown(tick=%d,last=%d)" % [sim_tick, div_ticks[i]]
		print("GateProbe cell=%d org=%d e=%.3f depth=%d links=%d divtick=%d -> %s" % [
			i, oid, energies[i], depths[i], link_counts[i], div_ticks[i], gate])
