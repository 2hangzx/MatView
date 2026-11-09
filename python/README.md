# FieldViz：Python 二维/三维数组查看器

这是 MATLAB `visualizeMatField` 的独立 Python 桌面移植版，不需要 MATLAB 运行时。
保持“来源 → 合法数组 → 高维子数组选择（如需要）→ 绘图模式 → 模式参数”的逐级控制规则。
二维数组只能显示切片；三维数组支持切片和半透明等值面。
这里的 `volume` 仍指原项目的**等值面**，不是光线投射体渲染。
四维及以上实数数组可先固定额外维度的索引，再按二维/三维子数组绘图。

## 快速开始

### Conda / Miniconda（换设备安装）

先复制或克隆完整项目，在终端中进入 `SwirlFlame/python` 目录；Windows 可使用 Miniconda Prompt。
不要只复制环境文件，因为安装时还需要这里的 `pyproject.toml` 和 `src/`。

```shell
conda env create -f environment.yml
conda activate fieldviz
python -m pip check
python -m fieldviz
```

这会创建独立的 Python 3.12 环境，安装查看器、基础依赖，以及 Zarr/Safetensors 支持。
Conda 负责 Python 和 pip；应用依赖由 pip 统一安装，避免给 Qt/VTK/NumPy 同时安装两套发行包。
环境文件不包含当前机器的绝对路径、CUDA 或平台专属构建编号。

已有适用的独立 Conda 环境时，激活后在本目录执行：

```shell
python -m pip install -r requirements.txt
python -m pip check
```

`requirements.txt` 通过 `-e .[storage]` 引用本项目，实际依赖和版本范围仍统一由 `pyproject.toml` 管理。
它是 **pip requirements**，不是 `conda install --file` 接受的 Conda 包清单。
这里采用可编辑安装：迁移时要复制源码并重新安装，不要复制旧 `.venv`/Conda 环境，也不要在安装后直接移动或删除源码目录。

#### 可选：Torch 与开发测试

只有读取 `.pt/.pth` 或直接传入 Tensor 时才需要 Torch。Windows/Linux 仅需 CPU 支持时：

```shell
python -m pip install "torch>=2.6" --index-url https://download.pytorch.org/whl/cpu
```

