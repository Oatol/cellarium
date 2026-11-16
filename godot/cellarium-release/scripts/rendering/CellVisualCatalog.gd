extends RefCounted
## 细胞外观静态目录（阶段7/8）。运行时细胞不再使用 guide-icon 贴图：
## Cell Lab 的主体渲染是顶点缓冲 + *_vert.glsl/*_frag.glsl 程序化绘制，guide-icons 只是图鉴。
## 这里保留类型名称/标签与图鉴路径供编辑器和图鉴使用，运行时只取 color()/accent_color()。
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

## 程序化细胞的主色：按类型 ID 稳定派生，不依赖贴图。
static func color(type_id: int) -> Color:
	var hue: float = fposmod(float(type_id) * 0.137 + 0.42, 1.0)
	return Color.from_hsv(hue, 0.42, 0.92, 1.0)

## 膜内侧与细胞器的对比色。
static func accent_color(type_id: int) -> Color:
	var hue: float = fposmod(float(type_id) * 0.137 + 0.52, 1.0)
	return Color.from_hsv(hue, 0.62, 0.72, 1.0)

## 多细胞协作的角色配色，按 CellLab 六类角色分组：结构/运动/能量/信息/稳态/生殖。
static func role(type_id: int) -> String:
	if type_id == 8 or type_id == 11 or type_id == 16:
		return "结构"
	if type_id == 1 or type_id == 2 or type_id == 3:
		return "运动"
	if type_id == 4 or type_id == 6 or type_id == 7 or type_id == 9 or type_id == 17:
		return "能量"
	if type_id == 5 or type_id == 12 or type_id == 13:
		return "信息"
	if type_id == 10:
		return "稳态"
	if type_id == 0 or type_id == 14 or type_id == 15:
		return "生殖"
	return "其他"

static func role_color(type_id: int) -> Color:
	match role(type_id):
		"结构": return Color(0.56, 0.82, 0.75, 1.0)
		"运动": return Color(0.48, 0.72, 1.0, 1.0)
		"能量": return Color(0.95, 0.78, 0.43, 1.0)
		"信息": return Color(0.77, 0.61, 1.0, 1.0)
		"稳态": return Color(0.49, 0.88, 0.63, 1.0)
		"生殖": return Color(1.0, 0.62, 0.71, 1.0)
		_: return color(type_id)
