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

PackedFloat32Array CellNeural::copy_outputs_to_intents(const PackedByteArray &alive,
		const PackedFloat32Array &intents, const PackedFloat32Array &outputs) {
	const int count = alive.size();
	PackedFloat32Array result;
	if (outputs.size() < count * OUTPUT_COUNT || intents.size() < count * OUTPUT_COUNT) {
		return result;
	}
	result = intents;
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		if (alive[cell_index] == 0) continue;
		const int start = cell_index * OUTPUT_COUNT;
		for (int output_index = 0; output_index < OUTPUT_COUNT; ++output_index) {
			result.set(start + output_index, outputs[start + output_index]);
		}
	}
	return result;
}

Dictionary CellNeural::collect_signal_sources(const PackedByteArray &alive,
		const PackedFloat32Array &intents, const PackedFloat32Array &pos_x,
		const PackedFloat32Array &pos_y, double dt) {
	PackedInt32Array indices;
	PackedFloat64Array amounts;
	const int count = alive.size();
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		if (alive[cell_index] == 0) continue;
		const int intent_index = cell_index * OUTPUT_COUNT + 3;
		if (intent_index >= intents.size()) continue;
		const double amount = (static_cast<double>(intents[intent_index]) > 0.0
				? static_cast<double>(intents[intent_index]) : 0.0) * dt;
		if (amount > 0.0) {
			indices.append(cell_index);
			amounts.append(amount);
		}
	}
	Dictionary result;
	result["indices"] = indices;
	result["amounts"] = amounts;
	return result;
}

void CellNeural::_bind_methods() {
	ClassDB::bind_method(D_METHOD("evaluate_into", "inputs", "weights", "offset"),
			&CellNeural::evaluate_into);
	ClassDB::bind_method(D_METHOD("evaluate_batch", "inputs_flat", "weights", "alive", "first", "last"),
			&CellNeural::evaluate_batch);
	ClassDB::bind_method(D_METHOD("copy_outputs_to_intents", "alive", "intents", "outputs"),
			&CellNeural::copy_outputs_to_intents);
	ClassDB::bind_method(D_METHOD("collect_signal_sources", "alive", "intents", "pos_x", "pos_y", "dt"),
			&CellNeural::collect_signal_sources);
}
