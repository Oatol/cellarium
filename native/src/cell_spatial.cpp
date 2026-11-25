#include "cell_spatial.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

constexpr int64_t FLAT_KEY_OFFSET = 1000000;
constexpr int64_t FLAT_KEY_SPAN = 2000001;
// Guard against pathologically sparse positions making the flat grid huge.
constexpr int64_t MAX_FLAT_GRID_CELLS = 4'000'000;

inline int64_t flat_key(int64_t cx, int64_t cy) {
	return (cx + FLAT_KEY_OFFSET) * FLAT_KEY_SPAN + (cy + FLAT_KEY_OFFSET);
}

inline int64_t cell_coord(float p, double cell_size) {
	return static_cast<int64_t>(std::floor(static_cast<double>(p) / cell_size));
}

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

// CSR-style flat grid buckets, Cell Lab style: fixed array + prefix-sum offsets,
// no per-cell unordered_map hashing. Bucket contents stay in insertion order
// (cell_index ascending) so collision pair order is bit-identical to GDScript.
struct GridBuckets {
	bool use_flat = false;
	int64_t min_x = 0, min_y = 0, width = 0, height = 0;
	std::vector<int32_t> offsets;  // size cells+1
	std::vector<int32_t> data;     // cell indices grouped by bucket
	std::unordered_map<int64_t, std::vector<int32_t>> fallback;

	static GridBuckets build(const PackedFloat32Array &pos_x, const PackedFloat32Array &pos_y,
			const PackedByteArray &alive, int count, double cell_size) {
		GridBuckets g;
		std::vector<int64_t> cx(static_cast<size_t>(count));
		std::vector<int64_t> cy(static_cast<size_t>(count));
		int64_t lo_x = std::numeric_limits<int64_t>::max();
		int64_t hi_x = std::numeric_limits<int64_t>::min();
		int64_t lo_y = std::numeric_limits<int64_t>::max();
		int64_t hi_y = std::numeric_limits<int64_t>::min();
		for (int i = 0; i < count; ++i) {
			if (alive[i] == 0) {
				cx[i] = cy[i] = 0;
				continue;
			}
			cx[i] = cell_coord(pos_x[i], cell_size);
			cy[i] = cell_coord(pos_y[i], cell_size);
			lo_x = std::min(lo_x, cx[i]); hi_x = std::max(hi_x, cx[i]);
			lo_y = std::min(lo_y, cy[i]); hi_y = std::max(hi_y, cy[i]);
		}
		if (count == 0 || lo_x > hi_x) {
			g.use_flat = true;
			g.width = g.height = 0;
			g.offsets.assign(1, 0);
			return g;
		}
		// Pad by 1 on each side for 3x3 neighbor queries at the border.
		const int64_t w = hi_x - lo_x + 3;
		const int64_t h = hi_y - lo_y + 3;
		g.use_flat = (w > 0 && h > 0 && w <= MAX_FLAT_GRID_CELLS && h <= MAX_FLAT_GRID_CELLS
				&& w * h <= MAX_FLAT_GRID_CELLS);
		if (!g.use_flat) {
			for (int i = 0; i < count; ++i) {
				if (alive[i] == 0) continue;
				g.fallback[flat_key(cx[i], cy[i])].push_back(i);
			}
			return g;
		}
		g.min_x = lo_x - 1;
		g.min_y = lo_y - 1;
		g.width = w;
		g.height = h;
		const size_t cell_count = static_cast<size_t>(w * h);
		g.offsets.assign(cell_count + 1, 0);
		for (int i = 0; i < count; ++i) {
			if (alive[i] == 0) continue;
			const size_t idx = static_cast<size_t>(cx[i] - g.min_x) * static_cast<size_t>(h)
					+ static_cast<size_t>(cy[i] - g.min_y);
			g.offsets[idx + 1] = g.offsets[idx + 1] + 1;
		}
		for (size_t i = 1; i <= cell_count; ++i) {
			g.offsets[i] += g.offsets[i - 1];
		}
		g.data.resize(static_cast<size_t>(g.offsets[cell_count]));
		std::vector<int32_t> cursor(g.offsets.begin(), g.offsets.end() - 1);
		for (int i = 0; i < count; ++i) {
			if (alive[i] == 0) continue;
			const size_t idx = static_cast<size_t>(cx[i] - g.min_x) * static_cast<size_t>(h)
					+ static_cast<size_t>(cy[i] - g.min_y);
			const int32_t slot = cursor[idx];
			g.data[static_cast<size_t>(slot)] = i;
			cursor[idx] = slot + 1;
		}
		return g;
	}

