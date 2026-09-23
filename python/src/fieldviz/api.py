"""Python entry points. Only source is positional; all choices are explicit keywords."""
import sys
from threading import current_thread, main_thread

from .core import Options, ViewState
from .sources import open_source

_application = None
_windows = set()


def visualize_field(source=None, *, field=None, namespace=None, mode=None, dimension=None,
                    index=None, color_limits=None, iso_values=None, num_isosurfaces=None,
                    iso_range=None, surface_alpha=None, max_render_size=None,
                    colormap="turbo", show=True):
    """Create a nonblocking viewer and return its window.

    ``source`` is a file path, ndarray, dense Tensor, nested dict or DataSource.
    ``namespace=globals()`` explicitly enables Python namespace browsing; local
    variables should instead be passed by value. No caller frame is inspected.
    Dimensions and slice indices are **1-based** to match the MATLAB viewer.
    Missing source/field opens a blank selector. Missing options enable the
    relevant UI controls. Use ``run()`` in a standalone script to run Qt.
    """
    global _application
    if current_thread() is not main_thread():
        raise RuntimeError("请在 Python 主线程创建查看器。")
    if field is not None and (not isinstance(field, str) or not field):
        raise ValueError("field 必须为非空变量路径字符串。")
    if field is not None and source is None and namespace is None:
        raise ValueError("显式 field 需要同时指定 source 或 namespace。")
    options = Options(mode=mode, dimension=dimension, index=index, color_limits=color_limits,
                      iso_values=iso_values, num_isosurfaces=num_isosurfaces, iso_range=iso_range,
                      surface_alpha=surface_alpha, max_render_size=max_render_size, colormap=colormap)
    from matplotlib import colormaps
    if colormap not in colormaps:
        raise ValueError(f"未知颜色映射：{colormap}")
    resolved = open_source(source, namespace=namespace) if source is not None or namespace is not None else None
    if resolved and not any(options.accepts(t) for t in resolved.list_targets()):
        # An empty namespace may be populated and refreshed after the viewer opens.
        if resolved.kind != "namespace":
            raise ValueError("来源中没有与当前参数兼容的实数二维/三维数组。")
    initial_state = None
    if resolved and (field is not None or resolved.automatic_target):
        key = field if field is not None else resolved.list_targets()[0].key
        initial_state = ViewState(resolved.open_target(key), options)
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import QApplication
    from .window import ViewerWindow
    _application = QApplication.instance() or QApplication(sys.argv[:1])
    window = ViewerWindow(options, source=resolved, field=field,
                          source_locked=source is not None or namespace is not None,
                          initial_state=initial_state)
    window.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
    _windows.add(window)
    window.destroyed.connect(lambda: _windows.discard(window))
    if show:
        window.show()
    return window


def run():
    """Start the Qt loop for standalone scripts; IPython users use ``%gui qt``."""
    if _application is None:
        raise RuntimeError("请先调用 visualize_field() 创建窗口。")
    return _application.exec()
