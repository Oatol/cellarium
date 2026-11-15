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

var version: int = 1
var flags: int = 0
var respiration: int = 1
var mutation_rate_exp: int = 0
var loci: PackedByteArray = PackedByteArray()
var traits: PackedByteArray = PackedByteArray()
var dev_program: Array[Dictionary] = []

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
	return copy
