extends SceneTree
## 阶段10验收：GPU 按细胞采样 + GPU delta 消费；每 tick 无全量场回读。
## 无 GPU 环境打印 SKIP 并正常退出；窗口 Vulkan 下执行完整断言。

func _initialize() -> void:
	await process_frame
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var defaults: PackedFloat32Array = PackedFloat32Array([0.2, 273.0, 0.21, 0.4, 0.1])
	var gpu: RefCounted = script.new() as RefCounted
	var cpu: RefCounted = script.new() as RefCounted
	gpu.call("configure", 32, Vector2.ZERO, 100.0, defaults, true)
	cpu.call("configure", 32, Vector2.ZERO, 100.0, defaults, false)
	var info: Dictionary = gpu.call("get_backend_diagnostics")
	if str(info.get("backend", "")) != "gpu_compute":
		print("GPU_SAMPLING SKIP backend=", str(info.get("backend", "?")))
		quit(0)
		return
	for field in [gpu, cpu]:
		field.call("set_value", 0, 15, 15, 1.0)
		field.call("set_value", 3, 18, 12, 0.8)
		field.call("set_advection", Vector2(0.25, -0.125))
	info = gpu.call("get_backend_diagnostics")
	var baseline_readbacks: int = int(info.get("gpu_full_readback_count", 0))
	for tick in range(3):
		gpu.call("diffuse_tick")
		cpu.call("diffuse_tick")
	info = gpu.call("get_backend_diagnostics")
	if int(info.get("gpu_full_readback_count", -1)) != baseline_readbacks or int(info.get("readback_bytes", -1)) != 0:
		push_error("GPU_SAMPLING FAIL: full field readback still happens per tick: " + str(info))
		quit(1)
		return
	var positions: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(37.0, 11.0), Vector2(-60.0, 25.0), Vector2(90.0, -10.0)]
	var gpu_samples: Array[PackedFloat32Array] = gpu.call("sample_cells", positions)
	var cpu_samples: Array[PackedFloat32Array] = cpu.call("sample_cells", positions)
	var max_error: float = 0.0
	for index in range(positions.size()):
		for channel in range(5):
			max_error = maxf(max_error, absf(gpu_samples[index][channel] - cpu_samples[index][channel]))
	if max_error > 0.0002:
		push_error("GPU_SAMPLING FAIL: per-cell sample error=" + str(max_error))
		quit(1)
		return
	info = gpu.call("get_backend_diagnostics")
	if int(info.get("gpu_sample_count", 0)) <= 0 or int(info.get("readback_bytes", 0)) != positions.size() * 5 * 4:
		push_error("GPU_SAMPLING FAIL: sample dispatch/readback diagnostics missing: " + str(info))
		quit(1)
		return
	gpu.call("consume", 0, positions[0], 0.01)
	cpu.call("consume", 0, positions[0], 0.01)
	gpu.call("diffuse_tick")
	cpu.call("diffuse_tick")
	info = gpu.call("get_backend_diagnostics")
	if int(info.get("gpu_delta_count", 0)) <= 0:
		push_error("GPU_SAMPLING FAIL: consume delta was not dispatched: " + str(info))
		quit(1)
		return
	var gpu_state: Array[PackedFloat32Array] = gpu.call("get_state_snapshot")
	var cpu_state: Array[PackedFloat32Array] = cpu.call("get_state_snapshot")
	var state_error: float = 0.0
	for channel in range(5):
		for index in range(gpu_state[channel].size()):
			state_error = maxf(state_error, absf(gpu_state[channel][index] - cpu_state[channel][index]))
	if state_error > 0.0005:
		push_error("GPU_SAMPLING FAIL: state error after delta=" + str(state_error))
		quit(1)
		return
	info = gpu.call("get_backend_diagnostics")
	if int(info.get("gpu_full_readback_count", 0)) <= 0:
		push_error("GPU_SAMPLING FAIL: snapshot did not lazily refresh CPU mirror")
		quit(1)
		return
	print("GPU_SAMPLING PASS sample_error=", max_error, " state_error=", state_error, " diag=", info)
	quit(0)
