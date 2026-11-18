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

## 22. GenomePreviewView 与 v0.13.1 发育预览（2026-11-17）

### 22.1 用户问题与静态证据

用户问「Cell Lab 基因组编辑页面上方那个可以看到细胞发育的页面是什么，能不能做一样的可视化效果」。为免按界面印象臆造，本轮重新从已提取目录 `analysis/cell_lab_apk_extract/tmp_macro` 重建 APK 并静态反编译（JADX 0.7.1，808 类 / 912 资源，APK 未执行；重建 zip 的 SHA256 为 `1f4593b864635335f92f975a09ec44a1198d648bfd204baeec12491735d86876`，与第 20 章的 `abfe6022…` 因 zip 容器元数据不同，解出的 DEX/资源树一致）。

- 类检索 `GenomePreview` 命中唯一类 `com.saterskog.cell_lab_enzymeglv.GenomePreviewView`（`ev_6ac4f8a4917f6afe05bdd029c2bba932cc5c1fcb0c4d0acd54a5efa2f8787cbc`；完整证据链接 `ev_6ad47d7a3bbfa2f4599587fadbbe0d914f421aa9fd24cd5fd0ad9d40c99b171c`）。
- 类清单（`ev_ef54d8a852cde2c2e2f1d62395c1c13f703fe576a03be9b30159bbe737c44912`）：7 个方法、12 个字段，包括 `onMeasure`、`onTouchEvent`、`requestRender`、`setPreviewLongPressCallback`、`setPreviewSelectionCallback`、`setOvernightRenderingSuppressed`；字段含 `s9 f892a`、`j4 f894c`、`GestureDetector f900k`、`float d/e/f/g/h`。
- 构造函数（`ev_b767a4f8b117ac1e4d422bcdc47f1ff1eca82bbede030477a29bc365e745f3a2`）：
  ```text
  f892a = new s9();
  setEGLContextClientVersion(2);
  f899j = PreferenceManager.getDefaultSharedPreferences(...).getBoolean("lock_preview", true);
  setEGLConfigChooser(8, 8, 8, 0, 16, 0);
  f894c = new j4(context);
  f894c.a0 = new i(5, this);
  setRenderer(f894c);
  setRenderMode(0);
  f900k = new GestureDetector(context, new m4(this, 0));
  ```
- 渲染器 `j4` 类清单（`ev_671207c154a5cb5043907153e39fb2444164ecea0bd6a48ee5734d43fb8f5b33`）持有 `SimulationWorld S`、`Gene[] V/X`、`FloatBuffer u0`、`ShortBuffer v0`，并有 `B(SimulationWorld, C, int, int): Bitmap`、`onSurfaceCreated`、`H(float[],…,Gene)` 等方法。

**结论**：那是**实时 GL 基因组预览**——用当前 `Gene` 起一个 `SimulationWorld`，由 `j4` 程序化绘制真实细胞发育，而不是一张静态图或时间轴示意图；触摸回调用于平移、缩放、选中细胞，`lock_preview` 默认 true 对应词条的「防止拖动/旋转/缩放预览」。

### 22.2 本项目派生实现（v0.13.1）

- 新增可复用 `scenes/ui/GenomePreview.tscn` + `scripts/ui/GenomePreview.gd`，嵌入统一细胞编辑左栏（节点优先，脚本只承载派生逻辑）。
- `set_program(dev_program, macro_draft)` 逐条派生状态：初始合子 → `DIVIDE` 按 `a=母细胞索引`、`b=角度×TAU/256`、`c=亲子间距` 生成子细胞并让亲子各偏半间距 → `DIFFERENTIATE` 改类型 → `LINK` 加连接；播放/暂停/上一步/下一步可观察每个发育阶段。
- 纯只读：不启动第二套 `SimulationWorld`，不写 `CommandBus`、环境场、GNP1、dev_program 或确定性 hash；颜色来自 `CellVisualCatalog.role_color()`。
- 与 Macro 的差别：Macro 用真模拟 + GL shader 与生物物理；本项目是 `dev_program` 的确定性可视化派生，保留了「看到自己编辑的细胞如何发育」的用途，不声称等价移植。

### 22.3 同批反馈修复

- 光场边缘：解析圆 + `fwidth()` 抗锯齿，shader 内画环，双线性采样跳过圆外格。
- 食物可见：`FoodLayer` 按营养局部对比度显示亮点，顶栏开关，投放量默认 0.12。
- 生态报告：`PanelChrome` 标题栏移到 `ChromeRoot` 索引 0（此前排在内容之后，按钮实际在底边），`visibility_changed` 同步状态；`AnalysisPanel` 6 tick 实时数字 + 30 tick 采样报告。
- 指令集：修正 `DIVIDE` 操作数提示，新增完整帮助文本与「单细胞 / 分裂×1/×2/×3」模板。
- 验证：发布工程与 D 盘运行工程均 `SCRIPTS=49 FAILURES=0 EXITCODE=0`。

## 23. v0.14.0 性能根因与食物实体池（2026-11-18）

### 23.1 「几个细胞也卡」的程序化测量

新增 `tools/ViewCostProbe.gd`，无头运行、不截图、不动鼠标，120 tick 平均（µs/tick）：

| 项 | 优化前 | 优化后 | 说明 |
| --- | --- | --- | --- |
| CPU 场扩散 | 18,923 | 1,335 | 真凶：每格新建 `[Vector2i...]` 数组 + 零平流仍做双线性 |
| 场纹理重建 | 2,006 | 1,961 | UPSCALE 4→2 + 6 tick 节流；此为显式 mark_dirty 成本，实际按节流摊薄 |
| 食物层重建 | 1,165 | 1,035 | 缓存格心，去每格 Vector2 分配；同样 6 tick 节流 |
| 模拟 1 细胞 | 93 | 95 | 与细胞数相关的部分极小 |

