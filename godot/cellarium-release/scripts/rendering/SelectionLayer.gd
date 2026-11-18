extends Node2D
## 选区高亮层：给 OrganismManager.selection 中的每枚细胞画一个环（诊断工具命中时选中）。
## 纯视图层，不写模拟状态；tick 驱动重绘，冻结档由 mark_dirty() 即时刷新。

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var ring_color: Color = Color(1.0, 0.86, 0.42, 0.95)
@export var ring_radius_offset: float = 4.0
@export var ring_width: float = 1.6

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var _pulse_phase: float = 0.0

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	# 冻结档无 tick，命令执行后立即重绘选中环。
	if command_bus != null and command_bus.has_signal("command_executed"):
		var on_cmd: Callable = Callable(self, "_on_command_executed")
		if not command_bus.is_connected("command_executed", on_cmd):
			command_bus.connect("command_executed", on_cmd)
	queue_redraw()

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	queue_redraw()

func _on_tick_advanced(_tick_index: int) -> void:
	_pulse_phase += 0.09
	queue_redraw()

func mark_dirty() -> void:
	queue_redraw()

func _draw() -> void:
	if organism_manager == null:
		return
	var selection: Array = organism_manager.get("selection") as Array
	if selection == null or selection.is_empty():
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var radius: float = float(organism_manager.get("cell_radius"))
	var radius_scales: PackedFloat32Array = cells.get("cell_radius_scale")
	var pulse: float = 0.5 + 0.5 * sin(_pulse_phase)
	for cell_index in selection:
		var index: int = int(cell_index)
		if index < 0 or index >= alive.size() or alive[index] == 0:
			continue
		var center: Vector2 = Vector2(pos_x[index], pos_y[index])
		var scale_value: float = float(radius_scales[index]) if index < radius_scales.size() else 1.0
		var ring_radius: float = radius * clampf(scale_value, 0.5, 2.0) + ring_radius_offset + pulse * 1.6
		var alpha: float = ring_color.a * (0.7 + 0.3 * pulse)
		draw_arc(center, ring_radius, 0.0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, alpha), ring_width, true)
		# 四个方位的短刻度，强化"被选中"的读数感。
		for angle in [0.0, TAU * 0.25, TAU * 0.5, TAU * 0.75]:
			var inner: Vector2 = center + Vector2(cos(angle), sin(angle)) * (ring_radius - 2.0)
			var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * (ring_radius + 2.0)
			draw_line(inner, outer, Color(ring_color.r, ring_color.g, ring_color.b, alpha), ring_width, true)
