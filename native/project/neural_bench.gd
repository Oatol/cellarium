extends SceneTree
## P1 micro-benchmark: pure neural inference throughput, C++ batch vs GDScript.
## Isolates evaluate only (no field sampling / neighbor collection).

const BEHAVIOR: Script = preload("res://cell_behavior.gd")
const ITERS: int = 200
const N: int = 3000
const IN: int = 8
const OUT: int = 6
const W: int = 56

func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var inputs_flat: PackedFloat32Array = PackedFloat32Array()
	inputs_flat.resize(N * IN)
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(N * W)
	var alive: PackedByteArray = PackedByteArray()
	alive.resize(N)
	for i in range(N * IN):
		inputs_flat[i] = rng.randf_range(-1.0, 1.0)
	for i in range(N * W):
		weights[i] = rng.randf_range(-0.25, 0.25)
	for i in range(N):
		alive[i] = 1

	var cpp = ClassDB.instantiate("CellNeural")

	# Warm up both paths.
	var out_cpp: PackedFloat32Array = cpp.call("evaluate_batch", inputs_flat, weights, alive, 0, N)
	var hidden: PackedFloat32Array = PackedFloat32Array()
	hidden.resize(4)
	var one_out: PackedFloat32Array = PackedFloat32Array()
	one_out.resize(OUT)
	var one_in: PackedFloat32Array = PackedFloat32Array()
	one_in.resize(IN)
	for i in range(IN):
		one_in[i] = inputs_flat[i]
	BEHAVIOR.evaluate_into(one_in, weights, 0, hidden, one_out, 0)

	var t0: int = Time.get_ticks_usec()
	for it in range(ITERS):
		out_cpp = cpp.call("evaluate_batch", inputs_flat, weights, alive, 0, N)
	var t1: int = Time.get_ticks_usec()
	var cpp_us: float = float(t1 - t0) / float(ITERS)

	# GDScript: loop evaluate_into per cell (same math, no field/neighbor).
	t0 = Time.get_ticks_usec()
	for it in range(ITERS):
		for c in range(N):
			var off: int = c * IN
			for i in range(IN):
				one_in[i] = inputs_flat[off + i]
			BEHAVIOR.evaluate_into(one_in, weights, c * W, hidden, one_out, 0)
	var t2: int = Time.get_ticks_usec()
	var gd_us: float = float(t2 - t0) / float(ITERS)

	print("NEURAL_BENCH: N=%d iters=%d" % [N, ITERS])
	print("NEURAL_BENCH: gd_eval=%.1fus cpp_batch=%.1fus speedup=%.2fx" % [gd_us, cpp_us, gd_us / maxf(cpp_us, 0.001)])
	quit(0)
