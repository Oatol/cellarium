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

## 营养摄入类型 ID：与 CellVisualCatalog.entries() 对齐。
## v0.13.0 修正：此前把体细胞 1 当光合、肌细胞 2 当化能，导致光合细胞不产能。
const CELL_TYPE_ZYGOTE: int = 0
const CELL_TYPE_PHOTOCYTE: int = 4
const CELL_TYPE_NITROCYTE: int = 10
const CELL_TYPE_FLAGELLOCYTE: int = 3

var cells: RefCounted = CELL_ARRAY_SCRIPT.new() as RefCounted
var organisms: RefCounted = ORGANISM_STORE_SCRIPT.new() as RefCounted
var genomes: Dictionary = {}
var environment_manager: Node = null
var tick_core: Node = null

## 工具命令诊断计数：仅统计外部干预注入，不进入确定性 hash（干预本身是外部输入）。
var tool_diagnostics: Dictionary = {"SPAWN": 0, "REMOVE": 0, "DRAG": 0, "BOOST": 0, "INSPECT": 0, "ADHERE": 0, "INJECT_GENOME": 0, "INJECT_SIGNAL": 0, "INJECT_SUBSTANCE": 0, "INJECT_COLOR": 0, "SELECT": 0, "CLEAR_SELECTION": 0, "ROTATE_SELECTION": 0, "TERRAIN_PAINT": 0, "TERRAIN_ERASE": 0, "STUB": 0}
var last_inspection: Dictionary = {}
## v0.14.1 只读能量流诊断：每个 tick 覆盖写，只供生态报告展示；不写模拟真相源、不进 hash / 存档。
## production = 环境摄入 + 捕食获得；self_cost = 基础代谢 + 运动；
## link_out / link_in = 连接转账；predation_drain = 被捕食抽走的能量。
var _energy_flow: Dictionary = {
	"tick": -1,
	"production": PackedFloat64Array(),
	"self_cost": PackedFloat64Array(),
	"link_out": PackedFloat64Array(),
	"link_in": PackedFloat64Array(),
	"predation_drain": PackedFloat64Array(),
}
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

const TOOL_TYPES: Array[String] = ["SPAWN", "REMOVE", "DRAG", "BOOST", "INSPECT", "ADHERE", "INJECT_GENOME", "INJECT_SIGNAL", "INJECT_SUBSTANCE", "INJECT_COLOR", "SELECT", "CLEAR_SELECTION", "ROTATE_SELECTION", "TERRAIN_PAINT", "TERRAIN_ERASE"]
## AgentBridge 写入命令与开发者命令（阶段5），均走 CommandBus → apply_command。
const AGENT_COMMAND_TYPES: Array[String] = ["SET_TEMP", "AGENT_SPAWN", "ERASE_AREA", "AGENT_TOOL", "GENE_SET_TRAIT", "GENE_SET_RESPIRATION", "DEV_FORCE_MUTATE", "DEV_FORCE_SPECIATE", "DEV_SPAWN_BATCH", "DEV_DUMP_WORLD"]

var _sim_tick: int = 0
## v0.31.0 原生加速开关（GDExtension CellSpatial）。默认 false = 纯 GDScript，
## 与 v0.30.0 状态 hash 逐位一致；置 true 走 C++ 碰撞/邻域，需先通过 state hash 对照。
## DLL 缺失或类未注册时自动回退 GDScript，不会导致启动失败。
@export var native_spatial_enabled: bool = false
var _native_spatial: RefCounted = null
var _native_spatial_checked: bool = false

func _get_native_spatial() -> RefCounted:
	if not native_spatial_enabled:
		return null
	if not _native_spatial_checked:
		_native_spatial_checked = true
		if ClassDB.class_exists("CellSpatial"):
			_native_spatial = ClassDB.instantiate("CellSpatial") as RefCounted
	return _native_spatial

## 行为热路径复用缓冲：避免每 tick 为每枚细胞分配输出数组（性能深化，不改变数学与顺序）。
var _behavior_outputs_flat: PackedFloat32Array = PackedFloat32Array()
## v0.20.0：分裂调度改为逐细胞 CellArray.cell_division_tick；旧的按个体串行字典已移除，
## 让所有成熟且能量达标的细胞在同一 tick 各自分裂，得到 Cell Lab 式 1/2/4/8 倍增。
## 最近一次工具的业务反馈（ADHERE 选点、INSPECT 摘要等），由 HUD 读取显示。
var last_tool_message: String = ""
var adhesion_anchor: int = -1

func _ready() -> void:
	species_system.call("configure", speciation_distance, speciation_cooldown)
	statistics.call("configure", 7200, 30)
	cells.set("max_cell_capacity", maxi(1, global_cell_capacity))

@export var dish_center: Vector2 = Vector2.ZERO
@export var dish_radius: float = 512.0
@export_range(0.0, 1.0, 0.01) var boundary_normal_damping: float = 0.5
@export var cell_radius: float = CELL_SHAPE_SCRIPT.REST_RADIUS
@export var base_metabolic_cost: float = 0.006
@export var autonomous_division_enabled: bool = true
@export var autonomous_division_energy: float = 0.16
@export var autonomous_division_cooldown: int = 300
## v0.18.0：旧的 per-organism 硬上限已废弃；-1 表示不再按 8 细胞截断个体。
@export var autonomous_max_cells_per_organism: int = -1
## v0.18.0：全局容量保护；达到后所有新增细胞/分裂路径一律拒绝。
@export var global_cell_capacity: int = 8000
## v0.19.0：半径-能量低通。对应 Cell Lab `CellWorld.f(double)`：目标倍率 d_target =
## sqrt(w / division_mass)，一阶低通（系数 relax_rate·dt）。仅 gene_mode 启用，
## 非基因模式保持 v0.18 固定表型倍率，逐位不变。所有运算为确定性标量，不写 RNG。
@export var energy_radius_growth_enabled: bool = true
@export var energy_radius_relax_rate: float = 5.0
@export var energy_radius_min_scale: float = 0.5
@export var energy_radius_max_scale: float = 1.0
@export var autonomous_division_separation: float = 14.0
@export var default_transfer_rate: float = 0.0
@export var facultative_aerobic_efficiency: float = 2.0
@export var anaerobic_toxicity_damage_per_second: float = 0.1
@export var heterotrophic_intake_rate: float = 0.05
## v0.14.1：原 0.02 产能偏低，光合细胞在默认光强下净收益接近 0；调到 0.08，
## 使充分光照时接近异养效率，但逐 tick 仍受光场与 DECAY[3]=0 约束，不改能量守恒。
@export var photosynthetic_intake_rate: float = 0.08
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

