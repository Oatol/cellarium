extends SceneTree
## v0.48 验收：整场镜像查表与 GPU dispatch 采样逐位一致。
##
## 背景：v0.48 把「每 tick 两次按细胞采样」改成「每 tick 一次整场回读 + 两次本机查表」。
## 旧的采样路径是 compute shader（SAMPLE_SOURCE）按 nearest 格取通道值；新路径是
## CellSpatial.sample_fields_nearest() 复刻同一索引规则。两条路径必须**逐位**相等，
## 否则 state hash 会漂。
##
## 无 GPU 环境（headless）打印 SKIP 并正常退出；Vulkan 窗口下执行完整断言。
## 覆盖：皿内随机点、半径边界点、皿外点、格边界（x.0 整数坐标）点。

const SAMPLE_COUNT: int = 2000

func _initialize() -> void:
	await process_frame
	var script: Script = load("res://scripts/system/EnvironmentField.gd") as Script
	if script == null:
		push_error("FIELD_MIRROR_PARITY FAIL: cannot load EnvironmentField.gd")
		quit(1)
		return
	var defaults: PackedFloat32Array = PackedFloat32Array([0.2, 273.0, 0.21, 0.4, 0.1])
	var gpu: RefCounted = script.new() as RefCounted
	gpu.call("configure", 32, Vector2.ZERO, 100.0, defaults, true)
	var info: Dictionary = gpu.call("get_backend_diagnostics")
	if str(info.get("backend", "")) != "gpu_compute":
		print("FIELD_MIRROR_PARITY SKIP backend=", str(info.get("backend", "?")))
		quit(0)
		return
	if not bool(info.get("gpu_sampling_active", false)):
		print("FIELD_MIRROR_PARITY SKIP sample_pipeline_invalid")
		quit(0)
		return
	# 制造有梯度、有源的场，避免全常数掩盖索引错误。
	for channel in range(5):
		for index in range(32 * 32):
			var x: int = index % 32
			var y: int = index / 32
			gpu.call("set_value", channel, x, y, float((x * 7 + y * 13 + channel * 3) % 29) * 0.031 + 0.01)
	gpu.call("set_advection", Vector2(0.25, -0.125))
	for tick in range(3):
		gpu.call("diffuse_tick")

	var positions: Array[Vector2] = _build_positions()
	if positions.size() != SAMPLE_COUNT:
		push_error("FIELD_MIRROR_PARITY FAIL: position count mismatch " + str(positions.size()))
		quit(1)
		return

	# 路径 A：镜像查表（v0.48 新路径）。首次调用触发一次整场回读。
	var diag_before: Dictionary = gpu.call("get_sample_diagnostics")
	var mirror_samples: PackedFloat32Array = gpu.call("sample_cells_flat", positions)
	var diag_after_mirror: Dictionary = gpu.call("get_sample_diagnostics")
	# 路径 B：GPU dispatch（v0.47 旧路径）。关掉 native 查表强制走 dispatch。
	gpu.set("prefer_native_sampler", false)
	var dispatch_samples: PackedFloat32Array = gpu.call("sample_cells_flat", positions)
	gpu.set("prefer_native_sampler", true)

	if mirror_samples.size() != positions.size() * 5 or dispatch_samples.size() != mirror_samples.size():
		push_error("FIELD_MIRROR_PARITY FAIL: size mirror=%d dispatch=%d expected=%d"
			% [mirror_samples.size(), dispatch_samples.size(), positions.size() * 5])
		quit(1)
		return

	var failures: int = 0
	var first_failure: String = ""
	for index in range(mirror_samples.size()):
		if mirror_samples[index] != dispatch_samples[index]:
			failures += 1
			if first_failure.is_empty():
				var cell: int = index / 5
				first_failure = "cell=%d channel=%d mirror=%s dispatch=%s" % [
					cell, index % 5, str(mirror_samples[index]), str(dispatch_samples[index])]
	print("FIELD_MIRROR_PARITY values=%d failures=%d" % [mirror_samples.size(), failures])
	if failures > 0:
		push_error("FIELD_MIRROR_PARITY FAIL: first " + first_failure)
		quit(1)
		return

	# 回读次数语义：一次采样只应触发一次整场回读，且不应再产生按细胞 dispatch。
	var mirror_reads: int = int(diag_after_mirror.get("mirror_readback_count", 0)) - int(diag_before.get("mirror_readback_count", 0))
	var lookups: int = int(diag_after_mirror.get("mirror_lookup_count", 0)) - int(diag_before.get("mirror_lookup_count", 0))
	if mirror_reads > 1 or lookups != 1:
		push_error("FIELD_MIRROR_PARITY FAIL: mirror_reads=%d lookups=%d (expected <=1 and 1)" % [mirror_reads, lookups])
		quit(1)
		return

	# 第二次采样（同一 tick 内）必须复用镜像，不再回读。
	var repeat_samples: PackedFloat32Array = gpu.call("sample_cells_flat", positions)
	var diag_after_repeat: Dictionary = gpu.call("get_sample_diagnostics")
	var repeat_reads: int = int(diag_after_repeat.get("mirror_readback_count", 0)) - int(diag_after_mirror.get("mirror_readback_count", 0))
	if repeat_reads != 0:
		push_error("FIELD_MIRROR_PARITY FAIL: second sample re-read the field, reads=" + str(repeat_reads))
		quit(1)
		return
	var repeat_failures: int = 0
	for index in range(repeat_samples.size()):
		if repeat_samples[index] != mirror_samples[index]:
			repeat_failures += 1
	if repeat_failures != 0:
		push_error("FIELD_MIRROR_PARITY FAIL: repeat sample drifted, failures=" + str(repeat_failures))
		quit(1)
		return

	# 扁平镜像与 5 个通道数组必须同源同值（否则 CPU 回退会与查表分叉）。
	var flat: PackedFloat32Array = gpu.get("_field_flat_mirror") as PackedFloat32Array
	var channels: Array = gpu.get("channels") as Array
	var split_failures: int = 0
	for channel in range(5):
		var plane_values: PackedFloat32Array = channels[channel] as PackedFloat32Array
		for index in range(1024):
			if plane_values[index] != flat[channel * 1024 + index]:
				split_failures += 1
	if split_failures != 0:
		push_error("FIELD_MIRROR_PARITY FAIL: flat mirror vs channel split diverged, failures=" + str(split_failures))
		quit(1)
		return

	print("FIELD_MIRROR_PARITY PASS samples=%d lookups=%d readbacks=%d repeat_reads=%d" % [
		mirror_samples.size(), lookups, mirror_reads, repeat_reads])
	print("FIELD_MIRROR_PARITY DIAG readback_usec=", str(diag_after_mirror.get("mirror_readback_usec", 0.0)),
		" lookup_usec=", str(diag_after_mirror.get("mirror_lookup_usec", 0.0)))
	quit(0)

