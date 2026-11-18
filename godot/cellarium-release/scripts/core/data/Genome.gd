extends RefCounted
## GNP1 运行时模型。发育指令按 [opcode:6][a:8][b:8][c:10] 编码为 u32。
## 字节序列化由 GenomeCodec 负责；dev_program 是唯一发育结构真相源。

const MAX_DEV_INSTRUCTIONS: int = 64
const MAX_GENE_DIVISIONS: int = 8
const MAX_OPCODE: int = 63
const MAX_OPERAND_8: int = 255
const MAX_OPERAND_10: int = 1023
const OP_DIVIDE: int = 0
const OP_DIFFERENTIATE: int = 1
const OP_LINK: int = 2

## v0.14.1 版本化追加：flags 位 0 表示「生成黏附素即亲子自动连接」。
## flags 本就在 GNP1 编码（GenomeCodec 第 2–3 字节）与存档 schema 内，不新增字段、不改格式；
## 只是给此前未使用的位赋予语义。DIVIDE 执行后按该位自动 link_cells(parent, child)，
## 因此用户无需再单独写 LINK 指令。0 = 旧行为（需显式 LINK）。
const FLAG_GLUE_LINKS: int = 1 << 0

## v0.15.0 版本化追加：flags 位 1 表示「基因驱动发育」（模仿 Cell Lab，不用 dev_program 指令序列）。
## 置位后：个体不经历指令发育期；分裂由 division_mass 能量阈值触发，子代类型按 child_types
## 逐次 assigned（分裂即分化，对应 Cell Lab Gene.i/j），亲子连接由 FLAG_GLUE_LINKS 决定。
## 该模式下 dev_program 为空；清零则保持 v0.14.x 的指令模式（旧存档完全兼容）。
const FLAG_GENE_MODE: int = 1 << 1

## v0.17.0 版本化追加：一个基因模式基因组由多个「模式槽」组成，对应 Macro 的 Gene 模式页。
## 每个模式有自己的类型、行为/特殊控制、两个子代模式；GNP1 布局仍冻结，modes 只随
## CommandBus 的 genome_gene payload 与存档 schema v5 走，且仅在基因模式下参与 hash。
const MAX_GENOME_MODES: int = 40
const DEFAULT_TRANSFER_RATE: float = 0.12
## v0.18.0：取消 per-organism 8 细胞硬上限；-1 表示无限，>=2 才作为显式个体上限。
const UNLIMITED_CELLS: int = -1
const UNLIMITED_TELOMERE: int = -1
const TELOMERE_OPTIONS: Array[int] = [-1, 5, 10, 20, 40, 80]
const GLOBAL_CELL_CAPACITY: int = 8000

## v0.17.0：证据边界——Macro 的 40 Gene 槽/完整行为总线未穷尽；本模型只把截图中可核对的
## 模式切换、两子代、黏附/镜像、分裂质量/角度/比例、营养优先级、RGB、黏附与骨架/大小/连接数
## 作为版本化追加字段。其余 Macro 专有控件不臆造运行时语义。
const MODE_FIELD_KEYS: Array[String] = [
	"name", "cell_type", "make_glue", "stay_alive", "initial",
	"child1_type", "child2_type", "child1_mode", "child2_mode",
	"child1_glue", "child2_glue", "child1_mirror", "child2_mirror",
	"child1_angle", "child2_angle", "division_mass", "invert_split_mass",
	"split_ratio", "max_divisions", "split_angle", "split_angle2", "ratio", "ratio2",
	"nutrition_priority", "transfer_rate", "cell_stiffness", "cell_size",
	"max_connections", "min_connections", "color_r", "color_g", "color_b",
	"adhesion_strength", "adhesion_length", "adhesion_stretch",
	"link_division_limit", "telomere",
]

static func has_glue_links(genome: RefCounted) -> bool:
	return genome != null and (int(genome.get("flags")) & FLAG_GLUE_LINKS) != 0

static func is_gene_mode(genome: RefCounted) -> bool:
	return genome != null and (int(genome.get("flags")) & FLAG_GENE_MODE) != 0

static func has_modes(genome: RefCounted) -> bool:
	if genome == null:
		return false
	var modes: Variant = genome.get("modes")
	return modes is Array and not (modes as Array).is_empty()

static func default_mode(index: int = 0) -> Dictionary:
	return normalized_mode({}, index)

