extends Control
## 统一「细胞编辑」面板：参考 Cell Lab / Macro 的编辑器布局（基因槽 + 分化程序 +
## 指令参数 + 规格参考 + 发育时间轴），吸收原「发育编辑」页的全部功能。
## 唯一发育真相源是 draft Genome 的 dev_program（DIVIDE/DIFFERENTIATE/LINK）。
## Cell Lab 专有的 40 Gene 槽 / Child1-4 / 信号 lane / 95 算子只作只读证据展示；GNP1 已冻结，
## 不写入编码、不臆造字段。编辑只改 draft；Apply 经 signal → GameHUD → CommandBus 进入模拟。
## 本面板不碰模拟状态、不改 dt、不改确定性 hash。

signal draft_applied(genome: RefCounted, type_id: int)

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

const TRAITS: Array[String] = ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const OPCODE_NAMES: Array[String] = ["DIVIDE 分裂", "DIFFERENTIATE 分化", "LINK 连接"]
const OPCODE_SHORT: Array[String] = ["DIVIDE", "DIFF", "LINK"]
const MAX_DEV_INSTRUCTIONS: int = 64
const CHANNEL_NAMES: Array[String] = ["营养0", "温度1", "氧气2", "光照3", "信号4"]
const GENE_SLOT_COUNT: int = 40
const RESPIRATION: Array[String] = ["兼性", "好氧", "厌氧"]

@export var content_path: NodePath = ^"Panel/Content"

var draft: RefCounted = null
var _selected_instruction: int = 0
var _type_id: int = 0

var _content: VBoxContainer = null
var _tree_rows: VBoxContainer = null
var _tree_counter: Label = null
var _param_opcode: OptionButton = null
var _param_a: SpinBox = null
var _param_b: SpinBox = null
var _param_c: SpinBox = null
var _param_hint: Label = null
var _trait_sliders: Array[HSlider] = []
var _trait_labels: Array[Label] = []
var _timeline_rows: HBoxContainer = null
var _summary_label: Label = null
var _type_option: OptionButton = null
var _respiration_option: OptionButton = null
var _status_label: Label = null
var _gene_slot_labels: Array[Label] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_content = get_node_or_null(content_path) as VBoxContainer
	draft = (GENOME_SCRIPT as Script).new() as RefCounted
	_reset_draft()
	_build_ui()
	_refresh_all()

func _reset_draft() -> void:
	if draft == null:
		return
	draft.set("version", 1)
	draft.set("flags", 0)
	draft.set("respiration", 1)
	draft.set("mutation_rate_exp", 0)
	draft.set("loci", PackedByteArray())
	draft.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	draft.call("set_development_program", default_dev_program())
	_selected_instruction = 0

static func default_dev_program() -> Array[Dictionary]:
	# 4 细胞协作模板：结构核 + 运动/能量/信息三类分化，三条 LINK 连成一体。
	# DIVIDE.c = 分裂间距；LINK.c = 静息长度。与原细胞编辑页完全一致的确定性模板。
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

