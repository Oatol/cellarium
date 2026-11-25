# 变更记录

版本号规则见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §11.1。文档版本与工程版本在本文件中关联。

---

## 0.40.0 — 2026-11-25

**类型**：tick CPU / 渲染解耦专项——真实窗口固定 1025 细胞分段定位 + 三角展开下沉。**结论：v0.39 合批虽把 draw call 降 88–94%，但 GDScript 逐顶点三角展开让批渲染缓存重建从约 1 ms 退化到 32.8 ms，抵消了收益；下沉 C++ 后 cache 降到 8.7 ms。tick 主瓶颈是 `metabolism` 8.6 ms（其中 `metab_env` 5.27 ms 的副作用循环仍在 GDScript），其次 physics 3.85 ms、dev 2.9 ms。≤8 ms/tick 目标仍未达成。**

### 诊断

- 新增 `tools/WindowPerfBenchmark.tscn` / `.gd`：实例化真实 `main.tscn`，用 M1 光合自分裂 × 无限分裂 × 黏附基因组铺 1025 细胞，冻结主 tick，手动按固定 budget 跑 5 个相位（tick1 / tick3 / cache / tick1_cache / tick3_cache）各 120 帧，输出 avg/p50/p95 到 `user://window_perf_bench.txt`。不使用编辑器 debugger / game_eval 参与测量，避免 Time 采样被调试暂停污染。
- 新增 tick 内部六段细分（cmd/physics/dev/nutrient/food/field），并通过 `PerfProbe.diagnostic_averages()` 暴露 metab_* 子阶段（只读，不进 STAGES 汇总与 state hash）。
- 真实窗口 1025 细胞最终读数：`tick1` 22.9 ms、`tick3` 65.1 ms、`cache` 8.7 ms；tick 内部 `advance_physics_tick` 17.7 ms + `advance_development_tick` 2.9 ms + `advance_field_tick` 0.92 ms；PerfProbe `behavior` 1.52 / `physics` 3.85 / `metabolism` 8.60 / `predation` 0.19 / `signal` 0.93 ms（total 15.09 ms）。
- `metabolism` 内部：`metab_env` 5.27 ms（环境代谢）、`metab_fields` 2.30 ms（场采样）、`metab_base` 0.77 ms，其余均 <0.11 ms。

### 实现

- `native/src/cell_render_cache.cpp`：`CellRenderCache.rebuild()` 顺带完成三角展开，新增 batch_vertices / batch_colors / batch_indices 三个输出；`append_triangle` / `append_segment` / `unit_circle` 辅助函数与 GDScript 兜底路径逐点同构。
- `CellPolygonBatchRenderer.gd`：native 路径直接取用 C++ 三角数组，跳过 GDScript `_build_batched_commands()`；DLL 缺失时仍回退 GDScript 展开。cache 重建 32.8 → 8.7 ms。
- 新 DLL SHA-256：`1770853EA1D5A880BE0471636F772F18B0DAA62A37EB4C0BDA573D19BE82E438`。

### 闸门

- `SmokeTest: SCRIPTS=69 FAILURES=0`。
- `RenderCacheParityProbe checked=266844 failures=0`（新增 batch 三角数组逐点对照，含顶点/颜色/索引）。
- 本轮改的是视图三角展开（不进 state hash 的只读派生数据）与诊断工具；`NativeParityProbe` state hash 逻辑未触及。DLL 升级仅为渲染缓存输出扩展，模拟路径二进制未变。

### 下一步（未在本版实施）

- `metab_env` 5.27 ms：`compute_environment_batch()` 纯计算已在 C++，但副作用循环（`consume_nutrient` / `consume_signal` / `energy_ledger.record` / `_energy_flow_add`）仍在 GDScript 逐细胞执行，是最大可下沉目标；涉及跨模块副作用顺序，需单独专项并保证 state hash 逐位一致。
- `metab_fields` 2.30 ms：环境场采样批量回读开销。
- 三级倍速下主循环每帧要跑多个 tick，tick CPU 是体验卡顿真凶；渲染解耦（模拟线程 / tick 分片）应围绕上述热点展开。

---

## 0.39.0 — 2026-11-22

**类型**：C 路线真实窗口诊断 + 绘制调用合批。**结论：GPU 合成/后处理不是用户卡顿主因；1324 细胞同场景 A/B 中 draw call 从 4231 降到 259，但运行态 3× FPS/帧时间基本不变（约 59 fps / 17 ms），瓶颈仍是 tick CPU。后处理开关只影响 1 个 draw call。**

### 诊断

- 新增帧时间 HUD（`scripts/system/FrameProfiler.gd` + `Main.gd` / `CellPolygonBatchRenderer.gd` / `CellSceneRenderer.gd` 埋点 + `GameHUD.gd` 上屏），显示帧间隔、引擎 `TIME_PROCESS`、draw call、细胞数。
- 自写 `Time.get_ticks_usec()` 分段在 GUI/调试器下与 TPS 不自洽（例如 92 tick/0.5 s 却报每 tick 27–64 ms），不作为结论依据；最终 HUD 只保留可交叉验证口径。
- 新增真实窗口诊断场景 `tools/WindowPerfScenario.tscn` / `.gd`：实例化 `main.tscn`，用 M1 光合自分裂 × 无限分裂 × 黏附基因组铺到 1324 细胞后冻结，便于同场景 A/B。所有注入走正常 `register_zygote`。
- 真实窗口基线（1324 细胞冻结）：FPS 144、frame 6.9 ms、CPU 7.9–8.3 ms/frame、draw 4231。关闭 `Postprocess` 只减 1 draw call，关闭 `LinkLayer` 只减 2；逐层开关定位到 `CellBatchPoly` 一层占 3972 draw calls。

### 实现

- `CellPolygonBatchRenderer.gd`：把每个细胞的体色三角扇、核三角、膜轮廓细四边形、共享弦连接细四边形全部展平为三角数组，用 `RenderingServer.canvas_item_add_triangle_array()` 一次提交；保留逐细胞 `draw_*` 旧路径兜底，并加 `use_triangle_batch` A/B 开关。
- `LinkLayer.gd`：连接光桥与黄色能量流光点同样展平为三角数组，一次提交；视觉与相位逻辑不变。
- `FrameProfiler.gd` / `GameHUD.gd`：统一显示为每帧平均口径；HUD 高度恢复两行。

### 验收

- 同场景同会话 A/B（1324 细胞冻结）：`use_triangle_batch=false` → draw 4231；`true` → draw 259；再切回 `false` 仍 4231、`true` 仍 259。CPU 8.24 → 7.93 ms/frame。
- 运行态 3× 1324 细胞：合批 on draw 547 / 17.0 ms / 59 fps；off draw 4519 / 17.1 ms / 59 fps。**draw call 大幅下降，但 FPS/帧时间未改善**，如实记录，不把该改动表述为解决卡顿。
- `SmokeTest: SCRIPTS=68 FAILURES=0`；`RenderCacheParityProbe checked=10353 failures=0`；`CellBatchOriginParityProbe checked=24 failures=0`。纯视图改动，state hash 不进渲染数据。
- DLL 未改，SHA 保持 `36DFEA19BEBB0FA72C5665A672E6EE1F15836C60506E11F609830EFA5AB53D19`。

### 后续

C 路线数据否定「GPU 合成/后处理是瓶颈」假设。下一步应回到 tick CPU / 渲染解耦专项，先定位运行态 3× 下 tick 与批渲染缓存的真实主线程占比，再决定是否继续下沉或拆分线程。

---

## 0.38.0 — 2026-11-22

**类型**：渲染缺陷修复（皿外方点 / 细胞重影）。**定位到 `CellBatchRenderer` 用 `Transform2D(0,pos).scaled()` 把细胞 origin 乘了 2 倍，皿内 (250,250) 的细胞被画到 (500,500) 的皿外大圆；且大规模时 CellBatch 与 CellBatchPoly 同时可见导致重复绘制。纯视图层修复，不进 state hash。**

### 根因与发现

- 用户截图反馈：512 细胞分裂到 1024 时，皿外出现大片青绿方形小点，形状是一个更大的圆，与皿内细胞位置成映射关系；刷新后仍在。
- 关键线索：只在细胞数 > 512（近景 → 批渲染 LOD 切换阈值）时出现。
- 根因 1（决定性）：`CellBatchRenderer._rebuild()` 第 81–82 行 `Transform2D(0.0, position).scaled(Vector2(cell_radius, cell_radius))` —— Godot 的 `Transform2D.scaled()` 会连 origin 一起缩放，`cell_radius=2.0` 时把 origin (250,250) 放大成 (500,500)。`tools/TransformScaledCheck` 实测确证。皿内细胞被整体放大 2 倍画到皿外，正是那片方点大圆。
- 根因 2：`CellSceneRenderer._rebuild()` 在 `indices.size() > max_instances` 时同时设 `batch_renderer.visible=true` 与 `polygon_batch.visible=true`；两批细胞绘制叠加、多一倍 draw call。`tools/RenderLayerStateProbe` 实测确认切换后两者皆 true。

### 实现

- `CellBatchRenderer.gd`：改为先缩放基向量再写回 origin（`Transform2D(0, ZERO).scaled(...)` 然后 `transform.origin = position`），细胞实例绘制在真实位置。
- `CellSceneRenderer.gd`：大规模分支关闭 `batch_renderer`、只保留 `polygon_batch`（v0.30 起多边形层已完整取代 MultiMesh 色块 LOD），消除重复绘制。

### 验证

- 新增 `tools/CellBatchOriginParityProbe.gd`：24 组位置/半径验证修正写法 origin 恒等于细胞位置（`failures=0`），登记入 SmokeTest manifest。
- 双工程 `SmokeTest: SCRIPTS=66 FAILURES=0`；`NativeParityProbe` legacy 240 tick hash 1356695503 逐位一致（纯视图改动无 hash 影响）。
- 本轮无 C++ 改动，DLL SHA 保持 v0.36 的 `36DFEA19BEBB0FA72C5665A672E6EE1F15836C60506E11F609830EFA5AB53D19`。

### 说明

- 皿外方点是坐标 bug，不是能量转移可视化、也不是细胞真的跑出培养皿（探针验证所有活细胞 bbox 均在皿内）。

---

## 0.37.0 — 2026-11-21

**类型**：真实体验验证 + 修复「原生优化从未启用」。**发现 `native_spatial_enabled` 默认 false 且 Main.gd/场景均未开启，导致 v0.31–v0.36 的 C++ 优化在真实运行中一直是关闭的（复现 512 个体约 6 TPS）。改为默认 true 后，同机真实帧成本 1024 细胞约 54–62 TPS（纯 GDScript 仅 6 TPS）。**

### 根因与发现

- 新增 `tools/RealWorldTpsProbe.gd`：模拟真实 1 倍速单帧（完整 tick 链 + 批渲染缓存重建），量化可达 TPS。
- 实测（headless，CPU 侧下界，未含真实 GPU 合成）：
  - native=false：512→1024 细胞帧成本 161ms，约 **6.2 TPS**（与用户截图 TPS 6 完全吻合）。
  - native=true：1024 细胞帧成本 16–19ms，约 **54–62 TPS**。
- `native_spatial_enabled` 默认 false，Main.gd 与 main.tscn/sandbox.tscn 均未设置 → 真实运行一直走纯 GDScript 回退路径，六个版本的原生优化从未生效。
- 批渲染缓存 `_get_native_render_cache()` 无开关、直接 `ClassDB.class_exists`，故 v0.35 的拖拽提速本就默认生效；漏开的只有 OrganismManager 的原生模拟开关。

### 实现

- `scripts/system/OrganismManager.gd`：`native_spatial_enabled` 默认 `false` → `true`；注释更新说明 DLL 缺失自动回退、置 false 可强制 CPU 路径做 A/B。
- `tools/SmokeTest.gd`：`_check_multicellular_cooperation()` 绕过正常 API 直接替换 `genomes[0]`，注入后须显式调用 `_invalidate_native_metabolism_cache()`（正常 register/inject/mutate 路径内部已自动失效）。native 默认开启后，缺失此步会用旧模式缓存导致子代类型错乱。

### 验证

- 双工程 `SmokeTest: SCRIPTS=65 FAILURES=0`。
- 五类 parity（CollectInputsGrid / BehaviorSignal / RenderCache / Metabolism / Physics）全 OK。
- `NativeParityProbe` 双工程 OK：legacy 240 tick hash 1356695503 逐位一致，M1 700 tick 检查点全等。
- 默认值切换前后 state hash 无漂移；native 与 GDScript 路径逐位等价。

### 说明

- 本轮无 C++ 改动，DLL SHA 保持 v0.36 的 `36DFEA19BEBB0FA72C5665A672E6EE1F15836C60506E11F609830EFA5AB53D19`。
- headless 帧成本是 CPU 下界；真实 GUI 的 GPU 合成/后处理开销仍需窗口实测，1024 细胞「1 倍速满速」暂不打包票。≤8ms/tick（裸 tick）口径仍未达标。

---

## 0.36.0 — 2026-11-20

**类型**：A 路线继续下沉（邻域输入收集融合，消除每 tick CSR 物化）。**behavior 从 5.57→1.27ms（4.4×），M1 场景全 tick 15.4→11.2ms，固定 3000 细胞 26.3→20.1ms。≤8ms/tick 仍未达标，如实记录。**

### 实现

- 新增 C++ `CellSpatial.collect_inputs_grid()`：一次建网格后逐细胞直接统计同类/异类邻居并组装 8 通道输入，跳过旧的 `build_neighbor_csr`（每 tick 对全细胞建 vector + sort + `PackedInt32Array.append`，实测 1490 细胞时单项 8.58ms）物化步骤。
- `OrganismManager.advance_physics_tick()` 的 native 分支优先走融合路径，DLL 缺失/类未注册回退旧 `build_neighbor_csr + collect_inputs_batch`；`_build_behavior_environment()` 保留作为回退与诊断路径。
- 逐位安全：邻居同/异类统计是整数累加，与遍历顺序无关，故融合路径无需 sort 即可与旧 CSR 逐位一致；场通道/能量通道完全照抄旧逻辑。硬编码 `cell_size=64`、`energy_max=1.0` 与旧 `_build_behavior_environment()` 返回值一致。
- 新增 `tools/CollectInputsGridParityProbe.gd`（41112 项 8 通道逐位对照）、`tools/BehaviorStageProbe.gd` / `tools/BehaviorPhysicsBreakdownProbe.gd`（一次性热点诊断，不登记 manifest）。脚本清单 64→65。

### 验证（程序化无头，双工程）

- `CollectInputsGridParityProbe` 41112 项 `failures=0`；`BehaviorSignalParityProbe` 4808、`RenderCacheParityProbe` 10353、`MetabolismHotspotsParityProbe` 1905、`PhysicsStepParityProbe` 2000 项全过。
- 双工程 `NativeParityProbe`：legacy 240 tick 检查点仍为 1356695503；M1 700 tick tick 2/302/602 细胞 8→16→32→64，GD/CPP hash 逐位一致，`failures=0`。
- 双工程 `SmokeTest: SCRIPTS=65 FAILURES=0`。

### 实测与诚实结论

| 口径 | v0.35 | v0.36 |
| --- | --- | --- |
| M1 全 tick（1024 细胞） | 15.4 ms | **11.2 ms** |
| M1 stage behavior | 5.57 ms | **1.27 ms** |
| 固定 3000 细胞全 tick | 26.3 ms | **20.1 ms** |
| 固定 1000 细胞全 tick | 9.0 ms | **7.2 ms** |

剩余大头转为 metabolism（M1 5.3ms / 3000 档 10ms，主体已 C++ 化，`metab_env` 后处理循环含 ledger/consume/死亡副作用需保序）、physics（约 3.9ms，Verlet/link/碰撞已 C++ 化）、场 tick（约 1.3ms）。**3000 档 `budget_met=false`，未达 ≤8ms/tick，不表述达标**。DLL SHA-256：`36DFEA19BEBB0FA72C5665A672E6EE1F15836C60506E11F609830EFA5AB53D19`。

---

## 0.35.0 — 2026-11-20

**类型**：A 路线继续下沉（行为输出批量复制 + 信号源批处理 + 批渲染缓存原生化）+ 拖拽视野卡顿根因定位。**M1 场景 native 全 tick 15.4ms（behavior 5.57 / physics 3.81 / metabolism 5.30 / signal 0.64）；批渲染缓存重建 43.4→1.03ms（约 42×）。≤8ms/tick 仍未达标，如实记录。**

### 拖拽视野卡顿根因（程序化探针定位）

- 新增 `tools/ViewDragCostProbe.gd`：独立量化 pan、批渲染缓存重建、tick、组合帧四条路径。
- 结论：`CameraController.pan_screen()` 每次约 **1 微秒**，且 `view_changed` 无监听者，**相机平移本身不是瓶颈**。真正随细胞数放大的是每 tick 后 `CellPolygonBatchRenderer._rebuild_cache()`：1024 细胞时每次 **43.4ms**，与 native 开关无关（纯 GDScript 视图计算）。它与主线程 tick 叠加，直接造成拖拽掉帧、细胞多时更明显。`view_changed` 无监听、`PostprocessLayer` 为不随相机变换的 UI 层固定成本，均非拖拽特有主因。
- 修复：把 `_rebuild_cache()` 整体下沉 C++，重建耗时 43.4→1.03ms；GDScript 保留回退。

### 实现

- 新增 C++ `CellRenderCache.rebuild()`（纯视图数据，不进 state hash，float32 精度即可）：复现空间哈希、共享弦求交、Sutherland-Hodgman 半平面裁剪、单位圆与逐细胞配色；`CellPolygonBatchRenderer` 优先走 native，缺失/未注册回退原 GDScript。缓存实例避免每帧 `ClassDB.instantiate()`。
- 新增 C++ `CellNeural.copy_outputs_to_intents()`：**只批量写回 6 个行为输出**，位移继续由 GDScript `apply_cached_intents()` 执行。完整下沉 `apply_outputs_flat()` 被逐位探针否决——`Vector2.rotated()` 的引擎内三角与 godot-cpp `std::cos` 在极少数角度差 1 ULP，会破坏 state hash。冻结边界下不悄悄改 hash。
- 新增 C++ `CellNeural.collect_signal_sources()`：批量筛出非零信号分泌源，返回升序 cell index 与 double amount；环境 `add_signal_source` 副作用仍在 GDScript 按原顺序执行。
- 新增 `tools/BehaviorSignalParityProbe.gd`（4808 项）、`tools/RenderCacheParityProbe.gd`（10353 项）、`tools/ViewDragCostProbe.gd`，并登记 manifest（脚本 62→64）。
- 冻结边界全部不动：GNP1、tick 阶段顺序、1/60 步长、单帧 12 tick 上限、CommandBus、五通道场 schema、存档 schema v8、状态 hash 算法。

### 验证（程序化无头，双工程）

- `BehaviorSignalParityProbe` 4808 项、`RenderCacheParityProbe` 10353 项、`MetabolismHotspotsParityProbe` 1905 项、`PhysicsStepParityProbe` 2000 项逐位/容差对照全部 `failures=0`。
- `NativeParityProbe` legacy 240 tick 检查点仍为 1356695503；M1 700 tick tick 2/302/602 细胞 8→16→32→64，GD/CPP hash 逐位一致，`failures=0`。
- 双工程 `SmokeTest: SCRIPTS=64 FAILURES=0`。

### 实测与诚实结论

| 口径（512 个体→1024 细胞，40 tick） | GD | native |
| --- | --- | --- |
| 全 tick | 141.5 ms | **16.3 ms** |
| stage behavior | 21.0 ms | 5.57 ms |
| stage physics | 39.3 ms | 3.81 ms |
| stage metabolism | 78.6 ms | 5.30 ms |
| stage signal | 1.56 ms | 0.64 ms |

拖拽路径 A/B（1024 细胞）：`pan_screen` GD 0.99µs / native 0.98µs；`rebuild_cache` GD 43.4ms → **native 1.03ms**；组合帧 250ms → 19.9ms。固定细胞数 `BenchTest`：300 档 2.7ms、1000 档 9.0ms、3000 档 **26.3ms**（`budget_met=false`）。剩余大头为 behavior 约 5.5ms（位移循环受 Vector2 逐位约束未下沉）、physics 约 3.8ms、metabolism 约 5.3ms、场 tick 1.3ms；**均未达 ≤8ms/tick，不表述达标**。DLL SHA-256：`5F22B56BE53A72FF673FD7A0449283A7A508CDF0D821FD364E1D072ACEDD2082`。

---

## 0.34.0 — 2026-11-20

**类型**：A 路线继续下沉（M1 自分裂场景诊断 + 代谢剩余热点 + Verlet/连接约束）。**1024 细胞同会话 A/B 全 tick 126.1→15.8ms（后续复跑 143.7→18.7ms），8ms 目标仍未达标**，如实记录。

### 默认测试口径变更

- 按用户要求，测试与默认演示改为 **M1 光合自分裂、保黏附、无分裂次数限制**：`Genome.default_mode()` / `Genome.solo_photo_modes()`，`Main.gd`、`DevEditorPanel` 新建草案与新增模式同步。
- 旧存档/旧 5 模式 demo genome 不受影响；SmokeTest 中多细胞协作断言显式构造旧 demo genome 保持回归覆盖。

### 实现

- 新增 C++ `CellMetabolism.compute_transfer_rates()` / `compute_energy_radius_scales()` / `select_lifecycle_candidates()`：把逐细胞 transfer_rate 构建、能量-半径低通、生命周期候选筛选下沉。genome 派生值改为每 tick 按个体缓存一次，基因组写入/替换时显式失效。
- 新增 C++ `CellSpatial.step_verlet_and_links()`：下沉 `CellPhysics.step()` 与 2 轮 `_solve_links()`；Verlet/约束中间值保持 double，写回 `PackedFloat32Array`。
- 副作用边界不动：分裂动作、连接重分配、死亡、账本、场消耗、环境写入仍在 GDScript 原顺序执行；DLL 缺失或类未注册逐段回退。
- 新增 `tools/MetabolismHotspotsParityProbe.gd`、`tools/PhysicsStepParityProbe.gd`、`tools/DenseClusterProbe.gd` 并登记 manifest（脚本 59→62）。
- 冻结边界全部不动：GNP1、tick 阶段顺序、1/60 步长、单帧 12 tick 上限、CommandBus 单写者、五通道场 schema、存档 schema v8、状态 hash 算法。

