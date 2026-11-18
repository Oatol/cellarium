extends SceneTree
## v0.30.0 细粒度性能分解探针。程序化、无鼠标、ASCII 输出。
## 用法：console.exe --headless --path <proj> --script res://tools/PerfBreakdownProbe.gd

const SAMPLES: int = 5
const TIERS: Array[int] = [1000, 3000]

var _env: Node = null
var _mgr: Node = null
var _cells: RefCounted = null
var _physics: Script = null
var _behavior: Script = null
var _metabolism: Script = null

func _initialize() -> void:
	await process_frame
	_physics = load("res://scripts/system/CellPhysics.gd") as Script
	_behavior = load("res://scripts/system/CellBehavior.gd") as Script
	_metabolism = load("res://scripts/system/CellMetabolism.gd") as Script
	for tier_count in TIERS:
		_setup(tier_count)
		_measure(tier_count)
		_teardown()
	quit(0)

func _setup(tier_count: int) -> void:
	var env_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	_env = env_script.new() as Node
	_env._ready()
	_mgr = manager_script.new() as Node
	_mgr.environment_manager = _env
	_mgr.dish_center = Vector2.ZERO
	_mgr.dish_radius = 4000.0
	_mgr._ready()
	_cells = _mgr.get("cells") as RefCounted
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	for i in range(tier_count):
		var angle: float = float(i) * 0.618
		var radius: float = sqrt(float(i)) * 12.0
		_mgr.call("register_zygote", i, 0, -1, genome, Vector2(cos(angle), sin(angle)) * radius, 0.8, 0)
	_mgr.call("advance_physics_tick", 1.0 / 60.0)
	_env.call("advance_field_tick")

func _teardown() -> void:
	if _mgr != null:
		_mgr.free()
	if _env != null:
		_env.free()
	_mgr = null
	_env = null

func _time(label: String, callable: Callable) -> void:
	var started: int = Time.get_ticks_usec()
	for _sample in range(SAMPLES):
		callable.call()
	var per_call: float = float(Time.get_ticks_usec() - started) / float(SAMPLES) / 1000.0
	print("Profile n=%d %-28s %.1fms" % [_cells.call("size"), label, per_call])

func _measure(_tier_count: int) -> void:
	var positions_func: Callable = func() -> void:
		_mgr.call("_field_sample_positions")
	_time("field_positions", positions_func)
	var sample_func: Callable = func() -> void:
		_env.call("begin_field_sampling_indexed", _mgr.call("_field_sample_positions"), _mgr.call("_field_sample_cell_indices"))
	_time("field_batch_sample", sample_func)
	var hash_func: Callable = func() -> void:
		_physics.call("build_spatial_hash", _cells)
	_time("spatial_hash", hash_func)
	var flat_hash_func: Callable = func() -> void:
		_physics.call("build_spatial_hash_flat", _cells)
	_time("spatial_hash_flat", flat_hash_func)
	var flat_buckets: Dictionary = _physics.call("build_spatial_hash_flat", _cells)
	var pairs_func: Callable = func() -> void:
		_physics.call("build_collision_pairs_flat", _cells, 7.0, _cells.get("cell_radius_scale"), flat_buckets)
	_time("collision_pairs_flat", pairs_func)
	var flat_pairs: PackedInt32Array = _physics.call("build_collision_pairs_flat", _cells, 7.0, _cells.get("cell_radius_scale"), flat_buckets)
	print("Profile n=%d collision_pairs_flat_count=%d" % [_cells.call("size"), flat_pairs.size() / 2])
	var neighbors_func: Callable = func() -> void:
		var alive: PackedByteArray = _cells.get("cell_alive")
		for cell_index in range(int(_cells.call("size"))):
			if alive[cell_index] != 0:
				_physics.call("query_neighbors_cached", _cells, cell_index, flat_buckets)
	_time("behavior_neighbors", neighbors_func)
	var behavior_env_func: Callable = func() -> void:
		_mgr.call("_build_behavior_environment")
	_time("behavior_environment", behavior_env_func)
	var outputs: PackedFloat32Array = PackedFloat32Array()
	outputs.resize(int(_cells.call("size")) * 6)
	var neural_func: Callable = func() -> void:
		var environment: Dictionary = _mgr.call("_build_behavior_environment")
		_behavior.call("compute_outputs_flat", _cells, environment, outputs)
	_time("behavior_neural", neural_func)
	var apply_func: Callable = func() -> void:
		_behavior.call("apply_outputs_flat", _cells, outputs, 1.0 / 60.0, 12.0)
	_time("behavior_apply", apply_func)
	var step_func: Callable = func() -> void:
		_physics.call("step", _cells, 1.0 / 60.0)
	_time("physics_step_links", step_func)
	var collision_func: Callable = func() -> void:
		_physics.call("resolve_collisions", _cells, 7.0, _cells.get("cell_radius_scale"), _cells.get("cell_stiffness"))
	_time("physics_collisions", collision_func)
	var project_func: Callable = func() -> void:
		_physics.call("project_to_dish", _cells, Vector2.ZERO, 4000.0, 0.5, _cells.get("cell_radius_scale"), 7.0)
	_time("physics_project", project_func)
	var transfer_func: Callable = func() -> void:
		_mgr.call("_build_transfer_rates")
	_time("transfer_rates", transfer_func)
	var redistribute_func: Callable = func() -> void:
		_metabolism.call("redistribute_link_energy", _cells, _mgr.call("_build_transfer_rates"), 1.0 / 60.0, {})
	_time("link_energy", redistribute_func)
	var base_func: Callable = func() -> void:
		_mgr.call("_apply_base_metabolism", 1.0 / 60.0)
	_time("metabolism_base", base_func)
	var env_func: Callable = func() -> void:
		_env.call("begin_field_sampling_indexed", _mgr.call("_field_sample_positions"), _mgr.call("_field_sample_cell_indices"))
		_mgr.call("_apply_environment_metabolism", 1.0 / 60.0)
	_time("metabolism_env", env_func)
	var radius_func: Callable = func() -> void:
		_mgr.call("_apply_energy_radius_relaxation", 1.0 / 60.0)
	_time("metabolism_radius", radius_func)
	var lifecycle_func: Callable = func() -> void:
		_mgr.call("_apply_autonomous_lifecycle")
	_time("metabolism_lifecycle", lifecycle_func)
	var predation_func: Callable = func() -> void:
		_mgr.call("_apply_predation", 1.0 / 60.0)
	_time("predation", predation_func)
	var signal_func: Callable = func() -> void:
		_mgr.call("_apply_signal_secretion", 1.0 / 60.0)
	_time("signal", signal_func)
	var stats_func: Callable = func() -> void:
		_mgr.call("_species_populations")
	_time("species_populations", stats_func)
