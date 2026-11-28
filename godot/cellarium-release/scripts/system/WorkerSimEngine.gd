extends RefCounted
## 阶段 B3：生产主场景的独立模拟线程引擎。
##
## 设计要点：
##   1. 主线程用 SaveManager.capture/restore 建立与主世界同状态的隔离世界；
##      隔离世界强制 CPU 场，不进场景树、不触碰 RenderingDevice / Node UI。
##   2. native 对象在主线程直接预热（_get_native_*），worker 只复用引用。
##   3. worker 连续跑真实完整 tick，不经过 tick_advanced signal / CommandBus.emit。
##   4. 主线程每帧在短临界区内把 SoA 快照整块写回主场景 CellArray，
##      现有 CellBatchRenderer / CellSceneRenderer / LinkLayer 等零改动继续工作。
##   5. 默认不启用；由 Main.threaded_simulation_enabled 与 start_threaded_simulation() 控制。

const OM_SCRIPT: Script = preload("res://scripts/system/OrganismManager.gd")
const EM_SCRIPT: Script = preload("res://scripts/system/EnvironmentManager.gd")
const TM_SCRIPT: Script = preload("res://scripts/core/tick/TickCore.gd")
const FIELD_SCRIPT: Script = preload("res://scripts/system/EnvironmentField.gd")
const PRESET_SCRIPT: Script = preload("res://scripts/core/data/EnvironmentPreset.gd")
const CONTEXT_SCRIPT: Script = preload("res://scripts/core/data/DevelopmentContext.gd")
const SAVE_MANAGER_SCRIPT: Script = preload("res://scripts/system/SaveManager.gd")
const SNAPSHOT_SCRIPT: Script = preload("res://scripts/system/SimSnapshot.gd")

const DT: float = 1.0 / 60.0
const SNAPSHOT_SLOTS: int = 3

## 渲染镜像只需要可见/诊断字段；完整确定性状态留在 worker 世界与 SaveManager。
## 神经权重/行为缓冲是 stride×N 的大数组，每 tick 拷进快照会把 worker 拖到 3×，这里明确跳过。
const CELL_ARRAY_NAMES: Array[String] = [
	"cell_pos_x", "cell_pos_y", "cell_energy", "cell_alive", "cell_type",
	"cell_org_id", "cell_link_count", "link_cell_a", "link_cell_b", "link_rest_length",
	"cell_radius_scale", "cell_stiffness", "cell_color_r", "cell_color_g", "cell_color_b",
	"cell_mode", "cell_mode_depth", "cell_telomere",
	"cell_radius_baseline", "cell_energy_scale", "cell_division_tick",
	"cell_orientation", "link_angle",
]
const ORG_ARRAY_NAMES: Array[String] = [
	"org_alive", "org_genome_id", "org_species_id", "org_parent_id",
	"org_age", "org_health", "org_death_cause", "org_state",
	"org_instruction_mask", "org_dev_cursor", "cell_offset", "cell_count",
]
const OM_EXPORT_KEYS: Array[String] = [
	"native_spatial_enabled", "dish_center", "dish_radius", "boundary_normal_damping",
	"cell_radius", "base_metabolic_cost", "autonomous_division_enabled",
	"autonomous_division_energy", "autonomous_division_cooldown",
	"autonomous_max_cells_per_organism", "global_cell_capacity",
	"energy_radius_growth_enabled", "energy_radius_relax_rate",
	"energy_radius_min_scale", "energy_radius_max_scale",
	"autonomous_division_separation", "default_transfer_rate",
	"facultative_aerobic_efficiency", "anaerobic_toxicity_damage_per_second",
	"heterotrophic_intake_rate", "photosynthetic_intake_rate", "chemotrophic_intake_rate",
	"predation_transfer_efficiency", "movement_energy_cost", "max_movement_speed",
	"predation_attack_threshold", "predation_reach", "predation_max_drain",
	"decomposition_writeback_rate", "reproduce_energy_threshold",
	"reproduce_parent_energy_fraction", "speciation_distance", "speciation_cooldown",
]
const ENV_SETTING_KEYS: Array[String] = [
	"nutrient_density", "temperature", "oxygen_fraction", "max_dev_depth",
	"light_intensity", "light_source_mode", "light_range", "light_angle_deg", "light_falloff",
	"food_spawn_amount", "food_lump_radius", "food_layer", "food_coated_ratio",
	"dish_center", "dish_radius",
]

