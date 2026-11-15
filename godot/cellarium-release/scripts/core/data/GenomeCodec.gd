extends RefCounted
## GNP1 线格式编解码。Header 12B + loci + traits + dev_program_len u16 + u32 指令 + reserved 对齐 + CRC32。

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const MAGIC: Array[int] = [71, 78, 80, 49]
const FIXED_HEADER_BYTES: int = 12
const CHECKSUM_BYTES: int = 4

static func encode(genome: RefCounted) -> PackedByteArray:
	if genome == null or not genome.get_script() == GENOME_SCRIPT or not bool(genome.call("is_valid")):
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray(MAGIC)
	bytes.append(int(genome.get("version")) & 255)
	bytes.append((int(genome.get("version")) >> 8) & 255)
	bytes.append(int(genome.get("flags")) & 255)
	bytes.append((int(genome.get("flags")) >> 8) & 255)
	bytes.append(int(genome.get("respiration")) & 255)
	var loci: PackedByteArray = genome.get("loci")
	var traits: PackedByteArray = genome.get("traits")
	bytes.append(loci.size() & 255)
	bytes.append(traits.size() & 255)
	bytes.append(int(genome.get("mutation_rate_exp")) & 255)
	bytes.append_array(loci)
	bytes.append_array(traits)
	var program: Array = genome.get("dev_program")
	bytes.append(program.size() & 255)
	bytes.append((program.size() >> 8) & 255)
	for instruction in program:
		var packed: int = (int(instruction["opcode"]) << 26) | (int(instruction["a"]) << 18) | (int(instruction["b"]) << 10) | int(instruction["c"])
		for shift in [0, 8, 16, 24]:
			bytes.append((packed >> shift) & 255)
	while bytes.size() % 4 != 0:
		bytes.append(0)
	var checksum: int = _crc32(bytes)
	for shift in [0, 8, 16, 24]:
		bytes.append((checksum >> shift) & 255)
	return bytes

static func decode(bytes: PackedByteArray) -> RefCounted:
	if bytes.size() < FIXED_HEADER_BYTES + 8 + 2 + CHECKSUM_BYTES:
		return null
	for i in range(MAGIC.size()):
		if int(bytes[i]) != MAGIC[i]:
			return null
	var payload_end: int = bytes.size() - CHECKSUM_BYTES
	if _read_u32(bytes, payload_end) != _crc32(bytes.slice(0, payload_end)):
		return null
	var version: int = _read_u16(bytes, 4)
	var flags: int = _read_u16(bytes, 6)
	var locus_count: int = int(bytes[9])
	var trait_count: int = int(bytes[10])
	if version < 1 or trait_count != 8:
		return null
	var cursor: int = FIXED_HEADER_BYTES
	if cursor + locus_count + trait_count + 2 > payload_end:
		return null
	var genome: RefCounted = GENOME_SCRIPT.new() as RefCounted
	genome.set("version", version)
	genome.set("flags", flags)
	genome.set("respiration", int(bytes[8]))
	genome.set("mutation_rate_exp", int(bytes[11]))
	genome.set("loci", bytes.slice(cursor, cursor + locus_count))
	cursor += locus_count
	genome.set("traits", bytes.slice(cursor, cursor + trait_count))
	cursor += trait_count
	var instruction_count: int = _read_u16(bytes, cursor)
	cursor += 2
	if instruction_count > 64 or cursor + instruction_count * 4 > payload_end:
		return null
	var program: Array[Dictionary] = []
	for i in range(instruction_count):
		var packed: int = _read_u32(bytes, cursor + i * 4)
		program.append({"opcode": (packed >> 26) & 63, "a": (packed >> 18) & 255, "b": (packed >> 10) & 255, "c": packed & 1023})
	if not bool(genome.call("set_development_program", program)):
		return null
	if not bool(genome.call("is_valid")):
		return null
	return genome

static func _read_u16(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8)

static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)

static func _crc32(bytes: PackedByteArray) -> int:
	var crc: int = 0xffffffff
	for value in bytes:
		crc = crc ^ int(value)
		for bit in range(8):
			if (crc & 1) != 0:
				crc = (crc >> 1) ^ 0xedb88320
			else:
				crc = crc >> 1
	return crc ^ 0xffffffff
