extends RefCounted
## Five-channel deterministic field with GPU compute and CPU fallback.

const CHANNEL_NUTRIENT: int = 0
const CHANNEL_TEMPERATURE: int = 1
const CHANNEL_OXYGEN: int = 2
const CHANNEL_LIGHT: int = 3
const CHANNEL_SIGNAL: int = 4
const CHANNEL_COUNT: int = 5
const DIFFUSION: Array[float] = [0.08, 0.16, 0.12, 0.20, 0.05]
const DECAY: Array[float] = [0.004, 0.002, 0.003, 0.0, 0.02]
const COMPUTE_SOURCE: String = """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) readonly buffer FieldIn { float values[]; } field_in;
layout(set = 0, binding = 1, std430) writeonly buffer FieldOut { float values[]; } field_out;
layout(set = 0, binding = 2, std430) readonly buffer Parameters { float values[]; } params;
layout(set = 0, binding = 3, std430) readonly buffer DishMask { uint values[]; } dish_mask;
layout(set = 0, binding = 4, std430) readonly buffer Sources { float values[]; } sources;
float sample_bilinear(uint channel, vec2 position, uint width, uint height) {
	vec2 bounded = clamp(position, vec2(0.0), vec2(float(width - 1u), float(height - 1u)));
	ivec2 base = ivec2(floor(bounded));
	vec2 fraction = fract(bounded);
	float total = 0.0;
	float weight_total = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			ivec2 point = clamp(base + ivec2(x, y), ivec2(0), ivec2(int(width) - 1, int(height) - 1));
			uint local_index = uint(point.y) * width + uint(point.x);
			if (dish_mask.values[local_index] == 0u) continue;
			float weight = (x == 0 ? 1.0 - fraction.x : fraction.x) * (y == 0 ? 1.0 - fraction.y : fraction.y);
			total += field_in.values[channel * width * height + local_index] * weight;
			weight_total += weight;
		}
	}
	return weight_total > 0.0 ? total / weight_total : 0.0;
}
void main() {
	uint x = gl_GlobalInvocationID.x;
	uint y = gl_GlobalInvocationID.y;
	uint channel = gl_GlobalInvocationID.z;
	uint width = uint(params.values[0]);
	uint height = uint(params.values[1]);
	if (x >= width || y >= height || channel >= 5u) return;
	uint plane = width * height;
	uint local_index = y * width + x;
	uint index = channel * plane + local_index;
	if (dish_mask.values[local_index] == 0u) {
		field_out.values[index] = 0.0;
		return;
	}
	float center = field_in.values[index];
	float laplacian = 0.0;
	if (x > 0u && dish_mask.values[local_index - 1u] != 0u) laplacian += field_in.values[index - 1u] - center;
	if (x + 1u < width && dish_mask.values[local_index + 1u] != 0u) laplacian += field_in.values[index + 1u] - center;
	if (y > 0u && dish_mask.values[local_index - width] != 0u) laplacian += field_in.values[index - width] - center;
	if (y + 1u < height && dish_mask.values[local_index + width] != 0u) laplacian += field_in.values[index + width] - center;
	vec2 velocity = vec2(params.values[12], params.values[13]);
	float advected = sample_bilinear(channel, vec2(float(x), float(y)) - velocity, width, height);
	float source = sources.values[index];
	float diffusion = params.values[2u + channel];
	float decay = params.values[7u + channel];
	field_out.values[index] = max(0.0, advected + diffusion * laplacian - decay * center + source);
}
"""

var resolution: int = 32
var center: Vector2 = Vector2.ZERO
var radius: float = 512.0
var channels: Array[PackedFloat32Array] = []
var dish_mask: PackedByteArray = PackedByteArray()
## 可编辑地形固体层（阶段5）：1=固体阻挡，0=可通行。独立于圆形 dish_mask。
var terrain_mask: PackedByteArray = PackedByteArray()
var advection: Vector2 = Vector2.ZERO
var _pending_sources: Array[PackedFloat32Array] = []
var backend_name: String = "cpu"
var device_name: String = ""
var device_vendor: String = ""
var _rendering_device: RenderingDevice = null
var _shader: RID
var _pipeline: RID
var _buffers: Array[RID] = []
var _uniform_sets: Array[RID] = []
var _parameter_buffer: RID
var _mask_buffer: RID
var _source_buffer: RID
var _active_buffer: int = 0
var _force_cpu: bool = false

