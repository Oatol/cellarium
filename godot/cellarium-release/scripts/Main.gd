extends Node2D
## 场景协调者：只做节点注入、状态显示与信号兜底，模拟逻辑留在各子系统。
## 依赖路径与培养基参数在 .tscn 中声明；脚本不硬编码节点名。

const FrameProfiler: RefCounted = preload("res://scripts/system/FrameProfiler.gd")
const WorkerSimEngineScript: RefCounted = preload("res://scripts/system/WorkerSimEngine.gd")

@export var tick_core_path: NodePath = ^"Simulation/TickCore"
@export var command_bus_path: NodePath = ^"Simulation/CommandBus"
@export var environment_path: NodePath = ^"Simulation/EnvironmentManager"
@export var organism_manager_path: NodePath = ^"Simulation/OrganismManager"
@export var status_label_path: NodePath = ^"UI/HUD/StatusBar"
@export var game_hud_path: NodePath = ^"UI/HUD"
@export var dish_view_path: NodePath = ^"DishView"
@export var analysis_panel_path: NodePath = ^"UI/AnalysisPanel"
@export var create_demo_organism: bool = true
## AgentBridge 默认关闭（§7.2）；仅当 .tscn 开启 agent_bridge_enabled 时才启用。
@export var agent_bridge_enabled: bool = false
@export var agent_permission: String = "readonly"
@export var agent_token: String = ""
## 阶段 B3：默认关闭。打开后权威模拟进入独立 worker，主线程只做快照写回与渲染。
@export var threaded_simulation_enabled: bool = false
## worker 模式下 GPU 场只服务视觉层；性能 A/B 可关闭以隔离 worker 成本。
@export var worker_visual_field_enabled: bool = true

var tick_core: Node = null
var command_bus: Node = null
var environment_manager: Node = null
var organism_manager: Node = null
var status_label: Label = null
var game_hud: Node = null
var dish_view: Node2D = null
var analysis_panel: Node = null
var executed_commands: int = 0
var agent_bridge: RefCounted = null
var worker_engine: RefCounted = null
var dev_mode: bool = false
var _carry_notified: bool = false
## 光学镊子/地形笔刷等拖拽型工具的连续输入状态：按住左键时逐 motion 事件入队。
var _pointer_dragging: bool = false
var _last_drag_world: Vector2 = Vector2.ZERO

func _ready() -> void:
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	environment_manager = get_node_or_null(environment_path)
	organism_manager = get_node_or_null(organism_manager_path)
	status_label = get_node_or_null(status_label_path) as Label
	game_hud = get_node_or_null(game_hud_path)
	dish_view = get_node_or_null(dish_view_path) as Node2D
	analysis_panel = get_node_or_null(analysis_panel_path)
	var on_tick: Callable = Callable(self, "_on_tick_advanced")
	if tick_core != null and tick_core.has_signal("tick_advanced") and not tick_core.is_connected("tick_advanced", on_tick):
		tick_core.connect("tick_advanced", on_tick)
	var on_cmd: Callable = Callable(self, "_on_command_executed")
	if command_bus != null and command_bus.has_signal("command_executed") and not command_bus.is_connected("command_executed", on_cmd):
		command_bus.connect("command_executed", on_cmd)
	var on_carry: Callable = Callable(self, "_on_carry_changed")
	if tick_core != null and tick_core.has_signal("carry_changed") and not tick_core.is_connected("carry_changed", on_carry):
		tick_core.connect("carry_changed", on_carry)
	var on_render_fps: Callable = Callable(self, "_on_speed_changed_render")
	if tick_core != null and tick_core.has_signal("speed_changed") and not tick_core.is_connected("speed_changed", on_render_fps):
		tick_core.connect("speed_changed", on_render_fps)
	if organism_manager != null:
		organism_manager.set("environment_manager", environment_manager)
		organism_manager.set("tick_core", tick_core)
	_setup_agent_bridge()
	if create_demo_organism and organism_manager != null and int(organism_manager.call("get_organism_count")) == 0:
		var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
		var genome: RefCounted = genome_script.new() as RefCounted
		genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
		# v0.34.0 默认演示：M1 光合自分裂集群——保黏附、无分裂次数限制。
		# 旧的 5 模式分化演示体仍在 Genome.demo_modes() 供回归测试/手动对比。
		genome.set("flags", int(genome_script.get_script_constant_map().get("FLAG_GENE_MODE", 2))
			| int(genome_script.get_script_constant_map().get("FLAG_GLUE_LINKS", 1)))
		genome.set("division_mass", 0.05)
		genome.set("max_divisions", int(genome_script.get_script_constant_map().get("MAX_GENE_DIVISIONS", 8)))
		genome.set("max_cells_per_organism", int(genome_script.get_script_constant_map().get("UNLIMITED_CELLS", -1)))
		genome.call("set_modes", genome_script.call("solo_photo_modes"))
		var org_id: int = int(organism_manager.call("register_zygote", 0, 0, -1, genome, Vector2(250, 250), 0.8, 0))
		if org_id >= 0 and status_label != null:
			status_label.text = "cellarium | tick 0 | demo multicellular organism"
	if threaded_simulation_enabled:
		start_threaded_simulation()
	print("[cellarium] boot ok basal_autonomy=", get_basal_autonomy())

