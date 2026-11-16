extends SceneTree

func _initialize() -> void:
	await process_frame
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var gpu: RefCounted = script.new() as RefCounted
	var cpu: RefCounted = script.new() as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([0.2, 273.0, 0.21, 0.4, 0.1])
	gpu.call("configure", 32, Vector2.ZERO, 100.0, defaults, true)
	cpu.call("configure", 32, Vector2.ZERO, 100.0, defaults, false)
	gpu.call("set_value", 0, 15, 15, 1.0)
	cpu.call("set_value", 0, 15, 15, 1.0)
	gpu.call("set_value", 3, 18, 12, 0.8)
	cpu.call("set_value", 3, 18, 12, 0.8)
	gpu.call("set_advection", Vector2(0.25, -0.125))
	cpu.call("set_advection", Vector2(0.25, -0.125))
	gpu.call("add_source", 0, 15, 15, 0.03)
	cpu.call("add_source", 0, 15, 15, 0.03)
	var gpu_info: Dictionary = gpu.call("get_backend_diagnostics")
	var cpu_info: Dictionary = cpu.call("get_backend_diagnostics")
	if gpu_info.get("backend", "") != "gpu_compute":
		push_error("GPU compute backend unavailable: " + str(gpu_info))
		quit(2)
		return
	var max_error: float = 0.0
	var max_channel: int = -1
	var max_index: int = -1
	for tick in range(2):
		gpu.call("diffuse_tick")
		cpu.call("diffuse_tick")
		var a: Array[PackedFloat32Array] = gpu.call("get_state_snapshot")
		var b: Array[PackedFloat32Array] = cpu.call("get_state_snapshot")
		var tick_max: float = 0.0
		for channel in range(5):
			for index in range(a[channel].size()):
				var error: float = absf(a[channel][index] - b[channel][index])
				tick_max = maxf(tick_max, error)
				if error > max_error:
					max_error = error
					max_channel = channel
					max_index = index
					print("MAX_DETAIL=", tick, ",", channel, ",", index, ",", a[channel][index], ",", b[channel][index])
		print("TICK_MAX_ERROR=", tick, ":", tick_max)
	var state: Array[PackedFloat32Array] = cpu.call("get_state_snapshot")
	var outside_value: float = state[0][0]
	print("GPU_BACKEND=", gpu_info)
	print("CPU_BACKEND=", cpu_info)
	print("MAX_ERROR=", max_error, " CHANNEL=", max_channel, " INDEX=", max_index)
	print("OUTSIDE_MASK_VALUE=", outside_value)
	print("CPU_HASH=", cpu.call("get_state_hash"), " GPU_HASH=", gpu.call("get_state_hash"))
	var parity_ok: bool = true
	var gpu_snapshot: Array[PackedFloat32Array] = gpu.call("get_state_snapshot")
	var cpu_snapshot: Array[PackedFloat32Array] = cpu.call("get_state_snapshot")
	for channel in range(5):
		for index in range(gpu_snapshot[channel].size()):
			var error: float = absf(gpu_snapshot[channel][index] - cpu_snapshot[channel][index])
			var tolerance: float = maxf(0.00001, absf(cpu_snapshot[channel][index]) * 0.0000002)
			if error > tolerance:
				parity_ok = false
	quit(3 if not parity_ok or outside_value != 0.0 else 0)