#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/variant/packed_float32_array.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"

using namespace godot;

class CellNeural : public RefCounted {
	GDCLASS(CellNeural, RefCounted)

protected:
	static void _bind_methods();

public:
	CellNeural() = default;
	~CellNeural() override = default;

	static constexpr int INPUT_COUNT = 8;
	static constexpr int HIDDEN_COUNT = 4;
	static constexpr int OUTPUT_COUNT = 6;
	static constexpr int WEIGHT_COUNT = INPUT_COUNT * HIDDEN_COUNT + HIDDEN_COUNT * OUTPUT_COUNT;

	// Bit-exact port of CellBehavior.evaluate_into (GDScript).
	// GDScript float is double; PackedFloat32Array elements are float32.
	// Accumulate and tanh in double, store back as float32.
	// Returns a fresh OUTPUT_COUNT array.
	PackedFloat32Array evaluate_into(const PackedFloat32Array &inputs,
			const PackedFloat32Array &weights, int offset);

	// Batch inference: inputs_flat is count*8, weights is count*56,
	// alive is count bytes; returns count*6 flat outputs. alive==0 rows are zeroed.
	// Only [first,last) rows are computed; rows outside are zeroed.
	PackedFloat32Array evaluate_batch(const PackedFloat32Array &inputs_flat,
			const PackedFloat32Array &weights, const PackedByteArray &alive,
			int first, int last);
};
