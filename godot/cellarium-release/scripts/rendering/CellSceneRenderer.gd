extends Node2D
## 阶段7：近景细胞用可复用 CellBase.tscn 实例渲染（Cell Lab 贴图）。
## 超过 max_instances 时隐藏本层，退回 MultiMesh 色块 LOD（CellBatchRenderer）。
## 只读 SoA；不写模拟状态，不参与确定性 hash。

@export var cell_scene: PackedScene = preload("res://scenes/cells/CellBase.tscn")
@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var batch_renderer_path: NodePath = ^"../CellBatch"
@export var max_instances: int = 512
@export var cell_radius: float = 4.0

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var batch_renderer: CanvasItem = null
var _pool: Array[Node2D] = []
var _active_count: int = 0
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

func _rebuild() -> void:
	if organism_manager == null or cell_scene == null:
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
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
	for i in range(indices.size()):
		var cell_index: int = indices[i]
		var view: Node2D = _pool[i]
		view.visible = true
		var type_id: int = 0 if cell_type.size() <= cell_index else int(cell_type[cell_index])
		var org_id: int = 0 if org_ids.size() <= cell_index else int(org_ids[cell_index])
		var energy: float = 0.0 if energies.size() <= cell_index else float(energies[cell_index])
		view.call("apply_cell", Vector2(pos_x[cell_index], pos_y[cell_index]), type_id, org_id, energy)
	for i in range(indices.size(), _pool.size()):
		_pool[i].visible = false
	_active_count = indices.size()

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
