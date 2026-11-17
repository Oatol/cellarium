extends Node2D
## 场可视化层：把环境场通道直接画出来，参考 Cell Lab「能看到光」。
## 纯视图层：只读 EnvironmentManager.field 的通道副本，不写模拟状态、不进 tick 计算。
## v0.13.0：不再按 32×32 格画方块；先把通道双线性上采样到 128×128，再由 canvas shader
## 以连续渐变绘制，避免粗颗粒。物理采样仍用原始 32×32 场，二者数值完全一致。

@export var environment_manager_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var channel_index: int = 3
@export var visible_by_default: bool = true
@export var max_alpha: float = 0.55

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
void fragment() {
	float value = clamp(texture(field_tex, UV).r, 0.0, 1.0);
	float alpha = smoothstep(0.02, 1.0, value) * max_alpha;
	COLOR = vec4(tint_color.rgb, alpha);
}
"""
	_field_material = ShaderMaterial.new()
	_field_material.shader = shader
	_field_material.set_shader_parameter("tint_color", CHANNEL_COLORS[clampi(channel_index, 0, CHANNEL_COLORS.size() - 1)])
	_field_material.set_shader_parameter("max_alpha", max_alpha)
	_field_rect.material = _field_material

func _on_tick_advanced(_tick_index: int) -> void:
	if _enabled:
		_refresh_texture()
		queue_redraw()

func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		_refresh_texture()
		queue_redraw()

func is_enabled() -> bool:
	return _enabled

func set_channel(index: int) -> void:
	channel_index = clampi(index, 0, CHANNEL_COLORS.size() - 1)
	if _field_material != null:
		_field_material.set_shader_parameter("tint_color", CHANNEL_COLORS[channel_index])
	_refresh_texture()
	queue_redraw()

func mark_dirty() -> void:
	_refresh_texture()
	queue_redraw()

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
			var world: Vector2 = center + Vector2(u * 2.0 - 1.0, v * 2.0 - 1.0) * radius
			var intensity: float = 0.0
			if world.distance_squared_to(center) <= radius * radius:
				intensity = clampf(_sample_grid(values, resolution, u * float(resolution) - 0.5, v * float(resolution) - 0.5) / max_value, 0.0, 1.0)
			_field_image.set_pixel(px, py, Color(intensity, 0.0, 0.0, 1.0))
	_field_texture.update(_field_image)

func _sample_grid(values: PackedFloat32Array, resolution: int, gx: float, gy: float) -> float:
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

func _draw() -> void:
	if not _enabled or environment_manager == null:
		return
	var field: RefCounted = environment_manager.get("field") as RefCounted
	if field == null:
		return
	var center: Vector2 = field.get("center")
	var radius: float = float(field.get("radius"))
	var tint: Color = CHANNEL_COLORS[clampi(channel_index, 0, CHANNEL_COLORS.size() - 1)]
	# 皿内边界描一条暖色细环，让「照明覆盖范围」一眼可辨（纯视图派生）。
	draw_arc(center, radius, 0.0, TAU, 128, Color(tint.r, tint.g, tint.b, 0.55), 2.0, true)