结论：卡顿是**固定成本**，与细胞数无关。Cell Lab 的流畅来自按需渲染与 O(1) 场采样，不是「细胞少」。

### 23.2 Cell Lab 代码级对照（本轮 REA 实际返回）

- `GenomePreviewView.<init>` 的 `setRenderMode(0)` = `RENDERMODE_WHEN_DIRTY`，按需渲染而非逐帧重画。证据 ID `ev_c248ea7a7bb218ac85dbd0596596dc87f8478d41dc2f14ba004635dbd665184f`。
- `Environment.q` 64×64 双线性（`min(63,...)`），无整场上采样/回传。证据 ID `ev_50171d8029e53948268a782d4b966caaeae0fc79a581088694cfc87df6ca93cc`。
- 构造期一次性预分配 `new Food[G2]` / `AdhesinLink[20]` / FloatBuffer/ShortBuffer，并含 "Too large timestep" 固定步长检查。证据 ID `ev_3d1b11f4044bcd77eb0ff6ff0bbe45c6402295acf13ce466d4a38da38e7dbae5`。
- **指令序列问题**：Cell Lab **有**分散式基因规则（`Gene.f(int)` 位掩码 `((1<<i)&f777q)`，证据 ID `ev_a2929d3348d54f79781e8dfd481e24e639a761c2aa355c6f4d6b71e55e7b9ce3`；dev_ 词条 "After N splits: daughter→M" 等，证据 ID `ev_f5f7e7c3ab07327dca44d05d2d3ec784656b8036fd36fb6da24dfe33e07dcb8a`），但是位运算+字段读、O(N) 常数极小。我们 `advance_development_tick` 每发育个体每 tick 一条指令，同样可忽略。**结论：dev_program 不是卡顿来源。**

### 23.3 食物实体池的规格修订与边界

按 §20.5 的要求，先修订 v1.0 §2.2 与 v2.1 §0.3 / §11，再落地 `FoodStore.gd`：定长 128 池、`spawn` 池内追加、`advance` 质量线性衰减 + 池尾交换、`to_payload/from_payload` 存档、涂层字段。实体由 `apply_nutrient_sources()` 的确定型位置派生，**能量真相仍是五通道营养场**，不进 hash、不改 schema。这是派生实现，不是 Macro `Food[]` 的逐行移植（衰减系数按本项目质量标度先取 0.11/s，v0.14.1 调慢为 0.012/s，见 §24.1）。

### 23.4 生态报告按钮的根因（反复修复的真正原因）

前两次只改了 `PanelChrome` 内部排序，但 chrome 在 `GameHUD._ready()` 安装，而 `AnalysisPanel._ready()` 在其后创建 `_body` 并 `add_child` 到面板 —— 内容成为 `ChromeRoot` 的兄弟节点，覆盖标题栏并抢走鼠标事件。v0.14.0 把 `_build_panel_chrome()` 改为 `call_deferred()`，等所有面板 `_ready()` 完成后再安装；`PanelChrome.install()` 加幂等保护。这是按钮「点了没用」的真正根因。

## 24. v0.14.1 反馈批次：产能 / 耗能诊断、黏附素即连接、参数校准（2026-11-18）

### 24.1 参数校准（按本项目标度，不是 Macro 常量移植）

- 光合摄入 `photosynthetic_intake_rate`：`0.02 → 0.08`。默认光强下原净收益接近 0，光合细胞难维持；0.08 使充分光照时接近异养效率（异养 0.05 × 呼吸效率），仍受光场值与 `DIFFUSION[3]=0` 约束，不改能量守恒。
- 食物质量衰减 `FoodStore.MASS_DECAY`：`0.11 → 0.012 / 秒`。按 0.2 初始质量估算，寿命由约 2 秒延长到约 17 秒（约 830 tick），与 Cell Lab `y2(double)` 的线性衰减 + 池尾交换形态一致；系数按本项目质量标度取值，不声称等于 Macro 的 0.006。
- 验证方式：SmokeTest 断言 120 tick 后食物实体仍在且质量 > 0.15，并断言光合速率字段为 0.08；不通过视觉截图判断。

### 24.2 黏附素即连接（GNP1 versioned append）

- `Genome.flags` 位 0 被赋予语义「生成黏附素」。`flags` 本就在 `GenomeCodec` 第 2–3 字节编码、本就在存档 schema 内，因此**不新增字段、不改冻结布局**；此前该位未使用，0 值行为完全不变。
- 执行点：`DevelopmentRules.execute_divide()` 在 `add_developed_cell()` 成功后按该位调用 `link_cells(parent, child, rest_length)`，rest_length 取亲子间距且至少为静息直径。`OrganismManager._apply_autonomous_lifecycle()` 对成熟后的自主分裂同样处理。`link_cells` 自带 `has_link` 幂等保护，模板里残留 `LINK` 指令不会重复建边。
- UI：`DevEditorPanel` 的「生成黏附素」勾选通过 `_sync_glue_flag()` 写入草案 flags；其余 25 个 Macro 字段仍只展示、不写 GNP1。状态栏明确提示该例外会改变基因组 hash。
- 后果边界：因 hash 覆盖编码后的 flags，置位基因组 hash 会变化；这是有意的新版本语义，不是确定性回归。SmokeTest 同时断言置位自动连接、清零保持旧行为、编辑器写入/清除位与 hash 变化。
- 与 Cell Lab 的关系：Cell Lab 的黏附素是基因位掩码驱动的物理连接生成；本项目只采纳「黏附素即连接」语义，并用既有 `flags` 位与 `dev_program` 表达，不复制 Gene 表或物理实现。

