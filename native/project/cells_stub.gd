extends RefCounted
var cell_pos_x: PackedFloat32Array = PackedFloat32Array()
var cell_pos_y: PackedFloat32Array = PackedFloat32Array()
var cell_alive: PackedByteArray = PackedByteArray()
var cell_energy: PackedFloat32Array = PackedFloat32Array()
var cell_type: PackedByteArray = PackedByteArray()
func size() -> int:
	return cell_alive.size()
