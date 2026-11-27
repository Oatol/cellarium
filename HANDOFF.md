# 创生模拟器 · 会话交接文档

> 面向**完全没有上下文的新对话**。读完本文件即可接手，不必翻历史聊天记录。
> 本文件更新于 2026-11-27，对应工程 HEAD `f42eaa5` / 最新版本标签 `v0.46.0`，工作区干净。

---

## 0. 一句话现状

我们在 Godot 4.7.2 里复刻 Cell Lab 的人工生命沙盒，第一阶段玩法已基本对齐；**性能专项已于 v0.45 达成核心目标**——1025 细胞真实窗口裸 tick 同会话两轮 7.48 / 7.29 ms，稳定低于 ≤8 ms/tick（v0.46 又将 signal 段降 31%）。全程 state hash 与场值 flat parity 逐位不变。性能专项已到收益递减拐点，下一步建议转向高倍速真实体感或玩法完成度收尾（见 §5）。

---

## 1. 项目定位与约束（新对话必须先理解）

- **产品**：Godot 4.x 2D 人工生命沙盒，场景设定木卫二冰下海洋。核心是沙盒，战役/星级只是 `ExperimentDef` 表现层（只读统计快照）。
- **用户最高准则**：所有开发**先读 Cell Lab 官方版/Macro 反编译源码**，能直接借鉴成熟机制就不重造；**禁止"看起来像"的近似公式**；允许重构 tick、数据布局、渲染、物理与原生层。
- **确定性铁律**：固定 1/60 tick；倍速靠 tick 频率 + LOD，单帧上限 12 tick；确定性 = 静态分区 + 单写者 + 派生 RNG；唯一写入口 `CommandBus`。
- **冻结边界**：`GNP1` 基因布局、存档 schema、Agent 契约冻结后只做版本化追加。v2.1 标"不采纳"的机制若要引入，先修订 v1.0 并同步 §0.3/§11。
- **验收口径**：≤8 ms/tick（裸 tick = PerfProbe 7 个 STAGES 之和，不含头部 tick_setup / tick_stats 与全链采样准备）。v0.45 起同会话两轮达标；`cpu_budget_met=false` 时如实记录，**绝不表述为达标**。全链 tick1 p50 约 9.4–9.7 ms 含头部采样与统计，不计入验收口径。
- **默认测试口径 M1**：光合自分裂、保持黏附、无分裂次数限制。所有测试一律按此。

### 权威文档（冲突时以此为准）
| 用途 | 文件 |
| --- | --- |
| 玩法原件（勿改） | `C:\Users\安\Downloads\创生模拟器 · 沙盒版人工生命系统设计文档.docx` |
| 玩法合并稿 | `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` |
| 实现权威（v2.1） | `docs/Godot项目技术设计文档.md` |
| Cell Lab 代码级分析（§32+） | `analysis/CellLab_细胞物理与外观_代码级分析.md`（最新 §51 = v0.46；§48 Cell Lab/Alien 防卡源码级结论，§49–§51 为 v0.44–v0.46 性能专项） |
| 变更记录 | `CHANGELOG.md`（顶部为最新版本） |
| 项目长期笔记 | `.workbuddy-ai/memory/MEMORY.md`（含全部踩坑结论，接手必读） |

---

## 2. 我们在做什么任务

分两条线，第一条基本完成，第二条已收尾达标：

**A. 第一阶段复刻 Cell Lab（已基本完成）**
- 能量逐 Link 转移、半径-能量低通 `d=sqrt(w)/20`、倍增分裂、40 槽分化树、旧连接按 `cos(轴−连接角)` 重分配、FLAG 后向 `cos<-0.8` 判死。
- 发育预览 = 同一真实模拟类的独立实例（`PreviewWorld`：隔离 OrganismManager/EnvironmentManager，不入场景树，强制 CPU 场，种子 1337，上限 96 细胞/4000 tick，连续时间轴 t=0），**不是第二套算法**。
- 连接机制查证：分裂硬链 + 接触动态链并存，锚点按当前半径实时重算；无黄色流动粒子（Godot 里的黄色光点是 `LinkLayer.gd` 自加视图，多连接时增 draw call）。
- 皿外方点已修：根因 `Transform2D(0,pos).scaled()` 连 origin 一起缩放，512→1024 触发 MultiMesh LOD 暴露。

