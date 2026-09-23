import numpy as np
import pytest
import h5py
from scipy.io import savemat
from scipy.sparse import csr_matrix

from fieldviz.sources import open_source, MemorySource, NamespaceSource


@pytest.fixture
def values():
    a, b, c = np.indices((4, 6, 8))
    return (100 * a + 10 * b + c).astype(np.float32)


def check_handle(handle, values):
    assert handle.target.shape == values.shape
    assert handle.target.dtype == "float32"
    np.testing.assert_array_equal(handle.read(), values)
    for dim in (1, 2, 3):
        np.testing.assert_array_equal(handle.read_slice(dim, 2), np.take(values, 1, axis=dim - 1))
    assert handle.finite_range() == (0, 357)
    sample, _ = handle.sample(3)
    np.testing.assert_array_equal(sample, values[::2, ::3, ::4])


def test_memory_dict_cycle_alias_and_namespace_snapshot(values):
    mapping = {"outer": {"field": values}, "outer.field": values + 1,
               "string": "no", "vector": np.arange(5), "complex": values + 1j}
    mapping["cycle"] = mapping
    source = MemorySource(mapping)
    assert {t.key for t in source.list_targets()} == {"outer/field", "outer.field"}
    check_handle(source.open_target("outer/field"), values)
    assert source.open_target("outer.field").read()[0, 0, 0] == 1
    namespace = NamespaceSource(mapping)
    first = namespace.open_target("outer/field")
    mapping["outer"]["field"] = values + 10
    assert first.read()[0, 0, 0] == 0
    assert namespace.open_target("outer/field").read()[0, 0, 0] == 10


@pytest.mark.parametrize("suffix", [".npy", ".npz", ".h5", ".mat", ".v73.mat"])
def test_formats_preserve_orientation_and_dtype(tmp_path, values, suffix):
    path = tmp_path / ("fixture" + suffix)
    if suffix == ".npy":
        np.save(path, values)
        key = "array"
    elif suffix == ".npz":
        np.savez_compressed(path, field=values, vector=np.arange(9), obj=np.array([{}], dtype=object))
        key = "field"
    elif suffix == ".h5":
        with h5py.File(path, "w") as file:
            file.create_dataset("nested/field", data=values)
            file.create_dataset("matrix", data=values[:, :, :1])
            file["cycle"] = file
            file["external"] = h5py.ExternalLink("missing.h5", "/field")
        key = "nested/field"
    else:
        data = {"nested": {"field": values, "bools": values > 1, "cx": values + 1j},
                "matrix": values[:, :, :1],
                "complex": values.astype(complex), "bools": values > 1}
        if suffix == ".mat":
            data["sparse"] = csr_matrix(np.eye(3))
            savemat(path, data)
        else:
            import hdf5storage
            hdf5storage.savemat(path, data, format="7.3", store_python_metadata=False)
        key = "nested/field"
    source = open_source(path)
    check_handle(source.open_target(key), values)
    assert not {"complex", "bools", "vector", "obj", "sparse"} & {t.key for t in source.list_targets()}
    assert not {"nested/bools", "nested/cx"} & {t.key for t in source.list_targets()}
    if suffix not in (".npy", ".npz"):
        matrix = source.open_target("matrix")
        assert matrix.target.shape == (4, 6)
        np.testing.assert_array_equal(matrix.read(), values[:, :, 0])


def test_mat_struct_reference_and_generic_hdf_shape(tmp_path, values):
    path = tmp_path / "references.mat"
    with h5py.File(path, "w") as file:
        field = file.create_dataset("#refs#/a", data=values.transpose())
        field.attrs["MATLAB_class"] = np.bytes_("single")
        group = file.create_group("S")
        group.attrs["MATLAB_class"] = np.bytes_("struct")
        refs = group.create_dataset("field", (1, 1), dtype=h5py.ref_dtype)
        refs[0, 0] = field.ref
        cells = file.create_dataset("cells", (1, 1), dtype=h5py.ref_dtype)
        cells.attrs["MATLAB_class"] = np.bytes_("cell")
        cells[0, 0] = field.ref
    source = open_source(path)
    assert [t.key for t in source.list_targets()] == ["S/field"]
    check_handle(source.open_target("S.field"), values)


def test_zarr(tmp_path, values):
    zarr = pytest.importorskip("zarr")
    path = tmp_path / "fixture.zarr"
    group = zarr.open_group(path, mode="w")
    group.create_array("flow/field", data=values, chunks=(2, 3, 4))
    source = open_source(path)
    check_handle(source.open_target("flow/field"), values)


def test_safetensors(tmp_path, values):
    st = pytest.importorskip("safetensors.numpy")
    path = tmp_path / "fixture.safetensors"
    st.save_file({"field": values}, str(path))
    check_handle(open_source(path).open_target("field"), values)


def test_torch_tensor_and_safe_checkpoint(tmp_path, values):
    torch = pytest.importorskip("torch")
    tensor = torch.from_numpy(values.copy()).requires_grad_()
    source = open_source(tensor)
    check_handle(source.open_target("array"), values)
    path = tmp_path / "fixture.pt"
    torch.save({"flow": {"field": tensor}}, path)
    check_handle(open_source(path).open_target("flow/field"), values)
    assert open_source(tensor.to(torch.bfloat16)).open_target("array").read().dtype == np.float32
    assert open_source(path).kind == "torch"
    source = open_source(path)
    torch.save({"flow": {"field": tensor + 2}}, path)
    assert source.refresh().open_target("flow/field").read()[0, 0, 0] == 2


def test_torch_does_not_fall_back_to_pickle(tmp_path):
    import pickle
    from types import SimpleNamespace
    torch = pytest.importorskip("torch")
    path = tmp_path / "unsupported.pt"
    torch.save(SimpleNamespace(field=torch.ones((3, 4))), path)
    with pytest.raises(pickle.UnpicklingError):
        open_source(path)


def test_numpy_pickle_not_accepted(tmp_path):
    path = tmp_path / "objects.npy"
    np.save(path, np.array([[{}, {}], [{}, {}]], dtype=object))
    with pytest.raises(ValueError):
        open_source(path)


def test_unsupported_source_and_empty():
    with pytest.raises(TypeError):
        open_source(object())
    assert NamespaceSource({}).list_targets() == []
