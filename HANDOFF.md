# 创生模拟器 · 会话交接文档

> 面向**完全没有上下文的新对话**。读完本文件即可接手，不必翻历史聊天记录。
> 本文件更新于 2026-11-28，最新版本标签 `v0.49.0`；工作区有**阶段 A 高倍速调度修复**、**阶段 B3 独立模拟线程（默认关闭）**，均已随 v0.47.0 发布，见 §4.1–§4.5。

---

## 0. 一句话现状

我们在 Godot 4.7.2 里复刻 Cell Lab 的人工生命沙盒，第一阶段玩法已基本对齐。**v0.47.0 把碰撞内核重构成 Cell Lab 式单轮软弹力**（真实皿 1024 细胞整 tick 墙钟 8801→6869 µs，碰撞段 1795→109.5 µs，16.4×），**v0.48.0 把场采样从「每 tick 两次 GPU 往返」改成「每 tick 一次整场回读 + 两次 C++ 本机查表」**（tick1 p50 −20% 量级），**v0.49.0 把 `metab_env` 的每 tick 重建表改成世代缓存 + 副作用循环下沉 C++**（3000 细胞 `metab_env` 2512.7→1301.5 µs，`metab_env_prep` 1232.3→5.1 µs）。state hash 基线 v0.47–v0.49 为 `114854044`，v0.50.0 重建为 `665147009`，**v0.51.0 重建为 `2825738337`**。**真实窗口当前实测：tick1 p50 4555–5214 µs、tick3 p50 12449–13396 µs，单 tick 已稳在 8 ms 预算内。** 下一个瓶颈是 `cache`（渲染缓存重建 p50 8531–8619 µs，把 3× 倍速相位帧时推到 16.66 ms）。

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

### 最近版本（重点，都是真实窗口分段计时驱动，全部逐位闸门通过）

**v0.49.0 — metab_env 三项下沉（当前版本）**
- 定位：`metab_env_prep` 占 `metab_env` 的一半（3000 细胞 1232.3 / 2512.7 µs），每 tick 遍历 `genomes` 重建 `respiration` / `nutrition_priority` 两张按个体表 —— 而它们只在基因变化时才会变。
- 改动：两张表并入按世代失效的原生缓存；`compute_environment_batch` 新增 `consume_cells` 输出；新增 `apply_environment_outcome()` 把逐细胞副作用 + 账本分组整段下沉（裸指针 + 256 定长桶单遍）；`EnergyLedger.record_batch()` 改单遍扫描 + 环形缓冲。
- A/B（`MetabolismBreakdownProbe`，3000 细胞 / 60 tick / native）：`metab_env` 2512.7→**1301.5 µs（−48.2%）**、`metab_env_prep` 1232.3→**5.1 µs（−99.6%）**。
- 真实窗口（1025 细胞，同机四跑）：tick1 p50 off 6107/6154 → eager **4555/5214**；tick3 off 16568/16628 → eager **12449/13396**；`STAGE metabolism` 1819.7/1756.0 → **1162.2/1215.7**。off 两跑差 0.77%。
- **口径**：本轮绝对值可与 v0.47 日志直接对比（off 走 v0.47 路径，6130 vs 6282 吻合）。v0.48.0 记录的 27426/20587 是后台进程抢 GPU 的高位。

**v0.48.0 — 整场回读一次 + C++ 批量查表（阶段 2 主方案）**
- 定位：一个 tick 里两次按细胞采样用的是同一份场状态（场扩散在 physics tick 之后才推进），旧路径却付了两次完整 GPU 往返，每次约 967 µs。
- 改动：`CellSpatial.sample_fields_nearest()` 新增 C++ 最近格查表（**全程 float32**，逐位复刻 shader；GDScript 的 double 乘法在 resolution 非 2 的幂时会分叉）；`_read_active_buffer()` 改 `to_float32_array()` + `slice()` 并同时产出 `_field_flat_mirror`；`sample_cells_flat()` 三级路由（镜像查表 / CPU 回退 / GPU dispatch）；`eager_mirror_readback` 把回读放在 `diffuse_tick` 的 sync 之后（比延迟到下次采样便宜 5.2×）。
- A/B（同机背靠背，off/lazy/eager 三跑）：tick1 p50 27426 / 22341 / **20587**；tick3 47742 / 38938 / **34671**；`setup_dispatch` 9823.9 / 8190.2 / **112.1**；`metab_fields` 2060.2 / 245.3 / **239.6**。基线噪声带 4.4%。
- 新闸门：`tools/FieldMirrorParityProbe.gd`（10000 值逐位对照镜像查表 vs GPU dispatch，0 差异）。
- **口径**：该轮绝对数值比 v0.47 日志高约 4 倍（测量期间机器有无关后台进程抢 GPU），只承认同会话相对比较。

