# 创生模拟器 · Godot 项目技术设计文档（工程实现版）

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v2.1 + P0 增补 + §0.7（2026-11-15 单细胞个体与发育深度轴实现约束；主版本号暂不升级，待 P1 实现后统一升 v2.2） |
| 日期 | 2026-11-11（初版） / 2026-11-15（P0 增补、第二轮增补） |
| 状态 | 待评审 · P0 条款已并入工作区 v1.1 合并稿（`docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md`）；v1.0 DOCX 权威原件保留不改，待用户确认后升为权威版 |
| 引擎基线 | Godot 4.3+（GDScript 为主，Forward+ 渲染器） |
| 上游文档 | 《创生模拟器 · 沙盒版人工生命系统设计文档》v1.0（用户指定权威原件）/ v1.1 合并稿（工作区新增，待用户确认） |
| 参考材料 | 《创生协议》实机视频（3 分 47 秒，1598×898）、本地设计文档 v1.0、Substrate: Emergence（Steam App 4248790）、Cell Lab（cell-lab.net）、Cell-Lab-Remake（GitHub）、ALIEN（GitHub chrxh/alien） |

## 0. 文档说明

### 0.1 本文与 v1.0 的关系

v1.0 已经把"做什么"定义完整：世界观（木卫二冰下海洋实验室）、五类环境场、呼吸机制、能量守恒、界面分区、10 类干预工具、16 种功能细胞、8 位点 + 8 全局性状的基因组、开放式进化与谱系追踪、六阶段路线图，以及 §10 的 AI Agent 交互接口规范（完整版文档）。本文不重复这些规则，而是补齐"怎么做"：工程分层、目录与场景树、数据契约与二进制格式、模拟时序、线程与 GPU 分工、接口签名、性能预算、测试与验收。上游 §10 定义的 17 个接口作为外部契约原样保留，其 Godot 实现与扩展见本文 §7。

一句话概括：**v1.0 是玩法与系统规格，v2.0 是同一套规格的 Godot 施工图和验收单。** 两文冲突时，玩法规则以 v1.0 为准，技术实现以本文为准；任何规则变更需同步更新两份文档。

v2.1 为**资料核对增补版**：新增 §0.5 记录四个外部参考原型（Substrate: Emergence、Cell Lab、Cell-Lab-Remake、ALIEN）的一手资料核对结论与借鉴取舍，并把可落地的技术点分散补入 §1、§3、§4、§5、§7、§8、§9、§11、§12。**v2.1 不修改任何 v1.0 玩法规则，也不改动已冻结或待冻结的数据契约**；所有新增字段均为可选、可版本化追加。参考原型带来的"不采纳项"同样记录在 §0.5，用于防止范围蔓延。

**P0 增补（2026-11-15，多细胞个体与细胞协作）**：依据 `analysis/CellLab_多细胞协作_设计规格.md` 与 `analysis/CellLab_APK_解析报告.md` §11 / §12，对 v1.0 §5.3 已定义的「多细胞发育机制」作细化，补上个体身份边界、细胞类型分工、细胞内能量再分配与协作产生的个体级属性。本次增补**不引入新玩法概念、不修改 v1.0 已有规则、不改动 GNP1 冻结布局**；修订索引与依据见 §0.6，v1.0 待并入条款见 `docs/v1.0_P0补充条款_待并入.md`。

### 0.2 参考材料核对结果

从《创生协议》实机视频中可以确认的界面与玩法元素，本文全部纳入实现范围：

| 视频中确认的元素 | 落地位置 |
| --- | --- |
| 主菜单：创生协议 / GENESIS PROTOCOL、"设计一种生命，然后看它自己活下去"、01 战役 / 02 沙盒 / 03 设置 / 04 退出、右下"培养皿实时：X 个生命 · Y 条谱系" | §6.2 主菜单场景、§6.6 模式分层 |
| 章节页：第六章·播种篇、熔岩滤食兽、深度/温度、目标 / 附加挑战 / 奖励 / 可用干预 / 已知信息 | §6.6 预设实验场景（可选层） |
| 生命设计器：A·生产者 / B·采集者 / C·捕食者标签，行为规则 / 物种 / 规则手册 / 病毒设计 / 身体；样本培养舱、染色体组、器官库；DNA 双螺旋与位点标注 | §6.3 生命设计器 |
| 基因条目：速度 / 感知 / 外壳 / 攻击 / 繁殖 / 代谢 / 神经 / 耐温，各带 Lv、消耗与说明；底部基因预算、预计耗能、分裂所需能量、游速、视野、自然变异、呼吸、保存到物种库、投放到培养皿 | §3.2 基因组格式、§6.3 数据绑定 |
| 模拟主界面：T+xx:xx、暂停 / 1x / 3x / 8x、实验目标、环境（温度 / 溶解营养 / 水流 / 生物量）、物种列表、事件日志、小地图、干预工具（营养投放、隔离膜、局部升温、洋流引导、撒铁粉、投放病毒、撒盐、搅动泥层、刺激头冠、地形编辑）、底部快捷键 V/X/C/F/R/Tab/G | §5.1–5.2 培养皿渲染、§6.4 主界面、§6.5 输入映射 |
| 生态报告：种群变化折线、物种与死因面板、图例（饥饿/被捕食/衰老/温度/酸度）、记录到的事实 | §6.7 生态报告 |
| 实验成功：三星评价（完成目标 / 附加挑战 / 低预算）、研究点 +30 | §6.6 结算层 |
| 开发者模式：解锁全部关卡、跳过引导、研究点 +100、基因预算不限、帧率与模拟耗时 | §6.8 开发者面板 |

上表只覆盖《创生协议》视频这一份表现层参考；四个外部参考原型的核对、可信度边界与借鉴决策见 §0.5。

### 0.3 范围与不做的事

**本版做**：单机 Godot 客户端；沙盒模式全功能；一个可选、轻量的"预设实验场景"层（承载视频中的章节/目标/星级，不改动模拟内核）；存档与分支；开发者调试；AI Agent 接口；一个生物个体由多个分化细胞构成、细胞通过弹性连接组成同一个体（v1.0 §5.3 的工程落地，规则细化见 §0.6）。

**本版不做**：联网与多人、云端存档、剧情/对白系统、关卡编辑器、生物外观美术资产生产管线、移动端导出、内置适应度函数或"自动引导物种变强"的逻辑；v2.1 追加明确排除：多阵营领地对抗与胜负条件、以引导突变方向为目标的人工选育算子、每细胞独立基因组、百万级粒子规模（依据见 §0.5.3）。

**v0.29.0 版本化追加（分化树 40 槽 / 旧连接方向重分配 / FLAG 后向连接校验）**：全量精读官方 `CellWorld.e(double)` 后，把此前 §0.6 标为「不采纳」的 40 Gene 槽分化树改为**版本化采纳**：`Genome.MAX_GENOME_MODES` 16→40，母细胞切到 `child_mode1`（官方 `Gene.i`）、子细胞切到 `child_mode2`（`Gene.j`）；模式槽仍只存 `Genome.modes` 字典，不进 GNP1。连接新增 `CellArray.link_angle`（连接的世界方向角）与 `cell_orientation`（细胞朝向），均为确定性状态，schema v8 保存（旧档 link_angle 由两端位置重算、朝向填 0），纳入 `get_state_hash()`。分裂时按官方点积 `cos(axis−link_angle)−(1−2·Gene.c)` 与 ±0.2 双阈值把旧连接分给母/子，中间带用四极值索引（左/右投影 max/min）补齐；未命中者丢弃，双方连接数上限仍为 20。新增逐模式 `link_keep_mother`/`link_keep_child`（官方 `Gene.m/n`，默认 false，旧 hash 不变）。细胞类型为 FLAGELLOCYTE（id=3）时，按 `cos(link_angle−cell_orientation)<−0.8` 标记后向连接形态异常并走统一死亡路径（新死因 `DEATH_BACKWARD_LINK=6`）。tick 顺序、单帧 12 tick 上限、CommandBus 单写者与 GNP1 布局不动；新字段只在对应开关置位时改变行为。

**v0.30.0 版本化实现约束（物理性能专项：SoA 缓存复用 + 单 CanvasItem 批渲染）**：Cell Lab `CellWorld` 的构造期固定池、并行 `double[]` SoA、一次性建格（`g()`，格边长 0.03、每细胞写 4 格、只处理 `i4=i3+1` 的唯一配对）与「物理接触阶段写 `A[]` 弦、渲染阶段只读 `A[]` 批量提交顶点」是本项目性能对齐目标（证据见分析文档 §33.2）。本版不改 `CellArray` 的 Packed*Array 数据契约、不改 GNP1/tick 顺序/单帧 12 tick 上限/`CommandBus` 单写者/场 schema：① 场采样改为按 `cell_index` 的 O(1) 索引，消除 `EnvironmentManager.sample_fields()` 的 `_sample_positions.find()` 线性查找；② 空间哈希一次构建后传给 behavior、碰撞与捕食共享，捕食不再按捕食者重建整格；邻域与场值改为扁平 CSR 视图，遍历顺序与旧路径一致；③ 新增单 CanvasItem 批渲染管线，复用现有共享弦与 `prepare_for_render` 切平膜，在 >512 细胞规模取代 MultiMesh 纯色块 LOD，保留类型/表型色、连接桥与选中环。所有优化都不得改变状态 hash 与存档；若浮点顺序变化导致 hash 漂移，必须回退或版本化，不允许静默改变确定性。

**v0.31.0 版本化实现约束（GDExtension 原生热点下沉，性能专项）**：为逼近 3000 细胞流畅，本版把物理热点下沉到 C++（GDExtension），仍是 Cell Lab 同构机制的实现替换而非新玩法。工具链：Godot 4.7.2 无对应 godot-cpp tag，改用引擎自导出的 `extension_api.json`（`godot --headless --dump-extension-api`）+ godot-cpp master `custom_api_file` + MSVC/SCons 编译；DLL 与 `.gdextension` 放 `bin/`，不入库（二进制/第三方源码按仓库约定不提交）。接入边界：① `OrganismManager.native_spatial_enabled`（默认 **false** = 纯 GDScript，与 v0.30 逐位一致；DLL 缺失/类未注册自动回退）；② 首个下沉对象是 `CellPhysics.resolve_collisions` → C++ `CellSpatial.resolve_collisions`，`BenchTest` 可用 `CELLARIUM_NATIVE=1` 切换同口径对比。**硬闸门**：C++ 必须逐位复现 GDScript 浮点（GDScript `float`=double，`PackedFloat32Array` 元素=float32，运算 double、写回转 float32）、碰撞对遍历顺序（a 升序→9 格偏移 `(offset_y,offset_x)`→格内插入序，`b>a` + 距离 >2×接触过滤），固定桶数组仅替代 `unordered_map` 不得加 Cell Lab 式 203 容量截断（会改变邻居集合）；`NativeParityProbe` 要求完整 tick `get_state_hash()` 逐位一致（240 tick 密集合子通过）。GNP1、tick 顺序、1/60 步长、单帧 12 tick 上限、CommandBus 单写者、五通道场 schema、存档 schema v8、状态 hash 算法均不改；神经/场采样/邻域 CSR/collect_inputs 的 C++ 原型已验证逐位等价但按收益排序择机接入。未达标数字（3000 细胞 C++ 碰撞后全 tick 约 85ms，目标 8ms）不得表述为达标。

**v0.32.0 版本化实现约束（行为热路径原生下沉：邻域 CSR / 输入收集 / 神经推理）**：延续 v0.31 A 路线，把 behavior 阶段三段热点接入 C++，仍是 Cell Lab 同构机制的实现替换，不改玩法。接入边界：沿用 `OrganismManager.native_spatial_enabled`（默认 **false**），新增 `ClassDB.class_exists("CellNeural")` 检查与 `_get_native_neural()`；`_build_behavior_environment()` 在 native 开启时调用 `CellSpatial.build_neighbor_csr()` 产出 (offsets, values)，尺寸不符或类缺失回退 `CellPhysics.build_spatial_hash_flat/query_neighbors_flat`；`advance_physics_tick()` 的 neural 分支用 `CellSpatial.collect_inputs_batch()` + `CellNeural.evaluate_batch()` 替换 `CellBehavior.compute_outputs_flat()`，`apply_outputs_flat()` 保持 GDScript 不动。**硬闸门**：① 三段逐位等价分别由 `spatial_parity_probe`（邻域索引 / collect_inputs float32）、`neural_parity_probe`（12000 float32 全等）与 `NativeParityProbe`（240 tick 全状态 hash）保证，任一失败即回退；② C++ 固定桶不加 Cell Lab 式 203 截断，9 格偏移顺序与 GDScript 一致，浮点 double 累加、写回转 float32；③ 死细胞 `sample_indices=-1`、`evaluate_batch` 输出置零，与 GDScript 语义一致。GNP1、tick 顺序、1/60 步长、单帧 12 tick 上限、CommandBus 单写者、五通道场 schema、存档 schema v8、状态 hash 算法均不改。实测同会话 A/B：3000 细胞 behavior 68.1→11.8ms（5.77×）、全 tick 232.0→68.6ms（3.38×）；**距 ≤8ms/tick 仍远，`cpu_budget_met=false`，不表述为达标**。新瓶颈转为 metabolism 43.0ms（未下沉）与 signal 7.2ms，留作下一专项。

**v0.33.0 版本化实现约束（代谢热点下沉 + 原生源码入库）**：用户决策「C++ 源码与 DLL 应入库以便回溯」，撤销 v0.31「二进制不入库」约定：新增工作区 `native/`（C++ 源码、逐位探针、构建脚本、`README.md`），入库 `godot/cellarium-release/bin/` 下 `.gdextension` 与 DLL；`.gitignore` 只排除编译中间产物与第三方 `godot-cpp` 副本，`extension_api.json` 不入库但记录 SHA-256 与导出命令。**实现**：新增 C++ `CellMetabolism.compute_environment_batch()`，把 `_apply_environment_metabolism_ranges()` 的纯计算段（呼吸规则、摄食增益、运动能耗、毒性标志）整段下沉；中间值用 `PackedFloat64Array` 返回以保留 double，避免多一次 float32 舍入改变 state hash；场消耗、能量账本、毒性伤害与死亡判定等副作用仍留在 GDScript 原顺序。`native_spatial_enabled` 默认 false、DLL 缺失逐段回退的边界不变。**硬闸门**：`metabolism_parity_probe` 逐位对照（1354 活细胞、`max_abs_diff=0`）、双工程 240 tick `get_state_hash()` 逐位一致（1356695503）、双工程 SmokeTest 与四探针全过。冻结边界全部不动。实测同会话 A/B：3000 细胞全 tick 230.2→43.9ms（5.25×），`metab_env` 20.42→5.60ms（3.64×）；1000 档首次 `budget_met=true`。**距 ≤8ms/tick 仍远（3000 档 `cpu_budget_met=false`），不表述为达标**；新瓶颈 `metab_lifecycle` 7.15ms。

**v0.22.0 缺陷修复（去掉 depth 分裂闸门）**：Cell Lab `e(double)` 无 mode depth 闸门，分裂次数由端粒 `T∈{-1,5,10,20,40,80}` 控制；本项目 `cell_telomere` 已承担该角色。v0.20.0 遗漏的第二套闸门（`depth >= mode.max_divisions` + 母细胞 depth+1）使自增殖模式（默认 `max_divisions=1`）每细胞分裂一次即锁死、卡在 4 细胞。本版删掉该闸门、母子 depth 不再累加（继承原值，自增殖恒 0），分裂次数统一由端粒控制；`cell_mode_depth` 字段/存档/hash 兼容、不升 schema；`GenomePreview` 三条派生路径同步去掉 depth 限制（预览步数仍由顶层 max_divisions 约束）。GNP1、tick 顺序、单帧 12 tick 上限不动。SmokeTest `OK v0.22.0` 验证 max_divisions=1 自增殖突破旧上限达 ≥8 且 depth 恒 0。

**v0.21.0 版本化追加（分裂倍增 / 半圆出生形状 / 发育预览分裂指示器）**：Cell Lab `CellWorld.e(double)` 逐细胞独立判定分裂、无 per-organism cooldown（同一 tick 所有成熟且能量达标者同时分裂 → 1/2/4/8 倍增）；出生时母子各偏分裂轴 `0.1r`（中心距 `0.2r`）、半径保留母半径、零力，靠下一 tick 接触弹开成两个半圆；Macro `GenomeEditorFragment` 有 `checkbox_show_split_indicators`。实现：① 分裂调度从 per-org 闸门改为逐细胞 cooldown，`CellArray.cell_division_tick`（上次分裂 sim_tick）进 hash/存档、schema v7（旧档填 -2），schema v6→v7 升级；② 出生间距 `max(0.5, 0.2·r·scale)`、母子各偏 `0.1r`、半径当帧不变、连接静止长度仍 `2r`，分裂在 metabolism 阶段（碰撞之后），下一 tick 接触排斥弹开；③ `GenomePreview.show_split_indicators` 纯绘制叠加切面线+方向箭头，新增 `get_split_count_at` / `get_split_angle_at` 只读接口。GNP1 二进制布局、tick 顺序、单帧 12 tick 上限不动；并行倍增改变默认演示体与旧快照的细胞数轨迹（由 max_divisions 链与能量减半约束上限）。