**B. 性能专项（已达标收尾，A + C + 后续 GDScript 扁平化路线）**
- A 路线：GDExtension/C++ 下沉热点（v0.31–v0.36、v0.44 碰撞、v0.45 collect_inputs），state hash 全程逐位一致。
- C 路线：GPU 合批 / 渲染解耦（v0.39–v0.42）。结论：**draw call 4231→259 但帧时间不变，GPU 合成不是瓶颈**；真凶是 tick CPU 与场采样准备。
- D 路线（v0.41–v0.46）：GDScript 诊断缓冲去字典化 + 批量写入，账本/索引数组/能量流/signal 分泌源逐个扁平化，纯 GDScript 拿到大收益。
- **结论：≤8 ms/tick 已达成**（v0.45 两轮 7.48 / 7.29 ms），v0.46 signal -31% 进一步扩余量。第 6 专项确认 metab_env 波动是负载噪声、beh_apply 下沉 C++ 有 1 ULP 差异被否决，性能专项到收益递减拐点。

---

## 3. 已经完成了什么

### 最近三个版本（重点，都是真实窗口分段计时驱动，全部逐位闸门通过）

**v0.46.0 — signal 分泌源批量写入（当前版本，纯 GDScript，DLL 未动）**
- 定位：signal 段加 `sig_collect`/`sig_add` 埋点，834 µs 中 sig_add 占 795（95%，524 源）。真凶是每源三次跨对象动态 `call()` + Vector2 分配 + 双层字典写入，与 C++ 采集（32 µs）无关。
- 改动：`EnvironmentField.add_signal_sources_batch()` 把 N 次 call 合成 1 次（同脚本内静态调 `get_grid_position` + 内联 `add_source`），indices 升序 / float32 位置 / 累加顺序不变。
- A/B：sig_add 795→516/535 µs（-33%）、signal 834→559/577 µs（-31%）。SHA 不变 `BFCF3222…00D7`。

**v0.45.0 — behavior 裸指针化 + 去字典（核心达标版本）**
- 定位：behavior 段加 5 段埋点，1456 µs 中 beh_collect 694（47%，C++ `collect_inputs_grid` 内层 1025×8 次 `inputs.set()` 的 COW/边界检查，与 v0.44 碰撞同源）+ idxarr 110 + apply 283。
- 改动：`collect_inputs_grid()` 一次 `ptrw()` 裸指针化；`get_field_sample_index_array()` 用活细胞升序索引直写替代字典 `.get()`；`_apply_base_metabolism()` 的 `self_cost` 诊断写入循环外取数组直写。
- A/B：beh_collect 694→392、beh_idxarr 102→30、metab_base 690→311、裸 tick **8.04→7.48/7.29 ms（同会话两轮均低于 8 ms，首次稳定达标）**。DLL SHA 更新为 `BFCF3222…00D7`。

**v0.44.0 — metab_env 扁平化 + C++ 碰撞裸指针化**
- 微探针：typed 属性访问 344→176 µs；`_energy_flow_add` 字典查找 1099 µs vs 扁平直写 329 µs。physics 拆 FFI 两侧后确认 3.97 ms 中 3.68 ms（93%）在 C++ `resolve_collisions`，GDScript 准备/写回 <10 µs。
- 改动：genome typed 访问 + 能量流扁平直写；`resolve_collisions()` 内层 pair 循环一次 `ptrw()` 裸指针。
- A/B：metab_env 2888→1496（-48%）、碰撞 3682→1679（-54%）、裸 tick 10.66→7.92/8.10 ms（两轮跨线，未达标）。DLL SHA `81142C2A…0738F`。

