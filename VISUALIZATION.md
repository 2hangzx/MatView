# 三维 MAT 场可视化

主入口是 `visualizeMatField.m`。每次调用都必须明确传入 MAT 文件和二级变量路径。
绘图模式及其下级参数可以省略；未指定绘图模式时默认显示三维多等值面。

## 常用命令

```matlab
cd('D:\myDocuments\BUAA\NeRF-RI\CFDdata\SwirlFlame')
matFile = fullfile(pwd, 'Data', 'data_uniGrid_zFlowDirct.mat');

% MAT 文件和二级变量必填，其余使用默认值（volume）
visualizeMatField(matFile, 'rho.rho_XYZ')

% 精确指定变量、图形、切片维度和索引
visualizeMatField(matFile, 'T.T_XYZ', ...
    'PlotType', 'slice', 'Dimension', 'Z', 'Index', 80)

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
visualizeMatField(matFile, variablePath, Name, Value, ...)
```

- `matFile` 和 `variablePath` 决定“读取哪个文件的哪个数组”，是必需的位置参数。
- 从第三个参数开始全部为可选 Name-Value，包括 `PlotType`；Name-Value 的排列顺序任意。
- 同一个参数不同时支持位置与 Name-Value 两套写法，避免无法判断用户是否显式指定。
- 参数名称大小写不敏感，但必须写完整，不接受 `PlotT` 等缩写。

因此，下面是完整且规范的调用：

```matlab
visualizeMatField('Data/data_uniGrid_zFlowDirct.mat', 'n.gradX_XYZ', ...
    'PlotType', 'slice', ...
    'Dimension', 2, ...
    'Index', 60)
```

## Slice 模式

- 未在命令行指定 `Dimension` 时才显示维度下拉框；`1/2/3` 也可以写成
  `I/J/K` 或 `X/Y/Z`。
- 未在命令行指定 `Index` 时才显示索引滑块和数值输入框，初值为该维度中点。
- 未指定 `ColorLimits` 时显示全局/当前切片色标范围下拉框。
- 命令行已经指定的参数不会在窗口中重复提供相应控制项。
- 显示当前切片和完整三维数组各自的 min/max。
- 色标可以在“全局范围”和“当前切片”间切换，colorbar 始终显示。
- 切换维度时，会按原切片在轴上的相对位置选择新索引，而不是突然跳到边界。

## 模式切换

只有命令行未指定 `PlotType` 时，窗口才显示“绘图模式”下拉框，可以在
`Volume（三维等值面）` 和 `Slice（二维切片）` 之间切换。切换会立即重建当前窗口中的
绘图区和当前模式所需的下级控制项，同时复用内存中已经加载的数组，不会再次读取 MAT
文件。命令行已指定 `PlotType` 时，不显示模式下拉框。

## 三维模式的选择

三维标量场没有唯一的“等高线图”。这里以**多层等值面**作为默认方案：二维等高线表示
`f(x,y)=c`，其自然的三维对应物就是 `f(x,y,z)=c` 的曲面。

Volume 参数也采用逐级兜底：

- 未指定 `NumIsosurfaces` 时显示等值面数量控件，默认 5 层。
- 未指定 `IsoRange` 时显示范围输入框，默认覆盖全局范围的 15%--85%。
- 未指定 `SurfaceAlpha` 时显示透明度滑块，默认 0.22。
- 可以通过 `IsoValues` 精确给出每个等值面值；此时不再显示数量和范围控件。
- 命令行已经指定的三维参数按原值绘制，不在窗口中重复提供相应控件。

例如：

```matlab
visualizeMatField(matFile, 'rho.rho_XYZ', 'PlotType', 'volume', ...
    'IsoValues', [0.35 0.60 0.85], 'SurfaceAlpha', 0.20)
```

为了让交互速度可接受，三维绘制默认将每个轴采样到不超过 96 个点；界面中的全局统计
仍来自完整数组。

参数严格按层级校验：`Index` 依赖 `Dimension`，切片参数依赖显式的 `slice/figure`
模式，等值面参数依赖显式的 `volume` 模式。缺少上级选择会直接给出说明性错误。

其他方案的适用范围：

- **三正交切片**：内部结构最清晰，但本质仍是若干二维平面，已经由 slice 模式覆盖。
- **体渲染**：适合烟雾状连续介质，但依赖传递函数，参数不当容易产生误导，并可能需要
  Image Processing Toolbox。
- **单等值面**：形状最清楚，但容易遗漏其他数值层次。

因此当前实现采用多等值面作为稳定、依赖少且最接近等高线语义的三维默认图。

## 维度约定

图中有意使用 `Dim 1/2/3`，没有擅自把数组维度解释成物理 `X/Y/Z`。这是因为项目同时
保存了 `*_IJK` 和 `*_XYZ` 字段，其内存维度与物理坐标的对应关系需要由数据生成约定确认。
三维图的三个坐标轴严格对应 MATLAB 数组的第一、第二和第三维。
