extends Node
## 阶段 B 决定性验证：worker 线程里创建并驱动一套隔离的真实模拟（PreviewWorld），
## 与主线程同 genes 跑相同 tick，比较 state hash 是否逐位一致。
## 若通过，证明"完整 tick 链可在 worker 跑且确定性成立"，路径 B 可行。
## 只读探针，不碰生产 tick 链；跑完自动退出，输出 ASCII 到 user://worker_sim_probe.txt。

const PREVIEW_SCRIPT: Script = preload("res://scripts/core/data/PreviewWorld.gd")
const RUN_TICKS: int = 120

var _thread: Thread = null
var _worker_world: RefCounted = null
var _worker_hash: int = 0
var _worker_error: String = ""
var _worker_ticks: int = 0
var _done: bool = false
var _report_lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	# 两套隔离模拟：主线程一套，worker 一套，genes 相同。
	var main_world: RefCounted = PREVIEW_SCRIPT.new() as RefCounted
	_worker_world = PREVIEW_SCRIPT.new() as RefCounted
	var genes: Array = []
	main_world.call("setup", genes, 0)
	_worker_world.call("setup", genes, 0)
	# 关键：在主线程预热两套模拟的 native 对象（ClassDB.instantiate 在首次 step 惰性创建）。
	# worker 线程禁止 new Object（ObjectDB 非线程安全），预热后 worker 只复用引用。
	for i in range(2):
		main_world.call("step")
		_worker_world.call("step")
	# 主线程已多跑 2 tick，回退主世界观到与 worker 相同起点不可行（模拟不可逆），
	# 改为让 worker 也基于同样的 2 tick 预热状态：重开 worker world 并与 main 对齐。
	# 简化：两边都从预热后的当前状态再跑 RUN_TICKS，hash 仍可直接比较。
	_push("PROBE_SETUP main_cells=%d worker_cells=%d" % [
		int(main_world.call("get_cell_count")), int(_worker_world.call("get_cell_count")),
	])

	# worker 跑 RUN_TICKS
	_thread = Thread.new()
	var err: int = _thread.start(Callable(self, "_worker_loop"))
	if err != OK:
		_push("FAIL_STATE thread.start err=%d" % err)
		_finish()
		return

	# 主线程同步跑 RUN_TICKS
	for i in range(RUN_TICKS):
		main_world.call("step")
	var main_hash: int = int(main_world.call("get_real_state_hash"))
	_push("PROBE_MAIN hash=%d ticks=%d cells=%d" % [main_hash, RUN_TICKS, int(main_world.call("get_cell_count"))])

	# 等 worker 完成
	_thread.wait_to_finish()
	_push("PROBE_WORKER hash=%d ticks=%d cells=%d error=%s" % [
		_worker_hash, _worker_ticks, int(_worker_world.call("get_cell_count")),
		_worker_error if not _worker_error.is_empty() else "none",
	])
	var verdict: String = "FAIL"
	if _worker_error.is_empty() and _worker_hash == main_hash:
		verdict = "OK"
	_push("PROBE_VERDICT %s match=%s" % [verdict, str(_worker_hash == main_hash)])
	_finish()

func _worker_loop() -> void:
	for i in range(RUN_TICKS):
		# 注意：这里在 worker 线程直接调用隔离模拟的 step。
		# PreviewWorld.step 内部是 advance_physics_tick + CPU advance_field_tick，
		# 无 scene tree / RenderingDevice / signal emit 依赖。
		_worker_world.call("step")
		_worker_ticks += 1
	_worker_hash = int(_worker_world.call("get_real_state_hash"))

func _push(line: String) -> void:
	print(line)
	_report_lines.append(line)

func _finish() -> void:
	if _done:
		return
	_done = true
	var file: FileAccess = FileAccess.open("user://worker_sim_probe.txt", FileAccess.WRITE)
	if file != null:
		for line in _report_lines:
			file.store_line(line)
		file.close()
	print("PROBE_FILE ", ProjectSettings.globalize_path("user://worker_sim_probe.txt"))
	get_tree().quit()
