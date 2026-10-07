#!/usr/bin/env python3
"""
make_train_v3.py — 至冬列车 sprite v3（按实机照片重画）

从实机特写提取的设计语言：
  · 顶部巨大的锯齿状头冠（向右上扬起）        ← 最醒目的剪影特征
  · 前脸大型蓝色晶体徽记（星形/雪花排列）      ← 识别核心
  · 深褐灰车身 + 横向板条纹理
  · 前脸金色/铜色弧形镶边
  · 下部红褐色排障器（雪铲），底缘黑色
  · 暖黄车灯（两侧）
  · 侧面一排扁长窗

用法：
    python3 make_train_v3.py                       # 侧面（默认）
    python3 make_train_v3.py --w 144 --cars 2
    python3 make_train_v3.py --view front --w 72   # 正脸
    python3 make_train_v3.py --scale 6
"""
import argparse, sys
from PIL import Image

C = {
    "outline":  (14, 12, 16),
    "hull":     (58, 54, 62),      # 车身主（深褐灰）
    "hull_l":   (86, 82, 92),      # 板条高光
    "hull_d":   (36, 34, 40),      # 车身暗
    "wood":     (78, 60, 50),      # 木质暖褐
    "plow":     (126, 72, 60),     # 排障器红褐
    "plow_l":   (162, 98, 82),
    "plow_d":   (84, 46, 40),
    "gold":     (186, 152, 84),    # 金色镶边
    "gold_d":   (128, 102, 54),
    "crystal":  (86, 176, 232),    # 蓝晶体
    "crystal_l":(160, 224, 255),
    "crystal_d":(40, 104, 168),
    "lamp":     (255, 226, 150),   # 暖黄灯
    "black":    (22, 22, 26),
    "win":      (178, 196, 216),   # 窗
    "win_d":    (110, 128, 150),
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


def crystal(im, cx, cy, r, long_axis='v'):
    """蓝色晶体徽记：菱形主瓣 + 四向短瓣"""
    for dy in range(-r, r + 1):
        w = max(0, r - abs(dy))
        for dx in range(-w, w + 1):
            col = C["crystal_l"] if abs(dx) + abs(dy) <= r * 0.4 else C["crystal"]
            put(im, cx + dx, cy + dy, col)
    put(im, cx, cy, C["crystal_l"])
    # 四向尖瓣
    for k in range(1, r + 2):
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


def side(w=144, cars=2, crest=True):
    h = max(20, round(w * 0.24))           # 车身高（含排障器）
    crest_h = max(6, round(h * 0.55)) if crest else 0
    im = Image.new("RGBA", (w, h + crest_h + 8), (0, 0, 0, 0))
    y_top = crest_h + 3                    # 车身顶
    body_h = h
    loco = max(46, round(w * 0.42))

    def draw_car(x, cw):
        """车厢：车身 + 板条 + 窗 + 底缘"""
        y0, y1 = y_top, y_top + body_h - 1
        plow = max(3, body_h // 5)
        rect(im, x, y0, x + cw - 1, y1 - plow, C["hull"])
        # 横向板条
        for yy in range(y0 + 2, y1 - plow, 3):
            ln(im, x + 1, x + cw - 2, yy, C["hull_l"])
        # 顶缘高光 / 底缘
        ln(im, x + 1, x + cw - 2, y0, C["hull_l"])
        # 排障器（红褐）
        rect(im, x + 1, y1 - plow + 1, x + cw - 2, y1, C["plow"])
        ln(im, x + 1, x + cw - 2, y1, C["black"])
        # 侧窗：一排扁长窗
        wy0 = y0 + 2
        wy1 = y0 + 2 + max(3, body_h // 4)
        cnt = max(2, cw // 16)
        span = cw - 8
        ww = max(4, (span - 2 * (cnt - 1)) // cnt)
        wx = x + 4
        for _ in range(cnt):
            if wx + ww > x + cw - 4:
                break
            rect(im, wx, wy0, wx + ww - 1, wy1, C["win"])
            ln(im, wx, wx + ww - 1, wy1, C["win_d"])
            wx += ww + 2

    # 车厢
    x = loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n - 1 else (w - x)
        if cw < 10:
            break
        draw_car(x, cw)
        x += cw

    # ── 车头 ──
    y0, y1 = y_top, y_top + body_h - 1
    plow = max(4, body_h // 5)
    rect(im, 2, y0, loco - 1, y1 - plow, C["hull"])
    for yy in range(y0 + 2, y1 - plow, 3):
        ln(im, 3, loco - 2, yy, C["hull_l"])
    ln(im, 3, loco - 2, y0, C["hull_l"])

    # 头冠：锯齿状，向右上扬起
    if crest:
        for i in range(loco - 6):
            t = i / max(1, loco - 7)
            top = y_top - int((1 - t) * crest_h * 0.95)
            col = C["hull"] if i < loco * 0.5 else C["hull_d"]
            for yy in range(top, y_top):
                put(im, 3 + i, yy, col)
        # 冠缘金线
        for i in range(0, loco - 6, 2):
            t = i / max(1, loco - 7)
            put(im, 3 + i, y_top - int((1 - t) * crest_h * 0.95) - 1, C["gold"])

    # 前脸：金色弧形镶边
    face_x = 2
    for yy in range(y0, y1 - plow):
        put(im, face_x, yy, C["gold"])
        put(im, face_x + 1, yy, C["gold_d"])
    # 前脸蓝晶体徽记（大）
    crystal(im, face_x + max(6, loco // 4), (y0 + y1 - plow) // 2 + 1, max(3, body_h // 7))
    # 车灯（前缘上下）
    put(im, face_x + 2, y0 + 2, C["lamp"]); put(im, face_x + 3, y0 + 2, C["lamp"])
    put(im, face_x + 2, y1 - plow - 2, C["lamp"])
    # 排障器（雪铲，向左前伸出）
    rect(im, 0, y1 - plow + 1, loco - 2, y1, C["plow"])
    ln(im, 0, loco - 2, y1 - plow + 1, C["plow_l"])
    ln(im, 0, loco - 2, y1, C["black"])
    # 铲面斜纹
    for i in range(0, loco - 3, 4):
        put(im, i, y1 - plow + 2, C["plow_d"])

    outline(im)
    return im


def front(w=72):
    h = max(24, round(w * 0.85))
    crest = max(6, round(h * 0.3))
    im = Image.new("RGBA", (w, h + crest + 6), (0, 0, 0, 0))
    y0 = crest + 3
    # 头冠（顶部锯齿）
    for i in range(w - 4):
        t = abs(i - (w - 5) / 2) / ((w - 5) / 2)
        top = y0 - int((1 - t) * crest)
        for yy in range(top, y0):
            put(im, 2 + i, yy, C["hull_d"])
    # 车身
    rect(im, 2, y0, w - 3, y0 + h, C["hull"])
    for yy in range(y0 + 2, y0 + h, 3):
        ln(im, 3, w - 4, yy, C["hull_l"])
    # 金色镶边（两侧弧）
    for yy in range(y0, y0 + h - 4):
        put(im, 2, yy, C["gold"]); put(im, w - 3, yy, C["gold"])
    # 大晶体徽记
    crystal(im, w // 2, y0 + h // 2 - 2, max(4, h // 6))
    # 排障器
    rect(im, 1, y0 + h - 4, w - 2, y0 + h, C["plow"])
    ln(im, 1, w - 2, y0 + h - 4, C["plow_l"])
    ln(im, 1, w - 2, y0 + h, C["black"])
    # 车灯
    put(im, 5, y0 + 3, C["lamp"]); put(im, w - 6, y0 + 3, C["lamp"])
    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=144)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--view", choices=["side", "front"], default="side")
    ap.add_argument("--no-crest", action="store_true")
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("-o", "--output", default="train_v3.png")
    a = ap.parse_args()
    im = side(a.w, a.cars, crest=not a.no_crest) if a.view == "side" else front(a.w)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width + 20, out.height + 20), (24, 30, 44, 255))
    bg.alpha_composite(out, (10, 10)); bg.save(a.output)
    print("已写出 %s" % a.output, file=sys.stderr)


if __name__ == "__main__":
    main()
