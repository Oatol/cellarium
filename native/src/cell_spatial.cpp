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
// v0.48.0: 环境场通道数（营养/温度/氧气/光照/信号），与 EnvironmentField.CHANNEL_COUNT 对齐。
constexpr int CHANNEL_COUNT_FOR_SAMPLING = 5;
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
	// v0.45：内层逐次 inputs.set() 含 COW + 边界检查（1025 细胞 ×8 次）；
	// 一次取裸指针直写，float32 舍入顺序与遍历语义完全不变，逐位等价。
	// 与 v0.44 resolve_collisions 同款改法，由 spatial_parity / NativeParityProbe 双重闸门保证。
	float *out_ptr = inputs.ptrw();
	const uint8_t *alive_ptr = alive.ptr();
	const uint8_t *types_ptr = types.ptr();
	const float *px = pos_x.ptr();
	const float *py = pos_y.ptr();
	const float *energy_ptr = energies.ptr();
	const float *fields_ptr = fields_flat.ptr();
	const int32_t *sample_ptr = sample_indices.ptr();
	const bool use_flat = fields_flat.size() > 0 && sample_indices.size() > 0;
	const double emax = std::max(energy_max, 0.000001);
	const GridBuckets grid = GridBuckets::build(pos_x, pos_y, alive, count, cell_size);
	for (int cell_index = 0; cell_index < count; ++cell_index) {
		const int out = cell_index * 8;
		for (int c = 0; c < 8; ++c) out_ptr[out + c] = 0.0f;
		if (alive_ptr[cell_index] == 0) continue;
		int sample_index = -1;
		if (use_flat && cell_index < sample_indices.size()) {
			sample_index = static_cast<int>(sample_ptr[cell_index]);
		}
		if (use_flat && sample_index >= 0) {
			const int flat_offset = sample_index * 5;
			for (int channel = 0; channel < 5; ++channel) {
				if (flat_offset + channel < fields_flat.size()) {
					out_ptr[out + channel] =
							static_cast<float>(clampd(static_cast<double>(fields_ptr[flat_offset + channel]), -1.0, 1.0));
				}
			}
		}
		int same_count = 0;
		int other_count = 0;
		const int64_t cx = cell_coord(px[cell_index], cell_size);
		const int64_t cy = cell_coord(py[cell_index], cell_size);
		const uint8_t self_type = types_ptr[cell_index];
		grid.for_each_neighbor(cx, cy, [&](int32_t neighbor) {
			if (neighbor == cell_index || neighbor < 0 || neighbor >= count || alive_ptr[neighbor] == 0) return;
			if (types_ptr[neighbor] == self_type) ++same_count; else ++other_count;
		});
		out_ptr[out + 5] = static_cast<float>(std::min(static_cast<double>(same_count) / 8.0, 1.0));
		out_ptr[out + 6] = static_cast<float>(std::min(static_cast<double>(other_count) / 8.0, 1.0));
		out_ptr[out + 7] = static_cast<float>(clampd(static_cast<double>(energy_ptr[cell_index]) / emax, 0.0, 1.0));
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

// v0.47：Cell Lab 式单轮软弹力碰撞。
// 与 resolve_collisions 的结构性差别（性能与手感同时来自这里）：
//   1. 只遍历一次固定网格，不迭代、不在中途重建网格（旧路径 6 轮 + 2 次重建）；
//   2. 不物化 pairs 向量，直接在 9 格邻域里判定，省掉每 tick 数万次 push_back；
//   3. 先比距离平方再开方，与 Cell Lab `d46 < d49*d49` 同序；
//   4. 每对只推开穿透深度的一部分（softness），剩余穿透留到后续 tick 继续松弛，
//      不做 Gauss-Seidel 反复修正 —— 这正是 Cell Lab 的软弹力手感，也避免多轮
//      位置修正反复注入能量造成的抖动；
//   5. cell_size <= 0 时按实际最大半径自动推导：9 格邻域只覆盖 Chebyshev 距离
//      ≤ cell_size，而 |Δ|∞ ≤ |Δ|₂，所以要保证不漏对必须 cell_size ≥ 最大接触距离。
//      旧路径写死 64.0，而典型细胞直径只有 14 —— 每桶挤 ~20 个细胞、9 桶扫 180 个
//      候选却只有 ~6 个真邻居，这是碰撞成本的主因（实测 64→14 单项就有 2.5×）。
Dictionary CellSpatial::resolve_collisions_soft(const PackedFloat32Array &pos_x_in,
		const PackedFloat32Array &pos_y_in, const PackedByteArray &alive,
		const PackedFloat32Array &radius_scales,
		const PackedFloat32Array &stiffnesses, double cell_radius,
		double cell_size, double softness) {
	PackedFloat32Array pos_x = pos_x_in;
	PackedFloat32Array pos_y = pos_y_in;
	const int count = pos_x.size();
	float *px = pos_x.ptrw();
	float *py = pos_y.ptrw();
	const uint8_t *alive_ptr = alive.ptr();
	const float *scale_ptr = radius_scales.ptr();
	const float *stiff_ptr = stiffnesses.ptr();
	const int scale_count = radius_scales.size();
	const int stiff_count = stiffnesses.size();
	const double soft = clampd(softness, 0.0, 1.0);

	double effective_cell_size = cell_size;
	if (effective_cell_size <= 0.0) {
		// 与 GDScript 回退路径完全同序：先求存活细胞的最大半径倍率，再乘 2×cell_radius。
		double max_scale = 0.0;
		for (int i = 0; i < count; ++i) {
			if (alive_ptr[i] == 0 || i >= scale_count) continue;
			const double s = static_cast<double>(scale_ptr[i]);
			if (s > max_scale) max_scale = s;
		}
		if (max_scale <= 0.0) max_scale = 1.0;
		effective_cell_size = 2.0 * cell_radius * max_scale;
		if (effective_cell_size < 1.0) effective_cell_size = 1.0;
	}

	const GridBuckets grid = GridBuckets::build(pos_x, pos_y, alive, count, effective_cell_size);
	int resolved = 0;
	double max_penetration = 0.0;
	for (int a = 0; a < count; ++a) {
		if (alive_ptr[a] == 0) continue;
		const int64_t cx = cell_coord(px[a], effective_cell_size);
		const int64_t cy = cell_coord(py[a], effective_cell_size);
		const double scale_a = (a < scale_count) ? static_cast<double>(scale_ptr[a]) : 1.0;
		grid.for_each_neighbor(cx, cy, [&](int32_t bv) {
			const int b = static_cast<int>(bv);
			if (b <= a) return;
			const double dx = static_cast<double>(px[b]) - static_cast<double>(px[a]);
			const double dy = static_cast<double>(py[b]) - static_cast<double>(py[a]);
			const double scale_b = (b < scale_count) ? static_cast<double>(scale_ptr[b]) : 1.0;
			const double contact = cell_radius * (scale_a + scale_b);
			const double distance_squared = dx * dx + dy * dy;
			if (distance_squared >= contact * contact) return;
			const double distance = std::sqrt(distance_squared);
			double normal_x = 1.0;
			double normal_y = 0.0;
			if (distance > 0.000001) {
				normal_x = dx / distance;
				normal_y = dy / distance;
			}
			double stiffness = 1.0;
			if (a < stiff_count && b < stiff_count) {
				stiffness = clampd((static_cast<double>(stiff_ptr[a]) + static_cast<double>(stiff_ptr[b])) * 0.5, 0.25, 2.0);
			}
			const double penetration = contact - distance;
			const double correction = penetration * 0.5 * stiffness * soft;
			px[a] = static_cast<float>(static_cast<double>(px[a]) - normal_x * correction);
			py[a] = static_cast<float>(static_cast<double>(py[a]) - normal_y * correction);
			px[b] = static_cast<float>(static_cast<double>(px[b]) + normal_x * correction);
			py[b] = static_cast<float>(static_cast<double>(py[b]) + normal_y * correction);
			++resolved;
			max_penetration = std::max(max_penetration, penetration);
		});
	}

	Dictionary result;
	result["pos_x"] = pos_x;
	result["pos_y"] = pos_y;
	result["resolved"] = resolved;
	result["max_penetration"] = max_penetration;
	result["cell_size"] = effective_cell_size;
	return result;
}

Dictionary CellSpatial::step_verlet_and_links(const PackedFloat32Array &pos_x,
		const PackedFloat32Array &pos_y, const PackedFloat32Array &prev_x,
		const PackedFloat32Array &prev_y, const PackedByteArray &alive,
		const PackedInt32Array &link_a, const PackedInt32Array &link_b,
		const PackedFloat32Array &rest_lengths,
		const PackedByteArray &link_counts, double damping,
		int constraint_iterations, double stiffness, double harden_gain,
		double harden_ratio, double velocity_damping, double tear_ratio) {
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
	const int link_total = link_a.size();
	const int link_count_size = link_counts.size();
	for (int iteration = 0; iteration < constraint_iterations; ++iteration) {
		for (int link_index = 0; link_index < link_total; ++link_index) {
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
			const double rest = static_cast<double>(rest_lengths[link_index]);
			const double delta = distance - rest;
			// 非线性硬化：偏离越大越硬（Cell Lab d35 = 1 + 2Δ²/0.0036，特征长度约 3r）。
			const double feature = harden_ratio * (rest > 0.000001 ? rest : 0.000001);
			const double hard = 1.0 + harden_gain * (delta * delta) / (feature * feature);
			// 连接数分摊：一个细胞连得越多，单条连接越软（Cell Lab d32 除以 max(linkCount)）。
			const int count_a = (a < link_count_size) ? static_cast<int>(link_counts[a]) : 1;
			const int count_b = (b < link_count_size) ? static_cast<int>(link_counts[b]) : 1;
			const int max_count = (count_a > count_b ? count_a : count_b);
			const double share = 1.0 / static_cast<double>(max_count > 1 ? max_count : 1);
			double k = stiffness * hard * share;
			if (k > 0.9) k = 0.9;
			const double inverse = 1.0 / distance;
			const double nx = dx * inverse;
			const double ny = dy * inverse;
			const double correction = delta * k * 0.5;
			next_pos_x.set(a, static_cast<float>(static_cast<double>(next_pos_x[a]) + nx * correction));
			next_pos_y.set(a, static_cast<float>(static_cast<double>(next_pos_y[a]) + ny * correction));
			next_pos_x.set(b, static_cast<float>(static_cast<double>(next_pos_x[b]) - nx * correction));
			next_pos_y.set(b, static_cast<float>(static_cast<double>(next_pos_y[b]) - ny * correction));
		}
	}
	// 端点相对速度阻尼：`pos − prev` 是本 tick 速度，沿连接方向消减相对分量。
	// v0.52.1：同时做过拉伸判定，超过静止长度 tear_ratio 倍的连接记入 break_links
	// （升序），由调用方倒序 remove_link —— 内核不改连接数组本身。
	PackedInt32Array break_links;
	for (int link_index = 0; link_index < link_total; ++link_index) {
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
		const double rest = static_cast<double>(rest_lengths[link_index]);
		if (tear_ratio > 0.0 && rest > 0.000001 && distance > tear_ratio * rest) {
			break_links.append(link_index);
			continue;
		}
		const double inverse = 1.0 / distance;
		const double nx = dx * inverse;
		const double ny = dy * inverse;
		const double rel_vx =
				(static_cast<double>(next_pos_x[b]) - static_cast<double>(next_prev_x[b])) -
				(static_cast<double>(next_pos_x[a]) - static_cast<double>(next_prev_x[a]));
		const double rel_vy =
				(static_cast<double>(next_pos_y[b]) - static_cast<double>(next_prev_y[b])) -
				(static_cast<double>(next_pos_y[a]) - static_cast<double>(next_prev_y[a]));
		const double along = (rel_vx * nx + rel_vy * ny) * velocity_damping * 0.5;
		next_pos_x.set(a, static_cast<float>(static_cast<double>(next_pos_x[a]) + nx * along));
		next_pos_y.set(a, static_cast<float>(static_cast<double>(next_pos_y[a]) + ny * along));
		next_pos_x.set(b, static_cast<float>(static_cast<double>(next_pos_x[b]) - nx * along));
		next_pos_y.set(b, static_cast<float>(static_cast<double>(next_pos_y[b]) - ny * along));
	}
	Dictionary result;
	result["pos_x"] = next_pos_x;
	result["pos_y"] = next_pos_y;
	result["prev_x"] = next_prev_x;
	result["prev_y"] = next_prev_y;
	result["break_links"] = break_links;
	return result;
}

// v0.52.1: 每 tick 派生连接静止长度。逐位同序于 GDScript 回退：
//   radius = cell_radius * radius_scale（缺省 1.0）
//   rest   = r_a + r_b - 2 * gap_ratio * min(r_a, r_b) + offset（缺省 0.0）
// 全程 double 计算、写回 float32，与 derive_link_rest_lengths 的 GDScript 版本一致。
PackedFloat32Array CellSpatial::derive_link_rest_lengths(
		const PackedFloat32Array &radius_scales,
		const PackedInt32Array &link_a, const PackedInt32Array &link_b,
		const PackedFloat32Array &link_offsets, double cell_radius,
		double gap_ratio) {
	const int link_count = link_a.size();
	PackedFloat32Array rest;
	rest.resize(link_count);
	if (link_count <= 0) {
		return rest;
	}
	const float *scales = radius_scales.ptr();
	const int scale_count = radius_scales.size();
	const int *la = link_a.ptr();
	const int *lb = link_b.ptr();
	const float *offsets = link_offsets.ptr();
	const int offset_count = link_offsets.size();
	float *out = rest.ptrw();
	const double base_radius = cell_radius;
	for (int i = 0; i < link_count; ++i) {
		const int a = la[i];
		const int b = lb[i];
		const double scale_a = (a >= 0 && a < scale_count)
				? static_cast<double>(scales[a]) : 1.0;
		const double scale_b = (b >= 0 && b < scale_count)
				? static_cast<double>(scales[b]) : 1.0;
		const double radius_a = base_radius * scale_a;
		const double radius_b = base_radius * scale_b;
		const double min_radius = radius_a < radius_b ? radius_a : radius_b;
		const double offset = (i < offset_count) ? static_cast<double>(offsets[i]) : 0.0;
		out[i] = static_cast<float>(radius_a + radius_b -
				2.0 * gap_ratio * min_radius + offset);
	}
	return rest;
}

// v0.48.0: 整场镜像查表。逐位复刻 SAMPLE_SOURCE 的索引推导：
//   normalized = (position - (center - vec2(radius))) / (2.0 * radius)
//   grid = ivec2(clamp(floor(normalized * resolution), 0, resolution - 1))
// 关键在于**全程 float32**。GDScript 的 float 是 double，而 Vector2 分量是 float32，
// `normalized.x * resolution` 在 GDScript 里会被提升成 double 乘法；resolution 为 32/64
// 这类 2 的幂时结果相同，但一旦改成非 2 的幂就会和 shader 分叉。这里统一用 float，
// 与 shader 的运算顺序和精度完全一致，因此镜像查表与 GPU dispatch 采样逐位相等。
PackedFloat32Array CellSpatial::sample_fields_nearest(const PackedFloat32Array &field_flat,
		const PackedFloat32Array &positions, int32_t resolution,
		const Vector2 &center, double radius) {
	PackedFloat32Array result;
	const int64_t position_count = positions.size() / 2;
	result.resize(position_count * CHANNEL_COUNT_FOR_SAMPLING);
	if (position_count <= 0 || resolution < 2) {
		return result;
	}
	const int64_t plane = static_cast<int64_t>(resolution) * static_cast<int64_t>(resolution);
	if (field_flat.size() < plane * CHANNEL_COUNT_FOR_SAMPLING) {
		result.resize(0);
		return result;
	}
	const float *field = field_flat.ptr();
	const float *pos = positions.ptr();
	float *out = result.ptrw();
	const float radius_f = static_cast<float>(radius);
	const float base_x = static_cast<float>(center.x) - radius_f;
	const float base_y = static_cast<float>(center.y) - radius_f;
	const float span = 2.0f * radius_f;
	const float resolution_f = static_cast<float>(resolution);
	const int max_grid = resolution - 1;
	for (int64_t i = 0; i < position_count; ++i) {
		const float normalized_x = (pos[i * 2] - base_x) / span;
		const float normalized_y = (pos[i * 2 + 1] - base_y) / span;
		int grid_x = static_cast<int>(std::floor(normalized_x * resolution_f));
		int grid_y = static_cast<int>(std::floor(normalized_y * resolution_f));
		if (grid_x < 0) {
			grid_x = 0;
		} else if (grid_x > max_grid) {
			grid_x = max_grid;
		}
		if (grid_y < 0) {
			grid_y = 0;
		} else if (grid_y > max_grid) {
			grid_y = max_grid;
		}
		const int64_t local_index = static_cast<int64_t>(grid_y) * resolution + grid_x;
		for (int channel = 0; channel < CHANNEL_COUNT_FOR_SAMPLING; ++channel) {
			out[i * CHANNEL_COUNT_FOR_SAMPLING + channel] = field[channel * plane + local_index];
		}
	}
	return result;
}

void CellSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_neighbor_csr", "pos_x", "pos_y", "alive", "cell_size"),
			&CellSpatial::build_neighbor_csr);	ClassDB::bind_method(D_METHOD("collect_inputs_batch", "energies", "alive", "types", "fields_flat", "sample_indices", "neighbor_offsets", "neighbor_values", "energy_max"),
			&CellSpatial::collect_inputs_batch);
	ClassDB::bind_method(D_METHOD("collect_inputs_grid", "pos_x", "pos_y", "energies", "alive", "types", "fields_flat", "sample_indices", "cell_size", "energy_max"),
			&CellSpatial::collect_inputs_grid);
	ClassDB::bind_method(D_METHOD("resolve_collisions", "pos_x", "pos_y", "alive", "radius_scales", "stiffnesses", "cell_radius", "cell_size", "iterations"),
			&CellSpatial::resolve_collisions);
	ClassDB::bind_method(D_METHOD("resolve_collisions_soft", "pos_x", "pos_y", "alive", "radius_scales", "stiffnesses", "cell_radius", "cell_size", "softness"),
			&CellSpatial::resolve_collisions_soft);
	ClassDB::bind_method(D_METHOD("step_verlet_and_links", "pos_x", "pos_y", "prev_x", "prev_y", "alive", "link_a", "link_b", "rest_lengths", "link_counts", "damping", "constraint_iterations", "stiffness", "harden_gain", "harden_ratio", "velocity_damping", "tear_ratio"),
			&CellSpatial::step_verlet_and_links);
	ClassDB::bind_method(D_METHOD("sample_fields_nearest", "field_flat", "positions", "resolution", "center", "radius"),
			&CellSpatial::sample_fields_nearest);
	ClassDB::bind_method(D_METHOD("derive_link_rest_lengths", "radius_scales", "link_a", "link_b", "link_offsets", "cell_radius", "gap_ratio"),
			&CellSpatial::derive_link_rest_lengths);
}
