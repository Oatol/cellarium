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

static func evaluate(inputs: PackedFloat32Array, weights: PackedFloat32Array, offset: int = 0) -> PackedFloat32Array:
	var outputs: PackedFloat32Array = PackedFloat32Array()
	outputs.resize(OUTPUT_COUNT)
	if inputs.size() != INPUT_COUNT or offset < 0 or offset + WEIGHT_COUNT > weights.size():
		return outputs
	var hidden: PackedFloat32Array = PackedFloat32Array()
	hidden.resize(HIDDEN_COUNT)
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
		outputs[output_index] = tanh(total)
	return outputs

static func collect_inputs(cells: RefCounted, cell_index: int, environment: Dictionary) -> PackedFloat32Array:
	var inputs: PackedFloat32Array = PackedFloat32Array()
	inputs.resize(INPUT_COUNT)
	if cell_index < 0 or cell_index >= int(cells.call("size")):
		return inputs
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var alive: PackedByteArray = cells.get("cell_alive")
	var types: PackedByteArray = cells.get("cell_type")
	for channel in range(5):
		var field_values: Array = environment.get("fields", [])
		if channel < field_values.size():
			inputs[channel] = clampf(float(field_values[channel]), -1.0, 1.0)
	var same_count: int = 0
	var other_count: int = 0
	var neighbors: Array = environment.get("neighbors", {}).get(cell_index, [])
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
	return inputs

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
