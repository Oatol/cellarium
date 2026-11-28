# 阶段 B 实施方案：独立模拟线程 + §2.6 修订

> 编制于 2026-11-27。目标：真正突破 12× 封顶。**本轮只做方案设计，未改生产代码。**
> 前置实测见 `analysis/高倍速真实窗口实测与架构判断.md`；规格边界见 `docs/Godot项目技术设计文档.md` §2.6。

### 用户决策（2026-11-27）

1. **路径 B（重建 hash 基线）**：理由——hash 是验证工具不是契约，真正冻结的是 GNP1 / 存档 schema / Agent 契约 / 五通道场 schema；不该为守住基线值而用路径 A 的复杂跨线程同步点束缚架构演进。重建基线时必须保住 hash 的功能：同种子两次运行一致、native/GDScript parity、回放一致。
2. **倍速目标**：先做 26–27×，保留 32× 能力；**不做单帧上限约束**（§2.6 的 12 tick 上限将被放宽/移除），32× 留待阶段 C/D 降单 tick 成本后自然达成。
3. **实施策略**：先做最小 Thread 原型验证（不改生产代码），确认 GDScript `Thread` + `Mutex` + 双缓冲 PackedArray 在本工程可行，再分阶段落地。

---

## 0. 先说清楚三件硬事实

1. **12× 封顶是 §2.6 冻结规格 + T11 断言的结果**，不是 bug。用户已授权修订 §2.6。
2. **独立线程只解耦响应性，不增加单 tick 算力**。单 tick ≈ 0.58 ms（1024 细胞实测），单 worker 理论上限 1724 tick/s ≈ 28.7×，扣除同步 / 快照拷贝 / 调度抖动后实际约 26–27×。**够不到 32×**（需 1920 tick/s，单 tick 须 ≤0.52 ms）。
3. **GPU 场不能跨线程**。`EnvironmentField` 的 RenderingDevice 路径（`compute_list_*` / `buffer_get_data`）必须留主线程；这决定了解耦方式。

---

## 1. 架构调研结论（源码级证据）

### 1.1 可搬到 worker 的部分
- 权威态已是 SoA / RefCounted：`CellArray.gd:13-51` 全是 PackedArray（pos / prev / energy / alive / org_id / link / neural_weights / behavior_intents）；`OrganismStore.gd:20-31` 同理；`FoodStore.gd:17-23`；`EnergyLedger.gd:12-15`。
- 纯计算链：command 队列搬运 → physics → development → signal → metabolism（organism 侧）。
- 已有 fork-join 先例（`CellBehavior.gd:187/238`、`OrganismManager.gd:636`）：静态分区、只写不重叠切片、回调只操作 RefCounted。

### 1.2 必须留主线程的部分
- `TickCore.gd:5/58` `tick_advanced.emit()`、`CommandBus.gd:18-24` `command_executed.emit()`（同步回调 UI / Node，跨线程 emit 不安全）。
- `EnvironmentField.gd:709` 建 local rendering device；`:830/396/579` dispatch；`:927/933` `buffer_update/buffer_get_data` 同步回读；`:608-615` `get_state_hash()` 先 GPU 回读。RID 与命令队列非线程安全。
- 所有渲染：`CellBatchRenderer.gd:58-64`、`CellariumView.gd:29-69` 直读 cells PackedArray；`CellPolygonBatchRenderer.gd:172` native CellRenderCache；`FieldLayer.gd:31` 纹理更新。
- `Main.gd:110-125` 的整条 Node.call 回调链。

### 1.3 线程原语现状
全项目 `Thread` 0 处、`Mutex` 0 处、`Semaphore` 0 处；无跨线程场景树先例。阶段 B 是从零引入线程原语。

### 1.4 Godot 4.x 线程安全规则（官方文档）
- Node.get/set、场景树交互：**不安全**，须 `call_deferred` / `set_deferred`。
- RenderingDevice 直接 GPU 交互：**不安全**，须与 RenderingServer 同步。
- PackedArray：读元素、写元素多线程 OK；**改变容器大小须 Mutex**；共享引用写元素触发 COW 竞争，双缓冲必须交换引用而非原地写。
- RefCounted 引用计数：**非原子**，不可跨线程 new/free 同一对象。
- 最低开销同步：`Mutex.lock/unlock`（原生推荐）> `call_deferred`（下一帧，不宜每 tick）> signal（跨线程要 CONNECT_DEFERRED，走队列）。

