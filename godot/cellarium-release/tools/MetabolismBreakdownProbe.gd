extends SceneTree
## v0.33.0 代谢阶段细分探针：定位 metabolism 43ms 内的真实热点。
## 只读取 PerfProbe 自定义子阶段埋点，不写模拟状态、不改 state hash。
## 运行：console.exe --headless --path <project> --script res://tools/MetabolismBreakdownProbe.gd

const TICKS: int = 60
const WALL_LIMIT_MS: float = 15000.0
const SUB_STAGES: Array[String] = [
	"metab_fields", "metab_rates", "metab_links", "metab_base",
	"metab_env", "metab_radius", "metab_lifecycle", "metabolism",
]
## v0.49：metab_env 内部细分（下沉 C++ 后重新定位用），累计值按 tick 平均输出。
const ENV_SUB_STAGES: Array[String] = [
	"metab_env_fetch", "metab_env_arrays", "metab_env_prep", "metab_env_compute",
	"metab_env_consume", "metab_env_outcome", "metab_env_ledger", "metab_env_tail",
]
const N: int = 3000

func _initialize() -> void:
	await process_frame
	var genome_script: Script = load("res://scripts/core/data/Genome.gd") as Script
	var manager_script: Script = load("res://scripts/system/OrganismManager.gd") as Script
	var environment_script: Script = load("res://scripts/system/EnvironmentManager.gd") as Script
	var environment: Node = environment_script.new() as Node
	environment._ready()
	var manager: Node = manager_script.new() as Node
	manager.environment_manager = environment
	manager.dish_center = Vector2.ZERO
	manager.dish_radius = 4000.0
	manager.native_spatial_enabled = OS.get_environment("CELLARIUM_NATIVE") == "1"
	manager._ready()
	var genome: RefCounted = genome_script.new() as RefCounted
	genome.set("traits", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	genome.call("set_development_program", [])
	for i in range(N):
		var angle: float = float(i) * 0.618
		var radius: float = sqrt(float(i)) * 12.0
		manager.call("register_zygote", i, 0, -1, genome, Vector2(cos(angle), sin(angle)) * radius, 0.8, 0)
	var probe: RefCounted = manager.call("get_perf_probe") as RefCounted
	var totals: Dictionary = {}
	for stage in SUB_STAGES:
		totals[stage] = 0.0
	var executed: int = 0
	var env_totals: Dictionary = {}
	for stage in ENV_SUB_STAGES:
		env_totals[stage] = 0.0
	var start_usec: int = Time.get_ticks_usec()
	for tick in range(TICKS):
		manager.call("advance_physics_tick", 1.0 / 60.0)
		environment.call("advance_field_tick")
		var snapshot: Dictionary = probe.call("last_snapshot") as Dictionary
		for stage in SUB_STAGES:
			totals[stage] = float(totals[stage]) + float(snapshot.get(stage, 0.0))
		for stage in ENV_SUB_STAGES:
			env_totals[stage] = float(env_totals[stage]) + float(snapshot.get(stage, 0.0))
		executed += 1
		if float(Time.get_ticks_usec() - start_usec) / 1000.0 >= WALL_LIMIT_MS:
			break
	print("METAB_PROBE: n=%d ticks=%d native=%s" % [N, executed, str(manager.native_spatial_enabled)])
	var metabolism: float = maxf(float(totals["metabolism"]), 1.0)
	for stage in SUB_STAGES:
		if stage == "metabolism":
			continue
		var us: float = float(totals[stage]) / float(maxi(executed, 1))
		print("METAB_PROBE: %-16s %8.1fus  %5.1f%% of metabolism" % [stage, us, 100.0 * us * float(executed) / metabolism])
	for stage in ENV_SUB_STAGES:
		var env_us: float = float(env_totals[stage]) / float(maxi(executed, 1))
		print("METAB_PROBE_ENV: %-20s %8.1fus" % [stage, env_us])
	manager.free()
	environment.free()
	quit(0)
