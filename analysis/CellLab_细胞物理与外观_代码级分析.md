# Cell Lab 细胞物理与外观：代码级分析

> 分析日期：2026-11-17
> 对象：官方汉化版 `cell-lab-zh.apk`（SHA256 `5f29fdf1…88986c`），JADX headless 0.7.1 静态反编译，APK 未执行
> 方法：REA/JADX `inspect_android_class` / `inspect_android_method` 逐方法读方法体 + 直接读取 `res/raw/*.glsl`
> 证据等级标注：**[证实]** = 方法体直接支持；**[推断]** = 多方法一致但无单一断言；**[未确认]** = 仍需更多证据
> 版权边界：仅记录机制与公式用于学习，不复制源码、shader、图片或文案到工程

## 0. 用户提出的四个现象

1. 细胞变形碰撞精度高，互相挤压的细胞膜间精密贴合；研究代码，能否还原 Cell Lab 的细胞外观。
2. 细胞饥饿会逐渐变小。
3. 细胞间的推动：变形到一定程度后才推动；是弹力产生作用力，还是直接推动？
4. 分裂从细胞核（圆心）位置生成两个子细胞（因碰撞呈两个半圆形，后因弹性碰撞分离）；分裂本身是否产生作用力，还是仅靠弹性恢复原圆形的相互推动？

结论先行：**四个现象的观察全部成立**，但成因与直觉有出入——贴合来自"物理与渲染共享同一组解析相交弦端点"，推动是"力 ∝ 相交面积"的软弹力（非直接位移），分裂本身**施加零力**，分离来自下一 tick 的接触排斥力。

---

## 1. 现象一：外观与精密贴合

### 1.1 证据链

| 环节 | 方法 / 文件 | 证据 ID | 作用 |
|---|---|---|---|
| 接触弦生成 | `CellWorld.d(int)` overload 2（接触物理） | `ev_0c1930e85e…` | 计算圆-圆相交面积与弦端点，写入 `cell.A[]` |
| 皿壁弦生成 | 同上（末尾皿壁分支） | 同上 | 皿壁相交弦写入 `A[]`，`g = -1` 标记 |
| 几何构建 | `CellWorld.a(float,float,float,float)` overload 7 | `ev_2214552d56c2f…` | 把 `A[]` 端点变成膜多边形顶点，弧段解析插值 |
| 顶点着色器 | `res/raw/cell_vert.glsl` | 本地文件 | 相对中心偏移 ×50、半径入 `col.a`、中心入 `vCenter` |
| 片元着色器 | `res/raw/cell_frag.glsl` | 本地文件 | `discard` 做片元级精确圆裁剪，接触区着暗色 |
| 绘制调用 | `CellWorld.a(float[])` overload 11 | `ev_3d3c8ccb…` | 每细胞 6 顶点 quad 批量绘制（`glDrawArrays(4,0,6)`） |

### 1.2 [证实] 精密贴合的几何根源

`d(int)` 中当 `this.U`（渲染标志）为真且两圆相交时：

- `d50` = 圆-圆相交面积的 Heron 解析式：
  `((-s+r1-r2)(-s-r1+r2)(-s+r1+r2)(s+r1+r2)) / s²`，其中 `s = 中心距`、`r1/r2 = 两半径`。
- `d51 = (s² − r2² + r1²) / (2s)`：中心线上到弦中点的距离；`d52/d53` 为中心连线单位向量；`d54/d55 = d51·(d52,d53)` 为弦中点。
- `d56 = sqrt(d50) / (2s)`：半弦修正量。
- 写入 `u = cell.A[cell.B]`：
  - `u.a = dy·d56 + d54`，`u.b = d55 − dx·d56` —— 弦端点 1（相对本细胞中心）
  - `u.c = d54 − dy·d56`，`u.d = d55 + dx·d56` —— 弦端点 2
  - `u.g = 对方索引`
- 同时写入对方 `cell6.A[]`，端点做镜像平移：`uVar2.a = u.c + b_self − b_other`，`uVar2.c = u.a + b_self − b_other`（`b/c` 字段同理）。

**要点：两个细胞在各自 `A[]` 里存的是同一条公共弦的两个端点（世界坐标完全一致）。** 这就是"膜间精密贴合"的根本原因——不是弹性形变碰巧对齐，而是物理阶段就把共享弦算好并分发给双方。

### 1.3 [证实] 从弦端点到可见膜

`a(float,float,float,float)` overload 7（`com.saterskog.b.a.b()` 报 "Tried to construct primitives for not yet calculated geometry"，确认是几何构建阶段）：

- `cell.B == 0`（无接触）：输出 4 顶点 quad，局部坐标 `±r`（`r = cell.d`），6 个索引 → 由 shader 裁成整圆。
- `cell.B > 1`（有接触）：
  1. 对 `A[]` 端点两两求交（解 d14–d17 的线性交点），剔除被完全遮挡的弦（d26 判据）；
  2. `Arrays.sort(cell.A, 0, cell.B)` 按角度排序；
  3. 以 `A[]` 端点作为膜多边形顶点写入 `ad[]`（相对中心偏移）；
  4. 相邻端点之间的**圆弧用解析圆插值**（`d31 = r²/(w0·d29 − v0·d30)` 等，插 1~3 个点），而不是简单连线；
  5. `af[]` = 细胞中心，`ag[]` = 类型/相位/颜色参数，`ae[]` = 类型与接触标记 → 对应 shader 的 `vCenter / vColor / vTPosition`。

`cell_frag.glsl`：`if (ds > col.a²) discard`，`ds = dot(p,p)`，`p = vPosition.xy × 50`，`col.a = 半径 × 50`。即**圆边界在片元级解析裁剪**，不是多边形近似；`ds > NR² && srr < 1` 区域画亮色（内部），其余画暗色（膜缘 + 接触弦区），`NR = 0.005×50 = 0.25` 为核半径。

### 1.4 能否还原外观：[证实] 可还原，且关键不在"弹性膜"

Cell Lab 的细胞外观 = **CPU 构建的"共享相交弦多边形 + 解析圆弧插值" + GPU 片元级解析圆裁剪**，每细胞仅 4~N 顶点。它不是贴图，也不是高分辨率弹性膜；`assets/guide-icons/` 只是图鉴图标（与既有结论一致）。

对当前工程（v0.8.7 的 `CellMembrane.gd` = 12 控制点 Catmull-Rom + 3 谐波 + 法线方向压平）的映射建议：

1. **保留** Catmull-Rom 呼吸/速度拉伸作为"生命感"，它对应 Cell Lab 的相位 `m/n` 与速度项，是外观加分项。
2. **替换**接触形变的算法核心：在物理/派生阶段对每个接触计算**公共弦两端点**（Heron 相交面积式），弦端点由双方共享；膜多边形直接采用这些端点，弧段用圆解析插值。当前"按法线投影压平"是单法线近似，两细胞各自压平、端点不共享，这正是放大后精度不如 Cell Lab 的原因。
3. **可加**片元级圆裁剪（Godot CanvasItem shader 用 SDF/`discard`）消除残余多边形棱角；`;col.a` 携带半径、`vCenter` 携带中心的做法可移植。
4. 皿壁接触用同一套路（相交弦 + `g=-1` 标记），可统一处理贴壁压平。

约束：只借鉴几何方法，用 Godot 原生节点/资源与自写 shader 重新实现，不复制 APK 的 shader 或资源（符合技术基线）。

---

## 2. 现象二：饥饿变小 —— [证实] 成立，机制是"半径向能量的平方根松弛"

`CellWorld.f(double)` overload 0（位置/半径积分）：

```text
if (cell.o > 5·d):
    cell.d += ((cell.w / 400) / cell.d − cell.d) · 0.5 · 10 · d
    if cell.d > 0.03: cell.d = 0.03
```

- 稳态条件 `((w/400)/d − d) = 0` ⇒ `d² = w/400` ⇒ **目标半径 `d_target = sqrt(w) / 20`**。
- 半径以系数 `0.5·10 = 5` 的一阶低通向目标趋近（时间常数约 0.2 时间单位），所以是**平滑收缩**而非突变。
- `cell.w < 0.072` 或 `cell.d < Cell.a` 或 `cell.Y > 1` 判死；上限 `d = 0.03`。

`CellWorld.g(double)`（代谢）：每 tick 扣基础代谢
`Q −= u · (1.3857 − 1.2857·n) · 400 · (d + 0.0075) · d · dt`，持续消耗 `w`；`w` 下降 ⇒ `d_target` 下降 ⇒ 半径收缩。

**结论**：用户观察正确。半径是能量的函数，饥饿 = 代谢耗尽 `w` = 目标半径下降；细胞并非被"啃掉"，而是半径低通跟踪能量。

---

## 3. 现象三：推动是弹力还是直接推动 —— [证实] 是软弹力，力 ∝ 相交面积

`CellWorld.d(int)`（接触物理）：

```text
dA = (d50 · 500) / (0.5/a(6)_self + 0.5/a(6)_other) / s
cell.g += (b − b_other) · dA ;  cell.h += (c − c_other) · dA
cell6.g −= ... ; cell6.h −= ...
```

