extends Node
## 主线程内拥有个体、细胞与基因组状态；CommandBus 下一 tick 调用 apply_command。

const CELL_ARRAY_SCRIPT: Script = preload("res://scripts/core/data/CellArray.gd")
const ORGANISM_STORE_SCRIPT: Script = preload("res://scripts/core/data/OrganismStore.gd")
const DEVELOPMENT_RULES_SCRIPT: Script = preload("res://scripts/core/data/DevelopmentRules.gd")
const CELL_PHYSICS_SCRIPT: Script = preload("res://scripts/system/CellPhysics.gd")
const CELL_METABOLISM_SCRIPT: Script = preload("res://scripts/system/CellMetabolism.gd")
const CELL_BEHAVIOR_SCRIPT: Script = preload("res://scripts/system/CellBehavior.gd")
const RESPIRATION_RULES_SCRIPT: Script = preload("res://scripts/system/RespirationRules.gd")
const PREDATION_SCRIPT: Script = preload("res://scripts/system/Predation.gd")
const ENERGY_LEDGER_SCRIPT: Script = preload("res://scripts/system/EnergyLedger.gd")

var cells: RefCounted = CELL_ARRAY_SCRIPT.new() as RefCounted
var organisms: RefCounted = ORGANISM_STORE_SCRIPT.new() as RefCounted
var genomes: Dictionary = {}
var environment_manager: Node = null

## 工具命令诊断计数：仅统计外部干预注入，不进入确定性 hash（干预本身是外部输入）。
var tool_diagnostics: Dictionary = {"SPAWN": 0, "REMOVE": 0, "DRAG": 0, "BOOST": 0, "INSPECT": 0, "ADHERE": 0, "INJECT_SIGNAL": 0, "INJECT_SUBSTANCE": 0, "INJECT_COLOR": 0, "STUB": 0}
var last_inspection: Dictionary = {}
var _next_genome_id: int = 1
var energy_ledger: RefCounted = ENERGY_LEDGER_SCRIPT.new() as RefCounted
var predation_diagnostics: Dictionary = {"events": 0, "energy_transferred": 0.0, "energy_to_detritus": 0.0, "deaths": 0}

const TOOL_TYPES: Array[String] = ["SPAWN", "REMOVE", "DRAG", "BOOST", "INSPECT", "ADHERE", "INJECT_SIGNAL", "INJECT_SUBSTANCE", "INJECT_COLOR", "SELECT", "ROTATE_SELECTION", "TERRAIN_PAINT", "TERRAIN_ERASE"]

@export var dish_center: Vector2 = Vector2.ZERO
@export var dish_radius: float = 512.0
@export_range(0.0, 1.0, 0.01) var boundary_normal_damping: float = 0.5
@export var cell_radius: float = 1.0
@export var base_metabolic_cost: float = 0.001
@export var default_transfer_rate: float = 0.0
@export var facultative_aerobic_efficiency: float = 2.0
@export var anaerobic_toxicity_damage_per_second: float = 0.1
@export var heterotrophic_intake_rate: float = 0.05
@export var photosynthetic_intake_rate: float = 0.02
@export var chemotrophic_intake_rate: float = 0.02
@export var predation_transfer_efficiency: float = 0.8
@export var movement_energy_cost: float = 0.001
@export var predation_attack_threshold: float = 0.35
@export var predation_reach: float = 14.0
@export var predation_max_drain: float = 0.25
@export var decomposition_writeback_rate: float = 1.0

func advance_physics_tick(dt: float) -> void:
	var behavior_outputs: Array[PackedFloat32Array] = _compute_behavior_outputs()
	CELL_BEHAVIOR_SCRIPT.call("apply_outputs", cells, behavior_outputs, dt)
	CELL_PHYSICS_SCRIPT.call("step", cells, dt)
	CELL_PHYSICS_SCRIPT.call("resolve_collisions", cells, cell_radius)
	CELL_PHYSICS_SCRIPT.call("project_to_dish", cells, dish_center, dish_radius, boundary_normal_damping)
	var rates: PackedFloat32Array = PackedFloat32Array()
	rates.resize(int(cells.call("size")))
	rates.fill(default_transfer_rate)
	CELL_METABOLISM_SCRIPT.call("redistribute_link_energy", cells, rates, dt)
	_apply_base_metabolism(dt)
	_apply_environment_metabolism(dt)
	_apply_predation(dt)
	_apply_signal_secretion(dt)

