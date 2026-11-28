extends Control
## HUD 控制器：把 ToolCatalog 的数据实例化为 Godot Control 节点（Button/HSlider），
## 绑定 pressed / value_changed → CommandBus.enqueue 或视图控制。
## 场景骨架（容器 Panel/HBox/VBox/Label）在 main.tscn 声明，本脚本只填充重复项与承载交互。
## 用词对照 analysis/CellLab_界面与实验条件_词条证据.md。

const CATALOG: RefCounted = preload("res://scripts/ui/ToolCatalog.gd")
const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")
const CODEC: RefCounted = preload("res://scripts/core/data/GenomeCodec.gd")
const CELL_VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const PANEL_CHROME: RefCounted = preload("res://scripts/ui/PanelChrome.gd")
const FrameProfiler: RefCounted = preload("res://scripts/system/FrameProfiler.gd")

## 这些键改动后需要重算环境场；食物投放参数只影响未来 tick 的源项。
const ENVIRONMENT_FIELD_KEYS: Array[String] = [
	"nutrient_density", "temperature", "oxygen_fraction",
	"light_intensity", "light_source_mode", "light_range", "light_angle_deg", "light_falloff",
]

@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var environment_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var camera_path: NodePath = ^"../../Camera2D"
@export var mode_row_path: NodePath = ^"TopBar/ModeRow"
@export var tool_groups_path: NodePath = ^"ToolDock/ToolGroups"
@export var substrate_rows_path: NodePath = ^"SubstratePanel/Panel/EnvironmentScroll/SubstrateRows"
@export var lens_row_path: NodePath = ^"MicroscopePanel/Panel/Content/LensRow"
@export var view_row_path: NodePath = ^"MicroscopePanel/Panel/Content/ViewRow"
@export var feedback_path: NodePath = ^"FeedbackLabel"
@export var perf_label_path: NodePath = ^"PerfLabel"
@export var speed_slider_path: NodePath = ^"SpeedPanel/Panel/SpeedRow/SpeedSlider"
@export var speed_spin_path: NodePath = ^"SpeedPanel/Panel/SpeedRow/SpeedSpin"
@export var speed_lod_path: NodePath = ^"SpeedPanel/Panel/SpeedRow/LodLabel"
@export var cell_editor_path: NodePath = ^"CellEditorPanel"
@export var cell_editor_button_path: NodePath = ^"CellEditorButton"

signal tool_changed(tool: Dictionary)
signal mode_changed(mode: Dictionary)

var command_bus: Node = null
var tick_core: Node = null
var environment_manager: Node = null
var organism_manager: Node = null
var camera: Camera2D = null

var _tools: Array[Dictionary] = []
var _modes: Array[Dictionary] = []
var _substrate: Array[Dictionary] = []
var _lenses: Array[String] = []
var _selected_index: int = 0
var _selected_mode: int = 1
var _selected_lens: int = 0
var _tool_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _lens_buttons: Array[Button] = []
var _value_labels: Array[Label] = []
var _feedback_label: Label = null
var _tint: ColorRect = null
var _speed_slider: HSlider = null
var _speed_spin: SpinBox = null
var _speed_lod: Label = null
var _cell_editor: Control = null
var _draft_genome: RefCounted = null
var _draft_type_id: int = 0
var _syncing_speed: bool = false
var _speed_capped: bool = false
## 面板装饰与顶栏开关：每个面板一个 chrome + 一个 toggle，关闭后可重新打开。
var _panel_chromes: Dictionary = {}
var _panel_toggles: Dictionary = {}
var _panel_default_visible: Dictionary = {}
## 对账缓存：避免 _process 每帧 get_node_or_null 做字符串路径查找。
var _reconcile_targets: Array = []
## 光场可视化层（阶段 UI 调整）。
var _field_layer: Node = null
var _food_layer: Node = null
var _selection_layer: Node = null
## FPS/TPS 仪表：真实帧/ tick 计数，1 秒窗口；不在模拟状态内，不进 hash。
var _perf_label: Label = null
var _fps_frames: int = 0
var _tps_ticks: int = 0
var _perf_elapsed: float = 0.0
var _last_tick_index: int = 0

func _ready() -> void:
	command_bus = get_node_or_null(command_bus_path)
	tick_core = get_node_or_null(tick_core_path)
	environment_manager = get_node_or_null(environment_path)
	organism_manager = get_node_or_null(organism_manager_path)
	camera = get_node_or_null(camera_path) as Camera2D
	_feedback_label = get_node_or_null(feedback_path) as Label
	_perf_label = get_node_or_null(perf_label_path) as Label
	_tools = CATALOG.call("tools")
	_modes = CATALOG.call("modes")
	_substrate = CATALOG.call("substrate")
	_lenses = CATALOG.call("lenses")
	_build_modes()
	_build_tools()
	_build_substrate()
	_build_lenses()
	_build_view_buttons()
	_build_tint()
	_build_injector()
	_register_speed_controls()
	_register_cell_editor()
	_register_view_layers()
	# chrome 必须在所有面板自己的 _ready() 之后安装：AnalysisPanel / DevEditorPanel
	# 在 _ready 里 add_child 内容，若 chrome 先装进空面板，内容会成为 ChromeRoot 的兄弟节点，
	# 既覆盖标题栏（看起来像没移到顶部），又抢走图钉/关闭按钮的鼠标事件。
	call_deferred("_build_panel_chrome")
	_build_panel_toggles()
	_register_semantic_ids()
	_apply_mode(_selected_mode)
	print("[GameHUD] ready tools=", _tools.size(), " modes=", _modes.size(), " substrate=", _substrate.size(), " semantic=", SEMANTIC.call("count"))

