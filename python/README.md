# FieldViz：Python 二维/三维数组查看器

这是 MATLAB `visualizeMatField` 的独立 Python 桌面移植版，不需要 MATLAB 运行时。
保持“来源 → 合法数组 → 绘图模式 → 模式参数”的逐级控制规则。
二维数组只能显示切片；三维数组支持切片和半透明等值面。
这里的 `volume` 仍指原项目的**等值面**，不是光线投射体渲染。

## 快速开始

建议使用 Python 3.12（包要求 Python ≥ 3.11）和有图形桌面的环境。在本目录运行：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
.\.venv\Scripts\python.exe -m fieldviz
```

最后一条命令打开空查看器。在路径框输入文件路径并按 Enter，或点击“浏览…”，然后选择目标数组。
相对路径始终相对于**进程当前工作目录**，与函数传参完全一致；不会相对于脚本或安装目录猜测路径。
Zarr 是目录存储，请在路径框直接输入 `.zarr` 目录路径。

也可以运行不依赖外部文件的示例：

```powershell
.\.venv\Scripts\python.exe examples/demo.py
```

Linux/macOS 将 `.\.venv\Scripts\python.exe` 换成 `.venv/bin/python`。
已在 Windows 实测；其他系统尚未实机验证，需要相应 Qt/VTK 图形驱动支持。

## 命令行

```powershell
# 选择 MAT 内的变量
.\.venv\Scripts\python.exe -m fieldviz ../Data/data_uniGrid_zFlowDirct.mat

# 精确指定切片；维度与索引均从 1 开始
.\.venv\Scripts\python.exe -m fieldviz ../Data/data_uniGrid_zFlowDirct.mat --field T.T_XYZ --mode slice --dimension 3 --index 80

# 一个或多个指定数值的等值面
.\.venv\Scripts\python.exe -m fieldviz ../Data/data_uniGrid_zFlowDirct.mat --field rho.rho_XYZ --mode isosurface --iso-values 0.4 0.7

# 查看完整参数
.\.venv\Scripts\python.exe -m fieldviz --help
```

安装环境已激活时，`fieldviz` 与 `python -m fieldviz` 等价。
`Data/` 保留在项目根目录，由 MATLAB/Python 共享，不复制大型文件。

## Python 中调用

只有 `source` 可以作为位置参数，其余参数一律使用关键字。
完整参数规范见 [API.md](API.md)。

```python
import numpy as np
from fieldviz import visualize_field, run