**v0.47.0 — 碰撞内核重构为 Cell Lab 式单轮软弹力（已 tag + push）**
- 定位：碰撞成本真凶是**网格尺寸**不是迭代次数。旧路径 `cell_size` 写死 64.0 而典型细胞直径仅 14 → 每桶挤约 20 个细胞、9 桶扫 180 候选只有约 6 个真邻居（30× 无效扫描）；单这一项 2.5×，叠加迭代与 pairs 物化才有 16–56×。
- 改动：`resolve_collisions_soft()` 单次网格遍历、不迭代、不物化 pairs、先比距离平方再开方、每对只推开 `穿透×0.5×stiffness×softness`；`cell_size <= 0` 由内核按存活细胞最大半径倍率自动推导（9 格邻域不漏对的下界）。
- A/B：`phys_collision` 1795.1→109.5 µs（16.4×）、整 tick 8800.6→6869.0 µs（TPS 113.6→145.6）。手感：最坏重叠 8.44→4.62（更小）、平均 0.437→0.679（contact 14 的 1.7%）。state hash 基线重建为 `114854044`。

**v0.46.0 — signal 分泌源批量写入（纯 GDScript，DLL 未动）**
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
- `SmokeTest: SCRIPTS=95 FAILURES=0`（工作区 + D 盘双工程，新增脚本必须登记 manifest）。
- `NativeParityProbe: NATIVE_E2E: OK (failures=0)`。
- `WorkerEngineProbe`（场景，非 `--script`）：`PROBE_SEQ hash=2825738337` / `PROBE_WORKER hash=2825738337` / `match=true`（v0.51.0 基线）。
- `SplitBandProbe`（headless）：`glue_off_d0 links=0`（未生成黏附素时零连接）。
- `FieldMirrorParityProbe`（**需 Vulkan 窗口**）：`FIELD_MIRROR_PARITY values=10000 failures=0`。
- `GpuSamplingTest`（**需 Vulkan 窗口**）：`GPU_SAMPLING PASS`，headless 打印 SKIP。
- `LedgerBatchParityProbe`（headless）：`LEDGER_PARITY: checked=36 failures=0 entries=7`。
- 真实 GPU 窗口 `WINDOW_BENCH_FLAT_PARITY values=5125 failures=0`（逐轮通过）。
- 生产 DLL SHA-256 `C58878CECF49F76C7B66181ACE0738D1DE43C0B874EF18B8FCDEF9AB6ED54FD5`（v0.49.0）。

---

## 4. 当前状态：≤8 ms/tick 已达标

**v0.49.0 真实窗口实测（Vulkan，1025 细胞冻结，同机四跑）**：

| 指标 | off #1 | off #2 | eager #1 | eager #2 |
| --- | ---: | ---: | ---: | ---: |
| tick1 work p50 | 6107 | 6154 | **4555** | **5214** |
| tick3 work p50 | 16568 | 16628 | **12449** | **13396** |
| tick1 frame ms avg | 6.96 | 6.86 | 6.76 | 6.68 |
| tick3 frame ms avg | 16.56 | 16.76 | 13.38 | 14.58 |

tick3 除以 3 即单 tick 成本：eager 下 4150–4465 µs，**稳在 8 ms 预算内，余量 3.5 ms 以上**。1× 倍速帧时 6.68–6.76 ms（≈148 fps）；3× 倍速帧时 13.38–14.58 ms，仍低于 16.7 ms 但余量只剩 2 ms 左右。

eager 模式下 1025 细胞的分段：

