import numpy as np
import pytest

from fieldviz.core import ArrayHandle, field_shape, Options, ViewState, display_range
from fieldviz.rendering import prepare_slice, prepare_mesh


def array():
    a, b, c = np.indices((7, 9, 11))
    return (100 * a + 10 * b + c).astype(np.float32)


@pytest.mark.parametrize("shape, valid", [((3, 4), (3, 4)), ((3, 4, 1), (3, 4)),
    ((3, 4, 5, 1), (3, 4, 5)), ((1, 4, 5), None), ((3, 4, 5, 6), None), ((4,), None)])
def test_shapes(shape, valid):
    assert field_shape(shape, "float32") == valid


@pytest.mark.parametrize("dtype", ["bool", "complex64", "object", "U3"])
def test_rejected_types(dtype):
    assert field_shape((3, 4), dtype) is None


def test_slice_dimension_order_and_dtype():
    a = array()
    handle = ArrayHandle.from_array("a", a)
    for dimension in (1, 2, 3):
        np.testing.assert_array_equal(handle.read_slice(dimension, 2), np.take(a, 1, axis=dimension - 1))
    assert handle.read().dtype == np.float32
    assert handle.finite_range() == (0, 690)
    a[:] = -1
    assert handle.finite_range() == (0, 690)  # Own immutable snapshot.


def test_statistics_nan_constant_and_sample():
    a = array()
    a[0, 0, 0], a[-1, -1, -1] = np.nan, np.inf
    handle = ArrayHandle.from_array("a", a)
    assert handle.finite_range() == (1, 689)
    sampled, coords = handle.sample(4)
    assert all(n <= 4 for n in sampled.shape)
    assert tuple(int(c[-1]) for c in coords) == (7, 7, 9)
    with pytest.raises(ValueError, match="有限"):
        ArrayHandle.from_array("a", np.full((3, 4), np.nan)).finite_range()
    assert display_range((2, 2))[0] < 2 < display_range((2, 2))[1]


@pytest.mark.parametrize("kwargs", [dict(index=2), dict(dimension=1),
    dict(mode="slice", dimension="x"), dict(mode="slice", dimension=1, index=0),
    dict(mode="isosurface", iso_values=[1], num_isosurfaces=2),
    dict(iso_values=[1]), dict(mode="isosurface", iso_range=(.8, .1)),
    dict(color_limits=(2, 1)), dict(mode="bad"), dict(mode="volume", surface_alpha=np.nan)])
def test_parameter_contract(kwargs):
    with pytest.raises(ValueError):
        Options(**kwargs)


def test_state_levels_and_playback():
    state = ViewState(ArrayHandle.from_array("a", array()), Options())
    np.testing.assert_allclose(state.levels(), np.linspace(103.5, 586.5, 5))
    state.mode = "slice"
    state.index = 11
    state.advance()
    assert state.index == 1
    state.mode, state.iso_mode, state.exact = "isosurface", "single", 690
    state.advance()
    assert state.exact == 0
    assert Options(mode="volume").mode == "isosurface"


def test_two_dimensional_and_frames():
    handle = ArrayHandle.from_array("a", array()[:, :, :1])
    assert handle.target.shape == (7, 9)
    state = ViewState(handle, Options())
    assert state.mode == "slice"
    with pytest.raises(ValueError):
        ViewState(handle, Options(mode="volume"))
    frame = prepare_slice(handle, 3, 1, "slice", (0, 1))
    assert frame.bounds == (0, 680)
    assert frame.axes == (1, 2)


def test_mesh_coordinates_and_original_dtype():
    a = np.broadcast_to(np.arange(1, 8, dtype=np.float32)[:, None, None], (7, 9, 11))
    handle = ArrayHandle.from_array("a", a)
    mesh, shape = prepare_mesh(handle, [3.5], 96)
    assert mesh.n_points > 0
    np.testing.assert_allclose(mesh.points[:, 0], 3.5)
    assert shape == (7, 9, 11)
    assert handle.read().dtype == np.float32
