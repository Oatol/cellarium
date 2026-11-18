extends Node2D
## 食物可视化层：v0.14.0 优先画 FoodStore 定长池实体（Cell Lab 方法），
## 兼容回退到营养通道的局部对比度团块视图；纯视图层，不写场、不进 tick 计算。

@export var environment_manager_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var channel_index: int = 0
@export var visible_by_default: bool = true
@export var max_dots: int = 96
@export var contrast_threshold: float = 0.004
@export var min_intensity: float = 0.02
@export var dot_radius: float = 3.2
## 视图刷新节流：食物团块由确定型源投放，10 Hz 足够，避免每 tick 全网格扫描。
const REFRESH_TICKS: int = 6

var environment_manager: Node = null
var tick_core: Node = null
var _enabled: bool = false
var _dots: Array[Dictionary] = []
var _entities: Array[Dictionary] = []
var _grid_centers: Array[float] = []  # x²+y² 相对皿心的平方距离，避免每 tick 分配 Vector2
var _cached_resolution: int = -1
var _cached_center: Vector2 = Vector2.ZERO
var _cached_radius: float = -1.0
var _ticks_since_refresh: int = 0

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
	if not _enabled:
		return
	_ticks_since_refresh += 1
	if _ticks_since_refresh >= REFRESH_TICKS:
		_ticks_since_refresh = 0
		mark_dirty()

func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		mark_dirty()

func is_enabled() -> bool:
	return _enabled

func get_last_dot_count() -> int:
	return _entities.size() if not _entities.is_empty() else _dots.size()

func mark_dirty() -> void:
	_rebuild_entities()
	_rebuild_dots()
	queue_redraw()

func _grid_center_world(resolution: int, center: Vector2, radius: float, x: int, y: int) -> Vector2:
	var local: Vector2 = Vector2(
		(float(x) + 0.5) / float(resolution) * 2.0 - 1.0,
		(float(y) + 0.5) / float(resolution) * 2.0 - 1.0
	)
	return center + local * radius

## 缓存每个格心是否皿内 + 世界坐标，只在几何变化时重算。
func _ensure_grid_cache(resolution: int, center: Vector2, radius: float) -> void:
	if resolution == _cached_resolution and center == _cached_center and is_equal_approx(radius, _cached_radius):
		return
	_cached_resolution = resolution
	_cached_center = center
	_cached_radius = radius
	_grid_centers.clear()
	_grid_centers.resize(resolution * resolution * 3)
	for y in range(resolution):
		for x in range(resolution):
			var world: Vector2 = _grid_center_world(resolution, center, radius, x, y)
			var index: int = (y * resolution + x) * 3
			_grid_centers[index] = world.x
			_grid_centers[index + 1] = world.y
			_grid_centers[index + 2] = 1.0 if world.distance_squared_to(center) <= radius * radius else 0.0

## v0.14.0：优先从 EnvironmentManager.food_store 取实体快照。
func _rebuild_entities() -> void:
	_entities.clear()
	if environment_manager == null or not environment_manager.has_method("get_food_store"):
		return
	var store: RefCounted = environment_manager.call("get_food_store") as RefCounted
	if store == null or not store.has_method("snapshot"):
		return
	_entities = store.call("snapshot") as Array[Dictionary]
	if _entities.size() > max_dots:
		_entities.resize(max_dots)

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
	_ensure_grid_cache(resolution, center, radius)
	for y in range(1, resolution - 1):
		for x in range(1, resolution - 1):
			var index: int = y * resolution + x
			if _grid_centers[index * 3 + 2] < 0.5:
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
					if _grid_centers[(ny * resolution + nx) * 3 + 2] < 0.5:
						continue
					neighbor_sum += values[ny * resolution + nx]
					neighbor_count += 1
			if neighbor_count == 0:
				continue
			var contrast: float = value - neighbor_sum / float(neighbor_count)
			if contrast < contrast_threshold:
				continue
			var cache_index: int = index * 3
			_dots.append({
				"position": Vector2(_grid_centers[cache_index], _grid_centers[cache_index + 1]),
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
	if not _entities.is_empty():
		for entity in _entities:
			var position: Vector2 = entity.get("position", Vector2.ZERO)
			var ratio: float = clampf(float(entity.get("ratio", 1.0)), 0.0, 1.0)
			var coating: float = clampf(float(entity.get("coating", 0.0)), 0.0, 1.0)
			var size_value: float = 0.55 + ratio * 0.9
			var glow: Color = Color(0.42, 1.0, 0.68, 0.14 * ratio)
			var core: Color = Color(
				lerpf(0.42, 0.95, coating), 1.0, lerpf(0.68, 0.52, coating),
				0.82 * (0.35 + 0.65 * ratio))
			draw_circle(position, dot_radius * (1.5 + size_value), glow)
			draw_circle(position, dot_radius * size_value, core)
			draw_circle(position, dot_radius * 0.28 * size_value, Color(0.92, 1.0, 0.94, 0.9 * ratio))
		return
	for dot in _dots:
		var position: Vector2 = dot.get("position", Vector2.ZERO)
		var strength: float = clampf(float(dot.get("strength", 0.0)), 0.0, 1.0)
		draw_circle(position, dot_radius * (1.6 + strength), Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.10 * strength))
		draw_circle(position, dot_radius * (0.55 + strength * 0.5), Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.78 * strength))
		draw_circle(position, dot_radius * 0.28, Color(0.90, 1.0, 0.92, 0.92 * strength))
