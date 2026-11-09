"""Export actual plot-only files for visual inspection (no controls)."""
from pathlib import Path
import numpy as np

from fieldviz import visualize_field


def main():
    output = Path("artifacts/export")
    output.mkdir(parents=True, exist_ok=True)
    coords = np.mgrid[-1:1:35j, -1:1:41j, -1:1:31j]
    array = (1.00003 + .00017 * np.exp(-3 * (coords ** 2).sum(axis=0))).astype(np.float32)
    window = visualize_field(array, colormap="jet")
    try:
        window.export_image(output / "python-volume.png", width=1200, height=900)
        window.iso_combo.setCurrentIndex(window.iso_combo.findData("single"))
        window.wait_until_ready()
        window.export_animation(output / "python-volume.gif", width=640, height=480, frames=8, fps=5)
        window.mode_combo.setCurrentIndex(window.mode_combo.findData("slice"))
        window.wait_until_ready()
        window.export_image(output / "python-slice.png", width=1200, height=900)
        window.export_animation(output / "python-slice.gif", width=640, height=480, frames=8, fps=5)
        window.export_slice_data(output / "python-slice.npz")
        window.grab().save(str(output / "python-menu.png"))
    finally:
        window.close()
    print("PYTHON_EXPORT_VISUAL_OK")


if __name__ == "__main__":
    main()
