extends SceneTree
## v0.34.0 direct parity gates for the three metabolism hotspot offloads:
## compute_transfer_rates / compute_energy_radius_scales / select_lifecycle_candidates.
## Each C++ result is compared with an explicit GDScript reference implementation.

const N: int = 600
const ORG_COUNT: int = 80
const MODE_STRIDE: int = 40
const MATURE_STATE: int = 2

var failures: int = 0
var checked: int = 0

func _initialize() -> void:
	if not ClassDB.class_exists("CellMetabolism"):
		print("METAB_HOTSPOTS_PARITY: SKIP (CellMetabolism not registered)")
		quit(0)
		return
	var cpp: RefCounted = ClassDB.instantiate("CellMetabolism") as RefCounted
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261120

	var alive: PackedByteArray = PackedByteArray()
	var energies: PackedFloat32Array = PackedFloat32Array()
	var org_ids: PackedInt32Array = PackedInt32Array()
	var mode_ids: PackedByteArray = PackedByteArray()
	var current_scales: PackedFloat32Array = PackedFloat32Array()
	var baselines: PackedFloat32Array = PackedFloat32Array()
	var division_ticks: PackedInt32Array = PackedInt32Array()
	var telomeres: PackedInt32Array = PackedInt32Array()
	var link_counts: PackedByteArray = PackedByteArray()
	alive.resize(N); energies.resize(N); org_ids.resize(N); mode_ids.resize(N)
	current_scales.resize(N); baselines.resize(N); division_ticks.resize(N)
	telomeres.resize(N); link_counts.resize(N)

	var org_gene: PackedByteArray = PackedByteArray()
	var org_has_modes: PackedByteArray = PackedByteArray()
	var org_present: PackedByteArray = PackedByteArray()
	var org_mode_counts: PackedInt32Array = PackedInt32Array()
	var org_max_cells: PackedInt32Array = PackedInt32Array()
	var org_cell_counts: PackedInt32Array = PackedInt32Array()
	var org_default_threshold: PackedFloat32Array = PackedFloat32Array()
	var org_default_rate: PackedFloat32Array = PackedFloat32Array()
	var org_default_division_mass: PackedFloat32Array = PackedFloat32Array()
	org_gene.resize(ORG_COUNT); org_has_modes.resize(ORG_COUNT); org_present.resize(ORG_COUNT)
	org_mode_counts.resize(ORG_COUNT); org_max_cells.resize(ORG_COUNT)
	org_cell_counts.resize(ORG_COUNT); org_default_threshold.resize(ORG_COUNT)
	org_default_rate.resize(ORG_COUNT); org_default_division_mass.resize(ORG_COUNT)
	var flat_count: int = ORG_COUNT * MODE_STRIDE
	var org_mode_rates: PackedFloat32Array = PackedFloat32Array()
	var org_mode_thresholds: PackedFloat32Array = PackedFloat32Array()
	var org_mode_division_mass: PackedFloat32Array = PackedFloat32Array()
	var org_mode_link_limits: PackedInt32Array = PackedInt32Array()
	org_mode_rates.resize(flat_count); org_mode_thresholds.resize(flat_count)
	org_mode_division_mass.resize(flat_count); org_mode_link_limits.resize(flat_count)
	org_mode_rates.fill(0.0); org_mode_thresholds.fill(0.0)
	org_mode_division_mass.fill(0.05); org_mode_link_limits.fill(-1)

	for i in range(N):
		alive[i] = 1 if rng.randi_range(0, 9) != 0 else 0
		energies[i] = rng.randf_range(0.0, 0.8)
		org_ids[i] = rng.randi_range(0, ORG_COUNT - 1)
		mode_ids[i] = rng.randi_range(0, 5)
		current_scales[i] = rng.randf_range(0.5, 1.0)
		baselines[i] = rng.randf_range(0.7, 1.3)
		division_ticks[i] = rng.randi_range(-2, 20)
		telomeres[i] = -1 if rng.randi_range(0, 4) != 0 else 0
		link_counts[i] = rng.randi_range(0, 6)
	for org_id in range(ORG_COUNT):
		org_gene[org_id] = 1 if rng.randi_range(0, 3) != 0 else 0
		org_has_modes[org_id] = 1 if org_gene[org_id] == 1 and rng.randi_range(0, 3) != 0 else 0
		org_present[org_id] = 1 if rng.randi_range(0, 9) != 0 else 0
		org_mode_counts[org_id] = 4 if org_has_modes[org_id] == 1 else 0
		org_max_cells[org_id] = -1 if rng.randi_range(0, 2) == 0 else rng.randi_range(100, 400)
		org_cell_counts[org_id] = rng.randi_range(10, 200)
		org_default_threshold[org_id] = rng.randf_range(0.05, 0.4)
		org_default_rate[org_id] = rng.randf_range(0.0, 1.0)
		org_default_division_mass[org_id] = rng.randf_range(0.05, 0.3)
		for mode_id in range(4):
			var flat: int = org_id * MODE_STRIDE + mode_id
			org_mode_rates[flat] = rng.randf_range(0.0, 1.0)
			org_mode_thresholds[flat] = rng.randf_range(0.05, 0.4)
			org_mode_division_mass[flat] = rng.randf_range(0.05, 0.3)
			org_mode_link_limits[flat] = -1 if rng.randi_range(0, 2) == 0 else rng.randi_range(1, 8)

	var org_alive: PackedByteArray = PackedByteArray()
	var org_state: PackedByteArray = PackedByteArray()
	org_alive.resize(ORG_COUNT); org_state.resize(ORG_COUNT)
	for org_id in range(ORG_COUNT):
		org_alive[org_id] = 1 if rng.randi_range(0, 9) != 0 else 0
		org_state[org_id] = MATURE_STATE if rng.randi_range(0, 2) != 0 else 0

	var dt: float = 1.0 / 60.0
	var cpp_rates: PackedFloat32Array = cpp.call("compute_transfer_rates", alive, org_ids,
		mode_ids, org_gene, org_has_modes, org_mode_counts, org_default_rate, org_mode_rates) as PackedFloat32Array
	var ref_rates: PackedFloat32Array = _reference_rates(alive, org_ids, mode_ids,
		org_gene, org_has_modes, org_mode_counts, org_default_rate, org_mode_rates)
	_compare_f32("rates", cpp_rates, ref_rates)

	var cpp_scales: Dictionary = cpp.call("compute_energy_radius_scales", alive, energies,
		org_ids, mode_ids, current_scales, baselines, org_gene, org_has_modes,
		org_mode_counts, org_default_division_mass, org_mode_division_mass,
		dt, 5.0, 0.5, 1.0) as Dictionary
	var ref_scales: Dictionary = _reference_scales(alive, energies, org_ids, mode_ids,
		current_scales, baselines, org_gene, org_has_modes, org_mode_counts,
		org_default_division_mass, org_mode_division_mass, dt, 5.0, 0.5, 1.0)
	_compare_f32("energy_scales", cpp_scales["energy_scales"], ref_scales["energy_scales"])
	_compare_f32("radius_scales", cpp_scales["radius_scales"], ref_scales["radius_scales"])

	var selection: Dictionary = cpp.call("select_lifecycle_candidates", alive, energies,
		org_ids, org_alive, org_state, mode_ids, division_ticks, telomeres, link_counts,
		org_present, org_gene, org_has_modes, org_max_cells, org_cell_counts,
		org_default_threshold, org_mode_counts, org_mode_thresholds, org_mode_link_limits,
		17, 5, MATURE_STATE) as Dictionary
	var ref_selection: Dictionary = _reference_lifecycle(alive, energies, org_ids,
		org_alive, org_state, mode_ids, division_ticks, telomeres, link_counts,
		org_present, org_gene, org_has_modes, org_max_cells, org_cell_counts,
		org_default_threshold, org_mode_counts, org_mode_thresholds, org_mode_link_limits,
		17, 5, MATURE_STATE)
	_compare_i32("lifecycle_candidates", selection["candidates"], ref_selection["candidates"])
	_compare_i32("lifecycle_grace", selection["grace"], ref_selection["grace"])

	print("METAB_HOTSPOTS_PARITY: checked=%d failures=%d" % [checked, failures])
	print("METAB_HOTSPOTS_PARITY: %s" % ["OK" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)

func _resolve_mode(mode_ids: PackedByteArray, mode_counts: PackedInt32Array, cell_index: int, org_id: int) -> int:
	var count: int = int(mode_counts[org_id])
	if count <= 0:
		return -1
	var raw: int = int(mode_ids[cell_index]) if cell_index < mode_ids.size() else 0
	return clampi(raw, 0, count - 1)

func _reference_rates(alive: PackedByteArray, org_ids: PackedInt32Array, mode_ids: PackedByteArray,
		org_gene: PackedByteArray, org_has_modes: PackedByteArray, mode_counts: PackedInt32Array,
		default_rates: PackedFloat32Array, mode_rates: PackedFloat32Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(alive.size()); result.fill(0.0)
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = int(org_ids[cell_index])
		if org_id < 0 or org_id >= default_rates.size():
			continue
		if org_gene[org_id] == 0:
			result[cell_index] = default_rates[org_id]
			continue
		if org_has_modes[org_id] == 0:
			continue
		var mode_slot: int = _resolve_mode(mode_ids, mode_counts, cell_index, org_id)
		if mode_slot < 0:
			continue
		result[cell_index] = clampf(float(mode_rates[org_id * MODE_STRIDE + mode_slot]), 0.0, 1.0)
	return result

func _reference_scales(alive: PackedByteArray, energies: PackedFloat32Array,
		org_ids: PackedInt32Array, mode_ids: PackedByteArray, current_scales: PackedFloat32Array,
		baselines: PackedFloat32Array, org_gene: PackedByteArray, org_has_modes: PackedByteArray,
		mode_counts: PackedInt32Array, default_mass: PackedFloat32Array,
		mode_mass: PackedFloat32Array, dt: float, relax_rate: float,
		min_scale: float, max_scale: float) -> Dictionary:
	var energy_scales: PackedFloat32Array = PackedFloat32Array()
	var radius_scales: PackedFloat32Array = PackedFloat32Array()
	energy_scales.resize(alive.size()); radius_scales.resize(alive.size())
	var step: float = clampf(relax_rate * dt, 0.0, 1.0)
	var min_power: float = maxf(0.0, min_scale)
	min_power *= min_power
	var max_power: float = maxf(min_power, max_scale)
	max_power *= max_power
	var round_buf: PackedFloat32Array = PackedFloat32Array()
	round_buf.resize(1)
	for cell_index in range(alive.size()):
		energy_scales[cell_index] = current_scales[cell_index]
		radius_scales[cell_index] = baselines[cell_index]
		if alive[cell_index] == 0:
			continue
		var org_id: int = int(org_ids[cell_index])
		if org_id < 0 or org_id >= org_gene.size() or org_gene[org_id] == 0:
			continue
		var reference: float = maxf(0.05, float(default_mass[org_id]))
		if org_has_modes[org_id] != 0 and cell_index < mode_ids.size():
			var mode_slot: int = _resolve_mode(mode_ids, mode_counts, cell_index, org_id)
			if mode_slot >= 0:
				reference = maxf(0.05, float(mode_mass[org_id * MODE_STRIDE + mode_slot]))
		var current: float = float(current_scales[cell_index])
		var current_power: float = current * current
		var target_power: float = clampf(maxf(0.0, float(energies[cell_index])) / reference, min_power, max_power)
		var next_scale: float = sqrt(maxf(0.0, current_power + (target_power - current_power) * step))
		round_buf[0] = clampf(next_scale, 0.1, 1.0)
		var stored_energy: float = float(round_buf[0])
		energy_scales[cell_index] = stored_energy
		round_buf[0] = clampf(float(baselines[cell_index]) * stored_energy, 0.05, 2.0)
		radius_scales[cell_index] = float(round_buf[0])
	return {"energy_scales": energy_scales, "radius_scales": radius_scales}

func _reference_lifecycle(alive: PackedByteArray, energies: PackedFloat32Array,
		org_ids: PackedInt32Array, org_alive: PackedByteArray, org_state: PackedByteArray,
		mode_ids: PackedByteArray, division_ticks: PackedInt32Array, telomeres: PackedInt32Array,
		link_counts: PackedByteArray, org_present: PackedByteArray, org_gene: PackedByteArray,
		org_has_modes: PackedByteArray, org_max_cells: PackedInt32Array,
		org_cell_counts: PackedInt32Array, default_threshold: PackedFloat32Array,
		mode_counts: PackedInt32Array, mode_thresholds: PackedFloat32Array,
		mode_link_limits: PackedInt32Array, sim_tick: int, cooldown: int,
		mature_state: int) -> Dictionary:
	var candidates: PackedInt32Array = PackedInt32Array()
	var grace: PackedInt32Array = PackedInt32Array()
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = int(org_ids[cell_index])
		if org_id < 0 or org_id >= org_alive.size() or org_alive[org_id] == 0 \
			or org_state[org_id] != mature_state:
			continue
		if org_id >= org_present.size() or org_present[org_id] == 0:
			continue
		var gene_mode: bool = org_gene[org_id] != 0
		var has_modes: bool = gene_mode and org_has_modes[org_id] != 0
		var threshold: float = float(default_threshold[org_id])
		var max_cells: int = int(org_max_cells[org_id])
		if has_modes:
			var mode_slot: int = _resolve_mode(mode_ids, mode_counts, cell_index, org_id)
			if mode_slot < 0:
				continue
			var flat: int = org_id * MODE_STRIDE + mode_slot
			threshold = float(mode_thresholds[flat])
			var limit: int = clampi(int(mode_link_limits[flat]), -1, 16)
			if limit >= 0 and cell_index < link_counts.size() and int(link_counts[cell_index]) >= limit:
				continue
		if cell_index < telomeres.size() and int(telomeres[cell_index]) == 0:
			continue
		var extant: int = int(org_cell_counts[org_id])
		if float(energies[cell_index]) < threshold or (max_cells >= 0 and extant >= max_cells):
			continue
		var division_tick: int = int(division_ticks[cell_index])
		if division_tick == -2:
			grace.append(cell_index)
			continue
		if division_tick >= 0 and sim_tick - division_tick < cooldown:
			continue
		candidates.append(cell_index)
	return {"candidates": candidates, "grace": grace}

func _compare_f32(name: String, cpp: PackedFloat32Array, reference: PackedFloat32Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("METAB_HOTSPOTS_PARITY: FAIL %s size %d/%d" % [name, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("METAB_HOTSPOTS_PARITY: FAIL %s[%d] cpp=%.9f ref=%.9f" % [name, i, cpp[i], reference[i]])

func _compare_i32(name: String, cpp: PackedInt32Array, reference: PackedInt32Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("METAB_HOTSPOTS_PARITY: FAIL %s size %d/%d" % [name, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("METAB_HOTSPOTS_PARITY: FAIL %s[%d] cpp=%d ref=%d" % [name, i, cpp[i], reference[i]])
