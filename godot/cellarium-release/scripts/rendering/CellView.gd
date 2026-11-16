extends Node2D
## 单个细胞的可复用视图控制器。外观节点、挂点均在 CellBase.tscn 中声明。
## 只读模拟数据，绝不回写；所有写操作仍走 CommandBus。
## 弹性膜：12 控制点 Catmull-Rom + 3 谐波，20fps 刷新，沿速度轴轻度拉伸。
## 速度做低通后再驱动形变，避免碰撞瞬间把膜拉成夸张的椭圆。

const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const MEMBRANE: RefCounted = preload("res://scripts/rendering/CellMembrane.gd")
const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")

@export var cell_radius: float = SHAPE.REST_RADIUS
## 碰撞半径与弹性膜静息半径同源（Cell Lab 的 Cell.d 用法）；不再分两套半径。
@export var visual_radius: float = SHAPE.REST_RADIUS
@export var shape_fps: float = 20.0
## 弹性膜最大拉伸比例。Cell Lab 靠接触点压平而非整体拉长，这里刻意压低。
@export_range(0.0, 0.2, 0.01) var max_stretch: float = 0.08
## 速度低通系数，避免单 tick 碰撞冲量造成突变。
@export_range(0.05, 1.0, 0.05) var stretch_smoothing: float = 0.18

@onready var body: Polygon2D = get_node_or_null("Body") as Polygon2D
@onready var outline: Line2D = get_node_or_null("Outline") as Line2D

var _type_id: int = -1
var _org_id: int = -1
var _velocity: Vector2 = Vector2.ZERO
var _shape_time: float = 0.0
var _accumulated: float = 0.0
var _membrane: RefCounted = null
var _texture_cache: Dictionary = {}
## 贴图内容矩形按资源路径全局缓存，避免数百个细胞实例重复扫描像素。
static var _shared_content_rects: Dictionary = {}
var _stretch: float = 0.0

func apply_cell(position: Vector2, type_id: int, org_id: int, energy: float, velocity: Vector2 = Vector2.ZERO) -> void:
	global_position = position
	_velocity = velocity
	if type_id != _type_id or org_id != _org_id:
		_org_id = org_id
		_apply_type(type_id)
	var hue: float = fposmod(float(org_id) * 0.173 + 0.42, 1.0)
	var tint: Color = Color.from_hsv(hue, 0.32, 1.0, 0.94)
	# 能量低时轻微变暗；仅视图反馈，不影响账本。
	var vitality: float = clampf(energy / 1.2, 0.35, 1.0)
	tint.r *= vitality
	tint.g *= vitality
	tint.b *= vitality
	if body != null:
		body.modulate = tint
	if outline != null:
		outline.modulate = Color(tint.r, tint.g, tint.b, 0.9)
	_refresh_shape()

func _process(delta: float) -> void:
	_accumulated += delta
	var interval: float = 1.0 / maxf(1.0, shape_fps)
	if _accumulated < interval:
		return
	_shape_time += _accumulated
	_accumulated = 0.0
	_refresh_shape()

func _refresh_shape() -> void:
	if body == null or outline == null or _membrane == null:
		return
	# 碰撞修正会带来单 tick 速度尖峰，先限幅再低通。
	var velocity_limit: float = maxf(1.0, visual_radius * 0.5)
	var target_stretch: float = clampf(_velocity.length() / velocity_limit, 0.0, 1.0) * max_stretch
	_stretch += (target_stretch - _stretch) * clampf(stretch_smoothing, 0.05, 1.0)
	var unit: PackedVector2Array = _membrane.outline(_shape_time, _stretch)
	var angle: float = 0.0 if _stretch < 0.001 else _velocity.angle()
	# 轮廓与 UV 用同一组旋转后的单位点，纹理才会跟着膜走，不再留缝。
	var rotated_unit: PackedVector2Array = PackedVector2Array()
	var world_points: PackedVector2Array = PackedVector2Array()
	for point in unit:
		var rotated_point: Vector2 = point.rotated(angle)
		rotated_unit.append(rotated_point)
		world_points.append(rotated_point * visual_radius)
	var texture: Texture2D = body.texture as Texture2D
	var texture_size: Vector2 = Vector2(64.0, 64.0) if texture == null else texture.get_size()
	var content: Rect2 = Rect2(Vector2.ZERO, texture_size)
	if texture != null:
		content = _content_rect(texture)
	body.polygon = world_points
	body.uv = _membrane.texture_uv(rotated_unit, texture_size, content)
	outline.points = world_points

## 取贴图实际不透明区域，裁掉 guide-icon 的透明内缩（zygocyte 166px 图内容仅 139px）。
func _content_rect(texture: Texture2D) -> Rect2:
	var path: String = texture.resource_path
	if _shared_content_rects.has(path):
		return _shared_content_rects[path]
	var image: Image = texture.get_image()
	var rect: Rect2 = Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height()))
	if image.get_width() > 0 and image.get_height() > 0:
		var min_x: int = image.get_width()
		var min_y: int = image.get_height()
		var max_x: int = -1
		var max_y: int = -1
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.03:
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
		if max_x >= min_x and max_y >= min_y:
			rect = Rect2(
				Vector2(float(min_x), float(min_y)),
				Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1))
			)
	_shared_content_rects[path] = rect
	return rect

func _apply_type(type_id: int) -> void:
	_type_id = type_id
	if body == null:
		return
	var path: String = CATALOG.call("texture_path", type_id)
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path)
	var texture: Texture2D = _texture_cache[path] as Texture2D
	if texture != null:
		body.texture = texture
	_membrane = MEMBRANE.new(MEMBRANE.call("make_signature", _org_id, type_id))

func get_type_id() -> int:
	return _type_id

func get_type_label() -> String:
	return str(CATALOG.call("label", _type_id))

func get_outline_point_count() -> int:
	return 0 if outline == null else outline.points.size()

func get_collision_radius() -> float:
	return cell_radius

func get_visual_rest_radius() -> float:
	return visual_radius

func get_stretch() -> float:
	return _stretch

func get_content_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(1, 1)) if body == null or body.texture == null else _content_rect(body.texture as Texture2D)
