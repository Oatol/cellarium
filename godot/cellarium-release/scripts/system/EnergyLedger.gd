extends RefCounted
## 能量守恒账本（v2.1 §4.3）。E_total = E_env + ΣE_bio + E_detritus + E_external。
## 逐项借记/贷记，任何一项缺失都能定位到具体账目动作；不参与玩法计算，不进确定性 hash。
## 纯 RefCounted，无 class_name，调用方 preload。所有数值为 float64 以降低累计误差。

const ACTION_TOOL_TO_ENV: String = "TOOL_TO_ENV"
const ACTION_ENV_TO_BIO: String = "ENV_TO_BIO"
const ACTION_BIO_TO_BIO: String = "BIO_TO_BIO"
const ACTION_BIO_TO_ENV: String = "BIO_TO_ENV"
const ACTION_INTERNAL_REDIST: String = "INTERNAL_REDIST"

var _balances: Dictionary = {"E_env": 0.0, "E_bio": 0.0, "E_detritus": 0.0, "E_external": 0.0}
var _initial_balances: Dictionary = {"E_env": 0.0, "E_bio": 0.0, "E_detritus": 0.0, "E_external": 0.0}
var _entries: Array[Dictionary] = []
var _max_entries: int = 256
var _violations: int = 0

func configure(max_entries: int = 256) -> void:
	_max_entries = maxi(1, max_entries)

func reset() -> void:
	_balances = {"E_env": 0.0, "E_bio": 0.0, "E_detritus": 0.0, "E_external": 0.0}
	_initial_balances = {"E_env": 0.0, "E_bio": 0.0, "E_detritus": 0.0, "E_external": 0.0}
	_entries.clear()
	_violations = 0

func set_balance(pool: String, value: float) -> void:
	if _balances.has(pool):
		_balances[pool] = value
		_initial_balances[pool] = value

func get_balance(pool: String) -> float:
	return float(_balances.get(pool, 0.0))

func total() -> float:
	return get_balance("E_env") + get_balance("E_bio") + get_balance("E_detritus") + get_balance("E_external")

func violation_count() -> int:
	return _violations

func entry_count() -> int:
	return _entries.size()

## 记一笔成对账目：从 debit_pool 借 amount，贷记 credit_pool。
## 允许 amount<=0（视为空操作，不记账）。返回是否成功入账。
func record(action: String, debit_pool: String, credit_pool: String, amount: float, context: String = "") -> bool:
	if amount <= 0.0 or not is_finite(amount):
		return false
	if not _balances.has(debit_pool) or not _balances.has(credit_pool):
		_violations += 1
		return false
	_balances[debit_pool] = float(_balances[debit_pool]) - amount
	_balances[credit_pool] = float(_balances[credit_pool]) + amount
	if _entries.size() >= _max_entries:
		_entries.pop_front()
	_entries.append({
		"action": action,
		"debit": debit_pool,
		"credit": credit_pool,
		"amount": amount,
		"context": context
	})
	return true

