extends PanelContainer
## 只读基因组发育预览（v0.13.1）。
signal mode_selected(mode_index: int)
## 静态证据：Macro `GenomePreviewView` 是 GLSurfaceView，持有 j4 渲染器与 SimulationWorld/Gene[]，
## 用 FloatBuffer/ShortBuffer 程序化绘制真实细胞，支持触摸平移/缩放/选中回调（REA 证据见分析文档 §22）。
## 本项目派生实现：不跑第二套模拟、不写 CommandBus/field/hash；只把 draft.dev_program 逐条翻译成
## 可视化状态（分裂/分化/连接），用于「看见自己编辑的细胞如何发育」。

const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")

const STEP_SECONDS: float = 0.75
const BASE_RADIUS: float = 15.0
const WORLD_SCALE: float = 5.0

@export var canvas_path: NodePath = ^"Margin/VBox/Canvas"
@export var caption_path: NodePath = ^"Margin/VBox/Caption"
@export var play_button_path: NodePath = ^"Margin/VBox/Controls/PlayButton"
@export var prev_button_path: NodePath = ^"Margin/VBox/Controls/PrevButton"
@export var next_button_path: NodePath = ^"Margin/VBox/Controls/NextButton"

var _canvas: Control = null
var _caption: Label = null
var _play_button: Button = null
var _program_signature: String = ""
var _states: Array[Dictionary] = []
var _cursor: int = 0
var _elapsed: float = 0.0
var _playing: bool = true

func _ready() -> void:
	_canvas = get_node_or_null(canvas_path) as Control
	_caption = get_node_or_null(caption_path) as Label
	_play_button = get_node_or_null(play_button_path) as Button
	var previous: Button = get_node_or_null(prev_button_path) as Button
	var following: Button = get_node_or_null(next_button_path) as Button
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
		_cursor = (_cursor + 1) % _states.size()
		_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _rebuild_states() -> void:
	_rebuild_states_from([], 0)

## v0.17.0 多模式：只读派生「当前模式 → 两个子代模式」的分裂序列。
## 与运行时同口径：母细胞索引作为子代 1，新细胞为子代 2；逐模式层数限制分裂。
func _rebuild_mode_states(draft: Dictionary, raw_modes: Array) -> void:
	_states.clear()
	_cursor = 0
	_elapsed = 0.0
	var modes: Array[Dictionary] = []
	for i in range(raw_modes.size()):
		modes.append(GENOME_SCRIPT.call("normalized_mode", raw_modes[i], i))
	if modes.is_empty():
		_rebuild_gene_states(draft)
		return
	var global_divisions: int = clampi(int(round(float(draft.get("max_divisions", 3)))), 0, 8)
	var root: Dictionary = modes[0]
	var initial: Array[Dictionary] = [{
		"index": 0, "pos": Vector2.ZERO, "type": int(root.get("cell_type", 0)),
		"parent": -1, "born": true, "mode": 0, "depth": 0,
	}]
	_append_state(initial, [], "%s · 阈值 %.2f · 传递率 %.2f" % [
		str(root.get("name", "M1")), float(root.get("division_mass", 0.05)), float(root.get("transfer_rate", 0.12))], 0)
	var links: Array = []
	for _division in range(global_divisions):
		var previous: Array[Dictionary] = _states[_states.size() - 1].get("cells", []) as Array[Dictionary]
		var cells: Array[Dictionary] = []
		for source in previous:
			cells.append((source as Dictionary).duplicate(true))
		var parent_index: int = -1
		var parent_mode: Dictionary = {}
		var parent_mode_index: int = -1
		for cell_index in range(cells.size()):
			var cell: Dictionary = cells[cell_index]
			var candidate_index: int = clampi(int(cell.get("mode", 0)), 0, modes.size() - 1)
			var candidate: Dictionary = modes[candidate_index]
			var depth: int = int(cell.get("depth", 0))
			if depth < int(candidate.get("max_divisions", 0)):
				parent_index = cell_index
				parent_mode = candidate
				parent_mode_index = candidate_index
				break
		if parent_index < 0:
			break
		var parent: Dictionary = cells[parent_index]
		var child1_mode: int = clampi(int(parent_mode.get("child1_mode", 0)), 0, modes.size() - 1)
		var child2_mode: int = clampi(int(parent_mode.get("child2_mode", 0)), 0, modes.size() - 1)
		var mode1: Dictionary = modes[child1_mode]
		var mode2: Dictionary = modes[child2_mode]
		var child1_angle: float = clampf(float(parent_mode.get("child1_angle", 0.0)), 0.0, 1.0)
		var child2_angle: float = clampf(float(parent_mode.get("child2_angle", 0.25)), 0.0, 1.0)
		if bool(parent_mode.get("child2_mirror", false)):
			child2_angle = fposmod(-child1_angle, 1.0)
		var angle: float = TAU * child2_angle
		var separation: float = 14.0 * maxf(0.5, float(parent_mode.get("cell_size", 1.0)))
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		parent["pos"] = (parent.get("pos", Vector2.ZERO) as Vector2) - direction * separation * 0.5
		parent["type"] = int(mode1.get("cell_type", 0))
		parent["mode"] = child1_mode
		parent["depth"] = int(parent.get("depth", 0)) + 1 if child1_mode == parent_mode_index else 0
		parent["born"] = false
		for cell in cells:
			if int((cell as Dictionary).get("index", -1)) != parent_index:
				(cell as Dictionary)["born"] = false
		var child_index: int = cells.size()
		cells.append({
			"index": child_index,
			"pos": (parent.get("pos", Vector2.ZERO) as Vector2) + direction * separation,
			"type": int(mode2.get("cell_type", 0)),
			"parent": parent_index, "born": true,
			"mode": child2_mode, "depth": 0,
		})
		var link_limit: int = clampi(int(mode1.get("max_connections", 4)), 0, 16)
		if (bool(parent_mode.get("child1_glue", false)) or bool(parent_mode.get("child2_glue", true))) \
			and _preview_can_link(links, parent_index, child_index, link_limit):
			links.append({"a": parent_index, "b": child_index, "rest": separation})
		var min_links: int = clampi(int(mode1.get("min_connections", 0)), 0, link_limit)
		if min_links > 0:
			for peer_index in range(cells.size() - 1):
				if peer_index == child_index or not _preview_can_link(links, child_index, peer_index, link_limit):
					continue
				links.append({"a": child_index, "b": peer_index, "rest": separation})
				if _preview_link_count(links, child_index) >= min_links:
					break
		var caption: String = "%s → %s / %s · 类型 %d → %d/%d · 连接 %d" % [
			str(parent_mode.get("name", "?")), str(mode1.get("name", "?")), str(mode2.get("name", "?")),
			int(parent.get("type", 0)), int(mode1.get("cell_type", 0)), int(mode2.get("cell_type", 0)), links.size()]
		_append_state(cells, links.duplicate(true), caption, 0)
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

