extends Resource
## 皿级只读环境预设。参数由场景中的 EnvironmentManager 在 .tscn 声明并绑定一次；
## basal_autonomy 不硬编码，由营养密度导出，随存档 / 快照 / 回放序列化。
## 无 class_name：调用方一律 preload，避免 Autoload 全局名耦合。

@export_range(0.0, 4.0, 0.01) var nutrient_density: float = 1.0
@export var basal_autonomy_floor: float = 0.15
@export var basal_autonomy_gain: float = 0.35
@export var temperature: float = 273.0

func get_basal_autonomy() -> float:
	return clampf(basal_autonomy_floor + basal_autonomy_gain * nutrient_density, 0.0, 1.0)

func to_snapshot() -> Dictionary:
	return {
		"nutrient_density": nutrient_density,
		"basal_autonomy_floor": basal_autonomy_floor,
		"basal_autonomy_gain": basal_autonomy_gain,
		"temperature": temperature,
		"basal_autonomy": get_basal_autonomy(),
	}
