extends RefCounted
## 发育计划由 GNP1 dev_program 唯一决定。v1 环境快照不改变细胞数量.

const ORGANISM_STORE_SCRIPT: Script = preload("res://scripts/core/data/OrganismStore.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const CELL_SHAPE_SCRIPT: Script = preload("res://scripts/core/data/CellShape.gd")

static func division_count(genome: RefCounted) -> int:
	if genome == null:
		return 0
	if bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
		return clampi(int(genome.get("max_divisions")), 0, int(GENOME_SCRIPT.get_script_constant_map().get("MAX_GENE_DIVISIONS", 8)))
	if not genome.has_method("division_count"):
		return 0
	return int(genome.call("division_count"))

static func expected_cell_count(genome: RefCounted) -> int:
	return 1 + division_count(genome)

static func initial_lifecycle_state(genome: RefCounted, current_cell_count: int) -> int:
	var states: Dictionary = ORGANISM_STORE_SCRIPT.get_script_constant_map()
	# v0.15.0 基因模式：发育不靠指令，成熟由分裂质量阈值触发，出生即 MATURE。
	if bool(GENOME_SCRIPT.call("is_gene_mode", genome)):
		return int(states.get("STATE_MATURE", 2))
	if current_cell_count == 1 and division_count(genome) == 0:
		return int(states.get("STATE_MATURE", 2))
	return int(states.get("STATE_DEVELOPING", 1))

static func validate_birth_command(command: Dictionary) -> bool:
	return command.get("type", "") == "REPRODUCE" and int(command.get("parent_org_id", -1)) >= -1

static func validate_divide_command(command: Dictionary) -> bool:
	return command.get("type", "") == "DIVIDE" and int(command.get("org_id", -1)) >= 0 and int(command.get("cell_index", -1)) >= 0

static func execute_instruction(genome: RefCounted, cells: RefCounted, organisms: RefCounted, command: Dictionary) -> int:
	if command.get("type", "") != "DEVELOPMENT_INSTRUCTION" or genome == null or cells == null or organisms == null:
		return -1
	var org_id: int = int(command.get("org_id", -1))
	var instruction_index: int = int(command.get("instruction_index", -1))
	if org_id < 0 or org_id >= organisms.get("org_alive").size() or organisms.get("org_alive")[org_id] == 0:
		return -1
	if organisms.get("org_state")[org_id] != ORGANISM_STORE_SCRIPT.get_script_constant_map()["STATE_DEVELOPING"]:
		return -1
	var program: Array = genome.get("dev_program")
	if instruction_index != int(organisms.get("org_dev_cursor")[org_id]) or instruction_index < 0 or instruction_index >= program.size():
		return -1
	var instruction: Dictionary = program[instruction_index]
	var opcode: int = int(instruction.get("opcode", -1))
	var a: int = int(instruction.get("a", -1))
	var b: int = int(instruction.get("b", -1))
	var c: int = int(instruction.get("c", -1))
	if opcode == 0:
		# DIVIDE 指令的 c 复用为分裂间距（世界单位，0 表示沿用默认 1）。
		# 同个体细胞不做自碰撞，因此发育期必须按静息直径分开，否则亲子会重叠。
		var separation: float = float(command.get("separation", 1.0))
		var instruction_separation: float = float(instruction.get("c", 0))
		if instruction_separation > 0.0:
			separation = instruction_separation
		var child_index: int = execute_divide(genome, cells, organisms, {"type": "DIVIDE", "org_id": org_id, "cell_index": a, "instruction_index": instruction_index, "separation": separation})
		if child_index >= 0:
			organisms.get("org_dev_cursor")[org_id] += 1
			_update_maturity(genome, organisms, org_id)
		return child_index
	if instruction_index >= 63 or (int(organisms.get("org_instruction_mask")[org_id]) & (1 << instruction_index)) != 0:
		return -1
	if opcode == 1:
		if a < 0 or a >= cells.call("size") or cells.get("cell_alive")[a] == 0 or cells.get("cell_org_id")[a] != org_id or b < 0 or b > 255:
			return -1
		cells.get("cell_type")[a] = b
	elif opcode == 2:
		# v0.15.0：LINK 已从编辑器/新基因组中移除；此分支仅为兼容 v0.14.x 及更早存档而保留。
		# 新基因组连接一律由 Genome.flags bit0 的黏附素语义在 DIVIDE 时自动建立。
		if a < 0 or b < 0 or a >= cells.call("size") or b >= cells.call("size") or c <= 0:
			return -1
		if cells.get("cell_alive")[a] == 0 or cells.get("cell_alive")[b] == 0:
			return -1
		if cells.get("cell_org_id")[a] != org_id or cells.get("cell_org_id")[b] != org_id:
			return -1
		if not bool(cells.call("link_cells", a, b, float(c))):
			return -1
	else:
		return -1
	organisms.get("org_instruction_mask")[org_id] = int(organisms.get("org_instruction_mask")[org_id]) | (1 << instruction_index)
	organisms.get("org_dev_cursor")[org_id] += 1
	_update_maturity(genome, organisms, org_id)
	return a

static func _update_maturity(genome: RefCounted, organisms: RefCounted, org_id: int) -> void:
	if int(organisms.get("cell_count")[org_id]) < expected_cell_count(genome):
		return
	var mask: int = int(organisms.get("org_instruction_mask")[org_id])
	for instruction_index in range(genome.get("dev_program").size()):
		var opcode: int = int(genome.get("dev_program")[instruction_index].get("opcode", -1))
		if opcode <= 2 and (mask & (1 << instruction_index)) == 0:
			return
	organisms.get("org_state")[org_id] = int(ORGANISM_STORE_SCRIPT.get_script_constant_map()["STATE_MATURE"])

static func execute_divide(genome: RefCounted, cells: RefCounted, organisms: RefCounted, command: Dictionary) -> int:
	if not validate_divide_command(command) or genome == null or cells == null or organisms == null:
		return -1
	var org_id: int = int(command["org_id"])
	var source_index: int = int(command["cell_index"])
	if org_id >= organisms.get("org_alive").size() or organisms.get("org_alive")[org_id] == 0:
		return -1
	if source_index >= cells.call("size") or cells.get("cell_alive")[source_index] == 0 or cells.get("cell_org_id")[source_index] != org_id:
		return -1
	if organisms.get("org_state")[org_id] != ORGANISM_STORE_SCRIPT.get_script_constant_map()["STATE_DEVELOPING"]:
		return -1
	if int(organisms.get("cell_count")[org_id]) >= expected_cell_count(genome):
		return -1
	var instruction_index: int = int(command.get("instruction_index", -1))
	var program: Array = genome.get("dev_program")
	if instruction_index != int(organisms.get("org_dev_cursor")[org_id]) or instruction_index < 0 or instruction_index >= program.size():
		return -1
	var instruction: Dictionary = program[instruction_index]
	if int(instruction.get("opcode", -1)) != 0 or int(instruction.get("a", -1)) != source_index or instruction_index >= 63:
		return -1
	var instruction_bit: int = 1 << instruction_index
	if (int(organisms.get("org_instruction_mask")[org_id]) & instruction_bit) != 0:
		return -1
	var angle: float = TAU * float(instruction.get("b", 0)) / 256.0
	var child_index: int = int(cells.call("divide_cell", source_index, angle, float(command.get("separation", 1.0))))
	if child_index < 0:
		return -1
	if not bool(organisms.call("add_developed_cell", org_id, child_index, expected_cell_count(genome))):
		return -1
	# v0.14.1：黏附素语义由 Genome.flags bit0 承载。置位后每次 DIVIDE 都自动把亲子连起来，
	# 用户不必再写 LINK 指令。静息长度沿用亲子间距，至少为静息直径。
	# link_cells 自身幂等：若模板同时写了 LINK，不会重复建边；连接上限导致的失败不回滚分裂。
	if bool(GENOME_SCRIPT.call("has_glue_links", genome)):
		var rest_radius: float = float(CELL_SHAPE_SCRIPT.get_script_constant_map().get("REST_RADIUS", 7.0))
		var rest_length: float = maxf(float(command.get("separation", 1.0)), rest_radius * 2.0)
		cells.call("link_cells", source_index, child_index, rest_length)
	organisms.get("org_instruction_mask")[org_id] = int(organisms.get("org_instruction_mask")[org_id]) | instruction_bit
	return child_index