func _process(delta: float) -> void:
	_update_perf_readout(delta)
	## 顶栏开关与各面板内部关闭按钮状态对账；节点引用在构建开关时缓存，避免每帧路径查找。
	for entry in _reconcile_targets:
		var button: Button = entry[0] as Button
		var node: Node = entry[1] as Node
		if button != null and node != null and button.is_pressed() != node.visible:
			button.set_pressed_no_signal(node.visible)

## FPS = 实际渲染帧数/秒；TPS = TickCore 实际推进 tick 数/秒（非 speed_scale × 60）。
func _update_perf_readout(delta: float) -> void:
	# v0.39.0：把真实帧间隔喂给分段 profiler（含 GPU/合成），用于 C 路线定位。
	# 必须在 _perf_label 空判断之前，避免 HUD 尚未装配时漏采样导致分段口径失真。
	FrameProfiler.note_frame(delta)
	if _perf_label == null:
		return
	_fps_frames += 1
	var current_tick: int = int(tick_core.get("tick_index")) if tick_core != null else 0
	if current_tick > _last_tick_index:
		_tps_ticks += current_tick - _last_tick_index
	_last_tick_index = current_tick
	_perf_elapsed += delta
	if _perf_elapsed < 0.5:
		return
	var window: float = _perf_elapsed
	_perf_elapsed = 0.0
	var fps: int = int(round(float(_fps_frames) / window))
	var tps: int = int(round(float(_tps_ticks) / window))
	_fps_frames = 0
	_tps_ticks = 0
	var speed_text: String = str(float(tick_core.get("speed_scale"))) if tick_core != null else "?"
	var line1: String = "FPS %d | TPS %d | 倍速 %s× | LOD %d" % [
		fps, tps, speed_text,
		int(tick_core.call("get_lod_level")) if tick_core != null and tick_core.has_method("get_lod_level") else 0,
	]
	# v0.39.0 C 路线：只展示可交叉验证的口径。
	# FrameProfiler 的 Time.get_ticks_usec 分段在 GUI/调试器下的读数与 TPS 不自洽，
	# 因此不再上屏；保留采样供离线分析，结论以帧间隔 + 引擎 process monitor + draw call 为准。
	var rep: Dictionary = FrameProfiler.report()
	var frame_us: float = float(rep.get("frame_avg_us", 0.0))
	var frame_calls: int = int(rep.get("frame_calls", 0))
	var engine_process_us: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000000.0
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# v0.51.0：`size()` 是数组长度（含死亡槽位，只增不减），上屏必须用存活数。
	var cell_count: int = int((organism_manager.get("cells") as RefCounted).call("alive_count")) if organism_manager != null and organism_manager.get("cells") != null else -1
	_perf_label.text = "%s\nFRAME %.1fms avg/%df | CPU %.2fms | draw %d | cells %d" % [
		line1, frame_us / 1000.0, frame_calls,
		engine_process_us / 1000.0, draw_calls, cell_count,
	]

## 光场/选区可视化层引用；光场默认可见，可在顶栏关闭。
func _register_view_layers() -> void:
	_field_layer = get_node_or_null("../../DishView/FieldLayer")
	_food_layer = get_node_or_null("../../DishView/FoodLayer")
	_selection_layer = get_node_or_null("../../DishView/SelectionLayer")
	# 光场默认可见：像 Cell Lab 一样开机就能看到照明覆盖范围，顶栏「光场」可关。
	if _field_layer != null and _field_layer.has_method("set_enabled"):
		_field_layer.call("set_enabled", true)
	if _food_layer != null and _food_layer.has_method("set_enabled"):
		_food_layer.call("set_enabled", true)

## 面板装饰系统：给每个面板加可拖动标题栏 + 图钉（可选）+ 关闭按钮。
## 面板自身 _ready 已缓存其子节点引用，这里重挂内容节点不会影响它们。
func _build_panel_chrome() -> void:
	var definitions: Array = [
		["ToolDock", "工具 · TOOLS", false],
		["SubstratePanel", "环境设置 · ENVIRONMENT", false],
		["MicroscopePanel", "显微镜 · MICROSCOPE", false],
		["SpeedPanel", "倍速 · SPEED", false],
		["CellEditorPanel", "细胞编辑 · CELL EDITOR", false],
		["../AnalysisPanel", "报告/诊断 · ANALYSIS", true],
		["../Minimap", "小地图 · MINIMAP", false],
	]
	for definition in definitions:
		var node_path: String = str(definition[0])
		var node: Node = get_node_or_null(node_path)
		if node == null or not (node is PanelContainer):
			continue
		var panel: PanelContainer = node as PanelContainer
		var chrome: RefCounted = (PANEL_CHROME as RefCounted).new(panel, str(definition[1]), bool(definition[2]))
		if not bool(chrome.call("install")):
			continue
		_panel_chromes[node_path] = chrome
		_panel_default_visible[node_path] = panel.visible
		var on_close: Callable = Callable(self, "_on_panel_close").bind(node_path)
		chrome.connect("close_requested", on_close)

