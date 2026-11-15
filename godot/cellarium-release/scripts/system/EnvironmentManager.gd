extends Node
## 皿级环境预设的持有者。培养基参数在本节点的 @export 中声明（.tscn），
## tick 内只读；预设在启动阶段绑定一次，回放时由 get_snapshot() 写入快照。

const PRESET_SCRIPT: GDScript = preload("res://scripts/core/data/EnvironmentPreset.gd")
const CONTEXT_SCRIPT: GDScript = preload("res://scripts/core/data/DevelopmentContext.gd")

@export_range(0.0, 4.0, 0.01) var nutrient_density: float = 1.0
@export_range(0, 64, 1) var max_dev_depth: int = 8

var preset: Resource = null
var dev_context: RefCounted = null

func _ready() -> void:
	bind_preset()

func bind_preset() -> void:
	preset = PRESET_SCRIPT.new() as Resource
	preset.set("nutrient_density", nutrient_density)
	dev_context = CONTEXT_SCRIPT.new() as RefCounted
	var snap: Variant = preset.call("to_snapshot")
	var summary: Dictionary = Dictionary(snap)
	dev_context.call("setup", summary, max_dev_depth)

func get_basal_autonomy() -> float:
	if preset == null:
		return 0.0
	return float(preset.call("get_basal_autonomy"))

func get_snapshot() -> Dictionary:
	if preset == null:
		return {}
	var snap: Variant = preset.call("to_snapshot")
	return Dictionary(snap)
