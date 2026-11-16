extends Control
## 细胞 / 多细胞编辑页：编辑 GNP1 组型、类型、呼吸方式与发育程序。
## 发育程序由 DIVIDE / DIFFERENTIATE / LINK 三类指令组成，直接写 draft.dev_program，
## 点「装载到合成器」后经 HUD → CommandBus 才进入模拟；本页不碰模拟状态。

signal draft_applied(genome: RefCounted, type_id: int)

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

const TRAITS: Array[String] = ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const RESPIRATION: Array[String] = ["兼性", "好氧", "厌氧"]
const OP_LABELS: Array[String] = ["分裂 DIVIDE", "分化 DIFFERENTIATE", "连接 LINK"]
const MAX_DEV_INSTRUCTIONS: int = 64

@export var trait_rows_path: NodePath = ^"Panel/Scroll/Content/TraitRows"
@export var type_option_path: NodePath = ^"Panel/Scroll/Content/ConfigRow/TypeOption"
@export var respiration_option_path: NodePath = ^"Panel/Scroll/Content/ConfigRow/RespirationOption"
@export var apply_button_path: NodePath = ^"Panel/Scroll/Content/ActionRow/ApplyButton"
@export var default_button_path: NodePath = ^"Panel/Scroll/Content/ActionRow/DefaultButton"
@export var close_button_path: NodePath = ^"Panel/Scroll/Content/ActionRow/CloseButton"
@export var dev_rows_path: NodePath = ^"Panel/Scroll/Content/DevRows"
@export var dev_add_path: NodePath = ^"Panel/Scroll/Content/DevActionRow/AddButton"
@export var dev_template_path: NodePath = ^"Panel/Scroll/Content/DevActionRow/TemplateButton"
@export var dev_clear_path: NodePath = ^"Panel/Scroll/Content/DevActionRow/ClearButton"
@export var dev_preview_path: NodePath = ^"Panel/Scroll/Content/DevPreview"

var draft: RefCounted = null
var _value_labels: Array[Label] = []
var _type_option: OptionButton = null
var _respiration_option: OptionButton = null
var _dev_rows: VBoxContainer = null
var _dev_preview: Label = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	draft = (GENOME_SCRIPT as Script).new() as RefCounted
	_reset_draft_data()
	_type_option = get_node_or_null(type_option_path) as OptionButton
	_respiration_option = get_node_or_null(respiration_option_path) as OptionButton
	_dev_rows = get_node_or_null(dev_rows_path) as VBoxContainer
	_dev_preview = get_node_or_null(dev_preview_path) as Label
	_build_traits()
	_build_options()
	_build_dev_actions()
	var apply_button: Button = get_node_or_null(apply_button_path) as Button
	if apply_button != null:
		apply_button.pressed.connect(_on_apply)
	var default_button: Button = get_node_or_null(default_button_path) as Button
	if default_button != null:
		default_button.pressed.connect(_on_default)
	var close_button: Button = get_node_or_null(close_button_path) as Button
	if close_button != null:
		close_button.pressed.connect(func() -> void: visible = false)
	_sync_controls()

static func default_dev_program() -> Array[Dictionary]:
	# 4 细胞协作模板：结构核 + 运动/能量/信息三类分化，三条 Link 连成一体。
	# DIVIDE 的 c 是分裂间距（世界单位），LINK 的 c 是静息长度。
	return [
		{"opcode": 0, "a": 0, "b": 0,   "c": 14},
		{"opcode": 0, "a": 0, "b": 85,  "c": 14},
		{"opcode": 0, "a": 1, "b": 170, "c": 14},
		{"opcode": 1, "a": 1, "b": 2,   "c": 0},
		{"opcode": 1, "a": 2, "b": 4,   "c": 0},
		{"opcode": 1, "a": 3, "b": 5,   "c": 0},
		{"opcode": 2, "a": 0, "b": 1,   "c": 14},
		{"opcode": 2, "a": 0, "b": 2,   "c": 14},
		{"opcode": 2, "a": 0, "b": 3,   "c": 14},
	]