func _compute_behavior_outputs() -> Array[PackedFloat32Array]:
	var neighbors: Dictionary = {}
	for cell_index in range(int(cells.call("size"))):
		neighbors[cell_index] = CELL_PHYSICS_SCRIPT.call("query_neighbors", cells, cell_index)
	var field_values: Array = []
	for cell_index in range(int(cells.call("size"))):
		if int(cells.get("cell_alive")[cell_index]) == 0:
			field_values.append(PackedFloat32Array())
			continue
		var position: Vector2 = cells.call("get_position", cell_index)
		var sampled: PackedFloat32Array = PackedFloat32Array()
		if environment_manager != null:
			sampled = environment_manager.call("sample_fields", position)
		field_values.append(sampled)
	var environment: Dictionary = {"fields_by_cell": field_values, "neighbors": neighbors, "energy_max": 1.0}
	return CELL_BEHAVIOR_SCRIPT.call("compute_outputs", cells, environment)

func _apply_base_metabolism(dt: float) -> void:
	if dt <= 0.0:
		return
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var alive: PackedByteArray = cells.get("cell_alive")
	var deltas: PackedFloat32Array = PackedFloat32Array()
	deltas.resize(energies.size())
	var range_count: int = mini(OS.get_processor_count(), energies.size())
	if range_count > 1:
		var task_ids: PackedInt32Array = PackedInt32Array()
		for range_index in range(range_count):
			var first: int = int(float(energies.size() * range_index) / float(range_count))
			var last: int = int(float(energies.size() * (range_index + 1)) / float(range_count))
			task_ids.append(WorkerThreadPool.add_task(_compute_base_metabolism_range.bind(first, last, dt, energies, alive, deltas), false, "cellarium metabolism %d" % range_index))
		for task_id in task_ids:
			WorkerThreadPool.wait_for_task_completion(task_id)
	else:
		_compute_base_metabolism_range(0, energies.size(), dt, energies, alive, deltas)
	for cell_index in range(energies.size()):
		if alive[cell_index] != 0:
			energies[cell_index] = maxf(0.0, energies[cell_index] + deltas[cell_index])
	cells.set("cell_energy", energies)
	for cell_index in range(energies.size() - 1, -1, -1):
		if alive[cell_index] != 0 and energies[cell_index] <= 0.0:
			_remove_cell_with_cause(cell_index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_STARVATION"]))

func _compute_base_metabolism_range(first: int, last: int, dt: float, _energies: PackedFloat32Array, alive: PackedByteArray, deltas: PackedFloat32Array) -> void:
	for cell_index in range(first, last):
		if alive[cell_index] != 0:
			deltas[cell_index] = -base_metabolic_cost * dt

func _apply_environment_metabolism(dt: float) -> void:
	var snapshots: Array[PackedFloat32Array] = []
	var count: int = int(cells.call("size"))
	snapshots.resize(count)
	for cell_index in range(count):
		snapshots[cell_index] = PackedFloat32Array()
		snapshots[cell_index].resize(5)
	var range_count: int = mini(OS.get_processor_count(), count)
	if range_count > 1:
		var sample_task_ids: PackedInt32Array = PackedInt32Array()
		for range_index in range(range_count):
			var first: int = int(float(count * range_index) / float(range_count))
			var last: int = int(float(count * (range_index + 1)) / float(range_count))
			sample_task_ids.append(WorkerThreadPool.add_task(_sample_environment_range.bind(first, last, snapshots), false, "cellarium field sample %d" % range_index))
		for task_id in sample_task_ids:
			WorkerThreadPool.wait_for_task_completion(task_id)
	else:
		_sample_environment_range(0, count, snapshots)
	_apply_environment_metabolism_ranges(dt, snapshots)

func _sample_environment_range(first: int, last: int, snapshots: Array[PackedFloat32Array]) -> void:
	for cell_index in range(first, last):
		if cells.get("cell_alive")[cell_index] == 0:
			continue
		var position: Vector2 = Vector2(cells.get("cell_pos_x")[cell_index], cells.get("cell_pos_y")[cell_index])
		snapshots[cell_index] = environment_manager.call("sample_fields", position)

func _apply_environment_metabolism_ranges(dt: float, field_samples: Array[PackedFloat32Array]) -> void:
	if environment_manager == null or dt <= 0.0:
		return
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var types: PackedByteArray = cells.get("cell_type")
	var positions: PackedFloat32Array = cells.get("cell_pos_x")
	var positions_y: PackedFloat32Array = cells.get("cell_pos_y")
	var health: PackedFloat32Array = organisms.get("org_health")
	var respiration_values: PackedByteArray = PackedByteArray()
	respiration_values.resize(organisms.get("org_alive").size())
	for org_id in genomes:
		respiration_values[int(org_id)] = int(genomes[org_id].get("respiration"))
	for cell_index in range(energies.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = org_ids[cell_index]
		var field_values: PackedFloat32Array = field_samples[cell_index]
		var oxygen: float = clampf(float(field_values[2]), 0.0, 1.0)
		var respiration: Dictionary = RESPIRATION_RULES_SCRIPT.call("evaluate", int(respiration_values[org_id]), oxygen, facultative_aerobic_efficiency)
		var food_gain: float = 0.0
		if types[cell_index] == 0:
			food_gain = maxf(0.0, float(field_values[0])) * heterotrophic_intake_rate * float(respiration.get("efficiency", 0.0)) * dt
		elif types[cell_index] == 1:
			food_gain = maxf(0.0, float(field_values[3])) * photosynthetic_intake_rate * dt
		elif types[cell_index] == 2:
			food_gain = maxf(0.0, float(field_values[4])) * chemotrophic_intake_rate * dt
		if food_gain > 0.0:
			var consumed: float = food_gain
			if types[cell_index] == 0:
				consumed = float(environment_manager.call("consume_nutrient", Vector2(positions[cell_index], positions_y[cell_index]), food_gain))
			elif types[cell_index] == 2:
				consumed = float(environment_manager.call("consume_signal", Vector2(positions[cell_index], positions_y[cell_index]), food_gain))
			energies[cell_index] += consumed
			if consumed > 0.0:
				energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_ENV_TO_BIO, "E_env", "E_bio", consumed, "intake_type_%d" % int(types[cell_index]))
		var intents: PackedFloat32Array = CELL_BEHAVIOR_SCRIPT.call("get_intents", cells, cell_index)
		var movement: float = absf(float(intents[0]))
		var movement_cost: float = movement_energy_cost * movement * movement * dt
		energies[cell_index] = maxf(0.0, energies[cell_index] - movement_cost)
		if bool(respiration.get("toxic", false)):
			health[org_id] = maxf(0.0, health[org_id] - anaerobic_toxicity_damage_per_second * dt)
	organisms.set("org_health", health)
	cells.set("cell_energy", energies)
	for org_id in range(health.size() - 1, -1, -1):
		if organisms.get("org_alive")[org_id] != 0 and health[org_id] <= 0.0:
			_remove_organism_cells(org_id, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_TOXICITY"]))

func _apply_predation(dt: float) -> void:
	if dt <= 0.0:
		return
	var events: Array[Dictionary] = PREDATION_SCRIPT.call("resolve_predation", cells, CELL_PHYSICS_SCRIPT,
		predation_transfer_efficiency, predation_attack_threshold, predation_reach, predation_max_drain)
	if events.is_empty():
		return
	for event in events:
		var drained: float = float(event.get("drained", 0.0))
		var gain: float = float(event.get("gain", 0.0))
		var loss: float = float(event.get("loss_to_detritus", 0.0))
		var prey_index: int = int(event.get("prey", -1))
		energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_BIO, "E_bio", "E_bio", gain, "predation_gain")
		if loss > 0.0:
			energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_ENV, "E_bio", "E_detritus", loss, "predation_loss")
		predation_diagnostics["events"] = int(predation_diagnostics["events"]) + 1
		predation_diagnostics["energy_transferred"] = float(predation_diagnostics["energy_transferred"]) + gain
		predation_diagnostics["energy_to_detritus"] = float(predation_diagnostics["energy_to_detritus"]) + loss
		## 猎物被榨干则记捕食死亡（能量已由 resolve_predation 扣除）。
		if prey_index >= 0 and float(cells.get("cell_energy")[prey_index]) <= 0.0001:
			_remove_cell_with_cause(prey_index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_PREDATION"]))
			predation_diagnostics["deaths"] = int(predation_diagnostics["deaths"]) + 1

func _apply_signal_secretion(dt: float) -> void:
	if environment_manager == null or dt <= 0.0 or not environment_manager.has_method("add_signal_source"):
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var intent: PackedFloat32Array = CELL_BEHAVIOR_SCRIPT.call("get_intents", cells, cell_index)
		var amount: float = maxf(0.0, float(intent[3])) * dt
		if amount > 0.0:
			environment_manager.call("add_signal_source", Vector2(pos_x[cell_index], pos_y[cell_index]), amount)

func _remove_organism_cells(org_id: int, death_cause: int) -> void:
	for cell_index in range(int(cells.call("size")) - 1, -1, -1):
		if int(cells.get("cell_org_id")[cell_index]) == org_id and int(cells.get("cell_alive")[cell_index]) != 0:
			var energy: float = float(cells.call("remove_cell", cell_index))
			if energy >= 0.0:
				organisms.call("remove_cell_from_organism", org_id, death_cause)

func register_zygote(genome_id: int, species_id: int, parent_id: int, genome: RefCounted, position: Vector2, energy: float, type_id: int = 0) -> int:
	if genome == null or not bool(genome.call("is_valid")) or genome_id < 0:
		return -1
	var org_id: int = int(organisms.call("create_organism", genome_id, species_id, parent_id, DEVELOPMENT_RULES_SCRIPT.call("initial_lifecycle_state", genome, 1)))
	if org_id < 0:
		return -1
	var cell_index: int = int(cells.call("append_cell", org_id, position, energy, type_id))
	if cell_index < 0:
		return -1
	genomes[org_id] = genome.duplicate_genome()
	CELL_BEHAVIOR_SCRIPT.call("initialize_weights", cells, cell_index, int(genome.call("hash")))
	organisms.call("add_developed_cell", org_id, cell_index, int(DEVELOPMENT_RULES_SCRIPT.call("expected_cell_count", genome)))
	return org_id

func _nearest_alive_cell(position: Vector2, max_distance: float) -> int:
	## 返回距 position 最近且存活的细胞索引；超出 max_distance 返回 -1。线性扫描，稳定顺序。
	var best_index: int = -1
	var best_distance_sq: float = max_distance * max_distance
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var dx: float = pos_x[cell_index] - position.x
		var dy: float = pos_y[cell_index] - position.y
		var distance_sq: float = dx * dx + dy * dy
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best_index = cell_index
	return best_index

func _default_genome() -> RefCounted:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	return genome

func _apply_tool_command(command: Dictionary) -> int:
	var command_type: String = str(command.get("type", ""))
	var position: Vector2 = command.get("position", Vector2.ZERO)
	var delta: Vector2 = command.get("delta", Vector2.ZERO)
	match command_type:
		"SPAWN":
			var genome: RefCounted = _default_genome()
			var org_id: int = register_zygote(_next_genome_id, 0, -1, genome, position, 0.8, 0)
			if org_id < 0:
				return -1
			_next_genome_id += 1
			energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_BIO, "E_external", "E_bio", 0.8, "tool_spawn")
			tool_diagnostics["SPAWN"] = int(tool_diagnostics["SPAWN"]) + 1
			return org_id
		"REMOVE":
			var index: int = _nearest_alive_cell(position, 24.0)
			if index < 0:
				return -1
			_remove_cell_with_cause(index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_INTERVENTION"]))
			tool_diagnostics["REMOVE"] = int(tool_diagnostics["REMOVE"]) + 1
			return index
		"DRAG":
			var index: int = _nearest_alive_cell(position - delta, 24.0)
			if index < 0:
				return -1
			cells.call("set_position", index, position)
			tool_diagnostics["DRAG"] = int(tool_diagnostics["DRAG"]) + 1
			return index
		"BOOST":
			var index: int = _nearest_alive_cell(position, 24.0)
			if index < 0:
				return -1
			var energies: PackedFloat32Array = cells.get("cell_energy")
			var before: float = float(energies[index])
			energies[index] = maxf(0.0, energies[index] + 0.3)
			var added: float = float(energies[index]) - before
			cells.set("cell_energy", energies)
			if added > 0.0:
				energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_BIO, "E_external", "E_bio", added, "tool_boost")
			tool_diagnostics["BOOST"] = int(tool_diagnostics["BOOST"]) + 1
			return index
		"INSPECT":
			var index: int = _nearest_alive_cell(position, 24.0)
			if index < 0:
				return -1
			last_inspection = {
				"cell_index": index,
				"org_id": int(cells.get("cell_org_id")[index]),
				"energy": float(cells.get("cell_energy")[index]),
				"cell_type": int(cells.get("cell_type")[index]),
				"position": cells.call("get_position", index)
			}
			tool_diagnostics["INSPECT"] = int(tool_diagnostics["INSPECT"]) + 1
			return index
		"ADHERE":
			var a: int = _nearest_alive_cell(position, 24.0)
			if a < 0:
				return -1
			var b: int = _nearest_alive_cell(position, 24.0)
			if b < 0:
				return -1
			var candidates: Array[int] = []
			var alive: PackedByteArray = cells.get("cell_alive")
			var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
			var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
			for cell_index in range(alive.size()):
				if cell_index == a or alive[cell_index] == 0:
					continue
				var dx: float = pos_x[cell_index] - pos_x[a]
				var dy: float = pos_y[cell_index] - pos_y[a]
				if dx * dx + dy * dy <= 24.0 * 24.0:
					candidates.append(cell_index)
			if candidates.is_empty():
				return -1
			b = candidates[0]
			var linked: bool = bool(cells.call("link_cells", a, b, 8.0))
			if not linked:
				return -1
			tool_diagnostics["ADHERE"] = int(tool_diagnostics["ADHERE"]) + 1
			return b
		"INJECT_SIGNAL":
			if environment_manager == null or not environment_manager.has_method("add_signal_source"):
				return -1
			environment_manager.call("add_signal_source", position, maxf(0.0, 0.5))
			tool_diagnostics["INJECT_SIGNAL"] = int(tool_diagnostics["INJECT_SIGNAL"]) + 1
			return 0
		"INJECT_SUBSTANCE":
			if environment_manager == null or environment_manager.get("field") == null:
				return -1
			var field: RefCounted = environment_manager.get("field")
			var grid: Vector2i = field.call("get_grid_position", position)
			var accepted: bool = bool(field.call("add_source", 0, grid.x, grid.y, 2.0))
			if not accepted:
				return -1
			energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_TOOL_TO_ENV, "E_external", "E_env", 2.0, "tool_inject_substance")
			tool_diagnostics["INJECT_SUBSTANCE"] = int(tool_diagnostics["INJECT_SUBSTANCE"]) + 1
			return 0
		"INJECT_COLOR":
			var index: int = _nearest_alive_cell(position, 24.0)
			if index < 0:
				return -1
			var types: PackedByteArray = cells.get("cell_type")
			var next_type: int = int(types[index]) + 1
			if next_type > 254:
				next_type = 0
			types[index] = next_type
			cells.set("cell_type", types)
			tool_diagnostics["INJECT_COLOR"] = int(tool_diagnostics["INJECT_COLOR"]) + 1
			return index
		"SELECT", "ROTATE_SELECTION", "TERRAIN_PAINT", "TERRAIN_ERASE":
			tool_diagnostics["STUB"] = int(tool_diagnostics["STUB"]) + 1
			return -2
	return -1

