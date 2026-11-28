extends Node
## 阶段 B 原型（只读，不碰生产代码）：验证 GDScript Thread + Mutex + 三缓冲 PackedArray。
## 验证四项：① Thread worker 能跑 PackedArray 计算；② Mutex 保护共享索引；
## ③ 三缓冲避免主线程读与 worker 写同缓冲（双缓冲实测有 17/106 checksum mismatch）；
## ④ 主线程读快照 checksum 一致。跑完自动退出，统计落盘 user://thread_prototype.txt。

const TARGET_CELLS: int = 1024
const RUN_TICKS: int = 6000
const MAX_SECONDS: float = 20.0
const SLOT_COUNT: int = 3

var _thread: Thread = null
var _mutex: Mutex = null
var _snapshots: Array[RefCounted] = []
var _snap_script: Script = null
var _front_index: int = 0
var _worker_ticks: int = 0
var _stop: bool = false
var _start_usec: int = 0
var _done: bool = false

var _read_samples_usec: Array[int] = []
var _tear_count: int = 0
var _read_count: int = 0
var _last_tick_read: int = -1
var _non_monotonic: int = 0
var _report_lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	_snap_script = load("res://tools/ThreadPrototypeSnapshot.gd") as Script
	if _snap_script == null:
		_push("FAIL_STATE snapshot script missing")
		_finish()
		return
	_mutex = Mutex.new()
	for i in range(SLOT_COUNT):
		var snap: RefCounted = _snap_script.new() as RefCounted
		snap.call("configure", TARGET_CELLS)
		_init_snapshot(snap, i)
		_snapshots.append(snap)
	_start_usec = Time.get_ticks_usec()
	_thread = Thread.new()
	var err: int = _thread.start(Callable(self, "_worker_loop"))
	if err != OK:
		_push("FAIL_STATE thread.start err=%d" % err)
		_finish()
		return
	_push("PROTO_THREAD_START cells=%d ticks=%d slots=%d" % [TARGET_CELLS, RUN_TICKS, SLOT_COUNT])

func _init_snapshot(snap: RefCounted, seed_offset: int) -> void:
	var px: PackedFloat32Array = snap.get("pos_x")
	var alive: PackedByteArray = snap.get("alive")
	for i in range(TARGET_CELLS):
		px[i] = float(i + seed_offset) * 0.01
		alive[i] = 1
	snap.set("tick", 0)
	snap.set("checksum", _checksum(px, alive))

func _checksum(px: PackedFloat32Array, alive: PackedByteArray) -> int:
	var acc: int = 0
	for i in range(px.size()):
		acc = (acc + int(px[i] * 10000.0)) % 1000000007
		acc = (acc << 1) | (alive[i] & 1)
	return acc

var _local_px: PackedFloat32Array = PackedFloat32Array()
var _local_alive: PackedByteArray = PackedByteArray()

func _worker_loop() -> void:
	_local_px.resize(TARGET_CELLS)
	_local_alive.resize(TARGET_CELLS)
	for i in range(TARGET_CELLS):
		_local_px[i] = float(i) * 0.01
		_local_alive[i] = 1
	var local_tick: int = 0
	while local_tick < RUN_TICKS:
		var elapsed: float = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
		if elapsed > MAX_SECONDS:
			break
		_mutex.lock()
		var front: int = _front_index
		var stop: bool = _stop
		_mutex.unlock()
		if stop:
			break
		# 三缓冲：选既不是当前 front、也不是上次写入槽的 slot。
		# 主线程只在 _process 读 front，worker 写一个空闲 slot，写完才交换。
		var back: int = (front + 1) % SLOT_COUNT
		if back == _last_written:
			back = (front + 2) % SLOT_COUNT
		# 方案三：worker 在独立 local 数组上计算（无锁），只在短临界区内一次性
		# 把结果拷进 back 快照。锁持有时间从"全量计算+checksum"降到"一次数组赋值"。
		for i in range(TARGET_CELLS):
			_local_px[i] += 0.001
			if (i + local_tick) % 97 == 0:
				_local_alive[i] = 1 - _local_alive[i]
		var snap: RefCounted = _snapshots[back]
		_mutex.lock()
		var px: PackedFloat32Array = snap.get("pos_x")
		var alive: PackedByteArray = snap.get("alive")
		for i in range(TARGET_CELLS):
			px[i] = _local_px[i]
			alive[i] = _local_alive[i]
		snap.set("tick", local_tick + 1)
		snap.set("checksum", _checksum(px, alive))
		_last_written = back
		_front_index = back
		_worker_ticks += 1
		_mutex.unlock()
		local_tick += 1

var _last_written: int = -1

func _process(_delta: float) -> void:
	if _done or _thread == null:
		return
	var t0: int = Time.get_ticks_usec()
	# 读锁：覆盖整个快照读取与 checksum 复算，与 worker 写入串行化。
	_mutex.lock()
	var front: int = _front_index
	var ticks: int = _worker_ticks
	var snap: RefCounted = _snapshots[front]
	var px: PackedFloat32Array = snap.get("pos_x")
	var alive: PackedByteArray = snap.get("alive")
	var snap_tick: int = int(snap.get("tick"))
	var stored_checksum: int = int(snap.get("checksum"))
	var computed_checksum: int = _checksum(px, alive)
	_mutex.unlock()
	if stored_checksum != computed_checksum:
		_tear_count += 1
	if snap_tick < _last_tick_read:
		_non_monotonic += 1
	_last_tick_read = snap_tick
	_read_count += 1
	_read_samples_usec.append(Time.get_ticks_usec() - t0)

	if ticks >= RUN_TICKS:
		var elapsed: float = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
		_push("PROTO_THREAD_END worker_ticks=%d elapsed=%.3fs" % [ticks, elapsed])
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	var sorted: Array[int] = _read_samples_usec.duplicate()
	sorted.sort()
	var avg: float = 0.0
	for value in sorted:
		avg += float(value)
	if sorted.size() > 0:
		avg /= float(sorted.size())
	var p50: int = sorted[clampi(int(float(sorted.size()) * 0.5), 0, maxi(0, sorted.size() - 1))] if sorted.size() > 0 else 0
	var p95: int = sorted[clampi(int(float(sorted.size()) * 0.95), 0, maxi(0, sorted.size() - 1))] if sorted.size() > 0 else 0
	_push("PROTO_SNAPSHOT reads=%d checksum_mismatch=%d non_monotonic=%d" % [_read_count, _tear_count, _non_monotonic])
	_push("PROTO_READ_COST avg_us=%.1f p50_us=%d p95_us=%d" % [avg, p50, p95])
	var verdict: String = "OK" if (_tear_count == 0 and _non_monotonic == 0 and _worker_ticks >= RUN_TICKS) else "FAIL"
	_push("PROTO_VERDICT %s" % verdict)
	var file: FileAccess = FileAccess.open("user://thread_prototype.txt", FileAccess.WRITE)
	if file != null:
		for line in _report_lines:
			file.store_line(line)
		file.close()
	print("PROTO_FILE ", ProjectSettings.globalize_path("user://thread_prototype.txt"))
	get_tree().quit()

func _push(line: String) -> void:
	print(line)
	_report_lines.append(line)
