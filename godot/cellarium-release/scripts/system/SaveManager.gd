extends RefCounted
## 存档快照与恢复（§3.5 / T08）。捕获影响确定性的全部运行时状态：
## 细胞/个体 SoA、基因组池、五通道环境场、物种谱系、统计环形缓冲、能量账本与 tick 计数。
## 纯 RefCounted，无 class_name，调用方 preload。schema_version 只升不降。
## 不修改 GNP1 冻结格式；species_id / lineage_id 作为运行时元数据随基因组池一起保存。

const SCHEMA_VERSION: int = 8
const SAVE_FORMAT: String = "cellarium.gsave.v1"

const CELL_ARRAY_NAMES: Array[String] = [
	"cell_pos_x", "cell_pos_y", "cell_prev_x", "cell_prev_y",
	"cell_energy", "cell_alive", "cell_type", "cell_org_id", "cell_link_count",
	"link_cell_a", "link_cell_b", "link_rest_length",
	"expression_weights", "neural_weights", "behavior_intents",
]

## v0.16.0：schema 1–2 的旧快照没有这些数组，恢复时按默认值补齐。
const PHENOTYPE_ARRAY_NAMES: Array[String] = [
	"cell_radius_scale", "cell_stiffness", "cell_color_r", "cell_color_g", "cell_color_b",
]

## v0.17.0：schema 1–3 的旧快照没有逐细胞模式槽，恢复时按 0 补齐。
const MODE_ARRAY_NAMES: Array[String] = ["cell_mode", "cell_mode_depth"]

## v0.18.0：schema 1–4 的旧快照没有逐细胞端粒，恢复时按 -1（无限）补齐。
const TELOMERE_ARRAY_NAMES: Array[String] = ["cell_telomere"]

## v0.19.0：schema 1–5 的旧快照没有半径低通基线/能量因子。
## 恢复时 baseline = 旧 cell_radius_scale，energy_scale = 1.0，逐位保持旧半径。
const ENERGY_RADIUS_ARRAY_NAMES: Array[String] = ["cell_radius_baseline", "cell_energy_scale"]

## v0.20.0：schema 1–6 的旧快照没有逐细胞分裂 tick，恢复时填 -2（未过宽限）。
const DIVISION_TICK_ARRAY_NAMES: Array[String] = ["cell_division_tick"]

## v0.29.0：schema 1–7 没有细胞朝向与连接方向；恢复时朝向填 0、连接方向按两端位置重算。
const LINK_DIRECTION_ARRAY_NAMES: Array[String] = ["cell_orientation", "link_angle"]

const ORGANISM_ARRAY_NAMES: Array[String] = [
	"org_alive", "org_genome_id", "org_species_id", "org_parent_id",
	"org_age", "org_health", "org_death_cause", "org_state",
	"org_instruction_mask", "org_dev_cursor", "cell_offset", "cell_count",
]

