extends PanelContainer
## 只读基因组发育预览（v0.26.0：Cell Lab Macro 同款连续时间轴）。
signal mode_selected(mode_index: int)
## Cell Lab 证据：`GenomePreviewView` 用真实模拟类的独立实例（官方版 new CellWorld(true,env)、
## Macro 版 new SimulationWorld(env,true)），换实验室环境、固定种子 1337，从单合子跑真实
## 物理/分裂/代谢，再程序化绘制真实细胞 + 分裂指示器 + 平移缩放选中回调（见分析文档 §32）。
##
## 交互严格对齐 Macro `GenomeEditorFragment.previewTimeHours`：
##   - 只有一个连续时间滑块（Cell Lab 是 0–90 小时；本项目直接映射模拟 tick），没有
##     「上一步/播放/下一步」离散阶段按钮——拖动时间即从合子跑真实模拟到那一刻。
##   - 断点续算：目标 tick 大于当前从当前状态续跑，小于当前则重置世界从合子重跑
##     （对应 J4 的 Z/T/V/W 缓存状态机）。
##   - 每帧渲染该 tick 的真实快照：位置/半径/表型色/模式/连接/共享弦都来自真实 CellArray。
##   - 视图按当前细胞包围盒自适应居中缩放，避免真实皿坐标(250,250)把细胞画到画布外。

const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const PREVIEW_WORLD: Script = preload("res://scripts/core/data/PreviewWorld.gd")
## 复用运行时的 Cell Lab 弦工具：物理与渲染共享同一组圆-圆相交弦端点。
const CHORDS: RefCounted = preload("res://scripts/rendering/CellContactChords.gd")

const MAX_DIVISION_EVENTS: int = 8   # 里程碑快照上限（供只读 API/回归；不影响连续渲染）
const VIEW_SCALE_MAX: float = 2.4
const VIEW_SCALE_MIN: float = 0.12
const VIEW_MARGIN_PX: float = 12.0
## 默认草案 division_mass=1.0 超出真实能量上限，永远不会分裂；空跑到 4000 tick 会卡死。
## 连续 N tick 没有分裂就认为该草案不再发育，提前收尾（有分裂时仍按真实发育继续）。
const IDLE_STOP_TICKS: int = 240

var _world: RefCounted = null
var _pan: Vector2 = Vector2.ZERO
var _zoom: float = 1.0

## v0.21.0：对应 Cell Lab Macro `checkbox_show_split_indicators`。纯绘制，不写模拟状态。
@export var show_split_indicators: bool = true

@export var canvas_path: NodePath = ^"Margin/VBox/Canvas"
@export var caption_path: NodePath = ^"Margin/VBox/Caption"
@export var timeline_path: NodePath = ^"Margin/VBox/Timeline/Slider"
@export var time_label_path: NodePath = ^"Margin/VBox/Timeline/TimeLabel"

var _canvas: Control = null
var _caption: Label = null
var _timeline: HSlider = null
var _time_label: Label = null
var _program_signature: String = ""
## 里程碑快照（每个分裂时刻一条），仅作为只读索引供 SmokeTest/外部检查；渲染不再逐条播放。
var _states: Array[Dictionary] = []
var _cursor: int = 0
## 连续时间轴：_current_tick 为滑块位置，_max_tick 为发育完成 tick（上限）。
var _current_tick: int = 0
var _max_tick: int = 0
var _current_state: Dictionary = {}
var _genes: Array[Dictionary] = []
var _initial_slot: int = 0
var _syncing_timeline: bool = false
## 自适应视图变换（按当前快照细胞包围盒居中），由 _refresh_view_transform 计算。
var _view_center: Vector2 = Vector2.ZERO
var _view_scale: float = 1.0

func _ready() -> void:
	_canvas = get_node_or_null(canvas_path) as Control
	_caption = get_node_or_null(caption_path) as Label
	_timeline = get_node_or_null(timeline_path) as HSlider
	_time_label = get_node_or_null(time_label_path) as Label
	if _timeline != null:
		_timeline.value_changed.connect(_on_timeline_changed)
	if _canvas != null:
		_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		if not _canvas.is_connected("draw", Callable(self, "_on_canvas_draw")):
			_canvas.draw.connect(_on_canvas_draw)
		if not _canvas.is_connected("gui_input", Callable(self, "_on_canvas_gui_input")):
			_canvas.gui_input.connect(_on_canvas_gui_input)
	_rebuild_states()

