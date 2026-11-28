extends Node
## 固定 1/60 tick。倍速只改 tick 频率（speed_scale），绝不缩放 dt。
## 单帧 tick 上限 12，超出余量结转 carry，不补帧雪崩（§2.6 / T11）。

signal tick_advanced(tick_index: int)
signal carry_changed(carry_ticks: int, lagging: bool)
signal speed_changed(speed: float, lod: int)

const TICK_RATE: float = 60.0
const TICK_DT: float = 1.0 / 60.0
const MAX_TICKS_PER_FRAME: int = 12

## 档位表（§2.6）：speed 为倍率，neural/field 为更新间隔 tick，render_fps=0 表示不锁帧。
const SPEED_STEPS: Array[Dictionary] = [
	{"speed": 0.0, "neural": 1, "field": 1, "render_fps": 0, "lod": 0},
	{"speed": 1.0, "neural": 1, "field": 1, "render_fps": 0, "lod": 0},
	{"speed": 3.0, "neural": 1, "field": 1, "render_fps": 0, "lod": 0},
	{"speed": 8.0, "neural": 2, "field": 1, "render_fps": 0, "lod": 1},
	{"speed": 16.0, "neural": 4, "field": 2, "render_fps": 0, "lod": 2},
	{"speed": 32.0, "neural": 8, "field": 4, "render_fps": 30, "lod": 3},
]

@export var running: bool = true
@export_range(0.0, 32.0, 0.25) var speed_scale: float = 1.0

var tick_index: int = 0
## 阶段 B3：worker 模式下 tick_index 是主线程目标 tick；真实推进由 worker ticks 回报。
var worker_target_mode: bool = false
var target_tick: int = 0
var worker_progress_tick: int = 0
var _accumulator: float = 0.0
## 结转的未执行 tick 数（§2.6）：32× 时一帧最多 12 tick，余量留到后续帧。
var carry_ticks: int = 0
var _carry_reported: bool = false
var _lod_level: int = 0
var _neural_interval: int = 1
var _field_interval: int = 1
var _render_fps: int = 0

func _ready() -> void:
	apply_speed(speed_scale)

func _process(delta: float) -> void:
	if not running:
		return
	if worker_target_mode:
		# 不再受 12 tick/帧限制：只发布目标 tick，worker 连续推进真实模拟。
		_accumulator += delta * speed_scale
		var produced: int = int(_accumulator / TICK_DT)
		_accumulator -= float(produced) * TICK_DT
		target_tick += produced
		_update_worker_carry()
		if produced > 0:
			# 一帧最多一次信号；Main 在 worker 模式把它当作目标 tick，而非同步执行请求。
			tick_advanced.emit(target_tick)
		return
	_accumulator += delta * speed_scale
	# v0.47：累加器只保留不足 1 tick 的小数余量，整数部分全部并入 carry。
	# 旧实现把 overflow 加进 carry 的同时又在 _accumulator 留了一份，造成双重计数，
	# carry 呈二次增长瞬间顶到 4096；现在 carry 是唯一欠账来源，下一帧优先消化。
	var whole_ticks: int = int(_accumulator / TICK_DT)
	_accumulator -= float(whole_ticks) * TICK_DT
	carry_ticks = mini(carry_ticks + whole_ticks, 4096)
	if carry_ticks <= 0:
		return
	# 单帧上限 12 是 §2.6 冻结规格、T11 硬断言，不因锁帧档放宽；
	# 30 fps 锁帧只降渲染开销，tick 吞吐仍按规格封顶 720 tick/s。
	var budget: int = mini(carry_ticks, MAX_TICKS_PER_FRAME)
	carry_ticks -= budget
	_update_carry_signal()
	for i in range(budget):
		tick_index += 1
		tick_advanced.emit(tick_index)

## 单步：绕过累加器，强制推进一 tick 并刷新调试视图（§2.6）。
func step_once() -> void:
	if worker_target_mode:
		target_tick += 1
		_update_worker_carry()
		tick_advanced.emit(target_tick)
		return
	tick_index += 1
	tick_advanced.emit(tick_index)