## 快照当前模拟状态。org_manager / env_manager / tick_core 均为场景节点。
static func capture(org_manager: Node, env_manager: Node, tick_core: Node) -> Dictionary:
	var snapshot: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"format": SAVE_FORMAT,
		"sim_tick": int(org_manager.get("_sim_tick")),
		"next_genome_id": int(org_manager.get("_next_genome_id")),
		"cells": {},
		"organisms": {},
		"genomes": [],
		"field": {},
		"species": {},
		"statistics": {},
		"ledger": {},
		"tick": {},
	}

	var cells: RefCounted = org_manager.get("cells") as RefCounted
	for array_name in CELL_ARRAY_NAMES:
		var source: Variant = cells.get(array_name)
		snapshot["cells"][array_name] = _copy_array(source)
	for array_name in PHENOTYPE_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))
	for array_name in MODE_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))
	for array_name in TELOMERE_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))
	for array_name in ENERGY_RADIUS_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))
	for array_name in DIVISION_TICK_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))
	for array_name in LINK_DIRECTION_ARRAY_NAMES:
		snapshot["cells"][array_name] = _copy_array(cells.get(array_name))

	var organisms: RefCounted = org_manager.get("organisms") as RefCounted
	for array_name in ORGANISM_ARRAY_NAMES:
		var source: Variant = organisms.get(array_name)
		snapshot["organisms"][array_name] = _copy_array(source)

	var genome_pool: Dictionary = org_manager.get("genomes") as Dictionary
	for genome_id in genome_pool:
		var genome: RefCounted = genome_pool[genome_id] as RefCounted
		snapshot["genomes"].append({
			"id": int(genome_id),
			"version": int(genome.get("version")),
			"flags": int(genome.get("flags")),
			"respiration": int(genome.get("respiration")),
			"mutation_rate_exp": int(genome.get("mutation_rate_exp")),
			"loci": _copy_array(genome.get("loci")),
			"traits": _copy_array(genome.get("traits")),
			"dev_program": _copy_program(genome.get("dev_program")),
			"division_mass": float(genome.get("division_mass")),
			"split_ratio": float(genome.get("split_ratio")),
			"max_divisions": int(genome.get("max_divisions")),
			"child_types": _copy_array(genome.get("child_types")),
			"split_angles": _copy_array(genome.get("split_angles")),
			"nutrition_priority": float(genome.get("nutrition_priority")),
			"cell_stiffness": float(genome.get("cell_stiffness")),
			"cell_size": float(genome.get("cell_size")),
			"max_connections": int(genome.get("max_connections")),
			"min_connections": int(genome.get("min_connections")),
			"color_r": float(genome.get("color_r")),
			"color_g": float(genome.get("color_g")),
			"color_b": float(genome.get("color_b")),
			"modes": (genome.get("modes") as Array).duplicate(true),
			"transfer_rate": float(genome.get("transfer_rate")),
			"max_cells_per_organism": int(genome.get("max_cells_per_organism")),
			"species_id": int(genome.get("species_id")),
			"lineage_id": int(genome.get("lineage_id")),
		})

	if env_manager != null:
		snapshot["environment_settings"] = (env_manager.call("get_environment_settings") as Dictionary).duplicate(true)
		if env_manager.has_method("get_food_store"):
			var food_store: RefCounted = env_manager.call("get_food_store") as RefCounted
			if food_store != null and food_store.has_method("to_payload"):
				snapshot["food_entities"] = food_store.call("to_payload")
		var field: RefCounted = env_manager.get("field") as RefCounted
		if field != null:
			snapshot["field"] = {
				"resolution": int(field.get("resolution")),
				"center": field.get("center"),
				"radius": float(field.get("radius")),
				"advection": field.get("advection"),
				"active_buffer": int(field.get("_active_buffer")),
				"channels": field.call("get_state_snapshot"),
				"dish_mask": _copy_array(field.get("dish_mask")),
				"terrain_mask": _copy_array(field.get("terrain_mask")),
				"pending_sources": _copy_array(field.get("_pending_sources")),
			}

	var species_system: RefCounted = org_manager.get("species_system") as RefCounted
	if species_system != null:
		snapshot["species"] = {
			"species": (species_system.get("_species") as Dictionary).duplicate(true),
			"next_species_id": int(species_system.get("_next_species_id")),
			"next_lineage": int(species_system.get("_next_lineage")),
			"events": (species_system.get("_events") as Array).duplicate(true),
		}

	var statistics: RefCounted = org_manager.get("statistics") as RefCounted
	if statistics != null:
		snapshot["statistics"] = {
			"samples": (statistics.get("_samples") as Array).duplicate(true),
			"head": int(statistics.get("_head")),
			"tick": int(statistics.get("_tick")),
			"last_sample_tick": int(statistics.get("_last_sample_tick")),
			"accum": (statistics.get("_accum") as Dictionary).duplicate(true),
		}

	var ledger: RefCounted = org_manager.get("energy_ledger") as RefCounted
	if ledger != null:
		snapshot["ledger"] = (ledger.call("get_snapshot") as Dictionary).duplicate(true)

	if tick_core != null:
		snapshot["tick"] = {
			"tick_index": int(tick_core.get("tick_index")),
			"accumulator": float(tick_core.get("_accumulator")),
			"running": bool(tick_core.get("running")),
			"speed_scale": float(tick_core.get("speed_scale")),
		}

	return snapshot