## 只读取 dev_program / 基因模式参数 / Macro 草案；相同参数重复调用不重置时间轴。
func set_program(program: Array, macro_draft: Dictionary = {}, gene_mode: bool = false, modes: Array = []) -> void:
	var signature: String = str(program) + "|" + str(gene_mode)
	var has_modes: bool = gene_mode and not modes.is_empty()
	if gene_mode:
		signature += "|" + str(macro_draft.get("cell_type", 0)) + "|" + str(macro_draft.get("division_mass", 1.0))
		signature += "|" + str(macro_draft.get("max_divisions", 3)) + "|" + str(macro_draft.get("make_glue", false))
		signature += "|" + str(macro_draft.get("nutrition_priority", 0.5)) + "|" + str(macro_draft.get("stiffness", 0.5))
		signature += "|" + str(macro_draft.get("cell_size", 1.0)) + "|" + str(macro_draft.get("max_connections", 4))
		signature += "|" + str(macro_draft.get("min_connections", 0)) + "|" + str(macro_draft.get("color_r", 0.36))
		signature += "|" + str(macro_draft.get("color_g", 0.88)) + "|" + str(macro_draft.get("color_b", 0.75))
		for child_index in range(1, 5):
			signature += "|" + str(macro_draft.get("child%d" % child_index, 0)) + ":" + str(macro_draft.get("child%d_angle" % child_index, 0.0))
		if has_modes:
			signature += "|modes=" + str(modes)
	else:
		signature += "|" + str(macro_draft.get("cell_type", 0))
	if signature == _program_signature and not _states.is_empty():
		return
	_program_signature = signature
	if gene_mode:
		if has_modes:
			_rebuild_mode_states(macro_draft, modes)
		else:
			_rebuild_gene_states(macro_draft)
	else:
		_rebuild_states_from(program, int(macro_draft.get("cell_type", 0)))

# ---------- 只读兼容 API（SmokeTest / DevEditorPanel 依赖） ----------
func get_state_count() -> int:
	return _states.size()

func get_cursor() -> int:
	return _cursor

func get_cell_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int((_states[state_index] as Dictionary).get("cells", []).size())

func get_link_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int(((_states[state_index] as Dictionary).get("links", []) as Array).size())

func get_split_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int(((_states[state_index] as Dictionary).get("splits", []) as Array).size())

func get_split_angle_at(state_index: int, split_index: int) -> float:
	if state_index < 0 or state_index >= _states.size():
		return -INF
	var splits: Array = (_states[state_index] as Dictionary).get("splits", []) as Array
	if split_index < 0 or split_index >= splits.size():
		return -INF
	return float((splits[split_index] as Dictionary).get("angle", -INF))

