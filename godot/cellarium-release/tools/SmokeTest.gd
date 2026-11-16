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
	"res://scripts/system/CellPhysics.gd",
	"res://scripts/system/CellMetabolism.gd",
	"res://scripts/system/CellBehavior.gd",
	"res://scripts/system/RespirationRules.gd",
	"res://scripts/system/EnvironmentField.gd",
	"res://scripts/system/Predation.gd",
	"res://scripts/system/EnergyLedger.gd",
	"res://scripts/rendering/CellariumView.gd",
	"res://scripts/rendering/DishLayer.gd",
	"res://scripts/rendering/LinkLayer.gd",
	"res://scripts/rendering/CellLayer.gd",
	"res://scripts/ui/ToolCatalog.gd",
	"res://scripts/ui/GameHUD.gd",
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
	var tick_route_ok: bool = await _check_tick_divide_route()
	if not tick_route_ok:
		failures += 1
	if not _check_cell_physics():
		failures += 1
	if not _check_dish_boundary():
		failures += 1
	if not _check_collision_resolution():
		failures += 1
	if not _check_phase_two_tick_integration():
		failures += 1
	var scene_visualization_ok: bool = await _check_scene_visualization()
	if not scene_visualization_ok:
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
	if not _check_cell_behavior():
		failures += 1
	if not _check_respiration_rules():
		failures += 1
	if not _check_environment_field():
		failures += 1
	if not _check_full_tick_determinism():
		failures += 1
	if not _check_phase_three_metabolism():
		failures += 1
	if not _check_signal_secretion():
		failures += 1
	if not await _check_tool_command_loop():
		failures += 1
	if not _check_predation():
		failures += 1
	if not _check_energy_ledger():
		failures += 1
	if not await _check_predation_integration():
		failures += 1
	print("SmokeTest: SCRIPTS=", SCRIPT_MANIFEST.size(), " FAILURES=", failures)
	quit(1 if failures > 0 else 0)

func _check_tick_divide_route() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
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

func _check_scene_visualization() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var dish_layer: Node = instance.get_node("DishView/DishFill")
	var link_layer: Node = instance.get_node("DishView/LinkLayer")
	var cell_layer: Node = instance.get_node("DishView/CellLayer")
	var cells: RefCounted = manager.get("cells") as RefCounted
	if int(manager.call("get_organism_count")) != 1 or int(cells.call("size")) != 1:
		push_error("SmokeTest: main scene must create a demonstration organism")
		instance.queue_free()
		return false
	if dish_layer.get_script() != load("res://scripts/rendering/DishLayer.gd") or link_layer.get_script() != load("res://scripts/rendering/LinkLayer.gd") or cell_layer.get_script() != load("res://scripts/rendering/CellLayer.gd"):
		push_error("SmokeTest: each scene layer must use its dedicated renderer")
		instance.queue_free()
		return false
	if link_layer.get("organism_manager") != manager or cell_layer.get("organism_manager") != manager:
		push_error("SmokeTest: render layers must read the scene OrganismManager")
		instance.queue_free()
		return false
	instance.queue_free()
	await process_frame
	print("SmokeTest: OK main scene demo organism / renderer binding")
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

