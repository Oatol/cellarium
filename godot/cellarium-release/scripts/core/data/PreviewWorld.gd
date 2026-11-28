extends RefCounted
## 发育预览内核（v0.25.0：直接复用项目已有的真实模拟）。
##
## 与 Cell Lab 一致：预览不另写一套近似公式，而是实例化一套**隔离的真实模拟**——
## 官方版 `new CellWorld(true, environment)` / Macro 版 `new SimulationWorld(env, true)`。
## 本项目对应 `OrganismManager` + `EnvironmentManager`：
##   - 独立实例，不加入主场景树、不写主 CommandBus / field / hash / 存档；
##   - 实验室环境（无食物投放、全皿均匀光照、强制 CPU 后端），对应 Cell Lab 预览的 env；
##   - 用编辑器 modes 构造真正的 Genome，register_zygote 从单个合子起跑；
##   - step() 直接调用真实的 advance_physics_tick(dt)，细胞的位置/半径/类型/颜色/连接/分裂
##     全部来自真实 CellArray —— 与培养皿里看到的实际模拟同源，不再有任何手拼标度。
##
## 快照的接触弦用运行时 CellSceneRenderer 的同源几何（CellContactChords.circle_chord /
## wall_chord），保证预览膜与实际渲染的切平方式一致。分裂事件由 cell_division_tick 变化
## 派生，仅用于叠加 Cell Lab j4.I() 指示器，不写模拟状态。

const OM_SCRIPT: Script = preload("res://scripts/system/OrganismManager.gd")
const EM_SCRIPT: Script = preload("res://scripts/system/EnvironmentManager.gd")
const FIELD_SCRIPT: Script = preload("res://scripts/system/EnvironmentField.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const CELL_PHYSICS: RefCounted = preload("res://scripts/system/CellPhysics.gd")
const CHORDS: RefCounted = preload("res://scripts/rendering/CellContactChords.gd")

const DT: float = 1.0 / 60.0             # 真实主 tick 步长（与实际模拟同源）
const MAX_CELLS: int = 96                # 预览发育上限（Cell Lab 也有超时/规模保护）
const MAX_TICKS: int = 4000              # 硬上限，防参数异常导致无限跑
const DIVISION_COOLDOWN: int = 12        # 实验室模式缩短节流，让发育在短时间内可见
const DISH_CENTER: Vector2 = Vector2(250.0, 250.0)
const DISH_RADIUS: float = 240.0
const ZYGOTE_ENERGY: float = 0.8
const CELL_RADIUS: float = 7.0           # CellShape.REST_RADIUS：实际渲染/碰撞半径基准

var _mgr: Node = null
var _env: Node = null
var _genome: RefCounted = null
var _genes: Array[Dictionary] = []
var _initial_slot: int = 0
var _tick: int = 0
var _last_division_ticks: Dictionary = {}   # cell_index -> division_tick（用于派生分裂事件）
var _pending_splits: Array[Dictionary] = []
var _accum_splits: Array[Dictionary] = []   # 从合子到当前 tick 的全部分裂（供连续时间轴指示器）

func _init() -> void:
	pass

## 隔离实例不是场景树节点，RefCounted 释放不会自动 free 它们；显式回收避免编辑器
## 反复 set_program / 拖动时间轴时累积 ObjectDB 泄漏。
func _notification(what: int) -> void:
	# PREDELETE 期间脚本方法已不可调用，直接内联回收（不要调用 _release_world）。
	if what == NOTIFICATION_PREDELETE:
		if _mgr != null and is_instance_valid(_mgr):
			_mgr.free()
		if _env != null and is_instance_valid(_env):
			_env.free()
		_mgr = null
		_env = null

func _release_world() -> void:
	if _mgr != null and is_instance_valid(_mgr):
		_mgr.free()
	if _env != null and is_instance_valid(_env):
		_env.free()
	_mgr = null
	_env = null

## 确定性 RNG：真实模拟的神经权重初始化读 genome.hash()，不依赖全局随机；
## 这里只保证同一 genes 构造出的 Genome 逐字段一致。
func setup(genes: Array, initial_mode: int = 0) -> void:
	_release_world()
	_genes = []
	for raw in genes:
		_genes.append((raw as Dictionary).duplicate(true))
	if _genes.is_empty():
		_genes.append(GENOME_SCRIPT.call("normalized_mode", {}, 0))
	_initial_slot = clampi(initial_mode, 0, _genes.size() - 1)

	# 1) 隔离的实验室环境：无食物投放、全皿均匀光照、强制 CPU 场后端。
	_env = EM_SCRIPT.new() as Node
	_env.set("light_source_mode", 0)       # 0 = 全皿均匀
	_env.set("light_intensity", 1.0)
	_env.set("nutrient_density", 1.2)
	_env.set("oxygen_fraction", 1.0)
	_env.set("food_spawn_amount", 0.0)     # 关掉食物团块投放
	_env.set("dish_center", DISH_CENTER)
	_env.set("dish_radius", DISH_RADIUS)
	# 强制 CPU 后端：configure 的 prefer_compute=false；_ready 默认 bind_preset 会用 compute=true，
	# 因此这里手动重建 field 配置，不依赖 _ready 的默认后端选择。
	var field: RefCounted = _env.get("field") as RefCounted
	if field != null:
		var defaults: PackedFloat32Array = PackedFloat32Array([1.2, 273.0, 1.0, 1.0, 0.0])
		field.call("configure", 32, DISH_CENTER, DISH_RADIUS, defaults, false)
		# 均匀光照铺满通道 3（DECAY[3]=0，持续可供光合类型使用）
		var res: int = int(field.get("resolution"))
		var light_values: PackedFloat32Array = PackedFloat32Array()
		light_values.resize(res * res)
		light_values.fill(1.0)
		field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_LIGHT, light_values)
	_env.call("apply_light_settings")

	# 2) 隔离的真实模拟：独立 OrganismManager 实例，不进场景树。
	_mgr = OM_SCRIPT.new() as Node
	_mgr.set("environment_manager", _env)
	_mgr.set("tick_core", null)
	_mgr.set("dish_center", DISH_CENTER)
	_mgr.set("dish_radius", DISH_RADIUS)
	_mgr.set("cell_radius", CELL_RADIUS)
	_mgr.set("autonomous_division_cooldown", DIVISION_COOLDOWN)
	_mgr.set("global_cell_capacity", MAX_CELLS)
	_mgr.call("_ready")

	# 3) 用编辑器 modes 构造真正的 Genome（基因模式 + 黏附素），从单合子起跑。
	_genome = _build_genome()
	var org_id: int = int(_mgr.call("register_zygote", 1, 0, -1, _genome, DISH_CENTER, ZYGOTE_ENERGY, 0))
	if org_id < 0:
		_mgr = null
		return
	_tick = 0
	_last_division_ticks = {}
	_pending_splits.clear()
	_accum_splits.clear()
	_sync_division_ticks()