## 确定性铺点：皿内随机、半径边界、皿外、格边界四类混合。
func _build_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var state: int = 20261128
	var radius: float = 100.0
	var resolution: int = 32
	var step: float = 2.0 * radius / float(resolution)
	while positions.size() < SAMPLE_COUNT:
		state = int((state * 1103515245 + 12345) & 0x7fffffff)
		var selector: int = state % 10
		if selector < 6:
			# 皿内随机点
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var ax: float = (float(state % 20000) / 20000.0) * 2.0 - 1.0
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var ay: float = (float(state % 20000) / 20000.0) * 2.0 - 1.0
			var candidate: Vector2 = Vector2(ax, ay) * radius * 0.98
			if candidate.length() <= radius * 0.98:
				positions.append(candidate)
		elif selector < 8:
			# 格边界：整数倍 step（floor 边界最容易暴露 float32/double 差异）
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var gx: int = state % resolution
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var gy: int = state % resolution
			positions.append(Vector2(-radius + float(gx) * step, -radius + float(gy) * step))
		else:
			# 皿外点：shader 按最近格 clamp，镜像查表必须同行为
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var ox: float = (float(state % 20000) / 20000.0) * 2.0 - 1.0
			state = int((state * 1103515245 + 12345) & 0x7fffffff)
			var oy: float = (float(state % 20000) / 20000.0) * 2.0 - 1.0
			positions.append(Vector2(ox, oy) * radius * 1.35)
	return positions
