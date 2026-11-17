extends RefCounted
## 接触弦几何：Cell Lab「物理与渲染共享同一组圆-圆相交弦端点」机制的 Godot 复刻。
## 纯静态工具，无 class_name、不写模拟状态、不参与确定性 hash。
## Concept from Cell Lab CellWorld.d(int) / a(FFFF); implementation is independent.

const MAX_CHORDS: int = 20

## 两圆相交弦。返回世界坐标端点 a/b，以及从 p0 指向 p1 的法线。
## 与 Cell Lab 的 d51/d54..d56 等价：d = (s² - r1² + r0²)/(2s)，h = sqrt(r0² - d²)。
static func circle_chord(p0: Vector2, r0: float, p1: Vector2, r1: float) -> Dictionary:
	var delta: Vector2 = p1 - p0
	var s: float = delta.length()
	if s < 0.000001:
		return {"valid": false}
	if s >= r0 + r1 - 0.000001:
		return {"valid": false}
	if s <= absf(r0 - r1) + 0.000001:
		return {"valid": false}
	var direction: Vector2 = delta / s
	var d: float = (s * s - r1 * r1 + r0 * r0) / (2.0 * s)
	var h_squared: float = r0 * r0 - d * d
	if h_squared <= 0.0:
		return {"valid": false}
	var middle: Vector2 = p0 + direction * d
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var h: float = sqrt(h_squared)
	# Cell Lab d(int) 的端点顺序：endpoint1 = middle - perp*h，endpoint2 = middle + perp*h。
	# 与 A[] 的 a/b/c/d 顺序保持一致，后续排序与圆弧重建才能稳定。
	return {
		"valid": true,
		"a": middle - perpendicular * h,
		"b": middle + perpendicular * h,
		"normal": direction,
		"distance": s
	}

## 皿壁接触：把皿壁视作半径 dish_radius 的大圆，取细胞圆在大圆内侧的相交弦。
## 小圆在包含它的大圆内部时，普通 circle_chord() 的 containment 检查会误判为无交，
## 这里单独推导：d = (r² − R² + s²)/(2s)，s > R − r 才接触。
static func wall_chord(position: Vector2, radius: float, dish_center: Vector2, dish_radius: float) -> Dictionary:
	var delta: Vector2 = dish_center - position
	var s: float = delta.length()
	if s < 0.000001 or dish_radius <= radius:
		return {"valid": false}
	if s + radius <= dish_radius + 0.000001:
		return {"valid": false}
	var direction: Vector2 = delta / s
	var d: float = (radius * radius - dish_radius * dish_radius + s * s) / (2.0 * s)
	var h_squared: float = radius * radius - d * d
	if h_squared <= 0.0:
		return {"valid": false}
	var middle: Vector2 = position + direction * d
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var h: float = sqrt(h_squared)
	return {
		"valid": true,
		"a": middle - perpendicular * h,
		"b": middle + perpendicular * h,
		"normal": -direction,
		"distance": s
	}

static func cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x

## Sutherland-Hodgman 半平面裁剪：保留包含原点（细胞中心）的一侧。
## 弦端点 a/b 必须是局部坐标（世界端点减去细胞中心）。
static func clip_keep_origin(
	points: PackedVector2Array,
	a: Vector2,
	b: Vector2
) -> PackedVector2Array:
	var edge: Vector2 = b - a
	if edge.length_squared() < 0.00000001:
		return points
	var count: int = points.size()
	if count < 3:
		return points
	var origin_side: float = cross2(edge, -a)
	var keep_positive: bool = origin_side >= 0.0
	var result: PackedVector2Array = PackedVector2Array()
	var previous: Vector2 = points[count - 1]
	var previous_distance: float = cross2(edge, previous - a)
	for index in range(count):
		var current: Vector2 = points[index]
		var current_distance: float = cross2(edge, current - a)
		var previous_inside: bool = (previous_distance >= 0.0) == keep_positive
		var current_inside: bool = (current_distance >= 0.0) == keep_positive
		if current_inside != previous_inside:
			var denominator: float = previous_distance - current_distance
			var t: float = 0.5 if absf(denominator) < 0.00000001 else previous_distance / denominator
			result.append(previous.lerp(current, clampf(t, 0.0, 1.0)))
		if current_inside:
			result.append(current)
		previous = current
		previous_distance = current_distance
	if result.size() < 3:
		# 退化时返回空多边形，而不是"未裁剪输入"：后者会让轮廓在下一帧突然
		# 跳回整圆，形成"多边形→消失→重建"的视觉循环。调用方负责跳过该弦。
		return PackedVector2Array()
	return result