**更早里程碑**：v0.43 dev 只读数组外提（p50 3285→71 µs）；v0.42 场采样准备下沉（setup_positions 559→150、GPU post 678→279、metab_fields 2243→1022 µs）；v0.41 账本批量化（metab_env 5.27→2.56 ms）；v0.40 三角展开下沉 C++（渲染缓存 32.8→8.7 ms）；v0.39 GPU 合批（draw call 4231→259 但帧时不变）；v0.38 皿外方点修复；v0.37 原生默认开启（此前优化从未生效！native=false 6.2 TPS vs true 54–62 TPS）；v0.36 `collect_inputs_grid` 融合；v0.33 C++ 源码/DLL 入库；v0.29 分裂对齐；v0.25–v0.28 预览真实内核/膜弦/时间轴。

### 闸门现状（接手后任何改动都要重跑）
- `SmokeTest: SCRIPTS=71 FAILURES=0`（工作区 + D 盘双工程，新增脚本必须登记 manifest）。
- `NativeParityProbe: OK failures=0`，m1_photo tick=1 `872470415` / tick=700 `3284848376`，与 v0.44 起逐位相同。
- 原型工程 `spatial_parity_probe.gd`：`SPATIAL_PARITY OK (total_failures=0)`（邻域 CSR 657380、collect_inputs 12000、碰撞 73620 次修正全等）。
- 真实 GPU 窗口 `WINDOW_BENCH_FLAT_PARITY values=5125 failures=0`（逐轮通过）。
- 生产 DLL SHA-256 `BFCF32227328E74120F93D4E42CF8775D3D1E7A72AEA50AC7E5E1722FB4E00D7`（v0.46 未改 DLL，沿用 v0.45）。

---

## 4. 当前状态：≤8 ms/tick 已达标

v0.45 同会话两轮裸 tick **7.48 / 7.29 ms**（余量 0.5–0.7 ms），v0.46 signal 再降 31%。1025 细胞真实窗口 v0.46 低负载轮分段：

| 段 | 耗时 | 说明 |
| --- | ---: | --- |
| metabolism | 3.3–4.1 ms | `metab_env` 1.42（负载高时到 2.3）/ `metab_fields` ~1.1–1.3 / `metab_base` 0.31 |
| physics | ~1.9 ms | `phys_collision` 1.64（C++ 已 ptrw 优化）、Verlet 38 µs、project 184 µs |
| behavior | ~1.06 ms | collect 0.39（已 ptrw）、eval 0.30、apply 0.27（**不可下沉 C++**）、idxarr 0.03 |
| signal | ~0.56 ms | v0.46 批量写入后（原 0.83） |
| 头部准备 | 1.2–2.0 ms | tick_setup，受机器负载波动大，不计入裸 tick 验收 |

**性能专项已到收益递减拐点**：第 6 专项确认 metab_env 波动是机器负载噪声（微探针稳定态 1.04 ms，无隐藏热点）；`beh_apply` 下沉 C++ 经 20000 组原型验证有 53 处 1 ULP 差异被否决。剩余大段要么已榨过、要么受负载主导，硬抠边际收益已低于逐位 hash 风险。

**注意物理限制**：机器长时间满载会过热蓝屏（`clock_watchdog_timeout`）。性能基准单次 ≤60 秒，禁止长跑满载扫描；并发编译 `-j 4`。

---

## 5. 下一步计划（性能专项已收尾，以下为可选方向）

性能核心 KPI 已达成，无明确的必做性能项。若继续开发，建议方向（由用户定优先级）：

1. **高倍速真实体感**（若用户关心倍速流畅度）：tick3 高倍速路径 p50 约 30 ms（3 tick 串行），尚未专项优化。先**只读确认它是否真是体感瓶颈**，再决定是否动 LOD 神经降频 / 单帧 tick 上限（当前 12）；**不要碰已通过的裸 tick 口径**。

2. **玩法完成度收尾**：第一阶段复刻此前只是"基本完成"。做一次系统性的玩法对齐验收，与 v1.1 合并稿逐条对照，列出剩余缺口。

