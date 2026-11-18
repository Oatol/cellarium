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
	# v0.25.0：内核由真实 OrganismManager 驱动 —— 状态 hash 非零、规模受真实上限保护。
	_check(int(w.get_real_state_hash()) != 0, "真实模拟内核状态 hash 非零")
	_check(w.get_cell_count() <= 96, "真实模拟规模受上限保护 (got " + str(w.get_cell_count()) + ")")
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
	_check(int(a.get_real_state_hash()) == int(b.get_real_state_hash()), "真实模拟状态 hash 逐位一致")
	# v0.25.0：半径来自真实能量低通，表型色来自真实逐细胞数组（不是类型回退）。
	var has_real_color: bool = not ca.is_empty() and (ca[0].get("color") is Color)
	_check(has_real_color, "快照含真实逐细胞表型色")
	var radius_bounded: bool = true
	for c in ca:
		var rr: float = float(c.get("radius", -1))
		if rr < 3.4 or rr > 14.1: radius_bounded = false; break
	_check(radius_bounded, "真实半径在 7×scale(3.5–14) 区间")
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
	_check(int(inst.call("get_current_tick")) == 0, "预览时间轴默认 t=0（避免一拖就重跑）")
	var nstate: int = int(inst.call("get_state_count"))
	_check(nstate >= 2, "GenomePreview 多模式真实模拟状态 >=2 (got " + str(nstate) + ")")
	var cells_last: int = int(inst.call("get_cell_count_at", nstate - 1))
	_check(cells_last >= 2, "GenomePreview 末态细胞 >=2 (got " + str(cells_last) + ")")
	# 5) v0.24.0：细胞膜弦——分裂时刻应有圆-圆相交弦（世界坐标端点）。
	var w3 = _make_world(script, [gene])
	var chord_seen: bool = false
	var shared_chord_ok: bool = false
	for t in range(60):
		w3.step()
		var chords: Array[Dictionary] = w3.snapshot_chords()
		if not chords.is_empty():
			chord_seen = true
			# 共享弦：同一条弦分发给双方，kind/peer 字段由真实黏附/碰撞关系派生。
			var first: Dictionary = chords[0]
			if first.has("a") and first.has("b") and first.has("peer") and first.has("kind"):
				shared_chord_ok = true
			break
	_check(chord_seen, "细胞膜弦在分裂接触时生成")
	_check(shared_chord_ok, "共享弦含端点/peer/kind（与运行时同源）")
	# 6) v0.26.0：Cell Lab 同款连续时间轴——只有滑块（无上一步/播放/下一步按钮），
	#    拖动到不同 tick 从真实模拟续跑/重置，细胞数随 tick 单调递增。
	var slider = inst.find_child("Slider", true, false)
	var time_label = inst.find_child("TimeLabel", true, false)
	_check(slider != null and time_label != null, "时间轴滑块与时刻标签存在")
	_check(inst.find_child("PrevButton", true, false) == null \
		and inst.find_child("PlayButton", true, false) == null \
		and inst.find_child("NextButton", true, false) == null, "无上一步/播放/下一步按钮（Cell Lab 同款）")
	var max_tick: int = int(inst.call("get_max_tick"))
	_check(max_tick >= 1, "连续时间轴 tick 上限 >=1 (got " + str(max_tick) + ")")
	if slider != null and max_tick >= 2:
		slider.set_value(0.0)
		_check(int(inst.call("get_current_tick")) == 0, "拖到 tick 0 回到合子")
		slider.set_value(float(max_tick))
		_check(int(inst.call("get_current_tick")) == max_tick, "拖到末 tick")
		slider.set_value(float(maxi(1, max_tick / 2)))
		_check(int(inst.call("get_current_tick")) >= 1, "拖动时间轴更新当前 tick")
		# 连续时间轴的累计分裂指示器应在发育中期出现（不是空）。
		var mid_splits: int = int((inst.get("_current_state") as Dictionary).get("splits", []).size()) if inst.get("_current_state") is Dictionary else 0
		_check(mid_splits >= 1, "连续时间轴累计分裂指示器非空 (got " + str(mid_splits) + ")")
	# 7) 坐标居中修复：快照 pos 应以原点为中心（|pos| 远小于皿半径 240）。
	var w4 = _make_world(script, [gene])
	for _t in range(60): w4.step()
	var centered: bool = true
	for c in w4.snapshot_cells():
		if (c as Dictionary).get("pos", Vector2.ZERO).length() > 80.0:
			centered = false; break
	_check(centered, "预览细胞坐标已居中（不在画布外）")
	print("PreviewReplica: FAILURES=", _failures)
	quit()
