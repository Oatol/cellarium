extends Node2D
## Shared scene view base for CellArray-backed rendering layers.
## 脏标记：仅在 tick_advanced 推进后重绘，冻结档零重绘；不再每帧 _process 无条件 queue_redraw。

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"

var organism_manager: Node = null
var tick_core: Node = null

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_advanced")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	queue_redraw()

func _on_tick_advanced(_tick_index: int) -> void:
	## 由 tick 驱动重绘，替代每帧 _process 无条件 queue_redraw。
	## Godot 会合并同一帧内的多次 queue_redraw，冻结档（无 tick）零重绘。
	queue_redraw()

func mark_dirty() -> void:
	## 供工具命令、视图控制等即时交互调用（不必等 tick）。
	queue_redraw()

func get_cells() -> RefCounted:
	if organism_manager == null:
		return null
	return organism_manager.get("cells") as RefCounted

func draw_cells_layer(cell_radius: float) -> void:
	var cells: RefCounted = get_cells()
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	## 按 org_id 分桶，减少颜色状态切换；每细胞 2 个实心圆，去掉 24 段弧。
	var buckets: Dictionary = {}
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var org_id: int = int(org_ids[cell_index])
		if not buckets.has(org_id):
			buckets[org_id] = []
		buckets[org_id].append(cell_index)
	for org_id in buckets:
		var hue: float = fposmod(float(org_id) * 0.173 + 0.42, 1.0)
		var fill: Color = Color.from_hsv(hue, 0.48, 0.92)
		var ring: Color = Color.from_hsv(hue, 0.32, 0.78, 0.6)
		var indices: Array = buckets[org_id]
		for cell_index in indices:
			var position: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index])
			draw_circle(position, cell_radius, fill)
			draw_circle(position + Vector2(-cell_radius * 0.28, -cell_radius * 0.28), cell_radius * 0.28, ring)

func draw_links_layer() -> void:
	var cells: RefCounted = get_cells()
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var link_color: Color = Color("#79a89b")
	for link_index in range(link_a.size()):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= alive.size() or b >= alive.size() or alive[a] == 0 or alive[b] == 0:
			continue
		draw_line(Vector2(pos_x[a], pos_y[a]), Vector2(pos_x[b], pos_y[b]), link_color, 0.8, true)