var _main_mgr: Node = null
var _main_env: Node = null
var _main_tick_core: Node = null
var _main_cells: RefCounted = null
var _main_orgs: RefCounted = null

var _worker_mgr: Node = null
var _worker_env: Node = null
var _worker_tick_core: Node = null

var _thread: Thread = null
var _mutex: Mutex = null
var _slots: Array[RefCounted] = []
var _front_index: int = 0
var _last_written: int = -1
var _capacity: int = 0

var _running: bool = false
var _stop: bool = false
var _target_tick: int = 0
var _worker_tick: int = 0
var _pending_commands: Array[Dictionary] = []
var _hash_requested: bool = false
var _hash_target_tick: int = -1
var _last_applied_tick: int = -1

## 只读诊断
var diag_worker_ticks: int = 0
var diag_target_ticks: int = 0
var diag_snapshot_writes: int = 0
var diag_last_hash: int = 0
var diag_field_resolution: int = 0
var diag_pending_signal_size: int = 0
var diag_neural_interval: int = 1
var diag_field_interval: int = 1
var diag_org_us: int = 0
var diag_dev_us: int = 0
var diag_nutrient_us: int = 0
var diag_food_us: int = 0
var diag_field_us: int = 0
var diag_snapshot_us: int = 0
var diag_last_error: String = ""


