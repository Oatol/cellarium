# Cell Lab APK 解析报告

日期：2026-11-13
最近更新：2026-11-15（新增多细胞协作专题，见 §13 第 6 条与配套文档）
历史更新：2026-11-14 补完官方核心模拟逻辑与 Macro 类型系统对照（§11）、4 通道化学信号独立子系统规格（§12）

## 1. 输入样本

| 样本 | 角色 | 文件大小 | SHA-256 | 签名结构 |
|---|---|---:|---|---|
| `C:\Users\安\Downloads\cell-lab-zh.apk` | 官方版本汉化包 | 8,576,192 B | `5f29fdf162fb443cc09be7808c70e9ec2501833d23c0801cea2810684c88986c` | v1，1 个声明 signer |
| `C:\Users\安\Downloads\cell-lab-macro-beta-latest.apk` | 社区 Macro Mod | 17,952,354 B | `9d0f3509c871ef4afbcf5547dd4125adbf5745059faf94e74d5d8b3e8aa48a1a` | v1 + v2，v1/v2 signer 指纹一致 |

签名结论只表示 APK 声明的签名结构和文件摘要，REA 没有执行证书真实性、证书链或签名密码学验证；不能据此确认发布者身份。

## 2. REA 分析状态

已使用 REA 做了：

- 两个 APK 的签名结构、SHA-256、大小和 v1/v2 scheme 对照。
- 使用 Apktool 3.0.3 解码官方版和 Macro Mod 的 Manifest、版本信息、locale 与字符串资源。
- 用户提供的 `jadx-headless-mcp-0.8.0-all.jar` 可启动，但 REA 明确拒绝该版本（要求 0.7.1）。用户随后提供 `jadx-headless-mcp-0.7.1-all.jar`；重启 WorkBuddy 后 REA 已成功识别该版本，两个 APK 的 Android package/DEX 元数据分析均完成。
- 已用 JADX 0.7.1 静态反编译 `Cell`、`CellWorld`、`Environment`、`Gene`、细胞类型枚举 `h`，以及 Macro 的 `Cell`、`Gene`、类型枚举 `C`、位标志类 `K8` 的关键方法体；APK 未执行。

Apktool 已经验证可用，REA 探针确认 launcher 为 `D:\Tools\Apktool\apktool.bat`、版本 3.0.3。本文将「直接 ZIP/资源证据」「Apktool 解码证据」「静态反编译证据」和「尚未确认的行为」分开记录，不把推测写成事实。

## 3. APK 容器结构

| 指标 | 官方汉化版 | Macro Mod |
|---|---:|---:|
| ZIP 条目总数 | 642 | 971 |
| `classes.dex` | 1，909,960 B | 1，1,511,564 B |
| `assets/*.substrate` | 66 | 68（另含 starter 子目录） |
| `assets/levels.xml` | 有，16,628 B | 有，16,639 B |
| 原生 `.so` | 未发现 | 未发现 |
| APK 内 `assets` 文件 | 66 | 122 |
| JADX 类数量 | 284 | 808 |
| Android 组件 | 7 个完整声明 | 组件清单部分覆盖，至少 3 个声明 |

两版都是单 DEX、无 APK 内原生库的 Android 包。Macro 的 DEX 约为官方版的 1.66 倍、类数约为 2.85 倍，ZIP 条目约多 329 个，证明存在显著代码与资源增量。组件差异显示 Macro 使用不同 package namespace `com.massivemistakes.hydralab.dev`，入口类名属于 `com.saterskog.cell_lab_enzymeglv`；官方包入口为 `com.saterskog.cell_lab.MainMenuLab`。Macro 的 Manifest 还声明 genome、substrate、selection 等自定义 MIME 类型及多种文件导入关联。

## 4. 共享玩法数据

两个版本的 `assets/levels.xml` 都包含 70 个 `<level>` 节点，绝大多数关卡配置完全相同。配置字段体现了以下玩法模型：

- 每关绑定一个 `.substrate` 场景数据文件。
- 初始用户细胞、可放置细胞、场上细胞数量上下限。
- `win-time`、`max-time` 等时间条件。
- `difficulty` 难度值。
- `tools` 工具白名单，例如 `cell,info`、`add,remove,move,info`。
- `unlocks` 细胞类型解锁。
- `feature` 等额外开关字段。

这与当前 Godot 项目的「沙盒核心 + ExperimentDef 表现层」方向一致：关卡配置适合作为数据驱动实验定义，不应把目标判定混入 tick 内物理计算。

## 5. Macro Mod 的代码规模和入口差异

REA/JADX 0.7.1 的 package 分析已完成：官方版共 284 个类，Macro Mod 共 808 个类。官方包 package 为 `com.saterskog.cell_lab`，Macro Manifest 的 applicationId 为 `com.massivemistakes.hydralab.dev`，入口类位于 `com.saterskog.cell_lab_enzymeglv`。

Macro Manifest 声明了 `.genome`、`.substrate`、`.clselection` 相关的文件打开/分享关联，以及 `application/x-cell-lab-macro-genome`、`application/x-cell-lab-macro-substrate`、`application/x-cell-lab-macro-selection` 等 MIME 类型。这表示 Macro 的外部数据工作流明确包含基因组、培养皿/底物和细胞选择文件。Manifest 是静态声明，不等于这些入口在当前 beta 中都可用；尤其关卡入口暂未开放的状态仍以实际运行观察为准。

Macro 的代码中存在专门的 `DisabledLevelsFragment`。REA 反编译其 `onCreateView()` 显示该界面创建居中的提示标题、说明文本，并显示带锁图标且 `setEnabled(false)` 的「关卡创建」按钮。这与用户在 MuMu 观察到关卡暂未开放的表现相符。具体中文文案存于 `levels_disabled_title` / `levels_disabled_message` Android string resource，应以已解码 `zh` 字符串为准；此处只记录代码绑定关系，避免把用户界面观察和静态源码混为同一证据。

Macro `GenomeEditorFragment.onCreateView()` 会动态组装参数行，而不是把所有参数写死在单一布局：包含分裂/子代设置、黏附长度与伸展、细胞骨架、细胞大小、最大/最小连接、分裂后模式、病毒来源、信号控制、鞭毛/纤毛、轴突髓鞘与延迟、细胞类型专属参数、感觉输入范围/FOV/RGB/阈值、神经输出通道、细胞类型下拉列表和基因组预览。控件按当前类型过滤，并绑定 seekbar、spinner、checkbox、帮助提示与预览回调。这为 Godot 重做编辑器提供了功能分组与动态显示依据，但不应照搬 Android 控件布局或反编译实现。

