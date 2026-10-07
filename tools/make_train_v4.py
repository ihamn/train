#!/usr/bin/env python3
"""
make_train_v4.py — 至冬列车 sprite v4（照实机照片的比例重画）

实机的关键几何（照片实测比例）：
  · 车头 = 厚重的「犁/船首」形，向前下方伸出，占比很大
  · 后上方：巨大翼状结构，高出车体 2~3 倍  ← 剪影第一特征
  · 蓝晶体成组：车头下部 2 块 + 上部 2~3 块
  · 红褐排障器占车头下半 1/2
  · 车身深褐灰 + 板条纹理；中段有烟囱/蒸汽设备凸起
  · 侧面长窗列

用法：
    python3 make_train_v4.py                        # 侧面
    python3 make_train_v4.py --w 160 --cars 2 --scale 5
    python3 make_train_v4.py --view front --w 80
"""
import argparse, sys
from PIL import Image

C = {
    "outline":   (16, 14, 18),
    "hull":      (52, 48, 56),
    "hull_l":    (84, 78, 88),
    "hull_d":    (30, 28, 34),
    "roof":      (40, 37, 44),
    "plow":      (134, 78, 62),
    "plow_l":    (176, 108, 86),
    "plow_d":    (88, 48, 40),
    "gold":      (190, 158, 92),
    "gold_d":    (132, 108, 58),
    "crystal":   (92, 182, 236),
    "crystal_l": (176, 230, 255),
    "crystal_d": (44, 110, 174),
    "lamp":      (255, 228, 152),
    "black":     (20, 20, 24),
    "win":       (170, 190, 212),
    "win_d":     (104, 122, 146),
    "fin":       (44, 41, 49),      # 翼
    "fin_l":     (76, 72, 82),
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


def crystal(im, cx, cy, r):
    for dy in range(-r, r + 1):
        w = max(0, r - abs(dy))
        for dx in range(-w, w + 1):
            put(im, cx + dx, cy + dy,
                C["crystal_l"] if abs(dx) + abs(dy) <= max(1, r // 2) else C["crystal"])
    for k in range(1, max(2, r)):
        put(im, cx, cy - r - k, C["crystal_d"])
        put(im, cx, cy + r + k, C["crystal_d"])
        put(im, cx - r - k, cy, C["crystal_d"])
        put(im, cx + r + k, cy, C["crystal_d"])


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


def side(w=160, cars=2):
    body_h = max(18, round(w * 0.155))       # 按照片：车体较扁
    fin_h  = max(10, round(body_h * 1.5))    # 翼高出车体 1.5 倍（照片约 2~3，取保守）
    total_h = fin_h + body_h + 6
    im = Image.new("RGBA", (w, total_h), (0, 0, 0, 0))

    y_body = fin_h + 3                        # 车体顶
    y_bot  = y_body + body_h - 1
    plow_h = max(5, body_h // 2)              # 排障器占车身下半 1/2
    loco   = max(56, round(w * 0.46))         # 车头占比大

    # ── 车头（左端） ──
    # 车身主体
    rect(im, 4, y_body, loco - 1, y_bot - plow_h, C["hull"])
    for yy in range(y_body + 2, y_bot - plow_h, 3):
        ln(im, 5, loco - 2, yy, C["hull_l"])
    ln(im, 5, loco - 2, y_body, C["hull_l"])
    # 车头「犁」：从车身向左前下方伸出
    nose_x = 0
    for i in range(loco // 2):
        x = nose_x + i
        top = y_body + int(i * 0.25)
        bot = y_bot - plow_h + int(i * 0.55)
        if bot > top:
            for y in range(top, min(bot, y_bot) + 1):
                put(im, x, y, C["hull"] if i % 3 else C["hull_l"])
    # 排障器（大，红褐，占车头下半）
    for i in range(loco):
        x = i
        top = y_bot - plow_h + max(0, plow_h // 2 - int(i * 0.35))
        for y in range(top, y_bot + 1):
            col = C["plow_l"] if y == top else C["plow"] if (x + y) % 7 else C["plow_d"]
            put(im, x, y, col)
    ln(im, 0, loco - 1, y_bot, C["black"])
    # 金边（前缘弧）
    for y in range(y_body, y_bot - plow_h):
        put(im, 3, y, C["gold"])
    # 蓝晶体：下部 2 块 + 上部 2 块
    crystal(im, max(10, loco // 5), y_bot - plow_h // 2, max(2, body_h // 9))
    crystal(im, max(20, loco // 3), y_bot - plow_h // 2 - 1, max(2, body_h // 10))
    crystal(im, max(14, loco // 4), y_body + body_h // 3, max(2, body_h // 10))
    crystal(im, max(26, loco // 2), y_body + body_h // 3 - 1, max(2, body_h // 11))
    # 车灯
    put(im, max(6, loco // 8), y_body + 2, C["lamp"])
    put(im, max(7, loco // 8) + 1, y_body + 2, C["lamp"])
    # 驾驶室窗列
    wx0, wx1 = loco // 2 + 2, loco - 3
    if wx1 > wx0:
        wy1 = y_body + 2 + max(3, body_h // 4)
        rect(im, wx0, y_body + 2, wx1, wy1, C["win"])
        ln(im, wx0, wx1, wy1, C["win_d"])
        for gx in range(wx0 + 5, wx1, 6):
            ln(im, gx, gx, y_body + 2, C["win_d"])
    # 烟囱/蒸汽凸起
    put(im, loco - 6, y_body - 2, C["roof"]); put(im, loco - 6, y_body - 1, C["roof"])
    put(im, loco - 5, y_body - 2, C["hull_l"])

    # ── 翼（后上方，巨大） ──
    fin_x0 = loco - 4
    for i in range(w - fin_x0):
        t = i / max(1, w - fin_x0 - 1)
        top = y_body - int(fin_h * (0.35 + 0.65 * t))
        col = C["fin"] if i % 2 else C["fin_l"]
        for y in range(top, y_body):
            put(im, fin_x0 + i, y, col)
    # 翼上缘金线
    for i in range(0, w - fin_x0, 2):
        t = i / max(1, w - fin_x0 - 1)
        put(im, fin_x0 + i, y_body - int(fin_h * (0.35 + 0.65 * t)) - 1, C["gold_d"])

    # ── 车厢 ──
    x = loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n - 1 else (w - x)
        if cw < 12:
            break
        rect(im, x, y_body, x + cw - 1, y_bot - plow_h + 2, C["hull"])
        for yy in range(y_body + 2, y_bot - plow_h + 2, 3):
            ln(im, x + 1, x + cw - 2, yy, C["hull_l"])
        ln(im, x + 1, x + cw - 2, y_body, C["hull_l"])
        rect(im, x, y_body, x + cw - 1, y_body, C["roof"])
        rect(im, x + 1, y_bot - plow_h + 3, x + cw - 2, y_bot, C["plow"])
        ln(im, x + 1, x + cw - 2, y_bot, C["black"])
        wy1 = y_body + 2 + max(3, body_h // 4)
        cnt = max(2, cw // 14)
        span = cw - 8
        ww = max(4, (span - 2 * (cnt - 1)) // cnt)
        wx = x + 4
        for _ in range(cnt):
            if wx + ww > x + cw - 4:
                break
            rect(im, wx, y_body + 2, wx + ww - 1, wy1, C["win"])
            ln(im, wx, wx + ww - 1, wy1, C["win_d"])
            wx += ww + 2
        x += cw

    outline(im)
    return im


def front(w=80):
    h = max(28, round(w * 0.80))
    fin = max(8, round(h * 0.45))
    im = Image.new("RGBA", (w, h + fin + 6), (0, 0, 0, 0))
    y0 = fin + 3
    # 翼（顶部，两侧高中间低）
    for i in range(w - 4):
        t = abs(i - (w - 5) / 2) / ((w - 5) / 2)
        top = y0 - int((0.35 + 0.65 * t) * fin)
        for y in range(top, y0):
            put(im, 2 + i, y, C["fin"] if i % 2 else C["fin_l"])
    rect(im, 3, y0, w - 4, y0 + h - 1, C["hull"])
    for yy in range(y0 + 2, y0 + h, 3):
        ln(im, 4, w - 5, yy, C["hull_l"])
    for y in range(y0, y0 + h - 6):
        put(im, 3, y, C["gold"]); put(im, w - 4, y, C["gold"])
    crystal(im, w // 2, y0 + h // 2 - 4, max(3, h // 8))
    crystal(im, w // 2 - 8, y0 + h // 2, max(2, h // 11))
    crystal(im, w // 2 + 8, y0 + h // 2, max(2, h // 11))
    rect(im, 2, y0 + h - 6, w - 3, y0 + h - 1, C["plow"])
    ln(im, 2, w - 3, y0 + h - 6, C["plow_l"])
    ln(im, 2, w - 3, y0 + h - 1, C["black"])
    put(im, 6, y0 + 3, C["lamp"]); put(im, w - 7, y0 + 3, C["lamp"])
    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=160)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--view", choices=["side", "front"], default="side")
    ap.add_argument("--scale", type=int, default=5)
    ap.add_argument("-o", "--output", default="train_v4.png")
    a = ap.parse_args()
    im = side(a.w, a.cars) if a.view == "side" else front(a.w)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width + 20, out.height + 20), (22, 28, 42, 255))
    bg.alpha_composite(out, (10, 10)); bg.save(a.output)
    print("已写出 %s" % a.output, file=sys.stderr)


if __name__ == "__main__":
    main()
