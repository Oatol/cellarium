extends SceneTree
## 无头解析清单 + 数据层契约断言。新增脚本必须登记到 SCRIPT_MANIFEST。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path <project> --script res://tools/SmokeTest.gd

const SCRIPT_MANIFEST: Array[String] = [
	"res://scripts/Main.gd",
	"res://scripts/system/OrganismManager.gd",
	"res://scripts/core/data/EnvironmentPreset.gd",
	"res://scripts/core/data/DevelopmentContext.gd",
	"res://scripts/core/data/Genome.gd",
	"res://scripts/core/data/GenomeCodec.gd",
	"res://scripts/core/data/CellArray.gd",
	"res://scripts/core/data/OrganismStore.gd",
	"res://scripts/core/data/DevelopmentRules.gd",
	"res://scripts/core/command/CommandBus.gd",
	"res://scripts/core/tick/TickCore.gd",
	"res://scripts/system/EnvironmentManager.gd",
	"res://scripts/system/OrganismManager.gd",
	"res://scripts/system/CellPhysics.gd",
	"res://scripts/system/CellMetabolism.gd",
]

func _initialize() -> void:
	await process_frame
	var failures: int = 0
	for path in SCRIPT_MANIFEST:
		var script: Script = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not script.can_instantiate():
			push_error("SmokeTest: failed to parse " + path)
			failures += 1
		else:
			print("SmokeTest: OK ", path)
	var scene: PackedScene = ResourceLoader.load("res://scenes/main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		push_error("SmokeTest: main.tscn not loadable")
		failures += 1
	else:
		print("SmokeTest: OK res://scenes/main.tscn")
	if not await _check_tick_divide_route():
		failures += 1
	if not _check_cell_physics():
		failures += 1
	if not _check_dish_boundary():
		failures += 1
	if not _check_collision_resolution():
		failures += 1
	if not _check_phase_two_tick_integration():
		failures += 1
	if not _check_spatial_hash():
		failures += 1
	if not _check_link_energy_redistribution():
		failures += 1
	if not _check_cell_death_cleanup():
		failures += 1
	if not _check_basal_autonomy():
		failures += 1
	if not _check_development_rules():
		failures += 1
	if not _check_cell_arrays():
		failures += 1
	if not _check_genome_codec():
		failures += 1
	print("SmokeTest: SCRIPTS=", SCRIPT_MANIFEST.size(), " FAILURES=", failures)
	quit(1 if failures > 0 else 0)

func _check_tick_divide_route() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [{"opcode": 0, "a": 0, "b": 64, "c": 0}, {"opcode": 1, "a": 1, "b": 3, "c": 0}, {"opcode": 2, "a": 0, "b": 1, "c": 4}])
	var org_id: int = int(manager.call("register_zygote", 0, 0, -1, genome, Vector2.ZERO, 0.8, 0))
	if org_id < 0:
		instance.queue_free()
		return false
	var cells: RefCounted = manager.get("cells")
	if int(cells.call("size")) != 1:
		instance.queue_free()
		return false
	bus.call("enqueue", {"type": "DIVIDE", "org_id": org_id, "cell_index": 0, "instruction_index": 0})
	if int(cells.call("size")) != 1:
		push_error("SmokeTest: queued DIVIDE changed state before next tick")
		instance.queue_free()
		return false
	bus.call("execute_tick_commands", 1)
	manager.call("advance_development_tick")
	if int(cells.call("size")) != 2 or int(manager.call("get_organism_count")) != 1:
		push_error("SmokeTest: next-tick DIVIDE did not update the existing organism")
		instance.queue_free()
		return false
	instance.call("_on_tick_advanced", 2)
	if not bool(cells.call("has_link", 0, 1)):
		push_error("SmokeTest: tick 2 must establish the LINK instruction")
		instance.queue_free()
		return false
	var replay_state: Dictionary = _run_development_replay(genome)
	var replay_again: Dictionary = _run_development_replay(genome)
	if replay_state != replay_again:
		push_error("SmokeTest: same development input must produce identical state")
		instance.queue_free()
		return false
	print("SmokeTest: OK deterministic per-tick development instruction route")
	instance.queue_free()
	await process_frame
	return true

