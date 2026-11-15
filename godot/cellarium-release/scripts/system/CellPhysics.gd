extends RefCounted
## Fixed-step cell integration and elastic-link constraints.

const DAMPING: float = 0.98
const CONSTRAINT_ITERATIONS: int = 2

static func step(cells: RefCounted, dt: float) -> void:
	if cells == null or dt <= 0.0:
		return
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	for i in range(count):
		if alive[i] == 0:
			continue
		var x: float = pos_x[i]
		var y: float = pos_y[i]
		var next_x: float = x + (x - prev_x[i]) * DAMPING
		var next_y: float = y + (y - prev_y[i]) * DAMPING
		prev_x[i] = x
		prev_y[i] = y
		pos_x[i] = next_x
		pos_y[i] = next_y
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	_solve_links(cells, count)

static func _solve_links(cells: RefCounted, cell_count: int) -> void:
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var rest_lengths: PackedFloat32Array = cells.get("link_rest_length")
	for iteration in range(CONSTRAINT_ITERATIONS):
		for link_index in range(link_a.size()):
			var a: int = link_a[link_index]
			var b: int = link_b[link_index]
			if a < 0 or b < 0 or a >= cell_count or b >= cell_count or alive[a] == 0 or alive[b] == 0:
				continue
			var dx: float = pos_x[b] - pos_x[a]
			var dy: float = pos_y[b] - pos_y[a]
			var distance: float = sqrt(dx * dx + dy * dy)
			if distance <= 0.000001:
				continue
			var correction: float = (distance - rest_lengths[link_index]) / distance
			var half_correction: float = correction * 0.5
			pos_x[a] += dx * half_correction
			pos_y[a] += dy * half_correction
			pos_x[b] -= dx * half_correction
			pos_y[b] -= dy * half_correction
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