`Environment` 默认构造函数初始化了多组环境倍率/因子、布尔配置、随机状态、角度/方向以及 0.3/0.4/0.3 的三通道权重；仅构造器字段名被混淆，不能仅凭默认值给每个字段强行命名。Cell Lab 官方 `CellWorld(Parcel)` 序列化读取顺序包含环境对象、细胞数组、食物数组、若干计数/状态整数以及两个 double 值；说明存档是组合式状态载荷，迁移时应映射成项目自有 schema，而不是复用原字节布局。

## 6. Macro Mod 的直接可见增量

### 6.1 新增实验数据

Macro 相对于官方版只新增两个 assets 路径：

- `assets/starter/Starter Plate.substrate`
- `assets/starter/Test Radiation.substrate`

两个文件均为 ZIP/JAR 风格容器头（`PK 03 04`），与官方版根目录下的 Java 序列化风格 `.substrate` 不同。它们不能直接按官方 `.substrate` 的格式读取，需要单独识别内部条目和序列化结构。

### 6.2 关卡配置差异

唯一发现的 `levels.xml` 解锁差异：

- 关卡 `9`：官方为 `Keratinocyte`；Macro 为 `Keratinocyte,Osteocyte`。

关卡数量仍为 70，未发现新增关卡节点或关卡 ID。

### 6.3 新增环境材质

Macro 新增：

- `assets/environment-materials/00.png` 至 `19.png`，共 20 张。

这表明 Macro 对环境/底物的视觉或材质表达有独立资源层。当前只证明资源存在，不证明它们参与了运行时物理求解。

### 6.4 新增细胞类型图标

Macro 新增 `assets/guide-icons/`，共 34 张 PNG，名称包括：

`adipocyte`、`axon`、`buoyocyte`、`catalocyte`、`ciliocyte`、`cnidocyte`、`devorocyte`、`flagellocyte`、`gamete`、`gangliocyte`、`glueocyte`、`keratinocyte`、`lipocyte`、`luminocyte`、`luxocyte`、`myocyte`、`neurocyte`、`nitrocyte`、`osteocyte`、`phagocyte`、`photocyte`、`proboscyte`、`progenocyte`、`rhizocyte`、`scopocyte`、`secrocyte`、`senseocyte`、`siphonocyte`、`somatocyte`、`stemocyte`、`stereocyte`、`virocyte`、`zygocyte`。

§11.6 已确认这些名称与 Macro 类型枚举 `C` 的 33 个常量高度对应，即这组图标基本就是类型图鉴，而不是泛用素材。不得直接复制进正式项目，后续应根据授权和项目视觉规范重绘或重新制作。

## 7. Android 包与中文资源证据

REA/Apktool 已成功解码两个 APK 的 Manifest 与资源表。

| 字段 | 官方汉化版 | Macro Mod |
|---|---|---|
| applicationId | `com.saterskog.cell_lab` | `com.massivemistakes.hydralab.dev` |
| versionName / versionCode | `103` / `103` | `0.2.0-beta.299` / `485` |
| minSdk / targetSdk | 14 / 21 | 14 / 35 |
| Manifest OpenGL ES 要求 | GLES 2.0 | GLES 2.0 |

Macro Mod 的 Apktool locale 清单包含 `zh`、`zh-rCN`、`zh-rHK`、`zh-rTW`；其 `zh` 字符串表明确包含简体中文内容，例如培养皿设置、细胞类型分类、细胞图鉴、基因组参数和新增细胞机制说明。此前 ZIP 路径搜索没有发现 `values-zh` 目录，是因为语言资源在 APK 的编译资源表中，必须解码 `resources.arsc` 后才能看到，不能据 ZIP 条目名判断没有中文。

用户在 MuMu 实际观察到的 Macro 中文界面提示：关卡相关内容正在重做，完成后会在后续版本重新开放。该运行时观察已由 §5 的 `DisabledLevelsFragment` 静态代码给出对应实现（禁用按钮 + 锁图标 + 提示文案），可确认关卡未开放是版本内容状态，而不是中文资源缺失或安装故障。两条证据相互印证，但仍不把「用户看到的文案」与「反编译得到的资源键」当作同一条证据。

## 8. 资源与渲染线索

官方版已经包含：

- `fragment_genome_editor.xml`、`gene_edit_params.xml`：基因组编辑器相关布局。
- `activity_play.xml`、`activity_main_menu.xml`：主菜单和实验运行界面布局。
- `signal_preset_dialog.xml`、`signal_val_dialog.xml`：信号参数编辑界面。
- `plate*.xml`、`temp_*.xml`、`tool_*.xml`：培养皿、温度和工具按钮资源。
- `res/raw/*_frag.glsl` 与 `*_vert.glsl`：细胞、食物、病毒、神经、纤毛、鞭毛、胶质等多类渲染 shader。

这支持当前项目已经确定的方向：细胞不是静态贴图，而是按细胞器/类型拥有不同的可视化部件和材质行为。Macro 的资源条目显著增多，但由于资源名被 Android 构建工具压缩为短名，必须先通过 Apktool/JADX 还原资源引用关系，才能建立「短资源名 → 语义用途」的可靠映射。

## 9. `.substrate` 初步格式观察

官方根目录 `.substrate` 文件的开头示例：

`AC ED 00 05 77 BF ...`

这是 Java Object Serialization 的流头（`AC ED 00 05`），后续为自定义对象/数据结构。Macro 新增 starter `.substrate` 的开头为：

`50 4B 03 04 ...`

即 ZIP 条目。两者不是同一种外层容器。后续若要把 Cell Lab 实验迁移到 Godot，建议建立独立的离线导入器：

1. 先按魔数区分 Java 序列化 `.substrate` 与 ZIP 容器 `.substrate`。
2. 对 Java 序列化只做白名单字段读取，不执行任意对象反序列化。
3. 对 ZIP 容器枚举内部条目，记录压缩方式、路径和字节摘要。
4. 导入为项目自己的版本化 `ExperimentDef`/场景数据，不在运行时依赖 APK 格式。

## 10. 对当前 Godot 项目的可用结论

