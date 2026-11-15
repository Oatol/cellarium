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
	if command.get("type", "") != "DIVIDE":
		return -1
	var org_id: int = int(command.get("org_id", -1))
	if not genomes.has(org_id):
		return -1
	return int(DEVELOPMENT_RULES_SCRIPT.call("execute_divide", genomes[org_id], cells, organisms, command))

func get_organism_count() -> int:
	var count: int = 0
	for alive in organisms.get("org_alive"):
		if alive != 0:
			count += 1
	return count