func _make_button(text_value: String, tip: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(84, 28)
	return button

func _make_section_title(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 14)
	return label

func _build_ui() -> void:
	if _content == null:
		return
	var title: Label = _make_section_title("细胞编辑 · CELL EDITOR · 参考 Cell Lab / Macro")
	_content.add_child(title)

	# 顶部工具条：表现类型 + 呼吸方式 + 模板 + Apply（写入仍只经 CommandBus）。
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	var type_label: Label = Label.new()
	type_label.text = "表现类型"
	_type_option = OptionButton.new()
	_type_option.custom_minimum_size = Vector2(150, 0)
	for entry in VISUALS.call("entries"):
		_type_option.add_item("%d %s" % [int(entry.get("id", 0)), str(entry.get("label", "?"))])
	toolbar.add_child(type_label)
	toolbar.add_child(_type_option)
	var respiration_label: Label = Label.new()
	respiration_label.text = "呼吸"
	_respiration_option = OptionButton.new()
	_respiration_option.custom_minimum_size = Vector2(84, 0)
	for name_value in RESPIRATION:
		_respiration_option.add_item(name_value)
	_respiration_option.selected = 1
	_respiration_option.item_selected.connect(_on_respiration_selected)
	toolbar.add_child(respiration_label)
	toolbar.add_child(_respiration_option)
	var template_button: Button = _make_button("4 细胞模板", "装载 4 细胞协作体 dev_program")
	template_button.pressed.connect(_on_load_template)
	var single_button: Button = _make_button("单细胞", "清空 dev_program，仅保留合子")
	single_button.pressed.connect(_on_clear_program)
	var apply_button: Button = _make_button("装载合成器", "写入草案 → GameHUD → CommandBus；皿内点击放置")
	apply_button.pressed.connect(_on_apply)
	var default_button: Button = _make_button("恢复默认", "恢复 4 细胞模板草案")
	default_button.pressed.connect(_on_default)
	var close_button: Button = _make_button("关闭", "关闭面板")
	close_button.pressed.connect(func() -> void: visible = false)
	for button in [template_button, single_button, apply_button, default_button, close_button]:
		toolbar.add_child(button)
	_content.add_child(toolbar)

	# 主体三栏。
	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(0, 420)
	body.add_child(_build_left_panel())
	body.add_child(_build_center_panel())
	body.add_child(_build_right_panel())
	_content.add_child(body)

	# 底部时间轴。
	var timeline_panel: PanelContainer = PanelContainer.new()
	timeline_panel.custom_minimum_size = Vector2(0, 96)
	var timeline_margin: MarginContainer = MarginContainer.new()
	timeline_margin.add_theme_constant_override("margin_left", 8)
	timeline_margin.add_theme_constant_override("margin_top", 6)
	timeline_margin.add_theme_constant_override("margin_right", 8)
	timeline_margin.add_theme_constant_override("margin_bottom", 6)
	var timeline_box: VBoxContainer = VBoxContainer.new()
	var timeline_title: Label = Label.new()
	timeline_title.text = "DEV TIMELINE · 指令按 tick 顺序执行 · 仅 UI 表达，不缩放 dt"
	timeline_title.add_theme_font_size_override("font_size", 12)
	_timeline_rows = HBoxContainer.new()
	_timeline_rows.add_theme_constant_override("separation", 4)
	timeline_box.add_child(timeline_title)
	timeline_box.add_child(_timeline_rows)
	timeline_margin.add_child(timeline_box)
	timeline_panel.add_child(timeline_margin)
	_content.add_child(timeline_panel)

	_status_label = Label.new()
	_status_label.text = "左栏基因槽/分化程序 → 中栏参数 → 右栏规格 → 底部时间轴；Apply 后经 CommandBus 落地。"
	_content.add_child(_status_label)

func _build_left_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_section_title("GENE SLOTS · 40 槽（前 8 槽 = GNP1 八性状）"))
	box.add_child(_build_gene_slots())
	box.add_child(_make_section_title("DEV · 分化程序 / 指令序列"))
	_tree_counter = Label.new()
	_tree_counter.text = "指令 0 / %d" % MAX_DEV_INSTRUCTIONS
	box.add_child(_tree_counter)
	_tree_rows = VBoxContainer.new()
	_tree_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tree_rows)
	var actions: HBoxContainer = HBoxContainer.new()
	var add_button: Button = _make_button("+ 指令", "追加一条 DIVIDE")
	add_button.pressed.connect(_on_add_instruction)
	var up_button: Button = _make_button("↑", "上移选中指令")
	up_button.pressed.connect(_on_move_up)
	var down_button: Button = _make_button("↓", "下移选中指令")
	down_button.pressed.connect(_on_move_down)
	var remove_button: Button = _make_button("×", "删除选中指令")
	remove_button.pressed.connect(_on_remove_instruction)
	for button in [add_button, up_button, down_button, remove_button]:
		actions.add_child(button)
	box.add_child(actions)
	var note: Label = Label.new()
	note.text = "Cell Lab：Cell.I[40] 运行时 40 槽；本项目 GNP1 冻结，以 dev_program 为真相源。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	box.add_child(note)
	margin.add_child(box)
	panel.add_child(margin)
	return panel

## Cell Lab 的 40 Gene 槽在本项目只做可视化：前 8 槽对应 GNP1 八性状，
## 后 32 槽是只读占位（GNP1 冻结，不臆造字段、不写入编码）。
func _build_gene_slots() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for i in range(GENE_SLOT_COUNT):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(28, 22)
		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		if i < TRAITS.size():
			label.text = TRAITS[i]
			label.tooltip_text = "GNP1 性状 %d · 在中栏滑块编辑" % i
		else:
			label.text = "—"
			label.tooltip_text = "GNP1 冻结：Cell Lab 专有第 %d 槽，本项目不写入" % i
		slot.add_child(label)
		_gene_slot_labels.append(label)
		grid.add_child(slot)
	return grid