func _run_development_replay(genome: RefCounted) -> Dictionary:
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var manager: Node = manager_script.new() as Node
	var genome_id: int = int(genome.call("hash"))
	var org_id: int = int(manager.call("register_zygote", genome_id, 0, -1, genome, Vector2.ZERO, 0.8, 0))
	manager.call("advance_development_tick")
	manager.call("advance_development_tick")
	manager.call("advance_development_tick")
	var cells: RefCounted = manager.get("cells")
	var organisms: RefCounted = manager.get("organisms")
	var state: Dictionary = {"org_id": org_id, "cell_count": int(organisms.get("cell_count")[org_id]), "org_state": int(organisms.get("org_state")[org_id]), "dev_cursor": int(organisms.get("org_dev_cursor")[org_id]), "cell_type": cells.get("cell_type").duplicate(), "positions": [cells.get("cell_pos_x").duplicate(), cells.get("cell_pos_y").duplicate()], "links": [cells.get("link_cell_a").duplicate(), cells.get("link_cell_b").duplicate()]}
	manager.free()
	return state

func _check_cell_physics() -> bool:
	var cell_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var physics_script: Script = load("res://scripts/system/CellPhysics.gd") as Script
	var first: RefCounted = cell_script.new() as RefCounted
	var second: RefCounted = cell_script.new() as RefCounted
	for cells in [first, second]:
		cells.call("append_cell", 0, Vector2(0, 0), 0.5, 0)
		cells.call("append_cell", 0, Vector2(10, 0), 0.5, 0)
		cells.call("link_cells", 0, 1, 4.0)
		cells.get("cell_prev_x")[0] = -1.0
		cells.get("cell_prev_x")[1] = 11.0
		physics_script.call("step", cells, 1.0 / 60.0)
	var first_distance: float = first.call("get_position", 0).distance_to(first.call("get_position", 1))
	var second_distance: float = second.call("get_position", 0).distance_to(second.call("get_position", 1))
	if not is_equal_approx(first_distance, 4.0) or first.get("cell_pos_x") != second.get("cell_pos_x"):
		push_error("SmokeTest: spring constraints must converge deterministically")
		return false
	if not is_equal_approx((float(first.get("cell_pos_x")[0]) + float(first.get("cell_pos_x")[1])) * 0.5, 5.0):
		push_error("SmokeTest: symmetric spring correction must preserve center of mass")
		return false
	var free_cells: RefCounted = cell_script.new() as RefCounted
	free_cells.call("append_cell", 0, Vector2.ZERO, 0.1, 0)
	free_cells.get("cell_prev_x")[0] = -1.0
	physics_script.call("step", free_cells, 1.0 / 60.0)
	if not is_equal_approx(float(free_cells.get("cell_pos_x")[0]), 0.98):
		push_error("SmokeTest: Verlet integration must apply 0.98 damping")
		return false
	print("SmokeTest: OK deterministic Verlet / damped motion / spring constraints")
	return true

