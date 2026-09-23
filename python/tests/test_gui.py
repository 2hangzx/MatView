import time
from threading import Event

import numpy as np
import pytest

from fieldviz import visualize_field
from fieldviz.jobs import LatestJob


def settled(qtbot, window):
    qtbot.waitUntil(lambda: window.state is not None and not window.render_job.busy
                    and not window.render_timer.isActive() and not window.load_job.busy, timeout=30000)
    assert not window.statusBar().currentMessage().startswith("错误"), window.statusBar().currentMessage()


def test_no_arguments_and_file_selection(qtbot, tmp_path):
    window = visualize_field()
    qtbot.addWidget(window)
    assert window.state is None
    assert not window.controls.isEnabled()
    assert not window.target_combo.isEnabled()
    path = tmp_path / "a.npz"
    np.savez(path, a=np.arange(60, dtype=np.float32).reshape(5, 12))
    window.load_path(path)
    qtbot.waitUntil(lambda: window.target_combo.isEnabled())
    assert window.state is None  # Must choose a target even if the archive has only one.
    window.target_combo.setCurrentIndex(1)
    settled(qtbot, window)
    assert window.state.mode == "slice"
    assert window.controls.isEnabled()
    assert not window._groups["dimension"].isVisible()
    assert not window._groups["mode"].isVisible()


def test_slice_controls_playback_and_colorbar_layout(qtbot):
    data = np.arange(6 * 8 * 10, dtype=np.float32).reshape(6, 8, 10) * 1e-5 + 1
    window = visualize_field(data, mode="slice")
    qtbot.addWidget(window)
    settled(qtbot, window)
    assert window._groups["dimension"].isVisible()
    window.dimension_combo.setCurrentIndex(0)
    window.index_control.set_value(6)
    window.index_control.changed.emit(6)
    settled(qtbot, window)
    window._toggle_play()
    qtbot.waitUntil(lambda: window.state.index == 1)
    window.stop_playback()
    settled(qtbot, window)
    window.color_low.changed.emit(1.0001)
    settled(qtbot, window)
    assert window.state.color_mode == "custom"
    assert window.colorbar.limits[0] == 1.0001
    window.resize(680, 620)
    qtbot.wait(100)
    assert window.colorbar.geometry().right() < window.centralWidget().width()
    assert window.colorbar.width() >= max(window.fontMetrics().horizontalAdvance(s)
                                           for s in window.colorbar.labels) + 50
    assert window.scroll.verticalScrollBar().maximum() > 0


def test_explicit_hierarchy_and_namespace_refresh(qtbot):
    namespace = {"a": np.zeros((5, 6), dtype=np.float32)}
    window = visualize_field(namespace=namespace)
    qtbot.addWidget(window)
    assert window.state is None
    window.target_combo.setCurrentIndex(1)
    settled(qtbot, window)
    namespace["a"] = np.ones((7, 8), dtype=np.float32)
    window.refresh_source()
    settled(qtbot, window)
    assert window.state.bounds == (1, 1)
    assert window.state.handle.target.shape == (7, 8)
    locked = visualize_field(np.ones((5, 6, 7)), mode="slice", dimension=2, index=3,
                             color_limits=(0, 2))
    qtbot.addWidget(locked)
    settled(qtbot, locked)
    for name in ("mode", "dimension", "index", "color_mode", "color_bounds", "play"):
        assert not locked._groups[name].isVisible()


def test_latest_job_drops_stale_results(qtbot):
    job = LatestJob()
    gate = Event()
    completed, executed = [], []
    job.result.connect(completed.append)
    def first():
        gate.wait(2)
        executed.append(0)
        return 0
    job.submit(first)
    for value in range(1, 100):
        job.submit(lambda n=value: (executed.append(n), n)[1])
    gate.set()
    qtbot.waitUntil(lambda: not job.busy)
    assert completed == [99]
    assert executed == [0, 99]
    job.close()


