# 通用二维/三维场可视化

主入口是 `visualizeMatField.m`。数据可以来自 MAT 文件、MATLAB Base Workspace，或调用
时直接传入的数组/标量结构体。无参数调用时可以在窗口内选择 MAT 文件或工作区；脚本会
递归发现顶层或嵌套标量 structure 中符合规则的数组。三维变量未指定绘图模式时默认使用
多等值面，二维变量自动使用 Slice。
四维及以上的实数数值数组可先选择保留的二维/三维子数组，再进入上述绘图流程。

实现已拆分到 `+matfield` 包；脚本职责、运行流程和模块依赖见
[`ARCHITECTURE.md`](ARCHITECTURE.md)。

图片、GIF/MP4/AVI 播放序列和原始切片数据导出，使用窗口顶部“导出”菜单或 `exportMatField(fig, path, ...)`。
图片包含图像、坐标轴、标题与完整颜色栏，不含控制台。格式、逐级启用规则与示例见 [EXPORT.md](EXPORT.md)。

## 目标变量规则

脚本只把以下数据视为可绘制目标：

- 实数数值二维矩阵 `[num_x, num_y]`：仅支持 Slice，直接绘制完整矩阵。
- 实数数值三维数组 `[num_x, num_y, num_z]`：支持 Slice 和 Volume。
- `[num_x, num_y, 1]` 的尾部单例维在 MATLAB 中会被折叠，按二维矩阵处理，仅支持 Slice。

四维及更高维实数数组作为“子数组来源”列入目标列表，至少需要两个长度大于 1 的维度。
向量、标量、空数组、稀疏数组、复数、logical、char/string、cell、table 和非标量
structure 都不会进入目标变量下拉列表。二维与三维目标的各个有效轴长度必须大于 1。
变量路径既可以是顶层名称（如 `top2`），也可以是任意深度的点分路径（如
`caseA.flow.temperature`）。

## 常用命令

```matlab
cd('D:\myDocuments\BUAA\NeRF-RI\CFDdata\SwirlFlame\matlab')
matFile = fullfile(pwd, '..', 'Data', 'data_uniGrid_zFlowDirct.mat');

% 不传参数：先在窗口中选择 MAT 文件，再选择目标变量
visualizeMatField()

% 直接显示当前函数或脚本工作区中的数组
visualizeMatField(myVolume)

% 直接传入复杂结构体，再在窗口中选择合法嵌套字段
visualizeMatField(myResult)

% 浏览 MATLAB Base Workspace
visualizeMatField('SourceType', 'workspace')

% 精确指定 Base Workspace 中的目标
visualizeMatField('SourceType', 'workspace', ...
    'WorkspaceVariable', 'myResult.flow.temperature')

% 不指定 MAT 文件，但预先固定绘图模式
visualizeMatField('PlotType', 'slice')

% 只指定 MAT 文件：先在窗口顶部选择目标变量
visualizeMatField(matFile)

% MAT 文件和三维变量均已指定，其余使用默认值（volume）
visualizeMatField(matFile, 'rho.rho_XYZ')

% 精确指定变量、图形、切片维度和索引
visualizeMatField(matFile, 'T.T_XYZ', ...
    'PlotType', 'slice', 'Dimension', 3, 'Index', 80)

% 指定变量和维度，索引自动取中间值
visualizeMatField(matFile, 'GD.gradNorm_XYZ', ...
    'PlotType', 'slice', 'Dimension', 1)

% 三维多等值面
visualizeMatField(matFile, 'rho.rho_XYZ', 'PlotType', 'volume')

% 调整三维绘制参数
visualizeMatField(matFile, 'T.gradNorm_XYZ', 'PlotType', '3d', ...
    'NumIsosurfaces', 7, 'IsoRange', [0.10 0.70], ...
    'SurfaceAlpha', 0.16, 'MaxRenderSize', 110)
```

`figure` 可以作为 `slice` 的别名：

```matlab
visualizeMatField(matFile, 'T.T_XYZ', ...
    'PlotType', 'figure', 'Dimension', 3, 'Index', 80)
```

## 高维数组：额外维度选择

例如 `A` 的大小为 `[161,161,159,3]`：

```matlab
visualizeMatField(A)
% 或从 MAT 文件加载同样的数组
visualizeMatField('prediction.mat', 'A')
```

