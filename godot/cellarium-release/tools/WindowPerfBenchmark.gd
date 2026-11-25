extends Node
## v0.40 诊断：真实 Vulkan 窗口内的固定细胞数分段计时。
## 与 HUD 不同：不使用编辑器 debugger / game_eval 参与测量，避免 Time 采样被调试暂停污染。
## 主 tick 被冻结，手动按固定 budget 调用完整 tick 链与批渲染缓存重建，输出 avg/p50/p95。

const TARGET_CELLS: int = 1024
const WARMUP_FRAMES: int = 12
const MEASURE_FRAMES: int = 120
const PHASES: Array[String] = ["tick1", "tick3", "cache", "tick1_cache", "tick3_cache"]
const TICK_DT: float = 1.0 / 60.0

var _main: Node = null
var _manager: Node = null
var _environment: Node = null
var _command_bus: Node = null
var _poly_renderer: Node = null
var _tick_core: Node = null
var _tick_index: int = 0
var _warmup_frames: int = 0
var _phase_index: int = 0
var _frame_in_phase: int = 0
var _done: bool = false
var _setup_done: bool = false
var _samples: Dictionary = {}
var _frame_samples: Dictionary = {}
## v0.40：tick 链内部六段细分，定位 tick CPU 的真正热点。
var _parts: Array[String] = ["cmd", "physics", "dev", "nutrient", "food", "field"]
var _part_samples: Dictionary = {}

func _ready() -> void:
	await get_tree().process_frame
	_setup()