func _setup_agent_bridge() -> void:
	## AgentBridge 默认关闭；显式启用时绑定依赖并设置权限/token（§7.2）。
	var bridge_script: Script = load("res://scripts/agent/AgentBridge.gd") as Script
	agent_bridge = bridge_script.new() as RefCounted
	agent_bridge.call("configure", command_bus, organism_manager, environment_manager, tick_core)
	if agent_bridge_enabled:
		var token_value: String = agent_token if not agent_token.is_empty() else _generate_token()
		var mode: String = agent_permission if agent_permission in ["readonly", "sandbox", "full"] else "readonly"
		agent_bridge.call("enable", token_value, mode)
		print("[cellarium] AgentBridge enabled mode=", mode, " token=", token_value)

func _generate_token() -> String:
	return "agent-%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000]

func get_agent_bridge() -> RefCounted:
	return agent_bridge

## 阶段 B3：把权威模拟切入独立 worker。主线程保留原节点作为渲染镜像。
func start_threaded_simulation() -> bool:
	if worker_engine != null and bool(worker_engine.call("is_running")):
		return true
	var engine: RefCounted = WorkerSimEngineScript.new() as RefCounted
	if not bool(engine.call("configure", organism_manager, environment_manager, tick_core)):
		push_warning("[cellarium] worker engine configure failed: %s" % str(engine.get("diag_last_error")))
		return false
	worker_engine = engine
	if tick_core != null:
		tick_core.call("set_worker_target_mode", true)
		tick_core.call("set_worker_progress", int(engine.call("get_worker_tick")))
	engine.call("set_speed", float(tick_core.get("speed_scale")))
	engine.call("set_target", int(tick_core.call("get_target_tick")))
	if not bool(engine.call("start")):
		push_warning("[cellarium] worker engine start failed: %s" % str(engine.get("diag_last_error")))
		if tick_core != null:
			tick_core.call("set_worker_target_mode", false)
		worker_engine = null
		return false
	print("[cellarium] threaded simulation ON")
	return true


func stop_threaded_simulation() -> void:
	if worker_engine == null:
		return
	worker_engine.call("dispose")
	worker_engine = null
	if tick_core != null:
		tick_core.call("set_worker_target_mode", false)
	print("[cellarium] threaded simulation OFF")


func get_worker_tick() -> int:
	if worker_engine == null:
		return int(tick_core.get("tick_index")) if tick_core != null else 0
	return int(worker_engine.call("get_worker_tick"))


## 阶段 C 只读诊断：worker 世界 PerfProbe 的权威分段。
func get_worker_stages() -> Dictionary:
	if worker_engine == null:
		return {}
	return worker_engine.call("get_worker_stage_averages") as Dictionary


func get_worker_stage_samples() -> int:
	if worker_engine == null:
		return 0
	var probe_stages: Dictionary = get_worker_stages()
	return int(probe_stages.get("__samples", 0))


## 阶段 C 只读诊断：worker 线程累计的分段耗时与快照写入次数。
func get_worker_diag() -> Dictionary:
	if worker_engine == null:
		return {}
	return {
		"org_us": int(worker_engine.get("diag_org_us")),
		"dev_us": int(worker_engine.get("diag_dev_us")),
		"nutrient_us": int(worker_engine.get("diag_nutrient_us")),
		"food_us": int(worker_engine.get("diag_food_us")),
		"field_us": int(worker_engine.get("diag_field_us")),
		"snapshot_us": int(worker_engine.get("diag_snapshot_us")),
		"worker_ticks": int(worker_engine.get("diag_worker_ticks")),
		"snapshot_writes": int(worker_engine.get("diag_snapshot_writes")),
		"neural_interval": int(worker_engine.get("diag_neural_interval")),
		"field_interval": int(worker_engine.get("diag_field_interval")),
	}


func is_threaded_simulation_running() -> bool:
	return worker_engine != null and bool(worker_engine.call("is_running"))


func _exit_tree() -> void:
	stop_threaded_simulation()


