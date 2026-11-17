extends Node2D
## 场可视化层：把环境场通道直接画出来，参考 Cell Lab「能看到光」。
## 纯视图层：只读 EnvironmentManager.field 的通道副本，不写模拟状态、不进 tick 计算。
## v0.13.1：皿壁边界改由 shader 用解析圆 + fwidth 抗锯齿绘制，不再用像素化遮罩/draw_arc；
## 双线性上采样时跳过圆外格，避免边缘把零值混进来形成暗边/锯齿。

@export var environment_manager_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var channel_index: int = 3
@export var visible_by_default: bool = true
@export var max_alpha: float = 0.55
@export var show_boundary_ring: bool = true

var environment_manager: Node = null
var tick_core: Node = null
var _enabled: bool = false
var _field_rect: ColorRect = null
var _field_material: ShaderMaterial = null
var _field_image: Image = null
var _field_texture: ImageTexture = null
var _cached_resolution: int = -1

const UPSCALE: int = 4
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
	_build_field_rect()
	visible = _enabled
	_refresh_texture()
	queue_redraw()

func _build_field_rect() -> void:
	_field_rect = ColorRect.new()
	_field_rect.name = "FieldRect"
	_field_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_field_rect)
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D field_tex;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float show_ring : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float dist = length(p);
	float aa = max(fwidth(dist), 0.0035);
	// 解析圆形抗锯齿遮罩：圆外完全透明，圆边按屏幕像素导数平滑。
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, dist);
	float value = clamp(texture(field_tex, UV).r, 0.0, 1.0);
	float field_alpha = smoothstep(0.02, 1.0, value) * max_alpha * inside;
	// 皿壁细环同样在 shader 里生成，避免 draw_arc 的 128 段折线锯齿。
	float ring = smoothstep(1.0 - aa * 3.0, 1.0 - aa, dist) * (1.0 - smoothstep(1.0, 1.0 + aa * 2.0, dist));
	float alpha = max(field_alpha, ring * 0.55 * show_ring);
	COLOR = vec4(tint_color.rgb, alpha);
}
"""
	_field_material = ShaderMaterial.new()
	_field_material.shader = shader
	_field_material.set_shader_parameter("tint_color", CHANNEL_COLORS[clampi(channel_index, 0, CHANNEL_COLORS.size() - 1)])
	_field_material.set_shader_parameter("max_alpha", max_alpha)
	_field_material.set_shader_parameter("show_ring", 1.0 if show_boundary_ring else 0.0)
	_field_rect.material = _field_material

func _on_tick_advanced(_tick_index: int) -> void:
	if _enabled:
		_refresh_texture()

func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		_refresh_texture()

func is_enabled() -> bool:
	return _enabled

func set_channel(index: int) -> void:
	channel_index = clampi(index, 0, CHANNEL_COLORS.size() - 1)
	if _field_material != null:
		_field_material.set_shader_parameter("tint_color", CHANNEL_COLORS[channel_index])
	_refresh_texture()

func mark_dirty() -> void:
	_refresh_texture()

func _refresh_texture() -> void:
	if environment_manager == null or _field_rect == null or _field_material == null:
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
	var display_resolution: int = resolution * UPSCALE
	if display_resolution != _cached_resolution or _field_image == null:
		_cached_resolution = display_resolution
		_field_image = Image.create(display_resolution, display_resolution, false, Image.FORMAT_RGBA8)
		_field_texture = ImageTexture.create_from_image(_field_image)
		_field_material.set_shader_parameter("field_tex", _field_texture)
	_field_rect.position = center - Vector2(radius, radius)
	_field_rect.size = Vector2(radius * 2.0, radius * 2.0)
	var max_value: float = 0.001
	for value in values:
		if value > max_value:
			max_value = value
	for py in range(display_resolution):
		for px in range(display_resolution):
			var u: float = (float(px) + 0.5) / float(display_resolution)
			var v: float = (float(py) + 0.5) / float(display_resolution)
			var intensity: float = clampf(
				_sample_grid_masked(values, resolution, center, radius,
					u * float(resolution) - 0.5, v * float(resolution) - 0.5) / max_value,
				0.0, 1.0)
			_field_image.set_pixel(px, py, Color(intensity, 0.0, 0.0, 1.0))
	_field_texture.update(_field_image)

func _grid_center_world(resolution: int, center: Vector2, radius: float, x: int, y: int) -> Vector2:
	var local: Vector2 = Vector2(
		(float(x) + 0.5) / float(resolution) * 2.0 - 1.0,
		(float(y) + 0.5) / float(resolution) * 2.0 - 1.0
	)
	return center + local * radius

func _sample_grid_masked(values: PackedFloat32Array, resolution: int, center: Vector2, radius: float, gx: float, gy: float) -> float:
	var bounded: Vector2 = Vector2(gx, gy).clamp(Vector2.ZERO, Vector2(float(resolution - 1), float(resolution - 1)))
	var base_x: int = floori(bounded.x)
	var base_y: int = floori(bounded.y)
	var next_x: int = mini(base_x + 1, resolution - 1)
	var next_y: int = mini(base_y + 1, resolution - 1)
	var fx: float = bounded.x - float(base_x)
	var fy: float = bounded.y - float(base_y)
	var total: float = 0.0
	var weight_total: float = 0.0
	for sample_y in [base_y, next_y]:
		for sample_x in [base_x, next_x]:
			var wx: float = fx if sample_x == next_x else 1.0 - fx
			var wy: float = fy if sample_y == next_y else 1.0 - fy
			var weight: float = wx * wy
			if weight <= 0.0:
				continue
			# 圆外格在物理场中恒 0；视图插值不能把它们混进来，否则边缘出现暗锯齿。
			if _grid_center_world(resolution, center, radius, sample_x, sample_y).distance_squared_to(center) > radius * radius:
				continue
			total += values[sample_y * resolution + sample_x] * weight
			weight_total += weight
	return total / weight_total if weight_total > 0.0 else 0.0
