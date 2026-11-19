extends SceneTree
## v0.35 parity: CellRenderCache.rebuild() vs GDScript _rebuild_cache_gdscript().
## View-only data: compare positions/radii/links and polygon point counts with tolerance.
## Run: console.exe --headless --path <project> --script res://tools/RenderCacheParityProbe.gd

const N: int = 320

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var renderer_script: Script = load("res://scripts/rendering/CellPolygonBatchRenderer.gd") as Script
	var env: Node = environment_script.new() as Node
	env._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = env
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 256.0
	manager.cell_radius = 8.0
	manager.native_spatial_enabled = false
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome_script.call("solo_photo_modes"))
	var spawned: int = 0
	for row in range(-12, 13):
		for col in range(-12, 13):
			if spawned >= N:
				break
			var x: float = float(col) * 16.0 + float(absi(row) % 2) * 8.0
			var y: float = float(row) * 13.856
			if x * x + y * y > 180.0 * 180.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1
	for i in range(6):
		manager.call("advance_physics_tick", 1.0 / 60.0)

	var renderer: Node2D = renderer_script.new() as Node2D
	renderer.organism_manager = manager
	manager.set("cell_radius", 8.0)
	manager.set("dish_center", Vector2.ZERO)
	manager.set("dish_radius", 256.0)

	# GDScript reference
	renderer.call("_rebuild_cache_gdscript")
	var gd_poly: Array = renderer.get("_polygons").duplicate()
	var gd_outline: Array = renderer.get("_outlines").duplicate()
	var gd_centers: PackedVector2Array = (renderer.get("_centers") as PackedVector2Array).duplicate()
	var gd_radii: PackedFloat32Array = (renderer.get("_radii") as PackedFloat32Array).duplicate()
	var gd_links: PackedVector2Array = (renderer.get("_links") as PackedVector2Array).duplicate()
	var gd_chords: int = int(renderer.get("_last_chord_count"))

	# C++ path
	var cells: RefCounted = manager.get("cells") as RefCounted
	if not ClassDB.class_exists("CellRenderCache"):
		print("RENDER_CACHE_PARITY: FAIL CellRenderCache not registered")
		quit()
	var cache: RefCounted = ClassDB.instantiate("CellRenderCache") as RefCounted
	var cell_size: float = float((load("res://scripts/system/CellPhysics.gd") as Script).get_script_constant_map().get("SPATIAL_HASH_CELL_SIZE", 64.0))
	var cpp: Dictionary = cache.call("rebuild",
		cells.get("cell_alive"), cells.get("cell_pos_x"), cells.get("cell_pos_y"),
		cells.get("cell_radius_scale"), cells.get("cell_type"), cells.get("cell_org_id"),
		cells.get("cell_color_r"), cells.get("cell_color_g"), cells.get("cell_color_b"),
		cells.get("cell_energy"), cells.get("link_cell_a"), cells.get("link_cell_b"),
		8.0, 0.0, 0.0, 256.0, cell_size, 12, 8000) as Dictionary

	var checked: int = 0
	var failures: int = 0
	if int(cpp.get("polygons", []).size()) != gd_poly.size():
		print("RENDER_CACHE_PARITY: FAIL polygons %d vs %d" % [int(cpp.get("polygons", []).size()), gd_poly.size()])
		failures += 1
	var cpp_poly: Array = cpp["polygons"]
	var cpp_outline: Array = cpp["outlines"]
	var cpp_centers: PackedVector2Array = cpp["centers"]
	var cpp_radii: PackedFloat32Array = cpp["radii"]
	var cpp_links: PackedVector2Array = cpp["links"]
	for i in range(mini(gd_poly.size(), cpp_poly.size())):
		var a: PackedVector2Array = gd_poly[i]
		var b: PackedVector2Array = cpp_poly[i]
		checked += 1
		if a.size() != b.size():
			failures += 1
			continue
		for p in range(a.size()):
			checked += 1
			if absf(a[p].x - b[p].x) > 0.01 or absf(a[p].y - b[p].y) > 0.01:
				failures += 1
		var ao: PackedVector2Array = gd_outline[i]
		var bo: PackedVector2Array = cpp_outline[i]
		checked += 1
		if ao.size() != bo.size():
			failures += 1
	for i in range(mini(gd_centers.size(), cpp_centers.size())):
		checked += 1
		if gd_centers[i].distance_to(cpp_centers[i]) > 0.01:
			failures += 1
	for i in range(mini(gd_radii.size(), cpp_radii.size())):
		checked += 1
		if absf(gd_radii[i] - cpp_radii[i]) > 0.01:
			failures += 1
	if gd_links.size() != cpp_links.size():
		failures += 1
	else:
		for i in range(gd_links.size()):
			checked += 1
			if gd_links[i].distance_to(cpp_links[i]) > 0.01:
				failures += 1
	if gd_chords != int(cpp.get("chord_count", -1)):
		print("RENDER_CACHE_PARITY: FAIL chords gd=%d cpp=%d" % [gd_chords, int(cpp.get("chord_count", -1))])
		failures += 1

	print("RENDER_CACHE_PARITY: checked=%d failures=%d cells=%d polys=%d" % [checked, failures, N, gd_poly.size()])
	if failures == 0:
		print("RENDER_CACHE_PARITY: OK")
	else:
		print("RENDER_CACHE_PARITY: FAIL")
	quit()