func _build_traits() -> void:
	var host: Node = get_node_or_null(trait_rows_path)
	if host == null:
		return
	for i in range(TRAITS.size()):
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		var label: Label = Label.new()
		label.text = TRAITS[i]
		label.custom_minimum_size = Vector2(72, 0)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 255.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(180, 0)
		slider.set_meta("trait_index", i)
		slider.value_changed.connect(_on_trait_changed.bind(i))
		var value_label: Label = Label.new()
		value_label.custom_minimum_size = Vector2(36, 0)
		row.add_child(label)
		row.add_child(slider)
		row.add_child(value_label)
		host.add_child(row)
		_value_labels.append(value_label)

func _build_options() -> void:
	if _type_option != null:
		_type_option.clear()
		var entries: Array[Dictionary] = CATALOG.call("entries")
		for entry in entries:
			_type_option.add_item(str(entry.get("label", "?")))
	if _respiration_option != null:
		_respiration_option.clear()
		for name_value in RESPIRATION:
			_respiration_option.add_item(name_value)
		var handler: Callable = Callable(self, "_on_respiration_selected")
		if not _respiration_option.is_connected("item_selected", handler):
			_respiration_option.connect("item_selected", handler)

func _build_dev_actions() -> void:
	var add_button: Button = get_node_or_null(dev_add_path) as Button
	if add_button != null:
		add_button.pressed.connect(_on_add_instruction)
	var template_button: Button = get_node_or_null(dev_template_path) as Button
	if template_button != null:
		template_button.pressed.connect(_on_load_template)
	var clear_button: Button = get_node_or_null(dev_clear_path) as Button
	if clear_button != null:
		clear_button.pressed.connect(_on_clear_program)

func _reset_draft_data() -> void:
	if draft == null:
		return
	draft.set("version", 1)
	draft.set("flags", 0)
	draft.set("respiration", 1)
	draft.set("mutation_rate_exp", 0)
	draft.set("loci", PackedByteArray())
	draft.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	draft.call("set_development_program", default_dev_program())

func _sync_controls() -> void:
	if draft == null:
		return
	var traits: PackedByteArray = draft.get("traits")
	for i in range(_value_labels.size()):
		var value: int = int(traits[i]) if i < traits.size() else 0
		_value_labels[i].text = str(value)
		var row: Node = _value_labels[i].get_parent()
		var slider: HSlider = row.get_child(1) as HSlider
		if slider != null:
			slider.set_value_no_signal(float(value))
	if _type_option != null and _type_option.item_count > 0:
		_type_option.selected = 0
	if _respiration_option != null and _respiration_option.item_count > 0:
		_respiration_option.selected = 1
	_rebuild_dev_rows()
	_refresh_dev_preview()

func _on_trait_changed(value: float, index: int) -> void:
	if draft == null or index < 0 or index >= TRAITS.size():
		return
	var traits: PackedByteArray = draft.get("traits")
	traits[index] = clampi(int(round(value)), 0, 255)
	draft.set("traits", traits)
	if index < _value_labels.size():
		_value_labels[index].text = str(int(traits[index]))

func _on_respiration_selected(index: int) -> void:
	if draft != null:
		draft.set("respiration", clampi(index, 0, 2))

func _rebuild_dev_rows() -> void:
	if _dev_rows == null or draft == null:
		return
	for child in _dev_rows.get_children():
		child.queue_free()
	var program: Array = draft.get("dev_program")
	for instruction_index in range(program.size()):
		var instruction: Dictionary = program[instruction_index]
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 26)
		var opcode: OptionButton = OptionButton.new()
		opcode.custom_minimum_size = Vector2(128, 0)
		for label_value in OP_LABELS:
			opcode.add_item(label_value)
		opcode.selected = clampi(int(instruction.get("opcode", 0)), 0, OP_LABELS.size() - 1)
		opcode.item_selected.connect(_on_opcode_changed.bind(instruction_index))
		var a_spin: SpinBox = SpinBox.new()
		a_spin.min_value = 0.0
		a_spin.max_value = 255.0
		a_spin.step = 1.0
		a_spin.custom_minimum_size = Vector2(54, 0)
		a_spin.value = float(int(instruction.get("a", 0)))
		a_spin.value_changed.connect(_on_operand_changed.bind(instruction_index, "a"))
		var b_spin: SpinBox = SpinBox.new()
		b_spin.min_value = 0.0
		b_spin.max_value = 255.0
		b_spin.step = 1.0
		b_spin.custom_minimum_size = Vector2(54, 0)
		b_spin.value = float(int(instruction.get("b", 0)))
		b_spin.value_changed.connect(_on_operand_changed.bind(instruction_index, "b"))
		var c_spin: SpinBox = SpinBox.new()
		c_spin.min_value = 0.0
		c_spin.max_value = 1023.0
		c_spin.step = 1.0
		c_spin.custom_minimum_size = Vector2(60, 0)
		c_spin.value = float(int(instruction.get("c", 0)))
		c_spin.value_changed.connect(_on_operand_changed.bind(instruction_index, "c"))
		var remove_button: Button = Button.new()
		remove_button.text = "×"
		remove_button.custom_minimum_size = Vector2(28, 0)
		remove_button.pressed.connect(_on_remove_instruction.bind(instruction_index))
		row.add_child(opcode)
		row.add_child(a_spin)
		row.add_child(b_spin)
		row.add_child(c_spin)
		row.add_child(remove_button)
		_dev_rows.add_child(row)

