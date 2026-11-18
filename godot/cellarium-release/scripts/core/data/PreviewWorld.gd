extends RefCounted
## 发育预览专用轻量模拟内核（v0.23.0）。
##
## 目标是"真实跑 Cell Lab 式模拟"而非把 dev_program 派生成静态状态。
## 严格复刻 CellWorld 中与预览视觉发育相关的核心公式（见 analysis/细胞物理与外观 第32章）：
##   - 合子初始化：w=0.288（合子 0.36）、d=sqrt(w/400)、p=1、T=-1、U[0..3]=0.01
##   - 固定种子 1337；dt=0.02；确定性 LCG（与 Java Random 同构，保证同初态逐位一致）
##   - 产能：可光合类型 w += 280*d²*dt（bg 实验室模式，无食物）
##   - 半径低通：d += ((w/400)/d - d)*0.5*10*dt
##   - 分裂条件链：有效能量>阈值、o>0.5、连接数<=上限、p>0.2、未死、非配子、池有位
##   - 分裂动作：母子各偏 0.1r（零力）、按 split_ratio 分能量、D=child1/child2 槽切换、
##     端粒同减、镜像异或、U/X/Y 按比、p 各半、o 归零
##   - 接触排斥：软弹力把重叠母子推开（力∝相交面积近似），下一 tick 分离
##
## 边界：独立 RefCounted，无 class_name，不写 CommandBus / EnvironmentField / Genome.hash /
## 存档 / 主模拟任何状态。只服务于 GenomePreview 的只读可视化，不进主 tick，不进确定性 hash。

const DT: float = 0.02
const SEED: int = 1337
const DEFAULT_ENERGY: float = 0.288
const ZYGOTE_ENERGY: float = 0.36
const CELL_FLOOR: float = 0.342          # 与 Cell.a = sqrt(1.8e-4) 对应（本标度 14px=2r）
const MAX_ENERGY: float = 0.36
const DISH_RADIUS: float = 5.0           # Environment.k（Macro 预览 2.5，本标度放大以便观察）
const REST_DISTANCE: float = 14.0        # 2r（与运行时碰撞最小中心距一致）
const MAX_CELLS: int = 512

# 可光合类型（h 枚举 s.s=true）：PHAGOCYTE=0, PHOTOCYTE=2, DEVOROCYTE=3, GLUEOCYTE=7
const PHOTOSYNTHETIC_TYPES: Array[int] = [0, 2, 3, 7]
const GAMETE_TYPE: int = 16

# SoA 细胞状态（固定容量，池尾交换删除）
var _pos: PackedVector2Array
var _vel: PackedVector2Array
var _radius: PackedFloat32Array
var _energy: PackedFloat32Array
var _age: PackedFloat32Array
var _orientation: PackedFloat32Array     # Cell.k 朝向（弧度）
var _phase: PackedFloat32Array           # Cell.m 相位
var _gene_slot: PackedInt32Array         # Cell.D 当前基因槽（mode index）
var _telomere: PackedInt32Array          # Cell.T，-1 无限
var _mirror: PackedByteArray             # Cell.y
var _alive: PackedByteArray
var _link_a: PackedInt32Array            # 邻接：每细胞最多一条亲子连接（预览足够）
var _link_b: PackedInt32Array
var _link_count: int = 0

var _count: int = 0
var _genes: Array[Dictionary] = []       # Gene 槽（每个 = normalized_mode）
var _rng_state: int = SEED
var _tick: int = 0
var _zygote_type: int = 0

# 本帧新产生的分裂事件（供指示器）；清理由 consume_splits 完成
var _pending_splits: Array[Dictionary] = []

# 本帧接触弦（世界坐标 a/b + peer + kind），与 Cell Lab cell.A[] 同源：
# 在接触阶段（推开之前）按圆-圆相交计算，供预览层用 CellContactChords 重建压平膜。
# kind: 0=细胞间接触弦，1=皿壁弦。
var _contact_chords: Array[Dictionary] = []

func _init() -> void:
	_reset_arrays()

