extends SceneTree
## §8.1 三档性能基准（300 / 1000 / 3000 生物）。每档固定 tick 上限，禁止长时间满载（§9.4）。
## 运行：console.exe --headless --path <project> --script res://tools/BenchTest.gd
## 输出：基准结果 CSV 到 user://cellarium_bench.csv，逐档打印 ASCII 摘要。

const TICKS_PER_TIER: int = 120
const TIERS: Array[int] = [300, 1000, 3000]
## 单档墙钟硬上限 15 秒：到达即停止该档剩余 tick，杜绝满载过热（§9.4）。
const TIER_WALL_LIMIT_MS: float = 15000.0

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var failures: int = 0
	var lines: Array[String] = ["tier,organisms,ticks,total_ms,avg_tick_us,budget_met"]

	for tier_count in TIERS:
		var environment: Node = environment_script.new() as Node
		environment._ready()
		var manager: Node = manager_script.new() as Node
		manager.environment_manager = environment
		manager.dish_center = Vector2.ZERO
		manager.dish_radius = 4000.0
		manager._ready()
		var genome: RefCounted = genome_script.new() as RefCounted
		genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
		genome.call("set_development_program", [])
		for i in range(tier_count):
			var angle: float = float(i) * 0.618
			var radius: float = sqrt(float(i)) * 12.0
			manager.call("register_zygote", i, 0, -1, genome, Vector2(cos(angle), sin(angle)) * radius, 0.8, 0)
		var start_usec: int = Time.get_ticks_usec()
		var executed_ticks: int = 0
		for tick in range(TICKS_PER_TIER):
			manager.call("advance_physics_tick", 1.0 / 60.0)
			environment.call("advance_field_tick")
			executed_ticks += 1
			if float(Time.get_ticks_usec() - start_usec) / 1000.0 >= TIER_WALL_LIMIT_MS:
				break
		var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
		var perf: Dictionary = manager.call("get_perf_snapshot") as Dictionary
		var averages: Dictionary = (manager.call("get_perf_probe") as RefCounted).call("averages") as Dictionary
		var avg_tick_us: float = float(averages.get("total", 0.0))
		var budget_met: bool = bool(perf.get("budget_met", false))
		lines.append("%d,%d,%d,%.1f,%.1f,%s" % [tier_count, int(manager.call("get_organism_count")), executed_ticks, elapsed_ms, avg_tick_us, "1" if budget_met else "0"])
		print("Bench: tier=%d organisms=%d ticks=%d wall_ms=%.1f avg_tick_us=%.1f cpu_budget_met=%s" % [tier_count, int(manager.call("get_organism_count")), executed_ticks, elapsed_ms, avg_tick_us, str(budget_met)])
		var stage_breakdown: String = ""
		for stage in ["behavior", "physics", "metabolism", "predation", "signal"]:
			stage_breakdown += "%s=%.0fus " % [stage, float(averages.get(stage, 0.0))]
		print("Bench:   stages " + stage_breakdown)
		# 墙钟上限是主动保护，不视为失败；只有初始化异常或零 tick 才是失败。
		if executed_ticks == 0:
			push_error("Bench: tier %d executed no ticks" % tier_count)
			failures += 1
		manager.free()
		environment.free()

	var file: FileAccess = FileAccess.open("user://cellarium_bench.csv", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
		print("Bench: CSV written user://cellarium_bench.csv")
	else:
		push_error("Bench: cannot write CSV")
		failures += 1
	print("Bench: FAILURES=", failures)
	quit(1 if failures > 0 else 0)
