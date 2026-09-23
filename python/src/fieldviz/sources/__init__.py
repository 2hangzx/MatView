from pathlib import Path
import os

import h5py

from .base import DataSource
from .files import NumpySource, Hdf5Source, ClassicMatSource
from .memory import MemorySource, NamespaceSource


def open_source(value, *, namespace=None):
    if namespace is not None:
        if value is not None:
            raise ValueError("source 与 namespace 不能同时指定。")
        return NamespaceSource(namespace)
    if isinstance(value, DataSource):
        return value
    if isinstance(value, (str, os.PathLike)):
        path = Path(value).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(path)
        suffix = path.suffix.lower()
        if suffix == ".mat":
            return Hdf5Source(path, matlab=True) if h5py.is_hdf5(path) else ClassicMatSource(path)
        if suffix in (".npy", ".npz"):
            return NumpySource(path)
        if suffix in (".h5", ".hdf5"):
            return Hdf5Source(path)
        if suffix in (".pt", ".pth"):
            from .optional import TorchSource
            return TorchSource(path)
        if suffix == ".zarr":
            from .optional import ZarrSource
            return ZarrSource(path)
        if suffix == ".safetensors":
            from .optional import SafetensorsSource
            return SafetensorsSource(path)
        raise ValueError("支持 .mat/.npy/.npz/.h5/.hdf5/.pt/.pth/.zarr/.safetensors。")
    return MemorySource(value)


__all__ = ["DataSource", "MemorySource", "NamespaceSource", "open_source"]
