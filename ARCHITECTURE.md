# 二维/三维场可视化器代码结构

## 1. 项目定位

`visualizeMatField` 用于从 MAT 文件、MATLAB Base Workspace 或调用时直接传入的内存值中
发现并加载符合规则的实数数值二维/三维数组，以二维切片或三维等值面方式交互显示。
对外只有 `visualizeMatField.m` 一个公共入口；实现代码位于 `+matfield` MATLAB 包中。

## 2. 目录与模块

```text
SwirlFlame/
├─ visualizeMatField.m          公共入口、帮助文本和最高层流程
├─ +matfield/                   内部实现包，不作为独立路径加入 MATLAB path
│  ├─ Input.m                   位置参数/Name-Value 解析与依赖校验
│  ├─ Data.m                    三种数据源的统一调度接口
│  ├─ FieldRules.m              目标数组分类、嵌套遍历和公共数值校验
│  ├─ MatSource.m               MAT 路径解析、变量发现和按目标加载
│  ├─ WorkspaceSource.m         Base Workspace 枚举、读取和刷新
│  ├─ MemorySource.m            直接数组/标量结构体的快照发现和读取
│  ├─ Viewer.m                  figure 生命周期、数据源回调和视图切换协调
│  ├─ SelectionView.m           尚未选择变量时的空绘图区与禁用控制台
│  ├─ SliceView.m               Slice 控件、回调、渲染和索引播放帧推进
│  ├─ VolumeView.m              Volume 控件、回调、等值面渲染和单值播放帧推进
│  ├─ Layout.m                  三分区布局及 wide/compact/narrow 响应式重排
│  ├─ Playback.m                公共 timer 启停、周期更新和销毁
│  └─ Graphics.m                colorbar、滑条、数值格式和图形句柄工具
├─ tests/
│  └─ testVisualizeMatField.m   公共流程回归测试
├─ demoVisualizeMatField.m      常用调用示例
└─ VISUALIZATION.md             面向使用者的参数与交互说明
```

`+matfield` 是 MATLAB package 目录。调用方只需把 `SwirlFlame` 根目录加入路径，
不要单独执行 `addpath('+matfield')`。包内模块采用静态方法类，仅用于组织命名空间，
不创建模块对象。

## 3. 模块关系

```text
visualizeMatField
   ├── Input ──────────────── 参数规范化与层级约束
   ├── Data ───────────────── 统一数据源门面
   │     ├── MatSource
   │     ├── WorkspaceSource
   │     ├── MemorySource
   │     └── FieldRules ───── 三种来源共享的目标数组规则
   └── 选择一种界面状态
       ├── SelectionView ─┐
       ├── SliceView ─────┼── Viewer ── 数据源选择、变量/模式切换
       └── VolumeView ────┘
              │
              ├── Layout ───── Graphics
              ├── Graphics
              └── Playback ─── MATLAB timer 生命周期
```

- `Input` 和数据源适配层不读取 figure 状态；视图不会判断数据究竟来自磁盘还是工作区。
- `Graphics` 是无业务含义的图形工具层；`Layout` 只重排控件，不加载数据或重绘场。
- `SelectionView`、`SliceView`、`VolumeView` 是并列视图模块。Slice 与 Volume 不直接
  切换彼此，由 `Viewer` 统一协调。
- 视图把数据源、变量、模式和 MAT 路径控件的事件交给 `Viewer`；`Viewer` 根据结果重新建立
  对应视图。这是控制器与视图之间的事件回路，不是数据层的循环依赖。
- `Playback` 只管理公共 timer 状态；具体“下一帧是什么”分别由 Slice/Volume 模块决定。

## 4. 典型运行流程

1. `visualizeMatField` 调用 `Input.parse`，统一识别两个可选位置参数和所有 Name-Value
   参数，并检查参数间的逐级依赖。
2. `Input` 建立统一 `Source` 描述：`matfile`、`workspace` 或 `memory`。MAT 相对路径由
   `MatSource` 解析；函数局部变量在调用时直接进入 `MemorySource`，不依赖后续 caller。
3. 若未指定目标变量，`Data.listTargets` 委托当前适配器，只寻找合法二维/三维实数数值
   数组，然后进入 `SelectionView`；数据源尚未就绪时保持变量选择和控制台禁用。
4. 变量确定后，`Data.loadTarget` 通过同一接口获得最终数组；
   `Data.validateLoadedArray` 计算有限值全局范围，但不改变大型数组的原始数值类型。
5. `Data.resolvePlotTypeForField` 根据二维/三维约束确定 Slice 或 Volume。
6. 对应视图通过 `Viewer.createViewerShell` 建立“数据源区、绘图区、控制台区”，再建立
   模式专属控件和状态，最后调用本视图的 `render...` 方法。
7. 控件回调遵循“读取 `fig.UserData` → 校验/更新状态 → 写回状态 → 局部重绘”的顺序。
8. 更换变量或模式时，`Viewer` 先保留可复用参数与内存中的数据，再在同一个 figure 中
   建立目标视图；调整窗口大小则只由 `Layout` 重排，不触发数据加载或等值面计算。

## 5. figure 状态约定

运行状态集中保存在 `fig.UserData`，避免全局变量和 `persistent` 状态。模块之间不传递一串
松散句柄，而是以该状态结构作为统一契约。

公共字段主要包括：

- 来源：`Source`（类型、位置、显示名以及内存根值）、`Variable`。
- 数据：`Data`、`DataSize`、`FieldDimension`、`GlobalRange`。
- 配置：`Options`、`PlotMode`。
- 图形：`Axes`、`Colorbar`、`Layout`、数据源控件句柄。
- 生命周期：`PlaybackTimer`、`PlayButton`。

Slice 另外保存 `Dimension`、`Index`、`ColorMode`、`CustomClim`、`Image` 等；Volume
另外保存 `IsoSelectionMode`、`IsoValues`、`ExactIsoValue`、`SurfaceAlpha`、`Patches`、
相机/工具栏相关句柄等。`SelectionView` 只保存建立空状态所需的公共字段。

## 6. 维护边界

- 新增公共参数：先在 `Input` 中完成解析、默认值和层级校验，再在相关视图消费。
- 新增目标数组规则：修改 `FieldRules`，不要在每个数据源或渲染函数中重复判断。
- 新增数据来源：实现与 `MatSource`/`WorkspaceSource`/`MemorySource` 相同的发现和加载
  契约，再在 `Data` 中增加分派。
- 新增/调整控件：视图负责创建与业务回调，`Layout` 负责不同窗口宽度下的位置。
- 修改绘制算法：放入 `SliceView.renderSlice` 或 `VolumeView.renderVolume`，不要让布局回调
  触发重新读取数据源。
- 新增播放方式：公共启停行为留在 `Playback`，帧值推进留在所属视图。
- MATLAB UI 数值属性需要 `double` 时，只转换传入 UI 的标量/小数组；原始场数据继续
  保持其来源中的类型。

## 7. 验证

在 MATLAB 中运行：

```matlab
cd('D:\myDocuments\BUAA\NeRF-RI\CFDdata\SwirlFlame')
results = runtests(fullfile('tests', 'testVisualizeMatField.m'));
assertSuccess(results)
```

测试覆盖数据源切换、MAT/Workspace/Memory 变量选择、Workspace 刷新、二维 Slice、
三维 Slice、Volume、模式往返切换、播放和响应式布局。涉及视觉布局或三维鼠标交互的
改动，自动测试通过后仍应使用真实可见窗口进行一次人工检查。
