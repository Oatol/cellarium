extends Camera2D
## 显微视野控制：滚轮以光标为锚点缩放，右键拖动平移。
## 只改视图（camera transform），绝不触碰模拟状态或 tick。

signal view_changed(zoom_value: float, center: Vector2)

@export var dish_center: Vector2 = Vector2(250, 250)
@export var dish_radius: float = 240.0
@export var min_zoom: float = 0.6
@export var max_zoom: float = 8.0
@export var wheel_step: float = 1.12
@export var pan_limit_scale: float = 1.1

var dragging: bool = false
var _drag_origin: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			zoom_at(mouse_button.position, wheel_step)
			get_viewport().set_input_as_handled()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			zoom_at(mouse_button.position, 1.0 / wheel_step)
			get_viewport().set_input_as_handled()
			return
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mouse_button.pressed
			_drag_origin = mouse_button.position
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and dragging:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		pan_screen(mouse_motion.position - _drag_origin)
		_drag_origin = mouse_motion.position
		get_viewport().set_input_as_handled()

## 屏幕点 → 世界点。Camera2D 默认 DRAG_CENTER，offset 为 0，父节点无变换。
## 用显式公式，不依赖 get_canvas_transform() 的帧内刷新时机。
func screen_to_world(screen_position: Vector2) -> Vector2:
	var viewport: Viewport = get_viewport()
	var center: Vector2 = Vector2.ZERO if viewport == null else viewport.get_visible_rect().size * 0.5
	var local: Vector2 = (screen_position - center - offset).rotated(-rotation)
	var z: float = maxf(zoom.x, 0.0001)
	return position + local / z

## 滚轮缩放：保持 screen_position 下的世界点不动。
func zoom_at(screen_position: Vector2, factor: float) -> void:
	var old_zoom: float = maxf(zoom.x, 0.0001)
	var new_zoom: float = clampf(old_zoom * factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var anchor: Vector2 = screen_to_world(screen_position)
	zoom = Vector2(new_zoom, new_zoom)
	var viewport: Viewport = get_viewport()
	var center: Vector2 = Vector2.ZERO if viewport == null else viewport.get_visible_rect().size * 0.5
	var local: Vector2 = (screen_position - center - offset).rotated(-rotation)
	position = anchor - local / new_zoom
	_clamp_position()
	view_changed.emit(zoom.x, position)

## 右键拖动：屏幕位移换算为世界位移。
func pan_screen(screen_delta: Vector2) -> void:
	if screen_delta == Vector2.ZERO:
		return
	position -= (screen_delta / maxf(zoom.x, 0.0001)).rotated(-rotation)
	_clamp_position()
	view_changed.emit(zoom.x, position)

func reset_view() -> void:
	zoom = Vector2(2.0, 2.0)
	position = dish_center
	rotation = 0.0
	dragging = false
	_clamp_position()
	view_changed.emit(zoom.x, position)

func _clamp_position() -> void:
	var limit: float = maxf(1.0, dish_radius * pan_limit_scale)
	var delta: Vector2 = position - dish_center
	if delta.length_squared() > limit * limit:
		position = dish_center + delta.normalized() * limit