1. **实验/关卡数据**：可继续采用数据驱动定义。字段至少应覆盖场景文件、用户初始数量、可放置数量、场上目标数量、工具权限、解锁内容、胜利/最大时间和难度。
2. **细胞类型目录**：Macro 的 guide icon 名称现已被证实对应 33 个真实类型枚举常量（§11.6），可作为候选类型词表；但必须与当前项目的 17 类细胞器和 8 类染色体组型区分，它们不是同一层级的数据。
3. **工具权限**：官方的 `tools` 白名单说明工具可按实验开放，当前 CommandBus + 干预工具体系可以增加 `ExperimentDef.allowed_tools`，但不改变「UI 只发命令、tick 统一执行」的规则。
4. **环境视觉层**：20 张 Macro 环境材质图可作为未来环境场可视化参考；HTML UI 预览阶段仍只做 UI，不把这些资源解释成流体物理证据。
5. **Macro 增量边界（已更新）**：Macro 不只是资源增量。它把细胞类型从官方 18 种向后兼容扩展到 33 种，并重构了 `Gene`/`Cell` 的字段与方法（新增 `AdhesinLink`、条件序列化、能力查询等）。但新增 15 种类型的具体物理/行为实现本轮尚未逐方法验证，不能据此断言机制细节。
6. **架构一致性**：官方的两阶段 tick、阶段锁、固定容量对象池、空间哈希与单写者顺序更新，与本项目已定的「固定 1/60 tick + CommandBus 单写入口」方向一致，可作为阶段划分的参考；不需要照搬其 RuntimeException 阶段锁或 Java 序列化布局。
7. **版权与实现边界**：解析结果用于行为和数据模型参考，不复制 APK 中的代码、shader、图片或文案；项目实现继续采用独立的 Godot 数据结构和重新制作的视觉资产。

## 11. 官方版核心模拟逻辑

分析对象为官方汉化 APK，通过 REA/JADX 0.7.1 静态反编译读取方法体；APK 未执行。类与方法大量混淆，以下只记录方法体直接支持的语义，并显式标注未确认项。方法名后括号内为 DEX 原型；同一名字的多个 overload 以反编译视图中的 overload_index 区分。

### 11.1 世界对象与容量

`CellWorld(boolean, Environment)` 构造一次性预分配所有对象，运行期不随细胞数增长：

- `Cell[d]`、`Food[aa]`、`e[ac]`（残骸/粒子）、`Link[20]` 共享暂存；`d` 与 `aa` 来自 `Environment.r` / `Environment.s`，`ac = (d+3)/4`；`z` 为当前活细胞数，用「末尾元素填补空位」的方式复用对象池。
- `bg` 布尔是「无食物/实验室」模式：为 true 时容量固定 100、`Food[]` 为 null，且跳过食物与部分环境阶段。
- 圆形培养皿半径是 `Environment.k`；碰撞网格边长 `Z = min(206, k/0.03 - 0.1)` 取偶数，气味网格边长 `bd = min(207, 2k/0.36)`。
- 两张固定上限网格：`aV/aW` 每格最多 203 个细胞索引；`ba/bb/bc` 每格最多 404 个气味条目，溢出会写日志断言。
- `ByteBuffer` / `FloatBuffer` / `ShortBuffer` 均按「容量 × 顶点数 × 分量」分配，并配一个 12 float 常量表；按分配模式判断是 OpenGL 渲染缓冲，不是模拟状态。
- 构造末尾 `a(true, 0.0)` 跑一次零步长 tick 做初始化；并有数值稳定性检查：若 `sqrt(1.8e-4) * Environment.g / 0.072 * 0.02 > 1` 就报警 timestep 过大。

### 11.2 两阶段 tick 与阶段锁

- 单次 tick 总入口是 `a(boolean, double)`，实现为 `b(z, d)`（update1）后接 `a(d)`（update2）。
- 字段 `X` 是阶段锁：update1 要求 `X == 0`，进入后 `++`（=1），末尾再 `++`（=2）；update2 要求 `X == 2`，结束置回 0。乱序调用抛出 `Tried to run update1/update2 too early`。
- 内部步长统一为 `dt = 0.02 * d`（`d` 为外部传入的时间/倍速量），两个阶段各自换算；`M` 累计仿真时间；`O += Environment.e * dt` 驱动全局方向 `P = cos(O)`、`Q = sin(O)`，即随时间旋转的洋流/光照方向。
- update1 阶段顺序（非 `bg` 时含食物阶段）：

  `i(dt)` → `k()` → `f(dt)` → `e(dt)` → `j()` → `g()` → `d(dt)` → `h(dt)` → `i()` → `c(z, dt)`（逐细胞调用 `d(i)`）→ `c(dt)` → `h()`

  其中 `f(dt)` = 位置积分/半径增长，`e(dt)` = 分裂与分化，`g()` = 网格重建，`d(i)` = 感知 + 接触物理 + 类型交互。各阶段之间有计时打点。
- update2：`g(dt)`（代谢、遗传、连接物质交换）→ `b(dt)`（4 子步信号积分）。

该顺序与本项目「固定 tick + 单写者 + 阶段化更新」一致，可作为 TickEngine 阶段划分的参照；本项目不需要照搬其异常式阶段锁。

### 11.3 空间索引与气味网格（§12 已修正语义）

`g()` 每 tick 清空 `aW` / `bc` 计数，按细胞中心 `(b, c)` 与半径 `d` 计算所在格，把细胞索引写入其覆盖的最多 4 个格（缓存为 `K/L/M/N`，重复格置 -1）。查询时只处理 `index > i` 的候选，保证每对细胞只算一次。

同一方法还构建 `ba/bb/bc` 网格。**本轮补读 `d(double)` 后修正上一轮表述**：该网格不是化学浓度场，而是「按感知输入类型分桶的局部实体索引表」。`bb` 是输入类型标签，`ba` 是实体索引（正数为 `Food[]` 下标，负数为 `-1-i` 编码的细胞下标）；`d(double)` 把两类食物写为标签 1/2，`g()` 把细胞写为标签 0，并把特定 `SECROCYTE` 改写为 1/2/3/5。真正的 4 通道化学信号是**每细胞私有的 `Cell.U[8]`**，不存在世界坐标上的浓度场；详见 §12。

### 11.4 数据模型（按证据等级）

`Environment` 与 `Gene` 都**没有任何更新/tick 方法**，只有构造、复制和 Parcel/Java 序列化——它们是纯配置数据容器，所有动态计算都在 `CellWorld` 里完成。

