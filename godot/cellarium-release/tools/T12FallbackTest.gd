extends SceneTree
## T12（§9.2）：禁用 compute 后重跑确定性回归，功能一致（精度/性能可降，玩法不缺）。
## 含短分段存档续跑验证（§9.4：避免长时间满载）。运行：--script res://tools/T12FallbackTest.gd

func _initialize() -> void:
	await process_frame
	var failures: int = 0
	var field_script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script

	# 1) 强制 CPU 后端：功能完整（五通道 / source / 地形 / 存档 / Agent 查询）
	var field: RefCounted = field_script.new() as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([0.5, 273.0, 0.21, 0.3, 0.0])
	if not bool(field.call("configure", 16, Vector2.ZERO, 100.0, defaults, false)):
		push_error("T12: forced CPU configure failed")
		quit(1); return
	var backend: Dictionary = field.call("get_backend_diagnostics") as Dictionary
	if str(backend.get("backend", "")) != "cpu":
		push_error("T12: expected cpu backend, got " + str(backend))
		failures += 1
	field.call("set_value", 0, 8, 8, 1.0)
	field.call("add_source", 0, 8, 8, 0.5)
	field.call("diffuse_tick")
	var sample: PackedFloat32Array = field.call("sample", Vector2.ZERO) as PackedFloat32Array
	if sample.size() != 5 or sample[0] <= 0.0:
		push_error("T12: CPU field lost nutrient channel")
		failures += 1
	var terrain_changed: int = int(field.call("paint_terrain", 8, 8, 1, true))
	if terrain_changed < 1 or int(field.call("get_terrain_solid_count")) < 1:
		push_error("T12: CPU terrain edit missing")
		failures += 1

	# 2) 连续 220 tick vs 110 tick→存档→读档→110 tick，两条路径哈希一致（CPU 回退下 T08 等价）
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var seg_path: String = "user://cellarium_t12_seg.gsave"
	var hash_a: int = _run_continuous(environment_script, manager_script, genome, 220)
	var hash_b: int = _run_with_checkpoint(environment_script, manager_script, genome, 110, 110, seg_path)
	if hash_a != hash_b:
		push_error("T12: CPU segmented replay hash mismatch %d vs %d" % [hash_a, hash_b])
		failures += 1

	# 3) 存档往返在 CPU 回退下完整
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager._ready()
	manager.call("register_zygote", 0, 0, -1, genome, Vector2.ZERO, 0.8, 0)
	if not bool(manager.call("save_state_to_file", "user://cellarium_t12_round.gsave")):
		push_error("T12: save failed on CPU fallback")
		failures += 1
	if not bool(manager.call("load_state_from_file", "user://cellarium_t12_round.gsave")):
		push_error("T12: load failed on CPU fallback")
		failures += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(seg_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cellarium_t12_round.gsave"))
	manager.free(); environment.free()

	print("T12: backend=", backend.get("backend", "?"), " hash_a=", hash_a, " hash_b=", hash_b, " FAILURES=", failures)
	quit(1 if failures > 0 else 0)

func _new_world(environment_script: Script, manager_script: Script, genome: RefCounted) -> Array:
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 1000.0
	manager._ready()
	manager.call("register_zygote", 0, 0, -1, genome, Vector2.ZERO, 0.8, 0)
	return [manager, environment]

func _advance(manager: Node, environment: Node, ticks: int) -> void:
	for tick in range(ticks):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		environment.call("advance_field_tick")

func _run_continuous(environment_script: Script, manager_script: Script, genome: RefCounted, ticks: int) -> int:
	var world: Array = _new_world(environment_script, manager_script, genome)
	_advance(world[0] as Node, world[1] as Node, ticks)
	var hash_value: int = int((world[0] as Node).call("get_state_hash"))
	(world[0] as Node).free(); (world[1] as Node).free()
	return hash_value

func _run_with_checkpoint(environment_script: Script, manager_script: Script, genome: RefCounted, first_ticks: int, second_ticks: int, save_path: String) -> int:
	var world_a: Array = _new_world(environment_script, manager_script, genome)
	_advance(world_a[0] as Node, world_a[1] as Node, first_ticks)
	(world_a[0] as Node).call("save_state_to_file", save_path)
	(world_a[0] as Node).free(); (world_a[1] as Node).free()
	# 第二段：全新世界读档续跑
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 1000.0
	manager._ready()
	manager.call("load_state_from_file", save_path)
	_advance(manager, environment, second_ticks)
	var hash_value: int = int(manager.call("get_state_hash"))
	manager.free(); environment.free()
	return hash_value
