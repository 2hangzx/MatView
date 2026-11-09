"""Read exported files back: pixels, raw numbers, metadata, frames and cancellation."""
import json
from itertools import product

import imageio.v2 as imageio
import numpy as np
from PIL import Image
import pytest
from PySide6.QtWidgets import QCheckBox, QDialog
from scipy.io import loadmat

from fieldviz import visualize_field
from fieldviz.cli import main
from fieldviz.exporting import ExportCancelled, PlotRenderer


def viewer(qtbot, array, **kwargs):
    window = visualize_field(array, **kwargs)
    qtbot.addWidget(window)
    window.wait_until_ready()
    return window


@pytest.mark.parametrize("extension", ["npz", "npy", "mat", "csv"])
def test_raw_slice_preserves_source_order_dtype_and_selection(qtbot, tmp_path, extension):
    array = np.arange(5 * 6 * 7 * 2, dtype=np.float32).reshape(5, 6, 7, 2)
    array[0, 2, 0, 1] = np.nan
    window = viewer(qtbot, array, mode="slice", retained_dimensions=(1, 2, 3), extra_indices={4: 2},
                    dimension=2, index=3, colormap="hot")
    output = tmp_path / ("切片." + extension)
    window.export_slice_data(output)
    if extension == "npz":
        with np.load(output, allow_pickle=False) as saved:
            data, metadata = saved["data"], json.loads(str(saved["metadata"]))
    elif extension == "mat":
        saved = loadmat(output)
        data, metadata = saved["data"], json.loads(str(saved["metadata_json"][0]))
    else:
        data = np.load(output) if extension == "npy" else np.loadtxt(output, delimiter=",")
        metadata = json.loads(output.with_name(output.name + ".json").read_text(encoding="utf-8"))
    np.testing.assert_array_equal(data, array[:, 2, :, 1])
    if extension != "csv":
        assert data.dtype == array.dtype
    assert metadata["data_dimensions"] == [1, 3]
    assert metadata["slice_dimension"] == 2 and metadata["slice_index"] == 3
    assert metadata["extra_indices"] == {"4": 2}
    assert metadata["colormap"] == "hot"


def test_plot_image_has_exact_size_and_independent_colorbar(qtbot, tmp_path):
    window = viewer(qtbot, np.linspace(1.00003, 1.0002, 30 * 40).reshape(30, 40), colormap="jet")
    before = window.slice_view.getViewBox().viewRange()
    path = tmp_path / "image.png"
    window.export_image(path, width=800, height=600)
    pixels = np.asarray(Image.open(path))
    assert pixels.shape == (600, 800, 3)
    # Find the vertically extended color gradient near the right edge.
    strip = pixels[120:450, 650:790]
    assert np.any(np.ptp(strip.astype(float), axis=2) > 100)
    assert before == window.slice_view.getViewBox().viewRange()
    assert window.export_controls.data.isEnabled()


def test_slice_export_parts_are_independent_and_require_their_parent(qtbot):
    window = viewer(qtbot, np.arange(30).reshape(5, 6))
    renderer = PlotRenderer(window, 480, 360, components=["axes", "axis_labels", "colorbar", "colorbar_ticks"])
    try:
        renderer.frame()
        ax, bar = renderer.figure.axes
        assert ax.axison and ax.get_xlabel() == "Dim 1 index"
        assert not len(ax.get_xticks())
        assert len(bar.get_yticks()) == 6 and not bar.get_ylabel()
        assert not renderer.figure.texts
    finally:
        renderer.close()
    renderer = PlotRenderer(window, 480, 360, components=["axis_labels", "axis_ticks", "colorbar_label",
                                                          "colorbar_ticks", "title"])
    try:
        renderer.frame()
        ax, = renderer.figure.axes
        assert not ax.axison and len(ax.images) == 1
        assert renderer.figure.texts[0].get_text()
    finally:
        renderer.close()


def test_export_settings_preserve_child_choices_when_parent_toggles(qtbot, monkeypatch):
    window = viewer(qtbot, np.arange(30).reshape(5, 6))

    def inspect(dialog):
        checks = {check.text(): check for check in dialog.findChildren(QCheckBox)}
        body = checks["图像主体（必选）"]
        assert body.isChecked() and not body.isEnabled()
        axes = checks["坐标轴 / 坐标框"]
        labels = checks["坐标轴标签"]
        ticks = checks["坐标轴刻度与数字"]
        ticks.setChecked(False)
        axes.setChecked(False)
        assert not labels.isEnabled() and not ticks.isEnabled()
        axes.setChecked(True)
        assert labels.isEnabled() and labels.isChecked()
        assert ticks.isEnabled() and not ticks.isChecked()
        return QDialog.DialogCode.Rejected

    monkeypatch.setattr(QDialog, "exec", inspect)
    window.export_controls.dialog("image")


@pytest.mark.parametrize("extension", ["gif", "mp4"])
def test_animation_frame_count_wrap_and_original_state(qtbot, tmp_path, extension):
    array = np.arange(6 * 8 * 3, dtype=np.float32).reshape(6, 8, 3)
    window = viewer(qtbot, array, mode="slice", dimension=3, index=3)
    output = tmp_path / ("animation." + extension)
    before = window.slice_view.image.image.copy()
    progress = []
    window.export_animation(output, width=400, height=300, frames=4, fps=5, components=["title"],
                            progress=lambda done, total: progress.append(done) is None)
    frames = imageio.mimread(output)
    assert len(frames) == 4
    assert frames[0].shape[:2] == (300, 400)
    assert not np.array_equal(frames[0], frames[1])
    if extension == "gif":
        with Image.open(output) as image:
            assert image.info["loop"] == 0
            assert image.info["duration"] == 200
    assert progress == [0, 1, 2, 3, 4]
    assert window.state.index == 3
    np.testing.assert_array_equal(window.slice_view.image.image, before)


