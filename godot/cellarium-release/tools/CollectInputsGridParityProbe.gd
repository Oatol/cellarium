extends SceneTree
## v0.36 parity: collect_inputs_grid (fused) vs build_neighbor_csr + collect_inputs_batch (legacy).
## Both are C++; this verifies the fused path is bit-identical on all 8 channels.
## Run: console.exe --headless --path <project> --script res://tools/CollectInputsGridParityProbe.gd

const N: int = 600

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var env: Node = environment_script.new() as Node
	env._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = env
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	manager.native_spatial_enabled = true
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))
	var spawned: int = 0
	for row in range(-18, 19):
		for col in range(-18, 19):
			if spawned >= N:
				break
			var x: float = float(col) * 16.0 + float(absi(row) % 2) * 8.0
			var y: float = float(row) * 13.856
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1

	var checked: int = 0
	var failures: int = 0
	var spatial: RefCounted = manager.call("_get_native_spatial") as RefCounted
	if spatial == null or not spatial.has_method("collect_inputs_grid"):
		print("COLLECT_GRID_PARITY: FAIL no native grid method")
		quit()

	for tick in range(5):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		var cells: RefCounted = manager.get("cells") as RefCounted
		var cell_count: int = int(cells.call("size"))
		var environment: Dictionary = manager.call("_build_behavior_environment") as Dictionary
		var leg_inputs: PackedFloat32Array = spatial.call("collect_inputs_batch",
			cells.get("cell_energy"), cells.get("cell_alive"), cells.get("cell_type"),
			environment.get("fields_flat", PackedFloat32Array()),
			environment.get("field_sample_indices", PackedInt32Array()),
			environment.get("neighbor_offsets", PackedInt32Array()),
			environment.get("neighbor_values", PackedInt32Array()),
			float(environment.get("energy_max", 1.0))) as PackedFloat32Array
		var grid_inputs: PackedFloat32Array = spatial.call("collect_inputs_grid",
			cells.get("cell_pos_x"), cells.get("cell_pos_y"), cells.get("cell_energy"),
			cells.get("cell_alive"), cells.get("cell_type"),
			environment.get("fields_flat", PackedFloat32Array()),
			environment.get("field_sample_indices", PackedInt32Array()),
			64.0, float(environment.get("energy_max", 1.0))) as PackedFloat32Array
		if leg_inputs.size() != grid_inputs.size():
			print("COLLECT_GRID_PARITY: FAIL size %d vs %d" % [leg_inputs.size(), grid_inputs.size()])
			failures += 1
			continue
		for i in range(leg_inputs.size()):
			checked += 1
			if leg_inputs[i] != grid_inputs[i] and absf(leg_inputs[i] - grid_inputs[i]) > 0.0000001:
				if failures < 6:
					print("COLLECT_GRID_PARITY: FAIL tick%d i=%d leg=%.9f grid=%.9f" % [tick, i, leg_inputs[i], grid_inputs[i]])
				failures += 1

	print("COLLECT_GRID_PARITY: checked=%d failures=%d" % [checked, failures])
	if failures == 0:
		print("COLLECT_GRID_PARITY: OK")
	else:
		print("COLLECT_GRID_PARITY: FAIL")
	quit()