array = np.random.default_rng(42).random((40, 58, 60), dtype=np.float32)
window = visualize_field(array)   # 直接数组立即绘图；默认三维等值面
run()                             # 普通脚本需要 Qt 事件循环
```

其他独立调用示例：

```python
window = visualize_field()  # 空窗口，先选文件再选变量
window = visualize_field("data.mat", field="flow.temperature")
window = visualize_field(array, mode="slice", dimension=2, index=20)
window = visualize_field({"flow": {"temperature": array}})  # 先在窗口选变量
window = visualize_field(namespace=globals())  # 显式浏览当前 Python 命名空间
```

IPython/Jupyter 本地内核先执行 `%gui qt`，再调用 `visualize_field`，不再调用 `run()`。
这是本地桌面窗口，不是浏览器内的 Notebook 控件；远程无桌面内核不能直接弹出本机窗口。

### Python 的“工作区”

- **直接值**：`visualize_field(A)` 或 `visualize_field(nested_dict)`，适合函数局部变量。
- **显式命名空间**：`visualize_field(namespace=globals())`；IPython 也可传 `get_ipython().user_ns`。
- 不自动扫描进程、调用栈或最初调用函数的局部工作区，不读取其他进程/IDE 的变量。
- 内存来源建立快照；命名空间在选择变量或点击“刷新来源”时建立该变量的快照。
- 不实时监视外部赋值。修改工作区变量后点击“刷新来源”才重新读取；这与播放/滑条自动重绘是两回事。

## 文件与数据类型

| 来源 | 支持范围 | 读取方式 |
|---|---|---|
| MAT v4/v5/v6/v7–7.2 | 实数数组、嵌套标量 struct | SciPy；按顶层变量读取，不能保证嵌套字段惰性读取 |
| MAT v7.3 | 同上，包括标量 struct 引用 | HDF5 元数据扫描；选中后按需读取 |
| `.npy` | 单个数值数组 | 内存映射；自动选中数组 |
| `.npz` | 多个命名数值数组 | 先读数组头；选中后解压该数组 |
| `.h5` / `.hdf5` | 嵌套组中的实数数据集 | 按需读取；不应用 MATLAB 的维度反转 |
| `.pt` / `.pth` | Tensor 或嵌套字典中的 Tensor | 可选 PyTorch；只使用 `weights_only=True` 加载 |
| `.safetensors` | 支持的数值 Tensor | 可选；先读元数据，再读所选 Tensor |
| `.zarr` | 数组或组中的数组 | 可选；按需分块读取 |
| NumPy / Torch / dict | 直接函数参数 | 只读数据快照 |
| Python namespace | 显式传入的字典/Mapping | 列举合法叶节点，选择后建立快照 |

可选依赖：

```powershell
.\.venv\Scripts\python.exe -m pip install -e ".[storage]"
# 如仅需 CPU Tensor/PT 文件，安装 CPU 版 PyTorch：
.\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cpu
```

GPU Tensor 会 `detach()` 后复制到 CPU；不更改原 Tensor，不保留梯度关系。
通常保留原始数值类型（`single` → `float32`，`double` → `float64`）。
例外：NumPy 不原生支持的 Torch `bfloat16` 转为 `float32`；VTK 只将**降采样的绘制副本**转为 `float64`。
原始大数组不会因为绘图控件需要浮点标量而整体提升精度。

合法目标与当前 MATLAB 版一致：去除尾随单例维度后，恰为二维或三维，且每个有效维度长度均大于 1。
因此 `[m,n,1]` 视为二维；不会用 `squeeze()` 猜测内部单例维度的含义。
排除标量、向量、空数组、复数、布尔、字符串、对象数组、稀疏数组、四维及以上有效数组。
不展开 cell、非标量 struct、任意对象属性或列表。

## 已实现交互

- 省略来源/变量时空窗口等待选择；没有目标时绘图控制禁用。
- 省略模式时可在窗口切换；二维目标自动约束为 Slice。
- 切片维度、索引输入/滑条、全局/当前切片/自定义颜色栏上下限及粗调滑条。
- 自动多层等值面的数量、值域百分比，以及指定单值的输入/滑条。
- 透明度实时更新，不重新计算等值面；数量/范围改动自动重绘。
- 切片索引与单值等值面循环播放；慢帧不会积压播放任务。
- 全局与切片有限值统计、颜色栏、三维旋转/平移/缩放及复位。
- 三个独立布局区域；控制组随宽度换列、短窗口滚动，颜色栏预留实际数字宽度。

## 边界与安全

- 全局统计遍历完整数据，等值面默认每轴最多约 96 个采样点；细小结构可能被采样遗漏。
  调高 `max_render_size` 可以提高质量，但会增加计算量与内存。
- 常量场、极值或某些非有限值区域可能没有等值面，界面会明确提示；颜色栏仍存在。
- 不覆盖或写回来源文件。NumPy 禁用 pickle；Torch 不回退到不受限的反序列化。
  这些措施不等于安全沙箱：仍只应打开可信文件，超大文件可能消耗大量资源。
- 展示标量采用 Python 双精度；极大整数（超出 `2**53`）或极端动态范围可能无法逐个位精确标注，原数据保持不变。
- 不自动转换整个数据集、不提供跨进程 Workspace、不支持真体渲染/时间轴语义推断。

模块关系见 [ARCHITECTURE.md](ARCHITECTURE.md)，迁移及验证记录见 [TESTING.md](TESTING.md)。
