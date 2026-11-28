#include "cell_metabolism.h"

#include "godot_cpp/core/class_db.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {

// RespirationRules.gd constants. Kept as local copies because a GDExtension
// cannot preload a GDScript resource without breaking parsing order.
constexpr int RESPIRATION_ANAEROBIC = 0;
constexpr int RESPIRATION_AEROBIC = 1;
constexpr int RESPIRATION_FACULTATIVE = 2;
constexpr double OXYGEN_TOXICITY_THRESHOLD = 0.08;
constexpr double ANAEROBIC_EFFICIENCY = 1.0;
constexpr double AEROBIC_EFFICIENCY = 3.0;
constexpr double HYPOXIC_AEROBIC_EFFICIENCY = 0.5;

// OrganismManager.gd cell type ids.
constexpr int CELL_TYPE_ZYGOTE = 0;
constexpr int CELL_TYPE_PHOTOCYTE = 4;
constexpr int CELL_TYPE_NITROCYTE = 10;

inline double clamp01(double value) {
	if (value < 0.0) return 0.0;
	if (value > 1.0) return 1.0;
	return value;
}

inline double max0(double value) {
	return value > 0.0 ? value : 0.0;
}

inline double clamp_range(double value, double low, double high) {
	if (value < low) return low;
	if (value > high) return high;
	return value;
}

inline int clamp_int(int value, int low, int high) {
	if (value < low) return low;
	if (value > high) return high;
	return value;
}

constexpr int MAX_GENOME_MODES = 40;

int resolve_mode_slot(const PackedByteArray &mode_ids,
		const PackedInt32Array &org_mode_counts, int cell_index, int org_id) {
	const int mode_count = (org_id >= 0 && org_id < org_mode_counts.size())
			? std::max(0, static_cast<int>(org_mode_counts[org_id])) : 0;
	if (mode_count <= 0) return -1;
	const int raw_mode = (cell_index >= 0 && cell_index < mode_ids.size())
			? static_cast<int>(mode_ids[cell_index]) : 0;
	return clamp_int(raw_mode, 0, mode_count - 1);
}

struct RespirationResult {
	double efficiency = 0.0;
	bool valid = false;
	bool toxic = false;
};

// Exact port of RespirationRules.evaluate(). Only efficiency and toxic are
// consumed by the caller; budget_cost does not affect simulation state here.
RespirationResult evaluate_respiration(int respiration, double oxygen,
		double facultative_aerobic_efficiency) {
	RespirationResult result;
	if (respiration < RESPIRATION_ANAEROBIC || respiration > RESPIRATION_FACULTATIVE ||
			oxygen < 0.0 || oxygen > 1.0) {
		return result;
	}
	if (facultative_aerobic_efficiency <= ANAEROBIC_EFFICIENCY ||
			facultative_aerobic_efficiency >= AEROBIC_EFFICIENCY) {
		return result;
	}
	const bool oxygenated = oxygen > OXYGEN_TOXICITY_THRESHOLD;
	result.valid = true;
	result.efficiency = ANAEROBIC_EFFICIENCY;
	switch (respiration) {
		case RESPIRATION_ANAEROBIC:
			result.toxic = oxygenated;
			break;
		case RESPIRATION_AEROBIC:
			result.efficiency = oxygenated ? AEROBIC_EFFICIENCY : HYPOXIC_AEROBIC_EFFICIENCY;
			break;
		case RESPIRATION_FACULTATIVE:
			result.efficiency = oxygenated ? facultative_aerobic_efficiency : ANAEROBIC_EFFICIENCY;
			break;
		default:
			break;
	}
	return result;
}

}  // namespace