func _check_cell_behavior() -> bool:
	var behavior: Script = load("res://scripts/system/CellBehavior.gd") as Script
	var cells_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var inputs: PackedFloat32Array = PackedFloat32Array([0.2, -0.4, 0.6, 0.1, -0.1, 0.25, 0.5, 0.8])
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(56)
	for index in range(weights.size()):
		weights[index] = float((index % 7) - 3) * 0.07
	var outputs: PackedFloat32Array = behavior.call("evaluate", inputs, weights)
	if outputs.size() != 6 or behavior.call("evaluate", PackedFloat32Array(), weights).size() != 6:
		push_error("SmokeTest: neural evaluation must return fixed output shape for valid and invalid inputs")
		return false
	for output in outputs:
		if not is_finite(output) or output < -1.0 or output > 1.0:
			push_error("SmokeTest: neural outputs must be finite and bounded")
			return false
	var first_cells: RefCounted = cells_script.new() as RefCounted
	var second_cells: RefCounted = cells_script.new() as RefCounted
	first_cells.call("append_cell", 0, Vector2.ZERO, 0.8, 0)
	second_cells.call("append_cell", 0, Vector2.ZERO, 0.8, 0)
	if not bool(behavior.call("initialize_weights", first_cells, 0, 12345)) or not bool(behavior.call("initialize_weights", second_cells, 0, 12345)):
		push_error("SmokeTest: neural weights must initialize")
		return false
	if first_cells.get("neural_weights") != second_cells.get("neural_weights"):
		push_error("SmokeTest: same genome/cell seed must yield identical neural weights")
		return false
	var parent_weights: PackedFloat32Array = first_cells.get("neural_weights").duplicate()
	var child_index: int = int(first_cells.call("divide_cell", 0, 0.0, 1.0))
	if child_index != 1 or first_cells.get("neural_weights").slice(56, 112) != parent_weights:
		push_error("SmokeTest: divided cells must inherit identical neural weights")
		return false
	var next_cell: int = int(first_cells.call("append_cell", 0, Vector2(2, 0), 0.2, 0))
	if not bool(behavior.call("initialize_weights", first_cells, next_cell, 12345)) or first_cells.get("neural_weights").slice(112, 168) == parent_weights:
		push_error("SmokeTest: each cell must derive distinct deterministic weights from its index")
		return false
	var neighbors: Dictionary = {0: [], 1: []}
	var environment: Dictionary = {"fields": [0.1, 0.2, 0.3, 0.4, 0.5], "neighbors": neighbors, "energy_max": 1.0}
	var replay_a: Array[PackedFloat32Array] = behavior.call("compute_outputs", second_cells, environment)
	var replay_b: Array[PackedFloat32Array] = behavior.call("compute_outputs", second_cells, environment)
	if replay_a != replay_b or replay_a[0].size() != 6:
		push_error("SmokeTest: neural output pass must be deterministic")
		return false
	if not bool(behavior.call("apply_outputs", second_cells, replay_a, 1.0 / 60.0)):
		push_error("SmokeTest: behavior intent application failed")
		return false
	var stored_intents: PackedFloat32Array = behavior.call("get_intents", second_cells, 0)
	var behavior_snapshot_a: PackedFloat32Array = behavior.call("snapshot_intents", second_cells)
	var behavior_snapshot_b: PackedFloat32Array = behavior.call("snapshot_intents", second_cells)
	if behavior_snapshot_a != behavior_snapshot_b:
		push_error("SmokeTest: behavior intent state snapshot must be deterministic")
		return false
	if stored_intents != replay_a[0] or stored_intents.size() != 6:
		push_error("SmokeTest: every neural output must persist as a queryable behavior intent")
		return false
	var child_intents: PackedFloat32Array = behavior.call("get_intents", first_cells, child_index)
	if child_intents != behavior.call("get_intents", first_cells, 0):
		push_error("SmokeTest: divided cells must inherit current behavior intents")
		return false
	print("SmokeTest: OK deterministic 8-4-6 cell behavior / bounded outputs / intent persistence / division inheritance")
	return true

func _check_signal_secretion() -> bool:
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment.nutrient_density = 0.0
	environment.dish_center = Vector2.ZERO
	environment.dish_radius = 100.0
	environment._ready()
	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 100.0
	manager.base_metabolic_cost = 0.0
	var org_id: int = int(manager.call("register_zygote", int(genome.call("hash")), 0, -1, genome, Vector2.ZERO, 0.8, 0))
	manager.get("cells").get("behavior_intents")[org_id * 6 + 3] = 0.75
	var before: Array[PackedFloat32Array] = environment.get("field").call("get_state_snapshot")
	manager.call("_apply_signal_secretion", 1.0 / 60.0)
	environment.call("advance_field_tick")
	var after: Array[PackedFloat32Array] = environment.get("field").call("get_state_snapshot")
	if after[4] == before[4] or after[0] != before[0]:
		push_error("SmokeTest: secretion intent must inject signal only, not create nutrient energy")
		manager.free()
		environment.free()
		return false
	manager.free()
	environment.free()
	print("SmokeTest: OK behavior secretion routes only to chemical signal field")
	return true