**v0.19.0 版本化追加（半径-能量低通 / 视图重建热点优化）**：Cell Lab `CellWorld.f(double)` 证实半径对 `d²` 一阶低通、稳态 `d_target = sqrt(w)/20`（分析文档 §2）。实现口径：`CellArray` 增 `cell_radius_baseline`（基因表型）与 `cell_energy_scale`（能量因子），`cell_radius_scale` 保持为有效倍率 = 二者之积，物理/渲染/分裂间距读取点不变；每 tick 在 metabolism 阶段调用 `_apply_energy_radius_relaxation(dt)`，以该细胞模式 `division_mass` 为 `E_ref`，`target² = clamp(E/E_ref, 0.5², 1²)`，`s² ← s² + (target² − s²)·5·dt`。仅 gene_mode 生效，非基因模式与开关关闭时保持 v0.18 固定倍率；纯标量、固定索引顺序、不写 RNG。schema v6 保存两个新数组（旧档 baseline=旧有效倍率、因子=1.0），数组纳入 `get_state_hash()`；GNP1、tick 顺序、单帧 12 tick 上限不动。视图侧把 `_build_shared_chords` 的字符串 pair key 改为整数打包，`CellView.outline_segments` 可配置（`CellBase.tscn`=48、独立实例默认 64），只优化渲染开销、不改模拟状态与 hash。

**v0.18.0 版本化追加（个体规模上限修订、连接数抑制分裂、端粒）**：Cell Lab 静态证据只有全局 `Cell[]` 对象池、每细胞连接上限、`P <= Gene.u[9]` 与端粒 `T`，没有显式 per-organism max cell count；本项目把旧的「每个个体最多 8 个细胞」从技术基线降级为兼容回退值。实现口径：`Genome.max_cells_per_organism = -1` 表示无限，非负值才作为个体细胞数上限；旧 payload/schema 缺字段时按 `max_divisions + 1` 回退，保证 v0.17 及更早行为不变；默认演示体显式设 4。全局保护改由 `CellArray.max_cell_capacity`（默认 8000）承担，所有新增细胞/分裂路径都在触顶时拒绝。逐模式 `link_division_limit` 实现「连接数达到上限则抑制分裂」（`-1` 关闭；旧模式缺字段回退 `-1`），逐模式 `telomere` 实现 Cell Lab `Gene.B[6]` 式谱系分裂次数（`-1/5/10/20/40/80`；有限值在分裂时母子同减，归零死亡）。新字段不进 GNP1，经 `CommandBus genome_gene` 与 `schema_version=5` 保存，基因模式显式混入 hash；tick 顺序与单帧 12 tick 上限不动。

**v0.17.0 版本化追加（多模式基因组与连接传递）**：基因模式从单套顶层字段升级为 `Genome.modes: Array[Dictionary]`。用户提供的 Macro 截图可核对「模式切换 / 当前类型 / 两子代模式 / 保留黏附素与镜像 / 分裂质量与质量比 / 营养优先级 / RGB / 黏附强度长度拉伸 / 骨架强度 / 细胞大小 / 连接上下限 / 特殊控制 / 可点击发育预览」；但 40 Gene 槽全量语义、行为总线全索引与 `Gene.f773m` 运行时消费点仍无逐行证据，因此只做版本化追加，不宣称等价移植。实现口径：每个模式只定义两个子代，母细胞索引成为子代 1、新细胞成为子代 2；`CellArray` 增 `cell_mode` / `cell_mode_depth`；连接传递率逐模式派生（默认 0.12），`CellMetabolism` 守恒公式不变；`modes` 经 `CommandBus` 的 `genome_gene` payload 与 `schema_version=4`（1–3 可恢复）保存，仅 `modes` 非空时混入 hash，GNP1/tick 顺序/单帧 12 tick 上限不动；空 modes 与 flags 清零保持 v0.16.0 及更早行为。默认演示体改为 5 模式/3 次分裂/4 细胞/3 连接。

**v0.16.0 版本化追加（基因模式补齐 Macro 表型字段）**：在 `FLAG_GENE_MODE` 置位的基因组上追加 `nutrition_priority` / `cell_stiffness` / `cell_size` / `max_connections` / `min_connections` / `color_r|g|b`。证据边界：Cell Lab 静态反编译确认 `seek_prio ↔ Gene.f773m`、`seek_stiff ↔ Gene.f774n`、`Gene.u[9]` 连接数上限、`Gene.a[3]` 颜色与 `Gene.z/A[6]` 0.5–2 范围；**`Gene.f773m` 的运行时消费点与独立「最小连接数」控件没有证据**，这两项明确记为本项目的版本化追加，不宣称等价移植。实现上：营养优先级只调异养/光合摄能权重（0.5 等价旧版），骨架强度只调接触分离系数（0.5 等价旧版 1.0），细胞大小写逐细胞 `cell_radius_scale` 并同时供物理碰撞/皿壁投影/共享弦使用；最大连接数阻断新增连接，最小连接数只在分裂后按同个体索引顺序补连。颜色只覆写视图基色。新增逐细胞数组随 `schema_version=3` 保存（1–2 恢复时填默认值），新基因字段显式混入基因组 hash；`flags` 清零时全部保持 v0.14.x 行为与 hash，GNP1 布局、tick 顺序与单帧 12 tick 上限不动。

**v0.15.0 版本化追加（基因驱动发育 / 移除指令序列）**：`Genome.flags` 位 1 置位进入基因模式——不再执行 `dev_program`，改用 `division_mass`（分裂能量阈值，Cell Lab `Gene.b`）、`split_ratio`（`Gene.c`）、`max_divisions`、`child_types`（`Gene.i/j` 分裂即分化）、`split_angles` 决定分裂；`LINK` / `DIFFERENTIATE` 指令对新基因组移除，连接仍由位 0 黏附素决定。这些字段不进 GNP1 冻结二进制，随存档 `schema_version=2` 版本化保存，命令走 `CommandBus` 的 `genome_gene` payload，并显式混入基因组 hash；零值 flags 完全保持 v0.14.x 指令模式与 hash。`register_zygote()` 中 `add_developed_cell()` 会覆写状态为 DEVELOPING，基因模式必须在之后恢复 MATURE，否则能量再高也不会触发自主分裂。

**v0.14.1 版本化追加（flags 位语义）**：给 GNP1 已编码、此前未使用的 `flags` 位 0 赋予语义——「生成黏附素即亲子自动连接」。置位后 `DIVIDE`（含成熟个体的自主分裂）执行完即在亲子间建立弹性连接，无需显式 `LINK` 指令；清零则保持 v0.14.0 及以前行为。**不新增字段、不改 GNP1 冻结布局、不改五通道 schema**；因 hash 覆盖编码后的 flags，置位基因组 hash 会变化，属于有意的新版本语义。生态报告新增只读能量流诊断（产能 / 自身耗能 / 连接转出 / 连接转入 / 捕食流失），逐 tick 覆盖派生，不写模拟状态、不进 hash、不进存档。

**v0.14.0 版本化追加（已修订 v1.0 §2.2）**：借鉴 Cell Lab `Food[]` 的定长对象池方法，新增**只读派生的食物实体池**——一次性分配固定容量、池尾交换回收、质量按 tick 线性衰减、涂层比例字段；实体由营养场源项的确定型投放位置派生，只承载可见颗粒与诊断位置，**能量真相仍是五通道营养场**。食物实体不写入能量结算、不进确定性 hash、不修改五通道 schema；如需让其参与摄能，须再次修订 v1.0 并版本化升级快照 schema。

**关键决策：战役目标放在表现层，不进模拟内核。** 视频中的关卡目标（如"生产者至少 60 只、采集者至少 20 只、捕食者至少 6 只"）与 v1.0 的"无适应度进化"并不矛盾——目标只是 UI 层的条件判定与结算，绝不参与生物的能量分配、繁殖概率或突变方向。判定器只读统计快照，不写模拟状态。这样既保留视频里的目标感，也守住"物种存续完全由环境自然筛选"的设计底线。

### 0.4 术语表

| 术语 | 含义 |
| --- | --- |
| Tick | 一次固定步长的模拟推进，逻辑 dt 恒为 1/60 s，与渲染帧率解耦 |
| 场（Field） | 覆盖培养皿的二维标量网格，GPU 侧以纹理存储，5 类场共存 |
| 位点（Locus） | 基因组上可装配一种功能细胞的位置，初始 8 个，可因重复/缺失突变增减 |
| 性状（Trait） | 8 项全局浮点属性，影响所有细胞的基础参数 |
| 发育程序 | 基因组中决定"受精卵如何分裂、分化、连接"的指令序列 |
| 细胞（Cell） | 个体内的最小模拟单元，由发育程序生成，归属唯一 `org_id`；不是独立个体，不单独参与谱系与物种判定 |
| 细胞类型（Cell Type） | 发育期由 `DIFFERENTIATE` 指令指定的运行时角色，决定产能 / 耗能 / 运动 / 感知 / 保护行为 |
| 细胞内再分配 | 能量沿弹性连接在个体内细胞间转移；只改变 `ΣE_cell` 的内部构成，不改变个体总能量与 `E_total` |
| 谱系（Lineage） | 由唯一 ID + 父代 ID 构成的父子关系图，物种分化节点挂在其上 |
| 语义 ID | 每个可交互控件与每条 Agent 命令的全局唯一字符串，供自动化定位 |
| SoA | Structure of Arrays，按字段分数组的运行时数据布局，便于批量与 GPU 上传 |

## 0.5 外部参考原型核对与借鉴决策（v2.1 增补）

### 0.5.1 一手资料清单与可信度边界

| 参考原型 | 一手来源 | 性质 | 可引用范围与边界 |
| --- | --- | --- | --- |
| Substrate: Emergence | Steam 商店页与 `appdetails` 接口，App ID 4248790 | 商业游戏公开文案（Early Access，2026-09-24 发售，Petri Dish Games LLC） | 可引用商店长描述、最低/推荐配置、类别与无障碍项；**无源码、无技术文档**，内部实现不可考，不得据营销文案推断其算法 |
| Cell Lab | 官网 `cell-lab.net`（含其转载的 Play 商店完整特性列表） | 已发行 Android 游戏官方介绍，开发者 Petter Säterskog | 可引用 45 挑战、16 细胞类型、20 cell-modes、22+ 参数、27 环境参数、1000 细胞等官方数字；玩法细节以官网文字为准 |
| Cell-Lab-Remake | GitHub `jtalbert123/Cell-Lab-Remake` 仓库 README | 获原作者许可的社区重制尝试（未完成） | 仅 README 自述可引用；**不是官方 PC 版**，实现未完成，不作工程基线 |
| ALIEN | GitHub `chrxh/alien` README 与 `resources/docs/*.md` | 开源工程，文档齐全，BSD 3-Clause | 机制与架构可核对到一手文档；**只借鉴概念，不复制代码或文档原文**，遵守许可证署名与免责要求 |

核对日期：2026-11-11。Steam 的完整长描述与系统要求此前一度抓取失败，v2.1 已通过 `appdetails` 接口补全；所有引用以本次核对到的一手文本为准。

### 0.5.2 直接回答：Cell-Lab-Remake 是不是 Cell Lab 的 PC 版？

**结论：它是"获原作者许可的 PC 版复刻尝试"，但不是官方 PC 版，也不是可玩的正式移植成品。** 三层辨析如下：

| 判断 | 依据 |
| --- | --- |
| 确实自称"PC version"且获授权 | README 首句原文：`A PC version created with permission from the original developer.`；原开发者为 Petter Säterskog（Cell Lab 官网载明） |
| 不是官方发布 | 官网明确写 `Cell Lab is a simulation game for Android.`，官方形态仍为 Android 应用；该仓库由第三方个人维护，自述 `I am new to the whole game making thing`，并公开招募开发者、美术与"懂 Cell Lab 机制的人"帮忙核对 |
| 不是成品 | 技术栈为 Unity + C#（另含 WinForms 工程与 Builds 目录），README 写 `At some point I hope to get it on Steam Greenlight, but that's a *long* way off for now.`；提交集中在 2017 年前后，无上架记录 |

因此本文把它定位为**玩法复刻的旁证**：它证明"参数化基因组 + 挑战/实验双模式"在 PC 上被社区尝试复刻过，但不作为技术选型、性能或数据格式的依据。它给本文最有价值的一条工程教训是——复刻者需要专门招募人"确保机制与原作一致"，这正对应 §9.3 的 golden run 基线与"规则以 v1.0 为唯一事实源"的约定。

### 0.5.3 借鉴决策总表

标记含义：**采纳** = 已在本版落地或补强；**部分采纳** = 只取机制、缩小范围或列为可选项；**不采纳** = 明确排除，避免破坏 v1.0 规格。

**Substrate: Emergence**

| 机制（一手依据） | 决策 | 本文落地 / 排除理由 | 章节 |
| --- | --- | --- | --- |
| 每个细胞都有独立基因组、外观由基因决定，且每个细胞跑一个由演化塑造的小型神经网络（`Every cell has its own genome...Each cell runs on a small neural network shaped by evolution`） | 部分采纳 | 本文是"每生物一份基因组、每细胞一个神经节点"：基因组池去重（§3.3 `org_genome_id`）、谱系与物种判定按生物个体（§4.7）。若改成每细胞独立基因组，谱系口径、突变结算与存档体积都会失控 | §3.2、§3.3、§4.6、§4.7、§5.2 |
| 模拟跑在 GPU compute shader 上；最低要求 DirectX 12 / Vulkan 1.1 且注明 `The simulation runs on GPU compute shaders`、Linux 下 `OpenGL cannot load the simulation shaders`；集显 2 GB 走 Low，独显 6 GB 走 High/Ultra | 采纳（路线佐证） | 独立佐证 §1.1 / §1.3 / §8.2 的 GPU 主线与画质分档思路；**但不采纳"无 CPU 回退"**——Godot 需覆盖 Mobile/Compatibility 渲染器、CI 与无 GPU 教学环境，故保留功能等价 CPU 回退并由 T12 常态验证 | §1.1、§1.3、§8.3、T12 |
| 挑选最有希望的细胞、引导突变、触发化学反应、必要时直接接管单个细胞（`Pick out your most promising cells and shape how they evolve...`） | 部分采纳 | 挑选 / 隔离 / 投放已作为玩家工具与 Agent 命令存在（§6.5、§7）；"引导突变方向"**不采纳**（等于引入适应度，违背 v1.0）；"接管单细胞"仅列为 §6.8 开发者模式的后续候选，本版不做 | §6.5、§6.8、§7 |
| 对手实验室、Bionet 领地、占区断粮、把化学当武器（`claim zones to starve them of resources, and use chemistry as a weapon`） | 不采纳 | 多阵营对抗与胜负条件属于玩法扩张，与单皿沙盒 + 无适应度冲突；其中"化学信号可作为空间竞争媒介"已被本文 5 类场中的化学信号场覆盖，无需引入阵营 | §0.3、§3.4、§11 |
| 菌株目录、跨代家族树、把最优细胞精炼成超级菌株（`Catalogue your strains, trace their family trees...`） | 采纳 | 对应物种库（§6.3）、谱系树（§4.7）、生态报告（§6.7）与存档分支（§3.5）；"精炼"由玩家在设计器里手动完成，内核不设选育算子 | §3.5、§4.7、§6.3、§6.7 |
| 可调字号、色彩替代、对比度控制、无需限时输入、随时存档；Windows + Linux（含 Steam Deck） | 采纳 | 补进 §5.4 无障碍行；"无需限时输入"与暂停 / 单步（§2.6）一致；Linux 支持与 §1.1 的"后续"一致，列为阶段 6 之后的验证项 | §1.1、§2.6、§5.4 |

**Cell Lab**

| 机制（一手依据） | 决策 | 本文落地 / 排除理由 | 章节 |
| --- | --- | --- | --- |
| 45 challenges + experimental mode：挑战解锁基因、自由环境编辑、随机基因组播种后观察其经微小突变适应环境 | 部分采纳 | 官方同样是"挑战关 + 自由实验"双模式，直接佐证 §6.6 的实验层与核心沙盒分层；**不采纳"通关解锁基因"式进度锁**，v1.0 沙盒全开放 | §0.3、§6.6 |
| 16 种细胞 / 每基因组 20 个 cell-modes / 每 mode 22+ 参数 / 环境编辑器 27 参数 | 采纳（思路） | 佐证"数据驱动的参数化基因组"：本文用 `.tres` 定义 + 位点与性状量化 + 附录 B 参数集中（§3.1、§3.2）；但不照搬 22+ 参数/细胞的复杂度，阶段 1–2 格式冻结前控制规模 | §3.1、§3.2、附录 B |
| 最多模拟并渲染 1000 个细胞仍保持流畅（移动端、矢量图形、可缩放至原子尺度） | 采纳（量级旁证） | 本文桌面目标 1000 生物 / 8000 细胞、软上限 3000 / 24000（§8.1），量级合理；视觉思路对应 §5.1 双标尺与 §5.2 三档 LOD + MultiMesh 色块，不追求"原子尺度"叙事 | §5.1、§5.2、§8.1 |
| 保存 / 加载 / 分享环境与基因组；快进与慢放 | 采纳 | 已有 §3.5 存档、§6.3 物种库、§7 `gene.export/import`、§2.6 倍速与单步；"分享"本版以文件导出为界，不做联网分享；慢放由暂停 + 单步覆盖 | §2.6、§3.5、§6.3、§7 |
| 官方声明 `This simulation is not biologically realistic`，每个细胞只承担一种功能（游动 / 进食 / 集光 / 漂浮） | 采纳（口径佐证） | 与 v1.0 的 16 种功能细胞"分工模型"口径一致，可作为细胞体系设计合理性的旁证；不因此改动 v1.0 的细胞清单 | §3.1、§4.2 |
| 无广告、无内购 | 采纳 | 与 §0.3 的单机范围一致，本版不含任何商业化模块 | §0.3 |
| 分化谱系 + 黏附连接 + 连接内物质交换，使不同细胞类型组成多细胞个体并协作（2026-11-15 静态反编译证据，见 `analysis/CellLab_多细胞协作_设计规格.md`） | 部分采纳（机制） | 只借鉴「局部规则生成形态 / 类型分工 / 连接内经济 / 簇级保护」四条机制；v1.0 §5.3 已有显式个体与发育程序，保持规约式身份模型，不改成 Cell Lab 的涌现式连通分量。**不采纳** 40 Gene 槽分化树、95 个突变算子、端粒、受精、病毒基因注入、每细胞独立基因组 | §0.6、§3.3、§4.3、§4.4、§4.5、§11 |