func _reset_arrays() -> void:
	_pos = PackedVector2Array(); _pos.resize(MAX_CELLS)
	_vel = PackedVector2Array(); _vel.resize(MAX_CELLS)
	_radius = PackedFloat32Array(); _radius.resize(MAX_CELLS)
	_energy = PackedFloat32Array(); _energy.resize(MAX_CELLS)
	_age = PackedFloat32Array(); _age.resize(MAX_CELLS)
	_orientation = PackedFloat32Array(); _orientation.resize(MAX_CELLS)
	_phase = PackedFloat32Array(); _phase.resize(MAX_CELLS)
	_gene_slot = PackedInt32Array(); _gene_slot.resize(MAX_CELLS)
	_telomere = PackedInt32Array(); _telomere.resize(MAX_CELLS)
	_mirror = PackedByteArray(); _mirror.resize(MAX_CELLS)
	_alive = PackedByteArray(); _alive.resize(MAX_CELLS)
	_link_a = PackedInt32Array(); _link_a.resize(MAX_CELLS); _link_a.fill(-1)
	_link_b = PackedInt32Array(); _link_b.resize(MAX_CELLS); _link_b.fill(-1)

## 确定性 LCG（-java.util.Random 同构：seed=(seed*0x5DEECE66D+0xB) mod 2^48）。
## Godot int 为 64 位有符号，用位掩码模拟 48 位无符号。
func _next_u48() -> int:
	# Java Random LCG：seed=(seed*0x5DEECE66D+0xB) mod 2^48。
	# Godot int 为 64 位有符号，乘法可能溢出为负；用低 48 位掩码截断即可（对 2^48 取模）。
	const MULT: int = 25214903917   # 0x5DEECE66D
	const ADD: int = 11
	const MASK48: int = 281474976710655  # 2^48 - 1
	_rng_state = (_rng_state * MULT + ADD) & MASK48
	return _rng_state

func _next_float() -> float:
	return float(_next_u48()) / float(1 << 48)

## 从编辑器 modes 初始化世界；modes 已由 Genome.normalized_mode 规整。
func setup(genes: Array, initial_mode: int = 0) -> void:
	_reset_arrays()
	_genes = []
	for raw in genes:
		var gene: Dictionary = (raw as Dictionary).duplicate(true)
		_genes.append(gene)
	if _genes.is_empty():
		_genes.append({"cell_type": 0, "division_mass": 0.05, "split_ratio": 0.5,
			"child1_mode": 0, "child2_mode": 0, "child1_angle": 0.0, "child2_angle": 0.25,
			"split_angle": 0.0, "split_angle2": 0.25, "ratio": 0.5, "ratio2": 0.5,
			"telomere": -1, "cell_size": 1.0, "max_connections": 16, "make_glue": true})
	var slot: int = clampi(initial_mode, 0, _genes.size() - 1)
	# 若调用方没指定，扫描 initial==true 的槽（对应 Cell Lab 扫描 Gene.p == true 取最大索引 D）
	if initial_mode < 0:
		for i in range(_genes.size()):
			if bool((_genes[i] as Dictionary).get("initial", false)):
				slot = i
	_zygote_type = int((_genes[slot] as Dictionary).get("cell_type", 0))
	_rng_state = SEED
	_tick = 0
	_count = 0
	_link_count = 0
	_pending_splits.clear()
	var energy: float = ZYGOTE_ENERGY if _zygote_type == 0 else DEFAULT_ENERGY
	_spawn_cell(Vector2.ZERO, energy, slot, -1)

func _spawn_cell(pos: Vector2, energy: float, slot: int, orientation_from: int) -> int:
	if _count >= MAX_CELLS:
		return -1
	var index: int = _count
	_count += 1
	_pos[index] = pos
	_vel[index] = Vector2.ZERO
	_energy[index] = energy
	_age[index] = 0.0
	_radius[index] = maxf(CELL_FLOOR, sqrt(energy / 400.0) * 500.0)  # 标度：Cell Lab d∈[0,0.03]→本标度 7px
	_radius[index] = clampf(_radius[index], 4.0, 14.0)
	_gene_slot[index] = slot
	_telomere[index] = int((_genes[slot] as Dictionary).get("telomere", -1))
	_mirror[index] = 0
	_alive[index] = 1
	_link_a[index] = -1
	_link_b[index] = -1
	var orientation: float = 0.0
	if orientation_from >= 0 and orientation_from < index:
		orientation = _orientation[orientation_from]
	_orientation[index] = orientation
	_phase[index] = _next_float() * TAU
	return index