| 类 | 已证实字段语义（保留混淆名） | 备注 |
|---|---|---|
| `Cell` | `b,c` 位置；`d` 半径（上限 0.03）；`e,f` 速度；`g,h` 本 tick 累积力；`j` 扭矩累积；`k` 朝向角（±π 归一）；`l` 角速度；`m,n` 相位角与相位角速度（±2π 归一）；`w` 能量/质量（上限 0.36，`<0.072` 判死）；`o` 年龄；`p` 内部浓度（`<0.1` 判死）；`x` 死亡标记；`D` 当前 Gene 槽索引；`I[40]` 基因组槽；`H[]/C` 连接列表与数量；`B` 本 tick 接触数（上限 20）；`A[20]` 接触形变记录；`U[8]` 双缓冲 4 通道信号；`W[4]` 当前输入和；`V[4]` 末步输入；`S` 脂肪储能（上限 1.8）；`T` 端粒剩余分裂次数（-1 为无限）；`G` 突变计数 | `q/F/J/K/Q/R/Z` 等仍存在用途未完全确认的读写 |
| `Gene` | `a[3]` 颜色；`t[11]` 参数调制器（内部类 `Gene.a`，含输入源 `d`、映射模式 `e`、权重/阈值 `a/b/c`）；`u[11]` 整数选项；`v[7]` 浮点参数；`s` 细胞类型；`i/j` 两个子代 Gene 槽索引（分化树）；`b` 分裂阈值；`c` 分裂质量比；`d/e/f` 分裂与子代角度；`g` 连接物质传递率；`h` 连接刚度；`l/m/n/o/q/r` 布尔开关；`p` 启用标记 | 默认构造：`t/u/v` 长度 11/11/7，默认类型 `PHAGOCYTE`，`t[11]` 逐项 new |
| `Environment` | `k` 皿半径；`g` 粘度/阻尼；`e` 方向旋转速率；`c` 突变率；`u` 锁定基因组（禁止多数变异）；`v` 启用寿命上限（age > 240 判死）；`x` 皿壁开关；`z` 环境浓度补给；`n` 影响基础代谢倍率；`i/j/h` 浮力/重力相关；`r/s` 容量；`t[18]` 各类型启用开关 | 其余约 14 个 double 与 4 个 boolean 仅确认存在，语义未逐一还原 |

`Gene` 的静态参数范围表（由 `<clinit>` smali 直接读出）：

- `w[11] = [40, 40, 4, 6, 15, 4, 4, 4, 4, 20, 6]`：11 个整数参数的取值上界。
- `x[11] / y[11]`：11 个调制输出的下界/上界，索引 0 为 `0..1`，1 为 `-3..3`，2/4/5/6 为 `-1..1`，3 为 `-0.5..0.5`，7..10 为 `-20..20`。
- `z[7] / A[7]`：7 个浮点基因参数范围，依次为 `-60..60`、`0..1`、`0..1`、`0..1`、`0..√3`、`0..0.01`、`0.5..2`。
- `B[6] = {-1, 5, 10, 20, 40, 80}`：端粒/分裂次数选项，`-1` 表示无限。

细胞类型枚举 `h` 有 **18** 个常量（ordinal 固定），构造参数中的 double 是用于基础代谢计算的 `u`，扩展构造器另有额外成本参数（`v`，推测为分裂/生成成本）：

| ordinal | 类型 | `u` | 额外参数 |
|---:|---|---:|---|
| 0 | PHAGOCYTE | 0.1 | — |
| 1 | FLAGELLOCYTE | 0.1 | 0.12 |
| 2 | PHOTOCYTE | 0.25 | — |
| 3 | DEVOROCYTE | 0.1 | 0.009 |
| 4 | LIPOCYTE | 0.005 | — |
| 5 | KERATINOCYTE | 0.01 | — |
| 6 | BUOYOCYTE | 0.02 | — |
| 7 | GLUEOCYTE | 0.01 | 0.012 |
| 8 | VIROCYTE | 0.2 | 0.009 |
| 9 | NITROCYTE | 0.02 | 0.0135 |
| 10 | STEREOCYTE | 0.01 | 0.012 |
| 11 | SENSEOCYTE | 0.01 | 0.006 |
| 12 | MYOCYTE | 0.02 | — |
| 13 | NEUROCYTE | 0.02 | — |
| 14 | SECROCYTE | 0.03 | — |
| 15 | STEMOCYTE | 0.02 | — |
| 16 | GAMETE | 0.005 | — |
| 17 | CILIOCYTE | 0.005 | 0.0045 |

### 11.5 核心子系统

**分裂与分化 `e(double)`**。触发条件：能量超过 `Gene.b` 阈值、年龄 `o > 0.5`、上一帧连接数 `P <= Gene.u[9]`、`p > 0.2`、未标记死亡、类型不是 GAMETE、对象池仍有空位。执行时从池末尾取一个 `Cell` 并用 `Cell.a(Cell)` 完整复制母细胞，按 `Gene.d` 分裂角度分开位置，按 `Gene.c` 质量比分配能量并扣除各自目标类型的基础成本，4 通道信号状态、浓度、年龄同样按比分配；母细胞与子代分别切换到 `Gene.i` / `Gene.j` 指定的基因槽——这就是**分化谱系树**。另有 `Gene.e/f` 子代角度、`q/r` 镜像标志、`l` 新建黏附、`m/n` 保留黏附的连接重建、`T` 端粒递减到 0 判死，以及子代能量 ≤ 0 时立即回收。

**代谢与遗传 `g(double)`**。每 tick 用 `Q`（净能量）、`R`（净浓度）、`Z/X/Y`（信号与激活）作暂存，按类型 `switch` 执行专属行为：FLAGELLOCYTE 推进耗能、PHOTOCYTE 按局部光照和面积产能、MYOCYTE 按输出变化耗能、STEMOCYTE 按阈值切到子代基因槽、NITROCYTE 固定浓度、GLUEOCYTE 黏附力、CILIOCYTE 纤毛相位、SECROCYTE 分泌消耗、BUOYOCYTE/GAMETE 相位调整。之后统一扣基础代谢 `u * (1.3857 - 1.2857 * Environment.n) * 400 * (d + 0.0075) * d * dt`，做 NaN/寿命/低浓度死亡检查，并把颜色向 `Gene.a[3]` 插值。连接之间按双方传递率交换能量与浓度（限幅 ±0.1），LIPOCYTE 把超过 0.36 的能量存入 `S` 供后续取用。

**突变系统**同样在 `g(double)` 内：每 15 tick 以 `Environment.c` 决定的概率触发 3 次突变，用 `nextInt(95)` 选择 95 个算子之一，覆盖颜色高斯扰动、三个角度、对数正态缩放、分裂阈值/比例、子代槽索引、多个布尔开关、细胞类型（受 `Environment.t` 白名单约束）、端粒、7 个浮点参数（按 `z/A` 范围）、11 个整数选项、以及 `t[11]` 的输入源/映射模式/权重。另有 1/5 概率走「分化树拓扑变异」：复制、插入或重连 40 个 Gene 槽的 `i/j` 子节点。`Environment.u` 为 true 时锁住大部分变异。

**神经/信号 `b(double)`**。4 子步、每步 `h = dt/4`，把当前输入 `W[4]` 低通积分到 `U`：`U_next = U_prev + (W - 5*U_prev) * h`，再限幅 `[-1, 1]`。`U` 是长度 8 的双缓冲，页偏移在 0 与 4 之间交替——这正好解释了 `Cell.a(int, int)` 的第二个参数：它读取 `U[input + pageOffset]`，所以是**子步页偏移**，不是通道编号。

