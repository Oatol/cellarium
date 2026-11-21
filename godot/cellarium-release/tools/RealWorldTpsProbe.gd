extends SceneTree
## v0.37 诊断：真实 1 倍速帧成本下的可达 TPS。
## 单帧 = 完整 tick 链(physics+development+nutrient+food+field) + 批渲染缓存重建。
## 1 倍速预算 16.67ms/帧；若帧成本超预算，实际 TPS 被压到 1e6/帧成本。
## headless 无 GPU/合成，这是 CPU 侧帧成本下界，真实 GPU 成本仍需窗口实测。
## 运行：CELLARIUM_NATIVE=0/1 console.exe --headless --path <project> --script res://tools/RealWorldTpsProbe.gd

const N: int = 512
const WARMUP_TICKS: int = 32
const MEASURE_FRAMES: int = 30
const WALL_LIMIT_MS: float = 30000.0

func _make_world() -> Dictionary:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var renderer_script: Script = load("res://scripts/rendering/CellPolygonBatchRenderer.gd") as Script
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	var native_env: String = OS.get_environment("CELLARIUM_NATIVE")
	if native_env == "0":
		manager.native_spatial_enabled = false
	elif native_env == "1":
		manager.native_spatial_enabled = true
	# 未设置 CELLARIUM_NATIVE 时保留脚本默认值（v0.37 起为 true）。
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))
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
	var renderer: Node2D = renderer_script.new() as Node2D
	renderer.organism_manager = manager
	return {"manager": manager, "environment": environment, "renderer": renderer}

func _full_tick(w: Dictionary, tick: int) -> void:
	var manager: Node = w["manager"]
	var environment: Node = w["environment"]
	manager.call("advance_physics_tick", 1.0 / 60.0)
	manager.call("advance_development_tick")
	environment.call("apply_nutrient_sources", tick)
	environment.call("advance_food_entities", 1.0 / 60.0)
	environment.call("advance_field_tick")

func _measure(w: Dictionary, label: String) -> void:
	var renderer: Node2D = w["renderer"]
	var manager: Node = w["manager"]
	var start_cells: int = int(manager.get("cells").call("size"))
	var t0: int = Time.get_ticks_usec()
	var frames: int = 0
	for f in range(MEASURE_FRAMES):
		_full_tick(w, f)
		renderer.call("_rebuild_cache")
		frames += 1
		if float(Time.get_ticks_usec() - t0) / 1000.0 >= WALL_LIMIT_MS:
			break
	var elapsed_us: int = Time.get_ticks_usec() - t0
	var per_frame_us: float = float(elapsed_us) / float(maxi(frames, 1))
	var achievable_tps: float = 1000000.0 / per_frame_us
	var budget_ratio: float = per_frame_us / 16667.0
	var end_cells: int = int(manager.get("cells").call("size"))
	print("REAL_TPS: %s cells=%d->%d frames=%d native=%s" % [label, start_cells, end_cells, frames, str(manager.native_spatial_enabled)])
	print("REAL_TPS: %s frame=%9.1fus budget_1x=16667us ratio=%5.2fx achievable_TPS=%6.1f" % [label, per_frame_us, budget_ratio, achievable_tps])

func _initialize() -> void:
	await process_frame
	var w: Dictionary = _make_world()
	_measure(w, "initial")
	for i in range(WARMUP_TICKS):
		_full_tick(w, 1000 + i)
	_measure(w, "grown")
	var manager: Node = w["manager"]
	var environment: Node = w["environment"]
	manager.free()
	environment.free()
	quit(0)