## 从快照恢复全部状态。返回恢复是否成功。配置类字段（@export / 模块 configure 参数）不改。
static func restore(snapshot: Dictionary, org_manager: Node, env_manager: Node, tick_core: Node) -> bool:
	var snapshot_version: int = int(snapshot.get("schema_version", -1))
	if snapshot_version < 1 or snapshot_version > SCHEMA_VERSION:
		push_error("SaveManager: unsupported schema_version %s" % str(snapshot.get("schema_version", "?")))
		return false
	if str(snapshot.get("format", "")) != SAVE_FORMAT:
		push_error("SaveManager: unexpected save format")
		return false

	var cells: RefCounted = org_manager.get("cells") as RefCounted
	var cell_data: Dictionary = snapshot.get("cells", {}) as Dictionary
	for array_name in CELL_ARRAY_NAMES:
		if not cell_data.has(array_name):
			push_error("SaveManager: missing cell array %s" % array_name)
			return false
		cells.set(array_name, _copy_array(cell_data[array_name]))

	for array_name in PHENOTYPE_ARRAY_NAMES:
		if cell_data.has(array_name):
			cells.set(array_name, _copy_array(cell_data[array_name]))
		else:
			var default_value: float = -1.0 if array_name.begins_with("cell_color") else 1.0
			var restored_values: PackedFloat32Array = PackedFloat32Array()
			restored_values.resize(int(cells.get("cell_pos_x").size()))
			restored_values.fill(default_value)
			cells.set(array_name, restored_values)

	for array_name in MODE_ARRAY_NAMES:
		if cell_data.has(array_name):
			cells.set(array_name, _copy_array(cell_data[array_name]))
		else:
			var restored_mode_values: PackedByteArray = PackedByteArray()
			restored_mode_values.resize(int(cells.get("cell_pos_x").size()))
			cells.set(array_name, restored_mode_values)

	for array_name in TELOMERE_ARRAY_NAMES:
		if cell_data.has(array_name):
			cells.set(array_name, _copy_array(cell_data[array_name]))
		else:
			var restored_telomeres: PackedInt32Array = PackedInt32Array()
			restored_telomeres.resize(int(cells.get("cell_pos_x").size()))
			restored_telomeres.fill(-1)
			cells.set(array_name, restored_telomeres)

	# v0.19.0：旧档把已恢复的有效倍率当作基因基线，能量因子填 1.0，半径逐位不变。
	var cell_count: int = int(cells.get("cell_pos_x").size())
	var effective_scales: PackedFloat32Array = cells.get("cell_radius_scale") as PackedFloat32Array
	var restored_baseline: PackedFloat32Array = PackedFloat32Array()
	var restored_energy: PackedFloat32Array = PackedFloat32Array()
	if cell_data.has("cell_radius_baseline"):
		restored_baseline = _copy_array(cell_data["cell_radius_baseline"])
	else:
		restored_baseline = effective_scales.duplicate()
	if cell_data.has("cell_energy_scale"):
		restored_energy = _copy_array(cell_data["cell_energy_scale"])
	else:
		restored_energy.resize(cell_count)
		restored_energy.fill(1.0)
	restored_baseline.resize(cell_count)
	restored_energy.resize(cell_count)
	cells.set("cell_radius_baseline", restored_baseline)
	cells.set("cell_energy_scale", restored_energy)

	for array_name in DIVISION_TICK_ARRAY_NAMES:
		if cell_data.has(array_name):
			cells.set(array_name, _copy_array(cell_data[array_name]))
		else:
			var restored_ticks: PackedInt32Array = PackedInt32Array()
			restored_ticks.resize(cell_count)
			restored_ticks.fill(-2)
			cells.set(array_name, restored_ticks)

	# v0.29.0：旧档没有方向数组，朝向填 0、连接方向按恢复后的两端位置重算。
	var restored_orientation: PackedFloat32Array = PackedFloat32Array()
	if cell_data.has("cell_orientation"):
		var raw_orientation: Variant = _copy_array(cell_data["cell_orientation"])
		if raw_orientation is PackedFloat32Array:
			restored_orientation = raw_orientation as PackedFloat32Array
		elif raw_orientation is Array:
			for value in raw_orientation as Array:
				restored_orientation.append(float(value))
	else:
		restored_orientation.resize(cell_count)
		restored_orientation.fill(0.0)
	cells.set("cell_orientation", restored_orientation)
	var restored_link_angles: PackedFloat32Array = PackedFloat32Array()
	if cell_data.has("link_angle"):
		var raw_angles: Variant = _copy_array(cell_data["link_angle"])
		if raw_angles is PackedFloat32Array:
			restored_link_angles = raw_angles as PackedFloat32Array
		elif raw_angles is Array:
			for value in raw_angles as Array:
				restored_link_angles.append(float(value))
	else:
		var links_a: Variant = cell_data.get("link_cell_a", [])
		var links_b: Variant = cell_data.get("link_cell_b", [])
		var pos_x: Variant = cell_data.get("cell_pos_x", [])
		var pos_y: Variant = cell_data.get("cell_pos_y", [])
		for link_index in range(int(links_a.size())):
			var a: int = int(links_a[link_index])
			var b: int = int(links_b[link_index])
			if a >= 0 and b >= 0 and a < int(pos_x.size()) and b < int(pos_x.size()):
				var dx: float = float(pos_x[b]) - float(pos_x[a])
				var dy: float = float(pos_y[b]) - float(pos_y[a])
				restored_link_angles.append(atan2(dy, dx) if dx * dx + dy * dy > 0.0 else 0.0)
			else:
				restored_link_angles.append(0.0)
	cells.set("link_angle", restored_link_angles)

	var organisms: RefCounted = org_manager.get("organisms") as RefCounted
	var organism_data: Dictionary = snapshot.get("organisms", {}) as Dictionary
	for array_name in ORGANISM_ARRAY_NAMES:
		if not organism_data.has(array_name):
			push_error("SaveManager: missing organism array %s" % array_name)
			return false
		organisms.set(array_name, _copy_array(organism_data[array_name]))

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var restored_genomes: Dictionary = {}
	for record in snapshot.get("genomes", []):
		var genome: RefCounted = genome_script.new() as RefCounted
		genome.set("version", int(record.get("version", 1)))
		genome.set("flags", int(record.get("flags", 0)))
		genome.set("respiration", int(record.get("respiration", 1)))
		genome.set("mutation_rate_exp", int(record.get("mutation_rate_exp", 0)))
		genome.set("loci", _copy_array(record.get("loci")))
		genome.set("traits", _copy_array(record.get("traits")))
		genome.set("division_mass", float(record.get("division_mass", 1.0)))
		genome.set("split_ratio", float(record.get("split_ratio", 0.5)))
		genome.set("max_divisions", int(record.get("max_divisions", 3)))
		genome.set("child_types", _copy_array(record.get("child_types", [])))
		genome.set("split_angles", _copy_array(record.get("split_angles", [])))
		genome.set("nutrition_priority", clampf(float(record.get("nutrition_priority", 0.5)), 0.0, 1.0))
		genome.set("cell_stiffness", clampf(float(record.get("cell_stiffness", 0.5)), 0.0, 1.0))
		genome.set("cell_size", clampf(float(record.get("cell_size", 1.0)), 0.5, 2.0))
		genome.set("max_connections", clampi(int(record.get("max_connections", 4)), 0, 16))
		genome.set("min_connections", clampi(int(record.get("min_connections", 0)), 0, 16))
		genome.set("color_r", clampf(float(record.get("color_r", 0.36)), 0.0, 1.0))
		genome.set("color_g", clampf(float(record.get("color_g", 0.88)), 0.0, 1.0))
		genome.set("color_b", clampf(float(record.get("color_b", 0.75)), 0.0, 1.0))
		# 旧快照缺 transfer_rate 时填 0.0：保持 v0.16.0 及更早的连接传递行为不变。
		genome.set("transfer_rate", clampf(float(record.get("transfer_rate", 0.0)), 0.0, 1.0))
		# v0.18.0：旧快照缺 max_cells_per_organism 时回退 max_divisions+1。
		var legacy_cell_cap: int = clampi(int(record.get("max_divisions", 3)) + 1, 2, 8000)
		var restored_cell_cap: int = clampi(int(record.get("max_cells_per_organism", legacy_cell_cap)), -1, 8000)
		genome.set("max_cells_per_organism", -1 if restored_cell_cap < 2 else restored_cell_cap)
		if not bool(genome.call("set_modes", record.get("modes", []))):
			push_error("SaveManager: invalid genome modes in save")
			return false
		genome.set("species_id", int(record.get("species_id", 0)))
		genome.set("lineage_id", int(record.get("lineage_id", -1)))
		if not bool(genome.call("set_development_program", record.get("dev_program", []))):
			push_error("SaveManager: invalid genome program in save")
			return false
		restored_genomes[int(record.get("id", -1))] = genome
	org_manager.set("genomes", restored_genomes)
	org_manager.set("_next_genome_id", int(snapshot.get("next_genome_id", 1)))
	org_manager.set("_sim_tick", int(snapshot.get("sim_tick", 0)))

	var environment_settings: Dictionary = snapshot.get("environment_settings", {}) as Dictionary
	if env_manager != null and not environment_settings.is_empty():
		env_manager.call("apply_environment_settings", environment_settings)

	var food_data: Dictionary = snapshot.get("food_entities", {}) as Dictionary
	if env_manager != null and not food_data.is_empty() and env_manager.has_method("get_food_store"):
		var food_store: RefCounted = env_manager.call("get_food_store") as RefCounted
		if food_store != null and food_store.has_method("from_payload"):
			if not bool(food_store.call("from_payload", food_data)):
				push_warning("SaveManager: food entity payload rejected, keeping empty pool")

	var field_data: Dictionary = snapshot.get("field", {}) as Dictionary
	if env_manager != null and not field_data.is_empty():
		var field: RefCounted = env_manager.get("field") as RefCounted
		var restored_channels: Array[PackedFloat32Array] = []
		for channel in field_data.get("channels", []):
			restored_channels.append(_copy_array(channel))
		if restored_channels.size() != 5:
			push_error("SaveManager: expected five environment channels")
			return false
		field.set("resolution", int(field_data.get("resolution", 32)))
		field.set("center", field_data.get("center"))
		field.set("radius", float(field_data.get("radius", 512.0)))
		field.set("advection", field_data.get("advection"))
		field.set("active_buffer", int(field_data.get("active_buffer", 0)))
		field.set("dish_mask", _copy_array(field_data.get("dish_mask")))
		var restored_terrain: Variant = field_data.get("terrain_mask")
		if restored_terrain != null:
			field.set("terrain_mask", _copy_array(restored_terrain))
		field.set("channels", restored_channels)
		var restored_sources: Array[PackedFloat32Array] = []
		for source in field_data.get("pending_sources", []):
			restored_sources.append(_copy_array(source))
		if not restored_sources.is_empty():
			field.set("_pending_sources", restored_sources)
		field.call("_upload_active_buffer")
		field.call("clear_runtime_caches")

	var species_data: Dictionary = snapshot.get("species", {}) as Dictionary
	if not species_data.is_empty():
		var species_system: RefCounted = org_manager.get("species_system") as RefCounted
		species_system.set("_species", (species_data.get("species", {}) as Dictionary).duplicate(true))
		species_system.set("_next_species_id", int(species_data.get("next_species_id", 0)))
		species_system.set("_next_lineage", int(species_data.get("next_lineage", 0)))
		species_system.set("_events", (species_data.get("events", []) as Array).duplicate(true))

	var stats_data: Dictionary = snapshot.get("statistics", {}) as Dictionary
	if not stats_data.is_empty():
		var statistics: RefCounted = org_manager.get("statistics") as RefCounted
		statistics.set("_samples", (stats_data.get("samples", []) as Array).duplicate(true))
		statistics.set("_head", int(stats_data.get("head", 0)))
		statistics.set("_tick", int(stats_data.get("tick", 0)))
		statistics.set("_last_sample_tick", int(stats_data.get("last_sample_tick", -1)))
		statistics.set("_accum", (stats_data.get("accum", {}) as Dictionary).duplicate(true))

	var ledger_data: Dictionary = snapshot.get("ledger", {}) as Dictionary
	if not ledger_data.is_empty():
		var ledger: RefCounted = org_manager.get("energy_ledger") as RefCounted
		ledger.call("restore_snapshot", ledger_data)

	var tick_data: Dictionary = snapshot.get("tick", {}) as Dictionary
	if tick_core != null and not tick_data.is_empty():
		tick_core.set("tick_index", int(tick_data.get("tick_index", 0)))
		tick_core.set("_accumulator", float(tick_data.get("accumulator", 0.0)))
		tick_core.set("running", bool(tick_data.get("running", true)))
		tick_core.set("speed_scale", float(tick_data.get("speed_scale", 1.0)))

	return true