## v0.15.0 基因模式（无 modes）：保留旧派生逻辑，供旧存档/旧命令回放。
func _rebuild_gene_states(draft: Dictionary) -> void:
	_states.clear()
	_cursor = 0
	_elapsed = 0.0
	var cell_type: int = clampi(int(draft.get("cell_type", 0)), 0, 255)
	var mass: float = float(draft.get("division_mass", 1.0))
	var divisions: int = clampi(int(round(float(draft.get("max_divisions", 3)))), 0, 8)
	var glue: bool = bool(draft.get("make_glue", false))
	var cell_size: float = clampf(float(draft.get("cell_size", 1.0)), 0.5, 2.0)
	var max_links: int = clampi(int(round(float(draft.get("max_connections", 4)))), 0, 16)
	var min_links: int = clampi(int(round(float(draft.get("min_connections", 0)))), 0, max_links)
	var rgb_text: String = "RGB(%.2f,%.2f,%.2f)" % [
		float(draft.get("color_r", 0.36)), float(draft.get("color_g", 0.88)), float(draft.get("color_b", 0.75))]
	var initial_cells: Array[Dictionary] = [{
		"index": 0, "pos": Vector2.ZERO, "type": cell_type, "parent": -1, "born": true,
	}]
	_append_state(initial_cells, [], "合子 · 阈值 %.2f · 大小 %.2f · %s" % [mass, cell_size, rgb_text], 0)
	var links: Array = []
	for division_index in range(divisions):
		var cells: Array[Dictionary] = []
		for source in _states[_states.size() - 1].get("cells", []):
			cells.append((source as Dictionary).duplicate(true))
		var parent_index: int = 0
		var parent: Dictionary = cells[parent_index]
		var child_type: int = clampi(int(draft.get("child%d" % (division_index + 1), 0)), 0, 255)
		var angle: float = TAU * clampf(float(draft.get("child%d_angle" % (division_index + 1), 0.0)), 0.0, 1.0)
		var separation: float = 14.0 * cell_size
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var child_pos: Vector2 = (parent.get("pos", Vector2.ZERO) as Vector2) + direction * separation * 0.5
		parent["pos"] = (parent.get("pos", Vector2.ZERO) as Vector2) - direction * separation * 0.5
		for cell in cells:
			cell["born"] = false
		var child_index: int = cells.size()
		cells.append({
			"index": child_index, "pos": child_pos, "type": child_type,
			"parent": parent_index, "born": true,
		})
		# v0.16.0：连接上限阻断，最小连接数按索引升序补连（与运行时同口径的只读派生）。
		if glue and _preview_can_link(links, parent_index, child_index, max_links):
			links.append({"a": parent_index, "b": child_index, "rest": separation})
		if min_links > 0:
			for peer_index in range(cells.size() - 1):
				if peer_index == child_index:
					continue
				if not _preview_can_link(links, child_index, peer_index, max_links):
					continue
				links.append({"a": child_index, "b": peer_index, "rest": separation})
				if _preview_link_count(links, child_index) >= min_links:
					break
		var caption: String = "分裂 %d · 质量 %.2f · 子代类型 %d · 连接 %d · %s" % [
			division_index + 1, mass, child_type, links.size(), rgb_text]
		_append_state(cells, links.duplicate(true), caption, 0)
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
			var child_pos: Vector2 = (parent.get("pos", Vector2.ZERO) as Vector2) + direction * separation * 0.5
			parent["pos"] = (parent.get("pos", Vector2.ZERO) as Vector2) - direction * separation * 0.5
			for cell in cells:
				cell["born"] = false
			cells.append({
				"index": cells.size(), "pos": child_pos, "type": int(parent.get("type", 0)),
				"parent": parent_index, "born": true,
			})
			caption = "DIVIDE %d · 母细胞 %d → %d 细胞" % [i, parent_index, cells.size()]
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
		_append_state(cells, links, caption, opcode)
	_sync_caption()
	if _canvas != null:
		_canvas.queue_redraw()

