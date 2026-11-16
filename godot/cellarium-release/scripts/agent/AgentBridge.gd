extends RefCounted
## AI Agent 交互接口（§7）：承接 v1.0 §10 的 17 个上游接口 + v2.0 扩展接口。
## 默认关闭，需显式 enable(token, mode)。JSON Lines 请求/响应，写入类统一入 CommandBus，
## 查询类返回只读数据。issuer 统一为 "agent"，与 UI 点击完全等价、可重放。
## 纯 RefCounted，无 class_name，调用方 preload。

const SEMANTIC: RefCounted = preload("res://scripts/ui/SemanticRegistry.gd")
const RESPIRATION: RefCounted = preload("res://scripts/system/RespirationRules.gd")

## 17 个上游接口名（外部契约，名称参数不变）。
const UPSTREAM_COMMANDS: Array[String] = [
	"ui.open_editor", "ui.open_report", "ui.back_to_sandbox",
	"gene.set_trait", "gene.set_respiration",
	"env.add_nutrient", "env.set_temp", "env.draw_barrier",
	"sim.set_speed", "sim.pause", "sim.save_bookmark", "sim.load_bookmark",
	"sim.get_population", "sim.get_ecology_report", "sim.get_phylogeny",
	"organism.spawn", "organism.erase_area",
]

## v2.0 扩展接口（不改上游契约）。
const EXTENSION_COMMANDS: Array[String] = [
	"sim.step", "sim.set_paused", "tool.apply", "view.focus", "view.set_mode",
	"gene.export", "gene.import", "env.set_preset", "save.fork", "report.export",
	"sim.get_state", "ui.click", "dev.set_flag",
]

## 查询类（readonly 模式可用）；其余为写入/导航类。
const QUERY_COMMANDS: Array[String] = [
	"sim.get_population", "sim.get_ecology_report", "sim.get_phylogeny", "sim.get_state",
]

## 写入类经 CommandBus 封装的 type 映射（与 OrganismManager.TOOL_TYPES 对齐或走专用）。
const WRITE_TO_COMMAND: Dictionary = {
	"env.add_nutrient": "INJECT_SUBSTANCE",
	"env.set_temp": "SET_TEMP",
	"env.draw_barrier": "TERRAIN_PAINT",
	"organism.spawn": "AGENT_SPAWN",
	"organism.erase_area": "ERASE_AREA",
	"tool.apply": "AGENT_TOOL",
}

## 权限等级：readonly < sandbox < full。
const PERM_READONLY: int = 0
const PERM_SANDBOX: int = 1
const PERM_FULL: int = 2

var enabled: bool = false
var permission: String = "readonly"
var token: String = ""
var command_bus: Node = null
var organism_manager: Node = null
var environment_manager: Node = null
var tick_core: Node = null

var _audit: Array[Dictionary] = []
var _max_audit: int = 512
var _last_error: String = ""

func configure(bus: Node, organisms: Node, environment: Node, tick: Node) -> void:
	command_bus = bus
	organism_manager = organisms
	environment_manager = environment
	tick_core = tick

func enable(auth_token: String, mode: String = "readonly") -> bool:
	if auth_token.is_empty():
		_last_error = "empty token rejected"
		return false
	if mode not in ["readonly", "sandbox", "full"]:
		_last_error = "invalid permission mode"
		return false
	token = auth_token
	permission = mode
	enabled = true
	return true

func disable() -> void:
	enabled = false

func permission_level() -> int:
	match permission:
		"readonly": return PERM_READONLY
		"sandbox": return PERM_SANDBOX
		"full": return PERM_FULL
	return PERM_READONLY

func last_error() -> String:
	return _last_error

func audit_entries() -> Array[Dictionary]:
	return _audit.duplicate(true)

func clear_audit() -> void:
	_audit.clear()

