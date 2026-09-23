from collections.abc import Mapping
import numpy as np

from ..core import ArrayHandle, Target, field_shape
from .base import DataSource, join_key


def is_tensor(value):
    return type(value).__module__.startswith("torch") and hasattr(value, "detach")


def as_array(value):
    if isinstance(value, np.ndarray):
        return value
    if is_tensor(value):
        import torch
        if value.layout != torch.strided or value.is_quantized or value.is_complex():
            raise ValueError("仅支持稠密、非量化、实数 Torch Tensor。")
        value = value.detach().cpu().resolve_conj().resolve_neg()
        if value.dtype == torch.bfloat16:
            value = value.float()
        return value.numpy()
    raise TypeError("需要 NumPy ndarray、Torch Tensor 或嵌套字典。")


def array_metadata(value):
    if isinstance(value, np.ndarray):
        return field_shape(value.shape, value.dtype), str(value.dtype)
    if is_tensor(value):
        import torch
        dtypes = {torch.float32: "float32", torch.float64: "float64", torch.float16: "float16",
                  torch.bfloat16: "float32", torch.int8: "int8", torch.uint8: "uint8",
                  torch.int16: "int16", torch.int32: "int32", torch.int64: "int64"}
        dtype = dtypes.get(value.dtype)
        if dtype and value.layout == torch.strided and not value.is_quantized:
            return field_shape(value.shape, dtype), dtype
    return None, ""


def discover(value, key="", ancestors=None):
    """Only inspect supported containers. Ignore arbitrary object attributes and cycles."""
    ancestors = set() if ancestors is None else ancestors
    shape, dtype = array_metadata(value)
    if shape:
        yield key or "array", value, shape, dtype
    elif isinstance(value, Mapping) and id(value) not in ancestors:
        next_ancestors = ancestors | {id(value)}
        for name, child in list(value.items()):
            if isinstance(name, str) and not name.startswith("__"):
                yield from discover(child, join_key(key, name), next_ancestors)


class MemorySource(DataSource):
    kind = "memory"

    def __init__(self, value, *, name="array", kind="memory"):
        self.name = name
        self.kind = kind
        self.automatic_target = isinstance(value, np.ndarray) or is_tensor(value)
        if not self.automatic_target and not isinstance(value, Mapping):
            raise TypeError("内存来源必须是数组、Tensor 或嵌套字典。")
        root = name if self.automatic_target else ""
        # Python has no MATLAB copy-on-write guarantee. Own explicit immutable snapshots.
        self._handles = {key: ArrayHandle.from_array(key, as_array(v), self.kind)
                         for key, v, _, _ in discover(value, root)}
        if not self._handles:
            raise ValueError("内存数据中没有合法实数二维/三维数组。")

    def list_targets(self):
        return sorted((h.target for h in self._handles.values()), key=lambda t: t.key)

    def open_target(self, key):
        return self._handles[self.resolve_key(key)]


class NamespaceSource(DataSource):
    kind = "namespace"
    name = "Python 命名空间（显式传入）"

    def __init__(self, namespace):
        if not isinstance(namespace, Mapping):
            raise TypeError("namespace 必须为 globals()、IPython user_ns 或显式字典。")
        self.namespace = namespace

    def list_targets(self):
        return sorted((Target(key, shape, dtype, self.kind)
                       for key, _, shape, dtype in discover(self.namespace)), key=lambda t: t.key)

    def open_target(self, key):
        key = self.resolve_key(key)
        for path, value, _, _ in discover(self.namespace):
            if key == path:
                return ArrayHandle.from_array(path, as_array(value), self.kind)
        raise KeyError(f"目标已从命名空间删除: {key}")