func get_cell_type_at(state_index: int, cell_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return -1
	var cells: Array = (_states[state_index] as Dictionary).get("cells", []) as Array
	if cell_index < 0 or cell_index >= cells.size():
		return -1
	return int((cells[cell_index] as Dictionary).get("type", -1))

func get_mode_at(state_index: int, cell_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return -1
	var cells: Array = (_states[state_index] as Dictionary).get("cells", []) as Array
	if cell_index < 0 or cell_index >= cells.size():
		return -1
	return int((cells[cell_index] as Dictionary).get("mode", -1))

func get_state_caption_at(state_index: int) -> String:
	if state_index < 0 or state_index >= _states.size():
		return ""
	return str((_states[state_index] as Dictionary).get("caption", ""))

## v0.26.0：时间轴即连续 tick，没有播放状态。保留 API 仅为外部兼容。
func is_playing() -> bool:
	return false

func set_playing(_value: bool) -> void:
	pass

func get_current_tick() -> int:
	return _current_tick

func get_max_tick() -> int:
	return _max_tick

## 兼容旧接口：跳到下一/上一里程碑快照 tick（对应原来按钮的只读语义）。
func step_forward() -> void:
	_cursor = mini(_cursor + 1, maxi(0, _states.size() - 1))
	_seek_milestone()

func step_back() -> void:
	_cursor = maxi(_cursor - 1, 0)
	_seek_milestone()

func _seek_milestone() -> void:
	if _cursor < 0 or _cursor >= _states.size() or _timeline == null:
		return
	_timeline.value = float((_states[_cursor] as Dictionary).get("tick", 0))
	_seek_to(int(_timeline.value))

# ---------- 构建真实模拟 + 里程碑索引 ----------
func _rebuild_states() -> void:
	var default_gene: Dictionary = GENOME_SCRIPT.call("normalized_mode", {}, 0)
	_run_simulation([default_gene], 0, 5)

func _rebuild_mode_states(draft: Dictionary, raw_modes: Array) -> void:
	var modes: Array[Dictionary] = []
	for i in range(raw_modes.size()):
		modes.append(GENOME_SCRIPT.call("normalized_mode", raw_modes[i], i))
	if modes.is_empty():
		_rebuild_gene_states(draft)
		return
	var initial_slot: int = 0
	for i in range(modes.size()):
		if bool((modes[i] as Dictionary).get("initial", false)):
			initial_slot = i
			break
	var global_divisions: int = clampi(int(round(float(draft.get("max_divisions", 3)))), 0, MAX_DIVISION_EVENTS)
	_run_simulation(modes, initial_slot, global_divisions)

## 用真实内核跑整段发育：记录里程碑快照（供只读索引），并把世界留在发育完成态。
func _run_simulation(genes: Array[Dictionary], initial_slot: int, max_events: int) -> void:
	# v0.51.0：改设置后重跑预览，但**保留时间轴位置**（Cell Lab 的发育预览刷新后不会跳回 t=0，
	# 否则每改一个滑块都要重新拖时间刻度）。超出新时长时由 _init_timeline 钳到末态。
	var previous_tick: int = _current_tick
	_states.clear()
	_cursor = 0
	_genes = []
	for g in genes:
		_genes.append((g as Dictionary).duplicate(true))
	_initial_slot = clampi(initial_slot, 0, maxi(0, _genes.size() - 1))
	_world = PREVIEW_WORLD.new()
	_world.setup(_genes, _initial_slot)
	var accumulated_splits: Array[Dictionary] = []
	var divisions: int = 0
	var last_split_tick: int = 0
	# 初始快照（合子）
	_states.append(_make_snapshot(0, "真实模拟 · 合子 · t=0", []))
	for _t in range(4000):
		_world.step()
		var splits: Array[Dictionary] = _world.consume_splits()
		if not splits.is_empty():
			last_split_tick = int(_world.get_tick())
			for entry in splits:
				accumulated_splits.append((entry as Dictionary).duplicate(true))
				divisions += 1
			if divisions <= max_events:
				var cells: Array[Dictionary] = _world.snapshot_cells()
				var caption: String = "真实模拟 · 分裂 %d · %d 细胞 · t=%d" % [divisions, cells.size(), int(_world.get_tick())]
				_states.append(_make_snapshot(divisions, caption, accumulated_splits.duplicate(true)))
		# 无分裂草案（如默认 division_mass=1.0）不再空跑满 4000 tick。
		if bool(_world.is_grown()) or int(_world.get_tick()) - last_split_tick >= IDLE_STOP_TICKS:
			break
	_max_tick = int(_world.get_tick())
	# 时间轴范围 = 本次发育收尾 tick；停在改动前的时刻（首次构建即 t=0）。
	_init_timeline(previous_tick)

## 连续时间定位：拖动滑块 → 真实模拟续跑/重置到该 tick → 渲染那一刻。
## 默认停在 t=0（合子）：先跑完整段只为拿 _max_tick/里程碑，拖到末态才需重跑 74 tick，
## 默认在末态时用户一拖就会触发重置+重跑而卡顿（Cell Lab Macro 也是从 0 小时开始）。
func _init_timeline(target_tick: int = 0) -> void:
	var restore: int = clampi(target_tick, 0, _max_tick)
	if _timeline != null:
		_timeline.min_value = 0.0
		_timeline.max_value = float(maxi(1, _max_tick))
		_timeline.step = 1.0
		_syncing_timeline = true
		_timeline.value = float(restore)
		_syncing_timeline = false
	_seek_to(restore)

func _on_timeline_changed(value: float) -> void:
	if _syncing_timeline:
		return
	_seek_to(int(round(value)))

func _seek_to(tick_value: int) -> void:
	_current_tick = clampi(tick_value, 0, _max_tick)
	if _world != null:
		_world.advance_to(_current_tick)
	# Cell Lab j4.I() 逐当前细胞派生指示点；不再累积历史分裂（否则绿点越堆越多）。
	var current_splits: Array[Dictionary] = []
	if _world != null:
		current_splits = _world.snapshot_split_indicators()
	_current_state = _make_snapshot(0, "真实模拟 · t=%d" % _current_tick, current_splits)
	# 让 _cursor 跟随当前 tick 最近的里程碑（只读 API 语义）。
	_cursor = 0
	for i in range(_states.size()):
		if int((_states[i] as Dictionary).get("tick", 0)) <= _current_tick:
			_cursor = i
		else:
			break
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _sync_caption() -> void:
	_sync_timeline()
	if _caption == null:
		return
	var cells: Array = _current_state.get("cells", []) as Array
	_caption.text = "真实模拟 · t=%d · %d 细胞（拖动时间轴观察发育）" % [_current_tick, cells.size()]

func _sync_timeline() -> void:
	if _timeline == null:
		return
	if not is_equal_approx(_timeline.max_value, float(maxi(1, _max_tick))):
		_timeline.max_value = float(maxi(1, _max_tick))
	_syncing_timeline = true
	_timeline.value = float(_current_tick)
	_syncing_timeline = false
	if _time_label != null:
		var cells: Array = _current_state.get("cells", []) as Array
		_time_label.text = "t=%d · %d胞" % [_current_tick, cells.size()]

func _make_snapshot(step_index: int, caption: String, splits: Array[Dictionary]) -> Dictionary:
	var cells: Array[Dictionary] = []
	if _world != null:
		for c in _world.snapshot_cells():
			var cell: Dictionary = (c as Dictionary).duplicate(true)
			cells.append(cell)
	var links: Array[Dictionary] = []
	var tick: int = 0
	if _world != null:
		links = _world.snapshot_links()
		tick = int(_world.get_tick())
	return {"cells": cells, "links": links, "caption": caption, "splits": splits, "step": step_index, "tick": tick}

func _rebuild_gene_states(draft: Dictionary) -> void:
	var genes: Array[Dictionary] = []
	var n_modes: int = 2
	for i in range(n_modes):
		var gene: Dictionary = {
			"cell_type": int(draft.get("cell_type", 0)) if i == 0 else int(draft.get("child%d" % (i + 1), draft.get("cell_type", 0))),
			"division_mass": float(draft.get("division_mass", 0.05)),
			"split_ratio": float(draft.get("split_ratio", 0.5)),
			"child1_mode": 0, "child2_mode": 1,
			"child1_angle": float(draft.get("child1_angle", 0.0)),
			"child2_angle": float(draft.get("child2_angle", 0.25)),
			"child1_mirror": bool(draft.get("child1_mirror", false)),
			"child2_mirror": bool(draft.get("child2_mirror", false)),
			"split_angle": float(draft.get("split_angle", 0.0)),
			"split_angle2": float(draft.get("split_angle2", 0.25)),
			"make_glue": bool(draft.get("make_glue", true)),
			"telomere": -1,
			"max_connections": int(draft.get("max_connections", 16)),
			"nutrition_priority": float(draft.get("nutrition_priority", 0.5)),
			"cell_size": float(draft.get("cell_size", 1.0)),
			"initial": i == 0,
		}
		genes.append(GENOME_SCRIPT.call("normalized_mode", gene, i))
	var divisions: int = clampi(int(round(float(draft.get("max_divisions", 3)))), 0, MAX_DIVISION_EVENTS)
	_run_simulation(genes, 0, divisions)

## 旧 dev_program 指令路径（新基因组为基因模式，基本不走）；保留只读兼容。
func _rebuild_states_from(program: Array, cell_type: int) -> void:
	var genes: Array[Dictionary] = [GENOME_SCRIPT.call("normalized_mode", {"cell_type": cell_type, "division_mass": 0.05}, 0)]
	_run_simulation(genes, 0, MAX_DIVISION_EVENTS)

# ---------- 交互 ----------
func _on_canvas_gui_input(event: InputEvent) -> void:
	if _canvas == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15); _canvas.accept_event(); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15); _canvas.accept_event(); return
		if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = mb.pressed
			_drag_last = mb.position
			_canvas.accept_event(); return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select_cell_at(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_pan += mm.position - _drag_last
		_drag_last = mm.position
		_canvas.queue_redraw()
		_canvas.accept_event()

var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

func _zoom_at(anchor: Vector2, factor: float) -> void:
	var old_zoom: float = _zoom
	var new_zoom: float = clampf(_zoom * factor, VIEW_SCALE_MIN, VIEW_SCALE_MAX)
	if abs(log(new_zoom / old_zoom)) > 0.3:
		new_zoom = old_zoom * exp(0.3 if factor > 1.0 else -0.3)
	var center: Vector2 = _canvas.size * 0.5
	var world_anchor: Vector2 = (anchor - center - _pan) / (_view_scale * old_zoom)
	_pan = anchor - center - world_anchor * _view_scale * new_zoom
	_zoom = new_zoom
	_canvas.queue_redraw()

func _select_cell_at(local_position: Vector2) -> void:
	var cells: Array = _current_state.get("cells", []) as Array
	if cells.is_empty():
		return
	var best_index: int = -1
	var best_distance: float = INF
	for cell_index in range(cells.size()):
		var cell: Dictionary = cells[cell_index] as Dictionary
		var screen_pos: Vector2 = _to_screen(cell.get("pos", Vector2.ZERO))
		var distance_value: float = local_position.distance_to(screen_pos)
		if distance_value < best_distance:
			best_distance = distance_value
			best_index = cell_index
	if best_index < 0:
		return
	var cell_radius_px: float = float((cells[best_index] as Dictionary).get("radius", 7.0)) * _view_scale * _zoom
	if best_distance > cell_radius_px + 8.0:
		return
	var mode_index: int = int((cells[best_index] as Dictionary).get("mode", -1))
	if mode_index >= 0:
		mode_selected.emit(mode_index)
		_canvas.accept_event()

## 自适应居中缩放：按当前快照细胞包围盒计算，真实皿坐标平移后在此居中，避免画到画布外。
func _refresh_view_transform() -> void:
	var cells: Array = _current_state.get("cells", []) as Array
	if cells.is_empty():
		_view_center = Vector2.ZERO
		_view_scale = 1.0
		return
	var centroid: Vector2 = Vector2.ZERO
	for item in cells:
		centroid += (item as Dictionary).get("pos", Vector2.ZERO)
	centroid /= float(cells.size())
	var extent: float = 8.0
	for item in cells:
		var cell: Dictionary = item as Dictionary
		extent = maxf(extent, centroid.distance_to(cell.get("pos", Vector2.ZERO)) + float(cell.get("radius", 7.0)))
	var half: float = mini(_canvas.size.x, _canvas.size.y) * 0.5 - VIEW_MARGIN_PX
	_view_center = centroid
	_view_scale = clampf(maxf(1.0, half) / extent, VIEW_SCALE_MIN, VIEW_SCALE_MAX)

func _to_screen(world_pos: Vector2) -> Vector2:
	return _canvas.size * 0.5 + _pan + (world_pos - _view_center) * _view_scale * _zoom

func _on_canvas_draw() -> void:
	if _canvas == null or _current_state.is_empty():
		return
	_refresh_view_transform()
	var cells: Array = _current_state.get("cells", []) as Array
	var links: Array = _current_state.get("links", []) as Array
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.02, 0.06, 0.055, 1.0))
	for link in links:
		var pair: Dictionary = link as Dictionary
		var a_index: int = int(pair.get("a", -1))
		var b_index: int = int(pair.get("b", -1))
		if a_index < 0 or b_index < 0 or a_index >= cells.size() or b_index >= cells.size():
			continue
		var a_pos: Vector2 = _to_screen((cells[a_index] as Dictionary).get("pos", Vector2.ZERO))
		var b_pos: Vector2 = _to_screen((cells[b_index] as Dictionary).get("pos", Vector2.ZERO))
		_canvas.draw_line(a_pos, b_pos, Color(0.36, 0.88, 0.75, 0.85), 2.0 * _zoom)
	for item in cells:
		var cell: Dictionary = item as Dictionary
		var pos: Vector2 = _to_screen(cell.get("pos", Vector2.ZERO))
		var world_radius: float = float(cell.get("radius", 7.0))
		var radius: float = world_radius * _view_scale * _zoom
		var type_id: int = int(cell.get("type", 0))
		var cell_color: Variant = cell.get("color", null)
		var base_color: Color = (cell_color as Color) if cell_color is Color else (VISUALS.call("role_color", type_id) as Color)
		var fill: Color = base_color
		fill.a = 0.55
		var membrane: Color = base_color.lightened(0.22)
		membrane.a = 1.0
		_draw_membrane(cell, pos, radius, world_radius, fill, membrane)
	# Cell Lab j4.I() 逐方法等价的分裂指示器。
	if not show_split_indicators:
		return
	var splits: Array = _current_state.get("splits", []) as Array
	for entry in splits:
		_draw_split_indicator(entry as Dictionary)