func _build_panel_toggles() -> void:
	var row: Node = get_node_or_null(mode_row_path)
	if row == null:
		return
	var separator: Label = Label.new()
	separator.text = "│ 面板"
	separator.add_theme_font_size_override("font_size", 11)
	row.add_child(separator)
	var definitions: Array = [
		["工具", "ToolDock"],
		["环境设置", "SubstratePanel"],
		["显微镜", "MicroscopePanel"],
		["倍速", "SpeedPanel"],
		["分析", "../AnalysisPanel"],
		["小地图", "../Minimap"],
		["细胞编辑", "CellEditorPanel"],
		["光场", "@field"],
		["食物", "@food"],
	]
	for definition in definitions:
		var button: Button = _make_button(str(definition[0]), "开/关面板 · " + str(definition[1]))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(66, 26)
		button.set_meta("target", str(definition[1]))
		button.toggled.connect(Callable(self, "_on_panel_toggle").bind(button))
		var target_path: String = str(definition[1])
		var target: Node = get_node_or_null(target_path)
		var initial_pressed: bool = target != null and target.visible
		if target_path == "@field" and _field_layer != null and _field_layer.has_method("is_enabled"):
			initial_pressed = bool(_field_layer.call("is_enabled"))
		elif target_path == "@food" and _food_layer != null and _food_layer.has_method("is_enabled"):
			initial_pressed = bool(_food_layer.call("is_enabled"))
		button.set_pressed_no_signal(initial_pressed)
		_panel_toggles[target_path] = button
		if target_path != "@field" and target_path != "@food" and target != null:
			_reconcile_targets.append([button, target])
		row.add_child(button)

func _on_panel_toggle(pressed: bool, button: Button) -> void:
	var target_path: String = str(button.get_meta("target", ""))
	if target_path == "@field":
		if _field_layer != null and _field_layer.has_method("set_enabled"):
			_field_layer.call("set_enabled", pressed)
			_set_feedback("光场可视化 · " + ("开" if pressed else "关") + " · 直接显示光照场强度")
		return
	if target_path == "@food":
		if _food_layer != null and _food_layer.has_method("set_enabled"):
			_food_layer.call("set_enabled", pressed)
			_set_feedback("食物可视化 · " + ("开" if pressed else "关") + " · 显示营养团块亮点")
		return
	var node: Node = get_node_or_null(target_path)
	if node == null:
		return
	node.visible = pressed
	# 生态报告等面板有 _visible_state 内部状态，保持同步避免 R 键/图钉逻辑失配。
	if node.has_method("set_visible_state"):
		node.call("set_visible_state", pressed)

func _on_panel_close(panel_path: String) -> void:
	var node: Node = get_node_or_null(panel_path)
	# 生态报告等面板有内部 _visible_state，关闭按钮必须同步，否则 R 键状态会失配。
	if node != null and node.has_method("set_visible_state"):
		node.call("set_visible_state", false)
	var button: Button = _panel_toggles.get(panel_path, null) as Button
	if button != null:
		button.set_pressed_no_signal(false)
	_set_feedback("面板已关闭 · 可用顶栏开关重新打开")

func _register_semantic_ids() -> void:
	# 场景可能被测试/热重载反复实例化：先清掉本实例命名空间下的旧注册再重注册。
	SEMANTIC.call("clear_prefix", "ui://sim/")
	for i in range(_mode_buttons.size()):
		_mode_buttons[i].set_meta("semantic_id", "ui://sim/mode/%d" % i)
		SEMANTIC.call("register", "ui://sim/mode/%d" % i, _mode_buttons[i])
	for tool in _tools:
		var tool_id: String = str(tool.get("id", ""))
		for button in _tool_buttons:
			if int(button.get_meta("index", -1)) == _tools.find(tool):
				button.set_meta("semantic_id", "ui://sim/tool/%s" % tool_id)
				SEMANTIC.call("register", "ui://sim/tool/%s" % tool_id, button)
				break
	for i in range(_lens_buttons.size()):
		_lens_buttons[i].set_meta("semantic_id", "ui://sim/lens/%d" % i)
		SEMANTIC.call("register", "ui://sim/lens/%d" % i, _lens_buttons[i])
	if _speed_slider != null:
		_speed_slider.set_meta("semantic_id", "ui://sim/speed/slider")
		SEMANTIC.call("register", "ui://sim/speed/slider", _speed_slider)
	if _speed_spin != null:
		_speed_spin.set_meta("semantic_id", "ui://sim/speed/input")
		SEMANTIC.call("register", "ui://sim/speed/input", _speed_spin)
	var editor_button: Button = get_node_or_null(cell_editor_button_path) as Button
	if editor_button != null:
		editor_button.set_meta("semantic_id", "ui://sim/cell-editor/toggle")
		SEMANTIC.call("register", "ui://sim/cell-editor/toggle", editor_button)

