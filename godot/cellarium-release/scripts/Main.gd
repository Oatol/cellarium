extends Node2D
## 场景协调者：只做节点注入、状态显示与信号兜底，模拟逻辑留在各子系统。
## 依赖路径与培养基参数在 .tscn 中声明；脚本不硬编码节点名。

@export var tick_core_path: NodePath = ^"Simulation/TickCore"
@export var command_bus_path: NodePath = ^"Simulation/CommandBus"
@export var environment_path: NodePath = ^"Simulation/EnvironmentManager"
@export var status_label_path: NodePath = ^"UI/HUD/StatusBar"

var tick_core: Node = null
var command_bus: Node = null
var environment_manager: Node = null
var status_label: Label = null
var executed_commands: int = 0

func _ready() -> void:
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	environment_manager = get_node_or_null(environment_path)
	status_label = get_node_or_null(status_label_path) as Label
	var on_tick: Callable = Callable(self, "_on_tick_advanced")
	if tick_core != null and tick_core.has_signal("tick_advanced") and not tick_core.is_connected("tick_advanced", on_tick):
		tick_core.connect("tick_advanced", on_tick)
	var on_cmd: Callable = Callable(self, "_on_command_executed")
	if command_bus != null and command_bus.has_signal("command_executed") and not command_bus.is_connected("command_executed", on_cmd):
		command_bus.connect("command_executed", on_cmd)
	print("[cellarium] boot ok basal_autonomy=", get_basal_autonomy())

func get_basal_autonomy() -> float:
	if environment_manager == null:
		return 0.0
	return float(environment_manager.call("get_basal_autonomy"))

func _on_tick_advanced(tick_index: int) -> void:
	if command_bus != null:
		executed_commands += int(command_bus.call("execute_tick_commands", tick_index))
	if status_label != null and tick_index % 60 == 0:
		status_label.text = "tick %d | organisms 0 | basal %.3f" % [tick_index, get_basal_autonomy()]

func _on_command_executed(command: Dictionary, tick_index: int) -> void:
	print("[cellarium] cmd ", command.get("type", "?"), " @tick ", tick_index)
