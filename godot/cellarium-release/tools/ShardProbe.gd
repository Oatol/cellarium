extends SceneTree
## 阶段 C 轻量原型：实测 evaluate_batch 分片 1/2/4/8 的加速比与逐位一致性。
## 只读探针，不改生产代码、不碰 state hash。墙钟一律用 OS 单调钟。

const CELLS: int = 1024
const REPEAT: int = 200

var _neural: RefCounted = null
var _inputs: PackedFloat32Array = PackedFloat32Array()
var _weights: PackedFloat32Array = PackedFloat32Array()
var _alive: PackedByteArray = PackedByteArray()
var _golden: PackedFloat32Array = PackedFloat32Array()

# WorkerThreadPool 任务函数需要的分片参数
var _shard_count: int = 1
var _results: Array[PackedFloat32Array] = []


func _initialize() -> void:
	if not ClassDB.class_exists("CellNeural"):
		print("SHARD: FAIL CellNeural not registered")
		quit(1)
		return
	var neural_script: Script = load("res://scripts/simulation/CellNeural.gd") as Script if ResourceLoader.exists("res://scripts/simulation/CellNeural.gd") else null
	# native 类通过 ClassDB 实例化（GDExtension）
	_neural = ClassDB.instantiate("CellNeural") as RefCounted
	if _neural == null:
		print("SHARD: FAIL instantiate CellNeural")
		quit(1)
		return
	_build_inputs()
	# golden = 单线程全量
	var t0: int = Time.get_ticks_usec()
	for r in range(REPEAT):
		_golden = _neural.call("evaluate_batch", _inputs, _weights, _alive, 0, CELLS) as PackedFloat32Array
	var t1: int = Time.get_ticks_usec()
	print("SHARD_BASE shards=1 us_per_call=%.1f" % [float(t1 - t0) / float(REPEAT)])

	for shards in [2, 4, 8]:
		var t2: int = Time.get_ticks_usec()
		var mismatch: int = 0
		for r in range(REPEAT):
			var ok: bool = _run_sharded(shards)
			if not ok and r == 0:
				mismatch = 1
		var t3: int = Time.get_ticks_usec()
		var speedup: float = float(t1 - t0) / float(maxi(1, t3 - t2))
		print("SHARD_RUN shards=%d us_per_call=%.1f speedup=%.2fx bitwise_match=%s" % [
			shards, float(t3 - t2) / float(REPEAT), speedup, str(mismatch == 0),
		])
	quit(0)


func _build_inputs() -> void:
	_inputs.resize(CELLS * 8)   # INPUT_COUNT=8
	_weights.resize(CELLS * 56) # WEIGHT_COUNT=8*4+4*6=56
	_alive.resize(CELLS)
	for i in range(_inputs.size()):
		_inputs[i] = fmod(float(i) * 0.001, 1.0)
	for i in range(_weights.size()):
		_weights[i] = fmod(float(i) * 0.0007 - 0.35, 1.0)
	for i in range(CELLS):
		_alive[i] = 1


func _shard_task(shard_index: int) -> void:
	var first: int = int(float(CELLS * shard_index) / float(_shard_count))
	var last: int = int(float(CELLS * (shard_index + 1)) / float(_shard_count))
	var part: PackedFloat32Array = _neural.call("evaluate_batch", _inputs, _weights, _alive, first, last) as PackedFloat32Array
	_results[shard_index] = part


func _run_sharded(shards: int) -> bool:
	_shard_count = shards
	_results.clear()
	for i in range(shards):
		_results.append(PackedFloat32Array())
	var task_ids: PackedInt32Array = PackedInt32Array()
	for i in range(shards):
		task_ids.append(WorkerThreadPool.add_task(Callable(self, "_shard_task").bind(i), false, "shard %d" % i))
	for tid in task_ids:
		WorkerThreadPool.wait_for_task_completion(tid)
	# 合并：按 cell 索引升序，只取各分片的非零行（逐位比对）
	var merged: PackedFloat32Array = PackedFloat32Array()
	merged.resize(CELLS * 6) # OUTPUT_COUNT=6
	for cell in range(CELLS):
		var shard: int = mini(int(float(cell * shards) / float(CELLS)), shards - 1)
		var part: PackedFloat32Array = _results[shard]
		for c in range(6):
			merged[cell * 6 + c] = part[cell * 6 + c]
	if merged.size() != _golden.size():
		return false
	for i in range(merged.size()):
		if merged[i] != _golden[i]:
			return false
	return true
