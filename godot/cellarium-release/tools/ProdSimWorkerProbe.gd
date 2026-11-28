extends Node
## 阶段 B B2 决定性验证：生产级 OrganismManager（1024 细胞、native FFI）+ CPU 场，
## 在 worker 线程跑完整 tick 链，与主线程同配置跑相同 tick，比较 state hash 逐位一致。
## 与 WorkerSimProbe 的区别：这个是全尺寸生产配置（cell_radius=7 纹理分辨率 64、
## 1024 细胞、native 开启），验证"生产规模在 worker 仍确定性"。
## 只读探针，跑完自动退出，输出 user://prod_sim_worker_probe.txt。

const OM_SCRIPT: Script = preload("res://scripts/system/OrganismManager.gd")
const EM_SCRIPT: Script = preload("res://scripts/system/EnvironmentManager.gd")
const FIELD_SCRIPT: Script = preload("res://scripts/system/EnvironmentField.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const DISH_CENTER: Vector2 = Vector2(250.0, 250.0)
const DISH_RADIUS: float = 240.0
const TARGET_CELLS: int = 512
const RUN_TICKS: int = 30

var _thread: Thread = null
var _worker_mgr: Node = null
var _worker_env: Node = null
var _worker_hash: int = 0
var _worker_error: String = ""
var _done: bool = false
var _report_lines: PackedStringArray = PackedStringArray()

func _ready() -> void:
	# 主线程构建两套隔离的生产级模拟（CPU 场）
	var main_world: Array = _build_world()
	var worker_world: Array = _build_world()
	var main_mgr: Node = main_world[0]
	var main_env: Node = main_world[1]
	_worker_mgr = worker_world[0]
	_worker_env = worker_world[1]

	# 主线程预热 native（worker 内禁止 new Object）
	for i in range(2):
		main_mgr.call("advance_physics_tick", 1.0 / 60.0)
		main_env.call("advance_field_tick")
		_worker_mgr.call("advance_physics_tick", 1.0 / 60.0)
		_worker_env.call("advance_field_tick")

	_push("PROBE_SETUP main_cells=%d worker_cells=%d native=%s" % [
		int((main_mgr.get("cells") as RefCounted).call("size")),
		int((_worker_mgr.get("cells") as RefCounted).call("size")),
		str(_worker_mgr.get("native_spatial_enabled")),
	])

	# worker 跑
	_thread = Thread.new()
	var err: int = _thread.start(Callable(self, "_worker_loop"))
	if err != OK:
		_push("FAIL_STATE thread.start err=%d" % err)
		_finish()
		return

	# 主线程跑
	for i in range(RUN_TICKS):
		main_mgr.call("advance_physics_tick", 1.0 / 60.0)
		main_env.call("advance_field_tick")
	var main_hash: int = int(main_mgr.call("get_state_hash"))
	_push("PROBE_MAIN hash=%d cells=%d" % [main_hash, int((main_mgr.get("cells") as RefCounted).call("size"))])

	_thread.wait_to_finish()
	_push("PROBE_WORKER hash=%d cells=%d error=%s" % [
		_worker_hash, int((_worker_mgr.get("cells") as RefCounted).call("size")),
		_worker_error if not _worker_error.is_empty() else "none",
	])
	var verdict: String = "FAIL"
	if _worker_error.is_empty() and _worker_hash == main_hash:
		verdict = "OK"
	_push("PROBE_VERDICT %s match=%s" % [verdict, str(_worker_hash == main_hash)])
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
	if field != null:
		var defaults: PackedFloat32Array = PackedFloat32Array([1.2, 273.0, 1.0, 1.0, 0.0])
		field.call("configure", 64, DISH_CENTER, DISH_RADIUS, defaults, false)
		var res: int = int(field.get("resolution"))
		var light_values: PackedFloat32Array = PackedFloat32Array()
		light_values.resize(res * res)
		light_values.fill(1.0)
		field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_LIGHT, light_values)
	env.call("apply_light_settings")

	var mgr: Node = OM_SCRIPT.new() as Node
	mgr.set("environment_manager", env)
	mgr.set("tick_core", null)
	mgr.set("dish_center", DISH_CENTER)
	mgr.set("dish_radius", DISH_RADIUS)
	mgr.set("cell_radius", 7.0)
	mgr.set("autonomous_division_enabled", false)
	mgr.call("_ready")

	# 铺 TARGET_CELLS 个光合细胞
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
	while spawned < TARGET_CELLS and row <= 30:
		var y: float = float(row) * spacing * 0.866
		var col: int = -30
		while col <= 30 and spawned < TARGET_CELLS:
			var x: float = float(col) * spacing + float(absi(row) % 2) * spacing * 0.5
			if x * x + y * y <= (DISH_RADIUS - 8.0) * (DISH_RADIUS - 8.0):
				mgr.call("register_zygote", 100000 + spawned, 0, -1, genome, DISH_CENTER + Vector2(x, y), 1.0, 0)
				spawned += 1
			col += 1
		row += 1
	return [mgr, env]

func _worker_loop() -> void:
	for i in range(RUN_TICKS):
		_worker_mgr.call("advance_physics_tick", 1.0 / 60.0)
		_worker_env.call("advance_field_tick")
	_worker_hash = int(_worker_mgr.call("get_state_hash"))

func _push(line: String) -> void:
	print(line)
	_report_lines.append(line)

func _finish() -> void:
	if _done:
		return
	_done = true
	var file: FileAccess = FileAccess.open("user://prod_sim_worker_probe.txt", FileAccess.WRITE)
	if file != null:
		for line in _report_lines:
			file.store_line(line)
		file.close()
	print("PROBE_FILE ", ProjectSettings.globalize_path("user://prod_sim_worker_probe.txt"))
	get_tree().quit()
