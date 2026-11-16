extends RefCounted
## UI 静态数据：工具 / 时间档位 / 培养基 / 镜头滤镜。
## 纯数据，无 class_name，调用方 preload。用词对照 analysis/CellLab_界面与实验条件_词条证据.md。
## group: celllab=官方5件 / macro=Macro新增5件 / edit=编辑能力4件
## kind: world=真实写入模拟 / view=仅视图控制 / stub=已入队但底层待接入

static func tools() -> Array[Dictionary]:
	return [
		{"id":"SPAWN","key":"1","name":"细胞合成器","en":"Cell synthesizer","group":"celllab","kind":"world","mode":"点击型","desc":"在培养皿落点投放一枚细胞；装载编辑草案后使用自定义基因组。"},
		{"id":"REMOVE","key":"2","name":"移除细胞","en":"Cell removal","group":"celllab","kind":"world","mode":"点击型","desc":"移除落点附近最近的一枚细胞。"},
		{"id":"DRAG","key":"3","name":"光学镊子","en":"Optical tweezers","group":"celllab","kind":"world","mode":"拖拽型","desc":"拖动落点附近细胞到新位置。"},
		{"id":"BOOST","key":"4","name":"细胞强化","en":"Cell boost","group":"celllab","kind":"world","mode":"点击型","desc":"为落点附近细胞注入额外能量。"},
		{"id":"INSPECT","key":"5","name":"细胞诊断","en":"Cell diagnostics","group":"celllab","kind":"world","mode":"点击型","desc":"读取落点细胞状态并显示在状态栏。"},
		{"id":"ADHERE","key":"6","name":"黏附连接","en":"Adhesion extruder","group":"macro","kind":"world","mode":"拖拽型","desc":"在落点附近两枚细胞间建立黏附连接。"},
		{"id":"INJECT_GENOME","key":"7","name":"基因组注射","en":"Genome injector","group":"macro","kind":"world","mode":"点击型","desc":"把编辑草案写入落点细胞所属个体，并切换其表现类型。"},
		{"id":"INJECT_SIGNAL","key":"8","name":"信号注射","en":"Signal injector","group":"macro","kind":"world","mode":"点击型","desc":"向信号通道注入化学信号 source。"},
		{"id":"INJECT_SUBSTANCE","key":"9","name":"物质注射","en":"Substance injector","group":"macro","kind":"world","mode":"点击型","desc":"在落点注入营养物质，进入场 source。"},
		{"id":"INJECT_COLOR","key":"0","name":"颜色注射","en":"Color injector","group":"macro","kind":"world","mode":"点击型","desc":"标记落点细胞的表现类型，用于观测分组。"},
		{"id":"SELECT","key":"Q","name":"选择","en":"Select","group":"edit","kind":"world","mode":"点击/框选","desc":"点选或框选细胞，写入选择集供选区工具使用。"},
		{"id":"ROTATE_SELECTION","key":"W","name":"旋转选区","en":"Rotate selection","group":"edit","kind":"world","mode":"拖拽型","desc":"绕选区质心旋转已选细胞。"},
		{"id":"TERRAIN_PAINT","key":"E","name":"地形笔刷","en":"Terrain brush","group":"edit","kind":"world","mode":"拖拽型","desc":"绘制固体地形，阻挡场扩散与细胞通行。"},
		{"id":"TERRAIN_ERASE","key":"R","name":"地形橡皮","en":"Terrain eraser","group":"edit","kind":"world","mode":"拖拽型","desc":"擦除固体地形，恢复场扩散。"}
	]

static func groups() -> Array[Dictionary]:
	return [
		{"k":"celllab","label":"Cell Lab · 5"},
		{"k":"macro","label":"Macro · 5"},
		{"k":"edit","label":"Edit · 4"}
	]

static func modes() -> Array[Dictionary]:
	## speed=-1 表示 running=false（冻结）；scale 为 TickCore.set_speed 参数。
	return [
		{"n":"冻结","en":"Freeze","scale":0.0,"running":false,"note":"暂停推进"},
		{"n":"观察","en":"Observe","scale":1.0,"running":true,"note":"1×"},
		{"n":"培养","en":"Incubate","scale":3.0,"running":true,"note":"3×"},
		{"n":"慢速观察","en":"Slow observe","scale":0.25,"running":true,"note":"非严格等价，仅降 tick 频率"},
		{"n":"过夜培养","en":"Overnight","scale":8.0,"running":true,"note":"无渲染快进，非缩放 dt"}
	]

static func substrate() -> Array[Dictionary]:
	## k 对应 EnvironmentManager 的 @export；writable=false 为纯 UI 占位。
	return [
		{"n":"营养密度","k":"nutrient_density","v":1.2,"min":0.0,"max":4.0,"step":0.05,"writable":true},
		{"n":"氧气分数","k":"oxygen_fraction","v":0.0,"min":0.0,"max":1.0,"step":0.01,"writable":true},
		{"n":"温度","k":"temperature","v":273.0,"min":260.0,"max":320.0,"step":1.0,"writable":true},
		{"n":"最大发育深度","k":"max_dev_depth","v":12,"min":0,"max":64,"step":1,"writable":true},
		{"n":"光照强度","k":"light_amount","v":0.6,"min":0.0,"max":1.0,"step":0.01,"writable":false},
		{"n":"黏度","k":"viscosity","v":0.35,"min":0.0,"max":1.0,"step":0.01,"writable":false},
		{"n":"重力","k":"gravity","v":0.1,"min":0.0,"max":1.0,"step":0.01,"writable":false},
		{"n":"盐度","k":"salinity","v":0.3,"min":0.0,"max":1.0,"step":0.01,"writable":false}
	]

static func lenses() -> Array[String]:
	return ["默认", "视野", "目镜", "融合镜", "偏振镜"]
