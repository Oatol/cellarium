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
## 圆外格 → 最近圆内格的索引映射（只依赖 resolution/center/radius，缓存避免每 tick O(res^4)）。
var _pad_source: PackedInt32Array = PackedInt32Array()
var _pad_center: Vector2 = Vector2.ZERO
var _pad_radius: float = -1.0
var _ticks_since_refresh: int = 0

## v0.14.0 性能：视图层刷新与 tick 解耦。场纹理只在节流窗口或显式 mark_dirty 时重建；
## 分辨率由 32×4=128 降到 32×2=64，shader 用 filter_linear 做 GPU 双线性，视觉仍平滑。
const UPSCALE: int = 2
## 1× 下每 6 tick 刷新（10 Hz）；光场是静态空间快照，肉眼看不出延迟。
const REFRESH_TICKS: int = 6
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
	// 皿内保留极淡基底：光场弱的一侧也不会出现黑色空环（Cell Lab 的光照是连续覆盖）。
	float field_alpha = (0.05 + 0.95 * smoothstep(0.0, 0.9, value)) * max_alpha * inside;
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
	if not _enabled:
		return
	_ticks_since_refresh += 1
	if _ticks_since_refresh >= REFRESH_TICKS:
		_ticks_since_refresh = 0
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
	# 生成补齐后的场：圆外的格在物理场里为 0，但若直接参与插值会形成黑色空环；
	# 这里只用于视图，用最近的圆内格值补齐，保证纹理铺满整个圆形皿。
	var padded: PackedFloat32Array = values.duplicate()
	if _pad_source.size() != resolution * resolution or center != _pad_center or not is_equal_approx(radius, _pad_radius):
		_build_pad_source(resolution, center, radius)
	for index in range(resolution * resolution):
		var source_index: int = _pad_source[index]
		if source_index >= 0 and source_index < values.size():
			padded[index] = values[source_index]
	for py in range(display_resolution):
		for px in range(display_resolution):
			var u: float = (float(px) + 0.5) / float(display_resolution)
			var v: float = (float(py) + 0.5) / float(display_resolution)
			var intensity: float = clampf(
				_sample_grid_masked(padded, resolution, center, radius,
					u * float(resolution) - 0.5, v * float(resolution) - 0.5) / max_value,
				0.0, 1.0)
			_field_image.set_pixel(px, py, Color(intensity, 0.0, 0.0, 1.0))
	_field_texture.update(_field_image)

## 圆外格映射到最近的圆内格；只在几何参数变化时算一次。
func _build_pad_source(resolution: int, center: Vector2, radius: float) -> void:
	_pad_source.resize(resolution * resolution)
	_pad_center = center
	_pad_radius = radius
	for index in range(_pad_source.size()):
		_pad_source[index] = -1
	for y in range(resolution):
		for x in range(resolution):
			var index: int = y * resolution + x
			if _grid_center_world(resolution, center, radius, x, y).distance_squared_to(center) <= radius * radius:
				_pad_source[index] = index
	for y in range(resolution):
		for x in range(resolution):
			var index: int = y * resolution + x
			if _pad_source[index] >= 0:
				continue
			var best_distance: float = INF
			var best_index: int = -1
			for sy in range(resolution):
				for sx in range(resolution):
					var source_index: int = sy * resolution + sx
					if _pad_source[source_index] != source_index:
						continue
					var distance_squared: float = float((sx - x) * (sx - x) + (sy - y) * (sy - y))
					if distance_squared < best_distance:
						best_distance = distance_squared
						best_index = source_index
			_pad_source[index] = best_index

func _grid_center_world(resolution: int, center: Vector2, radius: float, x: int, y: int) -> Vector2:
	var local: Vector2 = Vector2(
		(float(x) + 0.5) / float(resolution) * 2.0 - 1.0,
		(float(y) + 0.5) / float(resolution) * 2.0 - 1.0
	)
	return center + local * radius

func _sample_grid_masked(values: PackedFloat32Array, resolution: int, _center: Vector2, _radius: float, gx: float, gy: float) -> float:
	# values 已经过 _pad_source 补齐（圆外格复制最近圆内格），因此这里只做双线性，
	# 不再按格心距离剔除；否则外圈格心在圆外时会被全部跳过，形成黑色空隙。
	var bounded: Vector2 = Vector2(gx, gy).clamp(Vector2.ZERO, Vector2(float(resolution - 1), float(resolution - 1)))
	var base_x: int = floori(bounded.x)
	var base_y: int = floori(bounded.y)
	var next_x: int = mini(base_x + 1, resolution - 1)
	var next_y: int = mini(base_y + 1, resolution - 1)
	var fx: float = bounded.x - float(base_x)
	var fy: float = bounded.y - float(base_y)
	var top: float = lerpf(values[base_y * resolution + base_x], values[base_y * resolution + next_x], fx)
	var bottom: float = lerpf(values[next_y * resolution + base_x], values[next_y * resolution + next_x], fx)
	return lerpf(top, bottom, fy)
