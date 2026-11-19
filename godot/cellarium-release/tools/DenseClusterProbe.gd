extends SceneTree
## v0.33 诊断：复现用户截图场景（512 细胞密集堆积、皿半径 256、cell_radius 8），
## 逐段测量 Main._on_tick_advanced 的完整调用链，定位 TPS 6 的真实瓶颈。
## 运行：CELLARIUM_NATIVE=0/1 console.exe --headless --path <project> --script res://tools/DenseClusterProbe.gd

const N: int = 512
const TICKS: int = 40
const WALL_LIMIT_MS: float = 15000.0

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	manager.native_spatial_enabled = OS.get_environment("CELLARIUM_NATIVE") == "1"
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	# v0.34.0：标准测试基因组 = M1 光合自分裂，保黏附、无限分裂。
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_divisions", int(genome_script.get_script_constant_map().get("MAX_GENE_DIVISIONS", 8)))
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))
	# 六角密排，半径 200 的圆内取 512 点（与截图密度接近）。
	var spawned: int = 0
	for row in range(-18, 19):
		for col in range(-18, 19):
			if spawned >= N:
				break
			var row_offset: float = float(absi(row) % 2) * 8.0
			var x: float = float(col) * 16.0 + row_offset
			var y: float = float(row) * 13.856
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1
	var keys: Array[String] = ["physics_tick", "development", "nutrient_sources", "food_entities", "field_tick"]
	var totals: Dictionary = {}
	for key in keys:
		totals[key] = 0.0
	var executed: int = 0
	var start_usec: int = Time.get_ticks_usec()
	for tick in range(TICKS):
		var t0: int = Time.get_ticks_usec()
		manager.call("advance_physics_tick", 1.0 / 60.0)
		var t1: int = Time.get_ticks_usec()
		manager.call("advance_development_tick")
		var t2: int = Time.get_ticks_usec()
		environment.call("apply_nutrient_sources", tick)
		var t3: int = Time.get_ticks_usec()
		environment.call("advance_food_entities", 1.0 / 60.0)
		var t4: int = Time.get_ticks_usec()
		environment.call("advance_field_tick")
		var t5: int = Time.get_ticks_usec()
		totals["physics_tick"] += float(t1 - t0)
		totals["development"] += float(t2 - t1)
		totals["nutrient_sources"] += float(t3 - t2)
		totals["food_entities"] += float(t4 - t3)
		totals["field_tick"] += float(t5 - t4)
		executed += 1
		if float(Time.get_ticks_usec() - start_usec) / 1000.0 >= WALL_LIMIT_MS:
			break
	var probe: RefCounted = manager.call("get_perf_probe") as RefCounted
	var avg: Dictionary = probe.call("averages") as Dictionary
	var final_cells: int = int(manager.get("cells").call("size"))
	print("DENSE_PROBE: n=%d spawned=%d ticks=%d native=%s final_cells=%d organisms=%d" % [N, spawned, executed, str(manager.native_spatial_enabled), final_cells, int(manager.call("get_organism_count"))])
	for key in keys:
		print("DENSE_PROBE: %-18s %8.1fus" % [key, float(totals[key]) / float(maxi(executed, 1))])
	var snap: Dictionary = probe.call("last_snapshot") as Dictionary
	for key in ["metab_fields", "metab_rates", "metab_links", "metab_base", "metab_env", "metab_radius", "metab_lifecycle"]:
		print("DENSE_PROBE: sub %-16s %8.1fus" % [key, float(snap.get(key, 0.0))])
	for stage in ["behavior", "physics", "metabolism", "predation", "signal", "total"]:
		print("DENSE_PROBE: stage %-12s %8.1fus" % [stage, float(avg.get(stage, 0.0))])
	manager.free()
	environment.free()
	quit(0)