| 段 | 耗时 | 说明 |
| --- | ---: | --- |
| `PART physics` | 3337–3542 µs | 含 `STAGE physics 345`（`phys_collision` 137.7、`phys_project` 130.3、`phys_verlet` 38.3）+ `STAGE metabolism 1162–1216` + `behavior 1062` + `signal 479` |
| `PART field` | 1087–1316 µs | 含那一次 20 KB 整场回读（eager 下搬到这里） |
| `cache`（渲染缓存重建） | 8651–8672 µs | **新头号单项**，`tick3_cache` 帧时 16.66 ms 的主因 |
| `STAGE metabolism` | 1162–1216 µs | `metab_env` 558–581（`ledger` 382 / `compute` 62 / `tail` 39 / `fetch` 23 / `prep` 4.5 / `consume` 2）+ `metab_base` 232 + `metab_fields` 180 |
| `STAGE behavior` | 1000–1062 µs | `beh_collect` 418、`beh_eval` 310、`beh_apply` 195（**不可下沉 C++**）、`beh_copy` 38、`beh_idxarr` 22 |

**已到收益递减区**：`beh_apply` 下沉 C++ 经 20000 组原型验证有 53 处 1 ULP 差异被否决；GDScript 层多核分片实测负收益（Amdahl 上限 ~1.08×）。再降只能动 C++ 内核内部并行或阶段 4 GPU 主体化（需重建 hash 基线）。

**注意物理限制**：机器长时间满载会过热蓝屏（`clock_watchdog_timeout`）。性能基准单次 ≤60 秒，禁止长跑满载扫描；并发编译 `-j 4`。

### 4.1 阶段 A：高倍速调度修复（已实施，未发布）

新增 `tools/HighSpeedPerfBenchmark.gd/.tscn`（真实 Vulkan 窗口、真实 main.tscn tick 链、固定细胞数、1×/8×/16×/32× 实测）。实测确认 16×/32× 有效倍速封顶 12× 是 §2.6 冻结规格（"每帧 12 tick 余量结转"）+ T11 硬断言的结果，**不是 bug**；真正的问题是 carry 双重计数。

改动（不改 tick 内容、不改 hash、不改冻结规格）：
- `TickCore._process()`：修复 carry 双重计数（`_accumulator` 只留小数余量，整数并入唯一 carry 欠账来源，下一帧优先消化）。1024 细胞 carry max 16× 4096→294、32× 4096→1456。
- `Main._on_speed_changed_render()`：接 `speed_changed` → 按 `get_render_fps()` 设 `Engine.max_fps` + `ProjectSettings run/max_fps`，32× 锁 30 fps。
- 未做：自适应 budget（无收益）、放宽单帧上限 24（违反 §2.6/T11）、`should_update_field()`（改 hash，需用户拍板）。

闸门：SmokeTest `SCRIPTS=72 FAILURES=0` + T11、NativeParityProbe `OK (failures=0)`、state hash 全 match。详见 `analysis/高倍速真实窗口实测与架构判断.md` §5。

### 4.2 阶段 B3：独立模拟线程生产接入（已实施，未发布，默认关闭）

