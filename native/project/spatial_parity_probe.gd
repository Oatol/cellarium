extends SceneTree
## P2 determinism gate: bit-exact parity for the three spatial hotspots.
const PHYSICS: Script = preload("res://cell_physics.gd")
const BEHAVIOR: Script = preload("res://cell_behavior.gd")
const STUB: Script = preload("res://cells_stub.gd")

const CELL_SIZE: float = 64.0

func _initialize() -> void:
	var failures: int = 0
	if not ClassDB.class_exists("CellSpatial"):
		print("SPATIAL_PARITY: FAIL CellSpatial not registered")
		quit(1)
		return
	var cpp = ClassDB.instantiate("CellSpatial")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 987654321
	const N: int = 1500

	# ---- build positions with lots of local overlap ----
	var pos_x: PackedFloat32Array = PackedFloat32Array()
	var pos_y: PackedFloat32Array = PackedFloat32Array()
	var alive: PackedByteArray = PackedByteArray()
	var radius_scales: PackedFloat32Array = PackedFloat32Array()
	var stiffnesses: PackedFloat32Array = PackedFloat32Array()
	pos_x.resize(N); pos_y.resize(N); alive.resize(N); radius_scales.resize(N); stiffnesses.resize(N)
	for i in range(N):
		# cluster into 30 groups so each grid cell has many neighbors
		var g: int = i % 30
		pos_x[i] = float(g) * 20.0 + rng.randf_range(-8.0, 8.0)
		pos_y[i] = float(g / 30) * 20.0 + rng.randf_range(-8.0, 8.0)
		alive[i] = 1
		radius_scales[i] = 1.0
		stiffnesses[i] = 1.0

	# ---- TEST 1: build_neighbor_csr ----
	var gd_buckets: Dictionary = PHYSICS.build_spatial_hash_flat(_make_cells(pos_x, pos_y, alive))
	var gd_offsets: PackedInt32Array = PackedInt32Array()
	var gd_values: PackedInt32Array = PackedInt32Array()
	gd_offsets.resize(N + 1)
	for i in range(N):
		gd_offsets[i] = gd_values.size()
		if alive[i] == 0:
			continue
		var found: PackedInt32Array = PHYSICS.query_neighbors_flat(_make_cells(pos_x, pos_y, alive), i, gd_buckets)
		for n in found:
			gd_values.append(n)
	gd_offsets[N] = gd_values.size()
	var csr: Dictionary = cpp.call("build_neighbor_csr", pos_x, pos_y, alive, CELL_SIZE)
	var cpp_offsets: PackedInt32Array = csr["offsets"]
	var cpp_values: PackedInt32Array = csr["values"]
	var t1_fail: int = 0
	if gd_offsets.size() != cpp_offsets.size() or gd_values.size() != cpp_values.size():
		t1_fail = 1
	else:
		for i in range(gd_offsets.size()):
			if gd_offsets[i] != cpp_offsets[i]:
				t1_fail += 1
		for i in range(gd_values.size()):
			if gd_values[i] != cpp_values[i]:
				t1_fail += 1
	print("SPATIAL_PARITY: test1_neighbor_csr gd_vals=%d cpp_vals=%d failures=%d" % [gd_values.size(), cpp_values.size(), t1_fail])
	failures += t1_fail

	# ---- TEST 2: collect_inputs_batch ----
	var energies: PackedFloat32Array = PackedFloat32Array()
	var types: PackedByteArray = PackedByteArray()
	var fields_flat: PackedFloat32Array = PackedFloat32Array()
	var sample_indices: PackedInt32Array = PackedInt32Array()
	energies.resize(N); types.resize(N); fields_flat.resize(N * 5); sample_indices.resize(N)
	for i in range(N):
		energies[i] = rng.randf_range(0.0, 1.0)
		types[i] = i % 3
		sample_indices[i] = i
		for c in range(5):
			fields_flat[i * 5 + c] = rng.randf_range(-1.5, 1.5)
	var env: Dictionary = {
		"fields_flat": fields_flat, "field_sample_indices": sample_indices,
		"neighbor_offsets": gd_offsets, "neighbor_values": gd_values,
		"energy_max": 1.0, "fields_by_cell": [], "neighbors": [],
	}
	var gd_inputs: PackedFloat32Array = PackedFloat32Array()
	gd_inputs.resize(N * 8)
	var gcells: RefCounted = _make_cells_e(energies, alive, types)
	var tmp8: PackedFloat32Array = PackedFloat32Array()
	tmp8.resize(8)
	for i in range(N):
		BEHAVIOR.collect_inputs_into(gcells, i, env, tmp8)
		for c in range(8):
			gd_inputs[i * 8 + c] = tmp8[c]
	var cpp_inputs: PackedFloat32Array = cpp.call("collect_inputs_batch", energies, alive, types, fields_flat, sample_indices, gd_offsets, gd_values, 1.0)
	var t2_fail: int = 0
	if gd_inputs.size() != cpp_inputs.size():
		t2_fail = 1
	else:
		for i in range(gd_inputs.size()):
			if gd_inputs[i] != cpp_inputs[i]:
				t2_fail += 1
				if t2_fail <= 3:
					print("  INPUT MISMATCH idx=%d gd=%.9f cpp=%.9f" % [i, gd_inputs[i], cpp_inputs[i]])
	print("SPATIAL_PARITY: test2_collect_inputs n=%d failures=%d" % [gd_inputs.size(), t2_fail])
	failures += t2_fail

	# ---- TEST 3: resolve_collisions ----
	var cells_a: RefCounted = _make_full(pos_x, pos_y, alive, radius_scales, stiffnesses)
	var gd_resolved: int = PHYSICS.resolve_collisions(cells_a, 8.0, radius_scales, stiffnesses)
	var gd_px: PackedFloat32Array = cells_a.get("cell_pos_x")
	var gd_py: PackedFloat32Array = cells_a.get("cell_pos_y")
	var coll: Dictionary = cpp.call("resolve_collisions", pos_x, pos_y, alive, radius_scales, stiffnesses, 8.0, CELL_SIZE, 6)
	var cpp_px: PackedFloat32Array = coll["pos_x"]
	var cpp_py: PackedFloat32Array = coll["pos_y"]
	var t3_fail: int = 0
	for i in range(N):
		if gd_px[i] != cpp_px[i] or gd_py[i] != cpp_py[i]:
			t3_fail += 1
			if t3_fail <= 5:
				print("  COLL MISMATCH i=%d gd=(%.6f,%.6f) cpp=(%.6f,%.6f)" % [i, gd_px[i], gd_py[i], cpp_px[i], cpp_py[i]])
	print("SPATIAL_PARITY: test3_collisions gd_resolved=%d cpp_resolved=%d pos_failures=%d" % [gd_resolved, int(coll["resolved"]), t3_fail])
	failures += t3_fail

	print("SPATIAL_PARITY: %s (total_failures=%d)" % ["OK" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)

func _make_cells(px: PackedFloat32Array, py: PackedFloat32Array, al: PackedByteArray) -> RefCounted:
	var c: RefCounted = STUB.new()
	c.cell_pos_x = px.duplicate(); c.cell_pos_y = py.duplicate(); c.cell_alive = al.duplicate()
	return c

func _make_cells_e(en: PackedFloat32Array, al: PackedByteArray, ty: PackedByteArray) -> RefCounted:
	var c: RefCounted = STUB.new()
	c.cell_energy = en; c.cell_alive = al; c.cell_type = ty
	return c

func _make_full(px: PackedFloat32Array, py: PackedFloat32Array, al: PackedByteArray, rs: PackedFloat32Array, st: PackedFloat32Array) -> RefCounted:
	var c: RefCounted = STUB.new()
	c.cell_pos_x = px.duplicate(); c.cell_pos_y = py.duplicate(); c.cell_alive = al.duplicate()
	return c

func _slice8(arr: PackedFloat32Array, i: int) -> PackedFloat32Array:
	# Not used for real; collect_inputs_into needs a writable 8-len view.
	# We instead call collect_inputs into a temp then copy - see _initialize inline.
	return PackedFloat32Array()
