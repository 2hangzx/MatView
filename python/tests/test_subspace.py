"""N-D input stays N-D until a lazy, explicitly labelled field is selected."""
import h5py
import numpy as np
import pytest
from scipy.io import savemat

from fieldviz import visualize_field
from fieldviz.core import ArrayHandle, Target, Options, ViewState, field_shape, source_shape
from fieldviz.sources import open_source
from fieldviz.rendering import prepare_slice


def data():
    return np.arange(4 * 6 * 8 * 3, dtype=np.float32).reshape(4, 6, 8, 3)


def settle(qtbot, window):
    qtbot.waitUntil(lambda: window.state is not None and not window.load_job.busy
                    and not window.render_job.busy and not window.render_timer.isActive()
                    and not window.subspace_timer.isActive() and not window._subspace_busy, timeout=30000)
    assert not window.statusBar().currentMessage().startswith("错误"), window.statusBar().currentMessage()


def test_classification_and_ordinary_fields_unchanged():
    assert field_shape((4, 6, 8, 3), "float32") is None
    assert source_shape((4, 6, 8, 3), "float32") == (4, 6, 8, 3)
    assert source_shape((4, 6, 8, 1), "float32") == (4, 6, 8)
    assert source_shape((1, 4, 6, 8), "float32") == (1, 4, 6, 8)
    for shape, dtype in [((1, 4, 6), "float32"), ((4, 6, 8, 3), "complex64"),
                          ((4, 6, 8, 3), "bool"), ((1, 1, 1, 4), "float32")]:
        assert source_shape(shape, dtype) is None


def test_selection_preserves_dtype_exact_values_and_axis_names():
    a = data()
    raw = open_source(a).open_target("array")
    state = ViewState(raw, Options(extra_indices={4: 2}))
    assert state.source_handle.target.shape == a.shape
    np.testing.assert_array_equal(state.handle.read(), a[..., 1])
    assert state.handle.read().dtype == np.float32
    assert state.bounds == (1, 574)
    state = ViewState(raw, Options(retained_dimensions=(1, 3, 4), extra_indices={2: 3},
                                   mode="slice", dimension=4, index=2))
    assert state.handle.target.axes == (1, 3, 4)
    assert state.dimension == 3  # Local index, while API/labels use original dimension 4.
    frame = prepare_slice(state.handle, state.dimension, state.index, "global", state.color_bounds)
    assert frame.axes == (1, 3)
    np.testing.assert_array_equal(frame.data, a[:, 2, :, 1])
    plane = ViewState(raw, Options(retained_dimensions=(2, 4), extra_indices={1: 2, 3: 5}))
    assert plane.mode == "slice"
    assert plane.handle.target.axes == (2, 4)
    np.testing.assert_array_equal(plane.handle.read(), a[1, :, 4, :])


def test_reads_never_materialize_other_components():
    a = data()
    requests = []
    def read(selection):
        requests.append(selection)
        assert selection[3] == 2
        return a[selection]
    state = ViewState(ArrayHandle(Target("a", a.shape, "float32", "spy"), read),
                      Options(extra_indices={4: 3}))
    state.handle.read_slice(2, 3)
    state.handle.sample(16)
    assert requests
    assert all(s[3] == 2 for s in requests)


def test_torch_and_namespace_nd_sources(tmp_path):
    torch = pytest.importorskip("torch")
    a = data()
    path = tmp_path / "nd.pt"
    torch.save({"field": torch.from_numpy(a)}, path)
    raw = open_source(path).open_target("field")
    np.testing.assert_array_equal(ViewState(raw, Options(extra_indices={4: 3})).handle.read(), a[..., 2])
    namespace = {"flow": {"field": a}}
    raw = open_source(None, namespace=namespace).open_target("flow/field")
    np.testing.assert_array_equal(ViewState(raw, Options(extra_indices={4: 2})).handle.read(), a[..., 1])


@pytest.mark.parametrize("kwargs", [dict(retained_dimensions=(3, 2, 1)),
    dict(retained_dimensions=(1, 1, 2)), dict(retained_dimensions=(1,)),
    dict(extra_indices={4: 0}), dict(extra_indices={True: 1}),
    dict(retained_dimensions=(1, 2, 3), extra_indices={3: 2})])
def test_invalid_parameters(kwargs):
    with pytest.raises(ValueError):
        Options(**kwargs)


@pytest.mark.parametrize("kwargs", [dict(extra_indices={4: 4}), dict(extra_indices={5: 1}),
    dict(retained_dimensions=(2, 3, 5)), dict(retained_dimensions=(1, 2), mode="volume"),
    dict(retained_dimensions=(1, 2, 3), mode="slice", dimension=4)])
def test_target_dependent_validation(kwargs):
    with pytest.raises(ValueError):
        ViewState(open_source(data()).open_target("array"), Options(**kwargs))