def test_volume_switch_keeps_camera_and_alpha_avoids_mesh_rebuild(qtbot):
    x, y, z = np.ogrid[-1:1:15j, -1:1:17j, -1:1:19j]
    window = visualize_field(np.exp(-3 * (x*x + y*y + z*z)).astype(np.float32))
    qtbot.addWidget(window)
    settled(qtbot, window)
    assert window._volume_view is not None
    plotter = window._volume_view.plotter
    plotter.camera.azimuth += 20
    camera = tuple(plotter.camera.position)
    window.iso_combo.setCurrentIndex(1)
    settled(qtbot, window)
    assert tuple(plotter.camera.position) == camera
    actor = window._volume_view.actor
    window.alpha_control.changed.emit(0.7)
    assert window._volume_view.actor is actor
    assert abs(actor.prop.opacity - 0.7) < 1e-6
    assert not window.render_job.busy
    window.iso_combo.setCurrentIndex(0)
    settled(qtbot, window)
    assert tuple(plotter.camera.position) == camera
    window.mode_combo.setCurrentIndex(1)
    settled(qtbot, window)
    assert window.stack.currentWidget() is window.slice_view


def test_close_with_active_worker(qtbot):
    job = LatestJob()
    results = []
    job.result.connect(results.append)
    job.submit(lambda: (time.sleep(.05), 1)[1])
    job.close()
    qtbot.wait(100)
    assert results == []


def test_bad_file_recovery_and_automatic_npy_target(qtbot, tmp_path):
    path = tmp_path / "a.npy"
    np.save(path, np.ones((4, 7), dtype=np.float32))
    window = visualize_field()
    qtbot.addWidget(window)
    window.load_path(path)
    settled(qtbot, window)
    assert window.state.handle.target.shape == (4, 7)
    window.load_path(tmp_path / "missing.npy")
    qtbot.waitUntil(lambda: not window.load_job.busy)
    assert window.state is None
    assert window.path_edit.text() == str(path)
    assert window.statusBar().currentMessage().startswith("错误")
    window.load_path(path)
    settled(qtbot, window)


def test_single_isosurface_playback_and_auto_count_range(qtbot):
    x, y, z = np.ogrid[-1:1:11j, -1:1:13j, -1:1:15j]
    window = visualize_field((x*x + y*y + z*z).astype(np.float32))
    qtbot.addWidget(window)
    settled(qtbot, window)
    window.count_control.changed.emit(3)
    window.range_low.changed.emit(20)
    settled(qtbot, window)
    assert len(window.state.levels()) == 3
    assert window.state.fractions[0] == .2
    window.iso_combo.setCurrentIndex(1)
    settled(qtbot, window)
    window.exact_control.changed.emit(window.state.bounds[1])
    settled(qtbot, window)
    window._toggle_play()
    qtbot.waitUntil(lambda: window.state.exact == window.state.bounds[0], timeout=5000)
    window.stop_playback()
    settled(qtbot, window)


def test_invalid_call_does_not_create_a_window(qtbot):
    from PySide6.QtWidgets import QApplication
    before = set(QApplication.topLevelWidgets())
    with pytest.raises(ValueError, match="index"):
        visualize_field(np.ones((3, 4, 5)), mode="slice", dimension=2, index=100)
    assert set(QApplication.topLevelWidgets()) == before
    with pytest.raises(ValueError, match="field"):
        visualize_field(field="a")


def test_scientific_colorbar_and_precise_edit(qtbot):
    from fieldviz.widgets import ColorBar, NumberControl
    bar = ColorBar(np.array([[0, 0, 0], [255, 255, 255]]))
    qtbot.addWidget(bar)
    bar.set_limits((1.000000000001, 1.000000000002))
    assert len(set(bar.labels)) == 6
    number = NumberControl(0, 2, 1.000000000123)
    qtbot.addWidget(number)
    number._edited()
    assert number.value == 1.000000000123