- 权威模拟进入 worker：`scripts/system/WorkerSimEngine.gd` + `SimSnapshot.gd` 扩展；主线程通过 `Main.start_threaded_simulation()` 建立隔离 CPU 场世界、native 主线程预热、worker 连续跑完整 tick，每帧把渲染所需 SoA 写回主场景 `CellArray`，现有渲染器零改动。
- 调度：`TickCore.worker_target_mode` 发布 `target_tick`，不再走主线程每帧 12 tick；旧同步路径与 12 tick 上限保留。`Main.threaded_simulation_enabled` 默认 false；`HighSpeedPerfBenchmark --worker=1` 可启用 A/B。
- 修复：`SaveManager.capture()` 深拷 `field._pending_sources`，否则 64×64 场 restore 后残留 32×32 源缓冲导致信号写入越界；`WorkerSimEngine.repair_field_after_restore()` 兜底重建场缓冲。
- hash 基线：worker 路径采用 CPU 权威场，黄金值重建；`tools/WorkerEngineProbe.tscn` 512 细胞 / 32 场 / native / 30 tick，主线程顺序执行与 worker 同为 `4234109495`，快照首细胞坐标一致。旧主线程 GPU 场基线 `3284848376` 继续用于 legacy 路径。**v0.47.0 起这两个值都已作废**：碰撞软弹力重建后 worker 基线为 `114854044`（v0.48.0 仍为 `114854044`）。
- **⚠️ 2026-11-28 重大纠正**：B3 初版宣称的「512 worker 32× 有效 32.09–32.24× / 连续 5 秒 32.02×」**全部作废**。根因是 `HighSpeedPerfBenchmark` 用 `_process(delta)` 累加墙钟，delta 被 vsync/max_fps 钳在 16.7ms，60 帧只累计 1.0s，而外部 Stopwatch 实测进程真实运行 32.2s。基准已改用 OS 单调钟为墙钟。
- 修正墙钟后同会话真实 A/B（32× 档，60 帧）：**512** 旧 0.36×（720 tick/33.2s）→ worker **1.21×**（1910 tick/26.3s，85.3 tick/s）；**1024** 旧 0.86× → worker 0.83×（无提升）。worker 相对旧路径在 512 约 3.4× 提升，但两条路径都远未达 32×。**阶段 B3「突破 12×」目标未达成。**
- 权威单 tick 成本（worker 世界 PerfProbe）：512 total 6.24ms（metabolism 3.45、physics 1.86、metab_fields 1.33、collision 1.62），1024 total 12.10ms（metabolism 6.38、physics 3.98）。各段近线性 2×，无单一病理热点；单 worker 理论上限 161/82 tick/s 与实测 85/60 自洽。
- **未达标项**：worker 单 tick 成本是高倍速的真正瓶颈，需阶段 C（多核分片）或阶段 D（GPU 主体化）实质降低。worker 模式保持默认关闭，**不得对外宣称已达 32×**。

闸门：双工程 SmokeTest `SCRIPTS=81 FAILURES=0`、NativeParityProbe `OK (failures=0)`、WorkerEngineProbe `PROBE_VERDICT OK`。详见 `analysis/阶段B_独立模拟线程方案.md` §10。

### 4.3 v0.47.0 阶段 1：碰撞内核重构（已实施，未发布）

按 `analysis/架构诊断与重构路线.md` 的阶段 1 落地。诊断结论是碰撞**超线性爆炸**（1024 细胞 3.5 µs/细胞 → 3000 细胞 36 µs/细胞），根因不是"迭代次数太多"而是**网格尺寸与细胞直径严重不匹配**。

- 新增 `CellSpatial.resolve_collisions_soft()`：单轮固定网格遍历、不迭代、不物化 pairs、先比平方再开方、每对只推开 `穿透 × 0.5 × stiffness × softness`。旧 `resolve_collisions` 保留做 A/B 与回滚。
- **`cell_size` 从写死 64.0 改为按 `2 × cell_radius × 存活细胞最大半径倍率` 自动推导**。旧值 64 而典型细胞直径 14，每桶约 20 个细胞、9 桶扫 180 个候选只有约 6 个真邻居 —— 单项就浪费 2.5×。这是本次收益的最大来源。
- `CellPhysics.resolve_collisions_soft()` GDScript 回退与 C++ 逐位同序（`NativeParityProbe` 已验证）。
- `OrganismManager.soft_collision_enabled`（默认 true）= 回滚 / 同会话 A/B 开关。

实测（同会话，OS 单调钟）：

| 指标 | 旧 | 新 | 变化 |
| --- | ---: | ---: | --- |
| `phys_collision`（真实皿 1024 细胞） | 1795.1 µs | 109.5 µs | 16.4× |
| 整 tick 墙钟 | 8800.6 µs | 6869.0 µs | -21.9% |
| TPS | 113.6 | 145.6 | +28.2% |
| 等密度微基准 1024 / 3000 / 5000 | — | — | 24.2× / 40.9× / 56.5× |

手感：最坏重叠 4.62 单位（旧 8.44）、平均重叠 0.679 vs 0.437（contact 14 的 1.7%），细胞数与总能量两条路径一致。

闸门：双工程 SmokeTest `SCRIPTS=84 FAILURES=0`、NativeParityProbe `OK (failures=0)`、WorkerEngineProbe `PROBE_VERDICT OK`（**新 hash 基线 `114854044`**，旧 `4234109495` 作废）、BenchTest `FAILURES=0`。探针：`tools/CollisionSoftProbe.gd`（合成等密度 + cell_size 扫描）、`tools/CollisionRealProbe.gd`（真实皿完整 tick 链）。