## v0.18.0：端粒只允许 Cell Lab Gene.B[6] 的离散档；非法值取最近的有限档。
static func normalize_telomere(value: Variant) -> int:
	var raw: int = int(value)
	if raw == UNLIMITED_TELOMERE:
		return UNLIMITED_TELOMERE
	var best: int = 5
	var best_delta: int = 1000000
	for option in TELOMERE_OPTIONS:
		if option < 0:
			continue
		var delta: int = absi(raw - int(option))
		if delta < best_delta:
			best_delta = delta
			best = int(option)
	return best

## v0.17.0：默认 5 模式链接体：M1 → M2/M3，M2 → M4/M5，M3 → M3/M3；
## 共 3 次分裂得到 4 细胞/3 黏附连接，替代旧的 9 条 dev_program 演示。
static func demo_modes() -> Array[Dictionary]:
	return [
		normalized_mode({"name": "M1_Pg", "cell_type": 0, "child1_type": 2, "child2_type": 4,
			"child1_mode": 1, "child2_mode": 2, "child1_angle": 0.0, "child2_angle": 0.25,
			"division_mass": 0.05, "max_divisions": 1}, 0),
		normalized_mode({"name": "M2_Mv", "cell_type": 2, "child1_type": 2, "child2_type": 5,
			"child1_mode": 3, "child2_mode": 4, "child1_angle": 0.0, "child2_angle": 0.5,
			"division_mass": 0.05, "max_divisions": 1}, 1),
		normalized_mode({"name": "M3_En", "cell_type": 4, "child1_type": 4, "child2_type": 4,
			"child1_mode": 2, "child2_mode": 2, "child1_angle": 0.0, "child2_angle": 0.75,
			"division_mass": 0.05, "max_divisions": 1}, 2),
		normalized_mode({"name": "M4_Mv", "cell_type": 2, "max_divisions": 0}, 3),
		normalized_mode({"name": "M5_Info", "cell_type": 5, "max_divisions": 0}, 4),
	]

static func normalized_mode(value: Variant, index: int = 0) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var result: Dictionary = {}
	result["name"] = str(source.get("name", "M%d" % (index + 1)))
	result["cell_type"] = clampi(int(source.get("cell_type", 0)), 0, 255)
	result["make_glue"] = bool(source.get("make_glue", true))
	result["stay_alive"] = bool(source.get("stay_alive", true))
	result["initial"] = bool(source.get("initial", index == 0))
	result["child1_type"] = clampi(int(source.get("child1_type", 0)), 0, 255)
	result["child2_type"] = clampi(int(source.get("child2_type", 2)), 0, 255)
	result["child1_mode"] = clampi(int(source.get("child1_mode", 0)), 0, MAX_GENOME_MODES - 1)
	result["child2_mode"] = clampi(int(source.get("child2_mode", 0)), 0, MAX_GENOME_MODES - 1)
	result["child1_glue"] = bool(source.get("child1_glue", true))
	result["child2_glue"] = bool(source.get("child2_glue", true))
	result["child1_mirror"] = bool(source.get("child1_mirror", false))
	result["child2_mirror"] = bool(source.get("child2_mirror", false))
	for key in ["child1_angle", "child2_angle", "split_angle", "split_angle2", "ratio", "ratio2",
			"nutrition_priority", "cell_stiffness", "color_r", "color_g", "color_b"]:
		result[key] = clampf(float(source.get(key, 0.5)), 0.0, 1.0)
	result["child1_angle"] = clampf(float(source.get("child1_angle", 0.0)), 0.0, 1.0)
	result["child2_angle"] = clampf(float(source.get("child2_angle", 0.25)), 0.0, 1.0)
	result["split_angle"] = clampf(float(source.get("split_angle", 0.0)), 0.0, 1.0)
	result["split_angle2"] = clampf(float(source.get("split_angle2", 0.25)), 0.0, 1.0)
	result["ratio"] = clampf(float(source.get("ratio", 0.5)), 0.0, 1.0)
	result["ratio2"] = clampf(float(source.get("ratio2", 0.5)), 0.0, 1.0)
	result["nutrition_priority"] = clampf(float(source.get("nutrition_priority", 0.5)), 0.0, 1.0)
	result["cell_stiffness"] = clampf(float(source.get("cell_stiffness", 0.5)), 0.0, 1.0)
	result["color_r"] = clampf(float(source.get("color_r", 0.36)), 0.0, 1.0)
	result["color_g"] = clampf(float(source.get("color_g", 0.88)), 0.0, 1.0)
	result["color_b"] = clampf(float(source.get("color_b", 0.75)), 0.0, 1.0)
	result["division_mass"] = clampf(float(source.get("division_mass", 0.05)), 0.05, 100.0)
	result["invert_split_mass"] = bool(source.get("invert_split_mass", false))
	result["split_ratio"] = clampf(float(source.get("split_ratio", 0.5)), 0.05, 0.95)
	result["max_divisions"] = clampi(int(source.get("max_divisions", 1)), 0, MAX_GENE_DIVISIONS)
	result["transfer_rate"] = clampf(float(source.get("transfer_rate", DEFAULT_TRANSFER_RATE)), 0.0, 1.0)
	result["cell_size"] = clampf(float(source.get("cell_size", 1.0)), 0.5, 2.0)
	result["max_connections"] = clampi(int(source.get("max_connections", 4)), 0, 16)
	result["min_connections"] = clampi(int(source.get("min_connections", 0)), 0, result["max_connections"])
	for key in ["adhesion_strength", "adhesion_length", "adhesion_stretch"]:
		result[key] = clampf(float(source.get(key, 0.0)), 0.0, 1.0)
	# v0.18.0：旧模式缺字段时保持旧行为（不抑制分裂、端粒无限）。
	result["link_division_limit"] = clampi(int(source.get("link_division_limit", -1)), -1, 16)
	result["telomere"] = normalize_telomere(source.get("telomere", UNLIMITED_TELOMERE))
	# v0.29.0：官方 Gene.m/n —— 分裂时旧连接是否重分配给母/子。默认 false 保持旧行为与旧 hash。
	result["link_keep_mother"] = bool(source.get("link_keep_mother", false))
	result["link_keep_child"] = bool(source.get("link_keep_child", false))
	return result

