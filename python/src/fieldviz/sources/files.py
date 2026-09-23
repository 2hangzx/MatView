"""NumPy and HDF5 sources. File-backed handles own no user-memory copies."""
from pathlib import Path
import zipfile
import warnings

import h5py
import numpy as np

from ..core import ArrayHandle, Target, field_shape
from .base import FileSource, join_key


class NumpySource(FileSource):
    kind = "numpy"

    def __init__(self, path):
        self.path = Path(path)
        self.name = str(self.path)
        self.automatic_target = self.path.suffix.lower() == ".npy"
        self._targets = {}
        if self.automatic_target:
            value = np.load(self.path, mmap_mode="r", allow_pickle=False)
            shape = field_shape(value.shape, value.dtype)
            if shape:
                self._targets["array"] = Target("array", shape, str(value.dtype), self.kind)
            del value
        else:
            # Read only NPY headers; selecting a compressed NPZ entry decompresses that entry.
            with zipfile.ZipFile(self.path) as archive:
                for item in archive.infolist():
                    if not item.filename.endswith(".npy"):
                        continue
                    with archive.open(item) as stream:
                        version = np.lib.format.read_magic(stream)
                        if version == (1, 0):
                            shape, _, dtype = np.lib.format.read_array_header_1_0(stream)
                        elif version == (2, 0):
                            shape, _, dtype = np.lib.format.read_array_header_2_0(stream)
                        else:
                            raise ValueError("暂不支持该 NPZ 内部 NPY 版本。")
                    effective = field_shape(shape, dtype)
                    if effective:
                        key = item.filename[:-4]
                        self._targets[key] = Target(key, effective, str(dtype), self.kind)

    def list_targets(self):
        return sorted(self._targets.values(), key=lambda t: t.key)

    def open_target(self, key):
        key = self.resolve_key(key)
        if self.automatic_target:
            array = np.load(self.path, mmap_mode="r", allow_pickle=False)
        else:
            with np.load(self.path, allow_pickle=False) as archive:
                array = archive[key]
        return ArrayHandle.from_array(key, array, self.kind, copy=False)


class Hdf5Source(FileSource):
    kind = "hdf5"

    def __init__(self, path, *, matlab=False):
        self.path = Path(path)
        self.name = str(self.path)
        self.matlab = matlab
        if matlab:
            self.kind = "mat-v7.3"
        self._targets = {}
        with h5py.File(self.path, "r") as file:
            self._walk(file, "", set())

    def _walk(self, node, key, ancestors):
        address = h5py.h5o.get_info(node.id).addr
        if address in ancestors:
            return
        ancestors = ancestors | {address}
        if isinstance(node, h5py.Group):
            matlab_class = node.attrs.get("MATLAB_class", b"")
            if isinstance(matlab_class, bytes):
                matlab_class = matlab_class.decode()
            if self.matlab and node.name != "/" and matlab_class != "struct":
                return
            if self.matlab and matlab_class == "struct":
                # Non-scalar structs are reference arrays, outside this viewer's scope.
                if any(isinstance(child, h5py.Dataset) and h5py.check_dtype(ref=child.dtype)
                       and child.size != 1 for child in node.values()):
                    return
            for name in node:
                if name.startswith("#"):
                    continue
                link = node.get(name, getlink=True)
                if not isinstance(link, h5py.HardLink):
                    continue
                self._walk(node[name], join_key(key, name), ancestors)
        elif isinstance(node, h5py.Dataset):
            if self.matlab and h5py.check_dtype(ref=node.dtype):
                # Scalar struct field references only; cells are intentionally ignored.
                if node.size == 1 and node.attrs.get("MATLAB_class", b"") != b"cell":
                    ref = node[()].reshape(-1)[0]
                    if ref:
                        self._walk(node.file[ref], key, ancestors)
                return
            raw_shape = node.shape[::-1] if self.matlab else node.shape
            matlab_class = node.attrs.get("MATLAB_class", b"")
            if self.matlab and (node.attrs.get("MATLAB_empty", 0) or
                                matlab_class in (b"char", b"logical")):
                return
            effective = field_shape(raw_shape, node.dtype)
            if effective:
                self._targets[key] = (Target(key, effective, str(node.dtype), self.kind),
                                      node.name, raw_shape)

    def list_targets(self):
        return sorted((item[0] for item in self._targets.values()), key=lambda t: t.key)

    def open_target(self, key):
        target, dataset_path, raw_shape = self._targets[self.resolve_key(key)]
        # Reopen for each bounded read: switching sources cannot close a worker's file handle.
        def read(selection):
            selection = tuple(selection) + (0,) * (len(raw_shape) - len(selection))
            native = selection[::-1] if self.matlab else selection
            with h5py.File(self.path, "r") as file:
                value = file[dataset_path][native]
            if self.matlab:
                value = np.transpose(value)
            return value
        return ArrayHandle(target, read)


class ClassicMatSource(FileSource):
    kind = "mat-classic"

    def __init__(self, path):
        from scipy.io import loadmat, whosmat
        from scipy.io.matlab import mat_struct
        self.path = Path(path)
        self.name = str(self.path)
        self._targets = {}
        numeric = {"double", "single", "int8", "int16", "int32", "int64", "uint8",
                   "uint16", "uint32", "uint64"}

        def collect(value, key, root, fields):
            if isinstance(value, np.ndarray) and value.dtype.kind in "iuf":
                shape = field_shape(value.shape, value.dtype)
                if shape:
                    self._targets[key] = (Target(key, shape, str(value.dtype), self.kind), root, fields)
            elif isinstance(value, np.ndarray) and value.size == 1 and value.dtype.kind == "O":
                struct = value.reshape(-1)[0]
                if isinstance(struct, mat_struct):
                    for field in struct._fieldnames:
                        collect(getattr(struct, field), join_key(key, field), root, fields + (field,))

        # Classic MAT metadata lacks nested fields and the complex flag. Load one top-level
        # candidate at a time, discover and release it; do not claim lazy classic MAT reads.
        for name, _, cls in whosmat(self.path):
            if cls in numeric or cls == "struct":
                data = loadmat(self.path, variable_names=[name], squeeze_me=False, struct_as_record=False)
                collect(data[name], join_key("", name), name, ())
                del data
                if cls == "struct":
                    # SciPy's default preserves complex arrays but decodes logical leaves
                    # as uint8. A second, sequential metadata pass distinguishes logical
                    # from true uint8 without ever using its complex-to-real conversions.
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore", np.exceptions.ComplexWarning)
                        typed = loadmat(self.path, variable_names=[name], squeeze_me=False,
                                        struct_as_record=False, mat_dtype=True)[name]
                    rejected = []
                    for key, (_, root, fields) in self._targets.items():
                        if root != name:
                            continue
                        leaf = typed
                        for field in fields:
                            leaf = getattr(leaf.reshape(-1)[0], field)
                        if isinstance(leaf, np.ndarray) and leaf.dtype.kind == "b":
                            rejected.append(key)
                    for key in rejected:
                        del self._targets[key]
                    del typed

    def list_targets(self):
        return sorted((item[0] for item in self._targets.values()), key=lambda t: t.key)

    def open_target(self, key):
        from scipy.io import loadmat
        target, root, fields = self._targets[self.resolve_key(key)]
        value = loadmat(self.path, variable_names=[root], squeeze_me=False, struct_as_record=False)[root]
        for field in fields:
            value = getattr(value.reshape(-1)[0], field)
        return ArrayHandle.from_array(target.key, value, self.kind, copy=False)
