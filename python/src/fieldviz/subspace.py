"""Select an N-D source's 2-D/3-D subarray using only basic indexing (no data copy)."""
from collections.abc import Mapping
from numbers import Integral

from .core import ArrayHandle, Target


def _positive_integer(value):
    return isinstance(value, Integral) and not isinstance(value, bool) and value >= 1


def validate_parameters(dimensions, indices):
    if dimensions is not None:
        try:
            dimensions = tuple(dimensions)
        except TypeError as exc:
            raise ValueError("retained_dimensions 必须为递增的 2 或 3 个维度编号。") from exc
        if (len(dimensions) not in (2, 3) or not all(map(_positive_integer, dimensions))
                or tuple(sorted(set(dimensions))) != dimensions):
            raise ValueError("retained_dimensions 必须为递增的 2 或 3 个正整数维度编号。")
    if indices is not None:
        if not isinstance(indices, Mapping) or not all(
                _positive_integer(d) and _positive_integer(i) for d, i in indices.items()):
            raise ValueError("extra_indices 必须为 {维度编号: 索引}，编号与索引均为正整数。")
        indices = dict(indices)
        if dimensions is not None and set(dimensions) & indices.keys():
            raise ValueError("extra_indices 只能指定未保留的维度。")
    return dimensions, indices


def selection_for(target, dimensions=None, indices=None):
    dimensions, indices = validate_parameters(dimensions, indices)
    shape = target.shape
    if target.ndim <= 3:
        if (dimensions is not None and dimensions != target.axes) or indices:
            raise ValueError("二维/三维数组不需要额外维度选择。")
        return target.axes, {}
    if dimensions is None:
        dimensions = tuple(d for d, n in enumerate(shape, 1) if n > 1)[:3]
    if any(d > len(shape) or shape[d - 1] <= 1 for d in dimensions):
        raise ValueError("保留维度超出原数组范围，或该维长度不足 2。")
    extras = {d: 1 for d in range(1, len(shape) + 1) if d not in dimensions}
    for d, i in (indices or {}).items():
        if d not in extras or i > shape[d - 1]:
            raise ValueError(f"extra_indices 的 Dim {d} 索引 {i} 不合法。")
        extras[d] = i
    return dimensions, extras


def project(handle, dimensions, indices):
    if handle.target.ndim <= 3:
        return handle
    target = handle.target
    projected = Target(target.key, tuple(target.shape[d - 1] for d in dimensions),
                       target.dtype, target.source_type, dimensions)
    def read(selection):
        selectors = iter(selection)
        return handle.read(tuple(next(selectors) if d in dimensions else indices[d] - 1
                                 for d in range(1, target.ndim + 1)))
    return ArrayHandle(projected, read)
