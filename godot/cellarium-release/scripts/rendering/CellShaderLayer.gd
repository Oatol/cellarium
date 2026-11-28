extends MultiMeshInstance2D
## v0.52.0：对齐 Cell Lab 的细胞渲染路径。
##
## Cell Lab 每个对象只往扁平数组写固定 6 个顶点，一次 glDrawArrays 提交，
## 圆/膜/接触弦/细胞器全在 fragment shader 里算 —— 所以细胞数只改变顶点总数，
## 不改变管线，也不需要按数量切换画法。
##
## 这里用同样的结构：MultiMesh 的每个实例就是一个单位 quad（6 顶点），
## 每细胞参数（颜色、最多 8 条接触弦、5 个细胞器偏移）由原生 CellRenderCache
## 排成一张 RGBA32F 参数纹理，shader 用实例自定义数据里的下标去查。
## 弦的几何仍在 C++ 里算（复用同一套空间哈希），但三角展开整段跳过。
##
## 只读 SoA；不写模拟状态，不参与确定性 hash。

const SHADER: Shader = preload("res://shaders/cell_membrane.gdshader")
const CELL_PHYSICS: RefCounted = preload("res://scripts/system/CellPhysics.gd")
const SHAPE: RefCounted = preload("res://scripts/core/data/CellShape.gd")
const FrameProfiler: RefCounted = preload("res://scripts/system/FrameProfiler.gd")

## 必须与 shaders/cell_membrane.gdshader 的 PARAM_TEXELS 一致。
const PARAM_TEXELS: int = 16
## 纹理与实例缓冲按这个粒度扩容，避免细胞数抖动时每帧重建 GPU 资源。
const CAPACITY_STEP: int = 256
const OUTLINE_SEGMENTS: int = 12

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var max_cells: int = 8000

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null

var _native_cache: RefCounted = null
var _material: ShaderMaterial = null
var _texture: ImageTexture = null
var _image: Image = null
var _capacity: int = 0
var _tex_width: int = 0
var _active_count: int = 0
var _dirty: bool = true

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material

	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2.ONE
	var built: MultiMesh = MultiMesh.new()
	built.transform_format = MultiMesh.TRANSFORM_2D
	built.use_colors = false
	built.use_custom_data = true
	built.mesh = mesh
	multimesh = built
	_ensure_capacity(CAPACITY_STEP)

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
	FrameProfiler.poly_begin()
	_rebuild()
	FrameProfiler.poly_end()
	_dirty = false

func _on_tick_advanced(_tick_index: int) -> void:
	mark_dirty()

func _on_command_executed(_command: Dictionary, _tick_index: int) -> void:
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true

func get_active_count() -> int:
	return _active_count

## 原生 CellRenderCache 只在 C++ 扩展可用时存在；缺失时本层保持空，
## 由 CellSceneRenderer 回退到 CellBatchPoly。
func _get_native_cache() -> RefCounted:
	if _native_cache == null and ClassDB.class_exists("CellRenderCache"):
		_native_cache = ClassDB.instantiate("CellRenderCache") as RefCounted
	return _native_cache

func _ensure_capacity(cells: int) -> void:
	var wanted: int = maxi(CAPACITY_STEP, ceili(float(maxi(cells, 1)) / float(CAPACITY_STEP)) * CAPACITY_STEP)
	if wanted <= _capacity:
		return
	_capacity = wanted
	_tex_width = _capacity * PARAM_TEXELS
	_image = Image.create(_tex_width, 1, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("cell_params", _texture)
	_material.set_shader_parameter("tex_width", float(_tex_width))
	# instance_count 会重建缓冲，只在扩容时设置；实际绘制数量用 visible_instance_count 控制。
	multimesh.instance_count = _capacity
	multimesh.visible_instance_count = 0

func _rebuild() -> void:
	var native_cache: RefCounted = _get_native_cache()
	if native_cache == null or organism_manager == null:
		multimesh.visible_instance_count = 0
		_active_count = 0
		return
	var cells: RefCounted = organism_manager.get("cells") as RefCounted
	if cells == null:
		multimesh.visible_instance_count = 0
		_active_count = 0
		return
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
	# build_geometry = false：只算弦与颜色，跳过多边形裁剪与三角展开。
	var result: Dictionary = native_cache.call("rebuild",
		cells.get("cell_alive"), cells.get("cell_pos_x"), cells.get("cell_pos_y"),
		cells.get("cell_radius_scale"), cells.get("cell_type"), cells.get("cell_org_id"),
		cells.get("cell_color_r"), cells.get("cell_color_g"), cells.get("cell_color_b"),
		cells.get("cell_energy"), cells.get("link_cell_a"), cells.get("link_cell_b"),
		radius, dish_center.x, dish_center.y, dish_radius, cell_size,
		OUTLINE_SEGMENTS, max_cells, false) as Dictionary
	if result.is_empty() or not result.has("cell_params"):
		multimesh.visible_instance_count = 0
		_active_count = 0
		return
	var count: int = int(result.get("count", 0))
	var centers: PackedVector2Array = result["centers"] as PackedVector2Array
	var radii: PackedFloat32Array = result["radii"] as PackedFloat32Array
	count = mini(count, mini(centers.size(), radii.size()))
	if count <= 0:
		multimesh.visible_instance_count = 0
		_active_count = 0
		return
	_ensure_capacity(count)

	var params: PackedFloat32Array = result["cell_params"] as PackedFloat32Array
	var needed_floats: int = _capacity * PARAM_TEXELS * 4
	if params.size() < needed_floats:
		params.resize(needed_floats)
	_image.set_data(_tex_width, 1, false, Image.FORMAT_RGBAF, params.to_byte_array())
	_texture.update(_image)

	for index in range(count):
		var cell_radius: float = maxf(1.0, float(radii[index]))
		var center: Vector2 = centers[index]
		multimesh.set_instance_transform_2d(index, Transform2D(
			Vector2(cell_radius * 2.0, 0.0), Vector2(0.0, cell_radius * 2.0), center
		))
		multimesh.set_instance_custom_data(index, Color(float(index), 0.0, 0.0, 0.0))
	multimesh.visible_instance_count = count
	_active_count = count
