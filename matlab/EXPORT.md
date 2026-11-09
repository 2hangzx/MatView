# 图片、播放动画与原始切片导出

窗口顶部新增“导出”菜单：图片、播放动画和当前切片数据。
尚未选定目标时全部禁用；二维静态数组不能导出动画，Volume 自动多层模式也不提供动画。
三维 Slice 或“指定单值”模式可导出 GIF/视频；显式 `IsoValues` 只有一个数值时也支持动画。
显式固定索引/单值并不阻止导出独立扫描序列，原窗口的固定参数保持不变。

## 图片

```matlab
fig = visualizeMatField(A);
exportMatField(fig, 'plot.png', 'Width', 1600, 'Height', 1200);
```

支持 PNG/JPEG/TIFF。导出只包含当前图像、坐标轴、标题和完整颜色栏，排除文件选择区、控制台及工具按钮。
导出使用独立 figure，复制当前坐标轴和图形，颜色栏重新排版，保留当前切片、色图、颜色范围、透明度和观察视角。
字号/边距可能与屏幕窗口略有不同，不是窗口截图。所有导出结果写入指定路径，读取和交互不会修改数据来源。

`Width/Height` 是像素，默认 1600×1200；宽 320–8192、高 240–8192，总像素不超过 3200 万。
精确像素与留白控制使用 MATLAB R2025a 起提供的 `exportgraphics` 参数；当前在 R2026a 验证。
实现依据：[MathWorks exportgraphics 文档](https://www.mathworks.com/help/matlab/ref/exportgraphics.html)。

## 导出部件

图片和动画共用“导出部件”勾选区。图像主体固定保留，其他选项默认全选。
取消坐标轴或颜色栏时，其标签和刻度会禁用。重新选中上级会恢复下级原有的勾选状态。
标签指 `Dim 1 index`、`Value` 等名称，刻度包含刻度线和数字。

`Components` 指定要保留的可选部件。坐标轴组为 `axes`、`axis_labels`、`axis_ticks`，
颜色栏组为 `colorbar`、`colorbar_label`、`colorbar_ticks`，标题为 `title`。
省略 `Components` 时全部保留，传入 `[]` 时只导出图像主体。子项只在其上级也被选中时生效。

```matlab
exportMatField(fig, 'plot.png', 'Components', {'axes', 'axis_ticks', 'colorbar', 'colorbar_ticks'});
exportMatField(fig, 'body.png', 'Components', []);
```

## 自动播放序列

```matlab
fig = visualizeMatField(A, 'PlotType', 'slice', 'Dimension', 3, 'Index', 20);
exportMatField(fig, 'scan.gif', 'Frames', 60, 'FrameRate', 10);
exportMatField(fig, 'scan.mp4', 'Frames', 60, 'FrameRate', 10, ...
    'Width', 1280, 'Height', 960);
```

- 第一帧是当前画面；Slice 逐索引 +1，到末尾回到 1；Volume 单值按全局值域的 1% 增加，超过最大值后回到最小值。
- 默认帧数为当前切片维度的长度，或 101 个单值帧；默认帧率取当前播放间隔的倒数。
- `Frames` 是 1–10000 的整数，`FrameRate` 在 0.1–60 范围。GIF 无限循环；MP4/AVI 保存有限序列。
- GIF 时间间隔以 10 ms 为单位，最多 256 色；MP4/AVI 有损压缩，不适合作为数值数据存档。
- MP4 要求宽高为偶数，使用平台支持的 MPEG-4 编码；AVI 使用 Motion JPEG AVI。
- 不依赖实际屏幕播放速度：逐帧计算、写入，不因慢帧跳过数据。
- GUI 有进度和取消；先写临时文件，全部成功后替换目标，取消/失败不会覆盖已有目标文件。
- 导出不推进原窗口的索引/数值，也不改变相机。开始前暂停播放，导出完成或取消后恢复原播放状态。

这是导出从当前值开始的一段扫描序列，不是录制鼠标交互，也没有额外推断时间维。
常量场或某些极值可能生成空表面，仍保留坐标轴、标题和颜色栏。

## 当前切片数据

```matlab
fig = visualizeMatField(A, 'PlotType', 'slice');
exportMatField(fig, 'slice.mat');
exportMatField(fig, 'slice.csv');
```

二维数组与三维 Slice 均支持。保存的是**原数组顺序的数值切片**，不会执行显示转置、颜色映射或归一化。
例如固定 Dim 2，则 `data` 的两维分别对应原来的 Dim 1、Dim 3；第一维在查看器中沿水平方向显示。

- MAT 包含 `data`（保留原始 single/double/整数类型）和 `metadata` 结构体。
- CSV 保存原始数值，附带 `slice.csv.json` 元信息；CSV 不自带数值类型，读取时依据元信息指定类型。
- 元信息记录变量名、来源类型、原始形状、保留维度、额外索引、切片维度与索引、数据两维对应的原数组维度、色图和颜色范围。
- 导出的是完整当前切片，不受显示中的平移/缩放或 Volume 采样影响。

`exportMatField` 只有 `fig`、输出路径采用位置传参，其余均为 Name-Value；根据文件扩展名选择导出类别，无须再传模式参数。
程序调用可以传 `'Progress', @(done,total) ...`，返回 false 时取消动画并抛出 `visualizeMatField:ExportCancelled`。

## 验证

`runtests('tests/testExport.m')` 覆盖图片尺寸、MAT/CSV 数值与元信息、GIF 帧数/间隔、MP4 读回、取消保护以及原窗口状态保持。
导出升级后，完整 `runtests('tests')` 的 40 项测试在 MATLAB R2026a 下全部通过。
`addpath('tests'); visualExportSmoke` 在被忽略的 `artifacts/export/` 下生成两种模式的 PNG/GIF 和 MAT 数据，供人工检查。