func configure(main_mgr: Node, main_env: Node, main_tick_core: Node) -> bool:
	_main_mgr = main_mgr
	_main_env = main_env
	_main_tick_core = main_tick_core
	_main_cells = main_mgr.get("cells") as RefCounted if main_mgr != null else null
	_main_orgs = main_mgr.get("organisms") as RefCounted if main_mgr != null else null
	if _main_mgr == null or _main_env == null or _main_cells == null or _main_orgs == null:
		diag_last_error = "main refs missing"
		return false

	var snapshot: Dictionary = SAVE_MANAGER_SCRIPT.capture(_main_mgr, _main_env, _main_tick_core)
	if snapshot.is_empty():
		diag_last_error = "capture failed"
		return false

	_mutex = Mutex.new()
	_capacity = maxi(1024, int(_main_cells.call("size")) * 2)

	# 1) 隔离环境：设置与主世界相同，但 field 强制 CPU，且绝不进场景树。
	_worker_env = EM_SCRIPT.new() as Node
	for key in ENV_SETTING_KEYS:
		if _main_env.get(key) != null:
			_worker_env.set(key, _main_env.get(key))
	# 手工构造 preset/dev_context，绕开 bind_preset() 里默认 prefer_compute=true 的 GPU 配置。
	_worker_env.set("preset", PRESET_SCRIPT.new())
	_worker_env.set("dev_context", CONTEXT_SCRIPT.new())
	_worker_env.call("apply_environment_preset")
	var field_data: Dictionary = snapshot.get("field", {}) as Dictionary
	var field: RefCounted = _worker_env.get("field") as RefCounted
	if field == null or field_data.is_empty():
		diag_last_error = "worker field missing"
		return false
	var defaults: PackedFloat32Array = PackedFloat32Array([
		float(_worker_env.get("nutrient_density")),
		float(_worker_env.get("temperature")),
		float(_worker_env.get("oxygen_fraction")),
		float(_worker_env.get("light_intensity")),
		0.0,
	])
	field.call("configure", int(field_data.get("resolution", 32)),
		field_data.get("center", _worker_env.get("dish_center")),
		float(field_data.get("radius", _worker_env.get("dish_radius"))),
		defaults, false)
	_worker_env.call("apply_light_settings")

	# 2) 隔离管理器：复制全部 @export 配置，模块在 _ready 中按同一配置构造。
	_worker_mgr = OM_SCRIPT.new() as Node
	for key in OM_EXPORT_KEYS:
		if _main_mgr.get(key) != null:
			_worker_mgr.set(key, _main_mgr.get(key))
	_worker_mgr.set("environment_manager", _worker_env)
	_worker_tick_core = TM_SCRIPT.new() as Node
	var initial_speed: float = 1.0
	if _main_tick_core != null:
		initial_speed = float(_main_tick_core.get("speed_scale"))
	_worker_tick_core.call("apply_speed", initial_speed)
	diag_neural_interval = int(_worker_tick_core.call("get_neural_interval"))
	diag_field_interval = int(_worker_tick_core.call("get_field_interval"))
	_worker_mgr.set("tick_core", _worker_tick_core)
	_worker_mgr.call("_ready")

	# 3) native 必须在主线程 new；这里只实例化并缓存引用，不改模拟状态。
	for method_name in ["_get_native_spatial", "_get_native_neural", "_get_native_metabolism"]:
		if _worker_mgr.has_method(method_name):
			_worker_mgr.call(method_name)

	# 4) 用主世界快照灌入 worker 世界，随后 worker 从该 tick 继续。
	if not bool(SAVE_MANAGER_SCRIPT.restore(snapshot, _worker_mgr, _worker_env, null)):
		diag_last_error = "worker restore failed"
		return false
	repair_field_after_restore(field, field_data, defaults, false)
	var worker_field: RefCounted = _worker_env.get("field") as RefCounted
	diag_field_resolution = int(worker_field.get("resolution"))
	var worker_pending: Array = worker_field.get("_pending_sources") as Array
	if worker_pending.size() > 4:
		diag_pending_signal_size = (worker_pending[4] as PackedFloat32Array).size()
	_worker_tick = int(snapshot.get("sim_tick", 0))
	_target_tick = _worker_tick
	diag_worker_ticks = _worker_tick
	diag_target_ticks = _target_tick

	# 5) 三缓冲快照：完整 CellArray + OrganismStore 的 PackedArray 都预分配。
	var template_orgs: RefCounted = _worker_mgr.get("organisms") as RefCounted
	for i in range(SNAPSHOT_SLOTS):
		var snap: RefCounted = SNAPSHOT_SCRIPT.new() as RefCounted
		snap.call("configure", _capacity, CELL_ARRAY_NAMES, _worker_mgr.get("cells"))
		for name in ORG_ARRAY_NAMES:
			var source: Variant = template_orgs.get(name) if template_orgs != null else null
			snap.call("ensure_array", "org_" + name, source, _capacity)
		_slots.append(snap)
	return true


## SaveManager.restore 在 64×64 场配置下可能残留 32×32 的 _pending_sources，
## 导致 add_signal_sources_batch 越界。B3 路径在 restore 后重建场缓冲并原样灌回快照数据。
func repair_field_after_restore(field: RefCounted, field_data: Dictionary, defaults: PackedFloat32Array, prefer_compute: bool) -> void:
	if field == null or field_data.is_empty():
		return
	var resolution: int = int(field_data.get("resolution", 32))
	field.call("configure", resolution,
		field_data.get("center", field.get("center")),
		float(field_data.get("radius", field.get("radius"))),
		defaults, prefer_compute)
	var plane: int = resolution * resolution
	var channels: Array[PackedFloat32Array] = []
	for source in field_data.get("channels", []):
		var values: PackedFloat32Array = PackedFloat32Array()
		values = _copy_packed(source, values, mini(int(source.size()), plane)) as PackedFloat32Array
		channels.append(values)
	if channels.size() == FIELD_SCRIPT.CHANNEL_COUNT:
		field.set("channels", channels)
	var dish_mask: PackedByteArray = PackedByteArray()
	dish_mask = _copy_packed(field_data.get("dish_mask"), dish_mask, mini(int(field_data.get("dish_mask", []).size()), plane)) as PackedByteArray
	field.set("dish_mask", dish_mask)
	var terrain: Variant = field_data.get("terrain_mask")
	if terrain != null:
		var terrain_mask: PackedByteArray = PackedByteArray()
		terrain_mask = _copy_packed(terrain, terrain_mask, mini(int(terrain.size()), plane)) as PackedByteArray
		field.set("terrain_mask", terrain_mask)
	field.set("active_buffer", int(field_data.get("active_buffer", 0)))
	field.set("advection", field_data.get("advection", field.get("advection")))
	var pending: Array[PackedFloat32Array] = []
	for source in field_data.get("pending_sources", []):
		var values: PackedFloat32Array = PackedFloat32Array()
		values = _copy_packed(source, values, mini(int(source.size()), plane)) as PackedFloat32Array
		pending.append(values)
	if pending.size() == FIELD_SCRIPT.CHANNEL_COUNT:
		field.set("_pending_sources", pending)
	field.call("clear_runtime_caches")


