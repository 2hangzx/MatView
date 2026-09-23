"""The command line mirrors the keyword-only Python contract."""
import argparse

from .api import visualize_field, run


def parser():
    result = argparse.ArgumentParser(description="查看 MAT / NumPy / HDF5 / Torch 中的二维、三维数组")
    result.add_argument("source", nargs="?", help="文件路径；省略时由窗口选择")
    result.add_argument("--field", help="目标路径，如 rho/rho_XYZ；省略时由窗口选择")
    result.add_argument("--mode", choices=("slice", "isosurface", "volume"))
    result.add_argument("--dimension", type=int, choices=(1, 2, 3))
    result.add_argument("--index", type=int, help="从 1 开始的切片索引")
    colors = result.add_mutually_exclusive_group()
    colors.add_argument("--color-limits", nargs=2, type=float, metavar=("LOW", "HIGH"))
    colors.add_argument("--color-scale", choices=("global", "slice"))
    result.add_argument("--iso-values", nargs="+", type=float)
    result.add_argument("--num-isosurfaces", type=int)
    result.add_argument("--iso-range", nargs=2, type=float, metavar=("LOW", "HIGH"))
    result.add_argument("--surface-alpha", type=float)
    result.add_argument("--max-render-size", type=int)
    result.add_argument("--colormap", default="turbo")
    return result


def main(argv=None):
    command = parser()
    args = vars(command.parse_args(argv))
    scale = args.pop("color_scale")
    if scale is not None:
        args["color_limits"] = scale
    try:
        visualize_field(**args)
    except (ValueError, TypeError, KeyError, OSError, ImportError) as exc:
        command.error(str(exc))
    return run()
