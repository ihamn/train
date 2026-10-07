#!/usr/bin/env python3
"""
make_train_v2.py — 至冬列车 sprite v2（含车头细节）

依据官方活动宣传图提取的车头特征：
  · 深蓝车身，车头尖端收成银白（向下收尖）
  · 前脸上部：连续长窗（4~5 格，白边）
  · 正脸中央：白色雪花徽记
  · 前缘 3~4 枚圆形暖白车灯
  · 底部深灰机械部（转向架）
  · 侧面：白边长方窗

用法：
    python3 make_train_v2.py                      # 侧面视图（默认）
    python3 make_train_v2.py --w 96 --cars 2
    python3 make_train_v2.py --view front         # 正脸视图
    python3 make_train_v2.py --scale 10
"""
import argparse, sys
from PIL import Image

C = {
    "outline": (8, 12, 22),
    "body_d":  (28, 42, 78),      # 车身暗
    "body":    (40, 58, 102),     # 车身主
    "body_l":  (62, 86, 140),     # 车身上亮
    "silver":  (196, 210, 232),   # 银白（车头尖端/雪花）
    "silver_d":(140, 156, 186),
    "win":     (232, 240, 254),   # 车窗（冷白）
    "win_d":   (150, 170, 205),
    "lamp":    (255, 244, 214),   # 车灯暖白
    "grey":    (74, 80, 96),      # 底部机械
    "grey_d":  (46, 52, 66),
    "rail":    (120, 136, 168),
}