### 24.3 只读能量流诊断（不改变模拟数学）

- `CellMetabolism.redistribute_link_energy()` 增加可选 `diagnostics` 参数；仅在实际转账完成后把 `link_out[donor]` / `link_in[receiver]` 写入诊断缓冲，deltas 计算与 float 累加顺序完全不变；空参数时零额外数组分配。
- `OrganismManager` 新增 `_energy_flow` 五组 PackedFloat64Array：`production`（环境摄入 + 捕食获得）、`self_cost`（基础代谢 + 运动）、`link_out`（传输给其他细胞）、`link_in`（连接转入）、`predation_drain`（被捕食抽走）。每 tick 覆盖、分裂/死亡后索引仍稳定（`remove_cell` 只置 alive=0、不压缩数组）。
- `get_live_inspection()` 把这些字段与 `energy_flow_tick` 附加到只读诊断快照；`AnalysisPanel` 显示「产能 / 自身耗能 / 传输给其他细胞 / 连接转入」四项，捕食流失非零时追加一行。全部为派生读数，不写模拟状态、不进 hash、不进存档。
- 验证：SmokeTest 构造同一 org 的两细胞 + 非零 transfer rate，断言诊断缓冲与面板文本都出现转账数值。

## 25. v0.15.0 基因驱动发育与「能量高却不分裂」根因（2026-11-18）

### 25.1 现象与根因

用户截图：细胞能量 87.1230、光照 2.0，但不分裂；生态报告显示 `年龄 0 tick`、`个体 #0`、`活体个体 3`。

程序化定位（不是猜）：`register_zygote()` 先用 `initial_lifecycle_state()` 决定初始状态，随后调用 `OrganismStore.add_developed_cell()`，后者**无条件**把 `org_state` 写回 `STATE_DEVELOPING`。因此任何个体出生后都停在发育期，而 `_apply_autonomous_lifecycle()` 只处理 `STATE_MATURE` 个体——能量再高也不会分裂。旧模式靠 `advance_development_tick()` 逐条执行 `dev_program` 后才成熟，用户没写够指令就永久卡住；且分裂阈值 `autonomous_division_energy=0.16` 写死在管理器里，编辑器无从设置。

### 25.2 Cell Lab 代码证据（沿用已核对的静态分析）

- `Gene.b` = 分裂阈值，`Gene.c` = 分裂质量比，`Gene.d/e/f` = 分裂角，`Gene.i/j` = 母/子切换的分化树子槽；`e(double)` 触发条件含「能量超过 `Gene.b`、年龄 `o > 0.5`、连接数 ≤ `Gene.u[9]`、池有空位」，执行时复制母细胞、按 `Gene.c` 分配能量、母/子分别切到 `Gene.i/j`（见 APK 解析报告 §11.4 与分析文档 §23.2）。
- 黏附素由 `Gene.l` 等布尔开关在分裂时建连；Macro `AdhesinLink` 只确认结构，具体字段语义仍属未逐方法验证的边界。
- 结论：Cell Lab **没有逐 tick 指令序列**，分裂/分化/连接都由基因参数驱动。本项目据此做版本化追加，不复制 Gene 表或物理实现。

### 25.3 落地边界

- `Genome.flags` 位 1 = 基因模式；位 0 = 黏附素（v0.14.1）。清零时旧 `dev_program` 行为与 hash 逐位不变。
- 新字段 `division_mass` / `split_ratio` / `max_divisions` / `child_types` / `split_angles` 不进 GNP1 冻结二进制；走存档 `schema_version=2` 与 `CommandBus` 命令的 `genome_gene` payload，并显式混入 hash（仅基因模式）。
- `LINK` / `DIFFERENTIATE` 从编辑器与新基因组移除；`DevelopmentRules` 的 opcode 2 分支仅保留给 v0.14.x 及更早存档解码，旧存档里的 LINK 仍可执行，避免破坏回放。
- 发育预览改为按分裂次数派生状态：合子 → 逐次分裂（子代类型取 `child1–4`）→ 黏附素开启时显示亲子连接；不再有 LINK 阶段。
- 验证：SmokeTest 覆盖分裂质量滑块写 Genome、CommandBus/GNP1 往返、能量达标后 4 细胞 / 3 黏附连接、子代类型分化、预览连接数、schema v2 存档往返；`SCRIPTS=51 FAILURES=0`。

## 26. v0.16.0：Macro 表型字段落地与证据边界（2026-11-18）

### 26.1 已核对的代码证据（沿用 §20.1，未重新执行 APK）

- `GenomeEditorFragment.refreshControlsFromSelectedGene(boolean,boolean)`（`ev_3896a017015372230a52449ba233fdcaf267c026f0ef547286f68e74cdac85f3`）：`seek_prio → log(f773m/0.1)/log(99.99999850988391)`、`seek_stiff → f774n < 35 ? f774n/35 : 1`，`child1..4 → f778r/s/t/u`，两个分裂角 → `f770j/B ÷ TAU`。
- `Gene` 静态范围表（`CellLab_APK_解析报告.md` §11.4）：`z[7]/A[7] = 0.5..2`（第 7 个浮点参数），`w[11]` 中连接数选项上界含 20；`Cell.d` 是半径，`Gene.a[3]` 是颜色并在 `g(double)` 中向基因色插值；分裂触发条件含「连接数 `P ≤ Gene.u[9]`」（`e(double)`，见 §11.5）。
- 接触物理 `d(int)` 按 `Cell.a(6)` 的刚度做弹性排斥（§11.5）。
- **仍缺证据**：`Gene.f773m` 在运行时如何被消费（未逐行展开）；Macro 是否有独立的「最小连接数」控件（控件族里只确认 `spinner_types/cells` 与连接保持类布尔，未见独立 seekbar）。因此本版只把营养优先级与最小连接数记为**本项目版本化追加**。

