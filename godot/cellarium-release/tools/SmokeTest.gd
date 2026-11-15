extends SceneTree
## 无头解析清单 + 数据层契约断言。新增脚本必须登记到 SCRIPT_MANIFEST。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path <project> --script res://tools/SmokeTest.gd

const SCRIPT_MANIFEST: Array[String] = [
	"res://scripts/Main.gd",
	"res://scripts/core/data/EnvironmentPreset.gd",
	"res://scripts/core/data/DevelopmentContext.gd",
	"res://scripts/core/data/Genome.gd",
	"res://scripts/core/data/GenomeCodec.gd",
	"res://scripts/core/data/CellArray.gd",
	"res://scripts/core/data/OrganismStore.gd",
	"res://scripts/core/data/DevelopmentRules.gd",
	"res://scripts/core/command/CommandBus.gd",
	"res://scripts/core/tick/TickCore.gd",
	"res://scripts/system/EnvironmentManager.gd",
	"res://scripts/system/OrganismManager.gd",
]

func _initialize() -> void:
	await process_frame
	var failures: int = 0
	for path in SCRIPT_MANIFEST:
		var script: Script = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not script.can_instantiate():
			push_error("SmokeTest: failed to parse " + path)
			failures += 1
		else:
			print("SmokeTest: OK ", path)
	var scene: PackedScene = ResourceLoader.load("res://scenes/main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		push_error("SmokeTest: main.tscn not loadable")
		failures += 1
	else:
		print("SmokeTest: OK res://scenes/main.tscn")
	if not _check_basal_autonomy():
		failures += 1
	if not _check_development_rules():
		failures += 1
	if not _check_cell_arrays():
		failures += 1
	if not _check_genome_codec():
		failures += 1
	print("SmokeTest: SCRIPTS=", SCRIPT_MANIFEST.size(), " FAILURES=", failures)
	quit(1 if failures > 0 else 0)

func _check_basal_autonomy() -> bool:
	var script: Script = ResourceLoader.load("res://scripts/core/data/EnvironmentPreset.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if script == null or not script.can_instantiate():
		return false
	var preset: Object = script.new() as Object
	preset.set("nutrient_density", 1.0)
	var low: float = float(preset.call("get_basal_autonomy"))
	preset.set("nutrient_density", 2.0)
	var high: float = float(preset.call("get_basal_autonomy"))
	if high <= low:
		push_error("SmokeTest: basal_autonomy must derive from nutrient_density")
		return false
	print("SmokeTest: OK basal_autonomy scales ", low, " -> ", high)
	return true

func _check_development_rules() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var store_script: Script = load("res://scripts/core/data/OrganismStore.gd") as Script
	var rules_script: Script = load("res://scripts/core/data/DevelopmentRules.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [{"opcode": 0, "a": 0, "b": 32, "c": 0}])
	if not bool(genome.call("is_valid")) or int(genome.call("division_count")) != 1:
		push_error("SmokeTest: genome DIVIDE count/validation failed")
		return false
	if int(rules_script.call("expected_cell_count", genome)) != 2:
		push_error("SmokeTest: expected cell count must follow DIVIDE instructions")
		return false
	var division_cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var division_store: RefCounted = store_script.new() as RefCounted
	var division_org: int = int(division_store.call("create_organism", 0, 0, -1, 1))
	var parent_cell: int = int(division_cells.call("append_cell", division_org, Vector2.ZERO, 0.8, 0))
	division_store.call("add_developed_cell", division_org, parent_cell, 2)
	var child_cell: int = int(rules_script.call("execute_divide", genome, division_cells, division_store, {"type": "DIVIDE", "org_id": division_org, "cell_index": parent_cell, "instruction_index": 0}))
	if child_cell != 1 or division_cells.call("size") != 2 or int(division_store.get("cell_count")[division_org]) != 2:
		push_error("SmokeTest: DIVIDE must append a cell to the same organism")
		return false
	if not is_equal_approx(float(division_cells.get("cell_energy")[0] + division_cells.get("cell_energy")[child_cell]), 0.8):
		push_error("SmokeTest: DIVIDE must preserve total cell energy")
		return false
	if int(division_store.get("org_parent_id")[division_org]) != -1 or int(division_store.get("org_alive").size()) != 1:
		push_error("SmokeTest: DIVIDE must not create a lineage node")
		return false
	if int(division_store.get("org_state")[division_org]) != int(store_script.get_script_constant_map()["STATE_MATURE"]):
		push_error("SmokeTest: completed development must enter mature state")
		return false
	if int(rules_script.call("execute_divide", genome, division_cells, division_store, {"type": "DIVIDE", "org_id": division_org, "cell_index": parent_cell, "instruction_index": 0})) >= 0:
		push_error("SmokeTest: the same DIVIDE instruction must not execute twice")
		return false
	var invalid_cells: RefCounted = load("res://scripts/core/data/CellArray.gd").new() as RefCounted
	var invalid_parent: int = int(invalid_cells.call("append_cell", division_org, Vector2.ZERO, 0.8, 0))
	invalid_cells.call("link_cells", invalid_parent, int(invalid_cells.call("append_cell", division_org, Vector2.RIGHT, 0.0, 0)), 1.0)
	if int(rules_script.call("execute_divide", genome, invalid_cells, division_store, {"type": "DIVIDE", "org_id": division_org, "cell_index": invalid_parent, "instruction_index": 0})) >= 0:
		push_error("SmokeTest: unsupported linked-cell division must be rejected")
		return false
	var single: RefCounted = genome_script.new() as RefCounted
	single.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	single.call("set_development_program", [])
	var mature: int = int(rules_script.call("initial_lifecycle_state", single, 1))
	if mature != int(store_script.get_script_constant_map().get("STATE_MATURE", -1)):
		push_error("SmokeTest: a single-cell genome without DIVIDE must mature immediately")
		return false
	if not bool(rules_script.call("validate_divide_command", {"type": "DIVIDE", "org_id": 1, "cell_index": 0})):
		push_error("SmokeTest: valid DIVIDE command rejected")
		return false
	if bool(rules_script.call("validate_birth_command", {"type": "DIVIDE", "parent_org_id": 1})):
		push_error("SmokeTest: DIVIDE must not be accepted as REPRODUCE")
		return false
	if not bool(rules_script.call("validate_birth_command", {"type": "REPRODUCE", "parent_org_id": 1})):
		push_error("SmokeTest: valid REPRODUCE command rejected")
		return false
	print("SmokeTest: OK DIVIDE depth / single-cell maturity / command separation")
	return true

func _check_cell_arrays() -> bool:
	var cells_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var store_script: Script = load("res://scripts/core/data/OrganismStore.gd") as Script
	var cells: RefCounted = cells_script.new() as RefCounted
	var store: RefCounted = store_script.new() as RefCounted
	var org_a: int = int(store.call("create_organism", 0, 0, -1, 1))
	var org_b: int = int(store.call("create_organism", 0, 0, -1, 1))
	var a: int = int(cells.call("append_cell", org_a, Vector2.ZERO, 0.4, 0))
	var b: int = int(cells.call("append_cell", org_a, Vector2(10, 0), 0.2, 1))
	var c: int = int(cells.call("append_cell", org_b, Vector2(20, 0), 0.1, 0))
	if not bool(cells.call("link_cells", a, b, 10.0)) or not bool(cells.call("is_symmetric_link", a)):
		push_error("SmokeTest: same-organism link must be symmetric")
		return false
	if bool(cells.call("link_cells", b, c, 10.0)):
		push_error("SmokeTest: cross-organism link must be rejected")
		return false
	if not is_equal_approx(float(cells.call("total_energy_for_org", org_a)), 0.6):
		push_error("SmokeTest: organism energy must equal sum of cell energy")
		return false
	store.call("set_cell_range", org_a, 0, 2)
	store.call("set_cell_range", org_b, 2, 1)
	if not bool(store.call("validate_cell_ranges", 3)):
		push_error("SmokeTest: valid cell ranges rejected")
		return false
	print("SmokeTest: OK SoA ranges / symmetric links / same-organism constraint / energy sum")
	return true

func _check_genome_codec() -> bool:
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var codec_script: Script = load("res://scripts/core/data/GenomeCodec.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("version", 1)
	genome.set("flags", 1)
	genome.set("respiration", 2)
	genome.set("mutation_rate_exp", 7)
	genome.set("loci", PackedByteArray([1, 33, 127]))
	genome.set("traits", PackedByteArray([0, 1, 2, 3, 4, 5, 6, 63]))
	genome.call("set_development_program", [{"opcode": 0, "a": 2, "b": 128, "c": 12}, {"opcode": 4, "a": 0, "b": 0, "c": 60}])
	var encoded: PackedByteArray = codec_script.call("encode", genome)
	var decoded: RefCounted = codec_script.call("decode", encoded) as RefCounted
	if decoded == null or not bool(decoded.call("is_valid")):
		push_error("SmokeTest: GNP1 encode/decode round-trip failed")
		return false
	if int(decoded.get("mutation_rate_exp")) != 7 or decoded.get("loci") != genome.get("loci") or decoded.get("dev_program") != genome.get("dev_program"):
		push_error("SmokeTest: GNP1 round-trip lost payload fields")
		return false
	var damaged: PackedByteArray = encoded.duplicate()
	damaged[damaged.size() - 5] = int(damaged[damaged.size() - 5]) ^ 1
	if codec_script.call("decode", damaged) != null:
		push_error("SmokeTest: GNP1 checksum corruption was accepted")
		return false
	var unsupported: PackedByteArray = encoded.duplicate()
	unsupported[4] = 2
	var unsupported_crc: int = int(codec_script.call("_crc32", unsupported.slice(0, unsupported.size() - 4)))
	for shift in [0, 8, 16, 24]:
		unsupported[unsupported.size() - 4 + (shift / 8)] = (unsupported_crc >> shift) & 255
	if codec_script.call("decode", unsupported) != null:
		push_error("SmokeTest: unsupported GNP1 version was accepted")
		return false
	var trailing: PackedByteArray = encoded.slice(0, encoded.size() - 4)
	trailing.append(0)
	var trailing_crc: int = int(codec_script.call("_crc32", trailing))
	for shift in [0, 8, 16, 24]:
		trailing.append((trailing_crc >> shift) & 255)
	if codec_script.call("decode", trailing) != null:
		push_error("SmokeTest: GNP1 trailing bytes were accepted")
		return false
	print("SmokeTest: OK GNP1 round-trip / CRC / version / length rejection bytes=", encoded.size())
	return true