func _refresh_dev_preview() -> void:
	if _dev_preview == null or draft == null:
		return
	var program: Array = draft.get("dev_program")
	var cell_count: int = 1
	var link_count: int = 0
	var type_set: Dictionary = {}
	for instruction in program:
		var opcode: int = int(instruction.get("opcode", -1))
		if opcode == 0:
			cell_count += 1
		elif opcode == 1:
			type_set[int(instruction.get("b", 0))] = true
		elif opcode == 2:
			link_count += 1
	var labels: Array[String] = []
	for type_id in type_set:
		labels.append(str(CATALOG.call("label", int(type_id))))
	var role_text: String = " / ".join(labels) if not labels.is_empty() else "无分化"
	_dev_preview.text = "预览：%d 细胞 · %d 连接 · %s" % [cell_count, link_count, role_text]

func _write_program(program: Array) -> void:
	if draft == null:
		return
	if not bool(draft.call("set_development_program", program)):
		return
	_rebuild_dev_rows()
	_refresh_dev_preview()

func _on_opcode_changed(opcode_index: int, instruction_index: int) -> void:
	var program: Array = draft.get("dev_program")
	if instruction_index < 0 or instruction_index >= program.size():
		return
	program[instruction_index]["opcode"] = clampi(opcode_index, 0, 2)
	draft.set("dev_program", program)
	_refresh_dev_preview()

func _on_operand_changed(value: float, instruction_index: int, key: String) -> void:
	var program: Array = draft.get("dev_program")
	if instruction_index < 0 or instruction_index >= program.size():
		return
	var maximum: int = 1023 if key == "c" else 255
	program[instruction_index][key] = clampi(int(round(value)), 0, maximum)
	draft.set("dev_program", program)
	_refresh_dev_preview()

func _on_remove_instruction(instruction_index: int) -> void:
	var program: Array = draft.get("dev_program")
	if instruction_index < 0 or instruction_index >= program.size():
		return
	program.remove_at(instruction_index)
	_write_program(program)

func _on_add_instruction() -> void:
	var program: Array = draft.get("dev_program")
	if program.size() >= MAX_DEV_INSTRUCTIONS:
		return
	program.append({"opcode": 0, "a": 0, "b": 0, "c": 14})
	_write_program(program)

func _on_load_template() -> void:
	_write_program(default_dev_program())

func _on_clear_program() -> void:
	_write_program([])

func _on_apply() -> void:
	if draft == null or not bool(draft.call("is_valid")):
		return
	var type_id: int = 0 if _type_option == null else _type_option.selected
	draft_applied.emit(draft.duplicate_genome(), type_id)
	visible = false

func _on_default() -> void:
	_reset_draft_data()
	_sync_controls()

func get_draft() -> RefCounted:
	return draft

func get_dev_program() -> Array:
	return [] if draft == null else draft.get("dev_program")

func set_dev_program(program: Array) -> bool:
	if draft == null or not bool(draft.call("set_development_program", program)):
		return false
	_rebuild_dev_rows()
	_refresh_dev_preview()
	return true

func get_type_id() -> int:
	return 0 if _type_option == null else _type_option.selected
