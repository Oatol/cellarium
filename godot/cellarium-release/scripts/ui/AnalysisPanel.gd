extends PanelContainer
## 生态分析面板（阶段5 观测）：绑定 OrganismManager 的生态报告，R 键开合。
## 容器在 main.tscn 声明，本脚本只填 Label 与刷新逻辑；数据全部来自报告快照，非手填文案。
## 同时承载细胞诊断：INSPECT 工具写入 last_inspection 后自动弹出显示逐项状态。
## 语义 ID：ui://report/panel，供 Agent 自动化打开。

const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")
const VISUALS: RefCounted = preload("res://scripts/rendering/CellVisualCatalog.gd")

## 实时数字（tick / 活体数）每 6 tick 刷新；统计采样面板每 30 tick 刷新。
const LIVE_REFRESH_TICKS: int = 6
const REPORT_REFRESH_TICKS: int = 30

@export var organism_manager_path: NodePath = ^"../../Simulation/OrganismManager"
@export var tick_core_path: NodePath = ^"../../Simulation/TickCore"
@export var command_bus_path: NodePath = ^"../../Simulation/CommandBus"

var organism_manager: Node = null
var tick_core: Node = null
var command_bus: Node = null
var _body: VBoxContainer = null
var _text: Label = null
var _live_text: Label = null
var _inspect_title: Label = null
var _inspect_text: Label = null
var _visible_state: bool = false
var _tick_since_refresh: int = 0

func _on_tick_for_refresh(tick_index: int) -> void:
	_tick_since_refresh += 1
	if not visible:
		return
	# 统计采样每 30 tick 更新一次；tick / 活体数等实时数字每 6 tick 更新，避免看起来「不刷新」。
	if _tick_since_refresh >= REPORT_REFRESH_TICKS:
		_tick_since_refresh = 0
		_refresh()
	elif _tick_since_refresh % LIVE_REFRESH_TICKS == 0:
		_refresh_live()
	elif organism_manager != null and organism_manager.has_method("get_last_inspection"):
		_refresh_inspection()

## 供外部（含无头验收）强制刷新完整报告。
func refresh_now() -> void:
	_tick_since_refresh = 0
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			# 图钉固定后 R 键不关闭面板。
			if bool(get_meta("chrome_pinned", false)) and _visible_state:
				return
			_set_visible(not _visible_state)

## 供 Agent ui.click("ui://report/panel") 调用：切换面板。
func act() -> void:
	_set_visible(not _visible_state)

## 供顶栏开关同步内部可见状态（避免 R 键/图钉逻辑失配）。
func set_visible_state(value: bool) -> void:
	_visible_state = value
	visible = value
	if value:
		_refresh()

func _set_visible(value: bool) -> void:
	_visible_state = value
	visible = value
	if value:
		_refresh()

func _ready() -> void:
	organism_manager = get_node_or_null(organism_manager_path)
	tick_core = get_node_or_null(tick_core_path)
	command_bus = get_node_or_null(command_bus_path)
	# 场景可能被反复实例化（测试/热重载）：先清本命名空间旧注册再注册。
	SEMANTIC.call("clear_prefix", "ui://report/")
	SEMANTIC.call("register", "ui://report/panel", self)
	# 生态报告实时更新：每 30 tick 刷新一次（面板可见时才刷新，无 tick 的冻结档也定期刷新）。
	if tick_core != null and tick_core.has_signal("tick_advanced"):
		var on_tick: Callable = Callable(self, "_on_tick_for_refresh")
		if not tick_core.is_connected("tick_advanced", on_tick):
			tick_core.connect("tick_advanced", on_tick)
	_body = VBoxContainer.new()
	var title: Label = Label.new()
	title.text = "生态报告 · R 关闭"
	title.add_theme_font_size_override("font_size", 15)
	_live_text = Label.new()
	_live_text.name = "LiveStatsLabel"
	_live_text.text = "—"
	_live_text.add_theme_font_size_override("font_size", 13)
	_text = Label.new()
	_text.text = "—"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(title)
	_body.add_child(_live_text)
	_body.add_child(_text)
	_inspect_title = Label.new()
	_inspect_title.text = "细胞诊断 · 点击细胞后显示"
	_inspect_title.add_theme_font_size_override("font_size", 15)
	var unlock_button: Button = Button.new()
	unlock_button.name = "UnlockSelectionButton"
	unlock_button.text = "解除锁定"
	unlock_button.tooltip_text = "清除诊断选中的圆环（也可按 Esc 或用诊断工具点空白处）"
	unlock_button.custom_minimum_size = Vector2(84, 24)
	unlock_button.pressed.connect(_on_unlock_pressed)
	_inspect_text = Label.new()
	_inspect_text.text = "（用「细胞诊断」工具点击皿内细胞）"
	_inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_inspect_title)
	_body.add_child(unlock_button)
	_body.add_child(_inspect_text)
	add_child(_body)
	visible = false
	_refresh()

func _refresh() -> void:
	if organism_manager == null or _text == null:
		return
	_refresh_live()
	_refresh_ecology()
	_refresh_inspection()

## 实时数字直接来自快照 getter，不改模拟、不依赖 30 tick 采样窗口。
func _refresh_live() -> void:
	if _live_text == null:
		return
	var tick_value: int = int(tick_core.get("tick_index")) if tick_core != null else 0
	var alive: int = 0
	if organism_manager != null and organism_manager.has_method("get_organism_count"):
		alive = int(organism_manager.call("get_organism_count"))
	var speed_text: String = "?"
	if tick_core != null:
		speed_text = str(float(tick_core.get("speed_scale")))
	_live_text.text = "实时 tick %d · 活体个体 %d · 倍速 %s×" % [tick_value, alive, speed_text]

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

## 诊断解锁：仍走 CommandBus 唯一写入口；冻结档无下一 tick 时同步 flush。
func _on_unlock_pressed() -> void:
	if command_bus == null:
		return
	command_bus.call("enqueue", {"type": "CLEAR_SELECTION"})
	# 解锁是纯视图命令，UI 按钮立即 flush，圆环不等下一 tick 才消失。
	var tick_index: int = int(tick_core.get("tick_index")) if tick_core != null else 0
	command_bus.call("execute_tick_commands", tick_index)
	_refresh_inspection()

## Main 在 CLEAR_SELECTION 执行后调用，清掉面板里的旧诊断文本。
func refresh_inspection() -> void:
	_refresh_inspection()
