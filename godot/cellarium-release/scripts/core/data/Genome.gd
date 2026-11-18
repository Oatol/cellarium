extends RefCounted
## GNP1 运行时模型。发育指令按 [opcode:6][a:8][b:8][c:10] 编码为 u32。
## 字节序列化由 GenomeCodec 负责；dev_program 是唯一发育结构真相源。

const MAX_DEV_INSTRUCTIONS: int = 64
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

static func has_glue_links(genome: RefCounted) -> bool:
	return genome != null and (int(genome.get("flags")) & FLAG_GLUE_LINKS) != 0

var version: int = 1
var flags: int = 0
var respiration: int = 1
var mutation_rate_exp: int = 0
var loci: PackedByteArray = PackedByteArray()
var traits: PackedByteArray = PackedByteArray()
var dev_program: Array[Dictionary] = []
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
	copy.set("species_id", species_id)
	copy.set("lineage_id", lineage_id)
	return copy