- `d50` = 圆-圆相交面积（同一 Heron 式）；`s` = 中心距；`a(6)` = 基因给出的刚度，双方取调和平均。
- **力写入 `cell.g/h`（本 tick 力累加器），不是直接改位置**。皿壁同理：`dA2 = (500/s)·dSqrt8²·2·a(6)`，`cell.g −= b·dA2`。
- GAMETE 互为子代槽时 `dA ×= −0.6`（转吸引），否则 `×0`。

`CellWorld.c(double)` overload 1（速度积分）：

```text
d6 = (cell.g / w) · dt ;  d7 = (cell.h / w) · dt    // 力 / 质量 = 加速度
cell.e += d6 ; cell.f += d7                        // 加速度 → 速度
... 粘性/滚动摩擦限速（d16..d19, 环境 e.m）...
cell.g = cell.e ; cell.h = cell.f                  // 速度暂存
```

`CellWorld.f(double)`：`cell.b += cell.e·dt`，`cell.c += cell.f·dt`（速度 → 位置）。

**关键解释（对应"变形到一定程度后才推动"）**：`dA ∝ 相交面积 d50`。相交面积随重叠深度非线性增长（Heron 式在浅重叠时近 3/2 次幂），因此**浅接触力很小、深重叠力迅速增大**——宏观上就是"先贴合变形，压到一定程度才明显推开"。这是**弹力**（软接触排斥），不是直接位置修正；也不是刚体冲量。

---

## 4. 现象四：分裂 —— [证实] 从圆心生成重叠子细胞，分裂施加零力，靠下一 tick 弹力分离

`CellWorld.e(double)` overload 1（分裂与分化）：

- 触发：`w > Gene.b`、年龄 `o > 0.5`、上一帧连接数 `P ≤ u[9]`、`p > 0.2`、未死、非 GAMETE、对象池有空位（LIPOCYTE 用 `w + S` 判定）。
- `cell2 = x[z−1]`（池末尾对象），`cell2.a(cell)` **完整复制母细胞状态**。
- 分裂轴 `d7 = 母朝向 k + Gene.d`（`y` 为镜像标志）。
- **位置**：`d8 = cell.d · 0.05 · 2 = 0.1·r`；母 `b −= cos(d7)·d8`、子 `b += cos(d7)·d8`（`c` 同理），两者中心相距 `0.2·r`。此时两子细胞**仍保留母细胞半径**（半径只在 `f()` 里按新 `w` 缓慢松弛），所以是一对该位置高度重叠的大圆。
- **速度增量**：
  ```text
  cell.e  −= 0.0·dCos ;  cell.f  −= 0.0·dSin
  cell2.e += 0.0·dCos ;  cell2.f += 0.0·dSin
  ```
  **系数为 0.0 —— 分裂本身施加零力、零冲量。** 另有 `sin(z·10.34+43)·1e-7` 量级位置微扰，仅用于打破对称，非宏观力。
- 能量按 `Gene.c` 比例拆分并扣子代类型成本；`U[4]`、`X/Y`、`p` 按比分配；年龄归零；`k` 加 `Gene.e/f` 子代角度；`D` 切到 `Gene.i/j`（分化树）；`m ± 1`。

**结论**：用户描述成立且更精确地——

- "从细胞核（圆心）生成两个子细胞" ✓：中心只沿分裂轴各偏 `0.1r`。
- "因碰撞表现为两个半圆形" ✓（机制细节）：两圆中心距 `0.2r`、半径各约 `r`，高度重叠；接触弦近圆心，渲染成两个贴靠的半圆。
- "分裂本身不确定是否产生作用力" ✓：**确认为零力**。
- "分离来自弹性恢复/相互推动" —— 方向正确，但严格说是**下一 tick 的接触排斥力 `d(int)`（力 ∝ 相交面积）把高度重叠的两子细胞弹开**，不是"恢复圆形"这一形变本身产生力。

---

## 5. 四问速查

| 现象 | 是否成立 | 代码级成因 | 对 Godot 的落点 |
|---|---|---|---|
| 膜精密贴合 | ✓ | 物理/渲染共享同一组解析相交弦端点（`A[]`） | 用弦端点做膜顶点 + 弧解析插值；片元圆裁剪 |
| 饥饿变小 | ✓ | `f()` 中 `d_target = sqrt(w)/20`，低通跟踪 | 半径由能量派生，勿用独立缩放动画 |
| 变形后才推动 | ✓ | `d(int)` 力 ∝ 相交面积，经 `c()`/`f()` 积分 | 保持软弹力；力度用重叠面积而非穿透深度线性量 |
| 分裂零力 | ✓ | `e()` 速度增量系数 `0.0` | 子细胞初始重叠于圆心，靠接触排斥自然分离 |

## 6. 三个边界的后续确认（2026-11-17 第二轮）

> 方法：继续用 REA/JADX 0.7.1 反编译 `Cell` 全部 `a` 重载、`Gene.a` 内部类，并对弦剔除判据做数值等价验证（Python 5 组随机样本逐位一致）。

### 6.1 [证实] `a(6)` 刚度 → Gene 参数槽映射

`Cell.a(int)` overload 1 的方法体只有一行：

```java
public final float a(int i) { return this.I[this.D].v[i]; }
```

即**直接读当前基因槽 `I[D]` 的 `v[i]`，无任何调制**。所以：

- `a(6) == Gene.v[6]`，取值域 `0.5..2`（§11.4 的 `z[7]/A[7]` 表第 7 项）。它乘以 `a(6)` 在 `d(int)` 里作接触/皿壁刚度的调和平均分子：`dA = (d50·500)/((0.5/a6_self)+(0.5/a6_other))/s`。**修正此前解析报告 §11.4 把 `v[6]` 猜成"分裂成本相关"的表述：那是用处之一（`e()` 里 `max(0,v[6]-1)·0.054` 扣分裂能量），主语义是接触刚度。**
- 顺带确认同一方法族：
  - `Cell.a()` overload 0：`return I[D].s == LIPOCYTE ? (w+S)·0.36/2.16 : w` —— 返回"有效质量"，LIPOCYTE 计入脂肪储备 `S`。
  - `a(int,int)` overload 2 是**另一套**（调制输出），不要与 `a(int)` 混为一谈——这正是此前"行为总线语义未定"的混淆根源。

`Gene.v[0..6]` 完整用途（按本轮与既有调用点）：

| 槽 | 范围 | 用途（已证实调用点） |
|---:|---|---|
| `v[0]` | `−60..60` | 感知输入增益（`d(int)` 中 `v[0]·fSqrt`，clamp ±20） |
| `v[1..4]` | `0..1` | 同类感知的颜色目标 `v[1..3]` 与半径阈值 `v[4]`（`d(int)` 的 `u[3]==0` 分支） |
| `v[5]` | `0..√3` | [证实] `CellWorld.e(double)` 在 `Gene.l` 为真、分裂后建立母女连接时执行 `float fA = cell.a(5); link.l = fA; link2.l = fA;`，即新连接长度参数；不是行为总线槽 |
| `v[6]` | `0.5..2` | 接触刚度（`d(int)` 的 `a(6)`）+ 分裂能量修正（`e(double)`） |

### 6.2 [证实] `Cell.a(int,int)` 全索引语义 = 调制输出总线，不是简单参数表

`Cell.a(int i, int i2)` overload 2 方法体（完整逻辑）：

```java
Gene.a m = I[D].t[i];                    // 第 i 个调制器
if (m.e != 0) {
    float x = (m.d < 4) ? U[m.d + i2]    // 输入源 0..3：信号通道（i2 = 双缓冲页偏移）
            : m.d==4 ? (float)(w/0.36)   // 能量比
            : m.d==5 ? (float)(o*0.0041666667)  // 年龄/240
            : m.d==6 ? (float)p          // 内部浓度
            : /* m.d==7 */ C/20.0f;      // 连接数归一
    f = (m.e==1) ? x*m.a + m.b           // 线性映射
                 : (x < m.c ? m.a : m.b);// 阈值映射
} else f = m.b;                          // 调制器未启用，取常量 b
f = clamp(f, −1, 1);
return ((f+1) * (Gene.y[i] − Gene.x[i]) * 0.5) + Gene.x[i];  // 重映射到该槽的值域
```

**输入源 `m.d` 全索引（0..7，[证实]）**：

| `d` | 语义 | 备注 |
|---:|---|---|
| 0..3 | `U[d + i2]` | 4 通道信号；`i2` 是双缓冲页偏移（0 或 4），不是通道号 |
| 4 | `w / 0.36` | 能量/质量比，归一到 0..1 |
| 5 | `o / 240` | 年龄，`0.0041666667 = 1/240` |
| 6 | `p` | 内部浓度 |
| 7 | `C / 20` | 连接数，除以连接上限 20 |

**输出槽 `i`（0..10）值域与消费点**（值域来自 `Gene.x/y[11]`）：索引 0 = `0..1`（鞭毛推进力、能量消耗）；1 = `−3..3`（浮力项）；2/4/5 = `−1..1`、3 = `−0.5..0.5`（肌细胞收缩、纤毛相位、干细胞的 `a(5,0)/a(6,0)` 分化阈值）；7..10 = `−20..20`（神经细胞 4 个输出）。映射模式 `m.e`：0 = 未启用取常量 `b`，1 = 线性 `x·a+b`，其它 = 阈值二值 `x<c ? a : b`。`m.a/m.b/m.c` 由 95 个突变算子中的三簇修改（见 §11.5）。

### 6.3 [证实] 弦求交剔除的三角判据等价形式

