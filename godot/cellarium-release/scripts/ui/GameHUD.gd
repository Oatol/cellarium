extends Control
## HUD 控制器：把 ToolCatalog 的数据实例化为 Godot Control 节点（Button/HSlider），
## 绑定 pressed / value_changed → CommandBus.enqueue 或视图控制。
## 场景骨架（容器 Panel/HBox/VBox/Label）在 main.tscn 声明，本脚本只填充重复项与承载交互。
## 用词对照 analysis/CellLab_界面与实验条件_词条证据.md。

const CATALOG: RefCounted = preload("res://scripts/ui/ToolCatalog.gd")
const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")
const CODEC: RefCounted = preload("res://scripts/core/data/GenomeCodec.gd")

@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var environment_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var camera_path: NodePath = ^"../../Camera2D"
@export var mode_row_path: NodePath = ^"TopBar/ModeRow"
@export var tool_groups_path: NodePath = ^"ToolDock/ToolGroups"
@export var substrate_rows_path: NodePath = ^"SubstratePanel/SubstrateRows"
@export var lens_row_path: NodePath = ^"MicroscopePanel/Panel/Content/LensRow"
@export var view_row_path: NodePath = ^"MicroscopePanel/Panel/Content/ViewRow"
@export var feedback_path: NodePath = ^"FeedbackLabel"
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

func _ready() -> void:
	command_bus = get_node_or_null(command_bus_path)
	tick_core = get_node_or_null(tick_core_path)
	environment_manager = get_node_or_null(environment_path)
	organism_manager = get_node_or_null(organism_manager_path)
	camera = get_node_or_null(camera_path) as Camera2D
	_feedback_label = get_node_or_null(feedback_path) as Label
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
	_register_speed_controls()
	_register_cell_editor()
	_register_semantic_ids()
	_apply_mode(_selected_mode)
	print("[GameHUD] ready tools=", _tools.size(), " modes=", _modes.size(), " substrate=", _substrate.size(), " semantic=", SEMANTIC.call("count"))

## 把可交互控件注册到语义注册表（§3.6 / §6.9），供 Agent ui.click 无坐标访问。
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
	sync_speed_ui()

func _register_cell_editor() -> void:
	_cell_editor = get_node_or_null(cell_editor_path) as Control
	var editor_button: Button = get_node_or_null(cell_editor_button_path) as Button
	if editor_button != null:
		editor_button.pressed.connect(_on_cell_editor_toggle)
	if _cell_editor != null and _cell_editor.has_signal("draft_applied"):
		_cell_editor.connect("draft_applied", Callable(self, "_on_draft_applied"))

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
	if _speed_lod != null:
		_speed_lod.text = "LOD %d" % int(tick_core.call("get_lod_level"))

func _apply_speed_value(value: float) -> void:
	if tick_core == null:
		return
	var speed_value: float = clampf(value, 0.0, 32.0)
	tick_core.call("apply_speed", speed_value)
	if speed_value > 0.0:
		tick_core.set("running", true)
	tick_core.call("clear_carry")
	sync_speed_ui()
	_set_feedback("倍速 → %s× · LOD %d · dt 固定 1/60" % [str(speed_value), int(tick_core.call("get_lod_level"))])

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
	for i in range(_substrate.size()):
		var row_data: Dictionary = _substrate[i]
		var hbox: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = str(row_data.get("n", "?"))
		label.custom_minimum_size = Vector2(112, 0)
		var slider: HSlider = HSlider.new()
		slider.min_value = float(row_data.get("min", 0.0))
		slider.max_value = float(row_data.get("max", 1.0))
		slider.step = float(row_data.get("step", 0.01))
		slider.value = float(row_data.get("v", 0.0))
		slider.custom_minimum_size = Vector2(180, 0)
		slider.set_meta("index", i)
		slider.value_changed.connect(_on_substrate_changed.bind(i))
		var value_label: Label = Label.new()
		value_label.text = _format_value(slider.value, float(row_data.get("step", 0.01)))
		value_label.custom_minimum_size = Vector2(56, 0)
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
	_tint.color = Color(0, 0, 0, 0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.z_index = -1
	add_child(_tint)

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
	_selected_index = index
	for i in range(_tool_buttons.size()):
		_tool_buttons[i].set_pressed_no_signal(i == index)
	var tool: Dictionary = _tools[index]
	tool_changed.emit(tool)
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
		environment_manager.set(str(row_data.get("k", "")), value)

func _on_lens_pressed(index: int) -> void:
	_selected_lens = index
	for i in range(_lens_buttons.size()):
		_lens_buttons[i].set_pressed_no_signal(i == index)
	var name_value: String = _lenses[index]
	var tint: Color = Color(0, 0, 0, 0)
	var zoom: float = 2.0
	match name_value:
		"视野":
			zoom = 1.2
		"目镜":
			zoom = 3.0
		"融合镜":
			tint = Color(0.36, 0.88, 0.75, 0.10)
		"偏振镜":
			tint = Color(1.0, 0.54, 0.24, 0.10)
	if _tint != null:
		_tint.color = tint
	if camera != null:
		camera.zoom = Vector2(zoom, zoom)
	_set_feedback("镜头 → %s · 仅视图，不改 dt" % name_value)

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
	if command_bus == null:
		return false
	command_bus.call("enqueue", command)
	if tool_id == "SPAWN":
		_set_feedback("细胞合成器 → %s 落点 (%.1f, %.1f)" % [_genome_summary(), world_position.x, world_position.y])
	elif tool_id == "INJECT_GENOME":
		_set_feedback("基因组注射 → %s · CommandBus 入队" % _genome_summary())
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
