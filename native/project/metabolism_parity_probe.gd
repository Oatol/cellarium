extends SceneTree
## v0.33.0 metabolism parity: C++ CellMetabolism.compute_environment_batch
## vs the exact GDScript arithmetic in OrganismManager._apply_environment_metabolism_ranges.
## Compares doubles bit-for-bit (PackedFloat64Array) before any float32 write-back.

const RULES: Script = preload("res://RespirationRules.gd")

const N: int = 1500
const ORG_COUNT: int = 200
const TYPE_ZYGOTE: int = 0
const TYPE_PHOTOCYTE: int = 4
const TYPE_NITROCYTE: int = 10
const TYPES: Array[int] = [TYPE_ZYGOTE, TYPE_PHOTOCYTE, TYPE_NITROCYTE, 7]

var dt: float = 1.0 / 60.0
var hetero_rate: float = 0.42
var photo_rate: float = 0.08
var chemo_rate: float = 0.33
var move_cost: float = 0.021
var fac_eff: float = 2.0

func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8675309
	var alive: PackedByteArray = PackedByteArray()
	var types: PackedByteArray = PackedByteArray()
	var org_ids: PackedInt32Array = PackedInt32Array()
	var fields: PackedFloat32Array = PackedFloat32Array()
	var sample_indices: PackedInt32Array = PackedInt32Array()
	var respiration: PackedByteArray = PackedByteArray()
	var priority: PackedFloat32Array = PackedFloat32Array()
	var intents: PackedFloat32Array = PackedFloat32Array()
	alive.resize(N); types.resize(N); org_ids.resize(N); fields.resize(N * 5)
	sample_indices.resize(N); respiration.resize(ORG_COUNT); priority.resize(ORG_COUNT)
	intents.resize(N * 6)
	for i in range(N):
		alive[i] = 1 if rng.randi_range(0, 9) != 0 else 0
		types[i] = TYPES[rng.randi_range(0, TYPES.size() - 1)]
		org_ids[i] = i % ORG_COUNT
		sample_indices[i] = i if rng.randi_range(0, 9) != 0 else -1
		for c in range(5):
			fields[i * 5 + c] = rng.randf_range(-0.5, 1.5)
		fields[i * 5 + 2] = clampf(fields[i * 5 + 2], 0.0, 1.0)
		for o in range(6):
			intents[i * 6 + o] = rng.randf_range(-1.0, 1.0)
	for o in range(ORG_COUNT):
		respiration[o] = rng.randi_range(0, 3)
		priority[o] = rng.randf_range(0.0, 1.0)

	var cpp: RefCounted = ClassDB.instantiate("CellMetabolism")
	var batch: Dictionary = cpp.call("compute_environment_batch", alive, types, org_ids,
		fields, sample_indices, respiration, priority, intents,
		dt, hetero_rate, photo_rate, chemo_rate, move_cost, fac_eff)
	var cpp_food: PackedFloat64Array = batch["food_gains"]
	var cpp_move: PackedFloat64Array = batch["movement_costs"]
	var cpp_toxic: PackedByteArray = batch["toxic_flags"]

	var failures: int = 0
	var checked: int = 0
	var max_diff: float = 0.0
	for cell_index in range(N):
		if alive[cell_index] == 0:
			continue
		var org_id: int = org_ids[cell_index]
		var sample_index: int = sample_indices[cell_index]
		var field_offset: int = sample_index * 5
		var has_fields: bool = sample_index >= 0 and field_offset + 5 <= fields.size()
		var oxygen: float = clampf(float(fields[field_offset + 2]), 0.0, 1.0) if has_fields else 0.0
		var resp: Dictionary = RULES.evaluate(int(respiration[org_id]), oxygen, fac_eff)
		var feeding_factor: float = 0.25 + 1.5 * float(priority[org_id])
		var light_factor: float = 1.75 - 1.5 * float(priority[org_id])
		var food_gain: float = 0.0
		var t: int = types[cell_index]
		if t == TYPE_ZYGOTE:
			food_gain = maxf(0.0, float(fields[field_offset])) * hetero_rate * feeding_factor * float(resp.get("efficiency", 0.0)) * dt if has_fields else 0.0
		elif t == TYPE_PHOTOCYTE:
			food_gain = maxf(0.0, float(fields[field_offset + 3])) * photo_rate * light_factor * dt if has_fields else 0.0
		elif t == TYPE_NITROCYTE:
			food_gain = maxf(0.0, float(fields[field_offset + 4])) * chemo_rate * feeding_factor * dt if has_fields else 0.0
		var movement: float = absf(float(intents[cell_index * 6]))
		var movement_cost: float = move_cost * movement * movement * dt
		var toxic: int = 1 if bool(resp.get("toxic", false)) else 0
		var diff_food: float = absf(food_gain - float(cpp_food[cell_index]))
		var diff_move: float = absf(movement_cost - float(cpp_move[cell_index]))
		max_diff = maxf(max_diff, maxf(diff_food, diff_move))
		if food_gain != float(cpp_food[cell_index]) or movement_cost != float(cpp_move[cell_index]) or toxic != int(cpp_toxic[cell_index]):
			failures += 1
		checked += 1
	print("METAB_PARITY: checked=%d failures=%d max_abs_diff=%.17f" % [checked, failures, max_diff])
	if failures == 0:
		print("METAB_PARITY: OK")
	quit(0 if failures == 0 else 1)
