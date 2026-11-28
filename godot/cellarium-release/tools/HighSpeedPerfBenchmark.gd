extends Node
## Read-only real-window benchmark for high-speed feel.
## It runs the real main.tscn tick loop (TickCore._process -> Main._on_tick_advanced)
## at 1x / 8x / 16x / 32x with a frozen cell count, then writes measurements to
## user://high_speed_perf_bench.txt. No debugger / game_eval / mouse input is used.

const TICK_DT: float = 1.0 / 60.0
const DEFAULT_TARGET_CELLS: int = 512
const DEFAULT_WARMUP_FRAMES: int = 12
const DEFAULT_MEASURE_FRAMES: int = 60

var _target_cells: int = DEFAULT_TARGET_CELLS
var _warmup_frames: int = DEFAULT_WARMUP_FRAMES
var _measure_frames: int = DEFAULT_MEASURE_FRAMES
var _speeds: Array[float] = [1.0, 8.0, 16.0, 32.0]

var _main: Node = null
var _tick_core: Node = null
var _manager: Node = null
var _environment: Node = null
var _command_bus: Node = null
var _poly_renderer: Node = null
var _worker_mode: bool = false
var _worker_visual_field: bool = true
var _render_enabled: bool = true
var _prev_worker_tick: int = 0
var _setup_done: bool = false
var _done: bool = false

var _phase_index: int = 0
var _warmup_left: int = 0
var _frame_in_phase: int = 0
var _has_prev_frame: bool = false
var _prev_delta: float = 0.0
var _prev_ticks: int = 0
var _prev_tick_work_us: int = 0
var _prev_tick_max_us: int = 0

var _ticks_this_frame: int = 0
var _tick_work_total_us: int = 0
var _tick_work_max_us: int = 0
var _tick_begin_us: int = 0

## 阶段 C：worker diag 累计值在阶段起点的快照，用于算真实单世界的每 tick 分段。
var _phase_start_diag: Dictionary = {}
var _phase_start_worker_tick: int = 0
var _phase_start_wall_us: int = 0

var _frame_samples: Array[int] = []
var _tick_samples: Array[int] = []
var _tick_work_samples: Array[int] = []
var _tick_max_samples: Array[int] = []
var _carry_samples: Array[int] = []
var _phase_reports: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_parse_args()
	await get_tree().process_frame
	_setup()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cells="):
			_target_cells = maxi(64, int(arg.substr(8)))
		elif arg.begins_with("--warmup="):
			_warmup_frames = clampi(int(arg.substr(9)), 0, 120)
		elif arg.begins_with("--frames="):
			_measure_frames = clampi(int(arg.substr(9)), 10, 300)
		elif arg.begins_with("--worker"):
			_worker_mode = arg == "--worker" or arg == "--worker=1" or arg == "--worker=true"
		elif arg == "--no-visual-field":
			_worker_visual_field = false
		elif arg == "--no-render":
			_render_enabled = false
		elif arg.begins_with("--speeds="):
			_speeds.clear()
			for token in arg.substr(9).split(","):
				var speed: float = float(token)
				if speed > 0.0:
					_speeds.append(speed)