func configure(grid_resolution: int, dish_center: Vector2, dish_radius: float, defaults: PackedFloat32Array, prefer_compute: bool = true) -> bool:
	if grid_resolution < 2 or dish_radius <= 0.0 or defaults.size() != CHANNEL_COUNT:
		return false
	_free_gpu_resources()
	resolution = grid_resolution
	center = dish_center
	radius = dish_radius
	_force_cpu = not prefer_compute
	channels.clear()
	dish_mask.resize(resolution * resolution)
	terrain_mask.resize(resolution * resolution)
	for y in range(resolution):
		for x in range(resolution):
			var local_position: Vector2 = Vector2((float(x) + 0.5) / resolution * 2.0 - 1.0, (float(y) + 0.5) / resolution * 2.0 - 1.0)
			var index: int = y * resolution + x
			dish_mask[index] = 1 if local_position.length_squared() <= 1.0 else 0
			terrain_mask[index] = 0
	for channel_index in range(CHANNEL_COUNT):
		var values: PackedFloat32Array = PackedFloat32Array()
		values.resize(resolution * resolution)
		for index in range(values.size()):
			values[index] = defaults[channel_index] if _is_active(index) else 0.0
		channels.append(values)
	_pending_sources.clear()
	for channel_index in range(CHANNEL_COUNT):
		var source: PackedFloat32Array = PackedFloat32Array()
		source.resize(resolution * resolution)
		source.fill(0.0)
		_pending_sources.append(source)
	_active_buffer = 0
	_select_backend()
	return true

## 有效格：位于圆形皿内且未被地形固体阻挡。
func _is_active(index: int) -> bool:
	if index < 0 or index >= dish_mask.size():
		return false
	if dish_mask[index] == 0:
		return false
	if terrain_mask.size() == dish_mask.size() and terrain_mask[index] != 0:
		return false
	return true

## 地形笔刷：以 grid 坐标为中心、radius 为格半径写入固体层。solid=true 绘制，false 擦除。
## 返回实际变更的格数。写入后把被固体覆盖的格浓度清零，上传 GPU mask。
func paint_terrain(grid_x: int, grid_y: int, radius: int, solid: bool) -> int:
	var value: int = 1 if solid else 0
	var changed: int = 0
	for y in range(grid_y - radius, grid_y + radius + 1):
		for x in range(grid_x - radius, grid_x + radius + 1):
			if x < 0 or y < 0 or x >= resolution or y >= resolution:
				continue
			var dx: float = float(x - grid_x)
			var dy: float = float(y - grid_y)
			if dx * dx + dy * dy > float(radius * radius):
				continue
			var index: int = y * resolution + x
			if dish_mask[index] == 0:
				continue
			if terrain_mask[index] == value:
				continue
			terrain_mask[index] = value
			changed += 1
			if solid:
				for channel_index in range(CHANNEL_COUNT):
					channels[channel_index][index] = 0.0
	if changed > 0:
		_upload_mask_buffer()
		_upload_active_buffer()
	return changed

func get_terrain_solid_count() -> int:
	var count: int = 0
	for value in terrain_mask:
		count += int(value)
	return count

func _upload_mask_buffer() -> bool:
	if _rendering_device == null or not _mask_buffer.is_valid():
		return false
	var bytes: PackedByteArray = _pack_mask()
	return _rendering_device.buffer_update(_mask_buffer, 0, bytes.size(), bytes) == OK

func set_value(channel_index: int, x: int, y: int, value: float) -> bool:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or x < 0 or y < 0 or x >= resolution or y >= resolution or not is_finite(value):
		return false
	var index: int = y * resolution + x
	channels[channel_index][index] = value if _is_active(index) else 0.0
	return _upload_active_buffer()

func set_advection(velocity_cells_per_tick: Vector2) -> bool:
	if not is_finite(velocity_cells_per_tick.x) or not is_finite(velocity_cells_per_tick.y):
		return false
	advection = velocity_cells_per_tick
	if _parameter_buffer.is_valid() and _rendering_device != null:
		var bytes: PackedByteArray = _pack_parameters()
		return _rendering_device.buffer_update(_parameter_buffer, 0, bytes.size(), bytes) == OK
	return true

