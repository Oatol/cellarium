extends MultiMeshInstance2D
## 千级规模细胞批量渲染（§5.2 / §8.2 / §8.4）：从 SoA 一次组装 MultiMesh，
## 取代逐细胞 draw_circle。LOD 上限内用确定性 stride 稳定抽样，避免闪烁。
## 不写模拟状态；CPU 回退路径用同一 MultiMesh，视觉不降级。

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var cell_radius: float = 2.0
@export var max_instances: int = 8000

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var _dirty: bool = true

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	if command_bus != null and command_bus.has_signal("command_executed"):
		var on_command: Callable = Callable(self, "_on_command_executed")
		if not command_bus.is_connected("command_executed", on_command):
			command_bus.connect("command_executed", on_command)
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		multimesh.mesh = quad
	_rebuild()

func _process(_delta: float) -> void:
	## 仅在脏标记或 tick 推进时重建；倍速锁帧由 TickCore.render_fps 控制（上层可设 Engine.max_fps）。
	if _dirty:
		_rebuild()
		_dirty = false

func _on_tick_advanced(_tick_index: int) -> void:
	## 细胞位置/存活状态每个 tick 都可能变化，必须重建实例。
	mark_dirty()

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	## 冻结档干预会立即 flush，不等下一 tick，也要立刻刷新可见实例。
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true

func _rebuild() -> void:
	if organism_manager == null or multimesh == null:
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var count: int = alive.size()
	var visible_indices: Array[int] = []
	for cell_index in range(count):
		if alive[cell_index] != 0:
			visible_indices.append(cell_index)
	# LOD 上限：确定性 stride 抽样（不随机，避免闪烁）
	var total_visible: int = visible_indices.size()
	var instance_count: int = mini(total_visible, maxi(1, max_instances))
	if instance_count == 0:
		multimesh.instance_count = 0
		return
	multimesh.instance_count = instance_count
	var stride: float = float(total_visible) / float(instance_count)
	for i in range(instance_count):
		var source_index: int = visible_indices[mini(int(float(i) * stride), total_visible - 1)]
		var position: Vector2 = Vector2(pos_x[source_index], pos_y[source_index])
		var transform: Transform2D = Transform2D(0.0, position)
		transform = transform.scaled(Vector2(cell_radius, cell_radius))
		multimesh.set_instance_transform_2d(i, transform)
		var org_id: int = int(org_ids[source_index])
		var hue: float = fposmod(float(org_id) * 0.173 + 0.42, 1.0)
		multimesh.set_instance_color(i, Color.from_hsv(hue, 0.48, 0.92))

## 按 LOD 等级调整实例上限（宏观档只画色块）。
func apply_lod(lod_level: int) -> void:
	match lod_level:
		0: max_instances = 8000
		1: max_instances = 4000
		2: max_instances = 2000
		3: max_instances = 1000
	mark_dirty()

func get_instance_count() -> int:
	return multimesh.instance_count if multimesh != null else 0
