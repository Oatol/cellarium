extends Node
## 阶段 B B1 验证：封装后的 SimWorker 在 worker 跑真实隔离模拟，
## 主线程读三缓冲快照并做 checksum 校验，验证壳可用（快照无撕裂 + tick 推进 + 命令传递）。
## 只读探针，跑完自动退出，输出 user://sim_worker_probe.txt。

const PREVIEW_SCRIPT: Script = preload("res://scripts/core/data/PreviewWorld.gd")
const SIM_WORKER_SCRIPT: Script = preload("res://scripts/system/SimWorker.gd")
const RUN_TICKS: int = 200
const CAPACITY: int = 128

var _worker: RefCounted = null
var _prev_tick: int = -1
var _tear: int = 0
var _non_monotonic: int = 0
var _reads: int = 0
var _max_cells: int = 0
var _done: bool = false
var _report_lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	var world: RefCounted = PREVIEW_SCRIPT.new() as RefCounted
	world.call("setup", [], 0)
	# 主线程预热 native 对象（worker 内禁止 new Object）
	for i in range(2):
		world.call("step")
	_worker = SIM_WORKER_SCRIPT.new() as RefCounted
	_worker.call("configure", world, CAPACITY)
	if not bool(_worker.call("is_configured")):
		_push("FAIL_STATE not configured")
		_finish()
		return
	if not bool(_worker.call("start")):
		_push("FAIL_STATE start: %s" % str(_worker.get("diag_last_error")))
		_finish()
		return
	_push("PROBE_START capacity=%d target_ticks=%d" % [CAPACITY, RUN_TICKS])

func _process(_delta: float) -> void:
	if _done or _worker == null:
		return
	var snap: RefCounted = _worker.call("read_snapshot") as RefCounted
	var count: int = int(snap.get("cell_count"))
	var tick: int = int(snap.get("tick"))
	_max_cells = maxi(_max_cells, count)
	# checksum 复算：pos_x + alive，验证快照未被并发写坏
	var px: PackedFloat32Array = snap.get("pos_x")
	var al: PackedByteArray = snap.get("alive")
	var acc: int = 0
	for i in range(count):
		acc = (acc + int(px[i] * 10000.0)) % 1000000007
		acc = (acc << 1) | (al[i] & 1)
	var stored: int = int(snap.get("checksum"))
	if stored != acc:
		_tear += 1
	if tick < _prev_tick:
		_non_monotonic += 1
	_prev_tick = tick
	_reads += 1

	var worker_ticks: int = int(_worker.call("get_worker_ticks"))
	if worker_ticks >= RUN_TICKS:
		_worker.call("stop")
		_worker.call("wait")
		_push("PROBE_END worker_ticks=%d snapshot_tick=%d max_cells=%d" % [
			worker_ticks, tick, _max_cells,
		])
		_push("PROBE_SNAPSHOT reads=%d tear=%d non_monotonic=%d" % [
			_reads, _tear, _non_monotonic,
		])
		var verdict: String = "OK" if (_tear == 0 and _non_monotonic == 0 and worker_ticks >= RUN_TICKS) else "FAIL"
		_push("PROBE_VERDICT %s" % verdict)
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	var file: FileAccess = FileAccess.open("user://sim_worker_probe.txt", FileAccess.WRITE)
	if file != null:
		for line in _report_lines:
			file.store_line(line)
		file.close()
	print("PROBE_FILE ", ProjectSettings.globalize_path("user://sim_worker_probe.txt"))
	get_tree().quit()

func _push(line: String) -> void:
	print(line)
	_report_lines.append(line)
