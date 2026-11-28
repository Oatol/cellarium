extends SceneTree
## v0.34.0 parity gate for CellSpatial.step_verlet_and_links:
## exact port of CellPhysics.step + _solve_links, compared element-by-element.
## v0.52.1：连接求解换成软弹簧 + 端点速度阻尼，本探针同步到新签名与新算法。

const N: int = 500
const LINK_COUNT: int = 450
const DAMPING: float = 0.98
const ITERATIONS: int = 2
const LINK_STIFFNESS: float = 0.55
const LINK_HARDEN_GAIN: float = 2.0
const LINK_HARDEN_RATIO: float = 2.5
const LINK_VELOCITY_DAMPING: float = 0.12
const LINK_TEAR_RATIO: float = 2.4

var failures: int = 0
var checked: int = 0

func _initialize() -> void:
	if not ClassDB.class_exists("CellSpatial"):
		print("PHYSICS_STEP_PARITY: SKIP (CellSpatial not registered)")
		quit(0)
		return
	var cpp: RefCounted = ClassDB.instantiate("CellSpatial") as RefCounted
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 31415926
	var pos_x: PackedFloat32Array = PackedFloat32Array()
	var pos_y: PackedFloat32Array = PackedFloat32Array()
	var prev_x: PackedFloat32Array = PackedFloat32Array()
	var prev_y: PackedFloat32Array = PackedFloat32Array()
	var alive: PackedByteArray = PackedByteArray()
	var link_a: PackedInt32Array = PackedInt32Array()
	var link_b: PackedInt32Array = PackedInt32Array()
	var rest: PackedFloat32Array = PackedFloat32Array()
	var link_counts: PackedByteArray = PackedByteArray()
	pos_x.resize(N); pos_y.resize(N); prev_x.resize(N); prev_y.resize(N); alive.resize(N)
	for i in range(N):
		pos_x[i] = rng.randf_range(-120.0, 120.0)
		pos_y[i] = rng.randf_range(-120.0, 120.0)
		prev_x[i] = pos_x[i] - rng.randf_range(-2.0, 2.0)
		prev_y[i] = pos_y[i] - rng.randf_range(-2.0, 2.0)
		alive[i] = 1 if rng.randi_range(0, 9) != 0 else 0
		# 连接数分摊是软弹簧的一部分，必须覆盖 1..4 与 0 边界。
		link_counts.append(rng.randi_range(0, 4))
	for i in range(LINK_COUNT):
		link_a.append(rng.randi_range(0, N - 1))
		link_b.append(rng.randi_range(0, N - 1))
		rest.append(rng.randf_range(6.0, 18.0))

	var native: Dictionary = cpp.call("step_verlet_and_links", pos_x, pos_y, prev_x, prev_y,
		alive, link_a, link_b, rest, link_counts, DAMPING, ITERATIONS,
		LINK_STIFFNESS, LINK_HARDEN_GAIN, LINK_HARDEN_RATIO, LINK_VELOCITY_DAMPING,
		LINK_TEAR_RATIO) as Dictionary
	var reference: Dictionary = _reference_step(pos_x, pos_y, prev_x, prev_y,
		alive, link_a, link_b, rest, link_counts, DAMPING, ITERATIONS)
	for key in ["pos_x", "pos_y", "prev_x", "prev_y"]:
		_compare(key, native[key], reference[key])
	_compare_indices("break_links", native["break_links"], reference["break_links"])
	print("PHYSICS_STEP_PARITY: checked=%d failures=%d" % [checked, failures])
	print("PHYSICS_STEP_PARITY: %s" % ["OK" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)

func _reference_step(pos_x: PackedFloat32Array, pos_y: PackedFloat32Array,
		prev_x: PackedFloat32Array, prev_y: PackedFloat32Array, alive: PackedByteArray,
		link_a: PackedInt32Array, link_b: PackedInt32Array, rest: PackedFloat32Array,
		link_counts: PackedByteArray, damping: float, iterations: int) -> Dictionary:
	var next_pos_x: PackedFloat32Array = pos_x.duplicate()
	var next_pos_y: PackedFloat32Array = pos_y.duplicate()
	var next_prev_x: PackedFloat32Array = prev_x.duplicate()
	var next_prev_y: PackedFloat32Array = prev_y.duplicate()
	for i in range(alive.size()):
		if alive[i] == 0:
			continue
		var x: float = float(next_pos_x[i])
		var y: float = float(next_pos_y[i])
		var vx: float = x - float(next_prev_x[i])
		var vy: float = y - float(next_prev_y[i])
		next_prev_x[i] = x
		next_prev_y[i] = y
		next_pos_x[i] = x + vx * damping
		next_pos_y[i] = y + vy * damping
	var link_total: int = link_a.size()
	var broken: PackedInt32Array = PackedInt32Array()
	for iteration in range(iterations):
		for link_index in range(link_total):
			var a: int = int(link_a[link_index])
			var b: int = int(link_b[link_index])
			if a < 0 or b < 0 or a >= alive.size() or b >= alive.size() \
				or alive[a] == 0 or alive[b] == 0:
				continue
			var dx: float = float(next_pos_x[b]) - float(next_pos_x[a])
			var dy: float = float(next_pos_y[b]) - float(next_pos_y[a])
			var distance: float = sqrt(dx * dx + dy * dy)
			if distance <= 0.000001:
				continue
			var rest_length: float = float(rest[link_index])
			var delta: float = distance - rest_length
			var feature: float = LINK_HARDEN_RATIO * maxf(rest_length, 0.000001)
			var hard: float = 1.0 + LINK_HARDEN_GAIN * (delta * delta) / (feature * feature)
			var count_a: int = int(link_counts[a]) if a < link_counts.size() else 1
			var count_b: int = int(link_counts[b]) if b < link_counts.size() else 1
			var share: float = 1.0 / float(maxi(1, maxi(count_a, count_b)))
			var k: float = minf(LINK_STIFFNESS * hard * share, 0.9)
			var inverse: float = 1.0 / distance
			var nx: float = dx * inverse
			var ny: float = dy * inverse
			var correction: float = delta * k * 0.5
			next_pos_x[a] = float(next_pos_x[a]) + nx * correction
			next_pos_y[a] = float(next_pos_y[a]) + ny * correction
			next_pos_x[b] = float(next_pos_x[b]) - nx * correction
			next_pos_y[b] = float(next_pos_y[b]) - ny * correction
	for link_index in range(link_total):
		var a: int = int(link_a[link_index])
		var b: int = int(link_b[link_index])
		if a < 0 or b < 0 or a >= alive.size() or b >= alive.size() \
			or alive[a] == 0 or alive[b] == 0:
			continue
		var dx: float = float(next_pos_x[b]) - float(next_pos_x[a])
		var dy: float = float(next_pos_y[b]) - float(next_pos_y[a])
		var distance: float = sqrt(dx * dx + dy * dy)
		if distance <= 0.000001:
			continue
		var rest_length: float = float(rest[link_index])
		if LINK_TEAR_RATIO > 0.0 and rest_length > 0.000001 and distance > LINK_TEAR_RATIO * rest_length:
			broken.append(link_index)
			continue
		var inverse: float = 1.0 / distance
		var nx: float = dx * inverse
		var ny: float = dy * inverse
		var rel_vx: float = (float(next_pos_x[b]) - float(next_prev_x[b])) - (float(next_pos_x[a]) - float(next_prev_x[a]))
		var rel_vy: float = (float(next_pos_y[b]) - float(next_prev_y[b])) - (float(next_pos_y[a]) - float(next_prev_y[a]))
		var along: float = (rel_vx * nx + rel_vy * ny) * LINK_VELOCITY_DAMPING * 0.5
		next_pos_x[a] = float(next_pos_x[a]) + nx * along
		next_pos_y[a] = float(next_pos_y[a]) + ny * along
		next_pos_x[b] = float(next_pos_x[b]) - nx * along
		next_pos_y[b] = float(next_pos_y[b]) - ny * along
	return {"pos_x": next_pos_x, "pos_y": next_pos_y,
		"prev_x": next_prev_x, "prev_y": next_prev_y, "break_links": broken}

func _compare_indices(key: String, cpp: PackedInt32Array, reference: PackedInt32Array) -> void:
	checked += 1
	if cpp.size() != reference.size():
		failures += 1
		print("PHYSICS_STEP_PARITY: FAIL %s size %d/%d" % [key, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("PHYSICS_STEP_PARITY: FAIL %s[%d] cpp=%d ref=%d" % [key, i, cpp[i], reference[i]])
	print("PHYSICS_STEP_PARITY: %s count=%d" % [key, cpp.size()])

func _compare(key: String, cpp: PackedFloat32Array, reference: PackedFloat32Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("PHYSICS_STEP_PARITY: FAIL %s size %d/%d" % [key, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("PHYSICS_STEP_PARITY: FAIL %s[%d] cpp=%.9f ref=%.9f" % [key, i, cpp[i], reference[i]])