Dictionary CellMetabolism::compute_environment_batch(
		const PackedByteArray &alive, const PackedByteArray &types,
		const PackedInt32Array &org_ids, const PackedFloat32Array &fields_flat,
		const PackedInt32Array &sample_indices, const PackedByteArray &respiration_values,
		const PackedFloat32Array &priority_values, const PackedFloat32Array &intents,
		double dt, double heterotrophic_intake_rate, double photosynthetic_intake_rate,
		double chemotrophic_intake_rate, double movement_energy_cost,
		double facultative_aerobic_efficiency) {
	const int count = alive.size();
	PackedFloat64Array food_gains;
	PackedFloat64Array movement_costs;
	PackedByteArray toxic_flags;
	PackedInt32Array consume_cells;
	food_gains.resize(count);
	movement_costs.resize(count);
	toxic_flags.resize(count);

	for (int cell_index = 0; cell_index < count; ++cell_index) {
		food_gains.set(cell_index, 0.0);
		movement_costs.set(cell_index, 0.0);
		toxic_flags.set(cell_index, 0);
		if (alive[cell_index] == 0) continue;

		const int org_id = org_ids[cell_index];
		const int sample_index = (cell_index < sample_indices.size())
				? static_cast<int>(sample_indices[cell_index]) : -1;
		const int field_offset = sample_index * 5;
		const bool has_fields = sample_index >= 0 && field_offset + 5 <= fields_flat.size();
		const double oxygen = has_fields
				? clamp01(static_cast<double>(fields_flat[field_offset + 2])) : 0.0;
		const int respiration = (org_id >= 0 && org_id < respiration_values.size())
				? static_cast<int>(respiration_values[org_id]) : RESPIRATION_ANAEROBIC;
		const RespirationResult resp = evaluate_respiration(respiration, oxygen,
				facultative_aerobic_efficiency);
		const double priority = (org_id >= 0 && org_id < priority_values.size())
				? static_cast<double>(priority_values[org_id]) : 0.5;
		const double feeding_factor = 0.25 + 1.5 * priority;
		const double light_factor = 1.75 - 1.5 * priority;

		const int cell_type = static_cast<int>(types[cell_index]);
		double food_gain = 0.0;
		if (has_fields && cell_type == CELL_TYPE_ZYGOTE) {
			food_gain = max0(static_cast<double>(fields_flat[field_offset]))
					* heterotrophic_intake_rate * feeding_factor * resp.efficiency * dt;
		} else if (has_fields && cell_type == CELL_TYPE_PHOTOCYTE) {
			food_gain = max0(static_cast<double>(fields_flat[field_offset + 3]))
					* photosynthetic_intake_rate * light_factor * dt;
		} else if (has_fields && cell_type == CELL_TYPE_NITROCYTE) {
			food_gain = max0(static_cast<double>(fields_flat[field_offset + 4]))
					* chemotrophic_intake_rate * feeding_factor * dt;
		}
		food_gains.set(cell_index, food_gain);
		if (food_gain > 0.0
				&& (cell_type == CELL_TYPE_ZYGOTE || cell_type == CELL_TYPE_NITROCYTE)) {
			consume_cells.push_back(cell_index);
		}

		const int intent_offset = cell_index * 6;
		const double movement = (intent_offset < intents.size())
				? std::abs(static_cast<double>(intents[intent_offset])) : 0.0;
		movement_costs.set(cell_index, movement_energy_cost * movement * movement * dt);
		if (resp.toxic) toxic_flags.set(cell_index, 1);
	}

	Dictionary result;
	result["food_gains"] = food_gains;
	result["movement_costs"] = movement_costs;
	result["toxic_flags"] = toxic_flags;
	// v0.49.0：需要真正调用 consume() 的细胞（升序）。原 GDScript 逐细胞判断
	// `food_gain > 0 && (type == ZYGOTE || type == NITROCYTE)`；下沉后只需遍历这张
	// 稀疏表，M1 全 PHOTOCYTE 时为空，省掉每 tick 一次全细胞类型扫描。
	result["consume_cells"] = consume_cells;
	return result;
}

