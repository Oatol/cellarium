extends SceneTree
## v0.47 阶段 1 探针：Cell Lab 式单轮软弹力碰撞 vs 现有 6 轮迭代碰撞。
## 只读探针，不改生产代码、不碰 state hash。墙钟一律用 OS 单调钟。
##
## 场景参数取自真实工程：CELL_RADIUS=7.0、DISH_RADIUS=240.0、cell_size=64.0。
## 铺法：六方密堆 + 按细胞数自适应半径，保证每个 N 的填充率一致。
##   六方密堆单细胞占面积 ≈ 0.866·spacing²；取 90% 皿面积 → spacing ≈ 433.6/√N，
##   基准半径 r0 = spacing/2/1.02。N=1024→6.51、3000→3.80、5000→2.95。
##
## 三个场景：
##   contact  spacing×0.97 → 所有相邻对都轻微重叠（填充率 95.6%，物理可行）。
##            这是真实密堆的样子：pairs ≈ 3N，用来测加速比。
##   overpack spacing×0.80 → 填充率 140%，物理上不可能分开，只看超载退化不判稳定性。
##   稳定性：contact 场景连续跑单轮软弹力，用**独立 O(n²) 重算**的最大穿透看收敛，
##            不用内核返回的瞬时 max（Gauss-Seidel 顺序处理会产生瞬时尖峰，会误判）。

const CELL_RADIUS: float = 7.0
const DISH_RADIUS: float = 240.0
const CELL_SIZE: float = 64.0
const REPEAT: int = 20
const COUNTS: Array[int] = [1024, 3000, 5000]
## 网格尺寸扫描：真实工程用 64.0，而细胞直径只有 14。9 格邻域在 64 网格下要扫
## 约 20×9=180 个候选，其中只有 ~6 个是真邻居。
## 正确性约束：9 格邻域只覆盖 Chebyshev 距离 ≤ cell_size，而 |Δ|∞ ≤ |Δ|₂，
## 所以要保证不漏对必须 cell_size ≥ 最大接触距离。cell_radius_scale 被 clamp 在
## [0.05, 2.0]，故最大接触距离 = 2×7×2.0 = 28 → 28 是**全局安全下界**。
## 14（=2×7）只在全部 scale ≤ 1.0 时成立，作为上限收益参考一起测。
const CELL_SIZES: Array[float] = [64.0, 28.0, 0.0, 14.0]

var _spatial: RefCounted = null


func _initialize() -> void:
	if not ClassDB.class_exists("CellSpatial"):
		print("COLL: FAIL CellSpatial not registered")
		quit(1)
		return
	_spatial = ClassDB.instantiate("CellSpatial") as RefCounted
	if _spatial == null:
		print("COLL: FAIL instantiate CellSpatial")
		quit(1)
		return
	if not _spatial.has_method("resolve_collisions_soft"):
		print("COLL: FAIL resolve_collisions_soft missing (DLL stale)")
		quit(1)
		return
	print("COLL_PARAMS cell_radius=%.1f dish_radius=%.1f repeat=%d" % [
		CELL_RADIUS, DISH_RADIUS, REPEAT,
	])
	for cs in CELL_SIZES:
		for n in COUNTS:
			_run_case(n, 0.97, "contact", cs)
	quit(0)