func _register_speed_controls() -> void:
	_speed_slider = get_node_or_null(speed_slider_path) as HSlider
	_speed_spin = get_node_or_null(speed_spin_path) as SpinBox
	_speed_lod = get_node_or_null(speed_lod_path) as Label
	if _speed_slider != null:
		_speed_slider.value_changed.connect(_on_speed_slider_changed)
	if _speed_spin != null:
		_speed_spin.value_changed.connect(_on_speed_spin_changed)
	if tick_core != null and tick_core.has_signal("speed_changed"):
		var on_speed: Callable = Callable(self, "_on_tick_speed_changed")
		if not tick_core.is_connected("speed_changed", on_speed):
			tick_core.connect("speed_changed", on_speed)
	if tick_core != null and tick_core.has_signal("carry_changed"):
		var on_carry: Callable = Callable(self, "_on_speed_carry_changed")
		if not tick_core.is_connected("carry_changed", on_carry):
			tick_core.connect("carry_changed", on_carry)
	sync_speed_ui()

func _register_cell_editor() -> void:
	_cell_editor = get_node_or_null(cell_editor_path) as Control
	var editor_button: Button = get_node_or_null(cell_editor_button_path) as Button
	if editor_button != null:
		editor_button.pressed.connect(_on_cell_editor_toggle)
	if _cell_editor != null and _cell_editor.has_signal("draft_applied"):
		_cell_editor.connect("draft_applied", Callable(self, "_on_draft_applied"))

func _sync_toggle_for(panel_path: String, value: bool) -> void:
	var button: Button = _panel_toggles.get(panel_path, null) as Button
	if button != null:
		button.set_pressed_no_signal(value)

func sync_speed_ui() -> void:
	if tick_core == null or _syncing_speed:
		return
	var value: float = clampf(float(tick_core.get("speed_scale")), 0.0, 32.0)
	_syncing_speed = true
	if _speed_slider != null and not is_equal_approx(_speed_slider.value, value):
		_speed_slider.set_value_no_signal(value)
	if _speed_spin != null and not is_equal_approx(float(_speed_spin.value), value):
		_speed_spin.set_value_no_signal(value)
	_syncing_speed = false
	_update_speed_lod_text()

func _update_speed_lod_text() -> void:
	if _speed_lod == null or tick_core == null:
		return
	var text_value: String = "LOD %d" % int(tick_core.call("get_lod_level"))
	var tick_script: Script = tick_core.get_script() as Script
	var frame_cap: int = 12
	if tick_script != null:
		frame_cap = int(tick_script.get_script_constant_map().get("MAX_TICKS_PER_FRAME", 12))
	var capped: bool = _speed_capped or int(tick_core.get("carry_ticks")) > 0
	if capped and float(tick_core.get("speed_scale")) > float(frame_cap):
		text_value += " · 上限 %d×" % frame_cap
	_speed_lod.text = text_value

func _on_speed_carry_changed(_carry_ticks: int, lagging: bool) -> void:
	_speed_capped = lagging
	_update_speed_lod_text()

func _apply_speed_value(value: float) -> void:
	if tick_core == null:
		return
	var speed_value: float = clampf(value, 0.0, 32.0)
	tick_core.call("apply_speed", speed_value)
	if speed_value > 0.0:
		tick_core.set("running", true)
	tick_core.call("clear_carry")
	sync_speed_ui()
	_set_feedback("倍速 → %s× · LOD %d · dt 固定 1/60 · 单帧 ≤12 tick" % [str(speed_value), int(tick_core.call("get_lod_level"))])

func _on_speed_slider_changed(value: float) -> void:
	_apply_speed_value(value)

func _on_speed_spin_changed(value: float) -> void:
	_apply_speed_value(value)

func _on_tick_speed_changed(_speed: float, _lod: int) -> void:
	sync_speed_ui()

func _on_cell_editor_toggle() -> void:
	if _cell_editor == null:
		return
	_cell_editor.visible = not _cell_editor.visible
	if _cell_editor.visible:
		_cell_editor.call("move_to_front")
	_sync_toggle_for("CellEditorPanel", _cell_editor.visible)
	_set_feedback("细胞编辑 · " + ("打开" if _cell_editor.visible else "关闭"))

func set_draft(genome: RefCounted, type_id: int) -> bool:
	if genome == null or not bool(genome.call("is_valid")):
		return false
	_on_draft_applied(genome, type_id)
	return true

func _on_draft_applied(genome: RefCounted, type_id: int) -> void:
	if genome == null:
		return
	_draft_genome = genome
	_draft_type_id = type_id
	var spawn_index: int = -1
	for i in range(_tools.size()):
		if str(_tools[i].get("id", "")) == "SPAWN":
			spawn_index = i
			break
	if spawn_index >= 0:
		_on_tool_pressed(spawn_index)
	_set_feedback("已装载自定义基因组 · %s · 点击皿内放置" % _genome_summary())

func _genome_summary() -> String:
	if _draft_genome == null:
		return "默认基因组"
	var traits: PackedByteArray = _draft_genome.get("traits")
	return "类型 %d · 8 组型 %s" % [_draft_type_id, str(Array(traits))]

func clear_draft() -> void:
	_draft_genome = null
	_draft_type_id = 0
	_set_feedback("合成器恢复默认基因组")

