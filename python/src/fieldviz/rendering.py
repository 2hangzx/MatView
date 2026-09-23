"""Array-to-image/mesh preparation. No Qt objects are touched in these functions."""
from dataclasses import dataclass
import numpy as np

from .core import display_range


@dataclass
class SliceFrame:
    data: np.ndarray
    bounds: tuple | None
    limits: tuple
    axes: tuple


def prepare_slice(handle, dimension, index, color_mode, color_bounds):
    data = handle.read_slice(dimension, index)
    finite = data[np.isfinite(data)]
    bounds = (float(finite.min()), float(finite.max())) if finite.size else None
    limits = display_range(bounds or handle.finite_range()) if color_mode == "slice" else color_bounds
    axes = (1, 2) if handle.target.ndim == 2 else tuple(d for d in (1, 2, 3) if d != dimension)
    return SliceFrame(data, bounds, limits, axes)


def prepare_mesh(handle, levels, max_size):
    import pyvista as pv
    data, coordinates = handle.sample(max_size)
    # VTK cannot contour float16/int64 directly in every version. Convert only the
    # bounded rendering sample, never the stored field or the statistics.
    sample = np.array(data, dtype=np.float64, copy=True)
    sample[~np.isfinite(sample)] = np.nan
    grid = pv.RectilinearGrid(*coordinates)
    grid.point_data["value"] = sample.ravel(order="F")
    mesh = grid.contour(np.unique(levels), scalars="value")
    return mesh, data.shape
