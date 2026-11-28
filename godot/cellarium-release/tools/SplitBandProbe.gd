extends SceneTree
## 分裂几何闸门（v0.50.0 建立，v0.51.0 修正口径）
##   1) 分裂轴相对母细胞朝向（Cell Lab d7 = cell.k + Gene.d）：Gene.d=0 时子代沿母朝向延续。
##   2) 黏附以 Gene.l（生成黏附素）为准：make_glue=false 且未开额外子代开关时，分裂后**零连接**。
##
## 读数口径（v0.51.0 纠错，重要）：
##   - `glue_on_d0` 这类「所有细胞都继续分裂」的用例，32 个直径 14 的细胞必然挤成紧凑菌落
##     （span ≈ 56×37），elongation 1.3~1.5 是**正确**的二维堆叠，不是缺陷。
##   - 真正衡量「长带」的是 `chain_glue_on`：子代继续当干细胞（child1=终末、child2=干），
##     沿母朝向一节节接长，理想值是 8 条 14 单位连杆 → span_x=112、span_y=0。
##   - `chain_nobehavior` / `no_behavior_d0` 是**对照组**（neural_weights 清零 → 零推力）。
##     零推力时细胞从不离开共线解，span_y 恒为 0，因此它们只用来隔离「游动是否把链揉成团」，
##     不能当作几何目标值。
##
## v0.51.0 结论：链被揉成团的根因是**逐细胞推进速度不同 + 刚性连杆** → 链条受压屈曲。
##   对照：chain_nobehavior 112.0×0.0 / chain_glue_on（修复前）32.8×19.4。
##   修复：CellBehavior 位移改为「沿细胞朝向 + 同个体平均推进」，见 build_organism_thrust()。
##
## 程序化、无鼠标、ASCII 输出。用法：
##   godot --headless --path <proj> --script res://tools/SplitBandProbe.gd

const SAMPLE_TICKS: int = 240
const TARGET_CELLS: int = 32
## 丝状链伸长比下限：修复前 1.69（手风琴折叠），修复后 6.61，理想 112。取 4.0 作闸门。
const CHAIN_MIN_ELONGATION: float = 4.0

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	await process_frame
	await _run_case("glue_on_d0", true, 0.0, false)
	await _run_case("glue_off_d0", false, 0.0, false)
	await _run_case("glue_on_d90", true, 0.25, false)
	# 丝状链：母细胞切成终末模式 M2（不再分裂），**新细胞**留在干细胞 M1 继续分裂，
	# 于是链沿母朝向一节节接长。模式槽接反（母留 M1）会长成星形而不是链。
	await _run_case("chain_glue_on", true, 0.0, true)
	await _run_case("chain_nobehavior", true, 0.0, true, true)
	# 关掉神经/行为：把权重清零，输出恒 0 → 细胞不自游。用来隔离「游动把链条揉成团」。
	await _run_case("no_behavior_d0", true, 0.0, false, true)
	print("SPLIT_BAND RESULT checks=%d failures=%d" % [_checks, _failures])
	quit(0)

func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("SPLIT_CHECK %s %s %s" % ["PASS" if ok else "FAIL", label, detail])

