#include "cell_render_cache.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

constexpr double kTau = 6.283185307179586476925286766559;
constexpr int64_t kFlatKeyOffset = 1000000;
constexpr int64_t kFlatKeySpan = 2000001;

inline int64_t flat_key(int cell_x, int cell_y) {
	return (static_cast<int64_t>(cell_x) + kFlatKeyOffset) * kFlatKeySpan
		+ (static_cast<int64_t>(cell_y) + kFlatKeyOffset);
}

inline double clamp_d(double value, double lo, double hi) {
	return value < lo ? lo : (value > hi ? hi : value);
}

inline double cross2(const Vector2 &a, const Vector2 &b) {
	return static_cast<double>(a.x) * static_cast<double>(b.y)
		- static_cast<double>(a.y) * static_cast<double>(b.x);
}

PackedVector2Array unit_circle(int segments) {
	const int count = segments < 12 ? 12 : segments;
	PackedVector2Array unit;
	unit.resize(count);
	for (int index = 0; index < count; ++index) {
		const double angle = kTau * static_cast<double>(index) / static_cast<double>(count);
		unit.set(index, Vector2(static_cast<float>(std::cos(angle)), static_cast<float>(std::sin(angle))));
	}
	return unit;
}

/// Sutherland-Hodgman half-plane clip; keep the side containing the origin.
PackedVector2Array clip_keep_origin(const PackedVector2Array &points, const Vector2 &a, const Vector2 &b) {
	const Vector2 edge = b - a;
	if (edge.length_squared() < 0.00000001f) {
		return points;
	}
	const int count = points.size();
	if (count < 3) {
		return points;
	}
	const double origin_side = cross2(edge, -a);
	const bool keep_positive = origin_side >= 0.0;
	PackedVector2Array result;
	Vector2 previous = points[count - 1];
	double previous_distance = cross2(edge, previous - a);
	for (int index = 0; index < count; ++index) {
		const Vector2 current = points[index];
		const double current_distance = cross2(edge, current - a);
		const bool previous_inside = (previous_distance >= 0.0) == keep_positive;
		const bool current_inside = (current_distance >= 0.0) == keep_positive;
		if (current_inside != previous_inside) {
			const double denominator = previous_distance - current_distance;
			double t = 0.5;
			if (std::abs(denominator) >= 0.00000001) {
				t = previous_distance / denominator;
			}
			t = clamp_d(t, 0.0, 1.0);
			result.append(previous.lerp(current, static_cast<float>(t)));
		}
		if (current_inside) {
			result.append(current);
		}
		previous = current;
		previous_distance = current_distance;
	}
	if (result.size() < 3) {
		return PackedVector2Array();
	}
	return result;
}

bool circle_chord_local(const Vector2 &p0, double r0, const Vector2 &p1, double r1,
		Vector2 &out_a, Vector2 &out_b) {
	const Vector2 delta = p1 - p0;
	const double s = static_cast<double>(delta.length());
	const double epsilon = std::max(0.02, std::min(r0, r1) * 0.01);
	if (s < 0.000001 || s >= r0 + r1 - epsilon || s <= std::abs(r0 - r1) + 0.000001) {
		return false;
	}
	const Vector2 direction = delta / static_cast<float>(s);
	const double d = (s * s - r1 * r1 + r0 * r0) / (2.0 * s);
	const double h_squared = r0 * r0 - d * d;
	if (h_squared <= 0.0) {
		return false;
	}
	const Vector2 perpendicular(-direction.y, direction.x);
	const double h = std::sqrt(h_squared);
	const Vector2 middle = direction * static_cast<float>(d);
	const float inv_r0 = static_cast<float>(1.0 / r0);
	out_a = (middle - perpendicular * static_cast<float>(h)) * inv_r0;
	out_b = (middle + perpendicular * static_cast<float>(h)) * inv_r0;
	return true;
}

bool wall_chord_local(const Vector2 &p0, double r0, const Vector2 &dish_center, double dish_radius,
		Vector2 &out_a, Vector2 &out_b) {
	const Vector2 delta = dish_center - p0;
	const double s = static_cast<double>(delta.length());
	if (s < 0.000001 || dish_radius <= r0) {
		return false;
	}
	if (s + r0 <= dish_radius + std::max(0.02, r0 * 0.01)) {
		return false;
	}
	const Vector2 direction = delta / static_cast<float>(s);
	const double d = (r0 * r0 - dish_radius * dish_radius + s * s) / (2.0 * s);
	const double h_squared = r0 * r0 - d * d;
	if (h_squared <= 0.0) {
		return false;
	}
	const Vector2 perpendicular(-direction.y, direction.x);
	const double h = std::sqrt(h_squared);
	const Vector2 middle = direction * static_cast<float>(d);
	const float inv_r0 = static_cast<float>(1.0 / r0);
	out_a = (middle - perpendicular * static_cast<float>(h)) * inv_r0;
	out_b = (middle + perpendicular * static_cast<float>(h)) * inv_r0;
	return true;
}