func _append_state(cells: Array[Dictionary], links: Array, caption: String, opcode: int) -> void:
	_states.append({"cells": cells, "links": links, "caption": caption, "opcode": opcode})

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
	if _caption == null:
		return
	var caption: String = "" if _states.is_empty() else str(_states[_cursor].get("caption", ""))
	_caption.text = "%s · 状态 %d/%d %s" % [caption, _cursor + 1, _states.size(), "▶" if _playing else "⏸"]
	if _play_button != null:
		_play_button.text = "暂停" if _playing else "播放"

func _on_canvas_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed \
		or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if _states.is_empty() or _canvas == null:
		return
	var local_position: Vector2 = (event as InputEventMouseButton).position
	var center: Vector2 = _canvas.size * 0.5
	var cells: Array = (_states[_cursor] as Dictionary).get("cells", []) as Array
	var best_index: int = -1
	var best_distance: float = INF
	for cell_index in range(cells.size()):
		var cell: Dictionary = cells[cell_index] as Dictionary
		var cell_position: Vector2 = center + (cell.get("pos", Vector2.ZERO) as Vector2) * WORLD_SCALE
		var distance_value: float = local_position.distance_to(cell_position)
		if distance_value < best_distance:
			best_distance = distance_value
			best_index = cell_index
	if best_index < 0 or best_distance > BASE_RADIUS + 8.0:
		return
	var mode_index: int = int((cells[best_index] as Dictionary).get("mode", -1))
	if mode_index >= 0:
		mode_selected.emit(mode_index)
		_canvas.accept_event()

func _on_canvas_draw() -> void:
	if _canvas == null or _states.is_empty():
		return
	var state: Dictionary = _states[_cursor]
	var center: Vector2 = _canvas.size * 0.5
	var cells: Array = state.get("cells", []) as Array
	var links: Array = state.get("links", []) as Array
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.02, 0.06, 0.055, 1.0))
	for link in links:
		var pair: Dictionary = link as Dictionary
		var a_index: int = int(pair.get("a", -1))
		var b_index: int = int(pair.get("b", -1))
		if a_index < 0 or b_index < 0 or a_index >= cells.size() or b_index >= cells.size():
			continue
		var a_pos: Vector2 = center + (cells[a_index] as Dictionary).get("pos", Vector2.ZERO) * WORLD_SCALE
		var b_pos: Vector2 = center + (cells[b_index] as Dictionary).get("pos", Vector2.ZERO) * WORLD_SCALE
		_canvas.draw_line(a_pos, b_pos, Color(0.36, 0.88, 0.75, 0.85), 2.0)
	var progress: float = clampf(_elapsed / STEP_SECONDS, 0.0, 1.0)
	for item in cells:
		var cell: Dictionary = item as Dictionary
		var pos: Vector2 = center + (cell.get("pos", Vector2.ZERO) as Vector2) * WORLD_SCALE
		var appear: float = clampf(progress * 2.0, 0.05, 1.0) if bool(cell.get("born", false)) else 1.0
		var radius: float = BASE_RADIUS * appear
		var fill: Color = (VISUALS.call("role_color", int(cell.get("type", 0))) as Color)
		fill.a = 0.55 * appear
		_canvas.draw_circle(pos, radius, fill)
		var membrane: Color = (VISUALS.call("accent_color", int(cell.get("type", 0))) as Color)
		membrane.a = appear
		_canvas.draw_arc(pos, radius, 0.0, TAU, 32, membrane, 2.0, true)
		_canvas.draw_circle(pos, radius * 0.28, Color(0.9, 0.96, 0.92, 0.85 * appear))