func get_cell_count() -> int:
	return _count

func get_tick() -> int:
	return _tick

## 跑一个 Cell Lab tick（dt=0.02）。顺序对齐 §32.4：产能/代谢 → 半径 → 分裂 → 接触分离。
func step() -> void:
	_tick += 1
	_pending_splits.clear()
	_contact_chords.clear()
	_metabolize(DT)
	_relax_radius(DT)
	_divide(DT)
	_resolve_contacts()
	_integrate_positions(DT)

func _metabolize(dt: float) -> void:
	for i in range(_count):
		if _alive[i] == 0:
			continue
		var slot: int = _gene_slot[i]
		var gene: Dictionary = _genes[clampi(slot, 0, _genes.size() - 1)]
		var type_id: int = int(gene.get("cell_type", 0))
		# Cell Lab g(double)：bg && gene.s.s → Q += 280*d²*dt（本标度按半径归一到 r0）
		if PHOTOSYNTHETIC_TYPES.has(type_id):
			var d_norm: float = clampf(_radius[i] / 14.0, 0.1, 1.0)
			var priority: float = clampf(float(gene.get("nutrition_priority", 0.5)), 0.0, 1.0)
			_energy[i] += 280.0 * d_norm * d_norm * dt * (0.5 + priority)
		# 基础代谢（按 Cell Lab u*(1.3857-1.2857*n)*400*(d+0.0075)*d*dt 的本标度近似）
		var base_cost: float = 0.02 * (_radius[i] / 14.0) * dt * 6.0
		_energy[i] -= base_cost
		_age[i] += dt
		_energy[i] = clampf(_energy[i], 0.0, MAX_ENERGY * 2.0)

func _relax_radius(dt: float) -> void:
	for i in range(_count):
		if _alive[i] == 0:
			continue
		if _age[i] <= 5.0 * dt:
			continue
		var w: float = _energy[i]
		if w <= 0.0:
			continue
		var d: float = _radius[i] / 500.0  # 回到 Cell Lab 标度（0..0.03）
		var target_sq: float = w / 400.0
		var new_sq: float = target_sq + (d * d - target_sq) * (1.0 - 0.5 * 10.0 * dt)
		var new_d: float = sqrt(maxf(0.0, new_sq))
		new_d = clampf(new_d, CELL_FLOOR / 500.0, 0.03)
		_radius[i] = new_d * 500.0

func _effective_energy(i: int) -> float:
	# LIPOCYTE(4) 折算储能；预览无脂肪池，简化为 w
	return _energy[i]

