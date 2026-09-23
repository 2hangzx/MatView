"""Persistent render surfaces. Switching controls never recreates the window or camera."""
import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import QRectF
from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel


class SliceView(pg.PlotWidget):
    def __init__(self, colors):
        super().__init__(background="w")
        self.setMinimumSize(260, 220)
        self.image = pg.ImageItem(axisOrder="col-major")
        self.image.setLookupTable(np.asarray(colors, dtype=np.uint8))
        self.addItem(self.image)
        self.getViewBox().setAspectLocked(True)
        self.getPlotItem().setMenuEnabled(True)
        self.getPlotItem().showGrid(x=True, y=True, alpha=0.12)
        for name in ("left", "bottom"):
            self.getAxis(name).setTextPen("#313844")
            self.getAxis(name).setPen("#64748b")
        self._identity = None

    def display(self, frame, identity):
        self.image.setImage(frame.data, autoLevels=False, levels=frame.limits)
        self.image.setRect(QRectF(0.5, 0.5, *frame.data.shape))
        self.setLabel("bottom", f"Dim {frame.axes[0]} index")
        self.setLabel("left", f"Dim {frame.axes[1]} index")
        if identity != self._identity:
            self.getViewBox().autoRange()
            self._identity = identity

    def reset_view(self):
        self.getViewBox().autoRange()


class IsosurfaceView(QWidget):
    def __init__(self, colormap):
        super().__init__()
        from pyvistaqt import QtInteractor
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        self.plotter = QtInteractor(self, auto_update=False, multi_samples=0)
        self.plotter.setMinimumSize(0, 0)
        self.plotter.interactor.setMinimumSize(0, 0)
        self.plotter.set_background("white")
        self.plotter.enable_trackball_style()
        self.plotter.enable_parallel_projection()
        self.plotter.enable_depth_peeling(number_of_peels=8, occlusion_ratio=0.1)
        layout.addWidget(self.plotter.interactor)
        tools = QHBoxLayout()
        help_text = QLabel("左键旋转 · 中键或 Shift+左键平移 · 滚轮缩放")
        help_text.setWordWrap(True)
        tools.addWidget(help_text, 1)
        reset = QPushButton("复位视图")
        reset.clicked.connect(self.reset_view)
        tools.addWidget(reset)
        layout.addLayout(tools)
        self.setMinimumSize(260, 260)
        self.colormap = colormap
        self.actor = None
        self._identity = None
        self._bounds = None

    def display(self, mesh, shape, limits, alpha, identity):
        reset = self._identity != identity
        if reset:
            self.plotter.clear()
            self.actor = None
            self._identity = identity
            self._bounds = tuple(v for length in shape for v in (1, length))
        if self.actor is not None:
            self.plotter.remove_actor(self.actor, reset_camera=False, render=False)
            self.actor = None
        if mesh.n_points:
            self.actor = self.plotter.add_mesh(
                mesh, name="field", scalars="value", clim=limits, cmap=self.colormap,
                opacity=alpha, show_scalar_bar=False, reset_camera=False, render=False,
                smooth_shading=True)
        if reset:
            self.plotter.show_bounds(bounds=self._bounds, xtitle="Dim 1 index", ytitle="Dim 2 index",
                                     ztitle="Dim 3 index", color="#313844", font_size=13,
                                     bold=False, all_edges=True, location="outer", use_2d=False,
                                     use_3d_text=False,
                                     n_xlabels=3, n_ylabels=3, n_zlabels=3, render=False)
            self.reset_view()
        self.plotter.render()

    def set_alpha(self, value):
        if self.actor is not None:
            self.actor.prop.opacity = value
            self.plotter.render()

    def reset_view(self):
        self.plotter.view_isometric(render=False)
        if self._bounds:
            self.plotter.reset_camera(bounds=self._bounds, render=False)
            self.plotter.camera.zoom(0.75)
        self.plotter.render()

    def shutdown(self):
        self.plotter.close()