`a(FFFF)` overload 7 中预处理弦的两层循环（d8–d26）已还原为几何判据，并用 5 组随机样本数值验证等价（见 §7 工具记录）：

**第一层：两弦相交则截断端点。** 设弦 `i` 端点 `P_i = A[i].a/b`、`Q_i = A[i].c/d`（相对细胞中心，局部坐标），方向 `v_i = Q_i − P_i`。对弦 `i14` 与 `i16`（`i16 = (i14+k) mod B`）：

```
d14 = cross(v14, v16)        （反编译写法 d8·d11 − d9·d10，符号与标准 cross 相反但同为零点）
t   = d15 = cross(P16−P14, v16) / cross(v14, v16)
s   = d16 = cross(P16−P14, v14) / cross(v14, v16)
```

数值验证：`d15` 与标准线段参数 `t` 逐位相等，`d16` 与 `s` 逐位相等。当且仅当 `0 < t < 1` 且 `0 < s < 1` 时两弦内部相交，代码将相交点写回两弦端点（`d17` 的符号决定保留哪一侧端点），并把退化弦标记 `e = true`。

**第二层：遮挡剔除（重心/面积比判据）。** 对弦 `i17` 与另一弦 `i18`（端点不重合时才检查）：

```
d26 = cross(P18, v18) / cross(P17, v18)
    = [P18.x·(P18.y−Q18.y) − P18.y·(P18.x−Q18.x)] /
      [P17.x·(P18.y−Q18.y) − P17.y·(P18.x−Q18.x)]
```

即**以原点（细胞中心）为顶点，弦 18 为对边的三角形中，射线 `O→P17` 与对边相交的参数**。数值验证 `d26` 与 `cross(P18,Q18)/cross(P17, Q18−P18)` 逐位相等。当 `0 < d26 < 1` 时，说明 `P17` 被弦 18 挡在内侧 → 标记弦 `i17` 为 `e = true`（渲染时跳过）。

**等价实现要点（供 Godot 复刻）**：不需要真的构造三角形，直接用带符号面积比 `d26` 判定即可；`e` 标记是渲染剔除位，`f` 标记表示该弦端点被相交截断（弧段插值时跳过）。第三轮确认：排序发生在这两层 O(B²) 检查之后，不能改成"排序后只查相邻弦"（见 §7.3）。

## 7. [证实] 三个残留边界（2026-11-17 第三轮）

### 7.1 `u.compareTo()` 的精确排序键

`com.saterskog.cell_lab.u.compareTo(u)` 方法体：

```java
if (this.e && uVar.e) return 0;
if (this.e) return 1;
if (uVar.e) return -1;
if (uVar.b * this.b < 0.0d) return this.b > 0.0d ? -1 : 1;
return uVar.b * this.a > this.b * uVar.a ? -1 : 1;
```

- `e=true`（遮挡剔除）的弦排到末尾。
- 其余弦按端点 1 的 `b` 符号分组：`b>0` 在前，`b<0` 在后。
- 同号时比较 `other.b * this.a > this.b * other.a`，即按 `a/b` 降序；等价于极角 `atan2(b,a)` 在 `[0,2π)` 升序。
- 结论：此前"按角度排序"的记录得到证实，但精确键是 `a/b` 的交叉相乘比较 + `b` 符号分组，不是直接 `atan2` 浮点比较。

### 7.2 `Gene.v[5]` 的消费点

`CellWorld.e(double)` 分裂逻辑中，仅当 `Gene.l` 为真（分裂后保留母女连接）时：

```java
float fA = cell.a(5);
link.l = fA;
link2.l = fA;
```

因 `Cell.a(int i) = I[D].v[i]`，所以 `v[5]` 是**新连接的长度/初始间距参数**。注意 `Cell.a(5,0)` 是另一套调制输出总线，不能与 `Gene.v[5]` 混淆。

### 7.3 遮挡检查不能优化为排序后相邻比较

`CellWorld.a(FFFF)` 的实际顺序是：

1. 第一层：对 `A[]` 两两求交并截断端点，双层循环覆盖所有 `(i, (i+k) mod B)`，是 O(B²)。
2. 第二层：对每条未剔除弦与所有其他弦做 `0 < d26 < 1` 遮挡判断，也是 O(B²)。
3. **之后**才执行 `Arrays.sort(cell.A, 0, cell.B)`。

因此"排序后只查相邻弦"在当前代码路径中不成立；Godot 侧保留完整 O(B²) 判据才是等价复刻。B 上限 20，代价可接受。

## 8. [部分未确认] 仍需证据的边界

- `Gene.v[5]` 的取值范围 `0..√3` 是否在所有类型中都被解释为连接长度：官方版已确认 `CellWorld.e(double)` 一处、Macro 版已确认 `SimulationWorld.f1(double)` 一处，且两处调用点均无类型分支；但未逐一展开 `Cell.f` 的其余 5 个上游调用点，因此仍保留为「已确认主要消费点、非穷尽」。
- ~~Macro 版 `SimulationWorld` 把通道数扩到 101 后，`u.compareTo()` 是否仍用于同一套弦几何，未单独反编译 Macro APK 的对应类。~~ **v0.8.11 已确认**：Macro `Y8.compareTo()` 与官方 `u.compareTo()` 同构，`SimulationWorld.x()` 仍按「相交截断 → 遮挡剔除 → `Arrays.sort()` → 端点+圆弧」流程使用同一套共享弦几何。详见 §11。
- Macro shader 与官方版**不完全同构**：主体细胞片元着色器保留 `dot(p,p) > col.a² → discard` 的解析圆裁剪，但 Macro 额外扩展了 texture atlas / 光照 / 培养皿形状 / 多套细胞类型变体。只保留机制结论，不移植其资源或完整 shader。

## 9. 参考证据 ID 索引

（仅列工具实际返回的 evidence_id；短前缀来自早期会话，完整 ID 来自本轮，避免凭记忆补全 64 位哈希。）

- `ev_de5f0119d789…`：`Cell.a(int)` = `I[D].v[i]` 直读（刚度映射）
- `ev_ac24ab6c79fd…`：`Cell.a(int,int)` 调制总线完整方法体
- `ev_aa7d9234f915…`：`Gene.a` 内部类字段（a/b/c/d/e/f）
- `ev_d91292889d89…`：`Cell.a()` 有效质量（LIPOCYTE 含 S）
- `ev_384d742089242f069120f68f5ac428299eae321f9f9334c3bd27a3bc5b59ae5b`：`CellWorld.d(int)` 完整方法体（接触物理 + `A[]` 弦端点 + 皿壁弦）
- `ev_243f4ae4e394a3f49d2c8178698153c769fbfb9069aa71489617eff278e4e860`：`CellWorld.a(FFFF)` 完整方法体（相交截断 / 遮挡 / 排序 / 圆弧重建）
- `ev_a0753dce735ed54d0887951ddd67152eed1e8a6353a5319b3240010f5606fe01`：`CellWorld.i()` 每 tick 清零 `cell.B`
- `ev_88f4fee6465ee195389c675418c326bb3504bd6721729a29f5954f90be56961a`：`CellWorld.c(boolean,double)` 设置 `U=z` 后逐细胞 `d(i)`
- `ev_b41aa7296d69f62d275e24d24893976cdcbbf4743c8e29da799ffa0a443628eb`：`CellWorld.a(boolean,double)` = `b(z,d)` 后 `a(d)`
- `ev_5118658c5fb611243f0611bc4e0fb3e8257312c8b69779c21b513890c43c7fb2`：`CellWorld.b(boolean,double)` update1 阶段顺序
- `ev_e7d7309c40f094d6c03d6dc5485664c12ebc30892397eb7d99f7c1240714e351`：`u.compareTo()` 排序键
- `ev_22c3408b3e3c01183f81021b33dabcc438aeb2e41bce50afbf2ab074be68cf23`：`CellWorld.e(double)` 分裂与 `Gene.v[5]` 连接长度
- `ev_54b3a424a92363d552a50794586f536de460273f9d5f3e8cdaca7d5ca1e3fed3`：`CellWorld.f(double)` 位置 / 半径积分
- `ev_d78d513d05a3482dc97dc00e83d5eb46c4002599dfcbe154bb7f358a05dca9f4`：`CellWorld.g(double)` 代谢
- `ev_c3f729586c137…`：`CellWorld.f(double)` 半径积分（早期证据）
- `ev_6d733332b66d3…`：`CellWorld.e(double)` 分裂（早期证据）
- `ev_058788db988c9…`：`CellWorld.g(double)` 代谢（早期证据）
- `ev_1550a20c215cf…`：`CellWorld.c(double)` 速度积分（早期证据）
- `ev_63369ac0e02d0…`：`CellWorld.i()` 受精（旁证，非四问核心）
- `ev_2214552d56c2f…`：`CellWorld.a(FFFF)` 几何构建（早期证据）
- `ev_3d3c8ccb4e4e2…`：`CellWorld.a(float[])` 绘制分发（早期证据）
- 本地 shader（本轮从 APK 解压只读核对）：`res/raw/cell_vert.glsl`、`res/raw/cell_frag.glsl`。顶点只传 `vPosition.xy*50`，片元用 `discard` 做精确圆裁剪；相位 `tp` 只参与着色，不改几何。