	// Visit each cell in the 9-grid neighborhood; callback(cell_index) in bucket insertion order.
	template <typename Fn>
	void for_each_neighbor(int64_t cx, int64_t cy, Fn &&fn) const {
		if (use_flat) {
			for (int64_t oy = -1; oy <= 1; ++oy) {
				const int64_t gy = cy + oy - min_y;
				if (gy < 0 || gy >= height) continue;
				for (int64_t ox = -1; ox <= 1; ++ox) {
					const int64_t gx = cx + ox - min_x;
					if (gx < 0 || gx >= width) continue;
					const size_t idx = static_cast<size_t>(gx) * static_cast<size_t>(height) + static_cast<size_t>(gy);
					for (int32_t k = offsets[idx]; k < offsets[idx + 1]; ++k) {
						fn(data[static_cast<size_t>(k)]);
					}
				}
			}
		} else {
			for (int64_t oy = -1; oy <= 1; ++oy) {
				for (int64_t ox = -1; ox <= 1; ++ox) {
					const auto it = fallback.find(flat_key(cx + ox, cy + oy));
					if (it == fallback.end()) continue;
					for (const int32_t v : it->second) {
						fn(v);
					}
				}
			}
		}
	}
};

}  // namespace

Dictionary CellSpatial::build_neighbor_csr(const PackedFloat32Array &pos_x,
		const PackedFloat32Array &pos_y, const PackedByteArray &alive,
		double cell_size) {
	PackedInt32Array offsets;
	PackedInt32Array values;
	const int count = alive.size();
	offsets.resize(count + 1);
	const GridBuckets grid = GridBuckets::build(pos_x, pos_y, alive, count, cell_size);
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		offsets.set(cell_index, values.size());
		if (alive[cell_index] == 0) continue;
		const int64_t cx = cell_coord(pos_x[cell_index], cell_size);
		const int64_t cy = cell_coord(pos_y[cell_index], cell_size);
		std::vector<int> found;
		grid.for_each_neighbor(cx, cy, [&](int32_t neighbor) {
			if (neighbor != cell_index) found.push_back(static_cast<int>(neighbor));
		});
		std::sort(found.begin(), found.end());
		for (const int neighbor : found) values.append(neighbor);
	}
	offsets.set(count, values.size());
	Dictionary result;
	result["offsets"] = offsets;
	result["values"] = values;
	return result;
}

PackedFloat32Array CellSpatial::collect_inputs_batch(const PackedFloat32Array &energies,
		const PackedByteArray &alive, const PackedByteArray &types,
		const PackedFloat32Array &fields_flat, const PackedInt32Array &sample_indices,
		const PackedInt32Array &neighbor_offsets, const PackedInt32Array &neighbor_values,
		double energy_max) {
	const int count = alive.size();
	PackedFloat32Array inputs;
	inputs.resize(count * 8);
	const bool use_flat = fields_flat.size() > 0 && sample_indices.size() > 0;
	const bool use_csr = neighbor_offsets.size() > count;
	const double emax = std::max(energy_max, 0.000001);
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		const int out = cell_index * 8;
		for (int c = 0; c < 8; ++c) inputs.set(out + c, 0.0f);
		int sample_index = -1;
		if (use_flat && cell_index < sample_indices.size()) {
			sample_index = static_cast<int>(sample_indices[cell_index]);
		}
		if (use_flat && sample_index >= 0) {
			const int flat_offset = sample_index * 5;
			for (int channel = 0; channel < 5; ++channel) {
				if (flat_offset + channel < fields_flat.size()) {
					inputs.set(out + channel,
							static_cast<float>(clampd(static_cast<double>(fields_flat[flat_offset + channel]), -1.0, 1.0)));
				}
			}
		}
		int same_count = 0;
		int other_count = 0;
		if (use_csr) {
			const int neighbor_start = static_cast<int>(neighbor_offsets[cell_index]);
			const int neighbor_end = static_cast<int>(neighbor_offsets[cell_index + 1]);
			for (int cursor = neighbor_start; cursor < neighbor_end; ++cursor) {
				const int neighbor = static_cast<int>(neighbor_values[cursor]);
				if (neighbor < 0 || neighbor >= alive.size() || neighbor == cell_index || alive[neighbor] == 0) continue;
				if (types[neighbor] == types[cell_index]) ++same_count; else ++other_count;
			}
		}
		inputs.set(out + 5, static_cast<float>(std::min(static_cast<double>(same_count) / 8.0, 1.0)));
		inputs.set(out + 6, static_cast<float>(std::min(static_cast<double>(other_count) / 8.0, 1.0)));
		inputs.set(out + 7, static_cast<float>(clampd(static_cast<double>(energies[cell_index]) / emax, 0.0, 1.0)));
	}
	return inputs;
}

