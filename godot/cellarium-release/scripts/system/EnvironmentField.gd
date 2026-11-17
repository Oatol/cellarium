extends RefCounted
## Five-channel deterministic field with GPU compute and CPU fallback.

const CHANNEL_NUTRIENT: int = 0
const CHANNEL_TEMPERATURE: int = 1
const CHANNEL_OXYGEN: int = 2
const CHANNEL_LIGHT: int = 3
const CHANNEL_SIGNAL: int = 4
const CHANNEL_COUNT: int = 5
const DIFFUSION: Array[float] = [0.08, 0.16, 0.12, 0.0, 0.05]
## 光照是环境照明快照，不参与化学扩散；Macro 的 Environment.q() 也是空间采样而非 PDE。
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

## 阶段10：按细胞采样。CPU sample() 用最近格（_cell_index），shader 必须逐位等价。
const SAMPLE_SOURCE: String = """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) readonly buffer FieldIn { float values[]; } field_in;
layout(set = 0, binding = 1, std430) readonly buffer SampleParams { float values[]; } params;
layout(set = 0, binding = 2, std430) readonly buffer Positions { float values[]; } positions;
layout(set = 0, binding = 3, std430) writeonly buffer Samples { float values[]; } samples;
void main() {
	uint cell_index = gl_GlobalInvocationID.x;
	uint cell_count = uint(params.values[1]);
	if (cell_index >= cell_count) return;
	float resolution = params.values[0];
	vec2 center = vec2(params.values[2], params.values[3]);
	float radius = params.values[4];
	vec2 position = vec2(positions.values[cell_index * 2u], positions.values[cell_index * 2u + 1u]);
	vec2 normalized = (position - (center - vec2(radius))) / (2.0 * radius);
	ivec2 grid = ivec2(clamp(floor(normalized * resolution), vec2(0.0), vec2(resolution - 1.0)));
	uint local_index = uint(grid.y) * uint(resolution) + uint(grid.x);
	uint plane = uint(resolution) * uint(resolution);
	for (uint channel = 0u; channel < 5u; channel++) {
		samples.values[cell_index * 5u + channel] = field_in.values[channel * plane + local_index];
	}
}
"""

## 阶段10：把本 tick 消费量 scatter 回场缓冲；CPU 先按 (格,通道) 聚合，避免写竞争。
const DELTA_SOURCE: String = """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer FieldInOut { float values[]; } field;
layout(set = 0, binding = 1, std430) readonly buffer Deltas { uint values[]; } deltas;
layout(set = 0, binding = 2, std430) readonly buffer DeltaParams { float values[]; } params;
void main() {
	uint entry = gl_GlobalInvocationID.x;
	if (entry >= uint(params.values[1])) return;
	uint local_index = deltas.values[entry * 4u];
	uint channel = deltas.values[entry * 4u + 1u];
	float amount = uintBitsToFloat(deltas.values[entry * 4u + 2u]);
	uint plane = uint(params.values[0]) * uint(params.values[0]);
	uint index = channel * plane + local_index;
	field.values[index] = max(0.0, field.values[index] - amount);
}
"""

const MAX_GPU_SAMPLE_CELLS: int = 4096
const MAX_GPU_DELTA_ENTRIES: int = 8192

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
## GPU 深化：分项计时与回退计数，仅观测，不改变场数值或确定性。
var _gpu_tick_count: int = 0
var _gpu_fallback_count: int = 0
var _gpu_upload_usec: int = 0
var _gpu_dispatch_usec: int = 0
var _gpu_readback_usec: int = 0
## 阶段10：场状态驻留 GPU；CPU 镜像只在显式读写 API / 存档时惰性同步。
var _sample_shader: RID
var _sample_pipeline: RID
var _sample_uniform_sets: Array[RID] = []
var _sample_params_buffer: RID
var _position_buffer: RID
var _samples_buffer: RID
var _delta_shader: RID
var _delta_pipeline: RID
var _delta_uniform_sets: Array[RID] = []
var _delta_params_buffer: RID
var _delta_buffer: RID
var _sample_cache: Dictionary = {}
var _pending_deltas: Dictionary = {}
var _cpu_field_dirty: bool = false
var _gpu_sample_count: int = 0
var _gpu_sample_cells: int = 0
var _gpu_delta_count: int = 0
var _gpu_full_readback_count: int = 0
var _gpu_last_sample_bytes: int = 0

