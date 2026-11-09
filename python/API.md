# 调用规范与逐级控制

## 唯一主入口

```python
visualize_field(
    source=None, *, field=None, namespace=None,
    mode=None, dimension=None, index=None,
    color_limits=None, iso_values=None, num_isosurfaces=None,
    iso_range=None, surface_alpha=None, max_render_size=None,
    colormap=None, show=True,
    retained_dimensions=None, extra_indices=None,
)
```

返回 `ViewerWindow`，不阻塞。普通脚本最后调用 `run()`。
只能在主线程创建窗口；`show=False` 可用于自动测试，但依然需要 Qt/图形环境。

### 窗口导出方法

```python
window.export_image(path, *, width=1600, height=1200, components=None)
window.export_animation(path, *, width=1280, height=960, frames=None, fps=None, progress=None, components=None)
window.export_slice_data(path)
window.wait_until_ready(timeout=60)
```

路径允许位置传值，其余配置均为关键字。方法等待当前请求的画面完成，成功返回 `Path`；错误以异常返回。
必须在创建窗口的主线程调用。图片和动画始终保留图像主体，`components=None` 默认保留全部可选部件，`components=[]` 只保留主体。
支持 `axes`、`axis_labels`、`axis_ticks`、`title`、`colorbar`、`colorbar_label`、`colorbar_ticks`。
标签指坐标轴名称或颜色栏的 `Value`，刻度包含刻度线和数字。子项只在其上级也被选中时生效。
宽 320–8192、高 240–8192 像素，总量不超过 3200 万像素；MP4 两边必须为偶数。
动画只支持三维 Slice 或单值等值面，帧数为 1–10000、帧率为 0.1–60。
默认帧数为当前切片维度长度，或 101 个单值帧；`fps=None` 使用当前播放间隔的倒数。
从当前值开始并按原播放步长循环扫描，不改变窗口索引/数值/相机；显式固定索引不妨碍导出独立扫描序列。
`progress(done,total)` 在每一帧前和结束时调用；返回 `False` 抛出 `fieldviz.exporting.ExportCancelled`，已有目标不被覆盖。
GIF 无限循环、MP4 有限播放；原始切片数据支持 NPZ/NPY/MAT/CSV，格式与元信息详见 README。

CLI 增加 `--export-image PATH`、`--export-animation PATH`、`--export-slice-data PATH`，可组合执行后退出。
`--export-size WIDTH HEIGHT` 设置图片/动画尺寸，`--frames` 和 `--fps` 只能与 `--export-animation` 一起使用。
`--export-components` 后可列出保留的部件，例如 `--export-components axes axis_ticks`。单独传该标志可仅导出主体。
导出时必须已确定目标（直接 NPY 自动选中，多变量来源使用 `--field`）。

### 统一原则

1. 只有来源 `source` 允许位置传值，也接受 `source=...`；其余全部关键字传值，没有混合短写法。
2. `None` 表示用户没有显式固定该选项：使用默认值，并在所属分支提供控件。
3. 显式指定的选项不再由对应控件修改；来源/目标仍显示身份信息但不可编辑。
4. 子参数不能绕过上级约束；互斥分支不得同时传入。
5. 维度编号与索引都从 **1** 开始；普通二维/三维数组沿用 `dimension=1/2/3`。
   这是与 MATLAB 保持一致的刻意选择；内部读取时才转换为 NumPy 的 0 基索引。
   不接受 X/Y/Z/I/J/K 或字符串维度别名。

## 来源 → 目标

| 参数 | 规则 |
|---|---|
| `source` | 路径、NumPy 数组、Torch Tensor、嵌套字典或 `DataSource`。省略时空窗口选文件 |
| `namespace` | 显式 Mapping，例如 `globals()`；与非空 `source` 互斥 |
| `field` | 可绘制叶节点路径。显式传入时必须同时有 `source` 或 `namespace` |

直接数组、单数组 NPY/Zarr 自动选中；字典、命名空间和多变量格式（包括只有一个变量的 MAT/NPZ）先让用户选择。
不主动读 caller workspace，也不在 GUI 回调中访问最初调用函数的栈帧。

标准路径是 `/` 分隔的层级，例如 `flow/temperature`。
兼容 MATLAB 常见的 `flow.temperature`，但若字典中有字面键 `"flow.temperature"`，该键优先。
特殊键由百分号转义；路径是查找标识符，不交给 `eval` 执行。

文件选择器与函数调用都相对于 `Path.cwd()` 解析相对路径。
刷新文件重新扫描并读取；刷新 namespace 读取当前绑定；刷新 memory 仍是调用时的快照，不会抓取原调用者的新值。

## 目标 → 模式

高维目标首先经过子数组选择，再应用下方的模式规则。

### 高维来源 → 二维/三维子数组

- `retained_dimensions=(1,2,3)`：递增的两个或三个**原数组维度编号**；每个保留维度长度必须大于 1。
- `extra_indices={4:2, 5:1}`：未保留维度的索引，编号和索引均为正整数。部分指定时其余额外维度仍默认 1，并可交互调整。
- 默认保留最靠前的三个非单例维度（不足三个时保留两个），其他维度索引默认 1；不赋予轴物理含义。
- 这两个参数不要求显式 `mode`；它们在绘图模式之前生效。二维/三维来源继续使用原流程，不支持用它们重排或降维。
- 显式 `retained_dimensions` 固定保留维度；显式 `extra_indices` 仅固定其中指定的索引。
- `dimension` 始终指原数组维度编号，必须属于三个保留维度之一。例如保留 `(1,3,4)` 时 `dimension=4` 合法。
- 保留两个维度时固定为 Slice，不能传 `dimension/index` 或三维绘图参数。
- 每个子数组独立计算全局范围；切换额外索引时停止播放并更新统计。未保留维度通过基本整数索引选取，不做平均、合并或通道颜色映射。

