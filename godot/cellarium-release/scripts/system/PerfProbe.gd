extends RefCounted
## 性能埋点（§8.1 / §9.1）：分阶段 Time.get_ticks_usec() 计时 + 环形缓冲 + CSV 导出。
## 纯 RefCounted，无 class_name，调用方 preload。不写模拟状态，不进确定性 hash。

const STAGES: Array[String] = ["behavior", "physics", "metabolism", "predation", "signal", "field", "commit"]

var capacity: int = 600
var _samples: Array[Dictionary] = []
var _head: int = 0
var _tick: int = 0
var _active: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _start_usec: int = 0
var _save_usec: int = 0
var _boot_usec: int = 0

func configure(capacity_value: int = 600) -> void:
	capacity = maxi(8, capacity_value)
	reset()

func reset() -> void:
	_samples.clear()
	_head = 0
	_tick = 0
	_active.clear()
	_last_snapshot.clear()

func begin_tick() -> void:
	_tick += 1
	_active = {"tick": _tick}

func begin(stage: String) -> void:
	_active[stage + "_begin"] = Time.get_ticks_usec()

func end(stage: String) -> void:
	var begin_key: String = stage + "_begin"
	if not _active.has(begin_key):
		return
	var elapsed: float = float(Time.get_ticks_usec() - int(_active[begin_key]))
	_active[stage] = elapsed

func end_tick() -> void:
	var total: float = 0.0
	for stage in STAGES:
		total += float(_active.get(stage, 0.0))
	_active["total"] = total
	var snapshot: Dictionary = _active.duplicate(true)
	_last_snapshot = snapshot
	if _samples.size() < capacity:
		_samples.append(snapshot)
	else:
		_samples[_head] = snapshot
		_head = (_head + 1) % capacity

func record_save(elapsed_ms: float) -> void:
	_save_usec = int(elapsed_ms * 1000.0)

func record_boot(elapsed_ms: float) -> void:
	_boot_usec = int(elapsed_ms * 1000.0)

func last_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)

func sample_count() -> int:
	return _samples.size()

## 各阶段平均值（微秒）。
func averages() -> Dictionary:
	var result: Dictionary = {}
	if _samples.is_empty():
		return result
	for stage in STAGES + ["total"]:
		var sum_value: float = 0.0
		for sample in _samples:
			sum_value += float((sample as Dictionary).get(stage, 0.0))
		result[stage] = sum_value / float(_samples.size())
	return result

## v0.40：诊断用——返回所有样本中出现过的键的平均值（含 metab_* 子阶段）。
## 只读，不进 STAGES 汇总、不进 state hash，专供 WindowPerfBenchmark 定位热点。
func diagnostic_averages() -> Dictionary:
	var result: Dictionary = {}
	if _samples.is_empty():
		return result
	var keys: Dictionary = {}
	for sample in _samples:
		for key in (sample as Dictionary).keys():
			keys[str(key)] = true
	for key in keys.keys():
		var sum_value: float = 0.0
		var count: int = 0
		for sample in _samples:
			var value: Variant = (sample as Dictionary).get(key, null)
			if value != null:
				sum_value += float(value)
				count += 1
		if count > 0:
			result[str(key)] = sum_value / float(count)
	return result

## 是否达到 §8.1 目标：1000 生物 / 8000 细胞时 tick ≤ 8 ms（headless CPU 可放宽到 14 ms）。
func meets_tick_budget(cpu_fallback: bool = false) -> bool:
	var averages_value: Dictionary = averages()
	if averages_value.is_empty():
		return false
	var budget_ms: float = 14.0 if cpu_fallback else 8.0
	return float(averages_value.get("total", 0.0)) <= budget_ms * 1000.0

## 导出 CSV：tick + 各阶段微秒 + total。
func export_csv() -> String:
	var lines: Array[String] = []
	var header: Array[String] = ["tick"]
	for stage in STAGES:
		header.append(stage)
	header.append("total")
	lines.append(",".join(header))
	for sample in _samples:
		var values: Array[String] = [str(int((sample as Dictionary).get("tick", 0)))]
		for stage in STAGES:
			values.append("%.1f" % float((sample as Dictionary).get(stage, 0.0)))
		values.append("%.1f" % float((sample as Dictionary).get("total", 0.0)))
		lines.append(",".join(values))
	return "\n".join(lines)

## 写入 CSV 文件（供 benchmark 工具导出）。
func export_csv_to_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(export_csv())
	file.close()
	return true

func get_metadata() -> Dictionary:
	return {
		"samples": _samples.size(),
		"capacity": capacity,
		"save_ms": float(_save_usec) / 1000.0,
		"boot_ms": float(_boot_usec) / 1000.0,
		"budget_met": meets_tick_budget(true)
	}
