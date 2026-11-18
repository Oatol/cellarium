extends SceneTree
## v0.30.0 批渲染探针：>512 细胞时单 CanvasItem 批量画共享弦膜，且不写模拟状态。
## 程序化、无鼠标、ASCII 输出。

const CELL_COUNT: int = 600

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  OK ", label)
	else:
		push_error("BatchRender FAIL: " + label)
		_failures += 1

func _initialize() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	instance.set("create_demo_organism", false)
	root.add_child(instance)
	await process_frame
	var tick_core: Node = instance.get_node("Simulation/TickCore")
	tick_core.set("running", false)
	var manager: Node = instance.get_node("Simulation/OrganismManager")
	var renderer: Node = instance.get_node("DishView/CellSceneLayer")
	var batch: Node = instance.get_node("DishView/CellBatchPoly")
	_check(batch != null, "CellBatchPoly node exists")
	if batch == null:
		print("BatchRender: FAILURES=", _failures); quit(1); return

	var genome: RefCounted = load("res://scripts/core/data/Genome.gd").new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	var org_id: int = int(manager.call("register_zygote", 0, 0, -1, genome, Vector2(250, 250), 0.8, 0))
	var cells: RefCounted = manager.get("cells") as RefCounted
	var columns: int = 25
	for i in range(1, CELL_COUNT):
		var row: int = i / columns
		var column: int = i % columns
		var position: Vector2 = Vector2(210 + column * 5.0, 210 + row * 5.0)
		cells.call("append_cell", org_id, position, 0.8, 0)
	var hash_before: int = int(manager.call("get_state_hash"))

	renderer.call("mark_dirty")
	renderer.call("_rebuild")
	await process_frame
	var started: int = Time.get_ticks_usec()
	for _sample in range(10):
		batch.call("_rebuild_cache")
	var rebuild_us: float = float(Time.get_ticks_usec() - started) / 10.0
	var hash_after: int = int(manager.call("get_state_hash"))

	_check(bool(batch.get("visible")), "batch renderer visible above 512 cells")
	_check(int(batch.call("get_active_count")) >= CELL_COUNT, "batch cell count >= %d" % CELL_COUNT)
	_check(int(batch.call("get_polygon_count")) >= CELL_COUNT, "batch polygon count >= %d" % CELL_COUNT)
	_check(int(batch.call("get_chord_count")) > 0, "shared chords present in batch")
	_check(hash_before == hash_after, "batch render does not change state hash")
	print("BatchRender rebuild_us=%.1f chords=%d polygons=%d" % [
		rebuild_us, int(batch.call("get_chord_count")), int(batch.call("get_polygon_count"))
	])
	instance.queue_free()
	print("BatchRender: FAILURES=", _failures)
	quit(1 if _failures > 0 else 0)