## 诊断锁定时按当前模拟状态派生实时快照（只读）：last_inspection 只记录点击瞬间的细胞索引，
## 面板刷新时按该索引重采样，避免「实时 tick 会动但下面信息不刷新」。不写模拟状态、不进 hash。
func get_live_inspection() -> Dictionary:
	var base: Dictionary = (last_inspection as Dictionary).duplicate(true)
	if base.is_empty() or selection.is_empty():
		return base
	var index: int = int(base.get("cell_index", -1))
	if index < 0 or index >= int(cells.call("size")):
		return base
	if int(cells.get("cell_alive")[index]) == 0:
		return base
	var org_id: int = int(cells.get("cell_org_id")[index])
	var sampled: PackedFloat32Array = PackedFloat32Array()
	if environment_manager != null:
		sampled = environment_manager.call("sample_fields", cells.call("get_position", index))
	base["tick"] = _sim_tick
	base["energy"] = float(cells.get("cell_energy")[index])
	base["cell_type"] = int(cells.get("cell_type")[index])
	base["position"] = cells.call("get_position", index)
	base["radius"] = cell_radius
	base["links"] = int(cells.get("cell_link_count")[index])
	base["species_id"] = int(organisms.get("org_species_id")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_species_id").size()) else -1
	base["age"] = int(organisms.get("org_age")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_age").size()) else -1
	base["health"] = float(organisms.get("org_health")[org_id]) if org_id >= 0 and org_id < int(organisms.get("org_health").size()) else 0.0
	base["field"] = sampled.duplicate()
	# v0.14.1：只读能量流明细，随 tick 更新；不重算模拟。
	for key in ["production", "self_cost", "link_out", "link_in", "predation_drain"]:
		base[key] = _energy_flow_value(key, index)
	base["energy_flow_tick"] = int(_energy_flow.get("tick", -1))
	return base

func get_last_tool_message() -> String:
	return last_tool_message

## 每 tick 覆盖一次诊断缓冲。长度变化（分裂/回收）时重建，避免越界写入。
func _reset_energy_flow(count: int) -> void:
	for key in ["production", "self_cost", "link_out", "link_in", "predation_drain"]:
		var values: PackedFloat64Array = PackedFloat64Array()
		values.resize(count)
		_energy_flow[key] = values
	_energy_flow["tick"] = _sim_tick

func _energy_flow_add(key: String, cell_index: int, amount: float) -> void:
	if cell_index < 0 or amount == 0.0 or not _energy_flow.has(key):
		return
	var values: PackedFloat64Array = _energy_flow[key]
	if cell_index >= values.size():
		return
	values[cell_index] += amount

func _energy_flow_value(key: String, cell_index: int) -> float:
	if cell_index < 0 or not _energy_flow.has(key):
		return 0.0
	var values: PackedFloat64Array = _energy_flow[key]
	return float(values[cell_index]) if cell_index < values.size() else 0.0

func advance_physics_tick(dt: float) -> void:
	_sim_tick += 1
	_reset_energy_flow(int(cells.call("size")))
	perf_probe.call("begin_tick")
	# 阶段10：一个 tick 两批（物理前/后），每批一次 GPU 采样 dispatch + 小回读。
	if environment_manager != null:
		environment_manager.call("begin_field_sampling_indexed", _field_sample_positions(), _field_sample_cell_indices())
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
	var native_spatial: RefCounted = _get_native_spatial()
	if native_spatial != null:
		# v0.31.0：C++ 碰撞求解，逐位等价已由 spatial_parity_probe 验证（SPATIAL_HASH_CELL_SIZE=64）。
		var coll: Dictionary = native_spatial.call("resolve_collisions",
			cells.get("cell_pos_x"), cells.get("cell_pos_y"), cells.get("cell_alive"),
			cells.get("cell_radius_scale"), cells.get("cell_stiffness"),
			cell_radius, 64.0, 6)
		cells.set("cell_pos_x", coll["pos_x"])
		cells.set("cell_pos_y", coll["pos_y"])
	else:
		CELL_PHYSICS_SCRIPT.call("resolve_collisions", cells, cell_radius, cells.get("cell_radius_scale"), cells.get("cell_stiffness"))
	CELL_PHYSICS_SCRIPT.call("project_to_dish", cells, dish_center, maxf(1.0, dish_radius - maxf(cell_radius, 1.0)), boundary_normal_damping, cells.get("cell_radius_scale"), cell_radius)
	perf_probe.call("end", "physics")
	perf_probe.call("begin", "metabolism")
	if environment_manager != null:
		environment_manager.call("begin_field_sampling_indexed", _field_sample_positions(), _field_sample_cell_indices())
	# v0.17.0：按细胞所属模式的 transfer_rate 派生传递率；无 modes 的旧基因组保持 0，
	# 因此 v0.14–v0.16 的确定性能量账本不被悄悄改写。
	var rates: PackedFloat32Array = _build_transfer_rates()
	CELL_METABOLISM_SCRIPT.call("redistribute_link_energy", cells, rates, dt, _energy_flow)
	_apply_base_metabolism(dt)
	_apply_environment_metabolism(dt)
	_apply_energy_radius_relaxation(dt)
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

## v0.30.0：与 _field_sample_positions() 一一对应的活细胞索引，供 O(1) 场采样查找。
func _field_sample_cell_indices() -> Array[int]:
	var indices: Array[int] = []
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(int(cells.call("size"))):
		if alive[cell_index] != 0:
			indices.append(cell_index)
	return indices

## v0.17.0：连接传递率真相源。新多模式基因组逐模式配置；旧基因组保持 v0.14–v0.16 行为。
func _build_transfer_rates() -> PackedFloat32Array:
	var count: int = int(cells.call("size"))
	var rates: PackedFloat32Array = PackedFloat32Array()
	rates.resize(count)
	rates.fill(0.0)
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var mode_ids: PackedByteArray = cells.get("cell_mode")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var genome: RefCounted = genomes.get(int(org_ids[cell_index]), null) as RefCounted
		if genome == null:
			continue
		if bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
			if bool(GENOME_SCRIPT.call("has_modes", genome)):
				var mode_id: int = 0 if cell_index >= mode_ids.size() else int(mode_ids[cell_index])
				var mode: Dictionary = GENOME_SCRIPT.call("get_mode", genome, mode_id)
				rates[cell_index] = clampf(float(mode.get("transfer_rate", 0.0)), 0.0, 1.0)
		else:
			rates[cell_index] = default_transfer_rate
	return rates

func _build_behavior_environment() -> Dictionary:
	## v0.30.0：扁平空间哈希 + CSR 邻域。旧的每细胞 Array[int] 与 Vector2i 桶键
	## 在 3000 细胞下占 behavior 阶段一半以上；这里保持 sorted 邻居顺序与旧路径一致。
	var cell_count: int = int(cells.call("size"))
	var buckets: Dictionary = CELL_PHYSICS_SCRIPT.call("build_spatial_hash_flat", cells)
	var neighbor_offsets: PackedInt32Array = PackedInt32Array()
	neighbor_offsets.resize(cell_count + 1)
	var neighbor_values: PackedInt32Array = PackedInt32Array()
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(cell_count):
		neighbor_offsets[cell_index] = neighbor_values.size()
		if alive[cell_index] == 0:
			continue
		var found: PackedInt32Array = CELL_PHYSICS_SCRIPT.call("query_neighbors_flat", cells, cell_index, buckets)
		for neighbor in found:
			neighbor_values.append(neighbor)
	neighbor_offsets[cell_count] = neighbor_values.size()
	var fields_flat: PackedFloat32Array = PackedFloat32Array()
	var sample_indices: PackedInt32Array = PackedInt32Array()
	if environment_manager != null:
		fields_flat = environment_manager.call("get_field_samples_flat")
		sample_indices = environment_manager.call("get_field_sample_index_array", cell_count)
	return {
		"fields_by_cell": [],
		"fields_flat": fields_flat,
		"field_sample_indices": sample_indices,
		"neighbor_offsets": neighbor_offsets,
		"neighbor_values": neighbor_values,
		"neighbors": [],
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
			_energy_flow_add("self_cost", cell_index, base_metabolic_cost * dt)
	cells.set("cell_energy", energies)
	for cell_index in range(energies.size() - 1, -1, -1):
		if alive[cell_index] != 0 and energies[cell_index] <= 0.0:
			_remove_cell_with_cause(cell_index, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_STARVATION"]))

func _compute_base_metabolism_range(first: int, last: int, dt: float, _energies: PackedFloat32Array, alive: PackedByteArray, deltas: PackedFloat32Array) -> void:
	for cell_index in range(first, last):
		if alive[cell_index] != 0:
			deltas[cell_index] = -base_metabolic_cost * dt

func _apply_environment_metabolism(dt: float) -> void:
	## v0.30.0：场采样已是扁平缓冲 + cell_index 索引，无需每细胞 PackedFloat32Array 快照，
	## 也不再为该步开 WorkerThreadPool 任务；静态分区的代谢主循环仍在 _apply_base_metabolism。
	var count: int = int(cells.call("size"))
	var fields_flat: PackedFloat32Array = PackedFloat32Array()
	var sample_indices: PackedInt32Array = PackedInt32Array()
	if environment_manager != null:
		fields_flat = environment_manager.call("get_field_samples_flat")
		sample_indices = environment_manager.call("get_field_sample_index_array", count)
	_apply_environment_metabolism_ranges(dt, fields_flat, sample_indices)

func _apply_environment_metabolism_ranges(dt: float, field_samples: PackedFloat32Array, sample_indices: PackedInt32Array) -> void:
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
	## v0.16.0：营养优先级按个体派生，0.5 的系数恒为 1.0，旧基因组行为不变。
	var priority_values: PackedFloat32Array = PackedFloat32Array()
	priority_values.resize(organisms.get("org_alive").size())
	priority_values.fill(0.5)
	for org_id in genomes:
		respiration_values[int(org_id)] = int(genomes[org_id].get("respiration"))
		priority_values[int(org_id)] = clampf(float(genomes[org_id].get("nutrition_priority")), 0.0, 1.0)
	for cell_index in range(energies.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = org_ids[cell_index]
		var sample_index: int = int(sample_indices[cell_index]) if cell_index < sample_indices.size() else -1
		var field_offset: int = sample_index * 5
		var has_fields: bool = sample_index >= 0 and field_offset + 5 <= field_samples.size()
		var oxygen: float = clampf(float(field_samples[field_offset + 2]), 0.0, 1.0) if has_fields else 0.0
		var respiration: Dictionary = RESPIRATION_RULES_SCRIPT.call("evaluate", int(respiration_values[org_id]), oxygen, facultative_aerobic_efficiency)
		var feeding_factor: float = 0.25 + 1.5 * float(priority_values[org_id])
		var light_factor: float = 1.75 - 1.5 * float(priority_values[org_id])
		var food_gain: float = 0.0
		if types[cell_index] == CELL_TYPE_ZYGOTE:
			food_gain = maxf(0.0, float(field_samples[field_offset])) * heterotrophic_intake_rate * feeding_factor * float(respiration.get("efficiency", 0.0)) * dt if has_fields else 0.0
		elif types[cell_index] == CELL_TYPE_PHOTOCYTE:
			food_gain = maxf(0.0, float(field_samples[field_offset + 3])) * photosynthetic_intake_rate * light_factor * dt if has_fields else 0.0
		elif types[cell_index] == CELL_TYPE_NITROCYTE:
			food_gain = maxf(0.0, float(field_samples[field_offset + 4])) * chemotrophic_intake_rate * feeding_factor * dt if has_fields else 0.0
		if food_gain > 0.0:
			var consumed: float = food_gain
			if types[cell_index] == CELL_TYPE_ZYGOTE:
				consumed = float(environment_manager.call("consume_nutrient", Vector2(positions[cell_index], positions_y[cell_index]), food_gain))
			elif types[cell_index] == CELL_TYPE_NITROCYTE:
				consumed = float(environment_manager.call("consume_signal", Vector2(positions[cell_index], positions_y[cell_index]), food_gain))
			energies[cell_index] += consumed
			_energy_flow_add("production", cell_index, consumed)
			if consumed > 0.0:
				energy_ledger.call("record", ENERGY_LEDGER_SCRIPT.ACTION_ENV_TO_BIO, "E_env", "E_bio", consumed, "intake_type_%d" % int(types[cell_index]))
		var intents: PackedFloat32Array = CELL_BEHAVIOR_SCRIPT.call("get_intents", cells, cell_index)
		var movement: float = absf(float(intents[0]))
		var movement_cost: float = movement_energy_cost * movement * movement * dt
		energies[cell_index] = maxf(0.0, energies[cell_index] - movement_cost)
		_energy_flow_add("self_cost", cell_index, movement_cost)
		if bool(respiration.get("toxic", false)):
			health[org_id] = maxf(0.0, health[org_id] - anaerobic_toxicity_damage_per_second * dt)
	organisms.set("org_health", health)
	cells.set("cell_energy", energies)
	for org_id in range(health.size() - 1, -1, -1):
		if organisms.get("org_alive")[org_id] != 0 and health[org_id] <= 0.0:
			_remove_organism_cells(org_id, int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_TOXICITY"]))

## 发育程序完成后，能量充足的成熟个体按确定性的 tick/index 角度自主分裂。
## v0.15.0 基因模式：不读 dev_program，改用基因组的 division_mass / split_ratio / child_types /
## split_angles / max_divisions，对应 Cell Lab Gene.b/c/i/j；连接仍由黏附素 flag 决定。
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
	var mode_ids: PackedByteArray = cells.get("cell_mode")
	var mode_depths: PackedByteArray = cells.get("cell_mode_depth")
	var candidates: Array[Dictionary] = []
	for cell_index in range(energies.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = org_ids[cell_index]
		if org_id < 0 or org_id >= org_alive.size() or org_alive[org_id] == 0 or org_state[org_id] != mature_state:
			continue
		if not genomes.has(org_id):
			continue
		var genome: RefCounted = genomes[org_id] as RefCounted
		var gene_mode: bool = bool(GENOME_SCRIPT.call("is_gene_mode", genome))
		var has_modes: bool = gene_mode and bool(GENOME_SCRIPT.call("has_modes", genome))
		var threshold: float = maxf(0.05, float(genome.get("division_mass"))) if gene_mode else autonomous_division_energy
		var max_cells: int = _resolve_max_cells(genome)
		var mode_data: Dictionary = {}
		var mode_index: int = 0
		var depth: int = 0
		if has_modes:
			mode_index = 0 if cell_index >= mode_ids.size() else int(mode_ids[cell_index])
			depth = 0 if cell_index >= mode_depths.size() else int(mode_depths[cell_index])
			mode_data = GENOME_SCRIPT.call("get_mode", genome, mode_index)
			threshold = maxf(0.05, float(mode_data.get("division_mass", threshold)))
			# v0.22.0：去掉 mode depth/max_divisions 分裂闸门，对齐 Cell Lab e(double)。
			# Cell Lab 无「同模式分裂 N 代后锁死」机制；分裂次数由端粒 T 控制（-1 无限），
			# 本项目 cell_telomere 已承担该角色。depth 字段保留仅为兼容存档/预览莫斯，不再限制分裂。
			if _is_link_division_blocked(genome, cell_index):
				continue
		if int(cells.call("get_telomere", cell_index)) == 0:
			continue
		if energies[cell_index] < threshold or (max_cells >= 0 and int(cell_counts[org_id]) >= max_cells):
			continue
		# v0.20.0：逐细胞 cooldown。首次具备资格记录宽限（-2 → -1）并跳过本 tick，
		# 保持旧版「成熟当 tick 不立刻分裂」的节奏；此后每个细胞独立计时，不再按个体串行。
		var division_tick: int = int(cells.call("get_division_tick", cell_index))
		if division_tick == -2:
			cells.call("set_division_tick", cell_index, -1)
			continue
		if division_tick >= 0 and _sim_tick - division_tick < autonomous_division_cooldown:
			continue
		candidates.append({"cell": cell_index, "org": org_id, "genome": genome, "gene": gene_mode,
			"modes": has_modes, "mode": mode_data, "mode_index": mode_index, "depth": depth})
	for candidate in candidates:
		var cell_index: int = int(candidate["cell"])
		var org_id: int = int(candidate["org"])
		var genome: RefCounted = candidate["genome"] as RefCounted
		var gene_mode: bool = bool(candidate["gene"])
		var has_modes: bool = bool(candidate["modes"])
		var max_cells: int = _resolve_max_cells(genome)
		if max_cells >= 0 and int(cell_counts[org_id]) >= max_cells:
			continue
		# v0.20.0：移除「一个个体每 tick 最多分裂一次」的串行闸门。
		# 每个合格细胞都在本 tick 分裂；能量按 Gene.c 减半 + 逐细胞 cooldown 提供自然节流。
		var division_index: int = maxi(0, int(cell_counts[org_id]) - 1)
		var angle: float = TAU * fposmod(float(cell_index * 47 + _sim_tick * 13), 360.0) / 360.0
		if gene_mode and not has_modes:
			var angles: PackedByteArray = genome.get("split_angles")
			if division_index < angles.size():
				angle = TAU * float(angles[division_index]) / 256.0
		var radius_scale: float = 1.0
		var ratio: float = 0.5
		var glue: bool = bool(GENOME_SCRIPT.call("has_glue_links", genome))
		if has_modes:
			var mode_data: Dictionary = candidate["mode"] as Dictionary
			var max_mode_slot: int = maxi(0, int(GENOME_SCRIPT.get_script_constant_map().get("MAX_GENOME_MODES", 40)) - 1)
			# Cell Lab Gene.i/j：母细胞切到 i（child1_mode），新细胞切到 j（child2_mode）。
			var gene_i: int = clampi(int(mode_data.get("child1_mode", 0)), 0, max_mode_slot)
			var gene_j: int = clampi(int(mode_data.get("child2_mode", 0)), 0, max_mode_slot)
			var child1_angle: float = clampf(float(mode_data.get("child1_angle", 0.0)), 0.0, 1.0)
			var child2_angle: float = clampf(float(mode_data.get("child2_angle", 0.25)), 0.0, 1.0)
			if bool(mode_data.get("child2_mirror", false)):
				child2_angle = fposmod(-child1_angle, 1.0)
			angle = TAU * child2_angle
			radius_scale = clampf(float(mode_data.get("cell_size", 1.0)), 0.5, 2.0)
			ratio = clampf(float(mode_data.get("split_ratio", 0.5)), 0.05, 0.95)
			if bool(mode_data.get("invert_split_mass", false)):
				ratio = 1.0 - ratio
			glue = bool(mode_data.get("child1_glue", false)) or bool(mode_data.get("child2_glue", true))
			# 子代模式槽在 divide_cell 之后确定：母细胞索引切到 Gene.i，新细胞切到 Gene.j。
			candidate["child1_mode"] = gene_i
			candidate["child2_mode"] = gene_j
		elif gene_mode:
			radius_scale = float(cells.call("get_radius_scale", cell_index))
			ratio = clampf(float(genome.get("split_ratio")), 0.05, 0.95)
		var division_separation: float = maxf(autonomous_division_separation, cell_radius * 2.0 * radius_scale)
		# v0.21.0：Cell Lab e(double) 还原——出生中心距 0.2r（半径当帧保持母半径 → 两个贴靠半圆），
		# 连接静止长度仍为 2r，下一 tick 的接触排斥/弹簧把它们弹开。分裂本身零力。
		var birth_separation: float = maxf(0.5, cell_radius * 0.2 * radius_scale)
		var birth_origin: Vector2 = cells.call("get_position", cell_index)
		var child_index: int = int(cells.call("divide_cell", cell_index, angle, birth_separation))
		if child_index < 0:
			continue
		var add_limit: int = maxi(int(cell_counts[org_id]) + 1, max_cells)
		if not bool(organisms.call("add_developed_cell", org_id, child_index, add_limit)):
			cells.call("remove_cell", child_index)
			continue
		# v0.21.0：母子各沿分裂轴偏 0.1r（中心距 0.2r，中点在原母细胞位置）。
		# 半径当帧保持母半径 → 高度重叠 → 共享弦渲染成两个贴靠半圆；下一 tick 接触排斥弹开。
		var split_dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var half_offset: float = birth_separation * 0.5
		cells.call("set_position", cell_index, birth_origin - split_dir * half_offset)
		cells.call("set_position", child_index, birth_origin + split_dir * half_offset)
		var split_mode: Dictionary = candidate.get("mode", {}) as Dictionary
		if gene_mode and not split_mode.is_empty():
			# Cell Lab e(double)：k = sign*Gene.e/f + 分裂轴；朝向是方向型连接语义的真相源。
			var mother_sign: float = -1.0 if bool(split_mode.get("child1_mirror", false)) else 1.0
			var child_sign: float = -1.0 if bool(split_mode.get("child2_mirror", false)) else 1.0
			cells.call("set_orientation", cell_index, angle + mother_sign * TAU * clampf(float(split_mode.get("split_angle", 0.0)), 0.0, 1.0))
			cells.call("set_orientation", child_index, angle + child_sign * TAU * clampf(float(split_mode.get("split_angle2", 0.0)), 0.0, 1.0))
			# v0.29.0：先按旧连接的朝向分给母/子，再切换 Gene.i/j 模式槽。
			_redistribute_inherited_links(cell_index, child_index, angle, ratio, split_mode)
		if has_modes:
			# v0.22.0：不再累加 depth。Cell Lab 无同模式分裂代数上限；depth 字段保留为只读谱系标记，
			# 分裂次数由端粒控制。母/子 depth 均不随分裂递增（子细胞继承母细胞 depth）。
			var inherited_depth: int = int(candidate.get("depth", 0))
			_apply_cell_mode(genome, cell_index, int(candidate["child1_mode"]), inherited_depth)
			_apply_cell_mode(genome, child_index, int(candidate["child2_mode"]), inherited_depth)
			var mode_ratio_total: float = float(energies[cell_index]) + float(energies[child_index])
			energies[cell_index] = mode_ratio_total * ratio
			energies[child_index] = mode_ratio_total * (1.0 - ratio)
			cells.set("cell_energy", energies)
		elif gene_mode:
			# Gene.c 质量比：divide_cell 已对半分，这里只按基因组比例重新分配，能量守恒。
			var total: float = float(energies[cell_index]) + float(energies[child_index])
			energies[cell_index] = total * ratio
			energies[child_index] = total * (1.0 - ratio)
			cells.set("cell_energy", energies)
			# Gene.i/j 分裂即分化：子代类型由分化树第 division_index 个槽指定。
			var child_types: PackedByteArray = genome.get("child_types")
			if division_index < child_types.size():
				var types_array: PackedByteArray = cells.get("cell_type")
				types_array[child_index] = clampi(int(child_types[division_index]), 0, 255)
				cells.set("cell_type", types_array)
		# v0.14.1：成熟后的自主分裂同样遵守黏附素语义，亲子自动建连。
		# v0.16.0/v0.17.0：受当前模式 max_connections 上限约束；min_connections 为追加软补连。
		var rest_length: float = maxf(division_separation, cell_radius * 2.0 * radius_scale)
		if glue and _can_add_link(genome, cell_index, child_index):
			cells.call("link_cells", cell_index, child_index, rest_length)
		if gene_mode:
			_apply_min_connections(genome, org_id, child_index, rest_length)
		# v0.18.0：端粒按细胞谱系递减，归零时母子同死（Cell Lab Gene.B[6]）。
		if gene_mode:
			var parent_telomere: int = int(cells.call("decrement_telomere", cell_index))
			var child_telomere: int = int(cells.call("decrement_telomere", child_index))
			var telomere_death: int = int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_TELOMERE"])
			if parent_telomere == 0:
				_remove_cell_with_cause(cell_index, telomere_death)
			if child_telomere == 0:
				_remove_cell_with_cause(child_index, telomere_death)
		# v0.29.0：Cell Lab e(double) 末尾的 FLAGELLOCYTE 形态校验（新 D 槽类型生效后）。
		if gene_mode:
			var backward_death: int = int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["DEATH_BACKWARD_LINK"])
			if _has_backward_link(cell_index):
				_remove_cell_with_cause(cell_index, backward_death)
			if _has_backward_link(child_index):
				_remove_cell_with_cause(child_index, backward_death)
		if int(organisms.get("org_alive")[org_id]) != 0:
			org_state = organisms.get("org_state")
			org_state[org_id] = mature_state
			organisms.set("org_state", org_state)
		cell_counts = organisms.get("cell_count")
		# v0.20.0：母子各自重置 cooldown；刚出生的子细胞因此不会在同一 tick 立刻再分裂。
		var latest_alive: PackedByteArray = cells.get("cell_alive")
		if cell_index < latest_alive.size() and latest_alive[cell_index] != 0:
			cells.call("set_division_tick", cell_index, _sim_tick)
		if child_index >= 0 and child_index < latest_alive.size() and latest_alive[child_index] != 0:
			cells.call("set_division_tick", child_index, _sim_tick)

## v0.19.0：半径-能量低通。Cell Lab `f(double)` 对 d² 做低通、稳态 d ∝ sqrt(w)；
## 本项目以该细胞所属模式的 division_mass 作参考能量 E_ref：
##   target² = clamp(E / E_ref, min², max²)
##   s²_next = s² + (target² − s²) · relax_rate · dt
##   effective_scale = baseline × s
## 只对 gene_mode 生效；非基因模式保持 v0.18 固定表型。纯标量、固定细胞索引顺序，不写 RNG。
func _apply_energy_radius_relaxation(dt: float) -> void:
	if not energy_radius_growth_enabled or dt <= 0.0:
		return
	var count: int = int(cells.call("size"))
	if count <= 0:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var mode_ids: PackedByteArray = cells.get("cell_mode")
	var step: float = clampf(energy_radius_relax_rate * dt, 0.0, 1.0)
	var min_power: float = maxf(0.0, energy_radius_min_scale)
	min_power *= min_power
	var max_power: float = maxf(min_power, energy_radius_max_scale)
	max_power *= max_power
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		if cell_index >= org_ids.size() or not genomes.has(int(org_ids[cell_index])):
			continue
		var genome: RefCounted = genomes[int(org_ids[cell_index])] as RefCounted
		if not bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
			continue
		var reference: float = maxf(0.05, float(genome.get("division_mass")))
		if bool(GENOME_SCRIPT.call("has_modes", genome)) and cell_index < mode_ids.size():
			var mode: Dictionary = GENOME_SCRIPT.call("get_mode", genome, int(mode_ids[cell_index]))
			reference = maxf(0.05, float(mode.get("division_mass", reference)))
		var current: float = float(cells.call("get_energy_radius_scale", cell_index))
		var current_power: float = current * current
		var target_power: float = clampf(maxf(0.0, energies[cell_index]) / reference, min_power, max_power)
		var next_scale: float = sqrt(maxf(0.0, current_power + (target_power - current_power) * step))
		cells.call("set_energy_radius_scale", cell_index, next_scale)

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
		_energy_flow_add("production", int(event.get("predator", -1)), gain)
		_energy_flow_add("predation_drain", prey_index, drained)
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
	var initial_state: int = int(DEVELOPMENT_RULES_SCRIPT.call("initial_lifecycle_state", genome, 1))
	var org_id: int = int(organisms.call("create_organism", genome_id, species_id, parent_id, initial_state))
	if org_id < 0:
		return -1
	var cell_index: int = int(cells.call("append_cell", org_id, position, energy, type_id))
	if cell_index < 0:
		return -1
	var stored_genome: RefCounted = genome.duplicate_genome()
	stored_genome.set("species_id", species_id)
	stored_genome.set("lineage_id", int((species_system.call("get_species", species_id) as Dictionary).get("lineage_id", -1)))
	genomes[org_id] = stored_genome
	if bool(GENOME_SCRIPT.call("has_modes", stored_genome)):
		_apply_cell_mode(stored_genome, cell_index, 0, 0)
	else:
		_apply_cell_phenotype(stored_genome, cell_index)
	# v0.18.0：初始细胞继承当前模式的端粒；-1 表示无限。
	var initial_telomere: int = -1
	if bool(GENOME_SCRIPT.call("has_modes", stored_genome)):
		initial_telomere = int(GENOME_SCRIPT.call("get_mode", stored_genome, 0).get("telomere", -1))
	cells.call("set_cell_telomere", cell_index, initial_telomere)
	CELL_BEHAVIOR_SCRIPT.call("initialize_weights", cells, cell_index, int(genome.call("hash")))
	organisms.call("add_developed_cell", org_id, cell_index, int(DEVELOPMENT_RULES_SCRIPT.call("expected_cell_count", genome)))
	# add_developed_cell 会把状态改回 DEVELOPING；基因模式出生即成熟，必须恢复初值。
	# 这正是「能量很高却不分裂」的根因：个体永远卡在发育期，自主生命周期不会触发。
	var org_states: PackedByteArray = organisms.get("org_state")
	org_states[org_id] = initial_state
	organisms.set("org_state", org_states)
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
## v0.15.0：GNP1 冻结，基因模式参数走命令里的 genome_gene payload，解码后覆盖运行时字段。
func _genome_from_command(command: Dictionary) -> RefCounted:
	if not command.has("genome_bytes"):
		return _default_genome()
	var bytes: PackedByteArray = command.get("genome_bytes")
	var decoded: RefCounted = GENOME_CODEC_SCRIPT.call("decode", bytes) as RefCounted
	if decoded == null:
		return _default_genome()
	_apply_gene_payload(decoded, command.get("genome_gene", {}))
	return decoded

func _apply_gene_payload(genome: RefCounted, payload: Variant) -> void:
	if genome == null or not (payload is Dictionary):
		return
	var gene: Dictionary = payload as Dictionary
	if gene.is_empty():
		return
	genome.set("division_mass", clampf(float(gene.get("division_mass", 1.0)), 0.05, 100.0))
	genome.set("split_ratio", clampf(float(gene.get("split_ratio", 0.5)), 0.05, 0.95))
	genome.set("max_divisions", clampi(int(gene.get("max_divisions", 3)), 0, 8))
	# v0.18.0：旧 payload 缺字段时回退为 max_divisions+1，保持 v0.17 及更早行为。
	if gene.has("max_cells_per_organism"):
		var restored_cell_cap: int = clampi(int(gene.get("max_cells_per_organism")), -1, int(GENOME_SCRIPT.get_script_constant_map().get("GLOBAL_CELL_CAPACITY", 8000)))
		genome.set("max_cells_per_organism", -1 if restored_cell_cap < 2 else restored_cell_cap)
	else:
		genome.set("max_cells_per_organism", clampi(int(genome.get("max_divisions")) + 1, 2, int(GENOME_SCRIPT.get_script_constant_map().get("GLOBAL_CELL_CAPACITY", 8000))))
	var child_types: PackedByteArray = gene.get("child_types", PackedByteArray())
	var split_angles: PackedByteArray = gene.get("split_angles", PackedByteArray())
	if child_types is PackedByteArray:
		genome.set("child_types", (child_types as PackedByteArray).duplicate())
	if split_angles is PackedByteArray:
		genome.set("split_angles", (split_angles as PackedByteArray).duplicate())
	# v0.16.0：Macro 表型字段（缺省时保留 Genome 默认值，兼容旧命令 payload）。
	genome.set("nutrition_priority", clampf(float(gene.get("nutrition_priority", genome.get("nutrition_priority"))), 0.0, 1.0))
	genome.set("cell_stiffness", clampf(float(gene.get("cell_stiffness", genome.get("cell_stiffness"))), 0.0, 1.0))
	genome.set("cell_size", clampf(float(gene.get("cell_size", genome.get("cell_size"))), 0.5, 2.0))
	genome.set("max_connections", clampi(int(gene.get("max_connections", genome.get("max_connections"))), 0, 16))
	genome.set("min_connections", clampi(int(gene.get("min_connections", genome.get("min_connections"))), 0, 16))
	genome.set("color_r", clampf(float(gene.get("color_r", genome.get("color_r"))), 0.0, 1.0))
	genome.set("color_g", clampf(float(gene.get("color_g", genome.get("color_g"))), 0.0, 1.0))
	genome.set("color_b", clampf(float(gene.get("color_b", genome.get("color_b"))), 0.0, 1.0))
	# v0.17.0：模式槽与传递率经同一 CommandBus payload 落地；旧 payload 无 modes 时保持空。
	if gene.has("transfer_rate"):
		genome.set("transfer_rate", clampf(float(gene.get("transfer_rate")), 0.0, 1.0))
	if gene.has("modes"):
		genome.call("set_modes", gene.get("modes"))

## v0.16.0：最小连接数是本项目追加的软约束（Cell Lab 未证实独立控件）。
## 分裂后按 cell index 升序扫描同个体细胞，确定性补连到 min_connections；仍受上限约束。
func _apply_min_connections(genome: RefCounted, org_id: int, cell_index: int, rest_length: float) -> void:
	var mode: Dictionary = _mode_for_cell(genome, cell_index)
	var fallback_target: int = int(genome.get("min_connections"))
	var target: int = clampi(int(mode.get("min_connections", fallback_target)), 0, 16)
	if target <= 0 or cell_index < 0:
		return
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	if cell_index >= link_counts.size() or int(link_counts[cell_index]) >= target:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	for peer_index in range(alive.size()):
		if peer_index == cell_index or alive[peer_index] == 0 or org_ids[peer_index] != org_id:
			continue
		if not _can_add_link(genome, cell_index, peer_index):
			continue
		if bool(cells.call("link_cells", cell_index, peer_index, rest_length)):
			link_counts = cells.get("cell_link_count")
			if cell_index >= link_counts.size() or int(link_counts[cell_index]) >= target:
				return
func _apply_cell_phenotype(genome: RefCounted, cell_index: int) -> void:
	if genome == null or not bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
		return
	var mode: Dictionary = _mode_for_cell(genome, cell_index)
	var stiffness: float = clampf(float(mode.get("cell_stiffness", genome.get("cell_stiffness"))), 0.0, 1.0)
	var color: Color = Color(
		clampf(float(mode.get("color_r", genome.get("color_r"))), 0.0, 1.0),
		clampf(float(mode.get("color_g", genome.get("color_g"))), 0.0, 1.0),
		clampf(float(mode.get("color_b", genome.get("color_b"))), 0.0, 1.0),
		1.0
	)
	cells.call("set_cell_phenotype", cell_index,
		clampf(float(mode.get("cell_size", genome.get("cell_size"))), 0.5, 2.0),
		0.25 + 1.5 * stiffness, color)

## v0.17.0：把当前模式的类型、模式槽与分裂层数写入细胞，并同步表型。
func _apply_cell_mode(genome: RefCounted, cell_index: int, mode_index: int, depth: int) -> void:
	if genome == null or cell_index < 0 or not bool(GENOME_SCRIPT.call("is_gene_mode", genome)) \
		or not bool(GENOME_SCRIPT.call("has_modes", genome)):
		return
	var modes: Array = genome.get("modes") as Array
	if modes.is_empty():
		return
	var selected: int = clampi(mode_index, 0, modes.size() - 1)
	var mode: Dictionary = GENOME_SCRIPT.call("get_mode", genome, selected)
	cells.call("set_cell_mode", cell_index, selected, depth)
	var types: PackedByteArray = cells.get("cell_type")
	types[cell_index] = clampi(int(mode.get("cell_type", 0)), 0, 255)
	cells.set("cell_type", types)
	_apply_cell_phenotype(genome, cell_index)

func _mode_for_cell(genome: RefCounted, cell_index: int) -> Dictionary:
	if genome == null or not bool(GENOME_SCRIPT.call("has_modes", genome)):
		return {}
	var mode_ids: PackedByteArray = cells.get("cell_mode")
	var mode_id: int = 0 if cell_index < 0 or cell_index >= mode_ids.size() else int(mode_ids[cell_index])
	return GENOME_SCRIPT.call("get_mode", genome, mode_id)

## v0.18.0：基因模式按 Genome.max_cells_per_organism 限制个体；-1 无限。
## 旧非基因模式仍按 dev_program 固定细胞数，旧 payload 缺字段时由 _apply_gene_payload 回退。
func _resolve_max_cells(genome: RefCounted) -> int:
	if genome == null:
		return -1
	if not bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
		return int(DEVELOPMENT_RULES_SCRIPT.call("expected_cell_count", genome))
	# 旧快照/外部构造的 RefCounted 可能没有该字段；缺失时按 v0.17 的 max_divisions+1 回退。
	var raw_cap: Variant = genome.get("max_cells_per_organism")
	var cap: int = int(genome.get("max_divisions")) + 1 if raw_cap == null else int(raw_cap)
	if cap == int(GENOME_SCRIPT.get_script_constant_map().get("UNLIMITED_CELLS", -1)) or cap < 2:
		return -1
	return mini(cap, maxi(1, global_cell_capacity))

## v0.18.0：当前模式连接数达到 link_division_limit 即抑制分裂；-1 保持旧行为。
func _is_link_division_blocked(genome: RefCounted, cell_index: int) -> bool:
	if genome == null or not bool(GENOME_SCRIPT.call("is_gene_mode", genome)) \
		or not bool(GENOME_SCRIPT.call("has_modes", genome)):
		return false
	var limit: int = clampi(int(_mode_for_cell(genome, cell_index).get("link_division_limit", -1)), -1, 16)
	if limit < 0:
		return false
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	return cell_index >= 0 and cell_index < link_counts.size() and int(link_counts[cell_index]) >= limit

## v0.29.0：官方 CellWorld.e(double) 的旧连接重分配（Gene.m/n + ±0.2 双阈值）。
## 只处理分裂前母细胞已有的连接；亲子新连接在此之后建立，不会被重分配。
func _redistribute_inherited_links(mother_index: int, child_index: int, split_angle: float,
		split_ratio: float, mode_data: Dictionary) -> void:
	if mode_data.is_empty():
		return
	var keep_mother: bool = bool(mode_data.get("link_keep_mother", false))
	var keep_child: bool = bool(mode_data.get("link_keep_child", false))
	if not keep_mother and not keep_child:
		return
	var max_link_count: int = int(CELL_ARRAY_SCRIPT.get_script_constant_map().get("MAX_LINKS_PER_CELL", 20))
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var counts: PackedByteArray = cells.get("cell_link_count")
	var mother_pos: Vector2 = cells.call("get_position", mother_index)
	var axis: Vector2 = Vector2.RIGHT.rotated(split_angle)
	var inherited: Array[Dictionary] = []
	for link_index in range(link_a.size()):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		var other: int = -1
		if a == mother_index and b != child_index:
			other = b
		elif b == mother_index and a != child_index:
			other = a
		if other >= 0:
			inherited.append({"link": link_index, "other": other})
	if inherited.is_empty():
		return
	# 中间带四极值索引：左/右投影的最大与最小，对应官方 i13/i12/i9/i11。
	var left_max: int = -1
	var left_min: int = -1
	var right_max: int = -1
	var right_min: int = -1
	var left_max_v: float = -INF
	var left_min_v: float = INF
	var right_max_v: float = -INF
	var right_min_v: float = INF
	for entry in inherited:
		var link_index: int = int(entry.get("link", -1))
		var world_angle: float = _link_world_angle_from(link_index, mother_index)
		var d14: float = cos(split_angle - world_angle) - (1.0 - 2.0 * split_ratio)
		if absf(d14) > 0.2:
			continue
		var other_pos: Vector2 = cells.call("get_position", int(entry.get("other", -1)))
		var projection: float = (other_pos - mother_pos).dot(axis)
		var cross_value: float = sin(world_angle - split_angle)
		if cross_value > 0.0:
			if projection > left_max_v:
				left_max_v = projection; left_max = link_index
			if projection < left_min_v:
				left_min_v = projection; left_min = link_index
		else:
			if projection > right_max_v:
				right_max_v = projection; right_max = link_index
			if projection < right_min_v:
				right_min_v = projection; right_min = link_index
	# 逆序处理，remove_link 导致的索引位移只影响更后面的元素（已先处理）。
	for reverse_index in range(inherited.size() - 1, -1, -1):
		var entry: Dictionary = inherited[reverse_index] as Dictionary
		var link_index: int = int(entry.get("link", -1))
		if link_index < 0 or link_index >= link_a.size():
			continue
		var other: int = int(entry.get("other", -1))
		var world_angle: float = _link_world_angle_from(link_index, mother_index)
		var d14: float = cos(split_angle - world_angle) - (1.0 - 2.0 * split_ratio)
		var to_child: bool = keep_child and (d14 > 0.2 or (d14 > -0.2 \
			and (link_index == left_max or link_index == right_max)))
		var to_mother: bool = keep_mother and (d14 < -0.2 or (d14 < 0.2 \
			and (link_index == left_min or link_index == right_min)))
		if to_child and int(counts[child_index]) < max_link_count \
			and int(counts[other]) < max_link_count \
			and not bool(cells.call("has_link", child_index, other)):
			cells.call("set_link_endpoint", link_index, child_index, other, _angle_between(child_index, other))
		elif to_mother and int(counts[mother_index]) < max_link_count \
			and int(counts[other]) < max_link_count:
			cells.call("set_link_endpoint", link_index, mother_index, other, _angle_between(mother_index, other))
		else:
			cells.call("remove_link", link_index)

func _angle_between(from_index: int, to_index: int) -> float:
	var delta: Vector2 = cells.call("get_position", to_index) - cells.call("get_position", from_index)
	return atan2(delta.y, delta.x) if delta.length_squared() > 0.0 else 0.0

## 连接在某端看到的世界方向角（b 端为反向 +PI），用于点积与 FLAG 相对角。
func _link_world_angle_from(link_index: int, endpoint: int) -> float:
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	if link_index < 0 or link_index >= link_a.size():
		return 0.0
	var a: int = link_a[link_index]
	var b: int = link_b[link_index]
	var angle: float = _angle_between(a, b)
	if endpoint == b:
		angle += PI
	return fposmod(angle, TAU)

## 官方 e(double) 末尾：新 D 槽类型为 FLAGELLOCYTE 时，任一后向连接 cos<-0.8 即判死。
func _has_backward_link(cell_index: int) -> bool:
	if cell_index < 0 or cell_index >= int(cells.call("size")):
		return false
	var types: PackedByteArray = cells.get("cell_type")
	if int(types[cell_index]) != CELL_TYPE_FLAGELLOCYTE:
		return false
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var orientation: float = float(cells.call("get_orientation", cell_index))
	for link_index in range(link_a.size()):
		if link_a[link_index] != cell_index and link_b[link_index] != cell_index:
			continue
		var relative: float = _link_world_angle_from(link_index, cell_index) - orientation
		if cos(relative) < -0.8:
			return true
	return false

func _can_add_link(genome: RefCounted, a: int, b: int) -> bool:
	if genome == null or not bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
		return true
	var fallback_limit: int = int(genome.get("max_connections"))
	var limit: int = clampi(int(_mode_for_cell(genome, a).get("max_connections", fallback_limit)), 0, 16)
	if limit <= 0:
		return false
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	return a >= 0 and b >= 0 and a < link_counts.size() and b < link_counts.size() \
		and int(link_counts[a]) < limit and int(link_counts[b]) < limit

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
				# 点在空白处即解除诊断锁定，避免圆环一直跟着上一枚细胞。
				selection = []
				last_tool_message = "细胞诊断：附近没有细胞 · 已解除锁定"
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
			if injected == null:
				return -1
			_apply_gene_payload(injected, command.get("genome_gene", {}))
			if not bool(injected.call("is_valid")):
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
		"CLEAR_SELECTION":
			# 纯视图解锁：只清 selection / 诊断快照，不改物理、能量或确定性 hash。
			selection = []
			last_inspection = {}
			last_tool_message = "细胞诊断：已解除锁定"
			return 0
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
	# v0.19.0：半径低通的确定性状态（有效半径参与碰撞/分裂间距）。缺省空数组不参与，旧档无影响。
	for array_name in ["cell_radius_baseline", "cell_energy_scale", "cell_division_tick", "cell_orientation"]:
		for value in cells.get(array_name):
			hash_value = _hash_int(hash_value, int(round(float(value) * 1000000.0)))
	for array_name in ["link_cell_a", "link_cell_b", "link_rest_length", "link_angle"]:
		for value in cells.get(array_name):
			var quantized: int = int(round(float(value) * 1000000.0)) if array_name == "link_rest_length" or array_name == "link_angle" else int(value)
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