### 26.2 落地口径（不冒充等价移植）

| 字段 | 本项目语义 | 默认等价点 | 证据等级 |
| --- | --- | --- | --- |
| `nutrition_priority` | 异养/化能摄能 ×(0.25+1.5p)，光合 ×(1.75−1.5p) | p=0.5 → 1.0 | 控件映射有证据，消费点未证实 |
| `cell_stiffness` | 接触分离系数 0.25+1.5s | s=0.5 → 1.0 | 控件与 `Cell.a(6)` 有证据 |
| `cell_size` | 逐细胞半径倍率 0.5–2，物理/共享弦/选中环共用 | 1.0 | `Gene.z/A[6]` 范围有证据 |
| `max_connections` | 阻断新增连接 | 4（默认，与 v0.15.0 一致） | `Gene.u[9]` 有证据 |
| `min_connections` | 分裂后按 cell index 升序补连 | 0（不补连） | 本项目追加 |
| `color_r/g/b` | 基因模式直接作为细胞基色，仅视图 | 类型色（覆写值 -1） | `Gene.a[3]` 有证据，取消插值属简化 |

### 26.3 冻结边界与验证

- GNP1 二进制布局、tick 顺序、单帧 12 tick 上限不动；新字段只走 `CommandBus` 的 `genome_gene` payload 与存档 `schema_version=3`（1–2 恢复填 1.0/-1 默认值）。
- 新基因字段显式混入 hash（仅 `FLAG_GENE_MODE` 置位）；`flags` 清零时 hash 与行为与 v0.15.0 逐位一致；颜色只改视图、不进 hash。
- 规格先行：v1.1 §5.3、v2.1 §0.3 / §11 已于代码前修订，风险表新增「逐细胞数组改变存档与回放」条目。
- 验证：新增 SmokeTest 覆盖编辑器写入/hash 边界、旧模式 hash 不变、预览 caption 与补连、逐细胞半径/刚度/颜色、颜色真实渲染到 `CellBase` Body、连接上下限、schema v3 与旧快照回退；发布与 D 盘工程均 `SCRIPTS=51 FAILURES=0`。

## 27. v0.17.0：多模式基因组、两子代与连接传递（2026-11-18）

### 27.1 证据来源与边界

- 用户提供的 Cell Lab Macro 基因组编辑截图（`clipboard-2026-11-18T07-40-17-965Z-d1506c5a.jpg`）可直接核对页面结构：模式选择/编辑、当前细胞类型、子代 1 / 子代 2 的模式与角度、分裂质量/反转、分裂角度/比例、营养优先级、RGB、黏附强度/长度/拉伸、骨架强度、细胞大小、连接上下限；上方为可交互的发育预览。
- 静态证据仍沿用 §20 / §25：`Gene.b/c/i/j` 对应分裂阈值、质量比、分化树子槽；`Gene.f773m` 只有控件映射、无运行时消费点；40 Gene 槽、行为总线全索引、特殊控件逐项语义未穷尽。
- 因此本版是**版本化追加**，不是 Cell Lab Gene 表的全量复制：只把截图可核对的字段做成模式槽，并把「一个模式只有两个子代」作为本项目明确规则。

### 27.2 现象根因：连接转出/转入恒为 0

- `OrganismManager.advance_physics_tick()` 旧代码 `rates.fill(default_transfer_rate)`，而 `default_transfer_rate = 0.0`；`CellMetabolism` 公式 `flow = rate[b]*energy[a] - rate[a]*energy[b]` 因而恒为 0。`link_out / link_in` 诊断本身正确。
- 修复不改变守恒公式：新增逐细胞 `_build_transfer_rates()`，新多模式基因组按 `cell_mode` 取模式 `transfer_rate`（默认 0.12）；空 modes / 非基因模式仍读 `default_transfer_rate = 0.0`，保持 v0.14–v0.16 回放。默认演示体改为多模式，用户打开即能看到能量流。

### 27.3 模式运行时与预览口径

- `Genome.modes` 保存逐模式类型、行为、两子代模式/类型、黏附/镜像/角度、阈值/比例、特殊控制与表型；不进 GNP1，经 `genome_gene` payload 与 `schema_version=4` 保存，仅非空时混入 hash。
- `CellArray.cell_mode / cell_mode_depth` 逐细胞派生。分裂后母细胞索引成为子代 1、新细胞成为子代 2；切到不同模式时该模式分裂层数从 0 开始，同模式连续分裂才递增。每个个体每 tick 最多分裂一次，顶层 `max_divisions + 1` 仍是细胞总数上限。
- `GenomePreview` 按同一口径只读派生状态，并把 `mode` 写入每个预览细胞；画布左键命中细胞后 `mode_selected(mode_index)` 信号让 `DevEditorPanel.select_mode()` 直接跳转。
- `DevEditorPanel` 的模式切换遵循「先提交当前槽，再载入新槽」；`stiffness` 等旧键保留为兼容别名，避免 v0.16 编辑器回归断裂。

### 27.4 验证

- 新增 SmokeTest：两子代模式与逐模式编辑不串数据、预览点击跳转、hash 兼容边界（空 modes / flags 清零仍保持旧 hash）、模式分裂与表型继承、跨连接能量守恒、`genome_gene` payload 往返、schema v4 与旧快照缺字段回退。
- 同步更新旧断言：默认演示体改为多模式、速度探针使用单细胞避免中途分裂、模式子代类型按集合而非固定索引校验、schema 版本从 3 升到 4。

