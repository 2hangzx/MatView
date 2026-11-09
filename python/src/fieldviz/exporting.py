"""Deterministic, plot-only exports from an immutable viewer snapshot.

The original array, UI state and camera are never advanced by an export. Frames
are generated one at a time and atomically replace the destination on success.
"""
from contextlib import contextmanager
from copy import copy
import json
import math
import numbers
from pathlib import Path
import tempfile
import textwrap

import numpy as np
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.colors import Normalize
from matplotlib.figure import Figure
from matplotlib.font_manager import FontProperties, fontManager
from matplotlib.cm import ScalarMappable

from .core import display_range
from .rendering import prepare_mesh, prepare_slice


COMPONENT_CHOICES = (
    ("axes", "坐标轴 / 坐标框", None),
    ("axis_labels", "坐标轴标签", "axes"),
    ("axis_ticks", "坐标轴刻度与数字", "axes"),
    ("title", "标题", None),
    ("colorbar", "颜色栏", None),
    ("colorbar_label", "颜色栏标签", "colorbar"),
    ("colorbar_ticks", "颜色栏刻度与数字", "colorbar"),
)


def resolve_components(components):
    available = {name for name, _, _ in COMPONENT_CHOICES}
    if components is None:
        return frozenset(available)
    selected = {components} if isinstance(components, str) else set(components)
    if selected - available:
        raise ValueError(f"未知导出部件：{selected - available}")
    return frozenset(name for name, _, parent in COMPONENT_CHOICES
                     if name in selected and (parent is None or parent in selected))


class ExportCancelled(Exception):
    """An export was cancelled; the destination has not been replaced."""


def validate_size(width, height):
    for name, value, minimum in (("width", width, 320), ("height", height, 240)):
        if isinstance(value, bool) or not isinstance(value, numbers.Integral) or not minimum <= value <= 8192:
            raise ValueError(f"{name} 必须是 [{minimum}, 8192] 内的整数像素。")
    if width * height > 32_000_000:
        raise ValueError("导出图片不能超过 3200 万像素。")


def can_animate(state):
    return state is not None and state.handle.target.ndim == 3 and (
        state.mode == "slice" or state.iso_mode == "single"
        or state.iso_mode == "explicit" and len(state.iso_values) == 1)


def animation_defaults(state, interval):
    count = state.handle.target.shape[state.dimension - 1] if state.mode == "slice" else 101
    return count, min(60.0, max(0.1, 1 / interval))


@contextmanager
def destination(path, extensions):
    path = Path(path).expanduser().absolute()
    if path.suffix.lower() not in extensions:
        raise ValueError("支持的文件类型：" + ", ".join(extensions))
    if not path.parent.is_dir():
        raise FileNotFoundError(f"输出目录不存在：{path.parent}")
    with tempfile.TemporaryDirectory(prefix=".fieldviz-export-", dir=path.parent) as directory:
        temporary = Path(directory) / path.name
        yield temporary
        if not temporary.is_file() or not temporary.stat().st_size:
            raise OSError("导出未生成有效文件。")
        temporary.replace(path)


def slice_payload(state, colormap):
    if state.mode != "slice":
        raise ValueError("只有 Slice 模式可以导出当前切片数据。")
    frame = prepare_slice(state.handle, state.dimension, state.index, state.color_mode, state.color_bounds)
    metadata = {
        "variable": state.source_handle.target.key,
        "source_type": state.source_handle.target.source_type,
        "original_shape": list(state.source_handle.target.shape),
        "dtype": str(frame.data.dtype), "index_base": 1,
        "retained_dimensions": list(state.retained_dimensions),
        "extra_indices": {str(k): int(v) for k, v in state.extra_indices.items()},
        "slice_dimension": state.handle.target.axes[state.dimension - 1] if state.handle.target.ndim == 3 else None,
        "slice_index": state.index if state.handle.target.ndim == 3 else None,
        "data_dimensions": list(frame.axes),
        "data_order": "source array order; first dimension is horizontal in the viewer",
        "color_limits": list(frame.limits), "colormap": colormap,
    }
    return frame.data, metadata


def export_slice_data(state, colormap, path):
    data, metadata = slice_payload(state, colormap)
    encoded = json.dumps(metadata, ensure_ascii=False, indent=2)
    extension = Path(path).suffix.lower()
    with destination(path, (".npz", ".npy", ".mat", ".csv")) as temporary:
        if extension == ".npz":
            with temporary.open("wb") as stream:
                np.savez_compressed(stream, data=data, metadata=np.array(encoded))
        elif extension == ".mat":
            from scipy.io import savemat
            savemat(str(temporary), {"data": data, "metadata_json": encoded}, do_compression=True, appendmat=False)
        elif extension == ".npy":
            with temporary.open("wb") as stream:
                np.save(stream, data, allow_pickle=False)
        else:
            # 17 significant digits round-trip float64; integer fields remain exact.
            np.savetxt(temporary, data, delimiter=",", fmt="%d" if data.dtype.kind in "iu" else "%.17g")
        if extension in (".npy", ".csv"):
            sidecar = Path(str(Path(path).expanduser().absolute()) + ".json")
            # Finish all I/O before publishing the main data file.
            temporary.with_suffix(".json").write_text(encoded, encoding="utf-8")
            temporary.with_suffix(".json").replace(sidecar)
    return Path(path)


