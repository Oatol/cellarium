extends Control
## 统一「细胞编辑」面板：参考 Cell Lab / Macro 的编辑器布局（基因槽 + 分化程序 +
## 指令参数 + 规格参考 + 发育时间轴），吸收原「发育编辑」页的全部功能。
## 唯一发育真相源是 draft Genome 的 dev_program（DIVIDE/DIFFERENTIATE/LINK）。
## Cell Lab 专有的 40 Gene 槽 / Child1-4 / 信号 lane / 95 算子只作只读证据展示；GNP1 已冻结，
## 不写入编码、不臆造字段。编辑只改 draft；Apply 经 signal → GameHUD → CommandBus 进入模拟。
## 本面板不碰模拟状态、不改 dt；v0.14.1 起「生成黏附素」唯一例外，会写入 draft.flags bit0
## （GNP1 已编码字段的版本化语义追加），因此会改变该基因组的 hash；其余 Macro 字段仍只展示。

signal draft_applied(genome: RefCounted, type_id: int)

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")
const GENOME_PREVIEW_SCENE: PackedScene = preload("res://scenes/ui/GenomePreview.tscn")

const TRAITS: Array[String] = ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const OPCODE_NAMES: Array[String] = ["DIVIDE 分裂", "DIFFERENTIATE 分化", "LINK 连接"]
const OPCODE_SHORT: Array[String] = ["DIVIDE", "DIFF", "LINK"]
const MAX_DEV_INSTRUCTIONS: int = 64
const CHANNEL_NAMES: Array[String] = ["营养0", "温度1", "氧气2", "光照3", "信号4"]
const GENE_SLOT_COUNT: int = 40
const RESPIRATION: Array[String] = ["兼性", "好氧", "厌氧"]

## v0.13.0：Macro 编辑器字段作为可编辑草案展示；只改本面板 Dictionary，
## 不进入 dev_program。v0.14.1 例外：make_glue 映射到已存在的 Genome.flags bit0。
## 控件提示保留静态反编译字段来源。
const MACRO_FIELD_KEYS: Array[String] = [
	"cell_type", "make_glue", "child1", "child2", "child3", "child4",
	"child1_angle", "child2_angle", "child3_angle", "child4_angle",
	"split_mass", "invert_split_mass", "nutrition_priority",
	"split_angle", "split_angle2", "ratio", "ratio2",
	"stiffness", "cell_size", "max_connections", "min_connections",
	"stay_alive", "initial", "color_r", "color_g", "color_b",
]

@export var content_path: NodePath = ^"Panel/Content"

var draft: RefCounted = null
var _selected_instruction: int = 0
var _type_id: int = 0

var _content: VBoxContainer = null
var _tree_rows: VBoxContainer = null
var _tree_scroll: ScrollContainer = null
var _tree_fold_button: Button = null
var _tree_folded: bool = false
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
var _macro_draft: Dictionary = {}
var _macro_controls: Dictionary = {}
var _genome_preview: Node = null

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
	_macro_draft = default_macro_draft()
	_selected_instruction = 0

static func default_macro_draft() -> Dictionary:
	return {
		"cell_type": 0, "make_glue": false,
		"child1": 0, "child2": 0, "child3": 0, "child4": 0,
		"child1_angle": 0.0, "child2_angle": 0.25, "child3_angle": 0.5, "child4_angle": 0.75,
		"split_mass": 0.5, "invert_split_mass": false, "nutrition_priority": 0.5,
		"split_angle": 0.0, "split_angle2": 0.25, "ratio": 0.5, "ratio2": 0.5,
		"stiffness": 0.5, "cell_size": 1.0, "max_connections": 4, "min_connections": 0,
		"stay_alive": true, "initial": false,
		"color_r": 0.36, "color_g": 0.88, "color_b": 0.75,
	}

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

## 分裂模板：每条 DIVIDE 增加 1 个细胞；a=被分裂的母细胞索引，b=角度(0..255→0..360°)，
## c=亲子间距（世界单位，至少 2×静息半径，默认静态模板用 14）。
static func division_template(divide_count: int) -> Array[Dictionary]:
	var count: int = clampi(divide_count, 0, 8)
	var program: Array[Dictionary] = []
	# 始终从 0 号（合子）分裂，保持亲子链最短，避免引用还不存在的细胞索引。
	for i in range(count):
		program.append({"opcode": 0, "a": 0, "b": int(256 * i / maxi(1, count)) % 256, "c": 14})
	return program