### 验证（程序化无头，双工程）

- `MetabolismHotspotsParityProbe`：1905 项逐位对照 `failures=0`；`PhysicsStepParityProbe`：2000 项逐位对照 `failures=0`。
- `NativeParityProbe` 扩展为 legacy + M1 自分裂两场景：legacy 240 tick 5 检查点 hash 仍为 1356695503；M1 场景 700 tick，tick 2/302/602 实际细胞数 8→16→32→64，GD/CPP hash 与细胞数全部逐位一致。
- `SmokeTest: SCRIPTS=62 FAILURES=0`。

### 实测与诚实结论

| 口径（512 个体→1024 细胞，40 tick） | 全 tick GD→CPP | metabolism GD→CPP |
| --- | --- | --- |
| v0.34 下沉前 | 126.1 → 77.6 ms | 69.9 → 66.0 ms |
| 代谢热点下沉后 | 125.5 → **15.8 ms** | 69.7 → **4.9 ms** |
| 物理下沉后复跑 | 143.7 → **18.7 ms** | 81.2 → 5.9 ms |

`metab_rates` 14.5→0.04ms、`metab_radius` 14.4→0.08ms、`metab_lifecycle` 33.6→0.08ms；behavior/physics 已原生化，剩余大头转为 behavior 5–7ms、physics 4ms、signal 1–2ms、场 tick 1–2ms。**仍未达到 ≤8ms/tick，不表述达标**。固定细胞数 `BenchTest` 同会话 A/B：300 档 15.5→3.0ms、1000 档 59.1→9.7ms（`budget_met=true`）、3000 档 240.9→**27.9ms**（metabolism 64.7→9.7ms，`budget_met=false`）。DLL SHA-256：`86449DB2A3A65E9AC73F7B8BA08D7D83FC9434ECBF2C9ACCBC3DD8953240A9BF`。

---

## 0.33.0 — 2026-11-19

**类型**：A 路线继续下沉（环境代谢计算）+ C++ 源码与 DLL 入库（用户决策：可回溯）。**3000 细胞全 tick 230.2→43.9ms（5.25×），8ms 目标仍未达标**，如实记录。

### 入库决策变更（撤销 v0.31 约定）

- 用户明确：「C++ 源码与 DLL 应该入库啊，不然以后修改后怎么回溯版本」。撤销 v0.31/v0.32「二进制不入库」约定。
- 新增 `native/`：`src/`（C++ 源码）、`project/`（逐位探针与微基准）、`SConstruct` / `methods.py`、`README.md`（构建步骤、工具链锚点、逐位闸门、确定性铁律）。
- 入库运行产物：`godot/cellarium-release/bin/cellarium_native.gdextension` 与 `bin/windows/cellarium_native.windows.template_debug.x86_64.dll`。`.gitignore` 改为只排除编译中间产物（`*.obj` / `*.exp` / `*.lib` / `.sconsign.dblite`）与本地 `native/godot-cpp/`，DLL 与配置走白名单放行。
- 第三方 godot-cpp 源码与 6.9 MB `extension_api.json` 仍不入库；`native/README.md` 记录 master commit `24b9df7a88d40bcaf1f157703d4220185cb71fbf`、API JSON SHA-256 与导出命令，保证可复现。

### 实现

- 新增 C++ `CellMetabolism.compute_environment_batch()`：把环境代谢的纯计算段（呼吸规则、三类摄食增益、运动能耗、毒性标志）整段下沉。中间值用 `PackedFloat64Array` 返回，避免多一次 float32 舍入破坏 state hash；副作用（场消耗、`energy_ledger.record`、毒性伤害、死亡判定）仍在 GDScript 按原顺序执行。
- `OrganismManager` 新增 `_get_native_metabolism()` 与 `_apply_environment_metabolism_ranges()` 的 native 分支，DLL 缺失/类未注册回退原 GDScript 循环。
- 新增 `tools/MetabolismBreakdownProbe.gd`（把 metabolism 细分为 7 个子阶段，仅埋点不写状态），登记 manifest（脚本 58→59）。
- 冻结边界全部不动：GNP1、tick 阶段顺序、1/60 步长、单帧 12 tick 上限、CommandBus、五通道场 schema、存档 schema v8、状态 hash 算法。

### 验证（程序化无头，双工程）

- `metabolism_parity_probe.gd`：1354 个活细胞逐位对照，`food_gain` / `movement_cost`（double）/`toxic` 全等，`max_abs_diff=0`；`neural_parity` / `spatial_parity` 回归全过。
- 双工程 `NativeParityProbe` 240 tick / 5 检查点 `get_state_hash()` 逐位一致，tick=240 同为 **1356695503**（与 v0.31 / v0.32 逐位相同）。
- 双工程 `SmokeTest: SCRIPTS=59 FAILURES=0`；`PreviewReplica` / `DivisionAlignment` / `BatchRender` / `NativeParity` 四探针全 `FAILURES=0`。

### 实测与诚实结论

| 档位 | 全 tick gd→cpp | metabolism gd→cpp | budget |
| --- | --- | --- | --- |
| 300 | 11.8 → 3.9 ms | 2.8 → 2.1 ms | true |
| 1000 | 40.8 → 13.9 ms | 9.7 → 7.7 ms | **true** |
| 3000 | 230.2 → **43.9 ms** | 61.7 → 23.4 ms | false |

- 3000 细胞代谢子阶段（native）：`metab_lifecycle` 7.15ms（34.9%）、`metab_env` 5.60ms（27.4%，下沉前 20.4ms / 47.1%）、`metab_fields` 2.30ms、`metab_rates` 2.03ms、`metab_radius` 1.88ms、`metab_base` 1.36ms。
- **未达标**：43.9ms 仍远高于 8ms 目标，`cpu_budget_met=false`（3000 档）。1000 档首次达到预算。新瓶颈为 `metab_lifecycle`（生命周期/分裂判定，7.15ms）与 behavior 9.9ms。不把该数字表述为达标。

---

## 0.32.0 — 2026-11-19

**类型**：物理性能专项第三阶段 — behavior 热路径原生下沉（邻域 CSR / 输入收集 / 神经推理）。**3000 细胞全 tick 232.0→68.6ms（3.38×），8ms 目标仍未达标**，如实记录。

### 实现

- `OrganismManager.gd` 在 v0.31 的 `native_spatial_enabled` 开关上扩展：新增 `_get_native_neural()`（`ClassDB.class_exists("CellNeural")` 检查），DLL 缺失/类未注册自动回退 GDScript。
- `_build_behavior_environment()`：native 开启时用 `CellSpatial.build_neighbor_csr()` 直接产出 (offsets, values) CSR；尺寸不符或类缺失回退 `CellPhysics.build_spatial_hash_flat/query_neighbors_flat`。固定桶 + 9 格偏移 + 排序，遍历顺序与 GDScript 逐位一致，不加 Cell Lab 203 截断。
- `advance_physics_tick()` 的 neural 分支：用 `CellSpatial.collect_inputs_batch()` + `CellNeural.evaluate_batch()` 替换 `CellBehavior.compute_outputs_flat()`；`apply_outputs_flat()` 与运动意图落地仍走 GDScript。死细胞 `sample_indices=-1`、批次输出置零，语义与旧路径一致。
- C++ 源码/DLL 未改（三段原型 v0.31 已编译进同一 DLL），仅修改发布工程 `OrganismManager.gd` 一个脚本并同步 D 盘工程。
- 冻结边界全部不动：GNP1、tick 阶段顺序、1/60 固定步长、单帧 12 tick 上限、CommandBus 单写者、五通道场 schema、存档 schema v8、状态 hash 算法。

### 验证（程序化无头，双工程）

- 微基准复跑（D 盘工具区，N=3000）：邻域 CSR 2.30×（107.5→46.7ms）、碰撞 9.67×（857.4→88.7ms）、collect_inputs 12.63×（349.0→27.6ms）；神经纯推理 10.70×（9.11→0.85ms）。
- 端到端 `NativeParityProbe.gd`：双工程 40 密集合子、240 tick、5 检查点 `get_state_hash()` 全部逐位一致，tick=240 同为 1356695503（与 v0.31 逐位相同）。
- 双工程 `SmokeTest: SCRIPTS=58 FAILURES=0`；`PreviewReplica` / `DivisionAlignment` / `BatchRender` / `NativeParity` 四探针 `FAILURES=0`。

### 实测与诚实结论

- 同会话 A/B 基准（`CELLARIUM_NATIVE` 0/1）：

| 档位 | 全 tick gd→cpp | behavior | physics | metabolism |
| --- | --- | --- | --- | --- |
| 300 | 12.2 → 4.8 ms（budget true） | 3.9 → 0.9 ms | 4.9 → 0.5 ms | 2.9 → 2.9 ms |
| 1000 | 41.3 → 15.7 ms | 12.8 → 2.9 ms | 17.2 → 1.5 ms | 9.7 → 9.7 ms |
| 3000 | 232.0 → **68.6 ms** | 68.1 → 11.8 ms | 91.8 → 6.2 ms | 61.3 → 43.0 ms |

- GDScript 3000 档仅执行 63 tick（BenchTest 15 秒墙钟硬上限保护），Native 档跑满 120 tick；`avg_tick_us` 为单 tick 均值，口径一致。
- **未达标**：68.6ms 仍远高于 8ms 目标，`cpu_budget_met=false`（3000 档）。behavior 已从最大项降为次要项；**metabolism 43.0ms 成新瓶颈**，其下一次是 signal 7.2ms。不把该数字表述为达标，下一专项按用户「根据结果再考虑」决定。

---

## 0.31.0 — 2026-11-19

**类型**：物理性能专项第二阶段 — GDExtension/C++ 碰撞下沉（Cell Lab 固定桶同构，目标 3000 细胞流畅）
**触发**：用户专项「学 Cell Lab 用固定桶数组 + DLL 接入发布工程跑端到端验证」。**碰撞阶段 9.4×、全 tick 1.5×，8ms 目标仍未达标**，如实记录。

### 工具链（无 godot-cpp 4.7 tag 的破解）

- Godot `4.7.2.stable.official.ed1daf0bf` 用 `godot --headless --dump-extension-api` 自导出 `extension_api.json`（6.9MB）；godot-cpp master 用 `scons custom_api_file=extension_api.json` + `api_version=4.7` 生成绑定，不依赖官方 tag。MSVC14.44 + SCons 自动探测编译 DLL。`.gdextension` 精简为单 `windows.x86_64`，避免 20+ 平台路径致 headless 校验崩溃。
- DLL 与 `.gdextension` 放 `bin/` 并 gitignore（二进制/第三方源码不入库）；`.godot/extension_list.cfg` 由 `--editor --quit` 扫描生成，不入库。

### 实现

- 新增 C++ `CellSpatial`（`evaluate` 之外）：`build_neighbor_csr` / `collect_inputs_batch` / `resolve_collisions`。固定桶数组（CSR offsets+data）+ 前缀和，替代 `unordered_map`；**不加 Cell Lab 203 容量上限**（会截断邻居、破坏逐位等价）。碰撞对遍历顺序、浮点语义（GDScript float=double、数组 float32）逐位复现。
- `OrganismManager.native_spatial_enabled`（`@export`，默认 false）：false = 纯 GDScript（v0.30 逐位一致），true = C++ 碰撞；DLL 缺失自动回退。`BenchTest` 用 `CELLARIUM_NATIVE=1` 同口径 A/B。
- 冻结边界全部不动：GNP1、tick 顺序、1/60、单帧 12 tick、CommandBus、五通道场 schema、存档 schema v8、状态 hash 算法。

### 验证（程序化无头，双工程）

- 逐位等价：`neural_parity_probe`（12000 float32 全等）、`spatial_parity_probe`（邻域 657380 索引 / collect_inputs 12000 float32 / 碰撞 73620 次修正全等）。
- 端到端 `NativeParityProbe.gd`（40 密集合子、240 tick、5 检查点）：双工程 state hash 逐位一致（tick=240 同为 1356695503）。已登记 manifest。
- 双工程 `SCRIPTS=57 FAILURES=0`，三探针 `FAILURES=0`。

### 实测与诚实结论

- 同会话 A/B 基准：3000 细胞 physics 54.9→5.81ms（9.4×）、全 tick 128.0→84.9ms（1.5×）；300 细胞全 tick 12.8→7.9ms（budget_met=true）。
- **未达标**：84.9ms 远低于 8ms 目标，`cpu_budget_met=false`（3000 档）。physics 已非瓶颈，behavior(43ms)+metabolism(31ms) 成新大头；下一步下沉 collect_inputs（12.4× 已验证）与环境构建。不把该数字表述为达标。

---

## 0.30.0 — 2026-11-19

**类型**：物理性能专项 — SoA 计算路径 + 单 CanvasItem 批渲染对齐 Cell Lab（目标 3000 细胞流畅）
**触发**：用户专项「物理性能专项：SoA + 批渲染，目标 3000 细胞流畅」。**本版性能优化生效但 3000 细胞流畅目标未达标**，如实记录（见下）。

### 源码依据（分析文档 §33）

- 官方 `CellWorld.java` / Macro `SimulationWorld.java`：构造期固定池、逐细胞标量拆成并行 `double[]`（SoA）；空间哈希格边长 0.03、格上限 203、每细胞写 4 格、配对只从 `i4=i3+1`；接触循环 `d(int)` 顺带写共享弦 `A[]`，物理/渲染同源；渲染按类型分桶一次批提交 + `RENDERMODE_WHEN_DIRTY`。

### 实现

- 场采样：`EnvironmentManager.gd` 新增按 cell_index 的 O(1) 索引采样（`begin_field_sampling_indexed` / `get_field_samples_flat`），`EnvironmentField.gd` 新增 `sample_cells_flat()`，消除 `_sample_positions.find()` 的 O(n²) 线性查找；`OrganismManager.gd` 的两次场采样与代谢改为扁平消费。旧 API 保留兼容。
- 空间哈希：`CellPhysics.gd` 新增扁平键与 `build_spatial_hash_flat` / `query_neighbors_flat` / `build_collision_pairs_flat`；`Predation.gd` 每 tick 只建一次格、改 `query_neighbors_cached`。碰撞改扁平 pairs + 距离平方早退，过滤阈值取 2×接触距离以保留连锁分离语义。
- 神经行为：`CellBehavior.gd` 的 flat 输出计算/应用支持 `WorkerThreadPool` 静态分区（≥256 细胞写不重叠切片），确定性不变。
- 批渲染：新增 `CellPolygonBatchRenderer.gd`（单 `CanvasItem` 批量画共享弦切平膜/外轮廓/核点/连接线，>512 细胞启用），`CellSceneRenderer.gd` 与 `main.tscn` 接线 `CellBatchPoly` 节点；大规模 LOD 下保留 Cell Lab 膜外观而非 MultiMesh 纯色块。
- **冻结边界未动**：GNP1、tick 阶段顺序与 1/60 步长、单帧 12 tick 上限、`CommandBus` 单写者、五通道场 schema、存档 schema v8、状态 hash 逐位不变。

### 验证与实测

- 新增 `tools/PerfBreakdownProbe.gd`、`tools/BatchRenderProbe.gd` 并登记 manifest（脚本数 54→57）；双工程 `SCRIPTS=57 FAILURES=0 EXITCODE=0`，`PreviewReplica` / `DivisionAlignment` / `BatchRender` 探针均 `FAILURES=0`。
- `BenchTest.gd`：300 细胞 29.0→17.1 ms/tick、1000 细胞 114.2→60.2 ms/tick、3000 细胞 389.1→204.1 ms/tick（约 1.9×）；3000 细胞细分 behavior 63.1 / physics 85.0 / metabolism 48.0 ms。
- **未达标**：204 ms/tick 仍远低于 60fps 与倍速预算，`cpu_budget_met=false`；GDScript 解释执行与 Cell Lab 原生实现存在结构性差距，不把该数字表述为达标。批渲染功能断言全过且 hash 不变，但 600 细胞重建仍约 158–167ms。真正逼近流畅需把热点下沉到 GDExtension/C++ 或计算着色器，另立专项。

---

## 0.29.0 — 2026-11-19

**类型**：分裂机制进一步对齐 Cell Lab（40 槽分化树、旧连接重分配、FLAG 后向连接校验）
**触发**：用户专项「分裂机制进一步对齐 Cell Lab：40 槽分化树 i/j、旧连接重分配、FLAG 后向连接形态校验」。

### 源码依据

- 官方 `CellWorld.e(double):1968-2257`：`Cell.I = new Gene[40]`，母细胞 `D=Gene.i`、新细胞 `D=Gene.j`；`J[20]` 暂存旧连接，按 `cos(轴−世界角)−(1−2·Gene.c)` 与 ±0.2 双阈值重分配，中间带用左右投影四极值补齐，双方连接数 `<20` 才重建，对端 c/d 互换；D 槽切换后新类型为 FLAGELLOCYTE 时母/子后向连接 `cos(link.c)<-0.8` 判死。
- Macro `SimulationWorld.f1(D)V` 差异：`Gene.r/s` 是子代槽、`i/j` 为浮点；中间带处理不同且 FLAG 只判母细胞。以官方版完整机制为对齐目标，差异记入分析文档 §32.11。

### 实现

- `Genome.gd`：`MAX_GENOME_MODES` 16→40，`child1_mode/child2_mode` 对应官方 `Gene.i/j`，槽 39 保留；新增 `link_keep_mother/link_keep_child`（官方 `Gene.m/n`），仅任一开启时混入 hash，默认全关与 v0.28 逐位一致。
- `CellArray.gd`：新增 `cell_orientation` / `link_angle` SoA 数组；`link_cells()` 支持显式世界角，新增 `get_link_angle` / `set_link_endpoint` / `remove_link` / `get_orientation` / `set_orientation`，使旧连接可原地换端点与角度。
- `OrganismManager.gd`：分裂时按 `split_angle/split_angle2` 写母子朝向；`_redistribute_inherited_links()` 排除新生 child，按 `d14` ±0.2 与中间带四极值重分配，未命中者删除；`_has_backward_link()` 仅对 FLAG 类型（3）按 `cos(相对角)<-0.8` 判死，新死因 `DEATH_BACKWARD_LINK=6`，母/子均检查。
- `SaveManager.gd`：schema v7→v8，保存朝向/连接角；旧档朝向填 0、连接角按端点位置重算，兼容 `Array` 与 `PackedFloat32Array`。
- `DevEditorPanel.gd`：新增「旧连接归母 / 旧连接归子」两个 Macro 勾选项。GNP1、tick 顺序、单帧 12 tick 上限未改。

### 验证

- 新增 `tools/DivisionAlignmentProbe.gd`（登记入 manifest，脚本数 53→54），8 项断言全过：40 槽、槽 39/27 保留、Gene.m/n 落地、正向归子/反向归母、连接守恒、FLAG 后向判死、非 FLAG 不触发。
- 发布工程与 D 盘运行工程均 `SCRIPTS=54 FAILURES=0 EXITCODE=0`，`PreviewReplicaProbe FAILURES=0`；全程程序化无头验证。

---

## 0.28.0 — 2026-11-19

**类型**：对齐 Cell Lab 的指示点语义、预览刷新与模式化类型
**触发**：用户截图三问：绿色小点是什么；改颜色/连接数后预览不变；细胞类型应属于模式而非单独设子代类型。

### 源码依据

- `J4.java:688-765`：`j4.I()` 遍历当前世界 `S5[0..U5]` 的每个活细胞，按当前 Gene 画 2 个未来子代圆点（合子画 4 个），**不是历史分裂事件累积**。
- `Gene.java:99/110-116`：`o0` 是类型，`f778r/s/t/u` 是 4 个子代 Gene 槽索引；没有独立「子代类型」。

### 实现

- `PreviewWorld.gd` 新增 `snapshot_split_indicators()`，从真实当前细胞派生指示点；`GenomePreview.gd` 改用它渲染，颜色取目标子代模式，不再堆积历史绿点；`_accum_splits` 只留给只读里程碑索引。
- `DevEditorPanel.gd` 新增 `PreviewSyncTimer`（0.25s 防抖），Macro 字段改动后自动刷新预览。
- 删除 `child1_type` / `child2_type` 控件；兼容字段 `child_types` 改为从目标模式的 `cell_type` 派生，M2 设为光合后所有 M2 即光合。

### 验证

- 双工程 `SCRIPTS=53 FAILURES=0`、`EXITCODE=0`；预览探针全过，新增断言实测 8 细胞 = 8 组指示点，不再随历史分裂堆积。

---

## 0.27.0 — 2026-11-19

**类型**：发育预览默认 t=0 与编辑器 UI 精简
**触发**：用户截图反馈「发育预览的 t 默认为 0，不然一调整就卡死；上方说明删除，表现类型也可以删掉，发育预览的（只读，不跑第二套模拟）删掉」。

### 实现

- `GenomePreview.gd`：时间轴默认停在 t=0（合子）而不是末态，避免初始末态下拖动触发重置+重跑造成卡顿；同时为预跑增加 `IDLE_STOP_TICKS=240` 空转保护——默认草案 `division_mass=1.0` 超出真实能量上限，原本会空跑到 4000 tick（截图里的 `t=3983 · 0胞`），现在 240 tick 无分裂即收尾。有分裂时仍按真实发育继续，不改真实内核。
- `DevEditorPanel.gd`：删除顶部长篇基因模式说明面板；删除工具栏「表现类型」下拉（类型真相源改为右栏当前模式的「细胞类型」，`get_type_id()` 从 `_macro_draft.cell_type` 派生，API 保持兼容）；左栏标题精简为「GENOME PREVIEW · 发育预览」。
- `SmokeTest.gd` / `PreviewReplicaProbe.gd`：新增默认 t=0、无说明面板断言。

### 验证

- 双工程 `SCRIPTS=53 FAILURES=0`、`EXITCODE=0`；预览探针 25 项断言全过（`FAILURES=0`），默认 t=0、t=74 范围、累计分裂指示器与坐标居中均正常。

---

## 0.26.0 — 2026-11-19

**类型**：发育预览对齐 Cell Lab Macro 交互（连续时间轴）与坐标错位修复
**触发**：用户截图反馈「预览错位了，而且我想要的是 cell lab 的同款效果，不是像幻灯片一样一个阶段一个阶段的播放，上一步、播放、下一步的按钮都应该删掉，严格参考 cell lab marco」。

### 源码依据

