extends SceneTree
## v0.31.0 end-to-end determinism gate: full-tick state hash parity between
## GDScript (native_spatial_enabled=false) and C++ (true) collision paths.
## Both worlds are constructed identically and stepped with the same inputs.

const TICKS: int = 240

func _make_world(genome_script: Script, native: bool) -> Dictionary:
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
	genome.call("set_development_program", [])
	# Dense overlapping zygotes to force many collisions.
	for i in range(40):
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
			print("NATIVE_E2E: tick=%d gd=%d cpp=%d match=%s orgs=%d/%d" % [tick, ha, hb, str(ok), cells_a, cells_b])
			if not ok:
				fails += 1

	ma.free(); mb.free(); ea.free(); eb.free()
	print("NATIVE_E2E: %s (failures=%d)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