// v0.49.0: metab_env 副作用循环下沉。原来是每细胞 4 次 PackedArray 元素写入
// （energies/flow_production/flow_self_cost/health）加一次账本字典分组，1142 细胞
// 实测约 570 µs；账本分组里 `(dict[key] as PackedFloat64Array).append()` 还会因为
// COW 变成 O(n²)。C++ 侧用裸指针 + 定长桶一次走完。
Dictionary CellMetabolism::apply_environment_outcome(
		const PackedFloat32Array &energies_in, const PackedFloat64Array &food_gains,
		const PackedInt32Array &consume_cells, const PackedFloat64Array &consume_amounts,
		const PackedByteArray &alive, const PackedByteArray &types,
		const PackedInt32Array &org_ids, const PackedFloat64Array &movement_costs,
		const PackedByteArray &toxic_flags, const PackedFloat64Array &flow_production_in,
		const PackedFloat64Array &flow_self_cost_in, const PackedFloat32Array &health_in,
		double toxicity_damage) {
	const int64_t count = energies_in.size();
	PackedFloat32Array energies = energies_in;
	PackedFloat32Array health = health_in;
	PackedFloat64Array flow_production = flow_production_in;
	PackedFloat64Array flow_self_cost = flow_self_cost_in;
	if (count <= 0) {
		Dictionary empty_result;
		empty_result["energies"] = energies;
		empty_result["health"] = health;
		empty_result["flow_production"] = flow_production;
		empty_result["flow_self_cost"] = flow_self_cost;
		empty_result["ledger_groups"] = Dictionary();
		return empty_result;
	}
	float *energy_ptr = energies.ptrw();
	float *health_ptr = health.ptrw();
	double *production_ptr = flow_production.ptrw();
	double *self_cost_ptr = flow_self_cost.ptrw();
	const uint8_t *alive_ptr = alive.ptr();
	const uint8_t *types_ptr = types.ptr();
	const int32_t *org_ptr = org_ids.ptr();
	const double *gain_ptr = food_gains.ptr();
	const double *cost_ptr = movement_costs.ptr();
	const uint8_t *toxic_ptr = toxic_flags.ptr();
	const int64_t gain_count = food_gains.size();
	const int64_t cost_count = movement_costs.size();
	const int64_t org_count = org_ids.size();
	const int64_t health_count = health.size();
	const int64_t flow_count = std::min(flow_production.size(), flow_self_cost.size());
	const int64_t override_count = std::min(consume_cells.size(), consume_amounts.size());
	const int32_t *override_cell_ptr = consume_cells.ptr();
	const double *override_amount_ptr = consume_amounts.ptr();
	const int64_t type_count = types.size();
	int64_t override_cursor = 0;

	// 账本分组：桶按 cell_type 直接下标，插入序按首次出现记录，与 GDScript
	// Dictionary 的插入序一致（_flush_ledger_groups 依赖这个顺序）。
	std::vector<PackedFloat64Array> buckets(256);
	std::vector<int> bucket_order;
	std::vector<char> bucket_seen(256, 0);

	for (int64_t i = 0; i < count; ++i) {
		if (alive_ptr[i] == 0) {
			continue;
		}
		double consumed = (i < gain_count && gain_ptr[i] > 0.0) ? gain_ptr[i] : 0.0;
		if (override_cursor < override_count && override_cell_ptr[override_cursor] == i) {
			consumed = override_amount_ptr[override_cursor];
			++override_cursor;
		}
		if (consumed != 0.0) {
			energy_ptr[i] = static_cast<float>(static_cast<double>(energy_ptr[i]) + consumed);
			if (i < flow_count) {
				production_ptr[i] += consumed;
			}
		}
		if (i < cost_count) {
			const double cost = cost_ptr[i];
			energy_ptr[i] = static_cast<float>(
					std::max(0.0, static_cast<double>(energy_ptr[i]) - cost));
			if (cost != 0.0 && i < flow_count) {
				self_cost_ptr[i] += cost;
			}
		}
		if (i < org_count && i < health_count && toxic_ptr[i] != 0) {
			const int org_id = org_ptr[i];
			if (org_id >= 0 && org_id < health_count) {
				health_ptr[org_id] = static_cast<float>(std::max(0.0,
						static_cast<double>(health_ptr[org_id]) - toxicity_damage));
			}
		}
		if (consumed > 0.0 && i < type_count) {
			const int type_key = static_cast<int>(types_ptr[i]);
			if (type_key >= 0 && type_key < 256) {
				if (bucket_seen[type_key] == 0) {
					bucket_seen[type_key] = 1;
					bucket_order.push_back(type_key);
				}
				buckets[type_key].push_back(consumed);
			}
		}
	}

	Dictionary ledger_groups;
	for (const int type_key : bucket_order) {
		const PackedFloat64Array &source = buckets[type_key];
		const int64_t source_count = source.size();
		PackedFloat64Array values;
		values.resize(source_count);
		double *values_ptr = values.ptrw();
		for (int64_t k = 0; k < source_count; ++k) {
			values_ptr[k] = source[k];
		}
		ledger_groups[type_key] = values;
	}

	Dictionary result;
	result["energies"] = energies;
	result["health"] = health;
	result["flow_production"] = flow_production;
	result["flow_self_cost"] = flow_self_cost;
	result["ledger_groups"] = ledger_groups;
	return result;
}