PackedFloat32Array CellSpatial::collect_inputs_grid(const PackedFloat32Array &pos_x,
		const PackedFloat32Array &pos_y, const PackedFloat32Array &energies,
		const PackedByteArray &alive, const PackedByteArray &types,
		const PackedFloat32Array &fields_flat, const PackedInt32Array &sample_indices,
		double cell_size, double energy_max) {
	const int count = alive.size();
	PackedFloat32Array inputs;
	inputs.resize(count * 8);
	const bool use_flat = fields_flat.size() > 0 && sample_indices.size() > 0;
	const double emax = std::max(energy_max, 0.000001);
	const GridBuckets grid = GridBuckets::build(pos_x, pos_y, alive, count, cell_size);
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		const int out = cell_index * 8;
		for (int c = 0; c < 8; ++c) inputs.set(out + c, 0.0f);
		if (alive[cell_index] == 0) continue;
		int sample_index = -1;
		if (use_flat && cell_index < sample_indices.size()) {
			sample_index = static_cast<int>(sample_indices[cell_index]);
		}
		if (use_flat && sample_index >= 0) {
			const int flat_offset = sample_index * 5;
			for (int channel = 0; channel < 5; ++channel) {
				if (flat_offset + channel < fields_flat.size()) {
					inputs.set(out + channel,
							static_cast<float>(clampd(static_cast<double>(fields_flat[flat_offset + channel]), -1.0, 1.0)));
				}
			}
		}
		int same_count = 0;
		int other_count = 0;
		const int64_t cx = cell_coord(pos_x[cell_index], cell_size);
		const int64_t cy = cell_coord(pos_y[cell_index], cell_size);
		const uint8_t self_type = types[cell_index];
		grid.for_each_neighbor(cx, cy, [&](int32_t neighbor) {
			if (neighbor == cell_index || neighbor < 0 || neighbor >= count || alive[neighbor] == 0) return;
			if (types[neighbor] == self_type) ++same_count; else ++other_count;
		});
		inputs.set(out + 5, static_cast<float>(std::min(static_cast<double>(same_count) / 8.0, 1.0)));
		inputs.set(out + 6, static_cast<float>(std::min(static_cast<double>(other_count) / 8.0, 1.0)));
		inputs.set(out + 7, static_cast<float>(clampd(static_cast<double>(energies[cell_index]) / emax, 0.0, 1.0)));
	}
	return inputs;
}

