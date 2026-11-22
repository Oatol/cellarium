extends Node2D
## v0.30.0 大规模批渲染：单个 CanvasItem 批量提交细胞多边形，取代 >512 细胞时的
## MultiMesh 纯色块 LOD。共享弦与近景 CellView 同源，接触处仍切平膜；只读 SoA，
## 不写模拟状态、不参与 hash。细胞器/内膜在大规模档省略（Cell Lab 式 LOD）。

const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const CHORDS: RefCounted = preload("res://scripts/rendering/CellContactChords.gd")
const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const CELL_PHYSICS: RefCounted = preload("res://scripts/system/CellPhysics.gd")
const CELL_SCENE_RENDERER: RefCounted = preload("res://scripts/rendering/CellSceneRenderer.gd")
const FrameProfiler: RefCounted = preload("res://scripts/system/FrameProfiler.gd")

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export_range(12, 32, 1) var outline_segments: int = 12
@export var max_cells: int = 8000
## C 路线 A/B 开关：false 回到逐细胞 draw_* 旧路径，用于真实窗口同场景对照。
@export var use_triangle_batch: bool = true

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var _polygons: Array = []
var _outlines: Array = []
var _centers: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _body_colors: PackedColorArray = PackedColorArray()
var _outline_colors: PackedColorArray = PackedColorArray()
var _nucleus_colors: PackedColorArray = PackedColorArray()
var _links: PackedVector2Array = PackedVector2Array()
## v0.39 C 路线：把逐细胞 draw_* 合并为 3 次 CanvasItem 提交。
## 真实窗口 1324 细胞：逐细胞路径 4231 draw calls，合批后目标降到个位数。
var _batch_vertices: PackedVector2Array = PackedVector2Array()
var _batch_colors: PackedColorArray = PackedColorArray()
var _batch_indices: PackedInt32Array = PackedInt32Array()
var _dirty: bool = true
var _active_count: int = 0
var _last_chord_count: int = 0
var _native_render_cache: RefCounted = null
var _native_render_cache_checked: bool = false

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
	_rebuild_cache()
	_dirty = false
	queue_redraw()

func _process(_delta: float) -> void:
	if not _dirty:
		return
	FrameProfiler.poly_begin()
	_rebuild_cache()
	FrameProfiler.poly_end()
	_dirty = false
	queue_redraw()

func _on_tick_advanced(_tick_index: int) -> void:
	mark_dirty()

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true

func get_active_count() -> int:
	return _active_count

func get_polygon_count() -> int:
	return _polygons.size()

func get_chord_count() -> int:
	return _last_chord_count

func _draw() -> void:
	# v0.39 C 路线：所有几何（链接、细胞体、核、膜）已展开为三角面，
	# 用 RenderingServer 直提三角数组，一次提交替代每细胞 3 次 draw_*。
	if use_triangle_batch and _batch_vertices.size() >= 3 and _batch_indices.size() == _batch_vertices.size():
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _batch_indices, _batch_vertices, _batch_colors
		)
		return
	# 兜底：缓存尚未构建时保持旧行为，避免首帧空白。
	for link_index in range(0, _links.size(), 2):
		draw_line(_links[link_index], _links[link_index + 1], Color(0.58, 0.82, 0.72, 0.42), 2.0)
	for cell_index in range(_polygons.size()):
		draw_colored_polygon(_polygons[cell_index], _body_colors[cell_index])
		draw_polyline(_outlines[cell_index], _outline_colors[cell_index], 1.0)
		draw_circle(_centers[cell_index], maxf(1.0, _radii[cell_index] * 0.15), _nucleus_colors[cell_index])