本轮补读确认页序列为 `(读0,写4) → (读4,写0) → (读0,写4) → (读4,写0)`，**tick 结束时最新值必在页 0**，因此分裂、接触交互和跨阶段参数读取一律用页偏移 0，是自洽的而非巧合。NEUROCYTE 每个子步先清零 `W` 再用 `a(i+7, 读页)` 重算 4 个输出（按 `Gene.u[i+5]` 路由）；其他类型整 tick 共用同一份 `W`，只在第 4 子步把 `W` 存入 `V` 并清零。LIPOCYTE 对连接的非 LIPOCYTE 邻居按 `5*(other.U - self.U)*h` 扩散；首个子步还把代谢暂存 `Q/R/Z` 写回 `w/p/X`，并做 NaN 净能量回收。JADX 对该方法报「Code duplicated」，第 0 子步的扩散分支被折叠成空 `if`，四个子步一致性是按后 3 子步的形态推断。完整公式与时序见 §12。

**感知 `d(int)`**。STEREOCYTE / SENSEOCYTE 从 3×3 气味网格邻域取输入，`Gene.u[3]` 选择输入类型：同类细胞（按 `Gene.v[1..4]` 做颜色匹配与距离衰减）、两类食物、局部光照梯度、自身速度、距皿壁距离；结果乘 `Gene.v[0]` 增益、限幅 ±20 后累加到 `W[Cell.b(2)]` 指定通道。STEREOCYTE 还做方向投影与左右反转，形成方向性感知。

**接触物理 `d(int)`**。用圆-圆相交面积解析式计算重叠并把接触点写入 `A[]`（供膜压平渲染），按 `Cell.a(6)` 的刚度做弹性排斥；已建立的连接按弹簧-阻尼模型施加力与扭矩（MYOCYTE 会额外收缩），连接被拉断时双向解除；皿壁是半径 `Environment.k` 的圆形边界，按重叠面积反弹，GLUEOCYTE 可黏到壁上；最后叠加粘性阻尼（`Environment.g`）、角阻尼，以及 BUOYOCYTE 的浮力/重力项（`Environment.i/j/h`）。

**类型交互 `d(int)`**。GAMETE 双方成熟且基因槽互为子代时产生吸引（受精）；VIROCYTE 接触时把自身及分化树下游共 7 个 Gene 槽复制进宿主；GLUEOCYTE 建立黏附连接；DEVOROCYTE 按 `0.72*dt` 转移对方能量/浓度/信号；SECROCYTE 按 `u[4]` 通道执行刺激信号、加速生长、切断连接、以及 4 通道信号增减（7..10 降低、11..14 提高）；KERATINOCYTE 对吞噬/病毒/分泌提供屏蔽；CILIOCYTE 接触产生推力并登记纤毛事件。

**死亡回收 `a(int, boolean)`**。先解除该细胞所有连接的双向引用，并把末尾细胞的连接索引重映射到被删位置；可选把 `0.9 * w` 转成食物（LIPOCYTE 额外带 0.5 参数）、生成残骸粒子；最后 `x[i].a(x[z-1])` 复制末尾状态、`z--`、死亡计数 `R++`。这确认上一轮记录的 `Cell.a(Cell)` 是**对象池交换删除的复制路径**，不是分裂算法。

### 11.6 Macro 对照

- Macro 的细胞类型枚举是 `com.saterskog.cell_lab_enzymeglv.C`（官方是 `h`），`<clinit>` 明确创建 `0x21 = 33` 个常量。前 18 个的名称、ordinal、`u` 值与官方逐一一致，说明是**向后兼容扩展**而非重构。
- 新增 15 种（ordinal 18..32）：`OSTEOCYTE`(0.001)、`ADIPOCYTE`(0.005)、`AXON`(0.01)、`GANGLIOCYTE`(0.02)、`SCOPOCYTE`(0.01/0.018)、`RHIZOCYTE`(0.01/0.03)、`PROGENOCYTE`(0.02)、`ZYGOCYTE`(0.001)、`CATALOCYTE`(0.015)、`LUXOCYTE`(0.02/0)、`LUMINOCYTE`(0.02)、`CNIDOCYTE`(0.03)、`SOMATOCYTE`(0.0505)、`SIPHONOCYTE`(0.02)、`PROBOSCYTE`(0.1)。这组名称与 §6.4 的 guide-icons 名称高度对应，其中 `Osteocyte` 正是 §6.2 关卡 9 新增的解锁项。
- `Gene` / `Cell` 类名在 Macro 中保留，但混淆方案完全不同（大量 `fNNNx` 字段名）。`Cell` 仍持 `Gene[]`，并新增语义类名 `AdhesinLink[]`、多组 `boolean[]` / `float[]`、`long` 与 `byte` 字段；`Gene` 方法数由官方 10 个增至 22 个，新增 `(Gene, float, float, float)` 构造、能力查询 `f(int)/g(int)/n()`、按类型计算 `h(C)`、`k(C,int,int)`，以及带 boolean 参数的 `o(ObjectOutputStream, boolean)` 条件序列化。
- Macro 的 `K8` 不是枚举，而是由 3 组 `boolean[]` + `int[]` 构成的位标志/模式集合类；`C` 枚举自身提供 `a()/b()/c()/d()/g(): boolean` 与 `e(): float` 能力查询。
- Macro 的世界类不叫 `CellWorld`，而是 `SimulationWorld`（`search_android_classes` 查 "World" 唯一命中）；全包内没有名为 `Signal` 的类。其方法名改为 `A0..Z2 / a0..z2` 体系，字段大量为 `fNNNx` 形式。
- **信号通道扩展（本轮新增证据）**：Macro `Cell.<init>()` 分配 `new float[J8.d.f926a * 2]` 作双缓冲，另有多组 `float[101]` / `boolean[101]` 数组。`J8.<clinit>` 以 `new H8(0x65, 0)` 初始化 `J8.d`，`H8(int,int)` 把首参赋给 `f926a` 且报错文案为 `channelCount must be positive` ⇒ **通道数 = 101**，双缓冲长度 202。即 Macro 保留了官方的双缓冲结构，但把 4 通道推广为可配置的 101 通道；这直接支持把独立子系统的通道数做成常量而非硬编码。
- 结论：Macro 确实扩展了类型系统、基因组模型与信号通道规模，不只是资源增量。但本轮未逐方法验证新增类型的物理行为、突变规则、101 通道的积分与路由是否同构，不能据此写出它们的机制细节。

### 11.7 对 Godot 的映射建议（本轮不改代码）

