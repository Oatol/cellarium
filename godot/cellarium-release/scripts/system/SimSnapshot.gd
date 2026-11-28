extends RefCounted
## 阶段 B 快照单元。
##
## 旧 SimWorker 只同步 4 个字段（pos/alive/type），保留这些字段以兼容既有探针。
## 生产 B3 需要让现有渲染器零改动继续工作，因此增加 `arrays` 字典承载完整 CellArray SoA：
##   - worker 本地计算完成后，在短临界区内把每个 PackedArray 整块写入快照槽；
##   - 主线程每帧在短临界区内把快照写回主场景 CellArray；
##   - 主线程不读 worker 正在写的同一数组，避免 COW 竞争撕裂。

var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()
var cell_type: PackedByteArray = PackedByteArray()
var cell_count: int = 0
var org_count: int = 0
var tick: int = 0
var checksum: int = 0

## 动态 SoA 快照：key = CellArray 字段名，value = 对应类型的 PackedArray。
var arrays: Dictionary = {}
## 每个数组的实际长度；stride 数组（neural_weights/expression_weights 等）不等于 cell_count。
var array_counts: Dictionary = {}
var array_names: Array[String] = []
var state_hash: int = 0


func configure(capacity: int, names: Array[String] = [], template_cells: RefCounted = null) -> void:
	pos_x.resize(capacity)
	pos_y.resize(capacity)
	alive.resize(capacity)
	cell_type.resize(capacity)
	arrays.clear()
	array_counts.clear()
	array_names = names.duplicate()
	for name in array_names:
		var source: Variant = null
		if template_cells != null:
			source = template_cells.get(name)
		var source_size: int = _array_size(source)
		if source_size <= 0:
			source_size = capacity
		arrays[name] = _new_array_like(source, source_size)
		array_counts[name] = source_size


func set_array(name: String, values: Variant, value_count: int = -1) -> void:
	arrays[name] = values
	array_counts[name] = value_count if value_count >= 0 else _array_size(values)


func get_array(name: String) -> Variant:
	return arrays.get(name, null)


func ensure_array(name: String, source: Variant, capacity: int) -> void:
	if not arrays.has(name):
		var source_size: int = _array_size(source)
		if source_size <= 0:
			source_size = capacity
		arrays[name] = _new_array_like(source, source_size)
		array_counts[name] = source_size


func get_array_count(name: String) -> int:
	return int(array_counts.get(name, 0))


func _array_size(source: Variant) -> int:
	if source is PackedFloat32Array:
		return (source as PackedFloat32Array).size()
	if source is PackedInt32Array:
		return (source as PackedInt32Array).size()
	if source is PackedInt64Array:
		return (source as PackedInt64Array).size()
	if source is PackedByteArray:
		return (source as PackedByteArray).size()
	return 0


func _new_array_like(source: Variant, capacity: int) -> Variant:
	var result: Variant = null
	if source is PackedFloat32Array:
		result = PackedFloat32Array()
	elif source is PackedInt32Array:
		result = PackedInt32Array()
	elif source is PackedInt64Array:
		result = PackedInt64Array()
	elif source is PackedByteArray:
		result = PackedByteArray()
	else:
		result = PackedFloat32Array()
	# Variant 无法直接调用 resize，分派到具体类型。
	if result is PackedFloat32Array:
		(result as PackedFloat32Array).resize(capacity)
	elif result is PackedInt32Array:
		(result as PackedInt32Array).resize(capacity)
	elif result is PackedInt64Array:
		(result as PackedInt64Array).resize(capacity)
	elif result is PackedByteArray:
		(result as PackedByteArray).resize(capacity)
	return result
