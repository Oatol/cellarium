extends RefCounted
## Fixed-step cell integration and elastic-link constraints.

const DAMPING: float = 0.98
const CONSTRAINT_ITERATIONS: int = 2
const COLLISION_ITERATIONS: int = 6
## v0.47.0：单轮软弹力碰撞每对推开的穿透比例。1.0 = 每 tick 消除一半穿透，
## 剩余由后续 tick 松弛（Cell Lab 手感：轻微重叠、不硬吸附）。
const COLLISION_SOFTNESS: float = 1.0
## v0.52.1：Cell Lab 连接的端点间隙比例。`CellWorld` 连接求解里
## `d16 = min(r_a, r_b) * 0.4`，端点位于「中心 + (r − d16) 沿连接方向」，
## 两端点重合时中心距 = r_a + r_b − 0.8·min(r_a, r_b)。这是**静止目标**，
## 不是硬约束 —— 实际平衡距离由接触排斥决定。
const LINK_GAP_RATIO: float = 0.4
## v0.52.1：连接从「刚性 PBD 投影」换成软弹簧。Cell Lab 的连接力是
## `f = Δ·d35·d36·d32 + 端点相对速度·d32`，其中 d35 让偏离越大越硬、d32 除以
## max(linkCount) 让连接多的细胞更软。这里用位置空间的等价形式表达同一组性质：
## 每轮只消除 `stiffness × hard × share` 比例的误差，而不是像旧实现那样每轮消除一半。
## `hard = 1 + gain·Δ²/(harden_ratio·rest)²` 对应 Cell Lab `d35 = 1 + 2Δ²/0.0036`，
## 其特征长度 0.06 约为 3 倍细胞半径。
const LINK_STIFFNESS: float = 0.55
const LINK_HARDEN_GAIN: float = 2.0
const LINK_HARDEN_RATIO: float = 2.5
## 端点相对速度阻尼：沿连接方向消减的相对速度比例（Cell Lab `(d29−d27)·d32`）。
const LINK_VELOCITY_DAMPING: float = 0.12
## v0.52.1：过拉伸自动断连。Cell Lab 在「两侧端点距 > 2·max(r)」时删掉连接对
## （`CellWorld` 约 1242 行），换成中心距约为 3.2r；Alien 的 `maxBindingDistance`
## 默认 3.6（半径 1.0）也是同量级。
## 阈值必须按**静止长度**而非直径来定，因为静止长度是 1.2r 而实际平衡距离由接触排斥
## 顶到 2r（= 1.67 倍静止长度）。取 2.4 倍：比正常平衡高 44%，比 Cell Lab 的 2.67 倍略早。
## 取 1.75 会在分裂瞬间误断（实测 `no_behavior_d0` 32 细胞丢 2 条连接）。
## <= 0 关闭撕裂。
const LINK_TEAR_RATIO: float = 2.4
const SPATIAL_HASH_CELL_SIZE: float = 64.0
const SPATIAL_HASH_SOFT_LIMIT: int = 16
## v0.30.0：扁平哈希键偏移。坐标经 64 单位取整后远小于该范围，int64 不会溢出。
const FLAT_KEY_OFFSET: int = 1000000
const FLAT_KEY_SPAN: int = 2000001

static func project_to_dish(cells: RefCounted, center: Vector2, radius: float, normal_damping: float, radius_scales: PackedFloat32Array = PackedFloat32Array(), base_radius: float = 0.0) -> int:
	if cells == null or radius <= 0.0 or normal_damping < 0.0 or normal_damping > 1.0:
		return -1
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var projected: int = 0
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var scale: float = float(radius_scales[cell_index]) if cell_index < radius_scales.size() else 1.0
		var effective_radius: float = maxf(1.0, radius - base_radius * (scale - 1.0))
		var offset: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index]) - center
		if offset.length_squared() <= effective_radius * effective_radius:
			continue
		var normal: Vector2 = offset.normalized()
		var boundary: Vector2 = center + normal * effective_radius
		var current_position: Vector2 = Vector2(pos_x[cell_index], pos_y[cell_index])
		var velocity: Vector2 = current_position - Vector2(prev_x[cell_index], prev_y[cell_index])
		var tangent_velocity: Vector2 = velocity - normal * velocity.dot(normal)
		var reflected_velocity: Vector2 = tangent_velocity - normal * velocity.dot(normal) * normal_damping
		pos_x[cell_index] = boundary.x
		pos_y[cell_index] = boundary.y
		var adjusted_previous: Vector2 = boundary - reflected_velocity
		prev_x[cell_index] = adjusted_previous.x
		prev_y[cell_index] = adjusted_previous.y
		projected += 1
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	return projected

