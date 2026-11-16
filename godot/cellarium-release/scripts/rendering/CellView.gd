extends Node2D
## 单个细胞的可复用视图控制器。外观节点、挂点均在 CellBase.tscn 中声明。
## 只读模拟数据，绝不回写；所有写操作仍走 CommandBus。
## 弹性膜：12 控制点 Catmull-Rom + 3 谐波，20fps 刷新，沿速度轴拉伸。

const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const MEMBRANE: RefCounted = preload("res://scripts/rendering/CellMembrane.gd")

@export var cell_radius: float = 4.0
## 视觉半径略大于物理半径，让近景能看清膜形变；不影响碰撞。
@export var visual_radius: float = 7.0
@export var shape_fps: float = 20.0

@onready var body: Polygon2D = get_node_or_null("Body") as Polygon2D
@onready var outline: Line2D = get_node_or_null("Outline") as Line2D

var _type_id: int = -1
var _org_id: int = -1
var _velocity: Vector2 = Vector2.ZERO
var _shape_time: float = 0.0
var _accumulated: float = 0.0
var _membrane: RefCounted = null
var _texture_cache: Dictionary = {}

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
	var stretch: float = clampf(_velocity.length() * 0.18, 0.0, 0.28)
	var unit: PackedVector2Array = _membrane.outline(_shape_time, stretch)
	var texture: Texture2D = body.texture as Texture2D
	var texture_size: Vector2 = Vector2(64.0, 64.0) if texture == null else texture.get_size()
	var uv: PackedVector2Array = _membrane.texture_uv(unit, texture_size)
	var angle: float = 0.0 if stretch < 0.001 else _velocity.angle()
	var rotated: PackedVector2Array = PackedVector2Array()
	for point in unit:
		rotated.append(point.rotated(angle) * visual_radius)
	body.polygon = rotated
	body.uv = uv
	outline.points = rotated

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
