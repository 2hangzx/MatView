"""The command line mirrors the keyword-only Python contract."""
import argparse

from .api import visualize_field, run


def parser():
    result = argparse.ArgumentParser(description="查看 MAT / NumPy / HDF5 / Torch 中的二维、三维数组")
    result.add_argument("source", nargs="?", help="文件路径；省略时由窗口选择")
    result.add_argument("--field", help="目标路径，如 rho/rho_XYZ；省略时由窗口选择")
    result.add_argument("--mode", choices=("slice", "isosurface", "volume"))
    result.add_argument("--dimension", type=int, help="原数组中保留的切片维度编号，从 1 开始")
    result.add_argument("--retained-dimensions", nargs="+", type=int,
                        help="递增的 2 或 3 个原数组维度编号，例如 1 2 3")
    result.add_argument("--extra-index", action="append", type=_extra_index, default=[],
                        help="额外维度及索引，例如 4=2；可重复指定，均从 1 开始")
    result.add_argument("--index", type=int, help="从 1 开始的切片索引")
    colors = result.add_mutually_exclusive_group()
    colors.add_argument("--color-limits", nargs=2, type=float, metavar=("LOW", "HIGH"))
    colors.add_argument("--color-scale", choices=("global", "slice"))
    result.add_argument("--iso-values", nargs="+", type=float)
    result.add_argument("--num-isosurfaces", type=int)
    result.add_argument("--iso-range", nargs=2, type=float, metavar=("LOW", "HIGH"))
    result.add_argument("--surface-alpha", type=float)
    result.add_argument("--max-render-size", type=int)
    result.add_argument("--colormap", help="固定色图名称，例如 jet、hot；省略时默认 turbo 并可在窗口选择")
    return result


def main(argv=None):
    command = parser()
    args = vars(command.parse_args(argv))
    pairs = args.pop("extra_index")
    if len(dict(pairs)) != len(pairs):
        command.error("--extra-index 的维度不能重复。")
    args["extra_indices"] = dict(pairs) if pairs else None
    scale = args.pop("color_scale")
    if scale is not None:
        args["color_limits"] = scale
    try:
        visualize_field(**args)
    except (ValueError, TypeError, KeyError, OSError, ImportError) as exc:
        command.error(str(exc))
    return run()


def _extra_index(text):
    try:
        dimension, index = (int(part) for part in text.split("="))
        if dimension < 1 or index < 1:
            raise ValueError
        return dimension, index
    except ValueError as exc:
        raise argparse.ArgumentTypeError("格式必须为正整数 DIM=INDEX，例如 4=2。") from exc
