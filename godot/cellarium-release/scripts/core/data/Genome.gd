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

static func has_glue_links(genome: RefCounted) -> bool:
	return genome != null and (int(genome.get("flags")) & FLAG_GLUE_LINKS) != 0

static func is_gene_mode(genome: RefCounted) -> bool:
	return genome != null and (int(genome.get("flags")) & FLAG_GENE_MODE) != 0

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
	copy.set("species_id", species_id)
	copy.set("lineage_id", lineage_id)
	return copy