func set_worker_target_mode(enabled: bool) -> void:
	worker_target_mode = enabled
	if enabled:
		target_tick = tick_index
		worker_progress_tick = tick_index
	clear_carry()


func set_worker_progress(progress_tick: int) -> void:
	if not worker_target_mode:
		return
	worker_progress_tick = maxi(worker_progress_tick, progress_tick)
	_update_worker_carry()


func _update_worker_carry() -> void:
	carry_ticks = clampi(target_tick - worker_progress_tick, 0, 4096)
	_update_carry_signal()


func get_target_tick() -> int:
	return target_tick if worker_target_mode else tick_index

func set_speed(scale_value: float) -> void:
	apply_speed(scale_value)

## 设置倍速并同步 LOD 精度档；返回是否成功。
func apply_speed(scale_value: float) -> bool:
	var matched: Dictionary = _match_step(scale_value)
	if matched.is_empty():
		return false
	speed_scale = float(matched.get("speed", 1.0))
	_neural_interval = maxi(1, int(matched.get("neural", 1)))
	_field_interval = maxi(1, int(matched.get("field", 1)))
	_render_fps = maxi(0, int(matched.get("render_fps", 0)))
	_lod_level = int(matched.get("lod", 0))
	speed_changed.emit(speed_scale, _lod_level)
	return true

func _match_step(scale_value: float) -> Dictionary:
	for step in SPEED_STEPS:
		if is_equal_approx(float(step.get("speed", -1.0)), scale_value):
			return step
	# 非档位值（如 UI 滑块的 2.25）按最近档位吸附，但保留 speed 值用于结算元数据。
	var nearest: Dictionary = SPEED_STEPS[1]
	var best_delta: float = absf(scale_value - float(nearest.get("speed", 1.0)))
	for step in SPEED_STEPS:
		var delta_value: float = absf(scale_value - float(step.get("speed", 1.0)))
		if delta_value < best_delta:
			best_delta = delta_value
			nearest = step
	var result: Dictionary = nearest.duplicate()
	result["speed"] = clampf(scale_value, 0.0, 32.0)
	return result

func _update_carry_signal() -> void:
	var lagging: bool = carry_ticks > MAX_TICKS_PER_FRAME
	if lagging != _carry_reported or carry_ticks % 12 == 0:
		carry_changed.emit(carry_ticks, lagging)
		_carry_reported = lagging

## 清空结转（切档/读档时调用）。
func clear_carry() -> void:
	carry_ticks = 0
	_accumulator = 0.0
	_carry_reported = false
	carry_changed.emit(0, false)

func is_lagging() -> bool:
	return carry_ticks > MAX_TICKS_PER_FRAME

func get_lod_level() -> int:
	return _lod_level

func get_neural_interval() -> int:
	return _neural_interval

func get_field_interval() -> int:
	return _field_interval

func get_render_fps() -> int:
	return _render_fps

## 当前 tick 是否应执行神经更新（供 OrganismManager 降频）。
func should_update_neural() -> bool:
	return tick_index % maxi(1, _neural_interval) == 0

## 当前 tick 是否应执行场扩散（供 EnvironmentManager 降频）。
func should_update_field() -> bool:
	return tick_index % maxi(1, _field_interval) == 0

## 存档元数据：倍速与 LOD 精度档（§3.5）。
func get_timing_snapshot() -> Dictionary:
	return {
		"tick_index": tick_index,
		"speed_scale": speed_scale,
		"carry_ticks": carry_ticks,
		"accumulator": _accumulator,
		"running": running,
		"lod_level": _lod_level,
		"neural_interval": _neural_interval,
		"field_interval": _field_interval,
		"render_fps": _render_fps
	}

func restore_timing(snapshot: Dictionary) -> void:
	tick_index = int(snapshot.get("tick_index", tick_index))
	target_tick = tick_index
	worker_progress_tick = tick_index
	speed_scale = float(snapshot.get("speed_scale", speed_scale))
	carry_ticks = int(snapshot.get("carry_ticks", 0))
	_accumulator = float(snapshot.get("accumulator", 0.0))
	running = bool(snapshot.get("running", running))
	apply_speed(speed_scale)