func has_draft() -> bool:
	return _draft_genome != null

func get_draft_type_id() -> int:
	return _draft_type_id

func _make_button(text_value: String, tooltip_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.tooltip_text = tooltip_value
	button.custom_minimum_size = Vector2(96, 30)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button

func _build_modes() -> void:
	var row: Node = get_node_or_null(mode_row_path)
	if row == null:
		return
	for i in range(_modes.size()):
		var mode: Dictionary = _modes[i]
		var button: Button = _make_button(str(mode.get("n", "?")), "%s · %s" % [mode.get("en", "?"), mode.get("note", "")])
		button.toggle_mode = true
		button.set_meta("index", i)
		button.pressed.connect(_on_mode_pressed.bind(i))
		row.add_child(button)
		_mode_buttons.append(button)

func _build_tools() -> void:
	var host: Node = get_node_or_null(tool_groups_path)
	if host == null:
		return
	var groups: Array[Dictionary] = CATALOG.call("groups")
	for group in groups:
		var header: Label = Label.new()
		header.text = "■ " + str(group.get("label", ""))
		header.add_theme_font_size_override("font_size", 13)
		host.add_child(header)
		for i in range(_tools.size()):
			var tool: Dictionary = _tools[i]
			if str(tool.get("group", "")) != str(group.get("k", "")):
				continue
			var label_text: String = "%s  %s" % [str(tool.get("key", "?")), str(tool.get("name", "?"))]
			var tip: String = "%s · %s\n%s\n[%s]" % [tool.get("en", "?"), tool.get("mode", "?"), tool.get("desc", "?"), tool.get("kind", "?")]
			var button: Button = _make_button(label_text, tip)
			button.toggle_mode = true
			button.set_meta("index", i)
			button.pressed.connect(_on_tool_pressed.bind(i))
			host.add_child(button)
			_tool_buttons.append(button)

func _build_substrate() -> void:
	var host: Node = get_node_or_null(substrate_rows_path)
	if host == null:
		return
	var last_section: String = ""
	for i in range(_substrate.size()):
		var row_data: Dictionary = _substrate[i]
		var section: String = str(row_data.get("section", ""))
		if section != last_section and not section.is_empty():
			var section_label: Label = Label.new()
			section_label.text = "▸ " + section
			section_label.add_theme_font_size_override("font_size", 12)
			section_label.add_theme_color_override("font_color", Color(0.36, 0.88, 0.75))
			host.add_child(section_label)
			last_section = section
		var tip: String = str(row_data.get("tip", ""))
		var hbox: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = str(row_data.get("n", "?"))
		label.custom_minimum_size = Vector2(112, 0)
		label.tooltip_text = tip
		var slider: HSlider = HSlider.new()
		slider.min_value = float(row_data.get("min", 0.0))
		slider.max_value = float(row_data.get("max", 1.0))
		slider.step = float(row_data.get("step", 0.01))
		var initial_value: float = float(row_data.get("v", 0.0))
		if environment_manager != null and bool(row_data.get("writable", false)):
			var actual: Variant = environment_manager.get(str(row_data.get("k", "")))
			if actual != null:
				initial_value = float(actual)
		slider.value = initial_value
		slider.custom_minimum_size = Vector2(180, 0)
		slider.set_meta("index", i)
		slider.tooltip_text = tip
		slider.value_changed.connect(_on_substrate_changed.bind(i))
		var value_label: Label = Label.new()
		value_label.text = _format_value(slider.value, float(row_data.get("step", 0.01)))
		value_label.custom_minimum_size = Vector2(56, 0)
		value_label.tooltip_text = tip
		if not bool(row_data.get("writable", false)):
			value_label.text += " *"
			slider.editable = false
		hbox.add_child(label)
		hbox.add_child(slider)
		hbox.add_child(value_label)
		host.add_child(hbox)
		_value_labels.append(value_label)

func _build_lenses() -> void:
	var row: Node = get_node_or_null(lens_row_path)
	if row == null:
		return
	for i in range(_lenses.size()):
		var button: Button = _make_button(_lenses[i], "显微镜镜头滤镜 · 仅视图")
		button.toggle_mode = true
		button.set_meta("index", i)
		button.pressed.connect(_on_lens_pressed.bind(i))
		row.add_child(button)
		_lens_buttons.append(button)

func _build_view_buttons() -> void:
	var row: Node = get_node_or_null(view_row_path)
	if row == null:
		return
	var names: Array[String] = ["居中", "放大", "缩小", "旋转"]
	for n in names:
		var button: Button = _make_button(n, "显微视野控制 · 仅视图")
		button.pressed.connect(_on_view_pressed.bind(n))
		row.add_child(button)

func _build_tint() -> void:
	_tint = ColorRect.new()
	_tint.name = "LensFilter"
	_tint.color = Color(0, 0, 0, 0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.z_index = -1
	# 真正的滤镜：canvas_item shader 对屏幕做色相/对比/扫描线叠加，各镜头参数不同。
	# 只是视图呈现，不改 camera 变换、不改 dt、不写模拟。
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 filter_color : source_color = vec4(0.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float scanline : hint_range(0.0, 1.0) = 0.0;
uniform vec2 resolution = vec2(1920.0, 1080.0);
void fragment() {
	float scan = scanline * (0.5 + 0.5 * sin(UV.y * resolution.y * 3.14159));
	float a = clamp(filter_color.a * strength + scan, 0.0, 1.0);
	COLOR = vec4(filter_color.rgb, a);
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("filter_color", Color(0, 0, 0, 0))
	material.set_shader_parameter("strength", 0.0)
	material.set_shader_parameter("scanline", 0.0)
	material.set_shader_parameter("resolution", Vector2(1920, 1080))
	_tint.material = material
	add_child(_tint)

## 注射参数行：颜色注射选细胞类型、信号注射选场通道 + 注入量。
## 只在选中对应工具时显示，避免常驻占屏；控件用代码填充，与 _build_tools 风格一致。
func _build_injector() -> void:
	_injector_panel = HBoxContainer.new()
	_injector_panel.name = "InjectorPanel"
	_injector_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_injector_panel.offset_left = 12.0
	_injector_panel.offset_top = 88.0
	_injector_panel.offset_right = 720.0
	_injector_panel.offset_bottom = 120.0
	_injector_panel.add_theme_constant_override("separation", 6)

	_color_label = Label.new()
	_color_label.text = "颜色→类型"
	_color_option = OptionButton.new()
	_color_option.custom_minimum_size = Vector2(128, 0)
	for entry in CELL_VISUALS.call("entries"):
		_color_option.add_item("%d %s" % [int(entry.get("id", 0)), str(entry.get("label", "?"))])
	_color_option.item_selected.connect(_on_color_selected)

	_channel_label = Label.new()
	_channel_label.text = "信号→通道"
	_channel_option = OptionButton.new()
	_channel_option.custom_minimum_size = Vector2(96, 0)
	for channel_name in ["营养0", "温度1", "氧气2", "光照3", "信号4"]:
		_channel_option.add_item(channel_name)
	_channel_option.selected = 4
	_channel_option.item_selected.connect(_on_channel_selected)

	_amount_label = Label.new()
	_amount_label.text = "注入量"
	_amount_spin = SpinBox.new()
	_amount_spin.custom_minimum_size = Vector2(72, 0)
	_amount_spin.min_value = 0.0
	_amount_spin.max_value = 4.0
	_amount_spin.step = 0.1
	_amount_spin.value = 0.5
	_amount_spin.value_changed.connect(_on_amount_changed)

	_injector_panel.add_child(_color_label)
	_injector_panel.add_child(_color_option)
	_injector_panel.add_child(_channel_label)
	_injector_panel.add_child(_channel_option)
	_injector_panel.add_child(_amount_label)
	_injector_panel.add_child(_amount_spin)
	add_child(_injector_panel)
	_update_injector_visibility()

func _update_injector_visibility() -> void:
	if _injector_panel == null:
		return
	var tool_id: String = selected_tool_id()
	var show_color: bool = tool_id == "INJECT_COLOR"
	var show_signal: bool = tool_id == "INJECT_SIGNAL"
	_injector_panel.visible = show_color or show_signal
	if _color_label != null: _color_label.visible = show_color
	if _color_option != null: _color_option.visible = show_color
	if _channel_label != null: _channel_label.visible = show_signal
	if _channel_option != null: _channel_option.visible = show_signal
	if _amount_label != null: _amount_label.visible = show_signal
	if _amount_spin != null: _amount_spin.visible = show_signal

func _on_color_selected(index: int) -> void:
	set_inject_color_type(index)
	_set_feedback("颜色注射 → 类型 %d · 点击细胞写入" % index)

func _on_channel_selected(index: int) -> void:
	set_inject_signal_channel(index)
	_set_feedback("信号注射 → 通道 %d · 点击皿内注入" % index)

func _on_amount_changed(value: float) -> void:
	set_inject_signal_amount(value)

func _format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	return "%.2f" % value

func _set_feedback(text_value: String) -> void:
	if _feedback_label != null:
		_feedback_label.text = text_value

func _on_mode_pressed(index: int) -> void:
	_apply_mode(index)

func _apply_mode(index: int) -> void:
	if index < 0 or index >= _modes.size():
		return
	_selected_mode = index
	var mode: Dictionary = _modes[index]
	for i in range(_mode_buttons.size()):
		_mode_buttons[i].set_pressed_no_signal(i == index)
	if tick_core != null:
		tick_core.set("running", bool(mode.get("running", true)))
		tick_core.call("set_speed", float(mode.get("scale", 1.0)))
		sync_speed_ui()
	_set_feedback("档位 → %s（%s）：%s" % [mode.get("n", "?"), mode.get("en", "?"), mode.get("note", "?")])
	mode_changed.emit(mode)

func _on_tool_pressed(index: int) -> void:
	if index < 0 or index >= _tools.size():
		return
	var tool: Dictionary = _tools[index]
	# v0.51.0：立即型工具（培养基灭菌）按下即入队，不进入「选中后点击皿内执行」的流程。
	if str(tool.get("mode", "")) == "立即型":
		if index < _tool_buttons.size():
			_tool_buttons[index].set_pressed_no_signal(false)
		request_sterilize()
		return
	_selected_index = index
	for i in range(_tool_buttons.size()):
		_tool_buttons[i].set_pressed_no_signal(i == index)
	tool_changed.emit(tool)
	_update_injector_visibility()
	if str(tool.get("id", "")) == "SPAWN":
		_set_feedback("细胞合成器 · " + _genome_summary() + " · 在皿内点击放置")
	elif str(tool.get("id", "")) == "INJECT_GENOME":
		_set_feedback("基因组注射 · " + _genome_summary() + " · 点击皿内细胞写入")
	else:
		_set_feedback("已选 %s · %s · 在皿内点击执行" % [tool.get("name", "?"), tool.get("mode", "?")])

func _on_substrate_changed(value: float, index: int) -> void:
	if index < 0 or index >= _substrate.size():
		return
	var row_data: Dictionary = _substrate[index]
	if index < _value_labels.size():
		_value_labels[index].text = _format_value(value, float(row_data.get("step", 0.01)))
		if not bool(row_data.get("writable", false)):
			_value_labels[index].text += " *"
	if bool(row_data.get("writable", false)) and environment_manager != null:
		var key: String = str(row_data.get("k", ""))
		environment_manager.set(key, value)
		if ENVIRONMENT_FIELD_KEYS.has(key):
			environment_manager.call("apply_environment_preset")
			if _field_layer != null:
				_field_layer.call("mark_dirty")

## 镜头滤镜：只改滤镜参数，绝不改 camera.zoom / offset / rotation（视野交给滚轮与右键）。
## 五个镜头参数各不相同，确保切换后画面有真实差异，而非只是换了层半透明颜色。
func _on_lens_pressed(index: int) -> void:
	_selected_lens = index
	for i in range(_lens_buttons.size()):
		_lens_buttons[i].set_pressed_no_signal(i == index)
	var name_value: String = _lenses[index]
	# filter_color = RGB 染色 + A 基础不透明度；strength 放大染色；scanline 扫描线密度。
	var filter_color: Color = Color(0, 0, 0, 0)
	var strength: float = 0.0
	var scanline: float = 0.02
	var note: String = ""
	match name_value:
		"默认":
			strength = 0.0
			note = "无滤镜 · 原始画面"
		"视野":
			filter_color = Color(0.05, 0.12, 0.10, 0.05)
			strength = 0.30
			scanline = 0.0
			note = "宽视野 · 轻微冷调、无扫描线"
		"目镜":
			filter_color = Color(0.02, 0.06, 0.10, 0.10)
			strength = 0.75
			scanline = 0.09
			note = "高倍目镜 · 深冷调 + 明显扫描线"
		"融合镜":
			filter_color = Color(0.18, 0.72, 0.60, 0.16)
			strength = 0.85
			scanline = 0.03
			note = "融合镜 · 青绿色通道叠加"
		"偏振镜":
			filter_color = Color(0.92, 0.52, 0.22, 0.18)
			strength = 0.90
			scanline = 0.06
			note = "偏振镜 · 暖橙色通道 + 偏振纹"
	if _tint != null:
		_tint.color = filter_color
		var material: ShaderMaterial = _tint.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("filter_color", filter_color)
			material.set_shader_parameter("strength", strength)
			material.set_shader_parameter("scanline", scanline)
	_set_feedback("镜头 → %s · %s · 视野不变" % [name_value, note])

func _on_view_pressed(name_value: String) -> void:
	if camera == null:
		return
	match name_value:
		"居中":
			camera.position = Vector2(250, 250)
		"放大":
			camera.zoom = Vector2(minf(camera.zoom.x + 0.5, 6.0), minf(camera.zoom.y + 0.5, 6.0))
		"缩小":
			camera.zoom = Vector2(maxf(camera.zoom.x - 0.5, 0.5), maxf(camera.zoom.y - 0.5, 0.5))
		"旋转":
			camera.rotation += deg_to_rad(15.0)
	_set_feedback("视野 → %s · 仅视图" % name_value)

func selected_tool() -> Dictionary:
	if _selected_index >= 0 and _selected_index < _tools.size():
		return _tools[_selected_index]
	return {}

func selected_tool_id() -> String:
	return str(selected_tool().get("id", ""))

## 拖拽型工具（光学镊子/旋转选区/地形笔刷/地形橡皮）由 Main 在按住左键时连续入队。
func is_drag_tool() -> bool:
	return selected_tool_id() in ["DRAG", "ROTATE_SELECTION", "TERRAIN_PAINT", "TERRAIN_ERASE"]

## 当前注射工具的参数选择（颜色注射 = 细胞表现类型；信号注射 = 场通道）。
## 由 HUD 的选择控件写入；未提供时使用确定性的默认值，保持命令自包含。
var _inject_color_type: int = 0
var _inject_signal_channel: int = 4
var _inject_signal_amount: float = 0.5
var _injector_panel: HBoxContainer = null
var _color_option: OptionButton = null
var _channel_option: OptionButton = null
var _amount_spin: SpinBox = null
var _color_label: Label = null
var _channel_label: Label = null
var _amount_label: Label = null

func set_inject_color_type(type_id: int) -> void:
	_inject_color_type = maxi(0, type_id)

func set_inject_signal_channel(channel: int) -> void:
	_inject_signal_channel = clampi(channel, 0, 4)

func set_inject_signal_amount(amount: float) -> void:
	_inject_signal_amount = clampf(amount, 0.0, 4.0)

## 培养基灭菌：一次清除皿内全部细胞（对应 Cell Lab 的 Sterilize）。走 CommandBus，
## 因此可回放、可被 Agent 调用；实际清除在 OrganismManager 的 `STERILIZE` 分支。
func request_sterilize() -> bool:
	if command_bus == null:
		_set_feedback("培养基灭菌：命令总线未就绪")
		return false
	command_bus.call("enqueue", {"type": "STERILIZE", "kind": "world"})
	_set_feedback("培养基灭菌 · 已入队")
	return true

func world_action(world_position: Vector2, drag_delta: Vector2 = Vector2.ZERO) -> bool:
	## 由 Main 的鼠标输入调用：把当前工具 + 世界坐标封装成命令入队。
	var tool: Dictionary = selected_tool()
	if tool.is_empty():
		return false
	var tool_id: String = str(tool.get("id", ""))
	var command: Dictionary = {
		"type": tool_id,
		"position": world_position,
		"delta": drag_delta,
		"kind": str(tool.get("kind", "?"))
	}
	if (tool_id == "SPAWN" or tool_id == "INJECT_GENOME") and _draft_genome != null:
		if not bool(_draft_genome.call("is_valid")):
			_set_feedback("基因组草案无效，未入队")
			return false
		command["genome_bytes"] = CODEC.call("encode", _draft_genome)
		command["type_id"] = _draft_type_id
		# v0.15.0：GNP1 二进制冻结，基因模式参数走版本化命令 payload（也走 CommandBus）。
		command["genome_gene"] = {
			"division_mass": float(_draft_genome.get("division_mass")),
			"split_ratio": float(_draft_genome.get("split_ratio")),
			"max_divisions": int(_draft_genome.get("max_divisions")),
			"child_types": (_draft_genome.get("child_types") as PackedByteArray).duplicate(),
			"split_angles": (_draft_genome.get("split_angles") as PackedByteArray).duplicate(),
			# v0.18.0：个体上限与逐模式限制只走 CommandBus payload，不进 GNP1 冻结二进制。
			"max_cells_per_organism": int(_draft_genome.get("max_cells_per_organism")),
			# v0.16.0：Macro 表型字段同样经 CommandBus 传入，不进 GNP1 冻结二进制。
			"nutrition_priority": float(_draft_genome.get("nutrition_priority")),
			"cell_stiffness": float(_draft_genome.get("cell_stiffness")),
			"cell_size": float(_draft_genome.get("cell_size")),
			"max_connections": int(_draft_genome.get("max_connections")),
			"min_connections": int(_draft_genome.get("min_connections")),
			"color_r": float(_draft_genome.get("color_r")),
			"color_g": float(_draft_genome.get("color_g")),
			"color_b": float(_draft_genome.get("color_b")),
			# v0.17.0：多模式槽与传递率仍只走 CommandBus payload，不进 GNP1 冻结二进制。
			"modes": (_draft_genome.get("modes") as Array).duplicate(true),
			"transfer_rate": float(_draft_genome.get("transfer_rate")),
		}
	if tool_id == "INJECT_COLOR":
		command["color_type"] = _inject_color_type
	if tool_id == "INJECT_SIGNAL":
		command["signal_channel"] = _inject_signal_channel
		command["signal_amount"] = _inject_signal_amount
	if command_bus == null:
		return false
	command_bus.call("enqueue", command)
	if tool_id == "SPAWN":
		_set_feedback("细胞合成器 → %s 落点 (%.1f, %.1f)" % [_genome_summary(), world_position.x, world_position.y])
	elif tool_id == "INJECT_GENOME":
		_set_feedback("基因组注射 → %s · CommandBus 入队" % _genome_summary())
	elif tool_id == "INJECT_COLOR":
		_set_feedback("颜色注射 → 类型 %d · (%.1f, %.1f)" % [_inject_color_type, world_position.x, world_position.y])
	elif tool_id == "INJECT_SIGNAL":
		_set_feedback("信号注射 → 通道 %d 量 %.2f · (%.1f, %.1f)" % [_inject_signal_channel, _inject_signal_amount, world_position.x, world_position.y])
	else:
		_set_feedback("%s → CommandBus 入队（下一 tick 生效） @ (%.1f, %.1f)" % [tool.get("name", "?"), world_position.x, world_position.y])
	return true

func apply_result(command_type: String, result: int) -> void:
	## Main 在执行命令后回传结果，用于状态栏反馈。
	if result >= 0:
		_set_feedback("%s 执行成功 · code=%d" % [command_type, result])
	elif command_type == "SPAWN":
		_set_feedback("SPAWN 未执行 · code=%d · 请点在皿内；冻结档已自动 flush" % result)
	elif command_type == "INJECT_GENOME":
		_set_feedback("基因组注射未执行 · code=%d · 需先装载草案并点在细胞上" % result)
	else:
		_set_feedback("%s 未执行 · code=%d" % [command_type, result])

func show_tool_message(message: String) -> void:
	## 工具的业务反馈（INSPECT 摘要 / ADHERE 选点等），由 Main 在命令执行后透传。
	_set_feedback(message)