static func get_mode(genome: RefCounted, index: int) -> Dictionary:
	if not has_modes(genome):
		return {}
	var modes: Array = genome.get("modes") as Array
	var clamped: int = clampi(index, 0, modes.size() - 1)
	return normalized_mode(modes[clamped], clamped)

var version: int = 1
var flags: int = 0
var respiration: int = 1
var mutation_rate_exp: int = 0
var loci: PackedByteArray = PackedByteArray()
var traits: PackedByteArray = PackedByteArray()
var dev_program: Array[Dictionary] = []
## v0.15.0 基因驱动发育参数（Cell Lab Gene.b/c/i/j 语义）。不进 GNP1 冻结二进制，
## 随存档 schema 版本化保存；仅 FLAG_GENE_MODE 置位时参与运行时与 hash。
var division_mass: float = 1.0
var split_ratio: float = 0.5
var max_divisions: int = 3
var child_types: PackedByteArray = PackedByteArray()
var split_angles: PackedByteArray = PackedByteArray()
## v0.16.0 基因模式表型字段（补齐 Macro 编辑器草案；不进 GNP1 冻结二进制）。
## 证据与「本项目版本化追加」边界见 v1.1 §5.3 与 v2.1 §0.3。
var nutrition_priority: float = 0.5
var cell_stiffness: float = 0.5
var cell_size: float = 1.0
var max_connections: int = 4
var min_connections: int = 0
var color_r: float = 0.36
var color_g: float = 0.88
var color_b: float = 0.75
## v0.17.0：多模式基因组与全基因组传递率缺省。modes 为空时所有旧字段/旧 hash 完全不变。
var modes: Array[Dictionary] = []
var transfer_rate: float = DEFAULT_TRANSFER_RATE
## v0.18.0：个体细胞数上限，-1 无限；不进 GNP1，旧 payload/存档缺字段回退 max_divisions+1。
var max_cells_per_organism: int = UNLIMITED_CELLS
## 运行时谱系元数据（阶段 4）：不进 GNP1 二进制编解码（格式已冻结）。
var species_id: int = 0
var lineage_id: int = -1