3. **若仍要扩性能余量**：只在有明确新热点证据时动手，**必走先测后改**（分段计时 → 同会话 A/B）。已证伪方向见 §7，别重复。

4. **任何改动的固定流程**：分段计时定位 → 同会话 A/B → 双工程 SmokeTest + NativeParityProbe + 原型 spatial parity + 真实窗口 flat parity → 如实记录 `cpu_budget_met` → CHANGELOG / 分析文档 / 技术设计文档 / 项目记忆同步 → 提交 + tag + push。

5. **不要重做已完成的事**：GPU 合批、consume、账本、场采样、碰撞/behavior 裸指针、signal 批量都已做；原生默认已开启。别再回头猜这些。

---

## 6. 新对话开工必读：路径、命令、铁律

### 工程路径
- **工作区（源码/git）**：`C:\Users\安\WorkBuddy AI\创生模拟器`
- **D 盘运行工程（Godot MCP 实际跑的）**：`D:\Tools\Godot_v4.7.2\project\cellarium`
- **Godot 可执行文件**：`D:\Tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe`
- **原生源码**：`native/`；**DLL 与 .gdextension**：`godot/cellarium-release/bin/`
- **Cell Lab 反编译源码**：`analysis/celllab_apk_extract/decompiled_zh|macro/`（gitignore，代码级分析见分析文档 §32+）
- **GitHub**：`Oatol/cellarium`
- **Shell**：PowerShell 7（默认已是 Core）；禁止用 Git Bash。验证一律程序化，**不动用户鼠标、不截图**。

### 双工程同步（每次改完脚本必做）
工作区与 D 盘各有一份脚本。改完把相关 `.gd` 从 `godot/cellarium-release/` 复制到 `D:\Tools\Godot_v4.7.2\project\cellarium\` 对应路径。**保留 D 盘工程的 MCP autoload、脚本 `.uid`、场景 `unique_id`**。

### 常用命令
```powershell
$exe="D:\Tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$ws="C:\Users\安\WorkBuddy AI\创生模拟器"
$proj="D:\Tools\Godot_v4.7.2\project\cellarium"

# 无头闸门（先看 ASCII/数字，中文输出会乱码）
& $exe --headless --path $proj --script res://tools/SmokeTest.gd 2>&1 | Select-String "SCRIPTS=|FAILURES="
& $exe --headless --path $proj --script res://tools/NativeParityProbe.gd 2>&1 | Select-String "NATIVE_E2E|FAIL"

# 真实 Vulkan 窗口基准（须 GPU，headless 不行）
# 用 Godot MCP project_run 打开 res://tools/WindowPerfBenchmark.tscn，跑完读：
# C:\Users\安\AppData\Roaming\Godot\app_userdata\cellarium\window_perf_bench.txt

# 推送（每版 tag + CHANGELOG + 快照）
$tok=(gh auth token).Trim()
git -C $ws -c credential.helper= push "https://Oatol:$tok@github.com/Oatol/cellarium.git" main
git -C $ws -c credential.helper= push "https://Oatol:$tok@github.com/Oatol/cellarium.git" v0.46.0
```

### 测量口径（关键，避免误判）
- 真实窗口基准：`tools/WindowPerfBenchmark.tscn/.gd`，固定 1025 细胞冻结，手动 5 相位各 120 帧，读数**在场景内落盘**到 `user://window_perf_bench.txt`，不经 debugger/game_eval。
- 实时诊断场景：`tools/WindowPerfScenario.tscn`（铺 1324 细胞冻结做 A/B）。
- `FrameProfiler` 自写分段在 GUI/调试器下与 TPS 不自洽，**只保留采样不上屏**。
- 真实窗口跑完会后台冻结，`game_eval` 报 `EVAL_GAME_NOT_READY` —— 这是正常的，分段读数必须落盘后再读文件。
- **同会话 A/B 才宣称收益**；跨会话基线受机器负载影响会漂移。
- `PerfProbe` 埋点用任意键 `begin/end`，只读诊断不进 STAGES / state hash；输出过滤器在 `WindowPerfBenchmark.gd`（`metab_`/`tick_`/`setup_`/`phys_`/`beh_`/`sig_` 前缀，另输出 ENVIDIAG / GPUDIAG / SIGSRC 三段诊断）。子阶段 average 用 `diagnostic_averages()`。

