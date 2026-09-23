# 迁移与验证记录

## Git 与目录隔离

- MATLAB 整理提交：`14e6593`，位于原分支 `alpha1.0`。
- 将现有可视化入口、`+matfield/`、测试及 Markdown 文档迁入 `matlab/`；同步调整演示路径。
- 原本被忽略的旧 `Code/` 保留并移入 `matlab/Code/`，未强制纳入版本管理。
- 大型共享 `Data/` 保持原位和忽略规则。
- 从该整理提交建立 `python` 分支。Python 实现、文档、测试均位于 `python/`。
- 不依赖 MATLAB 引擎；MATLAB 仅用于可选的跨语言一致性测试。

## 本机已验证环境

Windows，Python 3.12.14，MATLAB R2026a。

| 组件 | 本次使用版本 |
|---|---|
| NumPy / SciPy | 2.5.3 / 1.18.1 |
| h5py | 3.16.0 |
| PySide6 / PyQtGraph | 6.11.2 / 0.14.0 |
| PyVista / PyVistaQt / VTK | 0.48.4 / 0.13.1 / 9.6.2 |
| PyTorch | 2.14.0+cpu |
| Zarr / Safetensors | 3.4.0 / 0.8.0 |
| pytest / pytest-qt | 9.1.1 / 4.5.0 |

项目使用版本范围而非这些版本的完整锁文件。其他操作系统、GPU Tensor、远程内核和旧版图形驱动未做实机验证。
硬件渲染差异不保证逐像素复现 MATLAB 图像；验证重点是数值、维度、交互和布局。

## 运行测试

在 `python/` 下：

```powershell
.\.venv\Scripts\python.exe -m pip install -e ".[dev,storage]"
# 可选：安装 Torch，相关测试在缺少它时会跳过
.\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cpu
New-Item -ItemType Directory -Path artifacts -Force
.\.venv\Scripts\python.exe -m pytest -q --basetemp=artifacts/pytest-local
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pip check
```

`--basetemp` 指定 pytest 专用临时目录，每次运行会清理其旧内容，不要指定存有用户数据的目录。
GUI 测试会短暂创建并关闭窗口，不更改来源文件。

### MATLAB 原生互操作

在 `python/` 目录启动 MATLAB，执行：

```matlab
run('tests/generate_matlab_fixture.m')
```

它在 `tests/generated/` 生成小型 v7/v7.3 MAT，包含不对称尺寸、float32 三维数据、二维平面、嵌套 uint16、logical 和 complex。
再次运行 Python 测试会检查精确数值、数组方向、类型保持，以及非法目标排除。
未生成文件时仅这两项互操作测试跳过，不会使普通用户安装依赖 MATLAB。

### 窗口可视检查

```powershell
.\.venv\Scripts\python.exe tests/visual_smoke.py
```

在 `artifacts/` 生成宽/窄窗口 Slice 与等值面的截图；若共享 `Data/` 中存在原始密度场，还会绘制真实 MAT 数据。
截图和测试数据均被 Git 忽略。

## 已验证内容

- 移动后的 MATLAB 测试：16 项通过。
- 本次 Python 自动测试：50 项全部通过，包含可选存储与 MATLAB 原生互操作，没有跳过项；静态检查、依赖检查和 wheel 构建通过。
- Python：数据分类、原始精度、三个方向的切片、等值面坐标、默认层级和参数互斥。
- `.npy/.npz/.h5`、经典 MAT、v7.3 MAT、Zarr、Safetensors、Tensor/PT 的读取及方向一致性。
- MATLAB 原生 v7/v7.3 文件的精确互操作；复杂和逻辑变量不会误当作数值目标。
- 空窗口、文件/变量选择、二维模式限制、显式参数隐藏、命名空间刷新。
- 滑条/输入触发重绘、颜色栏自定义、切片和单层等值面循环播放。
- 自动/单值切换保持相机；透明度修改不重算网格。
- 最新任务替换旧请求；关闭窗口停止投递结果；错误文件可恢复。
- 宽/窄窗口的实际截图检查，颜色栏数字完整、控制台可滚动。
- 原项目 `data_uniGrid_zFlowDirct.mat` 检出 30 个目标数组；`rho/rho_XYZ` 为 `(161,161,159)` float64，
  全局范围约 `0.15265021347792043–1.1284938241159597`，默认绘制采样为 `(81,81,80)`。

目前依赖库会产生 NumPy 2.5 对 VTK 内部数组形状赋值、hdf5storage 内部 chararray 的弃用警告；
未屏蔽这些测试警告，它们不影响本次结果。

## 后续建议验证

长期大数组播放的内存/驱动稳定性、多显示器缩放比例、Linux/macOS 图形环境、GPU Tensor 复制成本。
不能把已有自动测试等同于所有真实数据和所有设备都经过验证。