## 加权基因组距离（§4.7 物种判定）：位点汉明 + 性状 L1 + 发育程序编辑距离。
static func distance(a: RefCounted, b: RefCounted) -> float:
	if a == null or b == null:
		return 1.0e9
	var locus_distance: int = 0
	var loci_a: PackedByteArray = a.get("loci")
	var loci_b: PackedByteArray = b.get("loci")
	var max_loci: int = maxi(loci_a.size(), loci_b.size())
	for i in range(max_loci):
		var va: int = int(loci_a[i]) if i < loci_a.size() else -1
		var vb: int = int(loci_b[i]) if i < loci_b.size() else -1
		if va != vb:
			locus_distance += 1
	var trait_distance: int = 0
	var traits_a: PackedByteArray = a.get("traits")
	var traits_b: PackedByteArray = b.get("traits")
	for i in range(mini(traits_a.size(), traits_b.size())):
		trait_distance += absi(int(traits_a[i]) - int(traits_b[i]))
	var program_a: Array = a.get("dev_program")
	var program_b: Array = b.get("dev_program")
	var program_distance: int = absi(program_a.size() - program_b.size())
	for i in range(mini(program_a.size(), program_b.size())):
		var ia: Dictionary = program_a[i]
		var ib: Dictionary = program_b[i]
		for key in ["opcode", "a", "b", "c"]:
			if int(ia.get(key, -1)) != int(ib.get(key, -1)):
				program_distance += 1
	# v0.15.0：基因模式参数参与物种距离，避免不同分裂阈值/子代类型被当成同种。
	if is_gene_mode(a) or is_gene_mode(b):
		var mass_a: float = float(a.get("division_mass")) if is_gene_mode(a) else 0.0
		var mass_b: float = float(b.get("division_mass")) if is_gene_mode(b) else 0.0
		var div_a: int = int(a.get("max_divisions")) if is_gene_mode(a) else 0
		var div_b: int = int(b.get("max_divisions")) if is_gene_mode(b) else 0
		program_distance += absi(int(round(mass_a * 10.0)) - int(round(mass_b * 10.0)))
		program_distance += absi(div_a - div_b)
		var types_a: PackedByteArray = a.get("child_types")
		var types_b: PackedByteArray = b.get("child_types")
		for i in range(mini(types_a.size(), types_b.size())):
			if types_a[i] != types_b[i]:
				program_distance += 1
		# v0.16.0：表型差异也影响物种判定，但只有基因模式参与。
		program_distance += absi(int(round(float(a.get("nutrition_priority")) * 10.0)) - int(round(float(b.get("nutrition_priority")) * 10.0)))
		program_distance += absi(int(round(float(a.get("cell_size")) * 10.0)) - int(round(float(b.get("cell_size")) * 10.0)))
		program_distance += absi(int(a.get("max_connections")) - int(b.get("max_connections")))
		program_distance += absi(int(a.get("min_connections")) - int(b.get("min_connections")))
		# v0.17.0：模式数量与逐模式类型/子代模式差异参与物种判定；旧空 modes 不加分。
		var raw_modes_a: Variant = a.get("modes")
		var raw_modes_b: Variant = b.get("modes")
		var modes_a: Array = []
		var modes_b: Array = []
		if raw_modes_a is Array:
			modes_a = raw_modes_a as Array
		if raw_modes_b is Array:
			modes_b = raw_modes_b as Array
		program_distance += absi(modes_a.size() - modes_b.size())
		if not modes_a.is_empty() or not modes_b.is_empty():
			var cap_a: int = int(a.get("max_cells_per_organism")) if is_gene_mode(a) else UNLIMITED_CELLS
			var cap_b: int = int(b.get("max_cells_per_organism")) if is_gene_mode(b) else UNLIMITED_CELLS
			program_distance += absi(cap_a - cap_b)
		for i in range(mini(modes_a.size(), modes_b.size())):
			var mode_a: Dictionary = normalized_mode(modes_a[i], i)
			var mode_b: Dictionary = normalized_mode(modes_b[i], i)
			program_distance += absi(int(mode_a.get("cell_type")) - int(mode_b.get("cell_type")))
			program_distance += absi(int(mode_a.get("child1_mode")) - int(mode_b.get("child1_mode")))
			program_distance += absi(int(mode_a.get("child2_mode")) - int(mode_b.get("child2_mode")))
			program_distance += absi(int(round(float(mode_a.get("transfer_rate")) * 10.0)) - int(round(float(mode_b.get("transfer_rate")) * 10.0)))
			program_distance += absi(int(mode_a.get("link_division_limit")) - int(mode_b.get("link_division_limit")))
			program_distance += absi(int(mode_a.get("telomere")) - int(mode_b.get("telomere"))) / 5
	return float(locus_distance) * 1.0 + float(trait_distance) * 0.05 + float(program_distance) * 0.5