默认保留最靠前的三个长度大于 1 的维度（只有两个时保留两个），其他维度索引默认 1。
窗口新增“额外维度选择”区域，显示原始形状、保留维度和每个额外维度的当前索引。
对上述 `A`，Dim 4 提供索引输入框及滑条，可切换 1/2/3；改动自动更新图像、当前子数组的全局 min/max 和颜色栏。
切换索引会暂停播放；保留维度不变时复用坐标区和现有绘图设置，保持三维观察视角。
滑动时节流更新，松手后保证绘制最终索引，不需要“重新绘图”按钮。

“保留维度”输入框使用逗号分隔的递增编号，例如 `1, 2, 3`、`1, 3, 4` 或 `2, 4`。
保留两个维度时只能使用二维 Slice；保留三个维度时支持三维切片和等值面。
长度为 1 的额外维度固定在索引 1；保留维度的长度必须大于 1。
坐标标签继续对应**原数组**的 Dim 编号：例如保留 `[1,3,4]` 时不会重新命名为 Dim 1/2/3。
不推断最后一维是 RGB、通道、时间还是其他物理量。

也可以从命令行精确指定：

```matlab
% 第4维的第2项，固定此次选择
visualizeMatField(A, 'RetainedDimensions', [1,2,3], 'ExtraIndices', [4,2])

% ExtraIndices 每行是 [原数组维度编号, 索引]，适用于多个额外维度
visualizeMatField(B, 'RetainedDimensions', [1,2,3], 'ExtraIndices', [4,2; 5,3])

% 保留原数组第1/3/4维，沿原第4维取第2个切片
visualizeMatField(A, 'RetainedDimensions', [1,3,4], 'ExtraIndices', [2,1], ...
    'PlotType', 'slice', 'Dimension', 4, 'Index', 2)

% 直接二维子数组，只提供二维显示及颜色栏等相关控制
visualizeMatField(A, 'RetainedDimensions', [2,4])
```

`RetainedDimensions` 与 `ExtraIndices` 均只使用 Name-Value 传值，不要求预先指定 `PlotType`。
维度编号和索引均从 1 开始。显式指定的保留维度不允许在窗口修改；`ExtraIndices` 只固定其中指定的维度，未指定的额外维度仍可调整。
`Dimension/Index` 保持原有依赖：显式 `PlotType='slice'`，且 `Index` 需要显式 `Dimension`。
二维/三维普通输入仍走原流程；这两个参数不用于重排普通数组。
非法、越界或全非有限值的子数组选择会回退至上一合法选择；可见窗口给出错误信息。

MAT、直接内存数组/嵌套标量结构体、Base Workspace 均支持此功能。
工作区刷新时重新读取源变量并保留仍合法的额外索引；MATLAB 版仍使用原有 MAT 顶层变量加载方式，
不承诺对任意嵌套 MAT 字段进行磁盘惰性读取。切换分量复用已经载入的原始数组，不更改来源数据或类型。
MATLAB 版的文件入口仍为 MAT 文件；Python 的 `.npy/.pt` 文件支持不属于此次 MATLAB 升级。

## 色图选择：二维与三维通用

未显式指定 `Colormap` 时，默认 `turbo`，控制台提供“色图”下拉框，可选 `jet`、`hot`、`parula`、
`gray` 等本机 MATLAB 可用的内置色图。尚未选择目标时控件禁用。
二维图像、三维等值面和颜色栏同步换色；三维表面按等值面数值着色，透明度和光照继续影响最终观感。

```matlab
visualizeMatField(A, 'Colormap', 'jet')
visualizeMatField(A, 'PlotType', 'volume', 'Colormap', 'hot')
visualizeMatField('prediction.mat', 'A', 'PlotType', 'slice', 'Colormap', 'hot')
```

显式指定 `Colormap` 时按既有逐级规则固定该设置，隐藏对应下拉框；省略时允许交互选择。
`Colormap` 同时适用于两种模式，无需固定 `PlotType`。未知名称在创建窗口前报错。
换色直接更新图像色图和已有等值面 patch 的颜色，不重新加载数据、不重新计算等值面，保留
切片索引、颜色栏范围、等值面值、透明度、播放状态和观察视角。
在同一窗口中切换模式、变量或额外维度索引后，继续使用当前色图。
`ColorLimits` 决定数值范围，`Colormap` 决定该范围对应的颜色，两者独立。

升级后 35 项 MATLAB 测试全部通过，包含二维/三维换色、已有网格保持、视角/透明度/范围保持和显式参数固定。
`addpath('tests'); visualColormapSmoke` 可导出 jet/hot 的二维、三维及窄窗口截图。

## 传参规范

支持以下规范调用形式：

