# Cellarium 原生扩展（GDExtension）

本目录是 **C++ 源码、构建配置与逐位验证探针的入库副本**，用于版本回溯。二进制 DLL 与运行配置随发布工程一起入库：

- `godot/cellarium-release/bin/cellarium_native.gdextension`
- `godot/cellarium-release/bin/windows/cellarium_native.windows.template_debug.x86_64.dll`

`OrganismManager.native_spatial_enabled` 默认 `false`；DLL 缺失或类未注册时逐段回退 GDScript，clone 后不开原生也能跑。

## 目录

| 路径 | 用途 |
| --- | --- |
| `src/` | `CellNeural` / `CellSpatial` / `CellMetabolism` / 注册入口的 `.cpp` / `.h` |
| `project/` | C++ 逐位等价探针与微基准（Godot 场景脚本，孤立运行） |
| `SConstruct` / `methods.py` | SCons 构建脚本（godot-cpp master + 自导出 API） |

## 构建工作区与同步

本机构建工作区：`D:\Tools\Godot_v4.7.2\gdext_work\template\`（含 `godot-cpp/` 子模块与 junction）。**该目录不入库**。

版本库 `native/` 与构建工作区的 `src/` 是两份副本：**每次改 C++ 后必须两边同步再编译**，否则 DLL 与入库源码可能错位。DLL 编译后复制到两个工程的 `bin/windows/`：

1. `godot/cellarium-release/bin/windows/`
2. `D:\Tools\Godot_v4.7.2\project\cellarium\bin\windows\`

并同步 `.gdextension`（两工程内容相同）。编译产物 `.obj/.lib/.exp/.sconsign.dblite` 不入库。

## 工具链锚点（v0.32.0 时点）

- Godot `4.7.2.stable.official.ed1daf0bf`；godot-cpp 官方无 4.7 tag，使用 master commit `24b9df7a88d40bcaf1f157703d4220185cb71fbf`。
- `extension_api.json` 由 `godot --headless --dump-extension-api` 导出，**不入库**（6.9 MB 引擎产物），v0.32.0 时点 SHA-256：`d0e4c08c03b165156dabe6bfb6a906baf0069189f62035341230a246c86d6986`。重建时重新导出，引擎版本不符会导致绑定错位。
- v0.35.0 入库 DLL SHA-256：`5F22B56BE53A72FF673FD7A0449283A7A508CDF0D821FD364E1D072ACEDD2082`（新增 `CellRenderCache.rebuild()` 批渲染缓存原生化，`CellNeural.copy_outputs_to_intents()` / `collect_signal_sources()`；视图数据不进 state hash）。v0.34.0 为 `86449DB2A3A65E9AC73F7B8BA08D7D83FC9434ECBF2C9ACCBC3DD8953240A9BF`（transfer-rate / radius / lifecycle / Verlet+link 下沉），v0.33.0 为 `aba57d3102a93236f7457a068ab7e86c6e80e97b51bc49ffbaa8a5b641f02e8e`。每次发布新 DLL 时更新此值，便于回溯。
- 构建命令（在含 `godot-cpp/` 的构建工作区根目录）：

```powershell
scons target=template_debug platform=windows dev_build=no -j 4
```

`SConstruct` 内 `SConscript("godot-cpp/SConstruct", {"api_version": 4.7, "custom_api_file": "extension_api.json", ...})`，不要改成官方 tag 流程。`.gdextension` 只列 `windows.x86_64` 单平台；列全平台会让 headless 编辑器校验阶段崩溃（`0xC0000005`）。

## 逐位闸门（改任何 C++ 后必跑）

1. 原型工程（`gdext_work/template/project`）：`neural_parity_probe.gd`（12000 float32 全等）、`spatial_parity_probe.gd`（邻域索引 / collect_inputs / 碰撞修正全等）、新热点对应探针。
2. 两个发布工程：`tools/NativeParityProbe.gd`（40 密集合子 × 240 tick × 5 检查点 `get_state_hash()` 逐位一致）、`tools/SmokeTest.gd`（含全部脚本解析清单）。
3. 同会话 A/B 基准：`CELLARIUM_NATIVE=0/1` 两次跑 `tools/BenchTest.gd`，不跨会话比较数字。

## 确定性铁律

GDScript `float` 是 **double**，`PackedFloat32Array` 元素是 **float32**；C++ 一律 double 累加 / `std::tanh(double)`，写回转 float32 才逐位一致。需要把**中间值**交回 GDScript 继续运算时，用 `PackedFloat64Array` 保留 double，多一次 float32 舍入就会让 state hash 漂移。固定桶只替代 `unordered_map`，**不得加 Cell Lab 式 203 容量上限**（会截断邻居、改变邻居集合）。碰撞对遍历序：a 升序 → 9 格偏移 `(offset_y, offset_x)` → 格内插入序，`b > a` 且距离 `> 2×` 接触距离过滤。