---

## 2. 三条实施路径（按 hash 风险排序）

### 路径 A：保持 state hash 逐位不变（首选，复杂度最高）

思路：worker 跑 organism 纯计算；field 仍由主线程 GPU 更新；按 §2.6 的 `field_interval` 设同步点。

```text
worker tick 循环:
  for tick in batch:
    execute_commands()      # 无锁命令队列，不 emit signal
    physics / dev / signal / metabolism
    if tick % field_interval == 0:
      # 同步点：请求主线程更新 GPU field，等待结果
      mutex.lock(); field_request = tick; mutex.unlock()
      semaphore.wait()        # 主线程完成 GPU field 后 post
    write_snapshot()        # 双缓冲交换引用
main _process:
  if field_request: advance_field_tick(); semaphore.post()
  render(snapshot_back)     # 只读快照
```

- **hash 保持条件**：tick 顺序、field 更新时机（tick_index % interval）、float32 舍入顺序全部不变。
- **同步点频率**：16× field=2、32× field=4，从每 tick 降到每 2–4 tick，比纯主线程少 50–75%。
- **收益估算**：organism 侧 ~0.45 ms/tick + field 摊销 ~0.15 ms/tick ≈ 0.60 ms/tick → 约 **26–28×**。
- **风险**：命令队列与快照时序、hash/存档时点从帧对齐改为 tick 对齐；同步点实现错误会死锁或撕裂。

### 路径 B：重建 hash 基线（中等复杂度，精度语义变化）

思路：worker 跑完整 tick 链，field 用 CPU 回退（项目已有等价 CPU 实现）；主线程 GPU field 只做视觉。

- **hash 变化原因**：CPU / GPU 场最大误差 3.05e-5，不逐位相同；field hash 分裂。
- **收益**：无跨线程同步点，但 CPU field 扩散本身不便宜，未必比路径 A 快。
- **代价**：需重建黄金基线、重跑全链 parity、版本化声明 LOD 语义变化。**触及冻结边界，必须用户显式授权。**

### 路径 C：混合（折中）

worker 跑 organism + CPU 场，主线程保持 GPU 场作视觉层；hash 以 worker CPU 场为准。收益介于 A/B，复杂度同 B。

---

## 3. §2.6 修订建议（用户已授权）

当前：
> 单帧 tick 上限 12……16× / 32× 每渲染帧目标 tick 数 12（余量结转）

建议改为：

| 倍速 | worker 目标 tick/s | 模拟精度 | 渲染策略 |
| --- | --- | --- | --- |
| 1× / 3× | 60 / 180 | 全精度 | 60 fps，主线程同步（保留原路径） |
| 8× | 480 | 神经每 2 tick | 60 fps，独立线程 |
| 16× | 960 | 场每 2 tick，神经每 4 tick | 60 fps，独立线程 |
| 32× | 1920（受单 tick 成本限制，实际约 26–28×） | 场每 4 tick，神经每 8 tick | 30 fps，独立线程 |

- 单帧 tick 上限 12 改为"worker 每帧可提交的最大 tick 数"，仍保留防雪崩上限，但按倍速档动态计算。
- carry 语义保持：worker 落后目标时记欠账，HUD 提示。
- T11 需同步修订：断言档位元数据与 dt 不变，单帧上限改为按档位断言。

**注意**：1× / 3× 保留主线程同步路径，避免低倍速引入线程开销；独立线程只在 ≥8× 启用。

---

## 4. 收益上限定量

| 项 | 数值 | 来源 |
| --- | ---: | --- |
| 单 tick 成本（1024 细胞） | 0.58 ms | 阶段 A 实测 12 tick ≈ 6.9 ms |
| 单 worker 理论上限 | 1724 tick/s ≈ 28.7× | 1 / 0.00058 |
| 扣同步 / 快照 / 抖动（5–10%） | **26–27×** | 估算 |
| 32× 所需 | 1920 tick/s，≤0.52 ms/tick | 当前达不到 |
| 主线程改上限（不独立线程） | 32 tick × 0.58 = 18.6 ms > 16.7 ms 预算 → 掉帧 | 伪突破 |