```matlab
visualizeMatField()
visualizeMatField(Name, Value, ...)
visualizeMatField(matFile)
visualizeMatField(matFile, variablePath)
visualizeMatField(matFile, [variablePath], Name, Value, ...)
visualizeMatField(numericArray, Name, Value, ...)
visualizeMatField(scalarStruct, [variablePath], Name, Value, ...)
visualizeMatField('SourceType', 'workspace', Name, Value, ...)
```

- 第一个位置参数为文本时表示 MAT 文件路径；为数值数组或标量 structure 时表示调用时
  直接传入的内存数据。
- 第二个位置参数是目标字段路径，只能跟在 MAT 文件或直接传入的标量 structure 后面；
  直接数值数组自身就是目标，不接受第二个位置参数。
- `SourceType='workspace'` 用于浏览 Base Workspace；可用 `WorkspaceVariable` 显式指定
  顶层变量或嵌套字段。
- `SourceType='memory'` 通常由直接传值自动推断，不能在没有直接值时单独使用。
- 未提供位置参数时，Name-Value 可以从第一个参数开始。
- MAT 路径和直接内存数据只使用位置传参，不提供同名 Name-Value 写法。
- Name-Value 的排列顺序任意。
- 同一个参数不同时支持位置与 Name-Value 两套写法，避免无法判断用户是否显式指定。
- 参数名称大小写不敏感，但必须写完整，不接受 `PlotT` 等缩写。

因此，下面是完整且规范的调用：

```matlab
visualizeMatField('../Data/data_uniGrid_zFlowDirct.mat', 'n.gradX_XYZ', ...
    'PlotType', 'slice', ...
    'Dimension', 2, ...
    'Index', 60)
```

也可以在文件和变量均未指定时预先固定绘图模式：

```matlab
visualizeMatField('PlotType', 'slice', 'Dimension', 2)
```

## MAT 文件与变量选择

- 未指定 `matFile` 时，窗口顶部显示 MAT 文件路径输入框、“浏览…”按钮和禁用的变量
  下拉框，图像区为空，控制台全部禁用。
- 路径输入框与命令行参数使用相同的解析规则：支持绝对路径，也支持相对于 MATLAB 当前
  工作目录的路径。确认输入后立即检查文件并发现合法变量。
- “浏览…”按钮打开 MATLAB 原生文件选择窗口，并限制选择 `*.mat` 文件。
- 文件有效且存在符合当前参数要求的目标数组后，变量下拉框自动启用，但不会擅自选择
  变量或开始绘图。
- 如果在已经绘图后更换 MAT 文件，当前图像会清空，控制台重新禁用，并进入新文件的
  变量选择阶段。
- 命令行已明确指定 `matFile` 时不显示文件路径输入框和“浏览…”按钮。
- 未在命令行指定 `variablePath` 时，窗口顶部显示“目标变量”下拉框，图像区初始为空。
- 首次选择变量之前，当前绘图模式下的控制台选项全部禁用。
- 选择变量后会立即加载该数组，更新完整数据范围、采样信息及相关控件并自动绘图。
- 更换目标变量同样立即更新，不需要“重新绘图”按钮。
- 在 Slice 模式更换不同尺寸的数组时，尽量保持原切片在所选维度中的相对位置。
- 命令行已明确指定变量时不显示变量下拉框，界面与原调用方式一致。
- 下拉框列出符合二维/三维规则的目标及可提取子数组的高维实数来源，并显示原数组尺寸与维数。
- 对 v7.3 MAT 文件，变量列表递归读取 HDF5 元数据，不会为了生成下拉列表预先加载
  全部数组；对早期 MAT 格式，顶层数值数组使用 `whos` 元数据判断，只有标量 structure
  会按顶层变量逐个加载并递归检查。

## 工作区与直接内存数据

- 无参数调用时显示“数据源类型”下拉框，默认仍为 MAT 文件；切换为“MATLAB 工作区”后
  立即扫描 Base Workspace，并显示“刷新”按钮。
- 工作区变量不会后台轮询。选择变量时读取一次快照；点击“刷新”后重新扫描并重新读取
  当前目标。变量被删除或变为不兼容类型时，图像清空并回到目标选择状态。
- 工作区中的三维变量刷新后变为二维时，会自动降级到 Slice。
- 函数局部变量通过 `visualizeMatField(localValue)` 直接传入。figure 后续回调不使用
  `evalin('caller', ...)`，因此不依赖最初函数的 caller workspace 是否仍然存在。
- 直接传入数值数组时立即绘图；直接传入标量 structure 且未指定字段时，目标下拉框列出
  所有合法嵌套二维/三维数组。
- 直接传值采用 MATLAB copy-on-write 语义。调用后原变量的修改不会作为自动刷新信号；
  查看器继续显示调用时持有的数据快照。

