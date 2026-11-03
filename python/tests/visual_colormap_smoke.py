"""Render both modes using jet/hot and inspect a narrow control layout."""
from pathlib import Path
import numpy as np

from fieldviz import visualize_field
from visual_smoke import wait


def main():
    output = Path("artifacts")
    output.mkdir(exist_ok=True)
    x, y, z = np.ogrid[-1:1:35j, -1:1:43j, -1:1:31j]
    a = np.exp(-3 * (x*x + y*y + z*z)).astype(np.float32)
    window = visualize_field(np.stack((a, a * 2), axis=3))
    wait(window)
    for name in ("jet", "hot"):
        window.colormap_combo.setCurrentIndex(window.colormap_combo.findData(name))
        wait(window)
        window.grab().save(str(output / f"colormap-{name}-volume.png"))
    window.mode_combo.setCurrentIndex(1)
    wait(window)
    window.grab().save(str(output / "colormap-hot-slice.png"))
    window.resize(680, 680)
    wait(window)
    window.controls.show()
    window.scroll.ensureWidgetVisible(window.colormap_combo)
    wait(window)
    window.grab().save(str(output / "colormap-hot-slice-narrow.png"))
    window.close()
    print("COLORMAP_VISUAL_SMOKE_OK")


if __name__ == "__main__":
    main()