func add_source(channel_index: int, x: int, y: int, amount: float) -> bool:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or x < 0 or y < 0 or x >= resolution or y >= resolution or not is_finite(amount):
		return false
	var index: int = y * resolution + x
	if not _is_active(index):
		return false
	_pending_sources[channel_index][index] += amount
	return true

func sample(position: Vector2) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(CHANNEL_COUNT)
	if channels.size() != CHANNEL_COUNT or not _is_inside(position):
		return result
	var index: int = _cell_index(position)
	for channel_index in range(CHANNEL_COUNT):
		result[channel_index] = channels[channel_index][index]
	return result

func _read_gpu_state() -> void:
	if backend_name == "gpu_compute" and _rendering_device != null and _buffers.size() == 2:
		_read_active_buffer(_active_buffer)

func consume_nutrient(position: Vector2, requested: float) -> float:
	return consume(CHANNEL_NUTRIENT, position, requested)

func consume(channel_index: int, position: Vector2, requested: float) -> float:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or requested <= 0.0 or not is_finite(requested) or channels.size() != CHANNEL_COUNT or not _is_inside(position):
		return 0.0
	var index: int = _cell_index(position)
	var available: float = maxf(0.0, channels[channel_index][index])
	var consumed: float = minf(available, requested)
	channels[channel_index][index] = available - consumed
	_upload_active_buffer()
	return consumed

func get_total_nutrient() -> float:
	if channels.size() != CHANNEL_COUNT:
		return 0.0
	var total: float = 0.0
	for value in channels[CHANNEL_NUTRIENT]:
		total += value
	return total

func get_state_snapshot() -> Array[PackedFloat32Array]:
	_read_gpu_state()
	var snapshot: Array[PackedFloat32Array] = []
	for channel in channels:
		snapshot.append(channel.duplicate())
	return snapshot

func get_state_hash() -> int:
	var hash_value: int = 0x811c9dc5
	for channel_index in range(channels.size()):
		hash_value = _hash_int(hash_value, channel_index)
		for value in channels[channel_index]:
			hash_value = _hash_int(hash_value, int(round(value * 1000000.0)))
	return hash_value

func _hash_int(hash_value: int, value: int) -> int:
	var result: int = hash_value
	for shift in [0, 8, 16, 24]:
		result = int((result ^ ((value >> shift) & 255)) * 0x01000193) & 0xffffffff
	return result

func diffuse_tick(source_additions: Array[PackedFloat32Array] = []) -> bool:
	if channels.size() != CHANNEL_COUNT:
		return false
	if not source_additions.is_empty() and source_additions.size() != CHANNEL_COUNT:
		return false
	if not source_additions.is_empty():
		for channel_index in range(CHANNEL_COUNT):
			if source_additions[channel_index].size() != resolution * resolution:
				return false
	for channel_index in range(CHANNEL_COUNT):
		for index in range(_pending_sources[channel_index].size()):
			_pending_sources[channel_index][index] += source_additions[channel_index][index] if not source_additions.is_empty() else 0.0
	if backend_name == "gpu_compute":
		if not _upload_tick_buffers() or not _dispatch_gpu():
			backend_name = "cpu"
			_free_gpu_resources()
			_apply_cpu_diffusion(_pending_sources)
		else:
			_read_active_buffer(1 - _active_buffer)
			_active_buffer = 1 - _active_buffer
	else:
		_apply_cpu_diffusion(_pending_sources)
	for source in _pending_sources:
		source.fill(0.0)
	return true

func get_backend_diagnostics() -> Dictionary:
	return {"backend": backend_name, "compute_available": _rendering_device != null and _pipeline.is_valid(), "device": device_name, "vendor": device_vendor}