func _build_batched_commands() -> void:
	## 只读派生视图数据：细胞体/核拆成三角扇，膜与连接线拆成细四边形，
	## 全部塞进一个 PackedVector2Array/PackedColorArray，用一次 draw_polygon 提交。
	_batch_vertices = PackedVector2Array()
	_batch_colors = PackedColorArray()
	_batch_indices = PackedInt32Array()
	var count: int = mini(_polygons.size(), mini(_body_colors.size(),
		mini(_outlines.size(), mini(_centers.size(),
		mini(_radii.size(), mini(_outline_colors.size(), _nucleus_colors.size()))))))
	var nucleus_unit: PackedVector2Array = CHORDS.call("unit_circle", 8) as PackedVector2Array
	for cell_index in range(count):
		var polygon: PackedVector2Array = _polygons[cell_index] as PackedVector2Array
		if polygon.size() < 3:
			continue
		var body_color: Color = _body_colors[cell_index]
		var origin: Vector2 = polygon[0]
		for point_index in range(1, polygon.size() - 1):
			_append_triangle(origin, polygon[point_index], polygon[point_index + 1], body_color)
		var outline: PackedVector2Array = _outlines[cell_index] as PackedVector2Array
		var outline_color: Color = _outline_colors[cell_index]
		for point_index in range(outline.size()):
			_append_segment(outline[point_index], outline[(point_index + 1) % outline.size()], outline_color, 1.0)
		var nucleus_radius: float = maxf(1.0, _radii[cell_index] * 0.15)
		var nucleus_center: Vector2 = _centers[cell_index]
		var nucleus_color: Color = _nucleus_colors[cell_index]
		for point_index in range(nucleus_unit.size()):
			_append_triangle(
				nucleus_center,
				nucleus_center + nucleus_unit[point_index] * nucleus_radius,
				nucleus_center + nucleus_unit[(point_index + 1) % nucleus_unit.size()] * nucleus_radius,
				nucleus_color
			)
	var link_color: Color = Color(0.58, 0.82, 0.72, 0.42)
	for link_index in range(0, _links.size(), 2):
		_append_segment(_links[link_index], _links[link_index + 1], link_color, 2.0)
	_batch_indices.resize(_batch_vertices.size())
	for vertex_index in range(_batch_vertices.size()):
		_batch_indices[vertex_index] = vertex_index

func _append_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_batch_vertices.append(a)
	_batch_vertices.append(b)
	_batch_vertices.append(c)
	_batch_colors.append(color)
	_batch_colors.append(color)
	_batch_colors.append(color)

