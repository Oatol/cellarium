extends Node
## 皿级环境预设的持有者。培养基参数在本节点的 @export 中声明（.tscn），
## tick 内只读；预设在启动阶段绑定一次，回放时由 get_snapshot() 写入快照。

const PRESET_SCRIPT: GDScript = preload("res://scripts/core/data/EnvironmentPreset.gd")
const CONTEXT_SCRIPT: GDScript = preload("res://scripts/core/data/DevelopmentContext.gd")
const FIELD_SCRIPT: GDScript = preload("res://scripts/system/EnvironmentField.gd")
const FIELD_RESOLUTION: int = 32

## v0.13.0：环境设置快照键。只做版本化追加，不改 schema_version。
const ENVIRONMENT_SETTING_KEYS: Array[String] = [
	"nutrient_density", "temperature", "oxygen_fraction", "max_dev_depth",
	"light_intensity", "light_source_mode", "light_range", "light_angle_deg", "light_falloff",
	"food_spawn_amount", "food_lump_radius", "food_layer", "food_coated_ratio",
]

@export_range(0.0, 4.0, 0.01) var nutrient_density: float = 1.0
@export_range(0, 64, 1) var max_dev_depth: int = 8
@export var temperature: float = 273.0
@export_range(0.0, 1.0, 0.01) var oxygen_fraction: float = 0.0
## 光照强度写入场通道 3；DECAY[3]=0，能持续供光合类型使用。
@export_range(0.0, 2.0, 0.01) var light_intensity: float = 0.6
## v0.13.0 Macro 风格空间光照：0=全皿均匀，1=边缘点光，2=中心点光。
@export_range(0, 2, 1) var light_source_mode: int = 1
@export_range(0.2, 2.0, 0.01) var light_range: float = 1.25
@export_range(0.0, 360.0, 1.0) var light_angle_deg: float = 0.0
@export_range(0.0, 1.0, 0.01) var light_falloff: float = 0.55
## Macro 食物池在本项目映射为五通道营养场源项；不使用全局 RNG。
@export_range(0.0, 0.5, 0.001) var food_spawn_amount: float = 0.018
@export_range(0, 8, 1) var food_lump_radius: int = 2
@export_range(0.0, 1.0, 0.01) var food_layer: float = 0.5
## 静态证据字段：Macro 有涂层比例，本项目暂不进物理，仅随快照保存。
@export_range(0.0, 1.0, 0.01) var food_coated_ratio: float = 0.0
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
	apply_light_settings()
	field_diagnostics = field.call("get_backend_diagnostics")

## 兼容 v0.12.1 的调用点：现在实际写入 Macro 风格空间光照快照。
func apply_light_intensity() -> bool:
	return apply_light_settings()

## Macro 的 Environment.q() 是空间场采样；本项目把通道 3 做成可配置静态分布：
## 0=全皿均匀（v0.12.1 行为），1=边缘定向点光，2=中心点光。
func apply_light_settings() -> bool:
	if field == null:
		return false
	var grid_resolution: int = int(field.get("resolution"))
	var center_value: Vector2 = field.get("center")
	var radius_value: float = float(field.get("radius"))
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(grid_resolution * grid_resolution)
	var angle: float = deg_to_rad(light_angle_deg)
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var source: Vector2 = center_value
	if light_source_mode == 1:
		source = center_value + direction * radius_value * 0.95
	var reach: float = maxf(0.001, light_range * radius_value * 2.0)
	var exponent: float = 1.0 + clampf(light_falloff, 0.0, 1.0) * 4.0
	for row in range(grid_resolution):
		for column in range(grid_resolution):
			var index: int = row * grid_resolution + column
			if light_source_mode == 0:
				values[index] = light_intensity
				continue
			var local: Vector2 = Vector2(
				(float(column) + 0.5) / float(grid_resolution) * 2.0 - 1.0,
				(float(row) + 0.5) / float(grid_resolution) * 2.0 - 1.0
			)
			var world: Vector2 = center_value + local * radius_value
			var attenuation: float = clampf(1.0 - world.distance_to(source) / reach, 0.0, 1.0)
			values[index] = light_intensity * pow(attenuation, exponent)
	return bool(field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_LIGHT, values))