## 10. 弦抽搐：代码级归因与 Godot 修复（v0.8.9）

### 10.1 Cell Lab 为什么不会抽搐

- `i()` 每 tick 先 `cell.B = 0`；`c(boolean,double)` 设置 `U=z` 后调用 `d(i)`，在同一物理阶段把公共弦写入双方 `A[]`。
- 几何构建 `a(FFFF)` 用**精确 `cell.d`** 和 `A[]` 端点生成多边形顶点；相邻端点之间的圆弧用解析圆插值。
- `cell_vert.glsl` 只把局部偏移乘 50；`cell_frag.glsl` 以 `col.a = cell.d*50` 做片元级 `discard`。相位/呼吸量 `f24/f25` 写入 `ae[]`，经 `vTPosition` 仅影响着色，不参与顶点位置。
- 因此 Cell Lab 的接触端点来自同一 tick 的解析几何，且没有"呼吸膜与固定弦求交"的二阶扰动。

### 10.2 Godot v0.8.8 的实现偏差

1. `CellView._refresh_shape()` 先生成 12 控制点 Catmull-Rom + 3 谐波 + 速度拉伸的呼吸轮廓，再用共享弦做 Sutherland-Hodgman 半平面裁剪；弦端点固定在精确圆上，轮廓却在呼吸，交点自然滑动。
2. 裁剪按 `_chords` 的下发顺序逐个执行；邻居顺序由空间哈希给出，顺序变化会让两条相交弦的裁剪结果互换。
3. 缺少 Cell Lab 的第一层"弦相交截断"与排序步骤，`cull_occluded()` 只做了第二层 `d26`。

### 10.3 v0.8.9 修复（仅视觉层）

- `CellContactChords.gd` 新增 `make_unit_chords / truncate_intersections / mark_occluded / chord_less / sort_chords / prepare_for_render / build_outline`，严格按 Cell Lab 顺序：相交截断 → 遮挡剔除 → 排序 → 端点 + 解析圆弧重建轮廓。
- `CellView.gd` 在存在弦时直接采用重建轮廓，不再让呼吸相位参与接触边界；无弦时保留原弹性膜路径。
- `circle_chord()` 的端点顺序改为与 Cell Lab `A[]` 的 endpoint1/endpoint2 一致（`middle - perp*h` / `middle + perp*h`）。
- 所有改动只读 SoA；不进入 `CommandBus`，不写 tick 状态。SmokeTest 新增断言：输入顺序置换后轮廓逐点一致、呼吸相位变化后接触轮廓逐点一致、反复刷新视图前后 `OrganismManager.get_state_hash()` 不变。

### 10.4 v0.8.10：轮廓多边形化 / 消失的代码级再核对与修复

用户连续截图反馈细胞膜在几帧内由圆变多边形甚至完全消失。重新静态读取 `CellWorld.a(float,float,float,float)` 完整方法体（证据 `ev_23d9c8549e5a334ce01f02b6089fe546b100e25bd25dd54a2f17cd0128abd32f`，APK SHA256 与 §0 一致），逐项对照后确认：

1. **`A[]` 输入顺序**：Cell Lab 的 `d(int)` 按邻居 cell 索引升序追加 `A[]`；Godot 直接消费空间哈希邻居顺序。`truncate_intersections()` 会原地改写两弦端点，因此顺序变化会改变最终结果。诊断脚本显示 5–6 接触时逆序输入会让轮廓点数从 19 变 17、顶点最大偏移 >1（单位圆），即截图中的“快速变换”。修复：`prepare_for_render()` 先按 `(kind, peer)` 排序，再执行 Cell Lab 的原顺序流程。
2. **`f` 标记**：Cell Lab 在输出顶点后检查 `if (!cell5.A[i24].f)` 才做圆弧插值；被截断弦只保留端点。Godot v0.8.9 记录了 `truncated` 但未消费，导致截断端点之间仍插出交叉圆弧。修复：`build_outline()` 遇到 `truncated` 不再插弧，直接连到下一端点以保持 `Polygon2D` 闭合。
3. **退化保护**：3 个中心距 ≈ r 的深重叠接触会让所有弦端点被截成同一点；Cell Lab 用中心三角扇仍可渲染，Godot 的 `Polygon2D` 则塌缩为 2 点。修复：`build_outline()` 检测点数/面积/中心包含，退化时回退到解析单位圆半平面裁剪 `clip_unit_circle()`；过滤零长度弦。
4. **皿壁弦**：`wall_chord()` 原为 `circle_chord()` 的薄封装，其 `s <= |r0−r1|` 包含判据把“小圆在大圆内”当作无交，贴壁时几乎不产弦。修复：改用内侧相交式 `d = (r² − R² + s²)/(2s)`，`s > R − r` 才有效。
5. **符号复核**：`d17 = cross(v16, Q14−P16)` 与 `d26 = cross(P18,v18)/cross(P17,v18) ∈ (0,1)`（此处 `v18 = P18−Q18`）在 Godot 实现中原式正确，本轮未改；此前怀疑的符号反向是对反编译变量方向的误读。

所有改动仍只在视觉派生层：不写模拟状态、不经过 `CommandBus`、不改变 `get_state_hash()`。SmokeTest 新增多接触顺序置换、深重叠非退化、皿壁弦有效性和连续 30 tick 轮廓闭合断言，`SCRIPTS=43 FAILURES=0 EXITCODE=0`。

### 10.5 v0.8.11：少量接触时轮廓多边形化的残留修复

用户反馈 v0.8.10 后细胞膜仍会变成多边形。用临时几何诊断脚本量化后确认：这不是弦求交错误，而是**采样密度不足**：

- 2 条接触弦时 `build_outline()` 只产出 10 点（面积 2.8396），3 条弦时 15 点（面积 2.8681）；同一组弦用 `clip_unit_circle()` 分别得到 48 点（面积 2.9906）和 39 点（面积 2.8919）。
- Cell Lab 不存在这个问题：它的 `cell_frag.glsl` 用片元级 `discard(ds > cell.d*50²)` 做圆裁剪，顶点稀疏也不会露出多边形边。Godot 的 `Polygon2D` / `Line2D` 没有等价片元圆裁剪，必须在几何层解析采样。
- 修复：`CellView.gd` 在有弦时以 `clip_unit_circle(prepared, 64)` 作为主路径，对解析单位圆做半平面裁剪；`build_outline()` 不再作为主路径。顺序规范化、相交截断、遮挡剔除仍由 `prepare_for_render()` 完成，Cell Lab 的几何顺序不变。无弦时仍保留原弹性膜路径。
- SmokeTest 新增「接触轮廓点数 ≥ 24」断言，并把相切测试改成显式两细胞场景以消除发育时序 flake；连续两次 `SCRIPTS=43 FAILURES=0 EXITCODE=0`。
- 边界：仅视觉层；物理、tick 顺序、`get_state_hash()` 均不变。

### 10.6 v0.8.12：统一解析圆路径，消除弹性膜 / 弦膜循环

用户连续截图反馈「细胞一接触就 多边形化 → 消失 → 重建 → 多边形化」循环，并提出两个方案。代码级定位结果：

1. **运行副本版本落后**：用户打开的 `D:\Tools\Godot_v4.7.2\project\cellarium` 仍是 v0.8.10，`CellView.gd` 主路径为 `build_outline(prepared, 3)`，`CellContactChords.gd` 没有 `clip_unit_circle()`，且 `clip_keep_origin()` 在结果少于 3 点时返回未裁剪输入。少量接触时轮廓只有 5–15 点，退化时 `Polygon2D` 不可见而只留下细胞核/细胞器点；弦一消失又切回 72 点呼吸膜，构成截图循环。
2. **发布版 v0.8.11 仍有路径切换**：有弦 64 点解析圆、无弦 72 点呼吸膜，两套点集在接触边界跳变；`clip_keep_origin()` 的退化回退会让轮廓突然跳回整圆。
3. **Cell Lab 对照**：`cell_vert.glsl` / `cell_frag.glsl` 的相位 `tp` 只参与着色，外膜几何来自物理半径与 `A[]` 共享弦；不存在独立呼吸轮廓。方案①（同一细胞内混用弹性弧与弦段）会重新引入相位/端点不一致，故采用方案②的严格版本：统一解析圆。

实现：`unit_circle(64)` 作为唯一外膜基底；有弦时按「规范顺序 → 相交截断 → 遮挡剔除 → 排序 → 半平面裁剪」处理，无弦时只做浅接触压平；`clip_keep_origin()` 退化返回空数组，`clip_unit_circle()` 跳过退化弦。内膜按外膜同轮廓缩放，避免穿出压平边界。速度拉伸状态保留给 API/测试但不再施加到共享边界，以确保双方共边。SmokeTest 新增弦/无弦点集不切换、无弦轮廓 ≥64 点且面积非零断言。发布工程与用户运行工程均 `SCRIPTS=43 FAILURES=0 EXITCODE=0`。

### 10.7 v0.8.13：接触阈值抖动才是持续闪动的直接原因

v0.8.12 统一膜路径后用户仍看到「一直在闪动」，两张连续截图分别是有弦切平与无弦整圆。用临时无头诊断走真实场景链路（默认演示体，`advance_development_tick` → `advance_physics_tick` → `CellSceneRenderer._rebuild`），180 tick 结果：