结论：**32× 必须靠阶段 C 多核并行或阶段 D GPU 主体化降单 tick 成本**，阶段 B 只能到 26–27×。

---

## 5. 风险清单

- 死锁：worker 等 semaphore、主线程等 worker 完成快照，环形等待。
- 快照撕裂：渲染读到写一半的 PackedArray（须双缓冲交换引用 + Mutex）。
- COW 竞争：共享 PackedArray 引用写元素触发 COW，必须确认 worker 持有独占引用。
- RefCounted 跨线程 new/free：引用计数非原子，快照对象须预分配池、循环复用。
- hash 时序：hash/存档从帧对齐改 tick 对齐，parity probe 需重写。
- 命令时序：Agent / UI 命令入队与 worker 消费的 tick 对齐关系需明确。
- 散热红线：基准单次 ≤60 s，编译 -j 4，禁止长跑满载扫描。

---

## 6. 待用户拍板（阻塞项）

1. **路径选择**：A（保持 hash，复杂度最高）/ B（重建 hash，语义变化）/ C（折中）。
2. **32× 目标**：接受阶段 B 的 26–27× 上限，还是必须 32×（需连做阶段 C）。
3. **实施策略**：先做最小 Thread 原型验证（不改生产代码，证明 GDScript Thread + Mutex + 双缓冲可行），还是直接全量实施。

---

## 7. 原型验证结果（已完成，2026-11-27）

建只读原型 `tools/ThreadPrototype.gd/.tscn/.gd`（Snapshot 单元），1024 细胞 × 6000 tick，主线程每帧读快照并用 checksum 检测撕裂。四种同步方案实测：

| 方案 | checksum 失配 | 读快照 p50 | 读快照 p95 | 判定 |
| --- | ---: | ---: | ---: | --- |
| 双缓冲（Mutex 仅护索引） | 17/106 | 111 µs | 196 µs | **FAIL** |
| 三缓冲（Mutex 仅护索引） | 1/86 | 83 µs | 144 µs | **FAIL**（概率性） |
| 三缓冲 + 全量写锁 | 0/83 | 4960 µs | 11875 µs | OK 但不可接受（吃满帧预算） |
| **worker 本地缓冲 + 短临界区整块拷贝** | **0/108 × 4 轮** | **~95 µs** | **~290–620 µs** | **OK，采用** |

### 落地硬约束（原型给出）

1. **worker 必须在自己的 PackedArray 上算完，再在短锁内整块拷进快照槽**；绝不能让主线程读的缓冲被 worker 原地写——双缓冲 / 三缓冲仅靠 Mutex 护索引都会概率性撕裂（COW 竞争）。
2. 读写都进同一把 Mutex，但**临界区只含数组赋值，不含计算与 checksum**；这样读快照 p50 ~95 µs、p95 < 620 µs，帧预算可接受。
3. Godot 4 的 `Thread` 没有 `is_finished()`（原型的初版报 `Nonexistent function 'is_finished'`），退出用 `is_started()` + `wait_to_finish()`。
4. worker 6000 tick 0.72 s 是简单加法，不代表真实模拟吞吐；真实单 tick 0.58 ms 来自完整链，仍需按此估 26–27×。

### 后续落地顺序（路径 B，hash 重建）

1. 线程基础设施：本地缓冲 + 短临界区快照 + 三缓冲槽，按原型约束实现；
2. 机械移植 organism 侧计算到 worker（去 signal emit / Node.call，命令走无锁队列）；
3. field 路径：worker 用 CPU 场算权威态，主线程 GPU 场只做视觉；hash 以 worker CPU 场为准；
4. 重建黄金基线：同种子两次运行一致、native/CPU parity、回放一致三项必须保住；
5. 修订 §2.6 单帧上限与 T11，版本化发布。

## 8. B1 落地成果（2026-11-27，已完成）

