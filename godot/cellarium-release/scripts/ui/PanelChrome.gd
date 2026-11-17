extends RefCounted
## 通用面板装饰（阶段 UI 调整）：给任意 PanelContainer 注入标题栏 —— 拖动把手 + 图钉 + 关闭。
## 不改面板业务脚本；把面板原有内容包进 VBoxContainer，标题栏置顶。
## 纯 UI 层，不触碰模拟状态与 CommandBus。
## 节点优先：标题栏控件由代码按 .tscn 同构方式构建（与 GameHUD._build_tools 一致）。

signal close_requested()
signal pin_toggled(pinned: bool)

const HANDLE_HEIGHT: float = 26.0
const PIN_TEXT: String = "钉"
const PIN_ON_TEXT: String = "已固定"
const CLOSE_TEXT: String = "×"

var panel: PanelContainer = null
var title_text: String = ""
var use_pin: bool = false
var pinned: bool = false

var _handle: HBoxContainer = null
var _pin_button: Button = null
var _close_button: Button = null
var _drag_active: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO

func _init(target: PanelContainer, label: String, pin: bool = false) -> void:
	panel = target
	title_text = label
	use_pin = pin

func install() -> bool:
	if panel == null:
		return false
	# 把现有子节点（通常是唯一 MarginContainer）收拢进 VBoxContainer。
	var existing: Array[Node] = panel.get_children()
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "ChromeRoot"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	for child in existing:
		panel.remove_child(child)
		vbox.add_child(child)

	_handle = HBoxContainer.new()
	_handle.name = "ChromeHandle"
	_handle.custom_minimum_size = Vector2(0, HANDLE_HEIGHT)
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.gui_input.connect(_on_handle_gui_input)

	var title_label: Label = Label.new()
	title_label.text = title_text
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 12)
	_handle.add_child(title_label)

	if use_pin:
		_pin_button = Button.new()
		_pin_button.text = PIN_TEXT
		_pin_button.toggle_mode = true
		_pin_button.custom_minimum_size = Vector2(52, 22)
		_pin_button.tooltip_text = "固定面板：固定后不会被快捷键/自动逻辑关闭"
		_pin_button.toggled.connect(_on_pin_toggled)
		_handle.add_child(_pin_button)

	_close_button = Button.new()
	_close_button.text = CLOSE_TEXT
	_close_button.custom_minimum_size = Vector2(26, 22)
	_close_button.tooltip_text = "关闭面板（可用顶栏开关重新打开）"
	_close_button.pressed.connect(_on_close_pressed)
	_handle.add_child(_close_button)

	# VBox 顺序：标题栏在上，原内容在下。
	vbox.add_child(_handle)
	panel.add_child(vbox)
	panel.set_meta("chrome_pinned", false)
	return true

func _on_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_drag_active = true
				_drag_start_mouse = mouse_button.global_position
				_drag_start_pos = panel.global_position
			else:
				_drag_active = false
	elif event is InputEventMouseMotion and _drag_active:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = motion.global_position - _drag_start_mouse
		panel.global_position = _drag_start_pos + delta

func _on_close_pressed() -> void:
	if panel != null:
		panel.visible = false
	close_requested.emit()

func _on_pin_toggled(value: bool) -> void:
	pinned = value
	if _pin_button != null:
		_pin_button.text = PIN_ON_TEXT if value else PIN_TEXT
	if panel != null:
		panel.set_meta("chrome_pinned", value)
	pin_toggled.emit(value)

func get_pin_button() -> Button:
	return _pin_button

func get_close_button() -> Button:
	return _close_button