PackedFloat32Array CellMetabolism::compute_transfer_rates(
		const PackedByteArray &alive, const PackedInt32Array &org_ids,
		const PackedByteArray &mode_ids, const PackedByteArray &org_gene_mode,
		const PackedByteArray &org_has_modes, const PackedInt32Array &org_mode_counts,
		const PackedFloat32Array &org_default_rates,
		const PackedFloat32Array &org_mode_rates) {
	const int count = alive.size();
	PackedFloat32Array rates;
	rates.resize(count);
	rates.fill(0.0f);
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		if (alive[cell_index] == 0) continue;
		const int org_id = org_ids[cell_index];
		if (org_id < 0 || org_id >= org_default_rates.size()) {
			continue;
		}
		const bool gene_mode = org_id < org_gene_mode.size() && org_gene_mode[org_id] != 0;
		if (!gene_mode) {
			if (org_id < org_default_rates.size()) {
				rates.set(cell_index, org_default_rates[org_id]);
			}
			continue;
		}
		const bool has_modes = org_id < org_has_modes.size() && org_has_modes[org_id] != 0;
		if (!has_modes) continue;
		const int mode_slot = resolve_mode_slot(mode_ids, org_mode_counts, cell_index, org_id);
		if (mode_slot < 0) continue;
		const int flat = org_id * MAX_GENOME_MODES + mode_slot;
		if (flat >= 0 && flat < org_mode_rates.size()) {
			rates.set(cell_index, static_cast<float>(clamp01(
					static_cast<double>(org_mode_rates[flat]))));
		}
	}
	return rates;
}