1. **阶段化 tick**：可直接借鉴 §11.2 的阶段顺序（输入/环境 → 位置积分 → 分裂 → 网格重建 → 接触/交互 → 代谢遗传 → 信号积分），但项目仍用 1/60 固定 tick 与 CommandBus 单写入口，不引入异常式阶段锁。
2. **信号模型要分开（用户已确认采纳为独立子系统）**：Cell Lab 的 4 通道双缓冲化学信号是**每细胞私有状态**，与项目现有 8→4→6 稠密前馈网络、以及 5 类 global `EnvironmentField` 都是不同层次的东西。借鉴时实现为独立 `ChemicalSignalSystem`，不并入神经网络、不占用 ping-pong 场纹理。完整规格与接口草案见 §12。
3. **确定性**：固定容量对象池、空间哈希每格上限、以及「只处理 index > i」的配对顺序，与项目静态分区/确定性遍历思路一致；项目可用动态数组，但必须保证遍历顺序稳定。
4. **基因组复杂度**：Cell Lab 是「每细胞 40 个 Gene 槽 + 分化树 i/j + 95 个突变算子 + 端粒」，比项目当前 GNP1 单基因组复杂得多。建议先落地 18 种基础类型的行为基线，再把 Macro 的 15 种作为可选扩展包。
5. **需先修订玩法规格的机制**：端粒、突变、黏附连接、受精、病毒基因注入、分泌通道属于 Cell Lab 的核心玩法差异。若采纳，必须先修订上游 v1.0 玩法规格并同步设计文档，不能直接在 tick 里加参数。
6. **可直接作为行为规格参考**：圆形皿边界反弹、接触形变点（膜压平）、储能细胞、按类型分派的代谢与感知；但全部需重新实现，不复制源码、shader 或资源。

### 11.8 证据边界与未确认项

- update1 中 `i(dt)`（食物生成）、`k()`（自动补细胞）、`j()`（死亡回收）、`d(dt)`（食物衰减/摄食/气味网格写入）本轮已读，结论并入 §12.6；`h(dt)`、`i()`、`c(dt)`、`h()` 仍未读取，统计与渲染准备阶段语义待补。
- `ba/bb/bc` 网格语义已按 §12.1 纠正为「按感知输入类型分桶的实体索引表」，不是化学浓度场；上一轮表述作废。
- `Environment` 约 14 个 double 与 4 个 boolean 字段语义未逐一还原；`Cell` 的 `q/F/J/K/Q` 等字段用途仅部分确认；渲染缓冲用途是按分配模式推定，未追踪绘制调用。
- 95 个突变算子中若干编号区间（如 13、15..17、21、26..54 的部分 case）本轮未完整展开语义。
- 全部结论是**静态反编译证据**，APK 未执行，不能证明设备运行时行为；反射、动态分派及未覆盖调用点不作推断。
- Macro 33 种类型的具体行为、101 通道（`J8.d.f926a = 101`）的积分与路由，以及官方 `CellWorld` 与 Macro `SimulationWorld` 更新链是否结构相同，留待后续逐方法比对。

## 12. 独立子系统：4 通道化学信号（行为规格 + Godot 接口设计）

用户已确认：**把 Cell Lab 的通道化学信号作为独立子系统借鉴**，不并入现有 8→4→6 神经网络。本节是本轮深度反编译的成果，作为后续实现的规格稿；**Godot 运行时代码零改动**。

### 12.1 三句话结论与一处纠正

1. 信号是**每细胞私有的 4 通道状态**（`Cell.U[8]` 双缓冲），不是世界坐标上的浓度场，也没有扩散 PDE。
2. 它是一条**行为参数总线**：`Cell.a(int,int)` 把信号（或能量/年龄/浓度/连接数）经线性或阈值映射成 11 个行为参数；运动、代谢、分化、神经输出都读这条总线。
3. 传播只靠**接触、连接、分裂继承**三种离散事件，加上感知写入输入和；因此天然确定性，与 GPU 场后端无关。

**纠正 §11.3 上一轮的表述**：`ba/bb/bc` 网格不是「按格分桶的局部化学通道」，而是按**感知输入类型**分桶的实体索引表。本轮 `d(double)` 证明食物被写入同一张表并标为 1/2。

### 12.2 数据模型（官方，保留混淆名）

| 位置 | 字段 | 语义 |
|---|---|---|
| `Cell` | `U[8]` | 4 通道 × 2 页双缓冲，值域 `[-1,1]`；构造器 `new float[8]` |
| `Cell` | `W[4]` / `V[4]` | 本 tick 输入累加和 / 最后一个子步的输入快照 |
| `Cell` | `X` / `Y` / `Z` | 刺激量（每 tick 衰减 5%）/ 生长量（对 X 低通）/ X 的下一值暂存 |
| `Cell` | `p` | 内部浓度，分泌的底物；`<0.1` 判死，`>1.0` 限幅 |
| `Cell` | `J[4]` | 颜色插值缓存（感知时用于同类匹配，只取前 3 个分量） |
| `Gene` | `u[11]` | 整数选项，上界 `w[11]=[40,40,4,6,15,4,4,4,4,20,6]` |
| `Gene` | `v[7]` | 浮点参数，范围 `z/A[7]`；`v[0]∈[-60,60]` 是感知增益，`v[1..4]` 是同类颜色/半径，`v[6]` 与分裂成本相关 |
| `Gene` | `t[11]` | 参数调制器数组（内部类 `Gene.a`：`a,b,c` 浮点；`d,e` short） |

`Cell.a(int)` 返回 `Gene.v[i]`；`Cell.b(int)` 返回 `Gene.u[i]`；`Cell.c()` 保证 40 个 Gene 槽中至少有一个启用且只保留最靠前的启用项。

### 12.3 核心积分公式（`CellWorld.b(double)`，update2 末尾）

外部 `d` 在 `a(double)` 内换算为 `dt = 0.02*d`；`b(dt)` 取 `h = dt/4`，执行 4 个子步 `s = 0..3`：

- 页：`read = (s % 2) * 4`，`write = 4 - read`，即 `(读0,写4) → (读4,写0) → (读0,写4) → (读4,写0)`。**tick 结束最新值必在页 0**。
- 积分：`U[write+c] = clamp(U[read+c] + (W[c] - 5*U[read+c]) * h, -1, 1)`，`c=0..3`。这是 `dU/dt = W - 5U` 的显式欧拉，稳态 `U = W/5`、时间常数 `τ = 1/5 = 0.2`（仿真时间单位）。
- 输入语义分两类：
  - **非 NEUROCYTE**：`W` 在 update1 的感知阶段累加，整 tick 四个子步共用；`s=3` 时 `V[c] = W[c]` 并 `W[c] = 0`。
  - **NEUROCYTE**：每个子步先把 `W` 清零，再算 `fA = clamp(cell.a(7+i, read), -20, 20)` 并 `W[u[5+i]] += fA`（`i=0..3`），即 4 个输出按 `u[5..8]` 路由到通道。
- **LIPOCYTE 连接扩散**：对每个连接且类型非 LIPOCYTE 的邻居，追加 `U[write+c] += 5 * (other.U[read+c] - self.U[read+c]) * h`。
- `s=0` 还把代谢暂存写回 `w = Q`、`p = R`、`X = Z`，并对 `Q` 为 NaN 的细胞执行回收。

