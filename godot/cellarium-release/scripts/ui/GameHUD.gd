extends Control
## HUD 控制器：把 ToolCatalog 的数据实例化为 Godot Control 节点（Button/HSlider），
## 绑定 pressed / value_changed → CommandBus.enqueue 或视图控制。
## 场景骨架（容器 Panel/HBox/VBox/Label）在 main.tscn 声明，本脚本只填充重复项与承载交互。
## 用词对照 analysis/CellLab_界面与实验条件_词条证据.md。

const CATALOG: RefCounted = preload("res://scripts/ui/ToolCatalog.gd")

@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var environment_path: NodePath = ^"../../Simulation/EnvironmentManager"
@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var camera_path: NodePath = ^"../../Camera2D"
@export var mode_row_path: NodePath = ^"TopBar/ModeRow"
@export var tool_groups_path: NodePath = ^"ToolDock/ToolGroups"
@export var substrate_rows_path: NodePath = ^"SubstratePanel/SubstrateRows"
@export var lens_row_path: NodePath = ^"MicroscopePanel/LensRow"
@export var view_row_path: NodePath = ^"MicroscopePanel/ViewRow"
@export var feedback_path: NodePath = ^"FeedbackLabel"

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
	_apply_mode(_selected_mode)
	print("[GameHUD] ready tools=", _tools.size(), " modes=", _modes.size(), " substrate=", _substrate.size())

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
	var command: Dictionary = {
		"type": str(tool.get("id", "")),
		"position": world_position,
		"delta": drag_delta,
		"kind": str(tool.get("kind", "?"))
	}
	if command_bus == null:
		return false
	command_bus.call("enqueue", command)
	_set_feedback("%s → CommandBus 入队（下一 tick 生效） @ (%.1f, %.1f)" % [tool.get("name", "?"), world_position.x, world_position.y])
	return true

func apply_result(command_type: String, result: int) -> void:
	## Main 在执行命令后回传结果，用于状态栏反馈。
	if result >= 0:
		_set_feedback("%s 执行成功 · code=%d" % [command_type, result])
	else:
		_set_feedback("%s 未执行 · code=%d" % [command_type, result])
