extends SceneTree
## v0.29.0 分裂对齐探针：40 槽分化树、旧连接方向重分配、FLAG 后向连接校验。
## 程序化无头验证，不依赖截图/鼠标。

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  OK ", label)
	else:
		push_error("DivisionAlignment FAIL: " + label)
		_failures += 1

func _initialize() -> void:
	var genome_script: Script = ResourceLoader.load("res://scripts/core/data/Genome.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE)
	var manager_script: Script = ResourceLoader.load("res://scripts/system/OrganismManager.gd", "Script", ResourceLoader.CACHE_MODE_IGNORE)
	_check(genome_script != null and genome_script.can_instantiate(), "Genome.gd parse")
	_check(manager_script != null and manager_script.can_instantiate(), "OrganismManager.gd parse")
	if genome_script == null or manager_script == null:
		print("DivisionAlignment: FAILURES=", _failures); quit(); return

	# 1) 40 槽分化树：官方 Gene.i/j 对应 child1_mode/child2_mode，槽 39 不再被钳回 15。
	var max_modes: int = int(genome_script.get_script_constant_map().get("MAX_GENOME_MODES", 0))
	_check(max_modes == 40, "分化树槽上限 40 (got %d)" % max_modes)
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"cell_type": 0, "child1_mode": 39, "child2_mode": 27,
		"link_keep_mother": true, "link_keep_child": true,
	}, 0)
	_check(int(mode.get("child1_mode", -1)) == 39 and int(mode.get("child2_mode", -1)) == 27, \
		"Gene.i/j 槽 39/27 保留")
	_check(bool(mode.get("link_keep_mother", false)) and bool(mode.get("link_keep_child", false)), \
		"Gene.m/n 模式字段落地")

	# 2) 旧连接重分配：分裂轴 0（向右），正向邻居归子、反向邻居归母。
	var manager: Node = manager_script.new() as Node
	var cells: RefCounted = manager.get("cells") as RefCounted
	var mother: int = int(cells.call("append_cell", 1, Vector2(0, 0), 0.5, 0))
	var child: int = int(cells.call("append_cell", 1, Vector2(1, 0), 0.25, 0))
	var front: int = int(cells.call("append_cell", 1, Vector2(20, 0), 0.5, 0))
	var back: int = int(cells.call("append_cell", 1, Vector2(-20, 0), 0.5, 0))
	var ok_front: bool = bool(cells.call("link_cells", mother, front, 20.0))
	var ok_back: bool = bool(cells.call("link_cells", mother, back, 20.0))
	_check(ok_front and ok_back, "重分配测试连接建立")
	manager.call("_redistribute_inherited_links", mother, child, 0.0, 0.5, mode)
	_check(bool(cells.call("has_link", child, front)) and not bool(cells.call("has_link", mother, front)), \
		"正向旧连接按 Gene.n 归子")
	_check(bool(cells.call("has_link", mother, back)) and not bool(cells.call("has_link", child, back)), \
		"反向旧连接按 Gene.m 归母")
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	_check(int(link_counts[mother]) == 1 and int(link_counts[child]) == 1 \
		and int(link_counts[front]) == 1 and int(link_counts[back]) == 1, \
		"重分配后连接计数守恒")

	# 3) FLAG 后向连接校验：朝向 0 时，链接指向 PI 为后向。
	var flag: int = int(cells.call("append_cell", 1, Vector2(0, 0), 0.5, 3))
	var flag_front: int = int(cells.call("append_cell", 1, Vector2(20, 0), 0.5, 3))
	var flag_back: int = int(cells.call("append_cell", 1, Vector2(-20, 0), 0.5, 3))
	cells.call("set_orientation", flag, 0.0)
	cells.call("link_cells", flag, flag_front, 20.0)
	cells.call("link_cells", flag, flag_back, 20.0)
	_check(bool(manager.call("_has_backward_link", flag)), "FLAG 后向连接 cos<-0.8 判死")
	var normal: int = int(cells.call("append_cell", 1, Vector2(0, 0), 0.5, 4))
	cells.call("link_cells", normal, flag_front, 20.0)
	_check(not bool(manager.call("_has_backward_link", normal)), "非 FLAG 类型不触发后向判死")

	manager.free()
	print("DivisionAlignment: FAILURES=", _failures)
	quit()
