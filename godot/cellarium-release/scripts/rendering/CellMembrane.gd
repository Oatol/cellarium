extends RefCounted
## 弹性膜形态数据：12 控制点 → Catmull-Rom 闭合曲线 → 3 谐波扰动。
## 从 Cell Lab 弹性膜概念借鉴，按 v4 规格与旧工程 CellMorphology.gd 重新实现；
## 不复制 APK 源码，不写模拟状态，纯视图派生数据。
## 形态只由签名（org_id/type_id 派生）与视图时间决定，同输入必同轮廓。

const CONTROL_POINTS: int = 12
const BEZIER_SAMPLES: int = 6
const HARMONICS: Array[int] = [2, 3, 5]

var signature: int = 1
var control_radii: Array[float] = []
var harmonic_amp: Array[float] = []
var harmonic_phase: Array[float] = []
var harmonic_speed: Array[float] = []

func _init(signature_value: int = 1) -> void:
	signature = maxi(1, absi(signature_value))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = signature
	for i in range(CONTROL_POINTS):
		control_radii.append(1.0 + rng.randf_range(-0.022, 0.022))
	for _k in range(HARMONICS.size()):
		harmonic_amp.append(rng.randf_range(0.008, 0.022))
		harmonic_phase.append(rng.randf_range(0.0, TAU))
		harmonic_speed.append(rng.randf_range(0.7, 1.7))

static func make_signature(org_id: int, type_id: int) -> int:
	var h: int = 2166136261
	for value in [maxi(org_id, 0), maxi(type_id, 0), 0x5A]:
		h = (h ^ (value & 255)) * 16777619 & 0x7fffffff
		h = (h ^ ((value >> 8) & 255)) * 16777619 & 0x7fffffff
	return maxi(h, 1)

## 单位半径控制点：谐波呼吸 + 沿运动轴拉伸（x 方向）。
func control_points(t: float, stretch: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var amount: float = clampf(stretch, 0.0, 0.35)
	for i in range(CONTROL_POINTS):
		var angle: float = TAU * float(i) / float(CONTROL_POINTS)
		var wobble: float = 0.0
		for k in range(HARMONICS.size()):
			wobble += harmonic_amp[k] * sin(
				float(HARMONICS[k]) * angle + t * harmonic_speed[k] + harmonic_phase[k]
			)
		var radius: float = control_radii[i] * (1.0 + wobble)
		points.append(Vector2(
			cos(angle) * radius * (1.0 + amount),
			sin(angle) * radius * (1.0 - 0.65 * amount)
		))
	return points

## Catmull-Rom 闭合曲线采样，得到 72 点平滑轮廓。
func outline(t: float, stretch: float) -> PackedVector2Array:
	var control: PackedVector2Array = control_points(t, stretch)
	var count: int = control.size()
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(count):
		var p0: Vector2 = control[i]
		var p1: Vector2 = control[(i + 1) % count]
		var previous: Vector2 = control[(i - 1 + count) % count]
		var next: Vector2 = control[(i + 2) % count]
		var b1: Vector2 = p0 + (p1 - previous) / 6.0
		var b2: Vector2 = p1 - (next - p0) / 6.0
		for sample in range(BEZIER_SAMPLES):
			result.append(_cubic(p0, b1, b2, p1, float(sample) / float(BEZIER_SAMPLES)))
	return result

## 单位圆点 → 贴图 UV（纹理像素坐标）。
func texture_uv(points: PackedVector2Array, texture_size: Vector2) -> PackedVector2Array:
	var uv: PackedVector2Array = PackedVector2Array()
	for point in points:
		uv.append((point * 0.5 + Vector2(0.5, 0.5)) * texture_size)
	return uv

static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
