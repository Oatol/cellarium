extends Node2D
## 场可视化层（阶段 UI 调整）：把光照场通道直接画出来，参考 Cell Lab「能看到光」。
## 纯视图层：只读 EnvironmentManager.field 的通道副本，不写模拟状态、不进 tick 计算。
## 场按 32×32 网格存储，这里按格画半透明暖色方块，强度映射 alpha；可切换通道/开关。

@export var environment_manager_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var channel_index: int = 3
@export var visible_by_default: bool = false
@export var max_alpha: float = 0.42

var environment_manager: Node = null
var tick_core: Node = null
var _enabled: bool = false

const CHANNEL_COLORS: Array[Color] = [
	Color(0.36, 0.88, 0.62),  # 0 营养 青绿
	Color(0.95, 0.55, 0.42),  # 1 温度 暖红
	Color(0.48, 0.72, 1.0),   # 2 氧气 蓝
	Color(1.0, 0.86, 0.42),   # 3 光照 暖黄
	Color(0.72, 0.58, 1.0),   # 4 信号 紫
]

func _ready() -> void:
	environment_manager = get_node_or_null(environment_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	_enabled = visible_by_default
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	visible = _enabled
	queue_redraw()

func _on_tick_advanced(_tick_index: int) -> void:
	if _enabled:
		queue_redraw()

func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		queue_redraw()

func is_enabled() -> bool:
	return _enabled

func set_channel(index: int) -> void:
	channel_index = clampi(index, 0, CHANNEL_COLORS.size() - 1)
	queue_redraw()

func mark_dirty() -> void:
	queue_redraw()

func _draw() -> void:
	if not _enabled or environment_manager == null:
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
	var cell_size: float = (2.0 * radius) / float(resolution)
	var origin: Vector2 = center - Vector2(radius, radius)
	var tint: Color = CHANNEL_COLORS[clampi(channel_index, 0, CHANNEL_COLORS.size() - 1)]
	var max_value: float = 1.0
	for value in values:
		if value > max_value:
			max_value = value
	max_value = maxf(max_value, 0.001)
	for row in range(resolution):
		for column in range(resolution):
			var index: int = row * resolution + column
			if index >= values.size():
				continue
			var value: float = values[index]
			if value <= 0.001:
				continue
			var world_cell: Vector2 = origin + Vector2(float(column) * cell_size, float(row) * cell_size)
			# 圆外格不画（与场 _is_active 一致）。
			if world_cell.distance_to(center) > radius:
				continue
			var strength: float = clampf(value / max_value, 0.0, 1.0)
			draw_rect(Rect2(world_cell, Vector2(cell_size + 0.5, cell_size + 0.5)),
				Color(tint.r, tint.g, tint.b, strength * max_alpha), true)