### 8.1 新增文件
- `scripts/system/SimWorker.gd`：独立模拟线程基础设施（Thread + Mutex + 三缓冲快照 + 本地缓冲 + 短临界区拷贝 + 命令队列 + stop/wait）。
- `scripts/system/SimSnapshot.gd`：快照单元（pos_x/pos_y/alive/cell_type/checksum/tick）。
- `scripts/core/data/PreviewWorld.gd`：新增只读 `_manager()` 访问器（返回 Node，供 worker 消费命令）。
- 探针：`tools/WorkerSimProbe.gd/.tscn`、`tools/SimWorkerProbe.gd/.tscn`、`tools/ProdSimWorkerProbe.gd/.tscn`。
- SmokeTest manifest 74 → **79**，闸门 `SCRIPTS=79 FAILURES=0`、NativeParityProbe `OK (failures=0)`。

### 8.2 四项决定性验证（全部通过）
| 验证 | 内容 | 结果 |
| --- | --- | --- |
| 线程同步 | worker 本地算 + 短临界区拷贝 vs 双缓冲/全量锁 | 0/108 撕裂 ×4 轮（双缓冲 17/106 FAIL、全量锁 p95 12ms） |
| 小型隔离模拟 | PreviewWorld 2→96 细胞，worker vs 主线程 120 tick | hash `2088105189` 逐位一致 ×3 轮 |
| SimWorker 壳 | 封装后 worker tick 推进 + 快照 checksum + 命令队列 | 0 撕裂、0 非单调 ×3 轮 |
| **生产规模** | **512 细胞 + native FFI + CPU 场，worker vs 主线程 30 tick** | **hash `4033338755` 逐位一致 ×3 轮** |

### 8.3 关键工程约束（实测得出）
1. **native 对象必须在主线程预热**：`ClassDB.instantiate("CellSpatial"/"CellNeural")` 首次惰性创建在 worker 线程会碰 ObjectDB（非线程安全）；主线程 prewarm 2 tick 后 worker 只复用引用。
2. **CPU 场是 worker 化的前提**：`PreviewWorld` / 探针都用 `field.configure(..., prefer_compute=false)`；生产 GPU 场（RenderingDevice）不能跨线程。路径 B 的权威态必须是 CPU 场，GPU 场降级为视觉层——这正是 hash 基线要重建的原因。
3. 双缓冲 Mutex 只护索引会 COW 撕裂；全量写锁 p95 12ms 吃满帧预算；正解是本地缓冲 + 短临界区整块赋值。

---

## 9. B2/B3 待决策（冻结边界，阻塞）

B1 已清除全部可行性风险。但**把生产主场景正式切到 worker**需要同时做四件事，触及冻结边界：

1. 主 `OrganismManager` 从场景树摘出 / 改为 worker 内的隔离实例；
2. 所有渲染（CellBatchRenderer / CellariumView / FieldLayer）从直读生产 cells 改为读 SimSnapshot；
3. GPU 场降级为视觉层，权威态改 CPU 场 → **state hash 基线重建**；
4. `advance_field_tick` 的 source 写入（consume_nutrient / consume_signal / signal 分泌）从穿插 tick 中改为批次同步点 → **tick 时序改变**。

这些是 §2.6 冻结规格与 hash 基线的核心，属于用户已授权的路径 B 范围，但影响全-game 行为。建议作为**独立大版本**（v0.48.0）一次性落地并全链重建黄金基线，不在 v0.46 之上叠加。

**当时状态**：B1 基础设施已就位且验证通过；B2 生产切换待用户确认是否启动大版本重构。生产 tick 链、§2.6、hash 基线均未改动。

---

## 10. B3 生产接入结果（2026-11-27，已实施）

### 10.1 落地内容
- `scripts/system/WorkerSimEngine.gd`：生产级 worker 引擎。主线程用 `SaveManager.capture/restore` 建立同状态隔离世界（强制 CPU 场），native 对象在主线程直接 `_get_native_*` 预热；worker 连续跑完整 tick：`advance_physics_tick → advance_development_tick → apply_nutrient_sources → advance_food_entities → advance_field_tick`。
- `SimSnapshot.gd` 增加动态 `arrays`/`array_counts`，只承载渲染/诊断所需 SoA；明确跳过 `neural_weights`/`expression_weights`/`behavior_intents` 等 stride×N 大数组，避免 worker 被快照拷贝拖垮。
- `TickCore.worker_target_mode`：主线程发布 `target_tick`，一帧最多一次 `tick_advanced`；worker 进度由 `set_worker_progress()` 回报，`carry = target - progress`。旧主线程 12 tick/帧路径原样保留。
- `Main`：`threaded_simulation_enabled` 默认 false，`start_threaded_simulation()` 显式启用；`_process()` 每帧 `sync_main_state()` 并按帧推进 GPU 视觉场；命令仍走 CommandBus，worker 模式转发到 worker 命令队列。
- `HighSpeedPerfBenchmark --worker=1`：用 worker ticks 增量计算 effective，而不再数主线程 tick 信号。