**Cell-Lab-Remake**

| 机制 / 事实 | 决策 | 本文落地 / 排除理由 | 章节 |
| --- | --- | --- | --- |
| README 自述为获许可的 PC version，Unity + C#，含 Unity Project / WinForms Project / Builds，未上架 | 不采纳（作工程基线） | 技术栈与 Godot 无关，完成度不足；仅用于回答"是不是 PC 版"的疑问与佐证玩法复刻的可行性 | §0.5.2 |
| 公开招募熟悉原作机制者帮忙核对（`make sure I get the mechanics right`） | 采纳（教训） | 复刻类项目最常见的偏差来源是机制走样；本文以 v1.0 为唯一事实源，并用 §9.3 golden run 与命令脚本回归资产锁定行为 | §9.3、附录 A |

**ALIEN**

| 机制（一手依据） | 决策 | 本文落地 / 排除理由 | 章节 |
| --- | --- | --- | --- |
| `Evolution without a fitness function`；`Energy never appears out of nothing.`，能量在细胞、自由能量粒子与可选外部池之间循环 | 采纳（交叉验证） | 与 v1.0"无适应度进化"及本文 §4.3 守恒校验完全同构，作为独立工程佐证；据此把守恒式形式化为包含外部能量池的记账（见 §4.3） | §0.3、§4.3、§11 |
| 外部能量池 + 能量回流（backflow）、辐射源与分层（Layers / 线性力场）让参数随空间变化 | 部分采纳 | 本文已有洋流矢量场与 `SourceOp`（§3.4、§4.1）；v2.1 追加 `EnvironmentPreset.layers[]` 可选字段表达区域参数覆盖（热泉 / 光照区共存），并明确"不设全局重力参数"，力由层与场产生；**自动回流机制本版不启用**，只保留守恒记账 | §3.1、§3.4、§4.1、§4.3 |
| 三层基因组（Genome / Gene / Node）、constructor 逐细胞构建后代、8 种形状生成器、编辑器实时表型预览 | 部分采纳 | 佐证 §3.2 / §4.4 的发育程序与 §6.3 样本培养舱实时预览；本文用紧凑 u32 指令流而非基因/节点图，更利于 `GNP1` 二进制、确定性回放与存档体积；"逐细胞构建"作为 §4.4 发育 tick 预算上限的依据 | §3.2、§4.4、§6.3 |
| 突变率写进每个基因组并可自我演化（meta-mutations）；文档给出 0.001–0.01 的合理起点 | 采纳（参数旁证） | 与 §3.2 `mutation_rate_exp`、§4.7 元突变一致；附录 B `base_mutation_rate = 0.001` 乘 `pressure_mutation_mult ≤ 4.0` 后上界 0.004，落在 ALIEN 建议区间内，调参有据 | §3.2、§4.7、附录 B |
| 每 6 个 time step 一个细胞周期；16 输入 / 12 输出，其中 8 路信号 + 4 路记忆；多种激活函数 | 部分采纳 | 本文 §4.6 固定 8 输入 / 6 输出，§2.6 倍速 LOD 中"神经每 2/4/8 tick 更新"与 6-tick 周期同构；信号通道与记忆输出仅作为 `GNP1` 的 `flags` / `reserved[]` **预留位**，本版不实现，避免格式冻结前扩字段 | §2.6、§3.2、§4.6 |
| 15 类细胞（sensor 64 条扫描射线、attacker / digestor、injector 基因组接管、muscle、communicator、constructor 等） | 采纳（对照） | 与 v1.0 的 16 种功能细胞同属"功能分工"模型，可作为细胞能力清单的对照检查表；**不改写 v1.0 细胞规格** | §3.1、§4.6 |
| 内置 MCP server（`127.0.0.1:8765/mcp`）、命令日志保留最近 1000 条、工具按用途分组；`alien-cli` 无窗口跑批 | 部分采纳 | 佐证 §7 本地 Agent 通道与 `--headless` 回归（§9.1）；本版保持 JSON Lines + 17 个上游接口冻结，MCP 适配层与 `agent.get_command_log()` 列为 v2.2 候选（§7.5），**不进本版契约** | §7.5、§9.1 |
| CUDA / HIP 全 GPU 粒子引擎、Vulkan 渲染与互操作、实时百万粒子 | 不采纳（规模） | 佐证 GPU 路线，但本文用 Godot `RenderingDevice` compute 保持跨平台与零第三方依赖（§1.1）；规模目标见 §8.1，明确不追求百万粒子，避免过度设计 | §1.1、§8.1、§8.2 |
| BSD 3-Clause 许可 | 采纳（合规） | 只借鉴概念与公开机制描述，不复制源码、资源或文档原文；如需引用代码片段须按许可证保留版权与免责声明 | §0.5.1、附录 A |

### 0.5.4 本次增补对文档的影响清单

| 章节 | 增量 | 是否影响冻结契约 | 验收 |
| --- | --- | --- | --- |
| §1.1、§1.3 | 明确"GPU 主线 + 必须保留 CPU 回退"的取舍与探测降级 | 否 | T12 |
| §3.1、§3.4 | `EnvironmentPreset.layers[]` 可选区域覆盖；化学信号场定位为中立场通道 | 否（`EnvironmentPreset` 未冻结，版本化追加） | T14 |
| §4.3 | 守恒式加入 `E_external` 记账，工具干预形式化为 `E_external ↔ E_env` 转移 | 否（只做记账形式化，不改玩法规则） | T07、T13 |
| §4.4、§4.6 | 发育 tick 预算的依据、神经信号/记忆通道预留位 | 否（仅预留位） | T05 |
| §4.7、附录 B | 突变率区间旁证、调参上界与三个新增可选参数 | 否 | T01、T08 |
| §5.4 | 无障碍项补齐（字号、对比度、色彩替代、随时存档、无需限时输入） | 否 | UI 自动化 |
| §7.5 | MCP 适配与命令日志列为 v2.2 候选 | **否（本版 Agent 契约不动）** | 不验收 |
| §8.1、§11 | 规模量级旁证、范围蔓延风险入表 | 否 | 评审检查 |
| §9.2 | 新增 T13 外部能量池守恒、T14 区域参数覆盖 | 否 | T13、T14 |
| 附录 A | 四个原型加入参考映射与引用边界声明 | 否 | 文档检查 |
| §0.6、§0.3、§3.1–3.3、§4.3–4.5、§11、附录 A / B | P0 多细胞个体与细胞协作增补 | **否**（细化 v1.0 §5.3，未改冻结契约；条款已于 2026-11-15 并入工作区 v1.1 合并稿 §5.3.1–§5.3.5，v1.0 DOCX 原件保留不改） | 待 P1 补入 §9.2 |

**边界声明**：本节所有"采纳"项都不得反过来修改 v1.0 玩法规则；若未来需要引入领地对抗、适应度引导、每细胞独立基因组等"不采纳项"，须先修订 v1.0，并同步更新本文 §0.3、§0.5.3 与 §11。

### 0.6 P0 修订索引与依据（2026-11-15）

**依据**：`analysis/CellLab_APK_解析报告.md` §11 / §12 与 `analysis/CellLab_多细胞协作_设计规格.md`。证据为 REA / JADX 0.7.1 对两版 APK 的静态反编译，APK 未执行；Cell Lab 官方包内不存在 `Organism` / `Group` / `Colony` 类，"个体"是 `Link` 连接图的连通分量，属涌现式，本项目保留 v1.0 §5.3 的显式个体模型。

| 修订点 | 章节 | 性质 |
| --- | --- | --- |
| 个体身份边界仍由 `Organism` 承担，细胞不单独参与谱系 / 物种判定 | §0.3、§3.3、§4.2 | 细化 v1.0 §5.3 |
| 细胞类型 / 位点装备 / 全局性状三者层级澄清 | §0.4、§3.1、§4.4 | 术语消歧，不改规则 |
| 细胞内沿连接的能量再分配纳入守恒记账 | §4.3 | 记账细化，`E_total` 不变 |
| 协作产生的个体级属性（簇级保护、整体形变、供养、规模约束） | §4.4、§4.5、§11 | 新增实现约束 |
| Cell Lab 机制采纳边界与不采纳清单 | §0.5.3、§11、附录 A | 防范围蔓延 |
| GNP1 冻结布局不动；发育程序本就在 §3.2 变长段内 | §3.2 | 澄清，无格式变更 |
| 可选参数与后续验证项 | 附录 B、§9.2 | 待阶段 1–2 调参 |

**不采纳项**（本次明确排除，若将来引入须重新修订 v1.0）：95 个突变算子、端粒（v0.18 已单列版本化追加）、受精、病毒基因注入、Macro 的 15 种新增类型与 101 通道信号、每细胞独立基因组、任何形式的适应度引导。**40 Gene 槽分化树已于 v0.29.0 按 §0.3 版本化采纳，不再属于不采纳项**，但其完整 40 槽行为总线仍未穷尽，不宣称等价移植。

**与化学信号子系统的边界**：报告 §12.7 的 4 通道化学信号是每细胞私有的旁路行为参数总线，与本次多细胞结构层**并行但不合并**；两者共用 `CellArray` 提供的连接遍历。v1.0 §2.2 已定义"化学信号场"，其口径与独立子系统的差异留待该子系统立项时单独修订，本次不动。

### 0.7 单细胞个体与发育深度轴（2026-11-15 第二轮增补）

**依据**：用户 2026-11-15 四项决策；玩法条款见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §5.3.6 / §5.4.1 / §7.5。本节只给实现约束，**不改 §3.2 GNP1 冻结布局、不改 §4.3 守恒式、不改 §7 Agent 契约**。

| 玩法条款 | 实现落点 | 约束 |
| --- | --- | --- |
| 术语统一（细胞器 / 表达型） | `OrganelleDef.tres` + `CellArray.expression_weights: PackedFloat32Array` | `ExpressionProfile` 只是 UI 显示名，**不进模拟计算、不进存档**；不新增第二张类型清单 |
| 最小自治核 | `capability = basal × basal_autonomy + Σ(w_i × organelle_i.effect)` | 细胞器只放大系数，禁止实现成能力开关；细胞脱离连接后效率下降而非立即死亡 |
| 发育深度轴 | `dev_program[]` 中 `DIVIDE` 条数 → `cell_count` | 0 条 = 单细胞个体；`cell_count == 1` 且无 `DIVIDE` 时生命周期直接进 `MATURE`；不新增内核 |
| `DIVIDE` / `REPRODUCE` 分离 | 两个独立命令对象，均走 `CommandBus`，在下一 tick 执行 | `DIVIDE` 不产生 `org_id`、不写谱系；`REPRODUCE` 产生新 `org_id` + 父代 ID，多细胞个体从新受精卵重建而非对半切分 |
| 重复装备税 | 维护费 `Σ(w_i × cost_i) + k × (Σ w_i)²` | 保证「每个细胞全能」不会退化成 N 个单细胞粘在一起；参数进附录 B |
| 培养基参数 | `EnvironmentPreset.nutrient_density`（皿级只读标量）→ `basal_autonomy` | **不硬编码**；随存档 / 快照 / 回放序列化；局部营养场仍只影响摄能速率；tick 内只读，不得临时改写 |
| 可塑性接口预留 | `DevelopmentContext.gd`（`RefCounted`、无 `class_name`、调用方 `preload`） | 只读快照：`environment_summary` / `nutrient_density` / `max_dev_depth`；**v1 不接入发育决策**，`dev_program[]` 是唯一真相源；不进冻结的存档 schema |

**确定性约束**：上述新增量中只有 `expression_weights` 与 `cell_count` 是模拟状态；`basal_autonomy` 属于环境预设，在 tick 开始前绑定一次，回放必须写入快照。任一新增接口都不得在 tick 内读取环境场去增删发育指令。

**工程与开发方式（用户决策）**：新建独立工程 `D:\Tools\Godot_v4.7.2\project\cellarium\`，Genesis 保留为参考基线不删除。后续开发通过 **Godot MCP** 操作编辑器，**节点结构、属性与信号在 `.tscn` 场景中声明，脚本只承担必要逻辑**，不用纯代码堆砌场景树。无头编辑器需设置 `GODOT_AI_ALLOW_HEADLESS=1`，否则插件默认在 headless 模式禁用（已实测）。

**v1 明确不做**：环境诱导的发育深度可塑性（同一基因组按环境改变 `cell_count`）。接口只预留，不得成为第二真相源，也不得写入当前 tick 路径。

## 1. 技术基线

### 1.1 选型

| 项目 | 选择 | 理由 / 约束 |
| --- | --- | --- |
| 引擎 | Godot 4.3+，团队锁定同一小版本 | v1.0 基线；Compute Shader 依赖 `RenderingDevice`，需项目启动时探测能力 |
| 语言 | GDScript 为主，重计算模块预留 GDExtension(C++) | 迭代快、与编辑器集成好；只有当 benchmark 证明 GDScript 成为瓶颈才引入 C++，且不早于阶段 6 |
| 渲染器 | Forward+ 优先；Mobile/Compatibility 走 CPU 回退路径 | 计算着色器与存储纹理在低端渲染器上不保证可用，必须有一条能跑通全部玩法的 CPU 实现 |
| 物理 | 自研 Verlet + 空间哈希，不使用 PhysicsBody2D | 上万个细胞节点会压垮场景树与物理服务器；自研方案可控、可确定性、可批量 |
| UI | Control 节点 + 自定义 Theme，不用外部 UI 框架 | 视频中的深色科技风需要大量自绘，Control 足够且无依赖 |
| 平台 | Windows 桌面优先（1920×1080 基准，1280×720 最小），Linux 后续 | 长时间满载会显著发热，benchmark 场景须限时运行（见 §9.4） |
| 依赖 | 运行时零第三方依赖；测试期引入 GUT | 避免插件锁死引擎版本 |

**参考对照（v2.1，详见 §0.5）**：`Substrate: Emergence` 把 compute shader 设为运行硬门槛（最低配置要求 DirectX 12 / Vulkan 1.1，明确"模拟跑在 GPU compute shaders 上"，Linux 下 OpenGL 无法加载模拟着色器），并以 2 GB 集显 / 6 GB 独显划分 Low 与 High/Ultra 画质档；`ALIEN` 则用 CUDA/HIP + Vulkan 互操作跑百万级粒子。两者都佐证本文的 GPU 主线与画质分档思路。**本文与它们的关键差异是保留功能等价的 CPU 回退**：Godot 需覆盖 Mobile / Compatibility 渲染器、CI 与无 GPU 教学环境，因此"compute 不可用"不算启动失败，而是切换到 `CpuFieldBackend` 并由 T12 常态验证。规模上也不对标百万粒子，目标见 §8.1。

### 1.2 项目设置基线

| 设置 | 值 | 说明 |
| --- | --- | --- |
| `application/run/main_scene` | `res://scenes/main/Main.tscn` | 唯一入口 |
| `display/window/size/viewport_width/height` | 1920 / 1080 | `canvas_items` 拉伸模式，`expand` 宽高比 |
| `rendering/renderer/rendering_method` | `forward_plus` | 启动探测失败时提示切换 CPU 回退 |
| `physics/common/physics_ticks_per_second` | 60 | **仅用于 UI 动画**；模拟不使用 `_physics_process` |
| `application/run/max_fps` | 60 | 限时避免空转发热 |
| `debug/settings/fps/force_fps` | 关闭（发布版） | 开发者面板可临时开启 |

### 1.3 引擎能力探测

启动时由 `PlatformCaps` 一次性探测并写入 `DebugFlags`，后续所有系统只读结果：

| 能力 | 探测方式 | 不满足时的降级 |
| --- | --- | --- |
| Compute Shader | `RenderingServer.get_rendering_device()` + 编译最小 compute 管线 | 环境场扩散改 CPU 多线程实现，粒子物理降级为 LOD 简化 |
| 存储纹理浮点格式 | 尝试创建 `R16G16B16A16_SFLOAT` 带 `STORAGE_BIT` | 退回 `R8G8B8A8_UNORM` 归一化编码，精度降低但功能不变 |
| 线程数 | `OS.get_processor_count()` | 最小 2，WorkerThreadPool 组数按此裁剪 |

探测结果写入 `DebugFlags` 后不得在运行时反复查询；降级路径的**功能等价性**由 T12 保证（禁用 compute 后重跑 T03 / T10，允许精度与性能下降，不允许玩法缺失）。画质档与 compute 档分离：前者只影响 LOD 与后处理，后者决定场求解后端。

