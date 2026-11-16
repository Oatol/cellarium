extends RefCounted
## 细胞外观静态目录（阶段7）。贴图来源：Cell Lab guide-icons（本地开发资产）。
## 只提供视图资源，不写模拟状态；type_id 与 Genome/CellArray 的 type_id 对齐。
## 纯数据，无 class_name，调用方 preload。

const TEXTURE_ROOT: String = "res://assets/apk_local/guide-icons/"

static func entries() -> Array[Dictionary]:
	return [
		{"id": 0,  "name": "zygocyte",    "label": "受精卵",   "file": "zygocyte.png"},
		{"id": 1,  "name": "somatocyte",  "label": "体细胞",   "file": "somatocyte.png"},
		{"id": 2,  "name": "myocyte",     "label": "肌细胞",   "file": "myocyte.png"},
		{"id": 3,  "name": "flagellocyte","label": "鞭毛细胞", "file": "flagellocyte.png"},
		{"id": 4,  "name": "photocyte",   "label": "光合细胞", "file": "photocyte.png"},
		{"id": 5,  "name": "neurocyte",   "label": "神经细胞", "file": "neurocyte.png"},
		{"id": 6,  "name": "phagocyte",   "label": "吞噬细胞", "file": "phagocyte.png"},
		{"id": 7,  "name": "devorocyte",  "label": "掠食细胞", "file": "devorocyte.png"},
		{"id": 8,  "name": "keratinocyte","label": "角质细胞", "file": "keratinocyte.png"},
		{"id": 9,  "name": "lipocyte",    "label": "脂细胞",   "file": "lipocyte.png"},
		{"id": 10, "name": "nitrocyte",   "label": "硝化细胞", "file": "nitrocyte.png"},
		{"id": 11, "name": "glueocyte",   "label": "黏附细胞", "file": "glueocyte.png"},
		{"id": 12, "name": "senseocyte",  "label": "感觉细胞", "file": "senseocyte.png"},
		{"id": 13, "name": "gangliocyte", "label": "神经节细胞", "file": "gangliocyte.png"},
		{"id": 14, "name": "virocyte",    "label": "病毒细胞", "file": "virocyte.png"},
		{"id": 15, "name": "gamete",      "label": "配子",     "file": "gamete.png"},
		{"id": 16, "name": "osteocyte",   "label": "骨细胞",   "file": "osteocyte.png"},
		{"id": 17, "name": "luminocyte",  "label": "发光细胞", "file": "luminocyte.png"},
	]

static func entry(type_id: int) -> Dictionary:
	var list: Array[Dictionary] = entries()
	if type_id < 0 or type_id >= list.size():
		return list[0]
	return list[type_id]

static func texture_path(type_id: int) -> String:
	return TEXTURE_ROOT + str(entry(type_id).get("file", "zygocyte.png"))

static func label(type_id: int) -> String:
	return str(entry(type_id).get("label", "?"))
