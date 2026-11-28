extends RefCounted
## 阶段 B 原型的双缓冲快照单元：RefCounted 持有 PackedArray，交换引用而非原地改。

var pos_x: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()
var tick: int = 0
var checksum: int = 0

func configure(cell_count: int) -> void:
	pos_x.resize(cell_count)
	alive.resize(cell_count)