**实现补充（v0.9.0 / 阶段 10）**：GPU 后端下场缓冲常驻 GPU，逐细胞采样用独立 compute pass 写入 `N×5` 小 buffer 后回读；`consume()` 以聚合后的 `(格,通道)` 增量在下一 tick 由 GPU scatter pass 写回。全量 `5R²` 回读只在快照 / `get_state_hash()` / 存档 / 显式地形与温度编辑时惰性发生，不再属于每 tick 路径。该补充只改变宿主与 GPU 之间的数据搬运，不改变 §2.2 场定义、§2.4 确定性约束与 T12 回退要求；CPU 回退仍以同一采样语义重跑（批量采样 API 与逐点采样一致的断言已加入 SmokeTest）。

## 2. 系统架构

### 2.1 分层与依赖方向

| 层 | 内容 | 允许依赖 | 禁止依赖 |
| --- | --- | --- | --- |
| L0 Core | 纯数据类：Genome、Traits、SimConfig、IDs、CRC、RNG、数学工具 | 无（不 `extends Node`） | 任何引擎渲染/UI API |
| L1 Simulation | SimWorld、EnvironmentSystem、OrganismSystem、EvolutionSystem、StatisticsSystem | L0 | 场景树、Control、输入事件 |
| L2 Platform | SimClock、WorkerPool 封装、GpuFieldBackend / CpuFieldBackend、SaveManager | L0、L1（只读接口） | UI |
| L3 Presentation | 培养皿渲染、MultiMesh 批次、后处理、视图控制器 | L0、L1（只读快照） | 写模拟状态 |
| L4 UI | 各界面、工具控制器、报告、输入映射 | L0、L1 的命令接口、L3 的视图接口 | 直接改 SoA 数组 |
| L5 Agent | SemanticRegistry、AgentBridge、CommandBus | L4 的命令接口 | 绕过白名单 |

**规则**：依赖只能向下；所有跨层写操作必须经 `CommandBus`（命令对象 + 校验 + 审计），读操作可走只读快照。这样保证"暂停/回放/分支存档/自动化脚本"四条链路共享同一入口，不会出现某个 UI 按钮偷改状态导致存档不一致。

### 2.2 Autoload 单例

| 单例名 | 职责 | 关键对外接口 |
| --- | --- | --- |
| `SimClock` | 固定步长累加、暂停、倍速、单步、tick 序号 | `tick_advanced(tick_index)`、`set_speed()`、`step_once()` |
| `SimWorld` | 持有当前世界的全部运行时数据（SoA、场句柄、空间哈希） | `snapshot()`、`apply_command()` |
| `EventBus` | 全局信号总线（出生/死亡/突变/物种分化/工具应用/存档） | `emit_event(type, payload)` |
| `AssetDB` | 加载 `.tres` 定义：细胞类型、基因、工具、环境模板、预设实验 | `get_cell(id)`、`get_tool(id)` |
| `ToolRegistry` | 干预工具注册与冷却/消耗校验 | `begin_tool()`、`apply_tool()` |
| `SaveManager` | 自动存档、书签、分支、快照导入导出 | `save()`、`load()`、`fork()` |
| `CommandBus` | 唯一写入口，白名单、参数校验、undo 栈、审计日志 | `execute(cmd)`、`undo()` |
| `AgentBridge` | 本地 JSON Lines 通道（默认关闭） | `state_json()`、`handle_request()` |
| `DebugFlags` | 开发者模式开关、能力探测结果、性能 HUD 开关 | 只读字段 |
| `Settings` | 画质、音量、快捷键、存档间隔 | `get()` / `set()` |

### 2.3 目录结构

```
res://
├── project.godot
├── addons/gut/                    # 仅测试期
├── autoload/                      # 上表 10 个单例，各一个 .gd
├── core/
│   ├── genome/Genome.gd  GenomeCodec.gd  Mutation.gd  DevelopmentProgram.gd
│   ├── data/SimConfig.gd  CellTypeDef.gd  ToolDef.gd  EnvironmentPreset.gd
│   │            SpeciesRecord.gd  LineageNode.gd  ExperimentDef.gd
│   └── util/DeterministicRng.gd  Crc32.gd  SemanticId.gd  RingBuffer.gd
├── simulation/
│   ├── SimWorld.gd  SimTick.gd
│   ├── EnvironmentSystem.gd  FieldMath.gd
│   ├── OrganismSystem.gd  CellPhysics.gd  SpatialHash.gd  NeuralNet.gd
│   │            Development.gd  Metabolism.gd  Reproduction.gd
│   ├── EvolutionSystem.gd  Speciation.gd  LineageTracker.gd
│   └── StatisticsSystem.gd  FactGenerator.gd
├── platform/
│   ├── gpu/GpuFieldBackend.gd  compute/field_diffuse.glsl  cell_integrate.glsl
│   ├── cpu/CpuFieldBackend.gd
│   ├── WorkerBatch.gd
│   └── SaveManagerImpl.gd  SaveSchema.gd  ZipPackerUtil.gd
├── presentation/
│   ├── DishView.gd  DishMask.gdshader  DishPostprocess.gdshader
│   ├── CellBatchRenderer.gd  FieldOverlay.gd  MiniMapRenderer.gd
│   ├── LodController.gd  CameraRig.gd
│   └── theme/default_theme.tres  palette.tres
├── ui/
│   ├── UIManager.gd  Screen.gd
│   ├── menu/MainMenu.tscn  ChapterSelect.tscn
│   ├── designer/LifeDesigner.tscn  DnaView.gd  TraitPanel.gd  OrganLibrary.gd
│   ├── sim/SimHUD.tscn  SpeciesPanel.gd  EventLog.gd  ToolBar.gd
│   │            ObjectivePanel.gd  TimeControls.gd
│   ├── report/EcologyReport.tscn  PopulationChart.gd  DeathPanel.gd
│   ├── result/ExperimentResult.tscn
│   └── dev/DevPanel.tscn  Console.gd
├── agent/
│   ├── SemanticRegistry.gd  CommandBusImpl.gd  AgentBridge.gd
│   └── commands/*.gd
├── data/
│   ├── config/sim_defaults.tres  lod_levels.tres
│   ├── cells/*.tres  traits/*.tres  tools/*.tres
│   ├── environments/*.tres        # 热泉海床 / 浅海光照区 / 深海厌氧区 / 极端温度区
│   └── experiments/*.tres         # 可选预设实验（含视频中"播种篇"式目标）
├── scenes/main/Main.tscn
└── tests/unit/  tests/integration/  tests/bench/  tests/fixtures/
```

### 2.4 主场景树

```
Main (Node)                          # Main.tscn 根
├── SimulationLayer (Node)           # 无渲染，持有 SimWorld 与 tick 调度
├── WorldLayer (Node2D)
│   ├── DishView (Node2D)            # 圆形 mask + 网格 + 刻度
│   │   ├── FieldOverlay               # 热力/分析视图，shader 采样场纹理
│   │   ├── CellBatch (MultiMeshInstance2D)
│   │   ├── OrganismOverlay            # 选中高亮、轨迹、谱系标注
│   │   └── TerrainLayer               # 地形绘制结果（TextureRect + 遮罩）
│   └── CameraRig (Camera2D)
├── PostprocessLayer (CanvasLayer)   # 暗角/景深/扫描线，仅主视图生效
├── UILayer (CanvasLayer)
│   ├── ScreenStack (Control)        # 由 UIManager 管理压栈/出栈
│   ├── SimHUD                        # 常驻 HUD，沙盒模式可见
│   └── Toast / Tooltip / Cursor
└── DebugLayer (CanvasLayer)         # 性能 HUD、开发者面板，发布版隐藏
```

### 2.5 一次 Tick 的完整时序

`SimClock` 在 `_process(delta)` 累加时间；每满 1/60 s 调用 `SimTick.execute(world, tick_index)`，顺序固定，不允许系统间互相回调：

| 序 | 阶段 | 负责系统 | 线程 | 产出 |
| --- | --- | --- | --- | --- |
| 1 | 消费命令队列 | CommandBus | 主线程 | 干预工具、基因投放、环境改写全部在此生效，保证可重放 |
| 2 | 场源注入 | EnvironmentSystem | 主线程（提交 GPU 命令） | 热泉、光照、工具投放写入源纹理 |
| 3 | 场扩散 / 平流 | GpuFieldBackend 或 CpuFieldBackend | GPU / WorkerThreadPool | 5 类场的新一帧纹理（ping-pong） |
| 4 | 场采样 | EnvironmentSystem | 批量 | 每生物所在格的场值写入 `AgentSampleBuffer` |
| 5 | 感知 | NeuralNet | WorkerThreadPool 分组 | 输入：场梯度、邻近实体、化学信号；输出：行为卡槽激活 |
| 6 | 决策与运动意图 | NeuralNet + Metabolism | 同上 | 推进方向、攻击/吞噬意图 |
| 7 | 细胞积分与约束 | CellPhysics | WorkerThreadPool 分组 | Verlet 位置、弹簧连接、碰撞分离 |
| 8 | 空间哈希重建 | SpatialHash | 主线程（单写） | 网格索引，供下一 tick 的邻域查询 |
| 9 | 代谢与能量结算 | Metabolism | WorkerThreadPool 分组 | 摄入、维持成本、能量余额、中毒/温度损伤 |
| 10 | 发育 / 再生 | Development | 分组 | 分裂分化、连接建立、成熟激活 |
| 11 | 繁殖 / 死亡 / 分解 | Reproduction | 主线程（单写，按 ID 升序） | 新增/回收实体，避免并发写索引 |
| 12 | 突变与物种判定 | EvolutionSystem | 主线程 | 新基因组、谱系节点、物种分化事件 |
| 13 | 统计聚合 | StatisticsSystem | 主线程 | 环形缓冲写入、每 30 tick 生成一次快照 |
| 14 | 事件派发 | EventBus | 主线程 | 供 UI 与 Agent 消费的批量事件 |

**确定性约束**：第 5/6/7/9 步按实体 ID 区间静态分区，每个分区只写自己区间的数组；跨分区结果（新增实体、死亡回收、物种分化）集中在第 11–12 步由主线程按 ID 升序处理。随机数统一由 `DeterministicRng` 以 `(tick_index, entity_id, channel)` 派生，禁止使用全局 `randf()`。浮点累加顺序固定，禁止在工作线程内对共享浮点做 `+=`。

**阶段 3 实作状态（2026-11-16）**：已实现的线程池任务目前为基础代谢 delta 与场采样的固定索引区间；神经/感知、细胞积分仍为主线程串行，不能据此宣称本表所有并行项完成。GPU 场已在 Forward+ Vulkan 的 NVIDIA GeForce RTX 3050 Laptop GPU 实测真实 compute dispatch；当前原型使用 storage buffer 而非本节规划的打包存储纹理，但 CPU/GPU 已共享圆形 mask、零通量邻接、半拉格朗日平流、衰减与 tick 源项路径。两 tick 五通道全网格对照最大绝对误差为 `3.0517578e-5`，相对误差约 `1.1e-7`，按 `max(1e-5, |CPU|*2e-7)` 双阈值通过；由于 GPU/CPU 浮点运算次序不同，量化状态 hash 不保证逐位相同。Headless / Compatibility 模式按能力探测回退 CPU；GPU 每 tick 回读场数据以维持现有 CPU 侧生物采样契约，GPU 采样/统计缓冲仍是后续性能优化项。

### 2.6 时间控制

| 倍速 | 每渲染帧目标 tick 数 | 模拟精度 | 渲染策略 |
| --- | --- | --- | --- |
| 暂停 | 0 | 冻结全部 | 保留最后一帧画面，UI 仍响应 |
| 1× | 1 | 全精度 | 60 fps |
| 3× | 3 | 全精度 | 60 fps |
| 8× | 8 | 神经每 2 tick 更新一次 | 视野特效降级 |
| 16× | 12（余量结转） | 场每 2 tick 扩散一次，神经每 4 tick | 关闭景深，粒子上限 60% |
| 32× | 12（余量结转） | 场每 4 tick，神经每 8 tick，简化细胞物理 | 渲染 30 fps，仅宏观 LOD |

单帧 tick 上限 12，防止掉帧后"补帧雪崩"；超出部分记入 `carry`，并在 HUD 提示"模拟时间落后"。单步执行（`step_once`）绕过累加器，强制推进一帧并刷新全部调试视图。倍速切换不改变逻辑 dt，只改变 tick 频率与精度降级，因此同一存档在任何倍速下都能得到一致结果（精度降级本身作为存档元数据记录）。

## 3. 数据契约

### 3.1 资源定义（编辑器期，`.tres`）

| Resource 类 | 关键字段 | 用途 |
| --- | --- | --- |
| `CellTypeDef` | `id`, `display_name`, `category`, `cost_per_tick`, `organ_maintenance`, `effect_tags`, `icon` | 16 种功能细胞，见 v1.0 §5.1 |
| `TraitDef` | `id`, `min/max`, `budget_curve`, `cost_curve`, `affected_params`, `description` | 8 项全局性状，定义 Lv→效果与预算曲线 |
| `ToolDef` | `id`, `name`, `cost_biopoints`, `cooldown_s`, `shape`(point/line/brush), `duration_s`, `field_deltas`, `script` | 10 类干预工具数据驱动，避免硬编码 |
| `EnvironmentPreset` | `base_temperature`, `oxygen`, `nutrient_diffusion`, `light_profile`, `vent_sources[]`, `terrain_mask`, `layers[]` | 4 个环境模板 + 自定义；`layers[]` 为 v2.1 追加的可选区域参数覆盖 |
| `ExperimentDef` | `objective[]`, `bonus[]`, `budget_limit`, `reward_research`, `allowed_tools[]`, `description` | 可选预设实验，纯表现层 |
| `SimConfig` | `tick_rate`, `dish_radius`, `grid_size`, `field_diffusion[]`, `budget_max`, `mutation_base`, `speciation_distance`, `speciation_cooldown` | 全局可调参数，默认值见附录 B |

`layers[]` 参考 `ALIEN` 的 Layers / 线性力场思路（§0.5）：每个 layer 是"圆形或矩形区域 + 该区域内的场参数覆盖 + 恒定力矢量"，用于在同一个培养皿里同时表达热泉海床、浅海光照区与厌氧带，而不是把一个模板摊平到全皿。它是**可选字段**，为空时退化为全局参数；不设全局重力参数，洋流与定向力都由 layer 与 `SourceOp` 产生。区域边界处参数以 `layer_blend_width` 做平滑权重混合，避免场值突变破坏扩散稳定性（验收见 T14）。`Cell Lab` 的 27 项环境参数编辑器同样说明"参数集中 + 可覆盖"比散落在代码里更可维护，故本版仍坚持所有默认值集中在附录 B 对应的 `sim_defaults.tres`。

**P0 层级澄清（2026-11-15）**：`CellTypeDef` 的 16 种功能细胞是 **v1.0 §5.2 位点层的可装配装备**（基因组上的一个槽），不是多细胞个体里某个细胞分化出来的运行时类型。后者由 §4.4 的 `DIFFERENTIATE` 指令在发育期指定，落在 §3.3 的 `cell_type` 字段；§5.2 的 8 项全局性状是个体级加成，作用于所有细胞。三者是不同层级的数据，编辑器 UI 的「细胞器」与「染色体组型」词条分别对应前两者，不得混用。

### 3.2 基因组二进制格式（`.gnm` / 存档内 `genome`）

基因组需要在每次分裂时复制、每次突变时改写、每 N tick 上传 GPU，因此采用紧凑定长头 + 变长发育程序，纯 `PackedByteArray` 操作，不使用 JSON。

| 偏移 | 字段 | 类型 / 位宽 | 说明 |
| --- | --- | --- | --- |
| 0 | `magic` | 4 B | 固定 `GNP1`，用于导入校验 |
| 4 | `version` | u16 | 格式版本，解码器按版本分派 |
| 6 | `flags` | u16 | bit0 自然变异开关；bit1.. 预留 |
| 8 | `respiration` | u8 | 0 厌氧 / 1 好氧 / 2 兼性（兼性额外占 2 点预算） |
| 9 | `locus_count` | u8 | 位点数量，初始 8，重复/缺失突变可改变 |
| 10 | `trait_count` | u8 | 固定 8 |
| 11 | `mutation_rate_exp` | u8 | 元突变：以 2 为底的指数编码，基础 0.001 |
| 12 | `loci[]` | 每位点 u8 | 低 5 bit = 细胞类型 ID；高 3 bit = 表达强度 |
| 12+N | `traits[]` | 每项 u8 | 0..63 量化 Lv，映射到 `TraitDef.min/max` |
| … | `dev_program_len` | u16 | 发育指令条数 |
| … | `dev_program[]` | 每指令 u32 | 见 §4.4 指令编码 |
| … | `reserved[]` | 变长 | 4 B 对齐 |
| 末尾 | `checksum` | u32 | CRC32（不含自身），导入失败即拒绝并报错 |

对外 API：`GenomeCodec.encode(Genome) -> PackedByteArray`、`GenomeCodec.decode(PackedByteArray) -> Genome`、`Genome.hash() -> int`（供物种遗传距离与去重）。跨版本导入由 `SaveSchema` 的迁移函数链处理，迁移只升不降。

**P0 澄清**：`GNP1` 是「定长头 + 变长发育程序」结构，`dev_program[]` 本就在格式内（§4.4），因此多细胞发育**不需要新增基因组格式，也不需要改写已冻结的布局**；`version` 字段已为格式演进预留。当前运行时 `Genome.gd` 的 12 字节简化实现与 §3.2 完整格式之间的差距属于 P1 实现工作，按 `version` 分派升级，不是玩法规则变更。

### 3.3 运行时生物数据（SoA）

