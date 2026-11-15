extends Node2D
## Renders the dish, live cells and structural links from OrganismManager state.

@export var organism_manager_path: NodePath = ^"../Simulation/OrganismManager"
@export var dish_center: Vector2 = Vector2(250, 250)
@export var dish_radius: float = 240.0
@export var cell_radius: float = 1.0

var organism_manager: Node = null

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_circle(dish_center, dish_radius, Color("#081513"))
	draw_arc(dish_center, dish_radius, 0.0, TAU, 160, Color("#5ce0c0"), 1.5, true)
	if organism_manager == null:
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
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
	for cell_index in range(alive.size()):
		if alive[cell_index] == 0:
			continue
		var hue: float = fposmod(float(org_ids[cell_index]) * 0.173 + 0.42, 1.0)
		var color: Color = Color.from_hsv(hue, 0.48, 0.92)
		draw_circle(Vector2(pos_x[cell_index], pos_y[cell_index]), cell_radius, color)
		draw_arc(Vector2(pos_x[cell_index], pos_y[cell_index]), cell_radius, 0.0, TAU, 24, Color("#d5eee7"), 0.35, true)
