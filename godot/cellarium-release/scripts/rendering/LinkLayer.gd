extends "res://scripts/rendering/CellariumView.gd"
## 多细胞协作表现层：在细胞膜之间画黏附桥，并用沿连接移动的光点表示能量流方向。
## 纯视图派生：只读 CellArray / TickCore，不写模拟状态，不参与确定性 hash。
## 放在 CellSceneLayer 之前，连接桥会被程序化细胞遮住两端，像膜间结构而不是穿过细胞的线。

const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var link_width: float = 2.2
@export var show_flow_pulse: bool = true

var command_bus: Node = null
var _rendered_link_count: int = 0
var _last_flow_bias: float = 0.0

func _ready() -> void:
	super._ready()
	command_bus = get_node_or_null(command_bus_path)
	if command_bus != null and command_bus.has_signal("command_executed"):
		var on_command: Callable = Callable(self, "_on_command_executed")
		if not command_bus.is_connected("command_executed", on_command):
			command_bus.connect("command_executed", on_command)

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	mark_dirty()

func _draw() -> void:
	draw_cooperation_layer()

func get_rendered_link_count() -> int:
	return _rendered_link_count

func get_last_flow_bias() -> float:
	return _last_flow_bias

func draw_cooperation_layer() -> void:
	var cells: RefCounted = get_cells()
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var cell_type: PackedByteArray = cells.get("cell_type")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var link_rest: PackedFloat32Array = cells.get("link_rest_length")
	var radius: float = SHAPE.REST_RADIUS
	if organism_manager != null:
		var radius_value: Variant = organism_manager.get("cell_radius")
		if radius_value != null:
			radius = maxf(1.0, float(radius_value))
	var tick_value: int = 0
	if tick_core != null:
		tick_value = int(tick_core.get("tick_index"))
	_rendered_link_count = 0
	_last_flow_bias = 0.0
	for link_index in range(link_a.size()):
		if link_index >= link_b.size():
			break
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= alive.size() or b >= alive.size():
			continue
		if alive[a] == 0 or alive[b] == 0:
			continue
		var point_a: Vector2 = Vector2(pos_x[a], pos_y[a])
		var point_b: Vector2 = Vector2(pos_x[b], pos_y[b])
		var delta: Vector2 = point_b - point_a
		var distance_value: float = delta.length()
		if distance_value <= 0.001:
			continue
		var direction: Vector2 = delta / distance_value
		var trim_value: float = minf(radius * 0.82, distance_value * 0.35)
		var start: Vector2 = point_a + direction * trim_value
		var end: Vector2 = point_b - direction * trim_value
		var type_a: int = 0 if a >= cell_type.size() else int(cell_type[a])
		var type_b: int = 0 if b >= cell_type.size() else int(cell_type[b])
		var color_a: Color = CATALOG.call("role_color", type_a)
		var color_b: Color = CATALOG.call("role_color", type_b)
		var link_color: Color = color_a.lerp(color_b, 0.5)
		var energy_a: float = 0.0 if a >= energies.size() else float(energies[a])
		var energy_b: float = 0.0 if b >= energies.size() else float(energies[b])
		var energy_delta: float = energy_a - energy_b
		_last_flow_bias += energy_delta
		# 外层柔光让连接像膜间桥，而不是一条硬线。
		draw_line(start, end, Color(link_color.r, link_color.g, link_color.b, 0.16), link_width * 3.2, true)
		draw_line(start, end, Color(link_color.r, link_color.g, link_color.b, 0.88), link_width, true)
		# 光点沿高能量 → 低能量方向移动；能量相等时仍显示连接但不强调流向。
		if show_flow_pulse and absf(energy_delta) > 0.001:
			var phase: float = fposmod(float(tick_value) * 0.035 + float(link_index) * 0.17, 1.0)
			if energy_delta < 0.0:
				phase = 1.0 - phase
			var pulse: Vector2 = start.lerp(end, phase)
			var pulse_color: Color = Color(
				minf(color_a.r * 0.5 + color_b.r * 0.5 + 0.3, 1.0),
				minf(color_a.g * 0.5 + color_b.g * 0.5 + 0.3, 1.0),
				minf(color_a.b * 0.5 + color_b.b * 0.5 + 0.3, 1.0),
				0.95
			)
			draw_circle(pulse, 1.6, pulse_color)
		_rendered_link_count += 1
