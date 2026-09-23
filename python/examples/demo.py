"""Standalone synthetic example; no external data or MATLAB installation required."""
import numpy as np
from fieldviz import visualize_field, run

if __name__ == "__main__":
    d1, d2, d3 = np.ogrid[-1:1:55j, -1:1:65j, -1:1:45j]
    field = np.exp(-5 * (d1**2 + d2**2 + d3**2)).astype(np.float32)
    window = visualize_field({"demo": {"field": field, "plane": field[:, :, 22]}})
    run()
