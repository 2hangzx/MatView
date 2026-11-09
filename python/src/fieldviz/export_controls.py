"""Unified menu/right-click actions; dialogs never become part of exported plots."""
from PySide6.QtCore import Qt
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QDialog, QDialogButtonBox, QFormLayout, QSpinBox, QDoubleSpinBox, QGroupBox, QGridLayout, QCheckBox,
    QFileDialog, QProgressDialog, QApplication, QMessageBox, QMenu,
)

from . import exporting


class ExportControls:
    def __init__(self, window):
        self.window = window
        menu = window.menuBar().addMenu("导出")
        self.image = QAction("导出图片…", window)
        self.animation = QAction("导出播放动画（GIF / MP4）…", window)
        self.data = QAction("导出当前切片数据…", window)
        self.actions = (self.image, self.animation, self.data)
        for action, kind in zip(self.actions, ("image", "animation", "data")):
            action.triggered.connect(lambda checked=False, kind=kind: self.dialog(kind))
            menu.addAction(action)
        # Replace only the library's slice-only Export action. Keep View All,
        # axis options and the rest of pyqtgraph's navigation context menu.
        window.slice_view.scene().contextMenu = list(self.actions)

    def attach_context_menu(self, widget):
        widget.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        widget.customContextMenuRequested.connect(lambda position: self.context_menu(widget, position))

    def context_menu(self, widget, position):
        menu = QMenu(widget)
        menu.addActions(self.actions)
        menu.exec(widget.mapToGlobal(position))

    def update(self):
        window = self.window
        ready = (window.state is not None and not window._subspace_busy and not window._closed
                 and not window.load_job.busy and not window.render_job.busy
                 and not window.render_timer.isActive() and not getattr(window, "_exporting", False))
        self.image.setEnabled(ready)
        self.data.setEnabled(ready and window.state.mode == "slice")
        self.animation.setEnabled(ready and exporting.can_animate(window.state))

    def dialog(self, kind):
        window = self.window
        was_playing = window.play_timer.isActive()
        window.stop_playback()
        try:
            self._dialog(kind)
        finally:
            if was_playing and not window._closed:
                window._toggle_play()

    def _dialog(self, kind):
        window = self.window
        settings = {}
        if kind != "data":
            dialog = QDialog(window)
            dialog.setWindowTitle("导出图片" if kind == "image" else "导出循环播放序列")
            form = QFormLayout(dialog)
            for key, label, value, low, high in (("width", "宽度 / px", 1600, 320, 8192),
                                                ("height", "高度 / px", 1200, 240, 8192)):
                box = QSpinBox()
                box.setRange(low, high)
                box.setValue(value)
                settings[key] = box
                form.addRow(label, box)
            if kind == "animation":
                count, rate = exporting.animation_defaults(window.state, window.interval_control.value)
                box = QSpinBox()
                box.setRange(1, 10000)
                box.setValue(count)
                settings["frames"] = box
                form.addRow("帧数（从当前值开始，末尾循环）", box)
                box = QDoubleSpinBox()
                box.setRange(.1, 60)
                box.setDecimals(2)
                box.setValue(rate)
                settings["fps"] = box
                form.addRow("帧率 / fps", box)
            group = QGroupBox("导出部件")
            layout = QGridLayout(group)
            layout.setColumnMinimumWidth(0, 20)
            body = QCheckBox("图像主体（必选）")
            body.setChecked(True)
            body.setEnabled(False)
            layout.addWidget(body, 0, 0, 1, 2)
            checks = {}
            for row, (name, label, parent) in enumerate(exporting.COMPONENT_CHOICES, start=1):
                check = QCheckBox(label)
                check.setChecked(True)
                layout.addWidget(check, row, 1 if parent else 0, 1, 1 if parent else 2)
                checks[name] = check
                if parent:
                    checks[parent].toggled.connect(check.setEnabled)
            form.addRow(group)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
            buttons.accepted.connect(dialog.accept)
            buttons.rejected.connect(dialog.reject)
            form.addRow(buttons)
            if dialog.exec() != QDialog.DialogCode.Accepted:
                return
            settings = {key: box.value() for key, box in settings.items()}
            settings["components"] = [name for name, check in checks.items() if check.isChecked()]
        filters = {"image": "PNG (*.png);;JPEG (*.jpg);;TIFF (*.tif)",
                   "animation": "GIF 动画 (*.gif);;MP4 视频 (*.mp4)",
                   "data": "NumPy 数据与元信息 (*.npz);;NumPy 数组 (*.npy);;MAT 文件 (*.mat);;CSV (*.csv)"}
        path, chosen = QFileDialog.getSaveFileName(window, "选择导出文件", "", filters[kind])
        if not path:
            return
        from pathlib import Path
        if not Path(path).suffix:
            path += chosen[chosen.index("*.") + 1:chosen.index(")")]
        progress = QProgressDialog("正在导出…", "取消", 0, int(settings.get("frames", 0)), window)
        progress.setWindowModality(Qt.WindowModality.WindowModal)
        progress.setMinimumDuration(0)
        progress.setAutoClose(False)
        if kind != "animation":
            progress.setCancelButton(None)
        def advance(done, total):
            progress.setMaximum(total)
            progress.setValue(done)
            QApplication.processEvents()
            return not progress.wasCanceled()
        try:
            if kind == "animation":
                window.export_animation(path, **settings, progress=advance)
            elif kind == "image":
                QApplication.processEvents()
                window.export_image(path, **settings)
            else:
                window.export_slice_data(path)
            window.statusBar().showMessage(f"已导出：{path}")
        except exporting.ExportCancelled:
            window.statusBar().showMessage("导出已取消，目标文件未改动。")
        except Exception as exc:
            QMessageBox.warning(window, "无法导出", str(exc))
        finally:
            progress.close()
