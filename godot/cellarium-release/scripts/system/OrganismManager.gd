extends Node
## 主线程内拥有个体、细胞与基因组状态；CommandBus 下一 tick 调用 apply_command。

const CELL_ARRAY_SCRIPT: Script = preload("res://scripts/core/data/CellArray.gd")
const ORGANISM_STORE_SCRIPT: Script = preload("res://scripts/core/data/OrganismStore.gd")
const DEVELOPMENT_RULES_SCRIPT: Script = preload("res://scripts/core/data/DevelopmentRules.gd")

var cells: RefCounted = CELL_ARRAY_SCRIPT.new() as RefCounted
var organisms: RefCounted = ORGANISM_STORE_SCRIPT.new() as RefCounted
var genomes: Dictionary = {}

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
	organisms.call("add_developed_cell", org_id, cell_index, int(DEVELOPMENT_RULES_SCRIPT.call("expected_cell_count", genome)))
	return org_id

func apply_command(command: Dictionary) -> int:
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

func remove_cell(cell_index: int) -> float:
	if cell_index < 0 or cell_index >= int(cells.call("size")):
		return -1.0
	if int(cells.get("cell_alive")[cell_index]) == 0:
		return -1.0
	var org_id: int = int(cells.get("cell_org_id")[cell_index])
	var energy: float = float(cells.call("remove_cell", cell_index))
	if energy < 0.0 or not bool(organisms.call("remove_cell_from_organism", org_id)):
		return -1.0
	return energy

func get_organism_count() -> int:
	var count: int = 0
	for alive in organisms.get("org_alive"):
		if alive != 0:
			count += 1
	return count