## UI 改动环境预设后调用：重算 preset/dev_context 快照并刷新三张非光照通道。
func apply_environment_preset() -> bool:
	if preset == null:
		bind_preset()
	if preset == null:
		return false
	preset.set("nutrient_density", nutrient_density)
	preset.set("temperature", temperature)
	preset.set("oxygen_fraction", oxygen_fraction)
	var snap: Variant = preset.call("to_snapshot")
	var summary: Dictionary = Dictionary(snap)
	dev_context.call("setup", summary, max_dev_depth)
	var grid_resolution: int = int(field.get("resolution"))
	var count: int = grid_resolution * grid_resolution
	var nutrient_values: PackedFloat32Array = PackedFloat32Array()
	var temperature_values: PackedFloat32Array = PackedFloat32Array()
	var oxygen_values: PackedFloat32Array = PackedFloat32Array()
	nutrient_values.resize(count)
	temperature_values.resize(count)
	oxygen_values.resize(count)
	for index in range(count):
		nutrient_values[index] = nutrient_density
		temperature_values[index] = temperature
		oxygen_values[index] = oxygen_fraction
	var ok: bool = true
	ok = ok and bool(field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_NUTRIENT, nutrient_values))
	ok = ok and bool(field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_TEMPERATURE, temperature_values))
	ok = ok and bool(field.call("set_channel_values", FIELD_SCRIPT.CHANNEL_OXYGEN, oxygen_values))
	ok = ok and apply_light_settings()
	field_diagnostics = field.call("get_backend_diagnostics")
	return ok

## Macro 的 Food[] 定长池在本项目映射为营养场源项：每 tick 一个确定型团块。
## tick_index + 常量盐决定位置，不使用全局 RNG；外部干预不进确定性 hash。
func apply_nutrient_sources(tick_index: int) -> bool:
	if food_spawn_amount <= 0.0 or field == null:
		return false
	var angle_seed: float = _hash_unit(tick_index, 0x51f2a1c3, 0x9e3779b9)
	var radius_seed: float = _hash_unit(tick_index, 0x7f4a7c15, 0x85ebca6b)
	var radial_bias: float = lerpf(0.55, 1.8, clampf(food_layer, 0.0, 1.0))
	var radial: float = pow(sqrt(radius_seed), radial_bias) * 0.94
	var source_position: Vector2 = dish_center + Vector2(cos(angle_seed * TAU), sin(angle_seed * TAU)) * dish_radius * radial
	var grid: Vector2i = field.call("get_grid_position", source_position)
	var lump_radius: int = maxi(0, food_lump_radius)
	var offsets: Array[Vector2i] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for dy in range(-lump_radius, lump_radius + 1):
		for dx in range(-lump_radius, lump_radius + 1):
			var distance_sq: int = dx * dx + dy * dy
			if distance_sq > lump_radius * lump_radius:
				continue
			var weight: float = 1.0 / float(1 + distance_sq)
			offsets.append(Vector2i(dx, dy))
			weights.append(weight)
			total_weight += weight
	if total_weight <= 0.0:
		return false
	for index in range(offsets.size()):
		var offset: Vector2i = offsets[index]
		field.call("add_source", FIELD_SCRIPT.CHANNEL_NUTRIENT,
			grid.x + offset.x, grid.y + offset.y,
			food_spawn_amount * weights[index] / total_weight)
	return true

func _hash_unit(a: int, b: int, c: int) -> float:
	var hash_value: int = 0x811c9dc5
	for value in [a, b, c, 0x9e3779b9]:
		hash_value = int((hash_value ^ (value & 0xffffffff)) * 0x01000193) & 0xffffffff
	return float(hash_value) / 4294967296.0

func get_environment_settings() -> Dictionary:
	var result: Dictionary = {}
	for key in ENVIRONMENT_SETTING_KEYS:
		result[key] = get(key)
	return result

func apply_environment_settings(settings: Dictionary) -> bool:
	if settings == null:
		return false
	for key in ENVIRONMENT_SETTING_KEYS:
		if not settings.has(key):
			continue
		if key == "light_source_mode":
			light_source_mode = clampi(int(settings[key]), 0, 2)
		elif key == "food_lump_radius":
			food_lump_radius = clampi(int(settings[key]), 0, 8)
		elif key == "max_dev_depth":
			max_dev_depth = clampi(int(settings[key]), 0, 64)
		else:
			set(key, settings[key])
	return apply_environment_preset()

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
