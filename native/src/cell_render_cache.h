#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/variant/array.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/packed_color_array.hpp"
#include "godot_cpp/variant/packed_float32_array.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"
#include "godot_cpp/variant/packed_vector2_array.hpp"

using namespace godot;

/// v0.35.0: view-only polygon batch builder.
/// Mirrors CellPolygonBatchRenderer._rebuild_cache() but runs in C++.
/// Output is rendering data only: never read by simulation, never in state hash,
/// therefore float32 math is acceptable here.
class CellRenderCache : public RefCounted {
	GDCLASS(CellRenderCache, RefCounted)

protected:
	static void _bind_methods();

public:
	Dictionary rebuild(
			const PackedByteArray &alive,
			const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y,
			const PackedFloat32Array &radius_scales,
			const PackedByteArray &cell_type,
			const PackedInt32Array &cell_org_id,
			const PackedFloat32Array &color_r,
			const PackedFloat32Array &color_g,
			const PackedFloat32Array &color_b,
			const PackedFloat32Array &cell_energy,
			const PackedInt32Array &link_a,
			const PackedInt32Array &link_b,
			double base_radius,
			double dish_cx,
			double dish_cy,
			double dish_radius,
			double cell_size,
			int segments,
			int max_cells);
};