func _run_case(label: String, make_glue: bool, child2_angle: float, chain: bool, mute_behavior: bool = false) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	# v0.51.0：质量上限 0.36 之后「靠出生能量连裂」不再成立——必须让细胞真的光合产能，
	# 否则 8.0 的出生能量会被钳到 0.36，只够裂 3 代（8 细胞）。只关掉基础代谢消耗，保留产能。
	manager.set("base_metabolic_cost", 0.0)
	manager.set("movement_energy_cost", 0.0)
	manager.set("autonomous_division_cooldown", 1)
	manager.set("default_transfer_rate", 0.0)
	var cells: RefCounted = manager.get("cells")

	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2)))
	genome.set("division_mass", 0.05)
	genome.set("split_ratio", 0.5)
	genome.set("max_divisions", 8)
	genome.set("max_cells_per_organism", -1)
	genome.set("transfer_rate", 0.0)
	var mode: Dictionary = genome_script.call("normalized_mode", {
		"name": "M1", "cell_type": 0,
		"child1_mode": 1 if chain else 0, "child2_mode": 0,
		"make_glue": make_glue,
		"child1_glue": false, "child2_glue": false,
		"child1_angle": 0.0, "child2_angle": child2_angle,
		"split_angle": 0.0, "split_angle2": 0.0,
		"division_mass": 0.05, "max_divisions": 8,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 0)
	var terminal: Dictionary = genome_script.call("normalized_mode", {
		"name": "M2", "cell_type": 4,
		"child1_mode": 1, "child2_mode": 1,
		"make_glue": make_glue,
		"division_mass": 100.0,
		"link_division_limit": -1, "telomere": -1,
		"cell_size": 1.0, "split_ratio": 0.5, "transfer_rate": 0.0,
	}, 1)
	genome.call("set_modes", [mode, terminal])
	# 母细胞朝向固定为 0（+X），这样「沿轴跨度」就是 X 方向跨度。
	manager.call("register_zygote", 99, 99, -1, genome, Vector2(250, 250), 8.0, 0)
	var alive: PackedByteArray = cells.get("cell_alive")
	for index in range(alive.size()):
		if alive[index] != 0:
			cells.call("set_orientation", index, 0.0)
			break

	if mute_behavior:
		var weights: PackedFloat32Array = cells.get("neural_weights")
		weights.fill(0.0)
		cells.set("neural_weights", weights)
	for tick in range(SAMPLE_TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells.call("size")) >= TARGET_CELLS:
			break

	alive = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var min_x: float = 1e9
	var max_x: float = -1e9
	var min_y: float = 1e9
	var max_y: float = -1e9
	var live: int = 0
	for index in range(alive.size()):
		if alive[index] == 0:
			continue
		live += 1
		min_x = minf(min_x, pos_x[index])
		max_x = maxf(max_x, pos_x[index])
		min_y = minf(min_y, pos_y[index])
		max_y = maxf(max_y, pos_y[index])
	var links: int = 0
	for index in range(link_a.size()):
		if link_a[index] >= 0 and link_b[index] >= 0:
			links += 1
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	var orientations: PackedFloat32Array = cells.get("cell_orientation")
	var sum_fwd: float = 0.0
	var sum_steer: float = 0.0
	var sum_orient: float = 0.0
	var live2: int = 0
	for index in range(alive.size()):
		if alive[index] == 0:
			continue
		live2 += 1
		sum_fwd += absf(float(intents[index * 6]))
		sum_steer += absf(float(intents[index * 6 + 1]))
		sum_orient += absf(float(orientations[index]))
	var denom: float = float(maxi(1, live2))
	print("SPLIT_INTENT fwd=%.4f steer=%.4f orient_abs=%.3f" % [
		sum_fwd / denom, sum_steer / denom, sum_orient / denom,
	])
	var span_x: float = maxf(0.0, max_x - min_x)
	var span_y: float = maxf(0.0, max_y - min_y)
	var elongation: float = span_x / maxf(1.0, span_y)
	print("SPLIT_BAND case=%s cells=%d links=%d span_x=%.1f span_y=%.1f elongation=%.2f" % [
		label, live, links, span_x, span_y, elongation,
	])
	match label:
		"glue_off_d0":
			_check(label, links == 0, "links=%d" % links)
		"glue_on_d0":
			_check(label, links > 0 and live >= 16, "links=%d cells=%d" % [links, live])
		"chain_glue_on":
			_check(label, links >= 6 and elongation >= CHAIN_MIN_ELONGATION,
				"links=%d elongation=%.2f" % [links, elongation])
		"chain_nobehavior":
			# 对照组：零推力下必须完全共线，否则说明共线解本身就被破坏了。
			_check(label, span_y < 0.5, "span_y=%.1f" % span_y)
	instance.queue_free()
	await process_frame
