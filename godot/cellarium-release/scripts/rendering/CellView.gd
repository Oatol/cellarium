extends Node2D
## 单个细胞的可复用视图控制器。外观节点与挂点全部在 CellBase.tscn 中声明。
## 只读模拟数据，绝不回写；所有写操作仍走 CommandBus。
##
## Cell Lab 没有"细胞贴图"：细胞由 *_vert.glsl / *_frag.glsl + 顶点缓冲程序化绘制，
## guide-icons 只是类型图鉴。本项目同样用场景节点程序化画膜、内膜、核与细胞器，
## 并按共享弦把接触处切平（Cell Lab 的 A[] 接触点 → 膜压平概念）。
## 外膜统一用解析圆 + 共享弦裁剪，不叠加独立呼吸膜，避免两套轮廓互相切换。

const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const MEMBRANE: RefCounted = preload("res://scripts/rendering/CellMembrane.gd")
const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const CHORDS: RefCounted = preload("res://scripts/rendering/CellContactChords.gd")

@export var cell_radius: float = SHAPE.REST_RADIUS
## 物理碰撞半径与弹性膜静息半径同源（Cell Lab 的 Cell.d 用法）。
@export var visual_radius: float = SHAPE.REST_RADIUS
@export var shape_fps: float = 20.0
## v0.19.0：膜轮廓解析圆采样点数。默认 64 保持独立实例旧行为；
## CellBase.tscn 设为 48，链条增长时减少每帧每细胞的弦裁剪与顶点写入成本。
@export_range(12, 64, 1) var outline_segments: int = 64
## 速度拉伸上限，碰撞冲量先限幅再低通，避免夸张椭圆。
@export_range(0.0, 0.2, 0.01) var max_stretch: float = 0.08
@export_range(0.05, 1.0, 0.05) var stretch_smoothing: float = 0.18
## 三类接触的膜压平深度（相对半径）。普通碰撞最浅，黏附连接最平，皿壁居中。
@export_range(0.0, 0.3, 0.01) var contact_flatten: float = 0.09
@export_range(0.0, 0.3, 0.01) var adhesion_flatten: float = 0.15
@export_range(0.0, 0.3, 0.01) var wall_flatten: float = 0.13

@onready var body: Polygon2D = get_node_or_null("Body") as Polygon2D
@onready var outline: Line2D = get_node_or_null("Outline") as Line2D
@onready var inner_ring: Line2D = get_node_or_null("InnerRing") as Line2D
@onready var nucleus: Polygon2D = get_node_or_null("Nucleus") as Polygon2D
@onready var organelle_root: Node2D = get_node_or_null("OrganelleRoot") as Node2D

var _type_id: int = -1
var _org_id: int = -1
var _velocity: Vector2 = Vector2.ZERO
var _contacts: Array[Vector2] = []
var _adhesions: Array[Vector2] = []
var _wall_contacts: Array[Vector2] = []
var _chords: Array = []
var _shape_time: float = 0.0
var _accumulated: float = 0.0
var _stretch: float = 0.0
var _membrane: RefCounted = null
var _organelles: Array[Polygon2D] = []
var _base_color: Color = Color.WHITE
## v0.16.0：基因模式表型；旧模式保持 1.0/-1，渲染结果与 v0.15.0 一致。
var _radius_scale: float = 1.0
var _color_override: Color = Color(-1.0, -1.0, -1.0, 1.0)

func _ready() -> void:
	if organelle_root != null:
		for child in organelle_root.get_children():
			var organelle: Polygon2D = child as Polygon2D
			if organelle != null:
				_organelles.append(organelle)

func apply_cell(
	position: Vector2,
	type_id: int,
	org_id: int,
	energy: float,
	velocity: Vector2 = Vector2.ZERO,
	contacts: Array[Vector2] = [],
	adhesions: Array[Vector2] = [],
	wall_contacts: Array[Vector2] = [],
	chords: Array = [],
	radius_scale: float = 1.0,
	color_override: Color = Color(-1.0, -1.0, -1.0, 1.0)
) -> void:
	global_position = position
	_velocity = velocity
	_contacts = contacts.duplicate()
	_adhesions = adhesions.duplicate()
	_wall_contacts = wall_contacts.duplicate()
	_chords = chords.duplicate()
	if type_id != _type_id or org_id != _org_id or absf(radius_scale - _radius_scale) > 0.0001:
		_org_id = org_id
		_radius_scale = clampf(radius_scale, 0.5, 2.0)
		_apply_type(type_id)
	var vitality: float = clampf(energy / 1.2, 0.35, 1.0)
	_color_override = color_override
	if _color_override.r >= 0.0:
		# 基因模式：直接用 Genome 指定的 RGB，不做个体色相偏移。
		_base_color = Color(_color_override.r, _color_override.g, _color_override.b, 1.0)
	else:
		_base_color = CATALOG.call("color", _type_id)
		var org_hue: float = fposmod(float(org_id) * 0.173 + 0.42, 1.0)
		_base_color = _base_color.lerp(Color.from_hsv(org_hue, 0.34, 0.95), 0.16)
	_apply_vitality(vitality)
	_refresh_shape()