## 28. v0.18.0：个体规模上限修订、连接数抑制分裂与端粒（2026-11-18）

### 28.1 证据与决策

- Cell Lab 官方 `CellWorld` 只有全局 `Cell[Environment.r]` 对象池与 `z` 活细胞计数；静态搜索没有 `Organism` / `Group` / `Colony` 一级实体，个体是 `Link` 连通分量，因此没有显式 per-organism max cell count。
- 规模约束来自：全局对象池空位、`Gene.u[9]` 连接数分裂条件 `P <= Gene.u[9]`、每细胞连接硬上限 20 / GLUE 5、端粒 `T ∈ {-1,5,10,20,40,80}`，以及寿命/浓度/拉断。Macro 的 `SimulationWorld` 尚未逐方法穷尽，只能说「现有证据未发现」。
- 用户确认修订基线：本项目取消「每个个体最多 8 细胞」硬上限，`max_cells_per_organism=-1` 无限，保留全局容量保护，并把连接数抑制分裂与端粒/谱系分裂次数放到细胞编辑。

### 28.2 实现口径

- `CellArray.max_cell_capacity` 默认 8000；`append_cell()` 与 `divide_cell()` 在容量触顶时拒绝。它是全局保护，不替代个体语义。
- `Genome.max_cells_per_organism`：`-1` 无限；旧命令/旧存档缺字段回退 `max_divisions + 1`。默认演示体显式为 4，保持 4 细胞/3 连接快照；新编辑器草案为 -1。
- 逐模式 `link_division_limit`：`-1` 关闭；`>=0` 时当前细胞连接数 `>=` 阈值即不进入分裂候选。旧模式缺字段回退 -1。Cell Lab 的 `<=` 语义与本项目的「达到即停」不同，按版本化追加记录。
- 逐模式 `telomere`：`-1` 无限或 5/10/20/40/80；`CellArray.cell_telomere` 按细胞保存。初始细胞取当前模式值；每次分裂母子同减 1，归零时双方死亡并记死因 5「端粒耗尽」。
- 新字段不进 GNP1；走 `genome_gene` payload 与 `schema_version=5`，旧档逐字段回退；只在基因模式混入 hash，flags 清零保持旧 hash。

### 28.3 验证

- SmokeTest 覆盖：个体无限生长超过 8、全局容量拒绝、连接数抑制分裂、有限端粒递减与归零死亡、`-1` 无限端粒、schema v5 新旧回退、编辑器控件写入与 hash 边界。
- 验证口径：发布工程与 D 盘工程均 `SCRIPTS=51 FAILURES=0 EXITCODE=0`。

---

## 29. v0.19.0：半径-能量低通落地与视图重建热点优化

### 29.1 证据与决策

Cell Lab `CellWorld.f(double)` 已证实（§2）：半径 `d` 不随能量直接跳变，而是对 `d²` 做一阶低通，稳态 `d_target = sqrt(w) / 20`。用户实测本项目「细胞大小不随能量增加、刚分裂子细胞偏小」，与 Cell Lab 机制对照后确认是机制缺失，非贴图或缩放 bug。

15 细胞链卡顿查证：Cell Lab 的 `g()` 空间索引每对只算一次、物理与渲染共享 `A[]` 接触几何，且渲染为原生 OpenGL 顶点缓冲；本项目在 `CellSceneRenderer._build_shared_chords` 用字符串 `"%d:%d"` 做 pair key、每细胞固定 64 点解析圆，GDScript 层逐细胞重建产生超线性开销。程序化探针（`tools/ViewCostProbe.gd`）基线：15 细胞 view 重建 1845 µs/帧、30 细胞 4545 µs/帧。

### 29.2 实现口径

- 半径低通：`CellArray` 新增 `cell_radius_baseline`（基因表型）与 `cell_energy_scale`（能量派生因子）；`cell_radius_scale` 保持为「有效倍率 = baseline × energy_scale」，物理/渲染/分裂间距的所有既有读取点不变。
- 每 tick 在 metabolism 阶段调用 `_apply_energy_radius_relaxation(dt)`：以该细胞所属模式的 `division_mass` 作参考能量 `E_ref`，`target² = clamp(E / E_ref, min², max²)`，`s² ← s² + (target² − s²)·rate·dt`，`s = sqrt(s²)`。默认 rate=5、min=0.5、max=1.0，对应 Cell Lab 一阶低通与死亡半径比例。
- 仅 gene_mode 生效；非基因模式与 `energy_radius_growth_enabled=false` 保持 v0.18 固定表型倍率。纯标量、固定细胞索引顺序、不写 RNG；GNP1、tick 顺序、单帧 12 tick 上限不动。
- schema_version=6 保存两个新数组；旧档缺字段时 baseline=旧 `cell_radius_scale`、energy_scale=1.0，半径逐位不变。数组纳入 `get_state_hash()` 保证回放确定性。
- 视图热点：`_build_shared_chords` 的 pair key 由字符串改为整数打包 `low*8001+high`；`CellView` 新增 `outline_segments` 导出，默认 64 保持独立实例旧行为，`CellBase.tscn` 设 48 降低实际场景每帧弦裁剪与顶点写入成本。

### 29.3 验证

