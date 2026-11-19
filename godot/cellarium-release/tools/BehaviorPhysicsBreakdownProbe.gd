extends SceneTree
## v0.36 诊断：细分 behavior 与 physics 阶段中仍留在 GDScript 的串行段耗时。
## 目的：确认 apply_cached_intents / project_to_dish 的占比，再决定是否并行化。
## 运行：console.exe --headless --path <project> --script res://tools/BehaviorPhysicsBreakdownProbe.gd

const N: int = 1024
const REPEATS: int = 20

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var behavior_script: Script = load("res://scripts/system/CellBehavior.gd") as Script
	var physics_script: Script = load("res://scripts/system/CellPhysics.gd") as Script
	var env: Node = environment_script.new() as Node
	env._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = env
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	manager.native_spatial_enabled = true
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))
	var spawned: int = 0
	for row in range(-26, 27):
		for col in range(-26, 27):
			if spawned >= N:
				break
			var x: float = float(col) * 14.0 + float(absi(row) % 2) * 7.0
			var y: float = float(row) * 12.124
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1

	# 先跑几 tick 让细胞数稳定（关闭分裂以免测量期间数量变化）
	manager.set("division_mass", 100.0)
	for i in range(3):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var cells: RefCounted = manager.get("cells") as RefCounted
	var cell_count: int = int(cells.call("size"))

	var dt: float = 1.0 / 60.0
	var max_speed: float = float(manager.get("max_movement_speed"))
	if max_speed <= 0.0:
		max_speed = 12.0

	# apply_cached_intents (GDScript 串行) —— 单独计时
	var t0: int = Time.get_ticks_usec()
	for i in range(REPEATS):
		behavior_script.call("apply_cached_intents", cells, dt, max_speed)
	var apply_us: float = float(Time.get_ticks_usec() - t0) / float(REPEATS)

	# project_to_dish (GDScript) —— 单独计时
	var radius_scales: PackedFloat32Array = cells.get("cell_radius_scale")
	t0 = Time.get_ticks_usec()
	for i in range(REPEATS):
		physics_script.call("project_to_dish", cells, Vector2.ZERO, 248.0,
			float(manager.get("boundary_normal_damping")), radius_scales, 8.0)
	var project_us: float = float(Time.get_ticks_usec() - t0) / float(REPEATS)

	# 完整 physics_tick（native）对比基准
	t0 = Time.get_ticks_usec()
	for i in range(REPEATS):
		manager.call("advance_physics_tick", dt)
	var full_us: float = float(Time.get_ticks_usec() - t0) / float(REPEATS)

	print("BEHAV_PHYS_BREAKDOWN: cells=%d repeats=%d max_speed=%.2f" % [cell_count, REPEATS, max_speed])
	print("BEHAV_PHYS_BREAKDOWN: apply_cached_intents  %9.1f us" % apply_us)
	print("BEHAV_PHYS_BREAKDOWN: project_to_dish       %9.1f us" % project_us)
	print("BEHAV_PHYS_BREAKDOWN: full physics_tick     %9.1f us" % full_us)
	quit()