func is_configured() -> bool:
	return _mutex != null and _worker_mgr != null and _slots.size() == SNAPSHOT_SLOTS


func start() -> bool:
	if not is_configured() or _running:
		return false
	_stop = false
	_running = true
	diag_last_error = ""
	_thread = Thread.new()
	var err: int = _thread.start(Callable(self, "_worker_loop"))
	if err != OK:
		diag_last_error = "thread.start err=%d" % err
		_thread = null
		_running = false
		return false
	return true


func stop() -> void:
	if not _running or _mutex == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()


func wait() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_running = false


func dispose() -> void:
	stop()
	wait()
	_slots.clear()
	if _worker_mgr != null and is_instance_valid(_worker_mgr):
		_worker_mgr.free()
	if _worker_env != null and is_instance_valid(_worker_env):
		_worker_env.free()
	if _worker_tick_core != null and is_instance_valid(_worker_tick_core):
		_worker_tick_core.free()
	_worker_mgr = null
	_worker_env = null
	_worker_tick_core = null


func is_running() -> bool:
	return _running


func set_target(tick_index: int) -> void:
	if _mutex == null:
		return
	_mutex.lock()
	if tick_index > _target_tick:
		_target_tick = tick_index
	diag_target_ticks = _target_tick
	_mutex.unlock()


func set_speed(speed_scale: float) -> void:
	if _mutex == null or _worker_tick_core == null:
		return
	_mutex.lock()
	_worker_tick_core.call("apply_speed", speed_scale)
	diag_neural_interval = int(_worker_tick_core.call("get_neural_interval"))
	diag_field_interval = int(_worker_tick_core.call("get_field_interval"))
	_mutex.unlock()


func get_worker_tick() -> int:
	if _mutex == null:
		return 0
	_mutex.lock()
	var value: int = diag_worker_ticks
	_mutex.unlock()
	return value


func get_target_tick() -> int:
	if _mutex == null:
		return 0
	_mutex.lock()
	var value: int = _target_tick
	_mutex.unlock()
	return value


func submit_command(command: Dictionary) -> void:
	if _mutex == null:
		return
	_mutex.lock()
	_pending_commands.append(command.duplicate(true))
	_mutex.unlock()


func request_state_hash() -> void:
	request_state_hash_at(diag_worker_ticks + 1)


func request_state_hash_at(tick_index: int) -> void:
	if _mutex == null:
		return
	_mutex.lock()
	_hash_target_tick = maxi(1, tick_index)
	_mutex.unlock()


func get_state_hash() -> int:
	if _mutex == null:
		return 0
	_mutex.lock()
	var value: int = diag_last_hash
	_mutex.unlock()
	return value


## 阶段 C 只读诊断：worker 世界 OrganismManager 的 PerfProbe 分段平均值。
func get_worker_stage_averages() -> Dictionary:
	if _worker_mgr == null:
		return {}
	var probe: RefCounted = _worker_mgr.get("perf_probe") as RefCounted
	if probe == null or not probe.has_method("diagnostic_averages"):
		return {}
	var result: Dictionary = probe.call("diagnostic_averages") as Dictionary
	result["__samples"] = int(probe.call("sample_count"))
	return result


