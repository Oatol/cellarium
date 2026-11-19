extends RefCounted
## Minimal stub exposing the same Packed arrays CellBehavior reads.
var cell_energy: PackedFloat32Array = PackedFloat32Array()
var cell_alive: PackedByteArray = PackedByteArray()
var cell_type: PackedByteArray = PackedByteArray()
var neural_weights: PackedFloat32Array = PackedFloat32Array()
var behavior_intents: PackedFloat32Array = PackedFloat32Array()
var cell_pos_x: PackedFloat32Array = PackedFloat32Array()
var cell_pos_y: PackedFloat32Array = PackedFloat32Array()
var cell_prev_x: PackedFloat32Array = PackedFloat32Array()
var cell_prev_y: PackedFloat32Array = PackedFloat32Array()

func setup(n: int) -> void:
	cell_energy.resize(n)
	cell_alive.resize(n)
	cell_type.resize(n)
	neural_weights.resize(n * 56)
	behavior_intents.resize(n * 6)
	cell_pos_x.resize(n)
	cell_pos_y.resize(n)
	cell_prev_x.resize(n)
	cell_prev_y.resize(n)
	for i in range(n):
		cell_energy[i] = 0.5
		cell_alive[i] = 1
		cell_type[i] = 0

func size() -> int:
	return cell_alive.size()