static func resolve_collisions(cells: RefCounted, cell_radius: float, radius_scales: PackedFloat32Array = PackedFloat32Array(), stiffnesses: PackedFloat32Array = PackedFloat32Array()) -> int:
	if cells == null or cell_radius <= 0.0:
		return -1
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var resolved: int = 0
	# 连锁碰撞需要多轮：A 被外细胞推进 B 后，单轮按旧 pairs 已无法再分离 A/B。
	# v0.30.0：pairs 改为扁平 PackedInt32Array（a,b 交替），每 3 轮用同一顺序重建；
	# 遍历顺序与旧的 Array[Vector2i] 完全一致，标量运算替掉临时 Vector2，状态 hash 不变。
	var pairs: PackedInt32Array = build_collision_pairs_flat(cells, cell_radius, radius_scales)
	for iteration in range(COLLISION_ITERATIONS):
		if iteration > 0 and iteration % 3 == 0:
			pairs = build_collision_pairs_flat(cells, cell_radius, radius_scales)
		var round_resolved: int = 0
		var max_correction: float = 0.0
		for pair_index in range(0, pairs.size(), 2):
			var a: int = pairs[pair_index]
			var b: int = pairs[pair_index + 1]
			var dx: float = pos_x[b] - pos_x[a]
			var dy: float = pos_y[b] - pos_y[a]
			var scale_a: float = float(radius_scales[a]) if a < radius_scales.size() else 1.0
			var scale_b: float = float(radius_scales[b]) if b < radius_scales.size() else 1.0
			var contact_distance: float = cell_radius * (scale_a + scale_b)
			var distance_squared: float = dx * dx + dy * dy
			# 远离接触的配对无需 sqrt；边界附近仍走原 sqrt 判定，逐位结果不变。
			if distance_squared > contact_distance * contact_distance + 0.000001:
				continue
			var distance: float = sqrt(distance_squared)
			if distance >= contact_distance:
				continue
			var normal_x: float = 1.0
			var normal_y: float = 0.0
			if distance > 0.000001:
				normal_x = dx / distance
				normal_y = dy / distance
			var stiffness: float = 1.0
			if a < stiffnesses.size() and b < stiffnesses.size():
				stiffness = clampf((float(stiffnesses[a]) + float(stiffnesses[b])) * 0.5, 0.25, 2.0)
			var correction: float = (contact_distance - distance) * 0.5 * stiffness
			pos_x[a] -= normal_x * correction
			pos_y[a] -= normal_y * correction
			pos_x[b] += normal_x * correction
			pos_y[b] += normal_y * correction
			round_resolved += 1
			max_correction = maxf(max_correction, correction)
		resolved += round_resolved
		if max_correction < 0.001:
			break
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	return resolved