## 主线程每帧调用：把当前 front 快照整块写回主场景 CellArray。
## 临界区内只做 PackedArray 拷贝与赋值，不做模拟计算。
func sync_main_state() -> bool:
	if _mutex == null or _main_cells == null or _main_orgs == null:
		return false
	_mutex.lock()
	if _slots.is_empty():
		_mutex.unlock()
		return false
	var snap: RefCounted = _slots[_front_index]
	if int(snap.get("tick")) == _last_applied_tick:
		_mutex.unlock()
		return false
	for name in CELL_ARRAY_NAMES:
		var src: Variant = snap.call("get_array", name)
		if src == null:
			continue
		var count: int = int(snap.call("get_array_count", name))
		if count <= 0:
			continue
		var dst: Variant = _main_cells.get(name)
		dst = _copy_packed(src, dst, count)
		_main_cells.set(name, dst)
	for name in ORG_ARRAY_NAMES:
		var key: String = "org_" + name
		var src_org: Variant = snap.call("get_array", key)
		if src_org == null:
			continue
		var org_count: int = int(snap.call("get_array_count", key))
		if org_count <= 0:
			continue
		var dst_org: Variant = _main_orgs.get(name)
		dst_org = _copy_packed(src_org, dst_org, org_count)
		_main_orgs.set(name, dst_org)
	_main_mgr.set("_sim_tick", int(snap.get("tick")))
	_last_applied_tick = int(snap.get("tick"))
	_mutex.unlock()
	return true


func _worker_loop() -> void:
	while true:
		_mutex.lock()
		var stop: bool = _stop
		_mutex.unlock()
		if stop:
			break

		var target: int = get_target_tick()
		if _worker_tick >= target:
			OS.delay_msec(1)
			continue

		_mutex.lock()
		var commands: Array[Dictionary] = _pending_commands.duplicate(true)
		_pending_commands.clear()
		var want_hash: bool = _hash_requested
		_hash_requested = false
		if _hash_target_tick > 0 and _worker_tick + 1 >= _hash_target_tick:
			want_hash = true
			_hash_target_tick = -1
		_mutex.unlock()
		for command in commands:
			_apply_command_safe(command)

		_step_one_tick()
		if want_hash:
			diag_last_hash = int(_worker_mgr.call("get_state_hash"))
		_write_snapshot(target)


func _step_one_tick() -> void:
	_worker_tick += 1
	_worker_tick_core.set("tick_index", _worker_tick)
	var t0: int = Time.get_ticks_usec()
	_worker_mgr.call("advance_physics_tick", DT)
	var t1: int = Time.get_ticks_usec()
	_worker_mgr.call("advance_development_tick")
	var t2: int = Time.get_ticks_usec()
	_worker_env.call("apply_nutrient_sources", _worker_tick)
	var t3: int = Time.get_ticks_usec()
	_worker_env.call("advance_food_entities", DT)
	var t4: int = Time.get_ticks_usec()
	_worker_env.call("advance_field_tick")
	var t5: int = Time.get_ticks_usec()
	diag_org_us += t1 - t0
	diag_dev_us += t2 - t1
	diag_nutrient_us += t3 - t2
	diag_food_us += t4 - t3
	diag_field_us += t5 - t4


func _apply_command_safe(command: Dictionary) -> void:
	if _worker_mgr == null or not _worker_mgr.has_method("apply_command"):
		return
	_worker_mgr.call("apply_command", command)