所有实体存于 `SimWorld` 的并行数组，实体 ID = 数组下标 + 世代戳（避免对象池复用后的悬空引用）。

| 数组 | 类型 | 说明 |
| --- | --- | --- |
| `org_alive` | `PackedByteArray` | 存活位图 |
| `org_genome_id` | `PackedInt32Array` | 指向去重后的基因组池索引 |
| `org_species_id`, `org_parent_id` | `PackedInt32Array` | 谱系与物种 |
| `org_energy`, `org_age`, `org_health` | `PackedFloat32Array` | 能量、年龄、损伤 |
| `org_state` | `PackedByteArray` | 生命周期状态机枚举 |
| `cell_offset`, `cell_count` | `PackedInt32Array` | 每生物在细胞数组中的区间 |
| `cell_pos_x/y`, `cell_prev_x/y` | `PackedFloat32Array` | Verlet 位置与前帧位置 |
| `cell_type`, `cell_org_id` | `PackedByteArray` / `PackedInt32Array` | 细胞类型与归属 |
| `cell_link_a/b`, `cell_link_rest` | `PackedInt32Array` / `PackedFloat32Array` | 弹性连接与静息长度 |
| `nn_weight`, `nn_bias` | `PackedFloat32Array` | 神经网络权重（按行为卡槽布局） |
| `field_sample[]` | `PackedFloat32Array` | 每生物 5 类场采样值，tick 第 4 步写入 |

**规则**：数组只在阶段 11（主线程）扩容/回收；对象池维护 `free_entity_ids` 栈；任何系统不得持有跨 tick 的下标指针，必须持有 `(id, generation)` 并在使用前校验。

### 3.4 环境场数据

5 类场打包进 2 张 `R16G16B16A16_SFLOAT` 存储纹理（纹理 A：温度/营养/氧气/光照；纹理 B：化学信号 + 3 通道预留），分辨率固定 256×256（对应培养皿直径 2048 世界单位，1 格 = 8 单位），圆形边界由 mask 纹理裁剪。每类场使用 ping-pong 双缓冲，compute shader 一次 dispatch 完成扩散 + 平流 + 衰减 + 源注入。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `diffusion[]` | 温度 0.16 / 营养 0.08 / 氧气 0.12 / 光照 0.20 / 信号 0.05 | 每 tick 扩散系数，待调参 |
| `decay[]` | 0.002 / 0.004 / 0.003 / 0.0 / 0.02 | 每 tick 自然衰减 |
| `advection` | 洋流矢量场（工具 04 写入） | 半拉格朗日平流 |
| `boundary` | 圆形零通量（Neumann） | 皿壁不透物质 |

其中化学信号场（纹理 B 的 R 通道）除承担生物间通讯外，也是 `Substrate: Emergence` 所谓"化学作为武器"所依赖的那类空间竞争媒介；本文只把它实现为可被 `SourceOp` 写入、可扩散、可被神经感知的**中立场通道**，不引入阵营、领地或胜负判定（§0.5.3）。`EnvironmentPreset.layers[]` 的区域覆盖只改局部扩散/衰减系数与力矢量，不改变场的通道数与纹理布局，因此 GPU 与 CPU 两套后端共用同一份参数下发路径。

CPU 侧取值策略：**禁止每帧全量 `texture_get_data`**（会同步等待 GPU）。生物感知走 GPU 端采样写入 `AgentSampleBuffer`（storage buffer），CPU 每 4 tick 回读一次该紧凑缓冲；UI 热力图直接由 shader 采样纹理；CPU 回退后端则用同一接口的 `PackedFloat32Array` 实现。统计用的全场总量由 GPU `atomicAdd` 累加到 5 个计数器，随采样缓冲一起回读。

### 3.5 存档格式

一次存档为一个 `.gsave` 包（`ZIPPacker` 写入，便于人工排查与版本迁移）：

| 条目 | 内容 |
| --- | --- |
| `meta.json` | 版本号、引擎版本、模拟 tick 序号与游戏内时间、随机种子、倍速与 LOD 精度档、创建时间、父存档 ID |
| `config.tres` | 覆盖过的 SimConfig 字段（差分，不写全量） |
| `world.bin` | §3.3 全部 SoA 数组 + free list + 世代戳 |
| `genomes.bin` | 去重基因组池（`GNP1` 块拼接 + 索引表） |
| `fields.bin` | 2 张场纹理的原始数据 + 洋流矢量 + 地形 mask |
| `lineage.bin` | 谱系节点、物种记录、分化事件 |
| `stats.bin` | 环形缓冲内容、事实记录、报告曲线 |
| `bookmarks.json` | 书签与其 tick 序号 |
| `thumbnail.png` | 皿视图缩略图（256×256），供读档列表显示 |

**分支演化**：`SaveManager.fork(bookmark_id)` 复制父包并写入新的 `parent_archive_id`，不修改父包；分支树以 `meta.json` 的父 ID 链表示。自动存档间隔默认 60 秒，最多保留 8 个滚动槽 + 全部手动书签。存档写入在独立线程完成，写入期间 SimWorld 采用"先冻结快照再继续模拟"的双缓冲策略，避免边写边改。

### 3.6 语义 ID 规范

| 命名空间 | 格式 | 示例 |
| --- | --- | --- |
| 控件 | `ui://<screen>/<panel>/<widget>` | `ui://designer/trait_panel/speed_slider` |
| 工具 | `tool://<tool_id>` | `tool://tool_01_nutrient` |
| 命令 | `cmd://<domain>.<verb>` | `cmd://sim.set_speed` |
| 实体 | `org://<id>:<generation>` | `org://18422:3` |
| 物种 | `sp://<species_id>` | `sp://A-02` |

所有可交互 Control 在 `_ready()` 中向 `SemanticRegistry` 注册，运行时提供 `find(semantic_id) -> Control`。开发者面板可开启"显示控件 ID"浮层，便于写自动化脚本。

## 4. 模拟内核

### 4.1 环境场求解

离散形式（每 tick、每格）：`C' = C + D·∇²C − v·∇C − λ·C + S`，其中 `S` 为热泉、光合固定、工具投放、生物代谢排泄的源项，`v` 为洋流。实现上：

| 步骤 | 说明 |
| --- | --- |
| 源项写入 | CPU 收集本 tick 的源变更，打包成 `SourceOp` 数组上传 storage buffer，compute shader 一次消费，避免逐个 dispatch |
| 扩散/平流 | `field_diffuse.glsl` 单次 dispatch（8×8 工作组），读 ping 写 pong，圆形 mask 外置零且不参与交换 |
| 交换 | ping-pong 索引翻转，UI 与采样始终绑定"最新"句柄 |
| 生物采样 | 采样 shader 按 `org_pos` 双线性插值，输出 5 个 float 到 `AgentSampleBuffer` |
| 统计 | 同一 shader 内 `atomicAdd` 全场总量 |

工具效果全部表达为 `SourceOp`（位置、半径、场通道、增量、持续时间、形状），因此 10 类工具共用一套执行路径，也天然支持撤销与回放。`ToolDef.field_deltas` 决定作用通道，例如隔离膜写入"固体 mask 通道"而非浓度场，局部升温写入温度 + 临时计时源。

### 4.2 生命周期状态机

| 状态 | 进入条件 | 主要行为 | 转出 |
| --- | --- | --- | --- |
| `ZYGOTE` | 分裂产生 / 玩家投放 | 载入基因组，执行发育程序第 0 条 | → `DEVELOPING` |
| `DEVELOPING` | 首条分裂指令 | 按指令分裂、分化、建立连接；不参与感知与运动 | 程序结束 → `MATURE` |
| `MATURE` | 神经通路激活 | 感知-决策-运动-代谢全量参与；可繁殖 | 能量耗尽/损伤 → `DEAD`；局部受损 → `DAMAGED` |
| `DAMAGED` | 部分细胞被破坏且能量充足 | 暂停部分行为，按基因组指令再生 | 修复 → `MATURE`；失败 → `DEAD` |
| `DEAD` | 能量 ≤ 0 / 衰老 / 中毒 / 温度越界 | 记录死因与谱系，释放神经资源 | → `DECOMPOSING` |
| `DECOMPOSING` | 死亡后 N tick | 躯体按质量换算回营养场源项，完成能量闭环 | 结束 → 实体回收进对象池 |

### 4.3 代谢与能量守恒

每 tick 的能量结算遵循 `ΔE = 摄入 − 维持 − 运动 − 器官 − 繁殖储备`，且系统侧维护 `E_total = E_env + ΣE_bio + E_detritus + E_external` 的守恒校验（开发者模式可开启断言，误差超阈值报警）。`E_external` 是 v2.1 参照 `ALIEN` 外部能量池（§0.5）显式化的记账项：玩家的干预工具从该池扣减、死亡分解与生物代谢排泄写回场内，工具前后 `E_total` 不变——这只是把 §4.1 / §6.5 已有行为形式化为可对账的账目，**不改变任何玩法规则，也不启用 ALIEN 的自动能量回流（backflow）机制**。

| 摄入路径 | 公式要点 | 备注 |
| --- | --- | --- |
| 光合 | `gain = light·area·k_photo`，受光照场随深度衰减影响 | 生产者核心 |
| 异养取食 | `gain = nutrient·k_hetero·resp_eff` | 采集者取食生产者/溶解营养 |
| 捕食 | `gain = prey_energy·k_transfer` | 能量沿食物链逐级损耗 |
| 化能自养 | `gain = sulfide·k_chemo`（硫化酶细胞） | 热泉生态位 |

| 呼吸方式 | 效率修正 | 生存限制（v1.0 §2.3） |
| --- | --- | --- |
| 厌氧 | 基准 1.0 | 环境氧浓度 > 8% 时中毒损伤 |
| 好氧 | 氧充足时约 3.0；缺氧降至 0.5 | 依赖氧气场 |
| 兼性 | 有氧/无氧均可，峰值低于专精，基因预算 −2 | 无硬性致死阈值 |

维持成本 = 基础代谢（受"代谢"性状下调） + Σ器官维持 + 外壳体重附加 + 感知/神经开销；运动成本与"速度"性状平方相关。死亡分解时把剩余生物量按转化率写回营养场，**不允许凭空生成能量**；玩家的干预工具只能做空间转移（营养投放从储备池扣除，撒铁粉改变氧的可用性而非凭空增氧）。

**阶段 3 临时实现参数（用户确认，尚非玩法权威规则）**：T04 健康初值/上限 1，厌氧呼吸在氧浓度严格大于 8% 时每秒损失 0.1 健康；T06 好氧效率为有氧 3.0、缺氧 0.5，厌氧 1.0，兼性有氧效率 2.0 / 预算代价 2；异养、光合、化能摄入系数分别为 0.05 / 0.02 / 0.02，捕食能量转移率 0.8，运动成本系数 0.001。参数应可配置；在能量来源池、转移与守恒测试完整实现前，不得把当前摄入路径描述为已满足 §4.3 的总能量守恒。

| 账目动作 | 借记 | 贷记 | 触发 |
| --- | --- | --- | --- |
| 投放营养 / 局部升温 / 撒铁粉 | `E_external` | `E_env`（对应场通道） | 工具命令在 tick 第 1 阶段生效 |
| 隔离膜 / 洋流引导 / 搅拌 | 不变（只改空间分布或力场） | 不变 | 同上 |
| 生物摄入 / 捕食 | `E_env` 或猎物 `E_bio` | 自身 `E_bio` | tick 第 9 阶段 |
| 死亡分解 | `E_bio` | `E_env`（营养场源项） | tick 第 11 阶段 |
| 擦除区域（`organism.erase_area`） | `E_bio` | `E_env`（按分解规则） | 死因记为"干预" |
| 细胞内沿连接再分配（P0） | `E_cell(i)` | `E_cell(j)`（同一 `org_id` 内） | tick 第 9 阶段，成对等值反向 |

开发者模式的能量守恒断言改为同时核对上表逐项账目与总量，任何一项缺失都会定位到具体阶段而不是只报总误差；对应测试 T07 与 T13。

**P0 增补（细胞内再分配）**：一个生物个体的能量是其所含细胞能量之和，即 `E_bio(org) = Σ E_cell(i)`。沿弹性连接的细胞内结算采用「先合计、再分配」：净流量在成对细胞间等值反向记账，`ΣE_cell` 前后不变，`E_total` 亦不变；因此 §4.3 的守恒式**无需新增全局项**，只需把 `E_bio` 明确为可分解的细胞级账目。产能型细胞供养运动 / 感知型细胞、保护型细胞屏蔽相连细胞的负面交互，都属于个体内部再分配，不构成能量生成，也不构成跨个体转移。对应记账号见上表新增行，验收用例待 P1 补入 §9.2。

### 4.4 发育程序指令集

每条指令 u32：`[opcode:6][a:8][b:8][c:10]`。突变作用于指令本身，从而改变形态而非只改数值，这是 v1.0 "发育式形态 / 开放式形态演化" 的落地点。

| 指令 | 操作数语义 | 作用 |
| --- | --- | --- |
| `DIVIDE` | a=母细胞索引, b=分裂轴角度量化, c=保留 | 生成子细胞，按方向排列 |
| `DIFFERENTIATE` | a=目标细胞, b=细胞类型 ID | 分化为对应功能细胞 |
| `LINK` | a,b=两端细胞, c=静息长度 | 建立弹性连接与信号通路 |
| `SIGNAL` | a=源细胞, b=行为卡槽 | 绑定神经输出到运动/攻击 |
| `WAIT` | c=tick 数 | 发育时序控制 |
| `BRANCH` | a=条件(能量/场值), b=跳转偏移 | 环境依赖的形态可塑性 |
| `REPAIR` | a=细胞类型 | 成体再生模板 |

约束：指令条数上限 64，跳转只允许向前，程序执行有 tick 预算上限（防止突变产生死循环卡死模拟）。该预算参照 `ALIEN` constructor "一次触发构建一个细胞"的逐细胞构建节奏：本文允许一条 `DIVIDE` 生成一个细胞，但整个发育程序必须在 `dev_tick_budget` 内结束，超时按 T05 的非法程序处理回退父代，避免单个畸形基因组长期占用主线程。`ALIEN` 用 Genome / Gene / Node 三层图 + 形状生成器表达同一件事，本文选择 u32 指令流是为了让 `GNP1` 定长可校验、便于存档与确定性回放（§0.5）。

**P0 增补（局部规则与协作）**：`DIVIDE` / `DIFFERENTIATE` / `LINK` 三条指令共同决定个体的细胞类型布局与连接图，形态始终由指令生成而非预定义模板（守住 v1.0 §1.2 发育式形态）。运行时须保证：连接数达到上限时抑制继续 `DIVIDE`；细胞死亡时双向解除连接并重映射对端索引；同个体内细胞也按同一静息直径参与分离（§4.5，v0.8.7 修正：外部撞击会把细胞推入同簇，跳过自碰撞会造成重叠）；`cell_type` 决定该细胞在 §4.3 中的产能 / 耗能 / 保护角色。Cell Lab 的对应规则见 `analysis/CellLab_多细胞协作_设计规格.md` §3.1–3.7，但**不引入其 40 槽分化树与突变算子**。

### 4.5 细胞物理与空间哈希

| 项 | 方案 |
| --- | --- |
| 积分 | Verlet：`p' = 2p − p_prev + a·dt²`，阻尼 0.98；无刚体、无 Godot 物理节点 |
| 连接 | 弹性弹簧，每 tick 2 次约束迭代，防止拉伸爆炸 |
| 碰撞 | 空间哈希网格 64 世界单位，仅查 3×3 邻格；所有活细胞（含同生物内部）按同一半径分离，每 tick 最多 6 轮确定性位置修正（每 3 轮重建 pair），处理连锁重叠 |
| 边界 | 圆形皿壁与地形 mask：位置投影回合法区域，法向速度衰减 |
| 复杂度 | 建表 O(n)，邻域查询 O(n·k)，k 为单格平均密度（软上限 16，超出分网格） |
| 批处理 | 按网格行分区交给 `WorkerThreadPool.add_group_task`，边界格只读邻区数据 |

### 4.6 分布式神经与行为

每个细胞是一个神经节点，输入固定为 8 维（5 类场采样 + 邻近同类数 + 邻近异类数 + 自身能量比），输出固定为 6 维（前进、转向、攻击、吞噬、分泌信号、静止）。"神经"性状决定行为规则卡槽数量（初始 5 个）与可连接数；"记忆片段"细胞额外提供短时状态。权重数组在繁殖时复制并施加微小扰动，突变可增删卡槽。行为不设"寻路到最优资源"这种上帝视角逻辑——只依据局部场梯度与邻域信息，选择压力完全由环境产生。

**v2.1 预留位**：`ALIEN` 采用 16 输入 / 12 输出（8 路信号通道 + 4 路记忆输出）且每 6 个 time step 跑一次细胞周期（§0.5）。本文 §2.6 的倍速 LOD 已把神经更新降到每 2 / 4 / 8 tick 一次，与"周期化神经"同构；但本版不扩输入输出维度。`GNP1` 的 `flags` 保留位与 `reserved[]` 已为"信号通道数 / 记忆槽数"预留版本位，未来若要扩展，走 `version` 分派与版本化追加，**不改动阶段 2 冻结后的基础布局**。

