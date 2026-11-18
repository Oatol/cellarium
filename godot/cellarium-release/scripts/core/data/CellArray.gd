extends RefCounted
## 所有运行时细胞状态使用并行 packed arrays；只允许 SimWorld/TickCore 单写。
## 连接端点使用全局 cell index，删除/压缩由后续主线程阶段处理。

const MAX_LINKS_PER_CELL: int = 20
const NEURAL_WEIGHT_COUNT: int = 56
const BEHAVIOR_OUTPUT_COUNT: int = 6

var cell_pos_x: PackedFloat32Array = PackedFloat32Array()
var cell_pos_y: PackedFloat32Array = PackedFloat32Array()
var cell_prev_x: PackedFloat32Array = PackedFloat32Array()
var cell_prev_y: PackedFloat32Array = PackedFloat32Array()
var cell_energy: PackedFloat32Array = PackedFloat32Array()
var cell_alive: PackedByteArray = PackedByteArray()
var cell_type: PackedByteArray = PackedByteArray()
var cell_org_id: PackedInt32Array = PackedInt32Array()
var cell_link_count: PackedByteArray = PackedByteArray()
var link_cell_a: PackedInt32Array = PackedInt32Array()
var link_cell_b: PackedInt32Array = PackedInt32Array()
var link_rest_length: PackedFloat32Array = PackedFloat32Array()
var expression_weights: PackedFloat32Array = PackedFloat32Array()
var neural_weights: PackedFloat32Array = PackedFloat32Array()
var behavior_intents: PackedFloat32Array = PackedFloat32Array()
## v0.16.0：逐细胞表型数组。默认 1.0（半径倍率/刚度倍率）与 -1（颜色未覆写），
## 保证 flags 清零的旧基因组与旧存档行为逐位不变。
var cell_radius_scale: PackedFloat32Array = PackedFloat32Array()
var cell_stiffness: PackedFloat32Array = PackedFloat32Array()
var cell_color_r: PackedFloat32Array = PackedFloat32Array()
var cell_color_g: PackedFloat32Array = PackedFloat32Array()
var cell_color_b: PackedFloat32Array = PackedFloat32Array()
## v0.17.0：逐细胞所属模式槽与该模式已分裂层数。默认 0，旧细胞/旧存档行为不变。
var cell_mode: PackedByteArray = PackedByteArray()
var cell_mode_depth: PackedByteArray = PackedByteArray()

func append_cell(org_id: int, position: Vector2, energy: float, type_id: int = 0) -> int:
	if org_id < 0 or type_id < 0 or type_id > 255 or energy < 0.0:
		return -1
	var index: int = size()
	cell_pos_x.append(position.x)
	cell_pos_y.append(position.y)
	cell_prev_x.append(position.x)
	cell_prev_y.append(position.y)
	cell_energy.append(energy)
	cell_alive.append(1)
	cell_type.append(type_id)
	cell_org_id.append(org_id)
	cell_link_count.append(0)
	for i in range(8):
		expression_weights.append(0.0)
	for i in range(NEURAL_WEIGHT_COUNT):
		neural_weights.append(0.0)
	for i in range(BEHAVIOR_OUTPUT_COUNT):
		behavior_intents.append(0.0)
	cell_radius_scale.append(1.0)
	cell_stiffness.append(1.0)
	cell_color_r.append(-1.0)
	cell_color_g.append(-1.0)
	cell_color_b.append(-1.0)
	cell_mode.append(0)
	cell_mode_depth.append(0)
	return index

func size() -> int:
	return cell_org_id.size()

func divide_cell(index: int, angle: float, separation: float = 1.0) -> int:
	if index < 0 or index >= size() or separation <= 0.0:
		return -1
	if int(cell_link_count[index]) >= MAX_LINKS_PER_CELL:
		return -1
	var org_id: int = cell_org_id[index]
	var child_energy: float = cell_energy[index] * 0.5
	var child_position: Vector2 = get_position(index) + Vector2.RIGHT.rotated(angle) * separation
	var child_type: int = int(cell_type[index])
	cell_energy[index] -= child_energy
	var child_index: int = append_cell(org_id, child_position, child_energy, child_type)
	var neural_start: int = index * NEURAL_WEIGHT_COUNT
	for weight_index in range(NEURAL_WEIGHT_COUNT):
		neural_weights[child_index * NEURAL_WEIGHT_COUNT + weight_index] = neural_weights[neural_start + weight_index]
	var behavior_start: int = index * BEHAVIOR_OUTPUT_COUNT
	for output_index in range(BEHAVIOR_OUTPUT_COUNT):
		behavior_intents[child_index * BEHAVIOR_OUTPUT_COUNT + output_index] = behavior_intents[behavior_start + output_index]
	var expression_start: int = index * 8
	for trait_index in range(8):
		expression_weights[child_index * 8 + trait_index] = expression_weights[expression_start + trait_index]
	cell_radius_scale[child_index] = cell_radius_scale[index]
	cell_stiffness[child_index] = cell_stiffness[index]
	cell_color_r[child_index] = cell_color_r[index]
	cell_color_g[child_index] = cell_color_g[index]
	cell_color_b[child_index] = cell_color_b[index]
	cell_mode[child_index] = cell_mode[index]
	cell_mode_depth[child_index] = cell_mode_depth[index]
	return child_index

