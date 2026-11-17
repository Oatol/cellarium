extends PanelContainer
## 生态分析面板（阶段5 观测）：绑定 OrganismManager 的生态报告，R 键开合。
## 容器在 main.tscn 声明，本脚本只填 Label 与刷新逻辑；数据全部来自报告快照，非手填文案。
## 同时承载细胞诊断：INSPECT 工具写入 last_inspection 后自动弹出显示逐项状态。
## 语义 ID：ui://report/panel，供 Agent 自动化打开。

const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")
const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"

var organism_manager: Node = null
var tick_core: Node = null
var _body: VBoxContainer = null
var _text: Label = null
var _inspect_title: Label = null
var _inspect_text: Label = null
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
	_inspect_title = Label.new()
	_inspect_title.text = "细胞诊断 · 点击细胞后显示"
	_inspect_title.add_theme_font_size_override("font_size", 15)
	_inspect_text = Label.new()
	_inspect_text.text = "（用「细胞诊断」工具点击皿内细胞）"
	_inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_inspect_title)
	_body.add_child(_inspect_text)
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
	_refresh_ecology()
	_refresh_inspection()

func _refresh_ecology() -> void:
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

## 细胞诊断：把 OrganismManager.last_inspection 的每项状态转成可读文本。
## 全部来自快照，不在 UI 侧重算模拟。
func _refresh_inspection() -> void:
	if organism_manager == null or _inspect_text == null:
		return
	if not organism_manager.has_method("get_last_inspection"):
		return
	var info: Dictionary = organism_manager.call("get_last_inspection") as Dictionary
	if info.is_empty():
		_inspect_text.text = "（用「细胞诊断」工具点击皿内细胞）"
		return
	var type_id: int = int(info.get("cell_type", 0))
	var type_label: String = str(VISUALS.call("label", type_id))
	var position: Vector2 = info.get("position", Vector2.ZERO)
	var field_values: PackedFloat32Array = info.get("field", PackedFloat32Array())
	var channel_names: Array[String] = ["营养", "温度", "氧气", "光照", "信号"]
	var field_lines: Array[String] = []
	for i in range(mini(field_values.size(), channel_names.size())):
		field_lines.append("  %s %.4f" % [channel_names[i], field_values[i]])
	var lines: Array[String] = [
		"细胞 #%d · 个体 #%d · tick %d" % [int(info.get("cell_index", -1)), int(info.get("org_id", -1)), int(info.get("tick", -1))],
		"类型 %d %s · 半径 %.2f · 连接 %d" % [type_id, type_label, float(info.get("radius", 0.0)), int(info.get("links", 0))],
		"能量 %.4f · 健康 %.4f · 年龄 %d tick" % [float(info.get("energy", 0.0)), float(info.get("health", 0.0)), int(info.get("age", 0))],
		"物种 #%d · 位置 (%.2f, %.2f)" % [int(info.get("species_id", -1)), position.x, position.y],
		"场采样："
	]
	lines.append_array(field_lines)
	_inspect_text.text = "\n".join(lines)

## INSPECT 工具执行后由 Main 调用：弹出面板并立即刷新诊断段。
func show_inspection() -> void:
	_set_visible(true)