## 窗口分区与响应式布局

查看器统一划分为“数据源与目标变量区、绘图区、控制台区”三个区域。绘图区始终占用
除上下两区以外的弹性空间；窗口宽度变化时，另外两个区域会在宽、中、窄三种布局之间
自动重排，而不是继续压缩固定列直至控件被边框裁切。

- 宽窗口保持信息和控件的横向排列；中等窗口会把统计信息及相关参数分组换行；窄窗口
  进一步纵向排列，提示文字也会换行。
- 窗口高度不足以显示整个控制台时，控制台内部提供滚动访问，绘图区仍保留最低可用
  高度；不会用静默裁切隐藏控件。
- MAT 路径输入框使用弹性宽度，“浏览…”按钮始终保留；完整路径也可以通过输入框滚动
  或 Tooltip 查看。
- colorbar 在绘图区内拥有独立的顶部和右侧安全边距。刻度采用紧凑有效位显示，极端
  数值可使用科学计数法，但不会改变真实的 `ColorLimits`。
- 调整窗口尺寸只改变容器布局，不重新读取数据、不重新计算等值面，也不重建坐标区，
  因而不会重置三维观察视角、缩放/平移状态或坐标区工具栏。

## Slice 模式

- 二维目标直接显示完整矩阵，不提供切片维度、索引或索引自动播放控件，也不允许切换
  到 Volume。
- 三维目标才使用以下维度、索引和自动播放逻辑。
- 普通三维数组的 `Dimension` 接受数值 `1`、`2` 或 `3`；高维来源接受三个保留维度中的原数组编号。
- 未在命令行指定 `Dimension` 时才显示维度下拉框，标签对应保留的原始 Dim 编号。
- 未在命令行指定 `Index` 时才显示索引滑块和数值输入框，初值为该维度中点。
- 索引控件出现时同时提供自动播放：从当前索引逐帧递增，到该维末尾后从 1 循环；
  播放间隔可以直接设置。
- 未指定 `ColorLimits` 时显示颜色栏范围下拉框，可选择“全局范围”“当前切片”或
  “指定范围”。选择“指定范围”后，同时启用上下限精确输入框与两条粗调滑块；确认输入
  或拖动滑块都会立即更新图像，不需要额外的重绘按钮。
- 指定范围要求上下限均为有限数值且下限严格小于上限；无效输入会恢复上一次有效范围，
  滑块拖动越过另一端时会被限制在合法一侧。精确输入超出当前滑块范围时，滑块范围会
  自动扩展并与输入值同步。
- 命令行可以用 `'ColorLimits', [lower upper]` 固定范围；一旦显式传入，就不再显示前端
  颜色栏范围控件。
- 命令行已经指定的参数不会在窗口中重复提供相应控制项。
- 显示当前切片和完整三维数组各自的 min/max。
- 颜色栏可以在全局、当前切片和指定范围间切换，colorbar 始终显示。
- 切换维度时，会按原切片在轴上的相对位置选择新索引，而不是突然跳到边界。

## 模式切换

对于三维变量，只有命令行未指定 `PlotType` 时，窗口才显示“绘图模式”下拉框，可以在
`Volume（三维等值面）` 和 `Slice（二维切片）` 之间切换。切换会立即重建当前窗口中的
绘图区和当前模式所需的下级控制项，同时复用内存中已经加载的数组，不会再次读取 MAT
文件。命令行已指定 `PlotType` 时，不显示模式下拉框。二维变量只有 Slice 一种有效模式，
因此不显示模式下拉框；若显式为二维变量指定 `PlotType='volume'`，脚本会给出说明性错误。

## 三维模式的选择

三维标量场没有唯一的“等高线图”。这里以**多层等值面**作为默认方案：二维等高线表示
`f(x,y)=c`，其自然的三维对应物就是 `f(x,y,z)=c` 的曲面。

Volume 参数也采用逐级兜底：

- 未指定 `NumIsosurfaces` 时显示等值面数量控件，默认 5 层。
- 未指定 `IsoRange` 时显示范围输入框，默认覆盖全局范围的 15%--85%。
- 未指定 `SurfaceAlpha` 时显示透明度滑块，默认 0.22。
- 可以通过 `IsoValues` 精确给出每个等值面值；此时不再显示数量和范围控件。
- 当 `IsoValues`、`NumIsosurfaces`、`IsoRange` 都未指定时，界面会先显示“自动多层/指定单值”
  下拉框；选择“指定单值”后才显示等值面数值输入框和滑条，范围为全局 `[min,max]`。