func _process(_delta: float) -> void:
	if worker_engine == null or not bool(worker_engine.call("is_running")):
		return
	worker_engine.call("sync_main_state")
	# GPU 场降级为视觉层：按帧推进一次，不再参与权威 state hash / 回放。
	if environment_manager != null and worker_visual_field_enabled:
		environment_manager.call("apply_nutrient_sources", get_worker_tick())
		environment_manager.call("advance_food_entities", _delta)
		environment_manager.call("advance_field_tick")
	if tick_core != null:
		tick_core.call("set_worker_progress", get_worker_tick())

## 开发者模式开关（F9）：解锁 dev.* 命令入口，仅在当前进程生效。
func toggle_dev_mode() -> bool:
	dev_mode = not dev_mode
	if agent_bridge != null and dev_mode:
		agent_bridge.call("enable", str(agent_bridge.get("token")) if not str(agent_bridge.get("token")).is_empty() else "dev", "full")
	_set_status("dev mode " + ("ON" if dev_mode else "OFF"))
	return dev_mode

func _set_status(text_value: String) -> void:
	if status_label != null:
		status_label.text = text_value

func get_basal_autonomy() -> float:
	if environment_manager == null:
		return 0.0
	return float(environment_manager.call("get_basal_autonomy"))

func _on_tick_advanced(tick_index: int) -> void:
	FrameProfiler.tick_begin()
	if command_bus != null:
		executed_commands += int(command_bus.call("execute_tick_commands", tick_index))
	if worker_engine != null and bool(worker_engine.call("is_running")):
		# worker 模式：signal 携带的是目标 tick，主线程不跑模拟链。
		worker_engine.call("set_target", tick_index)
		worker_engine.call("sync_main_state")
		FrameProfiler.tick_end()
		return
	if organism_manager != null:
		organism_manager.call("advance_physics_tick", 1.0 / 60.0)
		organism_manager.call("advance_development_tick")
	if environment_manager != null:
		# v0.13.0：Macro 式营养源按 tick 确定型投放，再进入场扩散。
		environment_manager.call("apply_nutrient_sources", tick_index)
		environment_manager.call("advance_food_entities", 1.0 / 60.0)
		environment_manager.call("advance_field_tick")
	FrameProfiler.tick_end()
	if status_label != null and tick_index % 60 == 0:
		status_label.text = "tick %d | organisms %d | basal %.3f" % [tick_index, int(organism_manager.call("get_organism_count")) if organism_manager != null else 0, get_basal_autonomy()]

func _on_speed_changed_render(_speed: float, _lod: int) -> void:
	## §8.1：倍速 ≥16× 渲染锁 30 fps。render_fps=0 恢复不锁帧。
	## 放在 Main 而非 TickCore，避免无头 SmokeTest 创建裸 TickCore 时污染全局 Engine 状态。
	if tick_core == null:
		return
	var render_fps: int = int(tick_core.call("get_render_fps"))
	Engine.max_fps = render_fps
	# 同步 ProjectSettings，部分平台（Windows Vulkan）运行时改 Engine 属性不足，
	# 需一并改项目设置才能在主循环下一帧生效；0 表示恢复不锁帧。
	ProjectSettings.set_setting("run/max_fps", render_fps)
	if worker_engine != null:
		worker_engine.call("set_speed", float(tick_core.get("speed_scale")))


func _on_carry_changed(carry_ticks: int, lagging: bool) -> void:
	## 模拟时间落后提示（§2.6 / T11）：只在状态切换时刷新，避免每帧刷屏。
	if lagging and not _carry_notified:
		_set_status("模拟时间落后 · carry=%d · 倍速 %s×" % [carry_ticks, str(tick_core.get("speed_scale")) if tick_core != null else "?"])
	elif not lagging and _carry_notified:
		_set_status("模拟已追平 · carry=%d" % carry_ticks)
	_carry_notified = lagging

