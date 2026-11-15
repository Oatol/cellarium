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

static func execute_divide(genome: RefCounted, cells: RefCounted, organisms: RefCounted, command: Dictionary) -> int:
	if not validate_divide_command(command) or genome == null or cells == null or organisms == null:
		return -1
	var org_id: int = int(command["org_id"])
	var source_index: int = int(command["cell_index"])
	if org_id >= organisms.get("org_alive").size() or int(organisms.get("org_alive")[org_id]) == 0:
		return -1
	if source_index >= cells.call("size") or int(cells.get("cell_org_id")[source_index]) != org_id:
		return -1
	if int(organisms.get("org_state")[org_id]) != int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["STATE_DEVELOPING"]):
		return -1
	if int(organisms.get("cell_count")[org_id]) >= expected_cell_count(genome):
		return -1
	var instruction_index: int = int(command.get("instruction_index", -1))
	var program: Array = genome.get("dev_program")
	if instruction_index < 0 or instruction_index >= program.size():
		return -1
	var instruction: Dictionary = program[instruction_index]
	if int(instruction.get("opcode", -1)) != 0 or int(instruction.get("a", -1)) != source_index or instruction_index >= 63:
		return -1
	var instruction_bit: int = 1 << instruction_index
	if (int(organisms.get("org_divide_mask")[org_id]) & instruction_bit) != 0:
		return -1
	var angle: float = TAU * float(instruction.get("b", 0)) / 256.0
	var child_index: int = int(cells.call("divide_cell", source_index, angle, float(command.get("separation", 1.0))))
	if child_index < 0:
		return -1
	if not bool(organisms.call("add_developed_cell", org_id, child_index, expected_cell_count(genome))):
		return -1
	organisms.get("org_divide_mask")[org_id] = int(organisms.get("org_divide_mask")[org_id]) | instruction_bit
	return child_index
