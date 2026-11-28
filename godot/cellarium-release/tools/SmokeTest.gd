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
	"res://scripts/core/data/CellShape.gd",
	"res://scripts/core/data/CellArray.gd",
	"res://scripts/core/data/OrganismStore.gd",
	"res://scripts/core/data/DevelopmentRules.gd",
	"res://scripts/core/data/FoodStore.gd",
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
	"res://scripts/system/Mutation.gd",
	"res://scripts/system/SpeciesSystem.gd",
	"res://scripts/system/StatisticsSystem.gd",
	"res://scripts/system/SaveManager.gd",
	"res://scripts/system/PerfProbe.gd",
	"res://scripts/system/FrameProfiler.gd",
	"res://scripts/rendering/CellariumView.gd",
	"res://scripts/rendering/DishLayer.gd",
	"res://scripts/rendering/LinkLayer.gd",
	"res://scripts/rendering/CellLayer.gd",
	"res://scripts/rendering/CellBatchRenderer.gd",
	"res://scripts/rendering/PostprocessLayer.gd",
	"res://scripts/rendering/CellVisualCatalog.gd",
	"res://scripts/rendering/CellView.gd",
	"res://scripts/rendering/CellSceneRenderer.gd",
	"res://scripts/rendering/CellPolygonBatchRenderer.gd",
	"res://scripts/rendering/CameraController.gd",
	"res://scripts/rendering/CellMembrane.gd",
	"res://scripts/rendering/CellContactChords.gd",
	"res://scripts/ui/ToolCatalog.gd",
	"res://scripts/ui/DevEditorPanel.gd",
	"res://scripts/ui/PanelChrome.gd",
	"res://scripts/rendering/FieldLayer.gd",
	"res://scripts/rendering/FoodLayer.gd",
	"res://scripts/rendering/SelectionLayer.gd",
	"res://scripts/ui/GameHUD.gd",
	"res://scripts/ui/SemanticRegistry.gd",
	"res://scripts/agent/AgentBridge.gd",
	"res://tools/GpuSamplingTest.gd",
	"res://tools/ViewCostProbe.gd",
	"res://scripts/ui/AnalysisPanel.gd",
	"res://scripts/core/data/PreviewWorld.gd",
	"res://scripts/ui/GenomePreview.gd",
	"res://tools/PreviewReplicaProbe.gd",
	"res://tools/DivisionAlignmentProbe.gd",
	"res://tools/PerfBreakdownProbe.gd",
	"res://tools/BatchRenderProbe.gd",
	"res://tools/NativeParityProbe.gd",
	"res://tools/MetabolismBreakdownProbe.gd",
	"res://tools/MetabolismHotspotsParityProbe.gd",
	"res://tools/PhysicsStepParityProbe.gd",
	"res://tools/BehaviorSignalParityProbe.gd",
	"res://tools/RenderCacheParityProbe.gd",
	"res://tools/CollectInputsGridParityProbe.gd",
	"res://tools/CellBatchOriginParityProbe.gd",
	"res://tools/DenseClusterProbe.gd",
	"res://tools/WindowPerfScenario.gd",
	"res://tools/WindowPerfBenchmark.gd",
	"res://tools/HighSpeedPerfBenchmark.gd",
	"res://tools/ThreadPrototype.gd",
	"res://tools/ThreadPrototypeSnapshot.gd",
	"res://tools/WorkerSimProbe.gd",
	"res://tools/SimWorkerProbe.gd",
	"res://tools/ProdSimWorkerProbe.gd",
	"res://scripts/system/SimWorker.gd",
	"res://scripts/system/SimSnapshot.gd",
	"res://scripts/system/WorkerSimEngine.gd",
	"res://tools/WorkerEngineProbe.gd",
	"res://tools/ShardProbe.gd",
	"res://tools/CollisionSoftProbe.gd",
	"res://tools/CollisionRealProbe.gd",
	"res://tools/MetabEnvMicroProbe.gd",
	"res://tools/LedgerBatchParityProbe.gd",
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
	var cell_scene: PackedScene = ResourceLoader.load("res://scenes/cells/CellBase.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if cell_scene == null:
		push_error("SmokeTest: CellBase.tscn not loadable")
		failures += 1
	else:
		print("SmokeTest: OK res://scenes/cells/CellBase.tscn")
	var preview_scene: PackedScene = ResourceLoader.load("res://scenes/ui/GenomePreview.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if preview_scene == null:
		push_error("SmokeTest: GenomePreview.tscn not loadable")
		failures += 1
	else:
		print("SmokeTest: OK res://scenes/ui/GenomePreview.tscn")
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
	if not await _check_environment_settings():
		failures += 1
	if not _check_gpu_sampling_api():
		failures += 1
	if not _check_full_tick_determinism():
		failures += 1
	if not _check_phase_three_metabolism():
		failures += 1
	if not _check_signal_secretion():
		failures += 1
	if not await _check_tool_command_loop():
		failures += 1
	if not await _check_microscope_layout():
		failures += 1
	if not _check_predation():
		failures += 1
	if not _check_energy_ledger():
		failures += 1
	if not await _check_predation_integration():
		failures += 1
	if not _check_mutation():
		failures += 1
	if not _check_species_system():
		failures += 1
	if not _check_statistics():
		failures += 1
	if not _check_save_restore():
		failures += 1
	if not _check_semantic_registry():
		failures += 1
	if not _check_agent_bridge():
		failures += 1
	if not _check_terrain_and_t07():
		failures += 1
	if not _check_branching():
		failures += 1
	if not _check_t11_timing():
		failures += 1
	if not _check_perf_probe():
		failures += 1
	if not await _check_batch_renderer():
		failures += 1
	if not await _check_cell_scene_renderer():
		failures += 1
	if not await _check_shared_chords():
		failures += 1
	if not await _check_tangent_contact_stability():
		failures += 1
	if not _check_no_precontact_flatten():
		failures += 1
	if not await _check_multicellular_cooperation():
		failures += 1
	if not _check_cell_membrane():
		failures += 1
	if not await _check_camera_speed_editor():
		failures += 1
	if not await _check_multicell_editor():
		failures += 1
	if not await _check_shape_radius_and_motion():
		failures += 1
	if not await _check_lifecycle_and_injectors():
		failures += 1
	if not await _check_dev_editor_landing():
		failures += 1
	if not await _check_ui_chrome_and_filters():
		failures += 1
	if not await _check_v0141_food_and_photosynthesis():
		failures += 1
	if not await _check_v0141_energy_flow_diagnostics():
		failures += 1
	if not await _check_v0141_glue_link():
		failures += 1
	if not await _check_v0150_gene_save_roundtrip():
		failures += 1
	if not await _check_v0160_macro_editor_fields():
		failures += 1
	if not await _check_v0160_runtime_phenotype():
		failures += 1
	if not await _check_v0170_mode_editor_and_preview():
		failures += 1
	if not await _check_v0170_mode_remove():
		failures += 1
	if not await _check_v0170_runtime_transfer_and_modes():
		failures += 1
	if not await _check_v0180_population_limits():
		failures += 1
	if not await _check_v0190_energy_radius_relaxation():
		failures += 1
	if not await _check_v0210_division_doubling_and_split_shape():
		failures += 1
	if not await _check_v0220_no_depth_gate():
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
	if same_org.call("get_position", 0).distance_to(same_org.call("get_position", 1)) < 3.999:
		push_error("SmokeTest: same-organism cells must also separate")
		return false
	# 连锁重叠：外细胞把中间细胞推入同簇后，单轮修正不够，必须多轮重建 pair。
	var chain: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	chain.call("append_cell", 0, Vector2(0.0, 0.0), 0.1, 0)
	chain.call("append_cell", 0, Vector2(2.0, 0.0), 0.1, 0)
	chain.call("append_cell", 0, Vector2(4.0, 0.0), 0.1, 0)
	physics.call("resolve_collisions", chain, 2.0)
	if _min_alive_distance(chain) < 3.99:
		push_error("SmokeTest: chained overlap was not fully resolved")
		return false
	print("SmokeTest: OK all-cell collision resolution / same-organism separation / chained overlap")
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
	# 演示体按发育程序逐 tick 展开，断言时可能为 1~4 个细胞，但只能有一个个体。
	if int(manager.call("get_organism_count")) != 1 or int(cells.call("size")) < 1 or int(cells.call("size")) > 4:
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
	var flat_outputs: PackedFloat32Array = PackedFloat32Array()
	flat_outputs.resize(int(second_cells.call("size")) * 6)
	if not bool(behavior.call("compute_outputs_flat", second_cells, environment, flat_outputs)):
		push_error("SmokeTest: flat neural hot path rejected valid cells")
		return false
	for cell_index in range(int(second_cells.call("size"))):
		for output_index in range(6):
			if not is_equal_approx(replay_a[cell_index][output_index], flat_outputs[cell_index * 6 + output_index]):
				push_error("SmokeTest: flat neural hot path diverged from reference")
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
	var diagnostics: Dictionary = field.call("get_backend_diagnostics")
	if diagnostics.get("backend", "") != "cpu":
		push_error("SmokeTest: explicit CPU backend selection was ignored")
		return false
	for key in ["gpu_tick_count", "gpu_fallback_count", "gpu_upload_usec", "gpu_dispatch_usec", "gpu_readback_usec", "gpu_avg_tick_usec", "dispatch_groups", "readback_bytes"]:
		if not diagnostics.has(key):
			push_error("SmokeTest: backend diagnostics lost key " + str(key))
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

	# v0.14.0：非零平流必须仍走双线性。取 tick 前状态，用旧公式算一格再与 tick 后对比。
	var parity_field: RefCounted = script.new() as RefCounted
	parity_field.call("configure", 8, Vector2.ZERO, 20.0, PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0]), false)
	parity_field.call("set_advection", Vector2(0.35, -0.2))
	parity_field.call("add_source", 0, 4, 4, 0.25)
	var before_channels: Array = (parity_field.get("channels") as Array).duplicate(true)
	var before_sources: Array = (parity_field.get("_pending_sources") as Array).duplicate(true)
	parity_field.call("diffuse_tick")
	var advected_state: Array[PackedFloat32Array] = parity_field.call("get_state_snapshot")
	var parity_ok: bool = true
	for channel_index in range(5):
		var expected: float = _legacy_diffuse_cell(parity_field, channel_index, 4, 4, before_channels, before_sources)
		if not is_equal_approx(expected, advected_state[channel_index][4 * 8 + 4]):
			parity_ok = false
			break
	if not parity_ok:
		push_error("SmokeTest: nonzero-advection diffusion must still use bilinear sampling")
		return false
	print("SmokeTest: OK five-channel CPU field / circular mask / source injection / nutrient accounting / diffusion parity")
	return true

## 旧版 _sample_grid + 扩散公式，仅用于 v0.14.0 快速路径等价性回归。
func _legacy_diffuse_cell(field: RefCounted, channel: int, x: int, y: int, before_channels: Array, before_sources: Array) -> float:
	var resolution: int = int(field.get("resolution"))
	var channels_data: Array = before_channels
	var mask: PackedByteArray = field.get("dish_mask") as PackedByteArray
	var terrain: PackedByteArray = field.get("terrain_mask") as PackedByteArray
	var source: PackedFloat32Array = (before_sources as Array)[channel] as PackedFloat32Array
	var diffusion: Array[float] = [0.08, 0.16, 0.12, 0.0, 0.05]
	var decay: Array[float] = [0.004, 0.002, 0.003, 0.0, 0.02]
	var advection_value: Vector2 = field.get("advection") as Vector2
	var active_count: int = resolution * resolution
	var active := func(index: int) -> bool:
		if index < 0 or index >= active_count or mask[index] == 0:
			return false
		if terrain.size() == active_count and terrain[index] != 0:
			return false
		return true
	var center_value: float = (channels_data[channel] as PackedFloat32Array)[y * resolution + x]
	var laplacian: float = 0.0
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or ny < 0 or nx >= resolution or ny >= resolution:
			continue
		var neighbor_index: int = ny * resolution + nx
		if active.call(neighbor_index):
			laplacian += (channels_data[channel] as PackedFloat32Array)[neighbor_index] - center_value
	# 复刻 _sample_grid(channel, Vector2(x,y) - advection)
	var grid_position: Vector2 = Vector2(x, y) - advection_value
	var bounded: Vector2 = grid_position.clamp(Vector2.ZERO, Vector2.ONE * float(resolution - 1))
	var base_x: int = floori(bounded.x)
	var base_y: int = floori(bounded.y)
	var fraction: Vector2 = bounded - Vector2(base_x, base_y)
	var weighted_sum: float = 0.0
	var weight_total: float = 0.0
	for offset_y in range(2):
		for offset_x in range(2):
			var gx: int = mini(base_x + offset_x, resolution - 1)
			var gy: int = mini(base_y + offset_y, resolution - 1)
			var index_value: int = gy * resolution + gx
			if not active.call(index_value):
				continue
			var weight: float = (1.0 - fraction.x if offset_x == 0 else fraction.x) * (1.0 - fraction.y if offset_y == 0 else fraction.y)
			weighted_sum += (channels_data[channel] as PackedFloat32Array)[index_value] * weight
			weight_total += weight
	var advected: float = weighted_sum / weight_total if weight_total > 0.0 else 0.0
	return maxf(0.0, advected + diffusion[channel] * laplacian - decay[channel] * center_value + source[y * resolution + x])

func _check_environment_settings() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("SmokeTest: environment settings scene missing")
		return false
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var field: RefCounted = env.get("field") as RefCounted
	var settings: Dictionary = env.call("get_environment_settings") as Dictionary
	for key in ["light_source_mode", "light_range", "light_angle_deg", "light_falloff", "food_spawn_amount", "food_lump_radius", "food_layer"]:
		if not settings.has(key):
			push_error("SmokeTest: environment settings missing key " + key)
			instance.queue_free(); return false

	# Macro 式空间光照：边缘定向点光的近源侧必须明显亮于对侧。
	env.set("light_source_mode", 1)
	env.set("light_range", 1.2)
	env.set("light_angle_deg", 0.0)
	env.set("light_falloff", 0.5)
	env.set("light_intensity", 1.0)
	if not bool(env.call("apply_light_intensity")):
		push_error("SmokeTest: spatial light settings not applied")
		instance.queue_free(); return false
	var bright_position: Vector2 = Vector2(250.0 + 240.0 * 0.7, 250.0)
	var dark_position: Vector2 = Vector2(250.0 - 240.0 * 0.7, 250.0)
	var sampling_positions: Array[Vector2] = [bright_position, dark_position]
	env.call("begin_field_sampling", sampling_positions)
	var bright_sample: PackedFloat32Array = env.call("sample_fields", bright_position)
	var dark_sample: PackedFloat32Array = env.call("sample_fields", dark_position)
	if bright_sample.size() < 4 or dark_sample.size() < 4 or bright_sample[3] <= dark_sample[3] + 0.05:
		push_error("SmokeTest: spatial light must have near/far gradient")
		instance.queue_free(); return false

	# 确定型食物源：同一 tick 重放必须得到同一场 hash，且确实向营养场注入质量。
	env.set("nutrient_density", 0.0)
	env.set("food_spawn_amount", 0.2)
	env.set("food_lump_radius", 2)
	env.call("apply_environment_preset")
	env.call("apply_nutrient_sources", 42)
	var first_hash: int = int(field.call("get_state_hash"))
	env.call("apply_environment_preset")
	env.call("apply_nutrient_sources", 42)
	var second_hash: int = int(field.call("get_state_hash"))
	if first_hash != second_hash:
		push_error("SmokeTest: nutrient sources must be deterministic")
		instance.queue_free(); return false
	env.call("advance_field_tick")
	if field.call("get_total_nutrient") <= 0.0:
		push_error("SmokeTest: nutrient sources did not add food")
		instance.queue_free(); return false
	var food_layer: Node = instance.get_node_or_null("DishView/FoodLayer")
	if food_layer == null or not bool(food_layer.call("is_enabled")):
		push_error("SmokeTest: food layer missing or disabled")
		instance.queue_free(); return false
	food_layer.call("mark_dirty")
	if int(food_layer.call("get_last_dot_count")) <= 0:
		push_error("SmokeTest: food sources must produce visible dots")
		instance.queue_free(); return false

	# v0.14.0：Cell Lab 方法食物实体池——定长、质量衰减、池尾交换、存档 payload。
	var store: RefCounted = env.call("get_food_store") as RefCounted
	if store == null or int(store.call("active_count")) <= 0:
		push_error("SmokeTest: food entity pool empty after deterministic spawn")
		instance.queue_free(); return false
	if int(store.call("capacity")) <= 0 or int(store.call("capacity")) == int(store.call("active_count")):
		push_error("SmokeTest: food pool must be preallocated fixed capacity")
		instance.queue_free(); return false
	var entity_mass_before: float = float(store.call("get_mass", 0))
	env.call("advance_food_entities", 1.0 / 60.0)
	if float(store.call("get_mass", 0)) >= entity_mass_before:
		push_error("SmokeTest: food entity mass must decay each tick")
		instance.queue_free(); return false
	var payload: Dictionary = store.call("to_payload") as Dictionary
	if payload.is_empty() or int(payload.get("capacity", -1)) != int(store.call("capacity")):
		push_error("SmokeTest: food entity payload missing")
		instance.queue_free(); return false
	var spawned_mass: float = entity_mass_before
	for decay_index in range(64):
		env.call("advance_food_entities", 1.0 / 60.0)
	if int(store.call("active_count")) < 1:
		push_error("SmokeTest: food pool should still hold entities after 64 ticks")
		instance.queue_free(); return false

	# 环境设置页：分组标题与滚动容器存在；光场层用 shader texture 平滑绘制。
	var rows: Control = instance.get_node_or_null("UI/HUD/SubstratePanel/ChromeRoot/Panel/EnvironmentScroll/SubstrateRows") as Control
	if rows == null or rows.get_child_count() < 16:
		push_error("SmokeTest: environment settings rows missing")
		instance.queue_free(); return false
	var labels_text: String = ""
	for child in rows.get_children():
		if child is Label:
			labels_text += (child as Label).text + "|"
	if not labels_text.contains("食物") or not labels_text.contains("光照") or not labels_text.contains("氧气"):
		push_error("SmokeTest: environment settings sections missing")
		instance.queue_free(); return false
	var field_layer: Node = instance.get_node_or_null("DishView/FieldLayer")
	var field_rect: Node = field_layer.get_node_or_null("FieldRect") if field_layer != null else null
	if field_rect == null or field_rect.get("material") == null:
		push_error("SmokeTest: smooth field shader rect missing")
		instance.queue_free(); return false

	instance.queue_free()
	print("SmokeTest: OK environment settings / spatial light / deterministic food sources / smooth field layer")
	return true

