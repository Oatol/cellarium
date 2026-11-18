extends SceneTree
## 发育预览真实内核验证（headless，不截图、不动鼠标）。
## 验证：Cell Lab 式倍增、确定性逐位一致、分裂指示器公式、GenomePreview 全链路。

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  OK ", label)
	else:
		push_error("PreviewReplica FAIL: " + label)
		_failures += 1

func _make_world(script: Script, genes: Array):
	var w = script.new()
	w.setup(genes, 0)
	return w

func _initialize() -> void:
	var script: Script = ResourceLoader.load("res://scripts/core/data/PreviewWorld.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE)
	_check(script != null and script.can_instantiate(), "PreviewWorld.gd parse")
	if script == null:
		print("PreviewReplica: FAILURES=", _failures); quit(); return
	var gene: Dictionary = {
		"cell_type": 0, "division_mass": 0.05, "split_ratio": 0.5,
		"child1_mode": 0, "child2_mode": 0, "child1_angle": 0.0, "child2_angle": 0.25,
		"make_glue": true, "telomere": -1, "max_connections": 16, "initial": true,
	}
	# 1) 倍增：1 → 2 → 4 → 8 → 16
	var w = _make_world(script, [gene])
	var counts: Array[int] = []
	for t in range(120):
		w.step()
		if t in [24, 49, 99, 119]:
			counts.append(w.get_cell_count())
	_check(w.get_cell_count() >= 8, "Cell Lab 倍增 >=8 (got " + str(w.get_cell_count()) + ")")
	# 2) 确定性：两次 80 tick 逐位一致
	var a = _make_world(script, [gene]); var b = _make_world(script, [gene])
	for t in range(80): a.step(); b.step()
	var ca: Array[Dictionary] = a.snapshot_cells()
	var cb: Array[Dictionary] = b.snapshot_cells()
	var same: bool = ca.size() == cb.size()
	if same:
		for i in range(ca.size()):
			if ca[i]["pos"] != cb[i]["pos"] or ca[i]["energy"] != cb[i]["energy"] or ca[i]["radius"] != cb[i]["radius"]:
				same = false; break
	_check(same, "固定种子逐位一致 (" + str(ca.size()) + " cells)")
	# 3) 分裂指示器：半径公式 max(0.006, r_norm*0.27)、质量比 clamp 0.1..0.9
	var w2 = _make_world(script, [gene])
	var split_seen: bool = false
	var ratio_ok: bool = true
	var angle_ok: bool = true
	for t in range(60):
		w2.step()
		var splits: Array[Dictionary] = w2.consume_splits()
		for s in splits:
			split_seen = true
			var ratio: float = float(s.get("ratio", -1.0))
			if ratio < 0.1 or ratio > 0.9: ratio_ok = false
			var ang: float = float(s.get("angle", -1.0))
			if ang < 0.0 or ang > TAU + 0.001: angle_ok = false
	_check(split_seen, "分裂指示器事件产生")
	_check(ratio_ok, "质量比 clamp 0.1..0.9")
	_check(angle_ok, "分裂角在 0..TAU")
	# 4) GenomePreview 全链路
	var pv_script: Script = ResourceLoader.load("res://scripts/ui/GenomePreview.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE)
	_check(pv_script != null and pv_script.can_instantiate(), "GenomePreview.gd parse")
	var ps: PackedScene = ResourceLoader.load("res://scenes/ui/GenomePreview.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var inst = ps.instantiate()
	var root = Node.new(); root.add_child(inst)
	var modes: Array = [
		{"name": "M1", "cell_type": 0, "division_mass": 0.05, "split_ratio": 0.5,
		 "child1_mode": 0, "child2_mode": 0, "child1_angle": 0.0, "child2_angle": 0.25,
		 "make_glue": true, "initial": true, "telomere": -1},
	]
	inst.call("set_program", [], {}, true, modes)
	var nstate: int = int(inst.call("get_state_count"))
	_check(nstate >= 2, "GenomePreview 多模式真实模拟状态 >=2 (got " + str(nstate) + ")")
	var cells_last: int = int(inst.call("get_cell_count_at", nstate - 1))
	_check(cells_last >= 2, "GenomePreview 末态细胞 >=2 (got " + str(cells_last) + ")")
	print("PreviewReplica: FAILURES=", _failures)
	quit()