func _select_backend() -> void:
	backend_name = "cpu"
	device_name = ""
	device_vendor = ""
	if _force_cpu:
		return
	_rendering_device = RenderingServer.create_local_rendering_device()
	if _rendering_device == null:
		_rendering_device = RenderingServer.get_rendering_device()
	if _rendering_device == null:
		return
	device_name = _rendering_device.get_device_name()
	device_vendor = _rendering_device.get_device_vendor_name()
	var source: RDShaderSource = RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = COMPUTE_SOURCE
	var spirv: RDShaderSPIRV = _rendering_device.shader_compile_spirv_from_source(source)
	if spirv == null or not spirv.compile_error_compute.is_empty():
		_rendering_device = null
		return
	_shader = _rendering_device.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_rendering_device = null
		return
	_pipeline = _rendering_device.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		_free_gpu_resources()
		return
	var initial: PackedByteArray = _pack_channels()
	for buffer_index in range(2):
		_buffers.append(_rendering_device.storage_buffer_create(initial.size(), initial))
		if not _buffers[buffer_index].is_valid():
			_free_gpu_resources()
			return
	var parameter_bytes: PackedByteArray = _pack_parameters()
	_parameter_buffer = _rendering_device.storage_buffer_create(parameter_bytes.size(), parameter_bytes)
	if not _parameter_buffer.is_valid():
		_free_gpu_resources()
		return
	_mask_buffer = _rendering_device.storage_buffer_create(dish_mask.size() * 4, _pack_mask())
	_source_buffer = _rendering_device.storage_buffer_create(initial.size(), initial)
	if not _mask_buffer.is_valid() or not _source_buffer.is_valid():
		_free_gpu_resources()
		return
	for buffer_index in range(2):
		var uniforms: Array[RDUniform] = []
		uniforms.append(_make_storage_uniform(0, _buffers[buffer_index]))
		uniforms.append(_make_storage_uniform(1, _buffers[1 - buffer_index]))
		uniforms.append(_make_storage_uniform(2, _parameter_buffer))
		uniforms.append(_make_storage_uniform(3, _mask_buffer))
		uniforms.append(_make_storage_uniform(4, _source_buffer))
		var uniform_set: RID = _rendering_device.uniform_set_create(uniforms, _shader, 0)
		if not uniform_set.is_valid():
			_free_gpu_resources()
			return
		_uniform_sets.append(uniform_set)
	backend_name = "gpu_compute"

func _upload_tick_buffers() -> bool:
	if not _upload_active_buffer():
		return false
	var parameters: PackedByteArray = _pack_parameters()
	var sources: PackedByteArray = _pack_channels(_pending_sources)
	return _rendering_device.buffer_update(_parameter_buffer, 0, parameters.size(), parameters) == OK and _rendering_device.buffer_update(_source_buffer, 0, sources.size(), sources) == OK

func _dispatch_gpu() -> bool:
	var list: int = _rendering_device.compute_list_begin()
	if list < 0:
		return false
	_rendering_device.compute_list_bind_compute_pipeline(list, _pipeline)
	_rendering_device.compute_list_bind_uniform_set(list, _uniform_sets[_active_buffer], 0)
	_rendering_device.compute_list_dispatch(list, ceili(float(resolution) / 8.0), ceili(float(resolution) / 8.0), CHANNEL_COUNT)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	return true

func _apply_cpu_diffusion(source_additions: Array[PackedFloat32Array] = []) -> void:
	var next_channels: Array[PackedFloat32Array] = []
	for channel_index in range(CHANNEL_COUNT):
		var next_values: PackedFloat32Array = PackedFloat32Array()
		next_values.resize(resolution * resolution)
		var source: PackedFloat32Array = source_additions[channel_index] if source_additions.size() == CHANNEL_COUNT else PackedFloat32Array()
		for y in range(resolution):
			for x in range(resolution):
				var index: int = y * resolution + x
				if not _is_active(index):
					next_values[index] = 0.0
					continue
				var center_value: float = channels[channel_index][index]
				var laplacian: float = 0.0
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx < 0 or ny < 0 or nx >= resolution or ny >= resolution:
						continue
					var neighbor_index: int = ny * resolution + nx
					if _is_active(neighbor_index):
						laplacian += channels[channel_index][neighbor_index] - center_value
				var advected: float = _sample_grid(channel_index, Vector2(x, y) - advection)
				var source_value: float = source[index] if source.size() == resolution * resolution else 0.0
				next_values[index] = maxf(0.0, advected + DIFFUSION[channel_index] * laplacian - DECAY[channel_index] * center_value + source_value)
		next_channels.append(next_values)
	channels = next_channels
	_upload_active_buffer()