func _check_phase_three_metabolism() -> bool:
	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	genome.set("respiration", 0)
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment.nutrient_density = 0.0
	environment.oxygen_fraction = 0.10
	environment.dish_center = Vector2.ZERO
	environment.dish_radius = 100.0
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 100.0
	manager.base_metabolic_cost = 0.0
	manager.anaerobic_toxicity_damage_per_second = 1.0
	var org_id: int = int(manager.call("register_zygote", int(genome.call("hash")), 0, -1, genome, Vector2.ZERO, 0.8, 0))
	var store: RefCounted = manager.get("organisms")
	for tick in range(61):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	if int(store.get("org_alive")[org_id]) != 0 or int(store.get("org_death_cause")[org_id]) != int(store.get_script().get_script_constant_map()["DEATH_TOXICITY"]):
		push_error("SmokeTest: T04 anaerobic cell did not die from oxygen toxicity at 10 percent")
		manager.free()
		environment.free()
		return false
	manager.free()
	environment.free()
	for respiration in range(3):
		var rules: Script = load("res://scripts/system/RespirationRules.gd") as Script
		var oxygenated: Dictionary = rules.call("evaluate", respiration, 0.21, 2.0)
		var anoxic: Dictionary = rules.call("evaluate", respiration, 0.0, 2.0)
		if not bool(oxygenated.get("valid", false)) or not bool(anoxic.get("valid", false)):
			return false
	if not is_equal_approx(float(load("res://scripts/system/RespirationRules.gd").call("evaluate", 0, 0.0).get("efficiency", -1.0)), 1.0):
		return false
	if not is_equal_approx(float(load("res://scripts/system/RespirationRules.gd").call("evaluate", 1, 0.21).get("efficiency", -1.0)), 3.0):
		return false
	var facultative: Dictionary = load("res://scripts/system/RespirationRules.gd").call("evaluate", 2, 0.21)
	if not is_equal_approx(float(facultative.get("efficiency", -1.0)), 2.0) or int(facultative.get("budget_cost", 0)) != 2:
		return false
	print("SmokeTest: OK T04 oxygen toxicity death cause / T06 respiration efficiency and budget")
	return true

func _check_full_tick_determinism() -> bool:
	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var first: Dictionary = _run_physics_replay(genome, 240)
	var second: Dictionary = _run_physics_replay(genome, 240)
	if first != second:
		push_error("SmokeTest: same-seed complete physics ticks must produce identical state hashes")
		return false
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var baseline: Node = manager_script.new() as Node
	var baseline_org: int = int(baseline.call("register_zygote", int(genome.call("hash")), 0, -1, genome, Vector2.ZERO, 0.8, 0))
	var baseline_hash: int = int(baseline.call("get_state_hash"))
	baseline.get("organisms").get("org_health")[baseline_org] = 0.9
	if int(baseline.call("get_state_hash")) == baseline_hash:
		push_error("SmokeTest: organism hash must include health")
		baseline.free()
		return false
	baseline.get("organisms").get("org_health")[baseline_org] = 1.0
	baseline.get("cells").get("behavior_intents")[2] = 0.5
	if int(baseline.call("get_state_hash")) == baseline_hash:
		push_error("SmokeTest: organism hash must include behavior intents")
		baseline.free()
		return false
	baseline.free()
	var field: RefCounted = load("res://scripts/system/EnvironmentField.gd").new() as RefCounted
	field.call("configure", 8, Vector2.ZERO, 20.0, PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]), false)
	var field_hash: int = int(field.call("get_state_hash"))
	field.call("set_value", 4, 4, 4, 0.25)
	if int(field.call("get_state_hash")) == field_hash:
		push_error("SmokeTest: environment hash must include every channel cell")
		return false
	print("SmokeTest: OK 240-tick state hashes / health, intent and environment coverage")
	return true

func _run_physics_replay(genome: RefCounted, tick_count: int) -> Dictionary:
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment.nutrient_density = 1.2
	environment.oxygen_fraction = 0.21
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 1000.0
	manager.call("register_zygote", int(genome.call("hash")), 0, -1, genome, Vector2.ZERO, 0.8, 0)
	for tick in range(tick_count):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		environment.call("advance_field_tick")
	var state: Dictionary = {
		"organism_hash": int(manager.call("get_state_hash")),
		"environment_hash": int(environment.get("field").call("get_state_hash")),
	}
	manager.free()
	environment.free()
	return state

