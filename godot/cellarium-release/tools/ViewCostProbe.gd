extends SceneTree
## 视图开销诊断（v0.14.0）：量化「只有几个细胞也很卡」的固定成本来源。
## 程序化测量，不动鼠标、不截图。打印 ASCII，避免中文乱码。
## 用法：godot --headless --path <project> --script res://tools/ViewCostProbe.gd

const SAMPLE_TICKS: int = 120

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)

	var env: Node = instance.get_node("Simulation/EnvironmentManager")
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var field_layer: Node = instance.get_node("DishView/FieldLayer")
	var food_layer: Node = instance.get_node("DishView/FoodLayer")

	# 固定成本 A0：仅营养源投放（add_source × 团块格数 + 食物实体池）。
	var t0: int = Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		env.call("apply_nutrient_sources", i)
	var t_a0: int = Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		env.call("advance_food_entities", 1.0 / 60.0)
	var t_a1: int = Time.get_ticks_usec()
	# A2：场扩散（GPU dispatch 或 CPU 回退）。
	for i in range(SAMPLE_TICKS):
		env.call("advance_field_tick")
	var t1: int = Time.get_ticks_usec()
	print("ViewCost sources per tick us=", snappedf(float(t_a0 - t0) / float(SAMPLE_TICKS), 0.1))
	print("ViewCost food advance per tick us=", snappedf(float(t_a1 - t_a0) / float(SAMPLE_TICKS), 0.1))
	print("ViewCost field diffuse per tick us=", snappedf(float(t1 - t_a1) / float(SAMPLE_TICKS), 0.1))
	var diag: Dictionary = env.call("get_environment_settings") as Dictionary
	var field_diag: Dictionary = env.get("field_diagnostics") as Dictionary
	print("ViewCost backend=", str(field_diag.get("backend", "?")))

	# 固定成本 B：场纹理重建（v0.14.0 已降到 64² + 6-tick 节流）。
	t0 = Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		field_layer.call("mark_dirty")
	t1 = Time.get_ticks_usec()
	print("ViewCost field texture rebuild us=", snappedf(float(t1 - t0) / float(SAMPLE_TICKS), 0.1))

	# 固定成本 C：食物层重建（缓存格心 + 6-tick 节流）。
	t0 = Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		food_layer.call("mark_dirty")
	t1 = Time.get_ticks_usec()
	print("ViewCost food layer rebuild us=", snappedf(float(t1 - t0) / float(SAMPLE_TICKS), 0.1))

	# 对照：模拟 tick（1 个细胞）成本。
	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	manager.call("register_zygote", 0, 0, -1, genome, Vector2(250, 250), 0.8, 0)
	t0 = Time.get_ticks_usec()
	for i in range(SAMPLE_TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		manager.call("advance_development_tick")
	t1 = Time.get_ticks_usec()
	print("ViewCost sim tick (1 cell) us=", snappedf(float(t1 - t0) / float(SAMPLE_TICKS), 0.1))
	print("ViewCost note: view layers are fixed cost, independent of cell count")

	# v0.18.1：量化细胞链长度对模拟 tick 与视图重建的边际成本。
	var cells: RefCounted = manager.get("cells") as RefCounted
	var renderer: Node = instance.get_node("DishView/CellSceneLayer")
	var probe_genome: RefCounted = (load("res://scripts/core/data/Genome.gd") as GDScript).new() as RefCounted
	probe_genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	probe_genome.call("set_development_program", [])
	var probe_org: int = int(manager.call("register_zygote", 0, 0, -1, probe_genome, Vector2(250, 250), 0.2, 0))
	var chain: Array[int] = [0]
	for target: int in [5, 15, 30]:
		while chain.size() < target:
			var last: int = chain[chain.size() - 1]
			var new_index: int = int(cells.call("append_cell", probe_org, Vector2(250.0 + float(chain.size()) * 12.0, 250.0), 0.2, 0))
			cells.call("link_cells", last, new_index, 14.0)
			chain.append(new_index)
		t0 = Time.get_ticks_usec()
		for i in range(SAMPLE_TICKS):
			manager.call("advance_physics_tick", 1.0 / 60.0)
			manager.call("advance_development_tick")
		var sim_us: float = float(Time.get_ticks_usec() - t0) / float(SAMPLE_TICKS)
		t0 = Time.get_ticks_usec()
		for i in range(SAMPLE_TICKS):
			renderer.call("mark_dirty")
			renderer.call("_rebuild")
		var view_us: float = float(Time.get_ticks_usec() - t0) / float(SAMPLE_TICKS)
		print("ViewCost chain n=%d sim_us=%.1f view_us=%.1f active=%d" % [target, sim_us, view_us, int(renderer.call("get_active_count"))])
	instance.queue_free()
	quit(0)