JADX 对 `b(double)` 报多处 `Code duplicated`，第 0 子步的扩散分支被折叠成空 `if`；「四个子步都做扩散」是按后 3 子步形态的推断，不是直接读到的事实。

### 12.4 行为参数总线（`Cell.a(int i, int page)`）

`m = Gene.t[i]`，`i` 是调制器索引，`page` 是页偏移：

- `m.e == 0`（常量）→ `f = m.b`；否则先取输入 `x`：
  - `m.d ∈ 0..3` → `x = U[m.d + page]`（**这就是 4 通道信号**）
  - `m.d == 4` → `x = w / 0.36`（能量比）
  - `m.d == 5` → `x = o / 240`（年龄归一）
  - `m.d == 6` → `x = p`（内部浓度）
  - `m.d == 7` → `x = C / 20`（连接数归一）
- 映射：`m.e == 1` → `f = x*m.a + m.b`（线性）；否则 `f = (x < m.c) ? m.a : m.b`（阈值）。
- 最后 `f = clamp(f,-1,1)`，输出 `((f+1)*(Gene.y[i]-Gene.x[i])*0.5)+Gene.x[i]`，即把归一化值映到该调制器的参数区间。

11 个调制器索引的消费点（按调用点推定，输出范围来自 §11.4 的 `x/y[11]`）：

| 索引 | 主要消费点 | 输出范围 |
|---:|---|---|
| 0 | FLAGELLOCYTE 推进力（力 = `a(0,0)` × 朝向向量）与对应耗能 | `0..1` |
| 1 | BUOYOCYTE 浮力项 | `-3..3` |
| 2 / 3 / 4 | MYOCYTE 收缩与 CILIOCYTE 双纤毛相位（含 `y` 左右反转） | `-1..1` / `-0.5..0.5` / `-1..1` |
| 5 / 6 | STEMOCYTE 分化阈值（>0.5 切到 `u[0]` / `u[1]` 指定的 Gene 槽） | `-1..1` |
| 7..10 | NEUROCYTE 的 4 个输出（每子步重算） | `-20..20` |

### 12.5 输入、生产与传播链路

**感知（update1，`d(int)`，仅 STEREOCYTE / SENSEOCYTE）**。以 `u[3]` 选输入类型，扫描 3×3 气味网格邻域，只处理 `bb == u[3]` 的条目：

| `u[3]` | 输入 | 说明 |
|---:|---|---|
| 0 | 同类细胞 | 按 `Gene.v[1..4]` 做颜色距离匹配与半径筛选 |
| 1 / 2 | 两类食物 | `Food.f <= 0` / `> 0`，由 `d(double)` 标为标签 1/2 |
| 3 | 局部光照 | `c(x,y)` 标量或 `d()/e()` 方向导数 |
| 4 | 自身速度 | 模长 ×3 或侧向分量 ×3 |
| 5 | 距皿壁距离 | `clamp(1 - (k - r)/0.27, 0, 1)` |

距离衰减走 `com.saterskog.b.b`：索引 `clamp(round(x/0.01), 0, 499)`（表长 500），调用参数 `x = dist/0.09`；`a()` 用于标量、`b()` 用于方向性（乘侧向投影/距离），`a(0)=4.721`、`b(0)=99.974`，远端均近似 `0.494/x`。STEREOCYTE 额外做方向投影并按 `cell.y` 左右反转。输出：`W[u[2]] += clamp(v[0] * 感知和, -20, 20)`。`u[2]` 上界 4 ⇒ **感知输出通道 0..3**。

**分泌与刺激（`d(int)` 接触分支 + `g(double)` 代谢分支）**。仅 `SECROCYTE` 且 `p >= 0.2` 生效，`u[4]`（上界 15）决定模式：

| `u[4]` | 效果 |
|---:|---|
| 0 / 4 / 5 / 6 | 不直接改目标，而是在气味网格把该细胞标为 1 / 2 / 3 / 5（负编码索引 `-1-i`），供感知 |
| 1 | 目标 `X += 60 * dt`（刺激） |
| 2 | 目标 `Y += 0.1 * dt`（加速生长）；并使接触到的食物 `f` 递减 |
| 3 | 切断目标连接（含皿壁黏附） |
| 7..10 | 目标 `U[c] -= 60 * dt`，`c = u[4]-7` |
| 11..14 | 目标 `U[c] += 60 * dt`，`c = u[4]-11` |

后两类对 LIPOCYTE 无效，且直接写 `U[0..3]`（页 0，与 §12.3 的 tick 末状态一致）。KERATINOCYTE 对吞噬/病毒/分泌提供屏蔽。

**经济模型**：`g(double)` 里 `R`（下一 tick 浓度）在 `>0.25` 时按 `0.45*dt` 消耗、下限 0.25；环境按 `R += 1.2*(Environment.z - p)*dt` 补给；浓度足够时累加分泌相位 `r`。`X` 每 tick 衰减 5%（`Z = X - 0.05*X*dt`），`Y += (min(X,10)-Y)*0.05*dt`，`Y > 1` 判死。

**其他传播**：`g(double)` 中连接双方按 `3*dt` 交换 `X`；`DEVOROCYTE` 接触时按 `0.72*dt` 转移能量/浓度/`X`；分裂时 `e(double)` 只分配页 0：`U_mother[c] = Gene.c*U[c] + 1e-4`、`U_child[c] = (1-Gene.c)*U[c] + 1e-4`，`X/Y` 同比例分配、`p` 各半、年龄归零。

### 12.6 单 tick 读写时序

| 阶段 | 对信号状态的作用 |
|---|---|
| update1 `i(dt)` | 生成食物（泊松数量、圆内拒绝采样 + 高斯散布、簇大小 `1+Environment.p`） |
| `k()` | 自动补细胞（不写信号） |
| `f(dt)` | 位置/半径/朝向积分；`Y>1` 判死 |
| `e(dt)` | **写** `U[0..3]`、`X`、`Y`、`p`（分裂继承）；末尾 FLAGELLOCYTE 读 `a(0,0)` 施力 |
| `j()` | 回收死亡细胞（交换删除） |
| `g()` | 清空并重建两张网格；细胞写标签 0，特定 SECROCYTE 改标 1/2/3/5 |
| `d(dt)` | 食物衰减/摄食/运动；把存活食物写入气味网格，标 1/2 |
| `c(z,dt) → d(i)` | **写** `W`（感知）；**写** 目标 `U[0..3]`/`X`/`Y`（接触交互） |
| update2 `g(dt)` | 代谢、突变；`X` 衰减、`Y` 低通、连接交换 `X` |
| `b(dt)` | **唯一积分点**：4 子步更新 `U`，末步写 `V` 并清空 `W` |