- 最近邻中心距始终在 `13.999812 … 14.000039`（float32 抖动约 ±4e-4），远小于 `2r = 14` 的有效变化；
- 共享弦数量却在 `0/2/4/6` 间切换 **84 次**。

因此根因不是弹性膜路径、不是弦几何顺序，而是接触判定的数值阈值：

```text
circle_chord:  s >= r0 + r1 - 1e-6  → invalid
wall_chord:    s + radius <= dish_radius + 1e-6  → invalid
```

碰撞 `resolve_collisions()` / `project_to_dish()` 把中心钳在恰好相切处，1e-6 的阈值比抖动小 2–3 个数量级，于是弦在相邻 tick 间随机开关；视图随之切换「弦裁剪多边形」与「整圆 + 浅压平」，视觉上就是持续闪动。Cell Lab 不存在这个阈值问题：它用片元 `discard` 做圆裁剪，接触点来自物理阶段的 `A[]`，渲染阶段不再对「是否接触」做几何阈值判断。

修复：`contact_epsilon(radius) = maxf(0.02, radius * 0.01)`，圆弦与壁弦共用；半径 7 时阈值 0.07，约为实测抖动的 175 倍。真正重叠超过 0.07 仍生成弦并保持 Cell Lab 的共享端点机制；阈值内的相切由既有浅压平提供稳定形变。SmokeTest 加入相切抖动、真实重叠、皿壁抖动与 60 tick 场景级断言。同一诊断修复后 `chord_switch=0`。

**边界**：此修复只改视觉派生，不改物理碰撞、tick 顺序、`CommandBus` 或 `get_state_hash()`；也不改变连接静息长度。另观察到 `ADHERE` 工具写死 `link_cells(a, b, 8.0)`、`DevelopmentRules` 的 `LINK` 可写入 `< 14` 的静息长度，这与碰撞最小中心距 14 在语义上不一致；但它不会造成上述闪动（渲染看到的是碰撞后的位置），若将来要修正属于物理/存档 schema 变更，必须单独版本化并重新核对确定性 hash。

### 10.8 v0.8.14：接触前提前变形

用户反馈密集碰撞时细胞膜在尚未接触时就变形。视觉层原因：`CellSceneRenderer` 原用 `contact_range = 2r + 1`、`wall_range = 0.8r` 触发浅压平，半径 7 时分别相当于 gap=1 与 gap=5.6 就开始压平，远大于真实接触边界。无头诊断（默认演示体 600 tick、8 枚强制重叠细胞 180 tick）确认物理层均能在一 tick 内分离到 ≥2r，无残留重叠，因此只收紧视觉范围至 `2r + contact_epsilon(r)` 与 `contact_epsilon(r)`。SmokeTest 加入 gap=1 不压平、真实接触/贴壁才压平的断言。仍然不改物理与 hash。

## 11. Macro APK 边界确认（v0.8.11）

样本：`C:\Users\安\Downloads\cell-lab-macro-beta-latest.apk`，SHA256 `9d0f3509c871ef4afbcf5547dd4125adbf5745059faf94e74d5d8b3e8aa48a1a`，包名/入口类 `com.saterskog.cell_lab_enzymeglv.*`。全部为静态反编译与 APK 只读解包，APK 未执行。

### 11.1 通道数

`J8.<clinit>` 依次构造 `new J8(1)`、`new J8(0x65)`、`new H8(v1, 0)`，确认通道数为 **101**（`0x65`）；`H8.<init>(int,int)` 自带 `channelCount must be positive` 校验。证据 `ev_baaebfb812cccc31d89ae9e07416377da11f57acf64146bcf38803e792d2c32f`。对 Godot 的约束不变：`channel_count` 必须可配置，不能写死 4。

### 11.2 共享弦几何与排序

- `SimulationWorld.x(float,float,float,float)` 完整方法体共 1662 行 / 99,036 字符，`source.status = complete`、`body_status = available`。已用脚本对全部 1662 行逐行扫描，并抽取命中语句上下文；不是只看关键字片段。证据 `ev_22344a878059ddd47baa707160b4ca070b759dc94f8f8f5e85ea39ffe94fe387`。
- 相交截断：对 `Cell.f583j`（`Y8[]`）两两取 `(i, (i+k) mod B)`，命中时写回双方端点 `f1547c/f1545a` 与 `f1546b/d`，并置 `f1549f`（对应官方 `u.f` 截断标记）。
- 遮挡剔除：`if ((y.f1545a * y.d) - (y.f1546b * y.f1547c) < 0.0d) y.f1548e = true;`；第二层用 `0 < d26 < 1` 判遮挡，与官方判据同构。
- 排序：`Arrays.sort(cell9.f583j, 0, i63)`，位于两层 O(B²) 检查**之后**；`Y8.compareTo()` 的键为「遮挡置末 + b 符号分组 + a/b 降序」，与官方 `u.compareTo()` 同构（证据 `ev_e7bd831b4c3da629024bafa6259c458ad61a5471d6b3bc8044a93e6b700f3d70`）。
- 渲染：遍历 `f583j` 时跳过 `f1548e` 弦，端点送入顶点缓冲；仅 `f1549f == false` 的弦做解析圆弧插值。皿壁/地形壁弦写 `g = -1`，与官方一致。
- 结论：101 通道扩展**没有**改变共享弦几何拓扑与顺序要求；v0.8.8–v0.8.11 的 Godot 视觉层实现顺序仍然适用。

### 11.3 `r0[5]` / `Cell.f(5)` 的消费点

- `Cell.f(int)` = `this.s[this.f586m].r0[i2]`，即 Macro 把基因参数数组从官方 `v[]` 改名为 `r0[]`（证据 `ev_cacf0005ab42e57adf4ad251bcbe95f88fd9148a799c4092d60521065dba96c1`）。
- `Cell.f` 的静态调用者共 6 个（证据 `ev_5f971c734ece2f656c8774867adfe4168825cc9b5d91d323e69fd33e9d98403a`）：`SimulationWorld.f1/p1/t1/v1/w1/x1`。
- `SimulationWorld.f1(double)` 方法体 8517 行 / 166,000 字符（smali，`source.status = complete`，证据 `ev_38e6dfbad3eb74de3272c163a1db948796bd6635e4b0bd3992e8b2ba3f8888ce`）。在约第 4944–4959 行出现无条件序列：
  ```smali
  const/4 v4, 0x5
  invoke-virtual {v3, v4}, Lcom/saterskog/cell_lab_enzymeglv/Cell;->f(I)F
  move-result v4
  iput v4, v1, Lcom/saterskog/cell_lab_enzymeglv/AdhesinLink;->l:F
  iput v4, v2, Lcom/saterskog/cell_lab_enzymeglv/AdhesinLink;->l:F
  ```
  即 `r0[5]` → 分裂后两条 `AdhesinLink.l`（连接长度 / 初始间距），与官方 `CellWorld.e(double)` 的 `Gene.v[5]` 消费点一致，且此处无按细胞类型的分支。
- 旁证：`w1(...)` 与 `x1(...)` 均使用 `cell.f(6)` 乘皿壁/地形壁接触面积，说明 Macro 的 `r0[6]` 仍是接触刚度（证据 `ev_f02585fbd7030cdc37198b695db5b64a3fcd923e543382d8ac195ec61a85a5b7`、`ev_8369ea18c52025fa1ae919ae80cc96ae8421d449252e78619a048105f71f9ba2`）。
- 边界：`Cell.f` 的另外三个调用点 `p1/t1/v1` 未逐一展开常量索引，故「所有类型 / 全部调用点」仍按 §8 保留为部分未确认。

### 11.4 shader 对照

- 官方 `cell-lab-zh.apk` 的 `res/raw/cell_vert.glsl` 用 `vPosition.xy*50` 传局部偏移；`cell_frag.glsl` 用 `dot(p,p) > col.a*col.a → discard` 做片元级圆裁剪，相位 `tp` 只参与着色。
- Macro 的 shader 文件名被混淆（`res/-n.glsl`、`res/Mb.glsl` 等），但主体细胞变体保留同一判据；例如 `res/Mb.glsl` 含 `if(ds>col.a*col.a)discard;`，`res/-n.glsl` 等十余个变体同样包含该式。Macro 另增 `outsidePlate(worldPosition)` 裁剪、texture atlas、光照与类型专属变体。
- 结论：**圆裁剪机制沿用，实现不完全同构**；Godot 侧继续用解析圆弧采样近似片元裁剪即可，不引入 Macro 资源或 shader。

### 11.5 对工程的影响

- 无需改代码：`CellContactChords.gd` 的「规范顺序 → 相交截断 → 遮挡剔除 → 排序 → 解析圆弧」流程在两种 APK 上都成立。
- 配置约束：`channel_count` 保持可配置（Macro 101 / 官方 4）。
- 待办边界：`p1/t1/v1` 的 `Cell.f` 常量索引穷尽检查；Macro 各 shader 变体与细胞类型的一一对应关系（不影响当前视觉层实现）。

## 12. 阶段 10：完全 GPU 采样迁移（v0.9.0）

### 12.1 原瓶颈

`EnvironmentField.diffuse_tick()` 在 GPU dispatch 后调用 `_read_active_buffer()`，每 tick 把 `5 × R²` 个 float 从 GPU 回读到 CPU `channels`；生产 R=32 为 20 KB/tick，吞吐测试 R=64 为 80 KB/tick。而 CPU 侧真正需要的只是每个活细胞 5 个通道的采样值——被 `_build_behavior_environment()` 与 `_sample_environment_range()` 各取一次。