### 4.4 v0.48.0 阶段 2：整场回读一次 + C++ 批量查表（已实施）

**关键事实**：一个 tick 里两次按细胞采样（behavior 前 / metabolism 前）用的是**同一份场状态**。`advance_field_tick` 在整个 `advance_physics_tick` 之后才推进，两次采样之间只有细胞位置在变，场值不变。旧路径却为这同一份场付了两次 `submit()+sync()`。

- `CellSpatial.sample_fields_nearest(field_flat, positions, resolution, center, radius)`：C++ 最近格查表，**全程 float32**。这一点不能省 —— GDScript 的 `float` 是 double，`normalized.x * resolution` 在 GDScript 里会被提升成 double 乘法；resolution 为 32/64 时因为乘 2 的幂恰好不出错，换成非 2 的幂就会与 shader 分叉。内核不做皿内判定（与 shader 一致，越界按最近格 clamp）。
- `EnvironmentField._read_active_buffer()` 改 `to_float32_array()` + 5 次 `slice()`，同时产出 `_field_flat_mirror`（扁平 5R²，零拷贝交给 C++）与 5 个通道数组。
- `sample_cells_flat()` 三级路由：native 内核可用且镜像新鲜 → 镜像查表；否则同步镜像后走 CPU 回退；再否则旧 GPU dispatch。native 缺失时行为等同 v0.47。
- **`eager_mirror_readback = true`（默认）**：回读放在 `diffuse_tick` 的 sync 之后立刻做。同一份 20 KB 回读，紧跟 sync 约 1.3–1.6 ms，拖到下一个 physics tick 开头（渲染队列已堆积）会涨到 8.5 ms —— **5.2×** 差距，这是 lazy/eager 两档的唯一区别。
- 镜像失效点：`_upload_active_buffer()`、`diffuse_tick` 的 buffer 翻转、`_flush_pending_deltas()`。`sample()` 也优先读镜像，让 `consume()` 不再触发单元素 dispatch。

真实窗口三档 A/B（同机背靠背，环境变量 `WINDOW_BENCH_MIRROR=off|lazy|eager`）：

| µs/tick | off | lazy | eager |
| --- | ---: | ---: | ---: |
| tick1 p50 | 27426 | 22341 | **20587** |
| tick3 p50 | 47742 | 38938 | **34671** |
| `setup_dispatch` | 9823.9 | 8190.2 | **112.1** |
| `metab_fields` | 2060.2 | 245.3 | **239.6** |
| `PART physics` | 17436.6 | 13785.2 | **5321.9** |
| `PART field` | 1196.6 | 1329.2 | 7878.9 |

**口径**：本轮绝对值比 v0.47 日志（tick1 p50 6282）高约 4 倍，因为测量期间机器上有无关后台进程抢 GPU（同一张 RTX 3050 Laptop）。只承认同会话相对比较；基线噪声带 4.4%（off vs off2）。

闸门：双工程 SmokeTest `SCRIPTS=95 FAILURES=0`、NativeParityProbe `OK`、WorkerEngineProbe hash `114854044` 不变、`FieldMirrorParityProbe values=10000 failures=0`、`GpuSamplingTest PASS`、`WINDOW_BENCH_FLAT_PARITY 5125/0`。新探针 `tools/FieldMirrorParityProbe.gd` 已登记 manifest。

---

### 4.5 v0.49.0 metab_env 三项下沉（已实施）

**关键事实**：`metab_env_prep` 占 `metab_env` 的一半（3000 细胞 1232.3 / 2512.7 µs），它每 tick 遍历 `genomes` 重建两张按个体表（`respiration`、`nutrition_priority`）—— 而这两张表只在基因变化时才会变。同一份数据在 `_rebuild_native_metabolism_cache()` 里本来就要每世代遍历一遍，顺手派生即可。

