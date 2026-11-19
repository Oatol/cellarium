extends SceneTree
## v0.35.0 parity gate for CellNeural.apply_outputs_flat and collect_signal_sources.
## The reference implementation uses the exact GDScript operations being replaced.

const N: int = 700
const OUTPUT_COUNT: int = 6
const DT: float = 1.0 / 60.0
const MAX_SPEED: float = 144.0

var failures: int = 0
var checked: int = 0

func _initialize() -> void:
	if not ClassDB.class_exists("CellNeural"):
		print("BEHAVIOR_SIGNAL_PARITY: SKIP (CellNeural not registered)")
		quit(0)
		return
	var cpp: RefCounted = ClassDB.instantiate("CellNeural") as RefCounted
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 53589793
	var alive: PackedByteArray = PackedByteArray()
	var pos_x: PackedFloat32Array = PackedFloat32Array()
	var pos_y: PackedFloat32Array = PackedFloat32Array()
	var prev_x: PackedFloat32Array = PackedFloat32Array()
	var prev_y: PackedFloat32Array = PackedFloat32Array()
	var intents: PackedFloat32Array = PackedFloat32Array()
	var outputs: PackedFloat32Array = PackedFloat32Array()
	alive.resize(N); pos_x.resize(N); pos_y.resize(N)
	prev_x.resize(N); prev_y.resize(N)
	intents.resize(N * OUTPUT_COUNT); outputs.resize(N * OUTPUT_COUNT)
	for i in range(N):
		alive[i] = 1 if rng.randi_range(0, 9) != 0 else 0
		pos_x[i] = rng.randf_range(-80.0, 80.0)
		pos_y[i] = rng.randf_range(-80.0, 80.0)
		prev_x[i] = pos_x[i] - rng.randf_range(-1.0, 1.0)
		prev_y[i] = pos_y[i] - rng.randf_range(-1.0, 1.0)
		for j in range(OUTPUT_COUNT):
			intents[i * OUTPUT_COUNT + j] = rng.randf_range(-1.0, 1.0)
			outputs[i * OUTPUT_COUNT + j] = rng.randf_range(-1.0, 1.0)

	var copied: PackedFloat32Array = cpp.call("copy_outputs_to_intents", alive, intents, outputs) as PackedFloat32Array
	var ref_intents: PackedFloat32Array = _reference_copy(alive, intents, outputs)
	_compare_f32("copy.intents", copied, ref_intents)

	var native_sources: Dictionary = cpp.call("collect_signal_sources",
		alive, intents, pos_x, pos_y, DT) as Dictionary
	var ref_sources: Dictionary = _reference_signal(alive, intents, pos_x, pos_y, DT)
	_compare_i32("signal.indices", native_sources["indices"], ref_sources["indices"])
	_compare_f64("signal.amounts", native_sources["amounts"], ref_sources["amounts"])

	print("BEHAVIOR_SIGNAL_PARITY: checked=%d failures=%d" % [checked, failures])
	print("BEHAVIOR_SIGNAL_PARITY: %s" % ["OK" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)

func _reference_copy(alive: PackedByteArray, intents: PackedFloat32Array,
		outputs: PackedFloat32Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = intents.duplicate()
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var start: int = cell_index * OUTPUT_COUNT
		for output_index in range(OUTPUT_COUNT):
			result[start + output_index] = outputs[start + output_index]
	return result

func _reference_signal(alive: PackedByteArray, intents: PackedFloat32Array,
		pos_x: PackedFloat32Array, pos_y: PackedFloat32Array, dt: float) -> Dictionary:
	var indices: PackedInt32Array = PackedInt32Array()
	var amounts: PackedFloat64Array = PackedFloat64Array()
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var amount: float = maxf(0.0, float(intents[cell_index * OUTPUT_COUNT + 3])) * dt
		if amount > 0.0:
			indices.append(cell_index)
			amounts.append(amount)
	return {"indices": indices, "amounts": amounts}

func _compare_f32(name: String, cpp: PackedFloat32Array, reference: PackedFloat32Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("BEHAVIOR_SIGNAL_PARITY: FAIL %s size %d/%d" % [name, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("BEHAVIOR_SIGNAL_PARITY: FAIL %s[%d] cpp=%.9f ref=%.9f" % [name, i, cpp[i], reference[i]])

func _compare_i32(name: String, cpp: PackedInt32Array, reference: PackedInt32Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("BEHAVIOR_SIGNAL_PARITY: FAIL %s size %d/%d" % [name, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("BEHAVIOR_SIGNAL_PARITY: FAIL %s[%d] cpp=%d ref=%d" % [name, i, cpp[i], reference[i]])

func _compare_f64(name: String, cpp: PackedFloat64Array, reference: PackedFloat64Array) -> void:
	if cpp.size() != reference.size():
		failures += 1
		print("BEHAVIOR_SIGNAL_PARITY: FAIL %s size %d/%d" % [name, cpp.size(), reference.size()])
		return
	for i in range(cpp.size()):
		checked += 1
		if cpp[i] != reference[i]:
			failures += 1
			if failures <= 5:
				print("BEHAVIOR_SIGNAL_PARITY: FAIL %s[%d] cpp=%.17f ref=%.17f" % [name, i, cpp[i], reference[i]])
