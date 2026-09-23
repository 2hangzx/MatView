"""Optional storage dependencies are imported only when their format is selected."""
from pathlib import Path

from ..core import ArrayHandle, Target, field_shape
from .base import FileSource
from .memory import MemorySource


class TorchSource(MemorySource, FileSource):
    def __init__(self, path):
        try:
            import torch
        except ImportError as exc:
            raise ImportError('PT 文件需要安装 fieldviz[torch]。') from exc
        # Never fall back to unrestricted pickle or execute a stored model object.
        value = torch.load(path, map_location="cpu", weights_only=True)
        super().__init__(value, kind="torch")
        self.name = str(path)


class ZarrSource(FileSource):
    kind = "zarr"

    def __init__(self, path):
        try:
            import zarr
        except ImportError as exc:
            raise ImportError('Zarr 文件需要安装 fieldviz[storage]。') from exc
        self.name = str(Path(path))
        self.root = zarr.open(path, mode="r")
        self.automatic_target = isinstance(self.root, zarr.Array)
        members = [("array", self.root)] if self.automatic_target else self.root.members(max_depth=None)
        self._arrays = {name: item for name, item in members if isinstance(item, zarr.Array)
                        and field_shape(item.shape, item.dtype)}

    def list_targets(self):
        return [Target(key, field_shape(a.shape, a.dtype), str(a.dtype), self.kind)
                for key, a in sorted(self._arrays.items())]

    def open_target(self, key):
        key = self.resolve_key(key)
        array = self._arrays[key]
        target = Target(key, field_shape(array.shape, array.dtype), str(array.dtype), self.kind)
        return ArrayHandle(target, lambda s: array[s + (0,) * (array.ndim - len(s))])


class SafetensorsSource(FileSource):
    kind = "safetensors"

    def __init__(self, path):
        try:
            from safetensors import safe_open
        except ImportError as exc:
            raise ImportError('Safetensors 文件需要安装 fieldviz[storage]。') from exc
        self.path = str(path)
        self.name = self.path
        self._targets = {}
        dtype_names = {"F64": "float64", "F32": "float32", "F16": "float16",
                       "I64": "int64", "I32": "int32", "I16": "int16", "I8": "int8", "U8": "uint8"}
        with safe_open(self.path, framework="numpy") as file:
            for name in file.keys():
                view = file.get_slice(name)
                dtype = dtype_names.get(view.get_dtype())
                shape = field_shape(view.get_shape(), dtype) if dtype else None
                if shape:
                    self._targets[name] = Target(name, shape, dtype, self.kind)

    def list_targets(self):
        return list(self._targets.values())

    def open_target(self, key):
        from safetensors import safe_open
        key = self.resolve_key(key)
        with safe_open(self.path, framework="numpy") as file:
            value = file.get_tensor(key)
        return ArrayHandle.from_array(key, value, self.kind, copy=False)
