#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/packed_float32_array.hpp"
#include "godot_cpp/variant/packed_float64_array.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"

using namespace godot;

class CellMetabolism : public RefCounted {
	GDCLASS(CellMetabolism, RefCounted)

protected:
	static void _bind_methods();

public:
	CellMetabolism() = default;
	~CellMetabolism() override = default;

	// Bit-exact batch port of OrganismManager._apply_environment_metabolism_ranges
	// computation phase. Returns double arrays so GDScript can continue the original
	// arithmetic without an extra float32 rounding step:
	//   "food_gains"      : PackedFloat64Array, count
	//   "movement_costs"  : PackedFloat64Array, count
	//   "toxic_flags"     : PackedByteArray, count
	Dictionary compute_environment_batch(
			const PackedByteArray &alive,
			const PackedByteArray &types,
			const PackedInt32Array &org_ids,
			const PackedFloat32Array &fields_flat,
			const PackedInt32Array &sample_indices,
			const PackedByteArray &respiration_values,
			const PackedFloat32Array &priority_values,
			const PackedFloat32Array &intents,
			double dt,
			double heterotrophic_intake_rate,
			double photosynthetic_intake_rate,
			double chemotrophic_intake_rate,
			double movement_energy_cost,
			double facultative_aerobic_efficiency);
};