再核对 Macro 版反编译源码：`GenomeEditorFragment.java:134` 的 `previewTimeHours` 是连续时间量，`GenomeEditorFragment.java:5717` 把滑块值直接写 `j4Var.U`，`J4.java:852` 按 `U / 0.02` 计算目标 tick，`J4.java:930-944` 跑真实 tick 并用 `Z/T/V/W` 缓存状态做断点续算；源码里没有「上一步 / 播放 / 下一步」离散阶段按钮。v0.24 的离散状态幻灯片播放与按钮不符合 Cell Lab 交互。

### 实现

- `GenomePreview.tscn` 删除 `Controls` 及 `PrevButton`/`PlayButton`/`NextButton`，只保留连续 tick 滑块 + 时刻标签；标题改为「GENOME PREVIEW · 连续时间轴」。
- `GenomePreview.gd` 重写为单一连续时间轴：拖动滑块即 `_seek_to(tick)` → `PreviewWorld.advance_to(tick)`，渲染那一刻的真实快照；保留膜弦、分裂指示器、平移/缩放/点击跳模式；旧 step/cursor API 仅为外部兼容保留。
- `PreviewWorld.gd` 新增 `advance_to(target_tick)`：目标 tick 大于当前则从当前状态续跑，小于当前则重置世界从合子重跑（对应 J4 断点缓存）；新增 `_accum_splits` + `snapshot_accumulated_splits()`，保证任意 tick 都能显示从合子到该时刻的真实分裂指示器。
- 坐标错位修复：真实模拟坐标以 `DISH_CENTER=(250,250)` 为中心，快照 pos / 分裂点 / 弦端点统一 `_local()` 平移到预览原点；`GenomePreview._refresh_view_transform()` 按当前细胞包围盒自适应居中缩放。
- 显式回收隔离 `_mgr` / `_env` 节点（`setup()` 重建前释放 + `NOTIFICATION_PREDELETE` 内联释放），消除预览反复重建时的 ObjectDB 泄漏；headless 退出不再有 leaked instances 警告。

### 验证

- 双工程 `SCRIPTS=53 FAILURES=0`、`EXITCODE=0`；预览探针 24 项断言全过（`FAILURES=0`），含无按钮、max_tick=74、tick 0/末/中间跳转、累计分裂指示器 14 个、坐标居中。
- 探针退出无 ObjectDB 泄漏警告；主场景与 SmokeTest 的既有 `resources still in use at exit` 仍为无害 shutdown 提示。

---

## 0.25.0 — 2026-11-19

**类型**：发育预览方向性纠正（直接复用真实模拟，废弃手拼近似内核）
**触发**：用户指出预览效果「完全与 Cell Lab 不一样、与实际模拟大相径庭」，要求当作独立细胞模拟直接调用已有模拟。

### 源码依据

再核对 Cell Lab 两版反编译源码：官方版 `n.java:37` `new CellWorld(true,environment)`、Macro 版 `J4.java:67` `new SimulationWorld(env,true)`——预览持有的是**同一个真实模拟类的独立实例 + 实验室环境**，用编辑器 Gene 造合子、`setSeed(1337)` 后跑真实 tick，渲染直接调真实世界方法（详见分析文档 §32.8）。v0.23/v0.24 的 `PreviewWorld` 手拼近似公式（280d²dt / sqrt(w/400)*500 / 上限 0.36）在公式与标度上都不同于主模拟，这是效果对不上的根因。

### 实现

- `PreviewWorld.gd` 重写为隔离真实模拟的薄封装：实例化 `OrganismManager` + `EnvironmentManager`（实验室模式：无食物投放、全皿均匀光照、场强制 CPU 后端），用编辑器 modes 构造真正 Genome，`register_zygote` 后直接跑 `advance_physics_tick(1/60)`。快照全部读真实 `CellArray`（位置/半径/表型色/类型/模式/能量/连接/共享弦）。
- 规模/超时保护对齐 Cell Lab：`MAX_CELLS=96`、`MAX_TICKS=4000`、预览节流 12；`tick_core=null`，不写主 CommandBus/field/hash/存档，隔离状态 hash 可单独验证。
- 共享弦用与运行时 `CellSceneRenderer._build_shared_chords` 同源的 `circle_chord`/`wall_chord` + peer/kind，预览膜与实际渲染一致。
- `GenomePreview.gd`：快照颜色改用真实逐细胞表型色（缺省回退类型色），半径口径改为真实的 `7×cell_radius_scale(0.5–2)`；分裂指示器 j4.I()、手动时间轴、膜弦管线、平移缩放选中保持。

### 验证

- 双工程 `SCRIPTS=53 FAILURES=0 ERRORS=0`，预览探针 19 项断言全过；真实模拟实测 1→4→16→56→96，半径随能量低通 7.0→5.6；两次独立运行真实状态 hash 逐位一致（确定性）；主场景 headless boot ok、EXITCODE=0。

---

## 0.24.0 — 2026-11-19

**类型**：发育预览外观与时间轴完善（细胞膜弦贴合 + 手动时间轴）
**触发**：用户反馈预览缺少细胞膜弦等细节，且自动播放不便于后期观察复杂细胞，要求改为可手动调整的时间轴。

### 源码依据

全量反编译 `CellWorld.a(FFFF)` 完整方法体（见分析文档 §32.7）：接触阶段 `d(int)` 把圆-圆相交弦端点写进 `cell.A[]`（含遮挡/截断/对端索引标记），渲染阶段按角度排序后以圆心扇形三角剖分重建膜，相邻弦端点间用圆方程补弧；两细胞 Link 接触点间画四边形缝合膜；无接触时画包围盒由 fragment `discard(ds>r²)` 裁圆。物理与渲染共享同一组弦端点是精密贴合的根本。

### 实现

- `PreviewWorld.gd`：接触阶段（推开前）按 Cell Lab 解析式算弦端点，记 owner/kind 并随快照输出；皿壁弦单独处理内切。
- `GenomePreview.gd`：复用运行时 `CellContactChords.gd` 管线，有弦时画切平膜多边形、无弦时画正圆，叠加 `j4.I()` 分裂指示器不变。
- `GenomePreview.tscn`：新增 `Timeline/Slider` + `TimeLabel`；默认暂停、播放到末态即停不循环；拖滑块直接跳转时刻并暂停，按钮与滑块双向同步，标签显示真实 tick 与细胞数。
- 快照记录内核 tick，供复杂细胞逐时刻定位。

### 验证

- 探针新增：弦在分裂接触时生成、滑块/标签存在、默认暂停、拖动跳转末态；双工程 `SCRIPTS=53 FAILURES=0 ERRORS=0`，探针 `FAILURES=0`。
- 弦端点为只读视图派生，不写 CommandBus/field/hash/存档，主模拟确定性不受影响。

---

## 0.23.0 — 2026-11-19

**类型**：发育预览真实模拟复刻（Cell Lab GenomePreviewView 全量反编译 + 独立模拟内核）
**触发**：用户要求第一阶段先全量精读 Cell Lab 代码、完美移植复刻发育预览与分裂/物理机制，允许底层大改。经用户确认：本轮先做发育预览，接受引入第二套真实模拟内核，底层全面可改。

### 全量反编译（证据升级）

- 两个 DEX 全量反编译落地：`decompiled_zh/`（33 类，`CellWorld.java` 199KB）+ `decompiled_macro/`（554 类，`SimulationWorld.java` 2.5MB），逐行精读完整方法体，补齐此前「未确认」边界。中间产物由 `.gitignore` 排除，不入库。
- 关键机制（写入 `analysis/CellLab_细胞物理与外观_代码级分析.md` 第 32 章）：
  - 预览 = 当前 Gene[] 起真实模拟世界 + 固定种子 1337 + `u/0.02` 步 + 断点续算缓存 + 6 秒超时；合子 `w=0.288/0.36`、`d=sqrt(w/400)`。
  - 分裂指示器 `j4.I()`：分裂角 + 镜像位求方向，质量比 `clamp(f769i,0.1,0.9)`，圆点半径 `max(0.006,r*0.27)`、偏移 `r*0.42`，非合子 2 个 / 合子 4 个。
  - 分裂 `CellWorld.e(double)` 完整条件链 + 0.1r 母子偏移（零力）+ 分化槽 i/j + 连接重分配 + 端粒 + FLAG 形态校验。
  - 3000 细胞性能来自 SoA + 固定池 + 空间哈希（每格≤203、每细胞 4 格、配对唯一）+ 按需渲染 + O(1) 场采样；瓶颈在宿主侧固定成本而非细胞数。

### 实现

- 新增 `scripts/core/data/PreviewWorld.gd`：独立 `RefCounted` 轻量模拟内核，严格按 Cell Lab 公式跑确定性发育——合子初始化、光合产能 `280·d²·dt`、半径低通、分裂条件链（母子各偏 0.1r、按 split_ratio 分能量、`child1/child2_mode` 分化槽切换、端粒、镜像、黏附连接）、接触软排斥、亲子弹簧。固定种子 1337 的 Java-Random 同构 LCG，同初态逐位一致。不写 CommandBus/field/hash/存档，主模拟确定性不受影响。
- 重写 `scripts/ui/GenomePreview.gd`：由静态 `dev_program` 派生改为真实内核驱动——每个 state 是一次真实分裂时刻快照（真实位置/半径/朝向/分化槽/连接）；分裂指示器改为 Cell Lab `j4.I()` 逐方法等价（分裂角方向 + 质量比 + 圆点半径/偏移，合子四子代）；交互补齐平移/滚轮缩放（`|log(scale)|<0.3` 阈值）/单击选中回调；保留全部只读 API。
- SmokeTest manifest 登记新脚本；新增 `tools/PreviewReplicaProbe.gd` 验证倍增、确定性、指示器公式、全链路；三处旧派生断言更新为真实模拟不变量。

### 验证

- 发布工程与 D 盘运行工程均 `SCRIPTS=53 FAILURES=0 ERRORS=0`，探针 `FAILURES=0`。
- 内核倍增实测 1→2→4→16→256，120 tick 确定性两次逐位一致；分裂角 `π/2`（child2_angle=0.25）、质量比在 clamp 区间。

### 边界

- 预览内核只实现「视觉发育」所需子集，不引入 40 槽分化树全量、95 突变算子、101 信号通道等重型机制；`GNP1`/主 tick 顺序/CommandBus/单写者/schema 未改，主模拟不受影响。
- 分裂与物理机制的代码级规格已写入第 32 章，留待后续专项复刻（本轮按用户确认只做发育预览）。
- 反编译为静态分析，APK 未执行；GPU 实际观感需窗口环境复核。

---

## 0.22.0 — 2026-11-19

**类型**：缺陷修复（残余 depth 分裂闸门）——对齐 Cell Lab 的分裂次数控制语义
**触发**：用户实测细胞能量 2.0892（阈值 0.05 的 40 倍）却不分裂，只有链末端新生细胞分裂，呈线性增长。程序化闸门探针复现：所有细胞 `depth=1>=1` 被挡（旧行为卡在 4 细胞）。查证 Cell Lab `e(double)` 无 mode depth 闸门，分裂次数由端粒 `T∈{-1,5,10,20,40,80}` 控制，本项目 `cell_telomere` 已承担该角色。

### 根因

v0.20.0 只移除了 per-organism cooldown 串行锁，但遗漏了第二套独立闸门：`_apply_autonomous_lifecycle` 里 `depth >= mode.max_divisions` 检查，配合执行阶段母细胞分裂后 `depth+1`。对 M1→M1+M1 自增殖模式（`normalized_mode` 默认 `max_divisions=1`），每个细胞分裂一次后 depth=1 永久锁死，只剩 depth=0 的新子细胞能分裂 → 1/2/3/4 线性链。

### 修复

- `OrganismManager`：删掉 `depth >= max_divisions` 候选闸门；母/子细胞分裂时 depth 不再累加（均继承原 depth，自增殖恒为 0）。`cell_mode_depth` 字段、存档与 hash 保持兼容，不升 schema。
- `GenomePreview`：三条派生路径同步去掉 depth 候选限制与 depth+1，预览步数仍由顶层 `max_divisions` 约束以免无限绘制。
- 端粒（`cell_telomere`）继续作为分裂次数限制：有限值母子同减、归零死亡，`-1` 无限。GNP1、tick 顺序、单帧 12 tick 上限、schema v7 均不动。

### 验证

- SmokeTest 新增 `OK v0.22.0`：单模式 max_divisions=1 自增殖，细胞数突破旧上限达到 ≥8 且 depth 恒为 0。
- 闸门探针 `GateProbe.gd` 对比：修复前 tick=3 为 4 细胞全部 `depth=1>=1` 被挡；修复后 tick=3 为 8 细胞全部 depth=0、仅剩正常 cooldown/能量门槛，tick=55 达 128 细胞。
- 双工程（发布工程 + D 盘运行工程）均 `SCRIPTS=51 FAILURES=0 ERRORS=0`。

### 边界

- 本次只加诊断探针 GateProbe.gd / GrowthProbe.gd，未改判定阈值或产能参数。能量不足时仍按能量门槛停止分裂（真实代谢下光合产能弱，见 GrowthProbe），属参数平衡而非逻辑缺陷。
- 静态反编译证据 + headless CPU 探针；GPU 实际观感需窗口环境复核。

---

## 0.21.0 — 2026-11-19

**类型**：分裂机制对齐 Cell Lab（per-cell 并行倍增 + 半圆出生形状）+ 发育预览分裂指示器
**触发**：用户观察到 Godot 细胞链是 1/2/3/4 线性增长而非 Cell Lab 的倍增，分裂后细胞不再分裂；且分裂看不到 Cell Lab 的两个半圆效果，发育预览也没有分裂线/方向。静态查证确认：Cell Lab `e(double)` 对每个细胞独立判定分裂（无 per-organism cooldown），出生时母子各沿分裂轴移 0.1r（中心距 0.2r、半径不变→重叠半圆），分裂施加零力、下一 tick 接触排斥弹开；Macro `GenomeEditorFragment` 有 `checkbox_show_split_indicators` 控件。

### 实现

- **v0.20.0 并行倍增**：分裂调度从「按 org_id 每 tick 一次 + 个体级 cooldown=300」改为「每细胞独立 cooldown」。`CellArray` 新增确定性状态 `cell_division_tick`（上次分裂 sim_tick，进 hash/存档）；候选阶段用逐细胞 cooldown 取代 per-org 闸门并保留单细胞首帧宽限；分裂后母子各自重置 tick，刚出生的子细胞当 tick 不再分裂。实测单模式 M1→M1+M1 走 1→2→4→8→16→32，能量守恒。schema 升 v7（旧档 `cell_division_tick` 填 -2）。
- **v0.21.0 半圆出生形状**：出生间距从 `max(14, 2r)=14`（正好相切，看不到半圆）改为 Cell Lab 口径 `0.2r`；分裂后母子各沿分裂轴偏 `0.1r`（中点在原母细胞位置），半径当帧保持母半径 → 高度重叠，共享弦渲染成两个贴靠半圆。连接静止长度仍为 `2r`，分裂在 metabolism 阶段（碰撞之后），下一 tick 的接触排斥把两细胞弹开至 `2r`，与 Cell Lab「分裂零力、靠接触排斥分离」一致。
- **v0.21.0 发育预览分裂指示器**：`GenomePreview` 新增 `show_split_indicators` 导出（对应 Macro `checkbox_show_split_indicators`）。三条派生路径（多模式/基因模式/旧指令）均记录每次分裂的 `angle` 与亲子索引，`_on_canvas_draw` 叠加垂直于分裂轴的切面线（黄）与母→子的方向箭头（橙）。纯绘制，不写 CommandBus/field/hash/模拟状态。新增只读 `get_split_count_at` / `get_split_angle_at`。

### 验证

- SmokeTest 新增 `OK v0.21.0`：per-cell 倍增经过 2/4/8；出生帧母子中心距/接触距=0.1（即 0.2r）且半径保持 1.0；下一 tick 被排斥拉开。另在基因预览测试内断言分裂指示器数量随分裂递增、角度在 0..TAU。
- 程序化探针 `HalfCircleProbe.gd`：`BIRTH_FRAME dist=1.4 contact=14.0 ratio=0.1`；`NEXT_TICK dist=14.0 pushed_apart=true`。`DivisionProbe.gd` 复核倍增 1→2→4→8→16→32、能量守恒。
- 双工程（发布工程 + D 盘运行工程）均 `SCRIPTS=51 FAILURES=0 ERRORS=0`。

### 边界

- 并行倍增改变默认演示体与旧快照的细胞数轨迹（由 `max_divisions` 链与能量减半约束上限），GNP1 二进制布局、tick 顺序、单帧 12 tick 上限不动。
- 半圆效果基于共享弦对重叠圆的自然裁剪，分裂零力；视觉持续时间由接触排斥速度决定，未在渲染层额外加动画。
- 证据均来自静态反编译（APK 未执行），性能/形状数字来自 headless CPU 回退探针；GPU 实际观感需窗口环境复核。

---

## 0.19.0 — 2026-11-18

**类型**：玩法机制补齐（半径-能量低通）+ 视图热点优化；GNP1 二进制、tick 顺序、单帧 12 tick 上限不动
**触发**：用户观察到 15 细胞链明显掉帧而 Cell Lab 不明显，且刚分裂子细胞偏小、不随能量长大。查证 Cell Lab `f(double)` 已证实半径对 `d²` 一阶低通（稳态 `sqrt(w)/20`），确认本项目是机制缺失；性能侧确认视图重建的字符串 pair key 与固定 64 点膜是主要边际开销。

### 实现

- 半径-能量低通：`CellArray` 新增 `cell_radius_baseline`（基因 `cell_size` 表型）与 `cell_energy_scale`（能量因子），`cell_radius_scale` 保持为有效倍率 = 基线 × 因子，物理碰撞/皿壁投影/渲染/分裂间距所有读取点不变。
- 每 tick 在 metabolism 阶段以该细胞模式 `division_mass` 作参考能量 `E_ref`，对因子做有界一阶低通：`target² = clamp(E/E_ref, 0.5², 1²)`，`s² ← s² + (target² − s²)·rate·dt`（默认 rate=5）。能量越高半径越大并平滑趋近；饥饿收缩；刚分裂的低能量子细胞较小、随摄能长大。仅 gene_mode 生效，非基因模式与 `energy_radius_growth_enabled=false` 保持 v0.18 固定倍率。
- 视图热点：`CellSceneRenderer._build_shared_chords` 的 pair key 由字符串改为整数打包 `low*8001+high`；`CellView` 新增 `outline_segments` 导出（独立实例默认 64 保持旧行为，`CellBase.tscn` 设 48），降低每帧弦裁剪与顶点写入成本。视图优化不改任何模拟状态或 hash。
- 存档升 `schema_version=6`：保存两个新数组，旧档按 baseline=旧有效倍率、因子=1.0 回退，半径逐位不变；数组纳入 `get_state_hash()` 保证回放确定性。GNP1、tick 顺序、能量账本与守恒公式未改。

### 验证

- SmokeTest 新增 `OK v0.19.0`（稳态 `sqrt(1/4)=0.5`、首 tick 不跳变、能量回升可逆、开关冻结、schema v6 新旧回退、状态 hash 确定性）。
- `ViewCostProbe` 链长视图重建：15 细胞 1845→1453 µs/帧，30 细胞 4545→3707 µs/帧（约 -20%）；模拟 tick 成本不变。GPU 实际帧率与 `_process` 逐帧收益需窗口环境复核。
- 双工程验证：发布工程与 D 盘工程均 `SCRIPTS=51 FAILURES=0 ERRORS=0`。

---

## 0.18.0 — 2026-11-18

**类型**：玩法机制版本化追加（取消个体 8 细胞硬上限 / 全局容量保护 / 连接数抑制分裂 / 端粒；GNP1 二进制、tick 顺序、单帧 12 tick 上限不动）
**触发**：用户设计「单模式光合细胞持续分裂成粘连长带」时只长到 4 个细胞；查证 Cell Lab 静态证据后确认 Cell Lab 没有显式 per-organism max cell count，只有全局 `Cell[]` 池、每细胞连接上限、`P <= Gene.u[9]` 与端粒 `T ∈ {-1,5,10,20,40,80}`。用户授权不再把 8 细胞当硬基线，并要求把规模限制做进细胞编辑。

### 证据边界与规格先行

- 已解析证据只支持「Cell Lab 无显式个体最大细胞数字段，个体是 `Link` 连通分量」；`levels.xml` 的 `user-cells / place-cells / level-cells` 是关卡预算，不是生物学上限。
- 能量尺度上限查证结论本版不改：`Cell.w <= 0.36`、`< 0.072` 死亡、`LIPOCYTE.S <= 1.8`、连接流 `±0.1`。
- 规格先行：`analysis/CellLab_细胞物理与外观_代码级分析.md` §28、v1.1 合并稿新增版本化说明、`docs/Godot项目技术设计文档.md` §0.3 与 §11 风险表已先修订再落地代码。

### 实现

- `Genome.gd` 新增 `max_cells_per_organism = -1`（无限）与逐模式 `link_division_limit = -1 / telomere = -1`；端粒只允许 `-1/5/10/20/40/80`，非法值取最近档；校验、`distance`、`duplicate_genome` 同步；仅 `modes` 非空时混入 hash，空 modes / flags 清零保持旧 hash。
- `CellArray.gd` 新增 `max_cell_capacity = 8000` 全局容量，拒绝超额 `append_cell` / `divide_cell`；新增 `cell_telomere` 与递减 API。
- `OrganismManager`：个体上限改读 `max_cells_per_organism`，旧 payload/缺字段回退 `max_divisions+1`；逐模式连接数达到阈值即抑制分裂；端粒每次分裂母子同减，归零按 `DEATH_TELOMERE` 死亡；`autonomous_max_cells_per_organism` 默认改为 -1。
- `SaveManager` 升 `schema_version=5` 保存 `cell_telomere / max_cells_per_organism`；schema 1–4 旧快照端粒填 -1、个体上限回退 `max_divisions+1`。
- `DevEditorPanel` 新增 “SCALE · 个体规模 / 谱系限制” 三个控件，均可在细胞编辑页设置；`GameHUD` 经 `CommandBus genome_gene` payload 传新字段，GNP1 不变。
- `Main.gd` 默认演示体显式设置 `max_cells_per_organism = 4`，保持 v0.17 的 4 细胞 / 3 连接快照。
- `StatisticsSystem` 死因表新增 `5 = 端粒耗尽`。