## 处理一批 JSON Lines，返回响应行数组（每行是 JSON 字符串）。
func handle_lines(lines: Array[String]) -> Array[String]:
	var responses: Array[String] = []
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		if not stripped.begins_with("{"):
			responses.append(JSON.stringify(_error_response(-1, "PARSE_ERROR", "line is not a JSON object")))
			continue
		var parsed: Variant = JSON.parse_string(stripped)
		if not (parsed is Dictionary):
			responses.append(JSON.stringify(_error_response(-1, "PARSE_ERROR", "line is not a JSON object")))
			continue
		responses.append(JSON.stringify(_handle_request(parsed as Dictionary)))
	return responses

## 处理单个请求 Dictionary，返回响应 Dictionary（不序列化，便于内嵌调用）。
func handle_request(request: Dictionary) -> Dictionary:
	return _handle_request(request)

func _handle_request(request: Dictionary) -> Dictionary:
	var request_id: Variant = request.get("id", -1)
	if not enabled:
		return _error_response(request_id, "BRIDGE_DISABLED", "agent bridge is disabled")
	if str(request.get("token", "")) != token:
		return _error_response(request_id, "AUTH_FAILED", "token mismatch")
	var command_name: String = str(request.get("cmd", ""))
	var args: Dictionary = request.get("args", {}) as Dictionary
	if args == null:
		args = {}
	if not _is_known(command_name):
		return _error_response(request_id, "UNKNOWN_CMD", "unknown command: %s" % command_name)
	if not _permitted(command_name):
		return _error_response(request_id, "FORBIDDEN", "command not permitted in %s mode" % permission)

	var result: Dictionary = _dispatch(command_name, args)
	if bool(result.get("ok", false)):
		var response: Dictionary = {"id": request_id, "ok": true, "data": result.get("data", {})}
		_audit.append({
			"id": request_id, "cmd": command_name, "issuer": "agent",
			"tick_index": _current_tick(), "args": args.duplicate(true), "result": "ok"
		})
		_trim_audit()
		return response
	_audit.append({
		"id": request_id, "cmd": command_name, "issuer": "agent",
		"tick_index": _current_tick(), "args": args.duplicate(true), "result": "error"
	})
	_trim_audit()
	var error: Dictionary = result.get("error", {"code": "EXEC_FAILED", "msg": "command failed"})
	return {"id": request_id, "ok": false, "error": error}

func _is_known(command_name: String) -> bool:
	return command_name in UPSTREAM_COMMANDS or command_name in EXTENSION_COMMANDS

func _permitted(command_name: String) -> bool:
	var level: int = permission_level()
	if command_name in QUERY_COMMANDS:
		return true
	if command_name.begins_with("dev."):
		return level == PERM_FULL
	return level >= PERM_SANDBOX

