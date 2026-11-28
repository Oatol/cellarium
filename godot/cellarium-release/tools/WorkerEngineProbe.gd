extends Node
## B3 运行探针：生产规模、完整 tick 链、CPU 场、native 开启。
## 验证 WorkerSimEngine 的 worker 权威态与主线程同配置顺序执行逐位一致，
## 并验证快照写回主场景 CellArray 后细胞数/首细胞坐标不撕裂。

const OM_SCRIPT: Script = preload("res://scripts/system/OrganismManager.gd")
const EM_SCRIPT: Script = preload("res://scripts/system/EnvironmentManager.gd")
const TM_SCRIPT: Script = preload("res://scripts/core/tick/TickCore.gd")
const FIELD_SCRIPT: Script = preload("res://scripts/system/EnvironmentField.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const ENGINE_SCRIPT: Script = preload("res://scripts/system/WorkerSimEngine.gd")

const DT: float = 1.0 / 60.0
const DISH_CENTER: Vector2 = Vector2(250.0, 250.0)
const DISH_RADIUS: float = 240.0
const TARGET_CELLS: int = 512
const RUN_TICKS: int = 30

var _engine: RefCounted = null
var _worlds: Array[Node] = []
var _report: PackedStringArray = PackedStringArray()
var target_cells: int = TARGET_CELLS
var run_ticks: int = RUN_TICKS
var speed_scale: float = 1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cells="):
			target_cells = maxi(64, int(arg.substr(8)))
		elif arg.begins_with("--ticks="):
			run_ticks = clampi(int(arg.substr(8)), 1, 10000)
		elif arg.begins_with("--speed="):
			speed_scale = clampf(float(arg.substr(8)), 0.0, 32.0)
	var mirror: Array = _build_world()
	var sequential: Array = _build_world()
	for world in [mirror, sequential]:
		var mgr_node: Node = world[0] as Node
		var env_node: Node = world[1] as Node
		var tc_node: Node = world[2] as Node
		_worlds.append(mgr_node)
		_worlds.append(env_node)
		_worlds.append(tc_node)
	var mirror_mgr: Node = mirror[0]
	var mirror_env: Node = mirror[1]
	var seq_mgr: Node = sequential[0]
	var seq_env: Node = sequential[1]
	var seq_tc: Node = sequential[2]
	mirror[2].call("apply_speed", speed_scale)
	seq_tc.call("apply_speed", speed_scale)

	# 主线程 native 预热；顺序执行本身也会预热，但 worker 世界由引擎在主线程预热。
	for i in range(2):
		seq_mgr.call("advance_physics_tick", DT)
		seq_env.call("advance_field_tick")
	# 回退到 tick 0 的干净状态：两张世界都由同一 snapshot 重新灌入。
	var clean: Dictionary = _capture_clean(mirror_mgr, mirror_env, mirror[2])
	var clean_field: Dictionary = clean.get("field", {}) as Dictionary
	if not bool(load("res://scripts/system/SaveManager.gd").restore(clean, seq_mgr, seq_env, seq_tc)):
		_fail("sequential restore failed")
		return
	if not bool(load("res://scripts/system/SaveManager.gd").restore(clean, mirror_mgr, mirror_env, mirror[2])):
		_fail("mirror restore failed")
		return
	var helper: RefCounted = ENGINE_SCRIPT.new() as RefCounted
	var repair_defaults: PackedFloat32Array = PackedFloat32Array([1.2, 273.0, 1.0, 1.0, 0.0])
	helper.call("repair_field_after_restore", seq_env.get("field"), clean_field, repair_defaults, false)
	helper.call("repair_field_after_restore", mirror_env.get("field"), clean_field, repair_defaults, false)

	_engine = ENGINE_SCRIPT.new() as RefCounted
	if not bool(_engine.call("configure", mirror_mgr, mirror_env, mirror[2])):
		_fail("engine configure failed: %s" % str(_engine.get("diag_last_error")))
		return
	var mirror_field: RefCounted = mirror_env.get("field") as RefCounted
	var mirror_pending: Array = mirror_field.get("_pending_sources") as Array
	var mirror_pending_signal: int = 0
	if mirror_pending.size() > 4:
		mirror_pending_signal = (mirror_pending[4] as PackedFloat32Array).size()
	_push("PROBE_FIELD mirror_res=%d pending=%d worker_res=%d pending=%d" % [
		int(mirror_field.get("resolution")), mirror_pending_signal,
		int(_engine.get("diag_field_resolution")), int(_engine.get("diag_pending_signal_size")),
	])
	if not bool(_engine.call("start")):
		_fail("engine start failed: %s" % str(_engine.get("diag_last_error")))
		return
	_engine.call("set_speed", speed_scale)
	var worker_start_us: int = Time.get_ticks_usec()
	_engine.call("set_target", run_ticks)
	_engine.call("request_state_hash_at", run_ticks)

	for i in range(run_ticks):
		_step_world(seq_mgr, seq_env, seq_tc, i + 1)
	var main_hash: int = int(seq_mgr.call("get_state_hash"))

	var waited: int = 0
	var worker_hash: int = 0
	while waited < 10000:
		worker_hash = int(_engine.call("get_state_hash"))
		if worker_hash != 0 and int(_engine.call("get_worker_tick")) >= run_ticks:
			break
		OS.delay_msec(1)
		waited += 1

	var worker_elapsed_us: int = maxi(1, Time.get_ticks_usec() - worker_start_us)
	_push("PROBE_THROUGHPUT ticks=%d elapsed_ms=%.1f us_per_tick=%.1f" % [
		run_ticks, float(worker_elapsed_us) / 1000.0, float(worker_elapsed_us) / float(run_ticks),
	])
	_push("PROBE_SPLIT speed=%.1fx org=%.1f dev=%.1f nutrient=%.1f food=%.1f field=%.1f snapshot=%.1f us" % [
		speed_scale,
		float(int(_engine.get("diag_org_us"))) / float(run_ticks),
		float(int(_engine.get("diag_dev_us"))) / float(run_ticks),
		float(int(_engine.get("diag_nutrient_us"))) / float(run_ticks),
		float(int(_engine.get("diag_food_us"))) / float(run_ticks),
		float(int(_engine.get("diag_field_us"))) / float(run_ticks),
		float(int(_engine.get("diag_snapshot_us"))) / float(run_ticks),
	])
	var stages: Dictionary = _engine.call("get_worker_stage_averages") as Dictionary
	var stage_keys: Array[String] = ["behavior", "physics", "metabolism", "signal", "metab_fields", "metab_rates", "metab_links", "metab_base", "metab_env", "metab_radius", "metab_lifecycle", "beh_collect", "beh_eval", "beh_apply", "phys_collision", "phys_verlet", "total"]
	var stage_line: String = "PROBE_STAGES"
	for key in stage_keys:
		if stages.has(key):
			stage_line += " %s=%.1f" % [key, float(stages.get(key))]
	_push(stage_line)
	_engine.call("sync_main_state")
	var cells: RefCounted = mirror_mgr.get("cells") as RefCounted
	var seq_cells: RefCounted = seq_mgr.get("cells") as RefCounted
	var px: PackedFloat32Array = cells.get("cell_pos_x") as PackedFloat32Array
	var spx: PackedFloat32Array = seq_cells.get("cell_pos_x") as PackedFloat32Array
	var first_pos_match: bool = px.size() > 0 and spx.size() > 0 and is_equal_approx(px[0], spx[0])

	_push("PROBE_SETUP cells=%d native=%s ticks=%d" % [
		int(cells.call("size")), str(mirror_mgr.get("native_spatial_enabled")), run_ticks,
	])
	_push("PROBE_SEQ hash=%d cells=%d" % [main_hash, int(seq_cells.call("size"))])
	_push("PROBE_WORKER hash=%d ticks=%d wait_ms=%d" % [
		worker_hash, int(_engine.call("get_worker_tick")), waited,
	])
	_push("PROBE_SNAPSHOT cells=%d first_pos_match=%s" % [
		int(cells.call("size")), str(first_pos_match),
	])
	var ok: bool = worker_hash != 0 and worker_hash == main_hash and first_pos_match and int(cells.call("size")) == int(seq_cells.call("size"))
	_push("PROBE_VERDICT %s match=%s" % ["OK" if ok else "FAIL", str(worker_hash == main_hash)])
	_finish()


func _build_world() -> Array:
	var env: Node = EM_SCRIPT.new() as Node
	env.set("light_source_mode", 0)
	env.set("light_intensity", 1.0)
	env.set("nutrient_density", 1.2)
	env.set("oxygen_fraction", 1.0)
	env.set("food_spawn_amount", 0.0)
	env.set("dish_center", DISH_CENTER)
	env.set("dish_radius", DISH_RADIUS)
	var field: RefCounted = env.get("field") as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([1.2, 273.0, 1.0, 1.0, 0.0])
	field.call("configure", 32, DISH_CENTER, DISH_RADIUS, defaults, false)
	var res: int = int(field.get("resolution"))
	var light_values: PackedFloat32Array = PackedFloat32Array()
	light_values.resize(res * res)
	light_values.fill(1.0)
	field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_LIGHT, light_values)
	env.call("apply_light_settings")

	var tc: Node = TM_SCRIPT.new() as Node
	tc.call("apply_speed", 1.0)
	var mgr: Node = OM_SCRIPT.new() as Node
	mgr.set("environment_manager", env)
	mgr.set("tick_core", tc)
	mgr.set("dish_center", DISH_CENTER)
	mgr.set("dish_radius", DISH_RADIUS)
	mgr.set("cell_radius", 7.0)
	mgr.set("autonomous_division_enabled", false)
	mgr.set("native_spatial_enabled", true)
	mgr.call("_ready")

	var genome: RefCounted = GENOME_SCRIPT.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.set("flags", int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GENE_MODE", 2))
		| int(GENOME_SCRIPT.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
	genome.set("division_mass", 0.05)
	genome.set("max_cells_per_organism", int(GENOME_SCRIPT.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
	genome.call("set_modes", genome.call("solo_photo_modes"))
	var spacing: float = 13.0
	var spawned: int = 0
	var row: int = -30
	while spawned < target_cells and row <= 30:
		var y: float = float(row) * spacing * 0.866
		var col: int = -30
		while col <= 30 and spawned < target_cells:
			var x: float = float(col) * spacing + float(absi(row) % 2) * spacing * 0.5
			if x * x + y * y <= (DISH_RADIUS - 8.0) * (DISH_RADIUS - 8.0):
				mgr.call("register_zygote", 300000 + spawned, 0, -1, genome, DISH_CENTER + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1
	return [mgr, env, tc]


func _capture_clean(mgr: Node, env: Node, tc: Node) -> Dictionary:
	return load("res://scripts/system/SaveManager.gd").capture(mgr, env, tc)


func _step_world(mgr: Node, env: Node, tc: Node, tick_number: int) -> void:
	tc.set("tick_index", tick_number)
	mgr.call("advance_physics_tick", DT)
	mgr.call("advance_development_tick")
	env.call("apply_nutrient_sources", tick_number)
	env.call("advance_food_entities", DT)
	env.call("advance_field_tick")


func _fail(reason: String) -> void:
	_push("PROBE_FAIL " + reason)
	_finish()


func _push(line: String) -> void:
	print(line)
	_report.append(line)


func _finish() -> void:
	if _engine != null:
		_engine.call("dispose")
		_engine = null
	for node in _worlds:
		if is_instance_valid(node):
			node.free()
	_worlds.clear()
	var file: FileAccess = FileAccess.open("user://worker_engine_probe.txt", FileAccess.WRITE)
	if file != null:
		for line in _report:
			file.store_line(line)
		file.close()
	print("PROBE_FILE ", ProjectSettings.globalize_path("user://worker_engine_probe.txt"))
	get_tree().quit()