### 验证 / 同步

- 新增 SmokeTest：无限光合带突破 8 细胞、显式个体上限、全局容量拒绝、连接数抑制、端粒递减死亡、schema v5 与旧档回退、指令 payload 新旧路径、编辑器控件写入与 hash 边界。
- 发布工程与 D 盘运行工程分别 `SCRIPTS=51 FAILURES=0 EXITCODE=0`；D 盘同步 10 个脚本，保留 autoload / `.uid` / 场景 `unique_id`。

---

## 0.17.1 — 2026-11-18

**类型**：崩溃修复（模式槽删除）
**触发**：用户反馈删除已有模式会直接闪退，编辑器跳到 `DevEditorPanel.gd` 的子代角度写入循环附近。

### 根因

- `_on_remove_mode()` 先调用 `_commit_current_mode()`，随后 `_load_mode()` 默认又提交一次旧的 `_macro_draft`。槽已从 `_modes` 删除，但第二次提交仍把旧草稿写回已越界的索引，触发 `Invalid assignment of index`。
- 删除槽后其余模式的 `child1_mode / child2_mode` 未重编号，可能指向不存在的模式。

### 修复

- `_load_mode(index, commit_current := true)`：增删槽路径传 `false`，只同步最新 `modes` 到 Genome 草案，不再重复提交旧草稿。
- 删除槽时把指向被删槽的子代模式引用回退到 0，引用后续槽的索引前移。
- 新增 SmokeTest 覆盖：删除当前/末位/中间模式、删除后新增模式、草稿有效性与模式数量一致。

### 验证 / 同步

- 发布工程 `SCRIPTS=51 FAILURES=0 EXITCODE=0`；D 盘工程同步 `DevEditorPanel.gd` 与 `SmokeTest.gd` 后同口径回归。

---

## 0.17.0 — 2026-11-18

**类型**：玩法机制版本化追加（多模式基因组 / 两子代分裂 / 连接能量传递；GNP1 二进制、tick 顺序、单帧 12 tick 上限不动）
**触发**：用户反馈「连接的细胞没有能量转出/转入；细胞编辑为什么不能编辑细胞模式了，一个基因组由多个模式组成，每个模式存自己的类型、行为、子代与特殊控制；一个模式分裂为两个子代；发育预览中的细胞可点击跳转到对应模式编辑」。

### 根因与证据边界

- 连接转账为 0 的根因在调用端：`OrganismManager.default_transfer_rate = 0.0` 被 `rates.fill()` 传给 `CellMetabolism.redistribute_link_energy()`，诊断本身正确。
- 用户提供的 Cell Lab Macro 截图可核对模式列表、两子代模式、黏附/镜像/角度、分裂阈值/比例、营养优先级、RGB、黏附/骨架/大小/连接数与可点击发育预览；40 Gene 槽全量语义、行为总线全索引与 `Gene.f773m` 运行时消费点仍无逐行证据，本版只做版本化追加，不复制全量实现。
- 规格先行：v1.1 §5.3、v2.1 §0.3 / §11 与风险表、分析文档 §27 已先修订。

### 实现

- `Genome.gd` 新增 `modes: Array[Dictionary]` 与逐模式字段（类型、黏附、两子代模式/类型/角度/镜像、分裂质量/比例/层数、营养优先级、传递率、表型、颜色、黏附强度/长度/拉伸、特殊控制），并新增 `normalized_mode / get_mode / set_modes / demo_modes`；仅在 `modes` 非空时混入 hash，空 modes / flags 清零保持旧 hash。
- `CellArray.gd` 新增 `cell_mode / cell_mode_depth`；分裂后母细胞作为子代 1、新细胞作为子代 2，切模式层数归零，同模式连续分裂才递增；顶层最大分裂次数仍限制个体细胞数。
- `OrganismManager` 按模式派生传递率、阈值、质量比、子代模式/类型/表型与黏附连接；每个个体每 tick 最多分裂一次；`CellMetabolism` 守恒公式不变。默认演示体改为 5 模式 / 3 次分裂 / 4 细胞 / 3 连接。
- `SaveManager` 升 `schema_version=4` 保存 `modes / transfer_rate / cell_mode / cell_mode_depth`；schema 1–3 旧快照缺字段填空/空数组。
- `DevEditorPanel` 增加模式列表（新增/删除/切换/改名），当前 Macro 字段改为编辑当前模式，只显示子代 1 / 2；`GenomePreview` 每个派生细胞带模式索引，左键点击发出 `mode_selected` 跳转编辑。
- `GameHUD` 将 `modes / transfer_rate` 继续经 `CommandBus` 的 `genome_gene` payload 传入，不进冻结 GNP1。

### 验证 / 同步

- 新增 SmokeTest：逐模式编辑不串数据、两子代模式、预览点击跳转、hash 兼容边界、模式分裂与表型继承、连接转账守恒、payload 往返、schema v4 与旧档回退。
- 发布工程与 D 盘运行工程分别 `SCRIPTS=51 FAILURES=0 EXITCODE=0`；D 盘同步仅脚本，保留 autoload / `.uid` / 场景 `unique_id`。

---

## 0.16.0 — 2026-11-18

**类型**：玩法机制版本化追加（基因模式补齐 Macro 表型字段；GNP1 二进制、tick 顺序、单帧 12 tick 上限不动）
**触发**：用户在阶段选择中确认「补齐 Macro 基因字段」，即把此前仅作草案展示的营养优先级、细胞骨架强度、细胞大小、最大/最小连接数、RGB 颜色真正落地。

### 证据边界

- 静态反编译证据：`seek_prio → Gene.f773m`、`seek_stiff → Gene.f774n`、`Gene.u[9]` 连接数上限、`Gene.a[3]` 颜色插值、`Gene.z/A[6]` 0.5–2 范围、`Cell.a(6)` 接触刚度；证据 ID 见 `analysis/CellLab_细胞物理与外观_代码级分析.md` §20.1。
- **未证实边界**：`Gene.f773m` 的运行时消费点、独立「最小连接数」控件。这两项明确记为本项目的版本化追加，不宣称等价移植。
- 规格先行：已修订 v1.1 §5.3、v2.1 §0.3 / §11，再动代码。

### 实现

- `Genome.gd` 在 `FLAG_GENE_MODE` 下追加 `nutrition_priority / cell_stiffness / cell_size / max_connections / min_connections / color_r|g|b`，校验、duplicate、distance 同步；hash 显式混入新字段，`flags` 清零时逐位保持 v0.15.0 hash。
- `CellArray.gd` 新增逐细胞 `cell_radius_scale / cell_stiffness / cell_color_*`；物理碰撞、皿壁投影、共享弦、选中环与连接桥均按同一倍率计算，旧模式默认 1.0/-1，行为不变。
- `OrganismManager`：营养优先级调异养/光合摄能权重（0.5 等价旧版）；骨架强度映射接触分离系数 `0.25 + 1.5×stiffness`（0.5 等价旧版 1.0）；最大连接数阻断新增连接，最小连接数在分裂后按索引升序确定性补连；GNP1 不变，新参数走 `genome_gene` payload。
- `SaveManager` 升级 `schema_version=3` 并保存表型数组；schema 1–2 的旧快照恢复时填 1.0/-1 默认值。
- `DevEditorPanel` 将新字段写入草案（最小连接数自动钳制不超过最大连接数），提示与帮助文本标明证据边界；`GenomePreview` 显示大小/RGB/连接数并按补连派生连接，不改变模拟状态。
- 颜色只覆写视图基色，不进确定性 hash；新基因字段进 hash 但不进 GNP1。

### 验证 / 同步

- 新增 SmokeTest：编辑器字段写入与 hash 边界、旧模式 hash 不变、预览 caption/补连、逐细胞半径/刚度/颜色、颜色真实渲染到 `CellBase` 的 Body、连接上下限、schema v3 与旧快照回退。
- 发布工程与 D 盘运行工程分别 `SCRIPTS=51 FAILURES=0 EXITCODE=0`；D 盘同步 13 个脚本，保留 autoload / `.uid` / 场景 `unique_id`。

---

## 0.15.0 — 2026-11-18

**类型**：玩法机制版本化追加（基因驱动发育 / 移除指令序列；GNP1 二进制与单帧 12 tick 上限不动）
**触发**：用户反馈「细胞能量 87 为什么不分裂、在细胞编辑加分裂质量设置到什么质量分裂；LINK 指令直接删除；模仿 Cell Lab 应该没有指令集（分裂即分化，连接由黏附素决定）；发育预览也要显示子代黏附连接」。

### 根因

- 程序化定位：`register_zygote()` 调用 `OrganismStore.add_developed_cell()` 时，后者无条件把 `org_state` 写回 `STATE_DEVELOPING`，覆盖初始 MATURE；而自主生命周期只处理 MATURE 个体。旧模式必须靠 `dev_program` 执行完才成熟，用户没写够指令就永久卡住，能量 87 也不分裂。阈值 `autonomous_division_energy=0.16` 还写死在管理器，编辑器无法设置。

### 实现

- **基因模式**：`Genome.flags` 位 1 置位进入，字节编码不变、清零完全兼容 v0.14.x。新增 `division_mass`（分裂能量阈值，Cell Lab `Gene.b`）、`split_ratio`（`Gene.c`）、`max_divisions`、`child_types`（`Gene.i/j` 分裂即分化）、`split_angles`。这些字段不进 GNP1 冻结二进制，走存档 `schema_version=2` 与 `CommandBus` 的 `genome_gene` payload，并显式混入 hash。
- **分裂质量**：细胞编辑新增「分裂质量（能量阈值）」滑块（0.05–100）、分裂质量比、最大分裂次数；达到阈值即分裂，不再受 `dev_program` 发育期门控。`register_zygote()` 在 `add_developed_cell()` 后恢复初始状态，修复能量高却不分裂。
- **移除指令集**：新基因组 `dev_program` 恒为空；编辑器隐藏指令树/时间轴/模板/opcode 参数（节点保留供旧存档读取）；`LINK` 与 `DIFFERENTIATE` 不再生成，`DevelopmentRules` 的 opcode 2 仅保留旧存档兼容。
- **发育预览**：按分裂次数派生状态，子代类型取 `child1–4`，黏附素显示亲子连接，显示质量阈值；无 LINK 阶段。
- **诊断**：`AnalysisPanel` 继续显示产能/耗能明细（v0.14.1），生态报告不受影响。

### 验证 / 同步

- 新增 SmokeTest：分裂质量写入与 hash 变化、旧 Macro 字段不写 GNP1、指令 UI 隐藏、能量达标 → 4 细胞 / 3 黏附连接、子代类型分化、预览连接数/类型、schema v2 存档往返。`SCRIPTS=51 FAILURES=0 EXITCODE=0`。
- 已同步 D 盘运行工程并双工程验证；v1.1 §5.3、v2.1 §0.3/§11、分析文档 §25 同步。

---

## 0.14.1 — 2026-11-18

**类型**：反馈批次（参数校准 + 只读诊断 + GNP1 已有 flags 位的版本化语义追加；不改 tick 顺序、单帧 12 tick 上限、GNP1 布局、五通道 schema）
**触发**：用户反馈「光合细胞效率有点低，调高一点；生态报告诊断显示细胞当前产能和耗能（标出自身耗能与传输给其他细胞的耗能）；生成黏附素即视为子代细胞连接，不用单独设置连接的指令；食物消失太快，衰亡调慢」。

### 实现

- **光合效率**：`OrganismManager.photosynthetic_intake_rate` `0.02 → 0.08`，充分光照时接近异养效率；仍按光场值逐 tick 摄入，不改能量守恒。
- **食物衰亡**：`FoodStore.MASS_DECAY` `0.11 → 0.012 / 秒`，0.2 质量颗粒寿命约 830 tick；保持线性衰减 + 池尾交换，不是 Macro 常量逐行移植。
- **黏附素即连接**：`Genome.flags` 位 0 版本化赋予「生成黏附素」语义。`DevelopmentRules.execute_divide()` 与成熟后自主分裂在该位置位时自动 `link_cells(parent, child)`，无需显式 `LINK`；清零保持旧行为。`DevEditorPanel` 勾选「生成黏附素」写入该位，其余 25 个 Macro 字段仍只展示。已同步修订 v1.1 §5.3 与 v2.1 §0.3 / §11；**置位基因组 hash 会变化**，这是有意的新版本语义。
- **能量流诊断**：`CellMetabolism.redistribute_link_energy()` 增加可选只读诊断输出，累加顺序与 deltas 不变；`OrganismManager._energy_flow` 记录 `production / self_cost / link_out / link_in / predation_drain`，`get_live_inspection()` 逐 tick 派生；`AnalysisPanel` 显示产能、自身耗能、传输给其他细胞、连接转入（捕食流失非零时另列）。不写模拟状态、不进 hash、不进存档。

### 验证 / 同步

- 新增 SmokeTest 断言：60 秒食物质量残留、光合速率 0.08、能量流缓冲与面板文本、黏附素置位自动连接 / 清零不连接、编辑器 flags 位与 hash 变化；`SCRIPTS=51 FAILURES=0 EXITCODE=0`。
- 发布工程与 D 盘运行工程分别运行通过；D 盘同步 8 个脚本（保留 autoload / `.uid` / 场景 `unique_id`）。

---

## 0.14.0 — 2026-11-18

**类型**：性能根因修复 + 反馈批次 + 食物实体池（规格已版本化修订；不改 tick 顺序、GNP1、dev_program 语义、五通道 schema 与确定性 hash）
**触发**：用户反馈「只有几个细胞仍然很卡、Cell Lab 手机都流畅；页面显示 FPS/TPS；指令序列多时 UI 撑爆；生态报告按钮又失效且下方信息不刷新；Cell Lab 没有指令序列这东西、开销大吗；做食物实体用 Cell Lab 方法；光场在皿下方和右方有空隙」。

### 代码证据与测量

- 新增 `tools/ViewCostProbe.gd` 程序化测量（不截图/不动鼠标）：优化前 CPU 后端 `diffuse_tick` = **18,923 µs/tick**，模拟 1 个细胞仅 93 µs；确认卡顿与细胞数无关，真凶是 CPU 场扩散每格新建 `[Vector2i...]` 数组、`_sample_grid` 在零平流下仍做双线性（内部 4 次 `_is_active` + Vector2 分配）。
- Cell Lab 静态证据（APK 未执行）：启动时一次性 `new Food[G2]` 定长池 + active count，质量线性衰减、池尾交换回收（`analysis` §20.3 证据 ID 见文档）；`GenomePreviewView` 用 `RENDERMODE_WHEN_DIRTY` 按需渲染；`Environment.q` 64×64 双线性 O(1) 采样。Cell Lab **有**基因规则（位掩码条件-动作），但是 O(N) 位运算，开销可忽略；我们 dev_program 每发育个体每 tick 一条指令，同样可忽略——卡顿与指令序列无关。

### 实现

- **性能**：`EnvironmentField._apply_cpu_diffusion()` 重写为逐位等价快速路径（预计算 active mask、展开四邻域保持 LEFT/RIGHT/UP/DOWN 累加顺序、零平流直接取 center）。实测 **18,923 → 1,335 µs/tick（13.7×）**；SmokeTest 新增非零平流旧公式逐位等价回归，保护 CPU/GPU parity。
- **FPS/TPS**：`main.tscn` 增加 `UI/HUD/PerfLabel`，`GameHUD` 用真实帧计数与 tick 增量按 0.5 s 窗口刷新，显示 FPS / TPS / 倍速 / LOD。
- **指令序列 UI**：`DevEditorPanel` 的左栏指令列表包进 `InstructionScroll`（可滚动 + 折叠按钮），底部时间轴包进 `TimelineScroll`，指令再多也不会撑爆窗口。
- **生态报告**：`GameHUD._build_panel_chrome()` 改为 `call_deferred`，根因是 chrome 早于 AnalysisPanel 自己的 `_ready()` 安装，导致内容覆盖标题栏并抢走图钉/关闭按钮事件；`PanelChrome.install()` 幂等。新增 `OrganismManager.get_live_inspection()` 按选中细胞索引逐 tick 派生实时诊断（原来只存点击瞬间快照）；解锁默认自动收起报告页，只有手动按图钉才保持打开。
- **食物实体池**：按已修订的 v1.0 §2.2 / v2.1 §0.3 / §11 落地 `FoodStore.gd`——定长 128 池、池尾交换回收、质量线性衰减、涂层字段、存档 payload；由营养场确定型投放位置派生，`FoodLayer` 优先画实体颗粒（旧对比度视图作回退）。实体只读派生，不写能量结算、不进 hash、不改 schema。
- **光场空隙**：`FieldLayer._build_pad_source()` 缓存圆外格→最近圆内格映射，视图插值用补齐场铺满整个圆；shader 保留极淡基底，皿内不再有黑环；UPSCALE 4→2 + 6 tick 节流降固定成本。

### 规格 / 验证

- 修订 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §2.2 与 `docs/Godot项目技术设计文档.md` §0.3 / §11，声明食物实体池为只读派生的版本化追加，并列出「变第二套能量真相」的风险与对策。
- 发布工程与 D 盘运行工程均 `SCRIPTS=51 FAILURES=0 EXITCODE=0`；D 盘同步 14 个脚本 + `main.tscn` 增量新增 PerfLabel（保留 MCP autoload / 脚本 uid / 场景 unique_id）。

---

## 0.13.1 — 2026-11-17

**类型**：五项反馈修复 + 发育预览（纯视图 / 编辑器 UI，不改 tick、GNP1、dev_program 语义与确定性 hash）
**触发**：用户反馈「光场边缘锯齿、食物看不到、指令集不会用导致自建细胞不分裂、生态报告关闭按钮无效且不再刷新、Cell Lab 基因组编辑页上方的发育可视化是什么」。

### 代码证据

- 静态反编译 Macro `GenomePreviewView`（`com.saterskog.cell_lab_enzymeglv.GenomePreviewView`，JADX 0.7.1，APK 未执行）：类清单 `ev_ef54d8a852cde2c2e2f1d62395c1c13f703fe576a03be9b30159bbe737c44912`、构造函数 `ev_b767a4f8b117ac1e4d422bcdc47f1ff1eca82bbede030477a29bc365e745f3a2`、渲染器 `j4` 类清单 `ev_671207c154a5cb5043907153e39fb2444164ecea0bd6a48ee5734d43fb8f5b33`。确认它是 GLSurfaceView + `j4` 渲染器 + `SimulationWorld/Gene[]`，用 FloatBuffer/ShortBuffer 程序化绘制真实细胞，带触摸平移/缩放/长按与选中回调；不是静态示意图。详见分析文档 §22。

### 实现

- **光场边缘锯齿**：`FieldLayer` 改为 shader 内解析圆 + `fwidth()` 抗锯齿，圆环也由 shader 绘制，删掉 `draw_arc()` 折线；双线性采样跳过圆外格，避免圆外零值混入边缘形成暗边。
- **食物可见**：新增 `FoodLayer.gd`（只读营养通道 0，按局部对比度显示营养团块亮点）；`main.tscn` 增加 `DishView/FoodLayer`，顶栏新增「食物」开关；`food_spawn_amount` 默认 `0.018 → 0.12`（`EnvironmentManager` 与 `ToolCatalog` 同步）。仍不改五通道 schema，不新建实体池。
- **生态报告**：`PanelChrome.install()` 把标题栏移到 `ChromeRoot` 索引 0（原来排在内容之后，所谓「右上角关闭按钮」实际在面板底部），并监听 `visibility_changed` 同步面板状态；`AnalysisPanel` 新增 6 tick 实时数字（tick / 活体个体 / 倍速）+ 30 tick 采样报告，`refresh_now()` 供测试/外部强制刷新。
- **指令集易用性**：修正 `DIVIDE` 操作数提示（a=母细胞索引、b=角度 0–255、c=亲子间距，原误写成「a=子代类型」）；新增 `instruction_help_text()` 完整说明三种 opcode 与「装载合成器 → 皿内点击放置」流程；新增「单细胞 / 分裂×1 / 分裂×2 / 分裂×3」快捷模板按钮。
- **发育预览**：新增可复用 `scenes/ui/GenomePreview.tscn` + `scripts/ui/GenomePreview.gd`，嵌入统一细胞编辑左栏。按 `dev_program` 逐条派生分裂 / 分化 / 连接状态，支持播放、暂停、上一步、下一步；颜色沿用 `CellVisualCatalog` 角色配色。纯只读视图：不跑第二套模拟、不写 `CommandBus`、不改确定性 hash。

### 边界

- 预览是 `dev_program` 的确定性示意，不复制 Macro 的 `SimulationWorld`/GL 管线，也不把 Macro 的逐基因参数变成运行时物理。
- 食物仍是营养场源项派生的亮点视图，不是 Macro 的 `Food[]` 实体池。

### 验证

- `SmokeTest.gd`：新增脚本清单登记（`SCRIPTS=49`），断言光场抗锯齿与食物亮点、顶栏「食物」开关、chrome 标题栏在顶部、报告 6 tick 内刷新、指令帮助/模板与分裂细胞数、发育预览状态与步进且不污染 GNP1 hash。
- 发布工程与 D 盘运行工程均 `SCRIPTS=49 FAILURES=0 EXITCODE=0`；D 盘同步保留 MCP autoload、脚本 `.uid` 与场景 `unique_id`。

---

## 0.13.0 — 2026-11-17

**类型**：Macro 机制落地 —— 环境设置页 / 空间光照 / 食物源 / 细胞编辑 Macro 字段，并修正光合类型映射
**触发**：用户要求「先查相关代码」，再把 Cell Lab Macro 基因组编辑字段、光照、食物/营养生成与环境设置参考落到 Godot；同时反馈光合细胞在光场中不产能、环境不生成食物。

### 代码证据

- 静态反编译 Macro APK 的 `GenomeEditorFragment` / `Environment` / `Environment.q()` / `EnvironmentEditorFragment` / `Food` / `SimulationWorld.<init>` / `SimulationWorld.y2(double)`，证据与字段映射写入 `analysis/CellLab_细胞物理与外观_代码级分析.md` 第 20 章。APK 未执行。
- 确认 `Environment.q()` = 空间插值 + 64×64 分布图双线性叠加 + `min(1, …)`，用于场采样/预览/行为，不是直接产能公式；Macro 食物是定长 `Food[]` 对象池，本项目不引入第二套实体池。

### 实现

