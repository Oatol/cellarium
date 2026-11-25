extends SceneTree
## v0.41 诊断：M1 光合场景下 metab_env 副作用循环内部各步骤耗时细分。
## 复刻 _apply_environment_metabolism_ranges 的 native 副作用循环，用局部副本数组
## 分段计时，不写回 manager，纯诊断。headless 跑：console.exe --headless --path <proj> --script res://tools/MetabEnvMicroProbe.gd

const N: int = 1025
const REPEAT: int = 60

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var env_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var metabolism_script: Script = load("res://scripts/system/CellMetabolism.gd") as Script
	var ledger_script: Script = load("res://scripts/system/EnergyLedger.gd") as Script
	var env: Node = env_script.new() as Node
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
	for row in range(-16, 17):
		for col in range(-16, 17):
			if spawned >= N:
				break
			var x: float = float(col) * 16.0 + float(absi(row) % 2) * 8.0
			var y: float = float(row) * 13.856
			if x * x + y * y > 200.0 * 200.0:
				continue
			manager.call("register_zygote", spawned, 0, -1, genome, Vector2(x, y), 1.0, 0)
			spawned += 1
	for i in range(4):
		manager.call("advance_physics_tick", 1.0 / 60.0)
	var cells: RefCounted = manager.get("cells") as RefCounted
	var count: int = int(cells.call("size"))
	var alive: PackedByteArray = cells.get("cell_alive")
	var types: PackedByteArray = cells.get("cell_type")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var energies: PackedFloat32Array = (cells.get("cell_energy") as PackedFloat32Array).duplicate()
	var health: PackedFloat32Array = (manager.get("organisms") as RefCounted).get("org_health").duplicate()
	# 构造 food_gains / movement_costs / toxic_flags（光合场景典型值）
	var food_gains: PackedFloat64Array = PackedFloat64Array()
	var movement_costs: PackedFloat64Array = PackedFloat64Array()
	var toxic_flags: PackedByteArray = PackedByteArray()
	food_gains.resize(count)
	movement_costs.resize(count)
	toxic_flags.resize(count)
	for i in range(count):
		food_gains[i] = 0.0008 if alive[i] != 0 else 0.0
		movement_costs[i] = 0.00015 if alive[i] != 0 else 0.0
		toxic_flags[i] = 0
	var flow_prod: PackedFloat64Array = PackedFloat64Array()
	var flow_self: PackedFloat64Array = PackedFloat64Array()
	flow_prod.resize(count)
	flow_self.resize(count)
	var ledger: RefCounted = ledger_script.new() as RefCounted
	var ledger_b: RefCounted = ledger_script.new() as RefCounted
	# 预热两者到稳态 entries（_max_entries），避免首轮 append 与后续 pop_front 不可比。
	for i in range(256):
		ledger.call("record", "ENV_TO_BIO", "E_env", "E_bio", 0.0001, "warmup")
		ledger_b.call("record", "ENV_TO_BIO", "E_env", "E_bio", 0.0001, "warmup")
	var positive_gains: PackedFloat64Array = PackedFloat64Array()
	for i in range(count):
		if alive[i] != 0 and food_gains[i] > 0.0:
			positive_gains.append(food_gains[i])
	var acc_ledger_batch: int = 0
	var acc_read: int = 0
	var acc_read_us: int = 0
	var acc_energy: int = 0
	var acc_flow: int = 0
	var acc_ledger: int = 0
	var acc_health: int = 0
	var DT: float = 1.0 / 60.0
	var TOXIC: float = float(manager.get("anaerobic_toxicity_damage_per_second"))
	for rep in range(REPEAT):
		var e: PackedFloat32Array = energies.duplicate()
		var h: PackedFloat32Array = health.duplicate()
		var fp: PackedFloat64Array = flow_prod.duplicate()
		var fs: PackedFloat64Array = flow_self.duplicate()
		var t0: int = Time.get_ticks_usec()
		for i in range(count):
			if alive[i] == 0:
				continue
			var gain: float = float(food_gains[i])
			var cost: float = float(movement_costs[i])
			acc_read += int(gain > 0.0)
		var t1: int = Time.get_ticks_usec()
		acc_read_us += t1 - t0
		for i in range(count):
			if alive[i] == 0:
				continue
			var gain: float = float(food_gains[i])
			if gain > 0.0:
				e[i] += gain
			var cost: float = float(movement_costs[i])
			e[i] = maxf(0.0, e[i] - cost)
		var t2: int = Time.get_ticks_usec()
		for i in range(count):
			if alive[i] == 0:
				continue
			var gain: float = float(food_gains[i])
			var cost: float = float(movement_costs[i])
			if gain > 0.0:
				fp[i] += gain
			fs[i] += cost
		var t3: int = Time.get_ticks_usec()
		for i in range(count):
			if alive[i] == 0:
				continue
			var gain: float = float(food_gains[i])
			if gain > 0.0:
				ledger.call("record", "ENV_TO_BIO", "E_env", "E_bio", gain, "intake_type_4")
		var t4: int = Time.get_ticks_usec()
		ledger_b.call("record_batch", "ENV_TO_BIO", "E_env", "E_bio", positive_gains, "intake_type_4")
		var t4b: int = Time.get_ticks_usec()
		for i in range(count):
			if alive[i] == 0:
				continue
			if toxic_flags[i] != 0:
				var oid: int = org_ids[i]
				h[oid] = maxf(0.0, h[oid] - TOXIC * DT)
		var t5: int = Time.get_ticks_usec()
		acc_energy += t2 - t1
		acc_flow += t3 - t2
		acc_ledger += t4 - t3
		acc_ledger_batch += t4b - t4
		acc_health += t5 - t4b
	print("METAB_MICRO cells=%d repeat=%d" % [count, REPEAT])
	print("METAB_MICRO read_us=%.1f" % (float(acc_read_us) / float(REPEAT)))
	print("METAB_MICRO energy_us=%.1f" % (float(acc_energy) / float(REPEAT)))
	print("METAB_MICRO flow_us=%.1f" % (float(acc_flow) / float(REPEAT)))
	print("METAB_MICRO ledger_record_us=%.1f" % (float(acc_ledger) / float(REPEAT)))
	print("METAB_MICRO ledger_batch_us=%.1f" % (float(acc_ledger_batch) / float(REPEAT)))
	print("METAB_MICRO health_us=%.1f" % (float(acc_health) / float(REPEAT)))
	print("METAB_MICRO gain_positive=%d" % acc_read)
	quit()
