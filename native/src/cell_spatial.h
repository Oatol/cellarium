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

	// v0.36.0: fused path — builds the grid once and counts same/other neighbors inline,
	// avoiding the per-tick CSR materialization that dominated behavior. Produces the
	// exact same 8-channel inputs as collect_inputs_batch; bit-identical by construction
	// since only integer neighbor counts are involved and no sort is required.
	PackedFloat32Array collect_inputs_grid(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedFloat32Array &energies,
			const PackedByteArray &alive, const PackedByteArray &types,
			const PackedFloat32Array &fields_flat, const PackedInt32Array &sample_indices,
			double cell_size, double energy_max);

	// alive added so dead cells are excluded exactly as in GDScript build_collision_pairs_flat.
	Dictionary resolve_collisions(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedByteArray &alive,
			const PackedFloat32Array &radius_scales,
			const PackedFloat32Array &stiffnesses, double cell_radius,
			double cell_size, int iterations);

	// v0.47.0: Cell Lab 式单轮软弹力碰撞。单次网格遍历、不迭代、不物化 pairs，
	// 每对只推开穿透深度的一部分，剩余穿透由后续 tick 松弛。旧 resolve_collisions
	// 保留用于 A/B 与回放兼容。
	// cell_size <= 0 → 内核按「2 × cell_radius × 存活细胞最大半径倍率」自动推导，
	// 保证 9 格邻域不漏对（推导公式与 GDScript 回退路径逐位同序）。
	Dictionary resolve_collisions_soft(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedByteArray &alive,
			const PackedFloat32Array &radius_scales,
			const PackedFloat32Array &stiffnesses, double cell_radius,
			double cell_size, double softness);

	// v0.34.0: exact port of CellPhysics.step() Verlet integration plus
	// _solve_links() constraint iterations. Side-effect-free; returns new arrays.
	Dictionary step_verlet_and_links(const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, const PackedFloat32Array &prev_x,
			const PackedFloat32Array &prev_y, const PackedByteArray &alive,
			const PackedInt32Array &link_a, const PackedInt32Array &link_b,
			const PackedFloat32Array &rest_lengths, double damping,
			int constraint_iterations);
};