## 弦遮挡剔除（Cell Lab a(FFFF) 的 d26 判据）：
## d22 = P17.x，d23 = P18.x − Q18.x = −v.x，d24 = P17.y，d25 = P18.y − Q18.y = −v.y；
## d26 = (d25·P18.x − d23·P18.y)/(d22·d25 − d24·d23)
##     = cross(P18, v) / cross(P17, v)，0 < d26 < 1 表示弦 17 被弦 18 挡住。
static func is_occluded(chord: Dictionary, other: Dictionary) -> bool:
	var p_a: Vector2 = chord.get("local_a", Vector2.ZERO)
	var p_b: Vector2 = chord.get("local_b", Vector2.ZERO)
	var q_a: Vector2 = other.get("local_a", Vector2.ZERO)
	var q_b: Vector2 = other.get("local_b", Vector2.ZERO)
	var v_q: Vector2 = q_b - q_a
	var denominator: float = cross2(p_a, v_q)
	if absf(denominator) < 0.00000001:
		return false
	var numerator: float = cross2(q_a, v_q)
	var d26: float = numerator / denominator
	return d26 > 0.0 and d26 < 1.0

## 剔除被遮挡的弦；输入是已带 local_a/local_b 的 Dictionary 数组，顺序稳定。
static func cull_occluded(chords: Array) -> Array:
	var kept: Array = []
	for index in range(chords.size()):
		var chord: Dictionary = chords[index]
		var occluded: bool = false
		for other_index in range(chords.size()):
			if other_index == index:
				continue
			if is_occluded(chord, chords[other_index]):
				occluded = true
				break
		if not occluded:
			kept.append(chord)
	return kept

## 把世界端点转成 Cell Lab A[] 风格的局部端点。
## 半径取两端点到中心距离的平均，保证即使 visual_radius 与物理半径不同，
## 弦端点仍落在重建轮廓的单位圆上；angle 用于撤销速度拉伸造成的视觉旋转。
static func make_unit_chords(
	world_chords: Array,
	center: Vector2,
	angle: float,
	fallback_radius: float
) -> Array:
	var result: Array = []
	for item in world_chords:
		var endpoint_a: Vector2 = (item.get("a", Vector2.ZERO) - center).rotated(-angle)
		var endpoint_b: Vector2 = (item.get("b", Vector2.ZERO) - center).rotated(-angle)
		var length_a: float = endpoint_a.length()
		var length_b: float = endpoint_b.length()
		var chord_radius: float = (length_a + length_b) * 0.5
		if chord_radius < 0.000001:
			chord_radius = maxf(0.0001, fallback_radius)
		result.append({
			"local_a": endpoint_a / chord_radius,
			"local_b": endpoint_b / chord_radius,
			"kind": int(item.get("kind", 0)),
			"peer": int(item.get("peer", -1)),
			"occluded": false,
			"truncated": false
		})
	return result

## Cell Lab a(FFFF) 第一层：两弦内部相交时截断端点。
## 与 d15/d16 参数判据等价，d17 符号决定保留哪一侧；只改视图数据，不写模拟状态。
static func truncate_intersections(chords: Array) -> void:
	var count: int = chords.size()
	for index in range(count):
		var current: Dictionary = chords[index]
		if bool(current.get("occluded", false)):
			continue
		for offset in range(1, count):
			var other_index: int = (index + offset) % count
			var other: Dictionary = chords[other_index]
			if bool(other.get("occluded", false)):
				continue
			var p_i: Vector2 = current.get("local_a", Vector2.ZERO)
			var q_i: Vector2 = current.get("local_b", Vector2.ZERO)
			var p_j: Vector2 = other.get("local_a", Vector2.ZERO)
			var q_j: Vector2 = other.get("local_b", Vector2.ZERO)
			var v_i: Vector2 = q_i - p_i
			var v_j: Vector2 = q_j - p_j
			var denominator: float = cross2(v_i, v_j)
			if absf(denominator) < 0.000000001:
				continue
			var delta: Vector2 = p_j - p_i
			var t: float = cross2(delta, v_j) / denominator
			var s: float = cross2(delta, v_i) / denominator
			if t <= 0.0 or t >= 1.0 or s <= 0.0 or s >= 1.0:
				continue
			var intersection: Vector2 = p_i + v_i * t
			# CellLab d17 = cross(v16, Q14−P16)，与原实现同号，条件 d17 < 0 保留 Cell Lab 分支。
			var d17: float = cross2(v_j, q_i - p_j)
			if d17 < 0.0:
				current["local_b"] = intersection
				other["local_a"] = intersection
				current["truncated"] = true
			else:
				current["local_a"] = intersection
				other["local_b"] = intersection
				other["truncated"] = true
			if cross2(current["local_a"], current["local_b"]) < 0.0:
				current["occluded"] = true
			if cross2(other["local_a"], other["local_b"]) < 0.0:
				other["occluded"] = true

