# Python 模块关系与维护指南

## 目录与分层

```text
python/
├── pyproject.toml           包、依赖和 fieldviz 命令入口
├── src/fieldviz/
│   ├── api.py               主线程/API 参数入口、应用与窗口生命周期
│   ├── cli.py, __main__.py  命令行参数 → 同一个 API
│   ├── core.py              目标规则、ArrayHandle、Options、ViewState（无 Qt）
│   ├── sources/            数据来源适配层（无 Qt）
│   │   ├── base.py          DataSource 接口、路径标识规则
│   │   ├── files.py         MAT / NumPy / HDF5
│   │   ├── memory.py        内存快照、显式 namespace、Tensor 转换
│   │   └── optional.py      PT / Safetensors / Zarr，按需导入依赖
│   ├── rendering.py        准备切片/计算等值面；工作线程可执行
│   ├── jobs.py             最新请求调度、过期结果丢弃、关闭处理
│   ├── window.py           三分区 UI 组装、状态流转、信号接线
│   ├── views.py            持久 PyQtGraph 与 PyVista 渲染窗口
│   └── widgets.py          自适应控制组、输入/滑条、独立颜色栏
├── examples/demo.py        无外部数据的最小示例
└── tests/                  核心、格式、GUI、MATLAB 互操作与可视检查
```

MATLAB 代码完全保留在平行的 `matlab/` 中。Python 包不导入 MATLAB 文件，不通过 MATLAB 引擎绘图。

## 依赖和通信

```text
CLI ─┐
     ├→ API → Options → Source 适配器 → Target 列表
脚本 ─┘                      │             │ 选择目标
                             └────→ ArrayHandle → ViewState
                                                    │
                    Qt 信号 → ViewerWindow ← UI 控件 ┘
                                  │
                         LatestJob（后台线程）
                                  │
                      prepare_slice / prepare_mesh
                                  │ Qt 排队信号，仅交付最新结果
                     SliceView / IsosurfaceView + ColorBar
```

数据层不引用窗口或 Qt；绘图准备层不读取控件；所有图形对象修改均在主线程。
没有事件总线、RPC、数据库或跨进程通信。窗口拥有一个 `ViewState`，UI 信号更新该状态；
后台任务只捕获一次计算所需的句柄和参数，不访问不断变化的控件。

### 三个顶层区域

1. **来源/变量区域**：Qt 栅格布局。路径、变量文本可在控件内水平滚动/省略，不把整个界面撑出窗口。
2. **绘图区**：持久的堆叠视图 + 独立颜色栏。颜色栏根据字体测量结果保留完整标签宽度，不挤占或裁切数字。
3. **控制台**：`AdaptiveGrid` 随宽度换列，外部 `QScrollArea` 处理高度不足，底部始终留出内边距。

设置合理的最小窗口尺寸，不以负尺寸或越界绝对坐标布局强行容纳过小窗口。
相机与控件区布局没有耦合；自动多层/单值切换只更新网格，不重建相机。

## 生命周期

`visualize_field` 校验参数、解析来源、必要时读取初始目标 → 创建/复用 QApplication → 创建窗口。
无来源或无目标时进入空闲选择状态。用户选择后后台读取并统计，再生成 `ViewState`。
绘图控制按维度、模式和显式参数决定显示/禁用。

`run()` 只为普通脚本启动 Qt 事件循环。IPython 使用自己的 Qt 集成。
关闭窗口时停止播放和节流计时器、失效化任务、关闭绘图器及来源。
已开始的原生计算不能安全强行中断，因此允许其完成，但不再向已关闭窗口交付结果。
极慢任务可能使 Python 进程完全退出稍有等待；不会后台继续刷新已关闭界面。

## 性能和正确性约束

- `LatestJob` 每条队列最多一个运行任务、一个待执行最新任务。新拖动覆盖待执行任务，不积累长队列。
- UI 修改约 40 ms 节流；昂贵等值面结果若已过期则不显示。持续快速拖动三维滑条时可保留上一幅完成画面，
  松手后交付最新画面；不宣称每个鼠标事件都能产生完整三维帧。
- 播放在上一帧完成后才推进，不通过无限堆积定时器追赶时间。
- 全局有限值范围分块统计并缓存；只有目标更新/刷新才重新统计。
- 源数据类型不因控件而转换；为 VTK 转换的只是有限大小的绘制副本。
- HDF5/MAT v7.3 是按需读取；MAT 经典格式必须读取顶层候选，嵌套 struct 还需额外类型识别，不能假装廉价元数据访问。
- MemorySource 明确复制合法数组叶节点形成快照，内存开销约增加一份数据；NamespaceSource 只复制选中目标。
- v7.3 MAT 的文件维度在适配器中恢复为 MATLAB 数组顺序；普通 HDF5 不做反转。
- GUI 不知道 HDF5/NPZ/MAT 如何存储，只操作统一 `ArrayHandle`。

## 后续扩展位置

- 新文件格式：实现 `DataSource.list_targets/open_target`，在 `sources/__init__.py` 中注册，并添加方向/类型测试。
- 新渲染算法：在 `rendering.py` 添加准备函数，在 `views.py` 加持久视图；不要向数据适配器加入 GUI 代码。
- 新参数：先在 `Options` 明确依赖与互斥规则，再添加 UI 分支、API/CLI 参数及测试。
- 真体渲染、显式时间轴、坐标向量、数据导出均可后续加入，但不能根据 Dim1/2/3 自动猜测物理含义。

建议阅读顺序：`api.py` → `core.py` → `sources/base.py` → `window.py` → `rendering.py`。
