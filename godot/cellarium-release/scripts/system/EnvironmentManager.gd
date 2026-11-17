extends Node
## 皿级环境预设的持有者。培养基参数在本节点的 @export 中声明（.tscn），
## tick 内只读；预设在启动阶段绑定一次，回放时由 get_snapshot() 写入快照。

const PRESET_SCRIPT: GDScript = preload("res://scripts/core/data/EnvironmentPreset.gd")
const CONTEXT_SCRIPT: GDScript = preload("res://scripts/core/data/DevelopmentContext.gd")
const FIELD_SCRIPT: GDScript = preload("res://scripts/system/EnvironmentField.gd")
const FIELD_RESOLUTION: int = 32

@export_range(0.0, 4.0, 0.01) var nutrient_density: float = 1.0
@export_range(0, 64, 1) var max_dev_depth: int = 8
@export var temperature: float = 273.0
@export_range(0.0, 1.0, 0.01) var oxygen_fraction: float = 0.0
## 光照强度写入场通道 3；DECAY[3]=0，能持续供光合类型使用。
@export_range(0.0, 2.0, 0.01) var light_intensity: float = 0.6
@export var dish_center: Vector2 = Vector2(250, 250)
@export var dish_radius: float = 240.0

var preset: Resource = null
var dev_context: RefCounted = null
var field: RefCounted = FIELD_SCRIPT.new() as RefCounted
var field_diagnostics: Dictionary = {}
## 阶段10：每 tick 一次批量采样，行为/代谢复用同一批结果，不再逐细胞触发小回读。
var _sample_positions: Array[Vector2] = []
var _field_samples: Array[PackedFloat32Array] = []

func _ready() -> void:
	bind_preset()

func bind_preset() -> void:
	preset = PRESET_SCRIPT.new() as Resource
	preset.set("nutrient_density", nutrient_density)
	preset.set("temperature", temperature)
	preset.set("oxygen_fraction", oxygen_fraction)
	dev_context = CONTEXT_SCRIPT.new() as RefCounted
	var snap: Variant = preset.call("to_snapshot")
	var summary: Dictionary = Dictionary(snap)
	dev_context.call("setup", summary, max_dev_depth)
	var defaults: PackedFloat32Array = PackedFloat32Array([nutrient_density, float(summary.get("temperature", 273.0)), float(summary.get("oxygen_fraction", 0.0)), light_intensity, 0.0])
	field.call("configure", FIELD_RESOLUTION, dish_center, dish_radius, defaults)
	field_diagnostics = field.call("get_backend_diagnostics")

func apply_light_intensity() -> bool:
	return bool(field.call("fill_channel", 3, light_intensity))

func advance_field_tick(source_additions: Array[PackedFloat32Array] = []) -> bool:
	return bool(field.call("diffuse_tick", source_additions))

func begin_field_sampling(positions: Array[Vector2]) -> void:
	_sample_positions = positions.duplicate()
	_field_samples = field.call("sample_cells", positions)

func sample_fields(position: Vector2) -> PackedFloat32Array:
	var index: int = _sample_positions.find(position)
	if index >= 0 and index < _field_samples.size():
		return _field_samples[index]
	return field.call("sample", position)

func get_field_diagnostics() -> Dictionary:
	field_diagnostics = field.call("get_backend_diagnostics")
	return field_diagnostics.duplicate()

func consume_nutrient(position: Vector2, requested: float) -> float:
	return float(field.call("consume", 0, position, requested))

func consume_signal(position: Vector2, requested: float) -> float:
	return float(field.call("consume", 4, position, requested))

func add_nutrient_source(position: Vector2, amount: float) -> bool:
	if amount <= 0.0:
		return false
	var grid: Vector2i = field.call("get_grid_position", position)
	return bool(field.call("add_source", 0, grid.x, grid.y, amount))

func add_signal_source(position: Vector2, amount: float) -> bool:
	## 生物分泌/兼容路径：写入通道 4（化学信号）。
	return add_channel_source(position, 4, amount)

## 信号注射工具：按选定场通道注入 source。通道 0=营养 1=温度 2=氧气 3=光照 4=信号。
func add_channel_source(position: Vector2, channel_index: int, amount: float) -> bool:
	if amount <= 0.0 or channel_index < 0 or channel_index >= FIELD_SCRIPT.CHANNEL_COUNT:
		return false
	var grid: Vector2i = field.call("get_grid_position", position)
	return bool(field.call("add_source", channel_index, grid.x, grid.y, amount))

## 地形编辑（阶段5）：世界坐标 → 格坐标 → 固体 mask 笔刷。
func paint_terrain(position: Vector2, radius_cells: int, solid: bool) -> int:
	var grid: Vector2i = field.call("get_grid_position", position)
	return int(field.call("paint_terrain", grid.x, grid.y, radius_cells, solid))

func set_temperature_at(position: Vector2, value: float) -> bool:
	var grid: Vector2i = field.call("get_grid_position", position)
	return bool(field.call("set_value", 1, grid.x, grid.y, value))

func get_terrain_solid_count() -> int:
	return int(field.call("get_terrain_solid_count"))

func get_basal_autonomy() -> float:
	if preset == null:
		return 0.0
	return float(preset.call("get_basal_autonomy"))

func get_snapshot() -> Dictionary:
	if preset == null:
		return {}
	var snap: Variant = preset.call("to_snapshot")
	return Dictionary(snap)