func get_position(index: int) -> Vector2:
	if index < 0 or index >= size():
		return Vector2.ZERO
	return Vector2(cell_pos_x[index], cell_pos_y[index])

## v0.16.0：写入逐细胞表型（基因模式由 Genome 派生；旧模式保持默认值）。
func set_cell_phenotype(index: int, radius_scale: float, stiffness: float, color: Color) -> bool:
	if index < 0 or index >= size():
		return false
	cell_radius_scale[index] = clampf(radius_scale, 0.5, 2.0)
	cell_stiffness[index] = clampf(stiffness, 0.25, 2.0)
	cell_color_r[index] = color.r
	cell_color_g[index] = color.g
	cell_color_b[index] = color.b
	return true

func get_radius_scale(index: int) -> float:
	if index < 0 or index >= cell_radius_scale.size():
		return 1.0
	return cell_radius_scale[index]

func get_stiffness(index: int) -> float:
	if index < 0 or index >= cell_stiffness.size():
		return 1.0
	return cell_stiffness[index]

func get_color(index: int) -> Color:
	if index < 0 or index >= cell_color_r.size():
		return Color(-1.0, -1.0, -1.0, 1.0)
	return Color(cell_color_r[index], cell_color_g[index], cell_color_b[index], 1.0)

## v0.17.0：模式槽写入/读取；越界返回安全默认值，不改变其他 SoA 数组。
func set_cell_mode(index: int, mode_index: int, depth: int) -> bool:
	if index < 0 or index >= size():
		return false
	cell_mode[index] = clampi(mode_index, 0, 255)
	cell_mode_depth[index] = clampi(depth, 0, 255)
	return true

func get_mode(index: int) -> int:
	if index < 0 or index >= cell_mode.size():
		return 0
	return int(cell_mode[index])

func get_mode_depth(index: int) -> int:
	if index < 0 or index >= cell_mode_depth.size():
		return 0
	return int(cell_mode_depth[index])

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
		if cell_org_id[i] == org_id and cell_alive[i] != 0:
			total += cell_energy[i]
	return total

func remove_cell(index: int) -> float:
	if index < 0 or index >= size() or cell_alive[index] == 0:
		return -1.0
	var released_energy: float = cell_energy[index]
	for link_index in range(link_cell_a.size() - 1, -1, -1):
		if link_cell_a[link_index] == index or link_cell_b[link_index] == index:
			var other: int = link_cell_b[link_index] if link_cell_a[link_index] == index else link_cell_a[link_index]
			cell_link_count[other] -= 1
			cell_link_count[index] -= 1
			link_cell_a.remove_at(link_index)
			link_cell_b.remove_at(link_index)
			link_rest_length.remove_at(link_index)
	cell_alive[index] = 0
	cell_energy[index] = 0.0
	return released_energy

func link_cells(a: int, b: int, rest_length: float) -> bool:
	if a < 0 or b < 0 or a >= size() or b >= size() or a == b or rest_length <= 0.0:
		return false
	if cell_org_id[a] != cell_org_id[b] or int(cell_link_count[a]) >= MAX_LINKS_PER_CELL or int(cell_link_count[b]) >= MAX_LINKS_PER_CELL:
		return false
	if has_link(a, b):
		return false
	link_cell_a.append(a)
	link_cell_b.append(b)
	link_rest_length.append(rest_length)
	cell_link_count[a] += 1
	cell_link_count[b] += 1
	return true

func has_link(a: int, b: int) -> bool:
	for link_index in range(link_cell_a.size()):
		if (link_cell_a[link_index] == a and link_cell_b[link_index] == b) or (link_cell_a[link_index] == b and link_cell_b[link_index] == a):
			return true
	return false

func is_symmetric_link(cell_index: int) -> bool:
	if cell_index < 0 or cell_index >= size():
		return false
	var counted: int = 0
	for link_index in range(link_cell_a.size()):
		if link_cell_a[link_index] == cell_index:
			if link_cell_b[link_index] < 0 or link_cell_b[link_index] >= size():
				return false
			counted += 1
		elif link_cell_b[link_index] == cell_index:
			if link_cell_a[link_index] < 0 or link_cell_a[link_index] >= size():
				return false
			counted += 1
	return counted == int(cell_link_count[cell_index])