- SmokeTest 覆盖：初始 baseline×factor、低能量平滑趋向 `sqrt(1/4)=0.5` 且首 tick 不跳变、能量回升可逆、开关关闭冻结因子、schema v6 新旧回退、状态 hash 确定性。
- 视图优化后探针：15 细胞 1453 µs/帧、30 细胞 3707 µs/帧，较基线下降约 20%；模拟 tick 成本不受影响。
- 双工程验证：发布工程与 D 盘工程均 `SCRIPTS=51 FAILURES=0 EXITCODE=0`。
- 证据边界：性能数字来自 headless CPU 回退与同步循环，GPU 实际帧率与 `_process` 逐帧收益需窗口环境复核。

---

## 30. v0.20.0 / v0.21.0：分裂倍增与半圆出生形状、发育预览分裂指示器

### 30.1 查证结论

- **倍增**：Cell Lab `CellWorld.e(double)` 对**每个细胞独立判定**分裂，无 per-organism cooldown，同一 tick 所有成熟且能量达阈值的细胞同时分裂 → 细胞链按 1/2/4/8 倍增。本项目原实现有两处 per-org 闸门（个体级 cooldown=300、每体每 tick 一次分裂），造成 1/2/3/4 线性增长。用户实测「分裂后细胞不再分裂」的根因即在调度层，非能量传递。
- **半圆**：`e(double)` 出生时母子各沿分裂轴偏 `0.1r`（中心距 `0.2r`），**半径保留母半径**、速度增量为 0.0（零力）；因两圆高度重叠、接触弦近圆心，渲染成两个贴靠半圆；分离来自下一 tick 的接触排斥 `d(int)`（力 ∝ 相交面积）。本项目原出生间距 `max(14, 2r)=14` 正好相切，从无重叠阶段，故看不到半圆。
- **分裂指示器**：Macro `GenomeEditorFragment.onCreateView()` 控件族含 `checkbox_show_split_indicators`（分析文档 §20.1）；`GenomePreviewView` 是持 `SimulationWorld`/`Gene[]` 的实时 GL 预览（§22）。分裂角来自 `Gene.d/e/f`、质量比 `Gene.c`。

### 30.2 实现口径

- **per-cell 分裂调度**（v0.20.0）：`CellArray` 新增确定性状态 `cell_division_tick`（上次分裂 sim_tick，进 hash/存档）；候选阶段用逐细胞 cooldown 取代 per-org 闸门，保留单细胞首帧宽限；分裂后母子各重置 tick。schema v7（旧档填 -2）。GNP1、tick 顺序、单帧 12 tick 上限不动。
- **半圆出生形状**（v0.21.0）：出生间距改为 `max(0.5, 0.2·r·scale)`，母子各沿分裂轴偏 `0.1r`（中点在原母细胞位置），半径当帧保持母半径 → 重叠半圆；连接静止长度仍为 `2r`。分裂在 metabolism 阶段（碰撞之后），下一 tick 接触排斥弹开至 `2r`。
- **发育预览指示器**（v0.21.0）：`GenomePreview.show_split_indicators` 导出（默认 true，对应 Macro 控件）；三条状态派生路径（多模式/基因模式/旧指令）均记录每次分裂的 `angle` 与亲子索引；画布叠加垂直分裂轴的切面线（黄）与母→子方向箭头（橙）。纯绘制，不写 CommandBus/field/hash/模拟状态。新增只读 `get_split_count_at` / `get_split_angle_at`。

### 30.3 验证

- SmokeTest `OK v0.21.0`：倍增经过 2/4/8；出生帧 `dist/contact=0.1`（即 0.2r）且半径保持 1.0；下一 tick 排斥拉开。基因预览测试断言指示器数量随分裂递增、角度在 0..TAU。双工程 `SCRIPTS=51 FAILURES=0 ERRORS=0`。
- 探针 `HalfCircleProbe.gd`：`BIRTH_FRAME dist=1.4 contact=14.0 ratio=0.1`；`NEXT_TICK dist=14.0 pushed_apart=true`。`DivisionProbe.gd`：1→2→4→8→16→32、能量守恒。
- 证据边界：静态反编译 + headless CPU 回退探针；半圆持续帧数由接触排斥速度决定，未在渲染层加动画；GPU 实际观感需窗口环境复核。

---

## 31. v0.22.0：去掉 depth 分裂闸门（残余限制修复）

### 31.1 现象与根因

用户实测细胞能量 2.0892（阈值 0.05 的 40 倍）、连接 2 却不分裂，只有链末端新生细胞分裂，呈线性增长。`GateProbe.gd` 复刻候选筛选逐细胞报告：所有成熟细胞被 `depth=1>=1` 挡住，旧行为卡在 4 细胞。

根因：v0.20.0 移除 per-organism cooldown 串行锁时遗漏了第二套独立闸门——`_apply_autonomous_lifecycle` 的 `depth >= mode.max_divisions` 检查 + 执行阶段母细胞 `depth+1`。对 M1→M1+M1 自增殖模式（`normalized_mode` 默认 `max_divisions=1`），每个细胞分裂一次后 depth=1 永久锁死，只剩 depth=0 的新子细胞能分裂。

### 31.2 查证与修复

Cell Lab `e(double)` 触发条件（§4/§28、协作规格 §3.2）无 mode depth 闸门；分裂次数由端粒 `T∈{-1,5,10,20,40,80}` 控制，`-1` 无限、母子同减、归零死亡。本项目 `cell_telomere`（v0.18）已承担该角色，depth 闸门是本项目额外加的限制，按用户决策去掉以对齐 Cell Lab。

- 删掉候选阶段 `depth >= max_divisions` 检查；母/子分裂时 depth 不再累加（继承原值，自增殖恒 0）。字段/存档/hash 兼容，不升 schema。
- `GenomePreview` 三条派生路径同步去掉 depth 闸门与 depth+1，预览步数仍由顶层 `max_divisions` 约束。
- 端粒继续作为分裂次数限制。GNP1、tick 顺序、单帧 12 tick 上限不动。