- **类型映射 BUG 修正**：`OrganismManager._apply_environment_metabolism_ranges()` 原把体细胞 `type_id=1` 当光合、肌细胞 `2` 当化能；改为与 `CellVisualCatalog` 一致的光合 `4`、硝化/化能 `10`，异养仍为 `0`。光合细胞现在读取光照通道并真实增能。
- **空间光照**：`EnvironmentField` 新增 `set_channel_values()`，光照通道扩散系数改为 0（照明是静态环境快照，不是 PDE）；`EnvironmentManager` 新增 `light_source_mode / light_range / light_angle_deg / light_falloff`，支持全皿 / 边缘定向点光 / 中心点光。`FieldLayer` 改为 32×32 → 128×128 双线性上采样 + canvas shader 连续渐变，取代粗颗粒方块。
- **食物/营养源**：`EnvironmentManager.apply_nutrient_sources(tick_index)` 按 tick + 常量盐派生确定性位置与团块，向营养通道写入 pending source；不缩放 dt、不使用全局 RNG、不引入 `Food[]`。`Main` 在每次场扩散前调用。
- **环境设置页**：原「培养基」升级为「环境设置」，按食物 / 光照 / 氧气与温度 / 实验条件分组，共 16 行，带 Macro 控件来源 tooltip；加入 `ScrollContainer`。静态证据项（涂层比例、黏度、重力、盐度）明确标记不进物理。
- **细胞编辑 Macro 字段**：统一「细胞编辑」右栏改为可滚动的 `MACRO DRAFT`，新增 26 个草案字段：细胞类型、生成黏附素、Child 1–4 类型与角度、分裂质量 / 角度 / 营养优先级 / 比例、骨架强度、细胞大小、最大/最小连接数、RGB、保持存活、初始细胞等。每个控件 tooltip 标明对应 Macro `Gene` 字段；这些只存面板 Dictionary，**不写 GNP1、dev_program 或确定性 hash**。
- **存档**：`SaveManager` 版本化追加 `environment_settings`，恢复时先应用设置再恢复场通道；五通道 schema 与 `schema_version` 不变。

### 边界

- 逐基因刚度 / 子代质量 / 连接数 / 细胞大小仍是草案，不变成运行时物理参数；若要做必须先修订 v1.0 玩法文档并同步 v2.1 §0.3 / §11。
- `channel_count` 可配置化、第二套 `Food` 实体池、Macro shader 变体与类型一一对应、Macro `A2()` 初始投放位置仍未落地/未确认。

### 验证

- `SmokeTest.gd`：新增光合类型增能、环境设置键与空间光照梯度、食物源确定性与实际注入、渐变光场层 shader、Macro 26 草案字段与「不污染 GNP1 hash」断言。
- 发布工程与 D 盘运行工程均 `SCRIPTS=47 FAILURES=0 EXITCODE=0`；D 盘同步保留 MCP autoload、脚本 `.uid` 与场景 `unique_id`。

---

## 0.12.1 — 2026-11-17

**类型**：光场可视化修复（纯视图）
**触发**：用户再次反馈「光场看不到，希望像 Cell Lab 一样直接看到光照范围」

- **根因**：`GameHUD._register_view_layers()` 用 `../DishView/...` 找光场层；HUD 位于 `UI/HUD`，该路径实际解析到 `UI/DishView`，而 `DishView` 是主节点直接子节点，正确路径是 `../../DishView/...`。因此 `_field_layer` 一直为 null，顶栏「光场」开关从未作用到图层；同时图层默认 `visible_by_default=false`，双重写成不可见。
- `GameHUD`：修正 FieldLayer / SelectionLayer 路径；光场层默认启用；顶栏「光场」toggle 初始值改为读 `FieldLayer.is_enabled()`，不再因 `get_node("@field")` 为 null 而恒显示关闭。
- `FieldLayer.gd`：`visible_by_default=true`、`max_alpha=0.55`；在照亮格子外沿培养皿半径画一条暖色细环，让照明覆盖范围一眼可辨。只读场通道 3，不写模拟状态、不改 tick / hash。
- `main.tscn`：`FieldLayer.visible_by_default = true`。
- `SmokeTest.gd`：断言光场默认可见、HUD 层引用非空、光照通道确有正值、顶栏开关可关可开；D 盘同步保留 MCP autoload 与场景 ID。
- 发布工程与 D 盘运行工程均 `SCRIPTS=47 FAILURES=0 EXITCODE=0`。

---

## 0.12.0 — 2026-11-17

**类型**：编辑器合并 + 诊断解锁 / 关闭按钮修复（表现层 + 纯视图命令，不改模拟与确定性 hash）
**触发**：用户反馈诊断锁定无法解除、生态报告右上角关闭按钮无效；要求细胞编辑与发育编辑合并为单一「细胞编辑」，UI 参考 Cell Lab

### 修复

- `PanelChrome.gd`：标题栏拖动 handler 现在跳过图钉/关闭按钮区域，Button 能完整收到按下-抬起，`pressed` 正常触发（此前拖动逻辑抢走事件，表现为"点了没用"）。
- `GameHUD._on_panel_close()`：关闭按钮同步调用面板 `set_visible_state(false)`，生态报告内部状态与顶栏 toggle 不再失配。
- 诊断解锁三条入口：
  - 诊断工具点空白处 → `INSPECT` 未命中时清 `selection`；
  - `AnalysisPanel` 新增「解除锁定」按钮 → 经 `CommandBus.enqueue(CLEAR_SELECTION)` 并立即 flush（纯视图命令）；
  - `Esc` → Main 经 CommandBus 清 `selection` 与 `last_inspection`。
  - `OrganismManager` 新增 `CLEAR_SELECTION` 工具分支与 `TOOL_TYPES` 登记，只改视图状态，不动物理/能量/hash。

### 编辑器合并

- `scenes/main.tscn`：移除旧 `CellEditorPanel` 内联子树与 `DevEditorButton`；`DevEditorPanel.tscn` 实例改名为唯一 `CellEditorPanel`，保留 `CellEditorButton`「细胞编辑」。删除 `scripts/ui/CellEditorPanel.gd`。
- `scripts/ui/DevEditorPanel.gd` 成为统一编辑器：标题改为「细胞编辑 · CELL EDITOR」；吸收原细胞编辑页的呼吸方式选择、`default_dev_program()`、`get_dev_program/set_dev_program/get_type_id/get_draft` API 与 `(value, index, key)` 操作数写入兼容签名。
- UI 按 Cell Lab 布局与用词组织：`GENE SLOTS · 40 槽`（前 8 槽对应 GNP1 八性状并实时显示数值，后 32 槽只读占位、明确标注 GNP1 冻结）、`DEV · 分化程序 / 指令序列`、`PARAM · 指令参数 / GNP1 八性状`、`REFERENCE · Cell Lab 专有字段（只读证据）`、`DEV TIMELINE`。`dev_program` 仍是唯一发育真相源，写入只经 Apply → GameHUD → CommandBus。
- `GameHUD.gd`：移除发育编辑按钮/面板注册、顶栏「发育编辑」开关与语义 ID；面板 chrome/toggle 只剩单一「细胞编辑」。

### 验证

- `SmokeTest.gd`：SCRIPT_MANIFEST 47 项；新增 40 基因槽、合并入口唯一性、无重复 DevEditor 节点、报告关闭按钮（含图钉固定后）、`CLEAR_SELECTION` / 诊断点空白 / 面板解锁按钮三类解锁断言；原重叠断言改为仅编辑器可见时检查。
- 发布工程与 D 盘运行工程均 `SCRIPTS=47 FAILURES=0 EXITCODE=0`。D 盘同步回填 14 个 `ext_resource uid` + 9 个节点 `unique_id`，保留 MCP autoload，并删除旧 `CellEditorPanel.gd` 及 `.uid`。

---

## 0.11.0 — 2026-11-17

**类型**：UI 调整批次（纯表现层 / 编辑器体验，不改模拟与确定性 hash）
**触发**：用户反馈诊断不会选中细胞、生态报告不实时且不能固定、各面板不能拖动/关闭/重开、发育编辑半透明难读、看不到光场、切换镜头改变视野且各镜头只有颜色差别；询问细胞编辑下方选项用途

### 面板 chrome 与顶栏开关

- 新增 `scripts/ui/PanelChrome.gd`：给任意 `PanelContainer` 注入统一标题栏（拖动把手 + 图钉 + 关闭按钮），把原有内容节点重挂到 `ChromeRoot` 下，不改脚本逻辑。信号 `close_requested()` / `pin_toggled(pinned)`。
- `GameHUD.gd`：新增 `_build_panel_chrome()` 为 ToolDock / SubstratePanel / MicroscopePanel / SpeedPanel / CellEditorPanel / DevEditorPanel / AnalysisPanel / Minimap 安装 chrome；`_build_panel_toggles()` 在顶栏生成对应开关，关闭后可重新打开；`_on_panel_close()` 同步复位开关；新增 `_process()` 与面板 `visible` 对账，避免编辑器内部「关闭/Apply」按钮与顶栏 toggle 失配。
- `AnalysisPanel.gd`：图钉固定后 `R` 键不再关闭，仍可点标题栏关闭按钮；`set_visible_state()` 与顶栏开关共用状态。
- `scenes/ui/DevEditorPanel.tscn`：加不透明 `StyleBoxFlat`（深青底 + 青色描边），替换原先半透明底，解决阅读吃力。
- `SmokeTest.gd` 深层路径随 `ChromeRoot` 更新（GameHUD 内部引用在 `_ready()` 已缓存，不受重挂影响）。

### 诊断选中 / 报告实时 / 光场可见

- `OrganismManager.gd`：`INSPECT` 命中后写 `selection = [index]`（视图侧派生，不改模拟）。新增 `scripts/rendering/SelectionLayer.gd` 读 `selection` 画圆环 + 四向刻度，监听 `tick_advanced` / `command_executed` 刷新。
- `AnalysisPanel.gd`：每 30 tick 刷新一次生态报告，仅在可见时刷新；诊断段每次刷新读取最新 `get_last_inspection()`。`scenes/main.tscn` 新增 `SelectionLayer` 节点。
- 新增 `scripts/rendering/FieldLayer.gd`：只读 `EnvironmentManager.field` 通道 3，按格画半透明暖色格阵；默认关闭，顶栏「光场」开关可开可关，不改场数据。

### 镜头滤镜（只改滤镜、不改视野）

- `GameHUD.gd`：`_build_tint()` 改为 `canvas_item` + `unshaded` shader（`filter_color` / `strength` / `scanline`），挂为视口滤镜。
- `_on_lens_pressed()` 不再写 `camera.zoom` / 位置；默认 / 宽视野 / 高倍目镜 / 融合镜 / 偏振镜各有不同颜色、强度与扫描线参数，切换保持当前平移缩放。SmokeTest 断言「切换镜头 zoom 不变、参数互不相同」。

### 编辑器分工说明

- `CellEditorPanel.gd`：标题改为「单细胞组型 / 呼吸 / 类型」，并给下方 `DEVELOPMENT · 多细胞发育程序` 加 tooltip：该区是 `dev_program` 的紧凑表（DIVIDE 子代类型/角度/间距、DIFFERENTIATE 索引/目标类型、LINK 两端/静息长度），与顶栏「发育编辑」编辑同一份草案；完整可视化集中在发育编辑页。

### 验证与同步

- `SmokeTest.gd`：3 个新脚本加入 SCRIPT_MANIFEST，新增 `_check_ui_chrome_and_filters()`（chrome 存在、图钉 meta、开关关/开、关闭按钮复位 toggle、INSPECT 写 selection、FieldLayer 默认关闭且通道 3、镜头不 zoom 且参数不同）。
- 发布工程与 D 盘运行工程均 `SCRIPTS=48 FAILURES=0 EXITCODE=0`。D 盘同步保留 MCP autoload，并把 15 个 `ext_resource uid` 与 30 个节点 `unique_id` 从原场景回填到新版场景。

---

## 0.10.0 — 2026-11-17

**类型**：阶段 11 — 生命周期可见化 + 工具闭环 + 发育编辑器 Godot 落地
**触发**：用户反馈细胞不耗能/不分裂/不死亡、光照未生效；光学镊子拖拽中断、诊断无信息、黏附连接难用、颜色/信号注射不可选；发育编辑器从 HTML/SVG 规格稿落到 Godot

### 生命周期（可见化，不缩放 dt）

- `OrganismManager.gd`：
  - 基础代谢从 `0.001*dt` 提到 `base_metabolic_cost=0.006`，并新增 `_apply_base_metabolism()`（WorkerThreadPool 静态分区、能量归零触发 `DEATH_STARVATION`）。
  - `_apply_environment_metabolism()` 接入五场通道：类型 0 吃营养[0]、类型 1 光合吃光照[3]、类型 2 化能吃信号[4]；呼吸效率与运动耗能保留。
  - 新增 `_apply_autonomous_lifecycle()`：成熟个体按「能量阈值 + cooldown + 首次资格宽限期」确定性分裂（角度由 `cell_index/_sim_tick` 派生，不用全局 RNG），上限 `autonomous_max_cells_per_organism=8`，间隔 300 tick。宽限期保证发育程序 9 指令→4 细胞/3 连接的确定性快照不被当 tick 分裂破坏。
- `EnvironmentField.gd`：新增 `fill_channel(channel, value)`，整通道填充只上传一次 GPU 缓冲。
- `EnvironmentManager.gd`：新增 `light_intensity`（默认 0.6）与 `apply_light_intensity()`，bind_preset 默认值写入通道 3（DECAY[3]=0，光合可持续取用）。此前光照通道恒 0。
- `ToolCatalog.gd`：光照强度由「仅 UI 占位」改为可写；`GameHUD._on_substrate_changed()` 改动后调用 `apply_light_intensity()`。

### 工具闭环（外部干预，不进确定性 hash）

- 光学镊子拖拽：`Main.gd` 新增 `InputEventMouseMotion` 连续处理，按住左键且当前为拖拽型工具（DRAG/旋转选区/地形笔刷/橡皮）时逐 motion 事件经 CommandBus 入队；`GameHUD.is_drag_tool()` 判定工具类型。修复「点击后只能移动一小段」。
- 细胞诊断：`OrganismManager.INSPECT` 写入 `last_inspection`（索引/org/tick/能量/类型/位置/半径/连接/物种/年龄/健康/五通道场采样）与 `get_last_inspection()` getter；`AnalysisPanel.gd` 新增诊断段，INSPECT 命中后由 `Main` 自动弹出面板显示逐项状态（参考 Cell Lab）。
- 黏附连接：`ADHERE` 改为两枚细胞点击式建链（首点存 `adhesion_anchor`），静息长度 `max(14, 2r)` 不小于碰撞直径；成功/失败写 `last_tool_message`，HUD 实时反馈。
- 颜色注射：`INJECT_COLOR` 读取命令 `color_type`（0–17 官方类型），不再轮转；`GameHUD` 注射参数行提供类型下拉。
- 信号注射：`INJECT_SIGNAL` 读取 `signal_channel`（0–4）与 `signal_amount`；`EnvironmentManager.add_channel_source()` 按选定场通道注入 source。注射参数行提供通道下拉 + 注入量 SpinBox。

### 发育编辑器 Godot 落地（阶段 11）

- 新增 `scenes/ui/DevEditorPanel.tscn`（节点声明骨架）+ `scripts/ui/DevEditorPanel.gd`（三栏 + 底部时间轴）：A 分化程序指令序列（增删/上下移/选中）、B 指令参数（opcode/a/b/c 双向写回 dev_program）+ GNP1 八性状、C 规格参考（只读展示 Cell Lab 专有的 40 Gene 槽/Child1–4/信号 lane/95 算子，**不写入冻结 GNP1**）、DEV TIMELINE（指令按 tick 顺序，仅 UI 不缩放 dt）。
- `DevEditorPanel.draft_applied` → `GameHUD._on_draft_applied()` → 装载合成器 → CommandBus → 皿内放置，闭环复用现有命令通道。
- `main.tscn` / D 盘运行工程新增 `DevEditorButton`（顶栏「发育编辑」）与 `DevEditorPanel` 实例；GameHUD 语义 ID `ui://sim/dev-editor/toggle`。D 盘同步保留其 MCP autoload、脚本 `.uid` 与场景 `unique_id`。
- 设计约束遵循规格稿：GNP1 已冻结，dev_program 是唯一发育真相源；Cell Lab 专有字段只作证据展示，不臆造、不进编码。

### 验证

- `SmokeTest.gd`：新增 `_check_lifecycle_and_injectors()`（光照通道非零、基础代谢耗能、信号注射通道落地、颜色注射精确写入、INSPECT 字段完整、ADHERE 静息长度、DRAG 工具识别）与 `_check_dev_editor_landing()`（节点骨架、三栏控件、dev_program 双向编辑增删、Apply 发合法草案、main.tscn 接线）。新增脚本登记入 SCRIPT_MANIFEST。
- 发布工程与 D 盘运行工程均 `SCRIPTS=45 FAILURES=0 EXITCODE=0`。
- 删除临时诊断脚本 `tools/LifecycleDiag.gd` 与启动冒烟 `tools/BootSmoke.gd`（仅验证用，不发布）。

---

## 0.9.1 — 2026-11-17

**类型**：UI 布局修复 + 发育编辑器规格稿（文档/前端，不改模拟）
**触发**：用户反馈 SubstratePanel 的 Title 与培养基 UI 重叠；要求参考 Cell Lab Macro 先做发育编辑器 HTML/SVG

### 落地

- `scenes/main.tscn`：移除 `SubstratePanel/Panel/Title` 节点。原 `PanelContainer > MarginContainer` 下同时放 Title 与 SubstrateRows，两个子节点被 MarginContainer 叠在同一区域，导致文字与控件重叠；原说明改为 SubstratePanel 的 `tooltip_text`。
- `SmokeTest.gd`：新增「SubstrateRows 存在且有子节点、Title 节点不得存在」断言。发布工程与 D 盘运行工程均 `SCRIPTS=44 FAILURES=0`。
- 新增 `preview/dev_editor_preview.html`：单文件 HTML + 内联 SVG 的发育编辑器 UI 规格稿。包含 40 Gene 槽/分化树、Gene 参数（Child 1–4、on-contact、数值滑块、RGB）、dev_* 发育规则、信号 lane、GNP1 八性状、0–48h 时间轴与证据抽屉。
- 该稿明确标注：四标签页划分是提案；Cell Lab 原生快捷键未确认；40 modes（UI）≠ 40 Gene 槽（运行时）；时间轴只表达 dev_program，不缩放 dt。
- `analysis/CellLab_细胞物理与外观_代码级分析.md` 新增 §13 界面证据与规格稿差距、§14 待确认边界、§15 后续阶段路线（11–16）。

---

## 0.9.0 — 2026-11-17

**类型**：阶段 10 — 完全 GPU 采样迁移（架构变更）
**目标**：扩散结果驻留 GPU，取消每 tick 全量场回读；保留 CPU 回退与存档/快照语义

### 实现

- `EnvironmentField.gd`：
  - 新增两个 compute pass：`SAMPLE_SOURCE` 按细胞位置做与 CPU `_cell_index()` 等价的最近格采样，一次 dispatch 写出 N×5 个 float；`DELTA_SOURCE` 把消费量 scatter 回场缓冲。
  - `diffuse_tick()` 不再调用 `_read_active_buffer()`；只在显式 `set_value()` / `paint_terrain()` 编辑、快照、hash、存档和诊断时惰性回读。
  - `consume()` 在 GPU 后端改为「查采样缓存 → 聚合 (格,通道) 增量 → 下一 tick GPU delta pass」，CPU 后端保持原路径。
  - 新增 `sample_cells(positions)` 批量 API 与 `clear_runtime_caches()`；`SaveManager.restore()` 恢复后清理采样缓存和未提交增量。
  - 诊断新增 `gpu_sample_count / gpu_sample_cells / gpu_delta_count / gpu_full_readback_count / legacy_full_field_bytes / gpu_sampling_active`；`readback_bytes` 改为每 tick 实际采样回读字节。
- `EnvironmentManager.gd`：新增 `begin_field_sampling(positions)`，缓存本批结果；`sample_fields()` 优先命中缓存。
- `OrganismManager.gd`：每 tick 在物理前、物理后各做一次批量采样，替代原先每细胞两次逐点采样。
- 新增 `tools/GpuSamplingTest.gd`；SmokeTest 登记该脚本并加入批量采样 API / CPU 回退一致性断言。

### 验证

- 无头 CPU 回退：`SCRIPTS=44 FAILURES=0`、退出码 0。
- 窗口 Vulkan（RTX 3050 Laptop）：`SCRIPTS=44 FAILURES=0`；`GpuSamplingTest PASS`，采样误差 `5.96e-8`，消费后全场误差 `6.10e-5`，每 tick 回读 **80 B**（旧方案 20 KB @ R=32，80 KB @ R=64）。
- `GpuFieldParityTest` 通过，最大误差 `3.05e-5`（温度通道，与历史基准一致）；`GpuThroughputTest` GPU `1371 µs/tick`、CPU `68.2 ms/tick`，GPU 回读 0。
- 上限：单批最多 4096 个采样细胞、8192 条聚合增量；超过则回退逐点采样，仍不增加全量场回读。

---

## 0.8.14 — 2026-11-17

**类型**：细胞未接触先变形的视觉修复（纯视觉层）
**触发**：用户反馈细胞碰撞过多时，膜在尚未接触前就压平/切平

### 根因

`CellSceneRenderer._rebuild()` 把浅压平的接触范围写成 `radius * 2.0 + 1.0`（半径 7 时为 15，即相隔 1 世界单位就压平），皿壁范围写成 `max(1.0, radius * 0.8)`（相隔最多 5.6 单位就压平）。于是两细胞明明还有可见间隙，朝对方的膜已经被 `_flatten_contacts()` 拉平，视觉上就是"接触前先提前变形"。

无头诊断确认：默认演示体 600 tick、强制 8 枚细胞重叠成一团 180 tick，物理层均能在 1 tick 内分离到 ≥ 2r，**没有**残留重叠；问题只在视觉派生范围。

### Godot 落地（不改物理 / 不改确定性 hash）