func _setup() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn load failed")
		return
	_main = packed.instantiate()
	_main.set("create_demo_organism", false)
	# 基准先铺冻结细胞，再由 --worker 决定何时启动 worker，避免镜像世界空启动。
	_main.set("threaded_simulation_enabled", false)
	_main.set("worker_visual_field_enabled", _worker_visual_field)
	_tick_core = _main.get_node_or_null("Simulation/TickCore")
	if _tick_core == null:
		_fail("TickCore missing")
		return
	# Connect the begin marker before add_child so it runs before Main's tick handler.
	_tick_core.connect("tick_advanced", Callable(self, "_on_tick_begin"))
	add_child(_main)
	await get_tree().process_frame

	_manager = _main.get_node_or_null("Simulation/OrganismManager")
	_environment = _main.get_node_or_null("Simulation/EnvironmentManager")
	_command_bus = _main.get_node_or_null("Simulation/CommandBus")
	_poly_renderer = _main.get_node_or_null("DishView/CellBatchPoly")
	if _manager == null or _environment == null or _command_bus == null or _poly_renderer == null:
		_fail("required node missing")
		return
	var dish_view: Node2D = _main.get_node_or_null("DishView") as Node2D
	if dish_view != null:
		dish_view.visible = _render_enabled
	# Connect the end marker after Main._ready so Main's tick handler is between them.
	_tick_core.connect("tick_advanced", Callable(self, "_on_tick_end"))
	_manager.set("autonomous_division_enabled", false)
	_spawn_cells(_target_cells)
	if _worker_mode:
		if not bool(_main.call("start_threaded_simulation")):
			_fail("worker engine start failed")
			return
		_prev_worker_tick = int(_main.call("get_worker_tick"))
	print("HSPD_SETUP cells=%d worker=%s visual_field=%s render=%s native=%s render_cache=%s" % [
		int((_manager.get("cells") as RefCounted).call("size")),
		str(_worker_mode),
		str(_worker_visual_field),
		str(_render_enabled),
		str(_manager.get("native_spatial_enabled")),
		str(ClassDB.class_exists("CellRenderCache")),
	])
	_setup_done = true
	_start_phase(0)


func _fail(reason: String) -> void:
	print("HSPD_FAIL ", reason)
	_done = true
	_write_report()