Color hsv(double h, double s, double v) {
	h = std::fmod(h, 1.0);
	if (h < 0.0) h += 1.0;
	if (s <= 0.0) return Color(static_cast<float>(v), static_cast<float>(v), static_cast<float>(v), 1.0);
	// HSV -> RGB. Matches Godot Color.from_hsv closely enough for view-only data.
	const double c = v * s;
	const double x = c * (1.0 - std::abs(std::fmod(h * 6.0, 2.0) - 1.0));
	const double m = v - c;
	double r = 0.0, g = 0.0, b = 0.0;
	const double sector = h * 6.0;
	if (sector < 1.0) { r = c; g = x; }
	else if (sector < 2.0) { r = x; g = c; }
	else if (sector < 3.0) { g = c; b = x; }
	else if (sector < 4.0) { g = x; b = c; }
	else if (sector < 5.0) { r = x; b = c; }
	else { r = c; b = x; }
	return Color(static_cast<float>(r + m), static_cast<float>(g + m), static_cast<float>(b + m), 1.0);
}

}  // namespace

Dictionary CellRenderCache::rebuild(
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
		int max_cells) {
	Array polygons;
	Array outlines;
	PackedVector2Array centers;
	PackedFloat32Array radii;
	PackedColorArray body_colors;
	PackedColorArray outline_colors;
	PackedColorArray nucleus_colors;
	PackedVector2Array links;

	const int total = alive.size();
	const int limit = max_cells < total ? max_cells : total;
	std::vector<int> indices;
	indices.reserve(limit);
	for (int cell_index = 0; cell_index < limit; ++cell_index) {
		if (alive[cell_index] != 0) indices.push_back(cell_index);
	}

	if (!indices.empty()) {
		for (int link_index = 0; link_index < link_a.size(); ++link_index) {
			const int a = link_a[link_index];
			const int b = link_b[link_index];
			if (a < 0 || b < 0 || a >= total || b >= total) continue;
			if (alive[a] == 0 || alive[b] == 0) continue;
			links.append(Vector2(pos_x[a], pos_y[a]));
			links.append(Vector2(pos_x[b], pos_y[b]));
		}
	}

	std::unordered_map<int64_t, std::vector<int>> buckets;
	for (const int cell_index : indices) {
		const int cx = static_cast<int>(std::floor(static_cast<double>(pos_x[cell_index]) / cell_size));
		const int cy = static_cast<int>(std::floor(static_cast<double>(pos_y[cell_index]) / cell_size));
		buckets[flat_key(cx, cy)].push_back(cell_index);
	}

	const PackedVector2Array unit_circle_base = unit_circle(segments);
	const Vector2 dish_center(static_cast<float>(dish_cx), static_cast<float>(dish_cy));
	int chord_count = 0;

	for (const int cell_index : indices) {
		const Vector2 center(pos_x[cell_index], pos_y[cell_index]);
		double scale_value = 1.0;
		if (cell_index < radius_scales.size()) {
			scale_value = clamp_d(static_cast<double>(radius_scales[cell_index]), 0.5, 2.0);
		}
		const double effective_radius = std::max(1.0, base_radius * scale_value);
		PackedVector2Array unit = unit_circle_base;

		std::vector<Vector2> local_a;
		std::vector<Vector2> local_b;
		local_a.reserve(5);
		local_b.reserve(5);
		const int cx = static_cast<int>(std::floor(static_cast<double>(pos_x[cell_index]) / cell_size));
		const int cy = static_cast<int>(std::floor(static_cast<double>(pos_y[cell_index]) / cell_size));
		for (int offset_y = -1; offset_y <= 1; ++offset_y) {
			for (int offset_x = -1; offset_x <= 1; ++offset_x) {
				const auto found = buckets.find(flat_key(cx + offset_x, cy + offset_y));
				if (found == buckets.end()) continue;
				for (const int neighbor : found->second) {
					if (neighbor == cell_index || neighbor >= total || alive[neighbor] == 0) continue;
					if (local_a.size() >= 4) continue;
					double neighbor_scale = 1.0;
					if (neighbor < radius_scales.size()) {
						neighbor_scale = clamp_d(static_cast<double>(radius_scales[neighbor]), 0.5, 2.0);
					}
					const double neighbor_radius = std::max(1.0, base_radius * neighbor_scale);
					Vector2 a, b;
					if (circle_chord_local(center, effective_radius,
							Vector2(pos_x[neighbor], pos_y[neighbor]), neighbor_radius, a, b)) {
						local_a.push_back(a);
						local_b.push_back(b);
					}
				}
			}
		}
		Vector2 wall_a, wall_b;
		if (local_a.size() < 4 && wall_chord_local(center, effective_radius, dish_center, dish_radius, wall_a, wall_b)) {
			local_a.push_back(wall_a);
			local_b.push_back(wall_b);
		}
		chord_count += static_cast<int>(local_a.size());
		for (size_t chord_index = 0; chord_index < local_a.size(); ++chord_index) {
			const PackedVector2Array clipped = clip_keep_origin(unit, local_a[chord_index], local_b[chord_index]);
			if (clipped.size() >= 3) unit = clipped;
		}

		PackedVector2Array polygon;
		PackedVector2Array outline;
		polygon.resize(unit.size());
		outline.resize(unit.size());
		for (int point_index = 0; point_index < unit.size(); ++point_index) {
			const Vector2 world_point = center + unit[point_index] * static_cast<float>(effective_radius);
			polygon.set(point_index, world_point);
			outline.set(point_index, world_point);
		}
		if (polygon.size() < 3) continue;

		const int type_id = cell_index < cell_type.size() ? static_cast<int>(cell_type[cell_index]) : 0;
		const int org_id = cell_index < cell_org_id.size() ? cell_org_id[cell_index] : 0;
		const double energy = cell_index < cell_energy.size() ? static_cast<double>(cell_energy[cell_index]) : 0.0;
		const double vitality = clamp_d(energy / 1.2, 0.35, 1.0);
		Color base_color(-1.0f, -1.0f, -1.0f, 1.0f);
		if (cell_index < color_r.size() && cell_index < color_g.size() && cell_index < color_b.size()
				&& static_cast<double>(color_r[cell_index]) >= 0.0) {
			base_color = Color(color_r[cell_index], color_g[cell_index], color_b[cell_index], 1.0f);
		}
		if (base_color.r < 0.0f) {
			double type_hue = std::fmod(static_cast<double>(type_id) * 0.137 + 0.42, 1.0);
			if (type_hue < 0.0) type_hue += 1.0;
			base_color = hsv(type_hue, 0.42, 0.92);
			double org_hue = std::fmod(static_cast<double>(org_id) * 0.173 + 0.42, 1.0);
			if (org_hue < 0.0) org_hue += 1.0;
			const Color org_tint = hsv(org_hue, 0.34, 0.95);
			base_color = base_color.lerp(org_tint, 0.16f);
		}

		polygons.append(polygon);
		outlines.append(outline);
		centers.append(center);
		radii.append(static_cast<float>(effective_radius));
		body_colors.append(Color(base_color.r, base_color.g, base_color.b,
				static_cast<float>(0.30 * vitality + 0.10)));
		outline_colors.append(Color(std::min(static_cast<double>(base_color.r) * 1.35, 1.0),
				std::min(static_cast<double>(base_color.g) * 1.35, 1.0),
				std::min(static_cast<double>(base_color.b) * 1.35, 1.0), 0.95));
		nucleus_colors.append(Color(0.08f, 0.16f, 0.15f, static_cast<float>(0.85 * vitality)));
	}

	Dictionary result;
	result["polygons"] = polygons;
	result["outlines"] = outlines;
	result["centers"] = centers;
	result["radii"] = radii;
	result["body_colors"] = body_colors;
	result["outline_colors"] = outline_colors;
	result["nucleus_colors"] = nucleus_colors;
	result["links"] = links;
	result["active_count"] = polygons.size();
	result["chord_count"] = chord_count;
	return result;
}

void CellRenderCache::_bind_methods() {
	ClassDB::bind_method(D_METHOD("rebuild", "alive", "pos_x", "pos_y", "radius_scales",
			"cell_type", "cell_org_id", "color_r", "color_g", "color_b", "cell_energy",
			"link_a", "link_b", "base_radius", "dish_cx", "dish_cy", "dish_radius",
			"cell_size", "segments", "max_cells"),
			&CellRenderCache::rebuild);
}