func _check_dish_boundary() -> bool:
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var physics: Script = load("res://scripts/system/CellPhysics.gd") as Script
	cells.call("append_cell", 0, Vector2(13, 4), 0.1, 0)
	cells.get("cell_prev_x")[0] = 11.0
	cells.get("cell_prev_y")[0] = 4.0
	cells.call("append_cell", 0, Vector2(6, 0), 0.1, 0)
	cells.call("append_cell", 0, Vector2(20, 0), 0.1, 0)
	cells.get("cell_alive")[2] = 0
	var projected: int = int(physics.call("project_to_dish", cells, Vector2.ZERO, 10.0, 0.5))
	if projected != 1:
		push_error("SmokeTest: dish projection count must ignore inside and dead cells")
		return false
	var position: Vector2 = cells.call("get_position", 0)
	if not is_equal_approx(position.length(), 10.0) or not is_equal_approx(position.x, 10.0 * 13.0 / sqrt(185.0)):
		push_error("SmokeTest: projected cell must lie on the circular boundary")
		return false
	var previous: Vector2 = Vector2(cells.get("cell_prev_x")[0], cells.get("cell_prev_y")[0])
	var velocity: Vector2 = position - previous
	var normal: Vector2 = position.normalized()
	if velocity.dot(normal) >= 0.0 or not is_equal_approx(velocity.dot(normal), -1.0 * 13.0 / sqrt(185.0)):
		push_error("SmokeTest: boundary projection must reverse and damp normal velocity")
		return false
	if physics.call("project_to_dish", cells, Vector2.ZERO, 10.0, 1.1) != -1:
		push_error("SmokeTest: invalid boundary damping must be rejected")
		return false
	print("SmokeTest: OK circular dish projection / normal damping / dead-cell skip")
	return true

func _check_collision_resolution() -> bool:
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var physics: Script = load("res://scripts/system/CellPhysics.gd") as Script
	cells.call("append_cell", 0, Vector2.ZERO, 0.1, 0)
	cells.call("append_cell", 1, Vector2.ZERO, 0.1, 0)
	if int(physics.call("resolve_collisions", cells, 2.0)) != 1:
		push_error("SmokeTest: overlapping cross-organism cells must resolve")
		return false
	if cells.call("get_position", 0).distance_to(cells.call("get_position", 1)) < 3.999:
		push_error("SmokeTest: collision resolution must separate cells to diameter")
		return false
	var same_org: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	same_org.call("append_cell", 0, Vector2.ZERO, 0.1, 0)
	same_org.call("append_cell", 0, Vector2.ZERO, 0.1, 0)
	physics.call("resolve_collisions", same_org, 2.0)
	if not is_equal_approx(same_org.call("get_position", 0).distance_to(same_org.call("get_position", 1)), 0.0):
		push_error("SmokeTest: same-organism cells must skip collision separation")
		return false
	print("SmokeTest: OK cross-organism collision resolution / same-organism skip")
	return true

func _check_phase_two_tick_integration() -> bool:
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 10.0
	manager.cell_radius = 1.0
	manager.base_metabolic_cost = 1.0
	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var first: int = int(manager.call("register_zygote", 0, 0, -1, genome, Vector2(9.5, 0), 1.0, 0))
	var second: int = int(manager.call("register_zygote", 1, 0, -1, genome, Vector2(9.5, 0), 0.1, 0))
	if first < 0 or second < 0:
		manager.free()
		return false
	manager.call("advance_physics_tick", 1.0)
	var cells: RefCounted = manager.get("cells")
	var alive_count: int = 0
	for alive in cells.get("cell_alive"):
		alive_count += int(alive)
	if alive_count != 0 or int(manager.call("get_organism_count")) != 0:
		push_error("SmokeTest: phase-two tick must metabolize and reclaim exhausted cells")
		manager.free()
		return false
	if cells.call("get_position", 0).length() > 10.0001:
		push_error("SmokeTest: phase-two tick must project cells inside dish")
		manager.free()
		return false
	manager.free()
	print("SmokeTest: OK phase-two tick integration / physics / metabolism / reclamation")
	return true