func is_valid() -> bool:
	if version < 1 or flags < 0 or flags > 65535 or respiration < 0 or respiration > 2:
		return false
	if mutation_rate_exp < 0 or mutation_rate_exp > 255 or loci.size() > 255 or traits.size() != 8:
		return false
	if dev_program.size() > MAX_DEV_INSTRUCTIONS:
		return false
	for instruction in dev_program:
		var opcode: int = int(instruction.get("opcode", -1))
		var a: int = int(instruction.get("a", -1))
		var b: int = int(instruction.get("b", -1))
		var c: int = int(instruction.get("c", -1))
		if opcode < 0 or opcode > MAX_OPCODE or a < 0 or a > MAX_OPERAND_8:
			return false
		if b < 0 or b > MAX_OPERAND_8 or c < 0 or c > MAX_OPERAND_10:
			return false
	if division_mass < 0.05 or division_mass > 100.0:
		return false
	if split_ratio < 0.05 or split_ratio > 0.95:
		return false
	if max_divisions < 0 or max_divisions > MAX_GENE_DIVISIONS:
		return false
	if child_types.size() > MAX_GENE_DIVISIONS or split_angles.size() > MAX_GENE_DIVISIONS:
		return false
	if nutrition_priority < 0.0 or nutrition_priority > 1.0:
		return false
	if cell_stiffness < 0.0 or cell_stiffness > 1.0:
		return false
	if cell_size < 0.5 or cell_size > 2.0:
		return false
	if max_connections < 0 or max_connections > 16 or min_connections < 0 or min_connections > 16:
		return false
	if min_connections > max_connections:
		return false
	if modes.size() > MAX_GENOME_MODES:
		return false
	if transfer_rate < 0.0 or transfer_rate > 1.0:
		return false
	if max_cells_per_organism != UNLIMITED_CELLS and (max_cells_per_organism < 2 or max_cells_per_organism > GLOBAL_CELL_CAPACITY):
		return false
	for i in range(modes.size()):
		if not modes[i] is Dictionary:
			return false
		var normalized: Dictionary = normalized_mode(modes[i], i)
		if int(normalized.get("min_connections")) > int(normalized.get("max_connections")):
			return false
	return true

func set_modes(values: Array) -> bool:
	if values.size() > MAX_GENOME_MODES:
		return false
	var normalized: Array[Dictionary] = []
	for i in range(values.size()):
		if not values[i] is Dictionary:
			return false
		normalized.append(normalized_mode(values[i], i))
	var previous: Array[Dictionary] = modes
	modes = normalized
	if not is_valid():
		modes = previous
		return false
	return true

func set_development_program(instructions: Array) -> bool:
	if instructions.size() > MAX_DEV_INSTRUCTIONS:
		return false
	var normalized: Array[Dictionary] = []
	for value in instructions:
		if not value is Dictionary:
			return false
		if not value.has("opcode") or not value.has("a") or not value.has("b") or not value.has("c"):
			return false
		normalized.append(value.duplicate(true))
	var previous: Array[Dictionary] = dev_program
	dev_program = normalized
	if not is_valid():
		dev_program = previous
		return false
	return true

func division_count() -> int:
	var count: int = 0
	for instruction in dev_program:
		if int(instruction.get("opcode", -1)) == OP_DIVIDE:
			count += 1
	return count

static func _mix_quantized(current: int, quantized: int) -> int:
	var value: int = current
	for shift in [0, 8, 16, 24]:
		value = int((value ^ ((quantized >> shift) & 255)) * 16777619) & 0x7fffffff
	return value

