extends RefCounted
## Deterministic per-cell 8 -> 4 -> 6 behavior network and movement intent.

const INPUT_COUNT: int = 8
const HIDDEN_COUNT: int = 4
const OUTPUT_COUNT: int = 6
const WEIGHT_COUNT: int = INPUT_COUNT * HIDDEN_COUNT + HIDDEN_COUNT * OUTPUT_COUNT

static func initialize_weights(cells: RefCounted, cell_index: int, genome_hash: int) -> bool:
	if cell_index < 0 or cell_index >= int(cells.call("size")):
		return false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _derive_seed(genome_hash, cell_index)
	var weights: PackedFloat32Array = cells.get("neural_weights")
	var start: int = cell_index * WEIGHT_COUNT
	for weight_index in range(WEIGHT_COUNT):
		weights[start + weight_index] = rng.randf_range(-0.25, 0.25)
	cells.set("neural_weights", weights)
	return true

static func evaluate(
	inputs: PackedFloat32Array,
	weights: PackedFloat32Array,
	offset: int = 0
) -> PackedFloat32Array:
	var outputs: PackedFloat32Array = PackedFloat32Array()
	outputs.resize(OUTPUT_COUNT)
	var hidden: PackedFloat32Array = PackedFloat32Array()
	hidden.resize(HIDDEN_COUNT)
	evaluate_into(inputs, weights, offset, hidden, outputs, 0)
	return outputs

## 零分配热路径版本：输入/隐层/输出全部复用调用方数组，输出写到 output_offset。
static func evaluate_into(
	inputs: PackedFloat32Array,
	weights: PackedFloat32Array,
	offset: int,
	hidden: PackedFloat32Array,
	outputs: PackedFloat32Array,
	output_offset: int
) -> void:
	if outputs.size() < output_offset + OUTPUT_COUNT:
		return
	for output_index in range(OUTPUT_COUNT):
		outputs[output_offset + output_index] = 0.0
	if inputs.size() != INPUT_COUNT or offset < 0 or offset + WEIGHT_COUNT > weights.size():
		return
	if hidden.size() < HIDDEN_COUNT:
		return
	var cursor: int = offset
	for hidden_index in range(HIDDEN_COUNT):
		var total: float = 0.0
		for input_index in range(INPUT_COUNT):
			total += inputs[input_index] * weights[cursor]
			cursor += 1
		hidden[hidden_index] = tanh(total)
	for output_index in range(OUTPUT_COUNT):
		var total: float = 0.0
		for hidden_index in range(HIDDEN_COUNT):
			total += hidden[hidden_index] * weights[cursor]
			cursor += 1
		outputs[output_offset + output_index] = tanh(total)

static func collect_inputs(cells: RefCounted, cell_index: int, environment: Dictionary) -> PackedFloat32Array:
	var inputs: PackedFloat32Array = PackedFloat32Array()
	inputs.resize(INPUT_COUNT)
	collect_inputs_into(cells, cell_index, environment, inputs)
	return inputs

## 零分配热路径版本：inputs 由调用方复用；neighbors 支持 Array 或旧 Dictionary。
static func collect_inputs_into(
	cells: RefCounted,
	cell_index: int,
	environment: Dictionary,
	inputs: PackedFloat32Array
) -> void:
	if inputs.size() < INPUT_COUNT:
		return
	for i in range(INPUT_COUNT):
		inputs[i] = 0.0
	if cells == null or cell_index < 0 or cell_index >= int(cells.call("size")):
		return
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var alive: PackedByteArray = cells.get("cell_alive")
	var types: PackedByteArray = cells.get("cell_type")
	var fields_by_cell: Array = environment.get("fields_by_cell", [])
	var field_values: Variant = fields_by_cell[cell_index] if cell_index < fields_by_cell.size() else environment.get("fields", [])
	for channel in range(5):
		if channel < field_values.size():
			inputs[channel] = clampf(float(field_values[channel]), -1.0, 1.0)
	var same_count: int = 0
	var other_count: int = 0
	var neighbors_value: Variant = environment.get("neighbors", [])
	var neighbors: Array = []
	if neighbors_value is Dictionary:
		neighbors = neighbors_value.get(cell_index, [])
	elif neighbors_value is Array and cell_index < neighbors_value.size():
		neighbors = neighbors_value[cell_index]
	for neighbor_value in neighbors:
		var neighbor: int = int(neighbor_value)
		if neighbor < 0 or neighbor >= alive.size() or neighbor == cell_index or alive[neighbor] == 0:
			continue
		if types[neighbor] == types[cell_index]:
			same_count += 1
		else:
			other_count += 1
	inputs[5] = minf(float(same_count) / 8.0, 1.0)
	inputs[6] = minf(float(other_count) / 8.0, 1.0)
	var energy_max: float = maxf(float(environment.get("energy_max", 1.0)), 0.000001)
	inputs[7] = clampf(energies[cell_index] / energy_max, 0.0, 1.0)

static func compute_outputs(cells: RefCounted, environment: Dictionary) -> Array[PackedFloat32Array]:
	var outputs: Array[PackedFloat32Array] = []
	var count: int = int(cells.call("size"))
	outputs.resize(count)
	var alive: PackedByteArray = cells.get("cell_alive")
	var weights: PackedFloat32Array = cells.get("neural_weights")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			outputs[cell_index] = PackedFloat32Array()
			continue
		var inputs: PackedFloat32Array = collect_inputs(cells, cell_index, environment)
		outputs[cell_index] = evaluate(inputs, weights, cell_index * WEIGHT_COUNT)
	return outputs

