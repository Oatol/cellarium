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
const MUTATION_SCRIPT: Script = preload("res://scripts/system/Mutation.gd")
const SPECIES_SCRIPT: Script = preload("res://scripts/system/SpeciesSystem.gd")
const STATISTICS_SCRIPT: Script = preload("res://scripts/system/StatisticsSystem.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const GENOME_CODEC_SCRIPT: Script = preload("res://scripts/core/data/GenomeCodec.gd")
const CELL_SHAPE_SCRIPT: Script = preload("res://scripts/core/data/CellShape.gd")
const SAVE_MANAGER_SCRIPT: Script = preload("res://scripts/system/SaveManager.gd")
const PERF_PROBE_SCRIPT: Script = preload("res://scripts/system/PerfProbe.gd")

var cells: RefCounted = CELL_ARRAY_SCRIPT.new() as RefCounted
var organisms: RefCounted = ORGANISM_STORE_SCRIPT.new() as RefCounted
var genomes: Dictionary = {}
var environment_manager: Node = null
var tick_core: Node = null

## 工具命令诊断计数：仅统计外部干预注入，不进入确定性 hash（干预本身是外部输入）。
var tool_diagnostics: Dictionary = {"SPAWN": 0, "REMOVE": 0, "DRAG": 0, "BOOST": 0, "INSPECT": 0, "ADHERE": 0, "INJECT_GENOME": 0, "INJECT_SIGNAL": 0, "INJECT_SUBSTANCE": 0, "INJECT_COLOR": 0, "SELECT": 0, "ROTATE_SELECTION": 0, "TERRAIN_PAINT": 0, "TERRAIN_ERASE": 0, "STUB": 0}
var last_inspection: Dictionary = {}
var _next_genome_id: int = 1
var energy_ledger: RefCounted = ENERGY_LEDGER_SCRIPT.new() as RefCounted
var predation_diagnostics: Dictionary = {"events": 0, "energy_transferred": 0.0, "energy_to_detritus": 0.0, "deaths": 0}
var species_system: RefCounted = SPECIES_SCRIPT.new() as RefCounted
var statistics: RefCounted = STATISTICS_SCRIPT.new() as RefCounted
var reproduce_diagnostics: Dictionary = {"attempts": 0, "success": 0, "speciations": 0}
## 选择集（阶段5）：当前框选/点选的存活细胞索引，SELECT/ROTATE_SELECTION 真实写入。
var selection: Array[int] = []
var agent_diagnostics: Dictionary = {"commands": 0, "dev_commands": 0}
var perf_probe: RefCounted = PERF_PROBE_SCRIPT.new() as RefCounted

const TOOL_TYPES: Array[String] = ["SPAWN", "REMOVE", "DRAG", "BOOST", "INSPECT", "ADHERE", "INJECT_GENOME", "INJECT_SIGNAL", "INJECT_SUBSTANCE", "INJECT_COLOR", "SELECT", "ROTATE_SELECTION", "TERRAIN_PAINT", "TERRAIN_ERASE"]
## AgentBridge 写入命令与开发者命令（阶段5），均走 CommandBus → apply_command。
const AGENT_COMMAND_TYPES: Array[String] = ["SET_TEMP", "AGENT_SPAWN", "ERASE_AREA", "AGENT_TOOL", "GENE_SET_TRAIT", "GENE_SET_RESPIRATION", "DEV_FORCE_MUTATE", "DEV_FORCE_SPECIATE", "DEV_SPAWN_BATCH", "DEV_DUMP_WORLD"]

var _sim_tick: int = 0
## 行为热路径复用缓冲：避免每 tick 为每枚细胞分配输出数组（性能深化，不改变数学与顺序）。
var _behavior_outputs_flat: PackedFloat32Array = PackedFloat32Array()
## 自主生命周期：发育程序完成后仍按能量阈值分裂/耗尽死亡，避免"建成即静止"。
var _autonomous_division_tick: Dictionary = {}
## 最近一次工具的业务反馈（ADHERE 选点、INSPECT 摘要等），由 HUD 读取显示。
var last_tool_message: String = ""
var adhesion_anchor: int = -1

func _ready() -> void:
	species_system.call("configure", speciation_distance, speciation_cooldown)
	statistics.call("configure", 7200, 30)

@export var dish_center: Vector2 = Vector2.ZERO
@export var dish_radius: float = 512.0
@export_range(0.0, 1.0, 0.01) var boundary_normal_damping: float = 0.5
@export var cell_radius: float = CELL_SHAPE_SCRIPT.REST_RADIUS
@export var base_metabolic_cost: float = 0.006
@export var autonomous_division_enabled: bool = true
@export var autonomous_division_energy: float = 0.16
@export var autonomous_division_cooldown: int = 300
@export var autonomous_max_cells_per_organism: int = 8
@export var autonomous_division_separation: float = 14.0
@export var default_transfer_rate: float = 0.0
@export var facultative_aerobic_efficiency: float = 2.0
@export var anaerobic_toxicity_damage_per_second: float = 0.1
@export var heterotrophic_intake_rate: float = 0.05
@export var photosynthetic_intake_rate: float = 0.02
@export var chemotrophic_intake_rate: float = 0.02
@export var predation_transfer_efficiency: float = 0.8
@export var movement_energy_cost: float = 0.001
## 每 tick 位移上限（世界单位/秒）。神经输出很小，需放大到可见尺度；dt 仍固定 1/60。
@export var max_movement_speed: float = 144.0
@export var predation_attack_threshold: float = 0.35
@export var predation_reach: float = 14.0
@export var predation_max_drain: float = 0.25
@export var decomposition_writeback_rate: float = 1.0
@export var reproduce_energy_threshold: float = 1.2
@export var reproduce_parent_energy_fraction: float = 0.4
@export var speciation_distance: float = 6.0
@export var speciation_cooldown: int = 600

func get_last_inspection() -> Dictionary:
	return (last_inspection as Dictionary).duplicate(true)

func get_last_tool_message() -> String:
	return last_tool_message

func advance_physics_tick(dt: float) -> void:
	_sim_tick += 1
	perf_probe.call("begin_tick")
	# 阶段10：一个 tick 两批（物理前/后），每批一次 GPU 采样 dispatch + 小回读。
	if environment_manager != null:
		environment_manager.call("begin_field_sampling", _field_sample_positions())
	# LOD 神经降频（§2.6）：高倍速下按 tick_core 间隔更新神经，中间 tick 复用上次 intents。
	var update_neural: bool = tick_core == null or bool(tick_core.call("should_update_neural"))
	perf_probe.call("begin", "behavior")
	if update_neural:
		var environment: Dictionary = _build_behavior_environment()
		var needed: int = int(cells.call("size")) * 6
		if _behavior_outputs_flat.size() != needed:
			_behavior_outputs_flat.resize(needed)
		CELL_BEHAVIOR_SCRIPT.call("compute_outputs_flat", cells, environment, _behavior_outputs_flat)
		CELL_BEHAVIOR_SCRIPT.call("apply_outputs_flat", cells, _behavior_outputs_flat, dt, max_movement_speed)
	else:
		CELL_BEHAVIOR_SCRIPT.call("apply_cached_intents", cells, dt, max_movement_speed)
	perf_probe.call("end", "behavior")
	perf_probe.call("begin", "physics")
	CELL_PHYSICS_SCRIPT.call("step", cells, dt)
	CELL_PHYSICS_SCRIPT.call("resolve_collisions", cells, cell_radius)
	CELL_PHYSICS_SCRIPT.call("project_to_dish", cells, dish_center, maxf(1.0, dish_radius - maxf(cell_radius, 1.0)), boundary_normal_damping)
	perf_probe.call("end", "physics")
	perf_probe.call("begin", "metabolism")
	if environment_manager != null:
		environment_manager.call("begin_field_sampling", _field_sample_positions())
	var rates: PackedFloat32Array = PackedFloat32Array()
	rates.resize(int(cells.call("size")))
	rates.fill(default_transfer_rate)
	CELL_METABOLISM_SCRIPT.call("redistribute_link_energy", cells, rates, dt)
	_apply_base_metabolism(dt)
	_apply_environment_metabolism(dt)
	_apply_autonomous_lifecycle()
	perf_probe.call("end", "metabolism")
	perf_probe.call("begin", "predation")
	_apply_predation(dt)
	perf_probe.call("end", "predation")
	perf_probe.call("begin", "signal")
	_apply_signal_secretion(dt)
	perf_probe.call("end", "signal")
	statistics.call("advance_tick", _species_populations())
	perf_probe.call("end_tick")

func _species_populations() -> Dictionary:
	var populations: Dictionary = {}
	var alive: PackedByteArray = organisms.get("org_alive")
	var species_ids: PackedInt32Array = organisms.get("org_species_id")
	for org_id in range(alive.size()):
		if alive[org_id] == 0:
			continue
		var species_id: int = int(species_ids[org_id])
		populations[species_id] = int(populations.get(species_id, 0)) + 1
	return populations

func _field_sample_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(int(cells.call("size"))):
		if alive[cell_index] != 0:
			positions.append(cells.call("get_position", cell_index))
	return positions

func _build_behavior_environment() -> Dictionary:
	## 一次 tick 只建一次空间哈希；neighbors 用 Array 索引替代 Dictionary，减少热路径哈希开销。
	var buckets: Dictionary = CELL_PHYSICS_SCRIPT.call("build_spatial_hash", cells)
	var neighbors: Array[Array] = []
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(int(cells.call("size"))):
		if alive[cell_index] == 0:
			neighbors.append([])
			continue
		var found: Array[int] = CELL_PHYSICS_SCRIPT.call("query_neighbors_cached", cells, cell_index, buckets)
		neighbors.append(found)
	var field_values: Array = []
	for cell_index in range(int(cells.call("size"))):
		if alive[cell_index] == 0:
			field_values.append(PackedFloat32Array())
			continue
		var position: Vector2 = cells.call("get_position", cell_index)
		var sampled: PackedFloat32Array = PackedFloat32Array()
		if environment_manager != null:
			sampled = environment_manager.call("sample_fields", position)
		field_values.append(sampled)
	return {
		"fields_by_cell": field_values,
		"neighbors": neighbors,
		"energy_max": 1.0
	}

func _compute_behavior_outputs() -> Array[PackedFloat32Array]:
	var environment: Dictionary = _build_behavior_environment()
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

## 发育程序完成后，能量充足的成熟个体按确定性的 tick/index 角度自主分裂。
## 不调用全局 RNG，不写除 CommandBus 外的命令通道；死亡仍由能量<=0 触发。
func _apply_autonomous_lifecycle() -> void:
	if not autonomous_division_enabled or autonomous_division_cooldown <= 0:
		return
	var state_map: Dictionary = ORGANISM_STORE_SCRIPT.get_script_constant_map()
	var mature_state: int = int(state_map["STATE_MATURE"])
	var alive: PackedByteArray = cells.get("cell_alive")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var org_alive: PackedByteArray = organisms.get("org_alive")
	var org_state: PackedByteArray = organisms.get("org_state")
	var cell_counts: PackedInt32Array = organisms.get("cell_count")
	var candidates: Array[int] = []
	for cell_index in range(energies.size()):
		if alive[cell_index] == 0 or energies[cell_index] < autonomous_division_energy:
			continue
		var org_id: int = org_ids[cell_index]
		if org_id < 0 or org_id >= org_alive.size() or org_alive[org_id] == 0 or org_state[org_id] != mature_state:
			continue
		if int(cell_counts[org_id]) >= autonomous_max_cells_per_organism:
			continue
		# 首次具备分裂资格时记录起点并跳过本 tick：给发育完成一个 cooldown 宽限期，
		# 否则成熟当 tick 就分裂，会打破"发育程序 9 指令 → 4 细胞 3 连接"的确定性快照。
		if not _autonomous_division_tick.has(org_id):
			_autonomous_division_tick[org_id] = _sim_tick
			continue
		var last_tick: int = int(_autonomous_division_tick[org_id])
		if _sim_tick - last_tick < autonomous_division_cooldown:
			continue
		candidates.append(cell_index)
	for cell_index in candidates:
		if alive[cell_index] == 0 or energies[cell_index] < autonomous_division_energy:
			continue
		var org_id: int = org_ids[cell_index]
		if int(cell_counts[org_id]) >= autonomous_max_cells_per_organism:
			continue
		var angle: float = TAU * fposmod(float(cell_index * 47 + _sim_tick * 13), 360.0) / 360.0
		var child_index: int = int(cells.call("divide_cell", cell_index, angle, autonomous_division_separation))
		if child_index < 0:
			continue
		if not bool(organisms.call("add_developed_cell", org_id, child_index, autonomous_max_cells_per_organism)):
			cells.call("remove_cell", child_index)
			continue
		org_state[org_id] = mature_state
		organisms.set("org_state", org_state)
		cell_counts = organisms.get("cell_count")
		_autonomous_division_tick[org_id] = _sim_tick

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
	var species_id: int = int(organisms.get("org_species_id")[org_id])
	for cell_index in range(int(cells.call("size")) - 1, -1, -1):
		if int(cells.get("cell_org_id")[cell_index]) == org_id and int(cells.get("cell_alive")[cell_index]) != 0:
			var energy: float = float(cells.call("remove_cell", cell_index))
			if energy >= 0.0:
				organisms.call("remove_cell_from_organism", org_id, death_cause)
	if organisms.get("org_alive")[org_id] == 0:
		species_system.call("record_death", species_id, death_cause, _sim_tick)
		statistics.call("record_death", death_cause)
		var remaining: int = _count_alive_organisms_of_species(species_id)
		species_system.call("update_population", species_id, remaining)
		if remaining == 0:
			species_system.call("mark_extinct", species_id, _sim_tick)

func _count_alive_organisms_of_species(species_id: int) -> int:
	var count: int = 0
	var alive: PackedByteArray = organisms.get("org_alive")
	var species_ids: PackedInt32Array = organisms.get("org_species_id")
	for org_id in range(alive.size()):
		if alive[org_id] != 0 and species_ids[org_id] == species_id:
			count += 1
	return count

func register_zygote(genome_id: int, species_id: int, parent_id: int, genome: RefCounted, position: Vector2, energy: float, type_id: int = 0) -> int:
	if genome == null or not bool(genome.call("is_valid")) or genome_id < 0:
		return -1
	var org_id: int = int(organisms.call("create_organism", genome_id, species_id, parent_id, DEVELOPMENT_RULES_SCRIPT.call("initial_lifecycle_state", genome, 1)))
	if org_id < 0:
		return -1
	var cell_index: int = int(cells.call("append_cell", org_id, position, energy, type_id))
	if cell_index < 0:
		return -1
	var stored_genome: RefCounted = genome.duplicate_genome()
	stored_genome.set("species_id", species_id)
	stored_genome.set("lineage_id", int((species_system.call("get_species", species_id) as Dictionary).get("lineage_id", -1)))
	genomes[org_id] = stored_genome
	CELL_BEHAVIOR_SCRIPT.call("initialize_weights", cells, cell_index, int(genome.call("hash")))
	organisms.call("add_developed_cell", org_id, cell_index, int(DEVELOPMENT_RULES_SCRIPT.call("expected_cell_count", genome)))
	if int(species_system.call("species_count")) == 0:
		species_system.call("register_founder", genome, _sim_tick)
	species_system.call("record_birth", species_id, _sim_tick)
	species_system.call("update_population", species_id, 1)
	statistics.call("record_birth")
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

## 细胞编辑草案通过 CommandBus 传入二进制 GNP1；解码失败则回退默认基因组。
func _genome_from_command(command: Dictionary) -> RefCounted:
	if not command.has("genome_bytes"):
		return _default_genome()
	var bytes: PackedByteArray = command.get("genome_bytes")
	var decoded: RefCounted = GENOME_CODEC_SCRIPT.call("decode", bytes) as RefCounted
	if decoded == null:
		return _default_genome()
	return decoded

func _command_type_id(command: Dictionary) -> int:
	return clampi(int(command.get("type_id", 0)), 0, 17)

## 所有外部干预落点都钳制在皿内，保留 cell_radius 余量让细胞完整落在皿中。
func _clamp_to_dish(position: Vector2) -> Vector2:
	var max_radius: float = maxf(1.0, dish_radius - maxf(cell_radius, 1.0))
	var offset: Vector2 = position - dish_center
	if offset.length_squared() <= max_radius * max_radius:
		return position
	return dish_center + offset.normalized() * max_radius

func _apply_tool_command(command: Dictionary) -> int:
	var command_type: String = str(command.get("type", ""))
	var position: Vector2 = _clamp_to_dish(command.get("position", Vector2.ZERO))
	var delta: Vector2 = command.get("delta", Vector2.ZERO)
	match command_type:
		"SPAWN":
			var genome: RefCounted = _genome_from_command(command)
			var org_id: int = register_zygote(_next_genome_id, 0, -1, genome, position, 0.8, _command_type_id(command))
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
				last_tool_message = "细胞诊断：点击位置附近没有细胞"
				return -1
			# 诊断即选中：写入 selection，SelectionLayer 会画圆环高亮（纯视图，不改模拟）。
			selection = [index]
			var org_id: int = int(cells.get("cell_org_id")[index])
			var sampled: PackedFloat32Array = PackedFloat32Array()
			if environment_manager != null:
				sampled = environment_manager.call("sample_fields", cells.call("get_position", index))
			last_inspection = {
				"cell_index": index,
				"org_id": org_id,
				"tick": _sim_tick,
				"energy": float(cells.get("cell_energy")[index]),
				"cell_type": int(cells.get("cell_type")[index]),
				"position": cells.call("get_position", index),
				"radius": cell_radius,
				"links": int(cells.get("cell_link_count")[index]),
				"species_id": int(organisms.get("org_species_id")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_species_id").size()) else -1,
				"age": int(organisms.get("org_age")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_age").size()) else -1,
				"health": float(organisms.get("org_health")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_health").size()) else 0.0,
				"field": sampled.duplicate()
			}
			last_tool_message = "细胞诊断：#%d 能量 %.4f · 类型 %d · 连接 %d" % [
				index, float(last_inspection["energy"]), int(last_inspection["cell_type"]), int(last_inspection["links"])
			]
			tool_diagnostics["INSPECT"] = int(tool_diagnostics["INSPECT"]) + 1
			return index
		"ADHERE":
			var index: int = _nearest_alive_cell(position, 24.0)
			if index < 0:
				last_tool_message = "黏附连接：请点在细胞上"
				return -1
			if adhesion_anchor < 0 or adhesion_anchor >= int(cells.call("size")) or int(cells.get("cell_alive")[adhesion_anchor]) == 0:
				adhesion_anchor = index
				last_tool_message = "黏附连接：已选第一枚 #%d，再点另一枚细胞" % index
				return index
			var a: int = adhesion_anchor
			var b: int = index
			if b == a:
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
					last_tool_message = "黏附连接：第一枚附近没有第二枚细胞"
					return -1
				b = candidates[0]
			var rest_length: float = maxf(14.0, cell_radius * 2.0)
			var linked: bool = bool(cells.call("link_cells", a, b, rest_length))
			if not linked:
				last_tool_message = "黏附连接失败：两细胞需同个体且未连接"
				adhesion_anchor = -1
				return -1
			adhesion_anchor = -1
			last_tool_message = "黏附连接成功：#%d ↔ #%d · 静息长度 %.1f" % [a, b, rest_length]
			tool_diagnostics["ADHERE"] = int(tool_diagnostics["ADHERE"]) + 1
			return b
		"INJECT_GENOME":
			if not command.has("genome_bytes"):
				return -1
			var injected: RefCounted = GENOME_CODEC_SCRIPT.call("decode", command.get("genome_bytes")) as RefCounted
			if injected == null or not bool(injected.call("is_valid")):
				return -1
			var cell_index: int = _nearest_alive_cell(position, 24.0)
			if cell_index < 0:
				return -1
			var target_org: int = int(cells.get("cell_org_id")[cell_index])
			if not genomes.has(target_org):
				return -1
			var previous: RefCounted = genomes[target_org] as RefCounted
			injected.set("lineage_id", int(previous.get("lineage_id")))
			var species_id: int = int(species_system.call("classify", injected, int(previous.get("species_id")), _sim_tick))
			injected.set("species_id", species_id)
			genomes[target_org] = injected
			var species_ids: PackedInt32Array = organisms.get("org_species_id")
			if target_org < species_ids.size():
				species_ids[target_org] = species_id
				organisms.set("org_species_id", species_ids)
			var type_id: int = _command_type_id(command)
			var cell_types: PackedByteArray = cells.get("cell_type")
			var org_ids: PackedInt32Array = cells.get("cell_org_id")
			for i in range(org_ids.size()):
				if int(org_ids[i]) == target_org:
					cell_types[i] = type_id
			cells.set("cell_type", cell_types)
			tool_diagnostics["INJECT_GENOME"] = int(tool_diagnostics["INJECT_GENOME"]) + 1
			return target_org
		"INJECT_SIGNAL":
			if environment_manager == null or not environment_manager.has_method("add_channel_source"):
				return -1
			# 信号注射：可选场通道（默认 4=信号）与注入量；选择改变写入的通道，不是随机。
			var channel: int = clampi(int(command.get("signal_channel", 4)), 0, 4)
			var amount: float = clampf(float(command.get("signal_amount", 0.5)), 0.0, 4.0)
			if amount <= 0.0:
				return -1
			if not bool(environment_manager.call("add_channel_source", position, channel, amount)):
				return -1
			energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_TOOL_TO_ENV, "E_external", "E_env", amount, "tool_inject_signal_ch%d" % channel)
			last_tool_message = "信号注射：通道 %d 注入 %.2f @ (%.1f, %.1f)" % [channel, amount, position.x, position.y]
			tool_diagnostics["INJECT_SIGNAL"] = int(tool_diagnostics["INJECT_SIGNAL"]) + 1
			return channel
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
			# 颜色注射：写入用户选定的表现类型（0..17 官方细胞类型），不再轮转。
			var chosen: int = clampi(int(command.get("color_type", 0)), 0, 17)
			var types: PackedByteArray = cells.get("cell_type")
			types[index] = chosen
			cells.set("cell_type", types)
			last_tool_message = "颜色注射：#%d → 类型 %d" % [index, chosen]
			tool_diagnostics["INJECT_COLOR"] = int(tool_diagnostics["INJECT_COLOR"]) + 1
			return index
		"SELECT":
			# 点选：半径内最近细胞；delta.x>0 表示框选半径由 delta.y 指定。
			var radius: float = maxf(8.0, absf(delta.y))
			var index: int = _nearest_alive_cell(position, radius)
			var next_selection: Array[int] = []
			if index >= 0:
				next_selection.append(index)
			selection = next_selection
			tool_diagnostics["SELECT"] = int(tool_diagnostics["SELECT"]) + 1
			return index
		"ROTATE_SELECTION":
			# 绕选区质心旋转各细胞位置（确定性，角度来自 delta.x）。
			if selection.is_empty():
				return -1
			var center: Vector2 = Vector2.ZERO
			var valid: Array[int] = []
			var alive: PackedByteArray = cells.get("cell_alive")
			for index in selection:
				if index >= 0 and index < alive.size() and alive[index] != 0:
					center += cells.call("get_position", index)
					valid.append(index)
			if valid.is_empty():
				return -1
			center /= float(valid.size())
			var angle: float = deg_to_rad(delta.x)
			for index in valid:
				var offset: Vector2 = cells.call("get_position", index) - center
				cells.call("set_position", index, center + offset.rotated(angle))
			tool_diagnostics["ROTATE_SELECTION"] = int(tool_diagnostics["ROTATE_SELECTION"]) + 1
			return valid.size()
		"TERRAIN_PAINT", "TERRAIN_ERASE":
			if environment_manager == null or not environment_manager.has_method("paint_terrain"):
				return -1
			var solid: bool = command_type == "TERRAIN_PAINT"
			var radius_cells: int = maxi(0, int(delta.x)) if absf(delta.x) > 0.0 else 1
			var changed: int = int(environment_manager.call("paint_terrain", position, radius_cells, solid))
			tool_diagnostics[command_type] = int(tool_diagnostics.get(command_type, 0)) + 1
			return changed
	return -1

## AgentBridge 写入命令与开发者白名单命令（阶段5），在下一 tick 由 CommandBus 调用。
func _apply_agent_command(command: Dictionary) -> int:
	var command_type: String = str(command.get("type", ""))
	var args: Dictionary = command.get("args", {}) as Dictionary
	if args == null:
		args = {}
	agent_diagnostics["commands"] = int(agent_diagnostics["commands"]) + 1
	match command_type:
		"SET_TEMP":
			if environment_manager == null or not environment_manager.has_method("set_temperature_at"):
				return -1
			var position: Vector2 = command.get("position", Vector2.ZERO)
			var value: float = float(command.get("value", args.get("value", 273.0)))
			value = clampf(value, 260.0, 320.0)
			return 0 if bool(environment_manager.call("set_temperature_at", position, value)) else -1
		"AGENT_SPAWN":
			var position: Vector2 = _clamp_to_dish(command.get("position", Vector2.ZERO))
			var count: int = maxi(1, mini(int(command.get("count", args.get("count", 1))), 256))
			var genome: RefCounted = _default_genome()
			var last_id: int = -1
			for i in range(count):
				var offset: Vector2 = Vector2(float(i) * 4.0, 0.0)
				last_id = register_zygote(_next_genome_id, 0, -1, genome, _clamp_to_dish(position + offset), 0.8, 0)
				_next_genome_id += 1
				energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_BIO_TO_BIO, "E_external", "E_bio", 0.8, "agent_spawn")
			return last_id
		"ERASE_AREA":
			var position: Vector2 = command.get("position", Vector2.ZERO)
			var radius: float = clampf(float(args.get("radius", 24.0)), 1.0, 256.0)
			var removed: int = 0
			var alive: PackedByteArray = cells.get("cell_alive")
			var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
			var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
			for index in range(alive.size() - 1, -1, -1):
				if alive[index] == 0:
					continue
				var dx: float = pos_x[index] - position.x
				var dy: float = pos_y[index] - position.y
				if dx * dx + dy * dy <= radius * radius:
					_remove_cell_with_cause(index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_INTERVENTION"]))
					removed += 1
			return removed
		"AGENT_TOOL":
			var tool_id: String = str(args.get("tool_id", ""))
			if tool_id in TOOL_TYPES:
				var forwarded: Dictionary = command.duplicate(true)
				forwarded["type"] = tool_id
				return _apply_tool_command(forwarded)
			return -1
		"GENE_SET_TRAIT":
			return _set_gene_trait(args)
		"GENE_SET_RESPIRATION":
			return _set_gene_respiration(args)
		"DEV_FORCE_MUTATE":
			agent_diagnostics["dev_commands"] = int(agent_diagnostics["dev_commands"]) + 1
			return _dev_force_mutate(args)
		"DEV_FORCE_SPECIATE":
			agent_diagnostics["dev_commands"] = int(agent_diagnostics["dev_commands"]) + 1
			return _dev_force_speciate(args)
		"DEV_SPAWN_BATCH":
			agent_diagnostics["dev_commands"] = int(agent_diagnostics["dev_commands"]) + 1
			var forward: Dictionary = command.duplicate(true)
			forward["count"] = int(args.get("count", 10))
			return _apply_agent_command({"type": "AGENT_SPAWN", "position": command.get("position", Vector2.ZERO), "args": args})
		"DEV_DUMP_WORLD":
			agent_diagnostics["dev_commands"] = int(agent_diagnostics["dev_commands"]) + 1
			return int(get_state_hash())
	return -1

func _set_gene_trait(args: Dictionary) -> int:
	var species_id: int = int(args.get("species_id", 0))
	var trait_name: String = str(args.get("trait_name", ""))
	var level: int = int(args.get("level", 0))
	if level < 0 or level > 255:
		return -1
	var trait_index: int = _trait_name_to_index(trait_name)
	if trait_index < 0:
		return -1
	var changed: int = 0
	for org_id in genomes:
		var genome: RefCounted = genomes[org_id] as RefCounted
		if int(genome.get("species_id")) != species_id:
			continue
		var traits: PackedByteArray = genome.get("traits")
		if trait_index >= traits.size():
			continue
		traits[trait_index] = level
		genome.set("traits", traits)
		changed += 1
	return changed

func _set_gene_respiration(args: Dictionary) -> int:
	var species_id: int = int(args.get("species_id", 0))
	var respiration_type: int = int(args.get("type", 1))
	if respiration_type < 0 or respiration_type > 2:
		return -1
	var changed: int = 0
	for org_id in genomes:
		var genome: RefCounted = genomes[org_id] as RefCounted
		if int(genome.get("species_id")) != species_id:
			continue
		genome.set("respiration", respiration_type)
		changed += 1
	return changed

func _trait_name_to_index(trait_name: String) -> int:
	match trait_name:
		"speed", "速度": return 0
		"sense", "感知": return 1
		"shell", "外壳": return 2
		"attack", "攻击": return 3
		"reproduce", "繁殖": return 4
		"metabolism", "代谢": return 5
		"neural", "神经": return 6
		"temperature", "耐温": return 7
	return -1

func _dev_force_mutate(args: Dictionary) -> int:
	var org_id: int = int(args.get("org_id", -1))
	if not genomes.has(org_id):
		return -1
	var genome: RefCounted = genomes[org_id] as RefCounted
	var mutated: RefCounted = MUTATION_SCRIPT.call("mutate", genome, _next_genome_id, org_id, _sim_tick, 1.0)
	_next_genome_id += 1
	genomes[org_id] = mutated
	return int(mutated.call("hash"))

func _dev_force_speciate(args: Dictionary) -> int:
	var species_id: int = int(args.get("species_id", 0))
	var all_species: Dictionary = species_system.call("get_all_species") as Dictionary
	var representative: RefCounted = (all_species.get(species_id, {}) as Dictionary).get("representative") as RefCounted
	if representative == null:
		return -1
	var far: RefCounted = representative.duplicate_genome()
	var traits: PackedByteArray = far.get("traits")
	for i in range(traits.size()):
		traits[i] = (int(traits[i]) + 100) % 256
	far.set("traits", traits)
	return int(species_system.call("classify", far, species_id, _sim_tick + speciation_cooldown + 1))

func _execute_reproduce(command: Dictionary) -> int:
	## 无性繁殖（v1.0 §5.4 REPRODUCE）：亲代能量达阈值 → 突变子基因组 → 物种判定 → 新受精卵。
	var parent_org_id: int = int(command.get("parent_org_id", command.get("org_id", -1)))
	if parent_org_id < 0 or not genomes.has(parent_org_id):
		return -1
	if organisms.get("org_alive")[parent_org_id] == 0:
		return -1
	reproduce_diagnostics["attempts"] = int(reproduce_diagnostics["attempts"]) + 1
	var parent_genome: RefCounted = genomes[parent_org_id]
	var total_energy: float = cells.call("total_energy_for_org", parent_org_id)
	if total_energy < reproduce_energy_threshold:
		return -1
	var child_genome: RefCounted = MUTATION_SCRIPT.call("mutate", parent_genome, _next_genome_id, parent_org_id, _sim_tick, 0.0)
	if child_genome == null:
		return -1
	var parent_species_id: int = int(organisms.get("org_species_id")[parent_org_id])
	var child_species_id: int = int(species_system.call("classify", child_genome, parent_species_id, _sim_tick))
	if child_species_id < 0:
		return -1
	var origin: Vector2 = Vector2(dish_center.x, dish_center.y)
	if int(cells.get("cell_count")[parent_org_id]) > 0:
		origin = cells.call("get_position", int(cells.get("cell_offset")[parent_org_id]))
	var child_energy: float = total_energy * reproduce_parent_energy_fraction
	var new_org_id: int = register_zygote(_next_genome_id, child_species_id, parent_org_id, child_genome, origin, child_energy, 0)
	if new_org_id < 0:
		return -1
	_next_genome_id += 1
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var remaining: float = total_energy - child_energy
	var parent_cells: int = 0
	for cell_index in range(int(cells.call("size"))):
		if int(cells.get("cell_org_id")[cell_index]) == parent_org_id and int(cells.get("cell_alive")[cell_index]) != 0:
			parent_cells += 1
	if parent_cells > 0:
		var per_cell: float = remaining / float(parent_cells)
		for cell_index in range(int(cells.call("size"))):
			if int(cells.get("cell_org_id")[cell_index]) == parent_org_id and int(cells.get("cell_alive")[cell_index]) != 0:
				energies[cell_index] = per_cell
	cells.set("cell_energy", energies)
	species_system.call("record_birth", child_species_id, _sim_tick)
	species_system.call("update_population", child_species_id, 1)
	reproduce_diagnostics["success"] = int(reproduce_diagnostics["success"]) + 1
	if child_species_id != parent_species_id:
		reproduce_diagnostics["speciations"] = int(reproduce_diagnostics["speciations"]) + 1
	return new_org_id

func apply_command(command: Dictionary) -> int:
	var command_type: String = str(command.get("type", ""))
	if command_type == "REPRODUCE":
		return _execute_reproduce(command)
	if command_type in TOOL_TYPES:
		return _apply_tool_command(command)
	if command_type in AGENT_COMMAND_TYPES:
		return _apply_agent_command(command)
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

func get_reproduce_diagnostics() -> Dictionary:
	return reproduce_diagnostics.duplicate()

func get_species_report() -> Dictionary:
	var all_species: Dictionary = species_system.call("get_all_species") as Dictionary
	var events: Array = species_system.call("get_events") as Array
	return {
		"species_count": int(species_system.call("species_count")),
		"species": all_species,
		"events": events,
		"reproduction": reproduce_diagnostics.duplicate()
	}

func get_species_archive(species_id: int) -> Dictionary:
	return species_system.call("get_archive", species_id) as Dictionary

func export_phylogeny() -> Dictionary:
	return species_system.call("export_phylogeny") as Dictionary

func export_ecology_report() -> Dictionary:
	var archives: Dictionary = {}
	var all_species: Dictionary = species_system.call("get_all_species") as Dictionary
	for species_id in all_species:
		var archive: Dictionary = species_system.call("get_archive", int(species_id)) as Dictionary
		if not archive.is_empty():
			archives[species_id] = archive
	return statistics.call("export_report", archives) as Dictionary

## 存档接口（§3.5 / T08）：tick_core 可为空，此时不捕获 tick 调度状态。
func capture_state(tick_core: Node = null) -> Dictionary:
	return SAVE_MANAGER_SCRIPT.call("capture", self, environment_manager, tick_core) as Dictionary

func restore_state(snapshot: Dictionary, tick_core: Node = null) -> bool:
	return bool(SAVE_MANAGER_SCRIPT.call("restore", snapshot, self, environment_manager, tick_core))

func save_state_to_file(path: String, tick_core: Node = null) -> bool:
	var start_usec: int = Time.get_ticks_usec()
	var result: bool = bool(SAVE_MANAGER_SCRIPT.call("save_to_file", path, capture_state(tick_core)))
	perf_probe.call("record_save", float(Time.get_ticks_usec() - start_usec) / 1000.0)
	return result

func load_state_from_file(path: String, tick_core: Node = null) -> bool:
	var snapshot: Dictionary = SAVE_MANAGER_SCRIPT.call("load_from_file", path) as Dictionary
	if snapshot.is_empty():
		return false
	return restore_state(snapshot, tick_core)

func get_perf_snapshot() -> Dictionary:
	return perf_probe.call("get_metadata") as Dictionary

func export_perf_csv() -> String:
	return str(perf_probe.call("export_csv"))

func get_perf_probe() -> RefCounted:
	return perf_probe

func get_organism_count() -> int:
	var count: int = 0
	for alive in organisms.get("org_alive"):
		if alive != 0:
			count += 1
	return count
