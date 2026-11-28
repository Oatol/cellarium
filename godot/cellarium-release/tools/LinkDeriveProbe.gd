extends SceneTree
## v0.52.1：连接静止长度派生的成本闸门。
## `derive_link_rest_lengths` 每 tick 跑一次（1025 细胞真实皿约 1000 条连接），
## 需要确认它相对 8 ms tick 预算可以忽略，且原生与 GDScript 回退逐位一致。
## 用法：console.exe --headless --path <proj> --script res://tools/LinkDeriveProbe.gd

const CELL_COUNT: int = 1025
const LINK_COUNT: int = 1000
const NATIVE_SAMPLES: int = 200
const SCRIPT_SAMPLES: int = 20
const CELL_RADIUS: float = 7.0
const GAP_RATIO: float = 0.4

var failures: int = 0

func _initialize() -> void:
	var cell_script: Script = load("res://scripts/core/data/CellArray.gd") as Script
	var physics_script: Script = load("res://scripts/system/CellPhysics.gd") as Script
	var cells: RefCounted = cell_script.new() as RefCounted
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261128
	for i in range(CELL_COUNT):
		cells.call("append_cell", 0, Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200)), 0.2, 0)
	var scales: PackedFloat32Array = PackedFloat32Array()
	scales.resize(CELL_COUNT)
	for i in range(CELL_COUNT):
		scales[i] = rng.randf_range(0.6, 1.4)
	cells.set("cell_radius_scale", scales)
	for i in range(LINK_COUNT):
		var a: int = rng.randi_range(0, CELL_COUNT - 1)
		var b: int = rng.randi_range(0, CELL_COUNT - 1)
		if a == b:
			b = (b + 1) % CELL_COUNT
		# 用 link_cells 走真实建连路径（含偏移折算），避免手工拼数组掩盖签名错误。
		cells.call("link_cells", a, b, 14.0, NAN, 1.2 * CELL_RADIUS)
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var offsets: PackedFloat32Array = cells.get("link_offset")
	var scales_read: PackedFloat32Array = cells.get("cell_radius_scale")
	if link_a.size() < LINK_COUNT - 5:
		print("LINK_DERIVE: FAIL link_count=%d expected~%d" % [link_a.size(), LINK_COUNT])
		quit(1)
		return
	if offsets.size() != link_a.size():
		failures += 1
		print("LINK_DERIVE: FAIL link_offset size=%d links=%d" % [offsets.size(), link_a.size()])

	# 1) 原生耗时
	var native: RefCounted = null
	if ClassDB.class_exists("CellSpatial"):
		native = ClassDB.instantiate("CellSpatial") as RefCounted
	var native_rest: PackedFloat32Array = PackedFloat32Array()
	var native_us: int = 0
	if native != null:
		native.call("derive_link_rest_lengths", scales_read, link_a, link_b, offsets, CELL_RADIUS, GAP_RATIO)
		var start: int = Time.get_ticks_usec()
		for i in range(NATIVE_SAMPLES):
			native_rest = native.call("derive_link_rest_lengths",
				scales_read, link_a, link_b, offsets, CELL_RADIUS, GAP_RATIO)
		native_us = (Time.get_ticks_usec() - start) / NATIVE_SAMPLES
		print("LINK_DERIVE: native_us=%d links=%d" % [native_us, link_a.size()])
	else:
		print("LINK_DERIVE: SKIP native (CellSpatial not registered)")

	# 2) GDScript 回退耗时
	var script_cells: RefCounted = cells
	var script_start: int = Time.get_ticks_usec()
	for i in range(SCRIPT_SAMPLES):
		physics_script.call("derive_link_rest_lengths", script_cells, CELL_RADIUS)
	var script_us: int = (Time.get_ticks_usec() - script_start) / SCRIPT_SAMPLES
	print("LINK_DERIVE: script_us=%d" % script_us)

	# 3) 逐位一致
	if native != null:
		var script_rest: PackedFloat32Array = script_cells.get("link_rest_length")
		if native_rest.size() != script_rest.size():
			failures += 1
			print("LINK_DERIVE: FAIL size native=%d script=%d" % [native_rest.size(), script_rest.size()])
		else:
			for i in range(native_rest.size()):
				if native_rest[i] != script_rest[i]:
					failures += 1
					if failures <= 5:
						print("LINK_DERIVE: FAIL [%d] native=%.9f script=%.9f" % [i, native_rest[i], script_rest[i]])

	# 4) 语义断言：静止长度 = 1.2r 附近（偏移 14 − 8.4 = 5.6 → rest ≈ 14）
	var sample_rest: float = float(script_cells.get("link_rest_length")[0])
	if sample_rest <= 0.0:
		failures += 1
		print("LINK_DERIVE: FAIL rest must be positive, got %.4f" % sample_rest)

	# 5) 半径缩小后静止长度必须跟随（旧实现写死，这一步是回归闸门）
	var shrunk: PackedFloat32Array = PackedFloat32Array()
	shrunk.resize(CELL_COUNT)
	shrunk.fill(0.5)
	script_cells.set("cell_radius_scale", shrunk)
	physics_script.call("derive_link_rest_lengths", script_cells, CELL_RADIUS)
	var shrunk_rest: float = float(script_cells.get("link_rest_length")[0])
	if shrunk_rest >= sample_rest:
		failures += 1
		print("LINK_DERIVE: FAIL rest must shrink with radius, before=%.4f after=%.4f" % [sample_rest, shrunk_rest])

	print("LINK_DERIVE: RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
