extends RefCounted
## 只读发育上下文快照（v1 接口预留）。
## v1 不接入发育决策：dev_program[] 是唯一真相源；本对象不进存档 schema，
## 且禁止在 tick 内读取环境场去增删发育指令。
## 无 class_name：调用方 preload。

var environment_summary: Dictionary = {}
var nutrient_density: float = 0.0
var max_dev_depth: int = 0

func setup(summary: Dictionary, depth_cap: int) -> void:
	environment_summary = summary.duplicate(true)
	nutrient_density = float(summary.get("nutrient_density", 0.0))
	max_dev_depth = maxi(depth_cap, 0)

func is_read_only() -> bool:
	return true