func _refresh_gene_slots() -> void:
	if draft == null or _gene_slot_labels.is_empty():
		return
	var traits: PackedByteArray = draft.get("traits")
	for i in range(mini(_gene_slot_labels.size(), TRAITS.size())):
		_gene_slot_labels[i].text = "%s %d" % [TRAITS[i], int(traits[i]) if i < traits.size() else 0]

func _build_center_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_section_title("PARAM · 指令参数 / GNP1 八性状"))

	_param_opcode = OptionButton.new()
	for name_value in OPCODE_NAMES:
		_param_opcode.add_item(name_value)
	_param_opcode.item_selected.connect(_on_opcode_changed)
	box.add_child(_param_opcode)
	_param_hint = Label.new()
	_param_hint.add_theme_font_size_override("font_size", 10)
	box.add_child(_param_hint)

	_param_a = _make_operand_spin("a", 255)
	_param_b = _make_operand_spin("b", 255)
	_param_c = _make_operand_spin("c", 1023)
	box.add_child(_labeled_spin("a", _param_a))
	box.add_child(_labeled_spin("b", _param_b))
	box.add_child(_labeled_spin("c", _param_c))

	box.add_child(_make_section_title("GNP1 八性状（染色体组型）"))
	for i in range(TRAITS.size()):
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.text = TRAITS[i]
		label.custom_minimum_size = Vector2(64, 0)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 255.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(180, 0)
		slider.value_changed.connect(_on_trait_changed.bind(i))
		var value_label: Label = Label.new()
		value_label.custom_minimum_size = Vector2(36, 0)
		row.add_child(label)
		row.add_child(slider)
		row.add_child(value_label)
		box.add_child(row)
		_trait_sliders.append(slider)
		_trait_labels.append(value_label)

	margin.add_child(box)
	panel.add_child(margin)
	return panel

func _make_operand_spin(key: String, maximum: int) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = float(maximum)
	spin.step = 1.0
	spin.custom_minimum_size = Vector2(96, 0)
	spin.set_meta("operand_key", key)
	spin.value_changed.connect(_on_operand_changed.bind(key))
	return spin

func _labeled_spin(label_text: String, spin: SpinBox) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(24, 0)
	row.add_child(label)
	row.add_child(spin)
	return row

func _build_right_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_section_title("REFERENCE · Cell Lab 专有字段（只读证据）"))
	var reference: Label = Label.new()
	reference.text = "\n".join([
		"40 Gene 槽：Cell.I[40]，分裂按 Gene.i/j 重连（1/5 概率）",
		"Child 1–4：split mass / ratio / angle",
		"行为项：Make adhesin / Stay alive / Initial / Prioritize",
		"接触处理：On contact(Cell/Wall/Split) / Secretion",
		"数值控件：Cytoskeleton / Adhesin stiffness / Max connections / RGB",
		"dev_* 规则：After N splits→M / Differentiation / Conditional",
		"信号 lane：Add/Rename/Delete，output channel",
		"95 突变算子：nextInt(95)，逐编号语义未展开",
		"",
		"以上为 APK 静态解析证据。GNP1 架构冻结，以上字段不写入本项目编码；",
		"本编辑器以 dev_program（DIVIDE/DIFFERENTIATE/LINK）为唯一发育真相源。",
	])
	reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference.add_theme_font_size_override("font_size", 10)
	box.add_child(reference)

	box.add_child(_make_section_title("发育规则摘要（来自 dev_program）"))
	var summary: Label = Label.new()
	summary.name = "RuleSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 10)
	box.add_child(summary)
	_summary_label = summary
	margin.add_child(box)
	panel.add_child(margin)
	return panel

func _refresh_all() -> void:
	_refresh_tree()
	_refresh_params()
	_refresh_traits()
	_refresh_timeline()
	_refresh_summary()

func _program() -> Array:
	return [] if draft == null else draft.get("dev_program")

func _write_program(program: Array) -> void:
	if draft == null or not bool(draft.call("set_development_program", program)):
		return
	_selected_instruction = clampi(_selected_instruction, 0, maxi(0, program.size() - 1))
	_refresh_all()