func _append_segment(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var delta: Vector2 = b - a
	var length_squared: float = delta.length_squared()
	if length_squared < 0.000001:
		return
	var normal: Vector2 = Vector2(-delta.y, delta.x) / sqrt(length_squared) * (width * 0.5)
	var p0: Vector2 = a + normal
	var p1: Vector2 = a - normal
	var p2: Vector2 = b - normal
	var p3: Vector2 = b + normal
	_append_triangle(p0, p1, p2, color)
	_append_triangle(p0, p2, p3, color)

func _rebuild_cache() -> void:
	var native_cache: RefCounted = _get_native_render_cache()
	if native_cache != null:
		if _rebuild_cache_native(native_cache):
			return
	_rebuild_cache_gdscript()

func _get_native_render_cache() -> RefCounted:
	if not _native_render_cache_checked:
		_native_render_cache_checked = true
		if ClassDB.class_exists("CellRenderCache"):
			_native_render_cache = ClassDB.instantiate("CellRenderCache") as RefCounted
	return _native_render_cache

func _rebuild_cache_native(native_cache: RefCounted) -> bool:
	if organism_manager == null:
		return false
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return false
	var radius: float = SHAPE.REST_RADIUS
	var radius_value: Variant = organism_manager.get("cell_radius")
	if radius_value != null:
		radius = maxf(1.0, float(radius_value))
	var dish_center: Vector2 = Vector2(250.0, 250.0)
	var dish_radius: float = 240.0
	var center_value: Variant = organism_manager.get("dish_center")
	if center_value != null:
		dish_center = center_value
	var dish_radius_value: Variant = organism_manager.get("dish_radius")
	if dish_radius_value != null:
		dish_radius = maxf(1.0, float(dish_radius_value))
	var cell_size: float = float(CELL_PHYSICS.get_script_constant_map().get("SPATIAL_HASH_CELL_SIZE", 64.0))
	var result: Dictionary = native_cache.call("rebuild",
		cells.get("cell_alive"), cells.get("cell_pos_x"), cells.get("cell_pos_y"),
		cells.get("cell_radius_scale"), cells.get("cell_type"), cells.get("cell_org_id"),
		cells.get("cell_color_r"), cells.get("cell_color_g"), cells.get("cell_color_b"),
		cells.get("cell_energy"), cells.get("link_cell_a"), cells.get("link_cell_b"),
		radius, dish_center.x, dish_center.y, dish_radius, cell_size,
		clampi(outline_segments, 12, 48), max_cells) as Dictionary
	if result.is_empty() or not result.has("polygons"):
		return false
	_polygons = result["polygons"]
	_outlines = result["outlines"]
	_centers = result["centers"]
	_radii = result["radii"]
	_body_colors = result["body_colors"]
	_outline_colors = result["outline_colors"]
	_nucleus_colors = result["nucleus_colors"]
	_links = result["links"]
	_active_count = int(result.get("active_count", 0))
	_last_chord_count = int(result.get("chord_count", 0))
	_build_batched_commands()
	return true

func _rebuild_cache_gdscript() -> void:
	_batch_vertices = PackedVector2Array()
	_batch_colors = PackedColorArray()
	_batch_indices = PackedInt32Array()
	_polygons.clear()
	_outlines.clear()
	_centers.clear()
	_radii.clear()
	_body_colors.clear()
	_outline_colors.clear()
	_nucleus_colors.clear()
	_links = PackedVector2Array()
	_active_count = 0
	_last_chord_count = 0
	if organism_manager == null:
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		return
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var types: PackedByteArray = cells.get("cell_type")
	var radius_scales: PackedFloat32Array = cells.get("cell_radius_scale")
	var color_r: PackedFloat32Array = cells.get("cell_color_r")
	var color_g: PackedFloat32Array = cells.get("cell_color_g")
	var color_b: PackedFloat32Array = cells.get("cell_color_b")
	var radius: float = SHAPE.REST_RADIUS
	var radius_value: Variant = organism_manager.get("cell_radius")
	if radius_value != null:
		radius = maxf(1.0, float(radius_value))
	var dish_center: Vector2 = Vector2(250.0, 250.0)
	var dish_radius: float = 240.0
	var center_value: Variant = organism_manager.get("dish_center")
	if center_value != null:
		dish_center = center_value
	var dish_radius_value: Variant = organism_manager.get("dish_radius")
	if dish_radius_value != null:
		dish_radius = maxf(1.0, float(dish_radius_value))
	var indices: Array[int] = []
	for cell_index in range(mini(alive.size(), max_cells)):
		if alive[cell_index] != 0:
			indices.append(cell_index)
	if indices.is_empty():
		return
	_active_count = indices.size()
	for link_index in range(link_a.size()):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= alive.size() or b >= alive.size():
			continue
		if alive[a] == 0 or alive[b] == 0:
			continue
		_links.append(Vector2(pos_x[a], pos_y[a]))
		_links.append(Vector2(pos_x[b], pos_y[b]))
	var buckets: Dictionary = CELL_PHYSICS.call("build_spatial_hash_flat", cells)
	var cell_size: float = float(CELL_PHYSICS.get_script_constant_map().get("SPATIAL_HASH_CELL_SIZE", 64.0))
	var segments: int = clampi(outline_segments, 12, 48)
	var unit_circle: PackedVector2Array = CHORDS.call("unit_circle", segments)
	for cell_index in indices:
		var center: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index])
		var scale_value: float = 1.0
		if cell_index < radius_scales.size():
			scale_value = clampf(float(radius_scales[cell_index]), 0.5, 2.0)
		var effective_radius: float = maxf(1.0, radius * scale_value)
		var unit: PackedVector2Array = unit_circle
		## v0.30.0 大规模 LOD：无 Dictionary 的共享弦。端点仍由同一圆-圆解析式给出，
		## 但直接生成局部归一化端点，最多 8 条；近景 CellBase 仍走完整 A[] 管线。
		var local_a: PackedVector2Array = PackedVector2Array()
		var local_b: PackedVector2Array = PackedVector2Array()
		var cell_x: int = floori(pos_x[cell_index] / cell_size)
		var cell_y: int = floori(pos_y[cell_index] / cell_size)
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var key: int = int(CELL_PHYSICS.call("_flat_key", cell_x + offset_x, cell_y + offset_y))
				if not buckets.has(key):
					continue
				var bucket: PackedInt32Array = buckets[key]
				for neighbor in bucket:
					if neighbor == cell_index or neighbor >= alive.size() or alive[neighbor] == 0:
						continue
					if local_a.size() >= 4:
						continue
					var chord: PackedVector2Array = _circle_chord_local(
						center, effective_radius,
						Vector2(pos_x[neighbor], pos_y[neighbor]), _radius_at(radius, radius_scales, neighbor)
					)
					if chord.size() == 2:
						local_a.append(chord[0])
						local_b.append(chord[1])
		var wall: PackedVector2Array = _wall_chord_local(center, effective_radius, dish_center, dish_radius)
		if wall.size() == 2 and local_a.size() < 4:
			local_a.append(wall[0])
			local_b.append(wall[1])
		_last_chord_count += local_a.size()
		for chord_index in range(local_a.size()):
			var clipped: PackedVector2Array = CHORDS.call(
				"clip_keep_origin", unit, local_a[chord_index], local_b[chord_index]
			)
			if clipped.size() >= 3:
				unit = clipped
		var polygon: PackedVector2Array = PackedVector2Array()
		var outline: PackedVector2Array = PackedVector2Array()
		for point in unit:
			var world_point: Vector2 = center + point * effective_radius
			polygon.append(world_point)
			outline.append(world_point)
		if polygon.size() < 3:
			continue
		var type_id: int = 0 if cell_index >= types.size() else int(types[cell_index])
		var org_id: int = 0 if cell_index >= org_ids.size() else int(org_ids[cell_index])
		var energy: float = 0.0 if cell_index >= energies.size() else float(energies[cell_index])
		var vitality: float = clampf(energy / 1.2, 0.35, 1.0)
		var base_color: Color = Color(-1.0, -1.0, -1.0, 1.0)
		if cell_index < color_r.size() and color_index_valid(color_r, color_g, color_b, cell_index):
			base_color = Color(float(color_r[cell_index]), float(color_g[cell_index]), float(color_b[cell_index]), 1.0)
		if base_color.r < 0.0:
			base_color = CATALOG.call("color", type_id)
			var hue: float = fposmod(float(org_id) * 0.173 + 0.42, 1.0)
			base_color = base_color.lerp(Color.from_hsv(hue, 0.34, 0.95), 0.16)
		_polygons.append(polygon)
		_outlines.append(outline)
		_centers.append(center)
		_radii.append(effective_radius)
		_body_colors.append(Color(base_color.r, base_color.g, base_color.b, 0.30 * vitality + 0.10))
		_outline_colors.append(Color(
			minf(base_color.r * 1.35, 1.0), minf(base_color.g * 1.35, 1.0),
			minf(base_color.b * 1.35, 1.0), 0.95
		))
		_nucleus_colors.append(Color(0.08, 0.16, 0.15, 0.85 * vitality))
	_active_count = _polygons.size()
	_build_batched_commands()