class PlotRenderer:
    """Offscreen renderers reuse the viewer's slice/contour algorithms."""
    def __init__(self, window, width, height, *, components=None):
        validate_size(width, height)
        self.components = resolve_components(components)
        self.state = copy(window.state)
        self.colormap = window.colormap
        self.max_size = window.options.max_render_size or 96
        self.width, self.height = width, height
        viewbox = window.slice_view.getViewBox()
        self.slice_range = (viewbox.viewRange() if self.state.mode == "slice"
                            and window.slice_view.user_navigated else None)
        self.camera = None
        if self.state.mode != "slice" and window._volume_view is not None:
            self.camera = window._volume_view.plotter.camera.copy()
        names = {f.name for f in fontManager.ttflist}
        family = next((name for name in ("Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "DejaVu Sans")
                       if name in names), "DejaVu Sans")
        self.font = FontProperties(family=family, size=11)
        self.figure = Figure(figsize=(width / 120, height / 120), dpi=120, layout="constrained", facecolor="white")
        self.canvas = FigureCanvasAgg(self.figure)
        self.plotter = None
        self.actor = None
        self._started = False

    def frame(self):
        state = self.state
        parts = self.components
        self.figure.clear()
        ax = self.figure.add_subplot()
        if state.mode == "slice":
            frame = prepare_slice(state.handle, state.dimension, state.index, state.color_mode, state.color_bounds)
            limits = frame.limits
            image = ax.imshow(frame.data.T, origin="lower", interpolation="nearest", cmap=self.colormap,
                              vmin=limits[0], vmax=limits[1],
                              extent=(0.5, frame.data.shape[0] + .5, .5, frame.data.shape[1] + .5))
            if "axes" not in parts:
                ax.set_axis_off()
            else:
                if "axis_labels" in parts:
                    ax.set_xlabel(f"Dim {frame.axes[0]} index")
                    ax.set_ylabel(f"Dim {frame.axes[1]} index")
                if "axis_ticks" not in parts:
                    ax.set_xticks([])
                    ax.set_yticks([])
            if self.slice_range is not None:
                ax.set_xlim(*self.slice_range[0])
                ax.set_ylim(*self.slice_range[1])
            suffix = (f"Dim {state.handle.target.axes[state.dimension - 1]} = {state.index}"
                      if state.handle.target.ndim == 3 else "2-D array")
        else:
            limits = display_range(state.bounds)
            mesh, _ = prepare_mesh(state.handle, state.levels(), self.max_size)
            screenshot = self._volume_frame(mesh, limits)
            ax.imshow(screenshot, aspect="equal")
            ax.set_axis_off()
            image = ScalarMappable(norm=Normalize(*limits), cmap=self.colormap)
            suffix = "isosurfaces: " + ", ".join(f"{v:.9g}" for v in state.levels())
        if "title" in parts:
            title = f"{state.handle.target.key} | {suffix}"
            if state.extra_indices:
                title += " | " + ", ".join(f"Dim {d}={i}" for d, i in state.extra_indices.items())
            self.figure.suptitle("\n".join(textwrap.wrap(title, max(35, self.width // 10))),
                                 fontproperties=self.font)
        if "colorbar" in parts:
            bar = self.figure.colorbar(image, ax=ax, fraction=.045, pad=.035)
            if "colorbar_label" in parts:
                bar.set_label("Value")
            if "colorbar_ticks" in parts:
                ticks = np.linspace(*limits, 6)
                for precision in range(8, 18):
                    labels = [format(value, f".{precision}g") for value in ticks]
                    if len(set(labels)) == len(set(ticks)):
                        break
                bar.set_ticks(ticks, labels=labels)
            else:
                bar.set_ticks([])
        self.canvas.draw()
        return np.asarray(self.canvas.buffer_rgba())[:, :, :3].copy()

    def _volume_frame(self, mesh, limits):
        if self.plotter is None:
            import pyvista as pv
            from .views import show_volume_bounds
            self.plotter = pv.Plotter(off_screen=True, window_size=(max(260, int(self.width * .82)),
                                                                   max(220, self.height - 100)))
            self.plotter.set_background("white")
            self.plotter.enable_depth_peeling(number_of_peels=8, occlusion_ratio=.1)
            if self.camera is not None:
                self.plotter.camera = self.camera.copy()
            else:
                self.plotter.view_isometric(render=False)
                self.plotter.enable_parallel_projection()
            # CubeAxesActor retains a camera reference. Create it only after the
            # snapshot camera is installed, or its labels use the wrong camera.
            target = self.state.handle.target
            bounds = tuple(v for length in target.shape for v in (1, length))
            if "axes" in self.components:
                show_volume_bounds(self.plotter, bounds, target.axes, labels="axis_labels" in self.components,
                                   ticks="axis_ticks" in self.components)
            camera = self.plotter.camera
            requested_scale = camera.parallel_scale if self.camera is not None else 0
            # Center on the full field once, so pan and changing isosurfaces do
            # not shift the coordinate box within the export canvas.
            camera.SetWindowCenter(0, 0)
            self.plotter.reset_camera(bounds=bounds, render=False)
            self.plotter.renderer.ResetCameraClippingRange(*bounds)
            if camera.parallel_projection:
                direction = np.asarray(camera.direction)
                right = np.cross(direction, camera.up)
                right /= np.linalg.norm(right)
                up = np.cross(right, direction)
                half_lengths = (np.asarray(target.shape) - 1) / 2
                width, height = self.plotter.window_size
                # Parallel scale is half the visible height in data units.
                # Leave space around the projected box for the axis labels.
                fit_scale = max(np.abs(up) @ half_lengths, np.abs(right) @ half_lengths * height / width) / .78
                camera.parallel_scale = max(requested_scale, fit_scale)
            else:
                camera.zoom(.78)
        if self.actor is not None:
            self.plotter.remove_actor(self.actor, reset_camera=False, render=False)
            self.actor = None
        if mesh.n_points:
            self.actor = self.plotter.add_mesh(mesh, scalars="value", clim=limits, cmap=self.colormap,
                                             opacity=self.state.alpha, smooth_shading=True,
                                             show_scalar_bar=False, reset_camera=False, render=False)
        if not self._started:
            # show() initializes VTK's text actors even for an offscreen window.
            # screenshot() alone can omit the cube-axis labels on its first frame.
            self.plotter.show(auto_close=False, interactive=False)
            self._started = True
        self.plotter.render()
        return self.plotter.screenshot(return_img=True)

    def close(self):
        self.figure.clear()
        if self.plotter is not None:
            self.plotter.close()


def export_image(window, path, *, width=1600, height=1200, components=None):
    from PIL import Image
    with destination(path, (".png", ".jpg", ".jpeg", ".tif", ".tiff")) as temporary:
        renderer = PlotRenderer(window, width, height, components=components)
        try:
            Image.fromarray(renderer.frame()).save(temporary, dpi=(120, 120))
        finally:
            renderer.close()
    return Path(path)


def export_animation(window, path, *, width=1280, height=960, frames=None, fps=None, progress=None,
                     components=None):
    if not can_animate(window.state):
        raise ValueError("动画导出需要三维数组的 Slice 模式，或指定单层等值面模式。")
    defaults = animation_defaults(window.state, window.interval_control.value)
    frames = defaults[0] if frames is None else frames
    fps = defaults[1] if fps is None else fps
    if isinstance(frames, bool) or not isinstance(frames, numbers.Integral) or not 1 <= frames <= 10000:
        raise ValueError("frames 必须为 [1, 10000] 内的整数。")
    if isinstance(fps, bool) or not isinstance(fps, numbers.Real) or not math.isfinite(fps) or not .1 <= fps <= 60:
        raise ValueError("fps 必须在 [0.1, 60]。")
    validate_size(width, height)
    if Path(path).suffix.lower() == ".mp4" and (width % 2 or height % 2):
        raise ValueError("MP4 的宽和高必须为偶数像素。")
    import imageio.v2 as imageio
    with destination(path, (".gif", ".mp4")) as temporary:
        renderer = PlotRenderer(window, width, height, components=components)
        if renderer.state.mode != "slice":
            renderer.state.exact = float(renderer.state.levels()[0])
            renderer.state.iso_mode = "single"
        writer = None
        try:
            if temporary.suffix.lower() == ".gif":
                writer = imageio.get_writer(str(temporary), format="GIF-PIL", mode="I", duration=1 / fps, loop=0)
            else:
                writer = imageio.get_writer(str(temporary), format="FFMPEG", fps=fps, codec="libx264",
                                            macro_block_size=1, ffmpeg_log_level="error")
            for i in range(frames):
                if progress is not None and progress(i, frames) is False:
                    raise ExportCancelled()
                writer.append_data(renderer.frame())
                renderer.state.advance()
            if progress is not None and progress(frames, frames) is False:
                raise ExportCancelled()
        finally:
            try:
                if writer is not None:
                    writer.close()
            finally:
                renderer.close()
        if temporary.suffix.lower() == ".gif":
            # GIF-PIL streams frames with bounded memory, but writes 65535 for
            # loop=0. The Netscape extension's standard infinite value is 0.
            with temporary.open("r+b") as stream:
                header = stream.read(2048)
                marker = b"NETSCAPE2.0\x03\x01"
                position = header.find(marker)
                if position < 0:
                    raise OSError("GIF 缺少循环播放信息。")
                stream.seek(position + len(marker))
                stream.write(b"\x00\x00")
    return Path(path)
