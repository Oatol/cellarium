extends RefCounted
## 食物实体池（v0.14.0，版本化追加）：借鉴 Cell Lab `SimulationWorld` 的定长 `Food[]` 池方法。
## 静态证据见 analysis/CellLab_细胞物理与外观_代码级分析.md §20.3：
##   G2 = environment.Z; f1322a = new Food[G2]; f1324c = 0（active count）
##   y2(double): f729c -= 0.006*dt；<=0 时与池尾交换并 f1324c--；涂层 f731f。
##
## 边界（已修订 v1.0 §2.2 / v2.1 §0.3 / §11）：本池只读派生于营养场源项的确定型投放，
## 只承载「可见颗粒 + 诊断位置」，能量真相仍是五通道营养场。不写能量结算、不进确定性 hash、
## 不改 schema。纯 RefCounted，无 class_name，调用方 preload；不使用全局 RNG。

const CAPACITY: int = 128
## Cell Lab y2(double) 的形态：f729c -= k*dt，<=0 池尾交换回收。
## 本项目 food_spawn_amount 的质量标度与 Macro 不同，k 取 0.012/秒（约 830 tick 耗尽 0.2 质量），
## 让食物在皿内停留足够久可被细胞找到；保留线性衰减 + 池尾交换；不是 Macro 常量的逐行移植。
const MASS_DECAY: float = 0.012

var _position_x: PackedFloat32Array = PackedFloat32Array()
var _position_y: PackedFloat32Array = PackedFloat32Array()
var _mass: PackedFloat32Array = PackedFloat32Array()
var _initial_mass: PackedFloat32Array = PackedFloat32Array()
var _coating: PackedFloat32Array = PackedFloat32Array()
var _age: PackedInt32Array = PackedInt32Array()
var _active_count: int = 0

func _init(capacity: int = CAPACITY) -> void:
	var size_value: int = clampi(capacity, 1, 4096)
	_position_x.resize(size_value)
	_position_y.resize(size_value)
	_mass.resize(size_value)
	_initial_mass.resize(size_value)
	_coating.resize(size_value)
	_age.resize(size_value)
	_active_count = 0

func capacity() -> int:
	return _position_x.size()

func active_count() -> int:
	return _active_count

func clear() -> void:
	_active_count = 0

## 一次性预分配的池内追加；超容量时丢弃最旧颗粒（保持定长，不动态扩容）。
func spawn(position: Vector2, mass: float, coating: float = 0.0) -> int:
	if _active_count >= capacity():
		# Cell Lab 池尾交换回收：超容量时淘汰 0 号（最旧），把末位搬到 0 号。
		_remove_at(0)
	var index: int = _active_count
	_position_x[index] = position.x
	_position_y[index] = position.y
	_mass[index] = maxf(0.0, mass)
	_initial_mass[index] = maxf(0.0001, mass)
	_coating[index] = clampf(coating, 0.0, 1.0)
	_age[index] = 0
	_active_count += 1
	return index

## 每 tick 质量衰减；<=0 时与池尾交换并收缩 active count（Cell Lab y2(double) 方法）。
func advance(dt: float) -> int:
	var removed: int = 0
	var index: int = _active_count - 1
	while index >= 0:
		_mass[index] -= MASS_DECAY * maxf(0.0, dt)
		_age[index] += 1
		if _mass[index] <= 0.0:
			_remove_at(index)
			removed += 1
		index -= 1
	return removed

func _remove_at(index: int) -> void:
	var last: int = _active_count - 1
	if index < 0 or index > last:
		return
	if index != last:
		_position_x[index] = _position_x[last]
		_position_y[index] = _position_y[last]
		_mass[index] = _mass[last]
		_initial_mass[index] = _initial_mass[last]
		_coating[index] = _coating[last]
		_age[index] = _age[last]
	_active_count = last

func get_position(index: int) -> Vector2:
	if index < 0 or index >= _active_count:
		return Vector2.ZERO
	return Vector2(_position_x[index], _position_y[index])

func get_mass(index: int) -> float:
	if index < 0 or index >= _active_count:
		return 0.0
	return _mass[index]

func get_ratio(index: int) -> float:
	if index < 0 or index >= _active_count:
		return 0.0
	return clampf(_mass[index] / _initial_mass[index], 0.0, 1.0)

func get_coating(index: int) -> float:
	if index < 0 or index >= _active_count:
		return 0.0
	return _coating[index]

func get_age(index: int) -> int:
	if index < 0 or index >= _active_count:
		return -1
	return _age[index]

## 只读快照：供 FoodLayer 渲染与诊断，不改池状态。
func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_active_count):
		result.append({
			"position": get_position(index),
			"mass": get_mass(index),
			"ratio": get_ratio(index),
			"coating": get_coating(index),
			"age": get_age(index),
		})
	return result

func to_payload() -> Dictionary:
	return {
		"capacity": capacity(),
		"active_count": _active_count,
		"position_x": _position_x.duplicate(),
		"position_y": _position_y.duplicate(),
		"mass": _mass.duplicate(),
		"initial_mass": _initial_mass.duplicate(),
		"coating": _coating.duplicate(),
		"age": _age.duplicate(),
	}

## 存档恢复：只恢复池数据，不写场、不进 hash；容量不符则拒绝，避免半初始化实体。
func from_payload(payload: Dictionary) -> bool:
	if payload.is_empty():
		return false
	var expected: int = int(payload.get("capacity", -1))
	if expected != capacity():
		return false
	var active: int = int(payload.get("active_count", -1))
	if active < 0 or active > capacity():
		return false
	var px: PackedFloat32Array = payload.get("position_x", PackedFloat32Array())
	var py: PackedFloat32Array = payload.get("position_y", PackedFloat32Array())
	var mass: PackedFloat32Array = payload.get("mass", PackedFloat32Array())
	var initial: PackedFloat32Array = payload.get("initial_mass", PackedFloat32Array())
	var coating: PackedFloat32Array = payload.get("coating", PackedFloat32Array())
	var age: PackedInt32Array = payload.get("age", PackedInt32Array())
	if px.size() != capacity() or py.size() != capacity() or mass.size() != capacity() or initial.size() != capacity() or coating.size() != capacity() or age.size() != capacity():
		return false
	_position_x = px
	_position_y = py
	_mass = mass
	_initial_mass = initial
	_coating = coating
	_age = age
	_active_count = active
	return true