func _run_case(count: int, pack: float, tag: String, cell_size: float) -> void:
	var data: Dictionary = _pack(count, pack)
	var px: PackedFloat32Array = data["pos_x"]
	var py: PackedFloat32Array = data["pos_y"]
	var alive: PackedByteArray = data["alive"]
	var scales: PackedFloat32Array = data["scales"]
	var stiffs: PackedFloat32Array = data["stiffs"]
	var r_eff: float = data["r_eff"]
	# 旧路径不接受 0（会除零），cs=0 只用于测新路径的自动推导；旧路径一律按生产值 64。
	var old_cs: float = cell_size if cell_size > 0.0 else 64.0

	# 预热一次，避免首次调用的惰性初始化计入。
	_spatial.call("resolve_collisions", px, py, alive, scales, stiffs, CELL_RADIUS, old_cs, 6)
	_spatial.call("resolve_collisions_soft", px, py, alive, scales, stiffs, CELL_RADIUS, cell_size, 1.0)

	# --- 旧路径：6 轮迭代 ---
	var t0: int = Time.get_ticks_usec()
	var old_res: Dictionary = {}
	for r in range(REPEAT):
		old_res = _spatial.call("resolve_collisions", px, py, alive, scales, stiffs, CELL_RADIUS, old_cs, 6) as Dictionary
	var t1: int = Time.get_ticks_usec()
	var old_us: float = float(t1 - t0) / float(REPEAT)

	# --- 新路径：单轮软弹力 ---
	var t2: int = Time.get_ticks_usec()
	var new_res: Dictionary = {}
	for r in range(REPEAT):
		new_res = _spatial.call("resolve_collisions_soft", px, py, alive, scales, stiffs, CELL_RADIUS, cell_size, 1.0) as Dictionary
	var t3: int = Time.get_ticks_usec()
	var new_us: float = float(t3 - t2) / float(REPEAT)

	print("COLL_TIME tag=%s n=%d cs=%.0f r_eff=%.2f old_us=%.1f old_per_cell=%.2f new_us=%.1f new_per_cell=%.2f speedup=%.2fx" % [
		tag, count, cell_size, r_eff, old_us, old_us / float(count), new_us, new_us / float(count),
		old_us / maxf(1.0, new_us),
	])
	print("COLL_STAT tag=%s n=%d cs=%.1f auto_cs=%.2f old_resolved=%d new_resolved=%d pen_before=%.3f" % [
		tag, count, cell_size, float(new_res.get("cell_size", -1.0)),
		int(old_res.get("resolved", -1)), int(new_res.get("resolved", -1)),
		_max_pen(px, py, alive, r_eff),
	])

	# --- 稳定性：contact 场景连续单轮软弹力，独立重算最大穿透看收敛 ---
	if tag == "contact":
		var cur_x: PackedFloat32Array = px
		var cur_y: PackedFloat32Array = py
		var curve: Array[String] = ["%.3f" % _max_pen(cur_x, cur_y, alive, r_eff)]
		for step in range(10):
			var r: Dictionary = _spatial.call("resolve_collisions_soft", cur_x, cur_y, alive, scales, stiffs, CELL_RADIUS, cell_size, 1.0) as Dictionary
			cur_x = r["pos_x"]
			cur_y = r["pos_y"]
			if step in [0, 1, 2, 4, 9]:
				curve.append("%.3f" % _max_pen(cur_x, cur_y, alive, r_eff))
		print("COLL_RELAX tag=%s n=%d cs=%.0f max_pen_at_pass=[%s]" % [tag, count, cell_size, ",".join(curve)])
		# 旧路径对照：一次 6 轮迭代后残余穿透
		var ox: PackedFloat32Array = px
		var oy: PackedFloat32Array = py
		var old_r: Dictionary = _spatial.call("resolve_collisions", ox, oy, alive, scales, stiffs, CELL_RADIUS, old_cs, 6) as Dictionary
		print("COLL_OLDPEN tag=%s n=%d cs=%.0f old_6iter_max_pen=%.3f" % [
			tag, count, cell_size, _max_pen(old_r["pos_x"], old_r["pos_y"], alive, r_eff),
		])


## 独立重算最大穿透（O(n²)，只用于探针交叉校验，不进生产）。
func _max_pen(pos_x: PackedFloat32Array, pos_y: PackedFloat32Array, alive: PackedByteArray, r_eff: float) -> float:
	var count: int = pos_x.size()
	var worst: float = 0.0
	var contact: float = 2.0 * r_eff
	var broad: float = contact * contact * 4.0
	for a in range(count):
		if alive[a] == 0:
			continue
		for b in range(a + 1, count):
			if alive[b] == 0:
				continue
			var dx: float = pos_x[b] - pos_x[a]
			var dy: float = pos_y[b] - pos_y[a]
			var d2: float = dx * dx + dy * dy
			if d2 > broad:
				continue
			var d: float = sqrt(d2)
			if d < contact:
				worst = maxf(worst, contact - d)
	return worst


## 六方密堆铺 count 个细胞。
## 关键：r_eff 由**基准间距** spacing0 决定，pack 只缩放实际间距。
## 若从 pack 后的 spacing 反推 r_eff，接触距离会跟着缩小，永远刚好相切、零碰撞对
## —— 探针前三版都栽在这上面。pack<1 → 间距 < 2·r_eff → 全部相邻对重叠。
func _pack(count: int, pack: float) -> Dictionary:
	var spacing0: float = 433.6 / sqrt(float(count))
	var r_eff: float = spacing0 * 0.5 / 1.02
	var spacing: float = spacing0 * pack
	var pts: PackedVector2Array = PackedVector2Array()
	var limit: float = DISH_RADIUS - r_eff
	var row_h: float = spacing * 0.8660254037844386
	var y: float = -limit
	var row: int = 0
	while y <= limit:
		var x_off: float = 0.0 if (row % 2) == 0 else spacing * 0.5
		var x: float = -limit + x_off
		while x <= limit:
			if x * x + y * y <= limit * limit:
				pts.append(Vector2(x, y))
			x += spacing
		y += row_h
		row += 1
	if pts.size() < count:
		print("COLL_WARN pack_short count=%d got=%d pack=%.2f" % [count, pts.size(), pack])
	var pos_x: PackedFloat32Array = PackedFloat32Array()
	var pos_y: PackedFloat32Array = PackedFloat32Array()
	var alive: PackedByteArray = PackedByteArray()
	var scales: PackedFloat32Array = PackedFloat32Array()
	var stiffs: PackedFloat32Array = PackedFloat32Array()
	pos_x.resize(count)
	pos_y.resize(count)
	alive.resize(count)
	scales.resize(count)
	stiffs.resize(count)
	var scale_value: float = r_eff / CELL_RADIUS
	var usable: int = mini(count, pts.size())
	for i in range(count):
		if i < usable:
			pos_x[i] = pts[i].x
			pos_y[i] = pts[i].y
			alive[i] = 1
		else:
			pos_x[i] = 0.0
			pos_y[i] = 0.0
			alive[i] = 0
		scales[i] = scale_value
		stiffs[i] = 1.0
	return {
		"pos_x": pos_x, "pos_y": pos_y, "alive": alive,
		"scales": scales, "stiffs": stiffs, "r_eff": r_eff,
	}