## 阶段10：批量采样 API 在 CPU 回退路径必须与逐点 sample 完全一致，诊断字段齐全。
func _check_gpu_sampling_api() -> bool:
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var field: RefCounted = script.new() as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([1.0, 273.0, 0.21, 0.3, 0.05])
	field.call("configure", 16, Vector2.ZERO, 40.0, defaults, false)
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(12.0, 3.0), Vector2(-20.0, 8.0)]
	var batch: Array[PackedFloat32Array] = field.call("sample_cells", positions)
	if batch.size() != positions.size():
		push_error("SmokeTest: batch sampling lost positions")
		return false
	for index in range(positions.size()):
		if batch[index] != field.call("sample", positions[index]):
			push_error("SmokeTest: batch sampling must match point sampling on CPU fallback")
			return false
	var empty_positions: Array[Vector2] = []
	var empty_batch: Array[PackedFloat32Array] = field.call("sample_cells", empty_positions)
	if not empty_batch.is_empty():
		push_error("SmokeTest: empty sampling request must return empty result")
		return false
	var info: Dictionary = field.call("get_backend_diagnostics")
	for key in ["gpu_sample_count", "gpu_sample_cells", "gpu_delta_count", "gpu_full_readback_count", "legacy_full_field_bytes", "gpu_sampling_active"]:
		if not info.has(key):
			push_error("SmokeTest: stage10 diagnostics lost key " + str(key))
			return false
	if int(info.get("gpu_sampling_active", 1)) != 0:
		push_error("SmokeTest: CPU fallback must not claim GPU sampling")
		return false
	print("SmokeTest: OK batch field sampling API / CPU fallback parity")
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

	# 颜色注射：显式指定类型 6（吞噬细胞），验证写入的是用户所选而非轮转/随机。
	bus.call("enqueue", {"type": "INJECT_COLOR", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world", "color_type": 6})
	bus.call("execute_tick_commands", 3)
	if int(cells.get("cell_type")[spawned_index]) != 6:
		push_error("SmokeTest: INJECT_COLOR did not apply chosen type")
		instance.queue_free()
		return false

	var diag: Dictionary = manager.get("tool_diagnostics")
	if int(diag.get("SPAWN", 0)) < 1 or int(diag.get("BOOST", 0)) < 1 or int(diag.get("INJECT_COLOR", 0)) < 1:
		push_error("SmokeTest: tool diagnostics not incremented")
		instance.queue_free()
		return false

	# SELECT 现为真实选择集工具（阶段5），验证写入 selection
	bus.call("enqueue", {"type": "SELECT", "position": Vector2.ZERO, "delta": Vector2(0, 48), "kind": "world"})
	bus.call("execute_tick_commands", 4)
	if int(diag.get("SELECT", 0)) < 1:
		push_error("SmokeTest: SELECT tool not counted")
		instance.queue_free()
		return false

	# 冻结档点击：HUD → CommandBus → 立即 flush，合成器必须能落点且可见。
	var batch: Node = instance.get_node_or_null("DishView/CellBatch")
	if batch == null:
		push_error("SmokeTest: CellBatch node missing")
		instance.queue_free()
		return false
	var before_hud_spawn: int = int(cells.call("size"))
	if not bool(hud.call("world_action", Vector2(250, 250), Vector2.ZERO)):
		push_error("SmokeTest: HUD world_action rejected SPAWN")
		instance.queue_free()
		return false
	if int(cells.call("size")) != before_hud_spawn:
		push_error("SmokeTest: HUD SPAWN mutated state before flush")
		instance.queue_free()
		return false
	instance.call("_flush_commands_if_paused")
	if int(cells.call("size")) != before_hud_spawn + 1:
		push_error("SmokeTest: frozen-mode HUD SPAWN did not place cell")
		instance.queue_free()
		return false
	await process_frame
	if int(batch.call("get_instance_count")) < int(cells.call("size")):
		push_error("SmokeTest: spawned cell not rendered after flush")
		instance.queue_free()
		return false

	# 越界 SPAWN 必须钳制到皿内。
	var dish_center: Vector2 = manager.get("dish_center")
	var dish_radius: float = float(manager.get("dish_radius"))
	var cell_radius_value: float = float(manager.get("cell_radius"))
	var allowed_radius: float = maxf(1.0, dish_radius - maxf(cell_radius_value, 1.0))
	bus.call("enqueue", {"type": "SPAWN", "position": dish_center + Vector2(1000.0, 0.0), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 5)
	var clamped_index: int = int(cells.call("size")) - 1
	var clamped_pos: Vector2 = Vector2(float(cells.get("cell_pos_x")[clamped_index]), float(cells.get("cell_pos_y")[clamped_index]))
	if clamped_pos.distance_to(dish_center) > allowed_radius + 0.01:
		push_error("SmokeTest: out-of-dish SPAWN was not clamped")
		instance.queue_free()
		return false
	# 皿壁碰撞：把细胞强推到皿外，下一物理 tick 必须投回内壁。
	var px: PackedFloat32Array = cells.get("cell_pos_x")
	var py: PackedFloat32Array = cells.get("cell_pos_y")
	var ppx: PackedFloat32Array = cells.get("cell_prev_x")
	var ppy: PackedFloat32Array = cells.get("cell_prev_y")
	px[clamped_index] = dish_center.x + dish_radius + 50.0
	py[clamped_index] = dish_center.y
	ppx[clamped_index] = px[clamped_index] - 2.0
	ppy[clamped_index] = py[clamped_index]
	cells.set("cell_pos_x", px)
	cells.set("cell_pos_y", py)
	cells.set("cell_prev_x", ppx)
	cells.set("cell_prev_y", ppy)
	manager.call("advance_physics_tick", 1.0 / 60.0)
	var wall_pos: Vector2 = Vector2(float(cells.get("cell_pos_x")[clamped_index]), float(cells.get("cell_pos_y")[clamped_index]))
	if wall_pos.distance_to(dish_center) > allowed_radius + 0.01:
		push_error("SmokeTest: cell escaped dish wall")
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
	print("SmokeTest: OK tool loop SPAWN/BOOST/INJECT_COLOR/SELECT + frozen click + HUD 14 tools 5 modes")
	return true

func _check_microscope_layout() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("SmokeTest: microscope layout scene missing")
		return false
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var panel: Control = instance.get_node_or_null("UI/HUD/MicroscopePanel") as Control
	var lens: HBoxContainer = instance.get_node_or_null("UI/HUD/MicroscopePanel/ChromeRoot/Panel/Content/LensRow") as HBoxContainer
	var view: HBoxContainer = instance.get_node_or_null("UI/HUD/MicroscopePanel/ChromeRoot/Panel/Content/ViewRow") as HBoxContainer
	var status: Control = instance.get_node_or_null("UI/HUD/StatusBar") as Control
	if panel == null or lens == null or view == null or status == null:
		push_error("SmokeTest: microscope layout nodes missing")
		instance.queue_free()
		return false
	if lens.get_child_count() != 5 or view.get_child_count() != 4:
		push_error("SmokeTest: lens/view button count mismatch")
		instance.queue_free()
		return false
	var substrate_rows: Control = instance.get_node_or_null("UI/HUD/SubstratePanel/ChromeRoot/Panel/EnvironmentScroll/SubstrateRows") as Control
	if substrate_rows == null or substrate_rows.get_child_count() <= 0:
		push_error("SmokeTest: substrate rows missing")
		instance.queue_free()
		return false
	if instance.get_node_or_null("UI/HUD/SubstratePanel/ChromeRoot/Panel/Title") != null:
		push_error("SmokeTest: substrate title must not overlap rows in MarginContainer")
		instance.queue_free()
		return false
	var panel_rect: Rect2 = panel.get_global_rect()
	var lens_rect: Rect2 = lens.get_global_rect()
	var status_rect: Rect2 = status.get_global_rect()
	if lens_rect.end.x > panel_rect.end.x + 0.5:
		push_error("SmokeTest: lens row overflows microscope panel")
		instance.queue_free()
		return false
	if panel_rect.end.y > status_rect.position.y + 0.5:
		push_error("SmokeTest: microscope panel overlaps status bar")
		instance.queue_free()
		return false
	var last_button: Control = lens.get_child(lens.get_child_count() - 1) as Control
	if last_button == null or last_button.get_global_rect().end.x > lens_rect.end.x + 0.5:
		push_error("SmokeTest: rightmost lens button is clipped")
		instance.queue_free()
		return false
	print("SmokeTest: OK microscope layout / lens buttons visible / status bar clear")
	instance.queue_free()
	await process_frame
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

func _check_mutation() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var mutation: Script = load("res://scripts/system/Mutation.gd") as Script
	var base: RefCounted = genome_script.new() as RefCounted
	base.set("traits", PackedByteArray([10, 20, 30, 40, 50, 60, 0, 1]))
	base.set("loci", PackedByteArray([1, 2, 3, 4, 5, 6]))
	base.call("set_development_program", [{"opcode": 0, "a": 1, "b": 2, "c": 3}])
	var m1: RefCounted = mutation.call("mutate", base, 1, -1, 100, 1.0)
	var m2: RefCounted = mutation.call("mutate", base, 1, -1, 100, 1.0)
	if m1 == null or m2 == null or not bool(m1.call("is_valid")):
		push_error("SmokeTest: mutation produced invalid genome")
		return false
	if m1.call("hash") != m2.call("hash"):
		push_error("SmokeTest: mutation not deterministic for same seed")
		return false
	var changed_sample: RefCounted = null
	for tick in range(500):
		var sample: RefCounted = mutation.call("mutate", base, tick + 1, -1, 1, 1.0)
		if sample != null and sample.call("hash") != base.call("hash"):
			changed_sample = sample
			break
	if changed_sample == null:
		push_error("SmokeTest: no mutation observed across 500 seeded trials")
		return false
	var d_same: float = genome_script.call("distance", base, base)
	var d_other: float = genome_script.call("distance", base, changed_sample)
	if d_same != 0.0 or d_other <= 0.0:
		push_error("SmokeTest: genome distance invalid same=%.2f other=%.2f" % [d_same, d_other])
		return false
	var traits_before: PackedByteArray = base.get("traits")
	if int(traits_before[0]) != 10:
		push_error("SmokeTest: mutation mutated the source genome")
		return false
	print("SmokeTest: OK mutation deterministic distance(%.2f) source-immutable" % d_other)
	return true

func _check_species_system() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var species_script: Script = load("res://scripts/system/SpeciesSystem.gd") as Script
	var sys: RefCounted = species_script.new() as RefCounted
	sys.call("configure", 6.0, 10)
	var base: RefCounted = genome_script.new() as RefCounted
	base.set("traits", PackedByteArray([10, 20, 30, 40, 50, 60, 0, 1]))
	base.set("loci", PackedByteArray([1, 2, 3, 4]))
	base.call("set_development_program", [])
	var founder: int = int(sys.call("register_founder", base, 0))
	if founder != 0 or int(sys.call("species_count")) != 1:
		push_error("SmokeTest: species founder setup failed")
		return false
	var near: RefCounted = genome_script.new() as RefCounted
	near.set("traits", PackedByteArray([10, 20, 30, 40, 50, 60, 0, 2]))
	near.set("loci", PackedByteArray([1, 2, 3, 4]))
	near.call("set_development_program", [])
	if int(sys.call("classify", near, 0, 5)) != 0:
		push_error("SmokeTest: near genome should stay in founder species")
		return false
	var far: RefCounted = genome_script.new() as RefCounted
	far.set("traits", PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]))
	far.set("loci", PackedByteArray([9, 9, 9, 9, 9, 9]))
	far.set("mutation_rate_exp", 50)
	far.call("set_development_program", [{"opcode": 1, "a": 1, "b": 1, "c": 1}])
	var new_species: int = int(sys.call("classify", far, 0, 5))
	if new_species <= 0 or int(sys.call("species_count")) != 2:
		push_error("SmokeTest: far genome should speciate from founder")
		return false
	var far2: RefCounted = genome_script.new() as RefCounted
	far2.set("traits", PackedByteArray([2, 2, 2, 2, 2, 2, 2, 2]))
	far2.set("loci", PackedByteArray([8, 8, 8, 8, 8, 8]))
	far2.set("mutation_rate_exp", 60)
	far2.call("set_development_program", [{"opcode": 2, "a": 2, "b": 2, "c": 2}])
	if int(sys.call("classify", far2, 0, 8)) != new_species:
		push_error("SmokeTest: second speciation within cooldown should be gated")
		return false
	sys.call("record_birth", new_species, 20)
	sys.call("update_population", new_species, 3)
	sys.call("record_death", new_species, 1, 30)
	sys.call("mark_extinct", new_species, 40)
	var archive: Dictionary = sys.call("get_archive", new_species)
	if archive.is_empty() or int(archive.get("peak_population", 0)) != 3 or int(archive.get("main_death_cause", -1)) != 1:
		push_error("SmokeTest: extinction archive missing data")
		return false
	var events: Array = sys.call("get_events")
	if events.size() != 2:
		push_error("SmokeTest: expected SPECIATION + EXTINCTION events")
		return false
	var phylogeny: Dictionary = sys.call("export_phylogeny")
	if (phylogeny.get("nodes") as Array).size() != 2 or (phylogeny.get("edges") as Array).size() != 1 or (phylogeny.get("speciation_events") as Array).size() != 1:
		push_error("SmokeTest: phylogeny export must contain nodes, parent edge and speciation event")
		return false
	print("SmokeTest: OK species founder/classify/cooldown/extinction archive + phylogeny export")
	return true

func _check_statistics() -> bool:
	var stats_script: Script = load("res://scripts/system/StatisticsSystem.gd") as Script
	var stats: RefCounted = stats_script.new() as RefCounted
	stats.call("configure", 16, 10)
	stats.call("record_birth")
	stats.call("record_death", 3)
	for i in range(35):
		stats.call("advance_tick", {0: 3, 1: 1})
	if int(stats.call("sample_count")) != 3:
		push_error("SmokeTest: statistics sample count = %d" % int(stats.call("sample_count")))
		return false
	var series: Dictionary = stats.call("population_series")
	if not series.has(0) or (series[0] as Array).size() != 3:
		push_error("SmokeTest: population series missing species 0")
		return false
	var panel: Dictionary = stats.call("species_death_panel")
	if int(panel.get("deaths", 0)) != 1 or int((panel.get("death_causes", {}) as Dictionary).get("3", 0)) != 1:
		push_error("SmokeTest: death panel mismatch")
		return false
	var facts_a: Array = stats.call("generate_facts", {})
	if facts_a.is_empty():
		push_error("SmokeTest: no facts generated")
		return false
	stats.call("record_death", 1)
	for i in range(10):
		stats.call("advance_tick", {0: 3, 1: 1})
	var facts_b: Array = stats.call("generate_facts", {})
	if str(facts_a[0]) == str(facts_b[0]):
		push_error("SmokeTest: facts not data-driven (unchanged after death data changed)")
		return false
	var report: Dictionary = stats.call("export_report", {})
	if not report.has("population_series") or not report.has("facts"):
		push_error("SmokeTest: ecology report missing products")
		return false
	print("SmokeTest: OK statistics ring buffer / panel / data-driven facts")
	return true

## T08（§10）：存档 → 继续跑 → 读档 → 继续跑，两条路径 1000 tick 后状态一致。
func _check_save_restore() -> bool:
	var save_manager: Script = load("res://scripts/system/SaveManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var save_path: String = "user://cellarium_t08_roundtrip.gsave"
	var half_ticks: int = 500

	var first: Dictionary = _t08_make_world(genome_script)
	var first_env: Node = first["environment"]
	var first_manager: Node = first["manager"]
	for i in range(half_ticks * 2):
		first_manager.call("advance_physics_tick", 1.0 / 60.0)
		first_env.call("advance_field_tick")
	var first_state: Dictionary = _t08_world_state(first_manager, first_env)
	first_manager.free()
	first_env.free()

	var second: Dictionary = _t08_make_world(genome_script)
	var second_env: Node = second["environment"]
	var second_manager: Node = second["manager"]
	for i in range(half_ticks):
		second_manager.call("advance_physics_tick", 1.0 / 60.0)
		second_env.call("advance_field_tick")

	if not bool(second_manager.call("save_state_to_file", save_path)):
		push_error("SmokeTest: T08 save_state_to_file failed")
		second_manager.free()
		second_env.free()
		return false
	var loaded: Dictionary = save_manager.call("load_from_file", save_path) as Dictionary
	if loaded.is_empty() or int(loaded.get("sim_tick", -1)) != half_ticks:
		push_error("SmokeTest: T08 file round-trip lost sim_tick")
		second_manager.free()
		second_env.free()
		return false
	# 故意污染当前状态，确认 restore 真的写回而不是空操作
	var live_cells: RefCounted = second_manager.get("cells") as RefCounted
	var energy_snapshot: PackedFloat32Array = live_cells.get("cell_energy") as PackedFloat32Array
	if energy_snapshot.size() > 0:
		energy_snapshot[0] = 999.0
		live_cells.set("cell_energy", energy_snapshot)
	if not bool(second_manager.call("restore_state", loaded)):
		push_error("SmokeTest: T08 restore_state failed")
		second_manager.free()
		second_env.free()
		return false

	for i in range(half_ticks):
		second_manager.call("advance_physics_tick", 1.0 / 60.0)
		second_env.call("advance_field_tick")
	var second_state: Dictionary = _t08_world_state(second_manager, second_env)
	second_manager.free()
	second_env.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	for key in first_state:
		if str(first_state[key]) != str(second_state.get(key, "<missing>")):
			push_error("SmokeTest: T08 divergence on %s: %s vs %s" % [key, str(first_state[key]), str(second_state.get(key, "<missing>"))])
			return false
	if not bool(first_state.get("ledger_consistent", false)):
		push_error("SmokeTest: T08 ledger conservation broken after 1000 ticks")
		return false
	print("SmokeTest: OK T08 save/load round-trip, 1000-tick dual-path state match")
	return true

func _check_semantic_registry() -> bool:
	var registry: Script = load("res://scripts/ui/SemanticRegistry.gd") as Script
	registry.call("set_strict", false)
	registry.call("reset")
	var button_a: Button = Button.new()
	var button_b: Button = Button.new()
	registry.call("set_log_duplicates", false)  # 重复注册是本次测试的预期断言，静默其日志
	# 用 ui://test/ 独立前缀，避免与 GameHUD 的 ui://sim/ 重注册清理冲突
	if not bool(registry.call("register", "ui://test/tool/a", button_a)):
		push_error("SemanticRegistry: first registration must succeed")
		return false
	if not bool(registry.call("register", "ui://test/tool/b", button_b)):
		push_error("SemanticRegistry: second registration must succeed")
		return false
	if int(registry.call("count")) != 2:
		push_error("SemanticRegistry: expected 2 registered controls")
		return false
	if registry.call("find", "ui://test/tool/a") != button_a:
		push_error("SemanticRegistry: find must return registered control")
		return false
	# 重复 ID 必须被拒绝（非严格模式仅计数，不 assert）
	if bool(registry.call("register", "ui://test/tool/a", button_b)):
		push_error("SemanticRegistry: duplicate id must be rejected")
		return false
	if int(registry.call("duplicate_count")) != 1:
		push_error("SemanticRegistry: duplicate count mismatch")
		return false
	# 命名空间校验
	for valid_id in ["ui://sim/mode/0", "tool://tool_01", "cmd://sim.set_speed", "org://18422:3", "sp://A-02"]:
		if not bool(registry.call("is_valid_id", valid_id)):
			push_error("SemanticRegistry: valid id rejected %s" % valid_id)
			return false
	if bool(registry.call("is_valid_id", "bad://x")) or bool(registry.call("is_valid_id", "")):
		push_error("SemanticRegistry: invalid id accepted")
		return false
	# click 转发：Button 无 act 时回退 emit pressed（用 Dictionary 引用避免 int 按值捕获）
	var counter: Dictionary = {"n": 0}
	button_a.pressed.connect(func() -> void: counter["n"] = int(counter["n"]) + 1)
	if not bool(registry.call("click", "ui://test/tool/a")) or int(counter["n"]) != 1:
		push_error("SemanticRegistry: click must dispatch to control")
		return false
	registry.call("unregister", "ui://test/tool/a")
	if registry.call("find", "ui://test/tool/a") != null:
		push_error("SemanticRegistry: unregister failed")
		return false
	button_a.queue_free()
	button_b.queue_free()
	registry.call("set_strict", true)
	registry.call("set_log_duplicates", true)
	registry.call("reset")
	print("SmokeTest: OK semantic id registry / duplicate guard / namespace / click dispatch")
	return true

## T10：Agent 17 接口 + 权限门禁 + JSON Lines 端到端。
func _check_agent_bridge() -> bool:
	var bridge_script: Script = load("res://scripts/agent/AgentBridge.gd") as Script
	var bridge: RefCounted = bridge_script.new() as RefCounted
	var upstream: Array = bridge.get("UPSTREAM_COMMANDS")
	if upstream.size() != 17:
		push_error("SmokeTest: AgentBridge must expose 17 upstream commands, got %d" % upstream.size())
		return false
	# 未启用时全部拒绝
	var disabled_response: Dictionary = bridge.call("handle_request", {"id": 1, "cmd": "sim.get_state", "token": "x"})
	if bool(disabled_response.get("ok", false)) or str((disabled_response.get("error", {}) as Dictionary).get("code", "")) != "BRIDGE_DISABLED":
		push_error("SmokeTest: AgentBridge must be disabled by default")
		return false
	if not bool(bridge.call("enable", "test-token", "readonly")):
		push_error("SmokeTest: AgentBridge enable failed")
		return false
	# token 校验
	var bad_token: Dictionary = bridge.call("handle_request", {"id": 2, "cmd": "sim.get_state", "token": "wrong"})
	if bool(bad_token.get("ok", false)):
		push_error("SmokeTest: AgentBridge token mismatch must be rejected")
		return false
	# 绑定最小依赖：用独立节点，避免污染场景测试
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager._ready()
	var bus: Node = load("res://scripts/core/command/CommandBus.gd").new() as Node
	var tick: Node = load("res://scripts/core/tick/TickCore.gd").new() as Node
	bridge.call("configure", bus, manager, environment, tick)

	# readonly：查询可用、写入被拒
	var query: Dictionary = bridge.call("handle_request", {"id": 3, "cmd": "sim.get_state", "token": "test-token"})
	if not bool(query.get("ok", false)) or int((query.get("data", {}) as Dictionary).get("schema_version", 0)) != 1:
		push_error("SmokeTest: AgentBridge readonly query failed")
		return false
	var forbidden: Dictionary = bridge.call("handle_request", {"id": 4, "cmd": "organism.spawn", "token": "test-token", "args": {"x": 0, "y": 0, "count": 1}})
	if bool(forbidden.get("ok", false)) or str((forbidden.get("error", {}) as Dictionary).get("code", "")) != "FORBIDDEN":
		push_error("SmokeTest: AgentBridge readonly must forbid writes")
		return false
	# sandbox：写入入队
	bridge.call("enable", "test-token", "sandbox")
	var spawned: Dictionary = bridge.call("handle_request", {"id": 5, "cmd": "organism.spawn", "token": "test-token", "args": {"x": 10, "y": 10, "count": 1}})
	if not bool(spawned.get("ok", false)) or int(bus.call("pending_count")) < 1:
		push_error("SmokeTest: AgentBridge sandbox write must enqueue")
		return false
	# 执行队列 → 实际生成生物
	bus.call("execute_tick_commands", 1)
	manager.call("apply_command", {"type": "AGENT_SPAWN", "position": Vector2(10, 10), "args": {"count": 1}})
	# JSON Lines 批量
	var lines: Array[String] = [
		'{"id":6,"cmd":"sim.get_phylogeny","token":"test-token"}',
		'{"id":7,"cmd":"sim.get_ecology_report","token":"test-token"}',
		"not-json"
	]
	var responses: Array[String] = bridge.call("handle_lines", lines)
	if responses.size() != 3:
		push_error("SmokeTest: AgentBridge JSON Lines response count mismatch")
		return false
	var parsed_ok: Variant = JSON.parse_string(responses[0])
	if not (parsed_ok is Dictionary) or not bool((parsed_ok as Dictionary).get("ok", false)):
		push_error("SmokeTest: AgentBridge JSON Lines query failed")
		return false
	var parsed_bad: Variant = JSON.parse_string(responses[2])
	if not (parsed_bad is Dictionary) or bool((parsed_bad as Dictionary).get("ok", false)):
		push_error("SmokeTest: AgentBridge must reject malformed line")
		return false
	# 审计记录齐全
	if (bridge.call("audit_entries") as Array).size() < 4:
		push_error("SmokeTest: AgentBridge audit trail too short")
		return false
	manager.free()
	environment.free()
	bus.free()
	tick.free()
	print("SmokeTest: OK AgentBridge 17 upstream / permission gate / JSON Lines / audit")
	return true

## T07 + 地形：地形笔刷真实写入 mask；干预前后 E_total 不变。
func _check_terrain_and_t07() -> bool:
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager._ready()
	var field: RefCounted = environment.get("field")
	if int(environment.call("get_terrain_solid_count")) != 0:
		push_error("SmokeTest: terrain mask must start empty")
		manager.free(); environment.free(); return false
	var changed: int = int(environment.call("paint_terrain", Vector2(250, 250), 2, true))
	if changed <= 0 or int(environment.call("get_terrain_solid_count")) != changed:
		push_error("SmokeTest: terrain paint did not write mask")
		manager.free(); environment.free(); return false
	# 固体格浓度必须清零且不参与扩散
	field.call("diffuse_tick")
	if float(field.call("get_total_nutrient")) < 0.0:
		push_error("SmokeTest: terrain diffusion produced negative field")
		manager.free(); environment.free(); return false
	var erased: int = int(environment.call("paint_terrain", Vector2(250, 250), 2, false))
	if erased <= 0 or int(environment.call("get_terrain_solid_count")) != 0:
		push_error("SmokeTest: terrain erase failed")
		manager.free(); environment.free(); return false
	# T07：干预工具前后 E_total 不变
	var ledger: RefCounted = manager.get("energy_ledger")
	var before: float = float(ledger.call("total"))
	manager.call("apply_command", {"type": "SPAWN", "position": Vector2(20, 20), "delta": Vector2.ZERO})
	manager.call("apply_command", {"type": "BOOST", "position": Vector2(20, 20), "delta": Vector2.ZERO})
	manager.call("apply_command", {"type": "INJECT_SUBSTANCE", "position": Vector2(30, 30), "delta": Vector2.ZERO})
	manager.call("apply_command", {"type": "TERRAIN_PAINT", "position": Vector2(40, 40), "delta": Vector2(2, 0)})
	var after: float = float(ledger.call("total"))
	if absf(after - before) > 0.01:
		push_error("SmokeTest: T07 E_total changed across interventions %.4f -> %.4f" % [before, after])
		manager.free(); environment.free(); return false
	if not bool(ledger.call("assert_conservation", 0.01)):
		push_error("SmokeTest: T07 ledger self-consistency failed")
		manager.free(); environment.free(); return false
	manager.free(); environment.free()
	print("SmokeTest: OK terrain mask paint/erase + T07 E_total invariant across tools")
	return true

## T09：分支演化——父存档不被修改，父 ID 链正确。
func _check_branching() -> bool:
	var save_manager: Script = load("res://scripts/system/SaveManager.gd") as Script
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager._ready()
	var parent_path: String = "user://cellarium_t09_parent.gsave"
	var fork_path: String = "user://cellarium_t09_fork.gsave"
	if not bool(manager.call("save_state_to_file", parent_path)):
		push_error("SmokeTest: T09 parent save failed")
		manager.free(); environment.free(); return false
	var parent_snapshot: Dictionary = save_manager.call("load_from_file", parent_path) as Dictionary
	var parent_tick: int = int(parent_snapshot.get("sim_tick", 0))
	# 父存档继续演化并再次保存前，先做分支：fork 写新文件、带 parent_archive_id
	var fork_snapshot: Dictionary = parent_snapshot.duplicate(true)
	fork_snapshot["parent_archive_id"] = "cellarium_t09_parent"
	if not bool(save_manager.call("save_to_file", fork_path, fork_snapshot)):
		push_error("SmokeTest: T09 fork save failed")
		manager.free(); environment.free(); return false
	var fork_loaded: Dictionary = save_manager.call("load_from_file", fork_path) as Dictionary
	if str(fork_loaded.get("parent_archive_id", "")) != "cellarium_t09_parent":
		push_error("SmokeTest: T09 parent id chain missing")
		manager.free(); environment.free(); return false
	# 父存档文件未被 fork 修改（tick 仍一致）
	var parent_reloaded: Dictionary = save_manager.call("load_from_file", parent_path) as Dictionary
	if int(parent_reloaded.get("sim_tick", -1)) != parent_tick or parent_reloaded.has("parent_archive_id"):
		push_error("SmokeTest: T09 parent archive was modified by fork")
		manager.free(); environment.free(); return false
	# 分支可独立继续跑：加载 fork 到 manager，推进后状态推进
	if not bool(manager.call("restore_state", fork_loaded)):
		push_error("SmokeTest: T09 fork restore failed")
		manager.free(); environment.free(); return false
	manager.call("advance_physics_tick", 1.0 / 60.0)
	if int(manager.get("_sim_tick")) != parent_tick + 1:
		push_error("SmokeTest: T09 fork cannot advance independently")
		manager.free(); environment.free(); return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(parent_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fork_path))
	manager.free(); environment.free()
	print("SmokeTest: OK T09 fork parent-id chain / parent immutable / branch advances")
	return true

func _t08_make_world(genome_script: Script) -> Dictionary:
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment.nutrient_density = 1.2
	environment.oxygen_fraction = 0.21
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 1000.0
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	manager.call("register_zygote", int(genome.call("hash")), 0, -1, genome, Vector2.ZERO, 0.8, 0)
	manager.get("species_system").call("register_founder", genome, 0)
	manager.get("statistics").call("record_birth")
	return {"environment": environment, "manager": manager}

func _t08_world_state(manager: Node, environment: Node) -> Dictionary:
	var species_system: RefCounted = manager.get("species_system") as RefCounted
	var statistics: RefCounted = manager.get("statistics") as RefCounted
	var ledger: RefCounted = manager.get("energy_ledger") as RefCounted
	return {
		"organism_hash": int(manager.call("get_state_hash")),
		"field_hash": int(environment.get("field").call("get_state_hash")),
		"sim_tick": int(manager.get("_sim_tick")),
		"genome_count": (manager.get("genomes") as Dictionary).size(),
		"species_count": int(species_system.call("species_count")),
		"species_events": (species_system.call("get_events") as Array).size(),
		"sample_count": int(statistics.call("sample_count")),
		"ledger_total": int(round(float(ledger.call("total")) * 1000000.0)),
		"ledger_consistent": bool(ledger.call("assert_conservation", 0.01)),
	}

## T11：倍速档位 / carry 结转 / 单帧上限 / 单步 / 不缩放 dt。
func _check_t11_timing() -> bool:
	var tick: Node = load("res://scripts/core/tick/TickCore.gd").new() as Node
	if not bool(tick.call("apply_speed", 32.0)):
		push_error("SmokeTest: T11 32x speed step rejected")
		tick.free(); return false
	if int(tick.call("get_neural_interval")) != 8 or int(tick.call("get_field_interval")) != 4 or int(tick.call("get_lod_level")) != 3:
		push_error("SmokeTest: T11 32x LOD intervals mismatch")
		tick.free(); return false
	if not bool(tick.call("apply_speed", 16.0)) or int(tick.call("get_field_interval")) != 2:
		push_error("SmokeTest: T11 16x field interval mismatch")
		tick.free(); return false
	if not bool(tick.call("apply_speed", 3.0)) or int(tick.call("get_lod_level")) != 0:
		push_error("SmokeTest: T11 3x should be full precision")
		tick.free(); return false
	# 单帧上限 12：模拟 32× delta=1/60 → 理论 32 tick，实跑 12，余量结转
	tick.call("apply_speed", 32.0)
	var observed: Array[int] = []
	tick.connect("tick_advanced", func(tick_index: int) -> void: observed.append(tick_index))
	tick.call("_process", 1.0 / 60.0)
	if observed.size() != 12:
		push_error("SmokeTest: T11 single frame must cap at 12 ticks, got %d" % observed.size())
		tick.free(); return false
	if int(tick.get("carry_ticks")) < 1:
		push_error("SmokeTest: T11 overflow must carry")
		tick.free(); return false
	# 落后提示：carry > 12 时 is_lagging
	if int(tick.get("carry_ticks")) <= 12 or not bool(tick.call("is_lagging")):
		push_error("SmokeTest: T11 lagging hint missing at 32x")
		tick.free(); return false
	# 后续帧继续消化 carry，不雪崩：再跑 3 帧，每帧仍 ≤12
	for i in range(3):
		observed.clear()
		tick.call("_process", 1.0 / 60.0)
		if observed.size() > 12:
			push_error("SmokeTest: T11 later frame exceeded cap")
			tick.free(); return false
	# step_once 绕过累加器
	var before_step: int = int(tick.get("tick_index"))
	observed.clear()
	tick.call("step_once")
	if int(tick.get("tick_index")) != before_step + 1 or observed.size() != 1:
		push_error("SmokeTest: T11 step_once must advance exactly one tick")
		tick.free(); return false
	# 倍速不改 dt：TICK_DT 恒定
	if not is_equal_approx(float(tick.get("TICK_DT")), 1.0 / 60.0):
		push_error("SmokeTest: T11 dt must never scale with speed")
		tick.free(); return false
	# 存档元数据往返
	var timing: Dictionary = tick.call("get_timing_snapshot")
	if int(timing.get("lod_level", -1)) != 3 or int(timing.get("neural_interval", -1)) != 8:
		push_error("SmokeTest: T11 timing snapshot missing LOD metadata")
		tick.free(); return false
	tick.call("restore_timing", timing)
	if int(tick.call("get_neural_interval")) != 8:
		push_error("SmokeTest: T11 timing restore failed")
		tick.free(); return false
	tick.free()
	print("SmokeTest: OK T11 speed steps / carry / frame cap / lag hint / step_once / dt invariant")
	return true

func _check_perf_probe() -> bool:
	var probe_script: Script = load("res://scripts/system/PerfProbe.gd") as Script
	var probe: RefCounted = probe_script.new() as RefCounted
	probe.call("configure", 8)
	for tick in range(12):
		probe.call("begin_tick")
		probe.call("begin", "physics")
		var spin: int = 0
		for i in range(100):
			spin += i
		probe.call("end", "physics")
		probe.call("end_tick")
	if int(probe.call("sample_count")) != 8:
		push_error("SmokeTest: PerfProbe ring buffer capacity mismatch")
		return false
	var averages: Dictionary = probe.call("averages") as Dictionary
	if not averages.has("physics") or float(averages["physics"]) <= 0.0:
		push_error("SmokeTest: PerfProbe physics stage not recorded")
		return false
	var csv: String = str(probe.call("export_csv"))
	if not csv.begins_with("tick,behavior,physics") or csv.split("\n").size() < 9:
		push_error("SmokeTest: PerfProbe CSV export malformed")
		return false
	probe.call("record_save", 12.5)
	if int((probe.call("get_metadata") as Dictionary).get("save_ms", 0.0)) != 12:
		push_error("SmokeTest: PerfProbe save timing mismatch")
		return false
	print("SmokeTest: OK PerfProbe ring buffer / stage timing / CSV export")
	return true

func _check_batch_renderer() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", true)
	root.add_child(instance)
	await process_frame
	await process_frame
	var batch: Node = instance.get_node_or_null("DishView/CellBatch")
	var post: Node = instance.get_node_or_null("UI/Postprocess")
	if batch == null or post == null:
		push_error("SmokeTest: batch renderer / postprocess nodes missing")
		instance.queue_free(); return false
	var instance_count: int = int(batch.call("get_instance_count"))
	if instance_count < 1:
		push_error("SmokeTest: CellBatchRenderer produced no instances")
		instance.queue_free(); return false
	# LOD 抽样上限
	batch.call("apply_lod", 3)
	batch.call("_rebuild")
	if int(batch.call("get_instance_count")) > 1000:
		push_error("SmokeTest: LOD 3 must cap instances at 1000")
		instance.queue_free(); return false
	# 后处理默认启用，16× 以上自动关
	if not bool(post.call("is_effectively_enabled")):
		push_error("SmokeTest: postprocess should be enabled at 1x")
		instance.queue_free(); return false
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.call("apply_speed", 16.0)
	await process_frame
	if not bool(post.call("is_auto_disabled")):
		push_error("SmokeTest: postprocess must auto-disable at 16x")
		instance.queue_free(); return false
	# CellLayer 已禁用，避免与批量层重复绘制
	var cell_layer: Node = instance.get_node("DishView/CellLayer")
	if bool(cell_layer.get("visible")):
		push_error("SmokeTest: legacy CellLayer must be hidden when batch renderer active")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK MultiMesh batch instances / LOD cap / postprocess auto-disable")
	return true

func _check_cell_scene_renderer() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", true)
	root.add_child(instance)
	await process_frame
	await process_frame
	var layer: Node = instance.get_node_or_null("DishView/CellSceneLayer")
	var batch: Node = instance.get_node_or_null("DishView/CellBatch")
	var manager: Node = instance.get_node_or_null("Simulation/OrganismManager")
	var bus: Node = instance.get_node_or_null("Simulation/CommandBus")
	var tick_core: Node = instance.get_node_or_null("Simulation/TickCore")
	if layer == null or batch == null or manager == null or bus == null or tick_core == null:
		push_error("SmokeTest: CellSceneLayer nodes missing")
		instance.queue_free(); return false
	# 冻结发育 tick，避免测试期间自动分裂改变预期细胞数。
	tick_core.set("running", false)
	var cells: RefCounted = manager.get("cells") as RefCounted
	var alive: PackedByteArray = cells.get("cell_alive")
	var expected: int = 0
	for flag in alive:
		if flag != 0:
			expected += 1
	if expected < 1:
		push_error("SmokeTest: no demo cell for scene renderer")
		instance.queue_free(); return false
	layer.call("mark_dirty")
	await process_frame
	if int(layer.call("get_active_count")) != expected:
		push_error("SmokeTest: CellSceneLayer active count mismatch expected=%d actual=%d" % [expected, int(layer.call("get_active_count"))])
		instance.queue_free(); return false
	if bool(batch.get("visible")):
		push_error("SmokeTest: MultiMesh layer must hide in scene-render range")
		instance.queue_free(); return false
	var first_view: Node2D = layer.get_child(0) as Node2D
	if first_view == null:
		push_error("SmokeTest: CellSceneLayer has no instantiated cell view")
		instance.queue_free(); return false
	var body: Polygon2D = first_view.get_node_or_null("Body") as Polygon2D
	var outline: Line2D = first_view.get_node_or_null("Outline") as Line2D
	var inner_ring: Line2D = first_view.get_node_or_null("InnerRing") as Line2D
	var nucleus: Polygon2D = first_view.get_node_or_null("Nucleus") as Polygon2D
	var organelle_root: Node2D = first_view.get_node_or_null("OrganelleRoot") as Node2D
	var organelle_count: int = 0
	if organelle_root != null:
		for child in organelle_root.get_children():
			if child is Polygon2D:
				organelle_count += 1
	if first_view == null or body == null or outline == null or inner_ring == null or nucleus == null:
		push_error("SmokeTest: CellBase.tscn instance missing procedural nodes")
		instance.queue_free(); return false
	if body.texture != null:
		push_error("SmokeTest: CellBase.tscn must not depend on guide-icon texture")
		instance.queue_free(); return false
	if organelle_count < 5:
		push_error("SmokeTest: procedural cell needs at least 5 organelles")
		instance.queue_free(); return false
	var initial_chord_count: int = int(first_view.call("get_chord_count"))
	var configured_segments: int = clampi(int(first_view.get("outline_segments")), 12, 64)
	var minimum_outline_points: int = 12 if initial_chord_count > 0 else configured_segments
	if body.polygon.size() < minimum_outline_points or int(first_view.call("get_outline_point_count")) < minimum_outline_points:
		push_error("SmokeTest: membrane outline not generated")
		instance.queue_free(); return false
	if inner_ring.points.size() < minimum_outline_points or nucleus.polygon.size() < 8:
		push_error("SmokeTest: inner ring / nucleus not generated")
		instance.queue_free(); return false
	# 极高碰撞速度下形变也必须受限，不能拉成夸张椭圆。
	first_view.call("apply_cell", Vector2(250, 250), 0, 1, 1.0, Vector2(1000.0, 0.0))
	var stretch_value: float = float(first_view.call("get_stretch"))
	var outline_points: PackedVector2Array = (first_view.get_node_or_null("Outline") as Line2D).points
	var min_y: float = outline_points[0].y
	var max_y: float = outline_points[0].y
	for point in outline_points:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var aspect: float = _x_span(outline_points) / maxf(0.001, max_y - min_y)
	if stretch_value > 0.081 or aspect > 1.2:
		push_error("SmokeTest: membrane stretch not bounded under collision velocity spike")
		instance.queue_free(); return false
	# 接触点压平：同一签名下，右侧接触方向必须把右侧膜向内拉。
	first_view.set("stretch_smoothing", 1.0)
	var no_contacts: Array[Vector2] = []
	var right_contact: Array[Vector2] = [Vector2.RIGHT]
	first_view.call("apply_cell", Vector2(250, 250), 0, 1, 1.0, Vector2.ZERO, no_contacts)
	var plain_points: PackedVector2Array = (first_view.get_node_or_null("Outline") as Line2D).points
	var plain_max_x: float = _max_x(plain_points)
	first_view.call("apply_cell", Vector2(250, 250), 0, 1, 1.0, Vector2.ZERO, right_contact)
	var flattened_points: PackedVector2Array = (first_view.get_node_or_null("Outline") as Line2D).points
	var flattened_max_x: float = _max_x(flattened_points)
	if flattened_max_x >= plain_max_x - 0.2:
		push_error("SmokeTest: contact point did not flatten membrane inward")
		instance.queue_free(); return false
	if int(first_view.call("get_contact_count")) != 1:
		push_error("SmokeTest: CellView did not retain contact direction")
		instance.queue_free(); return false
	# 接触面必须是浅而平的弧段，不是单点深 V 凹口。
	var flat_point_count: int = 0
	for point in flattened_points:
		if point.x > flattened_max_x - 0.15:
			flat_point_count += 1
	if flat_point_count < 4 or flattened_max_x < plain_max_x - 1.5:
		push_error("SmokeTest: contact flatten must be shallow and planar")
		instance.queue_free(); return false
	# 皿壁接触方向同样应该压平朝壁一侧的膜。
	var right_wall: Array[Vector2] = [Vector2.RIGHT]
	first_view.call("apply_cell", Vector2(250, 250), 0, 1, 1.0, Vector2.ZERO, no_contacts, no_contacts, right_wall)
	var wall_points: PackedVector2Array = (first_view.get_node_or_null("Outline") as Line2D).points
	if _max_x(wall_points) >= plain_max_x - 0.2:
		push_error("SmokeTest: dish wall contact did not flatten membrane inward")
		instance.queue_free(); return false
	if int(first_view.call("get_wall_contact_count")) != 1:
		push_error("SmokeTest: CellView did not retain wall contact direction")
		instance.queue_free(); return false
	first_view.call("apply_cell", Vector2(250, 250), 0, 1, 1.0, Vector2.ZERO, no_contacts)
	var catalog: RefCounted = load("res://scripts/rendering/CellVisualCatalog.gd").new() as RefCounted
	var color_a: Color = catalog.call("color", 0)
	var color_b: Color = catalog.call("color", 1)
	var accent: Color = catalog.call("accent_color", 0)
	if color_a == color_b or accent == color_a:
		push_error("SmokeTest: procedural cell palette must vary by type")
		instance.queue_free(); return false
	# 渲染层必须从 SoA 邻域派生接触方向，而不是只发位置。
	bus.call("enqueue", {"type": "SPAWN", "position": Vector2(258, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	await process_frame
	expected += 1
	if int(layer.call("get_active_count")) != expected:
		push_error("SmokeTest: CellSceneLayer did not refresh after SPAWN")
		instance.queue_free(); return false
	if int(layer.call("get_last_contact_count")) <= 0:
		push_error("SmokeTest: CellSceneLayer did not derive contact directions")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK procedural CellBase.tscn / contact flatten / elastic membrane / scene-render refresh")
	return true

## 共享弦端点契约：几何公式正确、双方端点世界坐标一致、遮挡剔除与膜裁剪生效。
func _check_shared_chords() -> bool:
	var helper: RefCounted = load("res://scripts/rendering/CellContactChords.gd").new() as RefCounted
	var radius: float = 7.0
	var left: Vector2 = Vector2(250.0, 250.0)
	var right: Vector2 = Vector2(258.0, 250.0)
	var chord: Dictionary = helper.call("circle_chord", left, radius, right, radius)
	if not bool(chord.get("valid", false)):
		push_error("SmokeTest: overlapping cells must produce a shared chord")
		return false
	var endpoint_a: Vector2 = chord["a"]
	var endpoint_b: Vector2 = chord["b"]
	if absf(endpoint_a.x - endpoint_b.x) > 0.01:
		push_error("SmokeTest: chord endpoints must be symmetric across center line")
		return false
	if absf(endpoint_a.x - 254.0) > 0.01:
		push_error("SmokeTest: chord midpoint must sit at the radical line")
		return false
	# 相切 / 分离不产生弦。
	var tangent: Dictionary = helper.call("circle_chord", Vector2.ZERO, radius, Vector2(radius * 2.0, 0.0), radius)
	if bool(tangent.get("valid", false)):
		push_error("SmokeTest: tangent circles must not produce a chord")
		return false
	# 碰撞钳位后中心距有 float32 抖动；相切附近的抖动不得生成弦，否则膜会逐帧闪动。
	for jitter in [-0.0005, -0.0001, 0.0001, 0.0005]:
		var jittered: Dictionary = helper.call(
			"circle_chord", Vector2.ZERO, radius, Vector2(radius * 2.0 + jitter, 0.0), radius
		)
		if bool(jittered.get("valid", false)):
			push_error("SmokeTest: tangent jitter must not produce a chord")
			return false
	# 超过接触下限的真实重叠仍必须生成弦。
	var shallow: Dictionary = helper.call(
		"circle_chord", Vector2.ZERO, radius, Vector2(radius * 2.0 - 0.5, 0.0), radius
	)
	if not bool(shallow.get("valid", false)):
		push_error("SmokeTest: real overlap must still produce a chord")
		return false
	# d26 遮挡判据：同一位置附近的两条弦，后一条应被判遮挡。
	var first: Dictionary = {"local_a": Vector2(-2.0, -1.0), "local_b": Vector2(-2.0, 1.0)}
	var second: Dictionary = {"local_a": Vector2(-1.0, -1.0), "local_b": Vector2(-1.0, 1.0)}
	if not bool(helper.call("is_occluded", first, second)):
		push_error("SmokeTest: occluded chord must be culled by d26 criterion")
		return false
	var kept: Array = helper.call("cull_occluded", [first, second])
	if kept.size() != 1:
		push_error("SmokeTest: cull_occluded must drop the hidden chord")
		return false
	# 弦轮廓必须与输入顺序无关，且弦端点就是膜顶点；这是消除接触点抽搐的核心契约。
	var left_chord: Dictionary = {"a": Vector2(-6.0, -2.0), "b": Vector2(-6.0, 2.0), "peer": 0}
	var right_chord: Dictionary = {"a": Vector2(6.0, -2.0), "b": Vector2(6.0, 2.0), "peer": 1}
	var unit_forward: Array = helper.call(
		"make_unit_chords", [left_chord, right_chord], Vector2.ZERO, 0.0, 7.0
	)
	var prepared_forward: Array = helper.call("prepare_for_render", unit_forward)
	var outline_forward: PackedVector2Array = helper.call("build_outline", prepared_forward, 3)
	var unit_reverse: Array = helper.call(
		"make_unit_chords", [right_chord, left_chord], Vector2.ZERO, 0.0, 7.0
	)
	var prepared_reverse: Array = helper.call("prepare_for_render", unit_reverse)
	var outline_reverse: PackedVector2Array = helper.call("build_outline", prepared_reverse, 3)
	if outline_forward.size() < 4 or outline_forward.size() != outline_reverse.size():
		push_error("SmokeTest: chord outline must be stable under input permutation")
		return false
	for index in range(outline_forward.size()):
		if outline_forward[index].distance_to(outline_reverse[index]) > 0.0001:
			push_error("SmokeTest: chord outline order changed with neighbor order")
			return false
		if absf(outline_forward[index].length() - 1.0) > 0.001:
			push_error("SmokeTest: chord outline vertices must lie on the unit circle")
			return false
	for chord_entry in prepared_forward:
		var outline_endpoint_a: Vector2 = chord_entry.get("local_a", Vector2.ZERO)
		var outline_endpoint_b: Vector2 = chord_entry.get("local_b", Vector2.ZERO)
		var found_a: bool = false
		var found_b: bool = false
		for point in outline_forward:
			if point.distance_to(outline_endpoint_a) < 0.0001:
				found_a = true
			if point.distance_to(outline_endpoint_b) < 0.0001:
				found_b = true
		if not found_a or not found_b:
			push_error("SmokeTest: chord endpoints must be membrane vertices")
			return false
	# 多接触 / 深度重叠：邻居顺序不得改变轮廓，且轮廓永不退化为线段或消失。
	var multi_world: Array = []
	for index in range(5):
		var angle_value: float = deg_to_rad(float(index) * 72.0)
		var peer_position: Vector2 = Vector2(cos(angle_value), sin(angle_value)) * 12.0
		var entry: Dictionary = helper.call("circle_chord", Vector2.ZERO, radius, peer_position, radius)
		if bool(entry.get("valid", false)):
			entry["peer"] = index
			entry["kind"] = 0
			multi_world.append(entry)
	var multi_forward: Array = helper.call("make_unit_chords", multi_world, Vector2.ZERO, 0.0, radius)
	var reversed_world: Array = multi_world.duplicate()
	reversed_world.reverse()
	var multi_reverse: Array = helper.call("make_unit_chords", reversed_world, Vector2.ZERO, 0.0, radius)
	var multi_outline_forward: PackedVector2Array = helper.call(
		"build_outline", helper.call("prepare_for_render", multi_forward), 3
	)
	var multi_outline_reverse: PackedVector2Array = helper.call(
		"build_outline", helper.call("prepare_for_render", multi_reverse), 3
	)
	if multi_outline_forward.size() < 4 or multi_outline_forward.size() != multi_outline_reverse.size():
		push_error("SmokeTest: multi-contact outline must be stable under neighbor permutation")
		return false
	for index in range(multi_outline_forward.size()):
		if multi_outline_forward[index].distance_to(multi_outline_reverse[index]) > 0.0001:
			push_error("SmokeTest: multi-contact outline changed with neighbor order")
			return false
	if float(helper.call("polygon_area", multi_outline_forward)) < 0.5:
		push_error("SmokeTest: multi-contact outline collapsed")
		return false
	if not bool(helper.call("contains_origin", multi_outline_forward)):
		push_error("SmokeTest: multi-contact outline must contain the cell center")
		return false
	var deep_world: Array = []
	for index in range(3):
		var deep_angle: float = deg_to_rad(float(index) * 120.0)
		var deep_peer: Vector2 = Vector2(cos(deep_angle), sin(deep_angle)) * radius
		var deep_entry: Dictionary = helper.call("circle_chord", Vector2.ZERO, radius, deep_peer, radius)
		if bool(deep_entry.get("valid", false)):
			deep_entry["peer"] = index
			deep_world.append(deep_entry)
	var deep_prepared: Array = helper.call(
		"prepare_for_render", helper.call("make_unit_chords", deep_world, Vector2.ZERO, 0.0, radius)
	)
	var deep_outline: PackedVector2Array = helper.call("build_outline", deep_prepared, 3)
	if deep_outline.size() < 3 or float(helper.call("polygon_area", deep_outline)) < 0.5:
		push_error("SmokeTest: deeply overlapped cell outline must not disappear")
		return false
	if not bool(helper.call("contains_origin", deep_outline)):
		push_error("SmokeTest: deeply overlapped outline must contain the cell center")
		return false
	# 皿壁弦：细胞外缘越过皿壁时必须生成，且端点仍在细胞圆上。
	var wall_chord_value: Dictionary = helper.call(
		"wall_chord", Vector2(16.5, 250.0), radius, Vector2(250.0, 250.0), 240.0
	)
	if not bool(wall_chord_value.get("valid", false)):
		push_error("SmokeTest: wall overlap must produce a dish chord")
		return false
	if absf((wall_chord_value["a"] as Vector2).distance_to(Vector2(16.5, 250.0)) - radius) > 0.01:
		push_error("SmokeTest: wall chord endpoint must lie on the cell circle")
		return false
	# 皿壁钳位同样有抖动：正好贴壁不得生成弦，真实越界才生成。
	for wall_jitter in [-0.0005, 0.0005]:
		var wall_tangent: Dictionary = helper.call(
			"wall_chord", Vector2(17.0 + wall_jitter, 250.0), radius, Vector2(250.0, 250.0), 240.0
		)
		if bool(wall_tangent.get("valid", false)):
			push_error("SmokeTest: tangent wall jitter must not produce a chord")
			return false
	# 渲染层每对细胞只算一次，双方视图收到完全相同的世界端点。
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	await process_frame
	var layer: Node = instance.get_node_or_null("DishView/CellSceneLayer")
	var manager: Node = instance.get_node_or_null("Simulation/OrganismManager")
	var tick_core: Node = instance.get_node_or_null("Simulation/TickCore")
	if layer == null or manager == null or tick_core == null:
		push_error("SmokeTest: shared chord scene nodes missing")
		instance.queue_free(); return false
	tick_core.set("running", false)
	# 显式放两枚相切细胞（间距 2r），避免演示体发育时序影响断言。
	var bus: Node = instance.get_node_or_null("Simulation/CommandBus")
	var base_position: Vector2 = Vector2(250.0, 250.0)
	bus.call("enqueue", {"type": "SPAWN", "position": base_position, "delta": Vector2.ZERO, "kind": "world"})
	bus.call("enqueue", {"type": "SPAWN", "position": base_position + Vector2(14.0, 0.0), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	await process_frame
	layer.call("mark_dirty")
	await process_frame
	if int(layer.call("get_last_chord_count")) != 0:
		push_error("SmokeTest: tangent cells must not produce a chord")
		instance.queue_free(); return false
	var live_cells: RefCounted = manager.get("cells") as RefCounted
	bus.call("enqueue", {"type": "SPAWN", "position": base_position + Vector2(3.0, 0.0), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	await process_frame
	layer.call("mark_dirty")
	await process_frame
	if int(layer.call("get_last_chord_count")) <= 0:
		push_error("SmokeTest: scene renderer did not derive shared chords")
		instance.queue_free(); return false
	# 取两个实例，验证弦端点在双方 chord 列表中成对出现（世界坐标完全一致）。
	var chord_counts: Array[int] = []
	var all_chords: Array = []
	for index in range(int(layer.call("get_active_count"))):
		var chord_view: Node2D = layer.get_child(index) as Node2D
		chord_counts.append(int(chord_view.call("get_chord_count")))
		for entry in (chord_view.get("_chords") as Array):
			all_chords.append(entry)
	if chord_counts.is_empty() or chord_counts.max() <= 0:
		push_error("SmokeTest: no CellView received chord endpoints")
		instance.queue_free(); return false
	var shared_pair_found: bool = false
	for i in range(all_chords.size()):
		var entry_i: Dictionary = all_chords[i]
		if int(entry_i.get("kind", -1)) == 2:
			continue
		for j in range(i + 1, all_chords.size()):
			var entry_j: Dictionary = all_chords[j]
			if int(entry_j.get("kind", -1)) == 2:
				continue
			if int(entry_i.get("peer", -2)) == int(entry_j.get("peer", -1)):
				continue
			var a_i: Vector2 = entry_i["a"]
			var a_j: Vector2 = entry_j["a"]
			var b_i: Vector2 = entry_i["b"]
			var b_j: Vector2 = entry_j["b"]
			if a_i.distance_to(a_j) < 0.0001 and b_i.distance_to(b_j) < 0.0001:
				shared_pair_found = true
				break
		if shared_pair_found:
			break
	if not shared_pair_found:
		push_error("SmokeTest: chord endpoints must be byte-identical across both touching cells")
		instance.queue_free(); return false
	# CellView 共享弦裁剪后仍保持足够轮廓点，且弦线段落在膜边界上。
	var view_with_chord: Node2D = null
	for index in range(chord_counts.size()):
		if chord_counts[index] > 0:
			view_with_chord = layer.get_child(index) as Node2D
			break
	if view_with_chord == null:
		push_error("SmokeTest: no view with chords")
		instance.queue_free(); return false
	# 接触轮廓不得随呼吸相位变化；同一批弦重复刷新应逐点一致。
	var outline_before: PackedVector2Array = (view_with_chord.get_node_or_null("Outline") as Line2D).points.duplicate()
	if outline_before.size() < 24:
		push_error("SmokeTest: contact outline must stay analytically smooth, points=%d" % outline_before.size())
		instance.queue_free(); return false
	view_with_chord.set("_shape_time", 1.2345)
	view_with_chord.call("_refresh_shape")
	var outline_after: PackedVector2Array = (view_with_chord.get_node_or_null("Outline") as Line2D).points
	if outline_before.size() != outline_after.size():
		push_error("SmokeTest: contact outline changed size with membrane phase")
		instance.queue_free(); return false
	for index in range(outline_before.size()):
		if outline_before[index].distance_to(outline_after[index]) > 0.001:
			push_error("SmokeTest: contact outline twitched with membrane phase")
			instance.queue_free(); return false
	# 新增：移除/恢复弦时不得切换点集，外膜始终是同一套解析圆采样。
	var cached_chords: Array = view_with_chord.get("_chords")
	view_with_chord.set("_chords", [])
	view_with_chord.call("_refresh_shape")
	var no_chord_outline: PackedVector2Array = (view_with_chord.get_node_or_null("Outline") as Line2D).points
	var configured_segments: int = clampi(int(view_with_chord.get("outline_segments")), 12, 64)
	if no_chord_outline.size() < configured_segments:
		push_error("SmokeTest: no-chord outline must stay analytic circle, points=%d" % no_chord_outline.size())
		instance.queue_free(); return false
	if helper.call("polygon_area", no_chord_outline) <= 1.0:
		push_error("SmokeTest: no-chord outline collapsed")
		instance.queue_free(); return false
	view_with_chord.set("_chords", cached_chords)
	view_with_chord.call("_refresh_shape")
	var restored_outline: PackedVector2Array = (view_with_chord.get_node_or_null("Outline") as Line2D).points
	if restored_outline.size() != outline_before.size():
		push_error("SmokeTest: chord/no-chord path switched point count")
		instance.queue_free(); return false
	# 渲染只读：反复刷新视图不得改变模拟状态 hash。
	var hash_before_render: int = int(manager.call("get_state_hash"))
	for index in range(chord_counts.size()):
		var refresh_view: Node2D = layer.get_child(index) as Node2D
		if refresh_view != null:
			refresh_view.call("_refresh_shape")
			refresh_view.call("_refresh_shape")
	var hash_after_render: int = int(manager.call("get_state_hash"))
	if hash_before_render != hash_after_render:
		push_error("SmokeTest: chord rendering must not change simulation state hash")
		instance.queue_free(); return false
	# 连续推进 tick：每帧所有可见膜都必须是闭合且非退化的多边形。
	tick_core.set("running", true)
	for step in range(30):
		tick_core.call("_process", 1.0 / 60.0)
		await process_frame
		for view_index in range(int(layer.call("get_active_count"))):
			var dynamic_view: Node2D = layer.get_child(view_index) as Node2D
			if dynamic_view == null:
				continue
			var dynamic_outline: PackedVector2Array = (dynamic_view.get_node_or_null("Outline") as Line2D).points
			if dynamic_outline.size() < 3 or float(helper.call("polygon_area", dynamic_outline)) < 5.0:
				push_error("SmokeTest: membrane outline degenerated during live ticks")
				instance.queue_free(); return false
	tick_core.set("running", false)
	var points: PackedVector2Array = (view_with_chord.get_node_or_null("Outline") as Line2D).points
	if points.size() < 4:
		push_error("SmokeTest: chord-clipped membrane lost its outline")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK shared chord geometry / culling / scene renderer distribution")
	return true

## 默认演示体：碰撞钳位后的中心距在 2r 附近抖动，膜不得在整圆与切平多边形间闪动。
func _check_tangent_contact_stability() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node_or_null("Simulation/OrganismManager")
	var renderer: Node = instance.get_node_or_null("DishView/CellSceneLayer")
	var tick_core: Node = instance.get_node_or_null("Simulation/TickCore")
	if manager == null or renderer == null or tick_core == null:
		push_error("SmokeTest: tangent stability scene missing nodes")
		instance.queue_free(); return false
	tick_core.set("running", false)
	var cells: RefCounted = manager.get("cells")
	var diameter: float = 14.0
	for tick in range(60):
		manager.call("advance_development_tick")
		manager.call("advance_physics_tick", 1.0 / 60.0)
		renderer.call("_rebuild")
		var closest: float = 1e9
		var count: int = int(cells.call("size"))
		for a in range(count):
			if int(cells.get("cell_alive")[a]) == 0:
				continue
			for b in range(a + 1, count):
				if int(cells.get("cell_alive")[b]) == 0:
					continue
				var distance: float = cells.call("get_position", a).distance_to(cells.call("get_position", b))
				closest = minf(closest, distance)
		if closest >= diameter - 0.01 and int(renderer.call("get_last_chord_count")) != 0:
			push_error("SmokeTest: tangent cells must not derive flickering chords")
			instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK tangent contact stability / no chord flicker")
	return true

## 细胞尚未接触（含皿壁）时不得按接触法线提前压平细胞膜。
func _check_no_precontact_flatten() -> bool:
	var cell_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var physics_script: Script = load("res://scripts/system/CellPhysics.gd") as Script
	var chords_script: Script = load("res://scripts/rendering/CellContactChords.gd") as Script
	var renderer_script: Script = load("res://scripts/rendering/CellSceneRenderer.gd") as Script
	var renderer: Node = renderer_script.new() as Node
	var cells: RefCounted = cell_script.new() as RefCounted
	cells.call("append_cell", 0, Vector2(250.0, 250.0), 1.0, 0)
	cells.call("append_cell", 0, Vector2(265.0, 250.0), 1.0, 0) # gap = 1
	var radius: float = 7.0
	var contact_range: float = radius * 2.0 + float(chords_script.call("contact_epsilon", radius))
	var no_links: PackedInt32Array = PackedInt32Array()
	var result: Dictionary = renderer.call(
		"_collect_contacts", cells, 0, physics_script.call("build_spatial_hash", cells),
		cells.get("cell_pos_x"), cells.get("cell_pos_y"), cells.get("cell_org_id"),
		no_links, no_links, contact_range
	)
	if (result.get("contacts", []) as Array).size() != 0:
		push_error("SmokeTest: cell must not flatten before touching")
		renderer.free(); return false
	cells.call("set_position", 1, Vector2(264.0, 250.0)) # gap = 0
	result = renderer.call(
		"_collect_contacts", cells, 0, physics_script.call("build_spatial_hash", cells),
		cells.get("cell_pos_x"), cells.get("cell_pos_y"), cells.get("cell_org_id"),
		no_links, no_links, contact_range
	)
	if (result.get("contacts", []) as Array).size() <= 0:
		push_error("SmokeTest: touching cells must still derive contact direction")
		renderer.free(); return false
	var wall_range: float = float(chords_script.call("contact_epsilon", radius))
	if (renderer.call("_collect_wall_contacts", Vector2(250.0 + 240.0 - radius - 1.0, 250.0),
		Vector2(250.0, 250.0), 240.0, radius, wall_range) as Array).size() != 0:
		push_error("SmokeTest: dish wall must not flatten cell before touching")
		renderer.free(); return false
	if (renderer.call("_collect_wall_contacts", Vector2(250.0 + 240.0 - radius, 250.0),
		Vector2(250.0, 250.0), 240.0, radius, wall_range) as Array).size() <= 0:
		push_error("SmokeTest: touching wall must derive contact direction")
		renderer.free(); return false
	renderer.free()
	print("SmokeTest: OK no pre-contact cell / wall flatten")
	return true

func _check_multicellular_cooperation() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", true)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var cells: RefCounted = manager.get("cells") as RefCounted
	# v0.34.0：默认演示已改为 M1 光合自分裂；本项专门验证 5 模式分化协作渲染，
	# 因此显式把 org 0 的基因组换成旧的 5 模式演示体（Genome.demo_modes 原样保留）。
	var gs: Script = load("res://scripts/core/data/Genome.gd") as Script
	var demo_genome: RefCounted = gs.new() as RefCounted
	demo_genome.set("flags", int(gs.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(gs.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	demo_genome.set("division_mass", 0.05)
	demo_genome.set("max_divisions", 3)
	demo_genome.set("max_cells_per_organism", 4)
	demo_genome.set("child_types", PackedByteArray([2, 4, 5, 10]))
	demo_genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	var demo_modes_fixed: Array[Dictionary] = []
	for mode_variant in gs.call("demo_modes"):
		var mode: Dictionary = (mode_variant as Dictionary).duplicate(true)
		mode["make_glue"] = true
		mode["child1_glue"] = true
		mode["child2_glue"] = true
		mode["max_connections"] = 8
		demo_modes_fixed.append(mode)
	demo_genome.call("set_modes", demo_modes_fixed)
	manager.get("genomes")[0] = demo_genome
	# v0.37.0：本测试绕过正常 API 直接替换 genomes[0]，需手动失效 native 代谢缓存
	# （正常路径 register/inject/mutate 内部已自动失效）。native 默认开启后必须有这一步。
	manager.call("_invalidate_native_metabolism_cache")
	tick_core.set("running", true)
	tick_core.call("clear_carry")
	# v0.17.0 演示体改为多模式基因驱动：无头快验临时把分裂 cooldown 降为 1 tick。
	manager.set("autonomous_division_cooldown", 1)
	# 3 次模式分裂生成 4 细胞 + 3 条黏附连接。
	for _frame in range(12):
		tick_core.call("_process", 1.0 / 60.0)
	await process_frame
	var alive: PackedByteArray = cells.get("cell_alive")
	var cell_type: PackedByteArray = cells.get("cell_type")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var alive_count: int = 0
	var type_set: Dictionary = {}
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		alive_count += 1
		type_set[int(cell_type[cell_index])] = true
	print("SmokeTest: demo development alive=%d links=%d types=%s" % [alive_count, link_a.size(), str(type_set)])
	if alive_count != 4 or link_a.size() != 3:
		push_error("SmokeTest: demo multicellular organism did not develop 4 cells / 3 links")
		instance.queue_free(); return false
	if not type_set.has(2) or not type_set.has(4) or not type_set.has(5):
		push_error("SmokeTest: demo organism must contain motion/energy/info cell roles")
		instance.queue_free(); return false
	var shape: RefCounted = load("res://scripts/core/data/CellShape.gd") as RefCounted
	var min_distance: float = _min_alive_distance(cells)
	if min_distance < float(shape.call("min_center_distance")) - 0.5:
		push_error("SmokeTest: demo multicellular cells overlap, min_distance=%.3f" % min_distance)
		instance.queue_free(); return false
	var link_layer: Node = instance.get_node("DishView/LinkLayer")
	var scene_layer: Node = instance.get_node("DishView/CellSceneLayer")
	if int(link_layer.call("get_rendered_link_count")) != 3:
		push_error("SmokeTest: LinkLayer did not render all adhesion bridges")
		instance.queue_free(); return false
	if int(scene_layer.call("get_last_adhesion_count")) <= 0:
		push_error("SmokeTest: CellSceneLayer did not derive adhesion contacts from links")
		instance.queue_free(); return false
	var catalog: RefCounted = load("res://scripts/rendering/CellVisualCatalog.gd").new() as RefCounted
	if str(catalog.call("role", 10)) != "稳态":
		push_error("SmokeTest: nitrocyte must map to homeostasis role")
		instance.queue_free(); return false
	if catalog.call("role_color", 2) == catalog.call("role_color", 4):
		push_error("SmokeTest: cooperation roles must have distinct colors")
		instance.queue_free(); return false
	# 把细胞推到皿壁附近：gap=1.0 时不得提前压平，真正贴壁时才派生接触方向。
	tick_core.set("running", false)
	var dish_center: Vector2 = manager.get("dish_center")
	var dish_radius: float = float(manager.get("dish_radius"))
	var radius: float = float(manager.get("cell_radius"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	pos_x[0] = dish_center.x + dish_radius - radius - 1.0
	pos_y[0] = dish_center.y
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	scene_layer.call("mark_dirty")
	await process_frame
	if int(scene_layer.call("get_last_wall_contact_count")) != 0:
		push_error("SmokeTest: dish wall contact must not appear before touching")
		instance.queue_free(); return false
	pos_x = cells.get("cell_pos_x")
	pos_x[0] = dish_center.x + dish_radius - radius
	cells.set("cell_pos_x", pos_x)
	scene_layer.call("mark_dirty")
	await process_frame
	if int(scene_layer.call("get_last_wall_contact_count")) <= 0:
		push_error("SmokeTest: CellSceneLayer did not derive dish wall contact")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK 4-cell cooperation demo / role palette / link bridges / wall contact")
	return true

func _min_alive_distance(cells: RefCounted) -> float:
	var alive: PackedByteArray = cells.get("cell_alive")
	var positions: PackedFloat32Array = cells.get("cell_pos_x")
	var positions_y: PackedFloat32Array = cells.get("cell_pos_y")
	var minimum: float = INF
	for a in range(alive.size()):
		if alive[a] == 0:
			continue
		for b in range(a + 1, alive.size()):
			if alive[b] == 0:
				continue
			var distance_value: float = Vector2(
				positions[b] - positions[a],
				positions_y[b] - positions_y[a]
			).length()
			minimum = minf(minimum, distance_value)
	return minimum

func _max_x(points: PackedVector2Array) -> float:
	if points.is_empty():
		return 0.0
	var maximum: float = points[0].x
	for point in points:
		maximum = maxf(maximum, point.x)
	return maximum

func _x_span(points: PackedVector2Array) -> float:
	if points.is_empty():
		return 0.0
	var minimum: float = points[0].x
	var maximum: float = points[0].x
	for point in points:
		minimum = minf(minimum, point.x)
		maximum = maxf(maximum, point.x)
	return maximum - minimum

func _check_cell_membrane() -> bool:
	var script: Script = load("res://scripts/rendering/CellMembrane.gd") as Script
	var first: RefCounted = script.new(12345) as RefCounted
	var same: RefCounted = script.new(12345) as RefCounted
	var other: RefCounted = script.new(54321) as RefCounted
	var outline_a: PackedVector2Array = first.call("outline", 0.0, 0.0)
	var outline_same: PackedVector2Array = same.call("outline", 0.0, 0.0)
	var outline_other: PackedVector2Array = other.call("outline", 0.0, 0.0)
	if outline_a.size() != 72 or outline_a != outline_same:
		push_error("SmokeTest: elastic membrane must be deterministic per signature")
		return false
	if outline_other == outline_a:
		push_error("SmokeTest: different cell signatures must differ in shape")
		return false
	var stretched: PackedVector2Array = first.call("outline", 0.0, 0.25)
	if _x_span(stretched) <= _x_span(outline_a) * 1.05:
		push_error("SmokeTest: elastic membrane must stretch along motion axis")
		return false
	if first.call("outline", 1.3, 0.0) == outline_a:
		push_error("SmokeTest: elastic membrane must breathe over time")
		return false
	print("SmokeTest: OK elastic membrane 12-point Catmull-Rom / harmonics / stretch")
	return true

func _check_camera_speed_editor() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var camera: Camera2D = instance.get_node("Camera2D") as Camera2D
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	var hud: Node = instance.get_node("UI/HUD")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var editor: Control = instance.get_node("UI/HUD/CellEditorPanel") as Control
	if camera == null or tick_core == null or hud == null or manager == null or bus == null or editor == null:
		push_error("SmokeTest: camera/speed/editor nodes missing")
		instance.queue_free(); return false

	# 1920x1080 下新增控件不重叠、不出界。
	var speed_panel: Control = instance.get_node("UI/HUD/SpeedPanel") as Control
	var editor_button: Control = instance.get_node("UI/HUD/CellEditorButton") as Control
	var feedback: Control = instance.get_node("UI/HUD/FeedbackLabel") as Control
	var microscope: Control = instance.get_node("UI/HUD/MicroscopePanel") as Control
	if speed_panel == null or editor_button == null or feedback == null or microscope == null:
		push_error("SmokeTest: HUD new panels missing")
		instance.queue_free(); return false
	editor.call("_on_default")
	editor.call("_on_default")
	if speed_panel.get_global_rect().intersects(editor_button.get_global_rect()):
		push_error("SmokeTest: speed panel overlaps cell editor button")
		instance.queue_free(); return false
	if editor.visible and (editor.get_global_rect().intersects(feedback.get_global_rect()) or editor.get_global_rect().intersects(microscope.get_global_rect())):
		push_error("SmokeTest: visible cell editor panel overlaps feedback or microscope")
		instance.queue_free(); return false
	var viewport_rect: Rect2 = instance.get_viewport().get_visible_rect()
	if not viewport_rect.encloses(speed_panel.get_global_rect()) or not viewport_rect.encloses(editor_button.get_global_rect()):
		push_error("SmokeTest: speed/editor controls outside viewport")
		instance.queue_free(); return false

	# 滚轮缩放：光标世界锚点不动；右键拖动改变视野。
	camera.call("reset_view")
	var anchor: Vector2 = Vector2(700, 320)
	var before: Vector2 = camera.call("screen_to_world", anchor)
	camera.call("zoom_at", anchor, 1.12)
	var after: Vector2 = camera.call("screen_to_world", anchor)
	if camera.zoom.x <= 2.0 or before.distance_to(after) > 0.05:
		push_error("SmokeTest: wheel zoom must keep cursor world anchor stable")
		instance.queue_free(); return false
	var camera_position: Vector2 = camera.position
	camera.call("pan_screen", Vector2(40.0, 0.0))
	if camera.position.distance_to(camera_position) < 1.0:
		push_error("SmokeTest: right-drag pan did not move camera")
		instance.queue_free(); return false
	var right_press: InputEventMouseButton = InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(400, 300)
	camera.call("_unhandled_input", right_press)
	if not bool(camera.get("dragging")):
		push_error("SmokeTest: right mouse button did not start camera drag")
		instance.queue_free(); return false
	var right_release: InputEventMouseButton = InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	camera.call("_unhandled_input", right_release)
	if bool(camera.get("dragging")):
		push_error("SmokeTest: right mouse button did not end camera drag")
		instance.queue_free(); return false

	# 倍速滑块 / 右侧输入双向同步。
	var slider: HSlider = instance.get_node("UI/HUD/SpeedPanel/ChromeRoot/Panel/SpeedRow/SpeedSlider") as HSlider
	var spin: SpinBox = instance.get_node("UI/HUD/SpeedPanel/ChromeRoot/Panel/SpeedRow/SpeedSpin") as SpinBox
	if slider == null or spin == null:
		push_error("SmokeTest: speed slider/spin missing")
		instance.queue_free(); return false
	slider.value = 8.0
	await process_frame
	if not is_equal_approx(float(tick_core.get("speed_scale")), 8.0) or not is_equal_approx(float(spin.value), 8.0):
		push_error("SmokeTest: speed slider did not drive TickCore + numeric input")
		instance.queue_free(); return false
	spin.value = 3.0
	await process_frame
	if not is_equal_approx(float(tick_core.get("speed_scale")), 3.0) or not is_equal_approx(float(slider.value), 3.0):
		push_error("SmokeTest: numeric speed input did not drive TickCore + slider")
		instance.queue_free(); return false
	spin.value = 30.0
	for _frame in range(10):
		tick_core.call("_process", 1.0 / 60.0)
	var lod_label: Label = instance.get_node("UI/HUD/SpeedPanel/ChromeRoot/Panel/SpeedRow/LodLabel") as Label
	if lod_label == null or not lod_label.text.contains("上限") or int(tick_core.get("carry_ticks")) <= 0:
		push_error("SmokeTest: saturated speed must surface frame-cap hint in UI")
		instance.queue_free(); return false

	# 编辑草案 → 合成器 → CommandBus → 落地基因组与类型。
	tick_core.set("running", false)
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var draft: RefCounted = genome_script.new() as RefCounted
	var traits: PackedByteArray = PackedByteArray([9, 4, 7, 2, 1, 6, 3, 5])
	draft.set("traits", traits)
	draft.set("respiration", 1)
	draft.set("loci", PackedByteArray())
	draft.call("set_development_program", [])
	if not bool(hud.call("set_draft", draft, 6)):
		push_error("SmokeTest: HUD rejected edited genome draft")
		instance.queue_free(); return false
	if not bool(hud.call("has_draft")):
		push_error("SmokeTest: HUD did not hold edited genome draft")
		instance.queue_free(); return false
	if not bool(hud.call("world_action", Vector2(250, 250), Vector2.ZERO)):
		push_error("SmokeTest: synthesizer rejected draft placement")
		instance.queue_free(); return false
	instance.call("_flush_commands_if_paused")
	var cells: RefCounted = manager.get("cells") as RefCounted
	var last_index: int = int(cells.call("size")) - 1
	if last_index < 0:
		push_error("SmokeTest: custom genome SPAWN created no cell")
		instance.queue_free(); return false
	var org_id: int = int(cells.get("cell_org_id")[last_index])
	var stored: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	if stored == null or PackedByteArray(stored.get("traits")) != traits:
		push_error("SmokeTest: synthesizer did not use edited genome")
		instance.queue_free(); return false
	if int(cells.get("cell_type")[last_index]) != 6:
		push_error("SmokeTest: synthesizer did not use edited cell type")
		instance.queue_free(); return false

	# 基因组注射：把另一份草案写入该个体。
	var injected: RefCounted = genome_script.new() as RefCounted
	injected.set("traits", PackedByteArray([8, 8, 8, 8, 8, 8, 8, 8]))
	injected.set("respiration", 1)
	injected.set("loci", PackedByteArray())
	injected.call("set_development_program", [])
	var codec: RefCounted = load("res://scripts/core/data/GenomeCodec.gd") as RefCounted
	bus.call("enqueue", {
		"type": "INJECT_GENOME",
		"position": Vector2(250, 250),
		"delta": Vector2.ZERO,
		"kind": "world",
		"genome_bytes": codec.call("encode", injected),
		"type_id": 3
	})
	bus.call("execute_tick_commands", 99)
	var rewritten: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	if rewritten == null or int(rewritten.get("traits")[0]) != 8 or int(cells.get("cell_type")[last_index]) != 3:
		push_error("SmokeTest: INJECT_GENOME did not rewrite target organism")
		instance.queue_free(); return false
	if int((manager.get("tool_diagnostics") as Dictionary).get("INJECT_GENOME", 0)) < 1:
		push_error("SmokeTest: INJECT_GENOME diagnostic not incremented")
		instance.queue_free(); return false

	instance.queue_free()
	print("SmokeTest: OK camera wheel/pan / speed slider+input / editor-synthesizer-genome-inject loop")
	return true

func _check_multicell_editor() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var editor: Control = instance.get_node("UI/HUD/CellEditorPanel") as Control
	var hud: Node = instance.get_node("UI/HUD")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	if editor == null or hud == null or manager == null or tick_core == null:
		push_error("SmokeTest: multicell editor nodes missing")
		instance.queue_free(); return false
	tick_core.set("running", false)
	# v0.15.0：默认基因模式，无指令序列；分裂质量 / 分裂即分化 / 黏附素连接。
	if not (editor.call("get_dev_program") as Array).is_empty():
		push_error("SmokeTest: gene-mode editor default must have empty dev_program")
		instance.queue_free(); return false
	var draft_ref: RefCounted = editor.call("get_draft") as RefCounted
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var glue_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	if (int(draft_ref.get("flags")) & gene_flag) == 0 or (int(draft_ref.get("flags")) & glue_flag) == 0:
		push_error("SmokeTest: default draft must be gene mode with adhesin")
		instance.queue_free(); return false
	# v0.34.0：默认草案改为 M1 光合（division_mass=0.05，真实能量上限下可分裂）。
	if absf(float(draft_ref.get("division_mass")) - 0.05) > 0.001 or int(draft_ref.get("max_divisions")) != 3:
		push_error("SmokeTest: default division mass / max divisions wrong")
		instance.queue_free(); return false
	editor.call("_on_macro_value_changed", 2.5, "division_mass")
	# v0.18.0：旧断言期望 4 细胞；显式把个体上限设回 4，无限增长另由新测试覆盖。
	editor.call("_on_macro_value_changed", 4.0, "max_cells_per_organism")
	if absf(float(draft_ref.get("division_mass")) - 2.5) > 0.001:
		push_error("SmokeTest: division mass slider did not write draft")
		instance.queue_free(); return false
	editor.call("_on_apply")
	if not bool(hud.call("has_draft")):
		push_error("SmokeTest: gene-mode editor did not load draft into synthesizer")
		instance.queue_free(); return false
	if not bool(hud.call("world_action", Vector2(250, 250), Vector2.ZERO)):
		push_error("SmokeTest: synthesizer rejected gene-mode draft")
		instance.queue_free(); return false
	instance.call("_flush_commands_if_paused")
	var cells: RefCounted = manager.get("cells") as RefCounted
	var last_index: int = int(cells.call("size")) - 1
	var org_id: int = int(cells.get("cell_org_id")[last_index])
	var stored: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	if stored == null or not bool(genome_script.call("is_gene_mode", stored)) or absf(float(stored.get("division_mass")) - 2.5) > 0.001:
		push_error("SmokeTest: gene parameters did not survive CommandBus/GNP1 (stored=%s mode=%s mass=%s)" % [
			str(stored != null), str(stored != null and bool(genome_script.call("is_gene_mode", stored))),
			str(float(stored.get("division_mass"))) if stored != null else "?"])
		instance.queue_free(); return false
	# 能量超过分裂质量时必须真分裂；黏附素让亲子自动连成 4 细胞 / 3 连接。
	manager.set("autonomous_division_cooldown", 1)
	var energies: PackedFloat32Array = cells.get("cell_energy")
	energies[last_index] = 20.0
	cells.set("cell_energy", energies)
	for _tick in range(24):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var organisms_snapshot: RefCounted = manager.get("organisms") as RefCounted
	var org_states: PackedByteArray = organisms_snapshot.get("org_state")
	if int(cells.call("size")) != 4 or link_a.size() != 3:
		push_error("SmokeTest: division mass did not produce 4 cells / 3 adhesin links (cells=%d links=%d org_state=%d energy=%s enabled=%s cooldown=%d)" % [
			int(cells.call("size")), link_a.size(), int(org_states[org_id]) if org_id < org_states.size() else -1,
			str(cells.get("cell_energy")), str(manager.get("autonomous_division_enabled")), int(manager.get("autonomous_division_cooldown"))])
		instance.queue_free(); return false
	var child_type_values: PackedByteArray = cells.get("cell_type")
	var mode_zero: Dictionary = (stored.get("modes") as Array)[0] as Dictionary
	var expected_child1: int = int(mode_zero.get("child1_type", 0))
	var expected_child2: int = int(mode_zero.get("child2_type", 2))
	var observed_types: Dictionary = {}
	for cell_index in range(int(cells.call("size"))):
		observed_types[int(child_type_values[cell_index])] = true
	if not observed_types.has(expected_child1) or not observed_types.has(expected_child2):
		push_error("SmokeTest: mode division must differentiate into child1/child2 types (expected %d/%d types=%s)" % [
			expected_child1, expected_child2, str(observed_types)])
		instance.queue_free(); return false
	var shape: RefCounted = load("res://scripts/core/data/CellShape.gd") as RefCounted
	if _min_alive_distance(cells) < float(shape.call("min_center_distance")) - 0.5:
		push_error("SmokeTest: gene-mode organism cells overlap")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK gene-mode editor / division mass / differentiation / adhesin / synthesizer round-trip")
	return true

func _check_shape_radius_and_motion() -> bool:
	var shape: RefCounted = load("res://scripts/core/data/CellShape.gd") as RefCounted
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var radius: float = float(manager.get("cell_radius"))
	if not is_equal_approx(radius, float(shape.call("rest_radius"))):
		push_error("SmokeTest: physics radius must equal CellShape.REST_RADIUS")
		instance.queue_free(); return false
	var cell_scene: PackedScene = load("res://scenes/cells/CellBase.tscn") as PackedScene
	var view: Node2D = cell_scene.instantiate() as Node2D
	if view == null or not is_equal_approx(float(view.call("get_collision_radius")), radius) or not is_equal_approx(float(view.call("get_visual_rest_radius")), radius):
		push_error("SmokeTest: elastic membrane radius must equal physics collision radius")
		instance.queue_free(); return false
	view.free()

	# 碰撞间距必须等于弹性膜静息直径。
	var cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	cells.call("append_cell", 0, Vector2.ZERO, 0.5, 0)
	cells.call("append_cell", 1, Vector2(2.0, 0.0), 0.5, 0)
	load("res://scripts/system/CellPhysics.gd").call("resolve_collisions", cells, radius)
	var separation: float = cells.call("get_position", 0).distance_to(cells.call("get_position", 1))
	if separation < float(shape.call("min_center_distance")) - 0.01:
		push_error("SmokeTest: collision separation smaller than elastic diameter")
		instance.queue_free(); return false
	instance.queue_free()
	await process_frame

	# 倍速必须转化为更多 tick 与更大位移；30× 受单帧 12 tick 上限约束。
	var displacement_by_speed: Dictionary = {}
	var speed_genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	for speed_value in [1.0, 30.0]:
		var probe: Node = scene.instantiate()
		probe.set("create_demo_organism", false)
		root.add_child(probe)
		await process_frame
		var tick_core: Node = probe.get_node("Simulation/TickCore")
		var probe_manager: Node = probe.get_node("Simulation/OrganismManager")
		# 单细胞探针：避免 v0.17.0 多模式演示体在中途分裂，位移比较只测倍速→tick→运动。
		probe_manager.set("autonomous_division_enabled", false)
		var probe_genome: RefCounted = speed_genome_script.new() as RefCounted
		probe_genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
		probe_manager.call("register_zygote", 99, 99, -1, probe_genome, Vector2(250, 250), 0.8, 0)
		tick_core.set("running", true)
		tick_core.call("clear_carry")
		tick_core.call("apply_speed", speed_value)
		var probe_cells: RefCounted = probe_manager.get("cells") as RefCounted
		var start_position: Vector2 = probe_cells.call("get_position", 0)
		var start_tick: int = int(tick_core.get("tick_index"))
		for _frame in range(60):
			tick_core.call("_process", 1.0 / 60.0)
		var ticks: int = int(tick_core.get("tick_index")) - start_tick
		var displacement: float = start_position.distance_to(probe_cells.call("get_position", 0))
		displacement_by_speed[speed_value] = {"ticks": ticks, "displacement": displacement, "carry": int(tick_core.get("carry_ticks"))}
		probe.queue_free()
		await process_frame
	var slow: Dictionary = displacement_by_speed[1.0]
	var fast: Dictionary = displacement_by_speed[30.0]
	if int(slow["ticks"]) < 60 or int(fast["ticks"]) <= int(slow["ticks"]) * 5:
		push_error("SmokeTest: high speed did not produce proportionally more ticks")
		return false
	if float(slow["displacement"]) < 0.05 or float(fast["displacement"]) < float(slow["displacement"]) * 1.5:
		push_error("SmokeTest: high speed did not produce visibly larger cell displacement")
		return false
	if int(fast["carry"]) <= 0:
		push_error("SmokeTest: 30x should report frame-cap carry")
		return false
	print("SmokeTest: OK unified CellShape radius / collision diameter / speed-to-ticks-and-motion")
	return true

## 阶段11验收：光照通道 / 基础代谢耗能 / 信号注射通道 / 颜色注射 / 诊断 / 黏附 / 拖拽识别。
## 干预本身是外部输入，不进确定性 hash；这里只验证可见行为与参数落地。
func _check_lifecycle_and_injectors() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("SmokeTest: lifecycle scene missing")
		return false
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", true)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var cells: RefCounted = manager.get("cells") as RefCounted

	# (1) 光照通道：默认 light_intensity>0，场采样通道 3 必须非零（此前恒 0）。
	var light_value: float = float(env.get("light_intensity"))
	if light_value <= 0.0 or not bool(env.call("apply_light_intensity")):
		push_error("SmokeTest: light intensity not applied to field")
		instance.queue_free(); return false
	var center_sample: PackedFloat32Array = env.call("sample_fields", Vector2(250, 250))
	if center_sample.size() < 4 or center_sample[3] <= 0.0:
		push_error("SmokeTest: light channel sample must be non-zero")
		instance.queue_free(); return false

	# (1b) 光合类型映射：CellVisualCatalog type_id=4 必须读取光照通道产能。
	# v0.13.0 回归：旧实现误把体细胞 1 当光合，导致 photocyte 在光场中不增能。
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	bus.call("enqueue", {"type": "SPAWN", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 11)
	var photo_index: int = int(cells.call("size")) - 1
	bus.call("enqueue", {"type": "INJECT_COLOR", "position": Vector2(250, 250), "delta": Vector2.ZERO,
		"kind": "world", "color_type": 4})
	bus.call("execute_tick_commands", 12)
	if int(cells.get("cell_type")[photo_index]) != 4:
		push_error("SmokeTest: photocyte injection failed")
		instance.queue_free(); return false
	var photo_energy_before: float = float(cells.get("cell_energy")[photo_index])
	manager.call("advance_physics_tick", 1.0 / 60.0)
	var photo_energy_after: float = float(cells.get("cell_energy")[photo_index])
	if photo_energy_after <= photo_energy_before + 0.00001:
		push_error("SmokeTest: photocyte did not gain energy from light field (before=%.6f after=%.6f)" % [photo_energy_before, photo_energy_after])
		instance.queue_free(); return false
	if float(manager.get("photosynthetic_intake_rate")) < 0.0799:
		push_error("SmokeTest: photosynthetic intake rate regressed below v0.14.1 value")
		instance.queue_free(); return false

	# (2) 基础代谢：提高 base_metabolic_cost 后，固定能量细胞在若干 tick 内必须下降。
	manager.set("base_metabolic_cost", 0.4)
	manager.set("heterotrophic_intake_rate", 0.0)
	manager.set("photosynthetic_intake_rate", 0.0)
	manager.set("chemotrophic_intake_rate", 0.0)
	manager.set("movement_energy_cost", 0.0)
	bus.call("enqueue", {"type": "SPAWN", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	var probe_index: int = int(cells.call("size")) - 1
	var energy_before: float = float(cells.get("cell_energy")[probe_index])
	for _i in range(10):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var energy_after: float = float(cells.get("cell_energy")[probe_index])
	if energy_after >= energy_before:
		push_error("SmokeTest: base metabolism did not drain energy")
		instance.queue_free(); return false

	# (3) 信号注射：选定通道 2（氧气）注入后，推进一次场扩散，该通道值必须上升。
	# add_source 写入 pending source，需 diffuse_tick 结算；sample_fields 有缓存，需重新 begin。
	var o2_positions: Array[Vector2] = [Vector2(250, 250)]
	env.call("advance_field_tick")
	env.call("begin_field_sampling", o2_positions)
	var o2_sample: PackedFloat32Array = env.call("sample_fields", Vector2(250, 250))
	var o2_before: float = o2_sample[2] if o2_sample.size() > 2 else 0.0
	bus.call("enqueue", {"type": "INJECT_SIGNAL", "position": Vector2(250, 250), "delta": Vector2.ZERO,
		"kind": "world", "signal_channel": 2, "signal_amount": 1.5})
	bus.call("execute_tick_commands", 2)
	env.call("advance_field_tick")
	env.call("begin_field_sampling", o2_positions)
	var o2_after_sample: PackedFloat32Array = env.call("sample_fields", Vector2(250, 250))
	if o2_after_sample.size() <= 2 or o2_after_sample[2] <= o2_before + 0.01:
		push_error("SmokeTest: INJECT_SIGNAL did not write chosen field channel (before=%.4f after=%.4f)" % [o2_before, o2_after_sample[2] if o2_after_sample.size() > 2 else -1.0])
		instance.queue_free(); return false

	# (4) 颜色注射：选定类型 7 写入目标细胞，值精确等于选择（非轮转/随机）。
	var probe_pos: Vector2 = cells.call("get_position", probe_index)
	bus.call("enqueue", {"type": "INJECT_COLOR", "position": probe_pos,
		"delta": Vector2.ZERO, "kind": "world", "color_type": 7})
	bus.call("execute_tick_commands", 3)
	if int(cells.get("cell_type")[probe_index]) != 7:
		push_error("SmokeTest: INJECT_COLOR type mismatch")
		instance.queue_free(); return false

	# (5) 细胞诊断：INSPECT 写 last_inspection，getter 返回各项字段；工具反馈非空。
	bus.call("enqueue", {"type": "INSPECT", "position": probe_pos, "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 4)
	var info: Dictionary = manager.call("get_last_inspection") as Dictionary
	for required_key in ["cell_index", "org_id", "energy", "cell_type", "position", "radius", "links", "field"]:
		if not info.has(required_key):
			push_error("SmokeTest: INSPECT missing field " + str(required_key))
			instance.queue_free(); return false
	if str(manager.call("get_last_tool_message")).is_empty():
		push_error("SmokeTest: INSPECT tool message empty")
		instance.queue_free(); return false

	# (6) 黏附连接：同个体两细胞两次点击建链，静息长度 >= 2r，反馈可读。
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var probe_org: int = int(org_ids[probe_index])
	var alive: PackedByteArray = cells.get("cell_alive")
	var same_org_peer: int = -1
	for cell_index in range(alive.size()):
		if cell_index != probe_index and alive[cell_index] != 0 and int(org_ids[cell_index]) == probe_org:
			same_org_peer = cell_index
			break
	if same_org_peer < 0:
		print("SmokeTest: SKIP ADHERE sub-check (no same-org peer)")
	else:
		manager.set("adhesion_anchor", -1)
		bus.call("enqueue", {"type": "ADHERE", "position": cells.call("get_position", probe_index), "delta": Vector2.ZERO, "kind": "world"})
		bus.call("execute_tick_commands", 5)
		bus.call("enqueue", {"type": "ADHERE", "position": cells.call("get_position", same_org_peer), "delta": Vector2.ZERO, "kind": "world"})
		bus.call("execute_tick_commands", 6)
		var has_valid_rest: bool = false
		for rest_value in cells.get("link_rest_length"):
			if rest_value >= float(manager.get("cell_radius")) * 2.0:
				has_valid_rest = true
				break
		if not has_valid_rest:
			push_error("SmokeTest: ADHERE rest length below collision diameter")
			instance.queue_free(); return false

	# (7) 光学镊子：HUD.is_drag_tool 在 DRAG 工具下为真、SPAWN 为假。
	var hud: Node = instance.get_node("UI/HUD")
	if not hud.has_method("is_drag_tool"):
		push_error("SmokeTest: HUD.is_drag_tool missing")
		instance.queue_free(); return false
	var tools_data: Array[Dictionary] = hud.get("_tools") as Array[Dictionary]
	var drag_index: int = -1
	var spawn_index: int = -1
	for tool_index in range(tools_data.size()):
		var tool_id: String = str(tools_data[tool_index].get("id", ""))
		if tool_id == "DRAG":
			drag_index = tool_index
		elif tool_id == "SPAWN":
			spawn_index = tool_index
	if drag_index < 0:
		push_error("SmokeTest: DRAG tool missing")
		instance.queue_free(); return false
	hud.call("_on_tool_pressed", drag_index)
	if not bool(hud.call("is_drag_tool")):
		push_error("SmokeTest: DRAG must be recognized as drag tool")
		instance.queue_free(); return false
	hud.call("_on_tool_pressed", spawn_index)
	if bool(hud.call("is_drag_tool")):
		push_error("SmokeTest: SPAWN must not be a drag tool")
		instance.queue_free(); return false

	instance.queue_free()
	print("SmokeTest: OK lifecycle light/metabolism + injector channel/color/inspect/adhere + drag recognition")
	return true

## 阶段11：发育编辑器 Godot 落地验收。节点结构 / 三栏控件 / dev_program 双向编辑 / Apply 闭环。
class SignalCapture extends RefCounted:
	var genome: RefCounted = null
	var type_id: int = 0
	func on_applied(genome_value: RefCounted, type_id_value: int) -> void:
		genome = genome_value
		type_id = type_id_value

func _make_signal_capture() -> RefCounted:
	return SignalCapture.new() as RefCounted

func _check_dev_editor_landing() -> bool:
	var dev_scene: PackedScene = load("res://scenes/ui/DevEditorPanel.tscn") as PackedScene
	if dev_scene == null:
		push_error("SmokeTest: DevEditorPanel.tscn not loadable")
		return false
	var dev: Node = dev_scene.instantiate()
	root.add_child(dev)
	await process_frame
	# 骨架内容节点存在。
	if dev.get_node_or_null("Panel/Content") == null:
		push_error("SmokeTest: dev editor content skeleton missing")
		dev.queue_free(); return false
	# v0.27.0：顶部长篇说明已删除，避免遮挡预览并减少滚动。
	if dev.find_child("InstructionHelp", true, false) != null:
		push_error("SmokeTest: dev editor instruction help panel must be removed")
		dev.queue_free(); return false
	# v0.28.0：Macro 字段改动必须能延迟刷新预览（防抖定时器）。
	if dev.find_child("PreviewSyncTimer", true, false) == null:
		push_error("SmokeTest: preview sync debounce timer missing")
		dev.queue_free(); return false
	# v0.15.0：默认基因模式，dev_program 为空；DIVIDE/DIFFERENTIATE/LINK UI 全部隐藏。
	if not (dev.call("_program") as Array).is_empty():
		push_error("SmokeTest: gene-mode editor must have empty dev_program")
		dev.queue_free(); return false
	for legacy_name in ["TemplateRow", "InstructionScroll", "DevTimelinePanel", "LegacyInstructionParams"]:
		var legacy_node: Node = dev.find_child(legacy_name, true, false)
		if legacy_node == null or (legacy_node is CanvasItem and bool((legacy_node as CanvasItem).visible)):
			push_error("SmokeTest: legacy instruction UI must be hidden (" + legacy_name + ")")
			dev.queue_free(); return false
	var gene_labels: Array = dev.get("_gene_slot_labels") as Array
	if gene_labels == null or gene_labels.size() != 40 or not str((gene_labels[0] as Label).text).contains("速度"):
		push_error("SmokeTest: Cell Lab 40 gene slots not built")
		dev.queue_free(); return false
	var macro_draft: Dictionary = dev.call("get_macro_draft") as Dictionary
	var macro_controls: Dictionary = dev.get("_macro_controls") as Dictionary
	if macro_draft.size() < 29 or macro_controls.size() < 29:
		push_error("SmokeTest: Macro draft controls incomplete (%d/%d)" % [macro_draft.size(), macro_controls.size()])
		dev.queue_free(); return false
	# v0.28.0：Cell Lab Gene 没有独立子代类型控件，类型由目标模式的 cell_type 决定。
	if macro_controls.has("child1_type") or macro_controls.has("child2_type"):
		push_error("SmokeTest: child type selectors must be removed (use target mode type)")
		dev.queue_free(); return false
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var glue_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var draft_ref: RefCounted = dev.get("draft") as RefCounted
	var draft_hash_before: int = int(draft_ref.call("hash"))
	dev.call("_on_macro_value_changed", 0.8, "split_mass")
	if int(draft_ref.call("hash")) != draft_hash_before:
		push_error("SmokeTest: non-gene Macro field must not change GNP1 hash")
		dev.queue_free(); return false
	# 分裂质量属于真正落地的 Cell Lab Gene.b 参数，必须写入 Genome 并改变 hash。
	dev.call("_on_macro_value_changed", 2.0, "division_mass")
	if absf(float(draft_ref.get("division_mass")) - 2.0) > 0.001 or int(draft_ref.call("hash")) == draft_hash_before:
		push_error("SmokeTest: division mass must write Genome and change hash")
		dev.queue_free(); return false
	if (int(draft_ref.get("flags")) & gene_flag) == 0:
		push_error("SmokeTest: draft must be gene mode")
		dev.queue_free(); return false
	var gene_hash_before: int = int(draft_ref.call("hash"))
	dev.call("_on_macro_bool_changed", false, "make_glue")
	if (int(draft_ref.get("flags")) & glue_flag) != 0 or int(draft_ref.call("hash")) == gene_hash_before:
		push_error("SmokeTest: make_glue off must clear flags bit0 and change hash")
		dev.queue_free(); return false
	dev.call("_on_macro_bool_changed", true, "make_glue")
	if (int(draft_ref.get("flags")) & glue_flag) == 0:
		push_error("SmokeTest: make_glue on must set flags bit0")
		dev.queue_free(); return false
	# 基因模式发育预览：分裂次数 → 状态数，黏附素 → 亲子连接，child 类型 → 分裂即分化。
	var preview_node: Node = dev.find_child("GenomePreview", true, false)
	if preview_node == null or preview_node.find_child("Canvas", true, false) == null:
		push_error("SmokeTest: genome preview scene missing from editor")
		dev.queue_free(); return false
	# v0.23.0：预览改为真实模拟内核。前面的 hash 测试把 division_mass 设成 2.0
	# （超出 Cell Lab 能量上限 0.36，物理上不会分裂）；这里用可分裂阈值显式重建预览。
	var preview_draft: Dictionary = {
		"cell_type": 0, "division_mass": 0.05, "split_ratio": 0.5,
		"max_divisions": 3, "make_glue": true, "max_connections": 16,
	}
	preview_node.call("set_program", [], preview_draft, true)
	# v0.27.0：默认停在 t=0（合子），避免初始就停在末态导致一拖就重置重跑。
	if int(preview_node.call("get_current_tick")) != 0:
		push_error("SmokeTest: preview timeline must default to tick 0")
		dev.queue_free(); return false
	var state_count_gp: int = int(preview_node.call("get_state_count"))
	if state_count_gp < 2 or int(preview_node.call("get_cell_count_at", state_count_gp - 1)) < 2:
		push_error("SmokeTest: gene preview did not simulate division sequence")
		dev.queue_free(); return false
	if int(preview_node.call("get_link_count_at", state_count_gp - 1)) < 1:
		push_error("SmokeTest: gene preview must show adhesin parent-child links")
		dev.queue_free(); return false
	if int(preview_node.call("get_split_count_at", state_count_gp - 1)) < 1:
		push_error("SmokeTest: gene preview must record split indicators")
		dev.queue_free(); return false
	# v0.23.0：真实模拟下分裂指示器随分裂累积（单调不减），角度来自真实分裂轴。
	var prev_split_count: int = 0
	for split_state in range(state_count_gp):
		var sc: int = int(preview_node.call("get_split_count_at", split_state))
		if sc < prev_split_count:
			push_error("SmokeTest: split indicator count must be monotonic")
			dev.queue_free(); return false
		prev_split_count = sc
	var first_angle: float = float(preview_node.call("get_split_angle_at", 1, 0))
	if first_angle < 0.0 or first_angle > TAU:
		push_error("SmokeTest: split indicator angle out of range")
		dev.queue_free(); return false
	# v0.26.0：Cell Lab 同款连续时间轴（无上一步/播放/下一步按钮），拖到不同 tick 重跑真实模拟。
	var max_tick: int = int(preview_node.call("get_max_tick"))
	if max_tick < 1:
		push_error("SmokeTest: genome preview continuous timeline must have tick range")
		dev.queue_free(); return false
	var tl_slider = preview_node.find_child("Slider", true, false)
	if tl_slider == null or preview_node.find_child("PrevButton", true, false) != null \
		or preview_node.find_child("PlayButton", true, false) != null \
		or preview_node.find_child("NextButton", true, false) != null:
		push_error("SmokeTest: preview must use single continuous slider without step buttons")
		dev.queue_free(); return false
	tl_slider.set_value(0.0)
	if int(preview_node.call("get_current_tick")) != 0:
		push_error("SmokeTest: preview timeline seek to zygote failed")
		dev.queue_free(); return false
	tl_slider.set_value(float(max_tick))
	if int(preview_node.call("get_current_tick")) != max_tick:
		push_error("SmokeTest: preview timeline seek to end failed")
		dev.queue_free(); return false
	var preview_hash_before: int = int((dev.get("draft") as RefCounted).call("hash"))
	preview_node.call("set_program", [], {"cell_type": 0, "division_mass": 2.0, "max_divisions": 3, "make_glue": true, "child1": 0, "child2": 2, "child3": 4, "child4": 10, "child1_angle": 0.0, "child2_angle": 0.25, "child3_angle": 0.5, "child4_angle": 0.75}, true)
	if int((dev.get("draft") as RefCounted).call("hash")) != preview_hash_before:
		push_error("SmokeTest: genome preview must not change GNP1 hash")
		dev.queue_free(); return false
	# Apply → draft_applied 信号携带合法 genome 草案（不直接写模拟）。
	# Apply → draft_applied 信号携带合法 genome 草案（不直接写模拟）。
	# lambda 按值捕获，用一个 RefCounted 包装器承接回调结果。
	var applied: RefCounted = _make_signal_capture()
	dev.connect("draft_applied", Callable(applied, "on_applied"))
	dev.call("_on_apply")
	var applied_genome: RefCounted = applied.get("genome") as RefCounted
	if applied_genome == null or not bool(applied_genome.call("is_valid")):
		push_error("SmokeTest: dev editor Apply did not emit valid genome")
		dev.queue_free(); return false
	dev.queue_free()

	# main.tscn 只保留一个「细胞编辑」面板/按钮：原「发育编辑」入口必须消失。
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main_instance: Node = main_scene.instantiate()
	root.add_child(main_instance)
	await process_frame
	var hud: Node = main_instance.get_node_or_null("UI/HUD")
	var cell_panel: Node = main_instance.get_node_or_null("UI/HUD/CellEditorPanel")
	var cell_button: Node = main_instance.get_node_or_null("UI/HUD/CellEditorButton")
	if hud == null or cell_panel == null or cell_button == null:
		push_error("SmokeTest: merged cell editor button/panel missing")
		main_instance.queue_free(); return false
	if main_instance.get_node_or_null("UI/HUD/DevEditorPanel") != null or main_instance.get_node_or_null("UI/HUD/DevEditorButton") != null:
		push_error("SmokeTest: duplicate dev editor entry still present")
		main_instance.queue_free(); return false
	if not cell_panel.has_signal("draft_applied") or not cell_panel.has_method("get_dev_program"):
		push_error("SmokeTest: merged editor missing draft API")
		main_instance.queue_free(); return false
	main_instance.queue_free()
	print("SmokeTest: OK unified cell editor (gene slots / three-pane / dev_program / Apply / no duplicate entry)")
	return true

## UI 调整验收：面板 chrome（拖动/图钉/关闭/顶栏开关）、诊断选中、光场层、镜头滤镜不改视野。
func _check_ui_chrome_and_filters() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("SmokeTest: ui chrome scene missing")
		return false
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	var hud: Node = instance.get_node_or_null("UI/HUD")
	if hud == null:
		push_error("SmokeTest: HUD missing")
		instance.queue_free(); return false

	# (1) 面板 chrome：每个目标面板下有 ChromeHandle + 关闭按钮；报告面板额外有图钉。
	var panel_paths: Array[String] = [
		"UI/HUD/ToolDock", "UI/HUD/SubstratePanel", "UI/HUD/MicroscopePanel",
		"UI/HUD/SpeedPanel", "UI/HUD/CellEditorPanel",
		"UI/AnalysisPanel", "UI/Minimap",
	]
	for panel_path in panel_paths:
		var panel: Node = instance.get_node_or_null(panel_path)
		if panel == null or panel.get_node_or_null("ChromeRoot/ChromeHandle") == null:
			push_error("SmokeTest: panel chrome missing " + panel_path)
			instance.queue_free(); return false
	var report_panel: Node = instance.get_node_or_null("UI/AnalysisPanel")
	if report_panel == null or bool(report_panel.get_meta("chrome_pinned", true)) != false:
		push_error("SmokeTest: report panel chrome pin meta not initialized")
		instance.queue_free(); return false

	# (2) 顶栏开关按钮：每个面板/光场均有 toggle；关闭 → 重开闭环。
	var toggles: Dictionary = hud.get("_panel_toggles") as Dictionary
	if toggles.size() < 8 or toggles.has("DevEditorPanel"):
		push_error("SmokeTest: panel toggles not merged, size=%d" % toggles.size())
		instance.queue_free(); return false
	var speed_panel: Node = instance.get_node_or_null("UI/HUD/SpeedPanel")
	var speed_toggle: Button = toggles.get("SpeedPanel", null) as Button
	if speed_panel == null or speed_toggle == null:
		push_error("SmokeTest: speed panel toggle missing")
		instance.queue_free(); return false
	speed_panel.visible = false
	speed_toggle.set_pressed_no_signal(false)
	speed_toggle.set_pressed(true)
	if not speed_panel.visible:
		push_error("SmokeTest: toggle did not reopen panel")
		instance.queue_free(); return false

	# (3) 关闭按钮 → 面板隐藏 + 对应 toggle 复位。
	var chrome_map: Dictionary = hud.get("_panel_chromes") as Dictionary
	var speed_chrome: RefCounted = chrome_map.get("SpeedPanel", null) as RefCounted
	if speed_chrome == null or speed_chrome.get_close_button() == null:
		push_error("SmokeTest: speed panel close button missing")
		instance.queue_free(); return false
	speed_chrome.get_close_button().pressed.emit()
	if speed_panel.visible or speed_toggle.is_pressed():
		push_error("SmokeTest: close button did not hide panel/reset toggle")
		instance.queue_free(); return false

	# (4) 图钉切换：固定后 meta=true，R 键不关闭（这里验证 meta 与按钮文字）。
	var report_chrome: RefCounted = chrome_map.get("../AnalysisPanel", null) as RefCounted
	if report_chrome == null or report_chrome.get_pin_button() == null:
		push_error("SmokeTest: report pin button missing")
		instance.queue_free(); return false
	report_chrome.get_pin_button().set_pressed(true)
	if not bool(report_panel.get_meta("chrome_pinned", false)):
		push_error("SmokeTest: pin did not set chrome_pinned meta")
		instance.queue_free(); return false
	# (4b) 图钉固定后关闭按钮仍必须生效，并同步内部 _visible_state 与顶栏 toggle。
	report_panel.call("set_visible_state", true)
	var report_toggle: Button = toggles.get("../AnalysisPanel", null) as Button
	report_chrome.get_close_button().pressed.emit()
	if bool(report_panel.visible) or bool(report_panel.get("_visible_state")):
		push_error("SmokeTest: report close button did not hide panel/state")
		instance.queue_free(); return false
	if report_toggle != null and report_toggle.is_pressed():
		push_error("SmokeTest: report close button did not reset toggle")
		instance.queue_free(); return false

	# (4c) 标题栏必须在面板顶部：ChromeRoot 的第一个子节点是 ChromeHandle（原来错误地排在内容之后）。
	var report_root: Node = report_panel.get_node_or_null("ChromeRoot")
	if report_root == null or report_root.get_child_count() == 0 or report_root.get_child(0).name != "ChromeHandle":
		push_error("SmokeTest: chrome handle must be the first child (top-right close button)")
		instance.queue_free(); return false

	# (4d) 生态报告实时数字：6 tick 内必须跟着 tick_index 变，不再只有 30 tick 采样才动。
	var report_tick_core: Node = instance.get_node_or_null("Simulation/TickCore")
	if report_tick_core == null:
		push_error("SmokeTest: report tick core missing")
		instance.queue_free(); return false
	report_panel.call("set_visible_state", true)
	report_panel.call("refresh_now")
	var live_label: Node = report_panel.find_child("LiveStatsLabel", true, false)
	if live_label == null:
		push_error("SmokeTest: report live stats label missing")
		instance.queue_free(); return false
	var live_text: String = str(live_label.get("text"))
	var probe_tick: int = 137
	report_tick_core.set("tick_index", probe_tick)
	for i in range(6):
		report_panel.call("_on_tick_for_refresh", probe_tick + i)
	live_text = str(live_label.get("text"))
	if not live_text.contains("实时 tick %d" % probe_tick):
		push_error("SmokeTest: report live stats did not refresh within 6 ticks: " + live_text)
		instance.queue_free(); return false

	# (4e) v0.14.0：FPS/TPS 仪表真实存在且按 tick 推进更新。
	var perf_label: Node = hud.get_node_or_null("PerfLabel")
	if perf_label == null or not str(perf_label.get("text")).contains("FPS"):
		push_error("SmokeTest: perf FPS/TPS label missing")
		instance.queue_free(); return false
	for frame_index in range(35):
		await process_frame
	if not str(perf_label.get("text")).contains("TPS"):
		push_error("SmokeTest: perf label did not update")
		instance.queue_free(); return false

	# (4f) v0.14.0：关闭按钮点击链始终生效；「取消诊断锁定」默认自动收起、图钉固定后保持。
	var report_chrome_now: RefCounted = chrome_map.get("../AnalysisPanel", null) as RefCounted
	report_panel.call("set_visible_state", true)
	report_panel.set_meta("chrome_pinned", false)
	report_chrome_now.call("_on_close_pressed")
	if bool(report_panel.visible):
		push_error("SmokeTest: report close button click chain failed")
		instance.queue_free(); return false
	report_panel.call("set_visible_state", true)
	report_panel.call("on_selection_cleared")
	if bool(report_panel.visible):
		push_error("SmokeTest: unlock must auto-close unpinned report")
		instance.queue_free(); return false
	report_panel.call("set_visible_state", true)
	report_panel.set_meta("chrome_pinned", true)
	report_panel.call("on_selection_cleared")
	if not bool(report_panel.visible):
		push_error("SmokeTest: pinned report must stay open on unlock")
		instance.queue_free(); return false
	report_panel.set_meta("chrome_pinned", false)

	# (5) 诊断选中：INSPECT 写 selection，SelectionLayer 存在。
	var selection_layer: Node = instance.get_node_or_null("DishView/SelectionLayer")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var cells: RefCounted = manager.get("cells") as RefCounted
	if selection_layer == null or not selection_layer.has_method("mark_dirty"):
		push_error("SmokeTest: SelectionLayer missing")
		instance.queue_free(); return false
	bus.call("enqueue", {"type": "SPAWN", "position": Vector2(250, 250), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 1)
	var spawned: int = int(cells.call("size")) - 1
	bus.call("enqueue", {"type": "INSPECT", "position": cells.call("get_position", spawned), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 2)
	var selection: Array = manager.get("selection") as Array
	if selection.size() != 1 or int(selection[0]) != spawned:
		push_error("SmokeTest: INSPECT did not select cell")
		instance.queue_free(); return false
	# v0.14.0：诊断快照必须跟随 tick 实时派生，不再停在点击瞬间。
	var live_info_t0: Dictionary = manager.call("get_live_inspection") as Dictionary
	var inspect_label: Label = report_panel.find_child("InspectText", true, false) as Label
	if inspect_label == null:
		push_error("SmokeTest: inspect text label missing")
		instance.queue_free(); return false
	report_panel.call("refresh_now")
	manager.set("_sim_tick", int(live_info_t0.get("tick", 0)) + 42)
	var live_info_t1: Dictionary = manager.call("get_live_inspection") as Dictionary
	if int(live_info_t1.get("tick", -1)) <= int(live_info_t0.get("tick", -1)):
		push_error("SmokeTest: live inspection snapshot did not follow sim tick")
		instance.queue_free(); return false
	# 解锁三种入口：面板按钮（经 CommandBus）、Esc 命令、诊断点空白。
	bus.call("enqueue", {"type": "CLEAR_SELECTION"})
	bus.call("execute_tick_commands", 3)
	if not (manager.get("selection") as Array).is_empty():
		push_error("SmokeTest: CLEAR_SELECTION did not unlock")
		instance.queue_free(); return false
	bus.call("enqueue", {"type": "INSPECT", "position": cells.call("get_position", spawned), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 4)
	bus.call("enqueue", {"type": "INSPECT", "position": Vector2(20, 20), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 5)
	if not (manager.get("selection") as Array).is_empty():
		push_error("SmokeTest: INSPECT on empty space did not unlock")
		instance.queue_free(); return false
	var report_unlock: Node = report_panel.find_child("UnlockSelectionButton", true, false)
	if report_unlock == null:
		push_error("SmokeTest: analysis panel unlock button missing")
		instance.queue_free(); return false
	bus.call("enqueue", {"type": "INSPECT", "position": cells.call("get_position", spawned), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 6)
	(report_unlock as Button).pressed.emit()
	if not (manager.get("selection") as Array).is_empty():
		push_error("SmokeTest: report unlock button did not clear selection")
		instance.queue_free(); return false

	# (6) 光场层：默认可见、通道=3 有实际光照数据、顶栏开关可关可开。
	var field_layer: Node = instance.get_node_or_null("DishView/FieldLayer")
	if field_layer == null or not field_layer.has_method("set_enabled") or not field_layer.has_method("set_channel"):
		push_error("SmokeTest: FieldLayer view API missing")
		instance.queue_free(); return false
	if not bool(field_layer.call("is_enabled")) or not bool(field_layer.visible):
		push_error("SmokeTest: FieldLayer should be visible by default")
		instance.queue_free(); return false
	if hud.get("_field_layer") == null:
		push_error("SmokeTest: HUD field layer path is wrong")
		instance.queue_free(); return false
	var light_values: PackedFloat32Array = ((instance.get_node("Simulation/EnvironmentManager").get("field") as RefCounted).get("channels") as Array)[3] as PackedFloat32Array
	var lit_cells: int = 0
	for value in light_values:
		if value > 0.001:
			lit_cells += 1
	if lit_cells == 0:
		push_error("SmokeTest: light channel has no visible coverage")
		instance.queue_free(); return false
	var field_toggle: Button = toggles.get("@field", null) as Button
	if field_toggle == null or not field_toggle.is_pressed():
		push_error("SmokeTest: field toggle not initialized pressed")
		instance.queue_free(); return false
	field_toggle.set_pressed(false)
	if bool(field_layer.call("is_enabled")):
		push_error("SmokeTest: field toggle did not hide light field")
		instance.queue_free(); return false
	field_toggle.set_pressed(true)
	if not bool(field_layer.call("is_enabled")) or int(field_layer.get("channel_index")) != 3:
		push_error("SmokeTest: field toggle did not restore light field")
		instance.queue_free(); return false

	var food_layer: Node = instance.get_node_or_null("DishView/FoodLayer")
	var food_toggle: Button = toggles.get("@food", null) as Button
	if food_layer == null or not bool(food_layer.call("is_enabled")) or hud.get("_food_layer") == null:
		push_error("SmokeTest: food layer path/enabled state wrong")
		instance.queue_free(); return false
	if food_toggle == null or not food_toggle.is_pressed():
		push_error("SmokeTest: food toggle not initialized pressed")
		instance.queue_free(); return false
	food_toggle.set_pressed(false)
	if bool(food_layer.call("is_enabled")):
		push_error("SmokeTest: food toggle did not hide food layer")
		instance.queue_free(); return false
	food_toggle.set_pressed(true)
	if not bool(food_layer.call("is_enabled")):
		push_error("SmokeTest: food toggle did not restore food layer")
		instance.queue_free(); return false

	# (7) 镜头滤镜：切换镜头不改 camera.zoom；各镜头滤镜参数不同。
	var camera: Node = instance.get_node("Camera2D")
	var zoom_before: Vector2 = camera.get("zoom")
	var lens_defs: Array = hud.get("_lenses") as Array
	var lens_idx: int = lens_defs.find("目镜")
	if lens_idx < 0:
		push_error("SmokeTest: eyepiece lens missing")
		instance.queue_free(); return false
	hud.call("_on_lens_pressed", lens_idx)
	if not is_equal_approx((camera.get("zoom") as Vector2).x, zoom_before.x):
		push_error("SmokeTest: lens must not change camera zoom")
		instance.queue_free(); return false
	var tint: ColorRect = hud.get("_tint") as ColorRect
	var material: ShaderMaterial = tint.material as ShaderMaterial
	if material == null or float(material.get_shader_parameter("strength")) <= 0.0:
		push_error("SmokeTest: lens filter strength not applied")
		instance.queue_free(); return false
	var strength_eyepiece: float = float(material.get_shader_parameter("strength"))
	var fusion_idx: int = lens_defs.find("融合镜")
	hud.call("_on_lens_pressed", fusion_idx)
	var strength_fusion: float = float(material.get_shader_parameter("strength"))
	if is_equal_approx(strength_eyepiece, strength_fusion):
		push_error("SmokeTest: lenses must produce distinct filter params")
		instance.queue_free(); return false

	instance.queue_free()
	print("SmokeTest: OK UI chrome/pin/toggle + inspect-select + field layer + lens filter (no zoom)")
	return true

## v0.14.1：食物衰亡变慢 + 光合产能提高，参数与行为同时回归。
func _check_v0141_food_and_photosynthesis() -> bool:
	var food_script: Script = load("res://scripts/core/data/FoodStore.gd") as Script
	var decay: float = float(food_script.get_script_constant_map().get("MASS_DECAY", 0.11))
	if decay > 0.02:
		push_error("SmokeTest: food mass decay not slowed (%.4f)" % decay)
		return false
	var store: RefCounted = food_script.new() as RefCounted
	store.call("spawn", Vector2(120.0, 120.0), 0.2, 0.5)
	for _i in range(120):
		store.call("advance", 1.0 / 60.0)
	if int(store.call("active_count")) != 1 or float(store.call("get_mass", 0)) < 0.15:
		push_error("SmokeTest: food vanished too fast within 120 ticks")
		return false
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var rate: float = float(manager.get("photosynthetic_intake_rate"))
	if rate < 0.0799 or rate > 0.0801:
		push_error("SmokeTest: photosynthetic intake rate is not v0.14.1 value (%.4f)" % rate)
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.14.1 food decay + photosynthetic rate")
	return true

## v0.14.1：诊断面板显示产能/自身耗能/连接转出/连接转入，数值来自只读诊断派生。
func _check_v0141_energy_flow_diagnostics() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var bus: Node = instance.get_node("Simulation/CommandBus")
	var cells: RefCounted = manager.get("cells") as RefCounted
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	manager.set("heterotrophic_intake_rate", 0.0)
	manager.set("photosynthetic_intake_rate", 0.0)
	manager.set("chemotrophic_intake_rate", 0.0)
	manager.set("default_transfer_rate", 0.05)
	# 同一 org 的两枚细胞：用 flags=0 的一次 DIVIDE 发育产生，再手动建连。
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var plain_genome: RefCounted = genome_script.new() as RefCounted
	plain_genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	plain_genome.call("set_development_program", [{"opcode": 0, "a": 0, "b": 64, "c": 14}])
	if int(manager.call("register_zygote", 0, 0, -1, plain_genome, Vector2(250, 250), 0.8, 0)) < 0:
		push_error("SmokeTest: energy-flow test zygote registration failed")
		instance.queue_free(); return false
	manager.call("advance_development_tick")
	if int(cells.call("size")) < 2:
		push_error("SmokeTest: energy-flow test could not develop two cells")
		instance.queue_free(); return false
	var donor: int = 0
	var receiver: int = 1
	if not bool(cells.call("link_cells", donor, receiver, 14.0)):
		push_error("SmokeTest: energy-flow test could not link cells")
		instance.queue_free(); return false
	var energies: PackedFloat32Array = cells.get("cell_energy")
	energies[donor] = 0.8
	energies[receiver] = 0.1
	cells.set("cell_energy", energies)
	manager.call("advance_physics_tick", 1.0 / 60.0)
	var flow: Dictionary = manager.get("_energy_flow") as Dictionary
	var out_values: PackedFloat64Array = flow.get("link_out", PackedFloat64Array())
	var in_values: PackedFloat64Array = flow.get("link_in", PackedFloat64Array())
	if out_values.size() <= donor or in_values.size() <= receiver or out_values[donor] <= 0.0 or in_values[receiver] <= 0.0:
		push_error("SmokeTest: link transfer was not recorded in diagnostic buffer")
		instance.queue_free(); return false
	bus.call("enqueue", {"type": "INSPECT", "position": cells.call("get_position", donor), "delta": Vector2.ZERO, "kind": "world"})
	bus.call("execute_tick_commands", 2)
	var info: Dictionary = manager.call("get_live_inspection") as Dictionary
	for key in ["production", "self_cost", "link_out", "link_in", "predation_drain", "energy_flow_tick"]:
		if not info.has(key):
			push_error("SmokeTest: live inspection missing energy flow key " + key)
			instance.queue_free(); return false
	if float(info.get("link_out", 0.0)) <= 0.0 or float(info.get("self_cost", 0.0)) < 0.0:
		push_error("SmokeTest: live inspection energy flow values invalid")
		instance.queue_free(); return false
	var report: Node = instance.get_node_or_null("UI/AnalysisPanel")
	if report == null:
		push_error("SmokeTest: analysis panel missing for energy flow display")
		instance.queue_free(); return false
	report.call("refresh_now")
	var inspect_label: Label = report.find_child("InspectText", true, false) as Label
	var report_text: String = str(inspect_label.text) if inspect_label != null else ""
	if not report_text.contains("产能") or not report_text.contains("自身耗能") or not report_text.contains("传输给其他细胞"):
		push_error("SmokeTest: analysis panel did not render energy flow breakdown")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.14.1 energy flow diagnostics")
	return true

## v0.15.0：schema_version 2 版本化追加的基因参数必须随存档往返，不改 GNP1 二进制。
func _check_v0150_gene_save_roundtrip() -> bool:
	var save_script: Script = load("res://scripts/system/SaveManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", gene_flag)
	genome.set("division_mass", 3.5)
	genome.set("split_ratio", 0.35)
	genome.set("max_divisions", 5)
	genome.set("child_types", PackedByteArray([0, 2, 4, 10]))
	genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	var org_id: int = int(manager.call("register_zygote", 0, 0, -1, genome, Vector2.ZERO, 0.8, 0))
	if org_id < 0:
		push_error("SmokeTest: gene save roundtrip registration failed")
		instance.queue_free(); return false
	var snapshot: Dictionary = save_script.call("capture", manager, env, tick_core) as Dictionary
	if int(snapshot.get("schema_version", -1)) != 8:
		push_error("SmokeTest: save schema must be version 7")
		instance.queue_free(); return false
	var stored: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	stored.set("division_mass", 99.0)
	stored.set("max_divisions", 1)
	if not bool(save_script.call("restore", snapshot, manager, env, tick_core)):
		push_error("SmokeTest: gene-mode save restore failed")
		instance.queue_free(); return false
	stored = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	if stored == null or absf(float(stored.get("division_mass")) - 3.5) > 0.001 or int(stored.get("max_divisions")) != 5:
		push_error("SmokeTest: gene fields lost during save roundtrip")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.15.0 gene-mode save roundtrip (schema v8)")
	return true

## v0.14.1：make_glue 置位的 genome 分裂后自动连接亲子，未置位时保持旧行为。
func _check_v0141_glue_link() -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var cells: RefCounted = manager.get("cells") as RefCounted
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var glue_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	var program: Array = [{"opcode": 0, "a": 0, "b": 64, "c": 14}]
	var genome_on: RefCounted = genome_script.new() as RefCounted
	genome_on.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome_on.set("flags", glue_flag)
	genome_on.call("set_development_program", program)
	var parent_on: int = int(cells.call("size"))
	var org_on: int = int(manager.call("register_zygote", 0, 0, -1, genome_on, Vector2.ZERO, 0.8, 0))
	if org_on < 0:
		push_error("SmokeTest: glue genome registration failed")
		instance.queue_free(); return false
	manager.call("advance_development_tick")
	if int(cells.call("size")) != parent_on + 2 or not bool(cells.call("has_link", parent_on, parent_on + 1)):
		push_error("SmokeTest: glue genome division did not auto-link parent and child (size=%d parent=%d links=%d flag=%d has_glue=%s)" % [
			int(cells.call("size")), parent_on, (cells.get("link_cell_a") as PackedInt32Array).size(), glue_flag,
			str(genome_script.call("has_glue_links", manager.get("genomes")[org_on]))])
		instance.queue_free(); return false
	var parent_off: int = int(cells.call("size"))
	var genome_off: RefCounted = genome_script.new() as RefCounted
	genome_off.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome_off.set("flags", 0)
	# DIVIDE.a 是全局细胞索引，不是个体内序号；第二个个体的母细胞索引为 parent_off。
	genome_off.call("set_development_program", [{"opcode": 0, "a": parent_off, "b": 64, "c": 14}])
	var org_off: int = int(manager.call("register_zygote", 1, 0, -1, genome_off, Vector2(200, 0), 0.8, 0))
	if org_off < 0:
		push_error("SmokeTest: non-glue genome registration failed")
		instance.queue_free(); return false
	manager.call("advance_development_tick")
	if int(cells.call("size")) != parent_off + 2 or bool(cells.call("has_link", parent_off, parent_off + 1)):
		push_error("SmokeTest: non-glue genome must not auto-link (size=%d parent=%d links=%d link_a=%s)" % [
			int(cells.call("size")), parent_off, (cells.get("link_cell_a") as PackedInt32Array).size(), str(cells.get("link_cell_a"))])
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.14.1 glue links child without LINK instruction")
	return true

## v0.16.0：Macro 表型字段写入 Genome、改变基因模式 hash、预览可见；旧模式 hash 不变。
func _check_v0160_macro_editor_fields() -> bool:
	var dev_scene: PackedScene = load("res://scenes/ui/DevEditorPanel.tscn") as PackedScene
	if dev_scene == null:
		push_error("SmokeTest: DevEditorPanel scene missing for v0.16.0 check")
		return false
	var dev: Node = dev_scene.instantiate()
	root.add_child(dev)
	await process_frame
	var draft_ref: RefCounted = dev.get("draft") as RefCounted
	var hash_before: int = int(draft_ref.call("hash"))
	dev.call("_on_macro_value_changed", 1.5, "cell_size")
	dev.call("_on_macro_value_changed", 0.8, "stiffness")
	dev.call("_on_macro_value_changed", 0.9, "nutrition_priority")
	dev.call("_on_macro_value_changed", 2.0, "min_connections")
	dev.call("_on_macro_value_changed", 0.1, "color_r")
	dev.call("_on_macro_value_changed", 0.2, "color_g")
	dev.call("_on_macro_value_changed", 0.3, "color_b")
	if absf(float(draft_ref.get("cell_size")) - 1.5) > 0.001 \
		or absf(float(draft_ref.get("cell_stiffness")) - 0.8) > 0.001 \
		or absf(float(draft_ref.get("nutrition_priority")) - 0.9) > 0.001 \
		or int(draft_ref.get("min_connections")) != 2 \
		or absf(float(draft_ref.get("color_r")) - 0.1) > 0.001 \
		or absf(float(draft_ref.get("color_b")) - 0.3) > 0.001:
		push_error("SmokeTest: v0.16.0 macro fields did not reach Genome draft")
		dev.queue_free(); return false
	if int(draft_ref.call("hash")) == hash_before:
		push_error("SmokeTest: v0.16.0 macro fields must change gene-mode hash")
		dev.queue_free(); return false
	# 旧模式 flags=0：同样字段不得改变 hash，保证 v0.14.x 回放稳定。
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var plain: RefCounted = genome_script.new() as RefCounted
	plain.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	var tuned: RefCounted = genome_script.new() as RefCounted
	tuned.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	tuned.set("cell_size", 1.5)
	tuned.set("nutrition_priority", 0.9)
	tuned.set("color_r", 0.1)
	if int(plain.call("hash")) != int(tuned.call("hash")):
		push_error("SmokeTest: legacy-mode hash must ignore v0.16.0 fields")
		dev.queue_free(); return false
	# 预览按新字段派生 caption 与补连数量；只读，不写 Genome。
	var preview_node: Node = dev.find_child("GenomePreview", true, false)
	if preview_node == null:
		push_error("SmokeTest: genome preview missing for v0.16.0 check")
		dev.queue_free(); return false
	# v0.23.0：真实模拟内核要求能量可达阈值；用可分裂 draft（保留 cell 表型字段）。
	var v016_draft: Dictionary = dev.call("get_macro_draft")
	v016_draft["division_mass"] = 0.05
	preview_node.call("set_program", [], v016_draft, true)
	# 真实模拟内核 caption 标记"真实模拟"；表型数值由内核 gene 消费而非写进 caption。
	var caption: String = str(preview_node.call("get_state_caption_at", 0))
	if not caption.contains("真实模拟"):
		push_error("SmokeTest: preview must use real-simulation caption: " + caption)
		dev.queue_free(); return false
	var state_count: int = int(preview_node.call("get_state_count"))
	if state_count < 2 or int(preview_node.call("get_cell_count_at", state_count - 1)) < 2:
		push_error("SmokeTest: preview must simulate multiple cell states")
		dev.queue_free(); return false
	dev.queue_free()
	print("SmokeTest: OK v0.16.0 macro phenotype editor / hash boundary / preview")
	return true

## v0.16.0：逐细胞半径/刚度/颜色生效，连接上限与补连生效，schema v3 与旧档兼容。
func _check_v0160_runtime_phenotype() -> bool:
	var save_script: Script = load("res://scripts/system/SaveManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	manager.set("autonomous_division_cooldown", 1)
	var cells: RefCounted = manager.get("cells") as RefCounted
	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var glue_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", gene_flag | glue_flag)
	genome.set("division_mass", 0.2)
	genome.set("split_ratio", 0.5)
	genome.set("max_divisions", 2)
	genome.set("child_types", PackedByteArray([0, 2, 4, 10]))
	genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	genome.set("cell_size", 1.5)
	genome.set("cell_stiffness", 0.8)
	genome.set("nutrition_priority", 0.9)
	genome.set("max_connections", 4)
	genome.set("min_connections", 2)
	genome.set("color_r", 0.1)
	genome.set("color_g", 0.2)
	genome.set("color_b", 0.3)
	var base_count: int = int(cells.call("size"))
	var org_id: int = int(manager.call("register_zygote", 1, 1, -1, genome, Vector2.ZERO, 3.0, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.16.0 zygote registration failed")
		instance.queue_free(); return false
	var zygote_index: int = base_count
	if absf(float(cells.call("get_radius_scale", zygote_index)) - 1.5) > 0.001 \
		or absf(float(cells.call("get_stiffness", zygote_index)) - 1.45) > 0.001:
		push_error("SmokeTest: gene phenotype arrays not applied to zygote")
		instance.queue_free(); return false
	var cell_color: Color = cells.call("get_color", zygote_index) as Color
	if absf(cell_color.r - 0.1) > 0.001 or absf(cell_color.g - 0.2) > 0.001 or absf(cell_color.b - 0.3) > 0.001:
		push_error("SmokeTest: gene color not applied to zygote")
		instance.queue_free(); return false
	# 视图层：颜色覆写可见，半径倍率生效，而公开静息半径 API 保持兼容。
	var cell_view_scene: PackedScene = load("res://scenes/cells/CellBase.tscn") as PackedScene
	var view: Node2D = cell_view_scene.instantiate() as Node2D
	root.add_child(view)
	await process_frame
	var no_contacts: Array[Vector2] = []
	view.call("apply_cell", Vector2.ZERO, 0, 0, 1.0, Vector2.ZERO, no_contacts, no_contacts, no_contacts, [], 1.5, cell_color)
	var body: Polygon2D = view.get("body") as Polygon2D
	if body == null or absf(body.color.r - 0.1) > 0.001 or absf(body.color.g - 0.2) > 0.001:
		push_error("SmokeTest: genome color override not rendered on cell body")
		instance.queue_free(); view.queue_free(); return false
	if absf(float(view.call("get_visual_rest_radius")) - 7.0) > 0.001:
		push_error("SmokeTest: visual rest radius API must stay compatible")
		instance.queue_free(); view.queue_free(); return false
	view.queue_free()
	for step_index in range(240):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	var max_seen: int = 0
	for cell_index in range(link_counts.size()):
		max_seen = maxi(max_seen, int(link_counts[cell_index]))
	if int(cells.call("size")) < base_count + 2 or max_seen > 4 or max_seen < 2:
		push_error("SmokeTest: v0.16.0 division/link limits invalid (cells=%d max_links=%d)" % [int(cells.call("size")), max_seen])
		instance.queue_free(); return false
	# 新 schema 保存表型数组；旧快照缺字段时按 1.0/-1 恢复。
	var snapshot: Dictionary = save_script.call("capture", manager, env, tick_core) as Dictionary
	if int(snapshot.get("schema_version", -1)) != 8 or not (snapshot.get("cells", {}) as Dictionary).has("cell_radius_scale"):
		push_error("SmokeTest: schema v8 must persist phenotype arrays")
		instance.queue_free(); return false
	var legacy_snapshot: Dictionary = snapshot.duplicate(true)
	for array_name in ["cell_radius_scale", "cell_stiffness", "cell_color_r", "cell_color_g", "cell_color_b"]:
		(legacy_snapshot.get("cells", {}) as Dictionary).erase(array_name)
	if not bool(save_script.call("restore", legacy_snapshot, manager, env, tick_core)):
		push_error("SmokeTest: legacy snapshot restore failed")
		instance.queue_free(); return false
	var restored_scales: PackedFloat32Array = cells.get("cell_radius_scale") as PackedFloat32Array
	if restored_scales.is_empty() or absf(float(restored_scales[0]) - 1.0) > 0.001:
		push_error("SmokeTest: legacy snapshot must default radius scale to 1.0")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.16.0 runtime phenotype / link limits / schema v8 fallback")
	return true

## v0.17.0：模式列表逐模式编辑、两个子代模式、预览点击跳转，以及 hash 兼容边界。
func _check_v0170_mode_editor_and_preview() -> bool:
	var dev_scene: PackedScene = load("res://scenes/ui/DevEditorPanel.tscn") as PackedScene
	if dev_scene == null:
		push_error("SmokeTest: DevEditorPanel scene missing for v0.17.0 check")
		return false
	var dev: Node = dev_scene.instantiate()
	root.add_child(dev)
	await process_frame
	var draft_ref: RefCounted = dev.get("draft") as RefCounted
	# v0.34.0：默认草案已是单模式 M1 光合自分裂；本项测多模式切换，显式加载 5 模式演示体。
	dev.set("_modes", (load("res://scripts/core/data/Genome.gd") as Script).call("demo_modes"))
	dev.call("select_mode", 0)
	await process_frame
	var modes: Array = dev.call("get_modes") as Array
	if modes.size() < 2:
		push_error("SmokeTest: demo genome must contain multiple modes")
		dev.queue_free(); return false
	var first: Dictionary = modes[0] as Dictionary
	if int(first.get("child1_mode", -1)) < 0 or int(first.get("child2_mode", -1)) < 0 \
		or first.has("child3_mode") or first.has("child4_mode"):
		push_error("SmokeTest: a mode must define exactly two child modes")
		dev.queue_free(); return false
	var hash_before: int = int(draft_ref.call("hash"))
	dev.call("_on_macro_value_changed", 0.33, "transfer_rate")
	dev.call("select_mode", 1)
	if int(dev.call("get_selected_mode")) != 1:
		push_error("SmokeTest: mode switch failed")
		dev.queue_free(); return false
	dev.call("_on_macro_value_changed", 4.2, "division_mass")
	dev.call("select_mode", 0)
	modes = dev.call("get_modes") as Array
	if absf(float((modes[0] as Dictionary).get("transfer_rate", 0.0)) - 0.33) > 0.001 \
		or absf(float((modes[1] as Dictionary).get("division_mass", 0.0)) - 4.2) > 0.001:
		push_error("SmokeTest: per-mode edits leaked or were lost on switch")
		dev.queue_free(); return false
	if int(draft_ref.call("hash")) == hash_before:
		push_error("SmokeTest: mode edits must change gene-mode hash")
		dev.queue_free(); return false

	var preview_node: Node = dev.find_child("GenomePreview", true, false)
	if preview_node == null:
		push_error("SmokeTest: genome preview missing for v0.17.0 check")
		dev.queue_free(); return false
	# v0.23.0：前面的模式编辑把 division_mass 改成 4.2（超出能量上限，不分裂）；
	# 用可分裂阈值副本验证真实模拟预览，保留 clicked_mode 联动检查。
	var sim_modes: Array = []
	for m in dev.call("get_modes"):
		var mc: Dictionary = (m as Dictionary).duplicate(true)
		mc["division_mass"] = 0.05
		sim_modes.append(mc)
	preview_node.call("set_program", [], dev.call("get_macro_draft"), true, sim_modes)
	var state_count: int = int(preview_node.call("get_state_count"))
	# 真实模拟按分裂时刻记录状态，要求至少合子 + 一次分裂。
	if state_count < 2 or int(preview_node.call("get_cell_count_at", state_count - 1)) < 2:
		push_error("SmokeTest: mode preview must simulate multiple division states")
		dev.queue_free(); return false
	var clicked_mode: int = int(preview_node.call("get_mode_at", state_count - 1, 1))
	if clicked_mode < 0:
		push_error("SmokeTest: preview cell must expose its mode index")
		dev.queue_free(); return false
	preview_node.call("emit_signal", "mode_selected", clicked_mode)
	if int(dev.call("get_selected_mode")) != clicked_mode:
		push_error("SmokeTest: preview click did not jump to cell mode")
		dev.queue_free(); return false

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var old_a: RefCounted = genome_script.new() as RefCounted
	var old_b: RefCounted = genome_script.new() as RefCounted
	old_a.set("flags", gene_flag)
	old_b.set("flags", gene_flag)
	old_b.set("transfer_rate", 0.9)
	old_b.call("set_modes", genome_script.call("demo_modes"))
	if int(old_a.call("hash")) != int(old_b.call("hash")):
		push_error("SmokeTest: empty modes must preserve v0.16.0 gene-mode hash")
		dev.queue_free(); return false
	var plain: RefCounted = genome_script.new() as RefCounted
	var tuned: RefCounted = genome_script.new() as RefCounted
	tuned.call("set_modes", genome_script.call("demo_modes"))
	tuned.set("transfer_rate", 0.9)
	if int(plain.call("hash")) != int(tuned.call("hash")):
		push_error("SmokeTest: legacy-mode hash must ignore v0.17.0 fields")
		dev.queue_free(); return false
	dev.queue_free()
	print("SmokeTest: OK v0.17.0 mode editor / two child modes / preview jump / hash boundary")
	return true

## v0.17.1：删除任意模式槽不得崩溃，且剩余槽数量/名称保持一致。
func _check_v0170_mode_remove() -> bool:
	var dev_scene: PackedScene = load("res://scenes/ui/DevEditorPanel.tscn") as PackedScene
	var dev: Node = dev_scene.instantiate()
	root.add_child(dev)
	await process_frame
	# v0.34.0：默认单模式；本项测多槽删除，先补到 5 模式再逐次删。
	while (dev.call("get_modes") as Array).size() < 5:
		dev.call("_on_add_mode")
	var before: int = (dev.call("get_modes") as Array).size()
	if before <= 1:
		push_error("SmokeTest: remove-mode check needs multiple modes")
		dev.queue_free(); return false
	# 删除当前模式、末位模式、中间模式各一次。
	dev.call("_on_remove_mode")
	if (dev.call("get_modes") as Array).size() != before - 1:
		push_error("SmokeTest: remove current mode failed")
		dev.queue_free(); return false
	dev.call("select_mode", (dev.call("get_modes") as Array).size() - 1)
	dev.call("_on_remove_mode")
	if (dev.call("get_modes") as Array).size() != before - 2:
		push_error("SmokeTest: remove last mode failed")
		dev.queue_free(); return false
	dev.call("select_mode", 0)
	dev.call("_on_remove_mode")
	if (dev.call("get_modes") as Array).size() != before - 3:
		push_error("SmokeTest: remove middle mode failed")
		dev.queue_free(); return false
	dev.call("_on_add_mode")
	if (dev.call("get_modes") as Array).size() != before - 2:
		push_error("SmokeTest: add mode after removal failed")
		dev.queue_free(); return false
	var draft_ref: RefCounted = dev.get("draft") as RefCounted
	if not bool(draft_ref.call("is_valid")) or (draft_ref.get("modes") as Array).size() != before - 2:
		push_error("SmokeTest: draft invalid after mode removal")
		dev.queue_free(); return false
	dev.queue_free()
	print("SmokeTest: OK v0.17.1 mode removal")
	return true

## v0.17.0：连接传递真实发生且守恒；模式随 payload、分裂与 schema v8 存档往返。
func _check_v0170_runtime_transfer_and_modes() -> bool:
	var save_script: Script = load("res://scripts/system/SaveManager.gd") as Script
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var codec_script: Script = load("res://scripts/core/data/GenomeCodec.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	manager.set("heterotrophic_intake_rate", 0.0)
	manager.set("photosynthetic_intake_rate", 0.0)
	manager.set("chemotrophic_intake_rate", 0.0)
	manager.set("autonomous_division_cooldown", 1)
	var cells: RefCounted = manager.get("cells") as RefCounted
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
	genome.set("max_divisions", 3)
	genome.call("set_modes", genome_script.call("demo_modes"))
	var base_count: int = int(cells.call("size"))
	var org_id: int = int(manager.call("register_zygote", 7, 7, -1, genome, Vector2.ZERO, 1.0, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.17.0 mode zygote registration failed")
		instance.queue_free(); return false
	for _step in range(30):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells.call("size")) >= base_count + 4:
			break
	if int(cells.call("size")) < base_count + 4 or (cells.get("link_cell_a") as PackedInt32Array).size() < 3:
		push_error("SmokeTest: mode divisions did not produce 4 linked cells")
		instance.queue_free(); return false
	manager.set("autonomous_division_enabled", false)
	var mode_ids: PackedByteArray = cells.get("cell_mode") as PackedByteArray
	if mode_ids.size() <= base_count + 3 or int(mode_ids[base_count]) <= 0:
		push_error("SmokeTest: daughter cells did not inherit child modes")
		instance.queue_free(); return false
	var rates: PackedFloat32Array = manager.call("_build_transfer_rates") as PackedFloat32Array
	if rates.size() != int(cells.call("size")) or rates[base_count] <= 0.0:
		push_error("SmokeTest: mode transfer rate was not derived for linked cells")
		instance.queue_free(); return false
	var donor: int = base_count
	var receiver: int = base_count + 1
	var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
	energies[donor] = 0.8
	energies[receiver] = 0.1
	cells.set("cell_energy", energies)
	var total_before: float = 0.0
	for energy_value in cells.get("cell_energy"):
		total_before += float(energy_value)
	manager.call("advance_physics_tick", 1.0 / 60.0)
	var flow: Dictionary = manager.get("_energy_flow") as Dictionary
	var outgoing: PackedFloat64Array = flow.get("link_out", PackedFloat64Array()) as PackedFloat64Array
	var incoming: PackedFloat64Array = flow.get("link_in", PackedFloat64Array()) as PackedFloat64Array
	if outgoing.size() <= donor or incoming.size() <= receiver or outgoing[donor] <= 0.0 or incoming[receiver] <= 0.0:
		push_error("SmokeTest: linked cells still have zero energy transfer")
		instance.queue_free(); return false
	var total_after: float = 0.0
	for energy_value in cells.get("cell_energy"):
		total_after += float(energy_value)
	if absf(total_after - total_before) > 0.001:
		push_error("SmokeTest: link transfer was not energy conserving (%.6f -> %.6f)" % [total_before, total_after])
		instance.queue_free(); return false

	var command: Dictionary = {
		"genome_bytes": codec_script.call("encode", genome),
		"genome_gene": {"modes": genome.get("modes"), "transfer_rate": 0.33},
	}
	var decoded: RefCounted = manager.call("_genome_from_command", command) as RefCounted
	if decoded == null or not bool(genome_script.call("has_modes", decoded)) \
		or absf(float(decoded.get("transfer_rate")) - 0.33) > 0.001:
		push_error("SmokeTest: mode payload did not survive CommandBus genome path")
		instance.queue_free(); return false

	var snapshot: Dictionary = save_script.call("capture", manager, env, tick_core) as Dictionary
	if int(snapshot.get("schema_version", -1)) != 8 \
		or not (snapshot.get("cells", {}) as Dictionary).has("cell_mode") \
		or (snapshot.get("genomes", []) as Array).is_empty():
		push_error("SmokeTest: schema v8 must persist modes and cell_mode")
		instance.queue_free(); return false
	var stored: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	stored.call("set_modes", [])
	for record in snapshot.get("genomes", []):
		(record as Dictionary)["transfer_rate"] = 0.0
	if not bool(save_script.call("restore", snapshot, manager, env, tick_core)):
		push_error("SmokeTest: v0.17.0 save restore failed")
		instance.queue_free(); return false
	stored = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	var restored_modes: Array = stored.call("get_modes") if stored.has_method("get_modes") else []
	if not bool(genome_script.call("has_modes", stored)) or (stored.get("modes") as Array).is_empty():
		push_error("SmokeTest: modes were lost during save roundtrip")
		instance.queue_free(); return false
	var legacy_snapshot: Dictionary = snapshot.duplicate(true)
	(legacy_snapshot.get("cells", {}) as Dictionary).erase("cell_mode")
	(legacy_snapshot.get("cells", {}) as Dictionary).erase("cell_mode_depth")
	for record in legacy_snapshot.get("genomes", []):
		(record as Dictionary).erase("modes")
	if not bool(save_script.call("restore", legacy_snapshot, manager, env, tick_core)):
		push_error("SmokeTest: legacy snapshot restore failed for v0.17.0 fields")
		instance.queue_free(); return false
	var legacy_modes: PackedByteArray = cells.get("cell_mode") as PackedByteArray
	if legacy_modes.is_empty() or int(legacy_modes[0]) != 0:
		push_error("SmokeTest: legacy snapshot must default cell_mode to 0")
		instance.queue_free(); return false
	instance.queue_free()
	print("SmokeTest: OK v0.17.0 connected transfer / per-mode division / schema v8")
	return true

## v0.18.0：构造「单模式光合带」基因组；cell_cap=-1 表示无限，link_limit=-1 不抑制。
static func _v0180_mode_genome(script: Script, cell_cap: int, telomere: int, link_limit: int, glue: bool) -> RefCounted:
	var genome: RefCounted = script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
	genome.set("division_mass", 0.05)
	genome.set("split_ratio", 0.5)
	genome.set("max_divisions", 8)
	genome.set("max_cells_per_organism", cell_cap)
	genome.set("child_types", PackedByteArray([0, 0, 0, 0]))
	genome.set("split_angles", PackedByteArray([0, 64, 128, 192]))
	var mode: Dictionary = script.call("normalized_mode", {
		"name": "M1_Band", "cell_type": 0,
		"child1_type": 0, "child2_type": 0,
		"child1_mode": 0, "child2_mode": 0,
		"child1_glue": glue, "child2_glue": glue,
		"make_glue": glue,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": link_limit, "telomere": telomere,
	}, 0)
	genome.call("set_modes", [mode])
	return genome

static func _v0180_feed_energy(cells: RefCounted, amount: float, org_id: int) -> void:
	var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
	var alive: PackedByteArray = cells.get("cell_alive") as PackedByteArray
	var org_ids: PackedInt32Array = cells.get("cell_org_id") as PackedInt32Array
	for i in range(energies.size()):
		if alive[i] != 0 and org_ids[i] == org_id:
			energies[i] = amount
	cells.set("cell_energy", energies)

static func _v0180_prepare_manager(instance: Node) -> Dictionary:
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	manager.set("heterotrophic_intake_rate", 0.0)
	manager.set("photosynthetic_intake_rate", 0.0)
	manager.set("chemotrophic_intake_rate", 0.0)
	manager.set("autonomous_division_cooldown", 1)
	return {"manager": manager, "env": env, "tick": tick_core, "cells": manager.get("cells")}

## v0.18.0：移除 8 细胞硬上限；全局容量、连接抑制、端粒、schema v8 与编辑器同测。
func _check_v0180_population_limits() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var cell_array_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene

	# 1) 数据契约：缺省值、端粒离散档、合法性边界与 CellArray 全局容量。
	var default_mode: Dictionary = genome_script.call("normalized_mode", {})
	if int(default_mode.get("link_division_limit", 99)) != -1 or int(default_mode.get("telomere", 99)) != -1:
		push_error("SmokeTest: v0.18.0 legacy mode defaults must keep old behavior")
		return false
	if int(genome_script.call("normalize_telomere", 7)) != 5 or int(genome_script.call("normalize_telomere", 81)) != 80:
		push_error("SmokeTest: telomere must snap to Cell Lab discrete options")
		return false
	var invalid: RefCounted = genome_script.new() as RefCounted
	invalid.set("max_cells_per_organism", 8001)
	if bool(invalid.call("is_valid")):
		push_error("SmokeTest: cell cap above global capacity must be invalid")
		return false
	var array: RefCounted = cell_array_script.new() as RefCounted
	array.set("max_cell_capacity", 3)
	for _i in range(3):
		if int(array.call("append_cell", 0, Vector2.ZERO, 1.0, 0)) < 0:
			push_error("SmokeTest: capacity probe could not fill 3 cells")
			return false
	if int(array.call("append_cell", 0, Vector2.ZERO, 1.0, 0)) != -1 \
		or int(array.call("divide_cell", 0, 0.0, 1.0)) != -1:
		push_error("SmokeTest: global cell capacity must reject append and divide")
		return false

	# 2) 无限个体：单模式光合带应突破旧的 8 细胞硬上限。
	var band: RefCounted = _v0180_mode_genome(genome_script, -1, -1, -1, false)
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var context: Dictionary = _v0180_prepare_manager(instance)
	var manager: Node = context["manager"]
	var cells: RefCounted = context["cells"]
	var base: int = int(cells.call("size"))
	var org_id: int = int(manager.call("register_zygote", 80, 80, -1, band, Vector2(250, 250), 1.5, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.18.0 band zygote failed")
		instance.queue_free(); return false
	for _step in range(60):
		_v0180_feed_energy(cells, 2.0, org_id)
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells.call("size")) >= base + 12:
			break
	if int(cells.call("size")) < base + 12:
		push_error("SmokeTest: unlimited organism must exceed 8 cells (got %d)" % (int(cells.call("size")) - base))
		instance.queue_free(); return false
	instance.queue_free()

	# 3) 显式个体上限仍生效：旧 payload/存档回退值也必须能挡住分裂。
	var capped: RefCounted = _v0180_mode_genome(genome_script, 4, -1, -1, false)
	instance = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	context = _v0180_prepare_manager(instance)
	manager = context["manager"]
	cells = context["cells"]
	base = int(cells.call("size"))
	org_id = int(manager.call("register_zygote", 81, 81, -1, capped, Vector2(250, 250), 1.5, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.18.0 capped zygote failed")
		instance.queue_free(); return false
	for _step in range(30):
		_v0180_feed_energy(cells, 2.0, org_id)
		manager.call("advance_physics_tick", 1.0 / 60.0)
	if int(cells.call("size")) != base + 4:
		push_error("SmokeTest: explicit max_cells_per_organism=4 must cap at 4 cells (got %d)" % int(cells.call("size")))
		instance.queue_free(); return false
	instance.queue_free()

	# 4) 连接数抑制：有 1 条连接即停止分裂，个体上限保持无限。
	var linked: RefCounted = _v0180_mode_genome(genome_script, -1, -1, 1, true)
	instance = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	context = _v0180_prepare_manager(instance)
	manager = context["manager"]
	cells = context["cells"]
	base = int(cells.call("size"))
	org_id = int(manager.call("register_zygote", 82, 82, -1, linked, Vector2(250, 250), 1.5, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.18.0 link-limited zygote failed")
		instance.queue_free(); return false
	for _step in range(30):
		_v0180_feed_energy(cells, 2.0, org_id)
		manager.call("advance_physics_tick", 1.0 / 60.0)
	if int(cells.call("size")) != base + 2 or (cells.get("link_cell_a") as PackedInt32Array).is_empty():
		push_error("SmokeTest: link_division_limit=1 must stop after the first linked pair")
		instance.queue_free(); return false
	instance.queue_free()

	# 5) 端粒：每次母子同减，归零死亡；schema v8 保存新字段并兼容旧快照。
	var mortal: RefCounted = _v0180_mode_genome(genome_script, -1, 5, -1, false)
	instance = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	context = _v0180_prepare_manager(instance)
	manager = context["manager"]
	var env: Node = context["env"]
	var tick_core: Node = context["tick"]
	cells = context["cells"]
	org_id = int(manager.call("register_zygote", 83, 83, -1, mortal, Vector2(250, 250), 1.5, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.18.0 mortal zygote failed")
		instance.queue_free(); return false
	var telomeres: PackedInt32Array = cells.get("cell_telomere") as PackedInt32Array
	if telomeres.is_empty() or int(telomeres[base]) != 5:
		push_error("SmokeTest: initial cell must inherit mode telomere")
		instance.queue_free(); return false
	for _step in range(40):
		_v0180_feed_energy(cells, 2.0, org_id)
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var alive_flags: PackedByteArray = cells.get("cell_alive") as PackedByteArray
	telomeres = cells.get("cell_telomere") as PackedInt32Array
	var telomere_death: bool = false
	for i in range(telomeres.size()):
		if int(telomeres[i]) == 0 and int(alive_flags[i]) == 0:
			telomere_death = true
			break
	if not telomere_death:
		push_error("SmokeTest: exhausted telomere must kill the cell")
		instance.queue_free(); return false

	var save_script: Script = load("res://scripts/system/SaveManager.gd") as Script
	var codec_script: Script = load("res://scripts/core/data/GenomeCodec.gd") as Script
	var snapshot: Dictionary = save_script.call("capture", manager, env, tick_core) as Dictionary
	if int(snapshot.get("schema_version", -1)) != 8 \
		or not (snapshot.get("cells", {}) as Dictionary).has("cell_telomere") \
		or not (snapshot.get("cells", {}) as Dictionary).has("cell_energy_scale"):
		push_error("SmokeTest: schema v8 must persist telomere and energy-radius arrays")
		instance.queue_free(); return false
	var legacy: Dictionary = snapshot.duplicate(true)
	(legacy.get("cells", {}) as Dictionary).erase("cell_telomere")
	for record in legacy.get("genomes", []):
		(record as Dictionary).erase("max_cells_per_organism")
	if not bool(save_script.call("restore", legacy, manager, env, tick_core)):
		push_error("SmokeTest: legacy snapshot restore failed for v0.18.0 fields")
		instance.queue_free(); return false
	var restored_telomeres: PackedInt32Array = cells.get("cell_telomere") as PackedInt32Array
	if restored_telomeres.is_empty() or int(restored_telomeres[0]) != -1:
		push_error("SmokeTest: legacy telomere must default to unlimited")
		instance.queue_free(); return false
	var stored: RefCounted = (manager.get("genomes") as Dictionary).get(org_id) as RefCounted
	if stored == null or int(stored.get("max_cells_per_organism")) != int(stored.get("max_divisions")) + 1:
		push_error("SmokeTest: legacy payload must fall back to max_divisions+1")
		instance.queue_free(); return false

	# CommandBus payload：新字段经 genome_gene 进入运行时；旧 payload 仍回退旧行为。
	var command: Dictionary = {
		"genome_bytes": codec_script.call("encode", mortal),
		"genome_gene": {"modes": mortal.get("modes"), "max_divisions": 3, "max_cells_per_organism": 7},
	}
	var decoded: RefCounted = manager.call("_genome_from_command", command) as RefCounted
	if decoded == null or int(decoded.get("max_cells_per_organism")) != 7:
		push_error("SmokeTest: v0.18.0 command payload did not carry cell cap")
		instance.queue_free(); return false
	(command["genome_gene"] as Dictionary).erase("max_cells_per_organism")
	decoded = manager.call("_genome_from_command", command) as RefCounted
	if decoded == null or int(decoded.get("max_cells_per_organism")) != 4:
		push_error("SmokeTest: legacy command payload must fall back to 4")
		instance.queue_free(); return false
	instance.queue_free()

	# 6) 编辑器：顶层上限与逐模式限制可在同一页设置、切换模式不丢，hash 边界保持。
	var dev_scene: PackedScene = load("res://scenes/ui/DevEditorPanel.tscn") as PackedScene
	var dev: Node = dev_scene.instantiate()
	root.add_child(dev)
	await process_frame
	var draft_ref: RefCounted = dev.get("draft") as RefCounted
	if int(draft_ref.get("max_cells_per_organism")) != -1:
		push_error("SmokeTest: editor default cell cap must be unlimited")
		dev.queue_free(); return false
	dev.call("_on_macro_value_changed", 12.0, "max_cells_per_organism")
	dev.call("_on_macro_value_changed", 5.0, "telomere")
	dev.call("_on_macro_value_changed", 3.0, "link_division_limit")
	dev.call("select_mode", 1)
	dev.call("select_mode", 0)
	var edited_mode: Dictionary = (dev.call("get_modes") as Array)[0] as Dictionary
	if int(draft_ref.get("max_cells_per_organism")) != 12 \
		or int(edited_mode.get("telomere", -1)) != 5 \
		or int(edited_mode.get("link_division_limit", -1)) != 3:
		push_error("SmokeTest: editor v0.18.0 values must persist across mode switch")
		dev.queue_free(); return false
	var controls: Dictionary = dev.get("_macro_controls") as Dictionary
	var cap_control: Dictionary = controls.get("max_cells_per_organism", {})
	if cap_control.has("slider") and absf((cap_control["slider"] as HSlider).get_value() - 12.0) > 0.01:
		push_error("SmokeTest: editor cell cap slider did not refresh")
		dev.queue_free(); return false
	dev.queue_free()

	var gene_flag: int = int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	var plain: RefCounted = genome_script.new() as RefCounted
	var capped_hash: RefCounted = genome_script.new() as RefCounted
	plain.set("flags", gene_flag)
	capped_hash.set("flags", gene_flag)
	capped_hash.set("max_cells_per_organism", 32)
	if int(plain.call("hash")) != int(capped_hash.call("hash")):
		push_error("SmokeTest: empty modes must keep v0.17 hash boundary")
		return false
	var modes_a: RefCounted = genome_script.new() as RefCounted
	var modes_b: RefCounted = genome_script.new() as RefCounted
	modes_a.set("flags", gene_flag)
	modes_b.set("flags", gene_flag)
	modes_a.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	modes_b.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	var hash_mode: Array = [genome_script.call("normalized_mode", {"name": "M1_Hash"}, 0)]
	modes_a.call("set_modes", hash_mode)
	modes_b.call("set_modes", hash_mode)
	modes_b.set("max_cells_per_organism", 32)
	if int(modes_a.call("hash")) == int(modes_b.call("hash")):
		push_error("SmokeTest: cell cap must affect gene-mode hash when modes exist")
		return false

	print("SmokeTest: OK v0.18.0 unlimited organisms / global capacity / link limit / telomere / schema v8 / editor")
	return true

## v0.19.0：半径-能量低通。稳态 = sqrt(E / E_ref)，一阶平滑；基线×因子 = 有效倍率；
## 非基因模式与关闭开关保持固定半径；schema v8 保存新数组且旧档逐位兼容。
func _check_v0190_energy_radius_relaxation() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var save_script: Script = load("res://scripts/system/SaveManager.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var context: Dictionary = _v0180_prepare_manager(instance)
	var manager: Node = context["manager"]
	var env: Node = context["env"]
	var tick_core: Node = context["tick"]
	var cells: RefCounted = context["cells"]
	manager.set("autonomous_division_enabled", false)

	# 1) 基因模式、单模式、cell_size=1.5、division_mass=E_ref=0.05。
	var genome: RefCounted = _v0180_mode_genome(genome_script, 4, -1, -1, false)
	var modes: Array = genome.get("modes") as Array
	var tuned: Dictionary = (modes[0] as Dictionary).duplicate()
	tuned["cell_size"] = 1.5
	tuned["division_mass"] = 0.05
	modes[0] = tuned
	genome.call("set_modes", modes)
	var org_id: int = int(manager.call("register_zygote", 90, 90, -1, genome, Vector2(250, 250), 0.05, 0))
	if org_id < 0:
		push_error("SmokeTest: v0.19.0 zygote failed")
		instance.queue_free(); return false
	var initial_baseline: float = float((cells.get("cell_radius_baseline") as PackedFloat32Array)[0])
	var initial_energy: float = float(cells.call("get_energy_radius_scale", 0))
	var initial_effective: float = float(cells.call("get_radius_scale", 0))
	if absf(initial_baseline - 1.5) > 0.001 or absf(initial_energy - 1.0) > 0.001 or absf(initial_effective - 1.5) > 0.001:
		push_error("SmokeTest: initial radius must be baseline x energy factor")
		instance.queue_free(); return false

	# 2) 能量降到 E_ref/4，稳态因子应平滑趋向 0.5；首 tick 不得直接跳到稳态。
	var energies: PackedFloat32Array = cells.get("cell_energy") as PackedFloat32Array
	energies[0] = 0.0125
	cells.set("cell_energy", energies)
	manager.call("advance_physics_tick", 1.0 / 60.0)
	var after_one: float = float(cells.call("get_energy_radius_scale", 0))
	if after_one >= 0.98 or after_one <= 0.5:
		push_error("SmokeTest: energy radius must converge gradually, not jump")
		instance.queue_free(); return false
	for _step in range(180):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var low_factor: float = float(cells.call("get_energy_radius_scale", 0))
	var low_effective: float = float(cells.call("get_radius_scale", 0))
	if absf(low_factor - 0.5) > 0.01 or absf(low_effective - 0.75) > 0.01:
		push_error("SmokeTest: low-energy steady radius must be baseline x sqrt(1/4)")
		instance.queue_free(); return false

	# 3) 能量回到 E_ref，因子回升到 1.0；饥饿收缩可逆。
	energies = cells.get("cell_energy") as PackedFloat32Array
	energies[0] = 0.05
	cells.set("cell_energy", energies)
	for _step in range(180):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	if absf(float(cells.call("get_energy_radius_scale", 0)) - 1.0) > 0.01:
		push_error("SmokeTest: restored energy must regrow radius")
		instance.queue_free(); return false

	# 4) 关闭开关与 flags 清零：固定半径，不写低通状态。
	manager.set("energy_radius_growth_enabled", false)
	energies = cells.get("cell_energy") as PackedFloat32Array
	energies[0] = 0.0125
	cells.set("cell_energy", energies)
	for _step in range(30):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	if absf(float(cells.call("get_energy_radius_scale", 0)) - 1.0) > 0.0001:
		push_error("SmokeTest: disabled growth must freeze energy factor")
		instance.queue_free(); return false

	# 5) schema v8 保存两个新数组；删掉后旧档回填 baseline=旧有效倍率、factor=1.0。
	var snapshot: Dictionary = save_script.call("capture", manager, env, tick_core) as Dictionary
	var snap_cells: Dictionary = snapshot.get("cells", {}) as Dictionary
	if int(snapshot.get("schema_version", -1)) != 8 \
		or not snap_cells.has("cell_radius_baseline") or not snap_cells.has("cell_energy_scale"):
		push_error("SmokeTest: schema v8 must persist energy-radius arrays")
		instance.queue_free(); return false
	var legacy: Dictionary = snapshot.duplicate(true)
	var legacy_cells: Dictionary = legacy.get("cells", {}) as Dictionary
	legacy_cells.erase("cell_radius_baseline")
	legacy_cells.erase("cell_energy_scale")
	if not bool(save_script.call("restore", legacy, manager, env, tick_core)):
		push_error("SmokeTest: legacy save restore failed")
		instance.queue_free(); return false
	var restored_baseline: float = float((cells.get("cell_radius_baseline") as PackedFloat32Array)[0])
	var restored_factor: float = float(cells.call("get_energy_radius_scale", 0))
	if absf(restored_factor - 1.0) > 0.0001 or absf(restored_baseline - 1.5) > 0.01:
		push_error("SmokeTest: legacy save must map effective scale to baseline with factor 1")
		instance.queue_free(); return false

	# 6) 哈希确定性：相同快照恢复两次，状态 hash 必须一致。
	var hash_a: int = int(manager.call("get_state_hash"))
	if not bool(save_script.call("restore", snapshot, manager, env, tick_core)):
		push_error("SmokeTest: v0.19.0 save restore failed")
		instance.queue_free(); return false
	var hash_b: int = int(manager.call("get_state_hash"))
	if hash_a != hash_b:
		push_error("SmokeTest: energy-radius arrays must be in deterministic hash")
		instance.queue_free(); return false

	instance.queue_free()
	print("SmokeTest: OK v0.19.0 energy-radius lowpass / schema v8")
	return true

## v0.20.0/v0.21.0：per-cell 并行分裂（1/2/4/8 倍增）+ Cell Lab e(double) 半圆出生形状。
## 分裂在 metabolism 阶段、碰撞之后：出生帧母子中心距 0.2r（重叠半圆），下一 tick 被接触排斥弹到 2r。
func _check_v0210_division_doubling_and_split_shape() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var context: Dictionary = _v0180_prepare_manager(instance)
	var manager: Node = context["manager"]
	var tick_core: Node = context["tick"]
	var cells: RefCounted = context["cells"]
	manager.set("default_transfer_rate", 0.0)
	manager.set("autonomous_division_enabled", true)
	var genome: RefCounted = _v0180_mode_genome(genome_script, -1, -1, -1, false)
	var modes: Array = genome.get("modes") as Array
	var tuned: Dictionary = (modes[0] as Dictionary).duplicate()
	tuned["transfer_rate"] = 0.0
	modes[0] = tuned
	genome.call("set_modes", modes)
	manager.call("register_zygote", 91, 91, -1, genome, Vector2(250, 250), 8.0, 0)
	var radii: PackedFloat32Array = PackedFloat32Array()
	var doublings: Dictionary = {}
	var ok: bool = true
	var prev_size: int = 1
	for tick in range(80):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		var current_size: int = int(cells.call("size"))
		if current_size != prev_size:
			doublings[current_size] = true
			if current_size == 2:
				# 出生帧：母子中心距≈0.2r，半径保持母半径（1.0）。
				var px: PackedFloat32Array = cells.get("cell_pos_x") as PackedFloat32Array
				var py: PackedFloat32Array = cells.get("cell_pos_y") as PackedFloat32Array
				var scales: PackedFloat32Array = cells.get("cell_radius_scale") as PackedFloat32Array
				var d: float = Vector2(px[1] - px[0], py[1] - py[0]).length()
				var contact: float = float(manager.get("cell_radius")) * (scales[0] + scales[1])
				if absf(d / contact - 0.1) > 0.02 or absf(scales[0] - 1.0) > 0.01 or absf(scales[1] - 1.0) > 0.01:
					push_error("SmokeTest: v0.21.0 newborn pair must be overlapping half-circles (0.2r)")
					ok = false
			var next_size: int = int(cells.call("size"))
			prev_size = current_size
			if next_size >= 8:
				break
	# 断言出现过 2/4/8 三个规模（per-cell 并行 → 倍增，而非 1/2/3/4 线性）。
	if not (doublings.has(2) and doublings.has(4) and doublings.has(8)):
		push_error("SmokeTest: v0.20.0 division must double 1->2->4->8, got=%s" % str(doublings.keys()))
		ok = false
	# 出生后下一 tick 接触排斥应把重叠圆弹开（用已存在的两细胞场景另测一段）。
	var check_instance: Node = scene.instantiate()
	check_instance.set("create_demo_organism", false)
	root.add_child(check_instance)
	await process_frame
	var ctx2: Dictionary = _v0180_prepare_manager(check_instance)
	var mgr2: Node = ctx2["manager"]
	var cells2: RefCounted = ctx2["cells"]
	mgr2.set("default_transfer_rate", 0.0)
	var genome2: RefCounted = _v0180_mode_genome(genome_script, 2, -1, -1, false)
	var modes2: Array = genome2.get("modes") as Array
	var t2: Dictionary = (modes2[0] as Dictionary).duplicate()
	t2["transfer_rate"] = 0.0
	modes2[0] = t2
	genome2.call("set_modes", modes2)
	mgr2.call("register_zygote", 99, 99, -1, genome2, Vector2(250, 250), 2.0, 0)
	var born_dist: float = -1.0
	for tick in range(20):
		mgr2.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells2.call("size")) == 2 and born_dist < 0.0:
			var px2: PackedFloat32Array = cells2.get("cell_pos_x") as PackedFloat32Array
			var py2: PackedFloat32Array = cells2.get("cell_pos_y") as PackedFloat32Array
			born_dist = Vector2(px2[1] - px2[0], py2[1] - py2[0]).length()
			mgr2.call("advance_physics_tick", 1.0 / 60.0)
			px2 = cells2.get("cell_pos_x") as PackedFloat32Array
			py2 = cells2.get("cell_pos_y") as PackedFloat32Array
			var pushed: float = Vector2(px2[1] - px2[0], py2[1] - py2[0]).length()
			if pushed <= born_dist + 1.0:
				push_error("SmokeTest: v0.21.0 split pair must be pushed apart next tick")
				ok = false
			break
	if born_dist < 0.0:
		push_error("SmokeTest: v0.21.0 two-cell split never observed")
		ok = false
	instance.queue_free()
	check_instance.queue_free()
	if ok:
		print("SmokeTest: OK v0.21.0 division doubling / half-circle birth / contact separation")
	return ok

## v0.22.0：对齐 Cell Lab——去掉 mode max_divisions 的 depth 分裂闸门。
## 旧行为：自增殖模式（子代都回自身）max_divisions=1 时母细胞分裂一次后 depth=1 永久锁死，卡在 4 细胞。
## 新行为：depth 不累加上限，能量充足时能持续倍增；分裂次数只由端粒控制。
func _check_v0220_no_depth_gate() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var context: Dictionary = _v0180_prepare_manager(instance)
	var manager: Node = context["manager"]
	var cells: RefCounted = context["cells"]
	manager.set("default_transfer_rate", 0.0)
	manager.set("autonomous_division_enabled", true)
	# 单模式 M1->M1+M1，max_divisions=1（旧版会锁死在 depth=1）。
	var genome: RefCounted = _v0180_mode_genome(genome_script, -1, -1, -1, true)
	var modes: Array = genome.get("modes") as Array
	var tuned: Dictionary = (modes[0] as Dictionary).duplicate()
	tuned["max_divisions"] = 1
	tuned["transfer_rate"] = 0.0
	modes[0] = tuned
	genome.call("set_modes", modes)
	manager.call("register_zygote", 92, 92, -1, genome, Vector2(250, 250), 8.0, 0)
	var max_seen: int = 1
	var all_depth_zero: bool = true
	for tick in range(40):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		max_seen = maxi(max_seen, int(cells.call("size")))
		var depths: PackedByteArray = cells.get("cell_mode_depth") as PackedByteArray
		var alive: PackedByteArray = cells.get("cell_alive") as PackedByteArray
		for i in range(depths.size()):
			if alive[i] != 0 and depths[i] != 0:
				all_depth_zero = false
		if max_seen >= 8:
			break
	instance.queue_free()
	# 关键断言：旧 depth 闸门会让细胞数卡在 4；去掉后应突破到 >=8。
	if max_seen < 8:
		push_error("SmokeTest: v0.22.0 depth gate must not cap self-proliferation at 4 (max_seen=%d)" % max_seen)
		return false
	if not all_depth_zero:
		push_error("SmokeTest: v0.22.0 self-proliferating cells must keep depth=0")
		return false
	print("SmokeTest: OK v0.22.0 no depth gate / self-proliferation beyond depth=1")
	return true
