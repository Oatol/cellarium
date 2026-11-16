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
	return {
		"valid": true,
		"a": middle + perpendicular * h,
		"b": middle - perpendicular * h,
		"normal": direction,
		"distance": s
	}

## 皿壁接触：把皿壁视作半径 dish_radius 的大圆，取与细胞圆的相交弦。
static func wall_chord(position: Vector2, radius: float, dish_center: Vector2, dish_radius: float) -> Dictionary:
	return circle_chord(position, radius, dish_center, dish_radius)

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
		return points
	return result

## 弦遮挡剔除（Cell Lab a(FFFF) 的 d26 判据）：
## d26 = cross(P18, v18) / cross(P17, v18)；0 < d26 < 1 表示弦 17 被弦 18 挡住。
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
