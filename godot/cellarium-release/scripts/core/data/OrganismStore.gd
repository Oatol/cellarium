extends RefCounted
## 个体级 SoA 元数据。能量是细胞能量之和；不另存可漂移的重复 energy 字段。

const STATE_ZYGOTE: int = 0
const STATE_DEVELOPING: int = 1
const STATE_MATURE: int = 2
const STATE_DAMAGED: int = 3
const STATE_DEAD: int = 4

const DEATH_NONE: int = 0
const DEATH_STARVATION: int = 1
const DEATH_TOXICITY: int = 2
const DEATH_PREDATION: int = 3
const DEATH_INTERVENTION: int = 4
## v0.18.0：端粒归零，对应 Cell Lab Gene.B[6] 的分裂次数耗尽。
const DEATH_TELOMERE: int = 5

var org_alive: PackedByteArray = PackedByteArray()
var org_genome_id: PackedInt32Array = PackedInt32Array()
var org_species_id: PackedInt32Array = PackedInt32Array()
var org_parent_id: PackedInt32Array = PackedInt32Array()
var org_age: PackedFloat32Array = PackedFloat32Array()
var org_health: PackedFloat32Array = PackedFloat32Array()
var org_death_cause: PackedByteArray = PackedByteArray()
var org_state: PackedByteArray = PackedByteArray()
var org_instruction_mask: PackedInt64Array = PackedInt64Array()
var org_dev_cursor: PackedInt32Array = PackedInt32Array()
var cell_offset: PackedInt32Array = PackedInt32Array()
var cell_count: PackedInt32Array = PackedInt32Array()

func create_organism(genome_id: int, species_id: int, parent_id: int, initial_state: int = STATE_ZYGOTE) -> int:
	if genome_id < 0 or species_id < 0 or parent_id < -1 or initial_state > STATE_DEAD:
		return -1
	var org_id: int = org_alive.size()
	org_alive.append(1)
	org_genome_id.append(genome_id)
	org_species_id.append(species_id)
	org_parent_id.append(parent_id)
	org_age.append(0.0)
	org_health.append(1.0)
	org_death_cause.append(DEATH_NONE)
	org_state.append(initial_state)
	org_instruction_mask.append(0)
	org_dev_cursor.append(0)
	cell_offset.append(0)
	cell_count.append(0)
	return org_id

func set_cell_range(org_id: int, offset: int, count: int) -> bool:
	if org_id < 0 or org_id >= org_alive.size() or offset < 0 or count < 0:
		return false
	cell_offset[org_id] = offset
	cell_count[org_id] = count
	return true

func validate_cell_ranges(total_cells: int) -> bool:
	if total_cells < 0:
		return false
	for org_id in range(org_alive.size()):
		var start: int = cell_offset[org_id]
		var count: int = cell_count[org_id]
		if start < 0 or count < 0 or start + count > total_cells:
			return false
	return true

func remove_cell_from_organism(org_id: int, death_cause: int = DEATH_NONE) -> bool:
	if org_id < 0 or org_id >= org_alive.size() or org_alive[org_id] == 0 or cell_count[org_id] <= 0:
		return false
	cell_count[org_id] -= 1
	if cell_count[org_id] == 0:
		org_alive[org_id] = 0
		org_state[org_id] = STATE_DEAD
		if death_cause != DEATH_NONE:
			org_death_cause[org_id] = death_cause
	return true

func is_mature_single_cell(org_id: int, division_count: int) -> bool:
	return org_id >= 0 and org_id < cell_count.size() and cell_count[org_id] == 1 and division_count == 0

func add_developed_cell(org_id: int, cell_index: int, expected_count: int) -> bool:
	if org_id < 0 or org_id >= org_alive.size() or org_alive[org_id] == 0 or cell_index < 0 or expected_count < 1:
		return false
	if cell_count[org_id] >= expected_count:
		return false
	if cell_count[org_id] == 0:
		cell_offset[org_id] = cell_index
	cell_count[org_id] += 1
	org_state[org_id] = STATE_DEVELOPING
	return true