func _refresh_tree() -> void:
	if _tree_rows == null:
		return
	for child in _tree_rows.get_children():
		child.queue_free()
	var program: Array = _program()
	if _tree_counter != null:
		_tree_counter.text = "指令 %d / %d" % [program.size(), MAX_DEV_INSTRUCTIONS]
	for i in range(program.size()):
		var instruction: Dictionary = program[i]
		var opcode: int = clampi(int(instruction.get("opcode", 0)), 0, OPCODE_SHORT.size() - 1)
		var button: Button = Button.new()
		button.text = "%02d · %s  a%d b%d c%d" % [i, OPCODE_SHORT[opcode],
			int(instruction.get("a", 0)), int(instruction.get("b", 0)), int(instruction.get("c", 0))]
		button.toggle_mode = true
		button.set_pressed_no_signal(i == _selected_instruction)
		button.set_meta("instruction_index", i)
		button.pressed.connect(_on_tree_selected.bind(i))
		_tree_rows.add_child(button)
	if program.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "（无指令 · 单细胞合子）"
		_tree_rows.add_child(empty_label)

func _refresh_params() -> void:
	var program: Array = _program()
	if _selected_instruction < 0 or _selected_instruction >= program.size():
		if _param_opcode != null:
			_param_opcode.selected = -1
		return
	var instruction: Dictionary = program[_selected_instruction]
	var opcode: int = clampi(int(instruction.get("opcode", 0)), 0, OPCODE_NAMES.size() - 1)
	if _param_opcode != null:
		_param_opcode.set_item_text(opcode, OPCODE_NAMES[opcode])
		if _param_opcode.selected != opcode:
			_param_opcode.selected = opcode
	if _param_hint != null:
		_param_hint.text = _operand_hint(opcode) + "（a/b 0–255 · c 0–1023）"
	if _param_a != null:
		_param_a.set_value_no_signal(float(int(instruction.get("a", 0))))
	if _param_b != null:
		_param_b.set_value_no_signal(float(int(instruction.get("b", 0))))
	if _param_c != null:
		_param_c.set_value_no_signal(float(int(instruction.get("c", 0))))

func _operand_hint(opcode: int) -> String:
	match opcode:
		0: return "DIVIDE：a 子代类型 · b 分裂角度 · c 间距"
		1: return "DIFFERENTIATE：a 细胞索引 · b 目标类型 · c 保留"
		2: return "LINK：a 细胞 A · b 细胞 B · c 静息长度"
		_: return "a / b / c"

func _refresh_traits() -> void:
	if draft == null:
		return
	var traits: PackedByteArray = draft.get("traits")
	for i in range(_trait_sliders.size()):
		var value: int = int(traits[i]) if i < traits.size() else 0
		_trait_sliders[i].set_value_no_signal(float(value))
		_trait_labels[i].text = str(value)
	_refresh_gene_slots()

func _refresh_timeline() -> void:
	if _timeline_rows == null:
		return
	for child in _timeline_rows.get_children():
		child.queue_free()
	var program: Array = _program()
	for i in range(program.size()):
		var instruction: Dictionary = program[i]
		var opcode: int = clampi(int(instruction.get("opcode", 0)), 0, OPCODE_SHORT.size() - 1)
		var button: Button = Button.new()
		button.text = "t=%d %s" % [i + 1, OPCODE_SHORT[opcode]]
		button.custom_minimum_size = Vector2(88, 26)
		button.toggle_mode = true
		button.set_pressed_no_signal(i == _selected_instruction)
		button.pressed.connect(_on_tree_selected.bind(i))
		_timeline_rows.add_child(button)

func _refresh_summary() -> void:
	var summary: Label = _summary_label
	if summary == null:
		summary = _find_label_by_name("RuleSummary")
	if summary == null:
		return
	var program: Array = _program()
	var divides: int = 0
	var diffs: int = 0
	var links: int = 0
	for instruction in program:
		match int(instruction.get("opcode", -1)):
			0: divides += 1
			1: diffs += 1
			2: links += 1
	summary.text = "分裂 %d 条 → 预期细胞数 %d\n分化 %d 条 · 连接 %d 条\n发育完成需 %d tick（1× 下 %d 秒）\n成熟后由自主生命周期按能量继续分裂。" % [
		divides, 1 + divides, diffs, links, program.size(), program.size()
	]

func _find_label_by_name(node_name: String) -> Label:
	if _content == null:
		return null
	for candidate in _content.find_children("*", "Label", true, false):
		if candidate.name == node_name:
			return candidate as Label
	return null

