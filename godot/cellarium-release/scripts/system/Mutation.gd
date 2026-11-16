extends RefCounted
## 五类突变算子（§4.7）。确定性：种子由 genome_id/parent_id/tick/算子序号派生，不用全局随机。
## 不改变传入 genome（返回副本）；GNP1 二进制格式已冻结，本模块只操作运行时字段。
## 纯 RefCounted 静态模块，无 class_name，调用方 preload。

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")

const RATE_POINT: float = 0.001
const RATE_FUNCTION: float = 0.0004
const RATE_DUP_DEL: float = 0.0002
const RATE_DEVELOPMENT: float = 0.0005
const RATE_META: float = 0.0001
const MAX_ENV_STRESS_MULTIPLIER: float = 4.0
const MIN_LOCI: int = 4
const MAX_LOCI: int = 16
const MAX_TRAIT: int = 63

static func _rng(genome_id: int, parent_id: int, tick: int, salt: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_value: int = (genome_id * 0x9e3779b1 + parent_id * 0x85ebca6b + tick * 0xc2b2ae35 + salt * 0x27d4eb2f) & 0x7fffffff
	rng.seed = seed_value
	return rng

static func mutate(genome: RefCounted, genome_id: int, parent_id: int, tick: int,
		env_stress: float = 0.0) -> RefCounted:
	## 返回突变后的副本（可能无任何变化）。env_stress 仅放大概率，不改变方向。
	if genome == null or not bool(genome.call("is_valid")):
		return null
	var child: RefCounted = genome.call("duplicate_genome")
	var stress: float = clampf(env_stress, 0.0, 1.0)
	var multiplier: float = 1.0 + stress * (MAX_ENV_STRESS_MULTIPLIER - 1.0)
	var point_rng: RandomNumberGenerator = _rng(genome_id, parent_id, tick, 1)
	_apply_point_mutation(child, point_rng, multiplier)
	var func_rng: RandomNumberGenerator = _rng(genome_id, parent_id, tick, 2)
	_apply_function_mutation(child, func_rng, multiplier)
	var struct_rng: RandomNumberGenerator = _rng(genome_id, parent_id, tick, 3)
	_apply_structure_mutation(child, struct_rng, multiplier)
	var dev_rng: RandomNumberGenerator = _rng(genome_id, parent_id, tick, 4)
	_apply_development_mutation(child, dev_rng, multiplier)
	var meta_rng: RandomNumberGenerator = _rng(genome_id, parent_id, tick, 5)
	_apply_meta_mutation(child, meta_rng, multiplier)
	if not bool(child.call("is_valid")):
		return genome.call("duplicate_genome")
	return child

static func _apply_point_mutation(genome: RefCounted, rng: RandomNumberGenerator, multiplier: float) -> void:
	var traits: PackedByteArray = genome.get("traits")
	for i in range(traits.size()):
		if rng.randf() < RATE_POINT * multiplier:
			var delta: int = 1 if rng.randf() < 0.5 else -1
			traits[i] = clampi(int(traits[i]) + delta, 0, MAX_TRAIT)
	genome.set("traits", traits)

static func _apply_function_mutation(genome: RefCounted, rng: RandomNumberGenerator, multiplier: float) -> void:
	var loci: PackedByteArray = genome.get("loci")
	for i in range(loci.size()):
		if rng.randf() < RATE_FUNCTION * multiplier:
			var replacement: int = int(loci[i])
			while replacement == int(loci[i]):
				replacement = rng.randi_range(0, 16)
			loci[i] = replacement
	genome.set("loci", loci)

static func _apply_structure_mutation(genome: RefCounted, rng: RandomNumberGenerator, multiplier: float) -> void:
	if rng.randf() >= RATE_DUP_DEL * multiplier:
		return
	var loci: PackedByteArray = genome.get("loci")
	if loci.size() <= MIN_LOCI and rng.randf() < 0.5:
		return
	if loci.size() >= MAX_LOCI and rng.randf() >= 0.5:
		return
	if loci.size() > MIN_LOCI and rng.randf() < 0.5:
		loci.remove_at(rng.randi_range(0, loci.size() - 1))
	elif loci.size() < MAX_LOCI:
		var source: int = rng.randi_range(0, loci.size() - 1)
		loci.insert(source, int(loci[source]))
	genome.set("loci", loci)

static func _apply_development_mutation(genome: RefCounted, rng: RandomNumberGenerator, multiplier: float) -> void:
	var program: Array = genome.get("dev_program")
	if program.is_empty():
		return
	if rng.randf() < RATE_DEVELOPMENT * multiplier:
		var index: int = rng.randi_range(0, program.size() - 1)
		var instruction: Dictionary = (program[index] as Dictionary).duplicate()
		var key: String = ["a", "b", "c"][rng.randi_range(0, 2)]
		var max_value: int = 255 if key != "c" else 1023
		var delta: int = 1 if rng.randf() < 0.5 else -1
		instruction[key] = clampi(int(instruction.get(key, 0)) + delta, 0, max_value)
		program[index] = instruction
	genome.call("set_development_program", program)

static func _apply_meta_mutation(genome: RefCounted, rng: RandomNumberGenerator, multiplier: float) -> void:
	if rng.randf() < RATE_META * multiplier:
		var rate: int = int(genome.get("mutation_rate_exp"))
		var delta: int = 1 if rng.randf() < 0.5 else -1
		genome.set("mutation_rate_exp", clampi(rate + delta, 0, 255))