func _draw_split_indicator(indicator: Dictionary) -> void:
	# Cell Lab Macro `j4.I()` 逐方法等价：指示的是「当前细胞下一次分裂的子代去向」。
	#   d4  = 朝向 + (镜像?-1:1)*Gene.d          → 分裂轴
	#   fMax= max(0.006, q0*0.27)                → 标记半径
	#   f2  = q0 + 0.42*fMax ; f3 = f2*2
	#   f4  = (1-ratio)*f3（子代 1 侧）; f5 = ratio*f3（子代 2 侧）
	# 两个标记到中心的距离比 = 质量比，标记方向 = 分裂角。v0.50.0 额外补一条虚线分裂轴，
	# 让「角度」和「质量比」在画布上直接可读（Cell Lab 靠标记位置表达，本项目把它画出来）。
	var split_center: Vector2 = _to_screen(indicator.get("pos", Vector2.ZERO))
	var angle: float = float(indicator.get("angle", 0.0))
	var dir: Vector2 = Vector2(cos(angle), sin(angle))
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var unit: float = _view_scale * _zoom
	var world_radius: float = float(indicator.get("radius", 7.0))
	var f_max: float = maxf(0.006, world_radius * 0.27)
	var f2: float = world_radius + 0.42 * f_max
	var f3: float = f2 * 2.0
	var ratio: float = clampf(float(indicator.get("ratio", 0.5)), 0.1, 0.9)
	var d_child1: float = (1.0 - ratio) * f3
	var d_child2: float = ratio * f3
	var child1_slot: int = clampi(int(indicator.get("child1_mode", 0)), 0, 7)
	var child2_slot: int = clampi(int(indicator.get("child2_mode", 1)), 0, 7)
	var is_zygote: bool = bool(indicator.get("zygote", false))
	var p_child1: Vector2 = split_center + dir * d_child1 * unit
	var p_child2: Vector2 = split_center - dir * d_child2 * unit
	var child1_color: Color = _slot_color(child1_slot, 0)
	var child2_color: Color = _slot_color(child2_slot, 1)
	var dot_radius_px: float = maxf(2.0, f_max * unit)
	# 虚线分裂轴：从子代 2 标记穿过细胞中心到子代 1 标记，长度比即质量比。
	var axis_color: Color = Color(0.95, 0.88, 0.45, 0.85)
	_canvas.draw_dashed_line(p_child2, p_child1, axis_color, maxf(1.0, 1.2 * unit),
		maxf(2.0, 2.0 * unit), true, true)
	# 分裂面：过中心垂直于分裂轴的短线，提示「细胞在这里被切开」。
	var plane_half: float = maxf(2.0, 0.35 * f_max * unit)
	_canvas.draw_line(split_center - perp * plane_half, split_center + perp * plane_half,
		Color(axis_color.r, axis_color.g, axis_color.b, 0.6), maxf(1.0, 1.0 * unit), true)
	_draw_split_marker(p_child1, dot_radius_px, child1_color, 1)
	_draw_split_marker(p_child2, dot_radius_px, child2_color, 2)
	if is_zygote:
		# 合子四条去向：第二分裂轴取 Gene.B（本项目 `split_angle2` 的第二轴语义），
		# 比例取 ratio2。第三/第四槽未来加入时自动生效。
		var gene: Dictionary = _world.get_gene(clampi(int(indicator.get("gene_slot", 0)), 0, 7)) if _world != null else {}
		var axis2: float = TAU * clampf(float(gene.get("split_angle2", 0.0)), 0.0, 1.0)
		var dir2: Vector2 = Vector2(cos(axis2), sin(axis2))
		var f10: float = 1.5 * f_max
		var slots: Array[int] = [
			child1_slot, child2_slot,
			clampi(int(gene.get("child3_mode", child1_slot)), 0, 7),
			clampi(int(gene.get("child4_mode", child2_slot)), 0, 7),
		]
		for k in range(4):
			var gcol: Color = _slot_color(slots[k], k % 2)
			var sign: float = 1.0 if k % 2 == 0 else -1.0
			var dist: float = (1.0 - ratio) * f10 if k < 2 else ratio * f10
			var pp: Vector2 = split_center + dir2 * dist * unit * sign
			_canvas.draw_circle(pp, dot_radius_px * 0.8, Color(gcol.r, gcol.g, gcol.b, 0.85))

