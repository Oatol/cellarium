# 变更记录

版本号规则见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` §11.1。文档版本与工程版本在本文件中关联。

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
