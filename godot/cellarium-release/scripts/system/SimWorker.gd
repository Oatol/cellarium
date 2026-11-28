extends RefCounted
## 阶段 B：独立模拟线程基础设施（v0.47）。
##
## 设计约束（来自 tools/ThreadPrototype.gd + tools/WorkerSimProbe.gd 的实测）：
##   1. 权威模拟在 worker 线程跑（隔离的 OrganismManager + CPU 场，无 scene tree / RenderingDevice）。
##   2. native 对象（CellSpatial/CellNeural/CellMetabolism）必须在主线程预热后再交给 worker，
##      因为 GDScript 的 ObjectDB 非线程安全，worker 内禁止 new Object。
##   3. 快照用三缓冲 RefCounted；worker 在自己的本地 PackedArray 上算完，短临界区内整块拷贝，
##      锁内不做计算/checksum——双缓冲或"Mutex 只护索引"会概率性 COW 撕裂（实测 17/106、1/86）。
##   4. 命令队列由主线程写入、worker 消费；命令只在 tick 边界生效。
##
## 本类不触碰生产 tick 链；是否启用由上层开关 threaded_simulation_enabled 决定（默认 false）。

const SNAPSHOT_SCRIPT: Script = preload("res://scripts/system/SimSnapshot.gd")

var _world: RefCounted = null
var _thread: Thread = null
var _mutex: Mutex = null
var _slots: Array[RefCounted] = []
var _front_index: int = 0
var _last_written: int = -1

var _running: bool = false
var _stop: bool = false
var _worker_ticks: int = 0
var _pending_commands: Array[Dictionary] = []

var _cell_capacity: int = 0
var _local_px: PackedFloat32Array = PackedFloat32Array()
var _local_py: PackedFloat32Array = PackedFloat32Array()
var _local_alive: PackedByteArray = PackedByteArray()
var _local_type: PackedByteArray = PackedByteArray()

## 只读诊断
var diag_worker_ticks: int = 0
var diag_snapshot_writes: int = 0
var diag_last_error: String = ""


func configure(world: RefCounted, cell_capacity: int) -> void:
	_world = world
	_cell_capacity = cell_capacity
	_mutex = Mutex.new()
	_local_px.resize(cell_capacity)
	_local_py.resize(cell_capacity)
	_local_alive.resize(cell_capacity)
	_local_type.resize(cell_capacity)
	_slots.clear()
	for i in range(3):
		var snap: RefCounted = SNAPSHOT_SCRIPT.new() as RefCounted
		snap.call("configure", cell_capacity)
		_slots.append(snap)


func is_configured() -> bool:
	return _world != null and _mutex != null and _slots.size() == 3


func start() -> bool:
	if not is_configured() or _running:
		return false
	_stop = false
	_worker_ticks = 0
	diag_last_error = ""
	_thread = Thread.new()
	var err: int = _thread.start(Callable(self, "_worker_loop"))
	if err != OK:
		diag_last_error = "thread.start err=%d" % err
		_thread = null
		return false
	_running = true
	return true


func stop() -> void:
	if not _running:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()


func wait() -> void:
	if _thread == null:
		return
	if _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_running = false
	diag_worker_ticks = _worker_ticks


func submit_command(command: Dictionary) -> void:
	## 主线程调用；命令在下一个 tick 边界被 worker 消费。
	_mutex.lock()
	_pending_commands.append(command.duplicate(true))
	_mutex.unlock()


func get_worker_ticks() -> int:
	_mutex.lock()
	var value: int = _worker_ticks
	_mutex.unlock()
	return value


## 主线程读取当前快照：返回引用，调用方只读，不得写回。
func read_snapshot() -> RefCounted:
	_mutex.lock()
	var front: int = _front_index
	var snap: RefCounted = _slots[front]
	_mutex.unlock()
	return snap


func _worker_loop() -> void:
	while true:
		_mutex.lock()
		var stop: bool = _stop
		_mutex.unlock()
		if stop:
			break
		# 1) 消费本 tick 命令（只在 tick 边界）
		_mutex.lock()
		var commands: Array[Dictionary] = _pending_commands.duplicate(true)
		_pending_commands.clear()
		_mutex.unlock()
		for command in commands:
			_apply_command_safe(command)
		# 2) 跑一个完整真实 tick（世界内部是 CPU 场，无 GPU 依赖）
		_world.call("step")
		_worker_ticks += 1
		# 3) 在 worker 本地缓冲读取 cells SoA（不触碰主线程读的槽）
		var cells: RefCounted = _world.call("_cells") as RefCounted
		if cells == null:
			continue
		var n: int = mini(int(cells.call("size")), _cell_capacity)
		var src_px: PackedFloat32Array = cells.get("cell_pos_x")
		var src_py: PackedFloat32Array = cells.get("cell_pos_y")
		var src_alive: PackedByteArray = cells.get("cell_alive")
		var src_type: PackedByteArray = cells.get("cell_type")
		for i in range(n):
			_local_px[i] = src_px[i]
			_local_py[i] = src_py[i]
			_local_alive[i] = src_alive[i]
			_local_type[i] = src_type[i]
		# 4) 本地算 checksum（锁外），短临界区只赋值
		var local_checksum: int = 0
		for i in range(n):
			local_checksum = (local_checksum + int(_local_px[i] * 10000.0)) % 1000000007
			local_checksum = (local_checksum << 1) | (_local_alive[i] & 1)
		# 5) 短临界区：整块拷进空闲快照槽，只赋值不计算
		_mutex.lock()
		var front: int = _front_index
		var back: int = (front + 1) % 3
		if back == _last_written:
			back = (front + 2) % 3
		var snap: RefCounted = _slots[back]
		var dst_px: PackedFloat32Array = snap.get("pos_x")
		var dst_py: PackedFloat32Array = snap.get("pos_y")
		var dst_alive: PackedByteArray = snap.get("alive")
		var dst_type: PackedByteArray = snap.get("cell_type")
		for i in range(n):
			dst_px[i] = _local_px[i]
			dst_py[i] = _local_py[i]
			dst_alive[i] = _local_alive[i]
			dst_type[i] = _local_type[i]
		snap.set("cell_count", n)
		snap.set("tick", _worker_ticks)
		snap.set("checksum", local_checksum)
		_last_written = back
		_front_index = back
		diag_snapshot_writes += 1
		_mutex.unlock()


func _apply_command_safe(command: Dictionary) -> void:
	## worker 线程内只调 RefCounted 的 apply_command，不 emit signal、不碰 Node UI。
	if _world == null:
		return
	var mgr: Node = _world.call("_manager") as Node
	if mgr == null or not mgr.has_method("apply_command"):
		diag_last_error = "worker command target missing"
		return
	mgr.call("apply_command", command)