func configure(grid_resolution: int, dish_center: Vector2, dish_radius: float, defaults: PackedFloat32Array, prefer_compute: bool = true) -> bool:
	if grid_resolution < 2 or dish_radius <= 0.0 or defaults.size() != CHANNEL_COUNT:
		return false
	_free_gpu_resources()
	_gpu_tick_count = 0
	_gpu_fallback_count = 0
	_gpu_upload_usec = 0
	_gpu_dispatch_usec = 0
	_gpu_readback_usec = 0
	_gpu_sample_count = 0
	_gpu_sample_cells = 0
	_gpu_delta_count = 0
	_gpu_full_readback_count = 0
	_gpu_last_sample_bytes = 0
	_sample_cache.clear()
	_pending_deltas.clear()
	_cpu_field_dirty = false
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
	if backend_name == "gpu_compute":
		_read_gpu_state()
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
	if backend_name == "gpu_compute":
		_read_gpu_state()
	var index: int = y * resolution + x
	channels[channel_index][index] = value if _is_active(index) else 0.0
	return _upload_active_buffer()

## 阶段11光照落地：整通道填充，只上传一次 GPU 缓冲。
func fill_channel(channel_index: int, value: float) -> bool:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or not is_finite(value) or channels.size() != CHANNEL_COUNT:
		return false
	if backend_name == "gpu_compute":
		_read_gpu_state()
	for index in range(resolution * resolution):
		channels[channel_index][index] = value if _is_active(index) else 0.0
	if backend_name == "gpu_compute":
		_upload_active_buffer()
	return true

## v0.13.0：写入一个完整通道的空间分布（Macro 式光照快照）。
## GPU 后端先回读当前场，避免用过期 CPU 镜像覆盖其他通道；采样缓存随之失效。
func set_channel_values(channel_index: int, values: PackedFloat32Array) -> bool:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or channels.size() != CHANNEL_COUNT:
		return false
	if values.size() != resolution * resolution:
		return false
	if backend_name == "gpu_compute":
		_read_gpu_state()
	for index in range(resolution * resolution):
		if _is_active(index) and is_finite(values[index]):
			channels[channel_index][index] = maxf(0.0, values[index])
		else:
			channels[channel_index][index] = 0.0
	_sample_cache.clear()
	if backend_name == "gpu_compute":
		_upload_active_buffer()
	return true

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
	var zero_result: PackedFloat32Array = PackedFloat32Array()
	zero_result.resize(CHANNEL_COUNT)
	if channels.size() != CHANNEL_COUNT or not _is_inside(position):
		return zero_result
	if backend_name == "gpu_compute" and _sample_pipeline.is_valid():
		if _sample_cache.has(position):
			return (_sample_cache[position] as PackedFloat32Array).duplicate()
		var sampled: Array[PackedFloat32Array] = sample_cells([position])
		if not sampled.is_empty():
			return sampled[0]
	return _sample_cpu(position)

func _sample_cpu(position: Vector2) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(CHANNEL_COUNT)
	var index: int = _cell_index(position)
	for channel_index in range(CHANNEL_COUNT):
		result[channel_index] = channels[channel_index][index]
	return result