## v0.47.0：Cell Lab 式单轮软弹力碰撞（原生 `CellSpatial.resolve_collisions_soft` 的回退实现）。
## 与 resolve_collisions 的差别：单轮、不迭代、不物化 pairs、先比平方再开方、
## 每对只推开穿透深度的一部分（softness），剩余穿透留到后续 tick 松弛。
## 必须与 C++ 版本逐位同序，否则 NativeParityProbe 的 native/CPU 对照会漂移：
##   - contact 用 cell_radius * (scale_a + scale_b)，不要拆成两次乘法；
##   - cell_size <= 0 时按存活细胞最大半径倍率推导，公式与 C++ 完全一致；
##   - 修正量顺序固定为 penetration * 0.5 * stiffness * softness。
static func resolve_collisions_soft(cells: RefCounted, cell_radius: float, radius_scales: PackedFloat32Array = PackedFloat32Array(), stiffnesses: PackedFloat32Array = PackedFloat32Array(), cell_size: float = 0.0, softness: float = 1.0) -> int:
	if cells == null or cell_radius <= 0.0:
		return -1
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var effective_cell_size: float = cell_size
	if effective_cell_size <= 0.0:
		var max_scale: float = 0.0
		for i in range(count):
			if alive[i] == 0 or i >= radius_scales.size():
				continue
			var s: float = float(radius_scales[i])
			if s > max_scale:
				max_scale = s
		if max_scale <= 0.0:
			max_scale = 1.0
		effective_cell_size = 2.0 * cell_radius * max_scale
		if effective_cell_size < 1.0:
			effective_cell_size = 1.0
	var soft: float = clampf(softness, 0.0, 1.0)
	# 固定网格（与 C++ GridBuckets 的桶内插入序一致：cell_index 升序）。
	var buckets: Dictionary = {}
	for i in range(count):
		if alive[i] == 0:
			continue
		var key: int = _flat_key(floori(pos_x[i] / effective_cell_size), floori(pos_y[i] / effective_cell_size))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		var bucket: PackedInt32Array = buckets[key]
		bucket.append(i)
		buckets[key] = bucket
	var resolved: int = 0
	for a in range(count):
		if alive[a] == 0:
			continue
		var cell_x: int = floori(pos_x[a] / effective_cell_size)
		var cell_y: int = floori(pos_y[a] / effective_cell_size)
		var scale_a: float = float(radius_scales[a]) if a < radius_scales.size() else 1.0
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var key: int = _flat_key(cell_x + offset_x, cell_y + offset_y)
				if not buckets.has(key):
					continue
				var bucket: PackedInt32Array = buckets[key]
				for b in bucket:
					if b <= a:
						continue
					var dx: float = pos_x[b] - pos_x[a]
					var dy: float = pos_y[b] - pos_y[a]
					var scale_b: float = float(radius_scales[b]) if b < radius_scales.size() else 1.0
					var contact: float = cell_radius * (scale_a + scale_b)
					var distance_squared: float = dx * dx + dy * dy
					if distance_squared >= contact * contact:
						continue
					var distance: float = sqrt(distance_squared)
					var normal_x: float = 1.0
					var normal_y: float = 0.0
					if distance > 0.000001:
						normal_x = dx / distance
						normal_y = dy / distance
					var stiffness: float = 1.0
					if a < stiffnesses.size() and b < stiffnesses.size():
						stiffness = clampf((float(stiffnesses[a]) + float(stiffnesses[b])) * 0.5, 0.25, 2.0)
					var penetration: float = contact - distance
					var correction: float = penetration * 0.5 * stiffness * soft
					pos_x[a] -= normal_x * correction
					pos_y[a] -= normal_y * correction
					pos_x[b] += normal_x * correction
					pos_y[b] += normal_y * correction
					resolved += 1
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	return resolved

static func step(cells: RefCounted, dt: float) -> void:
	if cells == null or dt <= 0.0:
		return
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	for i in range(count):
		if alive[i] == 0:
			continue
		var x: float = pos_x[i]
		var y: float = pos_y[i]
		var next_x: float = x + (x - prev_x[i]) * DAMPING
		var next_y: float = y + (y - prev_y[i]) * DAMPING
		prev_x[i] = x
		prev_y[i] = y
		pos_x[i] = next_x
		pos_y[i] = next_y
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	cells.set("cell_prev_x", prev_x)
	cells.set("cell_prev_y", prev_y)
	_solve_links(cells, count)

## 复用已构建的空间哈希查询邻居（避免每细胞重建哈希的 O(n²)）；buckets 由 build_spatial_hash 生成。
static func query_neighbors_cached(cells: RefCounted, cell_index: int, buckets: Dictionary) -> Array[int]:
	var neighbors: Array[int] = []
	if cells == null or cell_index < 0:
		return neighbors
	var count: int = int(cells.call("size"))
	if cell_index >= count:
		return neighbors
	var alive: PackedByteArray = cells.get("cell_alive")
	if alive[cell_index] == 0 or buckets.is_empty():
		return neighbors
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var cell_x: int = floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE)
	var cell_y: int = floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var key: Vector2i = Vector2i(cell_x + offset_x, cell_y + offset_y)
			if not buckets.has(key):
				continue
			for sub_bucket in buckets[key]:
				for neighbor_value in sub_bucket:
					var neighbor: int = int(neighbor_value)
					if neighbor != cell_index:
						neighbors.append(neighbor)
	neighbors.sort()
	return neighbors