## Cell Lab a(FFFF) 第二层：d26 遮挡标记，带端点重合剔除。
static func mark_occluded(chords: Array) -> void:
	var count: int = chords.size()
	for index in range(count):
		var current: Dictionary = chords[index]
		if bool(current.get("occluded", false)):
			continue
		var p_i: Vector2 = current.get("local_a", Vector2.ZERO)
		var q_i: Vector2 = current.get("local_b", Vector2.ZERO)
		for other_index in range(count):
			if other_index == index:
				continue
			var other: Dictionary = chords[other_index]
			if bool(other.get("occluded", false)):
				continue
			var p_j: Vector2 = other.get("local_a", Vector2.ZERO)
			var q_j: Vector2 = other.get("local_b", Vector2.ZERO)
			# Cell Lab 的端点重合条件：P17 == Q18 或 Q17 == P18；任一成立就跳过该对。
			if p_i == q_j or q_i == p_j:
				continue
			var v_j: Vector2 = q_j - p_j
			var denominator: float = cross2(p_i, v_j)
			if absf(denominator) < 0.000000001:
				continue
			# CellLab d26 = cross(P18, v18)/cross(P17, v18)，有效区间 (0, 1)。
			var d26: float = cross2(p_j, v_j) / denominator
			if d26 > 0.0 and d26 < 1.0:
				current["occluded"] = true
				break

## u.compareTo() 的 Godot 等价：剔除弦置末，其余按 Cell Lab 的 a/b 斜率键排序
## （等价于极角 atan2(b,a) 在 [0,2π) 升序）。返回 true 表示 left 应排在 right 前。
static func chord_less(left: Dictionary, right: Dictionary) -> bool:
	var left_hidden: bool = bool(left.get("occluded", false))
	var right_hidden: bool = bool(right.get("occluded", false))
	if left_hidden and right_hidden:
		return false
	if left_hidden:
		return false
	if right_hidden:
		return true
	var p_left: Vector2 = left.get("local_a", Vector2.ZERO)
	var p_right: Vector2 = right.get("local_a", Vector2.ZERO)
	if p_right.y * p_left.y < 0.0:
		return p_left.y > 0.0
	return p_right.y * p_left.x > p_left.y * p_right.x

static func sort_chords(chords: Array) -> Array:
	var sorted_chords: Array = chords.duplicate()
	for index in range(1, sorted_chords.size()):
		var value: Dictionary = sorted_chords[index]
		var cursor: int = index - 1
		while cursor >= 0:
			var previous: Dictionary = sorted_chords[cursor]
			if not chord_less(value, previous):
				break
			sorted_chords[cursor + 1] = previous
			cursor -= 1
		sorted_chords[cursor + 1] = value
	return sorted_chords

## 按 Cell Lab 的固定顺序：规范输入顺序 → 相交截断 → 遮挡剔除 → 排序。
## Cell Lab 的 A[] 按邻居索引升序写入；这里把空间哈希给出的邻居顺序规范到
## (kind, peer) 升序，避免邻居遍历顺序改变截断结果。
static func prepare_for_render(chords: Array) -> Array:
	var ordered: Array = chords.duplicate()
	for index in range(1, ordered.size()):
		var value: Dictionary = ordered[index]
		var cursor: int = index - 1
		while cursor >= 0:
			var previous: Dictionary = ordered[cursor]
			if not _input_less(value, previous):
				break
			ordered[cursor + 1] = previous
			cursor -= 1
		ordered[cursor + 1] = value
	truncate_intersections(ordered)
	mark_occluded(ordered)
	var kept: Array = []
	for chord in ordered:
		if bool(chord.get("occluded", false)):
			continue
		var endpoint_a: Vector2 = chord.get("local_a", Vector2.ZERO)
		var endpoint_b: Vector2 = chord.get("local_b", Vector2.ZERO)
		if endpoint_a.distance_squared_to(endpoint_b) < 0.0000000001:
			continue
		kept.append(chord)
	return sort_chords(kept)

static func _input_less(left: Dictionary, right: Dictionary) -> bool:
	var left_kind: int = int(left.get("kind", 0))
	var right_kind: int = int(right.get("kind", 0))
	if left_kind != right_kind:
		return left_kind < right_kind
	return int(left.get("peer", -1)) < int(right.get("peer", -1))

