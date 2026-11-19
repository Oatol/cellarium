extends SceneTree
## P1 breakdown: where does behavior_neural's 84ms actually go?
const BEHAVIOR: Script = preload("res://cell_behavior.gd")
const MANAGER: Script = preload("res://cell_array_stub.gd")
const N: int = 3000
const ITERS: int = 60

func _make_cells() -> RefCounted:
	var cells: RefCounted = MANAGER.new()
	cells.call("setup", N)
	return cells

func _time(label: String, fn: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	for i in range(ITERS):
		fn.call()
	var us: float = float(Time.get_ticks_usec() - t0) / float(ITERS)
	print("SPLIT: %-24s %.1fus" % [label, us])

func _initialize() -> void:
	var cells: RefCounted = _make_cells()
	var weights: PackedFloat32Array = cells.get("neural_weights")
	var alive: PackedByteArray = cells.get("cell_alive")
	var outputs: PackedFloat32Array = PackedFloat32Array()
	outputs.resize(N * 6)

	# Fake environment with flat fields + CSR neighbors (typical shape).
	var fields_flat: PackedFloat32Array = PackedFloat32Array()
	fields_flat.resize(N * 5)
	var sample_indices: PackedInt32Array = PackedInt32Array()
	sample_indices.resize(N)
	var neighbor_offsets: PackedInt32Array = PackedInt32Array()
	neighbor_offsets.resize(N + 1)
	var neighbor_values: PackedInt32Array = PackedInt32Array()
	for i in range(N):
		sample_indices[i] = i
		neighbor_offsets[i] = i * 4
		neighbor_values.append(maxi(0, i - 1))
		neighbor_values.append(maxi(0, i - 2))
		neighbor_values.append(mini(N - 1, i + 1))
		neighbor_values.append(mini(N - 1, i + 2))
	neighbor_offsets[N] = N * 4
	var environment: Dictionary = {
		"fields_flat": fields_flat, "field_sample_indices": sample_indices,
		"neighbor_offsets": neighbor_offsets, "neighbor_values": neighbor_values,
		"energy_max": 1.0, "fields_by_cell": [], "neighbors": [],
	}

	_time("collect_inputs_only", func() -> void:
		var inputs: PackedFloat32Array = PackedFloat32Array()
		inputs.resize(8)
		for c in range(N):
			BEHAVIOR.collect_inputs_into(cells, c, environment, inputs)
	)
	_time("evaluate_only_gd", func() -> void:
		var inputs: PackedFloat32Array = PackedFloat32Array()
		inputs.resize(8)
		var hidden: PackedFloat32Array = PackedFloat32Array()
		hidden.resize(4)
		var out: PackedFloat32Array = PackedFloat32Array()
		out.resize(6)
		for c in range(N):
			BEHAVIOR.evaluate_into(inputs, weights, c * 56, hidden, out, 0)
	)
	_time("compute_outputs_flat", func() -> void:
		BEHAVIOR.compute_outputs_flat(cells, environment, outputs)
	)
	quit(0)
