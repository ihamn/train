#!/usr/bin/env python3
"""
rectify.py — 从 3/4 透视图反解侧视轮廓

方法（交比法，只需等距特征）：
  给定图像上等距排列的 n≥3 个特征点 x1,x2,x3…（真实侧视中等距），
  求分式线性变换 u(x) = (a x + b)/(c x + d) 使它们映到等距位置。

  u 的四个自由度被约束：
    u(x1) = 0, u(x2) = 1, u(x3) = 2,  a = 1（归一化）
  ⇒ 唯一解：
    c = [ (x3-x1) - 2(x2-x1) ] / [ 2(x3-x2) ]
    d = (x2-x1) - c·x2
    b = -x1

  该变换同时给出灭点：x_vp = -d/c（分母零点，被推到无穷远）。

用法：
    python3 rectify.py --pts 340,380,411 --src 照片.png --out 侧视轮廓.png
"""
import argparse, sys
import numpy as np
from PIL import Image


def solve_transform(pts):
    pts = sorted(pts)
    if len(pts) < 3:
        sys.exit("至少需要 3 个等距点")
    x1, x2, x3 = pts[0], pts[1], pts[2]
    c = ((x3 - x1) - 2 * (x2 - x1)) / (2 * (x3 - x2))
    d = (x2 - x1) - c * x2
    a, b = 1.0, -x1
    return a, b, c, d


def make_u(abcd):
    a, b, c, d = abcd
    def u(x):
        den = c * x + d
        return (a * x + b) / den if abs(den) > 1e-9 else float("nan")
    return u


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pts", required=True, help="等距特征点的图像 x 坐标，逗号分隔")
    ap.add_argument("--show", action="store_true")
    a = ap.parse_args()
    pts = [float(v) for v in a.pts.split(",")]
    abcd = solve_transform(pts)
    u = make_u(abcd)
    print("变换: u(x) = (%.3f·x + %.3f) / (%.8f·x + %.3f)" % abcd)
    print("灭点 x = %.1f" % (-abcd[3] / abcd[2]))
    print("验证:")
    for i, x in enumerate(sorted(pts)):
        print("   x=%8.2f → u=%8.4f  (期望 %d)" % (x, u(x), i))
    np.save("/data/data/com.termux/files/usr/tmp/abcd.npy", np.array(abcd))


if __name__ == "__main__":
    main()