func _on_tree_selected(index: int) -> void:
	_selected_instruction = clampi(index, 0, maxi(0, _program().size() - 1))
	_refresh_tree()
	_refresh_params()
	_refresh_timeline()

func _on_opcode_changed(index: int) -> void:
	var program: Array = _program()
	if _selected_instruction < 0 or _selected_instruction >= program.size():
		return
	program[_selected_instruction]["opcode"] = clampi(index, 0, 2)
	draft.set("dev_program", program)
	_refresh_tree()
	_refresh_timeline()
	_refresh_summary()
	_refresh_params()

func _on_operand_changed(value: float, key_or_index: Variant, maybe_key: String = "") -> void:
	# 兼容两种调用：中栏 SpinBox (value, key) 与旧版快速表 (value, instruction_index, key)。
	var instruction_index: int = _selected_instruction
	var key: String = str(key_or_index)
	if not maybe_key.is_empty():
		instruction_index = int(key_or_index)
		key = maybe_key
	var program: Array = _program()
	if instruction_index < 0 or instruction_index >= program.size():
		return
	program[instruction_index][key] = clampi(int(round(value)), 0, 1023 if key == "c" else 255)
	draft.set("dev_program", program)
	_refresh_tree()
	_refresh_timeline()
	_refresh_summary()

func _on_respiration_selected(index: int) -> void:
	if draft != null:
		draft.set("respiration", clampi(index, 0, RESPIRATION.size() - 1))

func _on_trait_changed(value: float, index: int) -> void:
	if draft == null or index < 0 or index >= TRAITS.size():
		return
	var traits: PackedByteArray = draft.get("traits")
	traits[index] = clampi(int(round(value)), 0, 255)
	draft.set("traits", traits)
	if index < _trait_labels.size():
		_trait_labels[index].text = str(int(traits[index]))
	_refresh_gene_slots()

func _on_add_instruction() -> void:
	var program: Array = _program()
	if program.size() >= MAX_DEV_INSTRUCTIONS:
		return
	program.append({"opcode": 0, "a": 0, "b": 0, "c": 14})
	_selected_instruction = program.size() - 1
	_write_program(program)

func _on_remove_instruction(instruction_index: int = -1) -> void:
	var program: Array = _program()
	if program.is_empty():
		return
	var target: int = clampi(instruction_index if instruction_index >= 0 else _selected_instruction, 0, program.size() - 1)
	program.remove_at(target)
	_selected_instruction = clampi(target, 0, maxi(0, program.size() - 1))
	_write_program(program)

func _on_move_up() -> void:
	var program: Array = _program()
	if _selected_instruction <= 0 or _selected_instruction >= program.size():
		return
	var temp: Dictionary = program[_selected_instruction]
	program[_selected_instruction] = program[_selected_instruction - 1]
	program[_selected_instruction - 1] = temp
	_selected_instruction -= 1
	_write_program(program)

func _on_move_down() -> void:
	var program: Array = _program()
	if _selected_instruction < 0 or _selected_instruction >= program.size() - 1:
		return
	var temp: Dictionary = program[_selected_instruction]
	program[_selected_instruction] = program[_selected_instruction + 1]
	program[_selected_instruction + 1] = temp
	_selected_instruction += 1
	_write_program(program)

func _on_load_template() -> void:
	_write_program(default_dev_program())
	_selected_instruction = 0
	_refresh_all()

func _on_clear_program() -> void:
	_write_program([])

func _on_default() -> void:
	_reset_draft()
	_refresh_all()

func _on_apply() -> void:
	if draft == null or not bool(draft.call("is_valid")):
		if _status_label != null:
			_status_label.text = "草案无效：指令数超过 %d 或操作数越界" % MAX_DEV_INSTRUCTIONS
		return
	_type_id = 0 if _type_option == null else _type_option.selected
	draft_applied.emit(draft.duplicate_genome(), _type_id)
	visible = false

## 供 GameHUD / 测试读取当前草案（与旧细胞编辑页同 API）。
func get_draft() -> RefCounted:
	return draft

func get_dev_program() -> Array:
	return _program()

func set_dev_program(program: Array) -> bool:
	_write_program(program)
	return true

func get_type_id() -> int:
	return 0 if _type_option == null else _type_option.selected

## 供 GameHUD 读取当前草案摘要（反馈用）。
func draft_summary() -> String:
	var program: Array = _program()
	return "细胞编辑草案：%d 指令 · 类型 %d" % [program.size(), _type_id]
