extends SceneTree
## v0.52.2：#41 诊断闸门 —— 分裂轴与「分裂后朝向」是否解耦。
##
## 用户报的现象：分裂轴 0° 时两子代应当「一左一右」；把「子代1分裂后朝向」设成 111°，
## 位置仍应是一左一右（只是其中一个细胞转了 111°），但现在会看到偏移。
##
## 本探针把「位置偏」与「推进偏」分开量：
##   - 分裂瞬间（tick 刚完成分裂，还没跑物理）两子代相对分裂轴的**垂直偏移**；
##   - 之后跑 N tick 再量同样的量 —— 增加的部分只能来自运动（推进沿各自朝向）。
##
## 用法：console.exe --headless --path <proj> --script res://tools/SplitAxisProbe.gd

const TICKS_AFTER: int = 60
const ENERGY: float = 0.3
const SIM_TICK: int = 200

var failures: int = 0

func _initialize() -> void:
	await process_frame
	var baseline: Dictionary = await _run_case("A_axis0_off0", 0.0, 0.0, 0.0)
	var turned: Dictionary = await _run_case("B_axis0_off111", 0.0, 111.0, 0.0)
	var mirrored: Dictionary = await _run_case("C_axis90_off0", 90.0, 0.0, 0.0)
	var both: Dictionary = await _run_case("D_axis0_off111_off240", 0.0, 111.0, 240.0)

	# 1) 分裂瞬间的位置与「分裂后朝向」无关：A 与 B 的瞬间几何必须逐位相同。
	if not _same_split_geometry(baseline, turned):
		failures += 1
		print("SPLIT_AXIS: FAIL instant geometry depends on split orientation")
		print("SPLIT_AXIS:   A=%s" % [baseline.get("instant")])
		print("SPLIT_AXIS:   B=%s" % [turned.get("instant")])
	# 2) 分裂轴决定排布：两子代必须沿轴分开（沿轴分量远大于垂直分量），与母朝向无关。
	for entry in [baseline, mirrored]:
		var along: float = absf(float((entry as Dictionary).get("instant_axis_dx")))
		var across: float = absf(float((entry as Dictionary).get("instant_axis_dy")))
		if along <= across:
			failures += 1
			print("SPLIT_AXIS: FAIL offspring must separate along the split axis: along=%.3f across=%.3f (%s)" % [
				along, across, (entry as Dictionary).get("label")])
	# 3) 两子代都转向时，瞬间位置仍然不变（D 与 B 只差子代2朝向）。
	if not _same_split_geometry(baseline, both):
		failures += 1
		print("SPLIT_AXIS: FAIL instant geometry depends on child2 split orientation")
	# 4) 记录运动后的偏移，作为「推进偏」的量级证据（不作为失败条件）。
	print("SPLIT_AXIS: drift_after_%d_ticks A=%.3f B=%.3f C=%.3f D=%.3f" % [
		TICKS_AFTER, baseline.get("drift"), turned.get("drift"),
		mirrored.get("drift"), both.get("drift")])
	print("SPLIT_AXIS: RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)

## 跑一个用例，返回瞬间与 N tick 后的几何读数。
## 所有读数都在「母细胞朝向 = axis_angle」的坐标系里，避免母朝向干扰。
func _run_case(label: String, mother_orientation_deg: float, split_angle_deg: float,
		split_angle2_deg: float) -> Dictionary:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var genome: RefCounted = genome_script.new() as RefCounted
	# Genome.is_valid() 要求 traits 恰好 8 字节；缺这一步 register_zygote 直接返回 -1。
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	# FLAG_GENE_MODE = 1<<1。不置位时 is_gene_mode 为 false，modes 整段不生效，
	# 自主分裂走的是旧「dev_program + expected_cell_count」路径（max_cells 会变成 1）。
	genome.set("flags", int(genome_script.get_script_constant_map()["FLAG_GENE_MODE"]))
	genome.set("max_cells_per_organism", 8)
	genome.set("max_connections", 8)
	genome.set("min_connections", 0)
	var mode: Dictionary = {
		"name": "probe", "cell_type": 0, "child1_type": 0, "child2_type": 0,
		"child1_mode": 0, "child2_mode": 0,
		"child2_angle": 0.0,
		"split_angle": clampf(split_angle_deg / 360.0, 0.0, 1.0),
		"split_angle2": clampf(split_angle2_deg / 360.0, 0.0, 1.0),
		"child1_mirror": false, "child2_mirror": false,
		"make_glue": false, "child1_glue": false, "child2_glue": false,
		"division_mass": 0.05, "split_ratio": 0.5, "max_divisions": 0,
	}
	genome.call("set_modes", [mode])
	var org_id: int = int(manager.call("register_zygote", int(genome.call("hash")), 0, -1,
		genome, Vector2.ZERO, ENERGY, 0))
	var result: Dictionary = {"label": label, "instant": {}, "drift": 0.0,
		"instant_axis_dx": 0.0, "instant_axis_dy": 0.0}
	if org_id < 0:
		failures += 1
		print("SPLIT_AXIS: FAIL cannot register zygote for %s" % label)
		instance.queue_free()
		await process_frame
		return result
	var cells: RefCounted = manager.get("cells")
	var organisms: RefCounted = manager.get("organisms")
	var state_map: Dictionary = (load("res://scripts/core/data/OrganismStore.gd") as Script).get_script_constant_map()
	# cooldown 必须 > 0，否则 _apply_autonomous_lifecycle 直接 return。
	manager.set("autonomous_division_cooldown", 1)
	manager.set("_sim_tick", SIM_TICK)
	(organisms.get("org_state") as PackedByteArray)[org_id] = int(state_map["STATE_MATURE"])
	var orientation: float = deg_to_rad(mother_orientation_deg)
	cells.call("set_orientation", 0, orientation)
	cells.call("set_division_tick", 0, -1)
	manager.call("_apply_autonomous_lifecycle")
	if int(cells.call("size")) < 2:
		failures += 1
		print("SPLIT_AXIS: FAIL %s did not divide (cells=%d)" % [label, int(cells.call("size"))])
		print("SPLIT_AXIS:   diag enabled=%s cooldown=%d tick=%d energy=%.4f division_tick=%d org_state=%d telomere=%d" % [
			manager.get("autonomous_division_enabled"), int(manager.get("autonomous_division_cooldown")),
			int(manager.get("_sim_tick")), float((cells.get("cell_energy") as PackedFloat32Array)[0]),
			int(cells.call("get_division_tick", 0)), int((organisms.get("org_state") as PackedByteArray)[org_id]),
			int(cells.call("get_telomere", 0))])
		print("SPLIT_AXIS:   native present=%s gene=%s modes=%s maxcells=%s counts=%s thr=%s linklim=%s" % [
			manager.get("_native_org_genome_present"), manager.get("_native_org_gene_mode"),
			manager.get("_native_org_has_modes"), manager.get("_native_org_max_cells"),
			manager.get("_native_org_mode_counts"), manager.get("_native_org_mode_thresholds"),
			manager.get("_native_org_mode_link_limits")])
		instance.queue_free()
		await process_frame
		return result
	# 分裂轴 = 母朝向 + axis_sign·TAU·Gene.d；本探针 child2_angle=0 且无镜像 → 轴 = 母朝向。
	var axis: float = orientation
	result["instant"] = _geometry(cells, axis)
	result["instant_axis_dx"] = float((result["instant"] as Dictionary)["axis_dx"])
	result["instant_axis_dy"] = float((result["instant"] as Dictionary)["axis_dy"])
	for i in range(TICKS_AFTER):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		if int(cells.call("size")) < 2:
			break
	result["drift"] = absf(float((_geometry(cells, axis) as Dictionary)["axis_dy"]))
	# 打印每次的原始读数，便于人工核对。
	var inst: Dictionary = result["instant"] as Dictionary
	print("SPLIT_AXIS: case=%s axis_dx=%.3f axis_dy=%.3f perp=%.3f ori1=%.1f ori2=%.1f drift=%.3f" % [
		label, inst["axis_dx"], inst["axis_dy"], inst["perp"],
		rad_to_deg(float(inst["ori1"])), rad_to_deg(float(inst["ori2"])), result["drift"]])
	instance.queue_free()
	await process_frame
	return result

## 在「分裂轴坐标系」里量两子代：沿轴距离差（axis_dx/axis_dy）与中点偏移（perp）。
## 位置对称时 axis_dy 必须为 0（两子代在轴的同一侧偏移量相等 → 差为 0）。
## `perp` 是中点离**分裂原点**的垂直距离，反映整体漂移，不是两子代的相对偏移。
func _geometry(cells: RefCounted, axis: float) -> Dictionary:
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var dir: Vector2 = Vector2.RIGHT.rotated(axis)
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var delta: Vector2 = Vector2(pos_x[1] - pos_x[0], pos_y[1] - pos_y[0])
	var mid: Vector2 = Vector2((pos_x[0] + pos_x[1]) * 0.5, (pos_y[0] + pos_y[1]) * 0.5)
	return {
		"axis_dx": delta.dot(dir),
		"axis_dy": delta.dot(normal),
		"perp": absf(mid.dot(normal)),
		"ori1": float(cells.call("get_orientation", 0)),
		"ori2": float(cells.call("get_orientation", 1)),
	}

## 瞬间几何逐位相同：位置差在分裂轴坐标系里必须完全一致（朝向不同不影响位置）。
func _same_split_geometry(a: Dictionary, b: Dictionary) -> bool:
	var ia: Dictionary = a.get("instant", {}) as Dictionary
	var ib: Dictionary = b.get("instant", {}) as Dictionary
	if ia.is_empty() or ib.is_empty():
		return false
	return absf(float(ia["axis_dx"]) - float(ib["axis_dx"])) < 0.0001 \
		and absf(float(ia["axis_dy"]) - float(ib["axis_dy"])) < 0.0001