### 12.7 Godot 独立子系统接口设计（规格草案，尚未实现）

**边界**：新建 `scripts/core/signal/ChemicalSignalSystem.gd`，`extends RefCounted`、**不加 `class_name`**（调用方 `const ... = preload(...)`，遵循项目既有约定）；由 `TickCore` 持有，不作为 Autoload，不在编译期引用任何 Autoload 全局名。它既不读写 `EnvironmentField` 的 2 张 ping-pong 纹理，也不读写 `NeuralNetwork` 的权重/输出。

**常量参数化**：`channel_count := 4`（官方基线；Macro 为 101，故必须可配置）、`substeps := 4`、`decay := 5.0`、`limit := 1.0`、`step_ratio := 0.02`。

**状态**：每个生物一份 `SignalState`（`extends RefCounted`）：`PackedFloat32Array` 长度 `2*channel_count`、`input_sum`、`last_input`。索引统一 `page*channel_count + channel`；读页固定 0 供跨阶段调用，写页在 `integrate()` 内交替。

**最小接口**（仅签名草案，不是已落地代码）：

| 方法 | 职责 | 调用时机 |
|---|---|---|
| `configure(channel_count, decay, substeps)` | 设定常量并校验 `channel_count > 0` | 世界初始化 |
| `accumulate(org_id, channel, amount)` | **唯一输入写入口**，累加到 `input_sum` | 感知阶段、分泌命令、接触交互 |
| `add_to_current(org_id, channel, delta)` | 直接改页 0（对应 SECROCYTE 的 `±60*dt`） | 接触交互 |
| `diffuse_along_links(pairs, dt)` | 连接邻居按 `decay*(other-self)*h` 扩散 | `integrate()` 内部子步 |
| `integrate(dt)` | 4 子步低通 + clamp + 页切换；末步存 `last_input` 并清零 | update2 末尾 |
| `sample(org_id, channel)` | 读页 0，供 `SignalModulator` 使用 | 任意需要行为参数的阶段 |
| `inherit_on_split(parent_id, child_id, ratio)` | 按质量比分配 + 本底 | 分裂命令 |
| `purge_on_death(org_id)` | 清理状态 | 回收阶段 |

**写者约束**：UI / Agent / 回放一律只 `enqueue_command`，真实写入发生在 `execute_tick_commands()` 或 `main_tick` 的对应阶段；`integrate()` 是唯一改写 `U` 双缓冲的地方，保证单写者与确定性遍历顺序。

**与现有模型解耦**：8→4→6 网络的传感输入仍只读 5 类环境场 + 同类/异类邻居 + 能量比；化学信号通过独立的 `SignalModulator`（对应 `Gene.t`）**旁路**影响行为参数，不进网络权重、不改 GNP1 二进制布局。若将来要合并两套模型，必须单独修订上游 v1.0 并做版本化追加。

**存档**：`signal_state` 需在存档 schema（阶段 4 冻结）前以版本化字段追加，字段包含 `channel_count`、双缓冲数组、输入和、末步输入；否则读档后信号轨迹会与重放不一致。

**验证清单**（headless 工具脚本，console exe + `--script`）：常数输入下稳态 `U = W/5`；4 子步页交替与末态落在页 0；分裂守恒（母+子 = 原值 + 2×本底）；接触增减 `±60*dt`；LIPOCYTE 扩散守恒；CPU/GPU 场后端切换后信号轨迹不变；同初态两次重放逐位一致；`channel_count` 改为 101 时不越界。

### 12.8 玩法规格影响与证据边界

- **需先修订上游 v1.0 才能采纳**：新增「化学信号通道」概念、分泌/感知/神经/脂肪细胞的分工、连接扩散、分裂继承。项目现有词条里已有「信号腺」「化学感受器」，可作为 SECROCYTE / SENSEOCYTE 的对应项，但 17 类细胞器与 8 类染色体组型的层级关系需重新对齐。
- **不随本子系统引入**：40 Gene 槽分化树、95 个突变算子、端粒、受精、病毒基因注入、黏附连接（除连接扩散所需的抽象外）。这些若采纳需另行立项。
- **证据边界**：全部为 REA/JADX 0.7.1 静态反编译，APK 未执行；`b(double)` 存在反编译器重复块折叠；`a(int,int)` 的调制器索引语义是按调用点推定，未逐个追溯到 UI 词条；Macro 的 101 通道只确认了常量与数组分配，其积分/路由是否同构、新增 15 种类型的信号行为均未逐方法验证；`com.saterskog.b.b` 两张衰减表只读取了端点与索引规则，未逐项拟合解析式。Godot 侧本轮零改动。

## 13. 建议的下一步解析顺序

1. 补读官方 update1 尚未逐一验证的 `h(dt)`、`i()`、`c(dt)`、`h()`，把统计/渲染准备阶段语义补进 §11.5；`i(dt)`、`k()`、`j()`、`d(dt)` 本轮已读，结论已并入 §12.6。
2. 逐方法比对 Macro `SimulationWorld` 的 101 通道积分与路由，确认它是否沿用官方 4 子步低通与页 0 收尾；再验证新增 15 种类型的信号相关分支。
3. 追踪 `Environment` 各 double 字段的写入点，建立有证据等级的字段语义表；解析 `Gene.a(Gene)` / 序列化方法确认存档字段顺序。
4. 若决定落地 §12.7：先修订上游 v1.0 玩法规格与 `docs/Godot项目技术设计文档.md`，再实现 `ChemicalSignalSystem` + headless 验证脚本；规格明确前不改运行时代码。
5. 若后续需要实验数据导入，再分别解析官方 Java 序列化 `.substrate` 与 Macro starter ZIP `.substrate`，输出项目自有版本化格式。
6. **多细胞个体与细胞协作（2026-11-15 已开专题）**：官方包内不存在 `Organism` / `Group` / `Colony` 类，唯一的相关实体是 `Link`；「个体」是连接图的连通分量，属涌现式。配套文档 `analysis/CellLab_多细胞协作_设计规格.md` 已给出六条协作机制的反编译证据、与本项目 v2.1 显式个体架构的差异，以及分阶段 Godot 落地规格。后续补读应聚焦 `Link.b`（先天/后天黏附）、`Gene.m/n` 分裂后连接重分配与 `KERATINOCYTE` 簇级屏蔽在 Macro 中的对应实现。

## 14. 证据文件

- 原始 APK：用户 Downloads 目录中的两个 APK。
- 抽取目录：`analysis/cell_lab_apk_extract/`
- 资源差异：`analysis/cell_lab_apk_extract/asset_diff.txt`
- 本报告：`analysis/CellLab_APK_解析报告.md`
- 多细胞协作专题：`analysis/CellLab_多细胞协作_设计规格.md`