func apply_command(command: Dictionary) -> int:
	var command_type: String = str(command.get("type", ""))
	if command_type in TOOL_TYPES:
		return _apply_tool_command(command)
	var org_id: int = int(command.get("org_id", -1))
	if not genomes.has(org_id):
		return -1
	if command.get("type", "") == "DIVIDE":
		var result: int = int(DEVELOPMENT_RULES_SCRIPT.call("execute_divide", genomes[org_id], cells, organisms, command))
		if result >= 0:
			organisms.get("org_dev_cursor")[org_id] += 1
			DEVELOPMENT_RULES_SCRIPT.call("_update_maturity", genomes[org_id], organisms, org_id)
		return result
	if command.get("type", "") == "DEVELOPMENT_INSTRUCTION":
		return int(DEVELOPMENT_RULES_SCRIPT.call("execute_instruction", genomes[org_id], cells, organisms, command))
	return -1

func advance_development_tick() -> int:
	var executed: int = 0
	for org_id in range(organisms.get("org_alive").size()):
		if organisms.get("org_alive")[org_id] == 0 or organisms.get("org_state")[org_id] != ORGANISM_STORE_SCRIPT.get_script_constant_map()["STATE_DEVELOPING"]:
			continue
		if not genomes.has(org_id):
			continue
		var cursor: int = int(organisms.get("org_dev_cursor")[org_id])
		var program: Array = genomes[org_id].get("dev_program")
		if cursor >= program.size():
			continue
		var result: int = int(DEVELOPMENT_RULES_SCRIPT.call("execute_instruction", genomes[org_id], cells, organisms, {"type": "DEVELOPMENT_INSTRUCTION", "org_id": org_id, "instruction_index": cursor}))
		if result >= 0:
			executed += 1
	return executed