func _spawn_cells(target: int) -> void:
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
	while spawned < target and row <= 30:
		var y: float = float(row) * spacing * 0.866
		var col: int = -30
		while col <= 30 and spawned < target:
			var x: float = float(col) * spacing + float(absi(row) % 2) * spacing * 0.5
			if x * x + y * y <= radius * radius:
				_manager.call("register_zygote", 200000 + spawned, 0, -1, genome, center + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1
	if spawned != target:
		print("HSPD_SPAWN_WARN spawned=%d target=%d" % [spawned, target])


func _start_phase(index: int) -> void:
	if index >= _speeds.size():
		_done = true
		print("HSPD_DONE")
		_write_report()
		get_tree().quit()
		return
	_phase_index = index
	var speed: float = _speeds[index]
	_tick_core.call("apply_speed", speed)
	_tick_core.call("clear_carry")
	_tick_core.set("running", true)
	_warmup_left = _warmup_frames
	_frame_in_phase = 0
	_frame_samples.clear()
	_tick_samples.clear()
	_tick_work_samples.clear()
	_tick_max_samples.clear()
	_carry_samples.clear()
	_ticks_this_frame = 0
	_tick_work_total_us = 0
	_tick_work_max_us = 0
	_has_prev_frame = false
	_phase_start_wall_us = Time.get_ticks_usec()
	if _worker_mode:
		_prev_worker_tick = int(_main.call("get_worker_tick"))
		_phase_start_worker_tick = _prev_worker_tick
		_phase_start_diag = (_main.call("get_worker_diag") as Dictionary).duplicate()
	print("HSPD_PHASE speed=%.2fx warmup=%d frames=%d cells=%d worker=%s" % [
		speed, _warmup_frames, _measure_frames, _target_cells, str(_worker_mode),
	])


func _on_tick_begin(_tick_index: int) -> void:
	_tick_begin_us = Time.get_ticks_usec()


func _on_tick_end(_tick_index: int) -> void:
	if _worker_mode:
		var worker_tick: int = int(_main.call("get_worker_tick"))
		_ticks_this_frame += maxi(0, worker_tick - _prev_worker_tick)
		_prev_worker_tick = worker_tick
		return
	_ticks_this_frame += 1
	var work_us: int = maxi(0, Time.get_ticks_usec() - _tick_begin_us)
	_tick_work_total_us += work_us
	_tick_work_max_us = maxi(_tick_work_max_us, work_us)


func _process(delta: float) -> void:
	if _done or not _setup_done:
		return
	if _has_prev_frame:
		_record_frame(_prev_delta, _prev_ticks, _prev_tick_work_us, _prev_tick_max_us)
		if _warmup_left <= 0 and _frame_in_phase >= _measure_frames:
			_report_phase()
			_start_phase(_phase_index + 1)
			return
	_prev_delta = delta
	_prev_ticks = _ticks_this_frame
	_prev_tick_work_us = _tick_work_total_us
	_prev_tick_max_us = _tick_work_max_us
	_ticks_this_frame = 0
	_tick_work_total_us = 0
	_tick_work_max_us = 0
	_has_prev_frame = true


func _record_frame(delta: float, ticks: int, work_us: int, max_work_us: int) -> void:
	if _warmup_left > 0:
		_warmup_left -= 1
		return
	_frame_samples.append(int(delta * 1000000.0))
	_tick_samples.append(ticks)
	_tick_work_samples.append(work_us)
	_tick_max_samples.append(max_work_us)
	_carry_samples.append(int(_tick_core.get("carry_ticks")))
	_frame_in_phase += 1


func _stats(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p50": 0, "p95": 0, "max": 0}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value in sorted:
		total += value
	var p50_index: int = clampi(int(float(sorted.size()) * 0.50), 0, sorted.size() - 1)
	var p95_index: int = clampi(int(float(sorted.size()) * 0.95), 0, sorted.size() - 1)
	return {
		"avg": float(total) / float(sorted.size()),
		"p50": sorted[p50_index],
		"p95": sorted[p95_index],
		"max": sorted[sorted.size() - 1],
	}


func _count_above(values: Array[int], threshold_us: int) -> int:
	var count: int = 0
	for value in values:
		if value > threshold_us:
			count += 1
	return count


func _report_phase() -> void:
	var speed: float = _speeds[_phase_index]
	var frame: Dictionary = _stats(_frame_samples)
	var ticks: Dictionary = _stats(_tick_samples)
	var work: Dictionary = _stats(_tick_work_samples)
	var max_work: Dictionary = _stats(_tick_max_samples)
	var carry: Dictionary = _stats(_carry_samples)
	var total_ticks: int = 0
	for value in _tick_samples:
		total_ticks += value
	# 阶段 C 修正：delta 被渲染 vsync / max_fps 钳制在 16.7ms，不能当墙钟。
	# 用 OS 单调钟测得的真实墙钟计算吞吐与 effective，避免虚高约 25-32×。
	var wall_seconds: float = float(Time.get_ticks_usec() - _phase_start_wall_us) / 1000000.0
	var frame_delta_seconds: float = float(frame["avg"]) * float(_frame_samples.size()) / 1000000.0
	var sim_seconds: float = float(total_ticks) * TICK_DT
	var effective: float = 0.0
	if wall_seconds > 0.0:
		effective = sim_seconds / wall_seconds
	var lines: PackedStringArray = PackedStringArray()
	lines.append("HSPD_RESULT speed=%.2fx effective=%.2fx ticks=%d sim_s=%.3f wall_s=%.3f frame_delta_s=%.3f frames=%d" % [
		speed, effective, total_ticks, sim_seconds, wall_seconds, frame_delta_seconds, _frame_samples.size(),
	])
	lines.append("HSPD_FRAME speed=%.2fx avg_ms=%.2f p50_ms=%.2f p95_ms=%.2f max_ms=%.2f" % [
		speed, float(frame["avg"]) / 1000.0, float(ticks_get(frame, "p50")) / 1000.0,
		float(ticks_get(frame, "p95")) / 1000.0, float(ticks_get(frame, "max")) / 1000.0,
	])
	lines.append("HSPD_TICKS speed=%.2fx avg=%.2f p50=%d p95=%d max=%d" % [
		speed, float(ticks["avg"]), int(ticks["p50"]), int(ticks["p95"]), int(ticks["max"]),
	])
	lines.append("HSPD_TICKWORK speed=%.2fx avg_us=%.1f p95_us=%d max_us=%d frame_max_us=%d" % [
		speed, float(work["avg"]), int(work["p95"]), int(work["max"]), int(max_work["max"]),
	])
	lines.append("HSPD_CARRY speed=%.2fx avg=%.1f p95=%d max=%d" % [
		speed, float(carry["avg"]), int(carry["p95"]), int(carry["max"]),
	])
	lines.append("HSPD_STALL speed=%.2fx gt33=%d gt50=%d gt100=%d" % [
		speed, _count_above(_frame_samples, 33000), _count_above(_frame_samples, 50000),
		_count_above(_frame_samples, 100000),
	])
	lines.append("HSPD_RENDER speed=%.2fx engine_max_fps=%d target_render_fps=%d" % [
		speed, Engine.max_fps, int(_tick_core.call("get_render_fps")),
	])
	lines.append("HSPD_WORKER speed=%.2fx enabled=%s worker_ticks=%d" % [
		speed, str(_worker_mode), int(_main.call("get_worker_tick")),
	])
	if _worker_mode:
		var wd: Dictionary = _main.call("get_worker_diag") as Dictionary
		lines.append("HSPD_WLOD speed=%.2fx neural=%d field=%d" % [
			speed, int(wd.get("neural_interval", -1)), int(wd.get("field_interval", -1)),
		])
		var real_wall_s: float = float(Time.get_ticks_usec() - _phase_start_wall_us) / 1000000.0
		var dwt: int = maxi(1, int(wd.get("worker_ticks", 0)) - _phase_start_worker_tick)
		lines.append("HSPD_WCLOCK speed=%.2fx real_wall_s=%.3f dworker_ticks=%d tick_per_s=%.1f" % [
			speed, real_wall_s, dwt, float(dwt) / maxf(0.001, real_wall_s),
		])
	if _worker_mode and not _phase_start_diag.is_empty():
		var end_diag: Dictionary = _main.call("get_worker_diag") as Dictionary
		var d_ticks: int = maxi(1, int(end_diag.get("worker_ticks", 0)) - _phase_start_worker_tick)
		lines.append("HSPD_WSPLIT speed=%.2fx dticks=%d org=%.1f dev=%.1f nutrient=%.1f food=%.1f field=%.1f snap=%.1f us" % [
			speed, d_ticks,
			float(int(end_diag.get("org_us", 0)) - int(_phase_start_diag.get("org_us", 0))) / float(d_ticks),
			float(int(end_diag.get("dev_us", 0)) - int(_phase_start_diag.get("dev_us", 0))) / float(d_ticks),
			float(int(end_diag.get("nutrient_us", 0)) - int(_phase_start_diag.get("nutrient_us", 0))) / float(d_ticks),
			float(int(end_diag.get("food_us", 0)) - int(_phase_start_diag.get("food_us", 0))) / float(d_ticks),
			float(int(end_diag.get("field_us", 0)) - int(_phase_start_diag.get("field_us", 0))) / float(d_ticks),
			float(int(end_diag.get("snapshot_us", 0)) - int(_phase_start_diag.get("snapshot_us", 0))) / float(d_ticks),
		])
	for line in lines:
		print(line)
		_phase_reports.append(line)
	_write_report()


func ticks_get(values: Dictionary, key: String) -> int:
	return int(values.get(key, 0))


func _write_report() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("HSPD_HEAD cells=%d warmup=%d measure_frames=%d speeds=%s" % [
		_target_cells, _warmup_frames, _measure_frames, str(_speeds),
	])
	for line in _phase_reports:
		lines.append(line)
	if _done:
		lines.append("HSPD_DONE")
	var file: FileAccess = FileAccess.open("user://high_speed_perf_bench.txt", FileAccess.WRITE)
	if file == null:
		return
	for line in lines:
		file.store_line(line)
	file.close()
	print("HSPD_FILE ", ProjectSettings.globalize_path("user://high_speed_perf_bench.txt"))