static func instruction_help_text() -> String:
	return (
		"指令集（dev_program 从上到下按 tick 顺序执行，不做并行）\n"
		+ "① DIVIDE 分裂：a=被分裂的细胞索引（从 0 合子开始）；b=分裂角度 0–255（0=向右，64=向下，128=向左，192=向上）；c=亲子间距（世界单位，建议 14，太小会重叠）。每 1 条 DIVIDE 多 1 个细胞。\n"
		+ "② DIFFERENTIATE 分化：a=细胞索引；b=目标类型（光合 4、硝化 10 等，见表现类型下拉）；c 保留。\n"
		+ "③ LINK 连接：a/b=两个细胞索引；c=连接静息长度（14 起）。不填连接也能分裂，只是不构成协作体。\n"
		+ "不会分裂最常见原因：dev_program 里没有 DIVIDE，或只改了草案没点「装载合成器」并在皿内点击放置。用上面「分裂×1」模板即可立刻验证。"
	)

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
	var template_row: HBoxContainer = HBoxContainer.new()
	template_row.name = "TemplateRow"
	template_row.add_theme_constant_override("separation", 6)
	var template_label: Label = Label.new()
	template_label.text = "模板"
	template_label.tooltip_text = "一键装载常用发育程序；装载后仍需点「装载合成器」并在皿内点击放置"
	template_row.add_child(template_label)
	var presets: Array = [
		["单细胞", "0 次分裂：只有合子，不会发育出多细胞", 0],
		["分裂×1", "1 条 DIVIDE → 2 细胞（最容易验证分裂）", 1],
		["分裂×2", "2 条 DIVIDE → 3 细胞", 2],
		["分裂×3", "3 条 DIVIDE → 4 细胞", 3],
	]
	for preset in presets:
		var preset_button: Button = _make_button(str(preset[0]), str(preset[1]))
		preset_button.name = "Preset_%d" % int(preset[2])
		preset_button.pressed.connect(_on_load_division_template.bind(int(preset[2])))
		template_row.add_child(preset_button)
	var template_button: Button = _make_button("4 细胞模板", "装载 4 细胞协作体 dev_program（含分化与连接）")
	template_button.pressed.connect(_on_load_template)
	template_row.add_child(template_button)
	_content.add_child(template_row)

	var apply_button: Button = _make_button("装载合成器", "写入草案 → GameHUD → CommandBus；皿内点击放置")
	apply_button.pressed.connect(_on_apply)
	var default_button: Button = _make_button("恢复默认", "恢复 4 细胞模板草案")
	default_button.pressed.connect(_on_default)
	var close_button: Button = _make_button("关闭", "关闭面板")
	close_button.pressed.connect(func() -> void: visible = false)
	for button in [apply_button, default_button, close_button]:
		toolbar.add_child(button)
	_content.add_child(toolbar)

	# 指令集说明：把 dev_program 的三个 opcode 与 a/b/c 语义写清楚，避免「不会用、细胞不分裂」。
	var help_panel: PanelContainer = PanelContainer.new()
	help_panel.name = "InstructionHelp"
	var help_margin: MarginContainer = MarginContainer.new()
	help_margin.add_theme_constant_override("margin_left", 8)
	help_margin.add_theme_constant_override("margin_top", 5)
	help_margin.add_theme_constant_override("margin_right", 8)
	help_margin.add_theme_constant_override("margin_bottom", 5)
	var help_label: Label = Label.new()
	help_label.name = "InstructionHelpLabel"
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 11)
	help_label.text = instruction_help_text()
	help_margin.add_child(help_label)
	help_panel.add_child(help_margin)
	_content.add_child(help_panel)

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
	var timeline_scroll: ScrollContainer = ScrollContainer.new()
	timeline_scroll.name = "TimelineScroll"
	timeline_scroll.custom_minimum_size = Vector2(0, 52)
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	timeline_scroll.add_child(_timeline_rows)
	timeline_box.add_child(timeline_title)
	timeline_box.add_child(timeline_scroll)
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
	box.add_child(_make_section_title("GENOME PREVIEW · 发育预览（只读，不跑第二套模拟）"))
	_genome_preview = (GENOME_PREVIEW_SCENE as PackedScene).instantiate()
	_genome_preview.name = "GenomePreview"
	box.add_child(_genome_preview)
	box.add_child(_make_section_title("GENE SLOTS · 40 槽（前 8 槽 = GNP1 八性状）"))
	box.add_child(_build_gene_slots())
	box.add_child(_make_section_title("DEV · 分化程序 / 指令序列"))
	_tree_counter = Label.new()
	_tree_counter.text = "指令 0 / %d" % MAX_DEV_INSTRUCTIONS
	# 标题行：折叠按钮 + 计数，避免指令很多时把面板撑到超出屏幕。
	var tree_header: HBoxContainer = HBoxContainer.new()
	_tree_fold_button = _make_button("折叠指令", "折叠/展开指令序列（内容始终保留，只是不占纵向空间）")
	_tree_fold_button.custom_minimum_size = Vector2(96, 24)
	_tree_fold_button.pressed.connect(_on_toggle_tree_fold)
	tree_header.add_child(_tree_fold_button)
	tree_header.add_child(_tree_counter)
	box.add_child(tree_header)
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.name = "InstructionScroll"
	_tree_scroll.custom_minimum_size = Vector2(0, 150)
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tree_rows = VBoxContainer.new()
	_tree_rows.name = "InstructionRows"
	_tree_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.add_child(_tree_rows)
	box.add_child(_tree_scroll)
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
	panel.custom_minimum_size = Vector2(340, 0)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "MacroReferenceScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_section_title("MACRO DRAFT · 发育字段草案（不写 GNP1）"))
	var note: Label = Label.new()
	note.text = "以下控件对应 Cell Lab Macro 的 Gene 字段与子代设置；当前仅存本页草案，Apply 不会写入冻结 GNP1 或确定性 hash。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	box.add_child(note)

	box.add_child(_make_section_title("TYPE / ADHESIN · 类型与黏附"))
	box.add_child(_make_macro_type_option("cell_type", "细胞类型", "spinner_types → Gene.C"))
	box.add_child(_make_macro_check("make_glue", "生成黏附素", "checkbox_make_glue → Gene.E；本项目 v0.14.1 写入 flags bit0：子代自动连接，无需 LINK 指令"))
	box.add_child(_make_macro_check("stay_alive", "保持存活", "checkbox_stay_alive → Gene.H"))
	box.add_child(_make_macro_check("initial", "初始细胞", "radio_initial → Gene.I"))

	box.add_child(_make_section_title("CHILD 1–4 · 子代类型与角度"))
	for child_index in range(1, 5):
		var key: String = "child%d" % child_index
		box.add_child(_make_macro_type_option(key, "子代 %d 类型" % child_index, "spinner_child%d → Gene.f778r/s/t/u" % child_index))
		var angle_key: String = "child%d_angle" % child_index
		box.add_child(_make_macro_slider(angle_key, "子代 %d 角度" % child_index, 0.0, 1.0, 0.01,
			"seek_child%d_angle → Gene.f771k/f772l/z/A ÷ TAU" % child_index, 2))

	box.add_child(_make_section_title("SPLIT · 分裂质量 / 角度 / 优先级"))
	box.add_child(_make_macro_slider("split_mass", "分裂质量", 0.0, 1.0, 0.01, "seek_mass → splitMassFraction(Gene)", 2))
	box.add_child(_make_macro_check("invert_split_mass", "反转分裂质量", "check_invert_split_mass → Gene.f768h"))
	box.add_child(_make_macro_slider("nutrition_priority", "营养优先级", 0.0, 1.0, 0.01, "seek_prio → Gene.f773m", 2))
	box.add_child(_make_macro_slider("split_angle", "分裂角度 1", 0.0, 1.0, 0.01, "seek_splitangle → Gene.f770j ÷ TAU", 2))
	box.add_child(_make_macro_slider("split_angle2", "分裂角度 2", 0.0, 1.0, 0.01, "seek_splitangle2 → Gene.B ÷ TAU", 2))
	box.add_child(_make_macro_slider("ratio", "子代比例 1", 0.0, 1.0, 0.01, "seek_ratio → Gene.f769i", 2))
	box.add_child(_make_macro_slider("ratio2", "子代比例 2", 0.0, 1.0, 0.01, "seek_ratio2 → Gene.C", 2))

	box.add_child(_make_section_title("PHYSICAL / COLOR · 数值草案"))
	box.add_child(_make_macro_slider("stiffness", "细胞骨架强度", 0.0, 1.0, 0.01, "seek_stiff → Gene.f774n", 2))
	box.add_child(_make_macro_slider("cell_size", "细胞大小", 0.5, 2.0, 0.01, "Macro 编辑器尺寸控件；本项目半径由 CellShape 冻结", 2))
	box.add_child(_make_macro_slider("max_connections", "最大连接数", 0.0, 16.0, 1.0, "Macro 编辑器连接控件；仅草案", 0))
	box.add_child(_make_macro_slider("min_connections", "最小连接数", 0.0, 16.0, 1.0, "Macro 编辑器连接控件；仅草案", 0))
	box.add_child(_make_macro_slider("color_r", "颜色 R", 0.0, 1.0, 0.01, "Macro RGB 控件；仅草案", 2))
	box.add_child(_make_macro_slider("color_g", "颜色 G", 0.0, 1.0, 0.01, "Macro RGB 控件；仅草案", 2))
	box.add_child(_make_macro_slider("color_b", "颜色 B", 0.0, 1.0, 0.01, "Macro RGB 控件；仅草案", 2))

	box.add_child(_make_section_title("REFERENCE · 证据边界"))
	var reference: Label = Label.new()
	reference.text = "\n".join([
		"40 Gene 槽：Cell.I[40]；仅前 8 槽映射 GNP1 八性状。",
		"信号 lane / 95 突变算子：APK 静态证据，未在本页展开编辑。",
		"On contact(Cell/Wall/Split)、Secretion：同属 Macro 专有字段。",
		"GNP1 / dev_program 仍是本项目唯一可落地真相源。",
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
	scroll.add_child(box)
	margin.add_child(scroll)
	panel.add_child(margin)
	_refresh_macro_controls()
	return panel

func _make_macro_section_label(text_value: String) -> Label:
	return _make_section_title(text_value)

func _make_macro_check(key: String, label_text: String, tip: String) -> CheckBox:
	var check: CheckBox = CheckBox.new()
	check.text = label_text
	check.tooltip_text = tip
	check.set_meta("macro_key", key)
	check.toggled.connect(_on_macro_bool_changed.bind(key))
	_macro_controls[key] = {"check": check}
	return check

func _make_macro_type_option(key: String, label_text: String, tip: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(104, 0)
	label.tooltip_text = tip
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size = Vector2(130, 0)
	option.tooltip_text = tip
	for entry in VISUALS.call("entries"):
		option.add_item("%d %s" % [int(entry.get("id", 0)), str(entry.get("label", "?"))])
	option.set_meta("macro_key", key)
	option.item_selected.connect(_on_macro_option_changed.bind(key))
	_macro_controls[key] = {"option": option}
	row.add_child(label)
	row.add_child(option)
	return row

func _make_macro_slider(key: String, label_text: String, minimum: float, maximum: float, step: float, tip: String, digits: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(104, 0)
	label.tooltip_text = tip
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(126, 0)
	slider.tooltip_text = tip
	slider.set_meta("macro_key", key)
	slider.value_changed.connect(_on_macro_value_changed.bind(key))
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(42, 0)
	_macro_controls[key] = {"slider": slider, "value_label": value_label, "digits": digits}
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	return row

func _refresh_macro_controls() -> void:
	for key in MACRO_FIELD_KEYS:
		if not _macro_draft.has(key) or not _macro_controls.has(key):
			continue
		var control: Dictionary = _macro_controls[key]
		var value: Variant = _macro_draft[key]
		if control.has("check"):
			(control["check"] as CheckBox).set_pressed_no_signal(bool(value))
		elif control.has("option"):
			(control["option"] as OptionButton).select(clampi(int(value), 0, (control["option"] as OptionButton).item_count - 1))
		elif control.has("slider"):
			var slider: HSlider = control["slider"] as HSlider
			slider.set_value_no_signal(float(value))
			(control["value_label"] as Label).text = _format_macro_value(key, float(value), int(control.get("digits", 2)))

func _format_macro_value(_key: String, value: float, digits: int) -> String:
	return String.num(value, digits)

func _on_macro_bool_changed(value: bool, key: String) -> void:
	_macro_draft[key] = value
	if key == "make_glue":
		_sync_glue_flag()
	_set_macro_status(key)

## v0.14.1：黏附素勾选写入 Genome.flags bit0（已编码字段，不新增 schema）。
## DIVIDE 执行时读该位自动 link 亲子，用户无需再写 LINK 指令。
func _sync_glue_flag() -> void:
	if draft == null:
		return
	var flag: int = int((GENOME_SCRIPT as Script).get_script_constant_map().get("FLAG_GLUE_LINKS", 1))
	var value: int = int(draft.get("flags"))
	if bool(_macro_draft.get("make_glue", false)):
		value |= flag
	else:
		value &= ~flag
	draft.set("flags", value)

func _on_macro_option_changed(index: int, key: String) -> void:
	_macro_draft[key] = index
	_set_macro_status(key)

func _on_macro_value_changed(value: float, key: String) -> void:
	if key == "max_connections" or key == "min_connections":
		_macro_draft[key] = int(round(value))
	else:
		_macro_draft[key] = value
	var control: Dictionary = _macro_controls.get(key, {})
	if control.has("value_label"):
		(control["value_label"] as Label).text = _format_macro_value(key, value, int(control.get("digits", 2)))
	_set_macro_status(key)

func _set_macro_status(key: String) -> void:
	if _status_label == null:
		return
	if key == "make_glue":
		var on: bool = bool(_macro_draft.get("make_glue", false))
		_status_label.text = "生成黏附素%s：子代自动连接（写入 flags bit0，影响该基因组 hash）；其余 Macro 字段仅展示。" % ("已开启" if on else "已关闭")
		return
	_status_label.text = "Macro 草案已改：%s · 仅本页展示，不写 GNP1 / dev_program / 确定性 hash。" % key

func get_macro_draft() -> Dictionary:
	return (_macro_draft as Dictionary).duplicate(true)

func _refresh_all() -> void:
	_refresh_tree()
	_refresh_params()
	_refresh_traits()
	_refresh_macro_controls()
	_refresh_timeline()
	_refresh_summary()
	_sync_preview()

func _sync_preview() -> void:
	if _genome_preview == null or not _genome_preview.has_method("set_program"):
		return
	_genome_preview.call("set_program", _program(), _macro_draft)

func _program() -> Array:
	return [] if draft == null else draft.get("dev_program")

func _write_program(program: Array) -> void:
	if draft == null or not bool(draft.call("set_development_program", program)):
		return
	_selected_instruction = clampi(_selected_instruction, 0, maxi(0, program.size() - 1))
	_refresh_all()

func _on_toggle_tree_fold() -> void:
	_tree_folded = not _tree_folded
	if _tree_scroll != null:
		_tree_scroll.visible = not _tree_folded
	if _tree_fold_button != null:
		_tree_fold_button.text = "展开指令" if _tree_folded else "折叠指令"

func _refresh_tree() -> void:
	if _tree_rows == null:
		return
	if _tree_counter != null:
		_tree_counter.text = "指令 %d / %d" % [_program().size(), MAX_DEV_INSTRUCTIONS]
	if _tree_folded:
		# 折叠时不重建行内容：下次展开时 _refresh_tree 会按最新 program 重画。
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
		0: return "DIVIDE：a 母细胞索引 · b 角度(0..255) · c 亲子间距(建议14)"
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

func _on_load_division_template(divide_count: int) -> void:
	_write_program(division_template(divide_count))
	_selected_instruction = 0
	_refresh_all()
	if _status_label != null:
		_status_label.text = "已装载「分裂×%d」模板：%d 条 DIVIDE → %d 细胞；点「装载合成器」后在皿内点击放置" % [divide_count, divide_count, divide_count + 1]

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
	_sync_glue_flag()
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
	var glue_text: String = " · 黏附素自动连接" if bool(_macro_draft.get("make_glue", false)) else ""
	return "细胞编辑草案：%d 指令 · 类型 %d · Macro 草案 %d 项%s" % [program.size(), _type_id, _macro_draft.size(), glue_text]
