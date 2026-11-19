extends SceneTree
## v0.34.0 parity gate for CellSpatial.step_verlet_and_links:
## exact port of CellPhysics.step + _solve_links, compared element-by-element.

const N: int = 500
const LINK_COUNT: int = 450
const DAMPING: float = 0.98
const ITERATIONS: int = 2

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
	pos_x.resize(N); pos_y.resize(N); prev_x.resize(N); prev_y.resize(N); alive.resize(N)
	for i in range(N):
		pos_x[i] = rng.randf_range(-120.0, 120.0)
		pos_y[i] = rng.randf_range(-120.0, 120.0)
		prev_x[i] = pos_x[i] - rng.randf_range(-2.0, 2.0)
		prev_y[i] = pos_y[i] - rng.randf_range(-2.0, 2.0)
		alive[i] = 1 if rng.randi_range(0, 9) != 0 else 0
	for i in range(LINK_COUNT):
		link_a.append(rng.randi_range(0, N - 1))
		link_b.append(rng.randi_range(0, N - 1))
		rest.append(rng.randf_range(6.0, 18.0))

	var native: Dictionary = cpp.call("step_verlet_and_links", pos_x, pos_y, prev_x, prev_y,
		alive, link_a, link_b, rest, DAMPING, ITERATIONS) as Dictionary
	var reference: Dictionary = _reference_step(pos_x, pos_y, prev_x, prev_y,
		alive, link_a, link_b, rest, DAMPING, ITERATIONS)
	for key in ["pos_x", "pos_y", "prev_x", "prev_y"]:
		_compare(key, native[key], reference[key])
	print("PHYSICS_STEP_PARITY: checked=%d failures=%d" % [checked, failures])
	print("PHYSICS_STEP_PARITY: %s" % ["OK" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)

func _reference_step(pos_x: PackedFloat32Array, pos_y: PackedFloat32Array,
		prev_x: PackedFloat32Array, prev_y: PackedFloat32Array, alive: PackedByteArray,
		link_a: PackedInt32Array, link_b: PackedInt32Array, rest: PackedFloat32Array,
		damping: float, iterations: int) -> Dictionary:
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
	for iteration in range(iterations):
		for link_index in range(link_a.size()):
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
			var correction: float = (distance - float(rest[link_index])) / distance
			var half: float = correction * 0.5
			next_pos_x[a] = float(next_pos_x[a]) + dx * half
			next_pos_y[a] = float(next_pos_y[a]) + dy * half
			next_pos_x[b] = float(next_pos_x[b]) - dx * half
			next_pos_y[b] = float(next_pos_y[b]) - dy * half
	return {"pos_x": next_pos_x, "pos_y": next_pos_y,
		"prev_x": next_prev_x, "prev_y": next_prev_y}

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