### 确定性 / C++ 铁律
- GDScript `float`=double，`PackedFloat32Array`=float32；C++ 用 double 累加/tanh，写回转 float32；**中间值回 GDScript 必须 `PackedFloat64Array`**。
- 完整 `apply_outputs_flat()` 下沉曾因 1 ULP 差异被否决，位移留在 GDScript `apply_cached_intents()`。
- **改 C++ 必须**：同步 `native/` 与 D 盘 `gdext_work/template/src/` → 重编译 DLL → 复制双工程 → 跑逐位闸门。第三方 godot-cpp/API JSON 不入库，`native/README.md` 记 commit/hash。
- 不传 APK / 反编译中间产物 / 凭据到 GitHub。

### 脚本层约定
- Autoload 实为 `CmdBus → TickCore → EnvironmentMgr → OrganismMgr`；静态单例 `CommandBus.instance` / `TickEngine.instance`。
- 脚本不用 `class_name`，调用方 `preload`；Variant 目标显式写类型。
- `Camera2D.zoom` 必须 `Vector2(2,2)`；`PanelChrome` 内容重挂到 `ChromeRoot`，外部深层路径须带 `ChromeRoot`；HUD 在 `UI/HUD`，DishView 路径 `../../DishView/...`。
- 细胞数据对象一律 `RefCounted`；MultiMesh 只作千级 LOD；CPU 场越界 0.0，GPU shader 一致；`main.tscn`/`sandbox.tscn` 结构同步。
- GDScript lambda 按值捕获，回写外层用 RefCounted 包装；`add_source` 写 pending 需 `advance_field_tick()` 结算；解析断言用 `ResourceLoader.load(..., CACHE_MODE_IGNORE)` + `can_instantiate()`。

---

## 7. 已证伪的猜测（别重复踩坑）

- ❌ "GPU 合成/合批能降帧时间" —— v0.39 证明 draw call 4231→259 帧时间不变。
- ❌ "metab_env 瓶颈是 consume" —— v0.41 微探针证明 M1 光合不调 consume，真凶是账本逐条建 entry。
- ❌ "physics 差额是 GPU 同步" —— v0.42 证明 dispatch+sync 仅 0.30 ms，真凶是逐细胞临时数组/字典缓存。
- ❌ "原生优化已生效" —— v0.37 前默认 false，从未生效；现在默认 true，DLL 缺失自动回退。
- ❌ "GDScript 手写插入排序建 CSR 更快" —— 实测反慢。
- ❌ "碰撞远邻可全过滤" —— 会破坏连锁分离。
- ❌ "behavior 的 `Vector2.rotated` 可下沉 C++" —— v0.35 判断，v0.46 第 6 专项原型 20000 组复验：godot-cpp `Math::sin/cos(float)` = `std::sin/cos(float)`，但与 GDScript rotated 有 53 处 1 ULP 差异，位移必须留 GDScript。
- ❌ "metab_env 1.4–2.3 ms 波动是隐藏热点" —— v0.46 第 6 专项微探针（稳定态）证明是机器负载噪声：prep_typed 197 + group_flow 382 + ledger_batch 461 ≈ 1.04 ms，与低负载窗口吻合。
- ⚠️ 拖拽卡顿真凶是每 tick 后 `_rebuild_cache()`（43.4 ms），已 C++ 降到 1.03 ms。
- ⚠️ GDScript `PackedFloat32Array` 局部引用写回有效：`local = arr[0]` 后 `local[i] = v` 会写回原数组（v0.46 实测），批量缓冲直写可用。
