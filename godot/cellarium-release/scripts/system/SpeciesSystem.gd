extends RefCounted
## 物种判定、谱系追踪与灭绝档案（§4.7）。确定性：只依赖 genome 距离与 tick，无全局随机。
## 纯 RefCounted，无 class_name，调用方 preload。species_id 从 0 递增，lineage_id 为首次分化序号。

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")

@export var speciation_distance: float = 6.0
@export var speciation_cooldown: int = 600

var _species: Dictionary = {}
var _next_species_id: int = 0
var _next_lineage: int = 0
var _events: Array[Dictionary] = []

func configure(speciation_distance_value: float, cooldown: int) -> void:
	speciation_distance = maxf(0.0, speciation_distance_value)
	speciation_cooldown = maxi(0, cooldown)

func reset() -> void:
	_species.clear()
	_next_species_id = 0
	_next_lineage = 0
	_events.clear()

func species_count() -> int:
	return _species.size()

func get_species(species_id: int) -> Dictionary:
	return _species.get(species_id, {}).duplicate(true)

func get_all_species() -> Dictionary:
	return _species.duplicate(true)

func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)

func register_founder(genome: RefCounted, tick: int) -> int:
	## 建立初始物种（species_id=0）。返回 species_id。
	if genome == null:
		return -1
	if _species.is_empty():
		_species[0] = {
			"representative": genome.call("duplicate_genome"),
			"lineage_id": _next_lineage,
			"created_tick": tick,
			"peak_population": 0,
			"births": 0,
			"deaths": 0,
			"death_causes": {},
			"extinct": false,
			"extinct_tick": -1
		}
		_next_lineage += 1
		_next_species_id = 1
		return 0
	return _find_nearest_species(genome)

func _find_nearest_species(genome: RefCounted) -> int:
	var best_id: int = -1
	var best_distance: float = 1.0e9
	for species_id in _species:
		var data: Dictionary = _species[species_id]
		var distance: float = float(GENOME_SCRIPT.call("distance", genome, data.get("representative")))
		if distance < best_distance:
			best_distance = distance
			best_id = int(species_id)
	return best_id

func classify(genome: RefCounted, parent_species_id: int, tick: int) -> int:
	## 依据距离与冷却判定 Return species_id；若超阈值且过冷却，新建物种并发事件。
	if genome == null:
		return -1
	if _species.is_empty():
		return register_founder(genome, tick)
	var nearest_id: int = _find_nearest_species(genome)
	var nearest_distance: float = float(GENOME_SCRIPT.call("distance", genome, _species[nearest_id].get("representative")))
	if nearest_distance <= speciation_distance:
		return nearest_id
	if not _species.has(parent_species_id):
		return nearest_id
	var last_split: int = int(_species[parent_species_id].get("last_split_tick", -speciation_cooldown - 1))
	if tick - last_split < speciation_cooldown:
		return nearest_id
	var new_id: int = _next_species_id
	_next_species_id += 1
	_species[new_id] = {
		"representative": genome.call("duplicate_genome"),
		"lineage_id": _next_lineage,
		"created_tick": tick,
		"peak_population": 0,
		"births": 0,
		"deaths": 0,
		"death_causes": {},
		"extinct": false,
		"extinct_tick": -1,
		"parent_species_id": parent_species_id
	}
	_next_lineage += 1
	_species[parent_species_id]["last_split_tick"] = tick
	_events.append({"type": "SPECIATION", "species_id": new_id, "parent_species_id": parent_species_id, "tick": tick, "distance": nearest_distance})
	return new_id

func record_birth(species_id: int, tick: int) -> void:
	if not _species.has(species_id):
		return
	var data: Dictionary = _species[species_id]
	data["births"] = int(data.get("births", 0)) + 1
	data["extinct"] = false
	data["extinct_tick"] = -1
	_species[species_id] = data

func record_death(species_id: int, death_cause: int, tick: int) -> void:
	if not _species.has(species_id):
		return
	var data: Dictionary = _species[species_id]
	data["deaths"] = int(data.get("deaths", 0)) + 1
	var causes: Dictionary = data.get("death_causes", {})
	causes[str(death_cause)] = int(causes.get(str(death_cause), 0)) + 1
	data["death_causes"] = causes
	_species[species_id] = data

func update_population(species_id: int, population: int) -> void:
	if not _species.has(species_id):
		return
	var data: Dictionary = _species[species_id]
	data["peak_population"] = maxi(int(data.get("peak_population", 0)), population)
	_species[species_id] = data

func mark_extinct(species_id: int, tick: int) -> void:
	if not _species.has(species_id):
		return
	var data: Dictionary = _species[species_id]
	if bool(data.get("extinct", false)):
		return
	data["extinct"] = true
	data["extinct_tick"] = tick
	_species[species_id] = data
	_events.append({"type": "EXTINCTION", "species_id": species_id, "tick": tick, "archive": _archive_for(species_id)})

func _archive_for(species_id: int) -> Dictionary:
	var data: Dictionary = _species.get(species_id, {})
	var causes: Dictionary = data.get("death_causes", {})
	var main_cause: int = -1
	var main_count: int = 0
	for cause_key in causes:
		if int(causes[cause_key]) > main_count:
			main_count = int(causes[cause_key])
			main_cause = int(cause_key)
	var representative: RefCounted = data.get("representative")
	var traits: PackedByteArray = PackedByteArray() if representative == null else representative.get("traits")
	return {
		"species_id": species_id,
		"lineage_id": int(data.get("lineage_id", -1)),
		"lifespan_ticks": int(data.get("extinct_tick", -1)) - int(data.get("created_tick", 0)),
		"peak_population": int(data.get("peak_population", 0)),
		"main_death_cause": main_cause,
		"core_traits": traits.duplicate(),
		"births": int(data.get("births", 0)),
		"deaths": int(data.get("deaths", 0))
	}

func get_archive(species_id: int) -> Dictionary:
	if not _species.has(species_id) or not bool(_species[species_id].get("extinct", false)):
		return {}
	return _archive_for(species_id)

## 系统发育树导出（§4.7 / §7 sim.get_phylogeny）：节点含物种与谱系编号，
## 边由 parent_species_id 生成，分化事件单独成列。只读，不改模拟状态。
func export_phylogeny() -> Dictionary:
	var nodes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	for species_id in _species:
		var data: Dictionary = _species[species_id]
		var parent_id: int = int(data.get("parent_species_id", -1))
		nodes.append({
			"species_id": int(species_id),
			"lineage_id": int(data.get("lineage_id", -1)),
			"parent_species_id": parent_id,
			"created_tick": int(data.get("created_tick", 0)),
			"extinct": bool(data.get("extinct", false)),
			"extinct_tick": int(data.get("extinct_tick", -1))
		})
		if parent_id >= 0:
			edges.append({"from": parent_id, "to": int(species_id), "tick": int(data.get("created_tick", 0))})
	var speciations: Array[Dictionary] = []
	for event in _events:
		if str(event.get("type", "")) == "SPECIATION":
			speciations.append((event as Dictionary).duplicate(true))
	return {
		"nodes": nodes,
		"edges": edges,
		"speciation_events": speciations,
		"species_count": _species.size()
	}