func _remove_cell_with_cause(cell_index: int, death_cause: int) -> float:
	if cell_index < 0 or cell_index >= int(cells.call("size")) or int(cells.get("cell_alive")[cell_index]) == 0:
		return -1.0
	var org_id: int = int(cells.get("cell_org_id")[cell_index])
	var position: Vector2 = cells.call("get_position", cell_index)
	var energy: float = float(cells.call("remove_cell", cell_index))
	if energy < 0.0 or not bool(organisms.call("remove_cell_from_organism", org_id, death_cause)):
		return -1.0
	## 死亡分解：剩余生物量按转化率写回营养场（E_bio -> E_env），不凭空生成能量。
	if energy > 0.0 and environment_manager != null and decomposition_writeback_rate > 0.0:
		var writeback: float = energy * decomposition_writeback_rate
		if environment_manager.has_method("add_nutrient_source"):
			environment_manager.call("add_nutrient_source", position, writeback)
		elif environment_manager.get("field") != null:
			var field: RefCounted = environment_manager.get("field")
			var grid: Vector2i = field.call("get_grid_position", position)
			field.call("add_source", 0, grid.x, grid.y, writeback)
		energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_ENV, "E_bio", "E_env", writeback, "decomposition")
	return energy

func remove_cell(cell_index: int) -> float:
	return _remove_cell_with_cause(cell_index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_NONE"]))

func evaluate_organism_respiration(org_id: int, oxygen_fraction: float) -> Dictionary:
	if org_id < 0 or org_id >= organisms.get("org_alive").size() or organisms.get("org_alive")[org_id] == 0 or not genomes.has(org_id):
		return {"valid": false, "efficiency": 0.0, "toxic": false, "budget_cost": 0}
	return RESPIRATION_RULES_SCRIPT.call("evaluate", int(genomes[org_id].get("respiration")), oxygen_fraction)

func get_state_hash() -> int:
	var hash_value: int = 0x811c9dc5
	for value in cells.get("cell_pos_x"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("cell_pos_y"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("cell_prev_x"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("cell_prev_y"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("cell_energy"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("cell_alive"):
		hash_value = _hash_int(hash_value, int(value))
	for value in cells.get("cell_org_id"):
		hash_value = _hash_int(hash_value, int(value))
	for value in cells.get("cell_type"):
		hash_value = _hash_int(hash_value, int(value))
	for value in cells.get("neural_weights"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for value in cells.get("behavior_intents"):
		hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for array_name in ["link_cell_a", "link_cell_b", "link_rest_length"]:
		for value in cells.get(array_name):
			var quantized: int = int(round(float(value) * 1000000.0)) if array_name == "link_rest_length" else int(value)
			hash_value = _hash_int(hash_value, quantized)
	for array_name in ["org_alive", "org_genome_id", "org_species_id", "org_parent_id", "org_age", "org_health", "org_death_cause", "org_state", "org_instruction_mask", "org_dev_cursor", "cell_offset", "cell_count"]:
		for value in organisms.get(array_name):
			var quantized: int = int(round(float(value) * 1000000.0)) if array_name == "org_age" or array_name == "org_health" else int(value)
			hash_value = _hash_int(hash_value, quantized)
	for org_id in range(organisms.get("org_alive").size()):
		if genomes.has(org_id):
			hash_value = _hash_int(hash_value, int(genomes[org_id].call("hash")))
	return hash_value

func _hash_int(hash_value: int, value: int) -> int:
	var result: int = hash_value
	for shift in [0, 8, 16, 24]:
		result = int((result ^ ((value >> shift) & 255)) * 0x01000193) & 0xffffffff
	return result

func get_energy_ledger_snapshot() -> Dictionary:
	return energy_ledger.call("get_snapshot") as Dictionary

func assert_energy_conservation(tolerance: float = 0.01) -> bool:
	return bool(energy_ledger.call("assert_conservation", tolerance))

func get_predation_diagnostics() -> Dictionary:
	return predation_diagnostics.duplicate()

func get_organism_count() -> int:
	var count: int = 0
	for alive in organisms.get("org_alive"):
		if alive != 0:
			count += 1
	return count
