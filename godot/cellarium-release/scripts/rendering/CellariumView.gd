extends Node2D
## Shared scene view base for CellArray-backed rendering layers.

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"

var organism_manager: Node = null

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)

func _process(_delta: float) -> void:
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
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var hue: float = fposmod(float(org_ids[cell_index]) * 0.173 + 0.42, 1.0)
		var color: Color = Color.from_hsv(hue, 0.48, 0.92)
		var position: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index])
		draw_circle(position, cell_radius, color)
		draw_arc(position, cell_radius, 0.0, TAU, 24, Color("#d5eee7"), 0.35, true)
		draw_circle(position + Vector2(-cell_radius * 0.28, -cell_radius * 0.28), cell_radius * 0.24, Color("#e7fff5", 0.72))

func draw_links_layer() -> void:
	var cells: RefCounted = get_cells()
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	for link_index in range(link_a.size()):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= alive.size() or b >= alive.size() or alive[a] == 0 or alive[b] == 0:
			continue
		draw_line(Vector2(pos_x[a], pos_y[a]), Vector2(pos_x[b], pos_y[b]), Color("#79a89b"), 0.8, true)
