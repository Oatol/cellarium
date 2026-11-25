extends SceneTree
## v0.41 parity: EnergyLedger.record_batch vs 逐条 record() 的余额与条目内容一致。
## 账本不进 state hash；group 后 entries 顺序按 type 分组，逐条参照同样按 type 分组。

func _initialize() -> void:
	await process_frame
	var ledger_script: Script = load("res://scripts/system/EnergyLedger.gd") as Script
	var ref: RefCounted = ledger_script.new() as RefCounted
	var batched: RefCounted = ledger_script.new() as RefCounted
	# 三种 intake type，交错顺序，含 <=0 与恰 0 值。
	var groups: Dictionary = {
		4: PackedFloat64Array([0.001, 0.002, 0.0, 0.003, -0.5]),
		2: PackedFloat64Array([0.004, 0.005]),
		10: PackedFloat64Array([0.006, 0.0, 0.007]),
	}
	# 参照：按 type 升序、组内按输入顺序逐条 record。
	var keys_sorted: Array = groups.keys()
	keys_sorted.sort()
	for type_key in keys_sorted:
		for amount in (groups[type_key] as PackedFloat64Array):
			if amount > 0.0:
				ref.call("record", "ENV_TO_BIO", "E_env", "E_bio", amount, "intake_type_%d" % int(type_key))
	# 批量：同样按 type 升序分组 record_batch。
	for type_key in keys_sorted:
		batched.call("record_batch", "ENV_TO_BIO", "E_env", "E_bio", groups[type_key], "intake_type_%d" % int(type_key))

	var failures: int = 0
	for pool in ["E_env", "E_bio", "E_detritus", "E_external"]:
		var a: float = float(ref.call("get_balance", pool))
		var b: float = float(batched.call("get_balance", pool))
		if absf(a - b) > 1.0e-12:
			failures += 1
			print("LEDGER_PARITY: balance mismatch %s ref=%.12f batch=%.12f" % [pool, a, b])
	var ref_entries: Array[Dictionary] = ref.call("get_entries")
	var bat_entries: Array[Dictionary] = batched.call("get_entries")
	if ref_entries.size() != bat_entries.size():
		failures += 1
		print("LEDGER_PARITY: entries size %d vs %d" % [ref_entries.size(), bat_entries.size()])
	else:
		for i in range(ref_entries.size()):
			var a: Dictionary = ref_entries[i]
			var b: Dictionary = bat_entries[i]
			if str(a.get("action", "")) != str(b.get("action", "")) \
				or str(a.get("context", "")) != str(b.get("context", "")) \
				or absf(float(a.get("amount", 0.0)) - float(b.get("amount", 0.0))) > 1.0e-12:
				failures += 1
				print("LEDGER_PARITY: entry %d mismatch" % i)
	if not bool(ref.call("assert_conservation")) or not bool(batched.call("assert_conservation")):
		failures += 1
		print("LEDGER_PARITY: conservation failed")
	print("LEDGER_PARITY: checked=%d failures=%d entries=%d" % [
		ref_entries.size() * 4 + 8, failures, ref_entries.size()
	])
	print("LEDGER_PARITY: ", "OK" if failures == 0 else "FAIL")
	quit()
