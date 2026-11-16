extends RefCounted
## 语义 ID 注册表（§3.6 / §6.9）。可交互 Control 在 _ready 注册，
## AgentBridge.ui.click(semantic_id) 按 ID 找到控件调用 act()，不依赖坐标。
## 纯静态模块，无 class_name，调用方 preload。重复 ID 在开发构建下断言失败。

## 命名空间前缀校验：控件 / 工具 / 命令 / 实体 / 物种。
const NAMESPACES: Array[String] = ["ui://", "tool://", "cmd://", "org://", "sp://"]

## 全局注册表：semantic_id -> WeakRef(Control)。用 WeakRef 避免节点释放后悬空。
static var _registry: Dictionary = {}
static var _strict: bool = true
static var _duplicate_count: int = 0
static var _log_duplicates: bool = true

## 开发构建下重复 ID 直接断言；发布构建只计数并返回 false。
static func set_strict(enabled: bool) -> void:
	_strict = enabled

static func set_log_duplicates(enabled: bool) -> void:
	_log_duplicates = enabled

static func is_strict() -> bool:
	return _strict

static func duplicate_count() -> int:
	return _duplicate_count

static func reset() -> void:
	_registry.clear()
	_duplicate_count = 0

static func is_valid_id(semantic_id: String) -> bool:
	if semantic_id.is_empty():
		return false
	for prefix in NAMESPACES:
		if semantic_id.begins_with(prefix) and semantic_id.length() > prefix.length():
			return true
	return false

static func register(semantic_id: String, control: Control) -> bool:
	if not is_valid_id(semantic_id) or control == null:
		push_error("SemanticRegistry: invalid semantic id or null control: %s" % semantic_id)
		return false
	if _registry.has(semantic_id):
		var existing: Variant = _registry.get(semantic_id)
		if existing is WeakRef and (existing as WeakRef).get_ref() != null:
			_duplicate_count += 1
			if _strict:
				assert(false, "SemanticRegistry: duplicate semantic id %s" % semantic_id)
			if _log_duplicates:
				push_error("SemanticRegistry: duplicate semantic id %s" % semantic_id)
			return false
	_registry[semantic_id] = weakref(control)
	return true

static func find(semantic_id: String) -> Control:
	if not _registry.has(semantic_id):
		return null
	var reference: Variant = _registry.get(semantic_id)
	if reference is WeakRef:
		var control: Variant = (reference as WeakRef).get_ref()
		if control == null:
			_registry.erase(semantic_id)
			return null
		return control as Control
	return null

static func unregister(semantic_id: String) -> void:
	_registry.erase(semantic_id)

## 清理某个命名空间前缀下的全部注册。供反复重建的 UI 根节点在重注册前调用，
## 避免旧实例残留导致重复 ID 断言（生产环境单实例无影响）。
static func clear_prefix(prefix: String) -> void:
	for semantic_id in _registry.keys():
		if str(semantic_id).begins_with(prefix):
			_registry.erase(semantic_id)

static func has(semantic_id: String) -> bool:
	return find(semantic_id) != null

static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for semantic_id in _registry:
		if find(str(semantic_id)) != null:
			result.append(str(semantic_id))
	result.sort()
	return result

static func count() -> int:
	return all_ids().size()

## 供 AgentBridge.ui.click 使用：优先调用控件的 act() 方法，退化为 button_pressed 信号 emit。
static func click(semantic_id: String) -> bool:
	var control: Control = find(semantic_id)
	if control == null:
		return false
	if control.has_method("act"):
		control.call("act")
		return true
	if control is Button:
		(control as Button).emit_signal("pressed")
		return true
	return false