func _check_environment_field() -> bool:
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var field: RefCounted = script.new() as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([2.0, 273.0, 0.21, 0.4, 0.0])
	if not bool(field.call("configure", 8, Vector2.ZERO, 20.0, defaults, false)):
		push_error("SmokeTest: CPU environment field configuration failed")
		return false
	var center_sample: PackedFloat32Array = field.call("sample", Vector2.ZERO)
	if center_sample != defaults:
		push_error("SmokeTest: environment field must return all five channel defaults")
		return false
	var outside_sample: PackedFloat32Array = field.call("sample", Vector2(21, 0))
	if outside_sample != PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]):
		push_error("SmokeTest: environment field must return zero outside dish")
		return false
	var before: float = float(field.call("get_total_nutrient"))
	var consumed: float = float(field.call("consume_nutrient", Vector2.ZERO, 0.75))
	var after: float = float(field.call("get_total_nutrient"))
	if not is_equal_approx(consumed, 0.75) or not is_equal_approx(before - after, consumed):
		push_error("SmokeTest: nutrient withdrawal must conserve field nutrient accounting")
		return false
	var too_much: float = float(field.call("consume_nutrient", Vector2.ZERO, 100.0))
	if too_much > 1.251 or float(field.call("consume_nutrient", Vector2(-21, 0), 1.0)) != 0.0:
		push_error("SmokeTest: nutrient withdrawal must clamp to available resource and dish boundary")
		return false
	if field.call("get_backend_diagnostics").get("backend", "") != "cpu":
		push_error("SmokeTest: explicit CPU backend selection was ignored")
		return false
	var mask_field: RefCounted = script.new() as RefCounted
	mask_field.call("configure", 8, Vector2.ZERO, 20.0, PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]), false)
	if not bool(mask_field.call("add_source", 0, 3, 3, 0.25)) or bool(mask_field.call("add_source", 0, 0, 0, 1.0)):
		push_error("SmokeTest: source additions must accept in-dish cells and reject masked cells")
		return false
	mask_field.call("set_value", 0, 3, 3, 1.0)
	mask_field.call("set_value", 0, 3, 2, 0.5)
	mask_field.call("diffuse_tick")
	var masked_state: Array[PackedFloat32Array] = mask_field.call("get_state_snapshot")
	if masked_state[0][0] != 0.0 or masked_state[0][27] < 0.9:
		push_error("SmokeTest: circular mask or queued source injection failed")
		return false
	print("SmokeTest: OK five-channel CPU field / circular mask / source injection / nutrient accounting")
	return true

func _check_respiration_rules() -> bool:
	var rules: Script = load("res://scripts/system/RespirationRules.gd") as Script
	var anaerobic_at_limit: Dictionary = rules.call("evaluate", 0, 0.08)
	var anaerobic_above_limit: Dictionary = rules.call("evaluate", 0, 0.080001)
	var aerobic_full: Dictionary = rules.call("evaluate", 1, 0.21)
	var aerobic_hypoxic: Dictionary = rules.call("evaluate", 1, 0.08)
	var facultative_oxygenated: Dictionary = rules.call("evaluate", 2, 0.21)
	var facultative_anoxic: Dictionary = rules.call("evaluate", 2, 0.0)
	if not anaerobic_at_limit.get("valid", false) or anaerobic_at_limit.get("toxic", true):
		push_error("SmokeTest: anaerobic toxicity threshold must be strictly greater than 8 percent")
		return false
	if not anaerobic_above_limit.get("toxic", false) or not is_equal_approx(float(anaerobic_above_limit.get("efficiency", 0.0)), 1.0):
		push_error("SmokeTest: anaerobic respiration must report toxicity above 8 percent")
		return false
	if not is_equal_approx(float(aerobic_full.get("efficiency", 0.0)), 3.0) or not is_equal_approx(float(aerobic_hypoxic.get("efficiency", 0.0)), 0.5):
		push_error("SmokeTest: aerobic respiration efficiency mismatch")
		return false
	if not is_equal_approx(float(facultative_oxygenated.get("efficiency", 0.0)), 2.0) or int(facultative_oxygenated.get("budget_cost", 0)) != 2:
		push_error("SmokeTest: facultative respiration efficiency or budget cost mismatch")
		return false
	if not is_equal_approx(float(facultative_anoxic.get("efficiency", 0.0)), 1.0) or int(facultative_anoxic.get("budget_cost", 0)) != 2:
		push_error("SmokeTest: facultative respiration must remain viable without oxygen")
		return false
	if bool(rules.call("evaluate", 3, 0.5).get("valid", true)) or bool(rules.call("evaluate", 1, 1.1).get("valid", true)):
		push_error("SmokeTest: invalid respiration type and oxygen fraction must be rejected")
		return false
	var preset: RefCounted = load("res://scripts/core/data/EnvironmentPreset.gd").new() as RefCounted
	preset.set("oxygen_fraction", 0.21)
	if not is_equal_approx(float(preset.call("to_snapshot").get("oxygen_fraction", -1.0)), 0.21):
		push_error("SmokeTest: oxygen background must persist in environment snapshots")
		return false
	print("SmokeTest: OK respiration thresholds / efficiencies / facultative budget / oxygen snapshot")
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