Dictionary CellMetabolism::compute_energy_radius_scales(
		const PackedByteArray &alive, const PackedFloat32Array &energies,
		const PackedInt32Array &org_ids, const PackedByteArray &mode_ids,
		const PackedFloat32Array &current_energy_scales,
		const PackedFloat32Array &baselines,
		const PackedByteArray &org_gene_mode, const PackedByteArray &org_has_modes,
		const PackedInt32Array &org_mode_counts,
		const PackedFloat32Array &org_default_division_mass,
		const PackedFloat32Array &org_mode_division_mass,
		double dt, double relax_rate, double min_scale, double max_scale) {
	const int count = alive.size();
	PackedFloat32Array energy_scales;
	PackedFloat32Array radius_scales;
	energy_scales.resize(count);
	radius_scales.resize(count);
	for (int i = 0; i < count; ++i) {
		energy_scales.set(i, i < current_energy_scales.size()
				? current_energy_scales[i] : 1.0f);
		radius_scales.set(i, i < baselines.size() ? baselines[i] : 1.0f);
	}
	const double step = clamp_range(relax_rate * dt, 0.0, 1.0);
	double min_power = max0(min_scale);
	min_power *= min_power;
	double max_power = std::max(min_power, max0(max_scale));
	max_power *= max_power;

	for (int cell_index = 0; cell_index < count; ++cell_index) {
		if (alive[cell_index] == 0) continue;
		const int org_id = org_ids[cell_index];
		if (org_id < 0 || org_id >= org_gene_mode.size()) continue;
		if (org_gene_mode[org_id] == 0) continue;
		double reference = 0.0;
		if (org_id < org_default_division_mass.size()) {
			reference = static_cast<double>(org_default_division_mass[org_id]);
		}
		reference = std::max(0.05, reference);
		const bool has_modes = org_id < org_has_modes.size() && org_has_modes[org_id] != 0;
		if (has_modes && cell_index < mode_ids.size()) {
			const int mode_slot = resolve_mode_slot(mode_ids, org_mode_counts, cell_index, org_id);
			const int flat = org_id * MAX_GENOME_MODES + mode_slot;
			if (mode_slot >= 0 && flat >= 0 && flat < org_mode_division_mass.size()) {
				reference = std::max(0.05,
						static_cast<double>(org_mode_division_mass[flat]));
			}
		}
		const double current = cell_index < current_energy_scales.size()
				? static_cast<double>(current_energy_scales[cell_index]) : 1.0;
		const double current_power = current * current;
		const double energy = cell_index < energies.size()
				? static_cast<double>(energies[cell_index]) : 0.0;
		const double target_power = clamp_range(max0(energy) / reference,
				min_power, max_power);
		const double next_scale = std::sqrt(std::max(0.0,
				current_power + (target_power - current_power) * step));
		const double stored_energy_scale = static_cast<double>(static_cast<float>(
				clamp_range(next_scale, 0.1, 1.0)));
		energy_scales.set(cell_index, static_cast<float>(stored_energy_scale));
		const double baseline = cell_index < baselines.size()
				? static_cast<double>(baselines[cell_index]) : 1.0;
		radius_scales.set(cell_index, static_cast<float>(clamp_range(
				baseline * stored_energy_scale, 0.05, 2.0)));
	}
	Dictionary result;
	result["energy_scales"] = energy_scales;
	result["radius_scales"] = radius_scales;
	return result;
}

