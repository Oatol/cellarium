# 变更记录

版本号规则见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §11.1。文档版本与工程版本在本文件中关联。

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
