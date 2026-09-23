"""Optional test against files produced by the adjacent MATLAB fixture generator."""
from pathlib import Path
import numpy as np
import pytest

from fieldviz.sources import open_source


@pytest.mark.parametrize("name", ["native_v7.mat", "native_v73.mat"])
def test_matlab_generated_fixture(name):
    path = Path(__file__).parent / "generated" / name
    if not path.exists():
        pytest.skip("Run tests/generate_matlab_fixture.m in MATLAB for cross-language checks")
    source = open_source(path)
    assert {t.key for t in source.list_targets()} == {"flow/field", "flow/plane", "flow/nested/matrix"}
    dim1, dim2, dim3 = np.indices((4, 6, 8))
    expected = (100 * dim1 + 10 * dim2 + dim3).astype(np.float32)
    handle = source.open_target("flow.field")
    assert handle.target.dtype == "float32"
    np.testing.assert_array_equal(handle.read(), expected)
    np.testing.assert_array_equal(handle.read_slice(2, 3), expected[:, 2, :])
    np.testing.assert_array_equal(source.open_target("flow/plane").read(), expected[:, :, 0])
    matrix = source.open_target("flow/nested/matrix").read()
    assert matrix.dtype == np.uint16
    np.testing.assert_array_equal(matrix, np.arange(1, 25).reshape((4, 6), order="F"))