```shell
python -m fieldviz image_pred.npy --retained-dimensions 1 2 3 --extra-index 4=2
# 多个额外维度时重复 --extra-index，例如 --extra-index 4=2 --extra-index 5=3
```

```python
visualize_field("image_pred.npy", retained_dimensions=(1, 2, 3), extra_indices={4: 2})
```

| `mode` | 行为 |
|---|---|
| `None` | 三维默认 `isosurface`，允许窗口切换；二维固定 `slice` |
| `"slice"` | 固定切片；可用于二维或三维 |
| `"isosurface"` | 固定三维等值面，仅三维目标 |
| `"volume"` | `"isosurface"` 的唯一兼容别名，不启用其他渲染算法 |

显式指定三维模式或维度时，变量选择器排除二维目标。
其他 MATLAB 的 `figure`/`3d` 模式别名不移植，以保持 Python 参数清晰。

## Slice 分支

| 参数 | 默认与范围 | 控件 |
|---|---|---|
| `dimension` | 普通三维默认 3；高维子数组默认最后一个保留维度，使用原数组编号 | 未指定时三维切片显示维度下拉框 |
| `index` | 默认该维度中间索引，从 1 开始 | 未指定时显示索引输入、滑条、播放 |
| `color_limits` | 默认 `"global"`；也可 `"slice"` 或 `(low, high)` | 未指定时显示颜色栏模式和上下限输入/滑条 |

`dimension` 或 `index` 需要显式 `mode="slice"`；`index` 还需要显式 `dimension`。
二维数组不能使用 `dimension/index`。
`color_limits` 只影响切片，可不固定 `mode`（便于在窗口切到切片后使用）。
上下限必须有限且 `low < high`。滑条用于全局值域内粗调，输入框允许输入值域外范围。
输入任一上下限自动转入自定义模式；非法数值/上下限倒置回退为上一次合法值。

播放从当前索引向后 +1，到末尾回到 1；默认间隔 0.12 秒，可在窗口修改。
二维静态数组没有索引和播放项。

## Isosurface 分支

以下参数均需显式 `mode="isosurface"`（或 `"volume"`）：

| 参数 | 默认与范围 |
|---|---|
| `iso_values` | 一个或多个有限等值面数值，必须在全局范围内；排序去重 |
| `num_isosurfaces` | 默认 5，整数 1–12 |
| `iso_range` | 默认 `(0.15, 0.85)`，满足 `0 <= low < high <= 1` |
| `surface_alpha` | 默认 0.22，范围 `(0,1]` |
| `max_render_size` | 默认 96，整数 ≥ 16，最大采样边长目标 |

自动模式采用**值域比例**，不是分位数：

```text
start = global_min + low_fraction  * (global_max - global_min)
end   = global_min + high_fraction * (global_max - global_min)
levels = linspace(start, end, count)
```

当 `count=1`，取 start/end 的中点。

- 显式 `iso_values` 与 `num_isosurfaces/iso_range` 互斥，数值固定，隐藏方式选择和单值播放。
- 未指定以上三者时，显示“自动多层 / 指定单值”下拉框。
- 显式指定数量或范围时，锁定自动分支；只暴露尚未指定的数量/范围控件。
- 自动分支数量/范围更改自动重绘；不需要“重新绘图”按钮。
- 指定单值分支显示数值输入/滑条与播放。默认数值为全局值域中点。
- 单值播放每次增加全局值域的 1%，超出最大值后回到最小值；常量场禁用播放。
- 未指定透明度时显示透明度输入/滑条，改变后直接更新已有 actor，不重算网格。
- 切换来源、目标、模式或切片维度会停止播放；三维方式切换保留视角。

等值面计算采用固定步长降采样并携带真实数组索引坐标。最后一个样本可能不恰好落在原数组末端，
坐标系仍表示完整数据范围；统计始终使用完整数据。

## 通用参数与错误

`colormap` 为 Matplotlib 注册色图名，例如 `jet`、`hot`、`turbo`、`viridis` 或 `hot_r`。
默认参数 `None` 表示使用 `turbo` 并允许 GUI 下拉框修改；显式指定任意名称（包括 `"turbo"`）时固定色图、隐藏选择器。
Slice 与 Isosurface 均支持，不要求显式 `mode`。图像、表面和颜色栏同步换色，不改变数值范围、几何或视角。
`show` 默认 `True`。
API 的非法调用抛出明确异常；CLI 转为用法错误；运行中的文件/计算错误显示在窗口底部，悬停可读完整信息。
新数据不兼容固定参数时明确报错，不偷偷改写用户参数。

## MATLAB → Python 参数映射

| MATLAB | Python |
|---|---|
| `visualizeMatField(file, 'T.T_XYZ', ...)` | `visualize_field(file, field="T.T_XYZ", ...)` |
| `'PlotType', 'volume'` | `mode="isosurface"` 或 `mode="volume"` |
| `'Dimension', 3, 'Index', 80` | `dimension=3, index=80` |
| `'ColorLimits', [a b]` | `color_limits=(a, b)` |
| `'NumIsosurfaces', n` | `num_isosurfaces=n` |
| `'IsoRange', [a b]` | `iso_range=(a, b)` |
| `'IsoValues', [a b]` | `iso_values=(a, b)` |
| `'SurfaceAlpha', a` | `surface_alpha=a` |
| `'MaxRenderSize', n` | `max_render_size=n` |
| Base Workspace | `namespace=globals()` 或 IPython `user_ns`，必须显式提供 |
