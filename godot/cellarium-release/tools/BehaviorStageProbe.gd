extends SceneTree
## v0.36 诊断：细分 behavior 阶段各子调用耗时（native 开启）。
## 运行：console.exe --headless --path <project> --script res://tools/BehaviorStageProbe.gd

const N: int = 1024
const REPEATS: int = 24

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
	for row in range(-26, 27):
		for col in range(-26, 27):
			if spawned >= N:
				break
			var x: float = float(col) * 14.0 + float(absi(row) % 2) * 7.0
			var y: float = float(row) * 12.124
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1
	manager.set("division_mass", 100.0)
	for i in range(3):
		manager.call("advance_physics_tick", 1.0 / 60.0)

	var native_spatial: RefCounted = manager.call("_get_native_spatial") as RefCounted
	var native_neural: RefCounted = manager.call("_get_native_neural") as RefCounted
	var cell_count: int = int(manager.get("cells").call("size"))
	var cells: RefCounted = manager.get("cells") as RefCounted
	var dt: float = 1.0 / 60.0

	# 各子调用独立计时
	var t: int = Time.get_ticks_usec()
	for i in range(REPEATS):
		manager.call("_field_sample_positions")
	var pos_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		manager.call("_field_sample_cell_indices")
	var idx_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		manager.call("_build_behavior_environment")
	var env_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# collect_inputs_batch
	var env_dict: Dictionary = manager.call("_build_behavior_environment") as Dictionary
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		native_spatial.call("collect_inputs_batch",
			cells.get("cell_energy"), cells.get("cell_alive"), cells.get("cell_type"),
			env_dict.get("fields_flat", PackedFloat32Array()),
			env_dict.get("field_sample_indices", PackedInt32Array()),
			env_dict.get("neighbor_offsets", PackedInt32Array()),
			env_dict.get("neighbor_values", PackedInt32Array()),
			float(env_dict.get("energy_max", 1.0)))
	var collect_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# evaluate_batch
	var inputs: PackedFloat32Array = native_spatial.call("collect_inputs_batch",
		cells.get("cell_energy"), cells.get("cell_alive"), cells.get("cell_type"),
		env_dict.get("fields_flat", PackedFloat32Array()),
		env_dict.get("field_sample_indices", PackedInt32Array()),
		env_dict.get("neighbor_offsets", PackedInt32Array()),
		env_dict.get("neighbor_values", PackedInt32Array()),
		float(env_dict.get("energy_max", 1.0))) as PackedFloat32Array
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		native_neural.call("evaluate_batch",
			inputs, cells.get("neural_weights"), cells.get("cell_alive"), 0, cell_count)
	var eval_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# begin_field_sampling_indexed (每 tick 两次)
	var positions: Array[Vector2] = manager.call("_field_sample_positions") as Array[Vector2]
	var indices: Array[int] = manager.call("_field_sample_cell_indices") as Array[int]
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		env.call("begin_field_sampling_indexed", positions, indices)
	var field_begin_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# build_behavior_env 内部：build_neighbor_csr
	var cell_pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var cell_pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var cell_alive: PackedByteArray = cells.get("cell_alive")
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		native_spatial.call("build_neighbor_csr", cell_pos_x, cell_pos_y, cell_alive, 64.0)
	var csr_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# get_field_samples_flat + get_field_sample_index_array
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		env.call("get_field_samples_flat")
	var field_flat_get_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		env.call("get_field_sample_index_array", cell_count)
	var field_idx_get_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	# sample_cells_flat (field 采样本体)
	var field_obj: RefCounted = env.get("field") as RefCounted
	t = Time.get_ticks_usec()
	for i in range(REPEATS):
		field_obj.call("sample_cells_flat", positions)
	var sample_flat_us: float = float(Time.get_ticks_usec() - t) / float(REPEATS)

	print("BEHAVIOR_STAGE: cells=%d repeats=%d" % [cell_count, REPEATS])
	print("BEHAVIOR_STAGE: field_sample_positions   %9.1f us" % pos_us)
	print("BEHAVIOR_STAGE: field_sample_indices     %9.1f us" % idx_us)
	print("BEHAVIOR_STAGE: build_behavior_env       %9.1f us" % env_us)
	print("BEHAVIOR_STAGE:   build_neighbor_csr     %9.1f us" % csr_us)
	print("BEHAVIOR_STAGE:   get_field_samples_flat %9.1f us" % field_flat_get_us)
	print("BEHAVIOR_STAGE:   get_field_sample_index %9.1f us" % field_idx_get_us)
	print("BEHAVIOR_STAGE:   sample_cells_flat      %9.1f us" % sample_flat_us)
	print("BEHAVIOR_STAGE: collect_inputs_batch     %9.1f us" % collect_us)
	print("BEHAVIOR_STAGE: evaluate_batch           %9.1f us" % eval_us)
	print("BEHAVIOR_STAGE: begin_field_sampling     %9.1f us" % field_begin_us)
	quit()
