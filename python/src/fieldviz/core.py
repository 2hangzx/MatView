"""Pure data contracts shared by every source and renderer; no Qt dependency."""
from dataclasses import dataclass
import math
import numbers
from typing import Callable

import numpy as np


def field_shape(shape, dtype):
    """Mirror MATLAB trailing-singleton rules without squeezing inner axes."""
    shape = tuple(int(n) for n in shape)
    while len(shape) > 2 and shape[-1] == 1:
        shape = shape[:-1]
    if np.dtype(dtype).kind not in "iuf" or len(shape) not in (2, 3) or min(shape) < 2:
        return None
    return shape


@dataclass(frozen=True)
class Target:
    key: str
    shape: tuple
    dtype: str
    source_type: str

    @property
    def ndim(self):
        return len(self.shape)


class ArrayHandle:
    """Reads logical dimensions, always in source array order, without transposing physics."""

    def __init__(self, target: Target, reader: Callable):
        self.target = target
        self._reader = reader
        self._range = None

    @classmethod
    def from_array(cls, key, array, source_type="memory", copy=True):
        shape = field_shape(array.shape, array.dtype)
        if shape is None:
            raise ValueError("目标必须是各有效维度长度大于 1 的实数二维/三维数组。")
        value = np.array(array, copy=True) if copy else np.asarray(array)
        value = value.reshape(shape)
        if copy:
            value.flags.writeable = False
        return cls(Target(key, shape, str(value.dtype), source_type), lambda selection: value[selection])

    def read(self, selection=None):
        if selection is None:
            selection = (slice(None),) * self.target.ndim
        return np.asarray(self._reader(tuple(selection)))

    def read_slice(self, dimension=3, index=1):
        if self.target.ndim == 2:
            return self.read()
        if dimension not in (1, 2, 3) or not 1 <= index <= self.target.shape[dimension - 1]:
            raise ValueError("切片维度或索引超出数组范围。")
        selection = [slice(None)] * 3
        selection[dimension - 1] = index - 1
        return self.read(selection)

    def sample(self, max_size=96):
        # Uniform stride with explicit coordinates retains original array indices.
        strides = [max(1, math.ceil((n - 1) / (max_size - 1))) for n in self.target.shape]
        selections = tuple(slice(None, None, s) for s in strides)
        coordinates = tuple(np.arange(1, n + 1, s, dtype=float)
                            for n, s in zip(self.target.shape, strides))
        return self.read(selections), coordinates

    def finite_range(self):
        if self._range is None:
            low, high = math.inf, -math.inf
            # Statistics are exact, but use bounded slabs instead of a full-volume mask.
            slab = max(1, (8 * 1024 * 1024) //
                       (int(np.prod(self.target.shape[1:])) * np.dtype(self.target.dtype).itemsize))
            for start in range(0, self.target.shape[0], slab):
                selection = [slice(None)] * self.target.ndim
                selection[0] = slice(start, min(start + slab, self.target.shape[0]))
                block = self.read(selection)
                finite = block[np.isfinite(block)]
                if finite.size:
                    low, high = min(low, float(finite.min())), max(high, float(finite.max()))
            if not math.isfinite(low):
                raise ValueError("目标数组不含有限数值。")
            self._range = (low, high)
        return self._range


def display_range(bounds):
    low, high = bounds
    if low == high:
        pad = max(abs(low) * 1e-6, 1e-12)
        return low - pad, high + pad
    return low, high