def put(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((int(x), int(y)), c + (255,))


def rect(im, x0, y0, x1, y1, c):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            put(im, x, y, c)


def ln(im, x0, x1, y, c):
    rect(im, x0, y, x1, y, c)


def outline(im):
    src = im.copy()
    for y in range(im.height):
        for x in range(im.width):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < im.width and 0 <= ny < im.height and src.getpixel((nx, ny))[3] > 0:
                        im.putpixel((x, y), C["outline"] + (255,))
                        break


def side(w=96, cars=2):
    """侧面视图"""
    h = max(14, round(w * 0.185))
    im = Image.new("RGBA", (w, h + 8), (0, 0, 0, 0))
    y0 = 3
    roof = max(2, h // 7)
    skirt = max(2, h // 6)
    by0, by1 = y0 + roof, y0 + h - skirt - 1
    loco = max(32, round(w * 0.42))

    # ── 车厢 ──
    x = loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n - 1 else (w - x)
        if cw < 8:
            break
        rect(im, x + 1, y0 + h - skirt, x + cw - 2, y0 + h, C["grey"])
        rect(im, x, by0, x + cw - 1, by1, C["body"])
        ln(im, x + 1, x + cw - 2, by0, C["body_l"])
        ln(im, x + 1, x + cw - 2, by1, C["outline"])
        rect(im, x, y0, x + cw - 1, by0 - 1, C["body_d"])
        ln(im, x + 1, x + cw - 2, y0, C["body_l"])
        ln(im, x + 1, x + cw - 2, y0 + h - 1, C["rail"])
        # 侧面窗：白边长窗
        wy0, wy1 = by0 + 1, min(by1 - 1, by0 + 1 + max(2, (by1 - by0) // 2))
        if wy1 > wy0:
            cnt = max(2, cw // 12)
            span = cw - 6
            ww = max(3, (span - 2 * (cnt - 1)) // cnt)
            wx = x + 3
            for k in range(cnt):
                if wx + ww > x + cw - 3:
                    break
                rect(im, wx, wy0, wx + ww - 1, wy1, C["win"])
                ln(im, wx, wx + ww - 1, wy1, C["win_d"])
                wx += ww + 2
        x += cw

    # ── 车头 ──
    lw = loco
    rect(im, 3, y0 + h - skirt, lw - 1, y0 + h, C["grey"])
    rect(im, 0, by0, lw - 1, by1, C["body"])
    ln(im, 4, lw - 2, by0, C["body_l"])
    ln(im, 3, lw - 2, by1, C["outline"])
    rect(im, 2, y0, lw - 1, by0 - 1, C["body_d"])
    ln(im, 5, lw - 2, y0, C["body_l"])
    # 车头尖端（向左收成银白三角）
    tip = max(7, lw // 3)
    span = by1 - by0
    for i in range(tip):
        t = i / max(1, tip - 1)
        top = by0 + int(t * span * 0.42)
        bot = by1 - int(t * span * 0.30)
        col = C["silver"] if t < 0.62 else C["silver_d"] if t < 0.80 else C["body"]
        for y in range(top, bot + 1):
            put(im, i + 1, y, col)
    # 前脸长窗（连续，白边）
    wx0, wx1 = tip + 4, lw - 3
    if wx1 > wx0:
        wy0, wy1 = by0 + 1, min(by1 - 1, by0 + 1 + max(2, (by1 - by0) // 2))
        rect(im, wx0, wy0, wx1, wy1, C["win"])
        ln(im, wx0, wx1, wy1, C["win_d"])
        # 窗格分隔
        for gx in range(wx0 + 4, wx1, 5):
            ln(im, gx, gx, wy0, C["win_d"])
    # 雪花徽记（中央）
    sx, sy = tip + 2, (by0 + by1) // 2 + 1
    for dx, dy in [(0, 0), (0, -1), (0, 1), (0, -2), (0, 2), (-1, 0), (1, 0),
                   (-2, 0), (2, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
        put(im, sx + dx, sy + dy, C["silver"])
    # 车灯（前缘上下一对）
    put(im, tip - 1, by0 + 1, C["lamp"])
    put(im, tip - 1, by1 - 1, C["lamp"])
    put(im, tip - 2, by0 + 1, C["lamp"])
    # 转向架（底部两处）
    for bx in (lw // 3, (lw * 2) // 3):
        rect(im, bx, y0 + h - skirt + 1, bx + 3, y0 + h + 1, C["grey_d"])

    outline(im)
    return im


def front(w=64):
    """正脸视图（用于停靠/对位特写）"""
    h = max(20, round(w * 0.72))
    im = Image.new("RGBA", (w, h + 6), (0, 0, 0, 0))
    y0 = 3
    rect(im, 2, y0, w - 3, y0 + h, C["body"])
    # 上：银白顶盖
    rect(im, 4, y0, w - 5, y0 + 2, C["body_d"])
    ln(im, 5, w - 6, y0, C["body_l"])
    # 前脸长窗
    wy0, wy1 = y0 + 4, y0 + 7
    rect(im, 5, wy0, w - 6, wy1, C["win"])
    ln(im, 5, w - 6, wy1, C["win_d"])
    for gx in range(9, w - 6, 5):
        ln(im, gx, gx, wy0, C["win_d"])
    # 中央雪花徽记
    cx, cy = w // 2, y0 + h // 2 + 2
    for dx, dy in [(0, 0), (0, -1), (0, 1), (0, -2), (0, 2), (0, -3), (0, 3),
                   (-1, 0), (1, 0), (-2, 0), (2, 0), (-3, 0), (3, 0),
                   (-1, -1), (1, -1), (-1, 1), (1, 1), (-2, -2), (2, -2), (-2, 2), (2, 2)]:
        put(im, cx + dx, cy + dy, C["silver"])
    # 底部银白尖端（向下收尖）
    for i in range(6):
        x0 = 2 + i
        x1 = w - 3 - i
        if x0 > x1:
            break
        ln(im, x0, x1, y0 + h - i, C["silver"] if i < 3 else C["body_d"])
    # 车灯
    for lx in (4, w - 5):
        put(im, lx, wy1 + 2, C["lamp"])
        put(im, lx, wy1 + 3, C["lamp"])
    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=96)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--view", choices=["side", "front"], default="side")
    ap.add_argument("--scale", type=int, default=8)
    ap.add_argument("-o", "--output", default="train_v2.png")
    a = ap.parse_args()

    im = side(a.w, a.cars) if a.view == "side" else front(a.w)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width + 20, out.height + 20), (22, 28, 42, 255))
    bg.alpha_composite(out, (10, 10))
    bg.save(a.output)
    print("已写出 %s / %s" % (a.output, a.output.replace(".png", "_1x.png")), file=sys.stderr)


if __name__ == "__main__":
    main()