func _apply_vitality(vitality: float) -> void:
	var color_value: Color = _base_color
	if body != null:
		body.color = Color(color_value.r, color_value.g, color_value.b, 0.30 * vitality + 0.10)
	if outline != null:
		outline.modulate = Color(
			minf(color_value.r * 1.35, 1.0),
			minf(color_value.g * 1.35, 1.0),
			minf(color_value.b * 1.35, 1.0),
			0.95
		)
	if inner_ring != null:
		inner_ring.modulate = Color(color_value.r, color_value.g, color_value.b, 0.70)
	if nucleus != null:
		nucleus.modulate = Color(0.08, 0.16, 0.15, 0.85 * vitality)
	var accent: Color = CATALOG.call("accent_color", _type_id)
	for organelle in _organelles:
		organelle.modulate = Color(accent.r, accent.g, accent.b, 0.72 * vitality + 0.12)

func _process(delta: float) -> void:
	_accumulated += delta
	if _accumulated < 1.0 / maxf(1.0, shape_fps):
		return
	_shape_time += _accumulated
	_accumulated = 0.0
	_refresh_shape()

func _refresh_shape() -> void:
	if body == null or outline == null:
		return
	# 只保留速度/相位状态供 API 与旧测试读取；外膜不再由呼吸膜生成。
	# Cell Lab 的细胞外形来自物理半径与共享弦，呼吸相位只用于着色。
	var effective_radius: float = visual_radius * _radius_scale
	var velocity_limit: float = maxf(1.0, effective_radius * 0.5)
	var target_stretch: float = clampf(_velocity.length() / velocity_limit, 0.0, 1.0) * max_stretch
	_stretch += (target_stretch - _stretch) * clampf(stretch_smoothing, 0.05, 1.0)
	var segments: int = clampi(outline_segments, 12, 64)
	# 统一基底：所有细胞外膜都是同一套解析圆。
	# 有弦时裁剪，无弦时仅按接触法线浅压平；绝不在呼吸膜与弦膜之间切换点集。
	var unit: PackedVector2Array = CHORDS.call("unit_circle", segments)
	if not _chords.is_empty():
		var unit_chords: Array = CHORDS.call("make_unit_chords", _chords, global_position, 0.0, effective_radius)
		var prepared: Array = CHORDS.call("prepare_for_render", unit_chords)
		var chord_outline: PackedVector2Array = CHORDS.call("clip_unit_circle", prepared, segments)
		if chord_outline.size() >= 3:
			unit = chord_outline
	var world_points: PackedVector2Array = PackedVector2Array()
	var inner_points: PackedVector2Array = PackedVector2Array()
	for point in unit:
		var shaped: Vector2 = point
		if _chords.is_empty():
			# 无弦时保留浅压平，供手动测试/未进入弦派发的视图使用。
			shaped = _flatten_contacts(shaped, _contacts, contact_flatten)
			shaped = _flatten_contacts(shaped, _adhesions, adhesion_flatten)
			shaped = _flatten_contacts(shaped, _wall_contacts, wall_flatten)
		world_points.append(shaped * effective_radius)
		inner_points.append(shaped * effective_radius * 0.62)
	body.polygon = world_points
	outline.points = world_points
	if inner_ring != null:
		inner_ring.points = inner_points

## 接触压平：把接触弧上的顶点投影到一条切平面，形成浅而宽的接触面。
## 旧版按角度缩放半径会得到深 V 形凹口；这里在接触核心区保留平面，边缘用 smoothstep 过渡。
static func _flatten_contacts(
	point: Vector2,
	normals: Array[Vector2],
	depth: float
) -> Vector2:
	var result: Vector2 = point
	for normal in normals:
		result = _flatten_against(result, normal, depth)
	var length_value: float = result.length()
	if length_value < 0.58 and length_value > 0.000001:
		result = result / length_value * 0.58
	return result

static func _flatten_against(point: Vector2, normal: Vector2, depth: float) -> Vector2:
	if normal.length_squared() < 0.5:
		return point
	var n: Vector2 = normal.normalized()
	var projection: float = point.dot(n)
	var edge: float = 0.80
	var core: float = 0.88
	if projection <= edge:
		return point
	var weight: float = _smoothstep(edge, core, projection)
	var plane: float = 1.0 - clampf(depth, 0.0, 0.3)
	var clipped: Vector2 = point - n * maxf(0.0, projection - plane)
	return point.lerp(clipped, weight)

static func _smoothstep(edge_0: float, edge_1: float, value: float) -> float:
	var t: float = clampf((value - edge_0) / maxf(0.0001, edge_1 - edge_0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _apply_type(type_id: int) -> void:
	_type_id = type_id
	_membrane = MEMBRANE.new(MEMBRANE.call("make_signature", _org_id, type_id))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = maxi(1, int(_membrane.get("signature")))
	var accent: Color = CATALOG.call("accent_color", type_id)
	var effective_radius: float = visual_radius * _radius_scale
	for i in range(_organelles.size()):
		var organelle: Polygon2D = _organelles[i]
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(0.22, 0.52)
		organelle.position = Vector2(cos(angle), sin(angle)) * distance * effective_radius
		var size_value: float = rng.randf_range(0.06, 0.12) * effective_radius
		organelle.polygon = _circle_polygon(size_value, 7)
		organelle.color = Color(accent.r, accent.g, accent.b, 0.8)
	if nucleus != null:
		nucleus.polygon = _circle_polygon(effective_radius * 0.15, 10)

static func _circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(3, segments)
	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

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

func get_contact_count() -> int:
	return _contacts.size()

func get_adhesion_count() -> int:
	return _adhesions.size()

func get_wall_contact_count() -> int:
	return _wall_contacts.size()

func get_chord_count() -> int:
	return _chords.size()