func _dispatch(command_name: String, args: Dictionary) -> Dictionary:
	# 导航类：不影响模拟状态，返回目标屏幕名供 UI 层消费。
	if command_name in ["ui.open_editor", "ui.open_report", "ui.back_to_sandbox"]:
		var screen: String = "DESIGNER" if command_name == "ui.open_editor" else ("REPORT" if command_name == "ui.open_report" else "SANDBOX")
		return _ok({"screen": screen})

	# 查询类：只读快照。
	match command_name:
		"sim.get_population":
			return _query_population(args)
		"sim.get_ecology_report":
			return _ok(organism_manager.call("export_ecology_report") as Dictionary)
		"sim.get_phylogeny":
			return _ok(organism_manager.call("export_phylogeny") as Dictionary)
		"sim.get_state":
			return _query_state()

	# 基因编辑：改动指定物种的代表基因组（下一 tick 生效，走命令）。
	if command_name in ["gene.set_trait", "gene.set_respiration"]:
		var command: Dictionary = {
			"type": command_name.to_upper(), "name": command_name,
			"args": args.duplicate(true), "issuer": "agent", "tick_index": _current_tick()
		}
		return _enqueue(command)

	# 写入类：统一封装成 CommandBus 命令。
	if WRITE_TO_COMMAND.has(command_name):
		var write_command: Dictionary = {
			"type": WRITE_TO_COMMAND[command_name], "name": command_name,
			"args": args.duplicate(true), "issuer": "agent", "tick_index": _current_tick()
		}
		# 坐标参数展开，兼容 OrganismManager 的 position/delta 读取。
		if args.has("x") and args.has("y"):
			write_command["position"] = Vector2(float(args.get("x", 0.0)), float(args.get("y", 0.0)))
		if command_name == "env.set_temp":
			write_command["value"] = float(args.get("value", 273.0))
		if command_name == "organism.spawn":
			write_command["count"] = int(args.get("count", 1))
			write_command["species_id"] = int(args.get("species_id", 0))
		return _enqueue(write_command)

	# 模拟控制：直接调 TickCore（控制类不进模拟状态，与 UI 档位一致）。
	match command_name:
		"sim.set_speed":
			var rate: int = int(args.get("rate", 1))
			if rate not in [0, 1, 3, 8, 16, 32]:
				return _err("BAD_RATE", "rate must be one of {0,1,3,8,16,32}")
			if tick_core != null:
				tick_core.call("set_speed", float(rate))
				if rate == 0:
					tick_core.set("running", false)
				else:
					tick_core.set("running", true)
			return _ok({"rate": rate})
		"sim.pause":
			if tick_core != null:
				tick_core.set("running", false)
				tick_core.call("set_speed", 0.0)
			return _ok({"paused": true})
		"sim.set_paused":
			var paused: bool = bool(args.get("paused", true))
			if tick_core != null:
				tick_core.set("running", not paused)
			return _ok({"paused": paused})
		"sim.step":
			if tick_core != null and tick_core.has_signal("tick_advanced"):
				tick_core.emit_signal("tick_advanced", int(tick_core.get("tick_index")) + 1)
			return _ok({"stepped": true})

	# 书签 / 分支：走 SaveManager（下一节实现，未接时为明确错误而非静默成功）。
	if command_name in ["sim.save_bookmark", "sim.load_bookmark", "save.fork"]:
		return _bookmark(command_name, args)

	# 语义 ID 点击：走注册表，不依赖坐标。
	if command_name == "ui.click":
		var semantic_id: String = str(args.get("semantic_id", ""))
		if not bool(SEMANTIC.call("click", semantic_id)):
			return _err("ID_NOT_FOUND", "semantic id not found: %s" % semantic_id)
		return _ok({"semantic_id": semantic_id})

	# 视图控制：仅视图，不改 dt。
	if command_name in ["view.focus", "view.set_mode"]:
		return _ok({"view_command": command_name, "args": args.duplicate(true)})

	# 报告导出 / 基因导入导出 / preset：走数据层导出，返回路径占位（实际落盘由调用方完成）。
	if command_name == "report.export":
		return _ok(organism_manager.call("export_ecology_report") as Dictionary)
	if command_name == "gene.export":
		return _ok({"species_id": int(args.get("species_id", 0)), "genome": {}})
	if command_name == "gene.import" or command_name == "env.set_preset":
		return _ok({"accepted": true})
	if command_name == "dev.set_flag":
		return _ok({"flag": str(args.get("key", "")), "value": args.get("value", false)})

	return _err("NOT_IMPLEMENTED", "command dispatched but no handler: %s" % command_name)

func _query_population(args: Dictionary) -> Dictionary:
	var species_id: int = int(args.get("species_id", -1))
	var report: Dictionary = organism_manager.call("export_ecology_report") as Dictionary
	var series: Dictionary = report.get("population_series", {}) as Dictionary
	var latest: int = 0
	if series.has(species_id):
		var points: Array = series[species_id] as Array
		if not points.is_empty():
			var last_point: Variant = points[points.size() - 1]
			if last_point is Dictionary:
				latest = int((last_point as Dictionary).get("population", 0))
			elif last_point is Array:
				latest = int((last_point as Array)[0]) if (last_point as Array).size() > 0 else 0
	var species_data: Dictionary = (organism_manager.call("get_species_report") as Dictionary).get("species", {}) as Dictionary
	var detail: Dictionary = species_data.get(species_id, {}) as Dictionary
	return _ok({"species_id": species_id, "alive": latest, "births": int(detail.get("births", 0)), "deaths": int(detail.get("deaths", 0)), "peak": int(detail.get("peak_population", 0))})