func _check_spatial_hash() -> bool:
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var physics: Script = load("res://scripts/system/CellPhysics.gd") as Script
	cells.call("append_cell", 0, Vector2(63, 0), 0.1, 0)
	cells.call("append_cell", 1, Vector2(64, 0), 0.1, 0)
	cells.call("append_cell", 1, Vector2(300, 20), 0.1, 0)
	cells.call("append_cell", 2, Vector2(-1, 0), 0.1, 0)
	cells.call("append_cell", 3, Vector2(300, 0), 0.1, 0)
	cells.get("cell_alive")[4] = 0
	var pairs: Array = physics.call("build_collision_pairs", cells)
	var pairs_again: Array = physics.call("build_collision_pairs", cells)
	if pairs != pairs_again or pairs.size() != 2:
		push_error("SmokeTest: spatial hash pairs must be stable, unique and exclude same-organism/dead cells")
		return false
	if pairs[0] != Vector2i(0, 3) or pairs[1] != Vector2i(0, 1):
		push_error("SmokeTest: 3x3 spatial hash neighbor enumeration mismatch")
		return false
	var neighbors: Array = physics.call("query_neighbors", cells, 0)
	if neighbors != [1, 3] or physics.call("query_neighbors", cells, 2) != []:
		push_error("SmokeTest: per-cell neighbor query must sort and ignore dead cells")
		return false
	var dense_cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	for i in range(20):
		dense_cells.call("append_cell", i, Vector2(10 + float(i) * 0.01, 10), 0.1, 0)
	var dense_pairs: Array = physics.call("build_collision_pairs", dense_cells)
	if dense_pairs.size() != 190 or dense_pairs[0] != Vector2i(0, 1) or dense_pairs[-1] != Vector2i(18, 19):
		push_error("SmokeTest: spatial hash must sub-bucket dense cells without losing pairs")
		return false
	var dense_neighbors: Array = physics.call("query_neighbors", dense_cells, 0)
	if dense_neighbors.size() != 19 or dense_neighbors[0] != 1 or dense_neighbors[-1] != 19:
		push_error("SmokeTest: neighbor query must search all dense sub-buckets")
		return false
	print("SmokeTest: OK deterministic 64-unit spatial hash / 3x3 neighbor pairs / dense sub-buckets")
	return true

func _check_link_energy_redistribution() -> bool:
	var cells_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var metabolism: Script = load("res://scripts/system/CellMetabolism.gd") as Script
	var cells: RefCounted = cells_script.new() as RefCounted
	cells.call("append_cell", 0, Vector2.ZERO, 1.0, 0)
	cells.call("append_cell", 0, Vector2.RIGHT, 0.0, 0)
	cells.call("append_cell", 0, Vector2.DOWN, 0.5, 0)
	cells.call("link_cells", 0, 1, 1.0)
	var before_energy: float = float(cells.call("total_energy_for_org", 0))
	var rates: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 0.0])
	if not bool(metabolism.call("redistribute_link_energy", cells, rates, 1.0)):
		push_error("SmokeTest: valid linked energy redistribution rejected")
		return false
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var after_energy: float = float(cells.call("total_energy_for_org", 0))
	if not is_equal_approx(energies[0], 0.9) or not is_equal_approx(energies[1], 0.1) or not is_equal_approx(energies[2], 0.5):
		push_error("SmokeTest: linked energy transfer direction or per-link clamp mismatch")
		return false
	if not is_equal_approx(before_energy, after_energy):
		push_error("SmokeTest: linked energy redistribution must conserve organism energy")
		return false
	var tick_cells: RefCounted = cells_script.new() as RefCounted
	tick_cells.call("append_cell", 0, Vector2.ZERO, 1.0, 0)
	tick_cells.call("append_cell", 0, Vector2.RIGHT, 0.0, 0)
	tick_cells.call("append_cell", 0, Vector2.DOWN, 0.0, 0)
	tick_cells.call("link_cells", 0, 1, 1.0)
	tick_cells.call("link_cells", 0, 2, 1.0)
	if not bool(metabolism.call("redistribute_link_energy", tick_cells, PackedFloat32Array([0.0, 1.0, 1.0]), 1.0 / 60.0)):
		push_error("SmokeTest: multi-link tick redistribution failed")
		return false
	if float(tick_cells.get("cell_energy")[0]) < 0.0 or not is_equal_approx(float(tick_cells.call("total_energy_for_org", 0)), 1.0):
		push_error("SmokeTest: multi-link donor scaling must preserve nonnegative energy and total")
		return false
	var dry_cells: RefCounted = cells_script.new() as RefCounted
	dry_cells.call("append_cell", 0, Vector2.ZERO, 0.0, 0)
	dry_cells.call("append_cell", 0, Vector2.RIGHT, 0.4, 0)
	dry_cells.call("link_cells", 0, 1, 1.0)
	if not bool(metabolism.call("redistribute_link_energy", dry_cells, PackedFloat32Array([1.0, 0.0]), 1.0)):
		push_error("SmokeTest: zero-energy redistribution failed")
		return false
	if not is_equal_approx(float(dry_cells.get("cell_energy")[0]), 0.1) or not is_equal_approx(float(dry_cells.get("cell_energy")[1]), 0.3):
		push_error("SmokeTest: transfer must not create negative cell energy")
		return false
	if bool(metabolism.call("redistribute_link_energy", dry_cells, PackedFloat32Array([1.0]), 1.0)):
		push_error("SmokeTest: mismatched transfer-rate array must be rejected")
		return false
	var foreign_cells: RefCounted = cells_script.new() as RefCounted
	foreign_cells.call("append_cell", 0, Vector2.ZERO, 0.4, 0)
	foreign_cells.call("append_cell", 1, Vector2.RIGHT, 0.6, 0)
	foreign_cells.get("link_cell_a").append(0)
	foreign_cells.get("link_cell_b").append(1)
	foreign_cells.get("link_rest_length").append(1.0)
	if bool(metabolism.call("redistribute_link_energy", foreign_cells, PackedFloat32Array([1.0, 0.0]), 1.0)):
		push_error("SmokeTest: cross-organism energy transfer must be rejected")
		return false
	if not is_equal_approx(float(foreign_cells.get("cell_energy")[0]), 0.4) or not is_equal_approx(float(foreign_cells.get("cell_energy")[1]), 0.6):
		push_error("SmokeTest: rejected cross-organism transfer changed energy")
		return false
	print("SmokeTest: OK conservative linked energy transfer / clamp / donor floor / ownership")
	return true

