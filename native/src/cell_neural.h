#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_float32_array.hpp"
#include "godot_cpp/variant/packed_float64_array.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"

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

	// v0.35.0: pure output-buffer copy used before CellBehavior.apply_cached_intents.
	// The actual movement stays in GDScript on purpose: Godot's Vector2.rotated
	// uses engine-internal float math that differs by 1 ULP from godot-cpp's
	// std::cos in a small number of angles, so moving it would drift state hash.
	PackedFloat32Array copy_outputs_to_intents(const PackedByteArray &alive,
			const PackedFloat32Array &intents, const PackedFloat32Array &outputs);

	// v0.35.0: pure candidate scan for OrganismManager._apply_signal_secretion.
	// Returns ascending cell indices and double secretion amounts; environment
	// add_signal_source side effects remain in GDScript.
	Dictionary collect_signal_sources(const PackedByteArray &alive,
			const PackedFloat32Array &intents, const PackedFloat32Array &pos_x,
			const PackedFloat32Array &pos_y, double dt);
};
