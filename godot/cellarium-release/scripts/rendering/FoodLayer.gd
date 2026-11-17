extends Node2D
## 食物可视化层：只读营养通道 0，把局部团块画成可见的亮点。
## 纯视图层：不写场、不进 tick 计算；只显示「高于局部平均」的确定型食物源，
## 因此均匀基底营养不会铺满屏幕，用户投放/环境生成的食物才可见。

@export var environment_manager_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var channel_index: int = 0
@export var visible_by_default: bool = true
@export var max_dots: int = 96
@export var contrast_threshold: float = 0.004
@export var min_intensity: float = 0.02
@export var dot_radius: float = 3.2

var environment_manager: Node = null
var tick_core: Node = null
var _enabled: bool = false
var _dots: Array[Dictionary] = []

const DOT_COLOR: Color = Color(0.42, 1.0, 0.68, 1.0)

func _ready() -> void:
	environment_manager = get_node_or_null(environment_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	_enabled = visible_by_default
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	visible = _enabled
	mark_dirty()

func _on_tick_advanced(_tick_index: int) -> void:
	if _enabled:
		mark_dirty()

func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		mark_dirty()

func is_enabled() -> bool:
	return _enabled

func get_last_dot_count() -> int:
	return _dots.size()

func mark_dirty() -> void:
	_rebuild_dots()
	queue_redraw()

func _grid_center_world(resolution: int, center: Vector2, radius: float, x: int, y: int) -> Vector2:
	var local: Vector2 = Vector2(
		(float(x) + 0.5) / float(resolution) * 2.0 - 1.0,
		(float(y) + 0.5) / float(resolution) * 2.0 - 1.0
	)
	return center + local * radius

func _rebuild_dots() -> void:
	_dots.clear()
	if environment_manager == null:
		return
	var field: RefCounted = environment_manager.get("field") as RefCounted
	if field == null:
		return
	var channels: Array = field.get("channels") as Array
	if channels == null or channel_index < 0 or channel_index >= channels.size():
		return
	var values: PackedFloat32Array = channels[channel_index] as PackedFloat32Array
	var resolution: int = int(field.get("resolution"))
	var center: Vector2 = field.get("center")
	var radius: float = float(field.get("radius"))
	if values.size() != resolution * resolution or resolution <= 0:
		return
	for y in range(1, resolution - 1):
		for x in range(1, resolution - 1):
			var index: int = y * resolution + x
			if _grid_center_world(resolution, center, radius, x, y).distance_squared_to(center) > radius * radius:
				continue
			var value: float = values[index]
			if value < min_intensity:
				continue
			var neighbor_sum: float = 0.0
			var neighbor_count: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= resolution or ny >= resolution:
						continue
					if _grid_center_world(resolution, center, radius, nx, ny).distance_squared_to(center) > radius * radius:
						continue
					neighbor_sum += values[ny * resolution + nx]
					neighbor_count += 1
			if neighbor_count == 0:
				continue
			var contrast: float = value - neighbor_sum / float(neighbor_count)
			if contrast < contrast_threshold:
				continue
			_dots.append({
				"position": _grid_center_world(resolution, center, radius, x, y),
				"strength": clampf(contrast * 18.0, 0.15, 1.0),
			})
	_dots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("strength", 0.0)) > float(b.get("strength", 0.0))
	)
	if _dots.size() > max_dots:
		_dots.resize(max_dots)

func _draw() -> void:
	if not _enabled:
		return
	for dot in _dots:
		var position: Vector2 = dot.get("position", Vector2.ZERO)
		var strength: float = clampf(float(dot.get("strength", 0.0)), 0.0, 1.0)
		draw_circle(position, dot_radius * (1.6 + strength), Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.10 * strength))
		draw_circle(position, dot_radius * (0.55 + strength * 0.5), Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.78 * strength))
		draw_circle(position, dot_radius * 0.28, Color(0.90, 1.0, 0.92, 0.92 * strength))