- `CellSceneRenderer.gd`：细胞接触范围收紧为 `2r + CHORDS.contact_epsilon(r)`，皿壁范围收紧为 `CHORDS.contact_epsilon(r)`；半径 7 时均为 0.07，只覆盖数值抖动与真实接触。
- `SmokeTest.gd`：新增「gap=1 不产生接触方向、gap=0 产生」「距壁 1 不产生壁接触、贴壁产生」断言；更新原多细胞协作测试，使皿壁断言从 gap=1 改为真正贴壁。
- 验证：发布工程 `SCRIPTS=43 FAILURES=0`、退出码 0。
- 同步：`CellSceneRenderer.gd` / `SmokeTest.gd` 复制到 `D:\Tools\Godot_v4.7.2\project\cellarium`，保留其 UID 与 MCP 插件配置。

---

## 0.8.13 — 2026-11-17

**类型**：接触弦阈值抖动导致的持续闪动修复（纯视觉层）
**触发**：用户反馈 v0.8.12 之后多细胞簇「一直在闪动」，两张截图分别显示有弦切平与无弦整圆交替出现

### 根因定位（程序化诊断，非推测）

- 临时场景诊断脚本逐 tick 调用真实的 `advance_development_tick()` → `advance_physics_tick()` → `CellSceneRenderer._rebuild()`，记录默认 4 细胞协作体 180 tick：
  - 细胞中心最近距离始终在 `13.9998 … 14.0000` 之间（float32 抖动约 ±4e-4）；
  - 共享弦数量却在 `0 / 2 / 4 / 6` 之间切换 **84 次**。
- `CellContactChords.circle_chord()` / `wall_chord()` 原阈值是 `s < r0+r1−1e-6` / `s+r > R+1e-6`。碰撞把中心钳在恰好相切处，1e-6 的阈值远小于数值抖动，于是弦逐 tick 生成/消失；`CellView` 随即在「64 点整圆 + 浅压平」与「弦裁剪多边形」之间跳变。这就是截图中的闪动，而不是膜路径或物理碰撞本身。

### Godot 落地（不改物理 / 不改确定性 hash）

- `CellContactChords.gd`：新增 `contact_epsilon(radius) = maxf(0.02, radius * 0.01)`；圆-圆与皿壁弦改用该下限判定接触。半径 7 时阈值 0.07，约为实测抖动的 175 倍；真实重叠 > 0.07 仍正常生成弦。
- 贴壁细胞在阈值内不生成壁弦，改由既有浅接触压平提供稳定形变；真正越过皿壁才切平。
- `SmokeTest.gd`：新增相切抖动（±1e-4 / ±5e-4）不得生成圆弦与壁弦、真实重叠 0.5 必须生成弦的断言；新增 60 tick 场景级断言——最近距离 ≥ 2r−0.01 时弦数量必须为 0。
- 验证：修复前同一诊断 `chord_switch=84`，修复后 `chord_switch=0`；发布工程 `SCRIPTS=43 FAILURES=0`、退出码 0。
- 同步：`CellContactChords.gd` / `SmokeTest.gd` 已复制到 `D:\Tools\Godot_v4.7.2\project\cellarium`；保留其 UID 与 MCP 插件配置，未覆盖 `project.godot` / `main.tscn`。

---

## 0.8.12 — 2026-11-17

**类型**：接触轮廓循环多边形化 / 消失的根因修复（视觉层）
**触发**：用户连续截图反馈「一接触就 多边形化 → 消失 → 重建 → 多边形化」循环，并给出两种方案：①接触用弦膜、非接触保留弹性膜；②直接去掉弹性膜路径

### 根因定位

- 用户实际运行的 `D:\Tools\Godot_v4.7.2\project\cellarium` 仍是 v0.8.10 代码：`CellView.gd` 主路径调用 `build_outline(prepared, 3)`，`CellContactChords.gd` 没有 `clip_unit_circle()`，`clip_keep_origin()` 在结果少于 3 点时返回**未裁剪输入**。少量接触时只能得到 5–15 个顶点，退化时 `Polygon2D` 顶点不足而不可见，只剩细胞核/细胞器点；弦消失后切回 72 点呼吸膜，于是形成截图中的循环。
- 即使已发布的 v0.8.11 也仍有隐患：有弦时用 64 点解析圆裁剪，无弦时用 72 点呼吸膜，两套点集在接触边界切换；`clip_keep_origin()` 的“返回未裁剪输入”会让轮廓在退化帧突然跳回整圆。
- Cell Lab 的外膜并不存在独立呼吸几何：相位只参与着色，外形由物理半径与共享弦端点决定。方案 ①（同一细胞内混用弹性弧与弦段）会重新引入相位/端点不一致，因此采用方案 ② 的统一路径。

### Godot 落地（仅视觉层）

- `CellContactChords.gd`：新增 `unit_circle(64)` 作为统一外膜基底；`clip_keep_origin()` 退化时返回空数组；`clip_unit_circle()` 跳过退化弦，保留上一帧有效凸多边形，绝不回退到未裁剪输入。
- `CellView.gd`：外膜不再调用 `_membrane.outline()`；始终从 64 点解析圆开始，有弦时按 Cell Lab 顺序裁剪，无弦时仅做浅接触压平。内膜按同一轮廓缩放，避免穿出压平边界。`_stretch` 状态保留给 API/测试，但不再施加到共享边界，以保证双方共边。
- `SmokeTest.gd`：新增「移除/恢复弦时点集不切换、无弦轮廓 ≥64 点且面积非零」断言；有弦轮廓点数下限从 4 提高到 48。
- 验证：发布工程与用户运行工程均 `SCRIPTS=43 FAILURES=0 EXITCODE=0`。
- 同步：`CellView.gd` / `CellContactChords.gd` / `SmokeTest.gd` 已复制到 `D:\Tools\Godot_v4.7.2\project\cellarium`，保留该目录的 MCP 插件配置与场景 UID，未覆盖 `project.godot` / `main.tscn`。重新运行场景即可生效。

---

## 0.8.11 — 2026-11-17

**类型**：接触轮廓多边形化残留修复（视觉层）
**触发**：用户反馈 v0.8.10 之后「bug 还在」，截图中细胞膜仍呈可见多边形

### 根因定位
- 几何诊断（`tools/OutlineDiag.gd`，验证后已删除）显示：2 条接触弦时 `build_outline()` 只产出 10 点、3 条时 15 点；同场景 `clip_unit_circle()` 产出 48 / 39 点，面积更接近解析圆。
- v0.8.10 把 `clip_unit_circle()` 仅作为退化回退，主路径仍走「弦端点 + 解析圆弧」。接触数少时采样点过于稀疏，视觉上就是六边形/多边形，并非弦几何本身错误。

### Godot 落地（仅视觉层）
- `CellView.gd`：有弦时主路径改为 `make_unit_chords()` → `prepare_for_render()` → `clip_unit_circle(..., 64)`，对解析单位圆做半平面裁剪，保证接触轮廓始终有 39–64 点平滑圆弧；不再用呼吸膜或稀疏端点直线重建。无弦时保留原弹性膜 / 法线压平路径。
- `SmokeTest.gd`：新增接触轮廓点数 ≥ 24 断言；相切场景改为显式 SPAWN 两枚间距 2r 的细胞（`create_demo_organism = false`），消除演示体发育时序导致的 flake。
- 验证：源码连续 2 次 `SCRIPTS=43 FAILURES=0 EXITCODE=0`。
- 约束：只改视觉派生；不写 tick 状态、不改物理、不改确定性 hash。

### 附：Macro APK 边界确认（同期完成，仅文档）

- APK `cell-lab-macro-beta-latest.apk`（SHA256 `9d0f3509…8a1a`）静态反编译，未执行：
  - 通道数 `0x65 = 101`，`H8` 构造校验保留，故 `channel_count` 必须可配置。
  - `SimulationWorld.x()` 完整 1662 行逐行扫描：共享弦相交截断 → `0 < d26 < 1` 遮挡剔除 → `Arrays.sort()` → 端点+圆弧重建，与官方版同构；`Y8.compareTo()` 排序键同构；皿壁/地形壁弦 `g = -1`。
  - `Cell.f(5)` = `Gene.r0[5]` 在 `SimulationWorld.f1(double)` 中无条件写入两条 `AdhesinLink.l`；`w1/x1` 的 `f(6)` 仍为接触刚度。
  - 主体细胞 shader 保留 `dot(p,p) > col.a² → discard` 圆裁剪，但 Macro 扩展了纹理/光照/培养皿形状变体，**不完全同构**，不移植资源。
- 结论写入 `analysis/CellLab_细胞物理与外观_代码级分析.md` §8 / §11；工程代码无需改动。

---

## 0.8.10 — 2026-11-17

**类型**：细胞膜多边形化 / 消失回归修复（视觉层）
**触发**：用户连续截图反馈「细胞膜快速变换，由圆形变成多边形，甚至消失」

### 根因定位
- 用诊断几何复现：3 个深重叠接触（中心距 ≈ 半径）时轮廓塌缩成 2 点、面积为 0；5–6 接触时输入顺序置换会让轮廓点数与顶点不一致。
- Cell Lab `CellWorld.a(FFFF)` 的 `A[]` 按邻居索引升序写入；Godot 侧直接吃空间哈希邻居顺序，而 `truncate_intersections()` 会原地改写端点，顺序变了结果就变。
- Cell Lab 用 `A[i].f` 标记被截断弦并跳过圆弧插值；Godot 侧记录了 `truncated` 却没用，导致截断端点之间仍插出交叉圆弧。
- 皿壁弦复用 `circle_chord()` 的外交判据，小圆完全在大圆内时被误判为无交，贴壁时几乎不产生共享弦。
- 复核 `d17` 与 `d26` 的符号：原式 `cross(v16, Q14−P16) < 0` 与 `d26 = cross(P18,v18)/cross(P17,v18) ∈ (0,1)` 与 Cell Lab 方法体一致，未修改。

### Godot 落地（仅视觉层）
- `CellContactChords.gd`：
  - `prepare_for_render()` 先按 `(kind, peer)` 规范输入顺序，再执行截断 / 遮挡 / 排序；等价 Cell Lab 的邻居索引顺序。
  - 过滤截断后零长度弦；`build_outline()` 尊重 `truncated` 标记，跳过其圆弧（改为直连下一端点以保持闭合）。
  - 新增 `polygon_area / contains_origin / canonicalize_points / clip_unit_circle`；轮廓退化时回退到解析单位圆半平面裁剪，保证永不消失。
  - `wall_chord()` 改用「小圆在大圆内侧」的解析相交式，`s > R − r` 时生成皿壁共享弦。
- `SmokeTest.gd`：新增多接触顺序置换逐点一致、深重叠轮廓面积/中心包含、皿壁弦有效性、连续 30 tick 所有膜轮廓闭合且面积非零断言。
- 验证：源码 `SCRIPTS=43 FAILURES=0 EXITCODE=0`。
- 约束：只改视觉派生；不写 tick 状态、不改物理、不改确定性 hash。

---

## 0.8.9 — 2026-11-17

**类型**：共享弦抽搐修复 + Cell Lab 视觉对齐代码级确认
**触发**：用户反馈「使用弦裁剪后接触点的弦会抽搐」，要求查 Cell Lab 相关代码、确认物理碰撞与视觉是否对齐、不改变模拟结果或确定性 hash，并确认仍需证据的边界

### 代码研究（APK 静态反编译，未执行）
- `CellWorld.i()` 每 tick 清零 `cell.B`；`c(boolean,double)` 设置 `U=z` 后逐细胞 `d(i)`；`d(int)` 在同一相交计算里同时产生力与 `A[]` 弦端点。
- `CellWorld.a(FFFF)` 使用精确 `cell.d` 与 `A[]` 端点构建顶点，圆弧解析插值；`cell_vert.glsl`/`cell_frag.glsl` 的相位 `tp` 只参与着色，不改几何。
- `u.compareTo()` 排序键 = 遮挡弦置末 + `b` 符号分组 + `a/b` 降序（等价极角 `[0,2π)` 升序）。
- `Gene.v[5]` 消费点 = `CellWorld.e(double)` 分裂建链时的 `link.l` 长度参数；不是行为总线槽。
- 相交截断与遮挡剔除都在 `Arrays.sort()` 之前，均为 O(B²)，不能优化为排序后相邻检查。
- 完整证据与结论见 `analysis/CellLab_细胞物理与外观_代码级分析.md` §7/§9/§10。

### Godot 落地（仅视觉层）
- `CellContactChords.gd`：新增 `make_unit_chords / truncate_intersections / mark_occluded / chord_less / sort_chords / prepare_for_render / build_outline`；端点顺序改为 Cell Lab `A[]` 的 endpoint1/endpoint2；按「相交截断 → 遮挡剔除 → 排序 → 端点+解析圆弧」重建轮廓。
- `CellView.gd`：有弦时直接采用重建轮廓，不再用 20fps 呼吸膜做顺序相关半平面裁剪；无弦时保留原弹性膜/法线压平路径。
- `SmokeTest.gd`：新增输入顺序置换不变、呼吸相位不变、弦端点即膜顶点、`get_state_hash()` 渲染前后不变断言；原轮廓点数阈值改为按有无弦区分。
- 验证：源码 `SCRIPTS=43 FAILURES=0 EXITCODE=0`，连续 3 次通过。
- 约束：所有改动只读 SoA，不经过 `CommandBus`，不写 tick 状态；物理与确定性 hash 不变。

---

## 0.8.8 — 2026-11-17

**类型**：Cell Lab 三项边界确认 + 共享弦端点贴合落地
**触发**：用户要求「确认三个边界（a(6) 刚度映射 / Cell.a(int,int) 行为总线 / 弦求交剔除三角判据），写入文档，最后实际落地」

### 代码研究（APK 静态反编译，未执行）
- `Cell.a(int)` = `I[D].v[i]` 直读：`a(6) == Gene.v[6]`，范围 `0.5..2`，即接触刚度（修正旧报告把它猜成"分裂成本"的表述；分裂成本是另一处用法）。
- `Cell.a(int,int)` = 调制输出总线：8 个输入源（4 信号通道 + 能量比 + 年龄 + 浓度 + 连接数）、2 种映射（线性/阈值）、11 个输出槽值域全部还原。
- 弦剔除三角判据：`d26 = cross(P18, v18)/cross(P17, v18)`，`0<d26<1` 为遮挡；线段参数 `d15/d16` 与标准 cross 交点式逐位等价（5 组随机样本数值验证）。
- 完整证据与映射表见 `analysis/CellLab_细胞物理与外观_代码级分析.md` §6。

### Godot 落地
- 新增 `scripts/rendering/CellContactChords.gd`（RefCounted、无 class_name、preload）：圆-圆相交弦、皿壁弦、Sutherland-Hodgman 半平面裁剪、`d26` 遮挡剔除。
- `CellSceneRenderer.gd`：每对重叠细胞只算一次弦，两个世界坐标端点**原样分发双方**；皿壁弦单独生成；新增 `get_last_chord_count()`。
- `CellView.gd`：新增共享弦路径——轮廓按弦内侧裁剪，双方膜在接触处共边（Cell Lab `A[]` 机制）；无弦时保留原法线压平路径；新增 `get_chord_count()`。纯视图派生，不写模拟状态、不参与确定性 hash。
- SmokeTest：登记新脚本，新增端点几何/遮挡判据/双方端点逐位一致/相切不产弦断言。
- 验证：源码 `SCRIPTS=43 FAILURES=0 EXITCODE=0`（连续 3 次）。

### 边界
- 弦裁剪只用于近景 `CellBase.tscn` 视图层；远景 MultiMesh LOD 不变。
- 物理仍用独立圆碰撞，`CellShape.REST_RADIUS` 唯一真相源未改；共享弦只对齐视觉，不改变模拟结果。

---

## 0.8.7 — 2026-11-16

**类型**：同个体自碰撞修复 + 性能与 GPU 深化
**触发**：用户反馈「没有自碰撞不太对，被其他细胞撞到细胞发生位移还是会重叠」，并要求「完成这个之后做性能与 GPU 深化」

### 自碰撞与连锁重叠

- `CellPhysics.build_collision_pairs()` 不再因 `org_id` 相同跳过；所有活细胞按同一半径参与分离，Link 静息长度仍等于静息直径 14。
- `resolve_collisions()` 改为最多 6 轮确定性位置修正，每 3 轮重建一次空间哈希 pair；收敛阈值 0.001。解决“外细胞把 A 推进同簇 B，单轮旧 pair 已处理完，A/B 仍重叠”的连锁问题。
- 同步修订 `docs/Godot项目技术设计文档.md` §4.4/§4.5：同生物内部细胞也参与分离，不再写“跳过自碰撞”。
- SmokeTest 将旧“同 org 跳过”断言改为同 org 必须分离，并新增三细胞连锁重叠收敛断言。

### 性能深化

- 行为热路径新增零分配接口：
  - `CellBehavior.collect_inputs_into()` / `evaluate_into()` / `compute_outputs_flat()` / `apply_outputs_flat()`；
  - 输入、隐层、输出、intents 全部复用调用方缓冲，不再每 tick 为每枚细胞创建临时 `PackedFloat32Array`。
- `OrganismManager._build_behavior_environment()` 用 `Array[Array]` 取代 `Dictionary[int → neighbors]`，减少邻域热路径哈希查找；旧 `_compute_behavior_outputs()` 仍保留供测试与兼容。
- SmokeTest 断言扁平热路径与旧逐细胞输出逐位一致（同输入/同权重/同顺序）。
- BenchTest 三档结果（headless CPU，120 tick 上限 / 3000 档墙钟保护提前停止）：

| 生物数 | avg tick | behavior | physics | 预算 |
|---:|---:|---:|---:|---|
| 300 | 18.0 ms | 7.85 ms | 7.87 ms | 未达 |
| 1000 | 64.6 ms | 28.3 ms | 29.4 ms | 未达 |
| 3000 | 204.7 ms | 89.6 ms | 96.2 ms | 未达 |

- 结论：零分配改造保持数值等价、未引入回归；headless CPU 仍未达 §8.1 预算，真实运行应走 GPU 场与 LOD，不通过缩放 dt 或提高单帧 12 tick 上限来“刷”指标。

### GPU 深化

- `EnvironmentField` 增加分项诊断：`gpu_tick_count` / `gpu_fallback_count` / `gpu_upload_usec` / `gpu_dispatch_usec` / `gpu_readback_usec` / `gpu_avg_tick_usec` / `dispatch_groups` / `readback_bytes`。仅观测，不改场数值与确定性。
- 新增 `tools/GpuThroughputTest.gd`：窗口 Vulkan 下以 64×64 五通道场跑 200 tick，输出 GPU/CPU 吞吐和后端诊断。
- 实测 RTX 3050 Laptop GPU：

| 后端 | 200 tick 墙钟 | 每 tick |
|---|---:|---:|
| gpu_compute | 470 ms | 2.35 ms |
| cpu | 12,191 ms | 60.95 ms |

- GPU 约快 **25.9×**；分项为 upload 141.6 ms / dispatch 37.0 ms / readback 148.6 ms，说明当前主要成本在缓冲上传与每 tick 回读，而不是 compute dispatch。dispatch groups = `(8,8,5)`，每 tick 回读 81,920 bytes。
- `GpuFieldParityTest` 复验通过：两 tick 最大误差 `3.05e-5`（温度通道量化差），皿外值 0，EXITCODE=0。

### 验收

- SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`。
- BenchTest：`FAILURES=0`；三档数据如上。
- GPU parity 与 throughput 均在窗口 Vulkan 下完成，无截图/人工干预。

### 边界

- GPU 仍每 tick 回读 80KB，以保持 CPU 侧采样契约；吞吐收益已显著，但回读仍是主成本，进一步优化需要把采样/行为完全搬到 GPU，属于后续专项。
- 同个体细胞现在物理分离，但连接内经济、角质 shielding、4 通道信号传播仍未实现。
- 单帧 12 tick 上限与固定 dt 均保持不变。

---

## 0.8.6 — 2026-11-16

**类型**：演示体重叠修复 + 多细胞编辑闭环
**触发**：用户反馈「默认演示体的细胞重叠了」「多细胞编辑是不是还没做」

### 演示体重叠修复

- 根因：同个体细胞按 v2.1 §4.5 跳过自碰撞，而 `DIVIDE` 指令默认只把子细胞分开 1 单位；连接求解在三个子细胞几乎重合时按顺序修正，把它们挤到同一侧。实测子细胞 1/2/3 曾聚集在 `(254.6, 249–252)`，彼此约 1.6 单位，明显重叠。
- `DevelopmentRules.execute_instruction()` 现在把 `DIVIDE` 指令的 `c` 复用为分裂间距（世界单位，`0` 沿用旧默认 1）；默认演示体的三条分裂指令改为 `c=14`，与 `LINK` 静息长度一致。
- 复测 30 tick 后四枚细胞位于 `(252,250) / (267,250) / (246,262) / (259,238)`，所有 Link 距离 14，任意两活细胞最小中心距 ≥ 14；SmokeTest 加入该断言，防止回归。

### 多细胞编辑闭环

- `CellEditorPanel.gd` 从单细胞编辑升级为细胞 / 多细胞编辑页：
  - 面板内容改成 `ScrollContainer`，TraitRows / 类型 / 呼吸 / 装载按钮下移，新增“DEVELOPMENT · 多细胞发育程序”区。
  - 发育程序以可编辑指令行呈现：`DIVIDE / DIFFERENTIATE / LINK` + A/B/C 三个操作数 + 删除按钮；可添加指令（上限 64）。
  - `DIVIDE.c` 是分裂间距，`LINK.c` 是连接静息长度；`DIFFERENTIATE.b` 是目标类型 ID。
  - 提供“4 细胞模板”和“单细胞”两个快捷按钮，以及实时预览（细胞数 / 连接数 / 分化类型标签）。
  - “恢复默认”现在载入 4 细胞协作模板，与默认演示体一致。
- 编辑后的 `dev_program` 通过 `draft_applied → HUD.set_draft → CommandBus → SPAWN` 完整往返；SmokeTest 验证 GNP1 编码/解码后指令数组一致，并能发育出 4 细胞 / 3 连接且不重叠。

### 验收

- 源码 SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`。
- 新增断言：演示体活细胞最小中心距 ≥ 静息直径；编辑器默认模板、清空、模板恢复、添加/删除指令、操作数修改；经合成器落地后发育程序一致且发育结果不重叠。

### 边界

- 这是发育指令级编辑，不是 Cell Lab 的 40 槽分化树或完整突变算子编辑；角色/类型沿用现有 18 种词条。
- 尚未提供指令拖拽排序与可视化谱系图；当前用 A/B/C 数值和实时预览编辑。
- 连接内经济、角质 shielding、化学信号沿连接传播仍未实现。