func _check_cell_death_cleanup() -> bool:
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var store: RefCounted = load("res://scripts/core/data/OrganismStore.gd").new() as RefCounted
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	var org_id: int = int(store.call("create_organism", 0, 0, -1, 2))
	var a: int = int(cells.call("append_cell", org_id, Vector2.ZERO, 0.2, 0))
	var b: int = int(cells.call("append_cell", org_id, Vector2.RIGHT, 0.3, 0))
	var c: int = int(cells.call("append_cell", org_id, Vector2.DOWN, 0.5, 0))
	store.call("set_cell_range", org_id, 0, 3)
	cells.call("link_cells", a, b, 1.0)
	cells.call("link_cells", b, c, 1.0)
	manager.set("cells", cells)
	manager.set("organisms", store)
	var returned_energy: float = float(manager.call("remove_cell", b))
	if not is_equal_approx(returned_energy, 0.3) or int(cells.get("link_cell_a").size()) != 0:
		push_error("SmokeTest: removing a cell must return energy and clear all links")
		manager.free()
		return false
	if int(store.get("cell_count")[org_id]) != 2 or int(store.get("org_alive")[org_id]) == 0:
		push_error("SmokeTest: organism must survive while cells remain")
		manager.free()
		return false
	if float(manager.call("remove_cell", b)) >= 0.0:
		push_error("SmokeTest: repeated cell removal must be rejected")
		manager.free()
		return false
	manager.call("remove_cell", a)
	manager.call("remove_cell", c)
	if int(store.get("org_alive")[org_id]) != 0 or int(store.get("org_state")[org_id]) != int(store.get_script().get_script_constant_map()["STATE_DEAD"]):
		push_error("SmokeTest: organism must die after its last cell is removed")
		manager.free()
		return false
	manager.free()
	print("SmokeTest: OK cell removal / edge cleanup / last-cell death")
	return true

