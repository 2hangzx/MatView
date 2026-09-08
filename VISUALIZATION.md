# 通用 MAT 二维/三维场可视化

主入口是 `visualizeMatField.m`。每次调用必须明确传入 MAT 文件，目标变量路径可以省略。
脚本不依赖 `data_uniGrid_zFlowDirct.mat` 的固定字段结构，会递归发现顶层或嵌套标量
structure 中符合规则的数组。省略变量时先显示变量选择界面；绘图模式及其下级参数也
可以省略。三维变量未指定绘图模式时默认使用多等值面，二维变量则自动使用 Slice。

## 目标变量规则

脚本只把以下数据视为可绘制目标：

- 实数数值二维矩阵 `[num_x, num_y]`：仅支持 Slice，直接绘制完整矩阵。
- 实数数值三维数组 `[num_x, num_y, num_z]`：支持 Slice 和 Volume。
- `[num_x, num_y, 1]` 的尾部单例维在 MATLAB 中会被折叠，按二维矩阵处理，仅支持 Slice。

向量、标量、四维及更高维数组、复数、logical、char/string、cell、table 和非标量
structure 都不会进入目标变量下拉列表。二维与三维目标的各个有效轴长度必须大于 1。
变量路径既可以是顶层名称（如 `top2`），也可以是任意深度的点分路径（如
`caseA.flow.temperature`）。

## 常用命令

```matlab
cd('D:\myDocuments\BUAA\NeRF-RI\CFDdata\SwirlFlame')
matFile = fullfile(pwd, 'Data', 'data_uniGrid_zFlowDirct.mat');

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

## 传参规范

统一调用形式为：

```matlab
visualizeMatField(matFile, [variablePath], Name, Value, ...)
```

- `matFile` 是必需的第一个位置参数。
- `variablePath` 是可选的第二个位置参数，可以是顶层名称或嵌套点分路径；省略时由
  窗口中的下拉框选择。
- Name-Value 位于变量路径之后；省略变量路径时可以紧跟在 `matFile` 后面，排列顺序任意。
- 同一个参数不同时支持位置与 Name-Value 两套写法，避免无法判断用户是否显式指定。
- 参数名称大小写不敏感，但必须写完整，不接受 `PlotT` 等缩写。

因此，下面是完整且规范的调用：

```matlab
visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'n.gradX_XYZ', ...
    'PlotType', 'slice', ...
    'Dimension', 2, ...
    'Index', 60)
```

也可以在未指定变量时预先固定绘图模式：

```matlab
visualizeMatField(matFile, 'PlotType', 'slice', 'Dimension', 2)
```

## 变量选择

- 未在命令行指定 `variablePath` 时，窗口顶部显示“目标变量”下拉框，图像区初始为空。
- 首次选择变量之前，当前绘图模式下的控制台选项全部禁用；只有目标变量下拉框可操作。
- 选择变量后会立即加载该数组，更新完整数据范围、采样信息及相关控件并自动绘图。
- 更换目标变量同样立即更新，不需要“重新绘图”按钮。
- 在 Slice 模式更换不同尺寸的数组时，尽量保持原切片在所选维度中的相对位置。
- 命令行已明确指定变量时不显示变量下拉框，界面与原调用方式一致。
- 下拉框只列出符合“实数数值二维/三维数组”规则的目标，并显示数组尺寸与维数。
- 对 v7.3 MAT 文件，变量列表递归读取 HDF5 元数据，不会为了生成下拉列表预先加载
  全部数组；对早期 MAT 格式，顶层数值数组使用 `whos` 元数据判断，只有标量 structure
  会按顶层变量逐个加载并递归检查。

## Slice 模式

- 二维目标直接显示完整矩阵，不提供切片维度、索引或索引自动播放控件，也不允许切换
  到 Volume。
- 三维目标才使用以下维度、索引和自动播放逻辑。
- `Dimension` 只接受数值 `1`、`2` 或 `3`，分别表示 MATLAB 数组的第一、第二或第三维。
- 未在命令行指定 `Dimension` 时才显示 `Dim 1/Dim 2/Dim 3` 维度下拉框。
- 未在命令行指定 `Index` 时才显示索引滑块和数值输入框，初值为该维度中点。
- 索引控件出现时同时提供自动播放：从当前索引逐帧递增，到该维末尾后从 1 循环；
  播放间隔可以直接设置。
- 未指定 `ColorLimits` 时显示全局/当前切片颜色栏范围下拉框。
- 命令行已经指定的参数不会在窗口中重复提供相应控制项。
- 显示当前切片和完整三维数组各自的 min/max。
- 颜色栏可以在“全局范围”和“当前切片”间切换，colorbar 始终显示。
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

查看器窗口启用 MATLAB 原生的 figure 工具栏；Volume 坐标区右上角的“三个点”工具栏
提供三维旋转、平移、放大、缩小和恢复视图。鼠标滚轮缩放仍然可用。调整等值面数量、
范围或指定单值并重新绘制时，会保留用户当前的坐标范围、相机位置、观察目标、朝上方向、
视角和投影方式，同时保留各相机属性原本的自动/手动模式；切换等值面方式不会改变随后
平移和缩放的交互语义。
Volume 绘图区会为标题、三维坐标框和刻度预留边距，初始视角也会自动后退，避免最大化
窗口时上下内容被裁切；坐标范围固定覆盖完整的绘制采样域，不会随等值面范围跳变。

参数严格按层级校验：`Index` 依赖 `Dimension`，切片参数依赖显式的 `slice/figure`
模式，等值面参数依赖显式的 `volume` 模式。缺少上级选择会直接给出说明性错误。

其他方案的适用范围：

- **三正交切片**：内部结构最清晰，但本质仍是若干二维平面，已经由 slice 模式覆盖。
- **体渲染**：适合烟雾状连续介质，但依赖传递函数，参数不当容易产生误导，并可能需要
  Image Processing Toolbox。
- **单等值面**：形状最清楚，但容易遗漏其他数值层次。

因此当前实现采用多等值面作为稳定、依赖少且最接近等高线语义的三维默认图。

## 维度约定

脚本只使用 `Dim 1/2/3` 描述 MATLAB 数组的第一、第二和第三维，不推断这些维度的
坐标名称或物理含义。数据维度可以代表空间、时间或其他自变量，具体含义由用户依据
数据来源判断。三维图的三个坐标轴严格对应数组的第一、第二和第三维。