### 12.2 新数据流

```text
GPU 场缓冲 active ──SAMPLE_SOURCE(dispatch 1)──> N×5 sample buffer ──小回读──> 行为/代谢
                    ▲                                   │
                    │                              consume() 聚合 Δ(index,channel)
                    └──DELTA_SOURCE(下一 tick)───────────┘
扩散：active ──COMPUTE_SOURCE──> inactive ──swap──> active（无回读）
CPU 镜像：仅 set_value / paint_terrain / snapshot / get_state_hash / 存档时惰性同步
```

- `SAMPLE_SOURCE` 的格坐标公式与 CPU `get_grid_position()` 一致：`floor((p - (center - radius)) / (2r) * R)`，不引入双线性，避免与 `sample()` 语义分叉。实测 GPU/CPU 采样最大误差 `5.96e-8`。
- `DELTA_SOURCE` 的输入由 CPU 按 `(格索引, 通道)` 聚合成唯一条目，因此不存在同一地址的写竞争；消费仍然先按当前场值 clamp，再写入，数值语义与旧 `consume()` 相同。
- `consume()` 使用的采样值来自本 tick 的批量采样缓存，与旧实现读「上一次扩散后镜像」的时序等价。
- `get_state_hash()` 与 `get_state_snapshot()` 现在先惰性同步 CPU 镜像，因此 hash 仍按全量场计算，不是按采样缓存计算；`SaveManager.restore()` 后清空缓存与未提交 Δ，避免跨局污染。

### 12.3 回退与边界

- CPU 后端走 `_sample_cpu()` / `_apply_pending_deltas_cpu()`，数值路径未变；SmokeTest 断言批量采样与逐点采样逐位相等。
- 单批样本上限 4096 细胞、8192 条聚合 Δ；超过上限退回逐点采样，且不恢复全量回读。
- `readback_bytes` 现在报告真实每 tick 回读量（4 细胞 = 80 B），`legacy_full_field_bytes` 保留旧全量方案作对照。
- Cell Lab 对照：官方版同样不把全量场搬到 CPU 做逐细胞采样；其顶点缓冲由 GPU 端场/参数直接生成。本次迁移只改变宿主侧数据搬运，不改变 §5–§11 的场数学与共享弦视觉机制。

## 13. 发育编辑器界面证据与规格稿（v0.9.1）

规格稿：`preview/dev_editor_preview.html`（单文件 HTML + 内联 SVG，纯 UI，不是实现）。

### 13.1 有证据的界面元素

- 40 Gene 槽与分化树：`Cell.I[40]` / `Cell.D` / `Gene.i,j` 子代槽索引；分裂时母/子切换，拓扑突变 1/5 概率重连（APK 解析报告 §11.4 / §11.5）。规格稿把 00–39 槽位做成左栏，并把 i/j 画成树边。
- Child 1–4、angle / split mass / ratio、Cytoskeleton、Adhesin stiffness、Max connections、RGB、Load / Save、Edit mode、On contact(Cell/Wall/Split)、Secretion、Virus copy from：来自 Macro `strings.xml` 的 `genome_editor_*` 词条族。
- 动态参数行（seekbar / spinner / checkbox / 帮助提示 / 预览回调）：Macro `GenomeEditorFragment.onCreateView()`（APK 报告 §5）。
- 发育规则：`dev_*` 词条族——After N splits→M、Differentiation、Conditional / Random path、Max / Min connections、Stop splitting；端粒候选 `{-1,5,10,20,40,80}`。
- 信号 lane：Add / Rename / Delete signal、Lane N output channel、Gene Bank、预览锁定（`setting_preview_lock`）；Macro 独有性未完全确认。
- 18 类型：官方 APK 前 18 与 Macro 一致（§11.6）。

### 13.2 明确未确认 / 不臆断

- Macro 编辑器的具体标签页划分未确认；规格稿的「基因槽 / 分化树 / 信号 lane / 预览」四页是**布局提案**。
- Cell Lab 原生 genome 编辑器快捷键未在资源中找到；Esc / Backspace 沿用本项目 v4 约定，不声称原版如此。
- 95 个突变算子（`nextInt(95)`，每 15 tick 三次）已确认存在，但逐编号语义未全部展开，规格稿只标注为待补齐面板。
- “40 modes” 是 UI 模式层，与运行时 `Cell.I[40]` 的 40 Gene 槽不同层，规格稿中已显式提示。

### 13.3 与当前 Godot 实现的差距

`CellEditorPanel.gd` 现有 8 滑块 / 呼吸 3 项 / 18 类型 / dev 指令表 / Add / Template / Clear / 文本预览 / Apply；缺 40 槽分化树、信号 lane、谱系图、撤销、参数与 dev_program 的双向可视化。本规格稿先确认布局，确认后再用 `Control` 节点落到 `.tscn`，所有写入仍只经 `CommandBus`。

## 14. 待确认边界（沿用）

- Macro 版 `p1/t1/v1` 的 `Cell.f` 常量索引未穷尽。
- Macro shader 变体与细胞类型一一对应关系未确认。
- 连接静息长度 `< 2r` 的语义不一致（见 §10.7），未改物理/schema。

## 15. 后续阶段路线（从 v0.9.1 起）

| 阶段 | 目标 | 主要内容 | 验收条件 |
| --- | --- | --- | --- |
| 11 | 发育编辑器 Godot 落地 | 按 `preview/dev_editor_preview.html` 用 `Control` / `.tscn` 搭 40 槽分化树、Gene 参数页、dev_program 时间轴、信号 lane；编辑只 enqueue，Apply 走 CommandBus | 编辑 → Apply → SPAWN 的 GNP1 往返一致；SmokeTest 覆盖树节点、时间轴、lane 与命令闭环 |
| 12 | 多细胞编辑增强 | 拖拽排序、谱系图、模板库；引入可验证的突变算子子集（不一次性移植 95 个） | 编辑后可回放得到相同发育结果；模板/撤销不绕过唯一写入口 |
| 13 | 连接内经济与信号传播 | 沿连接做能量再分配；4 通道信号按单 tick 时序传播；`channel_count` 可配置（Macro 101） | 能量守恒断言通过；信号时序不改 tick 顺序；存档 schema 只做版本化追加 |
| 14 | 视觉-物理一致性精修 | 接触弦贴合、弹性膜、贴壁形变、高密簇不交叉；ADHERE / LINK 的 `<2r` 静息长度若要修必须单独版本化 | 无提前变形/闪烁；几何断言与确定性 hash 复验通过 |
| 15 | 规模与性能深化 | 千级 LOD、GPU 采样批上限扩展、分段快进 + 检查点；>12× 有效倍速须先修订规格 | 性能数据真实（不缩放 dt、不突破单帧 12 tick 基线）；长跑分段可续 |
| 16 | 回归与发布 | 存档兼容、T12 回退、长跑分段、文档与快照/tag | 全量 SmokeTest / GPU parity / fallback 通过；每版 tag + CHANGELOG + 验收记录 |

优先级说明：阶段 11 直接响应用户当前需求；阶段 13/14 是已记录但尚未落地的机制边界；阶段 15 的倍速提升必须先走规格修订，不能靠改 `dt` 或突破单帧上限取巧。

## 16. v0.10.0 — 阶段 11 落地结论（2026-11-17）

阶段 11（发育编辑器 Godot 落地）已随 v0.10.0 完成，§15 路线中的阶段 11 行标记为已完成。落地口径严格遵循 §13/§15 与冻结约束：

- **真相源**：`dev_program`（DIVIDE/DIFFERENTIATE/LINK）是唯一发育结构；GNP1 二进制格式已冻结，规格稿中 Cell Lab 专有的 40 Gene 槽、Child 1–4、on-contact、信号 lane、95 算子只作只读证据展示，不写入编码、不臆造字段。
- **实现**：`scenes/ui/DevEditorPanel.tscn`（节点骨架）+ `scripts/ui/DevEditorPanel.gd`（三栏 + 时间轴）。左栏指令序列支持增删/上下移/选中；中栏 opcode/a/b/c 双向写回 draft 并编辑 GNP1 八性状；底部时间轴按 tick 顺序表达指令，仅 UI、不缩放 dt。
- **写入口**：`draft_applied` → `GameHUD._on_draft_applied()` → 装载合成器 → `CommandBus.enqueue()` → 皿内 SPAWN。面板不直接写模拟状态。
- **配套修复**（用户同批反馈）：生命周期可见化（基础代谢 0.006、光照通道 0.6、成熟个体按能量 cooldown 分裂、饥饿死亡）；工具闭环（光学镊子连续拖拽、INSPECT 诊断弹窗、ADHERE 双击建链、颜色/信号注射可选）。
- **行为边界**：自主分裂设「首次资格 cooldown 宽限期」，避免发育程序 9 指令→4 细胞/3 连接的确定性快照被成熟当 tick 分裂破坏；所有干预不进确定性 hash。
- **验收**：发布工程与 D 盘运行工程均 `SCRIPTS=45 FAILURES=0 EXITCODE=0`；新增生命周期与发育编辑器两组 SmokeTest。临时诊断脚本未发布。

## 17. v0.11.0 — UI 调整批次结论（2026-11-17）

