# Cell Lab / Macro 界面与实验条件 · 资源层词条证据

日期：2026-11-15
方法：Apktool 3.0.3 解码 `resources.arsc`（`d -f -s`，跳过 dex），比对 `res/values/` 与 `res/values-zh/` 下 `strings.xml`、`arrays.xml`；REA / JADX 0.7.1 用于类清单核对。**两个 APK 全程未执行**。
样本：
- 官方汉化 `cell-lab-zh.apk` → `%TEMP%\genesis_official_res\`（459 个资源键）
- Macro `cell-lab-macro-beta-latest.apk` → `%TEMP%\genesis_macro_res\`（1365 个资源键，Macro 独有 935 个）

本文只记录**资源层可观测事实**（词条名、中英文文案、数组顺序），不推断运行期数值。所有「借鉴条款」见 `docs/创生模拟器_沙盒版人工生命系统设计文档_v1.1_合并稿.md`。

---

## 1. 培养条件 / 时间模式

### 1.1 两版共有的 4 档模式

`res/values/arrays.xml` 的 `<string-array name="modes">`，**官方与 Macro 完全一致**：

| 索引 | EN | ZH（`values-zh`） |
| --- | --- | --- |
| 0 | Freeze | 冻结 |
| 1 | Observe | 观察 |
| 2 | Incubate | 培养 |
| 3 | Slow observe | 慢速观察 |

相关词条：

| 键 | EN | ZH |
| --- | --- | --- |
| `temp_menu_title` | Substrate temperature | 基底温度 |
| `settings_slow_motion` | Microscope slow motion | 显微镜慢动作 |
| `settings_slow_motion_description` | The slower simulation is not exactly equivalent to the normal speed simulation. | 较慢的模拟并不完全等同于正常速度下的模拟。 |

教程文本（`arrays.xml` 的 `tut_text_*` 条目）说明这组档位是以「温度」为叙事包装的模拟推进控制：

- "Our microscope also has a system for controlling the temperature of the substrate. Turn up the temperature to the \"Observe\" setting where the cells live but move slowly."
- "We want to incubate the substrate for a while so our cells attain an equilibrium. Increase the temperature to the \"Incubate\" setting."
- "We put a mutagen in the substrate ... Freeze the substrate before doing this."
- `tut_title_1` 含 "Temperature" / "Incubation" 两节。

**证据边界**：各档对应的实际 `dt` 倍率、tick 频率、是否改变积分步长，资源层没有给出数值；`settings_slow_motion_description` 反而明确提示慢速档「不等价于正常速度」。因此只能借鉴**档位划分与交互语义**，不能照搬数值或假定它满足确定性。

### 1.2 Macro 独有的「过夜培养」

| 键 | EN | ZH |
| --- | --- | --- |
| `overnight_incubation` | Overnight incubation | 过夜培养 |
| `overnight_renderless_status` | "Plate age: %1$,.1f %2$s Cells: %3$d" | "培养皿时间：%1$,.1f %2$s 细胞：%3$d" |
| `overnight_return_to_plate` | Return to plate | 返回培养皿 |
| `public.xml` 中的 drawable | `temp_overnight` | — |

配套：`log_intervals` 数组 = `none / 12m / 1h / 5h / 25h / 125h / 625h`（统计采样间隔）；`log_sub_stat` = Log substrate statistics to file；`setting_keep_from_sleeping` = 长模拟时保持设备唤醒；`setting_keep_from_sleeping` 的中文提示「请记得接上充电器」。

**判断**：`overnight_renderless_status` 的键名含 `renderless`，且状态栏只暴露「培养皿时间 / 细胞数」，与「关闭渲染的批量快进」一致；但这是键名推断，未经运行期验证。

### 1.3 冷冻库 / 样本（两版共有）

`freezer_new_plate`（新培养皿）、`freezer_relabel`、`freezer_bad_name`、`freezer_unfrozen_age`（解冻后年龄）、`freezer_long_press`、`email_substrate_title`（Frozen sample from Cell Lab）、`sample_info_age`（基底年龄）、`sample_info_cells`、`sample_info_food`、`sample_info_save_title`。

---

## 2. 工具系统

### 2.1 官方版 5 件（`tool_*` 键全部列出）

| 键 | EN | ZH |
| --- | --- | --- |
| `tool_cell` | Cell synthesizer | 细胞合成器 |
| `tool_remove` | Cell removal | 移除细胞 |
| `tool_move` | Optical tweezers | 光学镊子 |
| `tool_add` | Cell boost | 细胞强化 |
| `tool_info` | Cell diagnostics | 细胞诊断 |

### 2.2 Macro 版 10 件（在官方 5 件之外新增 5 件）

| 键 | EN | ZH | 归属 |
| --- | --- | --- | --- |
| `tool_adhesion_extruder` | Adhesion extruder | 黏附连接工具 | Macro 新增 |
| `tool_inject` | Genome injector | 基因组注射器 | Macro 新增 |
| `tool_signal_inject` | Signal injector | 信号注射器 | Macro 新增 |
| `tool_substance_inject` | Substance injector | 物质注射器 | Macro 新增 |
| `tool_color_inject` | Color injector | 颜色注射器 | Macro 新增 |

另有非 `tool_*` 前缀的编辑能力：

| 键 / 来源 | EN | ZH |
| --- | --- | --- |
| `popup_title_select_tool` | Select tool | 选择工具 |
| `saved_selection_tool` | Select | 选择 |
| `saved_selection_rotate` | Rotate selection | 旋转选择 |
| `terrain_brush_radius` | Terrain brush radius | — |
| `patch297_previous_release` | "Added separate terrain brush and eraser buttons" | — |
| `patch295_previous_release` | "Selection tools now use floating Capture/Paste controls" | — |

更新日志中还有「黏附连接工具拖动手柄」「选择框高亮」「旋转视图只保留旋转控件和关闭」等交互细节。

---

## 3. 显微视野

Macro 独有的一组镜头与视图控制（官方版无 `lens_*` / `micro_camera_*` 键）：

| 键 | EN | ZH |
| --- | --- | --- |
| `lens_menu_title` | Microscope lens | 显微镜镜头 |
| `lens_filter_title` | Microscope lens filter | 显微镜镜头滤镜 |
| `lens_button_label` | Lns | 镜头 |
| `lens_filter_fov` | Field of View | 视野 |
| `lens_filter_eyepiece` | Eyepiece | 目镜 |
| `lens_filter_fused` | Fusion Lens | 融合镜 |
| `lens_filter_sepia` | Polarized Lens | 偏振镜 |
| `lens_filter_chromium` | Chromium (By Noirmancer) | — |
| `lens_filter_default` | Default | 默认 |
| `eyepiece_magnifying_lenses` | Magnifying lenses | 放大镜片 |
| `micro_camera_title` | Micro Camera | 微型相机 |
| `micro_camera_center` | Center | 居中 |
| `micro_camera_center_zoom_out` | Center + Zoom Out | 居中 + 缩小 |
| `micro_camera_rotate_view` | Rotate view | 旋转视图 |
| `micro_camera_capture` | Capture | 捕获 |
| `micro_camera_plate` | Plate thumbnail | 培养皿缩略图 |
| `micro_camera_organism` | Organism thumbnail | 生物体缩略图 |
| `micro_camera_organism_editor` | Organism thumbnail (editor) | 生物体缩略图（编辑器） |
| `micro_camera_organism_plate` | Organism thumbnail (plate) | 生物体缩略图（培养皿） |
| `toast_zoom_max` | "Screen width now just 1 nm, can't resolve shorter distances with electron microscope." | 屏幕宽度现在只有 1 nm，电子显微镜无法分辨更短的距离。 |
| `wallpaper_microscope` | Microscope background | 显微镜背景 |
| `setting_preview_lock` | Lock genome preview | 锁定基因组预览 |
| `setting_preview_lock_summary` | "Prevents panning, rotating, or pinch-zooming the genome preview. Genome parameters, timeline controls, and editing remain available." | 防止拖动、旋转或双指缩放基因组预览。 |
| `wallpaper_microscope` | Microscope background | 显微镜背景 |

图例相关（`patch285/287/288/290_previous_release`）：显微镜可视化图例固定在左上 / 右侧、不预留屏幕空间、多个可视化图层启用时不裁切、锚定在 Genome 标签下方。词条：`distribution_legend_density / gravity / light`（密度 / 重力 / 光照）。

---

## 4. 培养基设置（Substrate / Environment）

### 4.1 官方版已有（基线）

`substrate_density`、`substrate_density_gradient`、`substrate_fricd`（动摩擦）、`substrate_frics`（静摩擦）、`substrate_gravity`、`substrate_viscosity`、`substrate_light_amount`、`substrate_light_range`、`substrate_light_speed`（光照方向变化）、`substrate_salinity`、`substrate_nitrates`、`substrate_radiation`、`substrate_nutrients`、`substrate_nutrient_size`、`substrate_nutrient_lump`、`substrate_nutrient_lump_size`、`substrate_aging`（细胞衰老）、`substrate_kill_edge`、`substrate_kill_terrain`、`substrate_tweak_mutations`（Only point mutations）、`substrate_contaminate`（随机细胞污染）、`substrate_action_reload`、`substrate_action_sterilize`、`substrate_help_title`、`log_sub_stat`。

### 4.2 Macro 新增（分组）

| 分组 | 键 | 中文 |
| --- | --- | --- |
| 氧气 | `substrate_oxygen`、`substrate_oxygen_min/max`、`substrate_oxygen_range_title`、`substrate_oxygen_distribution`、`environment_oxygen` | 氧气 / 最小·最大氧气 / 氧气梯度覆盖范围 / 氧气分布 |
| 昼夜与光源 | `environment_day_phase`、`environment_day_rate`、`environment_day_help`、`substrate_light_angle`、`substrate_light_source_mode`、`light_source_modes` | 昼夜相位 / 昼夜变化速率 / 光源（默认·直射光线·单点光源·中心光源·环形光源） |
| 光照范围 | `environment_range`、`environment_coverage_values` | 最小值 / 最大值与覆盖范围 |
| 食物分布 | `environment_food`、`environment_food_help`、`environment_distribution` | 食物 / 分布（团块中心与扩散范围） |
| 密度与重力 | `environment_density_distribution`、`environment_density_gravity`、`environment_gravity_direction`、`environment_gravity_help` | 密度分布 / 密度和重力 / 重力方向 |
| 物理 | `environment_physics`、`environment_snap_values`、`environment_default` | 黏度和摩擦 / 吸附取值 / 默认 |
| 隧道地形 | `environment_terrain`、`environment_terrain_generate`、`environment_terrain_branchiness`、`environment_terrain_holes`、`environment_terrain_smoothness`、`environment_terrain_wall_count`、`environment_terrain_wall_size`、`environment_terrain_reroll`、`environment_terrain_clear` | 隧道 / 生成 / 曲折度 / 腔室 / 平滑度 / 墙体数量 / 墙体厚度 / 重新随机种子 / 清除 |
| 颜色与总览 | `environment_options`、`environment_overview`、`environment_natural_plate_color`、`environment_wall_color`、`environment_color_reset` | 培养基选项 / 培养皿总览 / 自然培养皿颜色 / 墙壁颜色 / 重置 |
| 统计 | `substrate_statistics`、`substrate_load_diagnostic_*`、`sample_info_gene_pool` | 基底统计 / 基底加载诊断 / 基因池 |
| 黏附经济 | `adhesion_bias`、`substrate_help_adhesion_bias` | 黏附优势：1/2/≥3 条普通黏附分别使基础代谢 -25%/-30%/-35%；临时抓附与皿壁连接不计入 |

`oxygen_distributions` 数组：Top to bottom / Bottom to top / Left to right / Right to left。

`environment_terrain_confirm_text`："Generating terrain will sterilize the plate."（生成地形会对培养皿灭菌）——说明地形生成是一次性重建操作。

### 4.3 一个易混淆点

Macro 的 `temp_menu_title`（基底温度）与 `modes`（冻结/观察/培养/慢速观察）是**同一组时间/推进档位控制的叙事包装**，不是 §2.2 意义上的温度场参数。官方教程文本把它描述为「显微镜控制基底温度的系统」，但档位名与效果都指向模拟推进速度。合并稿只借鉴档位设计，**不把它当作温度场**。

---

## 5. 与 v1.0 的对照结论（供合并稿引用）

| 用户点名的借鉴点 | 官方 | Macro | 合并稿落点 |
| --- | --- | --- | --- |
| 冻结 / 观察 / 培养 / 慢速观察 | ✅ | ✅ | §4.3.1 实验条件档位 |
| 过夜培养 | ❌ | ✅ | §4.3.2 无渲染快进 |
| 工具 | 5 件 | 10 件 + 选择/框选/地形笔刷 | §4.4 工具系统扩展 |
| 培养基设置 | 23 项基础参数 | 增加氧梯度/昼夜/光源/食物分布/隧道地形/总览 | §7.5 培养基设置 |
| 显微视野 | 基础缩放 | 镜头滤镜/旋转/缩略图/图例/视野锁定 | §3.3.1 显微视野与观察控制 |

---

## 6. 证据边界

1. 全部结论来自编译资源表解码，APK 未执行；不证明运行期行为、控件真实布局或数值映射。
2. `values-zh` 是 Macro 内置中文；部分键（尤其更新日志与长帮助文本）中文可能省略或未完全本地化，本文以 EN 为键名依据、ZH 为显示文案依据。
3. 「过夜培养 = 无渲染快进」「温度档位 = 模拟推进档位」属于基于键名与教程文本的**推断**，不是反编译代码确认。
4. Macro 相比官方多出 935 个资源键，其中包含大量更新日志、帮助文本与新细胞类型词条；本文只抽取用户点名范围，未全量枚举。
5. 本轮未改动任何 Godot 运行时代码，未改动任何 APK。