---

## 0.8.5 — 2026-11-16

**类型**：接触形变修正 + 皿壁贴附 + 多细胞协作表现
**触发**：用户反馈「细胞碰撞的形变有点奇怪」「贴壁细胞的触壁细胞膜没有形变」，并要求「可以做多细胞协作表现了」

### 接触形变修正

- 旧版 `_flatten_contact()` 按角度缩放半径，接触处形成深 V 形凹口。新实现把接触弧顶点投影到切平面：中心区保持浅而平的接触面，边缘用 smoothstep 过渡，避免尖角与过度凹陷。
- 接触来源拆成三类并使用不同深度：普通碰撞 `0.09`、同个体黏附连接 `0.15`、皿壁锚定 `0.13`（均为相对半径）。外膜与内膜同步压平。
- `CellSceneRenderer` 复用空间哈希，同时读取 `link_cell_a/link_cell_b`，把同个体且已有 Link 的邻居归为黏附，其余归为普通碰撞；两者分别传给 `CellView.apply_cell()`。

### 皿壁贴附

- 渲染层从 `OrganismManager.dish_center/dish_radius` 派生皿壁方向；细胞中心距离壁面小于 `radius * 0.8` 时，传入朝皿外的接触法线。
- 贴壁细胞朝壁一侧出现局部平膜，不再保持完整圆形；不修改物理边界或皿壁碰撞规则。

### 多细胞协作表现

- `Main.gd` 默认演示体改为 4 细胞协作体：1 枚结构核 + 运动型（myocyte）/能量型（photocyte）/信息型（neurocyte），三条 Link 以 14 单位静息长度连成一体。发育程序每 tick 执行一条指令，约 9 tick 完成。
- `CellVisualCatalog` 新增六类角色配色：结构 / 运动 / 能量 / 信息 / 稳态 / 生殖，按 Cell Lab 类型分组但不复制其资源。
- `LinkLayer.gd` 从细直线升级为膜间黏附桥：两端按半径内缩，外层柔光 + 角色混合色核心；沿高能量 → 低能量方向显示移动光点，表示连接内定向流。纯视图派生，不写模拟状态。
- `CellSceneRenderer` 的黏附接触与 `LinkLayer` 的桥使用同一份 Link 数据，表现一致。

### 验收