- `OrganismManager._native_org_respiration` / `_native_org_priority`：在世代缓存里派生；失效已覆盖 `_apply_gene_payload()`（`nutrition_priority` 在同 payload 落地）与 `_set_gene_respiration()`。**新增基因写入路径时记得调 `_invalidate_native_metabolism_cache()`**，否则这两张表会读到旧值。无原生扩展时保留原每 tick 重建路径作为等价参照。
- `CellMetabolism.compute_environment_batch()` 新增 `consume_cells` 输出（升序、仅 `food_gain > 0 && (ZYGOTE || NITROCYTE)`）。M1 全 PHOTOCYTE 时为空表，省掉全细胞类型扫描。
- `CellMetabolism.apply_environment_outcome(...)`：逐细胞能量/能量流/健康更新 + 账本分组整段下沉，裸指针 + 256 定长桶单遍走完，`consume` 结果按升序稀疏覆盖写回。中间值仍走 `PackedFloat64Array` 保 double。
- `EnergyLedger.record_batch()` 改单遍扫描 + 环形缓冲；淘汰从逐条 `pop_front()`（每次 O(n)）改成一次性裁头。

`MetabolismBreakdownProbe`（3000 细胞 / 60 tick / `CELLARIUM_NATIVE=1`，同会话 A/B）：`metab_env` 2512.7→**1301.5 µs（−48.2%）**，`metab_env_prep` 1232.3→**5.1 µs（−99.6%）**，`metab_fields` 持平。收益几乎全部来自 prep 归零。

真实窗口 A/B（1025 细胞，同机四跑）：

| µs/tick | off #1 | off #2 | eager #1 | eager #2 |
| --- | ---: | ---: | ---: | ---: |
| tick1 p50 | 6107 | 6154 | **4555** | **5214** |
| tick3 p50 | 16568 | 16628 | **12449** | **13396** |
| `STAGE metabolism` | 1819.7 | 1756.0 | **1162.2** | **1215.7** |
| `metab_fields` | 851.3 | 830.5 | 180.0 | 189.4 |
| `setup_dispatch` | 1319.8 | 1595.0 | 78.9 | 82.6 |

`off` 两跑差 0.77%，噪声带很紧；eager 两跑差 14.5%，取均值 tick1 −20.3% / tick3 −22.1%。

**口径**：本轮绝对值可与 v0.47 日志直接对比 —— `off` 走的就是 v0.47 采样路径，本轮 6130 / 6154 µs 与 v0.47 记录的 6282 µs 吻合。v0.48.0 记录的 27426 / 20587 是那次测量期间后台进程抢 GPU 的高位，不代表代码退化。**下次重跑基准时若 `off` 显著高于 6300，先查后台进程再下结论。**

闸门：双工程 SmokeTest `SCRIPTS=95 FAILURES=0`、NativeParityProbe `OK`、WorkerEngineProbe hash `114854044` 不变、`LedgerBatchParityProbe checked=36 failures=0`、`WINDOW_BENCH_FLAT_PARITY 5125/0`（off 与 eager 各一次）。

---

## 5. 下一步计划（v0.49 之后）

碰撞已不是瓶颈（137.7 µs），场采样 GPU 往返已减半，`metab_env_prep` 已归零。剩余大头按 `analysis/架构诊断与重构路线.md`：

1. **`cache`（渲染缓存重建）p50 8531–8619 µs** —— 现在它是 `tick3_cache` 相位帧时 16.66 ms 的主因，3× 倍速已经贴着 60 fps 的线。这是当前最值得动的一块。
2. **`advance_field_tick` 里的那一次 20 KB 整场回读**（eager 下 `PART field` avg 1087–1316 / p50 829–958）。要再降只有两条路：把场整体移出主 tick 关键路径（阶段 4 GPU 主体化 / 阶段 B 独立模拟线程），或减少回读频率（场按固定间隔推进，会改语义）。
3. **`metab_env_consume`（3000 细胞 590.1 µs，M1 真实皿只有 2 µs）** —— 全是 `consume_nutrient` / `consume_signal` 的跨对象动态 call，批量化为一次 native 调用是明确收益，但会动到环境场消耗语义，需要单独闸门。
4. **`metab_env_ledger` 307.8 µs** —— 现在只剩每 tick 为尾部 `_max_entries` 条建 Dictionary。
5. **`behavior`（约 1000–1062 µs）**：`beh_collect` ~418 + `beh_eval` ~310。**注意 `beh_apply` 的 `Vector2.rotated` 已两次验证不可下沉 C++（1 ULP 差异）**。
6. **阶段 3：调度层降频 + 工作量硬上限**（低成本）：神经/行为按固定间隔更新；每细胞接触数硬上限。
7. **阶段 4：GPU 主体化**（长期）：collision 的 Gauss-Seidel 依赖已被阶段 1 消除；behavior（8→4→6 网络）+ `collect_inputs_grid`（整数邻域计数可保位）可搬 compute。
8. **高倍速真实体感**：worker 单 tick 成本降下来后 B3 的 32× 才有实际可能；先用 OS 单调钟口径重测，不要用 delta。
9. **玩法完成度收尾**：与 v1.1 合并稿逐条对照，列出剩余缺口。

