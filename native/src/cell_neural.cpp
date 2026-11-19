#include "cell_neural.h"

#include <cmath>

using namespace godot;

PackedFloat32Array CellNeural::evaluate_into(const PackedFloat32Array &inputs,
		const PackedFloat32Array &weights, int offset) {
	PackedFloat32Array outputs;
	outputs.resize(OUTPUT_COUNT);
	for (int output_index = 0; output_index < OUTPUT_COUNT; ++output_index) {
		outputs.set(output_index, 0.0f);
	}
	if (inputs.size() != INPUT_COUNT || offset < 0 || offset + WEIGHT_COUNT > weights.size()) {
		return outputs;
	}
	float hidden[HIDDEN_COUNT];
	int cursor = offset;
	for (int hidden_index = 0; hidden_index < HIDDEN_COUNT; ++hidden_index) {
		double total = 0.0;
		for (int input_index = 0; input_index < INPUT_COUNT; ++input_index) {
			total += static_cast<double>(inputs[input_index]) * static_cast<double>(weights[cursor]);
			++cursor;
		}
		hidden[hidden_index] = static_cast<float>(std::tanh(total));
	}
	for (int output_index = 0; output_index < OUTPUT_COUNT; ++output_index) {
		double total = 0.0;
		for (int hidden_index = 0; hidden_index < HIDDEN_COUNT; ++hidden_index) {
			total += static_cast<double>(hidden[hidden_index]) * static_cast<double>(weights[cursor]);
			++cursor;
		}
		outputs.set(output_index, static_cast<float>(std::tanh(total)));
	}
	return outputs;
}

PackedFloat32Array CellNeural::evaluate_batch(const PackedFloat32Array &inputs_flat,
		const PackedFloat32Array &weights, const PackedByteArray &alive,
		int first, int last) {
	const int count = alive.size();
	PackedFloat32Array outputs;
	outputs.resize(count * OUTPUT_COUNT);
	for (int i = 0; i < count * OUTPUT_COUNT; ++i) {
		outputs.set(i, 0.0f);
	}
	float hidden[HIDDEN_COUNT];
	for (int cell_index = first; cell_index < last; ++cell_index) {
		if (cell_index < 0 || cell_index >= count || alive[cell_index] == 0) {
			continue;
		}
		const int input_offset = cell_index * INPUT_COUNT;
		const int weight_offset = cell_index * WEIGHT_COUNT;
		if (input_offset + INPUT_COUNT > inputs_flat.size() || weight_offset + WEIGHT_COUNT > weights.size()) {
			continue;
		}
		int cursor = weight_offset;
		for (int hidden_index = 0; hidden_index < HIDDEN_COUNT; ++hidden_index) {
			double total = 0.0;
			for (int input_index = 0; input_index < INPUT_COUNT; ++input_index) {
				total += static_cast<double>(inputs_flat[input_offset + input_index]) * static_cast<double>(weights[cursor]);
				++cursor;
			}
			hidden[hidden_index] = static_cast<float>(std::tanh(total));
		}
		const int output_offset = cell_index * OUTPUT_COUNT;
		for (int output_index = 0; output_index < OUTPUT_COUNT; ++output_index) {
			double total = 0.0;
			for (int hidden_index = 0; hidden_index < HIDDEN_COUNT; ++hidden_index) {
				total += static_cast<double>(hidden[hidden_index]) * static_cast<double>(weights[cursor]);
				++cursor;
			}
			outputs.set(output_offset + output_index, static_cast<float>(std::tanh(total)));
		}
	}
	return outputs;
}

void CellNeural::_bind_methods() {
	ClassDB::bind_method(D_METHOD("evaluate_into", "inputs", "weights", "offset"),
			&CellNeural::evaluate_into);
	ClassDB::bind_method(D_METHOD("evaluate_batch", "inputs_flat", "weights", "alive", "first", "last"),
			&CellNeural::evaluate_batch);
}
