#!/usr/bin/env python3
"""
snap_windows.py — 把 sprite 上的窗户重画成规整矩形

为什么需要：AI 生成图里的窗框边缘是不规则的（JPEG 噪点 + 下采样抖动），
缩小后每个窗框都呈"断齿"状，看起来像糊了。滤镜类方法无法修复 ——
必须把窗户识别出来，再按像素网格重画。

做法：
  ① 在窗带内找米色块（窗户），按 x 聚类成一个个窗
  ② 每个窗对齐到整数网格，统一高度、统一 1px 深色边框
  ③ 窗间距不足时，把窗宽各收 1px 让间隔可见

用法：
    python3 snap_windows.py 输入.png -o 输出.png
    python3 snap_windows.py 输入.png -o 输出.png --frame "#1C1F23" --min-gap 2
"""
import argparse, sys
import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-o", "--output", default="snapped.png")
    ap.add_argument("--frame", default=None, help="窗框颜色 #RRGGBB（默认取窗带内最暗色）")
    ap.add_argument("--min-gap", type=int, default=2, help="窗之间最小间隔")
    ap.add_argument("--win-lo", type=int, default=200, help="窗户亮度下界")
    a = ap.parse_args()

    im = Image.open(a.src).convert("RGBA")
    arr = np.asarray(im).astype(np.int32).copy()
    H, W, _ = arr.shape
    fg = arr[:, :, 3] > 0
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b

    # 窗户 = 亮 + 偏暖（米色）
    win = fg & (lum > a.win_lo) & (r >= g) & (g > b)
    if win.sum() < 30:
        sys.exit("没找到窗户（试试调 --win-lo）")

    rows = np.where(win.sum(1) > 3)[0]
    y0, y1 = int(rows.min()), int(rows.max())
    band = win[y0:y1 + 1]
    colsum = band.sum(0)
    h = y1 - y0 + 1

    # 找窗块
    segs, ing = [], False
    for x in range(W):
        on = colsum[x] > h * 0.3
        if on and not ing:
            s = x; ing = True
        elif not on and ing:
            if x - s >= 3: segs.append([s, x - 1])
            ing = False
    if ing and W - s >= 3: segs.append([s, W - 1])
    print("找到 %d 个窗：%s" % (len(segs), segs), file=sys.stderr)

    # 统一窗高（取众数附近的中位）
    win_h = int(round(np.median([colsum[s:e+1].max() for s, e in segs])))
    win_h = max(3, win_h)
    yc = (y0 + y1) // 2
    ty0 = yc - win_h // 2
    ty1 = ty0 + win_h - 1

    # 窗框色：窗带内的暗色众数
    # 窗框色：取【窗户矩形外一圈】的暗色众数（不是窗内，窗内是玻璃色）
    ring = np.zeros((H, W), bool)
    for s_, e_ in segs:
        ry0, ry1 = max(0, ty0 - 2), min(H - 1, ty1 + 2)
        rx0, rx1 = max(0, s_ - 2), min(W - 1, e_ + 2)
        ring[ry0:ry1+1, rx0:rx1+1] = True
        ring[ty0:ty1+1, s_:e_+1] = False        # 挖掉窗内
    darkish = fg & ring & (lum < 110)
    if a.frame:
        fc = np.array([int(a.frame.lstrip("#")[i:i+2], 16) for i in (0, 2, 4)], np.int32)
    elif darkish.sum() > 10:
        px = arr[darkish][:, :3]
        vals, cnt = np.unique(px // 8 * 8, axis=0, return_counts=True)
        fc = vals[np.argmax(cnt)]
    else:
        fc = np.array([28, 31, 35], np.int32)
    print("窗框色 #%02X%02X%02X   窗高 %d" % (fc[0], fc[1], fc[2], win_h), file=sys.stderr)

    # 把窗重画成规整矩形
    gap = a.min_gap
    # 先从后往前收窄，保证间隔
    for i in range(len(segs) - 1, 0, -1):
        need = segs[i - 1][1] + gap + 1
        if segs[i][0] < need:
            shift = need - segs[i][0]
            segs[i][0] += shift
            segs[i][1] = max(segs[i][0] + 2, segs[i][1] - shift)
    for i in range(len(segs) - 1):
        need = segs[i + 1][0] - gap - 1
        if segs[i][1] > need:
            segs[i][1] = max(segs[i][0] + 2, need)

    body = arr[ty0:ty1+1, :, :3].reshape(-1, 3)
    for s, e in segs:
        if e - s < 2: continue
        # 窗内填米色（取该窗原本的亮色中位）
        sub = arr[ty0:ty1+1, s:e+1, :3]
        subm = win[ty0:ty1+1, s:e+1]
        fill = np.median(sub[subm], 0).astype(np.int32) if subm.sum() else np.array([246,225,186])
        arr[ty0+1:ty1, s+1:e, :3] = fill
        # 1px 边框
        arr[ty0, s:e+1, :3] = fc
        arr[ty1, s:e+1, :3] = fc
        arr[ty0:ty1+1, s, :3] = fc
        arr[ty0:ty1+1, e, :3] = fc

    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    out.save(a.output)
    print("写出 %s  (%dx%d)" % (a.output, out.width, out.height), file=sys.stderr)


if __name__ == "__main__":
    main()