**P0 实现状态注（2026-11-15 状态更新）**：运行时现有 `CellArray` 已为每个细胞维护 56 个独立权重槽，`CellBehavior.gd` 按 8 输入 / 4 隐藏 / 6 输出执行确定性前馈计算；权重以基因组哈希和稳定 cell index 派生，分裂时复制父细胞权重。更新分两阶段：先按稳定索引计算所有输出，再统一应用运动意图，避免共享写。当前环境 5 场输入仍为零、输出仅前进/转向接入物理；其余行为输出、氧/营养场与呼吸代谢未接入。因此本实现不改变 GNP1 布局，但不构成阶段 3 完成；阶段 DoD 仍需 T04/T06、WorkerThreadPool 静态分区无共享写和全模拟状态哈希回归。

**呼吸规则实现状态（2026-11-15）**：新增纯函数 `RespirationRules.gd`，按 v1.1 §2.3 / v2.1 §4.3 评估 8% 氧阈值、厌氧基准效率 1.0、好氧充氧效率 3.0 / 缺氧效率 0.5、兼性额外预算 2；兼性有氧效率暂用显式参数（默认 2.0），因为玩法只规定低于专精型、未给精确值。`EnvironmentPreset` 增加皿级 `oxygen_fraction` 背景值并写入快照；这不是空间氧浓度场。厌氧在阈值上方只返回 `toxic=true`，不扣健康值，因为规范未定义毒性伤害速率或死亡累计时长。故呼吸规则单测通过不等于 T04/T06 通过；仍需权威定量损伤规则、空间场采样与营养摄入能量函数。

**六维行为意图实现状态（2026-11-15）**：`CellArray.behavior_intents` 为每细胞保存 6 个神经输出，`CellBehavior.apply_outputs()` 在两阶段更新的应用阶段写入全部输出，并仅将前进/转向转换为物理位移；攻击、吞噬、分泌、静止作为可查询意图经 `get_intents()` 暴露，不擅自产生伤害、能量或场变化。`snapshot_intents()` 提供稳定顺序的意图快照；细胞分裂继承父代当前意图与网络权重。SmokeTest 覆盖输出持久化、快照重复一致、分裂继承。此实现没有新增 GNP1 字段，不代表行为效果已完整接线；待捕食、摄入、化学场与静止运动约束规则明确后再消费相应意图。

### 4.7 繁殖、突变与物种判定

| 算子 | 触发概率（默认） | 作用对象 | 实现要点 |
| --- | --- | --- | --- |
| 点突变 | 0.001 / 位点 / 分裂 | `traits[]` | ±1 量化级，钳制在 0..63 |
| 功能突变 | 0.0004 / 位点 / 分裂 | `loci[]` 类型位 | 换成随机其他细胞类型，需重算预算与成本 |
| 重复 / 缺失 | 0.0002 / 分裂 | `locus_count` | 复制或删除一段位点，钳制在 4..16 |
| 发育突变 | 0.0005 / 分裂 | `dev_program[]` | 指令参数扰动 / 插入 / 删除，校验合法性 |
| 元突变 | 0.0001 / 分裂 | `mutation_rate_exp` | 改变自身谱系的突变率，范围钳制 |

环境压力（温度越界、饥饿、毒素）对本 tick 的突变率施加乘数，仍不改变方向性。繁殖为无性二分裂：能量达到 `分裂阈值`（受"繁殖""代谢"性状影响）后产生 `ZYGOTE`，亲代能量按分配比例扣减，新生个体初始能量因此与"繁殖"性状负相关（对应 v1.0 的取舍设计）。

物种判定：`Genome.distance(a,b)` 为位点汉明距离 + 性状 L1 距离 + 发育程序编辑距离的加权和；超过 `speciation_distance` 且距上次分化超过 `speciation_cooldown` tick 时新建物种 ID、分配谱系编号并发出事件。物种灭绝时自动写入档案：存活时长、峰值种群、主要死因、核心性状特征。

**调参依据（v2.1）**：`ALIEN` 文档把 0.001–0.01 列为突变概率的合理起点，并把突变率写进每个基因组、允许其自我演化（meta-mutations），与本文 `mutation_rate_exp` + 元突变算子一致。附录 B 的 `base_mutation_rate = 0.001` 在最大环境压力乘数 4.0 下为 0.004，仍落在该区间内；若阶段 4 调参要突破 0.01，须重跑 T01 / T08 并说明生态后果。`Cell Lab` 的实验模式同样以"随机基因组播种 + 微小突变 → 逐渐适应环境"为核心体验，佐证 v1.0 的开放式进化不做人为方向引导。

### 4.8 统计与事实生成

`StatisticsSystem` 用环形缓冲保存最近 N 个采样点（默认 7200 点 = 2 分钟 @60Hz 的 30 tick 聚合粒度）：各物种数量、出生/死亡数、六类死因计数、平均体型/速度/代谢率、物种丰富度与均匀度。生态报告从缓冲生成三条产物：多物种折线图、物种与死因面板、"记录到的事实"（由 `FactGenerator` 的模板规则生成，例如"物种 A-02 最主要死因是衰老，占 99%""晨光丝种群峰值出现在 03:46"）。所有事实由数据驱动，禁止手写死文案。

## 5. 渲染与表现

### 5.1 培养皿视觉

| 层 | 实现 | 说明 |
| --- | --- | --- |
| 皿体 | `DishMask.gdshader` 圆形遮罩 + 边缘菲涅尔高光 + 玻璃厚度 | 对应视频中的显微镜圆形视野 |
| 网格与刻度 | `draw()` 自绘同心圆、角度刻度、坐标标注 | 随缩放淡入淡出，宏观显示 km/μm 双标尺 |
| 背景 | 深青灰渐变 + 噪点 + 缓慢漂移的微粒 | 深色科技风，主色青蓝 #4FD6E8 / 深灰 #10161C |
| 后处理 | 暗角、景深虚化、扫描线、色差（可关） | 16× 以上倍速自动关闭 |
| 选中标示 | 描边 shader + 轨迹线 + 谱系浮标 | 单生物跟随模式使用 |

### 5.2 实体渲染

| 视图层级 | 缩放范围 | 渲染内容 | 模拟精度 |
| --- | --- | --- | --- |
| 宏观 | 全皿 | 每物种一个颜色点/热度块，MultiMesh 批量 | 统计驱动，不逐细胞积分 |
| 群体 | 中景 | 每个生物 1 个 MultiMesh 实例（形态色块 + 朝向） | 全代谢、简化物理、神经降频 |
| 显微 | 近景 | 逐细胞实例 + 连接线 + 内部结构 + 神经可视化 | 全精度物理与神经 |

`CellBatchRenderer` 每帧从 SoA 组装 `Transform2D` 与 per-instance color，一次 `multimesh.set_as_bulk_visible` / buffer 更新；实例数按 LOD 上限截断并做稳定抽样（避免闪烁）。CPU 回退路径下用同一 MultiMesh，只是组装在 GDScript 中完成，视觉不降级。

### 5.3 场可视化

普通 / 热力 / 分析三视图共用 `FieldOverlay`：shader 采样最新场纹理，普通视图仅做微弱辉光，热力视图映射单通道到 8 色渐变，分析视图叠加等值线与矢量箭头（洋流）。视图切换只换 uniform，不重建场景。小地图复用同一纹理的低分辨率副本，帧率限制为 10 fps。

### 5.4 UI 主题

| 项 | 规格 |
| --- | --- |
| 配色 | 背景 #0C1218 / 面板 #131D26 / 主色 #4FD6E8 / 强调 #F2A65A（生产者橙）/ 警示 #E8615A / 文字 #DDE6EA |
| 字体 | 中文无衬线 + 等宽数字；标题字重 700，正文 400；最小字号 12 px |
| 面板 | 1 px 青蓝描边、4 px 圆角、16 px 内边距、细分割线 |
| 数值 | 统一等宽右对齐，带单位（℃ / μm/s / /s / 生物点） |
| 动效 | 面板淡入 120 ms，数值变化 200 ms 补间；不阻塞输入 |
| 无障碍 | 色盲友好图例（形状 + 颜色双编码）、可选高对比度与色彩替代主题、可调正文字号（12–20 px）、随时存档、无需限时输入；v2.1 参考 `Substrate: Emergence` 商店列出的可调字号 / 色彩替代 / 对比度控制 / Save Anytime / Playable without Timed Input 补齐（§0.5） |

## 6. 界面与交互实现

### 6.1 UIManager 与屏幕栈

`UIManager` 维护一个 `Screen` 栈，栈内屏幕按"是否暂停模拟"分两类：主菜单、设置、生命设计器、生态报告、结算页属于模态类（进入时按配置暂停或保持低速），模拟主界面属于常驻类（始终在栈底）。切换只做 `show/hide` 与 Tween，不反复 `instantiate`，避免编辑器里已绑定的语义 ID 丢失。

| 屏幕枚举 | 场景 | 进入时模拟状态 | 返回 |
| --- | --- | --- | --- |
| `MAIN_MENU` | `ui/menu/MainMenu.tscn` | 预览世界独立跑简化渲染 | — |
| `CHAPTER_SELECT` | `ui/menu/ChapterSelect.tscn` | 保持 | Esc → 主菜单 |
| `SANDBOX` | `ui/sim/SimHUD.tscn` | 恢复 | 栈底 |
| `DESIGNER` | `ui/designer/LifeDesigner.tscn` | 保持（可配置暂停） | Esc/Tab → 沙盒 |
| `REPORT` | `ui/report/EcologyReport.tscn` | 保持 | R/Esc → 沙盒 |
| `RESULT` | `ui/result/ExperimentResult.tscn` | 暂停 | → 沙盒 / 章节页 |
| `DEV_PANEL` | `ui/dev/DevPanel.tscn` | 不影响 | 浮层 |

### 6.2 主菜单

左侧文本区（标题、副标题、01 战役 / 02 沙盒 / 03 设置 / 04 退出），右侧为持续运行的培养皿预览：一个低负载的 `PreviewWorld`（最多 300 个实体、只跑代谢与运动、不跑进化），右下角实时显示"培养皿实时：X 个生命 · Y 条谱系"，左下角显示版本号与构建日期。预览世界与正式世界共用 `DishView`，保证视觉一致；点击"沙盒"时释放预览、构建正式 `SimWorld`，避免两套渲染逻辑。

### 6.3 生命设计器

界面分四区：左侧样本培养舱 + 染色体组 + 16 种器官库，中部 DNA 双螺旋与位点标注，右侧 8 项基因面板，底部状态与操作条。顶部标签为 A·生产者 / B·采集者 / C·捕食者（快速模板）、行为规则、物种、规则手册、病毒设计、身体。

| 数据链路 | 实现 |
| --- | --- |
| 编辑源 | `GenomeResource`（内存中的 `Genome` 对象），所有滑块/位点操作只改这一份 |
| 派生计算 | `DerivedStats.compute(genome)` 一次性算出预算、预计耗能、分裂所需能量、游速、视野、耐受温度、维持成本；纯函数、可单测 |
| 实时预览 | 样本培养舱用独立的 1 个实体跑完整发育程序，20 Hz 刷新，滑块拖动期间节流到 10 Hz |
| DNA 视图 | `DnaView` 按 `locus_count` 生成螺旋点位，点击位点 → `SemanticRegistry` 选中对应基因行；插入/删除位点时高亮重排 |
| 器官库 | 从 `AssetDB` 读 `CellTypeDef`，拖拽到空位点即写 `loci[]`，超预算时拒绝并给出原因 |
| 呼吸下拉 | 好氧 / 厌氧 / 兼性，切换后立即重算预算（兼性 −2）与派生属性 |
| 底部操作 | 保存到物种库（写 `.tres`）、投放到培养皿（生成 `organism.spawn` 命令）、自然变异开关（写 `flags.bit0`） |

**预算规则**：`ΣTraitDef.budget_curve(Lv) + ΣCellTypeDef.budget + 兼性修正 ≤ budget_max`（默认 16，沙盒模式解锁为无限）。所有拒绝都必须给出可读原因，禁止静默 clamp。开发者模式勾选"基因预算不限"时仅关闭校验，不修改派生计算，保证两种模式下同一基因组的表现一致。

### 6.4 模拟主界面

| 区域 | 控件与数据源 | 刷新频率 |
| --- | --- | --- |
| 顶部状态栏 | 时间 `T+mm:ss`、生命数、谱系数、暂停/倍速按钮、视图模式 | 4 Hz |
| 右上目标面板 | 沙盒显示"无限制"；预设实验显示 `ExperimentDef.objective[]` 与实时进度 | 4 Hz |
| 环境面板 | 温度、溶解营养、水流、生物量（来自 GPU 统计计数器） | 4 Hz |
| 左侧物种列表 | 每物种颜色点、名称、现存数、出生/死亡计数，点击可跟随 | 4 Hz |
| 左下事件日志 | `EventBus` 批量事件，环形上限 200 条，按类型着色 | 事件驱动 |
| 中央培养皿 | `DishView` + `CellBatch` + `FieldOverlay`，支持滚轮缩放、右键/中键平移 | 每帧 |
| 右上小地图 | 场纹理缩略 + 种群热力 + 视口框 | 10 Hz |
| 右下干预工具栏 | 10 项 `ToolDef`，显示名称、消耗生物点、快捷键、冷却 | 状态变化时 |
| 底部功能栏 | 观察 V / 分析 X / 视图 C / 跟随 F / 报告 R / 生命设计器 Tab / 地形编辑 G | 常驻 |

所有数值控件只读 `SimWorld.snapshot()` 的不可变快照，不直接引用 SoA 数组；UI 刷新在 `_process` 中按上表频率节流，避免每帧重建文本。

### 6.5 输入映射与工具交互

| 输入 | 动作 | 备注 |
| --- | --- | --- |
| `V` / `X` | 观察 / 分析模式 | 分析模式显示场等值线与选中体详情 |
| `C` | 循环视图：普通 → 热力 → 分析 | 只改 shader uniform |
| `F` | 跟随选中实体 | 相机绑定 `(id, generation)`，实体死亡自动解除 |
| `R` | 生态报告 | `R/Esc` 关闭 |
| `Tab` | 生命设计器 | `Esc` 返回培养皿 |
| `G` | 地形编辑器 | 画笔模式 |
| `Space` | 暂停 / 继续 | `1/2/3` 对应 1×/3×/8×，`Shift+3` 16×，`Shift+4` 32× |
| `滚轮` / 拖拽 | 缩放 / 平移 | 缩放联动 LOD 档位 |
| `左键` | 应用当前工具 / 选中实体 | 依 `ToolDef.shape` 决定 point/line/brush |
| `.`（句点） | 单步执行 | 仅暂停态有效 |

`ToolController` 状态机：`IDLE → PREVIEW`（显示作用范围与预估消耗）`→ APPLY`（生成 `SourceOp` 命令）`→ COOLDOWN → IDLE`。所有工具消耗"生物点"（视频中的 15 / 30 / 30 / 35 等数值即此资源），沙盒模式默认免费（与 v1.0 §3.3 一致），预设实验按 `ToolDef.cost_biopoints` 扣减。工具执行全部经 `CommandBus`，因此可撤销、可回放、可被 Agent 调用。

### 6.6 模式分层：沙盒、预设实验与结算

| 层 | 内容 | 是否影响模拟 |
| --- | --- | --- |
| 核心（必需） | 沙盒模拟：无目标、无预算、全工具、全细胞开放 | — |
| 实验层（可选） | `ExperimentDef`：初始环境模板、可用物种、允许工具、目标条件、附加挑战、预算上限、通关奖励 | 只设定初始条件，**不干预 tick 内的任何概率或能量计算** |
| 结算层（可选） | `ObjectiveEvaluator` 每 30 tick 读一次统计快照判定；三星规则：完成目标 / 完成附加挑战 / 消耗低于预算线；研究点按 `reward_research` 发放 | 只读 |

目标条件用小型数据 DSL 表达，避免为每种关卡写脚本：`{metric: population, species: producer, op: ">=", value: 60, sustain_ticks: 3600}`。可用 metric 限定为 `population` / `biomass` / `diversity` / `elapsed_time` / `death_cause_ratio` / `budget_spent`。章节页（视频中"第六章·播种篇 / 熔岩滤食兽"）只是 `ExperimentDef` 的展示卡：深度、温度、目标、附加挑战、奖励、可用干预、已知信息，全部从资源文件读取。

这样既保留视频中"实验成功 + 三星 + 研究点 +30"的目标感，也不违背 v1.0 的"无适应度进化"：**目标只在 UI 层被判定，模拟内核不知道目标存在**。

### 6.7 生态报告

`EcologyReport` 从 `StatisticsSystem` 的环形缓冲取数，左侧 `PopulationChart`（自绘折线，每物一条曲线，hover 显示该 tick 的物种明细），右侧物种与死因面板（现存 / 峰值 / 六类死因占比），底部"记录到的事实"由 `FactGenerator` 模板生成。图表在缓冲更新时增量重绘，不逐帧重算；报告可导出 PNG + JSON（`report.export` 命令）。关闭 `R/Esc`。

### 6.8 开发者模式与控制台

`DevPanel` 开关：解锁全部关卡、跳过引导、研究点 +100、基因预算不限、帧率与模拟耗时显示、关闭开发者模式；另有细胞级调试信息、神经网络连接可视化、能量守恒断言。控制台指令走 `CommandBus` 的白名单扩展集：`dev.force_mutate(org_id)`、`dev.force_speciate(species_id)`、`dev.spawn_batch(...)`、`dev.dump_world(path)`。发布版保留面板但以编译期常量隐藏入口，避免误触。

### 6.9 界面清单与语义 ID 注册