func _build_genome() -> RefCounted:
	var genome: RefCounted = GENOME_SCRIPT.new() as RefCounted
	genome.set("version", 1)
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	var flags: int = int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GENE_MODE", 2))
	# 任一模式开黏附素即置位（亲子自动连接），对齐编辑器行为。
	var glue: bool = false
	for gene in _genes:
		if bool((gene as Dictionary).get("make_glue", true)):
			glue = true
			break
	if glue:
		flags |= int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	genome.set("flags", flags)
	genome.set("modes", _genes.duplicate(true))
	var initial: Dictionary = _genes[_initial_slot]
	genome.set("division_mass", float(initial.get("division_mass", 0.05)))
	genome.set("split_ratio", float(initial.get("split_ratio", 0.5)))
	genome.set("max_divisions", 8)
	genome.set("max_cells_per_organism", MAX_CELLS)
	genome.set("nutrition_priority", float(initial.get("nutrition_priority", 0.5)))
	genome.set("cell_stiffness", float(initial.get("cell_stiffness", 0.5)))
	genome.set("cell_size", float(initial.get("cell_size", 1.0)))
	genome.set("max_connections", int(initial.get("max_connections", 4)))
	genome.set("min_connections", int(initial.get("min_connections", 0)))
	genome.set("color_r", float(initial.get("color_r", 0.36)))
	genome.set("color_g", float(initial.get("color_g", 0.88)))
	genome.set("color_b", float(initial.get("color_b", 0.75)))
	genome.set("transfer_rate", float(initial.get("transfer_rate", 0.12)))
	genome.set("dev_program", [])
	return genome

