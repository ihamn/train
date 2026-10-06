#!/usr/bin/env python3
"""
make_frames.py — 序列帧生成器

把「列车 sprite」沿一条路径贴到「场景底图」上，逐位置输出 N 帧。
用途：千星运行时不能移动控件，只能"逐帧换图"，所以移动 = 预先渲染 N 张图。

用法：
    # 直线轨道（水平）
    python3 make_frames.py --bg 场景.png --train 列车.png --frames 24 \
        --path "120,300 -> 900,300" -o frames/

    # 折线轨道（列车会按段自动旋转）
    python3 make_frames.py --bg 场景.png --train 列车.png --frames 48 \
        --path "100,300 -> 400,300 -> 600,240 -> 900,240" -o frames/ --rotate

    # 只出 1x 帧，不放大
    python3 make_frames.py ... --zoom 1

参数：
    --path      路径点，格式 "x,y -> x,y -> ..."（屏幕像素坐标）
    --frames    总帧数（列车位置的分档数量）
    --rotate    列车按路径方向旋转（需要 sprite 朝右）
    --zoom      输出放大倍数（默认 1）
    --alpha     列车透明度阈值
"""
import argparse
import math
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow")


def parse_path(spec):
    pts = []
    for part in spec.split("->"):
        part = part.strip()
        if not part:
            continue
        x, y = part.split(",")
        pts.append((float(x), float(y)))
    if len(pts) < 2:
        sys.exit("路径至少需要两个点")
    return pts


def path_length(pts):
    return [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]


def point_at(pts, lengths, dist):
    """沿折线走 dist 距离后的 (x, y, 方向角)"""
    total = sum(lengths)
    dist = max(0.0, min(total, dist))
    acc = 0.0
    for i, L in enumerate(lengths):
        if acc + L >= dist or i == len(lengths) - 1:
            t = 0.0 if L == 0 else (dist - acc) / L
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
            return x, y, ang
        acc += L
    x, y = pts[-1]
    return x, y, 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg", required=True, help="场景底图")
    ap.add_argument("--train", required=True, help="列车 sprite（建议 PNG 带透明）")
    ap.add_argument("--path", required=True, help='路径 "x,y -> x,y -> ..."')
    ap.add_argument("--frames", type=int, default=24)
    ap.add_argument("--rotate", action="store_true")
    ap.add_argument("--zoom", type=int, default=1)
    ap.add_argument("--anchor", default="center",
                    choices=["center", "bottom"],
                    help="列车对齐点：center=几何中心, bottom=底边中点(贴轨道)")
    ap.add_argument("-o", "--outdir", default="frames")
    a = ap.parse_args()

    bg = Image.open(a.bg).convert("RGBA")
    tr = Image.open(a.train).convert("RGBA")
    print("底图   %d × %d" % bg.size, file=sys.stderr)
    print("列车   %d × %d" % tr.size, file=sys.stderr)

    pts = parse_path(a.path)
    lens = path_length(pts)
    total = sum(lens)
    print("路径   %d 点，总长 %.0f px" % (len(pts), total), file=sys.stderr)

    os.makedirs(a.outdir, exist_ok=True)
    n = max(1, a.frames)

    for i in range(n):
        d = total * i / max(1, n - 1) if n > 1 else 0
        x, y, ang = point_at(pts, lens, d)

        sp = tr
        if a.rotate and abs(ang) > 0.01:
            sp = tr.rotate(-ang, resample=Image.NEAREST, expand=True)

        # 锚点
        if a.anchor == "bottom":
            ox = int(x - sp.width / 2)
            oy = int(y - sp.height)
        else:
            ox = int(x - sp.width / 2)
            oy = int(y - sp.height / 2)

        frame = bg.copy()
        frame.alpha_composite(sp, (ox, oy))
        if a.zoom > 1:
            frame = frame.resize((frame.width * a.zoom, frame.height * a.zoom),
                                 Image.NEAREST)
        fn = os.path.join(a.outdir, "f%03d.png" % i)
        frame.save(fn)

    print("已输出 %d 帧 → %s/" % (n, a.outdir), file=sys.stderr)
    print("提示：文本像素方案下，每帧跑一次", file=sys.stderr)
    print("      python3 png2blocks.py frames/f000.png --cols 160 --colors 24",
          file=sys.stderr)


if __name__ == "__main__":
    main()