| 语义 ID 前缀 | 覆盖控件 | 用途 |
| --- | --- | --- |
| `ui://menu/` | 战役 / 沙盒 / 设置 / 退出、版本标签、预览计数器 | 菜单自动化 |
| `ui://designer/` | 8 个 trait 滑块、位点列表、器官库、呼吸下拉、预算条、投放按钮 | Agent 改基因 |
| `ui://sim/` | 时间/倍速、物种列表项、环境数值、工具按钮、小地图、事件日志 | 状态读取与工具触发 |
| `ui://report/` | 曲线图、死因面板、事实列表、导出按钮 | 报告自动化 |
| `ui://result/` | 三星图标、奖励数值、继续/重试 | 结算验证 |

注册规则：控件在 `_ready()` 调用 `SemanticRegistry.register(id, self)`，重复 ID 在开发构建下直接断言失败；`AgentBridge` 的 `ui.click(id)` 通过注册表找到控件后调用其 `act()` 方法而非模拟鼠标坐标，避免分辨率依赖。

## 7. AI Agent 交互接口（承接 v1.0 §10）

### 7.1 契约与实现映射

v1.0 §10 定义的 17 个接口是**外部契约，名称与参数保持不变**。Godot 侧统一由 `CommandBus.execute(cmd)` 路由：命令对象含 `name`、`args`、`issuer`（ui/agent/script）、`tick_index`；查询类返回只读 JSON，写入类进入下一 tick 第 1 阶段的命令队列，因此 UI 点击与 Agent 调用完全等价、可重放。

| 类别 | 上游接口 | Godot 实现 | 校验 / 副作用 |
| --- | --- | --- | --- |
| 界面导航 | `ui.open_editor()` | `UIManager.push(DESIGNER)` | 模态切换，不改模拟状态 |
| 界面导航 | `ui.open_report()` | `UIManager.push(REPORT)` | 同上 |
| 界面导航 | `ui.back_to_sandbox()` | `UIManager.pop_to(SANDBOX)` | 同上 |
| 基因编辑 | `gene.set_trait(species_id, trait_name, level)` | 改 `GenomeResource.traits[]` | 校验 trait 名、Lv 范围、预算；重算派生属性 |
| 基因编辑 | `gene.set_respiration(species_id, type)` | 改 `respiration` 字节 | 校验枚举；兼性扣 2 点预算 |
| 环境干预 | `env.add_nutrient(x, y, amount)` | 生成 `SourceOp`（营养通道） | 世界坐标→格坐标；从储备池扣减，守恒 |
| 环境干预 | `env.set_temp(x, y, value)` | `SourceOp`（温度通道） | 钳制到配置范围；记录持续时间 |
| 环境干预 | `env.draw_barrier(x1, y1, x2, y2)` | `SourceOp`（固体 mask，45 s） | 线段长度上限；自动到期移除 |
| 模拟控制 | `sim.set_speed(rate)` | `SimClock.set_speed()` | 仅接受 {0,1,3,8,16,32} |
| 模拟控制 | `sim.pause()` | `SimClock.pause()` | 等价于 `set_speed(0)` |
| 模拟控制 | `sim.save_bookmark(name)` | `SaveManager.save(bookmark)` | 名称唯一性；异步落盘 |
| 模拟控制 | `sim.load_bookmark(name)` | `SaveManager.load()` | 版本迁移校验，失败不破坏当前世界 |
| 数据查询 | `sim.get_population(species_id)` | 读统计快照 | 返回 `{alive, births, deaths, peak}` |
| 数据查询 | `sim.get_ecology_report()` | 序列化报告缓冲 | 返回曲线、死因、事实数组 |
| 数据查询 | `sim.get_phylogeny()` | 序列化谱系树 | 返回节点/边/物种分化事件 |
| 生物操作 | `organism.spawn(species_id, x, y, count)` | 批量创建 `ZYGOTE` | 校验物种存在、坐标合法、实体上限 |
| 生物操作 | `organism.erase_area(x, y, radius)` | 标记区域内实体 `DEAD` | 半径上限；死因记为"干预" |

v2.0 扩展接口（不改动上游契约，单独列出）：`sim.step()`、`sim.set_paused(bool)`、`tool.apply(tool_id, params)`、`view.focus(org_id)`、`view.set_mode(mode)`、`gene.export(species_id, path)`、`gene.import(path)`、`env.set_preset(name)`、`save.fork(bookmark_name)`、`report.export(path)`、`sim.get_state()`、`ui.click(semantic_id)`、`dev.set_flag(key, value)`。

### 7.2 通道与安全

| 项 | 设计 |
| --- | --- |
| 默认状态 | **关闭**。需在设置或启动参数 `--agent-bridge` 显式启用 |
| headless 通道 | stdin/stdout 的 JSON Lines，一行一请求，适合自动化测试与脚本批处理 |
| 桌面通道 | 本地 TCP `127.0.0.1:39393`，同样 JSON Lines；不监听外网地址 |
| 请求格式 | `{"id": 12, "cmd": "gene.set_trait", "args": {...}, "token": "..."}` |
| 响应格式 | `{"id": 12, "ok": true, "data": {...}}` 或 `{"id": 12, "ok": false, "error": {"code": "...", "msg": "..."}}` |
| 鉴权 | 启动时生成一次性 token，写入本地临时文件并打印到控制台；无 token 请求一律拒绝 |
| 权限 | 三种模式 `readonly` / `sandbox` / `full`；只读模式仅查询类可用，`dev.*` 仅在 `full` 且开发者模式开启时可用 |
| 限流 | 单连接 60 请求/秒；写入命令合并到下一 tick，不在渲染线程直接改状态 |
| 审计 | 每条写入命令记录 `issuer / tick_index / args / 结果`，随存档保存，供回放复现 |

### 7.3 状态快照 schema

`sim.get_state()` 返回固定结构的只读 JSON，字段稳定、可版本化：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `schema_version` | int | 快照格式版本 |
| `tick` / `sim_time` | int / float | tick 序号与游戏内秒 |
| `speed` / `paused` | int / bool | 时间控制状态 |
| `life_count` / `lineage_count` | int | 对应主菜单右下角计数 |
| `species[]` | array | `{id, name, alive, peak, color}` |
| `environment` | object | 温度、溶解营养、氧气、光照、生物量、水流 |
| `fields_digest` | string | 场纹理哈希，用于回归比对 |
| `active_tools[]` | array | 仍在生效的干预工具与剩余时间 |
| `objective` | object / null | 预设实验的目标进度；沙盒模式为 null |

### 7.4 验收场景

在 `--headless --agent-bridge --readonly=false` 下，用一个脚本完成：`sim.pause()` → `gene.set_trait(A-02, speed, 40)` → `organism.spawn(A-02, 0, 0, 20)` → `sim.set_speed(8)` → 等待 600 tick → `sim.get_population(A-02)` → `sim.get_ecology_report()` → `report.export(path)`。要求：全程无人工点击、产物与 UI 手动操作等价、同一随机种子两次运行结果逐字段一致。这是阶段 5 的硬性 DoD。

### 7.5 后续候选（不进本版契约）

`ALIEN` 内置 MCP server（`127.0.0.1:8765/mcp`）、提供最近 1000 条命令日志并按用途给工具分组；其 `alien-cli` 支持无窗口批量跑模拟。这些设计佐证了本文 §7.2 的本地通道与 §9.1 的 `--headless` 回归路线。以下两项**列为 v2.2 候选，本版不实现、不进接口契约、不影响阶段 5 的冻结**：

| 候选 | 价值 | 前置条件 |
| --- | --- | --- |
| MCP 适配层（把现有命令白名单映射为 MCP tools） | Agent 可用自然语言驱动实验，无需记命令名 | 阶段 5 契约冻结后以独立适配层追加；不得反向修改 17 个上游接口 |
| `agent.get_command_log(limit)` | 让 Agent 自省最近写入命令，便于复现实验步骤 | 复用 §7.2 已有的审计日志，只加只读查询 |

本版仍以 JSON Lines + 一次性 token + `readonly / sandbox / full` 权限为准；引入 MCP 前需评估本地端口暴露面与鉴权模型，不得取消 token 校验。

## 8. 性能预算与优化

### 8.1 目标指标

| 指标 | 目标 | 测量方式 |
| --- | --- | --- |
| 渲染帧率 | 1920×1080，1× 倍速 ≥ 60 fps | 开发者 HUD / 导出帧耗时 CSV |
| 逻辑 tick 耗时 | 1000 生物 / 8000 细胞时 ≤ 8 ms（CPU 回退 ≤ 14 ms） | `Time.get_ticks_usec()` 分阶段埋点 |
| 实体规模 | 默认上限 3000 生物 / 24000 细胞 | 超限按最老/最弱个体自然淘汰，不硬截断 |
| 场更新 | 256² × 5 通道，单 tick ≤ 1.2 ms（GPU） | GPU 时间戳查询（可用时） |
| 内存 | 常驻 ≤ 1.2 GB，存档 ≤ 40 MB | OS 监控 + `Performance` 监视器 |
| 存档耗时 | 自动存档 ≤ 250 ms（异步，不卡帧） | SaveManager 埋点 |
| 启动时间 | 冷启动到主菜单 ≤ 4 s | 启动埋点 |

**规模口径（v2.1）**：`Cell Lab` 官方标定"最多 1000 个细胞仍流畅"（移动端、矢量渲染），`ALIEN` 则面向百万级 CUDA 粒子。本文取中间量级并明确**不追求百万粒子**：以 1000 生物 / 8000 细胞为性能达标线、3000 / 24000 为软上限，因为本版的开销大头是逐生物神经、发育程序与谱系记账，而不是纯粒子物理。所有跨原型对比都只用于校准量级，不作为提升目标的依据；任何规模目标上调需先重跑 §9.4 的三档基准。

**v0.30.0 专项验收口径**：v0.29 基线（无头 CPU 回退）为 300 细胞 29.0 ms/tick、1000 细胞 114.2 ms/tick、3000 细胞 389.1 ms/tick，且 30 细胞视图重建 5.25 ms/帧、>512 细胞退化为 MultiMesh 色块。本专项的「3000 细胞流畅」以同口径基准对比：去掉 O(n²) 场采样与重复建格后，3000 细胞 tick 成本须显著下降；批渲染层须在 3000 细胞规模保留共享弦切平膜而非纯色块，且不破坏 `get_state_hash()` 与存档兼容。测得数字写入 CHANGELOG 与分析文档 §33，不把未达标的数字表述为达标。

### 8.2 计算分工

| 任务 | 执行位置 | 说明 |
| --- | --- | --- |
| 场扩散 / 平流 / 采样 / 统计累加 | GPU Compute | 2 张 ping-pong 存储纹理 + 1 个 storage buffer |
| 感知 / 神经 / 代谢 / 细胞积分 | WorkerThreadPool 分组 | 按实体 ID 静态分区，单写者约束见 §2.5 |
| 实体增删 / 突变 / 物种判定 / 统计聚合 | 主线程 | 低频、顺序敏感，保证确定性 |
| 存档序列化 / 压缩 | 独立线程 | 双缓冲快照 |
| UI 组装 / MultiMesh 填充 | 主线程 | 按 §6.4 节流 |

### 8.3 降级阶梯

| 触发条件 | 动作 |
| --- | --- |
| 连续 30 帧 > 20 ms | 关闭景深与扫描线，粒子实例上限降至 60% |
| 连续 90 帧 > 22 ms | LOD 强制降一档，神经更新频率减半 |
| 倍速 ≥ 16× | 主动关闭后处理，渲染锁 30 fps |
| 实体数 > 80% 上限 | 提高分解速率、降低新生初始能量（通过资源竞争自然抑制，不直接杀实体） |
| 检测到 compute 不可用 | 整体切到 `CpuFieldBackend`，场分辨率降至 128²，功能不缺失 |

### 8.4 已知陷阱

| 陷阱 | 对策 |
| --- | --- |
| 每帧 `texture_get_data` 造成 GPU 同步等待 | 只回读紧凑采样缓冲，且每 4 tick 一次；热力图由 shader 直接采样 |
| 频繁 `instantiate/queue_free` 造成 GC 抖动 | 实体、细胞、事件、SourceOp 全部对象池 |
| 逐实体 `draw` 调用 | 统一 MultiMesh 批量 + 增量更新脏区间 |
| 长跑谱系数据膨胀 | 环形缓冲 + 每 N tick 降采样；灭绝物种只留摘要 |
| 浮点不确定性破坏回放 | 固定分区、固定累加顺序、派生 RNG，见 §2.5 |

## 9. 测试与验收

### 9.1 测试金字塔

| 层 | 工具 / 方式 | 覆盖 |
| --- | --- | --- |
| 纯逻辑单测 | GUT，`tests/unit/` | 基因组编解码、CRC、突变算子、派生属性、预算校验、发育指令合法性、DSL 判定 |
| 模拟集成 | `--headless` 场景，`tests/integration/` | 单细胞闭环、多细胞发育、能量守恒、呼吸机制、物种分化、工具效果、存档往返 |
| UI 自动化 | `SemanticRegistry` + `ui.click` | 生命设计器绑定到预览、工具应用、报告生成、屏幕栈 |
| 确定性回归 | 固定种子 + 命令脚本 | 同脚本两次运行逐字段一致 |
| 性能基准 | `tests/bench/` | §8.1 各项指标 |

### 9.2 关键测试用例

| 编号 | 用例 | 期望 |
| --- | --- | --- |
| T01 | `GenomeCodec.decode(encode(g))` 往返 10 万次随机基因组 | 逐字节一致，CRC 通过 |
| T02 | 破损/越版本基因组导入 | 拒绝并给出错误码，不产生半初始化实体 |
| T03 | 单个光合生物在恒定光照下跑 10000 tick | 能量守恒误差 < 0.1%，种群稳定不爆 |
| T04 | 厌氧生物置于氧浓度 10% 环境 | 按规则受到中毒损伤并最终死亡，死因归类正确 |
| T05 | 发育程序突变产生非法跳转/超长程序 | 校验器拒绝，回退到父代程序 |
| T06 | 好氧 / 厌氧 / 兼性在相同营养下的能量效率 | 符合 3.0 / 1.0 / 中间值与预算 −2 规则 |
| T07 | 干预工具只做空间转移 | 工具前后 `E_total` 在误差范围内不变 |
| T08 | 存档 → 继续跑 → 读档 → 继续跑 | 两条路径 1000 tick 后状态哈希一致 |
| T09 | 分支演化 | 父存档不被修改，父 ID 链正确 |
| T10 | Agent 脚本端到端（§7.4） | 全程自动、结果可复现 |
| T11 | 32× 倍速跑 10000 tick | 无补帧雪崩，模拟时间落后有提示，渲染不卡死 |
| T12 | 禁用 compute 后重跑 T03/T10 | 功能一致，仅精度/性能下降 |
| T13 | 连续应用 1000 次工具干预（营养投放 / 局部升温 / 隔离膜 / 擦除区域），逐项对账 `E_external ↔ E_env` 与 `E_bio → E_env` | 每一步借贷账目齐全，`E_total` 全程误差 < 0.1%；隔离膜/洋流类工具不产生能量增删 |
| T14 | 同一皿内配置 2 个不同参数的 `EnvironmentPreset.layers[]`，跑 5000 tick | 跨区域场值连续无突变、全场总量守恒、同种子两次运行状态哈希一致；清空 `layers[]` 后结果与全局参数模式一致 |

T13 / T14 为 v2.1 随外部参考增补新增，分别对应 §4.3 的外部能量池记账与 §3.1 的区域参数覆盖；两者都不改玩法规则，只把已有行为纳入回归资产。

### 9.3 确定性与存档回归

所有测试用固定种子 `DeterministicRng(seed)`；命令脚本（JSON Lines）既作为测试输入，也作为 Agent 接口的示例文档回归资产。每次提交跑一次"golden run"：生成 2000 tick 后的状态哈希与生态报告 JSON，与 `tests/fixtures/` 中基线比对；任何玩法规则变更需显式更新基线并在 PR 说明原因。

### 9.4 性能基准与长跑约束

基准场景分三档（300 / 1000 / 3000 生物），每档运行不超过 60 秒，导出帧耗时与阶段耗时 CSV 后即退出；**禁止无人值守的长时间满载循环**（开发机长时间满载易触发硬件保护）。长跑稳定性验证改为"分段运行 + 存档续跑"：每次 60 秒，读档继续，累计 30 分钟即可，既覆盖内存泄漏与数据膨胀，又避免持续满载。

### 9.5 CI 建议

最小可行流水线：`godot --headless --path . -s tests/run_unit.gd` → `tests/run_integration.gd` → `tests/bench/smoke.gd`（60 秒上限）→ 归档报告。GPU 相关用例在不具备 compute 的环境自动跳过并标记为 `skipped(reason)`，不得静默通过。

## 10. 开发里程碑与验收标准

沿用 v1.0 的六阶段节奏，为每阶段补充可验证的 Definition of Done。