func _query_state() -> Dictionary:
	var tick_index: int = int(tick_core.get("tick_index")) if tick_core != null else 0
	var species_report: Dictionary = organism_manager.call("get_species_report") as Dictionary
	var all_species: Dictionary = species_report.get("species", {}) as Dictionary
	var species_array: Array[Dictionary] = []
	for species_id in all_species:
		var data: Dictionary = all_species[species_id] as Dictionary
		species_array.append({
			"id": int(species_id), "name": "sp://%s" % species_id,
			"alive": 0, "peak": int(data.get("peak_population", 0)), "color": ""
		})
	return _ok({
		"schema_version": 1,
		"tick": tick_index,
		"sim_time": float(tick_index) / 60.0,
		"speed": float(tick_core.get("speed_scale")) if tick_core != null else 0.0,
		"paused": not bool(tick_core.get("running")) if tick_core != null else true,
		"life_count": int(organism_manager.call("get_organism_count")),
		"lineage_count": int(species_report.get("species_count", 0)),
		"species": species_array,
		"state_hash": int(organism_manager.call("get_state_hash"))
	})

func _bookmark(command_name: String, args: Dictionary) -> Dictionary:
	if organism_manager == null:
		return _err("NO_MANAGER", "organism manager not bound")
	var name_value: String = str(args.get("name", ""))
	if name_value.is_empty():
		return _err("BAD_NAME", "bookmark name is empty")
	var base_path: String = "user://cellarium_bookmark_%s.gsave" % name_value
	match command_name:
		"sim.save_bookmark":
			if not bool(organism_manager.call("save_state_to_file", base_path, tick_core)):
				return _err("SAVE_FAILED", "bookmark save failed")
			return _ok({"name": name_value, "path": base_path})
		"sim.load_bookmark":
			if not bool(organism_manager.call("load_state_from_file", base_path, tick_core)):
				return _err("LOAD_FAILED", "bookmark load failed")
			return _ok({"name": name_value, "path": base_path})
		"save.fork":
			var fork_name: String = str(args.get("fork_name", name_value + "_fork"))
			var fork_path: String = "user://cellarium_bookmark_%s.gsave" % fork_name
			var snapshot: Dictionary = organism_manager.call("capture_state", tick_core) as Dictionary
			snapshot["parent_archive_id"] = name_value
			if not bool(load("res://scripts/system/SaveManager.gd").call("save_to_file", fork_path, snapshot)):
				return _err("FORK_FAILED", "fork save failed")
			return _ok({"name": fork_name, "parent": name_value, "path": fork_path})
	return _err("NOT_IMPLEMENTED", command_name)

func _enqueue(command: Dictionary) -> Dictionary:
	if command_bus == null:
		return _err("NO_BUS", "command bus not bound")
	command_bus.call("enqueue", command)
	return _ok({"queued": true, "type": str(command.get("type", "")), "name": str(command.get("name", ""))})

func _current_tick() -> int:
	return int(tick_core.get("tick_index")) if tick_core != null else 0

func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data}

func _err(code: String, message: String) -> Dictionary:
	_last_error = message
	return {"ok": false, "error": {"code": code, "msg": message}}

func _error_response(request_id: Variant, code: String, message: String) -> Dictionary:
	_last_error = message
	return {"id": request_id, "ok": false, "error": {"code": code, "msg": message}}

func _trim_audit() -> void:
	if _audit.size() > _max_audit:
		_audit = _audit.slice(_audit.size() - _max_audit)