macOS 可使用 `python -m pip install "torch>=2.6"`。如需要 GPU 版，请根据目标机器按
[PyTorch 官方安装说明](https://pytorch.org/get-started/locally/)选择安装命令；不把一台机器的 CUDA 配置写入通用环境文件。
需要开发测试工具时执行 `python -m pip install -e ".[dev,storage]"`。
安装后可运行 `python examples/demo.py` 验证桌面绘图。

默认环境名为 `fieldviz`。如已存在同名环境，可使用
`conda env create -n fieldviz-new -f environment.yml` 创建新环境，再 `conda activate fieldviz-new`，不会覆盖旧环境。
这些文件用于**可迁移安装**，不是精确锁定全部传递依赖的 lock 文件；不同时间解析出的兼容版本可能不同。
如需严格复现实验，还应记录同一系统上的具体包版本和图形驱动信息。

环境声明采用 [Conda 的 environment.yml 格式](https://docs.conda.io/projects/conda/en/stable/user-guide/tasks/manage-environments.html#creating-an-environment-from-an-environment-yml-file)，
pip 清单格式见 [pip 官方说明](https://pip.pypa.io/en/stable/reference/requirements-file-format/)。

### venv（不使用 Conda）

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

直接绘图目标仍遵循原规则：去除尾随单例维度后，恰为二维或三维，且每个有效维度长度均大于 1。
因此 `[m,n,1]` 视为二维；不会用 `squeeze()` 猜测内部单例维度的含义。
Python 版另支持四维及以上实数数组作为子数组来源，至少需要两个长度大于 1 的维度；
最终绘图目标仍是二维/三维。不会根据末维长度是 3 就自动解释为 RGB 或矢量。
排除标量、向量、空数组、复数、布尔、字符串、对象数组、稀疏数组。
不展开 cell、非标量 struct、任意对象属性或列表。

## 高维数组：例如 image_pred.npy

对于形状 `(161, 161, 159, 3)` 的文件，可以直接打开：

```shell
python -m fieldviz "D:/myDocuments/temp/image_pred.npy"
```

默认保留 Dim 1/2/3，Dim 4 取索引 1；控制台新增“额外维度选择”组。
用 Dim 4 索引输入框或滑条切换 1/2/3 后自动重绘，不需要另存文件或点击重绘按钮。
界面中的原始形状、保留维度、固定索引和“当前子数组全局”范围说明正在显示哪一部分数据。
切换额外维度索引会停止播放，并更新所选子数组的统计和颜色栏；保留维度不变时保留视角和适用的绘图设置。

“保留维度”可输入递增的两个或三个原数组维度编号，例如 `1, 2, 3`、`1, 3, 4` 或 `2, 4`。
其余维度各自出现索引控件；长度为 1 的额外维度固定在索引 1。保留两个维度时仅提供二维 Slice。
坐标标签始终对应原数组：保留 `1, 3, 4` 后，坐标/切片维度显示 Dim 1、Dim 3、Dim 4。
不重排维度、不推断通道/时间/物理坐标。非法选择会回退，保留上一幅有效图像。

也可以精确指定第 4 维第 2 项：

```shell
python -m fieldviz image_pred.npy --retained-dimensions 1 2 3 --extra-index 4=2
```

```python
window = visualize_field("image_pred.npy", retained_dimensions=(1, 2, 3), extra_indices={4: 2})
```

维度编号和索引均从 1 开始。显式指定的保留维度和额外索引在界面固定；未指定的索引可交互调整。
默认选择原数组中最靠前的三个长度大于 1 的维度（只有两个时保留两个），其余维度默认索引 1。
前导或内部单例维度在高维来源中明确固定为索引 1，不会把长度大于 1 的维度悄悄压缩掉。
NPY 内存映射和 HDF5/Zarr 继续按所选子数组读取；内存/Torch 快照及压缩格式的原有加载开销仍然存在。

## 色图选择：Slice 与三维等值面通用

未指定 `colormap` 时默认 `turbo`，控制台提供“色图 (Colormap)”下拉框，优先列出 `jet`、`hot`、
`viridis` 等常用项，也包含当前 Matplotlib 注册的其他色图（含 `_r` 反向色图）。
尚未选择目标时控件禁用。选定色图后，二维图像、三维等值面与颜色栏立即同步更新。
三维等值面按等值面数值映射颜色；透明度和光照仍会影响表面的最终观感。

```shell
python -m fieldviz image_pred.npy --colormap jet
python -m fieldviz image_pred.npy --mode volume --colormap hot
```

```python
window = visualize_field(array, colormap="jet")
window = visualize_field(array, mode="isosurface", colormap="hot")
```

显式指定色图时按既有参数规则固定该设置，隐藏 GUI 选择器；省略时允许交互切换。
换色只更新颜色查找表，不重新读取来源或计算等值面，保留颜色范围、索引、等值面值、透明度和视角。
在同一窗口中切换绘图模式、目标变量、额外维度索引或刷新来源后，继续使用当前色图。
色图决定“数值映射为什么颜色”，颜色栏上下限由 `color_limits` 或相应 GUI 控件独立控制。

## 已实现交互

- 省略来源/变量时空窗口等待选择；没有目标时绘图控制禁用。
- 高维实数来源先选择二维/三维子数组；额外维度索引输入/滑条自动更新画面。
- 二维/三维共用的色图下拉框；切换时保留当前几何与视角。
- 省略模式时可在窗口切换；二维目标自动约束为 Slice。
- 切片维度、索引输入/滑条、全局/当前切片/自定义颜色栏上下限及粗调滑条。
- 自动多层等值面的数量、值域百分比，以及指定单值的输入/滑条。
- 透明度实时更新，不重新计算等值面；数量/范围改动自动重绘。
- 切片索引与单值等值面循环播放；慢帧不会积压播放任务。
- 全局与切片有限值统计、颜色栏、三维旋转/平移/缩放及复位。
- 三个独立布局区域；控制组随宽度换列、短窗口滚动，颜色栏预留实际数字宽度。

## 图片、播放动画与切片数据导出

窗口顶部的“导出”菜单，以及二维/三维绘图区右键菜单，使用同一套导出功能。
图片和动画默认保留绘图区的全部部件。可分别勾选坐标轴、轴标签、轴刻度、标题、颜色栏、颜色栏标签和颜色栏刻度，图像主体始终保留。
标签和刻度依赖对应的坐标轴或颜色栏。关闭上级会禁用子项，重新开启时恢复原有勾选。
设置中可指定宽高像素。二维导出沿用手动平移或缩放后的观察范围，默认视图适配导出画布。
三维导出保留旋转角度，将完整坐标框居中，并在当前缩放会导致裁切时适当缩小。
导出使用独立渲染器，不推进窗口索引，也不修改原始数据；字号和边距可能与屏幕显示略有不同。

| 内容 | 格式 | 启用条件 |
|---|---|---|
| 当前图片 | PNG / JPEG / TIFF | 当前目标完成绘图 |
| 播放序列 | GIF / MP4 | 三维数组的 Slice，或指定单层等值面 |
| 当前切片数据 | NPZ / NPY / MAT / CSV | Slice，二维数组也可用 |

GIF 无限循环；MP4 保存有限序列。第一帧为当前值，之后按现有播放规则推进：切片 +1，单值等值面 +全局值域的 1%，到末尾循环。
可指定帧数和帧率；默认一个切片维度长度，或 101 个单值帧，默认帧率取当前播放间隔的倒数（0.1–60 fps）。
导出逐帧计算并写入，不因机器较慢丢帧；进度窗口可取消，取消后已有目标文件保持不变。
自动多层模式没有天然的播放变量，因此禁用动画项；需要先切到“指定单值”。
显式固定索引/单个等值面仍可导出独立扫描序列，不会解锁或修改原窗口的固定参数。

```python
window = visualize_field(array, mode="slice")
window.export_image("plot.png", width=1600, height=1200)
window.export_animation("scan.gif", frames=60, fps=10, width=1280, height=960)
window.export_animation("scan.mp4", frames=60, fps=10)
window.export_slice_data("slice.npz")
```

```shell
python -m fieldviz image_pred.npy --mode slice --dimension 3 --index 20 --colormap jet --export-image plot.png --export-size 1600 1200
python -m fieldviz image_pred.npy --mode slice --export-animation scan.mp4 --frames 60 --fps 10
python -m fieldviz image_pred.npy --mode slice --export-slice-data slice.npz
```

命令行导出完成后退出；多变量文件需要 `--field` 明确选中目标。无可见窗口时仍需要可用的 Qt/VTK 图形环境。
MP4 使用随 `imageio[ffmpeg]` 安装的 FFmpeg，宽高须为偶数；更新环境运行 `python -m pip install -r requirements.txt`，Conda 环境也使用该依赖文件。
GIF 时间间隔以 10 ms 为单位，色彩量化为最多 256 色；MP4 采用有损压缩。科研数值分析应使用切片数据文件。

切片数据保持**原数组维度顺序和原始数值**，不执行显示用转置、色图映射或归一化。
NPZ 的 `data` 和 MAT 的 `data` 保留 dtype，`metadata`（NPZ 的 JSON 字符串）/`metadata_json`（MAT）记录原始形状、保留维度、额外索引、切片维度/索引及色图范围。
NPY/CSV 附带同名 `.npy.json` / `.csv.json` 元信息；CSV 为文本，不自带 dtype，读取时应依据元信息指定类型。
`data_dimensions` 按数据行、列对应原数组维度；第一维在查看器中沿水平方向显示。

## 边界与安全

- 全局统计遍历当前选中的完整二维/三维子数组，等值面默认每轴最多约 96 个采样点；细小结构可能被采样遗漏。
  调高 `max_render_size` 可以提高质量，但会增加计算量与内存。
- 常量场、极值或某些非有限值区域可能没有等值面，界面会明确提示；颜色栏仍存在。
- 读取和交互不会写回来源文件，导出仅写入用户指定的目标路径。NumPy 禁用 pickle；Torch 不回退到不受限的反序列化。
  这些措施不等于安全沙箱：仍只应打开可信文件，超大文件可能消耗大量资源。
- 展示标量采用 Python 双精度；极大整数（超出 `2**53`）或极端动态范围可能无法逐个位精确标注，原数据保持不变。
- 不自动转换整个数据集、不提供跨进程 Workspace、不支持真体渲染/时间轴语义推断。

模块关系见 [ARCHITECTURE.md](ARCHITECTURE.md)，迁移及验证记录见 [TESTING.md](TESTING.md)。