## 阶段10：一次 dispatch 采样所有细胞位置，只回读 N×5 个 float（生产默认 N≤数百）。
## 结果按世界坐标缓存，供本 tick 的行为与代谢共用；CPU 回退走同一 _sample_cpu()。
func sample_cells(positions: Array[Vector2]) -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	if positions.is_empty():
		return result
	if backend_name != "gpu_compute" or positions.size() > MAX_GPU_SAMPLE_CELLS or not _sample_pipeline.is_valid():
		for position in positions:
			result.append(_sample_cpu(position))
		return result
	var begin: int = Time.get_ticks_usec()
	var position_bytes: PackedByteArray = PackedByteArray()
	position_bytes.resize(positions.size() * 8)
	for index in range(positions.size()):
		position_bytes.encode_float(index * 8, positions[index].x)
		position_bytes.encode_float(index * 8 + 4, positions[index].y)
	var params: PackedFloat32Array = PackedFloat32Array([float(resolution), float(positions.size()), center.x, center.y, radius])
	if _rendering_device.buffer_update(_position_buffer, 0, position_bytes.size(), position_bytes) != OK:
		return _sample_cells_cpu(positions)
	if _rendering_device.buffer_update(_sample_params_buffer, 0, params.size() * 4, params.to_byte_array()) != OK:
		return _sample_cells_cpu(positions)
	var list: int = _rendering_device.compute_list_begin()
	if list < 0:
		return _sample_cells_cpu(positions)
	_rendering_device.compute_list_bind_compute_pipeline(list, _sample_pipeline)
	_rendering_device.compute_list_bind_uniform_set(list, _sample_uniform_sets[_active_buffer], 0)
	_rendering_device.compute_list_dispatch(list, ceili(float(positions.size()) / 64.0), 1, 1)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	var byte_count: int = positions.size() * CHANNEL_COUNT * 4
	var bytes: PackedByteArray = _rendering_device.buffer_get_data(_samples_buffer, 0, byte_count)
	if bytes.size() < byte_count:
		return _sample_cells_cpu(positions)
	_sample_cache.clear()
	for index in range(positions.size()):
		var values: PackedFloat32Array = PackedFloat32Array()
		values.resize(CHANNEL_COUNT)
		for channel_index in range(CHANNEL_COUNT):
			values[channel_index] = bytes.decode_float(index * CHANNEL_COUNT * 4 + channel_index * 4)
		_sample_cache[positions[index]] = values
		result.append(values)
	_gpu_sample_count += 1
	_gpu_sample_cells += positions.size()
	_gpu_last_sample_bytes = byte_count
	_gpu_readback_usec += maxi(0, Time.get_ticks_usec() - begin)
	return result

func _sample_cells_cpu(positions: Array[Vector2]) -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	for position in positions:
		result.append(_sample_cpu(position))
	return result

func clear_runtime_caches() -> void:
	## 存档恢复后调用：丢弃上一局采样缓存与尚未写入 GPU 的消费增量。
	_sample_cache.clear()
	_pending_deltas.clear()
	_gpu_last_sample_bytes = 0

func _read_gpu_state() -> void:
	if backend_name == "gpu_compute" and _rendering_device != null and _buffers.size() == 2:
		_flush_pending_deltas()
		_read_active_buffer(_active_buffer)

func consume_nutrient(position: Vector2, requested: float) -> float:
	return consume(CHANNEL_NUTRIENT, position, requested)

func consume(channel_index: int, position: Vector2, requested: float) -> float:
	if channel_index < 0 or channel_index >= CHANNEL_COUNT or requested <= 0.0 or not is_finite(requested) or channels.size() != CHANNEL_COUNT or not _is_inside(position):
		return 0.0
	if backend_name == "gpu_compute":
		var sampled: PackedFloat32Array = sample(position)
		if sampled.size() != CHANNEL_COUNT:
			return 0.0
		var gpu_available: float = maxf(0.0, sampled[channel_index])
		var gpu_consumed: float = minf(gpu_available, requested)
		if gpu_consumed > 0.0:
			_queue_delta(_cell_index(position), channel_index, gpu_consumed)
		return gpu_consumed
	var index: int = _cell_index(position)
	var available: float = maxf(0.0, channels[channel_index][index])
	var consumed: float = minf(available, requested)
	channels[channel_index][index] = available - consumed
	_upload_active_buffer()
	return consumed

func _queue_delta(index: int, channel_index: int, amount: float) -> void:
	var key: int = index * CHANNEL_COUNT + channel_index
	_pending_deltas[key] = float(_pending_deltas.get(key, 0.0)) + amount

func _apply_pending_deltas_cpu() -> void:
	for key in _pending_deltas:
		var amount: float = float(_pending_deltas[key])
		var index: int = int(key) / CHANNEL_COUNT
		var channel_index: int = int(key) % CHANNEL_COUNT
		channels[channel_index][index] = maxf(0.0, channels[channel_index][index] - amount)
	_pending_deltas.clear()

