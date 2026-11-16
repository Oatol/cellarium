extends SceneTree
## GPU/CPU 场吞吐与后端分项诊断。窗口 Vulkan 下运行可看到 gpu_compute 时间与回读量。
## 无 GPU 环境（headless/集显不可用）仍会跑 CPU 对照并正常退出，不视为失败。

const TICKS: int = 200
const RESOLUTION: int = 64

func _initialize() -> void:
	await process_frame
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	var defaults: PackedFloat32Array = PackedFloat32Array([0.2, 273.0, 0.21, 0.4, 0.1])
	for prefer_gpu in [true, false]:
		var field: RefCounted = script.new() as RefCounted
		field.call("configure", RESOLUTION, Vector2.ZERO, 100.0, defaults, prefer_gpu)
		field.call("set_advection", Vector2(0.125, -0.0625))
		var start_usec: int = Time.get_ticks_usec()
		for _tick in range(TICKS):
			field.call("diffuse_tick")
		var elapsed_usec: int = Time.get_ticks_usec() - start_usec
		var diagnostics: Dictionary = field.call("get_backend_diagnostics")
		print("THROUGHPUT backend=", str(diagnostics.get("backend", "?")),
			" ticks=", TICKS,
			" wall_usec=", elapsed_usec,
			" per_tick_usec=", float(elapsed_usec) / float(TICKS))
		print("DIAG=", diagnostics)
	quit(0)
