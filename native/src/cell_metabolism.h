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

	// v0.34.0: pure computation behind OrganismManager._build_transfer_rates.
	// Per-organism caches are rebuilt once per tick by GDScript; C++ expands them
	// per cell without calling GDScript Genome.get_mode() for every cell.
	PackedFloat32Array compute_transfer_rates(
			const PackedByteArray &alive,
			const PackedInt32Array &org_ids,
			const PackedByteArray &mode_ids,
			const PackedByteArray &org_gene_mode,
			const PackedByteArray &org_has_modes,
			const PackedInt32Array &org_mode_counts,
			const PackedFloat32Array &org_default_rates,
			const PackedFloat32Array &org_mode_rates);

	// v0.34.0: pure computation behind _apply_energy_radius_relaxation.
	// Returns final values already rounded exactly like CellArray.set_energy_radius_scale().
	Dictionary compute_energy_radius_scales(
			const PackedByteArray &alive,
			const PackedFloat32Array &energies,
			const PackedInt32Array &org_ids,
			const PackedByteArray &mode_ids,
			const PackedFloat32Array &current_energy_scales,
			const PackedFloat32Array &baselines,
			const PackedByteArray &org_gene_mode,
			const PackedByteArray &org_has_modes,
			const PackedInt32Array &org_mode_counts,
			const PackedFloat32Array &org_default_division_mass,
			const PackedFloat32Array &org_mode_division_mass,
			double dt,
			double relax_rate,
			double min_scale,
			double max_scale);

	// v0.34.0: pure candidate scan behind _apply_autonomous_lifecycle.
	// Side effects (grace division_tick writes and actual division) stay in GDScript
	// and keep the original order. "candidates" and "grace" are ascending cell indices.
	Dictionary select_lifecycle_candidates(
			const PackedByteArray &alive,
			const PackedFloat32Array &energies,
			const PackedInt32Array &org_ids,
			const PackedByteArray &org_alive,
			const PackedByteArray &org_state,
			const PackedByteArray &mode_ids,
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
			int sim_tick,
			int cooldown,
			int mature_state);
};