static func query_neighbors(cells: RefCounted, cell_index: int) -> Array[int]:
	var neighbors: Array[int] = []
	if cells == null:
		return neighbors
	var count: int = int(cells.call("size"))
	if cell_index < 0 or cell_index >= count:
		return neighbors
	var alive: PackedByteArray = cells.get("cell_alive")
	if alive[cell_index] == 0:
		return neighbors
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var buckets: Dictionary = build_spatial_hash(cells)
	var cell_x: int = floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE)
	var cell_y: int = floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var key: Vector2i = Vector2i(cell_x + offset_x, cell_y + offset_y)
			if not buckets.has(key):
				continue
			for sub_bucket in buckets[key]:
				for neighbor_value in sub_bucket:
					var neighbor: int = int(neighbor_value)
					if neighbor != cell_index:
						neighbors.append(neighbor)
	neighbors.sort()
	return neighbors

static func build_collision_pairs(cells: RefCounted) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	if cells == null:
		return pairs
	var count: int = int(cells.call("size"))
	var alive: PackedByteArray = cells.get("cell_alive")
	var buckets: Dictionary = build_spatial_hash(cells)
	for a in range(count):
		if alive[a] == 0:
			continue
		var cell_x: int = floori(float(cells.get("cell_pos_x")[a]) / SPATIAL_HASH_CELL_SIZE)
		var cell_y: int = floori(float(cells.get("cell_pos_y")[a]) / SPATIAL_HASH_CELL_SIZE)
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var key: Vector2i = Vector2i(cell_x + offset_x, cell_y + offset_y)
				if not buckets.has(key):
					continue
				for sub_bucket in buckets[key]:
					for b_value in sub_bucket:
						var b: int = int(b_value)
						# 同个体细胞也参与分离：外部撞击会把细胞推入同簇，跳过自碰撞会造成视觉重叠。
						if b <= a:
							continue
						pairs.append(Vector2i(a, b))
	return pairs

static func build_spatial_hash(cells: RefCounted) -> Dictionary:
	var buckets: Dictionary = {}
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var key: Vector2i = Vector2i(floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE), floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE))
		if not buckets.has(key):
			buckets[key] = [[]]
		var cell_buckets: Array = buckets[key]
		if cell_buckets[cell_buckets.size() - 1].size() >= SPATIAL_HASH_SOFT_LIMIT:
			cell_buckets.append([])
		cell_buckets[cell_buckets.size() - 1].append(cell_index)
		buckets[key] = cell_buckets
	return buckets

## v0.30.0：Cell Lab 式扁平空间哈希。整数键替代 Vector2i，桶内是单个 PackedInt32Array，
## 插入顺序与旧「Array of 16-size sub-buckets」完全一致，因此渲染/碰撞的遍历顺序不变。
static func _flat_key(cell_x: int, cell_y: int) -> int:
	return (cell_x + FLAT_KEY_OFFSET) * FLAT_KEY_SPAN + (cell_y + FLAT_KEY_OFFSET)

static func build_spatial_hash_flat(cells: RefCounted) -> Dictionary:
	var buckets: Dictionary = {}
	if cells == null:
		return buckets
	var count: int = int(cells.call("size"))
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	for cell_index in range(count):
		if alive[cell_index] == 0:
			continue
		var key: int = _flat_key(
			floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE),
			floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE)
		)
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		var bucket: PackedInt32Array = buckets[key]
		bucket.append(cell_index)
		buckets[key] = bucket
	return buckets

## 与 query_neighbors_cached 等价：3×3 邻域 + 排序；返回扁平数组，避免每细胞 Array 分配。
static func query_neighbors_flat(cells: RefCounted, cell_index: int, buckets: Dictionary) -> PackedInt32Array:
	var neighbors: PackedInt32Array = PackedInt32Array()
	if cells == null or cell_index < 0 or buckets.is_empty():
		return neighbors
	var count: int = int(cells.call("size"))
	if cell_index >= count:
		return neighbors
	var alive: PackedByteArray = cells.get("cell_alive")
	if alive[cell_index] == 0:
		return neighbors
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var cell_x: int = floori(pos_x[cell_index] / SPATIAL_HASH_CELL_SIZE)
	var cell_y: int = floori(pos_y[cell_index] / SPATIAL_HASH_CELL_SIZE)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var key: int = _flat_key(cell_x + offset_x, cell_y + offset_y)
			if not buckets.has(key):
				continue
			var bucket: PackedInt32Array = buckets[key]
			for neighbor in bucket:
				if neighbor != cell_index:
					neighbors.append(neighbor)
	neighbors.sort()
	return neighbors

