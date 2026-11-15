extends Node
## 个体注册表占位。P1 才接入 CellArray / Genome / 生命周期状态机；
## v1 骨架只保留计数，不创建实体，避免抢在文档冻结前写入模拟状态。

@export_range(0, 4096, 1) var initial_organism_count: int = 0

var organism_count: int = 0

func _ready() -> void:
	organism_count = initial_organism_count