func _write_snapshot(target: int) -> void:
	var snap_t0: int = Time.get_ticks_usec()
	_mutex.lock()
	var front: int = _front_index
	var back: int = (front + 1) % SNAPSHOT_SLOTS
	if back == _last_written:
		back = (front + 2) % SNAPSHOT_SLOTS
	_mutex.unlock()

	var snap: RefCounted = _slots[back]
	var cells: RefCounted = _worker_mgr.get("cells") as RefCounted
	var orgs: RefCounted = _worker_mgr.get("organisms") as RefCounted
	var n: int = int(cells.call("size"))
	if n > _capacity:
		_capacity = n
	for name in CELL_ARRAY_NAMES:
		var src: Variant = cells.get(name)
		var dst: Variant = snap.call("get_array", name)
		var count: int = _packed_size(src)
		snap.call("set_array", name, _copy_packed(src, dst, count), count)
	var org_count: int = _packed_size(orgs.get("org_alive"))
	for name in ORG_ARRAY_NAMES:
		var key: String = "org_" + name
		var src_org: Variant = orgs.get(name)
		var dst_org: Variant = snap.call("get_array", key)
		var count_org: int = _packed_size(src_org)
		snap.call("set_array", key, _copy_packed(src_org, dst_org, count_org), count_org)

	var px: PackedFloat32Array = snap.get("pos_x") as PackedFloat32Array
	var py: PackedFloat32Array = snap.get("pos_y") as PackedFloat32Array
	var alive: PackedByteArray = snap.get("alive") as PackedByteArray
	var ct: PackedByteArray = snap.get("cell_type") as PackedByteArray
	var px_variant: Variant = _copy_packed(snap.call("get_array", "cell_pos_x"), px, n)
	var py_variant: Variant = _copy_packed(snap.call("get_array", "cell_pos_y"), py, n)
	var alive_variant: Variant = _copy_packed(snap.call("get_array", "cell_alive"), alive, n)
	var ct_variant: Variant = _copy_packed(snap.call("get_array", "cell_type"), ct, n)
	snap.set("pos_x", px_variant)
	snap.set("pos_y", py_variant)
	snap.set("alive", alive_variant)
	snap.set("cell_type", ct_variant)
	px = px_variant as PackedFloat32Array
	py = py_variant as PackedFloat32Array
	alive = alive_variant as PackedByteArray
	ct = ct_variant as PackedByteArray

	var checksum: int = 0
	for i in range(n):
		checksum = (checksum + int(px[i] * 10000.0)) % 1000000007
		checksum = (checksum << 1) | (alive[i] & 1)

	diag_snapshot_us += Time.get_ticks_usec() - snap_t0
	_mutex.lock()
	snap.set("cell_count", n)
	snap.set("org_count", org_count)
	snap.set("tick", _worker_tick)
	snap.set("checksum", checksum)
	diag_worker_ticks = _worker_tick
	diag_target_ticks = target
	diag_snapshot_writes += 1
	_last_written = back
	_front_index = back
	_mutex.unlock()


func _packed_size(source: Variant) -> int:
	if source is PackedFloat32Array:
		return (source as PackedFloat32Array).size()
	if source is PackedInt32Array:
		return (source as PackedInt32Array).size()
	if source is PackedInt64Array:
		return (source as PackedInt64Array).size()
	if source is PackedByteArray:
		return (source as PackedByteArray).size()
	return 0


func _copy_packed(src: Variant, dst: Variant, count: int) -> Variant:
	if src == null:
		return dst
	# 快照元数据与实际 PackedArray 长度偶尔会跨 ticks 短暂错开（细胞数增长/首帧未发布），
	# 这里按实际可读长度收敛，绝不越界读；缺失尾部由下一个快照补齐。
	var available: int = _packed_size(src)
	if available <= 0:
		return dst
	count = mini(count, available)
	if dst is PackedFloat32Array:
		var d: PackedFloat32Array = dst as PackedFloat32Array
		var s: PackedFloat32Array = src as PackedFloat32Array
		if s == null:
			return d
		d.resize(count)
		for i in range(count):
			d[i] = s[i]
		return d
	if dst is PackedInt32Array:
		var d_i: PackedInt32Array = dst as PackedInt32Array
		var s_i: PackedInt32Array = src as PackedInt32Array
		if s_i == null:
			return d_i
		d_i.resize(count)
		for i in range(count):
			d_i[i] = s_i[i]
		return d_i
	if dst is PackedInt64Array:
		var d_l: PackedInt64Array = dst as PackedInt64Array
		var s_l: PackedInt64Array = src as PackedInt64Array
		if s_l == null:
			return d_l
		d_l.resize(count)
		for i in range(count):
			d_l[i] = s_l[i]
		return d_l
	if dst is PackedByteArray:
		var d_b: PackedByteArray = dst as PackedByteArray
		var s_b: PackedByteArray = src as PackedByteArray
		if s_b == null:
			return d_b
		d_b.resize(count)
		for i in range(count):
			d_b[i] = s_b[i]
		return d_b
	return dst