## 零分配批量推理：输出为 count*OUTPUT_COUNT 的扁平数组，顺序与 cell_index 对齐。
static func compute_outputs_flat(
	cells: RefCounted,
	environment: Dictionary,
	outputs: PackedFloat32Array
) -> bool:
	if cells == null or outputs.size() < int(cells.call("size")) * OUTPUT_COUNT:
		return false
	var inputs: PackedFloat32Array = PackedFloat32Array()
	inputs.resize(INPUT_COUNT)
	var hidden: PackedFloat32Array = PackedFloat32Array()
	hidden.resize(HIDDEN_COUNT)
	var alive: PackedByteArray = cells.get("cell_alive")
	var weights: PackedFloat32Array = cells.get("neural_weights")
	for cell_index in range(int(cells.call("size"))):
		var output_offset: int = cell_index * OUTPUT_COUNT
		if alive[cell_index] == 0:
			for output_index in range(OUTPUT_COUNT):
				outputs[output_offset + output_index] = 0.0
			continue
		collect_inputs_into(cells, cell_index, environment, inputs)
		evaluate_into(inputs, weights, cell_index * WEIGHT_COUNT, hidden, outputs, output_offset)
	return true

## 与 apply_outputs 等价，但输入是扁平输出数组，避免每个细胞一个临时 PackedFloat32Array。
static func apply_outputs_flat(
	cells: RefCounted,
	outputs: PackedFloat32Array,
	dt: float,
	max_speed: float = 12.0
) -> bool:
	if cells == null or dt < 0.0 or max_speed < 0.0:
		return false
	var count: int = int(cells.call("size"))
	if outputs.size() < count * OUTPUT_COUNT:
		return false
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var start: int = cell_index * OUTPUT_COUNT
		for output_index in range(OUTPUT_COUNT):
			intents[start + output_index] = outputs[start + output_index]
		var angle: float = outputs[start + 1] * PI
		var speed: float = outputs[start] * max_speed * dt
		var movement: Vector2 = Vector2.RIGHT.rotated(angle) * speed
		prev_x[cell_index] = pos_x[cell_index]
		prev_y[cell_index] = pos_y[cell_index]
		pos_x[cell_index] += movement.x
		pos_y[cell_index] += movement.y
	cells.set("behavior_intents", intents)
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	return true

static func apply_outputs(cells: RefCounted, outputs: Array[PackedFloat32Array], dt: float, max_speed: float = 12.0) -> bool:
	if dt < 0.0 or outputs.size() != int(cells.call("size")) or max_speed < 0.0:
		return false
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0 or outputs[cell_index].size() != OUTPUT_COUNT:
			continue
		var output: PackedFloat32Array = outputs[cell_index]
		for output_index in range(OUTPUT_COUNT):
			intents[cell_index * OUTPUT_COUNT + output_index] = output[output_index]
		var angle: float = output[1] * PI
		var speed: float = output[0] * max_speed * dt
		var movement: Vector2 = Vector2.RIGHT.rotated(angle) * speed
		prev_x[cell_index] = pos_x[cell_index]
		prev_y[cell_index] = pos_y[cell_index]
		pos_x[cell_index] += movement.x
		pos_y[cell_index] += movement.y
	cells.set("behavior_intents", intents)
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	return true

## LOD 中间 tick：复用已存的 behavior_intents 推进运动，不重算神经（§2.6）。
## 输出与 apply_outputs 一致，只是跳过神经推理，保证降频档位下运动连续。
static func apply_cached_intents(cells: RefCounted, dt: float, max_speed: float = 12.0) -> bool:
	if dt < 0.0:
		return false
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	var count: int = alive.size()
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var start: int = cell_index * OUTPUT_COUNT
		if start + 1 >= intents.size():
			continue
		var angle: float = intents[start + 1] * PI
		var speed: float = intents[start] * max_speed * dt
		var movement: Vector2 = Vector2.RIGHT.rotated(angle) * speed
		prev_x[cell_index] = pos_x[cell_index]
		prev_y[cell_index] = pos_y[cell_index]
		pos_x[cell_index] += movement.x
		pos_y[cell_index] += movement.y
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	return true

static func snapshot_intents(cells: RefCounted) -> PackedFloat32Array:
	return (cells.get("behavior_intents") as PackedFloat32Array).duplicate()

static func get_intents(cells: RefCounted, cell_index: int) -> PackedFloat32Array:
	var intents: PackedFloat32Array = PackedFloat32Array()
	intents.resize(OUTPUT_COUNT)
	if cell_index < 0 or cell_index >= int(cells.call("size")):
		return intents
	var stored: PackedFloat32Array = cells.get("behavior_intents")
	var start: int = cell_index * OUTPUT_COUNT
	for output_index in range(OUTPUT_COUNT):
		intents[output_index] = stored[start + output_index]
	return intents

static func _derive_seed(genome_hash: int, cell_index: int) -> int:
	var value: int = (genome_hash ^ (cell_index * 0x9e3779b9)) & 0x7fffffff
	value = int((value ^ (value >> 16)) * 0x45d9f3b) & 0x7fffffff
	value = int((value ^ (value >> 16)) * 0x45d9f3b) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff
