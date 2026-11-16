extends Node2D
## 场景协调者：只做节点注入、状态显示与信号兜底，模拟逻辑留在各子系统。
## 依赖路径与培养基参数在 .tscn 中声明；脚本不硬编码节点名。

@export var tick_core_path: NodePath = ^"Simulation/TickCore"
@export var command_bus_path: NodePath = ^"Simulation/CommandBus"
@export var environment_path: NodePath = ^"Simulation/EnvironmentManager"
@export var organism_manager_path: NodePath = ^"Simulation/OrganismManager"
@export var status_label_path: NodePath = ^"UI/HUD/StatusBar"
@export var game_hud_path: NodePath = ^"UI/HUD"
@export var dish_view_path: NodePath = ^"DishView"
@export var create_demo_organism: bool = true

var tick_core: Node = null
var command_bus: Node = null
var environment_manager: Node = null
var organism_manager: Node = null
var status_label: Label = null
var game_hud: Node = null
var dish_view: Node2D = null
var executed_commands: int = 0

func _ready() -> void:
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	environment_manager = get_node_or_null(environment_path)
	organism_manager = get_node_or_null(organism_manager_path)
	status_label = get_node_or_null(status_label_path) as Label
	game_hud = get_node_or_null(game_hud_path)
	dish_view = get_node_or_null(dish_view_path) as Node2D
	var on_tick: Callable = Callable(self, "_on_tick_advanced")
	if tick_core != null and tick_core.has_signal("tick_advanced") and not tick_core.is_connected("tick_advanced", on_tick):
		tick_core.connect("tick_advanced", on_tick)
	var on_cmd: Callable = Callable(self, "_on_command_executed")
	if command_bus != null and command_bus.has_signal("command_executed") and not command_bus.is_connected("command_executed", on_cmd):
		command_bus.connect("command_executed", on_cmd)
	if organism_manager != null:
		organism_manager.set("environment_manager", environment_manager)
	if create_demo_organism and organism_manager != null and int(organism_manager.call("get_organism_count")) == 0:
		var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
		genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
		genome.call("set_development_program", [])
		var org_id: int = int(organism_manager.call("register_zygote", 0, 0, -1, genome, Vector2(250, 250), 0.8, 0))
		if org_id >= 0 and status_label != null:
			status_label.text = "cellarium | tick 0 | demo organism"
	print("[cellarium] boot ok basal_autonomy=", get_basal_autonomy())

func get_basal_autonomy() -> float:
	if environment_manager == null:
		return 0.0
	return float(environment_manager.call("get_basal_autonomy"))

func _on_tick_advanced(tick_index: int) -> void:
	if command_bus != null:
		executed_commands += int(command_bus.call("execute_tick_commands", tick_index))
	if organism_manager != null:
		organism_manager.call("advance_physics_tick", 1.0 / 60.0)
		organism_manager.call("advance_development_tick")
	if environment_manager != null:
		environment_manager.call("advance_field_tick")
	if status_label != null and tick_index % 60 == 0:
		status_label.text = "tick %d | organisms %d | basal %.3f" % [tick_index, int(organism_manager.call("get_organism_count")) if organism_manager != null else 0, get_basal_autonomy()]

func _on_command_executed(command: Dictionary, tick_index: int) -> void:
	var result: int = -1
	if organism_manager != null:
		result = int(organism_manager.call("apply_command", command))
		if command.get("type", "") == "DIVIDE" and result < 0:
			push_warning("[cellarium] DIVIDE rejected @tick %d" % tick_index)
	if game_hud != null and game_hud.has_method("apply_result"):
		game_hud.call("apply_result", str(command.get("type", "?")), result)
	print("[cellarium] cmd ", command.get("type", "?"), " result=", result, " @tick ", tick_index)

func _unhandled_input(event: InputEvent) -> void:
	if game_hud == null or not game_hud.has_method("world_action"):
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			var world_position: Vector2 = get_global_mouse_position()
			game_hud.call("world_action", world_position, Vector2.ZERO)