func _divide(dt: float) -> void:
	var start_count: int = _count
	var i: int = 0
	while i < start_count:
		if _alive[i] == 0:
			i += 1
			continue
		var slot: int = _gene_slot[i]
		var gene: Dictionary = _genes[clampi(slot, 0, _genes.size() - 1)]
		var threshold: float = float(gene.get("division_mass", 0.05))
		var e_eff: float = _effective_energy(i)
		var link_n: int = _link_count_for(i)
		var max_links: int = clampi(int(gene.get("max_connections", 16)), 0, 16)
		var type_id: int = int(gene.get("cell_type", 0))
		var can_divide: bool = e_eff > threshold and _age[i] > 0.5 and link_n <= max_links \
			and _telomere[i] != 0 and type_id != GAMETE_TYPE and _count < MAX_CELLS
		if not can_divide:
			i += 1
			continue
		# 分裂轴 d7 = k + (镜像?-1:1)*Gene.d（Gene.d = child2_angle*TAU）
		var child2_angle: float = clampf(float(gene.get("child2_angle", 0.25)), 0.0, 1.0)
		if bool(gene.get("child2_mirror", false)):
			child2_angle = fposmod(-child2_angle, 1.0)
		var axis: float = _orientation[i] + child2_angle * TAU
		var dir: Vector2 = Vector2(cos(axis), sin(axis))
		var offset: float = _radius[i] * 0.1  # Cell Lab d8 = 0.1r
		var split_center: Vector2 = _pos[i]
		_pos[i] = split_center - dir * offset
		var ratio: float = clampf(float(gene.get("split_ratio", 0.5)), 0.05, 0.95)
		if bool(gene.get("invert_split_mass", false)):
			ratio = 1.0 - ratio
		var total: float = e_eff
		var child_slot: int = clampi(int(gene.get("child2_mode", slot)), 0, _genes.size() - 1)
		var mother_slot: int = clampi(int(gene.get("child1_mode", slot)), 0, _genes.size() - 1)
		var child_index: int = _spawn_cell(split_center + dir * offset, total * ratio, child_slot, i)
		if child_index < 0:
			i += 1
			continue
		_energy[i] = total * (1.0 - ratio)
		# 分化槽切换：母=child1_mode，子=child2_mode（Cell Lab cell.D=Gene.i / cell2.D=Gene.j）
		_gene_slot[i] = mother_slot
		_gene_slot[child_index] = child_slot
		# 朝向子代角 Gene.e/f（本标度用 split_angle / split_angle2）
		_orientation[i] = axis + clampf(float(gene.get("split_angle", 0.0)), 0.0, 1.0) * TAU
		_orientation[child_index] = axis + clampf(float(gene.get("split_angle2", 0.25)), 0.0, 1.0) * TAU
		# 镜像标志异或 Gene.q/r
		if bool(gene.get("child1_mirror", false)):
			_mirror[i] = 1 - _mirror[i]
		if bool(gene.get("child2_mirror", false)):
			_mirror[child_index] = 1 - _mirror[child_index]
		# 端粒母子同减，<=0 双亡
		if _telomere[i] != -1:
			_telomere[i] -= 1
			_telomere[child_index] = _telomere[i]
			if _telomere[i] <= 0:
				_alive[i] = 0
				_alive[child_index] = 0
		# 年龄归零；相位半个周期差
		_age[i] = 0.0
		_age[child_index] = 0.0
		_phase[child_index] = fposmod(_phase[i] + PI, TAU)
		# 黏附亲子连接（Gene.l = make_glue）
		if bool(gene.get("make_glue", true)):
			_link(i, child_index)
		_pending_splits.append({
			"pos": split_center, "angle": axis, "parent": i, "child": child_index,
			"ratio": ratio, "radius": _radius[i],
			"gene_slot": slot, "zygote": slot == 0,
		})
		i += 1

func _link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	if _link_a[a] != -1 or _link_a[b] != -1:
		return
	_link_a[a] = b
	_link_b[a] = a
	_link_count += 1

func _link_count_for(i: int) -> int:
	var n: int = 0
	if _link_a[i] != -1:
		n += 1
	if _link_b[i] != -1:
		n += 1
	return n

## 接触排斥：软弹力把重叠细胞对推开（力∝相交面积近似），下一 tick 分离。
## Cell Lab d(int) 在接触阶段算公共弦 + 写 A[]，力写 g/h 累加器；这里用简化径向排斥保持视觉一致。
func _resolve_contacts() -> void:
	var iterations: int = 2
	for it in range(iterations):
		for a in range(_count):
			if _alive[a] == 0:
				continue
			for b in range(a + 1, _count):
				if _alive[b] == 0:
					continue
				var delta: Vector2 = _pos[b] - _pos[a]
				var dist: float = delta.length()
				var min_dist: float = REST_DISTANCE * maxf(0.5, maxf(_radius[a], _radius[b]) / 14.0)
				if dist >= min_dist or dist < 1e-5:
					continue
				# 第一次迭代、推开之前记录圆-圆相交弦（与 Cell Lab d(int) A[] 同源）。
				if it == 0:
					var chord: Dictionary = _circle_chord(_pos[a], _radius[a], _pos[b], _radius[b], a, b)
					if not chord.is_empty():
						_contact_chords.append(chord)
				var overlap: float = min_dist - dist
				var push: Vector2 = delta / dist * (overlap * 0.5)
				_pos[a] -= push
				_pos[b] += push
	# 皿壁弦：细胞圆与皿壁圆（内切）相交时记录（kind=1）。
	var wall_r: float = DISH_RADIUS * 10.0
	for a in range(_count):
		if _alive[a] == 0:
			continue
		var s: float = _pos[a].length()
		if s < 1e-5 or s + _radius[a] <= wall_r:
			continue
		var direction: Vector2 = -_pos[a] / s  # 指向皿心
		var d: float = (_radius[a] * _radius[a] - wall_r * wall_r + s * s) / (2.0 * s)
		var h_sq: float = _radius[a] * _radius[a] - d * d
		if h_sq <= 0.0:
			continue
		var middle: Vector2 = _pos[a] + direction * d
		var perp: Vector2 = Vector2(-direction.y, direction.x)
		var h: float = sqrt(h_sq)
		_contact_chords.append({"a": middle - perp * h, "b": middle + perp * h, "owner_a": a, "owner_b": -1, "kind": 1})