func _on_command_executed(command: Dictionary, tick_index: int) -> void:
	var result: int = -1
	if worker_engine != null and bool(worker_engine.call("is_running")):
		# 唯一写入口不变：CommandBus 仍是入口，只是写目标从主场景镜像换成 worker 权威世界。
		worker_engine.call("submit_command", command)
		result = 0
		if game_hud != null and game_hud.has_method("apply_result"):
			game_hud.call("apply_result", str(command.get("type", "?")), result)
		print("[cellarium] cmd ", command.get("type", "?"), " queued to worker @tick ", tick_index)
		return
	if organism_manager != null:
		result = int(organism_manager.call("apply_command", command))
		if command.get("type", "") == "DIVIDE" and result < 0:
			push_warning("[cellarium] DIVIDE rejected @tick %d" % tick_index)
	if game_hud != null and game_hud.has_method("apply_result"):
		game_hud.call("apply_result", str(command.get("type", "?")), result)
	# 业务反馈：细胞诊断/黏附连接等工具在 OrganismManager 写入 last_tool_message，
	# 优先显示它，让"点了没反应"的工具给出可读提示。
	if organism_manager != null and game_hud != null and game_hud.has_method("show_tool_message"):
		var tool_message: String = str(organism_manager.call("get_last_tool_message"))
		if not tool_message.is_empty():
			game_hud.call("show_tool_message", tool_message)
	# 细胞诊断命中后自动弹出分析面板，展示逐项状态（参考 Cell Lab 诊断工具）。
	if command.get("type", "") == "INSPECT" and analysis_panel != null and analysis_panel.has_method("show_inspection"):
		# 落空（点空白处）在 OrganismManager 里已解除锁定：此时按解锁流程收起面板。
		if result >= 0:
			analysis_panel.call("show_inspection")
		elif analysis_panel.has_method("on_selection_cleared"):
			analysis_panel.call("on_selection_cleared")
	if command.get("type", "") == "CLEAR_SELECTION" and analysis_panel != null and analysis_panel.has_method("refresh_inspection"):
		analysis_panel.call("refresh_inspection")
	print("[cellarium] cmd ", command.get("type", "?"), " result=", result, " @tick ", tick_index)

## 屏幕坐标 → 模拟世界坐标。用事件自身的 position + canvas transform，
## 与渲染用的相机变换同源，避免 get_global_mouse_position() 在不同 viewport/stretch 下漂移。
func screen_to_world(screen_position: Vector2) -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return screen_position
	return viewport.get_canvas_transform().affine_inverse() * screen_position

## 冻结/暂停档没有下一 tick，用户干预必须立即经 CommandBus 落盘。
## 仍然保持「唯一写入口」契约：不绕过 CommandBus，只是同步 flush 待执行批次。
func _flush_commands_if_paused() -> void:
	if command_bus == null:
		return
	var paused: bool = tick_core == null or not bool(tick_core.get("running")) or float(tick_core.get("speed_scale")) <= 0.0
	if not paused:
		return
	var tick_index: int = int(tick_core.get("tick_index")) if tick_core != null else 0
	command_bus.call("execute_tick_commands", tick_index)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			# Esc 解除诊断锁定（圆环 + 诊断快照），仍经 CommandBus。
			if command_bus != null:
				command_bus.call("enqueue", {"type": "CLEAR_SELECTION"})
				_flush_commands_if_paused()
				_set_status("已解除细胞诊断锁定")
			return
		if key_event.keycode == KEY_F9:
			toggle_dev_mode()
			return
		if key_event.keycode == KEY_SPACE:
			if tick_core != null:
				tick_core.set("running", not bool(tick_core.get("running")))
				_set_status("暂停" if not bool(tick_core.get("running")) else "继续")
			return
		# 倍速快捷键（§6.5）：1/2/3 = 1×/3×/8×，Shift+3=16×，Shift+4=32×
		var speed_value: float = -1.0
		if key_event.shift_pressed:
			if key_event.keycode == KEY_3:
				speed_value = 16.0
			elif key_event.keycode == KEY_4:
				speed_value = 32.0
		else:
			match key_event.keycode:
				KEY_1: speed_value = 1.0
				KEY_2: speed_value = 3.0
				KEY_3: speed_value = 8.0
		if speed_value >= 0.0 and tick_core != null:
			tick_core.call("apply_speed", speed_value)
			tick_core.set("running", true)
			tick_core.call("clear_carry")
			_set_status("倍速 → %s× · LOD %d" % [str(speed_value), int(tick_core.call("get_lod_level"))])
			return
	if game_hud == null or not game_hud.has_method("world_action"):
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				var world_position: Vector2 = screen_to_world(mouse_button.position)
				var accepted: bool = bool(game_hud.call("world_action", world_position, Vector2.ZERO))
				if accepted:
					_flush_commands_if_paused()
					# 仅拖拽型工具（光学镊子/旋转选区/地形笔刷）进入连续拖拽态。
					if game_hud.has_method("is_drag_tool") and bool(game_hud.call("is_drag_tool")):
						_pointer_dragging = true
						_last_drag_world = world_position
			else:
				_pointer_dragging = false
	elif event is InputEventMouseMotion and _pointer_dragging:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		# 左键未按住（可能在窗口外释放）则结束拖拽，避免"粘住"。
		if (motion_event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_pointer_dragging = false
			return
		var world_position: Vector2 = screen_to_world(motion_event.position)
		var world_delta: Vector2 = world_position - _last_drag_world
		if world_delta.length_squared() <= 0.0001:
			return
		game_hud.call("world_action", world_position, world_delta)
		_flush_commands_if_paused()
		_last_drag_world = world_position
