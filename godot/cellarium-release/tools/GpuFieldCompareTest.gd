extends SceneTree

func _initialize() -> void:
	await process_frame
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var gpu: RefCounted = script.new() as RefCounted
	var cpu: RefCounted = script.new() as RefCounted
	var defaults: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	gpu.call("configure", 8, Vector2.ZERO, 20.0, defaults, true)
	cpu.call("configure", 8, Vector2.ZERO, 20.0, defaults, false)
	gpu.call("set_value", 0, 4, 4, 1.0)
	cpu.call("set_value", 0, 4, 4, 1.0)
	var gpu_diagnostics: Dictionary = gpu.call("get_backend_diagnostics")
	var cpu_diagnostics: Dictionary = cpu.call("get_backend_diagnostics")
	if gpu_diagnostics.get("backend", "") != "gpu_compute":
		push_error("GPU compute backend unavailable: " + str(gpu_diagnostics))
		quit(2)
		return
	gpu.call("diffuse_tick")
	cpu.call("diffuse_tick")
	var gpu_state: Array[PackedFloat32Array] = gpu.call("get_state_snapshot")
	var cpu_state: Array[PackedFloat32Array] = cpu.call("get_state_snapshot")
	var max_error: float = 0.0
	for channel in range(5):
		for index in range(gpu_state[channel].size()):
			max_error = maxf(max_error, absf(gpu_state[channel][index] - cpu_state[channel][index]))
	print("GPU_BACKEND=", gpu_diagnostics)
	print("CPU_BACKEND=", cpu_diagnostics)
	print("MAX_ERROR=", max_error)
	print("CENTER_GPU=", gpu_state[0][36], " NEIGHBOR_GPU=", gpu_state[0][35])
	quit(3 if max_error > 0.00001 else 0)