### 10.2 关键 bug 与修复
1. `SaveManager.capture()` 直接引用 `field._pending_sources` 外层数组；restore 时 `apply_environment_settings → bind_preset → field.configure(32)` 会就地清空它，导致 64×64 场快照的源缓冲变成 32×32，`add_signal_sources_batch` 越界。已改为 `_copy_array(field.get("_pending_sources"))` 深拷，并在 worker 恢复后用 `repair_field_after_restore()` 兜底重建。
2. `OrganismStore` 没有 `size()`；快照个体数改为 `org_alive.size()`。
3. 首帧快照元数据与 PackedArray 长度短暂错开；`_copy_packed()` 按实际可读长度收敛，禁止越界读。

### 10.3 hash 基线
worker 权威态改 CPU 场，旧 GPU 场黄金值不再适用。新增 `tools/WorkerEngineProbe.tscn`：512 细胞、CPU 场 32、native 开启、完整 tick 链 30 tick。主线程顺序执行与 worker 均得 `4234109495`，快照首细胞坐标一致，`PROBE_VERDICT OK`。legacy 路径仍保持 m1_photo tick=700 `3284848376`。

### 10.4 真实窗口 A/B（2026-11-28 修正，OS 单调钟墙钟）
> **旧表作废**：下表原数据（8× 7.94→8.01、16× 11.92→16.10、32× 11.98→32.24）用 `_process(delta)` 累加墙钟，delta 被 vsync/max_fps 钳在 16.7ms，60 帧只累计 1.0s，而外部 Stopwatch 实测进程真实运行 32.2s。effective 虚高约 25–32×。「32× 连续 300 帧 32.02×」同为错误口径，一并作废。

改用 OS 单调钟（`Time.get_ticks_usec()`）为墙钟后的同会话真实 A/B（32× 档，60 帧）：

| 规模 | 旧路径 effective | worker effective | worker tick/s | 真实墙钟 |
| --- | ---: | ---: | ---: | ---: |
| 512 细胞 | 0.36×（720 tick/33.2s） | **1.21×**（1910 tick/26.3s） | 85.3 | 26.3s |
| 1024 细胞 | 0.86×（720 tick/13.9s） | 0.83×（170 tick/2.84s） | 59.9 | 2.84s |

worker 相对旧路径在 512 约有 3.4× 提升，1024 无提升。两条路径都远未达到 32×。

**权威单 tick 成本**（`get_worker_stage_averages()`，worker 世界 PerfProbe，单 tick 微秒）：

| 段 | 512 | 1024 | 倍数 |
| --- | ---: | ---: | ---: |
| total | 6242 | 12103 | 1.94× |
| metabolism | 3445 | 6384 | 1.85× |
| ├ metab_fields | 1326 | 2594 | 1.96× |
| ├ metab_env | 1161 | 2187 | 1.88× |
| physics | 1858 | 3980 | 2.14× |
| ├ phys_collision | 1619 | 3578 | 2.21× |
| behavior | 288 | 541 | 1.88× |
| signal | 512 | 948 | 1.85× |

### 10.5 未达标边界
阶段 B3 **未达成突破 12× 的目标**。修正墙钟后 512 仅 1.21×、1024 仅 0.83×。所有段随细胞数近线性 2×，无单一病理热点；单 worker 理论上限 161（512）/ 82（1024）tick/s 与实测 85/60 自洽。要支撑高倍速必须实质降低单 tick 成本：阶段 C 多核分片，或阶段 D GPU 主体化。worker 模式保持默认关闭，不得对外宣称已达 32×。