func hash() -> int:
	var encoded: PackedByteArray = load("res://scripts/core/data/GenomeCodec.gd").call("encode", self)
	var value: int = 2166136261
	for byte_value in encoded:
		value = int((value ^ int(byte_value)) * 16777619) & 0x7fffffff
	# v0.15.0：基因模式字段不在 GNP1 冻结二进制里，显式混入 hash；
	# 旧模式（FLAG_GENE_MODE 清零）hash 与 v0.14.x 逐位一致。
	if is_gene_mode(self):
		for quantized in [int(round(division_mass * 1000000.0)), int(round(split_ratio * 1000000.0)), max_divisions]:
			for shift in [0, 8, 16, 24]:
				value = int((value ^ ((quantized >> shift) & 255)) * 16777619) & 0x7fffffff
		for byte_value in child_types:
			value = int((value ^ int(byte_value)) * 16777619) & 0x7fffffff
		for byte_value in split_angles:
			value = int((value ^ int(byte_value)) * 16777619) & 0x7fffffff
		# v0.16.0：Macro 表型字段同样不进 GNP1，显式混入基因模式 hash。
		var macro_quantized: Array[int] = [
			int(round(nutrition_priority * 1000000.0)),
			int(round(cell_stiffness * 1000000.0)),
			int(round(cell_size * 1000000.0)),
			max_connections, min_connections,
			int(round(clampf(color_r, 0.0, 1.0) * 255.0)),
			int(round(clampf(color_g, 0.0, 1.0) * 255.0)),
			int(round(clampf(color_b, 0.0, 1.0) * 255.0)),
		]
		for quantized in macro_quantized:
			for shift in [0, 8, 16, 24]:
				value = int((value ^ ((quantized >> shift) & 255)) * 16777619) & 0x7fffffff
		# v0.17.0：多模式只在 modes 非空时混入，空 modes 的旧基因模式 hash 与 v0.16.0 逐位一致。
		if not modes.is_empty():
			value = _mix_quantized(value, modes.size())
			value = _mix_quantized(value, int(round(transfer_rate * 1000000.0)))
			value = _mix_quantized(value, max_cells_per_organism)
			for mode_index in range(modes.size()):
				var mode_data: Dictionary = normalized_mode(modes[mode_index], mode_index)
				for key in MODE_FIELD_KEYS:
					var entry: Variant = mode_data.get(key, 0)
					var quantized: int = 0
					if entry is bool:
						quantized = 1 if bool(entry) else 0
					elif entry is int:
						quantized = int(entry)
					elif entry is float:
						quantized = int(round(float(entry) * 1000000.0))
					elif entry is String:
						for byte_value in str(entry).to_utf8_buffer():
							quantized = int((quantized ^ int(byte_value)) * 16777619) & 0x7fffffff
					value = _mix_quantized(value, quantized)
		# v0.29.0：Gene.m/n 只在任一模式开启时混入，两个都 false 的旧基因组 hash 与 v0.28 逐位一致。
		var link_split_enabled: bool = false
		for raw_mode in modes:
			if bool((raw_mode as Dictionary).get("link_keep_mother", false)) \
				or bool((raw_mode as Dictionary).get("link_keep_child", false)):
				link_split_enabled = true
				break
		if link_split_enabled:
			for mode_index in range(modes.size()):
				var split_mode: Dictionary = normalized_mode(modes[mode_index], mode_index)
				value = _mix_quantized(value, 1 if bool(split_mode.get("link_keep_mother", false)) else 0)
				value = _mix_quantized(value, 1 if bool(split_mode.get("link_keep_child", false)) else 0)
	return value

func duplicate_genome() -> RefCounted:
	var script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var copy: RefCounted = script.new() as RefCounted
	copy.set("version", version)
	copy.set("flags", flags)
	copy.set("respiration", respiration)
	copy.set("mutation_rate_exp", mutation_rate_exp)
	copy.set("loci", loci.duplicate())
	copy.set("traits", traits.duplicate())
	copy.call("set_development_program", dev_program)
	copy.set("division_mass", division_mass)
	copy.set("split_ratio", split_ratio)
	copy.set("max_divisions", max_divisions)
	copy.set("child_types", child_types.duplicate())
	copy.set("split_angles", split_angles.duplicate())
	copy.set("nutrition_priority", nutrition_priority)
	copy.set("cell_stiffness", cell_stiffness)
	copy.set("cell_size", cell_size)
	copy.set("max_connections", max_connections)
	copy.set("min_connections", min_connections)
	copy.set("color_r", color_r)
	copy.set("color_g", color_g)
	copy.set("color_b", color_b)
	copy.call("set_modes", modes.duplicate(true))
	copy.set("transfer_rate", transfer_rate)
	copy.set("max_cells_per_organism", max_cells_per_organism)
	copy.set("species_id", species_id)
	copy.set("lineage_id", lineage_id)
	return copy