## 两圆相交弦（Cell Lab d(int) d51/d54..d56）：返回世界坐标端点 a/b + 两端 owner。
func _circle_chord(p0: Vector2, r0: float, p1: Vector2, r1: float, owner_a: int, owner_b: int) -> Dictionary:
	var delta: Vector2 = p1 - p0
	var s: float = delta.length()
	if s < 0.000001 or s >= r0 + r1 or s <= absf(r0 - r1):
		return {}
	var direction: Vector2 = delta / s
	var d: float = (s * s - r1 * r1 + r0 * r0) / (2.0 * s)
	var h_sq: float = r0 * r0 - d * d
	if h_sq <= 0.0:
		return {}
	var middle: Vector2 = p0 + direction * d
	var perp: Vector2 = Vector2(-direction.y, direction.x)
	var h: float = sqrt(h_sq)
	return {"a": middle - perp * h, "b": middle + perp * h, "owner_a": owner_a, "owner_b": owner_b, "kind": 0}

func _integrate_positions(dt: float) -> void:
	for i in range(_count):
		if _alive[i] == 0:
			continue
		# 亲子连接的弹簧回拉（Cell Lab d(int) 弹簧-阻尼：约化质量 + 弹性项）
		var peer: int = _link_a[i]
		if peer >= 0 and peer < _count and _alive[peer] == 1:
			var delta: Vector2 = _pos[peer] - _pos[i]
			var dist: float = delta.length()
			if dist > 1e-5:
				var stretch: float = dist - REST_DISTANCE
				_vel[i] += delta / dist * stretch * 0.5 * dt
		_pos[i] += _vel[i] * dt
		_vel[i] *= 0.85  # 粘性阻尼
		_phase[i] = fposmod(_phase[i] + 0.02 * dt, TAU)
		# 皿壁约束
		var r: float = _pos[i].length()
		if r > DISH_RADIUS * 10.0:
			_pos[i] = _pos[i].normalized() * (DISH_RADIUS * 10.0)

## 读取快照（只读）：供 GenomePreview 绘制。
func snapshot_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(_count):
		if _alive[i] == 0:
			continue
		var cell_chords: Array[Dictionary] = []
		for chord in _contact_chords:
			var c: Dictionary = chord as Dictionary
			if int(c.get("owner_a", -1)) == i or int(c.get("owner_b", -1)) == i:
				cell_chords.append(c)
		result.append({
			"index": i, "pos": _pos[i], "radius": _radius[i],
			"energy": _energy[i], "age": _age[i], "orientation": _orientation[i],
			"gene_slot": _gene_slot[i], "mode": _gene_slot[i],
			"type": int((_genes[clampi(_gene_slot[i], 0, _genes.size() - 1)] as Dictionary).get("cell_type", 0)),
			"phase": _phase[i], "telomere": _telomere[i],
			"chords": cell_chords,
		})
	return result

## 只读：本帧全部接触弦（世界坐标），供连接板/诊断使用。
func snapshot_chords() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chord in _contact_chords:
		result.append((chord as Dictionary).duplicate(true))
	return result

func snapshot_links() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(_count):
		if _alive[i] == 0 or _link_a[i] < 0:
			continue
		result.append({"a": i, "b": _link_a[i], "rest": REST_DISTANCE})
	return result

func consume_splits() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _pending_splits:
		result.append((entry as Dictionary).duplicate(true))
	_pending_splits.clear()
	return result

func get_gene(slot: int) -> Dictionary:
	if slot < 0 or slot >= _genes.size():
		return {}
	return _genes[slot]