func get_cell_count() -> int:
	if _mgr == null:
		return 0
	return int((_mgr.get("cells") as RefCounted).call("size"))

func get_tick() -> int:
	return _tick

func is_grown() -> bool:
	return get_cell_count() >= MAX_CELLS or _tick >= MAX_TICKS

## 预览坐标：真实细胞坐标以 DISH_CENTER 为中心；预览画布以原点为中心，输出统一平移。
func _local(p: Vector2) -> Vector2:
	return p - DISH_CENTER

## 连续时间定位（Cell Lab J4 的 Z/T 断点缓存机制）：
## 目标 tick 大于当前 → 从当前状态续跑增量；小于当前 → 重置世界从合子重跑。
## 供 GenomePreview 的连续时间滑块拖动调用，渲染的是该 tick 的真实模拟状态。
func advance_to(target_tick: int) -> void:
	if _mgr == null:
		return
	target_tick = clampi(target_tick, 0, MAX_TICKS)
	if target_tick < _tick:
		setup(_genes, _initial_slot)
	while _tick < target_tick and not is_grown():
		step()
		consume_splits()   # 把本 tick 的分裂并入累计表，供连续时间轴指示器渲染

## 跑一个真实主 tick。分裂事件从 cell_division_tick 变化派生（只读）。
func step() -> void:
	_pending_splits.clear()
	if _mgr == null or is_grown():
		return
	_mgr.call("advance_physics_tick", DT)
	_env.call("advance_field_tick")
	_tick += 1
	_collect_splits()
	_sync_division_ticks()

func _cells() -> RefCounted:
	return _mgr.get("cells") as RefCounted

## 阶段 B：只读访问隔离的 OrganismManager，供 SimWorker 在 worker 线程消费命令。
func _manager() -> Node:
	return _mgr

func _live_indices(cells: RefCounted) -> Array[int]:
	var result: Array[int] = []
	var alive: PackedByteArray = cells.get("cell_alive")
	for i in range(alive.size()):
		if alive[i] != 0:
			result.append(i)
	return result

## 检测本 tick 新分裂的细胞（division_tick 从 -1/-2 变为 >=0，或由旧值变为当前 tick），
## 记录分裂中心/角度/质量比供 Cell Lab 指示器使用。纯读，不写模拟。
func _collect_splits() -> void:
	var cells: RefCounted = _cells()
	if cells == null:
		return
	var division_ticks: PackedInt32Array = cells.get("cell_division_tick")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	for i in _live_indices(cells):
		var now_tick: int = int(division_ticks[i]) if i < division_ticks.size() else -2
		var was_tick: int = int(_last_division_ticks.get(i, -2))
		if now_tick >= 0 and now_tick != was_tick:
			var mode_id: int = int(cells.call("get_mode", i))
			var gene: Dictionary = _genes[clampi(mode_id, 0, _genes.size() - 1)]
			# v0.50.0：Cell Lab d7 = cell.k + (镜像?-1:1)*Gene.d，分裂轴相对母细胞朝向。
			var axis_sign: float = -1.0 if bool(gene.get("child1_mirror", false)) else 1.0
			var angle: float = float(cells.call("get_orientation", i)) 				+ axis_sign * TAU * clampf(float(gene.get("child2_angle", 0.0)), 0.0, 1.0)
			_pending_splits.append({
				"pos": _local(Vector2(pos_x[i], pos_y[i])),
				"angle": angle,
				"parent": i,
				"child": i,
				"ratio": clampf(float(gene.get("split_ratio", 0.5)), 0.1, 0.9),
				"radius": _scaled_radius(cells, i),
				"gene_slot": mode_id,
				"zygote": mode_id == _initial_slot,
			})

func _sync_division_ticks() -> void:
	var cells: RefCounted = _cells()
	if cells == null:
		return
	var division_ticks: PackedInt32Array = cells.get("cell_division_tick")
	for i in _live_indices(cells):
		_last_division_ticks[i] = int(division_ticks[i]) if i < division_ticks.size() else -2

func _scaled_radius(cells: RefCounted, index: int) -> float:
	var scale: float = float(cells.call("get_radius_scale", index))
	scale = clampf(scale, 0.5, 2.0)
	return maxf(1.0, CELL_RADIUS * scale)

