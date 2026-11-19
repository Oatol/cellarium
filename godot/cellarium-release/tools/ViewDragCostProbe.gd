extends SceneTree
## v0.35 诊断：量化拖拽视野卡顿的 CPU 侧成本来源。
## 分别测量：相机 pan、批渲染缓存重建、tick、以及组合路径。
## 运行：console.exe --headless --path <project> --script res://tools/ViewDragCostProbe.gd

const N: int = 512
const PAN_REPEATS: int = 20000
const CACHE_REPEATS: int = 16

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var renderer_script: Script = load("res://scripts/rendering/CellPolygonBatchRenderer.gd") as Script
	var camera_script: Script = load("res://scripts/rendering/CameraController.gd") as Script

	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	manager.native_spatial_enabled = OS.get_environment("CELLARIUM_NATIVE") == "1"
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
			var row_offset: float = float(absi(row) % 2) * 8.0
			var x: float = float(col) * 16.0 + row_offset
			var y: float = float(row) * 13.856
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1

	# 相机实例不入场景树：pan_screen 只读 zoom/rotation/position。
	var camera: Node2D = camera_script.new() as Node2D
	camera.dish_center = Vector2.ZERO
	camera.dish_radius = 256.0
	camera.position = Vector2.ZERO

	# 批渲染缓存：直接引用 manager，绕过 NodePath 解析。
	var renderer: Node2D = renderer_script.new() as Node2D
	renderer.organism_manager = manager

	var t0: int = Time.get_ticks_usec()
	for i in range(PAN_REPEATS):
		camera.call("pan_screen", Vector2(1.0, 0.5))
	var pan_us: float = float(Time.get_ticks_usec() - t0)
	var pan_per_call: float = pan_us / float(PAN_REPEATS)

	t0 = Time.get_ticks_usec()
	for i in range(CACHE_REPEATS):
		renderer.call("_rebuild_cache")
	var cache_us: float = float(Time.get_ticks_usec() - t0)
	var cache_per_call: float = cache_us / float(CACHE_REPEATS)

	var tick_repeats: int = 8
	t0 = Time.get_ticks_usec()
	for i in range(tick_repeats):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var tick_us: float = float(Time.get_ticks_usec() - t0)
	var tick_per_call: float = tick_us / float(tick_repeats)

	# 组合：tick -> cache rebuild -> pan（模拟一帧内同时发生）
	var combo_repeats: int = 8
	t0 = Time.get_ticks_usec()
	for i in range(combo_repeats):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		renderer.call("_rebuild_cache")
		camera.call("pan_screen", Vector2(1.0, 0.5))
	var combo_us: float = float(Time.get_ticks_usec() - t0)
	var combo_per_frame: float = combo_us / float(combo_repeats)

	var cell_count: int = int(manager.get("cells").call("size"))
	var draw_calls: int = 0
	var polys: int = int(renderer.call("get_polygon_count"))
	var chords: int = int(renderer.call("get_chord_count"))
	draw_calls = polys * 3 + int(chords / 2)

	print("VIEW_DRAG: cells=%d polygons=%d chords=%d est_draw_calls=%d native=%s"
		% [cell_count, polys, chords, draw_calls, str(manager.native_spatial_enabled)])
	print("VIEW_DRAG: pan_screen      %10.3f us/call  (x%d)" % [pan_per_call, PAN_REPEATS])
	print("VIEW_DRAG: rebuild_cache   %10.1f us/call  (x%d)" % [cache_per_call, CACHE_REPEATS])
	print("VIEW_DRAG: physics_tick    %10.1f us/tick  (x%d)" % [tick_per_call, tick_repeats])
	print("VIEW_DRAG: combined frame  %10.1f us/frame (x%d)" % [combo_per_frame, combo_repeats])
	quit()
