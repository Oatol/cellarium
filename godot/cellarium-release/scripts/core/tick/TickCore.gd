extends Node
## 固定 1/60 tick。倍速只改 tick 频率（speed_scale），绝不缩放 dt。
## 单帧上限 12 tick，长帧不补算，保证确定性。

signal tick_advanced(tick_index: int)

const TICK_RATE: float = 60.0
const TICK_DT: float = 1.0 / 60.0
const MAX_TICKS_PER_FRAME: int = 12

@export var running: bool = true
@export_range(0.0, 8.0, 0.25) var speed_scale: float = 1.0

var tick_index: int = 0
var _accumulator: float = 0.0

func _process(delta: float) -> void:
	if not running:
		return
	_accumulator += delta * speed_scale
	var budget: int = mini(int(_accumulator / TICK_DT), MAX_TICKS_PER_FRAME)
	if budget <= 0:
		return
	_accumulator -= float(budget) * TICK_DT
	for i in range(budget):
		tick_index += 1
		tick_advanced.emit(tick_index)

func set_speed(scale_value: float) -> void:
	speed_scale = clampf(scale_value, 0.0, 8.0)
