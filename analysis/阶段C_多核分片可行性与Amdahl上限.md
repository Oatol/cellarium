# 阶段 C：多核分片可行性与 Amdahl 上限分析

> 编制于 2026-11-28。前置：`阶段B_独立模拟线程方案.md` §10「B3 的 32× 达标已证伪」。
> 本文只读分析 + 轻量原型，不改生产代码。目标：回答"多核分片能否支撑高倍速"。

## 1. 结论先行

**GDScript 层按细胞/个体分片无法支撑高倍速。** 真正可安全并行的部分（behavior 的 eval、base 代谢）合计占单 tick <11%，且 base 代谢**已经分片**、behavior 的高倍速路径已按 8 tick 降频。Amdahl 上限约 1.1×，远不足以把 512 的 6.2ms 单 tick 降到 32× 所需的 0.52ms。physics 碰撞与 link 代谢是顺序耦合的硬内核，必须保留单线程；它们是单 tick 大头，只有 C++ 内核内部并行或 GPU 主体化才动得了。

## 2. 各阶段分片边界（证据）

| 阶段 | 单 tick µs (512/1024) | 可分片？ | 依据 |
| --- | ---: | --- | --- |
| behavior / collect_inputs_grid | 718 / 312 | 否（内核全量） | `native/src/cell_spatial.cpp:210-263` 每次调用 `GridBuckets::build` 全量建网格 + 遍历全部 cell，无 first/last 参数 |
| behavior / evaluate_batch | 520 / 256 | **是** | `native/src/cell_neural.cpp:38-40` 支持 `first,last` 行区间；内核无实例状态、纯函数 |
| behavior / apply_cached_intents | 308 / 170 | 理论是 | `CellBehavior.gd:292-304` 每细胞只写自身，但 GDScript COW 写回需串行合并 |
| physics / step_verlet_and_links | 78 / 49 | 否 | `cell_spatial.cpp:377-403` link Gauss-Seidel 顺序遍历、逐条改写两端 |
| physics / resolve_collisions | 1619 / 3578 | 否 | `cell_spatial.cpp:309-345` 全局 pair 升序 + 6 轮迭代 + 每 3 轮重建 pair + 全局 `max_correction` 提前终止；分片破坏连锁分离 |
| metabolism / metab_fields | 1326 / 2594 | 部分 | GDScript 侧场采样准备（positions/indices 数组构建），O(n) 但含 Array[Vector2] COW |
| metabolism / metab_env | 1161 / 2187 | 否（内核单次批量） | `compute_environment_batch` 是 native 单次 FFI 调用，纯计算段已下沉，GDScript 层无分片空间 |
| metabolism / metab_base | 403 / 891 | **已是** | `OrganismManager.gd:630-640` 已用 `WorkerThreadPool.add_task` 按索引分片 |
| metabolism / metab_rates/links | ~200 / ~1000 | 否 | link 能量两遍 + 全局 outgoing 归约（`CellMetabolism.gd:32-63`） |
| signal | 512 / 948 | 部分 | 候选筛选可分片，但 `add_signal_sources_batch` 写共享环境须串行 |

## 3. native 内核线程安全（好消息但不够）

`CellSpatial` / `CellNeural` / `CellMetabolism` 均为 `RefCounted` 且**无实例成员变量**，方法纯函数（const & 入参 + 返回新数组），同一实例可被多线程同时调用（`native/src/cell_*.cpp`）。COW PackedArray 跨线程只读安全，写回发生在各自返回的新数组。**线程安全不是障碍，收益占比才是。**

## 4. 确定性 hash 约束

`get_state_hash()`（`OrganismManager.gd:1964-2001`）按 cell 索引升序、link 索引升序、org_id 升序遍历，FNV 变体。分片可行前提：按相同索引顺序写回 + 浮点累加顺序不变。`_energy_flow` / expression_weights / cell_color_* 等诊断缓冲不进 hash。link 代谢的 float 累加顺序若改变会破坏逐位一致。

## 5. Amdahl 上限估算（512 细胞，6.24ms 单 tick）

可并行部分（乐观，假设无限核、零同步开销）：
- evaluate_batch 520µs（但 32× 下 8 tick 才 1 次，摊薄到 65µs/tick）
- base 代谢 403µs（已分片，无新增收益）
- apply_cached_intents 308µs（摊薄到 38µs/tick）

不可并行部分：collision 1619 + metab_env 1161 + metab_fields 1326(大部分) + 其余 ≈ 5.3ms。

即使把可并行的 ~0.5ms 全部完美并行到 8 核：6.24 → ~5.8ms，**加速比 ~1.08×**。这与"32× 需 0.52ms"差一个数量级。

## 6. 建议

1. **不要在 GDScript 层做多核分片**——收益 <10%，且增加同步/确定性风险，不值得。
2. 真要降单 tick，只有两条实质路线：
   - **C++ 内核内部并行**：collision 的 pair 求解（需突破 Gauss-Seidel 顺序依赖，可能要用 Jacobi + 不改 hash 的收敛策略，风险极高）；metab_env 的 `compute_environment_batch` 内部按 cell 分片（纯计算、无顺序依赖，相对可行）。
   - **阶段 D GPU 主体化**：把 behavior/physics/metabolism 主体搬 GPU compute，符合最初"GPU 算力被浪费"的判断，但要保住逐位确定性，需重建 hash 基线。
3. 若目标只是"1024 细胞稳定运行不卡"（Cell Lab 那种 3000 细胞流畅），当前优化后的单线程路径已够（headless 下 60 TPS 量级）；若目标是"32× 高倍速"，则必须走 GPU 主体化。

## 7. 原型实测结果（2026-11-28）

`tools/ShardProbe.gd`：1024 细胞、`evaluate_batch` 分片 1/2/4/8，200 次重复，OS 单调钟墙钟：

| 分片数 | µs/call | 加速比 | 逐位一致 |
| ---: | ---: | ---: | --- |
| 1 | 422.5 | 1.00× | 基准 |
| 2 | 1086.5 | **0.39×** | true |
| 4 | 995.1 | **0.42×** | true |
| 8 | 1196.5 | **0.35×** | true |

**结论：分片后反而慢 2.4–2.9×。** 逐位一致（`bitwise_match=true`）证明分片在确定性上可行，但性能上是负收益。根因：`evaluate_batch`（`native/src/cell_neural.cpp:43-46`）每次调用都 `resize + 清零整个 count×6 输出数组`，分片 N 次就分配清零 N 份完整数组，加上 WorkerThreadPool 派发开销，远超神经推理本身（422µs）。要真正获益必须改 C++ 内核——增加"只写本人切片、不清零全数组"的分片入口，那已进入阶段 C++ 内核并行改造，且仍在 Amdahl 上限（占比 <11%）约束内。

**最终判断：GDScript 层多核分片路线不可行（负收益）。** 这与 §5 的 Amdahl 估算一致。要降单 tick 支撑高倍速，只能：① 改 C++ 内核内部并行（collision / compute_environment_batch），风险高、收益受 Amdahl 限；② 阶段 D GPU 主体化（最贴合"GPU 算力被浪费"的原始判断，但需重建 hash 基线）。建议用户在此二者间决策，或接受当前单线程路径作为稳定态。