Dictionary CellSpatial::resolve_collisions(const PackedFloat32Array &pos_x_in,
		const PackedFloat32Array &pos_y_in, const PackedByteArray &alive,
		const PackedFloat32Array &radius_scales,
		const PackedFloat32Array &stiffnesses, double cell_radius,
		double cell_size, int iterations) {
	PackedFloat32Array pos_x = pos_x_in;
	PackedFloat32Array pos_y = pos_y_in;
	const int count = pos_x.size();
	// v0.45：内层 pair 循环原本每次走 PackedFloat32Array::set/operator[]（含 COW 与边界检查）。
	// 这里一次取可写裸指针，读写仍是 float32 → double → float32 的原顺序，逐位等价。
	float *px = pos_x.ptrw();
	float *py = pos_y.ptrw();
	const uint8_t *alive_ptr = alive.ptr();
	const float *scale_ptr = radius_scales.ptr();
	const float *stiff_ptr = stiffnesses.ptr();

	auto build_pairs = [&]() -> std::vector<int> {
		const GridBuckets grid = GridBuckets::build(pos_x, pos_y, alive, count, cell_size);
		std::vector<int> pairs;
		for (int a = 0; a < count; ++a) {
			if (alive_ptr[a] == 0) continue;
			const int64_t cx = cell_coord(px[a], cell_size);
			const int64_t cy = cell_coord(py[a], cell_size);
			const double ax = static_cast<double>(px[a]);
			const double ay = static_cast<double>(py[a]);
			const double scale_a = (a < radius_scales.size()) ? static_cast<double>(scale_ptr[a]) : 1.0;
			const double contact_a = cell_radius * scale_a;
			grid.for_each_neighbor(cx, cy, [&](int32_t bv) {
				const int b = static_cast<int>(bv);
				if (b <= a) return;
				if (cell_radius > 0.0) {
					const double dx = static_cast<double>(px[b]) - ax;
					const double dy = static_cast<double>(py[b]) - ay;
					const double scale_b = (b < radius_scales.size()) ? static_cast<double>(scale_ptr[b]) : 1.0;
					const double contact_distance = contact_a + cell_radius * scale_b;
					if (dx * dx + dy * dy > contact_distance * contact_distance * 4.0) return;
				}
				pairs.push_back(a);
				pairs.push_back(b);
			});
		}
		return pairs;
	};

	std::vector<int> pairs = build_pairs();
	int resolved = 0;
	for (int iteration = 0; iteration < iterations; ++iteration) {
		if (iteration > 0 && iteration % 3 == 0) pairs = build_pairs();
		int round_resolved = 0;
		double max_correction = 0.0;
		for (size_t pair_index = 0; pair_index + 1 < pairs.size(); pair_index += 2) {
			const int a = pairs[pair_index];
			const int b = pairs[pair_index + 1];
			const double dx = static_cast<double>(px[b]) - static_cast<double>(px[a]);
			const double dy = static_cast<double>(py[b]) - static_cast<double>(py[a]);
			const double scale_a = (a < radius_scales.size()) ? static_cast<double>(scale_ptr[a]) : 1.0;
			const double scale_b = (b < radius_scales.size()) ? static_cast<double>(scale_ptr[b]) : 1.0;
			const double contact_distance = cell_radius * (scale_a + scale_b);
			const double distance_squared = dx * dx + dy * dy;
			if (distance_squared > contact_distance * contact_distance + 0.000001) continue;
			const double distance = std::sqrt(distance_squared);
			if (distance >= contact_distance) continue;
			double normal_x = 1.0, normal_y = 0.0;
			if (distance > 0.000001) {
				normal_x = dx / distance;
				normal_y = dy / distance;
			}
			double stiffness = 1.0;
			if (a < stiffnesses.size() && b < stiffnesses.size()) {
				stiffness = clampd((static_cast<double>(stiff_ptr[a]) + static_cast<double>(stiff_ptr[b])) * 0.5, 0.25, 2.0);
			}
			const double correction = (contact_distance - distance) * 0.5 * stiffness;
			px[a] = static_cast<float>(static_cast<double>(px[a]) - normal_x * correction);
			py[a] = static_cast<float>(static_cast<double>(py[a]) - normal_y * correction);
			px[b] = static_cast<float>(static_cast<double>(px[b]) + normal_x * correction);
			py[b] = static_cast<float>(static_cast<double>(py[b]) + normal_y * correction);
			++round_resolved;
			max_correction = std::max(max_correction, correction);
		}
		resolved += round_resolved;
		if (max_correction < 0.001) break;
	}

	Dictionary result;
	result["pos_x"] = pos_x;
	result["pos_y"] = pos_y;
	result["resolved"] = resolved;
	return result;
}