static func _radius_at(base_radius: float, scales: PackedFloat32Array, index: int) -> float:
	var scale_value: float = 1.0
	if index >= 0 and index < scales.size():
		scale_value = clampf(float(scales[index]), 0.5, 2.0)
	return maxf(1.0, base_radius * scale_value)

## 与 CellContactChords.circle_chord 同式的局部端点版本；返回空数组表示不相交。
static func _circle_chord_local(p0: Vector2, r0: float, p1: Vector2, r1: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var delta: Vector2 = p1 - p0
	var s: float = delta.length()
	var epsilon: float = maxf(0.02, minf(r0, r1) * 0.01)
	if s < 0.000001 or s >= r0 + r1 - epsilon or s <= absf(r0 - r1) + 0.000001:
		return result
	var direction: Vector2 = delta / s
	var d: float = (s * s - r1 * r1 + r0 * r0) / (2.0 * s)
	var h_squared: float = r0 * r0 - d * d
	if h_squared <= 0.0:
		return result
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var h: float = sqrt(h_squared)
	var middle: Vector2 = direction * d
	result.append((middle - perpendicular * h) / r0)
	result.append((middle + perpendicular * h) / r0)
	return result

## 皿壁大圆内切，返回相对细胞中心、按 r0 归一化的弦端点。
static func _wall_chord_local(p0: Vector2, r0: float, dish_center: Vector2, dish_radius: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var delta: Vector2 = dish_center - p0
	var s: float = delta.length()
	if s < 0.000001 or dish_radius <= r0:
		return result
	if s + r0 <= dish_radius + maxf(0.02, r0 * 0.01):
		return result
	var direction: Vector2 = delta / s
	var d: float = (r0 * r0 - dish_radius * dish_radius + s * s) / (2.0 * s)
	var h_squared: float = r0 * r0 - d * d
	if h_squared <= 0.0:
		return result
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var h: float = sqrt(h_squared)
	var middle: Vector2 = direction * d
	result.append((middle - perpendicular * h) / r0)
	result.append((middle + perpendicular * h) / r0)
	return result

func color_index_valid(r: PackedFloat32Array, g: PackedFloat32Array, b: PackedFloat32Array, index: int) -> bool:
	return index < r.size() and index < g.size() and index < b.size() and float(r[index]) >= 0.0
