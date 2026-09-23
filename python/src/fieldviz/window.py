"""Source -> target -> mode -> mode-specific controls, composed in three UI regions."""
from functools import partial
from pathlib import Path

import numpy as np
from matplotlib import colormaps
from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout, QFormLayout,
    QLabel, QLineEdit, QPushButton, QComboBox, QGroupBox, QScrollArea,
    QStackedWidget, QFileDialog, QSizePolicy,
)

from .core import ViewState, display_range
from .jobs import LatestJob
from .rendering import prepare_slice, prepare_mesh
from .sources import open_source
from .widgets import AdaptiveGrid, ColorBar, NumberControl
from .views import SliceView, IsosurfaceView


class ViewerWindow(QMainWindow):
    def __init__(self, options, *, source=None, field=None, source_locked=False, initial_state=None):
        super().__init__()
        self.options = options
        self.source = source
        self.state = None
        self.field_locked = field is not None
        self.source_locked = source_locked
        self._closed = False
        self._identity = 0
        self._syncing = False
        self._groups = {}
        self._volume_view = None
        colors = (colormaps[options.colormap](np.linspace(0, 1, 256)) * 255).astype(np.uint8)
        self.setWindowTitle("FieldViz · 二维/三维数组查看器")
        self.resize(1180, 900)
        self.setMinimumSize(680, 680)
        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(16, 12, 16, 16)
        layout.setSpacing(12)
        layout.addWidget(self._build_source_panel())
        self.title = QLabel("请选择数据来源和目标变量")
        self.title.setWordWrap(True)
        layout.addWidget(self.title)
        plot_row = QHBoxLayout()
        self.stack = QStackedWidget()
        self.empty = QLabel("图像区为空\n请先选择文件，再选择一个二维或三维数组。")
        self.empty.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.stack.addWidget(self.empty)
        self.slice_view = SliceView(colors)
        self.stack.addWidget(self.slice_view)
        plot_row.addWidget(self.stack, 1)
        self.colorbar = ColorBar(colors)
        self.colorbar.hide()
        plot_row.addWidget(self.colorbar)
        layout.addLayout(plot_row, 1)
        self.stats = QLabel("尚未选择目标变量")
        self.stats.setWordWrap(True)
        self.stats.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        layout.addWidget(self.stats)
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.controls = AdaptiveGrid()
        self.scroll.setWidget(self.controls)
        self.scroll.setMinimumHeight(170)
        self.scroll.setMaximumHeight(300)
        layout.addWidget(self.scroll)
        self._build_controls()
        self.statusBar().showMessage("就绪")
        self.load_job = LatestJob(self)
        self.load_job.result.connect(self._loaded)
        self.load_job.failed.connect(self._load_failed)
        self.render_job = LatestJob(self)
        self.render_job.result.connect(self._rendered)
        self.render_job.failed.connect(self._error)
        self.render_job.busy_changed.connect(self._render_busy)
        self.render_timer = QTimer(self)
        self.render_timer.setSingleShot(True)
        self.render_timer.setInterval(40)
        self.render_timer.timeout.connect(self._render)
        self.play_timer = QTimer(self)
        self.play_timer.setInterval(120)
        self.play_timer.timeout.connect(self._advance)
        self._populate_targets()
        if initial_state is not None:
            self._activate(initial_state)
        self._sync_controls()

    def _build_source_panel(self):
        panel = QGroupBox("数据来源与目标变量")
        grid = QGridLayout(panel)
        grid.setColumnStretch(1, 1)
        grid.setHorizontalSpacing(12)
        grid.addWidget(QLabel("文件路径"), 0, 0)
        self.path_edit = QLineEdit()
        self.path_edit.setMinimumWidth(0)
        self.path_edit.setPlaceholderText("绝对路径，或相对于当前 Python 工作目录的路径")
        self.path_edit.returnPressed.connect(self._path_entered)
        grid.addWidget(self.path_edit, 0, 1)
        self.browse_button = QPushButton("浏览…")
        self.browse_button.clicked.connect(self._browse)
        grid.addWidget(self.browse_button, 0, 2)
        grid.addWidget(QLabel("目标变量"), 1, 0)
        self.target_combo = QComboBox()
        self.target_combo.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
        self.target_combo.setMinimumWidth(0)
        self.target_combo.currentIndexChanged.connect(self._target_changed)
        grid.addWidget(self.target_combo, 1, 1)
        self.refresh_button = QPushButton("刷新来源")
        self.refresh_button.clicked.connect(self.refresh_source)
        self.refresh_button.setToolTip("重新扫描文件/命名空间，并重读当前目标；不会自动监视外部修改。")
        grid.addWidget(self.refresh_button, 1, 2)
        self.source_hint = QLabel("支持 MAT / NumPy / HDF5 / Torch；局部变量请通过函数参数直接传入。")
        self.source_hint.setWordWrap(True)
        grid.addWidget(self.source_hint, 2, 0, 1, 3)
        if self.source:
            self.path_edit.setText(self.source.name)
        editable = not self.source_locked and self.source is None
        self.path_edit.setReadOnly(not editable)
        self.browse_button.setEnabled(editable)
        return panel

    def _group(self, name, title):
        box = QGroupBox(title, self.controls)
        form = QFormLayout(box)
        form.setContentsMargins(10, 10, 10, 12)
        form.setSpacing(8)
        self._groups[name] = box
        self.controls.add_group(box)
        return form

    @staticmethod
    def _combo(items):
        combo = QComboBox()
        for text, value in items:
            combo.addItem(text, value)
        return combo

    def _build_controls(self):
        form = self._group("mode", "绘图模式")
        self.mode_combo = self._combo([("三维等值面 (Volume)", "isosurface"), ("二维切片 (Slice)", "slice")])
        form.addRow(self.mode_combo)
        self.mode_combo.currentIndexChanged.connect(self._mode_changed)
        form = self._group("dimension", "切片维度")
        self.dimension_combo = self._combo([(f"Dim {i}", i) for i in (1, 2, 3)])
        form.addRow(self.dimension_combo)
        self.dimension_combo.currentIndexChanged.connect(self._dimension_changed)
        form = self._group("index", "切片索引（从 1 开始）")
        self.index_control = NumberControl(1, 2, 1, integer=True)
        form.addRow(self.index_control)
        self.index_control.changed.connect(self._index_changed)
        form = self._group("color_mode", "颜色栏范围")
        self.color_combo = self._combo([("全局范围", "global"), ("当前切片", "slice"), ("自定义上下限", "custom")])
        form.addRow(self.color_combo)
        self.color_combo.currentIndexChanged.connect(self._color_mode_changed)
        form = self._group("color_bounds", "颜色栏上下限（输入或粗调）")
        self.color_low = NumberControl(0, 1, 0, allow_outside=True)
        self.color_high = NumberControl(0, 1, 1, allow_outside=True)
        form.addRow("下限", self.color_low)
        form.addRow("上限", self.color_high)
        self.color_low.changed.connect(partial(self._color_bound_changed, 0))
        self.color_high.changed.connect(partial(self._color_bound_changed, 1))
        form = self._group("iso_mode", "等值面方式")
        self.iso_combo = self._combo([("自动多层", "automatic"), ("指定单值", "single")])
        form.addRow(self.iso_combo)
        self.iso_combo.currentIndexChanged.connect(self._iso_mode_changed)
        form = self._group("count", "自动等值面数")
        self.count_control = NumberControl(1, 12, 5, integer=True)
        form.addRow(self.count_control)
        self.count_control.changed.connect(self._count_changed)
        form = self._group("range", "自动等值面范围（全局值域百分比）")
        self.range_low = NumberControl(0, 100, 15)
        self.range_high = NumberControl(0, 100, 85)
        form.addRow("下限 %", self.range_low)
        form.addRow("上限 %", self.range_high)
        self.range_low.changed.connect(partial(self._range_changed, 0))
        self.range_high.changed.connect(partial(self._range_changed, 1))
        form = self._group("exact", "单层等值面数值")
        self.exact_control = NumberControl(0, 1, 0.5)
        form.addRow(self.exact_control)
        self.exact_control.changed.connect(self._exact_changed)
        form = self._group("alpha", "等值面透明度")
        self.alpha_control = NumberControl(0.01, 1, 0.22)
        form.addRow(self.alpha_control)
        self.alpha_control.changed.connect(self._alpha_changed)
        form = self._group("play", "循环播放（从当前值继续）")
        self.play_button = QPushButton("播放")
        self.play_button.clicked.connect(self._toggle_play)
        self.interval_control = NumberControl(0.04, 60, 0.12, slider=False)
        self.interval_control.changed.connect(lambda v: self.play_timer.setInterval(round(v * 1000)))
        form.addRow(self.play_button)
        form.addRow("间隔 / s", self.interval_control)
        self.play_hint = QLabel("索引每次 +1；单值等值面每次增加全局值域的 1%。")
        self.play_hint.setWordWrap(True)
        form.addRow(self.play_hint)

    def _targets(self):
        return [t for t in self.source.list_targets() if self.options.accepts(t)] if self.source else []

    def _populate_targets(self, selected=None):
        self.target_combo.blockSignals(True)
        self.target_combo.clear()
        self.target_combo.addItem("请选择目标变量…", None)
        for target in self._targets():
            shape = " × ".join(map(str, target.shape))
            self.target_combo.addItem(f"{target.key}  [{shape}, {target.dtype}]", target.key)
        if selected is not None:
            self.target_combo.setCurrentIndex(max(0, self.target_combo.findData(selected)))
        self.target_combo.blockSignals(False)
        self.target_combo.setEnabled(self.source is not None and not self.field_locked
                                     and not self.source.automatic_target)
        self.refresh_button.setEnabled(self.source is not None)

    def _blank(self, message="请选择一个二维或三维数组。"):
        self.stop_playback()
        self.render_timer.stop()
        self.render_job.invalidate()
        self.state = None
        self.stack.setCurrentWidget(self.empty)
        self.empty.setText(message)
        self.colorbar.hide()
        self.title.setText("尚未绘图")
        self.stats.setText("尚未选择目标变量")
        self._sync_controls()

    def _path_entered(self):
        if not self.path_edit.isReadOnly():
            self.load_path(self.path_edit.text())

    def _browse(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择数据文件", str(Path.cwd()),
                    "数组文件 (*.mat *.npy *.npz *.h5 *.hdf5 *.pt *.pth *.safetensors);;所有文件 (*)")
        if path:
            self.path_edit.setText(path)
            self.load_path(path)

    def load_path(self, path):
        """Public UI action; relative paths resolve exactly as the function's source argument."""
        self._blank("正在读取来源…")
        self.target_combo.setEnabled(False)
        self.refresh_button.setEnabled(False)
        self.statusBar().showMessage("正在扫描合法二维/三维数组…")
        self.load_job.submit(lambda: ("source", open_source(path), None))

    def refresh_source(self):
        if not self.source:
            return
        key = self.state.handle.target.key if self.state else None
        source = self.source
        self._blank("正在刷新数据快照…")
        self.target_combo.setEnabled(False)
        self.refresh_button.setEnabled(False)
        def refresh():
            current = source.refresh()
            state = ViewState(current.open_target(key), self.options) if key else None
            return "source", current, state
        self.load_job.submit(refresh)

    def _target_changed(self, _):
        if self._syncing or self.source is None:
            return
        key = self.target_combo.currentData()
        self._blank("正在读取数组与统计范围…" if key else "请选择目标变量。")
        if not key:
            self.load_job.invalidate()
            return
        source = self.source
        self.load_job.submit(lambda: ("target", source, ViewState(source.open_target(key), self.options)))

    def _loaded(self, result):
        kind, source, state = result
        if kind == "source":
            previous = self.source
            self.source = source
            if previous is not None and previous is not source:
                previous.close()
            self.path_edit.setText(source.name)
            self.path_edit.setToolTip(source.name)
            self._populate_targets()
            if not self._targets():
                self._blank("来源中没有与当前参数兼容的实数二维/三维数组。")
                self.statusBar().showMessage("未找到可绘制变量")
                return
            if state is None and source.automatic_target:
                # Queue target I/O and statistics off the GUI thread as well.
                self.target_combo.setCurrentIndex(1)
                return
        if state is not None:
            self._activate(state)
        else:
            self._blank()
            self.statusBar().showMessage("请选择目标变量")

    def _activate(self, state):
        self.state = state
        self._identity += 1
        self._populate_targets(state.handle.target.key)
        self.setWindowTitle(f"{state.handle.target.key} · FieldViz")
        self._sync_controls()
        self._schedule_render()

    def _load_failed(self, message):
        self._blank("读取失败；请检查路径、变量或参数后重试。")
        if self.source is not None:
            self.path_edit.setText(self.source.name)
        self._populate_targets()
        self._error(message)

    def _sync_controls(self):
        self._syncing = True
        s, o = self.state, self.options
        self.controls.setEnabled(s is not None)
        is_slice = s is not None and s.mode == "slice"
        is_3d = s is None or s.handle.target.ndim == 3
        is_volume = s is not None and s.mode == "isosurface"
        automatic = s is not None and s.iso_mode == "automatic"
        single = s is not None and s.iso_mode == "single"
        visibility = {
            "mode": o.mode is None and is_3d,
            "dimension": is_slice and is_3d and o.dimension is None,
            "index": is_slice and is_3d and o.index is None,
            "color_mode": is_slice and o.color_limits is None,
            "color_bounds": is_slice and o.color_limits is None,
            "iso_mode": is_volume and o.iso_values is None and o.num_isosurfaces is None and o.iso_range is None,
            "count": is_volume and automatic and o.num_isosurfaces is None,
            "range": is_volume and automatic and o.iso_range is None,
            "exact": is_volume and single,
            "alpha": is_volume and o.surface_alpha is None,
            "play": (is_slice and is_3d and o.index is None) or (is_volume and single),
        }
        for key, group in self._groups.items():
            group.setVisible(visibility[key] if s else key in ("mode", "iso_mode", "count", "alpha"))
        if s:
            for combo, value in ((self.mode_combo, s.mode), (self.dimension_combo, s.dimension),
                                 (self.color_combo, s.color_mode), (self.iso_combo, s.iso_mode)):
                combo.blockSignals(True)
                combo.setCurrentIndex(combo.findData(value))
                combo.blockSignals(False)
            if is_3d:
                self.index_control.set_bounds(1, s.handle.target.shape[s.dimension - 1])
                self.index_control.set_value(s.index)
            bounds = display_range(s.bounds)
            for control, value in zip((self.color_low, self.color_high), s.color_bounds):
                control.set_bounds(*bounds)
                control.set_value(value)
            self.exact_control.set_bounds(*s.bounds)
            self.exact_control.set_value(s.exact)
            self.count_control.set_value(s.count)
            self.range_low.set_value(s.fractions[0] * 100)
            self.range_high.set_value(s.fractions[1] * 100)
            self.alpha_control.set_value(s.alpha)
            self.play_button.setEnabled(is_slice or s.bounds[0] < s.bounds[1])
        self.controls.reflow()
        self._syncing = False

    def _mode_changed(self, _):
        if self._syncing or self.state is None:
            return
        self.stop_playback()
        self.state.mode = self.mode_combo.currentData()
        self.render_job.invalidate()
        self.stack.setCurrentWidget(self.empty)
        self.empty.setText("正在准备图像…")
        self._sync_controls()
        self._schedule_render()

    def _dimension_changed(self, _):
        if self._syncing or self.state is None:
            return
        self.stop_playback()
        s = self.state
        s.dimension = self.dimension_combo.currentData()
        s.index = min(s.index, s.handle.target.shape[s.dimension - 1])
        self._sync_controls()
        self._schedule_render()

    def _index_changed(self, value):
        if self.state:
            self.state.index = int(value)
            self._schedule_render()

    def _color_mode_changed(self, _):
        if self._syncing or self.state is None:
            return
        self.state.color_mode = self.color_combo.currentData()
        if self.state.color_mode == "global":
            self.state.color_bounds = display_range(self.state.bounds)
        self._sync_controls()
        self._schedule_render()

    def _color_bound_changed(self, side, value):
        if self.state is None:
            return
        pair = list(self.state.color_bounds)
        pair[side] = value
        if pair[0] >= pair[1]:
            self._sync_controls()
            return
        self.state.color_bounds = tuple(pair)
        self.state.color_mode = "custom"
        self._sync_controls()
        self._schedule_render()

    def _iso_mode_changed(self, _):
        if self._syncing or self.state is None:
            return
        self.stop_playback()
        self.state.iso_mode = self.iso_combo.currentData()
        self._sync_controls()
        self._schedule_render()

    def _count_changed(self, value):
        if self.state:
            self.state.count = int(value)
            self._schedule_render()

    def _range_changed(self, side, value):
        if self.state is None:
            return
        pair = list(self.state.fractions)
        pair[side] = value / 100
        if pair[0] >= pair[1]:
            self._sync_controls()
            return
        self.state.fractions = tuple(pair)
        self._schedule_render()

    def _exact_changed(self, value):
        if self.state:
            self.state.exact = value
            self._schedule_render()

    def _alpha_changed(self, value):
        if self.state:
            self.state.alpha = value
            if self._volume_view:
                self._volume_view.set_alpha(value)

    def _schedule_render(self):
        self.render_job.invalidate()
        # Throttle, not debounce: continuous dragging still gets periodic latest updates.
        if not self.render_timer.isActive():
            self.render_timer.start()

    def _render(self):
        s = self.state
        if s is None:
            return
        if s.mode == "slice":
            function = partial(prepare_slice, s.handle, s.dimension, s.index, s.color_mode, s.color_bounds)
            mode = "slice"
        else:
            function = partial(prepare_mesh, s.handle, s.levels(), self.options.max_render_size or 96)
            mode = "isosurface"
        self.render_job.submit(lambda: (mode, function()))

    def _rendered(self, result):
        if self.state is None:
            return
        mode, frame = result
        s = self.state
        low, high = s.bounds
        stats = f"全局 [min, max]：{low:.10g} / {high:.10g}    原始类型：{s.handle.target.dtype}"
        if mode == "slice":
            self.slice_view.display(frame, (self._identity, s.dimension))
            self.stack.setCurrentWidget(self.slice_view)
            self.colorbar.set_limits(frame.limits)
            if frame.bounds:
                stats += f"    切片 [min, max]：{frame.bounds[0]:.10g} / {frame.bounds[1]:.10g}"
            else:
                stats += "    当前切片无有限数值"
            suffix = f"Dim {s.dimension} · 索引 {s.index}" if s.handle.target.ndim == 3 else "二维数组"
            self.title.setText(f"{s.handle.target.key} | {suffix}")
            if s.color_mode == "slice":
                s.color_bounds = frame.limits
                self._sync_controls()
        else:
            mesh, sampled_shape = frame
            if self._volume_view is None:
                self._volume_view = IsosurfaceView(self.options.colormap)
                self.stack.addWidget(self._volume_view)
            self._volume_view.display(mesh, s.handle.target.shape, display_range(s.bounds), s.alpha, self._identity)
            self.stack.setCurrentWidget(self._volume_view)
            self.colorbar.set_limits(display_range(s.bounds))
            levels = ", ".join(f"{x:.8g}" for x in s.levels())
            self.title.setText(f"{s.handle.target.key} | 等值面：{levels}")
            stats += f"    绘制采样：{sampled_shape}（统计使用完整数据）"
            if not mesh.n_points:
                stats += "    当前数值未生成表面（常量、极值或采样可能导致）"
        self.stats.setText(stats)
        self.colorbar.show()
        self.statusBar().showMessage("就绪")

    def _render_busy(self, busy):
        if busy:
            self.statusBar().showMessage("正在计算最新画面…")

    def _error(self, message):
        self.stop_playback()
        self.statusBar().showMessage(f"错误：{message}")
        self.statusBar().setToolTip(str(message))

    def _toggle_play(self):
        if self.play_timer.isActive():
            self.stop_playback()
        elif self.state is not None:
            self.play_timer.start()
            self.play_button.setText("暂停")

    def stop_playback(self):
        self.play_timer.stop()
        self.play_button.setText("播放")

    def _advance(self):
        if self.state is None or self.render_job.busy or self.render_timer.isActive():
            return
        self.state.advance()
        self._sync_controls()
        self._schedule_render()

    def closeEvent(self, event):
        self._closed = True
        self.stop_playback()
        self.render_timer.stop()
        self.load_job.close()
        self.render_job.close()
        if self._volume_view is not None:
            self._volume_view.shutdown()
        if self.source:
            self.source.close()
        super().closeEvent(event)
