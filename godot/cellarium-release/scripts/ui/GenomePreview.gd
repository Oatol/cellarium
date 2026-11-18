extends PanelContainer
## 只读基因组发育预览（v0.23.0：真实模拟内核复刻）。
signal mode_selected(mode_index: int)
## Cell Lab 静态证据：Macro `GenomePreviewView` 是 GLSurfaceView，持 j4 渲染器 + 真实 SimulationWorld，
## 固定种子 1337，从单合子跑真实物理/分裂/代谢，程序化绘制真实细胞 + 分裂指示器 + 平移缩放选中回调
## （完整方法体见 analysis/细胞物理与外观 第32章；两版源码已全量反编译落地）。
##
## v0.23.0 起本项目改为真实复刻：用独立 `PreviewWorld` 内核按 Cell Lab 公式跑确定性发育，
## 每个 state 是一次真实分裂时刻的快照（真实位置/半径/朝向/分化槽/连接 + 分裂指示器），
## 不再是 dev_program 的静态派生。内核不写 CommandBus/field/hash/存档，主模拟确定性不受影响。

const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const PREVIEW_WORLD: Script = preload("res://scripts/core/data/PreviewWorld.gd")
## 复用运行时的 Cell Lab 弦工具：物理与渲染共享同一组圆-圆相交弦端点。
const CHORDS: RefCounted = preload("res://scripts/rendering/CellContactChords.gd")

const STEP_SECONDS: float = 0.75
const BASE_RADIUS: float = 15.0
const WORLD_SCALE: float = 1.6       # 预览内核坐标已是 14px=2r 标度，缩小以适配画布
const MAX_SIM_TICKS: int = 4000      # 预跑上限，防止参数异常导致无限模拟
const MAX_DIVISION_EVENTS: int = 8   # 最多记录 8 次分裂时刻（1→256 细胞）

var _world: RefCounted = null
var _pan: Vector2 = Vector2.ZERO
var _zoom: float = 1.0

## v0.21.0：对应 Cell Lab Macro `checkbox_show_split_indicators`。
## 预览里叠加分裂线（垂直分裂轴的切面）与分裂方向箭头（母→子）。纯绘制，不写模拟状态。
@export var show_split_indicators: bool = true

@export var canvas_path: NodePath = ^"Margin/VBox/Canvas"
@export var caption_path: NodePath = ^"Margin/VBox/Caption"
@export var play_button_path: NodePath = ^"Margin/VBox/Controls/PlayButton"
@export var prev_button_path: NodePath = ^"Margin/VBox/Controls/PrevButton"
@export var next_button_path: NodePath = ^"Margin/VBox/Controls/NextButton"
@export var timeline_path: NodePath = ^"Margin/VBox/Timeline/Slider"
@export var time_label_path: NodePath = ^"Margin/VBox/Timeline/TimeLabel"

var _canvas: Control = null
var _caption: Label = null
var _play_button: Button = null
var _timeline: HSlider = null
var _time_label: Label = null
var _program_signature: String = ""
var _states: Array[Dictionary] = []
var _cursor: int = 0
var _elapsed: float = 0.0
## v0.24.0：默认手动时间轴（暂停），需要动态观察时再点播放。复杂细胞逐时刻查看更高效。
var _playing: bool = false
var _syncing_timeline: bool = false

func _ready() -> void:
	_canvas = get_node_or_null(canvas_path) as Control
	_caption = get_node_or_null(caption_path) as Label
	_play_button = get_node_or_null(play_button_path) as Button
	var previous: Button = get_node_or_null(prev_button_path) as Button
	var following: Button = get_node_or_null(next_button_path) as Button
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
	if _play_button != null:
		_play_button.pressed.connect(_on_play_pressed)
	if previous != null:
		previous.pressed.connect(_step_back)
	if following != null:
		following.pressed.connect(_step_forward)
	_rebuild_states()