## v0.41.0：批量记同类型账目。语义等价于对 amounts 中每个 amount>0 逐条 record()，
## 但把 1025 次 GDScript 调用压成 1 次：Dictionary 池查找/balance 更新各做一次，
## entries 仍按输入顺序逐条追加并按 _max_entries 截断，因此条目内容与顺序一致。
## amount<=0 或非有限值跳过（与 record() 的空操作语义一致）；返回成功入账条数。
func record_batch(action: String, debit_pool: String, credit_pool: String, amounts: PackedFloat64Array, context: String) -> int:
	if not _balances.has(debit_pool) or not _balances.has(credit_pool):
		_violations += 1
		return 0
	var debit_value: float = float(_balances[debit_pool])
	var credit_value: float = float(_balances[credit_pool])
	# v0.49.0：单遍扫描。原实现扫两遍（先统计有效条数与余额增量，再扫一遍挑最后
	# _max_entries 条），1142 条时约 392 µs。这里第一遍就用环形缓冲记下尾部候选，
	# 第二遍完全省掉；索引循环 + typed 取值也避免了 for-in 的 Variant 装箱。
	var count: int = amounts.size()
	var tail: PackedFloat64Array = PackedFloat64Array()
	tail.resize(_max_entries)
	var valid_count: int = 0
	var tail_pos: int = 0
	for index in range(count):
		var amount: float = amounts[index]
		if amount <= 0.0 or not is_finite(amount):
			continue
		debit_value -= amount
		credit_value += amount
		tail[tail_pos] = amount
		tail_pos += 1
		if tail_pos >= _max_entries:
			tail_pos = 0
		valid_count += 1
	_balances[debit_pool] = debit_value
	_balances[credit_pool] = credit_value
	if valid_count == 0:
		return 0
	var new_count: int = mini(valid_count, _max_entries)
	# 只有容量真的溢出才淘汰旧条目。原来逐条 pop_front()（每次 O(n) 位移），
	# 这里一次性裁掉头部，代价一次 O(n)。
	var overflow: int = maxi(0, _entries.size() + new_count - _max_entries)
	if overflow > 0:
		var kept: Array[Dictionary] = []
		kept.resize(_entries.size() - overflow)
		for index in range(overflow, _entries.size()):
			kept[index - overflow] = _entries[index]
		_entries = kept
	# 环形缓冲的读起点：溢出时 tail_pos 正好指向最旧的一条；未溢出时从 0 开始。
	var start: int = 0 if valid_count < _max_entries else tail_pos
	for step in range(new_count):
		_entries.append({
			"action": action,
			"debit": debit_pool,
			"credit": credit_pool,
			"amount": tail[(start + step) % _max_entries],
			"context": context,
		})
	return valid_count

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

## 断言：所有账目的借贷净额必须与各池余额一致。
## 由于池余额由 record() 直接维护，这里校验的是"账目自洽"：Σ(amount) 借贷成对。
func assert_conservation(tolerance: float = 0.01) -> bool:
	var net: Dictionary = {"E_env": 0.0, "E_bio": 0.0, "E_detritus": 0.0, "E_external": 0.0}
	for entry in _entries:
		var amount: float = float(entry.get("amount", 0.0))
		net[entry.get("debit", "")] = float(net.get(entry.get("debit", ""), 0.0)) - amount
		net[entry.get("credit", "")] = float(net.get(entry.get("credit", ""), 0.0)) + amount
	for pool in net:
		var expected: float = float(_initial_balances.get(pool, 0.0)) + float(net[pool])
		if absf(expected - get_balance(pool)) > tolerance:
			_violations += 1
			return false
	return _violations == 0

func get_snapshot() -> Dictionary:
	return {
		"E_env": get_balance("E_env"),
		"E_bio": get_balance("E_bio"),
		"E_detritus": get_balance("E_detritus"),
		"E_external": get_balance("E_external"),
		"total": total(),
		"violations": _violations,
		"entries": _entries.size(),
		"initial": _initial_balances.duplicate(),
		"entry_list": _entries.duplicate(true)
	}

## 从存档恢复账本余额、初始余额与流水（§3.5）。_max_entries 是配置，不随存档改。
func restore_snapshot(snapshot: Dictionary) -> void:
	_balances = {
		"E_env": float(snapshot.get("E_env", 0.0)),
		"E_bio": float(snapshot.get("E_bio", 0.0)),
		"E_detritus": float(snapshot.get("E_detritus", 0.0)),
		"E_external": float(snapshot.get("E_external", 0.0))
	}
	_initial_balances = (snapshot.get("initial", {}) as Dictionary).duplicate()
	_entries.clear()
	for entry in snapshot.get("entry_list", []):
		if entry is Dictionary:
			_entries.append((entry as Dictionary).duplicate(true))
	_violations = int(snapshot.get("violations", 0))