Dictionary CellMetabolism::select_lifecycle_candidates(
		const PackedByteArray &alive, const PackedFloat32Array &energies,
		const PackedInt32Array &org_ids, const PackedByteArray &org_alive,
		const PackedByteArray &org_state, const PackedByteArray &mode_ids,
		const PackedInt32Array &cell_division_tick,
		const PackedInt32Array &cell_telomere,
		const PackedByteArray &cell_link_count,
		const PackedByteArray &org_genome_present,
		const PackedByteArray &org_gene_mode,
		const PackedByteArray &org_has_modes,
		const PackedInt32Array &org_max_cells,
		const PackedInt32Array &org_cell_counts,
		const PackedFloat32Array &org_default_threshold,
		const PackedInt32Array &org_mode_counts,
		const PackedFloat32Array &org_mode_thresholds,
		const PackedInt32Array &org_mode_link_limits,
		int sim_tick, int cooldown, int mature_state) {
	PackedInt32Array candidates;
	PackedInt32Array grace;
	const int count = alive.size();
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		if (alive[cell_index] == 0) continue;
		const int org_id = org_ids[cell_index];
		if (org_id < 0 || org_id >= org_alive.size() || org_alive[org_id] == 0 ||
				org_id >= org_state.size() || org_state[org_id] != mature_state) {
			continue;
		}
		if (org_id >= org_genome_present.size() || org_genome_present[org_id] == 0) {
			continue;
		}
		const bool gene_mode = org_id < org_gene_mode.size() && org_gene_mode[org_id] != 0;
		const bool has_modes = gene_mode && org_id < org_has_modes.size()
				&& org_has_modes[org_id] != 0;
		double threshold = org_id < org_default_threshold.size()
				? static_cast<double>(org_default_threshold[org_id]) : 0.0;
		const int max_cells = org_id < org_max_cells.size()
				? static_cast<int>(org_max_cells[org_id]) : -1;
		if (has_modes) {
			const int mode_slot = resolve_mode_slot(mode_ids, org_mode_counts, cell_index, org_id);
			if (mode_slot < 0) continue;
			const int flat = org_id * MAX_GENOME_MODES + mode_slot;
			if (flat >= 0 && flat < org_mode_thresholds.size()) {
				threshold = static_cast<double>(org_mode_thresholds[flat]);
			}
			if (flat >= 0 && flat < org_mode_link_limits.size()) {
				const int limit = clamp_int(static_cast<int>(org_mode_link_limits[flat]), -1, 16);
				if (limit >= 0 && cell_index < cell_link_count.size()
						&& static_cast<int>(cell_link_count[cell_index]) >= limit) {
					continue;
				}
			}
		} else if (!gene_mode) {
			// Non gene-mode genomes keep the legacy autonomous energy threshold
			// supplied in org_default_threshold by GDScript.
		}
		const int telomere = cell_index < cell_telomere.size()
				? static_cast<int>(cell_telomere[cell_index]) : -1;
		if (telomere == 0) continue;
		const double energy = cell_index < energies.size()
				? static_cast<double>(energies[cell_index]) : 0.0;
		const int extant = org_id < org_cell_counts.size()
				? static_cast<int>(org_cell_counts[org_id]) : 0;
		if (energy < threshold || (max_cells >= 0 && extant >= max_cells)) {
			continue;
		}
		const int division_tick = cell_index < cell_division_tick.size()
				? static_cast<int>(cell_division_tick[cell_index]) : -2;
		if (division_tick == -2) {
			grace.append(cell_index);
			continue;
		}
		if (division_tick >= 0 && sim_tick - division_tick < cooldown) {
			continue;
		}
		candidates.append(cell_index);
	}
	Dictionary result;
	result["candidates"] = candidates;
	result["grace"] = grace;
	return result;
}

void CellMetabolism::_bind_methods() {
	ClassDB::bind_method(D_METHOD("compute_environment_batch", "alive", "types", "org_ids",
			"fields_flat", "sample_indices", "respiration_values", "priority_values", "intents",
			"dt", "heterotrophic_intake_rate", "photosynthetic_intake_rate",
			"chemotrophic_intake_rate", "movement_energy_cost", "facultative_aerobic_efficiency"),
			&CellMetabolism::compute_environment_batch);
	ClassDB::bind_method(D_METHOD("apply_environment_outcome", "energies", "food_gains",
			"consume_cells", "consume_amounts", "alive", "types", "org_ids",
			"movement_costs", "toxic_flags", "flow_production", "flow_self_cost",
			"health", "toxicity_damage"),
			&CellMetabolism::apply_environment_outcome);
	ClassDB::bind_method(D_METHOD("compute_transfer_rates", "alive", "org_ids", "mode_ids",
			"org_gene_mode", "org_has_modes", "org_mode_counts", "org_default_rates",
			"org_mode_rates"), &CellMetabolism::compute_transfer_rates);
	ClassDB::bind_method(D_METHOD("compute_energy_radius_scales", "alive", "energies",
			"org_ids", "mode_ids", "current_energy_scales", "baselines",
			"org_gene_mode", "org_has_modes", "org_mode_counts",
			"org_default_division_mass", "org_mode_division_mass",
			"dt", "relax_rate", "min_scale", "max_scale"),
			&CellMetabolism::compute_energy_radius_scales);
	ClassDB::bind_method(D_METHOD("select_lifecycle_candidates", "alive", "energies",
			"org_ids", "org_alive", "org_state", "mode_ids", "cell_division_tick",
			"cell_telomere", "cell_link_count", "org_genome_present", "org_gene_mode",
			"org_has_modes", "org_max_cells", "org_cell_counts", "org_default_threshold",
			"org_mode_counts", "org_mode_thresholds", "org_mode_link_limits",
			"sim_tick", "cooldown", "mature_state"),
			&CellMetabolism::select_lifecycle_candidates);
}