func _check_basal_autonomy() -> bool:
	var script: Script = ResourceLoader.load("res://scripts/core/data/EnvironmentPreset.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if script == null or not script.can_instantiate():
		return false
	var preset: Object = script.new() as Object
	preset.set("nutrient_density", 1.0)
	var low: float = float(preset.call("get_basal_autonomy"))
	preset.set("nutrient_density", 2.0)
	var high: float = float(preset.call("get_basal_autonomy"))
	if high <= low:
		push_error("SmokeTest: basal_autonomy must derive from nutrient_density")
		return false
	print("SmokeTest: OK basal_autonomy scales ", low, " -> ", high)
	return true

func _check_development_rules() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var store_script: Script = load("res://scripts/core/data/OrganismStore.gd") as Script
	var rules_script: Script = load("res://scripts/core/data/DevelopmentRules.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [{"opcode": 0, "a": 0, "b": 32, "c": 0}, {"opcode": 1, "a": 1, "b": 3, "c": 0}, {"opcode": 2, "a": 0, "b": 1, "c": 4}])
	if not bool(genome.call("is_valid")) or int(genome.call("division_count")) != 1:
		push_error("SmokeTest: genome DIVIDE count/validation failed")
		return false
	if int(genome.call("hash")) != int(genome.call("duplicate_genome").call("hash")):
		push_error("SmokeTest: equivalent genomes must hash identically")
		return false
	var mutated_hash_genome: RefCounted = genome.call("duplicate_genome") as RefCounted
	mutated_hash_genome.set("mutation_rate_exp", 1)
	if int(genome.call("hash")) == int(mutated_hash_genome.call("hash")):
		push_error("SmokeTest: genome hash must include serialized fields")
		return false
	if int(rules_script.call("expected_cell_count", genome)) != 2:
		push_error("SmokeTest: expected cell count must follow DIVIDE instructions")
		return false
	var division_cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var division_store: RefCounted = store_script.new() as RefCounted
	var division_org: int = int(division_store.call("create_organism", 0, 0, -1, 1))
	var parent_cell: int = int(division_cells.call("append_cell", division_org, Vector2.ZERO, 0.8, 0))
	division_store.call("add_developed_cell", division_org, parent_cell, 2)
	var child_cell: int = int(rules_script.call("execute_instruction", genome, division_cells, division_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": division_org, "instruction_index": 0}))
	if child_cell != 1 or division_cells.call("size") != 2 or int(division_store.get("cell_count")[division_org]) != 2:
		push_error("SmokeTest: DIVIDE must append a cell to the same organism")
		return false
	if not is_equal_approx(float(division_cells.get("cell_energy")[0] + division_cells.get("cell_energy")[child_cell]), 0.8):
		push_error("SmokeTest: DIVIDE must preserve total cell energy")
		return false
	if int(division_store.get("org_parent_id")[division_org]) != -1 or int(division_store.get("org_alive").size()) != 1:
		push_error("SmokeTest: DIVIDE must not create a lineage node")
		return false
	if int(division_store.get("org_state")[division_org]) != int(store_script.get_script_constant_map()["STATE_DEVELOPING"]):
		push_error("SmokeTest: development must remain active while structural instructions remain")
		return false
	if int(rules_script.call("execute_instruction", genome, division_cells, division_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": division_org, "instruction_index": 0})) >= 0:
		push_error("SmokeTest: the same DIVIDE instruction must not execute twice")
		return false
	if int(rules_script.call("execute_instruction", genome, division_cells, division_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": division_org, "instruction_index": 1})) != child_cell:
		push_error("SmokeTest: DIFFERENTIATE must update the target cell")
		return false
	if int(division_cells.get("cell_type")[child_cell]) != 3:
		push_error("SmokeTest: DIFFERENTIATE target type mismatch")
		return false
	if int(rules_script.call("execute_instruction", genome, division_cells, division_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": division_org, "instruction_index": 2})) != parent_cell:
		push_error("SmokeTest: LINK instruction was not executed")
		return false
	if int(division_store.get("org_state")[division_org]) != int(store_script.get_script_constant_map()["STATE_MATURE"]):
		push_error("SmokeTest: completed development must enter mature state")
		return false
	if int(rules_script.call("execute_instruction", genome, division_cells, division_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": division_org, "instruction_index": 2})) >= 0:
		push_error("SmokeTest: consumed LINK instruction must not execute twice")
		return false
	var foreign_cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var foreign_store: RefCounted = store_script.new() as RefCounted
	var foreign_org: int = int(foreign_store.call("create_organism", 0, 0, -1, 1))
	foreign_store.call("create_organism", 0, 0, -1, 1)
	foreign_cells.call("append_cell", foreign_org, Vector2.ZERO, 0.4, 0)
	foreign_cells.call("append_cell", foreign_org + 1, Vector2.RIGHT, 0.4, 0)
	foreign_store.call("add_developed_cell", foreign_org, 0, 2)
	if int(rules_script.call("execute_instruction", genome, foreign_cells, foreign_store, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": foreign_org, "instruction_index": 2})) >= 0:
		push_error("SmokeTest: LINK must reject cross-organism endpoints")
		return false
	if not bool(division_cells.call("has_link", parent_cell, child_cell)) or not bool(division_cells.call("is_symmetric_link", parent_cell)) or not bool(division_cells.call("is_symmetric_link", child_cell)):
		push_error("SmokeTest: LINK instruction must create a symmetric mother-child edge")
		return false
	var single: RefCounted = genome_script.new() as RefCounted
	single.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	single.call("set_development_program", [])
	var mature: int = int(rules_script.call("initial_lifecycle_state", single, 1))
	if mature != int(store_script.get_script_constant_map().get("STATE_MATURE", -1)):
		push_error("SmokeTest: a single-cell genome without DIVIDE must mature immediately")
		return false
	if not bool(rules_script.call("validate_divide_command", {"type": "DIVIDE", "org_id": 1, "cell_index": 0})):
		push_error("SmokeTest: valid DIVIDE command rejected")
		return false
	if bool(rules_script.call("validate_birth_command", {"type": "DIVIDE", "parent_org_id": 1})):
		push_error("SmokeTest: DIVIDE must not be accepted as REPRODUCE")
		return false
	if not bool(rules_script.call("validate_birth_command", {"type": "REPRODUCE", "parent_org_id": 1})):
		push_error("SmokeTest: valid REPRODUCE command rejected")
		return false
	print("SmokeTest: OK DIVIDE depth / single-cell maturity / command separation")
	return true

func _check_cell_arrays() -> bool:
	var cells_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var store_script: Script = load("res://scripts/core/data/OrganismStore.gd") as Script
	var cells: RefCounted = cells_script.new() as RefCounted
	var store: RefCounted = store_script.new() as RefCounted
	var org_a: int = int(store.call("create_organism", 0, 0, -1, 1))
	var org_b: int = int(store.call("create_organism", 0, 0, -1, 1))
	var a: int = int(cells.call("append_cell", org_a, Vector2.ZERO, 0.4, 0))
	var b: int = int(cells.call("append_cell", org_a, Vector2(10, 0), 0.2, 1))
	var c: int = int(cells.call("append_cell", org_b, Vector2(20, 0), 0.1, 0))
	var d: int = int(cells.call("append_cell", org_a, Vector2(0, 10), 0.1, 0))
	if not bool(cells.call("link_cells", a, b, 10.0)) or not bool(cells.call("is_symmetric_link", a)):
		push_error("SmokeTest: same-organism link must be symmetric")
		return false
	if not bool(cells.call("link_cells", a, d, 10.0)) or int(cells.get("cell_link_count")[a]) != 2:
		push_error("SmokeTest: cells must support multiple links")
		return false
	if bool(cells.call("link_cells", b, c, 10.0)):
		push_error("SmokeTest: cross-organism link must be rejected")
		return false
	var crowded: RefCounted = cells_script.new() as RefCounted
	var hub: int = int(crowded.call("append_cell", org_a, Vector2.ZERO, 0.0, 0))
	for i in range(20):
		var leaf: int = int(crowded.call("append_cell", org_a, Vector2(i + 1, 0), 0.0, 0))
		if not bool(crowded.call("link_cells", hub, leaf, 1.0)):
			push_error("SmokeTest: link capacity rejected before 20 links")
			return false
	var overflow_leaf: int = int(crowded.call("append_cell", org_a, Vector2(21, 0), 0.0, 0))
	if bool(crowded.call("link_cells", hub, overflow_leaf, 1.0)) or int(crowded.get("cell_link_count")[hub]) != 20:
		push_error("SmokeTest: link capacity must stop at 20")
		return false
	if not is_equal_approx(float(cells.call("total_energy_for_org", org_a)), 0.7):
		push_error("SmokeTest: organism energy must equal sum of cell energy")
		return false
	store.call("set_cell_range", org_a, 0, 3)
	store.call("set_cell_range", org_b, 3, 1)
	if not bool(store.call("validate_cell_ranges", 4)):
		push_error("SmokeTest: valid cell ranges rejected")
		return false
	print("SmokeTest: OK SoA ranges / symmetric links / same-organism constraint / energy sum")
	return true

func _check_genome_codec() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var codec_script: Script = load("res://scripts/core/data/GenomeCodec.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("version", 1)
	genome.set("flags", 1)
	genome.set("respiration", 2)
	genome.set("mutation_rate_exp", 7)
	genome.set("loci", PackedByteArray([1, 33, 127]))
	genome.set("traits", PackedByteArray([0, 1, 2, 3, 4, 5, 6, 63]))
	genome.call("set_development_program", [{"opcode": 0, "a": 2, "b": 128, "c": 12}, {"opcode": 4, "a": 0, "b": 0, "c": 60}])
	var encoded: PackedByteArray = codec_script.call("encode", genome)
	var decoded: RefCounted = codec_script.call("decode", encoded) as RefCounted
	if decoded == null or not bool(decoded.call("is_valid")):
		push_error("SmokeTest: GNP1 encode/decode round-trip failed")
		return false
	if int(decoded.get("mutation_rate_exp")) != 7 or decoded.get("loci") != genome.get("loci") or decoded.get("dev_program") != genome.get("dev_program"):
		push_error("SmokeTest: GNP1 round-trip lost payload fields")
		return false
	var damaged: PackedByteArray = encoded.duplicate()
	damaged[damaged.size() - 5] = int(damaged[damaged.size() - 5]) ^ 1
	if codec_script.call("decode", damaged) != null:
		push_error("SmokeTest: GNP1 checksum corruption was accepted")
		return false
	var unsupported: PackedByteArray = encoded.duplicate()
	unsupported[4] = 2
	var unsupported_crc: int = int(codec_script.call("_crc32", unsupported.slice(0, unsupported.size() - 4)))
	for shift in [0, 8, 16, 24]:
		unsupported[unsupported.size() - 4 + (shift / 8)] = (unsupported_crc >> shift) & 255
	if codec_script.call("decode", unsupported) != null:
		push_error("SmokeTest: unsupported GNP1 version was accepted")
		return false
	var trailing: PackedByteArray = encoded.slice(0, encoded.size() - 4)
	trailing.append(0)
	var trailing_crc: int = int(codec_script.call("_crc32", trailing))
	for shift in [0, 8, 16, 24]:
		trailing.append((trailing_crc >> shift) & 255)
	if codec_script.call("decode", trailing) != null:
		push_error("SmokeTest: GNP1 trailing bytes were accepted")
		return false
	print("SmokeTest: OK GNP1 round-trip / CRC / version / length rejection bytes=", encoded.size())
	return true