func _sample_grid(channel_index: int, grid_position: Vector2) -> float:
	var bounded: Vector2 = grid_position.clamp(Vector2.ZERO, Vector2.ONE * float(resolution - 1))
	var base_x: int = floori(bounded.x)
	var base_y: int = floori(bounded.y)
	var fraction: Vector2 = bounded - Vector2(base_x, base_y)
	var weighted_sum: float = 0.0
	var weight_total: float = 0.0
	for offset_y in range(2):
		for offset_x in range(2):
			var x: int = mini(base_x + offset_x, resolution - 1)
			var y: int = mini(base_y + offset_y, resolution - 1)
			var index: int = y * resolution + x
			if not _is_active(index):
				continue
			var weight: float = (1.0 - fraction.x if offset_x == 0 else fraction.x) * (1.0 - fraction.y if offset_y == 0 else fraction.y)
			weighted_sum += channels[channel_index][index] * weight
			weight_total += weight
	return weighted_sum / weight_total if weight_total > 0.0 else 0.0

func _apply_source_additions(source_additions: Array[PackedFloat32Array]) -> void:
	if source_additions.size() != CHANNEL_COUNT:
		return
	for channel_index in range(CHANNEL_COUNT):
		if source_additions[channel_index].size() != channels[channel_index].size():
			continue
		for index in range(channels[channel_index].size()):
			channels[channel_index][index] = maxf(0.0, channels[channel_index][index] + source_additions[channel_index][index])

func _upload_active_buffer() -> bool:
	if _rendering_device == null or _buffers.size() != 2:
		return false
	var bytes: PackedByteArray = _pack_channels()
	return _rendering_device.buffer_update(_buffers[_active_buffer], 0, bytes.size(), bytes) == OK

func _read_active_buffer(buffer_index: int) -> void:
	var bytes: PackedByteArray = _rendering_device.buffer_get_data(_buffers[buffer_index])
	var cursor: int = 0
	for channel_index in range(CHANNEL_COUNT):
		for index in range(channels[channel_index].size()):
			channels[channel_index][index] = bytes.decode_float(cursor)
			cursor += 4

func _pack_channels(source_channels: Array[PackedFloat32Array] = []) -> PackedByteArray:
	var values: Array[PackedFloat32Array] = source_channels if source_channels.size() == CHANNEL_COUNT else channels
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(resolution * resolution * CHANNEL_COUNT * 4)
	var cursor: int = 0
	for channel in values:
		for value in channel:
			bytes.encode_float(cursor, value)
			cursor += 4
	return bytes

func _pack_mask() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(dish_mask.size() * 4)
	for index in range(dish_mask.size()):
		var active: bool = _is_active(index)
		bytes.encode_u32(index * 4, 1 if active else 0)
	return bytes

func _pack_parameters() -> PackedByteArray:
	var values: PackedFloat32Array = PackedFloat32Array([float(resolution), float(resolution)])
	for value in DIFFUSION:
		values.append(value)
	for value in DECAY:
		values.append(value)
	values.append(advection.x)
	values.append(advection.y)
	return values.to_byte_array()

func _make_storage_uniform(binding_index: int, buffer_rid: RID) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding_index
	uniform.add_id(buffer_rid)
	return uniform

func _free_gpu_resources() -> void:
	if _rendering_device == null:
		return
	for uniform_set in _uniform_sets:
		if uniform_set.is_valid():
			_rendering_device.free_rid(uniform_set)
	_uniform_sets.clear()
	for buffer_rid in _buffers:
		if buffer_rid.is_valid():
			_rendering_device.free_rid(buffer_rid)
	_buffers.clear()
	if _parameter_buffer.is_valid():
		_rendering_device.free_rid(_parameter_buffer)
		_parameter_buffer = RID()
	if _mask_buffer.is_valid():
		_rendering_device.free_rid(_mask_buffer)
		_mask_buffer = RID()
	if _source_buffer.is_valid():
		_rendering_device.free_rid(_source_buffer)
		_source_buffer = RID()
	if _pipeline.is_valid():
		_rendering_device.free_rid(_pipeline)
		_pipeline = RID()
	if _shader.is_valid():
		_rendering_device.free_rid(_shader)
		_shader = RID()

func get_grid_position(position: Vector2) -> Vector2i:
	var normalized: Vector2 = (position - (center - Vector2.ONE * radius)) / (2.0 * radius)
	var x: int = clampi(int(floor(normalized.x * resolution)), 0, resolution - 1)
	var y: int = clampi(int(floor(normalized.y * resolution)), 0, resolution - 1)
	return Vector2i(x, y)

func _cell_index(position: Vector2) -> int:
	var grid_position: Vector2i = get_grid_position(position)
	return grid_position.y * resolution + grid_position.x

func _is_inside(position: Vector2) -> bool:
	return position.distance_squared_to(center) <= radius * radius