### 31.3 验证

- SmokeTest `OK v0.22.0`：单模式 max_divisions=1 自增殖突破旧上限达 ≥8、depth 恒 0；双工程 `SCRIPTS=51 FAILURES=0 ERRORS=0`。
- GateProbe：修复后 tick=3 为 8 细胞（修复前 4）、tick=55 为 128 细胞。
- 证据边界：能量不足时仍按门槛停分裂（GrowthProbe 显示真实代谢下产能弱属参数平衡）；静态反编译 + headless CPU 探针，GPU 观感需窗口复核。

---

## 32. v0.23.0：全量反编译落地与发育预览真实模拟内核（2026-11-19）

### 32.1 全量源码落地（本轮新增证据等级：方法体全文）

此前所有结论均来自 MCP 逐方法片段读取。本轮把两个 DEX **全量反编译成 Java 文件**落地本地，逐行精读完整方法体：

- 官方版 `cell-lab-zh/classes.dex` → `decompiled_zh/`，33 个核心类全部 `OK`，其中 `CellWorld.java` 199,230 B、`Gene.java` 19,764 B、`Cell.java` 18,492 B、`n.java`（预览渲染器）6,067 B。
- Macro 版 `cell-lab-macro-beta-latest/classes.dex` → `decompiled_macro/`，554 个核心类全部 `OK`，其中 `SimulationWorld.java` 2,492,398 B、`GenomeEditorFragment.java` 610,250 B、`J4.java`（预览渲染器）46,462 B、`GenomePreviewView.java` 8,117 B。
- 反编译中间产物位于 `analysis/cell_lab_apk_extract/decompiled_zh|macro/`，已被 `.gitignore` 覆盖，不入库。
- 工具链：`D:\Tools\JADX-MCP\jadx-headless-mcp-0.7.1-all.jar`，通过 stdio MCP `tools/call` → `get_class_source({class_name, max_bytes, smali_fallback:true})` 批量导出；驱动脚本 `mcp_export.py` 同目录（本地工具，不入库）。

### 32.2 发育预览：完整机制（对照 v0.21 派生实现）

**承载链路**：`GenomePreviewView`（GLSurfaceView）→ `n`（官方）/ `j4`（Macro）渲染器 → 持真实 `CellWorld`/`SimulationWorld`。

**模拟器初始化**（官方 `n.a(float[])`，Macro `j4.e` 同构）：
- `Environment` 特化：`bg=true`（无食物实验室）、`c=0`（无突变）、`r=128` 容量、`k=1.0`（皿半径）、`g=75`（粘度）、`z=1`（浓度补给）；Macro `g=2.5`、`k=2.5`。
- 合子构造：`cell.I=v`（编辑器传入 Gene[]），扫描 40 槽取 `p==true` 者作 `D`；`w=0.288`（非合子）或 `0.36`（ZYGOCYTE）；LIPOCYTE 额外 `S=1.8`；`d=sqrt(w/400)`；`J[0..2]=Gene.a[3]` 颜色；`p=1.0`、`T=-1`、`U[0..3]=0.01`。
- **固定种子 `setSeed(1337L)`**，每帧跑 `u/0.02` 步，每步 `a(false,1.0)`（dt=0.02）；`this.t` 缓存已完成结果，Macro 额外 `Z/V==X/Y>=0` 断点续算 + 6 秒超时保护。

**分裂指示器 `j4.I(float[])`（Macro，`show_split_indicators` 对应，逐方法等价）**：
- 遍历 `simulationWorld.S5[0..U5]`；条件 `cell!=null && cell.s!=null && 0<=D<len`。
- 分裂轴 `d4 = (镜像 f1 ? -1 : 1) * gene.f770j + cell.y0`（朝向）；方向 `(cos,sin)`。
- 圆点半径 `fMax = max(0.006, cell.q0 * 0.27)`；偏移基准 `f2 = cell.q0 + 0.42*fMax`。
- 质量比 `ratio = clamp(gene.f769i, 0.1, 0.9)`；两子中心距 `f3=f2*2`，`f4=(1-ratio)*f3`，`f5=ratio*f3`；两标记位于 `center ± dir*(对应距离)`。
- 非合子：画 2 个圆点，颜色取 `child1=f778r`、`child2=s` 槽的 Gene.a[3]。
- 合子 ZYGOCYTE：第二分裂轴 `d12=(镜像? -1:1)*gene.B + y0`，第二比例 `ratio2=clamp(gene.C,0.1,0.9)`，`f10=1.5*fMax`，画 4 个圆点（child1..4 = `f778r/s/t/u`）。
- 关闭 GL depth/blend 后与细胞、连接、纤毛同帧绘制（`e()` 末段依次 `U/V/S/W/Z` 后调 `I()`）。

**交互**（`GenomePreviewView.onTouchEvent`）：单指拖动平移、双指缩放（`|log(scale)|<0.3` 才生效，中心锚定）、`lock_preview` 默认 true 锁交互、单击命中细胞取 `D` 槽回调。

### 32.3 分裂 `CellWorld.e(double)` 完整条件链与动作（全文精读）