@dataclass(frozen=True)
class Options:
    mode: str | None = None
    dimension: int | None = None
    index: int | None = None
    color_limits: object = None
    iso_values: tuple | None = None
    num_isosurfaces: int | None = None
    iso_range: tuple | None = None
    surface_alpha: float | None = None
    max_render_size: int | None = None
    colormap: str = "turbo"

    def __post_init__(self):
        if self.mode == "volume":
            # MATLAB's historical volume means isosurfaces, never silently a new renderer.
            object.__setattr__(self, "mode", "isosurface")
        if self.mode not in (None, "slice", "isosurface"):
            raise ValueError("mode 必须为 slice 或 isosurface（volume 是兼容别名）。")
        for name, minimum, maximum in (("dimension", 1, 3), ("index", 1, None),
                                       ("num_isosurfaces", 1, 12), ("max_render_size", 16, None)):
            value = getattr(self, name)
            if value is not None and (isinstance(value, bool) or not isinstance(value, numbers.Integral)
                                      or value < minimum or (maximum is not None and value > maximum)):
                raise ValueError(f"{name} 超出允许的整数范围。")
        if self.index is not None and self.dimension is None:
            raise ValueError("index 需要显式指定 dimension。")
        if (self.dimension is not None or self.index is not None) and self.mode != "slice":
            raise ValueError("dimension/index 需要显式指定 mode='slice'。")
        volume_options = (self.iso_values, self.num_isosurfaces, self.iso_range,
                          self.surface_alpha, self.max_render_size)
        if any(v is not None for v in volume_options) and self.mode != "isosurface":
            raise ValueError("等值面参数需要显式指定 mode='isosurface'。")
        if self.iso_values is not None:
            values = np.asarray(self.iso_values, dtype=float).reshape(-1)
            if not values.size or not np.all(np.isfinite(values)):
                raise ValueError("iso_values 必须包含有限数值。")
            if self.num_isosurfaces is not None or self.iso_range is not None:
                raise ValueError("iso_values 与自动数量/范围互斥。")
            object.__setattr__(self, "iso_values", tuple(np.unique(values)))
        if self.iso_range is not None:
            pair = tuple(float(x) for x in self.iso_range)
            if len(pair) != 2 or not 0 <= pair[0] < pair[1] <= 1:
                raise ValueError("iso_range 必须是 0 <= low < high <= 1。")
            object.__setattr__(self, "iso_range", pair)
        if self.surface_alpha is not None and not 0 < self.surface_alpha <= 1:
            raise ValueError("surface_alpha 必须在 (0, 1]。")
        if self.color_limits is not None:
            if isinstance(self.color_limits, str):
                if self.color_limits not in ("global", "slice"):
                    raise ValueError("color_limits 必须为 global、slice 或 (low, high)。")
            else:
                pair = tuple(float(x) for x in self.color_limits)
                if len(pair) != 2 or not all(map(math.isfinite, pair)) or pair[0] >= pair[1]:
                    raise ValueError("颜色栏上下限必须有限且 low < high。")
                object.__setattr__(self, "color_limits", pair)

    def accepts(self, target):
        return target.ndim == 3 or (self.mode != "isosurface" and self.dimension is None)


class ViewState:
    """Selected field and interactive values; explicit options stay locked in the UI."""

    def __init__(self, handle, options):
        if not options.accepts(handle.target):
            raise ValueError("目标维数与显式绘图参数不兼容。")
        self.handle = handle
        self.bounds = handle.finite_range()
        self.mode = "slice" if handle.target.ndim == 2 else (options.mode or "isosurface")
        self.dimension = options.dimension or 3
        length = handle.target.shape[self.dimension - 1] if handle.target.ndim == 3 else 1
        self.index = options.index if options.index is not None else (length + 1) // 2
        if self.index > length:
            raise ValueError(f"index 超出当前维度的 [1, {length}] 范围。")
        self.color_mode = options.color_limits if isinstance(options.color_limits, str) else "global"
        self.color_bounds = display_range(self.bounds)
        if isinstance(options.color_limits, tuple):
            self.color_mode, self.color_bounds = "custom", options.color_limits
        self.iso_mode = "explicit" if options.iso_values is not None else "automatic"
        self.iso_values = options.iso_values
        if self.iso_values and any(v < self.bounds[0] or v > self.bounds[1] for v in self.iso_values):
            raise ValueError("iso_values 必须在目标数组的全局范围内。")
        self.count = options.num_isosurfaces or 5
        self.fractions = options.iso_range or (0.15, 0.85)
        self.exact = sum(self.bounds) / 2
        self.alpha = options.surface_alpha if options.surface_alpha is not None else 0.22

    def levels(self):
        if self.iso_mode == "explicit":
            return np.asarray(self.iso_values)
        if self.iso_mode == "single":
            return np.array([self.exact])
        low, high = self.bounds
        start, end = (low + f * (high - low) for f in self.fractions)
        return np.array([(start + end) / 2]) if self.count == 1 else np.linspace(start, end, self.count)

    def advance(self):
        if self.mode == "slice" and self.handle.target.ndim == 3:
            self.index = self.index % self.handle.target.shape[self.dimension - 1] + 1
        elif self.iso_mode == "single":
            low, high = self.bounds
            step = (high - low) / 100
            self.exact = low if self.exact + step > high else self.exact + step