func _cell_color(cells: RefCounted, index: int, type_id: int) -> Color:
	var r: float = float(cells.get("cell_color_r")[index]) if index < (cells.get("cell_color_r") as PackedFloat32Array).size() else -1.0
	var g: float = float(cells.get("cell_color_g")[index]) if index < (cells.get("cell_color_g") as PackedFloat32Array).size() else -1.0
	var b: float = float(cells.get("cell_color_b")[index]) if index < (cells.get("cell_color_b") as PackedFloat32Array).size() else -1.0
	if r >= 0.0:
		return Color(r, g, b, 1.0)
	# 回退到模式表型色（与 GenomePreview._gene_color 一致）
	var mode_id: int = int(cells.call("get_mode", index))
	var gene: Dictionary = _genes[clampi(mode_id, 0, _genes.size() - 1)]
	return Color(float(gene.get("color_r", 0.36)), float(gene.get("color_g", 0.88)), float(gene.get("color_b", 0.75)), 1.0)

## 与运行时 CellSceneRenderer._build_shared_chords 同源：每对相邻细胞只算一次圆-圆相交弦，
## 端点原样分发给双方；再加皿壁弦。返回 cell_index -> chords 数组。只读 SoA。
func _build_shared_chords(cells: RefCounted, indices: Array[int]) -> Dictionary:
	var lists: Dictionary = {}
	for index in indices:
		lists[index] = []
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var buckets: Dictionary = CELL_PHYSICS.call("build_spatial_hash", cells)
	var seen: Dictionary = {}
	for index in indices:
		var neighbors: Array[int] = CELL_PHYSICS.call("query_neighbors_cached", cells, index, buckets)
		for neighbor in neighbors:
			if not lists.has(neighbor) or neighbor == index:
				continue
			var low: int = mini(index, neighbor)
			var high: int = maxi(index, neighbor)
			var key: int = low * 8001 + high
			if seen.has(key):
				continue
			seen[key] = true
			var p0: Vector2 = Vector2(pos_x[index], pos_y[index])
			var p1: Vector2 = Vector2(pos_x[neighbor], pos_y[neighbor])
			var chord: Dictionary = CHORDS.call("circle_chord", p0, _scaled_radius(cells, index), p1, _scaled_radius(cells, neighbor))
			if not bool(chord.get("valid", false)):
				continue
			var adhesion: bool = index < org_ids.size() and neighbor < org_ids.size() \
				and org_ids[index] == org_ids[neighbor] and _has_link(link_a, link_b, index, neighbor)
			var kind: int = 1 if adhesion else 0
			var la: Vector2 = _local(chord["a"])
			var lb: Vector2 = _local(chord["b"])
			(lists[index] as Array).append({"a": la, "b": lb, "kind": kind, "peer": neighbor})
			(lists[neighbor] as Array).append({"a": la, "b": lb, "kind": kind, "peer": index})
	for index in indices:
		var position: Vector2 = Vector2(pos_x[index], pos_y[index])
		var chord: Dictionary = CHORDS.call("wall_chord", position, _scaled_radius(cells, index), DISH_CENTER, DISH_RADIUS)
		if bool(chord.get("valid", false)):
			(lists[index] as Array).append({"a": _local(chord["a"]), "b": _local(chord["b"]), "kind": 2, "peer": -1})
	return lists

func _has_link(link_a: PackedInt32Array, link_b: PackedInt32Array, a: int, b: int) -> bool:
	for i in range(link_a.size()):
		if (link_a[i] == a and link_b[i] == b) or (link_a[i] == b and link_b[i] == a):
			return true
	return false

