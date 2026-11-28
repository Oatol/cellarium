extends SceneTree
## v0.47 阶段 2 定位探针：真实皿 1024 细胞下，把「一次 tick」拆成可归因的几块。
## 只读，不改模拟逻辑、不碰 state hash。
##
## 关注点：
##   1. organism tick 与 environment field tick 各占多少（CollisionRealProbe 里
##      wall 6869µs 与 PerfProbe total 4378µs 的差额就是 field tick，但没单独量过）；
##   2. metab_fields 内部：positions/indices 的 duplicate、_sample_index_by_cell 建字典、
##      field.sample_cells_flat 三段各占多少（EnvironmentManager 已有 diag_* 计数器）；
##   3. metab_env / behavior / signal 的权威数字。

const OM_SCRIPT: Script = preload("res://scripts/system/OrganismManager.gd")
const EM_SCRIPT: Script = preload("res://scripts/system/EnvironmentManager.gd")
const TM_SCRIPT: Script = preload("res://scripts/core/tick/TickCore.gd")
const FIELD_SCRIPT: Script = preload("res://scripts/system/EnvironmentField.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")

const DT: float = 1.0 / 60.0
const DISH_CENTER: Vector2 = Vector2(250.0, 250.0)
const DISH_RADIUS: float = 240.0
const WARMUP_TICKS: int = 15
const MEASURE_TICKS: int = 60
const TARGET_CELLS: int = 1024

const STAGE_KEYS: Array[String] = [
	"behavior", "physics", "metabolism", "signal", "commit", "total",
	"metab_fields", "metab_rates", "metab_links", "metab_base", "metab_env",
	"beh_collect", "beh_eval", "beh_apply", "phys_collision", "phys_verlet",
]


func _initialize() -> void:
	await process_frame
	var world: Array = _build_world()
	var mgr: Node = world[0] as Node
	var env: Node = world[1] as Node

	for i in range(WARMUP_TICKS):
		mgr.call("advance_physics_tick", DT)
		env.call("advance_field_tick")

	var cells: RefCounted = mgr.get("cells") as RefCounted
	print("S2_SETUP cells=%d dish_r=%.0f warmup=%d measure=%d" % [
		int(cells.call("size")), DISH_RADIUS, WARMUP_TICKS, MEASURE_TICKS,
	])

	# 重置采样计数器，然后分段计时。
	env.set("diag_sample_calls", 0)
	env.set("diag_duplicate_usec", 0)
	env.set("diag_index_map_usec", 0)
	env.set("diag_field_sample_usec", 0)
	var probe: RefCounted = mgr.get("perf_probe") as RefCounted
	probe.call("reset")

	var org_us: int = 0
	var field_us: int = 0
	for i in range(MEASURE_TICKS):
		var t0: int = Time.get_ticks_usec()
		mgr.call("advance_physics_tick", DT)
		var t1: int = Time.get_ticks_usec()
		env.call("advance_field_tick")
		var t2: int = Time.get_ticks_usec()
		org_us += t1 - t0
		field_us += t2 - t1

	var n: float = float(MEASURE_TICKS)
	print("S2_TICK org_us_per_tick=%.1f field_us_per_tick=%.1f sum=%.1f" % [
		float(org_us) / n, float(field_us) / n, float(org_us + field_us) / n,
	])

	var stages: Dictionary = probe.call("diagnostic_averages") as Dictionary
	var line: String = "S2_STAGES"
	for key in STAGE_KEYS:
		if stages.has(key):
			line += " %s=%.1f" % [key, float(stages.get(key))]
	print(line)

	var calls: int = maxi(1, int(env.get("diag_sample_calls")))
	print("S2_SAMPLING calls_per_tick=%.2f dup_us=%.1f index_map_us=%.1f field_sample_us=%.1f" % [
		float(calls) / n,
		float(int(env.get("diag_duplicate_usec"))) / float(calls),
		float(int(env.get("diag_index_map_usec"))) / float(calls),
		float(int(env.get("diag_field_sample_usec"))) / float(calls),
	])

	# 组织侧准备开销：把两个采样数组的构造成本单独量出来（与 metab_fields 同口径）。
	var build_us: int = 0
	for i in range(MEASURE_TICKS):
		var t3: int = Time.get_ticks_usec()
		var p: Array[Vector2] = mgr.call("_field_sample_positions") as Array[Vector2]
		var idx: Array[int] = mgr.call("_field_sample_cell_indices") as Array[int]
		var t4: int = Time.get_ticks_usec()
		build_us += t4 - t3
		if p.is_empty() and idx.is_empty():
			break
	print("S2_ARRAYBUILD positions_plus_indices_us=%.1f" % [float(build_us) / n])
	mgr.queue_free()
	env.queue_free()
	quit(0)


func _build_world() -> Array:
	var env: Node = EM_SCRIPT.new() as Node
	env.set("light_source_mode", 0)
	env.set("light_intensity", 1.0)
	env.set("nutrient_density", 1.2)
	env.set("oxygen_fraction", 1.0)
	env.set("food_spawn_amount", 0.0)
	env.set("dish_center", DISH_CENTER)
	env.set("dish_radius", DISH_RADIUS)
	var field: RefCounted = env.get("field") as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([1.2, 273.0, 1.0, 1.0, 0.0])
	field.call("configure", 32, DISH_CENTER, DISH_RADIUS, defaults, false)
	var res: int = int(field.get("resolution"))
	var light_values: PackedFloat32Array = PackedFloat32Array()
	light_values.resize(res * res)
	light_values.fill(1.0)
	field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_LIGHT, light_values)
	env.call("apply_light_settings")

	var tc: Node = TM_SCRIPT.new() as Node
	tc.call("apply_speed", 1.0)
	var mgr: Node = OM_SCRIPT.new() as Node
	mgr.set("environment_manager", env)
	mgr.set("tick_core", tc)
	mgr.set("dish_center", DISH_CENTER)
	mgr.set("dish_radius", DISH_RADIUS)
	mgr.set("cell_radius", 7.0)
	mgr.set("autonomous_division_enabled", false)
	mgr.set("native_spatial_enabled", true)
	mgr.call("_ready")

	var genome: RefCounted = GENOME_SCRIPT.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(GENOME_SCRIPT.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome.call("solo_photo_modes"))
	var spacing: float = 13.0
	var spawned: int = 0
	var row: int = -30
	while spawned < TARGET_CELLS and row <= 30:
		var y: float = float(row) * spacing * 0.866
		var col: int = -30
		while col <= 30 and spawned < TARGET_CELLS:
			var x: float = float(col) * spacing + float(absi(row) % 2) * spacing * 0.5
			if x * x + y * y <= (DISH_RADIUS - 8.0) * (DISH_RADIUS - 8.0):
				mgr.call("register_zygote", 300000 + spawned, 0, -1, genome, DISH_CENTER + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1
	return [mgr, env, tc]
