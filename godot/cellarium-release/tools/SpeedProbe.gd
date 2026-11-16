extends SceneTree
## 诊断：倍速设置是否真的转化成 tick 数与细胞位移（不缩放 dt）。

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	for speed_value in [1.0, 8.0, 30.0, 32.0]:
		var instance: Node = scene.instantiate()
		instance.set("create_demo_organism", true)
		root.add_child(instance)
		await process_frame
		var tick_core: Node = instance.get_node("Simulation/TickCore")
		var manager: Node = instance.get_node("Simulation/OrganismManager")
		tick_core.set("running", true)
		tick_core.call("clear_carry")
		tick_core.call("apply_speed", speed_value)
		var cells: RefCounted = manager.get("cells") as RefCounted
		var start_position: Vector2 = cells.call("get_position", 0)
		var start_tick: int = int(tick_core.get("tick_index"))
		var intents: PackedFloat32Array = cells.get("behavior_intents")
		var start_intent: float = float(intents[0]) if intents.size() > 0 else 0.0
		for _frame in range(120):
			tick_core.call("_process", 1.0 / 60.0)
		var end_tick: int = int(tick_core.get("tick_index"))
		var end_position: Vector2 = cells.call("get_position", 0)
		var end_intents: PackedFloat32Array = cells.get("behavior_intents")
		print("SpeedProbe speed=", speed_value,
			" ticks=", end_tick - start_tick,
			" carry=", int(tick_core.get("carry_ticks")),
			" displacement=", snappedf(start_position.distance_to(end_position), 0.0001),
			" intent0=", snappedf(start_intent, 0.0001), "->", snappedf(float(end_intents[0]) if end_intents.size() > 0 else 0.0, 0.0001),
			" scale=", tick_core.get("speed_scale"),
			" lod=", int(tick_core.call("get_lod_level")))
		instance.queue_free()
		await process_frame
	quit(0)