**任何改动的固定流程**：分段计时定位 → 同会话 A/B → 双工程 SmokeTest + NativeParityProbe + WorkerEngineProbe + FieldMirrorParityProbe + LedgerBatchParityProbe + 真实窗口 flat parity → 如实记录 `cpu_budget_met` → CHANGELOG / 分析文档 / 技术设计文档 / 项目记忆同步 → 提交 + tag + push。

**改物理/连接/分裂时必须额外跑的三道**（v0.52 起）：
- `PhysicsStepParityProbe`：`checked=2001 failures=0`，含 `break_links` 逐位一致。
- `LinkDeriveProbe`：`failures=0`，`native_us` 应为个位数（1025 细胞 / 999 连接）。
- `SplitAxisProbe`：`RESULT failures=0`，四用例瞬间 `axis_dy=0.000` —— **分裂排布只由分裂轴决定**（技术设计文档 §4.5 不变式）。

**不要重试的路线（已证伪）**：
- `beh_apply` / `apply_outputs_flat()` 下沉 C++（`Vector2.rotated` 与 `Math::sin/cos` 有 1 ULP 差异）。
- GDScript 层多核分片（逐位一致但 0.35–0.42× 负收益，可并行占比 <11%）。
- GPU 合成 / draw call 合批（4231→259 但帧时间不变）。
- 用「分裂后的 `cell_orientation`」反推分裂轴（已被 `Gene.e/f` 覆盖，见 §4.5）。

**测量纪律（本轮新增，务必遵守）**：
- 跑真实窗口基准前先确认没有残留 Godot 进程（`Get-Process | Where ProcessName -like "Godot*"`）。一个残留进程就能让 `dispatch+sync` 从 567 µs 涨到 4787 µs。
- 同会话背靠背跑 `off` 两遍界定噪声带，再跑目标变体；只承认超出噪声带的差值。
- 基准跑完进程不会退出（`_report()` 之后游戏继续跑），看到 `WINDOW_BENCH_FILE` 就手动 `Stop-Process`。

**不要重做已完成的事**：GPU 合批、consume、账本、场采样、碰撞内核、behavior 裸指针、signal 批量、整场镜像查表都已做；原生默认已开启。别再回头猜这些。

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
- 高倍速体感基准：`tools/HighSpeedPerfBenchmark.tscn/.gd`，真实 `main.tscn` tick 链，固定 512 / 1024 细胞，测 1× / 8× / 16× / 32×，落盘 `user://high_speed_perf_bench.txt`。实测 16× / 32× 均封顶约 12×，carry 到 4096，帧时未爆；结论见 `analysis/高倍速真实窗口实测与架构判断.md`。
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
- ❌ "碰撞贵是因为 6 轮迭代太多" —— v0.47 分解证明最大单项是**网格尺寸 64 vs 细胞直径 14**（约 2.5×），迭代+pairs 物化约 6×，两者相乘才有 16–56×。只减迭代只拿到 3–4×。
- ⚠️ **写碰撞/密度探针的两个坑（v0.47 连踩三次）**：① 若 `r_eff` 从 `spacing` 反推，`pack` 系数会被抵消，永远刚好相切、零碰撞对；半径必须由**基准间距**决定。② 若铺点循环在点数不足时收缩间距重试，同样会把 `pack` 抵消掉。探针必须先打印 `pen_before`/`resolved` 确认真的产生了重叠，再相信耗时。
- ⚠️ 拖拽卡顿真凶是每 tick 后 `_rebuild_cache()`（43.4 ms），已 C++ 降到 1.03 ms。
- ⚠️ GDScript `PackedFloat32Array` 局部引用写回有效：`local = arr[0]` 后 `local[i] = v` 会写回原数组（v0.46 实测），批量缓冲直写可用。