func _check_tool_command_loop() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("SmokeTest: tool loop scene missing")
		return false
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var hud: Node = instance.get_node("UI/HUD")
	if manager == null or bus == null or hud == null:
		push_error("SmokeTest: tool loop nodes missing")
		instance.queue_free()
		return false
	var catalog_script: Script = load("res://scripts/ui/ToolCatalog.gd") as Script
	var tools: Array = catalog_script.call("tools")
	if tools.size() != 14:
		push_error("SmokeTest: tool catalog != 14")
		instance.queue_free()
		return false
	var cells: RefCounted = manager.get("cells")
	var base_count: int = int(cells.call("size"))

	bus.call("enqueue", {"type": "SPAWN", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	if int(cells.call("size")) != base_count:
		push_error("SmokeTest: SPAWN mutated state before tick")
		instance.queue_free()
		return false
	bus.call("execute_tick_commands", 1)
	if int(cells.call("size")) != base_count + 1:
		push_error("SmokeTest: SPAWN did not create cell next tick")
		instance.queue_free()
		return false

	var spawned_index: int = int(cells.call("size")) - 1
	var energy_before: float = float(cells.get("cell_energy")[spawned_index])
	bus.call("enqueue", {"type": "BOOST", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 2)
	var energy_after: float = float(cells.get("cell_energy")[spawned_index])
	if energy_after <= energy_before:
		push_error("SmokeTest: BOOST did not add energy")
		instance.queue_free()
		return false

	bus.call("enqueue", {"type": "INJECT_COLOR", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 3)
	if int(cells.get("cell_type")[spawned_index]) == 0:
		push_error("SmokeTest: INJECT_COLOR did not change type")
		instance.queue_free()
		return false

	var diag: Dictionary = manager.get("tool_diagnostics")
	if int(diag.get("SPAWN", 0)) < 1 or int(diag.get("BOOST", 0)) < 1 or int(diag.get("INJECT_COLOR", 0)) < 1:
		push_error("SmokeTest: tool diagnostics not incremented")
		instance.queue_free()
		return false

	bus.call("enqueue", {"type": "SELECT", "position": Vector2.ZERO, "delta": Vector2.ZERO, "kind": "stub"})
	var stub_result: int = -99
	bus.call("execute_tick_commands", 4)
	stub_result = int(diag.get("STUB", 0))
	if stub_result < 1:
		push_error("SmokeTest: stub tool not counted")
		instance.queue_free()
		return false

	var hud_tools: int = hud.get("_tool_buttons").size()
	var hud_modes: int = hud.get("_mode_buttons").size()
	if hud_tools != 14 or hud_modes != 5:
		push_error("SmokeTest: HUD buttons tools=%d modes=%d" % [hud_tools, hud_modes])
		instance.queue_free()
		return false
	if str(hud.call("selected_tool_id")) != "SPAWN":
		push_error("SmokeTest: HUD default tool != SPAWN")
		instance.queue_free()
		return false

	instance.queue_free()
	print("SmokeTest: OK tool loop SPAWN/BOOST/INJECT_COLOR/STUB + HUD 14 tools 5 modes")
	return true

func _check_predation() -> bool:
	var predation: Script = load("res://scripts/system/Predation.gd") as Script
	var physics: Script = load("res://scripts/system/CellPhysics.gd") as Script
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	cells.call("append_cell", 0, Vector2(100, 100), 1.0, 0)
	cells.call("append_cell", 1, Vector2(104, 100), 0.6, 0)
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	intents[0 * 6 + 2] = 1.0
	intents[1 * 6 + 2] = -1.0
	cells.set("behavior_intents", intents)
	var events: Array = predation.call("resolve_predation", cells, physics, 0.8, 0.35, 14.0, 0.25)
	if events.size() != 1:
		push_error("SmokeTest: predation event count = %d" % events.size())
		return false
	var event: Dictionary = events[0]
	if int(event.get("predator", -1)) != 0 or int(event.get("prey", -1)) != 1:
		push_error("SmokeTest: predation predator/prey mismatch")
		return false
	var gain: float = float(event.get("gain", 0.0))
	var loss: float = float(event.get("loss_to_detritus", 0.0))
	if absf(gain - 0.2) > 0.0001 or absf(loss - 0.05) > 0.0001:
		push_error("SmokeTest: predation energy split gain=%.4f loss=%.4f" % [gain, loss])
		return false
	var energies: PackedFloat32Array = cells.get("cell_energy")
	if absf(float(energies[0]) - 1.2) > 0.0001 or absf(float(energies[1]) - 0.35) > 0.0001:
		push_error("SmokeTest: predation energy transfer mismatch")
		return false
	var events_again: Array = predation.call("resolve_predation", cells, physics, 0.8, 0.35, 14.0, 0.25)
	if events_again.size() != 1:
		push_error("SmokeTest: predation not repeatable")
		return false
	print("SmokeTest: OK predation intent->transfer gain=0.2 loss=0.05 deterministic")
	return true

func _check_energy_ledger() -> bool:
	var ledger_script: Script = load("res://scripts/system/EnergyLedger.gd") as Script
	var ledger: RefCounted = ledger_script.new() as RefCounted
	ledger.call("set_balance", "E_external", 10.0)
	ledger.call("record", "TOOL_TO_ENV", "E_external", "E_env", 2.0, "t1")
	ledger.call("record", "ENV_TO_BIO", "E_env", "E_bio", 1.5, "t2")
	ledger.call("record", "BIO_TO_BIO", "E_bio", "E_bio", 0.4, "t3")
	ledger.call("record", "BIO_TO_ENV", "E_bio", "E_detritus", 0.1, "t4")
	if absf(float(ledger.call("total")) - 10.0) > 0.000001:
		push_error("SmokeTest: ledger total drifted")
		return false
	if not bool(ledger.call("assert_conservation", 0.001)):
		push_error("SmokeTest: ledger self-consistency failed")
		return false
	var snap: Dictionary = ledger.call("get_snapshot")
	if int(snap.get("entries", 0)) != 4 or int(snap.get("violations", 0)) != 0:
		push_error("SmokeTest: ledger snapshot mismatch")
		return false
	print("SmokeTest: OK energy ledger E_total invariant + self-consistency")
	return true

func _check_predation_integration() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var cells: RefCounted = manager.get("cells")
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var a: int = int(manager.call("register_zygote", 1, 0, -1, genome, Vector2(250, 250), 1.0, 0))
	var b: int = int(manager.call("register_zygote", 2, 1, -1, genome, Vector2(254, 250), 0.6, 0))
	if a < 0 or b < 0 or int(cells.call("size")) != 2:
		push_error("SmokeTest: predation integration setup failed")
		instance.queue_free()
		return false
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	intents[a * 6 + 2] = 1.0
	intents[b * 6 + 2] = -1.0
	cells.set("behavior_intents", intents)
	manager.call("_apply_predation", 1.0 / 60.0)
	var pred: Dictionary = manager.call("get_predation_diagnostics")
	if int(pred.get("events", 0)) < 1 or float(pred.get("energy_transferred", 0.0)) <= 0.0:
		push_error("SmokeTest: integrated predation did not fire")
		instance.queue_free()
		return false
	var ledger: Dictionary = manager.call("get_energy_ledger_snapshot")
	if int(ledger.get("entries", 0)) < 1:
		push_error("SmokeTest: integrated ledger has no entries")
		instance.queue_free()
		return false
	instance.queue_free()
	print("SmokeTest: OK integrated predation events=%d ledger_entries=%d" % [int(pred.get("events", 0)), int(ledger.get("entries", 0))])
	return true