本批全部是表现层/编辑器体验，未改 tick 顺序、物理、Chem 通道或 GNP1 编码，确定性 hash 不受影响。

- **面板 chrome**：`PanelChrome.gd` 统一注入标题栏（拖动/图钉/关闭），内容重挂 `ChromeRoot`；注意这会使外部深层节点路径变化，SmokeTest 与新代码都要按新路径取节点，脚本内部 `_ready()` 缓存不受影响。
- **顶栏开关**：每个面板有可复位 toggle；编辑器内部关闭按钮与顶栏状态由 `GameHUD._process()` 对账。AnalysisPanel 图钉固定后 `R` 不关闭。
- **诊断/报告**：INSPECT 命中写 `selection`，由 `SelectionLayer.gd` 画圆环；生态报告每 30 tick（可见时）刷新，属观察便利，不改快照。
- **光场**：`FieldLayer.gd` 只读通道 3 画格阵，是场的可视化而非新物理场；Cell Lab 的光照可见效果在本项目以同一通道数据呈现。
- **镜头**：切换到 `canvas_item` shader 滤镜，不再动相机；五镜头参数不同但仍只是滤镜，不声称还原 Cell Lab 的光学系统。
- **编辑器分工**：`CellEditorPanel` 下方 `dev_program` 快速表 = `dev ...` 指令紧凑编辑；`DevEditorPanel` 是同一草案的完整可视化。两者共享真相源，不重复写模拟。
- **验收**：发布与 D 盘工程 `SCRIPTS=48 FAILURES=0 EXITCODE=0`；D 盘同步回填 15 个脚本 uid + 30 个节点 unique_id，MCP autoload 保留。

## 18. v0.12.0 — 统一细胞编辑与诊断解锁（2026-11-17）

- **用户反馈**：诊断锁定后无法解除；生态报告右上角关闭按钮无效；细胞编辑与发育编辑重复，要求合并为单一「细胞编辑」并参考 Cell Lab UI。
- **关闭按钮根因**：`PanelChrome` 的标题栏 `gui_input` 也接收图钉/关闭按钮上的鼠标事件，拖动逻辑抢走 press/release，`Button.pressed` 不触发。现在 `_event_over_button()` 对按钮区域直接返回；`GameHUD._on_panel_close()` 同时同步面板内部可见状态。
- **解锁语义**：`selection` 是视图状态，解锁仍统一经 `CommandBus` 的 `CLEAR_SELECTION` 工具命令；入口为诊断点空白、分析面板「解除锁定」按钮、Esc。只清圆环与 `last_inspection`，不触碰物理、能量、dev_program 或确定性 hash。
- **编辑器合并**：唯一面板 `CellEditorPanel`（`scenes/ui/DevEditorPanel.tscn` 实例，脚本 `DevEditorPanel.gd`），原 `CellEditorPanel.gd` 删除。三栏 + 时间轴参考 Cell Lab：左栏 `GENE SLOTS 40`（前 8 槽 = GNP1 八性状，后 32 槽只读占位）、`DEV` 指令树；中栏参数与八性状；右栏 Cell Lab 专有字段只读证据；底部 `DEV TIMELINE`。`dev_program` 仍是唯一发育真相源；40 Gene 槽、Child 1–4、信号 lane、95 算子仍不写入 GNP1。
- **行为兼容**：合并编辑器保留旧 API 与 `(value, index, key)` 操作数写入签名；呼吸方式选择吸收进同一工具条；Apply 仍经 `draft_applied` → HUD → CommandBus → 皿内 SPAWN。
- **验收**：发布与 D 盘工程 `SCRIPTS=47 FAILURES=0 EXITCODE=0`。

## 19. v0.12.1 — 光场可见性根因与修复（2026-11-17）

- **现象**：用户仍反馈看不到光场，希望像 Cell Lab 一样直接显示光照范围。
- **根因**：`GameHUD._register_view_layers()` 用相对路径 `../DishView/FieldLayer`；HUD 位于 `UI/HUD`，实际解析到 `UI/DishView`，而 `DishView` 是主节点直接子节点（`/root/Main/DishView`）。`_field_layer` 一直为 null，顶栏「光场」toggle 的 `set_enabled()` 从未作用到图层；叠加 `visible_by_default=false`，图层始终不可见。顶栏开关初始化又用 `get_node("@field")`（必然 null）取初值，所以按钮也恒为关闭态，进一步误导。
- **修复**：路径改为 `../../DishView/...`；光场默认启用且 toggle 初值读 `FieldLayer.is_enabled()`；光场 alpha 提至 0.55，并在照亮格子的外沿按场半径画暖色细环，明确「照明覆盖范围」。
- **边界**：FieldLayer 仍只读 `EnvironmentManager.field` 通道 3；不新增物理场、不写场数据、不改 tick 与确定性 hash。皿内光照默认值 0.6 为均匀填充，因此可见范围覆盖整个皿内区域，这与场数据一致，不伪造聚光。
- **验收**：发布与 D 盘工程 `SCRIPTS=47 FAILURES=0 EXITCODE=0`。

## 20. Macro 编辑器 / 光照 / 基质设置补证（v0.13.0 前，2026-11-17）

本节只使用静态反编译证据。目标 APK 为从已提取目录重建的 `cell_lab_macro_recon.apk`（SHA256 `abfe6022ad178e061b6bacf257af11317e6d06c0afff662dc2ed604110f077a1`），JADX 0.7.1，808 类 / 912 资源；APK 未执行。除特别说明外，证据 ID 均为 REA 本轮实际返回值。

### 20.1 基因组编辑器字段：控件 → `Gene` 字段的写入链

- `GenomeEditorFragment.onCreateView()`（`ev_1727c69d65eead1f7b420113a3ed49c0ad4364379c1f66850975f566fe062be2`）确认编辑器控件族：`spinner_types/cells/child1..child4`、`seek_child1..4_angle`、`seek_mass`、`seek_prio`、`seek_ratio/ratio2`、`seek_splitangle/splitangle2`、`seek_stiff`、`checkbox_make_glue/stay_alive/keep_glue1..4/mirror1..4/snap/show_split_indicators/function_signal_gate`、`check_invert_split_mass`、`radio_initial`、RGB 与 GL 预览 `GenomePreviewView`。
- `GenomeEditorFragment.refreshControlsFromSelectedGene(boolean,boolean)`（`ev_3896a017015372230a52449ba233fdcaf267c026f0ef547286f68e74cdac85f3`）确认读取映射：
  - `child1..4` → `Gene.f778r / s / t / u`；四个子代角度 → `f771k / f772l / z / A`，除以 `TAU`。
  - `seek_mass` → `splitMassFraction(gene)`；反转质量 → `f768h`；营养优先级 → `log(f773m/0.1)/log(99.99999850988391)`。
  - `seek_ratio/ratio2` → `1 - (f769i-0.1)/0.8`、`1 - (C-0.1)/0.8`；两个分裂角 → `f770j / B`，除以 `TAU`。
  - `seek_stiff` → `f774n < 35 ? f774n/35 : 1`；`make_glue` → `E`；`stay_alive` → `H`；`keep_glue1..4` → `F/G/v/w`；`mirror1..4` → `J/K/x/y`；`initial` → `I`。
- 预览读取环境倍率：`activeEnvironment.P0/Q0/R0` 分别对应 feeding / light / salinity 预览倍率（来自 `onCreateView()` 与 `refreshControlsFromSelectedGene()`）。
- 边界：这些字段证明「Macro 编辑器有这些可调参数」，但本项目 `GNP1` 已冻结、`dev_program` 是唯一发育真相源。40 槽 / Child1–4 / 信号 lane / 95 算子不能写入 GNP1 编码，也不能据此改确定型 hash。

### 20.2 光照调用链：`Environment.q()` 是空间场采样，不是直接产能

- `Environment.q(double,double)`（本轮复核 `ev_817d7427f4b750f22bba16e14bddbd796a314ebe9ec512dc65ecfe8fd20eaf27`）：
  ```text
  dN = n(x, y, K0, J0, L0, M0, N0)
  if C0 == null: d4 = 0
  else: d4 = bilinear(C0.f490a, 64x64)
  return min(1, dN + d4)
  ```
  即「空间插值/梯度 + 64×64 分布图双线性叠加 + 上限 1」。
- `trace_android_references(Environment.q)`（`ev_8c44f454ca50cf98baf1b34a57fb613a36fdb4feabf35894e3e399618754d48f`）给出完整使用节点 5 个：`PlateDistributionPreviewView.onDraw`（预览）、`SimulationWorld.A2`、`SimulationWorld.u1`、`SimulationWorld.v1`、`v7.Q`。
- `SimulationWorld.u1(...)`（`ev_7b72fa0a55323c6e4cf0e2518ffc17d0e32094b659dc1327dac667fa510da387`）中 `i35 == 6` 分支直接调用 `environment.q(...)`，结果经 `t0()` 限幅后写入 `cell.G[...]`（行为总线/转向意图）。这证明 `q()` 参与**感知/行为输入**，不是把光量直接加到细胞能量。
- `SimulationWorld.v1(int)` 完整方法体已从 `ev_d374c9e008921ff0a50ad34f745854f4362eba7723f0167a7ce6ce3c1f17ba07` 逐行读取（1–1921 行，100%）：`q()` 在立体细胞/感觉细胞分支中同样用于读取空间场并写入行为力（`fQ` → `cell.G`），而食物/细胞接触在 `Q(...)` 与 `u1(...)` 中另行处理。结论：**不能声称 `q()` 就是光合产能公式**；它是「场采样 + 预览」的通用路径。
- 本项目落地口径：把通道 3 做成可配置的空间分布（强度/范围/角度/模式），让 `FieldLayer` 按同一通道插值显示，光合类型取该通道采样值产能；不复制 Macro shader，也不把 `q()` 当成能量公式。