- `SmokeTest.gd` 新增/更新断言：接触面浅而平（至少 4 个近共线点且不过深）、皿壁接触方向使朝壁膜内缩、渲染层派生黏附/皿壁接触、4 细胞演示体含 2/4/5 三类角色、3 条连接全部渲染、角色配色有区分。
- 源码 SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`。

### 边界

- 这是协作“表现层”：连接桥与光点来自现有链接和能量差，尚未实现 Cell Lab 的连接内经济结算、角质 shielding、化学信号沿连接传播。
- 角色配色只用于识别分工，不改变代谢/行为参数；不复制 Cell Lab shader 或贴图。
- 512 实例阈值、MultiMesh LOD 与单帧 12 tick 上限均未改。

---

## 0.8.4 — 2026-11-16

**类型**：程序化细胞外观 + 接触点压平
**触发**：用户问「能不能直接用 cell lab 的细胞贴图，cell lab 的细胞贴图是怎么实现的，看起来不像一张图，倒像是程序化生成的。接触点压平要做！」

### Cell Lab 贴图结论

- 静态反编译证据（`analysis/CellLab_APK_解析报告.md` §8、`CellLab_多细胞协作_设计规格.md` §3.1）：Cell Lab 运行时细胞不是一张贴图，而是 `*_vert.glsl` / `*_frag.glsl` + `ByteBuffer/FloatBuffer/ShortBuffer` 逐 tick 程序化绘制；`assets/guide-icons/*.png` 只是类型图鉴图标。
- 因此不把 guide-icon 当运行时细胞贴图，也不复制 APK shader；按同一思路改为「可复用 `.tscn` 节点 + 程序化几何/配色」。

### 程序化细胞

- `scenes/cells/CellBase.tscn` 移除 `Texture2D` 外部资源，保留 `Body` / `Outline` / `OrganelleRoot` / `SignalAnchor`，新增 `InnerRing`、`Nucleus` 与 5 个 `OrganelleN: Polygon2D`。所有外观节点由场景声明，脚本只填几何与颜色。
- `CellView.gd` 按 `org_id/type_id` 派生稳定签名，生成弹性膜轮廓、内膜环、细胞核与随机分布细胞器；`CellVisualCatalog.color()/accent_color()` 提供类型稳定配色。
- 膜仍是 12 控制点 Catmull-Rom + 3 谐波 + 速度限幅拉伸；碰撞半径、静息视觉半径、膜半径继续共用 `CellShape.REST_RADIUS = 7.0`。

### 接触点压平

- 参照 Cell Lab 的 `A[]` 接触点概念：`CellSceneRenderer` 复用 `CellPhysics` 空间哈希，为近景细胞取 `radius*2+1` 范围内最近的 6 个邻居方向，作为世界坐标接触方向传给 `CellView.apply_cell(..., contacts)`；不写模拟状态、不参与确定性 hash。
- `CellView._flatten_contact()` 对与接触方向夹角小于约 38° 的膜点向内拉，最大压平 22%，下限 55%；压平同时作用于外膜与内膜，形成局部接触面而不是整体缩小。
- 远景仍回退 MultiMesh 色块 LOD；512 实例阈值与单帧 12 tick 上限均未改。

### 验收

- `SmokeTest.gd` 删除 guide-icon 贴图/UV 裁切断言，改为断言无贴图依赖、程序化节点齐全、细胞器与核几何已生成、接触方向使右侧膜最大 x 内缩、`CellSceneRenderer` 确实派生接触方向。
- 源码 SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`。

### 边界

- guide-icons 继续保留为图鉴/编辑器资源，不再参与运行时细胞渲染；没有复制 Cell Lab shader 源码。
- 当前压平只按接触方向，不含 Cell Lab 的圆-圆重叠面积深度与 4 通道化学信号；后者仍按上游规格冻结。

---

## 0.8.3 — 2026-11-16

**类型**：贴图贴合与形变幅度修正
**触发**：用户反馈「放大看有贴图空隙」「细胞过近时形变夸张」，并追问 12 tick 上限出处

### 贴图贴合

- 诊断 `tools/TextureProbe.gd`：`zygocyte.png` 为 166×166，实际不透明区域只有 `(13,13)–(152,152)`；`myocyte/photocyte` 为 `(17,17)–(148,148)`。原 UV 按整张 166px 映射，贴图内容只占膜直径的 84%，所以放大后能看到明显空隙。
- `CellMembrane.texture_uv()` 增加 `uv_rect` 参数，把单位圆映射到贴图的**实际不透明内容矩形**；`CellView` 按资源路径全局缓存内容矩形，并把 UV 钳制在内容区内，避免谐波轮廓超出单位圆时又采到透明留白。
- 轮廓旋转后 UV 用同一组旋转点计算，贴图随膜一起转，不再出现「膜转、纹理不转」的错位。

### 形变幅度

- 速度拉伸从 `clampf(v*0.18, 0, 0.28)` 改为「限幅 → 低通 → 最大 8%」：碰撞修正造成的单 tick 速度尖峰不再把膜拉成夸张椭圆。
- 新增 `max_stretch=0.08` / `stretch_smoothing=0.18` 两个可调参数；SmokeTest 断言极高速度下 `stretch <= 0.081` 且轮廓长宽比 `<= 1.2`。

### 12 tick 上限说明（未改）

- 出处：`docs/Godot项目技术设计文档.md` §2.6，倍速表的 16× / 32× 行都写「12（余量结转）」，正文明确「单帧 tick 上限 12，防止掉帧后补帧雪崩；超出部分记入 carry」。属于 v2.1 技术基线「不可擅改」项，合并稿也写「倍速仍遵循 v2.1 tick 频率 + LOD、单帧上限 12」。
- 不是单纯拍脑袋：§8.1 目标是 1000 生物 / 8000 细胞，BenchTest 在 300 生物时 avg tick 已约 12.4 ms，12 tick/帧就已远超 16.7 ms 预算；继续提高只会把掉帧变成雪崩，并与本机长跑过热约束冲突。
- 真要提升必须走规格修订（v1.0 + v2.1 §0.3/§11），并改用「分批快进 + 检查点」而不是无限提高每帧 tick；本次不动基线。

### 验收

- SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`，新增 UV 裁切范围、UV 不越界、形变上限断言；源码与快照一致。

### 边界

- 仍未实现 Cell Lab 的接触点 `A[]` → 膜压平；细胞贴近时是「圆形膜 + 有限拉伸 + 物理分离」，不是局部压平。
- guide-icons 本身是图鉴/引导图标，Cell Lab 的细胞主体是顶点缓冲程序化绘制；本项目继续用它们作本地开发贴图，按内容矩形裁切后贴合。

---

## 0.8.2 — 2026-11-16

**类型**：碰撞半径对齐弹性膜 + 倍速可见性诊断与修正
**触发**：用户反馈「碰撞箱与实际大小不符」并质疑「30× 下细胞速度变化不明显，倍速是否真的生效」

### 碰撞半径统一

- Cell Lab 证据（`analysis/CellLab_APK_解析报告.md` §11.3/§11.5）：碰撞网格 `g()` 按细胞中心 `(b,c)` 与**同一个半径 `d`** 分格；接触物理也用圆-圆相交面积并把接触点写入 `A[]` 供膜压平，皿壁半径 `Environment.k`。渲染与碰撞不分两套半径。
- 新增 `scripts/core/data/CellShape.gd`，`REST_RADIUS = 7.0` 作为唯一半径真相源；`OrganismManager.cell_radius`、`CellView.visual_radius`、`CellView.cell_radius` 全部改为引用它，`main.tscn` 从 4.0 改为 7.0；删除 `CellSceneRenderer` 里残留的 4.0 半径参数。
- 物理最小中心距现在是弹性膜静息直径 14；SmokeTest 断言物理半径、视图碰撞半径、视觉静息半径三者相等，且两枚重叠细胞被推到 ≥ 静息直径。

### 倍速真实性与可见性

- 定量诊断 `tools/SpeedProbe.gd`：1× 跑 120 tick / 位移 0.0575；8× 跑 960 tick / 位移 3.09；30× 与 32× 均跑 1440 tick / 位移 5.44，`carry=4096`。**倍速确实生效**，但 30×/32× 都撞上「单帧 12 tick」硬上限，有效只有 12×，所以两者看起来一样快。
- 另一个原因是基础运动量太小：8→4→6 输出经 tanh 后约 ±0.01，`max_speed=12` 使 1× 下 2 秒只走 0.0575 世界单位。新增 `OrganismManager.max_movement_speed = 144` 并传入 `apply_outputs/apply_cached_intents`；1× 位移升到 0.69，30× 升到 65.3（仍受 12 tick 上限）。dt 依旧固定 1/60，能量成本仍按 intent 平方计算，不受影响。
- 顶栏 LOD 标签在饱和时显示「上限 12×」；反馈文字注明「单帧 ≤12 tick」。不绕过单帧上限、不缩放 dt，保持确定性基线。

### 验收

- 源码 SmokeTest：`SCRIPTS=42 FAILURES=0 EXITCODE=0`，新增半径一致性、碰撞间距、倍速→tick/位移比例、carry 与 UI 上限提示断言。
- `SpeedProbe` 四档测量无报错。

### 边界

- 弹性膜目前只在静息半径上与碰撞一致；Cell Lab 的「接触点写入 `A[]` → 膜压平」尚未实现，接触时仍是圆形轮廓。
- 30× 以上是名义倍率，实际受 12 tick/帧约束；若要真正超过 12×，需要修改基线约束（当前未做）。

---

## 0.8.1 — 2026-11-16

**类型**：v0.8.0 补丁
- 修复 `CellEditorPanel._sync_controls()` 每次「恢复默认」都重复连接 `item_selected`，导致 Godot 报 `Signal is already connected`。连接移到 `_build_options()` 并加 `is_connected()` 守卫。
- `SmokeTest` 新增连续两次 `_on_default()` 的回归调用；源码 `SCRIPTS=41 FAILURES=0 EXITCODE=0`，无信号错误。

---

## 0.8.0 — 2026-11-16

**类型**：相机控制 + 倍速直输 + 弹性细胞 + 细胞编辑闭环
**触发**：用户要求「滚轮缩放、右键拖动视野；倍速滑条与右侧直接输入；弹性细胞参考 Cell Lab；细胞编辑与合成器闭环」

### 相机控制

- 新增 `scripts/rendering/CameraController.gd` 并挂到 `Camera2D`：滚轮以光标为世界锚点缩放（0.6×～8×），右键按住拖动平移，视野中心限制在培养皿附近。
- 屏幕→世界换算用显式相机公式，不依赖 `get_canvas_transform()` 的帧内刷新时机；`Main.screen_to_world()` 的点击落点逻辑保持不变。
- 新增 `view_changed` 信号，后续 HUD 读数可直接订阅。

### 倍速滑条与数值输入

- `main.tscn` 顶栏右侧新增 `SpeedPanel`：HSlider + SpinBox 双向绑定 `TickCore.speed_scale`（0～32，步进 0.25），旁边显示当前 LOD 档。
- `TickCore` 新增 `speed_changed(speed, lod)`；HUD 订阅后同步滑块/输入框，键盘 1/2/3 快捷键与档位按钮也反向同步 UI。
- 仍严格遵守「倍速只改 tick 频率、不缩放 dt、单帧 12 tick 上限、carry 结转」的基线。

### 弹性细胞

- 新增 `scripts/rendering/CellMembrane.gd`：12 控制点 + Catmull-Rom 闭合曲线（72 点）+ 3 谐波呼吸 + 沿速度轴 `scale(1+s, 1-0.65s)`；签名由 org_id/type_id 派生，同输入同轮廓，不消耗全局 RNG。
- `CellBase.tscn` 的 `Body` 从 Sprite2D 换成 `Polygon2D`（贴 Cell Lab guide-icons，UV 映射单位圆），新增 `Outline` Line2D 描边；`OrganelleRoot` / `SignalAnchor` 挂点保留，后续细胞器继续在场景里扩展。
- `CellView.gd` 以 20fps 刷新膜轮廓，从 SoA 的 `cell_prev_*` 取速度做拉伸；`CellSceneRenderer` 传速度，仍然只读模拟状态、不进确定性 hash。>512 细胞仍回退 MultiMesh LOD。
- 算法参考旧工程 `CellMorphology.gd` 与 v4 UI 规格，按 v2.1 约束重新实现，不复制 APK 源码。

### 细胞编辑与合成器闭环

- 新增 `CellEditorPanel`（8 组型 0–255 滑块 / 呼吸方式 / 18 种类型 / 装载按钮），草案为本地 GNP1 Genome，不直接写模拟状态。
- 「装载到合成器」自动选中 SPAWN；落点时把 GNP1 二进制经 CommandBus 传入，`OrganismManager._genome_from_command()` 解码后用于 `register_zygote`，细胞类型同步生效。
- `INJECT_GENOME` 从 stub 变为真实命令：解码草案 → 命中细胞所属个体 → 重写基因组与物种归类 → 同步该个体细胞类型。
- `INJECT_GENOME` 加入 `TOOL_TYPES` 与诊断计数；`ToolCatalog` 中 SPAWN / INJECT_GENOME 描述同步更新。

### 验收

- `SmokeTest.gd`：`SCRIPTS=41 FAILURES=0 EXITCODE=0`。新增断言：弹性膜确定性与拉伸/呼吸、CellBase 弹性节点点数、滚轮锚点与右键拖拽、倍速滑条/输入双向同步、编辑草案→合成器→基因组落地、INJECT_GENOME 真化、HUD 新控件不重叠不出界。
- 主场景 headless 90 帧：`EXITCODE=0`，无解析/运行错误。
- 发布快照版本 `0.8.0`。

### 边界

- 细胞编辑目前覆盖 8 组型 / 呼吸 / 类型；40 modes / 54 settings / 18 细胞器的完整 Cell Lab 编辑器仍未做，发育指令程序编辑未开放。
- 弹性膜是表现层派生数据，不改变 SoA 物理形状或碰撞半径。
- 化学信号子系统仍冻结，等待上游 v1.0 §2.2 修订。

---

## 0.7.0 — 2026-11-16

**类型**：阶段 7 细胞可视化 + 三个交互 BUG 修复
**触发**：用户反馈「落点偏移 / 皿壁无碰撞 / 可生成在皿外」，并要求随后做阶段 7、贴图用 Cell Lab 资源

### BUG 修复

- **落点偏移**：`Main._unhandled_input()` 原来用 `get_global_mouse_position()`，在不同 viewport/stretch 下与相机 canvas transform 不同源。改为 `screen_to_world(mouse_button.position)`，显式使用 `viewport.get_canvas_transform().affine_inverse()`，与渲染相机变换一致。
- **皿壁碰撞**：`OrganismManager.advance_physics_tick()` 调 `project_to_dish` 时改为 `dish_radius - cell_radius`，细胞中心不再能贴到圆心边界导致半身出皿；下一 tick 强制投影回内壁并反射法向速度。
- **越界生成**：新增 `OrganismManager._clamp_to_dish()`，`SPAWN` / `AGENT_SPAWN` / 工具落点统一钳制到皿内（保留 cell_radius 余量），Agent 批量生成的每个偏移位置也单独钳制。
- SmokeTest 新增集成断言：越界 SPAWN 被钳制；细胞被强推到皿外后下一物理 tick 回到内壁。

### 阶段 7 · 细胞可视化

- **可复用场景**：新增 `scenes/cells/CellBase.tscn`，用 `Sprite2D` + `OrganelleRoot` + `SignalAnchor` 声明细胞外观与挂点；`scripts/rendering/CellView.gd` 只负责只读同步位置/类型/org_id/能量，绝不回写模拟状态。
- **Cell Lab 贴图**：新增 `scripts/rendering/CellVisualCatalog.gd`，把 18 种细胞类型映射到 Cell Lab guide-icons（zygocyte/somatocyte/myocyte/photocyte/neurocyte/phagocyte 等）。按用户明确要求，18 张 PNG + `.import` 纳入 `godot/cellarium-release/assets/apk_local/guide-icons/`；仅作本地工程资源使用。
- **双层渲染**：新增 `CellSceneRenderer.gd` / `DishView/CellSceneLayer`：≤512 细胞时用 CellBase.tscn 实例逐细胞渲染；>512 隐藏该层、退回 `CellBatchRenderer` MultiMesh 色块 LOD。tick 与 `command_executed` 均触发脏标记，冻结档干预后下一帧即可见。
- 修复 `CellSceneRenderer` 的相对 NodePath（`../../Simulation/...`）与 `cell_type` 的 `PackedByteArray` 类型，避免路径/类型静默失败。
- `main.tscn` 新增 `CellSceneLayer` 与 CellBase/MultiMesh 渲染器 ext_resource；`CellLayer` 仍隐藏。

### 验收

- `SmokeTest.gd`：`SCRIPTS=38 FAILURES=0 EXITCODE=0`——新增可复用 tscn 实例化、贴图可加载、SPAWN 后场景层刷新、MultiMesh 自动隐藏、坐标/皿壁/越界断言全通过。
- 主场景 headless 900 帧：`EXITCODE=0`，无解析/运行错误。
- 模拟确定性未改：细胞视图只读 SoA，不进状态 hash。

### 边界

- 贴图来自 Cell Lab APK 资源，按用户指令用于本地工程；不上传 APK 本体、反编译中间产物或音频。
- 细胞编辑页仍未做，`INJECT_GENOME` 仍是 stub；阶段 8 再处理。

---

## 0.6.2 — 2026-11-16

**类型**：细胞可见性修复补丁
**触发**：用户反馈「默认基因组细胞放下了什么都看不到」

### 根因与修复

- **不是细胞没生成**：命令、SoA 数据与神经都正常；`SmokeTest` 已验证 SPAWN 后 `cells.size()` 增加。问题在渲染层：`CellBatchRenderer` 只在 `_ready()` 调一次 `_rebuild()`，而它运行在 `Main._ready()` 创建 demo 细胞之前，且**没有连接 `tick_advanced` / `command_executed`**，所以实例数一直停留在 0。
- 新增 `command_bus_path` 与两个信号连接：每 tick 标记 dirty；冻结档干预经 `CommandBus.execute_tick_commands()` 立即 flush 时也标记 dirty，下一帧重建 MultiMesh。保持渲染只读，不写模拟状态。
- 细胞可见性仍为**最小可读形态**：QuadMesh + per-instance color，按 org_id 着色；贴图、弹性膜、组织特异性外观尚未做（见下方阶段路线）。

### 验收

- `SmokeTest.gd`：`SCRIPTS=35 FAILURES=0 EXITCODE=0`——冻结档 HUD 落点后，`CellBatch.get_instance_count()` 至少覆盖当前存活细胞数。
- 主场景 headless 900 帧：`EXITCODE=0`，无警告。

### 后续约定

- 用户明确要求：**后续细胞用可复用的 `.tscn` 场景/预制体做外观与挂载点**（节点优先、可复用），届时批量渲染与实例外观要重新对齐，不继续在脚本里堆一次性绘制代码。

---

## 0.6.1 — 2026-11-16

**类型**：v0.6.0 UI 交互修复补丁
**触发**：用户反馈「细胞合成器点击后放置不了、MicroscopePanel 重叠、偏振镜点不到」

### 根因与修复

- **合成器放置失败根因**：`main.tscn` 中 `UI/HUD` 的依赖路径覆盖写成了 `Simulation/CommandBus` / `Camera2D` 等从 HUD 出发的错误相对路径，实际解析为 `UI/HUD/Simulation/...`，导致 `GameHUD.command_bus`、`environment_manager`、`camera` 全部为 null，`world_action()` 直接返回 false；培养基滑块与镜头按钮同样无效。已改为 `../../Simulation/...` 与 `../../Camera2D`，与脚本默认值一致。**这才是点击工具后无法落点的真正原因，不是命令总线或 SPAWN 写入逻辑故障。**
- **冻结档交互**：冻结/暂停时没有下一 tick，命令会一直留在队列里造成「点了没反应」。新增 `Main._flush_commands_if_paused()`，在暂停或 `speed_scale<=0` 时立即经 `CommandBus.execute_tick_commands()` 落盘，仍保持唯一写入口契约。
- **MicroscopePanel 布局**：`LensTitle` / `LensRow` / `ViewRow` 原本同为 `MarginContainer` 直接子节点而互相重叠；新增 `Content` VBoxContainer 纵向排列，面板加宽到 580px（5 个镜头按钮 + 4 个视野按钮完整可见），底边上移到 `-40` 与 StatusBar 留出 12px 间隙，「偏振镜」不再被裁切/遮挡。
- **反馈与状态澄清**：选中/落点细胞合成器时明确提示「默认基因组直接放置；细胞编辑页尚未接入」；SPAWN 失败提示补充皿内落点检查。`main.tscn` 同时移除全部 `ext_resource` 的 UID 声明，消除 3 条 invalid UID 警告。
- **细胞编辑页**：确认尚未移植到 cellarium（旧 Genesis 有 `GenomeEditorPanel.gd`）。本补丁不假装已有；`INJECT_GENOME` 仍是唯一 stub。

### 验收

- `SmokeTest.gd`：`SCRIPTS=35 FAILURES=0 EXITCODE=0`——新增两项断言：①冻结档下 `HUD.world_action()` → `CommandBus` → 立即 flush 后细胞数 +1；②镜头面板 5/4 按钮完整、LensRow 不溢出面板、面板不与 StatusBar 重叠、最右侧按钮不被裁切。
- 主场景 headless 900 帧：`EXITCODE=0`，无 UID/解析/运行警告。

---

## 0.6.0 — 2026-11-16

**类型**：阶段 6 倍速、LOD 与性能验证
**触发**：v0.5.0 发布后按用户指令「继续阶段 6」

### 工程（godot/cellarium-release）

- **T11 倍速与 LOD 阶梯**：`TickCore.gd` 新增 1×/3×/8×/16×/32× 档位表，单帧最多执行 12 tick，余量结转 `carry_ticks` 并通过 `carry_changed` 提示「模拟时间落后」；神经按 1/1/2/4/8 tick、环境场按 1/1/1/2/4 tick 降频，32× 限制渲染 30 FPS。**倍速只改 tick 频率，不缩放 dt**，固定 1/60 步与确定性基线不变。新增 `step_once()` 供逐帧调试。
- **性能埋点**：新增 `scripts/system/PerfProbe.gd`，分 `behavior/physics/metabolism/predation/signal/field/commit` 七阶段以 `Time.get_ticks_usec()` 计时，环形缓冲 + `averages()` + CSV 导出；`OrganismManager.advance_physics_tick()` 全段接入。
- **关键 O(n²) 修复**：`CellPhysics` 公开 `build_spatial_hash()` 并增加 `query_neighbors_cached()`；`OrganismManager._compute_behavior_outputs()` 从「每细胞重建哈希」改为「每 tick 构建一次、所有细胞复用」。300 生物平均 tick 从 99.9ms 降至 12.4ms，1000 生物从 884.5ms 降至 60.4ms。
- **神经 LOD 降频**：非神经更新 tick 调 `CellBehavior.apply_cached_intents()`，复用上一轮 `behavior_intents` 推进运动，不重算 8-4-6 前馈；高倍速下行为意图与物理推进解耦但仍按固定 dt。
- **批量渲染与后处理**：新增 `CellBatchRenderer.gd`（`MultiMeshInstance2D` + per-instance color + 稳定 stride LOD 抽样上限）接管 `CellBatch` 节点，原 `CellLayer` 保留作细粒度参考；新增 `PostprocessLayer.gd`（纯叠加式暗角/扫描线，16× 以上自动关闭）。后处理只影响呈现，不写模拟状态。
- **主场景与 HUD**：`Main.gd` 接入 carry 提示、TickCore 注入、倍速快捷键（1/2/3 = 1×/3×/8×，Shift+3 = 16×，Shift+4 = 32×，空格暂停）；`main.tscn` 移除 ext_resource UID 声明，新增 `CellBatch`/`Postprocess` 节点。

### 验收

- `SmokeTest.gd`：`SCRIPTS=35 FAILURES=0 EXITCODE=0`——新增 T11 档位/carry/帧上限/落后提示/`step_once`/dt invariant、PerfProbe 分阶段计时与 CSV、MultiMesh 批量实例与 LOD 上限/后处理自动关闭三项测试全过，前 5 阶段测试保持通过。
- 主场景 headless 900 帧：`EXITCODE=0`、无解析/运行错误；`[GameHUD] ready tools=14 modes=5 substrate=8 semantic=24`。
- `BenchTest.gd`：300 生物 120 tick / 3369.8ms / avg 12417.6us，`cpu_budget_met=true`；1000 生物 120 tick / 10047.3ms / avg 60415.2us；3000 生物 50 tick / 15205.8ms / avg 270055.8us。单档 15 秒墙钟上限生效，结果 CSV 已导出，`FAILURES=0`。
- `T12FallbackTest.gd`：`backend=cpu hash_a=1174237790 hash_b=1174237790 FAILURES=0`——强制 CPU 回退下连续 220 tick 与「110 tick → 存档 → 读档 → 110 tick」状态哈希一致；五通道场、地形 mask、存档恢复功能完整。
- 快照独立 SmokeTest、headless 900 帧均与源工程一致；`scripts/scenes/tools` 逐文件 SHA256 比对 `MISMATCHES=0`。

### 边界

- **性能预算未全达标**：§8.1 的 8ms/14ms 目标仅在 300 生物 CPU 回退下达到；1000/3000 生物仍超预算，主要耗时在行为网络（36.9ms / 165.9ms）、物理（13.6ms / 62.3ms）与代谢（7.6ms / 31.4ms）。当前策略依赖高倍速 LOD 降频与 MultiMesh 降低实际运行压力；更深层的 GDScript→GPU Compute 迁移不在本版本完成。
- 窗口 Vulkan GPU Compute parity 未在本轮重跑；headless 验证的是 CPU 回退与解析路径。
- 化学信号子系统仍按 v2.1 §0.5/§12.7 冻结；`INJECT_GENOME` 仍是唯一 stub。

---

## 0.5.0 — 2026-11-16

**类型**：阶段 5 沙盒工具与观测
**触发**：阶段 4 发布后按用户指令「开始阶段 5」

### 工程（godot/cellarium-release）

- **语义 ID 注册表**：新增 `scripts/ui/SemanticRegistry.gd`（静态模块），支持 §3.6 五类命名空间 `ui://tool://cmd://org://sp://`；重复 ID 在开发构建下断言失败、发布构建只计数；WeakRef 避免悬空。GameHUD 的 14 工具/5 档位/5 镜头按钮在 `_ready` 注册（24 个 ID），并提供 `ui.click` → `act()`/`pressed` 无坐标派发。场景反复实例化时先 `clear_prefix` 再注册，避免误报重复。
- **AgentBridge（17 接口）**：新增 `scripts/agent/AgentBridge.gd`，承接 v1.0 §10 全部 17 个上游接口 + 13 个 v2.0 扩展接口；默认关闭，需 `enable(token, mode)`，JSON Lines 请求/响应，`readonly`/`sandbox`/`full` 三档权限，逐条审计记录（issuer/tick/args/result）。写入类统一封装成 CommandBus 命令，与 UI 点击等价可重放；查询类返回只读快照。`Main.gd` 持有实例并支持启动参数式启用（默认关）。
- **地形编辑真实化**：`EnvironmentField` 增加独立可编辑 `terrain_mask`（固体阻挡层），`_is_active()` 统一有效格判定，CPU 扩散/采样、GPU mask 上传同步生效；`paint_terrain()` 笔刷写入并清零固体格浓度。SELECT/ROTATE_SELECTION/TERRAIN_PAINT/TERRAIN_ERASE 从 stub 变为真实写入（选择集/质心旋转/场 mask），ToolCatalog 对应 kind 改为 world。地形 mask 纳入存档往返。
- **书签与分支（T09）**：`AgentBridge` 的 `sim.save_bookmark`/`load_bookmark`/`save.fork` 走 SaveManager，分支快照写入 `parent_archive_id` 且不修改父包；父 ID 链可核验。
- **开发者模式**：`Main.gd` F9 切换 dev_mode，白名单命令 `DEV_FORCE_MUTATE`/`DEV_FORCE_SPECIATE`/`DEV_SPAWN_BATCH`/`DEV_DUMP_WORLD` 经 CommandBus → OrganismManager 执行。
- **生态分析面板**：空壳 `AnalysisPanel` 接入数据驱动脚本，R 键开合，显示种群折线/死因/事实；注册 `ui://report/panel` 供 Agent 自动化。

### 验收

- `SmokeTest.gd`：`SCRIPTS=32 FAILURES=0 EXITCODE=0`——新增语义注册表（重复守卫/命名空间/click 派发）、AgentBridge（17 接口数量/默认关闭/token 门禁/权限分级/JSON Lines/审计）、T07（干预前后 E_total 不变 + 账本自洽）、T09（父存档不可变/父 ID 链/分支独立推进）四项测试全过，原有 28 项保持通过。
- 主场景 headless 900 帧：无报错、EXITCODE=0；`[GameHUD] ready tools=14 modes=5 substrate=8 semantic=24`。
- 快照独立 headless 冒烟通过；移除 `main.tscn` 的 ext_resource UID 声明，消除快照无 .uid 历史文件的启动警告。
- GPU/CPU 场 parity：地形 mask 改动在无地形时行为不变，headless 自动回退 CPU 通过；窗口 Vulkan 复验归入阶段 6。

### 边界

- 化学信号子系统仍按 v2.1 §0.5/§12.7 冻结，未实现。
- `INJECT_GENOME` 仍为唯一 stub（基因组注射底层待接）。
- 32× 倍速/T11、CPU 回退长跑/T12、性能基准等归入阶段 6。

---

## 0.4.0 — 2026-11-16

**类型**：阶段 4 完整进化引擎
**触发**：v0.3.0 推送后按用户要求推进阶段 4

### 工程（godot/cellarium-release）

- **五类突变**：新增 `scripts/system/Mutation.gd`——点突变 0.001 / 功能 0.0004 / 重复缺失 0.0002 / 发育 0.0005 / 元突变 0.0001，环境压力乘数上限 4.0；确定性种子由 `genome_id/parent_id/tick/salt` 派生，源基因组不可变。
- **物种与谱系**：新增 `SpeciesSystem.gd`——`Genome.distance()` 加权距离（位点汉明 + 性状 L1×0.05 + 发育程序编辑×0.5），超过 `speciation_distance=6.0` 且距上次分化超过 `speciation_cooldown=600` tick 才新建物种；灭绝档案含寿命/峰值种群/主要死因/核心性状；`export_phylogeny()` 导出节点/父子边/分化事件。`Genome.gd` 增加运行时 `species_id`/`lineage_id`，**不进已冻结的 GNP1 二进制格式**。
- **统计与生态报告**：新增 `StatisticsSystem.gd`——环形缓冲默认 7200 点 / 30 tick 聚合，采样种群、出生死亡、六类死因、平均体型/速度/代谢、丰富度与均匀度；三条产物为种群折线、物种与死因面板、数据驱动事实。事实全部模板生成，禁止手写死文案。
- **存档与 T08**：新增 `SaveManager.gd`——版本化 `.gsave` 包捕获/恢复细胞与个体 SoA、基因组池、五通道场（含 pending sources）、物种谱系、统计缓冲、能量账本与 tick 调度状态；`OrganismManager` 暴露 `capture_state`/`restore_state`/`save_state_to_file`/`load_state_from_file`。
- **繁殖闭环**：`REPRODUCE` 走 `CommandBus`，能量阈值检查 → 突变 → 物种判定 → 新受精卵注册 → 亲代扣能；死亡记录物种死亡与灭绝档案。
- `EnergyLedger` 增加 `restore_snapshot()` 与完整流水导出，存档往返后守恒断言仍成立。

### 验收

- `SmokeTest.gd`：`SCRIPTS=29 FAILURES=0 EXITCODE=0`——新增突变、物种/冷却/灭绝/谱系导出、统计环形缓冲/数据驱动事实、**T08 存档往返 1000 tick 双路径状态哈希一致**。
- 主场景 headless 900 帧：无报错、EXITCODE=0；`[GameHUD] ready tools=14 modes=5 substrate=8`。
- 快照独立 headless 冒烟通过（无 MCP 插件依赖）。

### 边界

- 化学信号子系统仍按 v2.1 §0.5/§12.7 冻结，上游 v1.0 §2.2 修订前不实现。
- 选择/旋转选区/地形笔刷仍为 stub（仅命令计数），属阶段 5 后续工作。

---

## 0.3.0 — 2026-11-16

**类型**：阶段 3 收尾（捕食 + 能量守恒）/ 阶段 5 UI 骨架落地
**触发**：用户确认 UI v5 布局后落地 Godot，并补齐阶段 3 最后两块缺口

### 工程（godot/cellarium-release）

- **UI 骨架（阶段 5 起点）**：新增 `scripts/ui/ToolCatalog.gd`（14 工具 / 5 档模式 / 8 培养基 / 5 镜头数据目录）与 `scripts/ui/GameHUD.gd`（数据驱动实例化 `Button`/`HSlider` 进 `.tscn` 声明的 `Control` 容器）。`main.tscn` 的 `UI/HUD` 下声明 `TopBar`/`ToolDock`/`SubstratePanel`/`MicroscopePanel`/`StatusBar`/`FeedbackLabel`。模式按钮接 `TickCore.set_speed`（冻结/观察/培养/慢速观察/过夜培养，**不缩放 dt**），镜头/视图仅改 `Camera2D`，培养基可写参数直接改 `EnvironmentManager` 导出值。
- **交互闭环**：`Main.gd` 的 `_unhandled_input` 把皿内左键点击 → `CommandBus.enqueue()` → 下一 tick `apply_command` → 结果回传 HUD。`OrganismManager.apply_command` 扩展 `TOOL_TYPES`：SPAWN/REMOVE/DRAG/BOOST/INSPECT/ADHERE/INJECT_SIGNAL/INJECT_SUBSTANCE/INJECT_COLOR 真实写入；SELECT/ROTATE_SELECTION/TERRAIN_PAINT/TERRAIN_ERASE 返回 -2 记入 `tool_diagnostics.STUB`（底层待接入，不虚假承诺）。
- **捕食闭环（阶段 3）**：新增 `scripts/system/Predation.gd`——消费神经攻击意图 `intent[2]`（阈值 0.35），空间哈希找邻近异种细胞捕食，转移率 0.8；按索引升序 + 邻居排序保证确定性，猎物榨干记 `DEATH_PREDATION`。
- **能量守恒账本（阶段 3）**：新增 `scripts/system/EnergyLedger.gd` 追踪 `E_env/E_bio/E_detritus/E_external` 四池逐项借贷，`assert_conservation()` 校验 `初始+Σ流水净额==当前`。摄入（ENV→BIO）、捕食（BIO→BIO + 损耗→detritus）、死亡分解（经 `add_nutrient_source` 写回场）、工具干预（E_external→对应池）全部记账，工具前后 E_total 不变。参数可配置，不进确定性 hash。
- **渲染批量化**：`CellariumView.gd` 去掉每帧 `_process→queue_redraw`，改由 `tick_advanced` 信号驱动（冻结档零重绘）；细胞按 `org_id` 分桶减少颜色切换，每细胞 2 实心圆替代 24 段弧。
- `ChemicalSignalSystem` 空节点只加 `editor_description` 标注待立项，**未实现**（遵守 v2.1 §0.5/§12.7「上游 v1.0 §2.2 修订前不动」）。

### 验收

- `SmokeTest.gd`：`SCRIPTS=25 FAILURES=0 EXITCODE=0`——新增工具闭环、捕食单元、守恒账本、捕食端到端集成四项测试全过；原有 T04/T06、五场 parity 前置、同种子 hash、GNP1 等全部保持通过。
- 主场景 headless 900 tick：无报错、EXITCODE=0；`[GameHUD] ready tools=14 modes=5 substrate=8`。
- 快照独立 headless 冒烟通过（无 MCP 插件依赖）。
- `preview/ui_skeleton_v5.html`：纯 UI 规格稿（PC 整体单视图），不在公开快照内（`.gitignore`）。

---

## 0.2.0 — 2026-11-15

**类型**：玩法决策落地 / Godot P1 数据层 / 可运行工程快照
**触发**：纳入 Godot 源码并继续实现核心数据模型

### 四项决策

1. **区分 `DIVIDE` 与 `REPRODUCE`**：`DIVIDE` 让同一个体 `cell_count += 1`（发育，不产生新 `org_id`、不写谱系），`REPRODUCE` 让个体数 +1（繁殖，产生新 `org_id` 与父代 ID）。v1.0 §5.4「无性二分裂」解释为 `REPRODUCE`；多细胞个体从新受精卵重建，不是把母体对半切开。
2. **最小自治核基础值做成培养基参数**：由 `EnvironmentPreset.nutrient_density`（皿级只读标量）导出 `basal_autonomy`，不硬编码；随存档 / 快照 / 回放序列化，局部营养场仍只影响摄能速率。
3. **v1 不做环境诱导的发育深度可塑性，但保留接口**：预留 `DevelopmentContext` 只读快照接口；v1 发育深度完全由 `dev_program[]` 遗传决定，tick 内禁止读环境场增删发育指令。
4. **新建独立 Godot 工程 `D:\Tools\Godot_v4.7.2\project\cellarium`**：Genesis 保留为参考基线；后续开发通过 Godot MCP 操作编辑器，节点 / 属性 / 信号在 `.tscn` 中声明，脚本只承担必要逻辑。

### 文档变更

- `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md`：新增 §5.3.6（术语统一、最小自治核、发育深度轴、表达预算与经济性、培养基参数、可塑性接口预留）、§5.4.1（发育与繁殖分离）；§7.5 增补营养密度参数；§10.3 更新工程位置与开发方式；§0 / §11.5 / 附录 A 同步。原文 128 段 / 13 表仍逐字保留，结构校验 `PROBLEMS=0`。
- `docs/Godot项目技术设计文档.md`：新增 §0.7 实现约束（数据结构映射、命令对象、重复装备税、确定性约束、Godot MCP 开发方式、v1 不做项），头部版本与日期同步。
- `README.md`：文档索引补充第二轮增补内容及公开 Godot 工程快照路径。
- `godot/cellarium-release/`：纳入可运行 Godot 4.7.2 工程快照，含主场景、基础模拟节点和 P1 数据层源码；不含 `.godot/` 缓存、Godot AI MCP 插件、安装包与本地安装脚本。

### 工程

- 新建 `D:\Tools\Godot_v4.7.2\project\cellarium`：主场景与节点树通过 Godot MCP 创建。Genesis 未改动。
- P1 首批数据层：SoA `CellArray` / `OrganismStore`、GNP1 运行时 `Genome` 与 u32 `GenomeCodec`、`DevelopmentRules`；实现连接同个体校验、个体能量聚合、DIVIDE 深度、REPRODUCE 命令分离、单细胞直接成熟。
- Godot MCP 插件仍留在本机工程；公开快照可不依赖插件独立打开和运行。

### 验收

- 合并稿结构校验：PASS（0 problems）。
- `SmokeTest.gd`：12 个运行脚本 + `main.tscn` 全部加载；自治值随营养密度变化；SoA 范围 / 同个体双向连接 / 能量求和 / DIVIDE 深度 / 单细胞成熟 / `DIVIDE` 与 `REPRODUCE` 分离 / GNP1 编解码与 CRC 损坏拒绝均 PASS；`FAILURES=0`、`EXITCODE=0`。
- 主场景运行时：Godot MCP helper live、无启动错误；实测 tick 推进且排队命令在下一 tick 消费。
- 干净快照独立 headless 验收通过；快照包含 12 个本项目脚本和 1 个场景，不含缓存与插件。

---

## 0.1.0-docs — 2026-11-15

**类型**：文档基线 / 首次备份
**状态**：待用户审阅（v1.1 合并稿尚未正式升为玩法权威）

### 本次交付

- `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md`（新建）
  - 以用户指定的权威 v1.0 DOCX 为底稿，按 body 顺序逐段提取；§1–§9 原文 128 段 / 13 表逐字保留，章节编号不变。
  - 正式并入 P0 条款 §5.3.1–§5.3.5（多细胞个体与细胞协作）。
  - 新增 §3.3.1 显微视野与观察控制、§4.3.1 实验条件档位、§4.3.2 无渲染快进、§4.4 细胞级工具扩展、§7.5 培养基设置。
  - 新增 §10 借鉴边界与工程重写、§11 版本管理与备份、附录 A 证据索引。
  - 校验：原文逐字命中、章节齐全、6 个 ASCII 布局表代码围栏闭合、Markdown 表格列数一致，PROBLEMS=0。
- `analysis/CellLab_界面与实验条件_词条证据.md`（新建）
  - Apktool 3.0.3 解码两版 `resources.arsc`：官方 459 键 / Macro 1365 键（Macro 独有 935）。
  - 确认 4 档培养条件两版共有（冻结 / 观察 / 培养 / 慢速观察）、过夜培养为 Macro 独有；官方 5 件工具、Macro 10 件；Macro 独有镜头滤镜与缩略图相机；培养基参数分组对照。
- `docs/Godot项目技术设计文档.md`：头部「状态」「上游文档」与 §0.5.4 影响清单同步为「P0 条款已并入 v1.1 合并稿」。
- `docs/v1.0_P0补充条款_待并入.md`：标注已并入，更正同步事项表。

### 备份范围

本次为**仅文档**备份：README / CHANGELOG / VERSION / `.gitignore` + `docs/*.md` + `analysis/*.md` + `analysis/cell_lab_apk_extract/asset_diff.txt`。

未纳入：Godot 工程代码、`preview/` UI 预览、所有 `.docx` / `.apk` / `.dex` / 反编译中间产物、`.workbuddy-ai/` 项目数据。

### 验收

- 文档结构校验：PASS（0 problems）。
- Godot 无头冒烟：本版本**未改动任何运行时代码**，沿用 2026-11-15 基线结果 `EXITCODE=0`、846+ tick、无脚本解析错误。
- GitHub：创建公开仓库 `cellarium`，本条目对应首个 tag。

### 已知事项

- 仓库名称已由用户选定；v1.1 合并稿仍待用户审阅确认。
- 公开文档中包含本机开发路径；如需脱敏，后续版本统一替换。
- Godot 工程与工作区此前均无 git，本版本起建立版本控制；核心重写须在首次快照之后进行。
