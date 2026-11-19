#include "cell_metabolism.h"

#include "godot_cpp/core/class_db.hpp"

#include <algorithm>

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
	return result;
}

void CellMetabolism::_bind_methods() {
	ClassDB::bind_method(D_METHOD("compute_environment_batch", "alive", "types", "org_ids",
			"fields_flat", "sample_indices", "respiration_values", "priority_values", "intents",
			"dt", "heterotrophic_intake_rate", "photosynthetic_intake_rate",
			"chemotrophic_intake_rate", "movement_energy_cost", "facultative_aerobic_efficiency"),
			&CellMetabolism::compute_environment_batch);
}