## 只读取 dev_program / 基因模式参数 / Macro 草案；相同参数重复调用不会重置播放进度。
## v0.15.0：基因模式按分裂质量阈值推导分裂序列，子代类型来自 child1–4（分裂即分化），
## 亲子连接来自黏附素 flag；不再有 LINK 指令阶段。
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

func get_state_count() -> int:
	return _states.size()

func get_cursor() -> int:
	return _cursor

func get_cell_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int(_states[state_index].get("cells", []).size())

## v0.15.0：供 SmokeTest / 外部只读检查预览里的黏附连接数量。
func get_link_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int((_states[state_index].get("links", []) as Array).size())

## v0.21.0：只读分裂指示器数量；供回归检查预览确实记录了分裂线与方向。
func get_split_count_at(state_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return 0
	return int((_states[state_index].get("splits", []) as Array).size())

## v0.21.0：只读某条分裂指示器的角度（弧度）。无记录返回 -INF。
func get_split_angle_at(state_index: int, split_index: int) -> float:
	if state_index < 0 or state_index >= _states.size():
		return -INF
	var splits: Array = _states[state_index].get("splits", []) as Array
	if split_index < 0 or split_index >= splits.size():
		return -INF
	return float((splits[split_index] as Dictionary).get("angle", -INF))

func get_cell_type_at(state_index: int, cell_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return -1
	var cells: Array = _states[state_index].get("cells", []) as Array
	if cell_index < 0 or cell_index >= cells.size():
		return -1
	return int((cells[cell_index] as Dictionary).get("type", -1))

## v0.17.0：预览细胞所属模式槽；旧模式/旧指令状态返回 -1（不可点击跳转）。
func get_mode_at(state_index: int, cell_index: int) -> int:
	if state_index < 0 or state_index >= _states.size():
		return -1
	var cells: Array = _states[state_index].get("cells", []) as Array
	if cell_index < 0 or cell_index >= cells.size():
		return -1
	return int((cells[cell_index] as Dictionary).get("mode", -1))

## v0.16.0：只读 caption，供 "预览显示表型" 的回归断言使用。
func get_state_caption_at(state_index: int) -> String:
	if state_index < 0 or state_index >= _states.size():
		return ""
	return str(_states[state_index].get("caption", ""))

func is_playing() -> bool:
	return _playing

func set_playing(value: bool) -> void:
	_playing = value
	_sync_caption()

func step_forward() -> void:
	_step_forward()

func step_back() -> void:
	_step_back()

func _process(delta: float) -> void:
	if not _playing or _states.size() <= 1:
		return
	_elapsed += delta
	if _elapsed >= STEP_SECONDS:
		_elapsed = 0.0
		if _cursor < _states.size() - 1:
			_cursor += 1
			_sync_caption()
			_sync_timeline()
		else:
			_playing = false  # 播放到末态即停，不循环回合子
			_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

## 手动拖动时间轴：直接跳到对应分裂时刻并暂停。
func _on_timeline_changed(value: float) -> void:
	if _syncing_timeline or _states.is_empty():
		return
	_playing = false
	_cursor = clampi(int(round(value)), 0, _states.size() - 1)
	_elapsed = 0.0
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _sync_timeline() -> void:
	if _timeline == null or _states.is_empty():
		return
	_syncing_timeline = true
	_timeline.max_value = float(_states.size() - 1)
	_timeline.value = float(_cursor)
	_syncing_timeline = false
	var tick: int = int((_states[_cursor] as Dictionary).get("tick", 0))
	var cells: int = int((_states[_cursor] as Dictionary).get("cells", []).size())
	if _time_label != null:
		_time_label.text = "t=%d · %d胞" % [tick, cells]

func _rebuild_states() -> void:
	# 无指令时用默认基因跑真实内核，给出 Cells Lab 式发育演示。
	var default_gene: Dictionary = GENOME_SCRIPT.call("normalized_mode", {}, 0)
	_run_simulation([default_gene], 0, 5)
	_sync_caption()

## v0.23.0 多模式：用真实 PreviewWorld 内核按 Cell Lab 公式模拟发育。
## 母细胞切 child1_mode、新细胞切 child2_mode（对应 Cell Lab cell.D=Gene.i / cell2.D=Gene.j）。
func _rebuild_mode_states(draft: Dictionary, raw_modes: Array) -> void:
	var modes: Array[Dictionary] = []
	for i in range(raw_modes.size()):
		modes.append(GENOME_SCRIPT.call("normalized_mode", raw_modes[i], i))
	if modes.is_empty():
		_rebuild_gene_states(draft)
		return
	# 确定初始模式槽：initial==true 者，否则槽 0（对应扫描 Gene.p）
	var initial_slot: int = 0
	for i in range(modes.size()):
		if bool((modes[i] as Dictionary).get("initial", false)):
			initial_slot = i
			break
	var global_divisions: int = clampi(int(round(float(draft.get("max_divisions", 3)))), 0, MAX_DIVISION_EVENTS)
	_run_simulation(modes, initial_slot, global_divisions)
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

## 用真实内核预跑发育，并把每次分裂时刻记录为一个快照 state。
func _run_simulation(genes: Array[Dictionary], initial_slot: int, max_events: int) -> void:
	_states.clear()
	_cursor = 0
	_elapsed = 0.0
	_world = PREVIEW_WORLD.new()
	_world.setup(genes, initial_slot)
	var initial_snapshot: Dictionary = _make_snapshot(0, "合子 · 真实模拟 · 种子1337", [])
	_states.append(initial_snapshot)
	var divisions: int = 0
	var accumulated_splits: Array[Dictionary] = []
	for _t in range(MAX_SIM_TICKS):
		_world.step()
		var splits: Array[Dictionary] = _world.consume_splits()
		if splits.is_empty():
			continue
		for entry in splits:
			accumulated_splits.append((entry as Dictionary).duplicate(true))
			divisions += 1
		var cells: Array[Dictionary] = _world.snapshot_cells()
		var caption: String = "分裂 %d · %d 细胞 · 阈值 %.2f · 种子1337" % [
			divisions, cells.size(), float((genes[clampi(initial_slot, 0, genes.size() - 1)] as Dictionary).get("division_mass", 0.05))]
		_states.append(_make_snapshot(divisions, caption, accumulated_splits.duplicate(true)))
		if divisions >= max_events:
			break
	_sync_caption()

func _make_snapshot(step_index: int, caption: String, splits: Array[Dictionary]) -> Dictionary:
	var cells: Array[Dictionary] = []
	if _world != null:
		for c in _world.snapshot_cells():
			var cell: Dictionary = (c as Dictionary).duplicate(true)
			cell["born"] = int(cell.get("index", -1)) >= maxi(0, _states.size() - 1)
			cells.append(cell)
	var links: Array[Dictionary] = []
	var tick: int = 0
	if _world != null:
		links = _world.snapshot_links()
		tick = int(_world.get_tick())
	return {"cells": cells, "links": links, "caption": caption, "opcode": 0, "splits": splits, "step": step_index, "tick": tick}

func _rebuild_gene_states(draft: Dictionary) -> void:
	# 用真实内核跑单基因模式；子代类型按 child1/child2 轮转（对应 Cell Lab 分化树 i/j）。
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
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

static func _preview_link_count(links: Array, cell_index: int) -> int:
	var count: int = 0
	for entry in links:
		var link: Dictionary = entry as Dictionary
		if int(link.get("a", -1)) == cell_index or int(link.get("b", -1)) == cell_index:
			count += 1
	return count

static func _preview_can_link(links: Array, a: int, b: int, limit: int) -> bool:
	if a == b or limit <= 0:
		return false
	if _preview_link_count(links, a) >= limit or _preview_link_count(links, b) >= limit:
		return false
	for entry in links:
		var link: Dictionary = entry as Dictionary
		if (int(link.get("a", -1)) == a and int(link.get("b", -1)) == b) \
			or (int(link.get("a", -1)) == b and int(link.get("b", -1)) == a):
			return false
	return true

func _rebuild_states_from(program: Array, cell_type: int) -> void:
	_states.clear()
	_cursor = 0
	_elapsed = 0.0
	var initial_cells: Array[Dictionary] = [{
		"index": 0, "pos": Vector2.ZERO, "type": cell_type, "parent": -1, "born": true,
	}]
	_append_state(initial_cells, [], "单细胞 · 合子（0）", -1)
	var splits: Array = []
	for i in range(program.size()):
		var instruction: Dictionary = program[i] as Dictionary
		var opcode: int = int(instruction.get("opcode", -1))
		var a: int = int(instruction.get("a", -1))
		var b: int = int(instruction.get("b", 0))
		var c: int = int(instruction.get("c", 0))
		var cells: Array[Dictionary] = []
		for source in _states[_states.size() - 1].get("cells", []):
			cells.append((source as Dictionary).duplicate(true))
		var links: Array = (_states[_states.size() - 1].get("links", []) as Array).duplicate(true)
		var caption: String = "指令 %d" % i
		if opcode == 0:
			var parent_index: int = clampi(a, 0, maxi(0, cells.size() - 1))
			var parent: Dictionary = cells[parent_index]
			var angle: float = TAU * float(b) / 256.0
			var separation: float = float(maxi(0, c))
			if separation <= 0.0:
				separation = 14.0
			var direction: Vector2 = Vector2(cos(angle), sin(angle))
			var split_center: Vector2 = parent.get("pos", Vector2.ZERO) as Vector2
			var child_pos: Vector2 = split_center + direction * separation * 0.5
			parent["pos"] = split_center - direction * separation * 0.5
			for cell in cells:
				cell["born"] = false
			cells.append({
				"index": cells.size(), "pos": child_pos, "type": int(parent.get("type", 0)),
				"parent": parent_index, "born": true,
			})
			caption = "DIVIDE %d · 母细胞 %d → %d 细胞" % [i, parent_index, cells.size()]
			splits.append({"pos": split_center, "angle": angle, "parent": parent_index, "child": cells.size() - 1})
		elif opcode == 1:
			if a >= 0 and a < cells.size():
				cells[a]["type"] = b
			for cell in cells:
				cell["born"] = false
			caption = "DIFFERENTIATE %d · 细胞 %d → 类型 %d" % [i, a, b]
		elif opcode == 2:
			# v0.15.0：LINK 已从新基因组移除；旧存档链接由黏附素语义派生，这里只保留状态不计连接。
			for cell in cells:
				cell["born"] = false
			caption = "旧存档 LINK %d（已由黏附素决定连接）" % i
		else:
			caption = "未知指令 %d（忽略）" % i
		_append_state(cells, links, caption, opcode, splits.duplicate(true))
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _append_state(cells: Array[Dictionary], links: Array, caption: String, opcode: int, splits: Array = []) -> void:
	_states.append({"cells": cells, "links": links, "caption": caption, "opcode": opcode, "splits": splits})

func _step_forward() -> void:
	if _states.is_empty():
		return
	_cursor = mini(_cursor + 1, _states.size() - 1)
	_elapsed = 0.0
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _step_back() -> void:
	if _states.is_empty():
		return
	_cursor = maxi(_cursor - 1, 0)
	_elapsed = 0.0
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _on_play_pressed() -> void:
	_playing = not _playing
	_sync_caption()

func _sync_caption() -> void:
	_sync_timeline()
	if _caption == null:
		return
	var caption: String = "" if _states.is_empty() else str(_states[_cursor].get("caption", ""))
	_caption.text = "%s · 时刻 %d/%d %s（拖动时间轴或点播放）" % [caption, _cursor + 1, _states.size(), "▶" if _playing else "⏸"]
	if _play_button != null:
		_play_button.text = "暂停" if _playing else "播放"

func _on_canvas_gui_input(event: InputEvent) -> void:
	if _canvas == null:
		return
	# 滚轮缩放（锚定鼠标位置，对应 Cell Lab 双指缩放 |log(scale)|<0.3 阈值）。
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
			_canvas.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
			_canvas.accept_event()
			return
		if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_dragging = true
				_drag_last = mb.position
			else:
				_dragging = false
			_canvas.accept_event()
			return
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
	var new_zoom: float = clampf(_zoom * factor, 0.4, 4.0)
	if abs(log(new_zoom / old_zoom)) > 0.3:
		new_zoom = old_zoom * exp(0.3 if factor > 1.0 else -0.3)
		new_zoom = clampf(new_zoom, 0.4, 4.0)
	var center: Vector2 = _canvas.size * 0.5
	var world_anchor: Vector2 = (anchor - center - _pan) / (WORLD_SCALE * old_zoom)
	_pan = anchor - center - world_anchor * WORLD_SCALE * new_zoom
	_zoom = new_zoom
	_canvas.queue_redraw()

func _select_cell_at(local_position: Vector2) -> void:
	if _states.is_empty():
		return
	var cells: Array = (_states[_cursor] as Dictionary).get("cells", []) as Array
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
	var cell_radius_px: float = float((cells[best_index] as Dictionary).get("radius", 7.0)) * WORLD_SCALE * _zoom
	if best_distance > cell_radius_px + 8.0:
		return
	var mode_index: int = int((cells[best_index] as Dictionary).get("mode", -1))
	if mode_index >= 0:
		mode_selected.emit(mode_index)
		_canvas.accept_event()

func _to_screen(world_pos: Vector2) -> Vector2:
	return _canvas.size * 0.5 + _pan + world_pos * WORLD_SCALE * _zoom

func _on_canvas_draw() -> void:
	if _canvas == null or _states.is_empty():
		return
	var state: Dictionary = _states[_cursor]
	var cells: Array = state.get("cells", []) as Array
	var links: Array = state.get("links", []) as Array
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
	var progress: float = clampf(_elapsed / STEP_SECONDS, 0.0, 1.0)
	var newest_index: int = maxi(0, _states.size() - 1)
	for item in cells:
		var cell: Dictionary = item as Dictionary
		var pos: Vector2 = _to_screen(cell.get("pos", Vector2.ZERO))
		var appear: float = clampf(progress * 2.0, 0.05, 1.0) if bool(cell.get("born", false)) else 1.0
		# 半径来自真实内核（Cell Lab 半径是能量的低通结果，刚分裂子细胞偏小）。
		var world_radius: float = float(cell.get("radius", 7.0))
		var radius: float = world_radius * WORLD_SCALE * _zoom * appear
		var type_id: int = int(cell.get("type", 0))
		var fill: Color = (VISUALS.call("role_color", type_id) as Color)
		fill.a = 0.55 * appear
		var membrane: Color = (VISUALS.call("accent_color", type_id) as Color)
		membrane.a = appear
		_draw_membrane(cell, pos, radius, world_radius, fill, membrane, appear)
	# Cell Lab j4.I() 逐方法等价的分裂指示器：子代将出现的位置画圆点。
	if not show_split_indicators:
		return
	var splits: Array = state.get("splits", []) as Array
	for entry in splits:
		var indicator: Dictionary = entry as Dictionary
		var split_center: Vector2 = _to_screen(indicator.get("pos", Vector2.ZERO))
		var angle: float = float(indicator.get("angle", 0.0))
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var world_radius: float = float(indicator.get("radius", 7.0))
		var r_norm: float = clampf(world_radius / 14.0, 0.1, 1.0)
		# Cell Lab: fMax = max(0.006, q0*0.27)（归一化半径），f2 = q0 + 0.42*fMax
		var f_max: float = maxf(0.006, r_norm * 0.27)
		var f2: float = r_norm + 0.42 * f_max
		var ratio: float = clampf(float(indicator.get("ratio", 0.5)), 0.1, 0.9)
		var f3: float = f2 * 2.0
		var d1: float = (1.0 - ratio) * f3
		var d2: float = ratio * f3
		var dot_radius_px: float = f_max * 14.0 * WORLD_SCALE * _zoom
		var gene_slot: int = int(indicator.get("gene_slot", 0))
		var gene: Dictionary = _world.get_gene(gene_slot) if _world != null else {}
		var is_zygote: bool = bool(indicator.get("zygote", false))
		# 非合子：2 个圆点（母侧/子侧）；合子：4 个（child1..4）。
		var p_child: Vector2 = split_center + dir * d2 * 14.0 * WORLD_SCALE * _zoom
		var p_mother: Vector2 = split_center - dir * d1 * 14.0 * WORLD_SCALE * _zoom
		var child_color: Color = _gene_color(gene, "child2_mode", 1)
		var mother_color: Color = _gene_color(gene, "child1_mode", 0)
		_canvas.draw_circle(p_child, dot_radius_px, Color(child_color.r, child_color.g, child_color.b, 0.9))
		_canvas.draw_circle(p_mother, dot_radius_px, Color(mother_color.r, mother_color.g, mother_color.b, 0.9))
		if is_zygote:
			var axis2: float = TAU * clampf(float(gene.get("split_angle2", 0.25)), 0.0, 1.0)
			var dir2: Vector2 = Vector2(cos(axis2), sin(axis2))
			var f10: float = 1.5 * f_max
			for k in range(4):
				var gm: Dictionary = _world.get_gene(k) if _world != null else {}
				var gcol: Color = Color(float(gm.get("color_r", 0.36)), float(gm.get("color_g", 0.88)), float(gm.get("color_b", 0.75)))
				var sign: float = 1.0 if k % 2 == 0 else -1.0
				var dist: float = (1.0 - ratio) * f10 if k < 2 else ratio * f10
				var pp: Vector2 = split_center + dir2 * dist * 14.0 * WORLD_SCALE * _zoom * sign
				_canvas.draw_circle(pp, dot_radius_px * 0.8, Color(gcol.r, gcol.g, gcol.b, 0.85))

## Cell Lab a(FFFF)/d(int) 复刻：物理与渲染共享同一组圆-圆相交弦端点。
## 有弦时用 CellContactChords 把解析圆按公共弦切平（细胞膜贴合），无弦时用正圆。
func _draw_membrane(cell: Dictionary, screen_pos: Vector2, radius: float, world_radius: float,
		fill: Color, membrane: Color, appear: float) -> void:
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
		# 膜：折线闭合
		var closed: PackedVector2Array = world_poly.duplicate()
		closed.append(world_poly[0])
		_canvas.draw_polyline(closed, membrane, 2.0, true)
	else:
		_canvas.draw_circle(screen_pos, radius, fill)
		_canvas.draw_arc(screen_pos, radius, 0.0, TAU, 32, membrane, 2.0, true)
	# 细胞核 CELL Lab NR=0.25
	_canvas.draw_circle(screen_pos, radius * 0.25, Color(0.9, 0.96, 0.92, 0.85 * appear))

func _gene_color(gene: Dictionary, mode_key: String, fallback: int) -> Color:
	var slot: int = clampi(int(gene.get(mode_key, fallback)), 0, 7)
	var gm: Dictionary = _world.get_gene(slot) if _world != null else {}
	if gm.is_empty():
		return (VISUALS.call("role_color", fallback) as Color)
	return Color(float(gm.get("color_r", 0.36)), float(gm.get("color_g", 0.88)), float(gm.get("color_b", 0.75)))
