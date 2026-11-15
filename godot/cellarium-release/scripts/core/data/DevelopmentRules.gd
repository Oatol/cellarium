extends RefCounted
## 发育计划由 GNP1 dev_program 唯一决定。v1 环境快照不改变细胞数量。

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const ORGANISM_STORE_SCRIPT: Script = preload("res://scripts/core/data/OrganismStore.gd")

static func division_count(genome: RefCounted) -> int:
	if genome == null or not genome.has_method("division_count"):
		return 0
	return int(genome.call("division_count"))

static func expected_cell_count(genome: RefCounted) -> int:
	return 1 + division_count(genome)

static func initial_lifecycle_state(genome: RefCounted, current_cell_count: int) -> int:
	var states: Dictionary = ORGANISM_STORE_SCRIPT.get_script_constant_map()
	if current_cell_count == 1 and division_count(genome) == 0:
		return int(states.get("STATE_MATURE", 2))
	return int(states.get("STATE_DEVELOPING", 1))

static func validate_birth_command(command: Dictionary) -> bool:
	return command.get("type", "") == "REPRODUCE" and int(command.get("parent_org_id", -1)) >= -1

static func validate_divide_command(command: Dictionary) -> bool:
	return command.get("type", "") == "DIVIDE" and int(command.get("org_id", -1)) >= 0 and int(command.get("cell_index", -1)) >= 0
