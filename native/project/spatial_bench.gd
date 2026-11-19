extends SceneTree
## P2 micro-benchmark: three spatial hotspots, GDScript vs C++.
const PHYSICS: Script = preload("res://cell_physics.gd")
const BEHAVIOR: Script = preload("res://cell_behavior.gd")
const STUB: Script = preload("res://cells_stub.gd")
const CELL_SIZE: float = 64.0
const N: int = 3000
const ITERS: int = 30

func _time(label: String, fn: Callable) -> float:
	fn.call()  # warmup
	var t0: int = Time.get_ticks_usec()
	for i in range(ITERS):
		fn.call()
	var us: float = float(Time.get_ticks_usec() - t0) / float(ITERS)
	print("BENCH: %-22s %.1fus" % [label, us])
	return us

func _initialize() -> void:
	var cpp = ClassDB.instantiate("CellSpatial")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 13579
	var pos_x: PackedFloat32Array = PackedFloat32Array()
	var pos_y: PackedFloat32Array = PackedFloat32Array()
	var alive: PackedByteArray = PackedByteArray()
	var radius_scales: PackedFloat32Array = PackedFloat32Array()
	var stiffnesses: PackedFloat32Array = PackedFloat32Array()
	pos_x.resize(N); pos_y.resize(N); alive.resize(N); radius_scales.resize(N); stiffnesses.resize(N)
	for i in range(N):
		var g: int = i % 60
		pos_x[i] = float(g) * 15.0 + rng.randf_range(-7.0, 7.0)
		pos_y[i] = float(g / 60) * 15.0 + rng.randf_range(-7.0, 7.0)
		alive[i] = 1; radius_scales[i] = 1.0; stiffnesses[i] = 1.0
	var cells: RefCounted = STUB.new()
	cells.cell_pos_x = pos_x.duplicate(); cells.cell_pos_y = pos_y.duplicate(); cells.cell_alive = alive.duplicate()
	var gd_buckets: Dictionary = PHYSICS.build_spatial_hash_flat(cells)

	# --- neighbor CSR: GDScript full rebuild (hash + query + CSR) ---
	var gd_csr_us: float = _time("gd_neighbor_csr", func() -> void:
		var b: Dictionary = PHYSICS.build_spatial_hash_flat(cells)
		var off: PackedInt32Array = PackedInt32Array(); off.resize(N + 1)
		var val: PackedInt32Array = PackedInt32Array()
		for i in range(N):
			off[i] = val.size()
			var f: PackedInt32Array = PHYSICS.query_neighbors_flat(cells, i, b)
			for n in f: val.append(n)
		off[N] = val.size()
	)
	var cpp_csr_us: float = _time("cpp_neighbor_csr", func() -> void:
		cpp.call("build_neighbor_csr", pos_x, pos_y, alive, CELL_SIZE)
	)

	# --- collisions ---
	var gd_col_us: float = _time("gd_collisions", func() -> void:
		var c: RefCounted = STUB.new()
		c.cell_pos_x = pos_x.duplicate(); c.cell_pos_y = pos_y.duplicate(); c.cell_alive = alive.duplicate()
		PHYSICS.resolve_collisions(c, 8.0, radius_scales, stiffnesses)
	)
	var cpp_col_us: float = _time("cpp_collisions", func() -> void:
		cpp.call("resolve_collisions", pos_x, pos_y, alive, radius_scales, stiffnesses, 8.0, CELL_SIZE, 6)
	)

	# --- collect_inputs (using gd CSR) ---
	var energies: PackedFloat32Array = PackedFloat32Array(); energies.resize(N)
	var types: PackedByteArray = PackedByteArray(); types.resize(N)
	var fields_flat: PackedFloat32Array = PackedFloat32Array(); fields_flat.resize(N * 5)
	var sample_indices: PackedInt32Array = PackedInt32Array(); sample_indices.resize(N)
	for i in range(N):
		energies[i] = 0.5; types[i] = 0; sample_indices[i] = i
	var csr: Dictionary = cpp.call("build_neighbor_csr", pos_x, pos_y, alive, CELL_SIZE)
	var off: PackedInt32Array = csr["offsets"]; var val: PackedInt32Array = csr["values"]
	var env: Dictionary = {"fields_flat": fields_flat, "field_sample_indices": sample_indices, "neighbor_offsets": off, "neighbor_values": val, "energy_max": 1.0, "fields_by_cell": [], "neighbors": []}
	var gcells: RefCounted = STUB.new(); gcells.cell_energy = energies; gcells.cell_alive = alive; gcells.cell_type = types
	var gd_collect_us: float = _time("gd_collect_inputs", func() -> void:
		var tmp: PackedFloat32Array = PackedFloat32Array(); tmp.resize(8)
		for i in range(N): BEHAVIOR.collect_inputs_into(gcells, i, env, tmp)
	)
	var cpp_collect_us: float = _time("cpp_collect_inputs", func() -> void:
		cpp.call("collect_inputs_batch", energies, alive, types, fields_flat, sample_indices, off, val, 1.0)
	)

	print("BENCH: N=%d iters=%d" % [N, ITERS])
	print("BENCH: neighbor_csr %.2fx  collisions %.2fx  collect_inputs %.2fx" % [
		gd_csr_us / maxf(cpp_csr_us, 0.001), gd_col_us / maxf(cpp_col_us, 0.001), gd_collect_us / maxf(cpp_collect_us, 0.001)])
	quit(0)
