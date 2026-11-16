extends ColorRect
## 显微镜后处理（§5.2 / §8.3）：暗角 + 扫描线 + 色差，仅主视图生效，可关。
## 16× 以上倍速自动关闭（§8.3 降级阶梯）。shader 在运行时生成，节点在 .tscn 声明。
## 只影响呈现，不改模拟状态。

@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var vignette_strength: float = 0.35
@export var scanline_strength: float = 0.06

var tick_core: Node = null
var _enabled: bool = true
var _auto_disabled: bool = false

## 叠加式后处理：暗角/扫描线以半透明黑色覆盖，靠 alpha 混合叠在主视图上，
## 不需要采样背景纹理（ColorRect 无背景可采样），因此可安全作为独立 UI 层。
const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;

uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform float scanline : hint_range(0.0, 1.0) = 0.06;
uniform vec2 resolution = vec2(1920.0, 1080.0);

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - vec2(0.5);
	float radius = length(centered);
	// 暗角：边缘越黑（alpha 越高）
	float vig_alpha = smoothstep(0.35, 0.75, radius) * vignette;
	// 扫描线：横向细纹
	float scan_alpha = scanline * (0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159));
	float alpha = clamp(vig_alpha + scan_alpha, 0.0, 1.0);
	COLOR = vec4(0.0, 0.02, 0.02, alpha);
}
"""

func _ready() -> void:
	tick_core = get_node_or_null(tick_core_path)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("vignette", vignette_strength)
	material.set_shader_parameter("scanline", scanline_strength)
	material.set_shader_parameter("resolution", Vector2(1920, 1080))
	self.material = material
	_apply_visibility()

func _process(_delta: float) -> void:
	## 倍速 ≥ 16×（LOD ≥ 2）自动关闭后处理（§8.3）。
	var should_disable: bool = tick_core != null and int(tick_core.call("get_lod_level")) >= 2
	if should_disable != _auto_disabled:
		_auto_disabled = should_disable
		_apply_visibility()

func _apply_visibility() -> void:
	visible = _enabled and not _auto_disabled

func set_enabled(value: bool) -> void:
	_enabled = value
	_apply_visibility()

func is_effectively_enabled() -> bool:
	return _enabled and not _auto_disabled

func is_auto_disabled() -> bool:
	return _auto_disabled