Dictionary CellSpatial::step_verlet_and_links(const PackedFloat32Array &pos_x,
		const PackedFloat32Array &pos_y, const PackedFloat32Array &prev_x,
		const PackedFloat32Array &prev_y, const PackedByteArray &alive,
		const PackedInt32Array &link_a, const PackedInt32Array &link_b,
		const PackedFloat32Array &rest_lengths, double damping,
		int constraint_iterations) {
	PackedFloat32Array next_pos_x = pos_x;
	PackedFloat32Array next_pos_y = pos_y;
	PackedFloat32Array next_prev_x = prev_x;
	PackedFloat32Array next_prev_y = prev_y;
	const int count = alive.size();
	for (int i = 0; i < count; ++i) {
		if (alive[i] == 0) continue;
		const double x = static_cast<double>(next_pos_x[i]);
		const double y = static_cast<double>(next_pos_y[i]);
		const double vx = x - static_cast<double>(next_prev_x[i]);
		const double vy = y - static_cast<double>(next_prev_y[i]);
		next_prev_x.set(i, static_cast<float>(x));
		next_prev_y.set(i, static_cast<float>(y));
		next_pos_x.set(i, static_cast<float>(x + vx * damping));
		next_pos_y.set(i, static_cast<float>(y + vy * damping));
	}
	for (int iteration = 0; iteration < constraint_iterations; ++iteration) {
		for (int link_index = 0; link_index < link_a.size(); ++link_index) {
			const int a = link_a[link_index];
			const int b = link_b[link_index];
			if (a < 0 || b < 0 || a >= count || b >= count ||
					alive[a] == 0 || alive[b] == 0) {
				continue;
			}
			const double dx = static_cast<double>(next_pos_x[b]) -
					static_cast<double>(next_pos_x[a]);
			const double dy = static_cast<double>(next_pos_y[b]) -
					static_cast<double>(next_pos_y[a]);
			const double distance = std::sqrt(dx * dx + dy * dy);
			if (distance <= 0.000001) continue;
			const double correction = (distance -
					static_cast<double>(rest_lengths[link_index])) / distance;
			const double half = correction * 0.5;
			const double ax = static_cast<double>(next_pos_x[a]) + dx * half;
			const double ay = static_cast<double>(next_pos_y[a]) + dy * half;
			const double bx = static_cast<double>(next_pos_x[b]) - dx * half;
			const double by = static_cast<double>(next_pos_y[b]) - dy * half;
			next_pos_x.set(a, static_cast<float>(ax));
			next_pos_y.set(a, static_cast<float>(ay));
			next_pos_x.set(b, static_cast<float>(bx));
			next_pos_y.set(b, static_cast<float>(by));
		}
	}
	Dictionary result;
	result["pos_x"] = next_pos_x;
	result["pos_y"] = next_pos_y;
	result["prev_x"] = next_prev_x;
	result["prev_y"] = next_prev_y;
	return result;
}

void CellSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_neighbor_csr", "pos_x", "pos_y", "alive", "cell_size"),
			&CellSpatial::build_neighbor_csr);
	ClassDB::bind_method(D_METHOD("collect_inputs_batch", "energies", "alive", "types", "fields_flat", "sample_indices", "neighbor_offsets", "neighbor_values", "energy_max"),
			&CellSpatial::collect_inputs_batch);
	ClassDB::bind_method(D_METHOD("collect_inputs_grid", "pos_x", "pos_y", "energies", "alive", "types", "fields_flat", "sample_indices", "cell_size", "energy_max"),
			&CellSpatial::collect_inputs_grid);
	ClassDB::bind_method(D_METHOD("resolve_collisions", "pos_x", "pos_y", "alive", "radius_scales", "stiffnesses", "cell_radius", "cell_size", "iterations"),
			&CellSpatial::resolve_collisions);
	ClassDB::bind_method(D_METHOD("step_verlet_and_links", "pos_x", "pos_y", "prev_x", "prev_y", "alive", "link_a", "link_b", "rest_lengths", "damping", "constraint_iterations"),
			&CellSpatial::step_verlet_and_links);
}
