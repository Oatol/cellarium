extends RefCounted
## 统计环形缓冲与生态报告（§4.8）。默认 7200 点（2 分钟 @60Hz / 30 tick 聚合）。
## 三条产物：多物种折线图数据、物种与死因面板、"记录到的事实"（全部模板生成，禁止手写死文案）。
## 纯 RefCounted，无 class_name，调用方 preload。确定性：只依赖采样输入。

const DEATH_LABELS: Dictionary = {0: "未死亡", 1: "饥饿", 2: "中毒", 3: "被捕食", 4: "干预"}

@export var capacity: int = 7200
@export var sample_interval_ticks: int = 30

var _samples: Array[Dictionary] = []
var _head: int = 0
var _tick: int = 0
var _last_sample_tick: int = -1
var _accum: Dictionary = {"births": 0, "deaths": 0, "death_causes": {}}

func configure(capacity_value: int, interval: int) -> void:
	capacity = maxi(8, capacity_value)
	sample_interval_ticks = maxi(1, interval)
	reset()

func reset() -> void:
	_samples.clear()
	_head = 0
	_tick = 0
	_last_sample_tick = -1
	_accum = {"births": 0, "deaths": 0, "death_causes": {}}

func sample_count() -> int:
	return _samples.size()

func record_birth() -> void:
	_accum["births"] = int(_accum["births"]) + 1

func record_death(cause: int) -> void:
	_accum["deaths"] = int(_accum["deaths"]) + 1
	var causes: Dictionary = _accum["death_causes"]
	causes[str(cause)] = int(causes.get(str(cause), 0)) + 1
	_accum["death_causes"] = causes

## 每个模拟 tick 调用。按 sample_interval_ticks 聚合成一个采样点。
func advance_tick(species_populations: Dictionary, avg_body: float = 0.0, avg_speed: float = 0.0, avg_metabolism: float = 0.0) -> void:
	_tick += 1
	if _tick - _last_sample_tick < sample_interval_ticks:
		return
	_last_sample_tick = _tick
	var snapshot: Dictionary = {
		"tick": _tick,
		"populations": species_populations.duplicate(true),
		"births": int(_accum["births"]),
		"deaths": int(_accum["deaths"]),
		"death_causes": (_accum["death_causes"] as Dictionary).duplicate(true),
		"avg_body": avg_body,
		"avg_speed": avg_speed,
		"avg_metabolism": avg_metabolism,
		"richness": species_populations.size(),
		"evenness": _evenness(species_populations)
	}
	_accum = {"births": 0, "deaths": 0, "death_causes": {}}
	if _samples.size() < capacity:
		_samples.append(snapshot)
	else:
		_samples[_head] = snapshot
		_head = (_head + 1) % capacity

func _evenness(populations: Dictionary) -> float:
	var values: Array[int] = []
	var total: int = 0
	for key in populations:
		var value: int = maxi(0, int(populations[key]))
		values.append(value)
		total += value
	if values.is_empty() or total == 0:
		return 0.0
	var sum_sq: int = 0
	for value in values:
		sum_sq += value * value
	var simpson: float = 1.0 - float(sum_sq) / float(total * total)
	var max_simpson: float = 1.0 - 1.0 / float(values.size())
	if max_simpson <= 0.0:
		return 0.0
	return clampf(simpson / max_simpson, 0.0, 1.0)

func get_series() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	if _samples.size() < capacity:
		for sample in _samples:
			ordered.append((sample as Dictionary).duplicate(true))
		return ordered
	for i in range(capacity):
		var index: int = (_head + i) % capacity
		ordered.append((_samples[index] as Dictionary).duplicate(true))
	return ordered

## 产物 1：多物种折线图（species_id -> [{tick, count}]，全来自采样）。
func population_series() -> Dictionary:
	var series: Dictionary = {}
	for sample in get_series():
		var tick: int = int(sample.get("tick", 0))
		var populations: Dictionary = sample.get("populations", {})
		for species_id in populations:
			if not series.has(species_id):
				series[species_id] = []
			(series[species_id] as Array).append({"tick": tick, "count": int(populations[species_id])})
	return series

## 产物 2：物种与死因面板（聚合采样，全来自数据）。
func species_death_panel() -> Dictionary:
	var cause_totals: Dictionary = {}
	var peak_by_species: Dictionary = {}
	var births: int = 0
	var deaths: int = 0
	for sample in get_series():
		births += int(sample.get("births", 0))
		deaths += int(sample.get("deaths", 0))
		var causes: Dictionary = sample.get("death_causes", {})
		for cause in causes:
			cause_totals[cause] = int(cause_totals.get(cause, 0)) + int(causes[cause])
		var populations: Dictionary = sample.get("populations", {})
		for species_id in populations:
			peak_by_species[species_id] = maxi(int(peak_by_species.get(species_id, 0)), int(populations[species_id]))
	return {
		"births": births,
		"deaths": deaths,
		"death_causes": cause_totals,
		"peak_population_by_species": peak_by_species
	}

## 产物 3：记录到的事实。模板规则生成，字符串中的数值/名称全部来自数据与档案。
func generate_facts(archives: Dictionary) -> Array[String]:
	var facts: Array[String] = []
	var panel: Dictionary = species_death_panel()
	var causes: Dictionary = panel.get("death_causes", {})
	var deaths: int = int(panel.get("deaths", 0))
	if deaths > 0 and not causes.is_empty():
		var top_cause: String = ""
		var top_count: int = 0
		for cause in causes:
			if int(causes[cause]) > top_count:
				top_count = int(causes[cause])
				top_cause = cause
		var ratio: float = float(top_count) / float(deaths) * 100.0
		facts.append("最主要死因是%s，占 %.1f%%（%d/%d）" % [DEATH_LABELS.get(int(top_cause), "未知"), ratio, top_count, deaths])
	for species_id in archives:
		var archive: Dictionary = archives[species_id]
		if archive.is_empty():
			continue
		var peak: int = int(archive.get("peak_population", 0))
		var cause: int = int(archive.get("main_death_cause", -1))
		var lifespan: int = int(archive.get("lifespan_ticks", 0))
		facts.append("物种 %d 峰值种群 %d，主要死因%s，存续 %d tick" % [int(species_id), peak, DEATH_LABELS.get(cause, "未知"), lifespan])
	var series: Array[Dictionary] = get_series()
	if not series.is_empty():
		var last: Dictionary = series[series.size() - 1]
		facts.append("末次采样 tick %d：物种丰富度 %d，均匀度 %.2f" % [int(last.get("tick", 0)), int(last.get("richness", 0)), float(last.get("evenness", 0.0))])
	return facts

func export_report(archives: Dictionary) -> Dictionary:
	return {
		"sample_count": sample_count(),
		"capacity": capacity,
		"population_series": population_series(),
		"species_death_panel": species_death_panel(),
		"facts": generate_facts(archives),
		"archives": archives.duplicate(true)
	}
