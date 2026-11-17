# 变更记录

版本号规则见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §11.1。文档版本与工程版本在本文件中关联。

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
