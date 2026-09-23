"""Render actual windows for visual QA; outputs are deliberately not tracked by Git."""
from pathlib import Path
import time

import numpy as np
from PySide6.QtWidgets import QApplication
from fieldviz import visualize_field


def wait(window):
    deadline = time.monotonic() + 60
    app = QApplication.instance()
    while window.render_timer.isActive() or window.render_job.busy or window.load_job.busy:
        app.processEvents()
        if time.monotonic() > deadline:
            raise TimeoutError("Rendering timed out")
        time.sleep(.01)
    for _ in range(10):
        app.processEvents()
        time.sleep(.02)
    assert not window.statusBar().currentMessage().startswith("错误"), window.statusBar().currentMessage()


def main():
    output = Path("artifacts")
    output.mkdir(exist_ok=True)
    x, y, z = np.ogrid[-1:1:35j, -1:1:43j, -1:1:31j]
    data = (1 + 0.0002 * np.exp(-3 * (x*x + y*y + z*z))).astype(np.float32)
    window = visualize_field(data)
    wait(window)
    window.grab().save(str(output / "volume-wide.png"))
    window.resize(680, 620)
    wait(window)
    window.grab().save(str(output / "volume-narrow.png"))
    window.mode_combo.setCurrentIndex(1)
    wait(window)
    window.grab().save(str(output / "slice-narrow.png"))
    window.resize(1180, 900)
    wait(window)
    window.grab().save(str(output / "slice-wide.png"))
    window.close()
    real = Path("../Data/data_uniGrid_zFlowDirct.mat")
    if real.exists():
        window = visualize_field(real, field="rho.rho_XYZ")
        wait(window)
        window.grab().save(str(output / "real-rho-volume.png"))
        window.close()
    print("VISUAL_SMOKE_OK")


if __name__ == "__main__":
    main()