func _flush_pending_deltas() -> bool:
	if _pending_deltas.is_empty():
		return true
	if backend_name != "gpu_compute" or not _delta_pipeline.is_valid():
		_apply_pending_deltas_cpu()
		return true
	var keys: Array = _pending_deltas.keys()
	keys.sort()
	var count: int = mini(keys.size(), MAX_GPU_DELTA_ENTRIES)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(MAX_GPU_DELTA_ENTRIES * 16)
	for entry in range(count):
		var key: int = int(keys[entry])
		bytes.encode_u32(entry * 16, key / CHANNEL_COUNT)
		bytes.encode_u32(entry * 16 + 4, key % CHANNEL_COUNT)
		var amount_bytes: PackedByteArray = PackedByteArray()
		amount_bytes.resize(4)
		amount_bytes.encode_float(0, float(_pending_deltas[key]))
		bytes.encode_u32(entry * 16 + 8, amount_bytes.decode_u32(0))
	var params: PackedFloat32Array = PackedFloat32Array([float(resolution), float(count)])
	if _rendering_device.buffer_update(_delta_buffer, 0, bytes.size(), bytes) != OK:
		return false
	if _rendering_device.buffer_update(_delta_params_buffer, 0, params.size() * 4, params.to_byte_array()) != OK:
		return false
	var list: int = _rendering_device.compute_list_begin()
	if list < 0:
		return false
	_rendering_device.compute_list_bind_compute_pipeline(list, _delta_pipeline)
	_rendering_device.compute_list_bind_uniform_set(list, _delta_uniform_sets[_active_buffer], 0)
	_rendering_device.compute_list_dispatch(list, ceili(float(count) / 64.0), 1, 1)
	_rendering_device.compute_list_end()
	_rendering_device.submit()
	_rendering_device.sync()
	_gpu_delta_count += count
	_pending_deltas.clear()
	return true

func get_total_nutrient() -> float:
	if channels.size() != CHANNEL_COUNT:
		return 0.0
	_read_gpu_state()
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
	_read_gpu_state()
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
		var upload_begin: int = Time.get_ticks_usec()
		var prepared: bool = true
		if _cpu_field_dirty:
			prepared = _upload_active_buffer()
			_cpu_field_dirty = false
		if prepared:
			prepared = _flush_pending_deltas()
		var uploaded: bool = false if not prepared else _upload_tick_buffers(false)
		var dispatch_begin: int = Time.get_ticks_usec()
		var dispatched: bool = false if not uploaded else _dispatch_gpu()
		var dispatch_end: int = Time.get_ticks_usec()
		if not uploaded or not dispatched:
			_gpu_fallback_count += 1
			backend_name = "cpu"
			_free_gpu_resources()
			_apply_pending_deltas_cpu()
			_apply_cpu_diffusion(_pending_sources)
		else:
			# 阶段10：扩散结果留在 GPU，不再每 tick 回读 5R² 个 float。
			# 采样走独立小 buffer；完整镜像只在 snapshot/hash/存档时惰性同步。
			_gpu_upload_usec += maxi(0, dispatch_begin - upload_begin)
			_gpu_dispatch_usec += maxi(0, dispatch_end - dispatch_begin)
			_gpu_tick_count += 1
			_active_buffer = 1 - _active_buffer
			_sample_cache.clear()
	else:
		_apply_pending_deltas_cpu()
		_apply_cpu_diffusion(_pending_sources)
	for source in _pending_sources:
		source.fill(0.0)
	return true

func get_backend_diagnostics() -> Dictionary:
	var total_usec: int = _gpu_upload_usec + _gpu_dispatch_usec + _gpu_readback_usec
	var average_usec: float = float(total_usec) / float(maxi(1, _gpu_tick_count)) if _gpu_tick_count > 0 else 0.0
	return {
		"backend": backend_name,
		"compute_available": _rendering_device != null and _pipeline.is_valid(),
		"device": device_name,
		"vendor": device_vendor,
		"gpu_tick_count": _gpu_tick_count,
		"gpu_fallback_count": _gpu_fallback_count,
		"gpu_upload_usec": _gpu_upload_usec,
		"gpu_dispatch_usec": _gpu_dispatch_usec,
		"gpu_readback_usec": _gpu_readback_usec,
		"gpu_avg_tick_usec": average_usec,
		"dispatch_groups": [ceili(float(resolution) / 8.0), ceili(float(resolution) / 8.0), CHANNEL_COUNT],
		"readback_bytes": _gpu_last_sample_bytes,
		"legacy_full_field_bytes": CHANNEL_COUNT * resolution * resolution * 4,
		"gpu_sample_count": _gpu_sample_count,
		"gpu_sample_cells": _gpu_sample_cells,
		"gpu_delta_count": _gpu_delta_count,
		"gpu_full_readback_count": _gpu_full_readback_count,
		"gpu_sampling_active": backend_name == "gpu_compute" and _sample_pipeline.is_valid()
	}

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
	if not _create_sampling_resources():
		_free_gpu_resources()
		return
	backend_name = "gpu_compute"