### 20.3 食物/营养生成：`Food` 是定长对象池，营养在 `y2()` 中衰减

- `Food` 类（`ev_eabf830731079bf1380e1324e3f54236e4112978fa1147020c131661a1ca3c30`）只有 6 个方法与 7 个 float 字段：位置 `f727a/f728b`、质量/半径 `f729c`、速度 `d/f730e`、涂层 `f731f`。没有 PDE 场，也没有自动生成器。
- `Food.<init>()` 的静态引用（`ev_175682a9f9b0d3d96b57c222d5f0a80e48b2caaa182d550ff269f1406636f825`）只出现在 `SimulationWorld.<init>(Environment,boolean)`；构造函数（`ev_882a8622b3dda014f5c7badf3c99136dd213cb501dab44fa8603a61d76bc3e6c`）确认：
  ```text
  G2 = environment.Z
  f1322a = new Food[G2]
  f1324c = 0            // active count
  ```
  即启动时一次性分配固定食物池，非每 tick 凭空新建。
- `Food.a(Food)` 的引用（`ev_e26fdea06239f5b51b1b6659fe4f361e046139ddf1cb6891068d595f93f824e5`）出现在 `SimulationWorld.a(SimulationWorld)`（池复制）与 `SimulationWorld.y2(double)`（食物消失/池尾交换）。
- `SimulationWorld.y2(double)`（`ev_2c4014fe27663d7df1a80a319ee44fa26a5ca6fcbbc943a9a4cea7673693bbe8`）确认食物质量按 `f729c -= 0.006 * dt` 衰减；`<=0` 时与池尾交换并 `f1324c--`；吞噬/黏附细胞可改写 `f731f` 涂层；`environment.g0` 控制移动食物，`environment.e0` 控制触壁死亡/投影，`environment.s==0` 走圆形皿，`s==2` 走矩形皿，`N7.c(s)` 走隧道地形。
- 边界：Macro 的 `seekBar_food` 等控件决定的是初始池规模与投放形态；本项目已有五通道营养场，不引入第二套 `Food` 实体池。落地时把「食物密度/团块/层/涂层比例/移动食物」映射为营养场源项的确定型投放参数即可，并在文档里标明这是派生实现，不是 Macro 对象池的逐行移植。`A2()` 初始投放位置未逐行展开，保留为边界。

### 20.4 环境设置页控件：`EnvironmentEditorFragment`

- `EnvironmentEditorFragment.onCreateView()`（`ev_e0fd8444fd47a5c78d9ad8bf4a4831c307bd46aa8480c6f1eb3c74abdd0e90c2`；类清单 `ev_306f9d92ad69be61a20e6ae902c3433fc272b0ab080b844cdb213b84bff1a45a`）确认页面分组：
  - 食物：`seekBar_food / food_size / food_lump / food_lump_size / food_layer / food_coated_ratio`；
  - 理化：`salinity / viscosity / fricd / frics / radiation / radiation_spectrum / radiation_wave / dens / grav / grad / nitrates`；
  - 光照：`light / lightRange / lightAngle / lightT` + `bindLightPreview / bindLightSourceModeSpinner`；
  - 氧气：`bindOxygenPreview / bindOxygenRangeControl / bindOxygenDistributionSpinner`；
  - 开关：`add_random / die_edge / die_terrain / tweak / aging / adhesion_bias / mobile_food / fluid_dynamics / bacteria_layer / cell_translucency / light_dependent_vision`；
  - 部分控件在 `K.d(0,getActivity())` 为假时隐藏，说明 Macro 对不同实验条件有 UI 级裁剪。
- `Environment.f(Environment,boolean)`（`ev_d280626053e0d46e8b7642437e14c637723ec1c7113c84f30cb1dbdb932f38cf`）确认 `P0/Q0/R0` 与 `Y/Z`、`C0` 64×64 map、`J0/K0/L0/M0/N0` 空间模式参数一起被深拷贝，属于环境快照的一部分，不是临时 UI 数值。

### 20.5 落地边界与版本化结论

1. **可直接落地（不改变冻结 schema）**：环境设置页的 UI 与 `EnvironmentManager` 的运行参数；光场通道 3 的空间分布；营养源确定型投放；光合类型修正。它们只改变场初值/源项与视图，不改 `GNP1`、`dev_program`、tick 顺序或确定性规则（投放位置按 tick 派生，不使用全局 RNG）。
2. **只做编辑器草案/证据展示**：`Gene.f77x/f78x`、`E/F/G/H/I/J/K/v/w/x/y`、40 槽、Child1–4、信号 lane、95 算子。可在统一细胞编辑里编辑草案并标注来源，但不进入 `GNP1` 编码。
3. **需要规格修订才可做**：把 Macro 的逐基因刚度、子代质量、最小/最大连接数、细胞大小变成每个细胞真实运行的物理参数；把 `channel_count` 从 5 改成可配置；引入第二套 `Food` 实体池。这些要改 v1.0 玩法文档与 v2.1 §0.3/§11，不能藏在版本号里悄悄改。
4. **本项目当前发现的具体错误**：`OrganismManager._apply_environment_metabolism_ranges()` 把 `cell_type == 1`（体细胞）当光合、`== 2`（肌细胞）当化能；`CellVisualCatalog` 中光合细胞是 `type_id == 4`，硝化/化能是 `10`。这解释了用户「光合细胞在光场中不产能」的现象，v0.13.0 必须修正。

## 21. v0.13.0 落地记录与未决边界（2026-11-17）

### 21.1 已落地

1. `OrganismManager`：营养摄入类型改为 `ZYGOTE=0 / PHOTOCYTE=4 / NITROCYTE=10`，与 `CellVisualCatalog` 一致；光合读取光照通道 3，硝化/化能读取信号通道 4，异养读取营养通道 0。SmokeTest 断言光合细胞在光场中增能。
2. `EnvironmentField`：新增 `set_channel_values()`；写整通道前在 GPU 后端先回读当前场，避免过期 CPU 镜像覆盖其他通道；光照扩散系数 `DIFFUSION[3]` 改为 0，使空间照明保持为静态环境快照。CPU/GPU 使用同一常量，不改变五通道 schema。
3. `EnvironmentManager`：按 Macro 证据落地 `light_source_mode / light_range / light_angle_deg / light_falloff` 三种照明模式（全皿 / 边缘定向 / 中心点光）；新增 `food_spawn_amount / food_lump_radius / food_layer / food_coated_ratio`，其中 `apply_nutrient_sources(tick_index)` 用 tick 派生位置向营养场写入确定型团块源。`Main` 在 `advance_field_tick()` 前调用，不使用全局 RNG。
4. `FieldLayer`：32×32 场双线性上采样到 128×128，再由 canvas shader 连续渐变绘制，解决粗颗粒光场；仍为纯视图层，不写模拟状态。
5. `ToolCatalog` / `GameHUD` / `main.tscn`：原「培养基」升级为「环境设置」，16 行控件按食物 / 光照 / 氧气与温度 / 实验条件分组，带 Macro 来源 tooltip；`ScrollContainer` 防止内容溢出。
6. `DevEditorPanel`：右栏改为 26 项 Macro 发育字段草案，覆盖用户列出的细胞类型、黏附素、Child 1–4、分裂角度/质量/营养优先级/比例、颜色、骨架强度、细胞大小、连接数等，并保留 Gene 字段来源提示。`get_macro_draft()` 可读取；SmokeTest 断言编辑这些控件不改变 `Genome.hash()` 与 `dev_program`。
7. `SaveManager`：版本化追加 `environment_settings`，恢复顺序为「先设置 → 再恢复场通道」，避免刷新掉存档场。

### 21.2 仍不是等价移植 / 未决边界

- Macro 的 `Food[]` 是定长实体池；本项目仍用五通道营养场源项，不引入第二套实体池。`A2()` 初始投放位置未逐行展开。
- Macro 的 `Environment.q()` 参与场采样/感知/预览；本项目的光照通道只作为细胞能量输入与视图显示，没有把 `q()` 直接当光合公式。
- Macro shader 变体与 18+ 类型的对应关系未确认；本项目光场只显示全部通道强度，不模拟 Macro 的光谱/颜色效果。
- `channel_count` 可配置化、逐基因物理参数化、连接静息长度语义不一致、单帧 >12 tick 有效倍速，仍需规格修订后再做。
- 本次没有改 `GNP1`、`dev_program`、`schema_version`、tick 顺序或倍速规则；Macro 专有字段只作为 UI 草案存在。

### 21.3 验证

- 发布工程与 D 盘运行工程均 `SCRIPTS=47 FAILURES=0 EXITCODE=0`。
- D 盘同步 10 个脚本与 `main.tscn` 的 3 处语义改动，保留 MCP autoload、脚本 `.uid` 与场景节点 `unique_id`。