- 自动多层模式下，确认新的等值面数量或范围上下限后会立即重绘，不再需要单独点击
  “重新绘制”。
- 指定单值模式下提供自动播放：从当前数值开始，每帧增加全局值域的 1%，超过最大值后
  回到最小值；播放间隔可以设置。切回自动多层模式时播放会自动停止。
- 命令行已经指定的三维参数按原值绘制，不在窗口中重复提供相应控件。

默认自动多层的数值为
`globalMin + linspace(0.15, 0.85, 5) * (globalMax - globalMin)`。

例如：

```matlab
visualizeMatField(matFile, 'rho.rho_XYZ', 'PlotType', 'volume', ...
    'IsoValues', [0.35 0.60 0.85], 'SurfaceAlpha', 0.20)
```

为了让交互速度可接受，三维绘制默认将每个轴采样到不超过 96 个点；界面中的全局统计
仍来自完整数组。切片索引和透明度滑条在拖动期间采用限频刷新，而且不会反向设置正在
拖动的滑条；播放定时器也会丢弃来不及处理的旧帧，避免长时间拖动或播放后积压回调。
自动多层的数量和范围只在输入值被确认时重绘，而不是在键入每个字符时重绘，因为一次
重绘需要为每个层级重新计算完整三维等值面，代价明显高于更新二维切片或透明度属性。

R2025a 起查看器窗口会启用 MATLAB 原生的 figure 工具栏。更早版本通过 Volume 坐标区
右上角的“三个点”工具栏操作。坐标区工具栏提供三维旋转、平移、放大、缩小和恢复视图。
鼠标滚轮缩放也可用。调整等值面数量、
范围或指定单值并重新绘制时，会保留用户当前的坐标范围、相机位置、观察目标、朝上方向、
视角和投影方式，同时保留各相机属性原本的自动/手动模式；切换等值面方式不会改变随后
平移和缩放的交互语义。
Volume 绘图区会为标题、三维坐标框和刻度预留边距，初始视角也会自动后退，避免最大化
窗口时上下内容被裁切；坐标范围固定覆盖完整的绘制采样域，不会随等值面范围跳变。

参数严格按以下层级处理：

1. 数据源决定目标来自 MAT 文件、Base Workspace 或直接内存值；未指定时在窗口中选择。
2. 目标变量依赖有效数据源；直接数值数组自身就是目标，MAT、Workspace 和内存结构体
   可以通过字段路径或变量下拉框进一步选择。
3. 高维来源先按 `RetainedDimensions/ExtraIndices` 提取子数组。`PlotType` 依赖最终子数组的维数：
   二维只能 Slice，三维可以 Slice 或 Volume。
4. `Dimension` 依赖显式的 Slice 模式；`Index` 进一步依赖显式的 `Dimension`。
5. `NumIsosurfaces`、`IsoRange`、`IsoValues`、`SurfaceAlpha` 和 `MaxRenderSize` 依赖显式的
   Volume 模式；`IsoValues` 与自动多层的数量/范围参数互斥。

数据源或目标可以留给 UI 后续选择，但命令行中的下级参数仍必须满足上述依赖；缺少必需
的上级模式参数会立即给出说明性错误。

其他方案的适用范围：

- **三正交切片**：内部结构最清晰，但本质仍是若干二维平面，已经由 slice 模式覆盖。
- **体渲染**：适合烟雾状连续介质，但依赖传递函数，参数不当容易产生误导，并可能需要
  Image Processing Toolbox。
- **单等值面**：形状最清楚，但容易遗漏其他数值层次。

因此当前实现采用多等值面作为稳定、依赖少且最接近等高线语义的三维默认图。

## 维度约定

脚本使用 `Dim n` 描述原始 MATLAB 数组的第 n 维，不推断这些维度的
坐标名称或物理含义。数据维度可以代表空间、时间或其他自变量，具体含义由用户依据
数据来源判断。普通三维图对应原数组第一、第二和第三维；高维子数组的坐标轴对应用户保留的原始维度。

## 高维升级验证

MATLAB R2026a 下运行 `runtests('tests')`：原有 16 项及新增 13 项测试共 29 项通过。
新增覆盖 MAT v7/v7.3 嵌套字段、内存快照、工作区刷新、四/五维、单例维、原始维度标签、
显式参数固定、切片/等值面切换、播放暂停、相机保持及无有限数值的选择回退。
`tests/visualSubspaceSmoke.m` 导出宽/窄窗口截图，检查坐标区、颜色栏、额外维度区与可滚动控制台。
运行前可执行 `addpath('tests'); visualSubspaceSmoke`；截图写入被忽略的 `artifacts/`。
