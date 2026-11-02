"""Visual QA of an N-D source through the same blank-window workflow used by users."""
import argparse
from pathlib import Path

import numpy as np
from fieldviz import visualize_field
from visual_smoke import wait


def main():
    command = argparse.ArgumentParser()
    command.add_argument("source", help="An N-D NPY file; read-only")
    args = command.parse_args()
    a = np.load(args.source, mmap_mode="r", allow_pickle=False)
    assert a.ndim == 4 and all(n > 1 for n in a.shape)
    window = visualize_field()
    window.load_path(args.source)
    # Source loading can enqueue target loading in a completion callback.
    wait(window)
    assert window.state is not None
    output = Path("artifacts")
    output.mkdir(exist_ok=True)
    for index in range(1, min(3, a.shape[3]) + 1):
        window.subspace_controls.extra_controls[4].changed.emit(index)
        wait(window)
        np.testing.assert_array_equal(window.state.handle.read_slice(3, 80 if a.shape[2] >= 80 else 1),
                                      a[:, :, 79 if a.shape[2] >= 80 else 0, index - 1])
        window.grab().save(str(output / f"nd-component-{index}-volume.png"))
        print("Component", index, "bounds", window.state.bounds,
              "mesh points", window._volume_view.actor.mapper.dataset.n_points)
    window.mode_combo.setCurrentIndex(1)
    wait(window)
    window.grab().save(str(output / "nd-slice-wide.png"))
    window.resize(680, 680)
    wait(window)
    window.grab().save(str(output / "nd-slice-narrow.png"))
    window.close()
    print("ND_VISUAL_SMOKE_OK")


if __name__ == "__main__":
    main()