## 与 build_collision_pairs 顺序完全一致（桶遍历顺序，不排序），但写入扁平 PackedInt32Array。
static func build_collision_pairs_flat(cells: RefCounted, cell_radius: float = 0.0, radius_scales: PackedFloat32Array = PackedFloat32Array(), buckets: Dictionary = {}) -> PackedInt32Array:
	var pairs: PackedInt32Array = PackedInt32Array()
	if cells == null:
		return pairs
	var flat_buckets: Dictionary = buckets if not buckets.is_empty() else build_spatial_hash_flat(cells)
	var count: int = int(cells.call("size"))
	var alive: PackedByteArray = cells.get("cell_alive")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	## v0.30.0：只剔除「远到 6 轮修正也不可能相碰」的候选对（距离 > 2×接触距离），
	## 保留下来的对仍按原桶遍历顺序输出。连锁重叠靠这些近邻对求解，hash 不变。
	for a in range(count):
		if alive[a] == 0:
			continue
		var cell_x: int = floori(pos_x[a] / SPATIAL_HASH_CELL_SIZE)
		var cell_y: int = floori(pos_y[a] / SPATIAL_HASH_CELL_SIZE)
		var ax: float = pos_x[a]
		var ay: float = pos_y[a]
		var contact_a: float = cell_radius * (float(radius_scales[a]) if a < radius_scales.size() else 1.0)
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var key: int = _flat_key(cell_x + offset_x, cell_y + offset_y)
				if not flat_buckets.has(key):
					continue
				var bucket: PackedInt32Array = flat_buckets[key]
				for b in bucket:
					if b <= a:
						continue
					if cell_radius > 0.0:
						var dx: float = pos_x[b] - ax
						var dy: float = pos_y[b] - ay
						var scale_b: float = float(radius_scales[b]) if b < radius_scales.size() else 1.0
						var contact_distance: float = contact_a + cell_radius * scale_b
						if dx * dx + dy * dy > contact_distance * contact_distance * 4.0:
							continue
					pairs.append(a)
					pairs.append(b)
	return pairs

## v0.52.1：Cell Lab 语义的静止中心距 —— 两侧端点重合时的中心距。
## `CellWorld` 用 `d16 = min(r_a,r_b)*0.4` 作端点内缩量，端点位于
## 「中心 + (r − d16) 沿连接局部角方向」，故静止中心距 = r_a + r_b − 2·0.4·min。
static func link_rest_base(radius_a: float, radius_b: float) -> float:
	return radius_a + radius_b - 2.0 * LINK_GAP_RATIO * minf(radius_a, radius_b)

## v0.52.1：每 tick 由当前半径重新派生全部连接的静止长度（原生 `derive_link_rest_lengths` 的回退）。
## 半径随能量低通变化，而旧实现把 `link_rest_length` 在创建时写死 —— 细胞长大/缩小时连接长度不跟随，
## 群体被锁成刚性骨架。派生后 `link_rest_length` 是缓存，持久量只有 `link_offset`。
static func derive_link_rest_lengths(cells: RefCounted, cell_radius: float) -> void:
	if cells == null:
		return
	var scales: PackedFloat32Array = cells.get("cell_radius_scale")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var offsets: PackedFloat32Array = cells.get("link_offset")
	var rest: PackedFloat32Array = cells.get("link_rest_length")
	var link_count: int = link_a.size()
	if rest.size() != link_count:
		rest.resize(link_count)
	if offsets.size() != link_count:
		offsets.resize(link_count)
	var scale_count: int = scales.size()
	for link_index in range(link_count):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		var radius_a: float = cell_radius * (float(scales[a]) if a >= 0 and a < scale_count else 1.0)
		var radius_b: float = cell_radius * (float(scales[b]) if b >= 0 and b < scale_count else 1.0)
		rest[link_index] = link_rest_base(radius_a, radius_b) + offsets[link_index]
	cells.set("link_rest_length", rest)