## 只读快照：全部来自真实 CellArray，无手拼标度。
func snapshot_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells: RefCounted = _cells()
	if cells == null:
		return result
	var indices: Array[int] = _live_indices(cells)
	var chord_lists: Dictionary = _build_shared_chords(cells, indices)
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	for i in indices:
		var pos: Vector2 = _local(Vector2(pos_x[i], pos_y[i]))
		var radius: float = _scaled_radius(cells, i)
		var type_id: int = int(cells.get("cell_type")[i])
		var mode_id: int = int(cells.call("get_mode", i))
		var cell_chords: Array = chord_lists.get(i, [])
		result.append({
			"index": i,
			"pos": pos,
			"radius": radius,
			"radius_scale": clampf(float(cells.call("get_radius_scale", i)), 0.5, 2.0),
			"energy": float(cells.get("cell_energy")[i]),
			"age": int(division_tick_age(cells, i)),
			"orientation": 0.0,
			"gene_slot": mode_id,
			"mode": mode_id,
			"type": type_id,
			"color": _cell_color(cells, i, type_id),
			"phase": 0.0,
			"telomere": int(cells.call("get_telomere", i)),
			"chords": cell_chords,
		})
	return result

func division_tick_age(cells: RefCounted, index: int) -> int:
	## 只读派生年龄：用真实 sim tick 差近似（division_tick>=0 时为距上次分裂的 tick）。
	var dtick: int = int(cells.call("get_division_tick", index))
	if dtick < 0:
		return _tick
	return maxi(0, _tick - dtick)

func snapshot_chords() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells: RefCounted = _cells()
	if cells == null:
		return result
	var chord_lists: Dictionary = _build_shared_chords(cells, _live_indices(cells))
	for key in chord_lists.keys():
		for chord in (chord_lists[key] as Array):
			result.append((chord as Dictionary).duplicate(true))
	return result

func snapshot_links() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells: RefCounted = _cells()
	if cells == null:
		return result
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var rest: PackedFloat32Array = cells.get("link_rest_length")
	for i in range(link_a.size()):
		result.append({"a": link_a[i], "b": link_b[i], "rest": float(rest[i]) if i < rest.size() else CELL_RADIUS * 2.0})
	return result

func consume_splits() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _pending_splits:
		var duplicate: Dictionary = (entry as Dictionary).duplicate(true)
		result.append(duplicate)
		_accum_splits.append(duplicate)
	_pending_splits.clear()
	return result

## 从合子到当前 tick 的累计分裂事件（连续时间轴指示器用；只读）。
func snapshot_accumulated_splits() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _accum_splits:
		result.append((entry as Dictionary).duplicate(true))
	return result

## Cell Lab Macro j4.I()：逐**当前细胞**派生「下一次分裂会变成什么」的指示点。
## 源码 J4.java:701-765 遍历 simulationWorld.S5[0..U5]，每个活细胞按当前基因槽画 2 点，
## 合子（Gene.o0==ZYGOCYTE）画 4 点；不是历史分裂事件的累积标记。
func snapshot_split_indicators() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells: RefCounted = _cells()
	if cells == null:
		return result
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var types: PackedByteArray = cells.get("cell_type")
	for i in _live_indices(cells):
		var mode_id: int = int(cells.call("get_mode", i))
		var gene: Dictionary = get_gene(mode_id)
		if gene.is_empty():
			continue
		# v0.50.0：Cell Lab d7 = cell.k + (镜像?-1:1)*Gene.d，分裂轴相对母细胞朝向。
		var axis_sign: float = -1.0 if bool(gene.get("child1_mirror", false)) else 1.0
		var angle: float = float(cells.call("get_orientation", i)) 			+ axis_sign * TAU * clampf(float(gene.get("child2_angle", 0.0)), 0.0, 1.0)
		result.append({
			"pos": _local(Vector2(pos_x[i], pos_y[i])),
			"angle": angle,
			"ratio": clampf(float(gene.get("split_ratio", 0.5)), 0.1, 0.9),
			"radius": _scaled_radius(cells, i),
			"gene_slot": mode_id,
			"child1_mode": clampi(int(gene.get("child1_mode", 0)), 0, maxi(0, _genes.size() - 1)),
			"child2_mode": clampi(int(gene.get("child2_mode", 0)), 0, maxi(0, _genes.size() - 1)),
			"zygote": i < types.size() and int(types[i]) == 0,
		})
	return result

func get_gene(slot: int) -> Dictionary:
	if slot < 0 or slot >= _genes.size():
		return {}
	return (_genes[slot] as Dictionary).duplicate(true)

func get_real_state_hash() -> int:
	## 只读：真实隔离模拟的状态 hash，供探针验证确定性与隔离性。
	if _mgr == null:
		return 0
	return int(_mgr.call("get_state_hash"))
