"""The command line mirrors the keyword-only Python contract."""
import argparse

from .api import visualize_field, run
from .exporting import COMPONENT_CHOICES


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
    result.add_argument("--export-image", metavar="PATH", help="导出仅含绘图区的图片后退出")
    result.add_argument("--export-animation", metavar="PATH", help="导出当前切片/单层等值面播放序列，GIF 或 MP4")
    result.add_argument("--export-slice-data", metavar="PATH", help="导出切片原始数据，NPZ/NPY/MAT/CSV")
    result.add_argument("--export-size", nargs=2, type=int, default=(1600, 1200), metavar=("WIDTH", "HEIGHT"))
    result.add_argument("--export-components", nargs="*", metavar="PART",
                        help="保留的可选部件（省略则全部保留）：" + ", ".join(name for name, _, _ in COMPONENT_CHOICES))
    result.add_argument("--frames", type=int, help="动画帧数；默认一个切片周期或 101 个单值帧")
    result.add_argument("--fps", type=float, help="导出帧率；默认采用当前播放间隔")
    return result


def main(argv=None):
    command = parser()
    args = vars(command.parse_args(argv))
    exports = {key: args.pop(key) for key in ("export_image", "export_animation", "export_slice_data")}
    width, height = args.pop("export_size")
    components = args.pop("export_components")
    if components is not None and not (exports["export_image"] or exports["export_animation"]):
        command.error("--export-components 需要同时指定 --export-image 或 --export-animation。")
    frames, fps = args.pop("frames"), args.pop("fps")
    if (frames is not None or fps is not None) and not exports["export_animation"]:
        command.error("--frames/--fps 需要同时指定 --export-animation。")
    pairs = args.pop("extra_index")
    if len(dict(pairs)) != len(pairs):
        command.error("--extra-index 的维度不能重复。")
    args["extra_indices"] = dict(pairs) if pairs else None
    scale = args.pop("color_scale")
    if scale is not None:
        args["color_limits"] = scale
    try:
        window = visualize_field(**args, show=not any(exports.values()))
        if any(exports.values()):
            try:
                if exports["export_image"]:
                    window.export_image(exports["export_image"], width=width, height=height, components=components)
                if exports["export_animation"]:
                    window.export_animation(exports["export_animation"], width=width, height=height,
                                            frames=frames, fps=fps, components=components)
                if exports["export_slice_data"]:
                    window.export_slice_data(exports["export_slice_data"])
            finally:
                window.close()
            return 0
    except (ValueError, TypeError, KeyError, OSError, ImportError, RuntimeError, TimeoutError) as exc:
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
