extends RefCounted
## Fixed-step cell integration and elastic-link constraints.

const DAMPING: float = 0.98
const CONSTRAINT_ITERATIONS: int = 2
const SPATIAL_HASH_CELL_SIZE: float = 64.0
const SPATIAL_HASH_SOFT_LIMIT: int = 16

static func project_to_dish(cells: RefCounted, center: Vector2, radius: float, normal_damping: float) -> int:
	if cells == null or radius <= 0.0 or normal_damping < 0.0 or normal_damping > 1.0:
		return -1
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var projected: int = 0
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var offset: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index]) - center
		if offset.length_squared() <= radius * radius:
			continue
		var normal: Vector2 = offset.normalized()
		var boundary: Vector2 = center + normal * radius
		var current_position: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index])
		var velocity: Vector2 = current_position - Vector2(prev_x[cell_index], prev_y[cell_index])
		var tangent_velocity: Vector2 = velocity - normal * velocity.dot(normal)
		var reflected_velocity: Vector2 = tangent_velocity - normal * velocity.dot(normal) * normal_damping
		pos_x[cell_index] = boundary.x
		pos_y[cell_index] = boundary.y
		var adjusted_previous: Vector2 = boundary - reflected_velocity
		prev_x[cell_index] = adjusted_previous.x
		prev_y[cell_index] = adjusted_previous.y
		projected += 1
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	return projected

static func resolve_collisions(cells: RefCounted, cell_radius: float) -> int:
	if cells == null or cell_radius <= 0.0:
		return -1
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var pairs: Array[Vector2i] = build_collision_pairs(cells)
	var resolved: int = 0
	for pair in pairs:
		var a: int = pair.x
		var b: int = pair.y
		var delta: Vector2 = Vector2(pos_x[b] - pos_x[a], pos_y[b] - pos_y[a])
		var distance: float = delta.length()
		if distance >= cell_radius * 2.0:
			continue
		var normal: Vector2 = Vector2.RIGHT if distance <= 0.000001 else delta / distance
		var correction: float = (cell_radius * 2.0 - distance) * 0.5
		pos_x[a] -= normal.x * correction
		pos_y[a] -= normal.y * correction
		pos_x[b] += normal.x * correction
		pos_y[b] += normal.y * correction
		resolved += 1
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	return resolved

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

static func query_neighbors(cells: RefCounted, cell_index: int) -> Array[int]:
	var neighbors: Array[int] = []
	if cells == null:
		return neighbors
	var count: int = int(cells.call("size"))
	if cell_index < 0 or cell_index >= count:
		return neighbors
	var alive: PackedByteArray = cells.get("cell_alive")
	if alive[cell_index] == 0:
		return neighbors
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var buckets: Dictionary = _build_spatial_hash(cells)
	var cell_x: int = floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE)
	var cell_y: int = floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var key: Vector2i = Vector2i(cell_x + offset_x, cell_y + offset_y)
			if not buckets.has(key):
				continue
			for sub_bucket in buckets[key]:
				for neighbor_value in sub_bucket:
					var neighbor: int = int(neighbor_value)
					if neighbor != cell_index:
						neighbors.append(neighbor)
	neighbors.sort()
	return neighbors

static func build_collision_pairs(cells: RefCounted) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	if cells == null:
		return pairs
	var count: int = int(cells.call("size"))
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var buckets: Dictionary = _build_spatial_hash(cells)
	for a in range(count):
		if alive[a] == 0:
			continue
		var cell_x: int = floori(float(cells.get("cell_pos_x")[a]) / SPATIAL_HASH_CELL_SIZE)
		var cell_y: int = floori(float(cells.get("cell_pos_y")[a]) / SPATIAL_HASH_CELL_SIZE)
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var key: Vector2i = Vector2i(cell_x + offset_x, cell_y + offset_y)
				if not buckets.has(key):
					continue
				for sub_bucket in buckets[key]:
					for b_value in sub_bucket:
						var b: int = int(b_value)
						if b <= a or org_ids[a] == org_ids[b]:
							continue
						pairs.append(Vector2i(a, b))
	return pairs

static func _build_spatial_hash(cells: RefCounted) -> Dictionary:
	var buckets: Dictionary = {}
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var key: Vector2i = Vector2i(floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE), floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE))
		if not buckets.has(key):
			buckets[key] = [[]]
		var cell_buckets: Array = buckets[key]
		if cell_buckets[cell_buckets.size() - 1].size() >= SPATIAL_HASH_SOFT_LIMIT:
			cell_buckets.append([])
		cell_buckets[cell_buckets.size() - 1].append(cell_index)
		buckets[key] = cell_buckets
	return buckets

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
