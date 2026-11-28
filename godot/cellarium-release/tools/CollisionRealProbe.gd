extends SceneTree
## v0.47 阶段 1 真实工程 A/B：单轮软弹力碰撞 vs 旧 6 轮迭代碰撞。
## 场景与 WorkerEngineProbe 完全一致（皿半径 240、cell_radius 7、六方密堆 spacing 13、
## 关闭自主分裂），这样跑的是真实 tick 链，不是合成微基准。
## 同会话内跑两遍，只有 soft_collision_enabled 不同；墙钟一律 OS 单调钟。

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
	"behavior", "physics", "metabolism", "signal", "field", "commit", "total",
	"phys_verlet", "phys_collision", "phys_collision_write", "phys_project",
	"metab_fields", "metab_env", "metab_base", "metab_links", "beh_collect", "beh_eval",
]


func _initialize() -> void:
	await process_frame
	print("CREAL_PARAMS dish_radius=%.0f cell_radius=7.0 target=%d warmup=%d measure=%d" % [
		DISH_RADIUS, TARGET_CELLS, WARMUP_TICKS, MEASURE_TICKS,
	])
	for soft in [true, false]:
		_run(soft)
	quit(0)


func _run(soft: bool) -> void:
	var world: Array = _build_world(soft)
	var mgr: Node = world[0] as Node
	var env: Node = world[1] as Node
	var tag: String = "soft" if soft else "legacy"

	# 预热：让分裂/黏附/场收敛到稳态，不计入平均。
	for i in range(WARMUP_TICKS):
		mgr.call("advance_physics_tick", DT)
		env.call("advance_field_tick")
	var probe: RefCounted = mgr.get("perf_probe") as RefCounted
	probe.call("reset")
	var cells: RefCounted = mgr.get("cells") as RefCounted
	var cells_at_start: int = int(cells.call("size"))

	var t0: int = Time.get_ticks_usec()
	for i in range(MEASURE_TICKS):
		mgr.call("advance_physics_tick", DT)
		env.call("advance_field_tick")
	var t1: int = Time.get_ticks_usec()
	var wall_us_per_tick: float = float(t1 - t0) / float(MEASURE_TICKS)

	var stages: Dictionary = probe.call("diagnostic_averages") as Dictionary
	var line: String = "CREAL_STAGES tag=%s" % tag
	for key in STAGE_KEYS:
		if stages.has(key):
			line += " %s=%.1f" % [key, float(stages.get(key))]
	print(line)
	print("CREAL_TICK tag=%s cells_start=%d cells_end=%d wall_us_per_tick=%.1f probe_total_us=%.1f tps=%.1f" % [
		tag, cells_at_start, int(cells.call("size")), wall_us_per_tick,
		float(stages.get("total", 0.0)), 1000000.0 / maxf(1.0, wall_us_per_tick),
	])
	# 稳定性代理：细胞是否飞散/堆死（皿内包围盒）与总能量守恒量级。
	var px: PackedFloat32Array = cells.get("cell_pos_x")
	var py: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var min_r: float = 1.0e9
	var max_r: float = 0.0
	var count_alive: int = 0
	var energy_sum: float = 0.0
	var energies: PackedFloat32Array = cells.get("cell_energy")
	for i in range(px.size()):
		if alive[i] == 0:
			continue
		count_alive += 1
		var d: float = Vector2(px[i] - DISH_CENTER.x, py[i] - DISH_CENTER.y).length()
		min_r = minf(min_r, d)
		max_r = maxf(max_r, d)
		energy_sum += float(energies[i])
	print("CREAL_SHAPE tag=%s alive=%d bbox_r_min=%.1f bbox_r_max=%.1f dish_r=%.0f energy_sum=%.3f" % [
		tag, count_alive, min_r, max_r, DISH_RADIUS, energy_sum,
	])
	var overlap: Array = _overlap_stats(px, py, alive, cells.get("cell_radius_scale") as PackedFloat32Array)
	print("CREAL_OVERLAP tag=%s max_pen=%.4f mean_pen=%.4f pairs=%d" % [
		tag, float(overlap[0]), float(overlap[1]), int(overlap[2]),
	])
	mgr.queue_free()
	env.queue_free()


## 用固定网格统计真实场景的重叠：返回 [max_pen, mean_pen, pair_count]。
## 网格尺寸按最大接触距离推导，保证不漏对（与内核同一判据）。
func _overlap_stats(pos_x: PackedFloat32Array, pos_y: PackedFloat32Array, alive: PackedByteArray, scales: PackedFloat32Array) -> Array:
	var count: int = pos_x.size()
	var max_scale: float = 0.0
	for i in range(count):
		if alive[i] == 0 or i >= scales.size():
			continue
		max_scale = maxf(max_scale, float(scales[i]))
	if max_scale <= 0.0:
		max_scale = 1.0
	var cell_size: float = maxf(1.0, 2.0 * 7.0 * max_scale)
	var buckets: Dictionary = {}
	for i in range(count):
		if alive[i] == 0:
			continue
		var key: int = (floori(pos_x[i] / cell_size) + 1000000) * 2000001 + (floori(pos_y[i] / cell_size) + 1000000)
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		var bucket: PackedInt32Array = buckets[key]
		bucket.append(i)
		buckets[key] = bucket
	var worst: float = 0.0
	var total: float = 0.0
	var pairs: int = 0
	for a in range(count):
		if alive[a] == 0:
			continue
		var cx: int = floori(pos_x[a] / cell_size)
		var cy: int = floori(pos_y[a] / cell_size)
		var scale_a: float = float(scales[a]) if a < scales.size() else 1.0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var key: int = (cx + ox + 1000000) * 2000001 + (cy + oy + 1000000)
				if not buckets.has(key):
					continue
				for b in (buckets[key] as PackedInt32Array):
					if b <= a:
						continue
					var dx: float = pos_x[b] - pos_x[a]
					var dy: float = pos_y[b] - pos_y[a]
					var scale_b: float = float(scales[b]) if b < scales.size() else 1.0
					var contact: float = 7.0 * (scale_a + scale_b)
					var d2: float = dx * dx + dy * dy
					if d2 >= contact * contact:
						continue
					var pen: float = contact - sqrt(d2)
					worst = maxf(worst, pen)
					total += pen
					pairs += 1
	return [worst, total / float(maxi(1, pairs)), pairs]


func _build_world(soft: bool) -> Array:
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
	mgr.set("soft_collision_enabled", soft)
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