static func polygon_area(points: PackedVector2Array) -> float:
	var count: int = points.size()
	if count < 3:
		return 0.0
	var total: float = 0.0
	for index in range(count):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % count]
		total += current.x * following.y - following.x * current.y
	return absf(total) * 0.5

static func contains_origin(points: PackedVector2Array) -> bool:
	var count: int = points.size()
	var inside: bool = false
	for index in range(count):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % count]
		if ((current.y > 0.0) != (following.y > 0.0)) and (
			0.0 < (following.x - current.x) * (0.0 - current.y) / (following.y - current.y) + current.x
		):
			inside = not inside
	return inside

static func canonicalize_points(points: PackedVector2Array) -> PackedVector2Array:
	var unique: Array[Vector2] = []
	for point in points:
		var duplicate: bool = false
		for existing in unique:
			if point.distance_squared_to(existing) < 0.0000000001:
				duplicate = true
				break
		if not duplicate:
			unique.append(point)
	unique.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var angle_a: float = atan2(a.y, a.x)
		var angle_b: float = atan2(b.y, b.x)
		if absf(angle_a - angle_b) < 0.0000001:
			return a.length_squared() < b.length_squared()
		return angle_a < angle_b
	)
	var result: PackedVector2Array = PackedVector2Array()
	for point in unique:
		result.append(point)
	return result

## 解析单位圆：作为所有细胞外膜的统一基底，避免与 12 点呼吸膜互相切换。
static func unit_circle(segments: int = 64) -> PackedVector2Array:
	var count: int = maxi(12, segments)
	var unit: PackedVector2Array = PackedVector2Array()
	for index in range(count):
		var angle_value: float = TAU * float(index) / float(count)
		unit.append(Vector2(cos(angle_value), sin(angle_value)))
	return unit

## 退化保护：用解析单位圆作为基底逐条半平面裁剪，结果再按极角规范化。
## 不再在弦端点被截成同一点时回退到另一套点集，保证轮廓点数与拓扑稳定。
static func clip_unit_circle(chords: Array, segments: int = 64) -> PackedVector2Array:
	var unit: PackedVector2Array = unit_circle(segments)
	for chord in chords:
		var clipped: PackedVector2Array = clip_keep_origin(
			unit, chord.get("local_a", Vector2.ZERO), chord.get("local_b", Vector2.ZERO)
		)
		# 数值退化弦直接跳过，保持上一帧有效的凸多边形；空轮廓绝不写回视图。
		if clipped.size() >= 3:
			unit = clipped
	return canonicalize_points(unit)

## 用弦端点 + 单位圆弧重建轮廓，替代「呼吸膜 + 顺序相关半平面裁剪」。
## 弦段本身作为边界，非截断弦之后补解析圆弧，因此接触点不会随相位或裁剪顺序跳动。
static func build_outline(chords: Array, arc_steps: int = 3) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var count: int = chords.size()
	if count == 0:
		return result
	var steps: int = maxi(1, arc_steps)
	for index in range(count):
		var current: Dictionary = chords[index]
		var endpoint_a: Vector2 = current.get("local_a", Vector2.ZERO)
		var endpoint_b: Vector2 = current.get("local_b", Vector2.ZERO)
		result.append(endpoint_a)
		result.append(endpoint_b)
		# Cell Lab 用 A[i].f 标记被截断的弦并跳过其圆弧插值；
		# 这里改为直线连到下一端点，Polygon2D/Line2D 才能保持闭合轮廓。
		if bool(current.get("truncated", false)):
			continue
		var next: Dictionary = chords[(index + 1) % count]
		var next_a: Vector2 = next.get("local_a", Vector2.ZERO)
		if endpoint_b.distance_squared_to(next_a) < 0.0000000001:
			continue
		var cross_value: float = endpoint_b.x * next_a.y - next_a.x * endpoint_b.y
		var start_angle: float = atan2(endpoint_b.y, endpoint_b.x)
		var end_angle: float = atan2(next_a.y, next_a.x)
		var span: float = fposmod(end_angle - start_angle, TAU)
		if span < 0.00001:
			continue
		var arc_count: int = 4 if cross_value <= 0.0 else steps
		for step in range(1, arc_count + 1):
			var ratio: float = float(step) / float(arc_count + 1)
			var angle_value: float = start_angle + span * ratio
			result.append(Vector2(cos(angle_value), sin(angle_value)))
	# 多接触深度重叠时，Cell Lab 的 f 标记会让所有圆弧被跳过；其三角形扇仍可渲染，
	# 但 Polygon2D 需要闭合顶点。这里检测退化并回退到解析圆半平面裁剪。
	if result.size() < 3 or polygon_area(result) < 0.02 or not contains_origin(result):
		return clip_unit_circle(chords)
	return result
