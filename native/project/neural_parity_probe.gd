extends SceneTree
## P1 determinism gate: bit-exact parity between GDScript CellBehavior.evaluate_into
## and C++ CellNeural.evaluate_into. Run on the template project (has the extension).

const BEHAVIOR: Script = preload("res://cell_behavior.gd")

func _initialize() -> void:
	var failures: int = 0
	if not ClassDB.class_exists("CellNeural"):
		print("NEURAL_PARITY: FAIL CellNeural not registered")
		quit(1)
		return
	var cpp = ClassDB.instantiate("CellNeural")

	# Deterministic PRNG so the probe is reproducible.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261119

	var cases: int = 2000
	var weight_count: int = 56
	var checked: int = 0
	var max_abs_diff: float = 0.0
	for case_index in range(cases):
		var inputs: PackedFloat32Array = PackedFloat32Array()
		inputs.resize(8)
		var weights: PackedFloat32Array = PackedFloat32Array()
		weights.resize(weight_count)
		for i in range(8):
			inputs[i] = rng.randf_range(-1.0, 1.0)
		for i in range(weight_count):
			weights[i] = rng.randf_range(-0.25, 0.25)

		var hidden_gd: PackedFloat32Array = PackedFloat32Array()
		hidden_gd.resize(4)
		var outputs_gd: PackedFloat32Array = PackedFloat32Array()
		outputs_gd.resize(6)
		BEHAVIOR.evaluate_into(inputs, weights, 0, hidden_gd, outputs_gd, 0)

		var outputs_cpp: PackedFloat32Array = cpp.call("evaluate_into", inputs, weights, 0)
		if outputs_cpp.size() != 6:
			failures += 1
			continue
		for o in range(6):
			var a: float = outputs_gd[o]
			var b: float = outputs_cpp[o]
			var diff: float = absf(a - b)
			if diff > max_abs_diff:
				max_abs_diff = diff
			# float32 stored values: exact bit parity means exact equality (both NaN excluded).
			if a != b:
				failures += 1
				if failures <= 5:
					print("MISMATCH case=%d out=%d gd=%.9f cpp=%.9f diff=%.6f" % [case_index, o, a, b, diff])
		checked += 6

	print("NEURAL_PARITY: cases=%d checked=%d max_abs_diff=%.9f failures=%d" % [cases, checked, max_abs_diff, failures])
	print("NEURAL_PARITY: %s" % ("OK" if failures == 0 else "FAIL"))
	quit(1 if failures > 0 else 0)