func _setup() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("WindowPerfBenchmark: main.tscn load failed")
		_done = true
		return
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().process_frame

	_manager = _main.get_node_or_null("Simulation/OrganismManager")
	_environment = _main.get_node_or_null("Simulation/EnvironmentManager")
	_command_bus = _main.get_node_or_null("Simulation/CommandBus")
	_tick_core = _main.get_node_or_null("Simulation/TickCore")
	_poly_renderer = _main.get_node_or_null("DishView/CellBatchPoly")
	if _manager == null or _environment == null or _command_bus == null or _tick_core == null or _poly_renderer == null:
		push_error("WindowPerfBenchmark: required node missing")
		_done = true
		return

	# 冻结主循环：本场景手动推进 tick，保证 1×/3× budget 与固定细胞数可重复。
	_tick_core.set("running", false)
	_manager.set("autonomous_division_enabled", false)

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))

	var center: Vector2 = _manager.get("dish_center")
	var radius: float = maxf(64.0, float(_manager.get("dish_radius")) - 8.0)
	var spacing: float = 13.0
	var spawned: int = 0
	var row: int = -30
	while spawned < TARGET_CELLS and row <= 30:
		var y: float = float(row) * spacing * 0.866
		var col: int = -30
		while col <= 30 and spawned < TARGET_CELLS:
			var x: float = float(col) * spacing + float(absi(row) % 2) * spacing * 0.5
			if x * x + y * y <= radius * radius:
				_manager.call("register_zygote", 100000 + spawned, 0, -1, genome, center + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1
	if spawned != TARGET_CELLS:
		push_warning("WindowPerfBenchmark: spawned=%d target=%d" % [spawned, TARGET_CELLS])

	for phase in PHASES:
		_samples[phase] = [] as Array[int]
		_frame_samples[phase] = [] as Array[int]
	for part in _parts:
		_part_samples[part] = [] as Array[int]
	print("WINDOW_BENCH_SETUP cells=%d native=%s render_cache=%s" % [
		(_manager.get("cells") as RefCounted).call("size"),
		str(_manager.get("native_spatial_enabled")),
		str(ClassDB.class_exists("CellRenderCache")),
	])
	_verify_flat_parity()
	_setup_done = true

## v0.42：真实 GPU 窗口内，专用 flat 路径与旧 sample_cells()+复制路径的逐位对照。
## 只在 setup 阶段执行一次，不进入任何测量相位。
func _verify_flat_parity() -> void:
	var field_ref: RefCounted = _environment.get("field") as RefCounted
	if field_ref == null or not field_ref.has_method("sample_cells"):
		return
	var positions: Array[Vector2] = _manager.call("_field_sample_positions")
	if positions.is_empty():
		return
	var new_flat: PackedFloat32Array = field_ref.call("sample_cells_flat", positions)
	var sampled: Array = field_ref.call("sample_cells", positions)
	var old_flat: PackedFloat32Array = PackedFloat32Array()
	old_flat.resize(new_flat.size())
	for index in range(mini(sampled.size(), positions.size())):
		var values: PackedFloat32Array = sampled[index]
		var offset: int = index * 5
		for channel in range(mini(values.size(), 5)):
			if offset + channel < old_flat.size():
				old_flat[offset + channel] = values[channel]
	var failures: int = 0
	for index in range(new_flat.size()):
		if new_flat[index] != old_flat[index]:
			failures += 1
	print("WINDOW_BENCH_FLAT_PARITY values=%d failures=%d" % [new_flat.size(), failures])

func _process(delta: float) -> void:
	if _done or not _setup_done:
		return
	if _warmup_frames < WARMUP_FRAMES:
		_run_tick()
		_run_cache()
		_warmup_frames += 1
		return
	if _phase_index >= PHASES.size():
		_done = true
		_report()
		return
	var phase: String = PHASES[_phase_index]
	var us: int = 0
	match phase:
		"tick1":
			us = _run_tick()
		"tick3":
			us = _run_tick() + _run_tick() + _run_tick()
		"cache":
			us = _run_cache()
		"tick1_cache":
			us = _run_tick() + _run_cache()
		"tick3_cache":
			us = _run_tick() + _run_tick() + _run_tick() + _run_cache()
	var samples: Array[int] = _samples[phase]
	var frames: Array[int] = _frame_samples[phase]
	samples.append(us)
	# 跳过相位前 5 帧：其 delta 属于上一相位，不能归因到当前工作。
	if _frame_in_phase >= 5:
		frames.append(int(delta * 1000000.0))
	_frame_in_phase += 1
	if _frame_in_phase >= MEASURE_FRAMES:
		_phase_index += 1
		_frame_in_phase = 0

func _run_tick() -> int:
	var t0: int = Time.get_ticks_usec()
	var tick: int = _tick_index
	var marks: Array[int] = [t0]
	_command_bus.call("execute_tick_commands", tick)
	marks.append(Time.get_ticks_usec())
	_manager.call("advance_physics_tick", TICK_DT)
	marks.append(Time.get_ticks_usec())
	_manager.call("advance_development_tick")
	marks.append(Time.get_ticks_usec())
	_environment.call("apply_nutrient_sources", tick)
	marks.append(Time.get_ticks_usec())
	_environment.call("advance_food_entities", TICK_DT)
	marks.append(Time.get_ticks_usec())
	_environment.call("advance_field_tick")
	marks.append(Time.get_ticks_usec())
	# 仅在测量相位（非 warmup）采样分段，避免预热污染统计。
	if _warmup_frames >= WARMUP_FRAMES and not _done and _phase_index < PHASES.size():
		for i in range(_parts.size()):
			(_part_samples[_parts[i]] as Array[int]).append(marks[i + 1] - marks[i])
	_tick_index += 1
	return marks[marks.size() - 1] - t0

func _run_cache() -> int:
	var t0: int = Time.get_ticks_usec()
	_poly_renderer.call("_rebuild_cache")
	return Time.get_ticks_usec() - t0

func _stats(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p50": 0.0, "p95": 0.0, "max": 0}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value in sorted:
		total += value
	var p50_index: int = clampi(int(float(sorted.size()) * 0.50), 0, sorted.size() - 1)
	var p95_index: int = clampi(int(float(sorted.size()) * 0.95), 0, sorted.size() - 1)
	return {
		"avg": float(total) / float(sorted.size()),
		"p50": float(sorted[p50_index]),
		"p95": float(sorted[p95_index]),
		"max": sorted[sorted.size() - 1],
	}

func _report() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("WINDOW_BENCH_DONE cells=%d phases=%d frames_per_phase=%d" % [
		(_manager.get("cells") as RefCounted).call("size"), PHASES.size(), MEASURE_FRAMES,
	])
	for phase in PHASES:
		var work: Dictionary = _stats(_samples[phase])
		var frame: Dictionary = _stats(_frame_samples[phase])
		var line: String = "WINDOW_BENCH %s work_us avg=%.1f p50=%.1f p95=%.1f max=%d | frame_ms avg=%.2f p95=%.2f" % [
			phase, float(work["avg"]), float(work["p50"]), float(work["p95"]), int(work["max"]),
			float(frame["avg"]) / 1000.0, float(frame["p95"]) / 1000.0,
		]
		print(line)
		lines.append(line)
	# tick 内部六段（跨所有含 tick 的相位累计），定位真正热点。
	lines.append("WINDOW_BENCH_TICK_PARTS samples_per_part=%d" % (_part_samples[_parts[0]] as Array[int]).size())
	for part in _parts:
		var stat: Dictionary = _stats(_part_samples[part])
		var line: String = "WINDOW_BENCH_PART %s avg=%.1fus p50=%.1f p95=%.1f max=%d" % [
			part, float(stat["avg"]), float(stat["p50"]), float(stat["p95"]), int(stat["max"]),
		]
		print(line)
		lines.append(line)
	# OrganismManager 自带 PerfProbe 的 behavior/physics/metabolism 细分，
	# 由 advance_physics_tick 内部 begin_tick/end_tick 采样，避开后台 eval 冻结。
	var probe: RefCounted = _manager.get("perf_probe") as RefCounted
	if probe != null:
		var avg: Dictionary = probe.call("averages")
		lines.append("WINDOW_BENCH_PERFPROBE samples=%d" % int(probe.call("sample_count")))
		for key in avg.keys():
			var pline: String = "WINDOW_BENCH_STAGE %s avg=%.1fus" % [str(key), float(avg[key])]
			print(pline)
			lines.append(pline)
		# metab_* 诊断子阶段（不进 STAGES 汇总），定位 metabolism 8ms 的内部构成。
		if probe.has_method("diagnostic_averages"):
			var diag: Dictionary = probe.call("diagnostic_averages")
			var diag_keys: Array = diag.keys()
			diag_keys.sort()
			for key in diag_keys:
				var k: String = str(key)
				# *_begin 是埋点记录的绝对时间戳，不是耗时，不得当子阶段打印。
				if k.ends_with("_begin"):
					continue
				if k.begins_with("metab_") or k.begins_with("tick_") or k.begins_with("setup_") or k.begins_with("phys_"):
					var dline: String = "WINDOW_BENCH_SUBSTAGE %s avg=%.1fus" % [k, float(diag[key])]
					print(dline)
					lines.append(dline)
	# v0.42：EnvironmentManager 批量采样准备分段（累计值按调用次数平均）。
	var sample_calls: int = int(_environment.get("diag_sample_calls"))
	if sample_calls > 0:
		var eline: String = "WINDOW_BENCH_ENVIDIAG calls=%d duplicate=%.1fus index_map=%.1fus field_sample=%.1fus" % [
			sample_calls,
			float(int(_environment.get("diag_duplicate_usec"))) / float(sample_calls),
			float(int(_environment.get("diag_index_map_usec"))) / float(sample_calls),
			float(int(_environment.get("diag_field_sample_usec"))) / float(sample_calls),
		]
		print(eline)
		lines.append(eline)
	# v0.42：GPU 批量采样内部四段（上传 / dispatch+sync / 回读 / 逐细胞缓存构建）。
	var field_ref: RefCounted = _environment.get("field") as RefCounted
	if field_ref != null and field_ref.has_method("get_sample_diagnostics"):
		var fd: Dictionary = field_ref.call("get_sample_diagnostics")
		var fline: String = "WINDOW_BENCH_GPUDIAG calls=%d upload=%.1fus dispatch=%.1fus readback=%.1fus post=%.1fus" % [
			int(fd.get("calls", 0)), float(fd.get("upload_usec", 0.0)),
			float(fd.get("dispatch_usec", 0.0)), float(fd.get("readback_usec", 0.0)),
			float(fd.get("post_usec", 0.0)),
		]
		print(fline)
		lines.append(fline)
	var path: String = ProjectSettings.globalize_path("user://window_perf_bench.txt")
	var file: FileAccess = FileAccess.open("user://window_perf_bench.txt", FileAccess.WRITE)
	if file != null:
		for line in lines:
			file.store_line(line)
		file.close()
		print("WINDOW_BENCH_FILE ", path)