## Cell Lab `H()`：带编号的子代标记，颜色取该子代目标 Gene 槽的 RGB。
func _draw_split_marker(center: Vector2, radius: float, color: Color, index: int) -> void:
	_canvas.draw_circle(center, radius, Color(color.r, color.g, color.b, 0.9))
	_canvas.draw_arc(center, radius, 0.0, TAU, 16, Color(0.05, 0.08, 0.09, 0.9), 1.0, true)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var text: String = str(index)
	var font_size: int = maxi(7, int(radius * 1.5))
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_canvas.draw_string(font, center + Vector2(-width * 0.5, font_size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.05, 0.08, 0.09, 0.95))

func _slot_color(slot: int, fallback: int) -> Color:
	var gene: Dictionary = _world.get_gene(slot) if _world != null else {}
	if gene.is_empty():
		return (VISUALS.call("role_color", fallback) as Color)
	return Color(float(gene.get("color_r", 0.36)), float(gene.get("color_g", 0.88)), float(gene.get("color_b", 0.75)), 1.0)

## Cell Lab a(FFFF)/d(int) 复刻：物理与渲染共享同一组圆-圆相交弦端点。
func _draw_membrane(cell: Dictionary, screen_pos: Vector2, radius: float, world_radius: float,
		fill: Color, membrane: Color) -> void:
	var world_chords: Array = cell.get("chords", []) as Array
	var cell_center: Vector2 = cell.get("pos", Vector2.ZERO)
	var outline_points: PackedVector2Array = PackedVector2Array()
	if not world_chords.is_empty():
		var unit_chords: Array = CHORDS.call("make_unit_chords", world_chords, cell_center, 0.0, world_radius)
		var prepared: Array = CHORDS.call("prepare_for_render", unit_chords)
		outline_points = CHORDS.call("clip_unit_circle", prepared, 48)
	if outline_points.size() >= 3:
		var world_poly: PackedVector2Array = PackedVector2Array()
		for point in outline_points:
			world_poly.append(screen_pos + point * radius)
		_canvas.draw_colored_polygon(world_poly, fill)
		var closed: PackedVector2Array = world_poly.duplicate()
		closed.append(world_poly[0])
		_canvas.draw_polyline(closed, membrane, 2.0, true)
	else:
		_canvas.draw_circle(screen_pos, radius, fill)
		_canvas.draw_arc(screen_pos, radius, 0.0, TAU, 32, membrane, 2.0, true)
	_canvas.draw_circle(screen_pos, radius * 0.25, Color(0.9, 0.96, 0.92, 0.85))