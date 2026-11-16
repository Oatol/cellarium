extends Node2D
## 单个细胞的可复用视图控制器（阶段7）。外观节点、挂点均在 CellBase.tscn 中声明。
## 只读模拟数据，绝不回写；所有写操作仍走 CommandBus。

const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

@export var cell_radius: float = 4.0

@onready var body: Sprite2D = get_node_or_null("Body") as Sprite2D

var _type_id: int = -1
var _texture_cache: Dictionary = {}

func apply_cell(position: Vector2, type_id: int, org_id: int, energy: float) -> void:
	global_position = position
	if type_id != _type_id:
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

func _apply_type(type_id: int) -> void:
	_type_id = type_id
	if body == null:
		return
	var path: String = CATALOG.call("texture_path", type_id)
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path)
	var texture: Texture2D = _texture_cache[path] as Texture2D
	if texture == null:
		return
	body.texture = texture
	var size: Vector2 = texture.get_size()
	var diameter: float = maxf(1.0, cell_radius * 2.0)
	body.scale = Vector2(diameter / maxf(size.x, 1.0), diameter / maxf(size.y, 1.0))

func get_type_id() -> int:
	return _type_id

func get_type_label() -> String:
	return str(CATALOG.call("label", _type_id))
