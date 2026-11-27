# cellarium

Godot 4.x 2D 人工生命沙盒（木卫二冰下海洋世界观）的设计文档与工程规格仓库。

核心玩法：玩家设计单细胞与多细胞生物，投放到可交互的圆形培养皿中，观察其在自然选择下的生存、繁殖、突变与生态涌现。**无适应度函数、无强制关卡**，能量与物质严格守恒，支持从宏观种群到显微细胞的多级观测与全维度环境干预。

复刻重点：Cell Lab 的**多细胞设计**，以及**不同细胞类型组成同一个体后互相协作的设计理念**（借鉴概念与机制，不复制源码、shader、图片或文案）。

---

## 文档索引

| 文件 | 作用 | 权威级别 |
| --- | --- | --- |
| `godot/cellarium-release/` | 可运行 Godot 工程快照（4.7.2；不含本机 MCP 插件与引擎缓存） | 实现快照 |
| `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md` | 玩法与系统规格：v1.0 原文逐字保留 + P0 多细胞协作条款 + Cell Lab / Macro 借鉴章节 + 第二轮增补（§5.3.6 单细胞个体与发育深度轴、§5.4.1 DIVIDE/REPRODUCE 分离）+ 工程重写与版本备份 | **玩法权威（待用户确认后正式生效）** |
| `docs/Godot项目技术设计文档.md` | Godot 施工图：tick 架构、数据结构、CommandBus、GNP1、Agent 契约、GPU 场与验收基准 | **实现权威** |
| `docs/v1.0_P0补充条款_待并入.md` | P0 五条玩法条款的原件存档（已并入 v1.1 合并稿） | 存档 |
| `analysis/CellLab_APK_解析报告.md` | 两个 Cell Lab APK 的静态解析：tick 主循环、对象池、分化树、18/33 类型、4 通道化学信号 | 证据 |
| `analysis/CellLab_多细胞协作_设计规格.md` | 多细胞个体与细胞协作的反编译证据、六条机制、P0–P3 落地方案与验证清单 | 证据 / 规格 |
| `analysis/CellLab_界面与实验条件_词条证据.md` | 工具、培养基设置、显微视野、培养条件（冻结 / 慢速观察 / 观察 / 培养 / 过夜培养）的资源层词条证据 | 证据 |

冲突时：**玩法看 v1.1 合并稿，实现看 v2.1 设计文档**；任一层改动须同步另外两层。

## 参考与证据边界

- 上游参考：《创生协议》界面与玩法、Alien（chrxh/alien）粒子物理与进化框架、Substrate 的化学场、Cell Lab 的基因编辑与细胞分工。
- APK 样本：Cell Lab 官方汉化 v103（`com.saterskog.cell_lab`）与 Macro 0.2.0-beta.299（`com.massivemistakes.hydralab.dev`）。**全程静态反编译 / 资源解码，APK 未执行**；不证明运行期行为，也不包含任何 APK 二进制或反编译中间产物。
- 文档中的本机路径是开发记录，不是运行时依赖。

## 工程与验证

新 Godot 工程位于本机 `D:\Tools\Godot_v4.7.2\project\cellarium\`，可运行源码快照纳入 `godot/cellarium-release/`（不含 `.godot/` 缓存与本机 MCP 插件）；旧 `Genesis` 保留为参考与回退基线，不纳入本仓库。无头验证命令：

```
Godot_v4.7.2-stable_win64_console.exe --headless --path <project> --script res://tools/SmokeTest.gd
```

验收要求：`EXITCODE=0`、无脚本解析错误；新增脚本必须登记 `SmokeTest.gd` 清单。GPU 场需窗口 Vulkan 环境验证，无头下会自动回退 CPU。

技术基线（不可擅改）：沙盒为核心；固定 1/60 tick 与「tick 频率 + LOD、单帧上限 12」；确定性（静态分区 + 单写者 + 派生 RNG）；`CommandBus` 唯一写入口；5 类环境场 2 张 ping-pong 存储纹理 + 等价 CPU 回退；GNP1 / 存档 schema / Agent 契约冻结后只做版本化追加。

## 性能专项（已达标）

1025 细胞真实窗口裸 tick 同会话两轮 **7.48 / 7.29 ms**，稳定低于 ≤8 ms/tick（v0.45 达标，v0.46 signal 再降 31%）。全程 state hash 与场值 flat parity 逐位不变。分段计时驱动的全过程、闸门口径与已证伪猜测见：

- `HANDOFF.md`：会话交接（现状、路径、命令、铁律、已证伪清单）
- `analysis/CellLab_细胞物理与外观_代码级分析.md` §48–§51：Cell Lab / Alien 防卡源码级结论 + v0.44–v0.46 性能专项
- `CHANGELOG.md`：逐版本 A/B 数据与闸门记录
- `.workbuddy-ai/memory/MEMORY.md`：踩坑结论（接手必读）

性能基准单次 ≤60 秒（机器长时满载会过热蓝屏），并发编译 `-j 4`；任何改动须重跑双工程 SmokeTest + NativeParityProbe + 真实窗口 flat parity。

## 版本与备份

见 `CHANGELOG.md` 与 v1.1 合并稿 §11。每个版本上传：tag + 变更摘要 + 文档/代码快照 + 验收记录。
