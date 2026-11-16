extends RefCounted
## 细胞形状的唯一半径真相源。
## Cell Lab 的碰撞网格、接触物理与膜压平都读同一个 Cell.d（半径）；
## 本项目同样只保留一个静息半径，物理碰撞与 CellBase 弹性膜必须共用。

## 静息半径（世界单位）。弹性膜呼吸/拉伸只改变表现轮廓，不改变碰撞半径。
const REST_RADIUS: float = 7.0

static func rest_radius() -> float:
	return REST_RADIUS

static func min_center_distance() -> float:
	return REST_RADIUS * 2.0
