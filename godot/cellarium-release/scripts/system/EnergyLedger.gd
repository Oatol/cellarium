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