| 阶段 | 周期 | v1.0 交付 | 本文追加的 DoD |
| --- | --- | --- | --- |
| 1 基础沙盒原型 | 2 周 | 圆形皿视图与缩放、单细胞进食/运动/分裂/死亡、营养与温度场、最简 4 性状编辑器、种群统计与事件日志 | 项目骨架与 Autoload 全部就位；T03 通过；固定 tick 与 1×/3×/8× 可用；帧率 ≥ 60 fps @300 生物 |
| 2 多细胞发育体系 | 4 周 | 发育式基因组、受精卵到成熟、10 种功能细胞、弹性连接与软物理、编辑器支持多细胞构型 | T01/T05 通过；`GenomeCodec` 与 `.gnm` 格式冻结；能量守恒断言默认开启 |
| 3 分布式神经与行为 | 3 周 | 细胞级神经、感知-决策-运动闭环、觅食/避障/捕食、呼吸与能量效率 | T04/T06 通过；WorkerThreadPool 分区无共享写；同种子两次运行哈希一致 |
| 4 完整进化引擎 | 3 周 | 全类型突变、谱系追踪、物种分化、系统发育树、演化趋势、生态报告 | 物种判定与灭绝档案可导出；T08 通过；报告事实全部由数据生成 |
| 5 沙盒工具与观测 | 3 周 | 10 类工具、地形编辑、多视图、存档/书签/分支、开发者模式 | T07/T09/T10 全部通过；Agent 17 个上游接口 100% 可用；语义 ID 无重复 |
| 6 性能与视觉打磨 | 2 周 | Compute Shader 迁移、千级规模优化、显微镜后处理、物种库与环境模板、交互反馈 | §8.1 指标全达标；T11/T12 通过；CPU 回退路径功能完整；长时间分段跑无泄漏 |

**跨阶段约束**：阶段 2 冻结基因组二进制格式，阶段 4 冻结存档 schema，阶段 5 冻结 Agent 接口契约。冻结后只允许追加字段与版本化迁移，不允许破坏性改名——否则回归资产与外部脚本会全部失效。

## 11. 风险与对策

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| Compute Shader 在部分 GPU / 渲染器不可用 | 核心玩法跑不起来 | 启动能力探测 + 功能等价的 CPU 回退路径，T12 常态验证 |
| 多线程破坏确定性 | 存档回放与 Agent 自动化失效 | 静态分区 + 单写者 + 派生 RNG + golden run 基线 |
| 开放式进化导致生态崩溃或种群爆炸 | 体验失真、性能失控 | 资源竞争自然抑制、实体软上限、自动存档与分支回溯；不引入人工适应度干预 |
| 谱系/日志数据长时间膨胀 | 内存与存档体积失控 | 环形缓冲、降采样、灭绝物种只留摘要 |
| 发育突变产生非法程序导致卡死 | 主线程挂起 | 指令校验器 + 执行 tick 预算 + 非法回退父代 |
| UI 控件数量多、布局适配复杂 | 语义 ID 漂移、自动化脆弱 | 屏幕栈复用实例、`_ready()` 注册 + 重复 ID 断言、UI 自动化回归 |
| 上游规格与视频表现存在冲突（关卡 vs 沙盒） | 设计摇摆 | §0.3 / §6.6 明确分层：目标只在表现层判定，模拟内核无感知 |
| 中途更换引擎小版本 | 计算管线与序列化行为变化 | 锁定 `project.godot` 与导出模板版本，升级需跑完整回归并更新基线 |
| 参考原型导致范围蔓延（领地对抗 / 适应度引导 / 每细胞独立基因组 / 百万粒子） | 破坏 v1.0 规格、工期与性能失控 | §0.5.3 决策表逐条标注"采纳 / 部分采纳 / 不采纳"；不采纳项若需引入，必须先修订 v1.0 并同步 §0.3 与本节；新增机制一律配 T13/T14 式回归用例 |
| 多细胞个体引入后范围蔓延（分化树 / 端粒 / 受精 / 病毒注入 / 每细胞独立基因组） | 破坏 v1.0 §5.3 与冻结契约，存档体积与性能失控 | §0.5.3 与 §0.6 明确「部分采纳（机制）」边界与不采纳清单；分化树 40 槽已于 v0.29.0 先修订 v1.1 §5.3.5 再按 §0.3 版本化追加；新增机制须先修订 v1.0，并配 §9.2 回归用例；细胞内结算采用"先合计再分配"，由守恒断言兜底 |
| 食物实体池变成第二套能量真相 | 与五通道营养场冲突、确定性 hash 与存档回放失效 | v0.14.0 已修订 v1.0 §2.2 与本文 §0.3：实体池只读派生、池尾交换、质量衰减、不写能量结算/不进 hash；若未来要参与摄能，必须先版本化升级 schema 并配回归用例 |
| `flags` bit1 基因模式改变基因组 hash | 与 v0.14.x 指令模式的回放/物种 hash 不同 | 只给已编码的未使用位追加语义（v1.1 §5.3 / 本文 §0.3 已记录）；0 值完全保持旧行为；基因字段走 schema v2/v3 + 命令 payload，不进 GNP1；SmokeTest 断言两种模式、存档往返与分裂分化连接 |
| v0.16.0 逐细胞半径/刚度/颜色数组改变存档与回放 | 旧快照缺字段、物理结果漂移 | 新数组列为可选字段：schema 1–2 恢复填 1.0/类型色默认值；物理与渲染共用同一倍率，0.5 默认强度与 1.0 默认半径逐位保持旧结果；新基因字段只进 hash 不进 GNP1；SmokeTest 覆盖旧档恢复、倍率效应与颜色仅视图不改 hash |
| v0.17.0 多模式槽改变分裂/表型/存档 | 旧快照缺 `modes`、`cell_mode`；逐模式编辑串数据；连接传递率从 0 变非零改变能量轨迹 | `modes` 只在非空时混入 hash；schema 4 保存，1–3 恢复填空数组/0；flags 清零或空 modes 保持旧传递率 0 与旧行为；模式切换先提交当前槽再载入；每个体每 tick 最多一次分裂 + 顶层最大细胞数双约束；SmokeTest 覆盖两子代模式、预览点击、hash 边界、跨模式能量守恒与旧档回退 |
| v0.18.0 个体上限改无限 + 连接抑制分裂 + 端粒 | 无限个体叠加多细胞可能拖垮性能；旧快照/命令缺字段导致回放漂移；端粒死亡改变死因统计 | 每基因组 `max_cells_per_organism=-1` 只解除 per-organism 上限，仍受 `CellArray.max_cell_capacity=8000` 全局容量；旧 payload/schema 缺字段回退 `max_divisions+1`；逐模式 `link_division_limit=-1`/`telomere=-1` 保持旧行为；schema v5 保存并显式混入 hash；SmokeTest 覆盖无限生长、全局容量、连接抑制、端粒归零与旧档回退 |
| v0.22.0 去掉 depth 分裂闸门 | 去掉自增殖代数上限后细胞可能无限增殖拖垮性能；depth 字段语义变更导致旧快照/hash 漂移；预览与实际分裂口径不一致 | Cell Lab 无 depth 闸门、分裂次数由端粒 `cell_telomere` 控制（-1 无限/有限递减/归零死亡）；仅删候选闸门与 depth+1、字段/存档/hash 保持兼容不升 schema；预览三条派生路径同步去掉 depth 限制、步数仍由顶层 max_divisions 约束；GNP1/tick 顺序/12 tick 上限不动；SmokeTest 验证 max_divisions=1 自增殖突破旧上限且 depth 恒 0、双工程回归 |
| v0.21.0 分裂倍增 + 半圆出生 + 预览分裂指示器 | 逐细胞并行分裂使旧演示体/快照细胞数轨迹漂移；半圆出生间距过小可能与邻接细胞过度重叠；`cell_division_tick` 漏进 hash/存档导致回放漂移；指示器绘制误写模拟状态 | 倍增仅改调度、由 max_divisions 链与能量减半约束上限，GNP1/tick 顺序/12 tick 上限不动；出生中心距 0.2r 且下一 tick 接触排斥弹开、半径当帧不变；`cell_division_tick` 进 hash 且 schema v7 旧档填 -2；预览指示器纯绘制、不写 CommandBus/field/hash；SmokeTest 覆盖 1/2/4/8 倍增、出生帧 0.2r、下一 tick 排斥、指示器递增与双工程回归 |
| v0.19.0 半径随能量收缩/长大 + 视图热点优化 | 半径参与碰撞与分裂间距，改变位置轨迹与旧快照 hash；低通参数不当导致半径抖动或恒不长大；整数 pair key 在超 8000 索引时碰撞；降膜点数影响贴合视觉 | 仅 gene_mode 生效，非基因模式/开关关闭逐位保持旧半径；`target²=clamp(E/E_ref,0.5²,1²)` + 一阶低通有界（step≤1）且固定索引顺序、不写 RNG；schema v6 旧档 baseline=旧有效倍率、因子=1.0；数组纳入状态 hash；pair key 用 `low*8001+high`（>8000 全局容量）；`outline_segments` 默认 64 保持独立实例旧行为、CellBase 场景设 48；SmokeTest 覆盖稳态/渐进/可逆/旧档/hash 与双工程回归 |
| `flags` bit0 语义改变基因组 hash | 旧快照里的 flags 位从「无语义」变为「亲子自动连接」，回放/物种 hash 随之改变 | 只给已编码的未使用位追加语义（v1.1 §5.3 / 本文 §0.3 已记录）；0 值完全保持旧行为；SmokeTest 断言置位/清零两条路径与 hash 变化，发布说明明确提示版本差异 |

## 12. 附录

### 附录 A 参考材料与章节映射

| 上游 / 参考 | 本文对应章节 |
| --- | --- |
| v1.0 §1 项目概述、§2 核心模拟设定 | §0.3 范围决策、§4.1 场求解、§4.3 代谢 |
| v1.0 §3 界面系统规范 | §5.4 主题、§6.2–6.9 界面实现 |
| v1.0 §4 干预工具系统、§4.3 时间控制 | §3.1 ToolDef、§2.6 时间控制、§6.5 工具交互 |
| v1.0 §5 生物与基因系统 | §3.2 基因组、§4.2–4.7 发育/物理/神经/突变 |
| v1.0 §6 进化与生态、§7 沙盒特性 | §4.7–4.8、§3.5 存档与分支、§6.7 报告 |
| v1.0 §8 Godot 技术方案 | §1 技术基线、§2 架构、§3 数据结构、§8 性能 |
| v1.0 §9 开发路线图 | §10 里程碑与 DoD |
| v1.0 §10 AI Agent 接口规范（完整版新增） | §7 全部，17 个上游接口原样保留 |
| 视频：主菜单 / 章节页 / 设计器 / 模拟 HUD / 报告 / 结算 / 开发者面板 | §0.2 核对表、§6 各界面 |
| Substrate: Emergence（Steam 商店长描述、最低/推荐配置、无障碍类别） | §0.5.1 / §0.5.3、§1.1、§1.3、§5.4、§8.1 |
| Cell Lab（官网特性列表与 Play 商店文案） | §0.5.1 / §0.5.3、§0.3、§3.1、§5.1–5.2、§6.6、§8.1 |
| Cell-Lab-Remake（GitHub README） | §0.5.2 版本辨析、§9.3 单一事实源约定 |
| ALIEN（README 与 `resources/docs/*.md`，BSD 3-Clause） | §0.5.1 / §0.5.3、§3.1、§3.4、§4.3、§4.4、§4.6、§4.7、§7.5、§8.1 |
| Cell Lab 官方汉化 APK v103 / Macro 0.2.0-beta.299（REA / JADX 0.7.1 静态反编译，APK 未执行） | `analysis/CellLab_APK_解析报告.md` §11 / §12、`analysis/CellLab_多细胞协作_设计规格.md`；对应 §0.6、§4.3–4.5、§11 |

**引用边界**：上表四个原型仅用于机制对照、量级校准与取舍论证。ALIEN 为 BSD 3-Clause 开源工程，本文只引用其公开文档中的机制描述，未复制源码、资源或文档原文；Substrate: Emergence 与 Cell Lab 为商业产品，只引用其官方公开文案，不推断未公开的内部实现。

**P0 引用边界补充**：两份 APK 解析文档只用于机制对照与规则细化，未复制反编译源码、shader、图片或文案；静态反编译不证明设备运行时行为，相关推断的置信度与未确认项见 `analysis/CellLab_多细胞协作_设计规格.md` §7。

### 附录 B 默认参数表

以下为**设计默认值，需在阶段 1–2 通过基准测试调参**，全部集中在 `res://data/config/sim_defaults.tres`，禁止散落在代码里。

| 参数 | 默认值 | 参数 | 默认值 |
| --- | --- | --- | --- |
| `tick_rate` | 60 Hz | `dish_radius` | 1024 世界单位 |
| `field_resolution` | 256² | `spatial_grid_size` | 64 单位 |
| `budget_max` | 16（沙盒无限） | `locus_count` | 8（允许 4–16） |
| `base_temperature` | 22 ℃ | `vent_temperature` | 基准 +40 ℃ |
| `base_mutation_rate` | 0.001 / 分裂 | `pressure_mutation_mult` | 1.0–4.0 |
| `speciation_distance` | 待调参（初值 12） | `speciation_cooldown` | 600 tick |
| `max_organisms` | 3000 | `max_cells` | 24000 |
| `auto_save_interval` | 60 s | `rolling_save_slots` | 8 |
| `stats_buffer_size` | 7200 点 | `stats_aggregate_every` | 30 tick |
| `single_frame_tick_cap` | 12 | `agent_port` | 39393（仅本机） |
| `dev_tick_budget` | 600 tick | `layer_blend_width` | 32 世界单位 |
| `external_energy_pool_init` | 由 `EnvironmentPreset` 给定 | `energy_assert_epsilon` | 0.001（相对误差） |
| `max_links_per_cell` | 20（待调参） | `cell_transfer_rate` | 待调参（初值 0.1） |
| `max_cells_per_organism` | 待调参 | `dev_divide_link_limit` | 同 `max_links_per_cell` |

`dev_tick_budget`、`layer_blend_width`、`external_energy_pool_init`、`energy_assert_epsilon` 为 v2.1 增补，分别对应 §4.4 发育预算、§3.1 区域边界混合、§4.3 守恒断言；`max_links_per_cell`、`cell_transfer_rate`、`max_cells_per_organism`、`dev_divide_link_limit` 四项为 P0 增补，对应 §4.4 连接数抑制分裂与 §4.3 细胞内再分配，缺省时退化为单细胞个体行为。全部为设计默认值，需在阶段 1–2 通过基准测试调参；v2.1 与 P0 增补项均为可选，缺省时行为与 v2.0 完全一致。

### 附录 C 关键接口签名

| 类 | 签名 | 职责 |
| --- | --- | --- |
| `SimClock` | `func advance(delta: float) -> void` / `signal tick_advanced(index: int)` | 固定步长调度、倍速、暂停、单步 |
| `SimTick` | `static func execute(world: SimWorld, tick: int) -> void` | 按 §2.5 固定顺序推进 14 个阶段 |
| `CommandBus` | `func execute(cmd: Command) -> Result` / `func undo() -> Result` | 唯一写入口、校验、审计 |
| `GenomeCodec` | `static func encode(g: Genome) -> PackedByteArray` / `static func decode(b: PackedByteArray) -> Genome` | `GNP1` 二进制编解码 |
| `DerivedStats` | `static func compute(g: Genome) -> DerivedStats` | 纯函数派生属性（预算/耗能/游速/视野） |
| `IFieldBackend` | `func step(sources: Array[SourceOp]) -> void` / `func sample(pos: PackedVector2Array) -> PackedFloat32Array` | GPU / CPU 双实现同接口 |
| `SimWorld` | `func snapshot() -> WorldSnapshot` / `func digest() -> String` | 只读快照与确定性哈希 |
| `SaveManager` | `func save(name: String) -> void` / `func fork(bookmark: String) -> String` | 存档、书签、分支 |
| `SemanticRegistry` | `func register(id: String, c: Control) -> void` / `func find(id: String) -> Control` | 语义控件注册与查找 |
| `AgentBridge` | `func handle_request(line: String) -> String` / `func state_json() -> Dictionary` | JSON Lines 请求与状态导出 |
| `ObjectiveEvaluator` | `func evaluate(def: ExperimentDef, s: WorldSnapshot) -> ObjectiveState` | 只读目标判定，永不写模拟 |

**P0 注**：多细胞相关的 `CellArray` / `DevProgram` / `MulticellularBody` 接口签名草案见 `analysis/CellLab_多细胞协作_设计规格.md` §5「接口草案」，属 P1 实现范围；待落地并跑通 headless 验证后再补入本表。

### 附录 D 交付物清单

| 交付物 | 路径 | 说明 |
| --- | --- | --- |
| 工程实现版设计文档 | `docs/Godot项目技术设计文档.md` | 本文，随仓库版本管理 |
| 可评审 DOCX | `创生模拟器_Godot项目技术设计文档.docx` | 与本文内容一致的排版版本 |
| 配置基线 | `res://data/config/sim_defaults.tres` | 阶段 1 建立，附录 B 为初始值 |
| 接口契约 | `res://agent/commands/*.gd` | 阶段 5 建立，附录 C 与 §7 为契约 |
| 回归资产 | `tests/fixtures/` | golden run 哈希、命令脚本、示例存档 |

---

**变更记录**：

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| v2.0 | 2026-11-11 | 初稿，基于 v1.0 完整版（含 §10 AI Agent 接口规范）与《创生协议》实机视频核对结果编写 |
| v2.1 | 2026-11-11 | 增补 §0.5 外部参考原型核对（Substrate: Emergence / Cell Lab / Cell-Lab-Remake / ALIEN），回答"Cell-Lab-Remake 是否为官方 PC 版"，并把可落地技术点补入 §1、§3、§4、§5、§7.5、§8、§9、§11、附录 A/B；新增 T13/T14 回归用例。**未修改 v1.0 玩法规则，未改动任何已冻结或待冻结契约** |

后续玩法规则变更须同步维护 v1.0 与本文；引入 §0.5.3 标注为"不采纳"的机制前，须先走规则变更流程。