## 写入 .gsave 二进制包。头部 4 字节为 schema 版本，其后为 var_to_bytes(snapshot)。
static func save_to_file(path: String, snapshot: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open %s for writing (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	var payload: PackedByteArray = var_to_bytes(snapshot)
	file.store_32(int(snapshot.get("schema_version", SCHEMA_VERSION)))
	file.store_buffer(payload)
	file.close()
	return true

## 读回 .gsave 包。格式或版本不符返回空 Dictionary。
static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("SaveManager: save file not found %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot open %s for reading (err=%d)" % [path, FileAccess.get_open_error()])
		return {}
	if file.get_length() < 4:
		file.close()
		push_error("SaveManager: truncated save file %s" % path)
		return {}
	var file_version: int = file.get_32()
	var payload: PackedByteArray = file.get_buffer(file.get_length() - 4)
	file.close()
	if file_version != SCHEMA_VERSION:
		push_error("SaveManager: save version %d != %d" % [file_version, SCHEMA_VERSION])
		return {}
	var decoded: Variant = bytes_to_var(payload)
	if not (decoded is Dictionary):
		push_error("SaveManager: save payload is not a dictionary")
		return {}
	return decoded as Dictionary

static func _copy_array(source: Variant) -> Variant:
	if source is PackedFloat32Array:
		return (source as PackedFloat32Array).duplicate()
	if source is PackedInt32Array:
		return (source as PackedInt32Array).duplicate()
	if source is PackedInt64Array:
		return (source as PackedInt64Array).duplicate()
	if source is PackedByteArray:
		return (source as PackedByteArray).duplicate()
	if source is Array:
		return (source as Array).duplicate(true)
	return source

static func _copy_program(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (source is Array):
		return result
	for instruction in source as Array:
		if not (instruction is Dictionary):
			continue
		result.append({
			"opcode": int(instruction.get("opcode", 0)),
			"a": int(instruction.get("a", 0)),
			"b": int(instruction.get("b", 0)),
			"c": int(instruction.get("c", 0)),
		})
	return result
