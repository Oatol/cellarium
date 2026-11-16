extends Control
## 细胞编辑页：把 8 组型 / 呼吸方式 / 18 种细胞类型编辑为可落地的 GNP1 基因组。
## 只写本地草案，不碰模拟状态；点「装载到合成器」后经 HUD → CommandBus 才生效。

signal draft_applied(genome: RefCounted, type_id: int)

const GENOME_SCRIPT: Script = preload("res://scripts/core/data/Genome.gd")
const CATALOG: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

const TRAITS: Array[String] = ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const RESPIRATION: Array[String] = ["兼性", "好氧", "厌氧"]

@export var trait_rows_path: NodePath = ^"Panel/Content/TraitRows"
@export var type_option_path: NodePath = ^"Panel/Content/ConfigRow/TypeOption"
@export var respiration_option_path: NodePath = ^"Panel/Content/ConfigRow/RespirationOption"
@export var apply_button_path: NodePath = ^"Panel/Content/ActionRow/ApplyButton"
@export var default_button_path: NodePath = ^"Panel/Content/ActionRow/DefaultButton"
@export var close_button_path: NodePath = ^"Panel/Content/ActionRow/CloseButton"

var draft: RefCounted = null
var _value_labels: Array[Label] = []
var _type_option: OptionButton = null
var _respiration_option: OptionButton = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	draft = (GENOME_SCRIPT as Script).new() as RefCounted
	_reset_draft_data()
	_type_option = get_node_or_null(type_option_path) as OptionButton
	_respiration_option = get_node_or_null(respiration_option_path) as OptionButton
	_build_traits()
	_build_options()
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

func _reset_draft_data() -> void:
	if draft == null:
		return
	draft.set("version", 1)
	draft.set("flags", 0)
	draft.set("respiration", 1)
	draft.set("mutation_rate_exp", 0)
	draft.set("loci", PackedByteArray())
	draft.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	draft.call("set_development_program", [])

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
	if _respiration_option != null:
		_respiration_option.item_selected.connect(_on_respiration_selected)

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

func get_type_id() -> int:
	return 0 if _type_option == null else _type_option.selected
