"""Colormap changes update existing render objects, not geometry or scalar ranges."""
import numpy as np
import pytest
from matplotlib import colormaps

from fieldviz import visualize_field
from fieldviz.core import Options
from fieldviz.cli import parser


def settled(qtbot, window):
    qtbot.waitUntil(lambda: not window.render_timer.isActive() and not window.render_job.busy
                    and not window.load_job.busy and not window._subspace_busy
                    and not window.subspace_timer.isActive(), timeout=30000)
    assert not window.statusBar().currentMessage().startswith("错误")


def colors(name):
    return (colormaps[name](np.linspace(0, 1, 256)) * 255).astype(np.uint8)


def select(window, name):
    window.colormap_combo.setCurrentIndex(window.colormap_combo.findData(name))


def test_defaults_and_command_line_contract():
    assert Options().colormap == "turbo"
    assert not Options().colormap_specified
    assert Options(colormap="turbo").colormap_specified
    assert parser().parse_args([]).colormap is None
    assert parser().parse_args(["--colormap", "jet"]).colormap == "jet"
    with pytest.raises(ValueError, match="colormap"):
        Options(colormap=123)
    with pytest.raises(ValueError, match="未知色图"):
        visualize_field(colormap="__invalid__")


def test_empty_viewer_disables_then_enables_colormap(qtbot, tmp_path):
    window = visualize_field()
    qtbot.addWidget(window)
    assert window._groups["colormap"].isVisible()
    assert not window.colormap_combo.isEnabled()
    path = tmp_path / "plane.npy"
    np.save(path, np.arange(30, dtype=np.float32).reshape(5, 6))
    window.load_path(path)
    settled(qtbot, window)
    assert window.colormap_combo.isEnabled()
    select(window, "jet")
    assert window.colormap == "jet"


def test_slice_recolor_preserves_array_image_range_and_view(qtbot):
    a = np.arange(5 * 6 * 7, dtype=np.float32).reshape(5, 6, 7)
    window = visualize_field(a, mode="slice", color_limits=(-1, 500))
    qtbot.addWidget(window)
    settled(qtbot, window)
    image = window.slice_view.image
    data = image.image
    index = window.state.index
    window.slice_view.getViewBox().setRange(xRange=(1, 3), yRange=(2, 5), padding=0)
    view = window.slice_view.getViewBox().viewRange()
    for name in ("jet", "hot", "viridis", "hot_r"):
        select(window, name)
        assert window.slice_view.image is image
        assert image.image is data
        np.testing.assert_array_equal(image.lut, colors(name))
        np.testing.assert_array_equal(window.colorbar.colors, colors(name))
        assert window.colorbar.limits == (-1, 500)
        assert window.state.index == index
        np.testing.assert_allclose(window.slice_view.getViewBox().viewRange(), view)
        assert not window.render_job.busy and not window.render_timer.isActive()


def test_volume_recolor_preserves_mesh_alpha_camera_and_selected_subarray(qtbot):
    x, y, z = np.ogrid[-1:1:11j, -1:1:13j, -1:1:15j]
    a = np.exp(-3 * (x*x + y*y + z*z)).astype(np.float32)
    window = visualize_field(np.stack((a, a * 2), axis=3))
    qtbot.addWidget(window)
    settled(qtbot, window)
    view = window._volume_view
    actor = view.actor
    mesh = actor.mapper.dataset
    limits = actor.mapper.scalar_range
    alpha = actor.prop.opacity
    view.plotter.camera.azimuth += 20
    camera = tuple(view.plotter.camera.position)
    levels = window.state.levels().copy()
    select(window, "hot")
    assert view.actor is actor and actor.mapper.dataset is mesh
    assert actor.mapper.scalar_range == limits
    assert actor.prop.opacity == alpha
    assert tuple(view.plotter.camera.position) == camera
    np.testing.assert_array_equal(actor.mapper.lookup_table.values, colors("hot"))
    np.testing.assert_array_equal(window.state.levels(), levels)
    assert not window.render_job.busy and not window.render_timer.isActive()
    window.subspace_controls.extra_controls[4].changed.emit(2)
    settled(qtbot, window)
    np.testing.assert_array_equal(view.actor.mapper.lookup_table.values, colors("hot"))
    window.mode_combo.setCurrentIndex(1)
    settled(qtbot, window)
    np.testing.assert_array_equal(window.slice_view.image.lut, colors("hot"))
    select(window, "jet")
    window.mode_combo.setCurrentIndex(0)
    settled(qtbot, window)
    np.testing.assert_array_equal(view.actor.mapper.lookup_table.values, colors("jet"))


@pytest.mark.parametrize("mode", ["slice", "volume"])
def test_explicit_colormap_is_locked_and_applied(qtbot, mode):
    window = visualize_field(np.arange(5 * 6 * 7).reshape(5, 6, 7), mode=mode, colormap="hot")
    qtbot.addWidget(window)
    settled(qtbot, window)
    assert not window._groups["colormap"].isVisible()
    np.testing.assert_array_equal(window.colorbar.colors, colors("hot"))
    if mode == "volume":
        np.testing.assert_array_equal(window._volume_view.actor.mapper.lookup_table.values, colors("hot"))
    else:
        np.testing.assert_array_equal(window.slice_view.image.lut, colors("hot"))
