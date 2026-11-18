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
	root.add_child(inst)  # SceneTree.root：触发 _ready 连接时间轴信号
	await process_frame   # 等 _ready 完成，时间轴信号才连上
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
	# 5) v0.24.0：细胞膜弦——分裂时刻应有圆-圆相交弦（世界坐标端点）。
	var w3 = _make_world(script, [gene])
	var chord_seen: bool = false
	for t in range(60):
		w3.step()
		if not w3.snapshot_chords().is_empty():
			chord_seen = true; break
	_check(chord_seen, "细胞膜弦在分裂接触时生成")
	# 6) v0.24.0：手动时间轴——滑块/时刻标签存在，默认暂停，拖动跳转生效。
	var slider = inst.find_child("Slider", true, false)
	var time_label = inst.find_child("TimeLabel", true, false)
	_check(slider != null and time_label != null, "时间轴滑块与时刻标签存在")
	_check(not bool(inst.call("is_playing")), "默认暂停（手动时间轴）")
	if slider != null and nstate >= 2:
		slider.set_value(float(nstate - 1))
		_check(int(inst.call("get_cursor")) == nstate - 1, "拖动时间轴跳转到末态")
	print("PreviewReplica: FAILURES=", _failures)
	quit()
