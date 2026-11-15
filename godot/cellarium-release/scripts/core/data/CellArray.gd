extends RefCounted
## 所有运行时细胞状态使用并行 packed arrays；只允许 SimWorld/TickCore 单写。
## 连接以全局 cell index 存储，删除/压缩由后续主线程阶段处理。

var cell_pos_x: PackedFloat32Array = PackedFloat32Array()
var cell_pos_y: PackedFloat32Array = PackedFloat32Array()
var cell_prev_x: PackedFloat32Array = PackedFloat32Array()
var cell_prev_y: PackedFloat32Array = PackedFloat32Array()
var cell_energy: PackedFloat32Array = PackedFloat32Array()
var cell_type: PackedByteArray = PackedByteArray()
var cell_org_id: PackedInt32Array = PackedInt32Array()
var cell_link_a: PackedInt32Array = PackedInt32Array()
var cell_link_b: PackedInt32Array = PackedInt32Array()
var cell_link_rest: PackedFloat32Array = PackedFloat32Array()
var expression_weights: PackedFloat32Array = PackedFloat32Array()

func append_cell(org_id: int, position: Vector2, energy: float, type_id: int = 0) -> int:
	if org_id < 0 or type_id < 0 or type_id > 255 or energy < 0.0:
		return -1
	var index: int = size()
	cell_pos_x.append(position.x)
	cell_pos_y.append(position.y)
	cell_prev_x.append(position.x)
	cell_prev_y.append(position.y)
	cell_energy.append(energy)
	cell_type.append(type_id)
	cell_org_id.append(org_id)
	cell_link_a.append(-1)
	cell_link_b.append(-1)
	cell_link_rest.append(0.0)
	for i in range(8):
		expression_weights.append(0.0)
	return index

func size() -> int:
	return cell_org_id.size()

func get_position(index: int) -> Vector2:
	if index < 0 or index >= size():
		return Vector2.ZERO
	return Vector2(cell_pos_x[index], cell_pos_y[index])

func set_position(index: int, position: Vector2) -> bool:
	if index < 0 or index >= size():
		return false
	cell_prev_x[index] = cell_pos_x[index]
	cell_prev_y[index] = cell_pos_y[index]
	cell_pos_x[index] = position.x
	cell_pos_y[index] = position.y
	return true

func total_energy_for_org(org_id: int) -> float:
	var total: float = 0.0
	for i in range(size()):
		if cell_org_id[i] == org_id:
			total += cell_energy[i]
	return total

func link_cells(a: int, b: int, rest_length: float) -> bool:
	if a < 0 or b < 0 or a >= size() or b >= size() or a == b or rest_length <= 0.0:
		return false
	if cell_org_id[a] != cell_org_id[b] or cell_link_a[a] >= 0 or cell_link_a[b] >= 0:
		return false
	cell_link_a[a] = b
	cell_link_b[a] = b
	cell_link_a[b] = a
	cell_link_b[b] = a
	cell_link_rest[a] = rest_length
	cell_link_rest[b] = rest_length
	return true

func is_symmetric_link(a: int) -> bool:
	if a < 0 or a >= size():
		return false
	var b: int = cell_link_a[a]
	return b >= 0 and b < size() and cell_link_a[b] == a and cell_link_b[a] == b