def test_cancel_leaves_destination_and_viewer_unchanged(qtbot, tmp_path):
    window = viewer(qtbot, np.arange(5 * 6 * 4).reshape(5, 6, 4), mode="slice")
    path = tmp_path / "keep.gif"
    path.write_bytes(b"original")
    with pytest.raises(ExportCancelled):
        window.export_animation(path, width=400, height=300, frames=5,
                                progress=lambda done, total: done < 1)
    assert path.read_bytes() == b"original"
    assert window.centralWidget().isEnabled()
    assert not list(tmp_path.glob(".fieldviz-export-*"))


def test_volume_image_and_single_level_animation(qtbot, tmp_path):
    coords = np.mgrid[-1:1:13j, -1:1:15j, -1:1:17j]
    array = (coords ** 2).sum(axis=0).astype(np.float32)
    window = viewer(qtbot, array, colormap="hot")
    with pytest.raises(ValueError, match="动画导出"):
        window.export_animation(tmp_path / "auto.gif", width=400, height=300, frames=2)
    window.export_image(tmp_path / "volume.png", width=640, height=480)
    renderer = PlotRenderer(window, 400, 300)
    try:
        renderer.frame()
        # Cube-axis labels must use the same camera as the mesh, especially when
        # copying an interactive camera into a fresh offscreen render window.
        assert (renderer.plotter.renderer.cube_axes_actor.GetCamera().GetAddressAsString("")
                == renderer.plotter.camera.GetAddressAsString(""))
    finally:
        renderer.close()
    window.iso_combo.setCurrentIndex(window.iso_combo.findData("single"))
    window.wait_until_ready()
    camera = window._volume_view.plotter.camera_position
    exact = window.state.exact
    window.export_animation(tmp_path / "single.gif", width=400, height=300, frames=3, fps=5)
    assert len(imageio.mimread(tmp_path / "single.gif")) == 3
    assert camera == window._volume_view.plotter.camera_position
    assert exact == window.state.exact


def test_volume_export_fits_full_box_after_panning_and_zooming(qtbot):
    coords = np.mgrid[-1:1:13j, -1:1:15j, -1:1:17j]
    window = viewer(qtbot, (coords ** 2).sum(axis=0))
    live = window._volume_view.plotter.camera
    live.Azimuth(29)
    live.Elevation(14)
    offset = np.array([40, -25, 0])
    live.position = np.asarray(live.position) + offset
    live.focal_point = np.asarray(live.focal_point) + offset
    live.zoom(4)
    initial_pose = (live.position, live.focal_point, live.parallel_scale)
    renderer = PlotRenderer(window, 400, 700, components=["axes", "axis_labels"])
    try:
        renderer.frame()
        plotter = renderer.plotter
        box = plotter.renderer.cube_axes_actor
        assert box.GetXTitle() == "Dim 1 index"
        assert not box.GetXAxisTickVisibility() and not any(box.x_labels)
        np.testing.assert_allclose(plotter.camera.direction, live.direction)
        # Check what VTK actually projects into the narrow output viewport.
        corners = []
        for corner in product((1, 13), (1, 15), (1, 17)):
            plotter.renderer.SetWorldPoint(*corner, 1)
            plotter.renderer.WorldToDisplay()
            corners.append(plotter.renderer.GetDisplayPoint()[:2])
        lower, upper = np.min(corners, axis=0), np.max(corners, axis=0)
        size = np.asarray(plotter.window_size)
        assert np.all(lower > 0) and np.all(upper < size)
        np.testing.assert_allclose(lower + upper, size)
    finally:
        renderer.close()
    assert (live.position, live.focal_point, live.parallel_scale) == initial_pose
    renderer = PlotRenderer(window, 400, 300, components=[])
    try:
        rgb = renderer.frame()
        assert renderer.plotter.renderer.cube_axes_actor is None
        assert np.any(np.ptp(rgb, axis=2) > 30)
    finally:
        renderer.close()


def test_empty_2d_restrictions_and_cli(qtbot, tmp_path):
    blank = visualize_field()
    qtbot.addWidget(blank)
    assert not blank.export_controls.image.isEnabled()
    with pytest.raises(ValueError, match="目标变量"):
        blank.export_image(tmp_path / "empty.png")
    array = np.arange(5 * 6).reshape(5, 6)
    source = tmp_path / "input.npy"
    np.save(source, array)
    window = viewer(qtbot, array)
    assert not window.export_controls.animation.isEnabled()
    with pytest.raises(ValueError, match="动画导出"):
        window.export_animation(tmp_path / "2d.gif")
    assert main([str(source), "--export-image", str(tmp_path / "cli.png"), "--export-size", "400", "300",
                 "--export-slice-data", str(tmp_path / "cli.npz"), "--export-components"]) == 0
    with np.load(tmp_path / "cli.npz") as saved:
        np.testing.assert_array_equal(saved["data"], array)


def test_export_validation_releases_ui(qtbot, tmp_path):
    window = viewer(qtbot, np.arange(5 * 6 * 3).reshape(5, 6, 3), mode="slice")
    for kwargs in ({"width": 0}, {"width": 401, "height": 300}, {"fps": 0}, {"frames": 0}):
        with pytest.raises(ValueError):
            window.export_animation(tmp_path / "invalid.mp4", **kwargs)
        assert window.centralWidget().isEnabled()
    assert not list(tmp_path.iterdir())
