extends SceneTree
## v0.31.0 end-to-end determinism gate: full-tick state hash parity between
## GDScript (native_spatial_enabled=false) and C++ (true) collision paths.
## Both worlds are constructed identically and stepped with the same inputs.

const TICKS: int = 240

func _make_world(genome_script: Script, native: bool, gene_mode: bool = false, cell_count: int = 40) -> Dictionary:
	var environment: Node = load("res://scripts/system/EnvironmentManager.gd").new() as Node
	environment.nutrient_density = 1.2
	environment.oxygen_fraction = 0.21
	environment._ready()
	var manager: Node = load("res://scripts/system/OrganismManager.gd").new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 300.0
	manager.native_spatial_enabled = native
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	if gene_mode:
		genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
			| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
		genome.set("division_mass", 0.05)
		genome.set("max_divisions", int(genome_script.get_script_constant_map().get("MAX_GENE_DIVISIONS", 8)))
		genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
		genome.call("set_modes", genome_script.call("solo_photo_modes"))
	else:
		genome.call("set_development_program", [])
	# Dense overlapping zygotes to force many collisions.
	for i in range(cell_count):
		var angle: float = float(i) * 0.7
		var r: float = float(i % 8) * 6.0
		manager.call("register_zygote", int(genome.call("hash")), i, -1, genome,
			Vector2(cos(angle), sin(angle)) * r, 0.8, 0)
	return {"environment": environment, "manager": manager}

func _initialize() -> void:
	if not ClassDB.class_exists("CellSpatial"):
		print("NATIVE_E2E: FAIL CellSpatial not registered (DLL missing?)")
		quit(1)
		return
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var fails: int = 0
	var checkpoints: Array[int] = [1, 10, 60, 120, TICKS]
	var scenario: String = "legacy"

	var a: Dictionary = _make_world(genome_script, false)
	var b: Dictionary = _make_world(genome_script, true)
	var ma: Node = a["manager"]; var mb: Node = b["manager"]
	var ea: Node = a["environment"]; var eb: Node = b["environment"]

	# Initial hash must match before any tick.
	if int(ma.call("get_state_hash")) != int(mb.call("get_state_hash")):
		print("NATIVE_E2E: FAIL initial hash differs")
		fails += 1

	for tick in range(1, TICKS + 1):
		ma.call("advance_physics_tick", 1.0 / 60.0)
		ea.call("advance_field_tick")
		mb.call("advance_physics_tick", 1.0 / 60.0)
		eb.call("advance_field_tick")
		if checkpoints.has(tick):
			var ha: int = int(ma.call("get_state_hash"))
			var hb: int = int(mb.call("get_state_hash"))
			var cells_a: int = int(ma.call("get_organism_count"))
			var cells_b: int = int(mb.call("get_organism_count"))
			var ok: bool = (ha == hb)
			print("NATIVE_E2E: %s tick=%d gd=%d cpp=%d match=%s orgs=%d/%d" % [scenario, tick, ha, hb, str(ok), cells_a, cells_b])
			if not ok:
				fails += 1

	ma.free(); mb.free(); ea.free(); eb.free()

	# v0.34.0: cover gene-mode M1 self-division, where transfer-rate,
	# energy-radius and lifecycle candidate caches are actually consumed.
	scenario = "m1_photo"
	checkpoints = [1, 2, 10, 60, 300, 302, 600, 602, 700]
	a = _make_world(genome_script, false, true, 8)
	b = _make_world(genome_script, true, true, 8)
	ma = a["manager"]; mb = b["manager"]
	ea = a["environment"]; eb = b["environment"]
	if int(ma.call("get_state_hash")) != int(mb.call("get_state_hash")):
		print("NATIVE_E2E: FAIL %s initial hash differs" % scenario)
		fails += 1
	for tick in range(1, 701):
		ma.call("advance_physics_tick", 1.0 / 60.0)
		ea.call("advance_field_tick")
		mb.call("advance_physics_tick", 1.0 / 60.0)
		eb.call("advance_field_tick")
		if checkpoints.has(tick):
			var m1_ha: int = int(ma.call("get_state_hash"))
			var m1_hb: int = int(mb.call("get_state_hash"))
			var orgs_a: int = int(ma.call("get_organism_count"))
			var orgs_b: int = int(mb.call("get_organism_count"))
			var m1_cells_a: int = int(ma.get("cells").call("size"))
			var m1_cells_b: int = int(mb.get("cells").call("size"))
			var m1_ok: bool = (m1_ha == m1_hb) and m1_cells_a == m1_cells_b
			print("NATIVE_E2E: %s tick=%d gd=%d cpp=%d match=%s cells=%d/%d orgs=%d/%d" % [scenario, tick, m1_ha, m1_hb, str(m1_ok), m1_cells_a, m1_cells_b, orgs_a, orgs_b])
			if not m1_ok:
				fails += 1
	ma.free(); mb.free(); ea.free(); eb.free()

	print("NATIVE_E2E: %s (failures=%d)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
