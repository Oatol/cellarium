#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_float32_array.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"

using namespace godot;

class CellSpatial : public RefCounted {
	GDCLASS(CellSpatial, RefCounted)

protected:
	static void _bind_methods();

public:
	CellSpatial() = default;
	~CellSpatial() override = default;

	Dictionary build_neighbor_csr(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedByteArray &alive,
			double cell_size);

	PackedFloat32Array collect_inputs_batch(const PackedFloat32Array &energies,
			const PackedByteArray &alive, const PackedByteArray &types,
			const PackedFloat32Array &fields_flat, const PackedInt32Array &sample_indices,
			const PackedInt32Array &neighbor_offsets, const PackedInt32Array &neighbor_values,
			double energy_max);

	// alive added so dead cells are excluded exactly as in GDScript build_collision_pairs_flat.
	Dictionary resolve_collisions(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedByteArray &alive,
			const PackedFloat32Array &radius_scales,
			const PackedFloat32Array &stiffnesses, double cell_radius,
			double cell_size, int iterations);

	// v0.34.0: exact port of CellPhysics.step() Verlet integration plus
	// _solve_links() constraint iterations. Side-effect-free; returns new arrays.
	Dictionary step_verlet_and_links(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedFloat32Array &prev_x,
			const PackedFloat32Array &prev_y, const PackedByteArray &alive,
			const PackedInt32Array &link_a, const PackedInt32Array &link_b,
			const PackedFloat32Array &rest_lengths, double damping,
			int constraint_iterations);
};
