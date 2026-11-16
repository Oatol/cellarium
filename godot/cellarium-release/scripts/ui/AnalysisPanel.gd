extends PanelContainer
## 生态分析面板（阶段5 观测）：绑定 OrganismManager 的生态报告，R 键开合。
## 容器在 main.tscn 声明，本脚本只填 Label 与刷新逻辑；数据全部来自报告快照，非手填文案。
## 语义 ID：ui://report/panel，供 Agent 自动化打开。

const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")

@export var organism_manager_path: NodePath = ^"../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../Simulation/TickCore"

var organism_manager: Node = null
var tick_core: Node = null
var _body: VBoxContainer = null
var _text: Label = null
var _visible_state: bool = false

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	# 场景可能被反复实例化（测试/热重载）：先清本命名空间旧注册再注册。
	SEMANTIC.call("clear_prefix", "ui://report/")
	SEMANTIC.call("register", "ui://report/panel", self)
	_body = VBoxContainer.new()
	var title: Label = Label.new()
	title.text = "生态报告 · R 关闭"
	title.add_theme_font_size_override("font_size", 15)
	_text = Label.new()
	_text.text = "—"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(title)
	_body.add_child(_text)
	add_child(_body)
	visible = false
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			_set_visible(not _visible_state)

## 供 Agent ui.click("ui://report/panel") 调用：切换面板。
func act() -> void:
	_set_visible(not _visible_state)

func _set_visible(value: bool) -> void:
	_visible_state = value
	visible = value
	if value:
		_refresh()

func _refresh() -> void:
	if organism_manager == null or _text == null:
		return
	var report: Dictionary = organism_manager.call("export_ecology_report") as Dictionary
	var series: Dictionary = report.get("population_series", {}) as Dictionary
	var panel: Dictionary = report.get("species_death_panel", {}) as Dictionary
	var facts: Array = report.get("facts", []) as Array
	var lines: Array[String] = []
	lines.append("采样点: %d" % int(report.get("sample_count", 0)))
	lines.append("物种数: %d" % series.size())
	lines.append("累计出生: %d | 死亡: %d" % [int(panel.get("births", 0)), int(panel.get("deaths", 0))])
	var causes: Dictionary = panel.get("death_causes", {}) as Dictionary
	for cause_key in causes:
		lines.append("  死因 %s: %d" % [str(cause_key), int(causes[cause_key])])
	if not facts.is_empty():
		lines.append("— 记录到的事实 —")
		for fact in facts:
			lines.append("· " + str(fact))
	_text.text = "\n".join(lines)
