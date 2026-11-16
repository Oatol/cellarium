extends Node2D
## 阶段7/8：近景细胞用可复用 CellBase.tscn 实例渲染（程序化膜 + 细胞器）。
## 超过 max_instances 时隐藏本层，退回 MultiMesh 色块 LOD（CellBatchRenderer）。
## 只读 SoA；不写模拟状态，不参与确定性 hash。
## Cell Lab 的接触点 A[] 概念在这里派生为邻域方向，交给 CellView 局部压平膜。

const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const CELL_PHYSICS: RefCounted = preload("res://scripts/system/CellPhysics.gd")

@export var cell_scene: PackedScene = preload("res://scenes/cells/CellBase.tscn")
@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var batch_renderer_path: NodePath = ^"../CellBatch"
@export var max_instances: int = 512

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var batch_renderer: CanvasItem = null
var _pool: Array[Node2D] = []
var _active_count: int = 0
var _last_contacts_sent: int = 0
var _dirty: bool = true

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	batch_renderer = get_node_or_null(batch_renderer_path) as CanvasItem
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	if command_bus != null and command_bus.has_signal("command_executed"):
		var on_command: Callable = Callable(self, "_on_command_executed")
		if not command_bus.is_connected("command_executed", on_command):
			command_bus.connect("command_executed", on_command)
	_rebuild()
	_dirty = false

func _process(_delta: float) -> void:
	if not _dirty:
		return
	_rebuild()
	_dirty = false

func _on_tick_advanced(_tick_index: int) -> void:
	mark_dirty()

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true

func get_active_count() -> int:
	return _active_count

func get_last_contact_count() -> int:
	return _last_contacts_sent

func _rebuild() -> void:
	if organism_manager == null or cell_scene == null:
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var cell_type: PackedByteArray = cells.get("cell_type")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var indices: Array[int] = []
	for cell_index in range(alive.size()):
		if alive[cell_index] != 0:
			indices.append(cell_index)
	if indices.size() > maxi(1, max_instances):
		# 大规模回退到 MultiMesh 色块，避免成百上千个 Control/Node2D 实例。
		_hide_all()
		if batch_renderer != null:
			batch_renderer.visible = true
		return
	if batch_renderer != null:
		batch_renderer.visible = false
	_ensure_pool(indices.size())
	var radius: float = SHAPE.REST_RADIUS
	var radius_value: Variant = organism_manager.get("cell_radius")
	if radius_value != null:
		radius = maxf(1.0, float(radius_value))
	var contact_range: float = radius * 2.0 + 1.0
	var buckets: Dictionary = CELL_PHYSICS.call("build_spatial_hash", cells)
	_last_contacts_sent = 0
	for i in range(indices.size()):
		var cell_index: int = indices[i]
		var view: Node2D = _pool[i]
		view.visible = true
		var type_id: int = 0 if cell_type.size() <= cell_index else int(cell_type[cell_index])
		var org_id: int = 0 if org_ids.size() <= cell_index else int(org_ids[cell_index])
		var energy: float = 0.0 if energies.size() <= cell_index else float(energies[cell_index])
		var velocity: Vector2 = Vector2.ZERO
		if prev_x.size() > cell_index and prev_y.size() > cell_index:
			velocity = Vector2(pos_x[cell_index] - prev_x[cell_index], pos_y[cell_index] - prev_y[cell_index])
		var contacts: Array[Vector2] = _collect_contacts(
			cells, cell_index, buckets, pos_x, pos_y, contact_range
		)
		_last_contacts_sent += contacts.size()
		view.call(
			"apply_cell",
			Vector2(pos_x[cell_index], pos_y[cell_index]),
			type_id,
			org_id,
			energy,
			velocity,
			contacts
		)
	for i in range(indices.size(), _pool.size()):
		_pool[i].visible = false
	_active_count = indices.size()

## 从既有空间哈希派生接触方向，只取最近的 6 个；方向是世界坐标，与 CellView 的旋转后轮廓对齐。
static func _collect_contacts(
	cells: RefCounted,
	cell_index: int,
	buckets: Dictionary,
	pos_x: PackedFloat32Array,
	pos_y: PackedFloat32Array,
	contact_range: float
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if cells == null or buckets.is_empty():
		return result
	var alive: PackedByteArray = cells.get("cell_alive")
	if cell_index < 0 or cell_index >= alive.size() or alive[cell_index] == 0:
		return result
	var candidates: Array[Dictionary] = []
	var neighbors: Array[int] = CELL_PHYSICS.call("query_neighbors_cached", cells, cell_index, buckets)
	var range_squared: float = contact_range * contact_range
	for neighbor in neighbors:
		if neighbor < 0 or neighbor >= alive.size() or alive[neighbor] == 0:
			continue
		var delta: Vector2 = Vector2(
			pos_x[neighbor] - pos_x[cell_index],
			pos_y[neighbor] - pos_y[cell_index]
		)
		var distance_squared: float = delta.length_squared()
		if distance_squared <= 0.000001 or distance_squared > range_squared:
			continue
		candidates.append({"dir": delta.normalized(), "dist": distance_squared})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dist"]) < float(b["dist"])
	)
	for candidate in candidates.slice(0, 6):
		result.append(candidate["dir"])
	return result

func _ensure_pool(wanted: int) -> void:
	while _pool.size() < wanted:
		var view: Node2D = cell_scene.instantiate() as Node2D
		if view == null:
			push_error("CellSceneRenderer: CellBase.tscn instantiate failed")
			return
		add_child(view)
		_pool.append(view)

func _hide_all() -> void:
	for view in _pool:
		view.visible = false
	_active_count = 0
