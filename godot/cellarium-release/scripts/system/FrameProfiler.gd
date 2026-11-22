extends RefCounted
## v0.39.0 C 路线诊断：逐帧分段计时（纯观测，不写模拟状态、不进 hash）。
## 用静态累加器，各热点在每帧调用 begin_* / end_*，GameHUD 每 0.5s 读 report() 显示。
## 所有方法在无计时（未调用 begin）时安全返回，默认零开销可忽略。

const ENABLED: bool = true

# 各段累计 us（每 0.5s 窗口清零由 report 完成）
static var _tick_us: int = 0
static var _tick_calls: int = 0
static var _rebuild_poly_us: int = 0
static var _rebuild_scene_us: int = 0
static var _rebuild_calls: int = 0
static var _frame_us: int = 0
static var _frame_calls: int = 0

# 瞬时值（最近一次）
static var _last_tick_us: int = 0
static var _last_poly_us: int = 0
static var _last_scene_us: int = 0

static var _t0_tick: int = 0
static var _t0_poly: int = 0
static var _t0_scene: int = 0
static var _t0_frame: int = 0

## 由 GameHUD 每帧调用一次，传入引擎 delta（= 上一帧到本帧的真实间隔，含 GPU/合成）。
static func note_frame(delta_seconds: float) -> void:
	if not ENABLED:
		return
	_frame_us += int(delta_seconds * 1000000.0)
	_frame_calls += 1

static func tick_begin() -> void:
	if not ENABLED:
		return
	_t0_tick = Time.get_ticks_usec()

static func tick_end() -> void:
	if not ENABLED:
		return
	var dt: int = Time.get_ticks_usec() - _t0_tick
	_tick_us += dt
	_tick_calls += 1
	_last_tick_us = dt

static func poly_begin() -> void:
	if not ENABLED:
		return
	_t0_poly = Time.get_ticks_usec()

static func poly_end() -> void:
	if not ENABLED:
		return
	var dt: int = Time.get_ticks_usec() - _t0_poly
	_rebuild_poly_us += dt
	_rebuild_calls += 1
	_last_poly_us = dt

static func scene_begin() -> void:
	if not ENABLED:
		return
	_t0_scene = Time.get_ticks_usec()

static func scene_end() -> void:
	if not ENABLED:
		return
	var dt: int = Time.get_ticks_usec() - _t0_scene
	_rebuild_scene_us += dt
	_last_scene_us = dt

## 返回窗口内的分段统计字典，并清零累加器。avg_* 为每帧/每 tick 微秒。
static func report() -> Dictionary:
	var n_frame: int = maxi(_frame_calls, 1)
	var n_tick: int = maxi(_tick_calls, 1)
	var result: Dictionary = {
		"frame_total_us": float(_frame_us),
		"frame_calls": _frame_calls,
		"frame_avg_us": float(_frame_us) / float(n_frame),
		"tick_total_us": float(_tick_us),
		"tick_avg_us": float(_tick_us) / float(n_tick),
		"tick_per_frame_us": float(_tick_us) / float(n_frame),
		"tick_calls": _tick_calls,
		"poly_avg_us": float(_rebuild_poly_us) / float(n_frame),
		"scene_avg_us": float(_rebuild_scene_us) / float(n_frame),
		"last_tick_us": float(_last_tick_us),
		"last_poly_us": float(_last_poly_us),
		"last_scene_us": float(_last_scene_us),
	}
	_tick_us = 0; _tick_calls = 0
	_rebuild_poly_us = 0; _rebuild_scene_us = 0; _rebuild_calls = 0
	_frame_us = 0; _frame_calls = 0
	return result

static func reset() -> void:
	_tick_us = 0; _tick_calls = 0
	_rebuild_poly_us = 0; _rebuild_scene_us = 0; _rebuild_calls = 0
	_frame_us = 0; _frame_calls = 0
	_last_tick_us = 0; _last_poly_us = 0; _last_scene_us = 0