条件（全真）：`有效能量 > Gene.b && o>0.5 && P<=u[9] && p>0.2 && !死亡 && 类型!=GAMETE && 池有空位`。
- 有效能量：LIPOCYTE 为 `0.072+((w+S)-0.072)/2.088*0.288`，其余 `w`。
- 位置：分裂轴 `d7=k+(镜像?-1:1)*Gene.d`；`d8=0.05r*2=0.1r`；母子各偏 `±d8` 并叠加 `sin(z*10.34+43)*1e-7` 级微扰；**速度增量系数 0.0（零力）**。
- 能量：`w_child=Gene.c*Σ - 子代类型成本 v`，`w_mother=(1-c)*Σ - 母类型成本 v`，再各减 `max(0,v[6]-1)*0.054`。
- 分配：`U[0..3]` 按 c / (1-c) 各 +1e-4；`S=0`；`X/Y` 按比；`p` 各半；`o=0`；朝向 `k` 加 `Gene.e/f`；镜像 `y` 异或 `Gene.q/r`；`m±1`。
- 旧连接：`J[20]` 暂存后按 `Gene.m/n` + 点积 `d14` 阈值 ±0.2（含中间带极值索引）重分配母子，双向重建并换算到各自新朝向，上限 20。
- 新黏附 `Gene.l`：母子间建双向 Link，`b=true`、刚度 `Gene.h`、长度 `cell.a(5)`（Gene.v[5]）。
- 分化树：`cell.D=Gene.i`、`cell2.D=Gene.j`。
- 端粒 `T!=-1` 时母子同减，`<=0` 双亡。
- FLAGELLOCYTE 后向连接 `cos(link.c)<-0.8` 判死。
- 末尾能量 clamp 0.36（LIPOCYTE 超出转 `S`，上限 1.8）。
- **倍增根因（再确认）**：`while(i4<z)` 逐细胞判定，池尾 `cell2=x[z-1]` 复制后 `z++`，新细胞当帧 `o=0` 不分裂，下一 tick 全体达标者同时分裂 → 1/2/4/8。

### 32.4 物理与 3000 细胞性能：代码级机制清单

- 两阶段 tick：`a(boolean,double)=b(z,d)[update1]+a(d)[update2]`；`dt=0.02*d`；阶段锁 `X`。
- update1：`i(dt)` 食物 → `k()` 补细胞 → `f(dt)` 位置/半径 → `e(dt)` 分裂 → `j()` 回收 → `g()` 网格 → `d(dt)` 食物 → `h(dt)` → `i()` → `c(z,dt)` 逐细胞 `d(i)` 感知/接触 → `c(dt)` 速度积分 → `h()`；update2：`g(dt)` 代谢/遗传 → `b(dt)` 4 子步信号。
- 空间哈希：`Z=min(206,k/0.03-0.1)` 偶数；每格 `aV[格]` 上限 203 细胞、`ba/bb/bc` 上限 404 气味；每细胞按包围盒写 4 格（K/L/M/N，重复置 -1）；查询只处理 `index>i`，配对唯一。
- 接触排斥：`d50`=Heron 相交面积；`dA=(d50*500)/((0.5/a6_i)+(0.5/a6_j))/中心距`；力写 `cell.g/h` 累加器，经 `c(dt)` 做 `力/质量` 积分；约化质量 `25*w_i*w_j/(w_i+w_j)` 按连接数较大者分摊；弹性项 `1+2*disp²/0.0036`；皿壁 `dA2=(500/s)*overlap²*2*a6`。
- 阻尼：`f()` 里半径低通 `d += ((w/400)/d - d)*0.5*10*dt`（`o>5dt` 才启动、上限 0.03）；`c(dt)` 里粘性限速 `d9=clamp(1-q*3,0,4)`。
- 构造期一次性预分配 `Cell[d]/Food[aa]/残骸[(d+3)/4]/Link[20]` 与 Float/Short/ByteBuffer，运行期零增长。
- 渲染：CPU 构建共享相交弦多边形（`u.compareTo()` 按角度排序 + 遮挡剔除）+ 片元 `discard(ds>col.a²)` 解析圆裁剪；`RENDERMODE_WHEN_DIRTY` 按需绘制。
- **对 Godot 3000 细胞的落点**：性能瓶颈不在细胞数而在宿主侧固定成本（已测场扩散 18,923→1,335µs）；真复刻需 SoA + 固定池 + 空间哈希 + 按需渲染 + O(1) 场采样，而非场景树逐 CellView 实例。

### 32.5 本轮决策（用户确认）

1. 本轮先做**发育预览**。
2. **接受引入第二套真实模拟内核**（预览独立跑 Cell Lab 式物理/分裂，固定种子）。
3. 底层**全面可改**（含 tick 阶段/数据布局），GNP1/tick顺序/CommandBus/单写者可按需调整。

### 32.6 预览内核映射（本项目 modes → Cell Lab Gene 槽）

- 每个 mode → 一个 Gene 槽：`s=cell_type`、`b=division_mass`、`c=split_ratio`、`d/e/f=child2_angle/split_angle` 对应弧度、`i/j=child1_mode/child2_mode`、`l=make_glue`、`h=adhesion_strength*35`、`a[3]=(color_r,g,b)`、`v[6]=cell_stiffness`。
- 合子初始槽 = `initial==true` 的 mode；能量 0.288（无食物实验室仍需产能，PHAGOCYTE/PHOTOCYTE/DEVOROCYTE/GLUEOCYTE 的 `s.s=true` 走 `Q+=280*d²*dt`）。
- 分裂：`w>division_mass`、`o>0.5`、连接数<=max_connections、`p>0.2`、池有空位；母子各偏 `0.1r`、能量按 split_ratio 分；`D=child1_mode`（母）/`child2_mode`（子）；合子画 4 指示器（child1..4），非合子画 2。
- 半径低通、接触排斥、连接弹簧按 §32.4 原式。
- 内核为 `RefCounted`、无 `class_name`、固定种子、不写 CommandBus/field/hash/save，纯只读派生，保证主模拟确定性不受影响。