func _compile_compute_shader(source_text: String) -> RID:
	var source: RDShaderSource = RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = source_text
	var spirv: RDShaderSPIRV = _rendering_device.shader_compile_spirv_from_source(source)
	if spirv == null or not spirv.compile_error_compute.is_empty():
		return RID()
	var shader: RID = _rendering_device.shader_create_from_spirv(spirv)
	return shader if shader.is_valid() else RID()

func _create_storage_buffer(byte_size: int) -> RID:
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(byte_size)
	return _rendering_device.storage_buffer_create(byte_size, zeros)

func _create_sampling_resources() -> bool:
	_sample_shader = _compile_compute_shader(SAMPLE_SOURCE)
	if not _sample_shader.is_valid():
		return false
	_sample_pipeline = _rendering_device.compute_pipeline_create(_sample_shader)
	if not _sample_pipeline.is_valid():
		return false
	_sample_params_buffer = _create_storage_buffer(20)
	_position_buffer = _create_storage_buffer(MAX_GPU_SAMPLE_CELLS * 8)
	_samples_buffer = _create_storage_buffer(MAX_GPU_SAMPLE_CELLS * CHANNEL_COUNT * 4)
	if not _sample_params_buffer.is_valid() or not _position_buffer.is_valid() or not _samples_buffer.is_valid():
		return false
	for buffer_index in range(2):
		var uniforms: Array[RDUniform] = []
		uniforms.append(_make_storage_uniform(0, _buffers[buffer_index]))
		uniforms.append(_make_storage_uniform(1, _sample_params_buffer))
		uniforms.append(_make_storage_uniform(2, _position_buffer))
		uniforms.append(_make_storage_uniform(3, _samples_buffer))
		var uniform_set: RID = _rendering_device.uniform_set_create(uniforms, _sample_shader, 0)
		if not uniform_set.is_valid():
			return false
		_sample_uniform_sets.append(uniform_set)
	_delta_shader = _compile_compute_shader(DELTA_SOURCE)
	if not _delta_shader.is_valid():
		return false
	_delta_pipeline = _rendering_device.compute_pipeline_create(_delta_shader)
	if not _delta_pipeline.is_valid():
		return false
	_delta_params_buffer = _create_storage_buffer(8)
	_delta_buffer = _create_storage_buffer(MAX_GPU_DELTA_ENTRIES * 16)
	if not _delta_params_buffer.is_valid() or not _delta_buffer.is_valid():
		return false
	for buffer_index in range(2):
		var uniforms: Array[RDUniform] = []
		uniforms.append(_make_storage_uniform(0, _buffers[buffer_index]))
		uniforms.append(_make_storage_uniform(1, _delta_buffer))
		uniforms.append(_make_storage_uniform(2, _delta_params_buffer))
		var uniform_set: RID = _rendering_device.uniform_set_create(uniforms, _delta_shader, 0)
		if not uniform_set.is_valid():
			return false
		_delta_uniform_sets.append(uniform_set)
	return true

func _upload_tick_buffers(upload_field: bool = true) -> bool:
	if upload_field and not _upload_active_buffer():
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
	_gpu_full_readback_count += 1
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
	for uniform_set in _sample_uniform_sets:
		if uniform_set.is_valid():
			_rendering_device.free_rid(uniform_set)
	_sample_uniform_sets.clear()
	for uniform_set in _delta_uniform_sets:
		if uniform_set.is_valid():
			_rendering_device.free_rid(uniform_set)
	_delta_uniform_sets.clear()
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
	for rid_value in [_sample_params_buffer, _position_buffer, _samples_buffer, _delta_params_buffer, _delta_buffer]:
		if rid_value.is_valid():
			_rendering_device.free_rid(rid_value)
	_sample_params_buffer = RID()
	_position_buffer = RID()
	_samples_buffer = RID()
	_delta_params_buffer = RID()
	_delta_buffer = RID()
	if _sample_pipeline.is_valid():
		_rendering_device.free_rid(_sample_pipeline)
		_sample_pipeline = RID()
	if _sample_shader.is_valid():
		_rendering_device.free_rid(_sample_shader)
		_sample_shader = RID()
	if _delta_pipeline.is_valid():
		_rendering_device.free_rid(_delta_pipeline)
		_delta_pipeline = RID()
	if _delta_shader.is_valid():
		_rendering_device.free_rid(_delta_shader)
		_delta_shader = RID()

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