@pytest.mark.parametrize("suffix", [".npy", ".npz", ".h5", ".mat", ".v73.mat", ".zarr", ".safetensors"])
def test_nd_sources(tmp_path, suffix):
    a = data()[..., None, :]  # (4,6,8,1,3): fixed singleton plus independently selected Dim5.
    path = tmp_path / ("field" + suffix)
    if suffix == ".npy":
        np.save(path, a)
        key = "array"
    elif suffix == ".npz":
        np.savez(path, field=a)
        key = "field"
    elif suffix == ".h5":
        with h5py.File(path, "w") as file:
            file.create_dataset("field", data=a)
        key = "field"
    elif suffix == ".zarr":
        zarr = pytest.importorskip("zarr")
        zarr.open_group(path, mode="w").create_array("field", data=a)
        key = "field"
    elif suffix == ".safetensors":
        pytest.importorskip("safetensors.numpy").save_file({"field": a}, str(path))
        key = "field"
    else:
        key = "flow/field"
        if suffix == ".mat":
            savemat(path, {"flow": {"field": a}})
        else:
            pytest.importorskip("hdf5storage").savemat(
                path, {"flow": {"field": a}}, format="7.3", store_python_metadata=False)
    raw = open_source(path).open_target(key)
    assert raw.target.shape == a.shape
    state = ViewState(raw, Options(extra_indices={5: 2}))
    assert state.extra_indices == {4: 1, 5: 2}
    np.testing.assert_array_equal(state.handle.read(), a[:, :, :, 0, 1])
    other = ViewState(raw, Options(retained_dimensions=(2, 3, 5), extra_indices={1: 3}))
    np.testing.assert_array_equal(other.handle.read(), a[2, :, :, 0, :])
    np.testing.assert_array_equal(other.handle.read_slice(1, 2), a[2, 1, :, 0, :])


def test_gui_nd_file_switch_and_refresh(qtbot, tmp_path):
    path = tmp_path / "image.npy"
    a = data()
    np.save(path, a)
    window = visualize_field()
    qtbot.addWidget(window)
    window.load_path(path)
    settle(qtbot, window)
    assert window._groups["subspace"].isVisible()
    assert window.state.extra_indices == {4: 1}
    window._volume_view.plotter.camera.azimuth += 10
    camera = tuple(window._volume_view.plotter.camera.position)
    for index in (2, 1, 3, 2):
        window.subspace_controls.extra_controls[4].changed.emit(index)
    settle(qtbot, window)
    assert window.state.extra_indices == {4: 2}
    assert tuple(window._volume_view.plotter.camera.position) == camera
    assert "Dim 4=2" in window.stats.text()
    np.testing.assert_array_equal(window.state.handle.read(), a[..., 1])
    window.refresh_source()
    settle(qtbot, window)
    assert window.state.extra_indices == {4: 2}
    window.subspace_controls.retained_edit.setText("2, 4")
    window.subspace_controls._retained_edited()
    settle(qtbot, window)
    assert window.state.mode == "slice"
    assert window.state.handle.target.axes == (2, 4)
    assert not window._groups["mode"].isVisible()
    assert not window._groups["index"].isVisible()
    assert window.slice_view.getAxis("bottom").labelText == "Dim 2 index"
    window.resize(680, 680)
    qtbot.wait(80)
    assert window.scroll.verticalScrollBar().maximum() > 0


def test_explicit_nd_options_lock_only_requested_controls(qtbot):
    window = visualize_field(data()[..., None, :].repeat(2, axis=3), mode="slice", dimension=3,
                             retained_dimensions=(1, 2, 3), extra_indices={5: 2})
    qtbot.addWidget(window)
    settle(qtbot, window)
    assert window.subspace_controls.retained_edit.isReadOnly()
    assert set(window.subspace_controls.extra_controls) == {4}
    assert not window._groups["dimension"].isVisible()
    assert window._groups["index"].isVisible()


def test_nd_dimension_labels_and_invalid_retained_edit(qtbot):
    window = visualize_field(data(), mode="slice")
    qtbot.addWidget(window)
    settle(qtbot, window)
    window.subspace_controls.retained_edit.setText("1, 3, 4")
    window.subspace_controls._retained_edited()
    settle(qtbot, window)
    assert [window.dimension_combo.itemText(i) for i in range(3)] == ["Dim 1", "Dim 3", "Dim 4"]
    assert "Dim 4" in window.title.text()
    window.subspace_controls.retained_edit.setText("4, 3, 1")
    window.subspace_controls._retained_edited()
    assert window.subspace_controls.retained_edit.text() == "1, 3, 4"
    window.subspace_controls.extra_controls[2].changed.emit(2)
    settle(qtbot, window)
    assert window.state.retained_dimensions == (1, 3, 4)


def test_cli_nd_parameter_parsing():
    from fieldviz.cli import parser
    args = parser().parse_args(["image.npy", "--retained-dimensions", "1", "2", "3",
                                "--extra-index", "4=2", "--extra-index", "5=1"])
    assert args.retained_dimensions == [1, 2, 3]
    assert args.extra_index == [(4, 2), (5, 1)]
    with pytest.raises(SystemExit):
        parser().parse_args(["image.npy", "--extra-index", "4=0"])


def test_invalid_or_nonfinite_subspace_keeps_last_valid_frame(qtbot):
    a = data()
    a[..., 1] = np.nan
    window = visualize_field(a, mode="slice")
    qtbot.addWidget(window)
    settle(qtbot, window)
    window.subspace_controls.extra_controls[4].changed.emit(2)
    qtbot.waitUntil(lambda: not window._subspace_busy, timeout=30000)
    assert window.state.extra_indices == {4: 1}
    assert window.subspace_controls.extra_controls[4].value == 1
    assert window.statusBar().currentMessage().startswith("错误")