## v0.52.1：软弹簧连接求解（原生 `step_verlet_and_links` 的回退实现）。
## 与旧实现的区别：不再每轮消除一半误差把连接变成不可伸长的杆，而是按
## `stiffness × 硬化 × 连接数分摊` 只消除一部分，再对端点相对速度加阻尼。
## 这样逐细胞推进速度差会被连接吸收成轻微伸缩，而不是被杆件转成压差 → 欧拉屈曲。
static func _solve_links(cells: RefCounted, cell_count: int) -> void:
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var prev_x: PackedFloat32Array = cells.get("cell_prev_x")
	var prev_y: PackedFloat32Array = cells.get("cell_prev_y")
	var alive: PackedByteArray = cells.get("cell_alive")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var rest_lengths: PackedFloat32Array = cells.get("link_rest_length")
	var link_counts: PackedByteArray = cells.get("cell_link_count")
	var count: int = link_a.size()
	for iteration in range(CONSTRAINT_ITERATIONS):
		for link_index in range(count):
			var a: int = link_a[link_index]
			var b: int = link_b[link_index]
			if a < 0 or b < 0 or a >= cell_count or b >= cell_count or alive[a] == 0 or alive[b] == 0:
				continue
			var dx: float = pos_x[b] - pos_x[a]
			var dy: float = pos_y[b] - pos_y[a]
			var distance: float = sqrt(dx * dx + dy * dy)
			if distance <= 0.000001:
				continue
			var rest: float = rest_lengths[link_index]
			var delta: float = distance - rest
			var feature: float = LINK_HARDEN_RATIO * maxf(rest, 0.000001)
			var hard: float = 1.0 + LINK_HARDEN_GAIN * (delta * delta) / (feature * feature)
			var count_a: int = int(link_counts[a]) if a < link_counts.size() else 1
			var count_b: int = int(link_counts[b]) if b < link_counts.size() else 1
			var share: float = 1.0 / float(maxi(1, maxi(count_a, count_b)))
			var k: float = minf(LINK_STIFFNESS * hard * share, 0.9)
			var inverse: float = 1.0 / distance
			var nx: float = dx * inverse
			var ny: float = dy * inverse
			var correction: float = delta * k * 0.5
			pos_x[a] += nx * correction
			pos_y[a] += ny * correction
			pos_x[b] -= nx * correction
			pos_y[b] -= ny * correction
	# 端点相对速度阻尼：Verlet 的 `pos − prev` 就是本 tick 速度，沿连接方向消减相对分量。
	# 质心不变（两端等量反向），与 Cell Lab 力模型里 `(d29 − d27) · d32` 同向同效。
	# v0.52.1：同时做过拉伸判定 —— 中心距超过静止长度 `LINK_TEAR_RATIO` 倍的连接直接断开
	# （Cell Lab 的等价阈值是端点距 > 2·max(r)，约 2.7 倍静止长度）。
	var broken: PackedInt32Array = PackedInt32Array()
	for link_index in range(count):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= cell_count or b >= cell_count or alive[a] == 0 or alive[b] == 0:
			continue
		var dx: float = pos_x[b] - pos_x[a]
		var dy: float = pos_y[b] - pos_y[a]
		var distance: float = sqrt(dx * dx + dy * dy)
		if distance <= 0.000001:
			continue
		var rest: float = rest_lengths[link_index]
		if LINK_TEAR_RATIO > 0.0 and rest > 0.000001 and distance > LINK_TEAR_RATIO * rest:
			broken.append(link_index)
			continue
		var inverse: float = 1.0 / distance
		var nx: float = dx * inverse
		var ny: float = dy * inverse
		var rel_vx: float = (pos_x[b] - prev_x[b]) - (pos_x[a] - prev_x[a])
		var rel_vy: float = (pos_y[b] - prev_y[b]) - (pos_y[a] - prev_y[a])
		var along: float = (rel_vx * nx + rel_vy * ny) * LINK_VELOCITY_DAMPING * 0.5
		pos_x[a] += nx * along
		pos_y[a] += ny * along
		pos_x[b] -= nx * along
		pos_y[b] -= ny * along
	cells.set("cell_pos_x", pos_x)
	cells.set("cell_pos_y", pos_y)
	# 倒序删除，避免每次 remove_at 后索引位移。
	for i in range(broken.size() - 1, -1, -1):
		cells.call("remove_link", broken[i])
