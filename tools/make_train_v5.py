#!/usr/bin/env python3
"""
make_train_v5.py — 至冬列车 sprite v5（小猪佩奇式扁平简笔风）

风格要点（对照佩奇）：
  · 粗黑轮廓 + 纯色填充，零渐变零纹理
  · 几何化：矩形、三角形、圆
  · 高饱和、平涂
  · 车头 = 明显的 V 字形（前脸斜下去再斜上来）

纯侧面视角。

用法：
    python3 make_train_v5.py                      # 默认
    python3 make_train_v5.py --w 128 --cars 2
    python3 make_train_v5.py --scale 6 --outline 2
"""
import argparse, sys
from PIL import Image

# 佩奇风配色：高饱和平涂
C = {
    "line": (25, 23, 30),
    "body": (59, 55, 76),
    "body_d": (38, 35, 51),
    "roof": (77, 71, 96),
    "win": (192, 197, 219),
    "plow": (86, 57, 50),
    "crystal": (75, 147, 198),
    "lamp": (234, 208, 129),
    "wheel": (26, 25, 30),
    "chim": (79, 78, 86)
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


def circle(im, cx, cy, r, c):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + r * 0.5:
                put(im, cx + dx, cy + dy, c)


def thick_outline(im, n=2, line=None):
    """粗轮廓：不透明区域向外扩 n 像素"""
    for _ in range(n):
        src = im.copy()
        for y in range(im.height):
            for x in range(im.width):
                if src.getpixel((x, y))[3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                                   (1, 1), (1, -1), (-1, 1), (-1, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < im.width and 0 <= ny < im.height:
                            if src.getpixel((nx, ny))[3] > 0:
                                im.putpixel((x, y), (line or C["line"]) + (255,))
                                break


def build(w=128, cars=2, ol=2):
    """纯侧面 + V 形车头"""
    body_h = max(16, round(w * 0.19))          # 扁长车身
    pad = ol + 3
    h = body_h + pad * 2 + max(4, body_h // 4)
    im = Image.new("RGBA", (w + pad * 2, h), (0, 0, 0, 0))

    y0 = pad + max(3, body_h // 5)             # 车顶
    y1 = y0 + body_h - 1                       # 车底
    loco = max(40, round(w * 0.40))            # 车头长度

    # ── 车厢（右侧）──
    x = pad + loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n - 1 else (w + pad - x)
        if cw < 10:
            break
        rect(im, x, y0, x + cw - 1, y1, C["body"])
        # 圆角顶（用一像素削角模拟佩奇的圆润）
        ln(im, x + 1, x + cw - 2, y0, C["roof"])
        # 窗：等距方窗
        wy0, wy1 = y0 + 3, y1 - max(4, body_h // 3)
        cnt = max(2, cw // 15)
        span = cw - 8
        ww = max(5, (span - 3 * (cnt - 1)) // cnt)
        wx = x + 4
        for _ in range(cnt):
            if wx + ww > x + cw - 4:
                break
            rect(im, wx, wy0, wx + ww - 1, wy1, C["win"])
            wx += ww + 3
        x += cw

    # ── 车头（左侧，尖鼻楔形 = V 字侧视）──
    lx0 = pad
    nose_x = lx0 + max(2, loco // 8)           # 鼻尖（最左）
    top_x  = lx0 + max(14, int(loco * 0.55))   # 上斜边终点（回到车顶）
    bot_x  = lx0 + max(16, int(loco * 0.70))   # 下斜边终点（回到车底）
    nose_y = (y0 + y1) // 2 + max(1, body_h // 8)

    # 整车头先铺底色
    rect(im, lx0, y0, lx0 + loco - 1, y1, C["body"])
    # 挖掉前缘外侧（形成尖角轮廓）
    for x in range(lx0, nose_x):
        for y in range(y0, y1 + 1):
            im.putpixel((x, y), (0, 0, 0, 0))
    # 上斜边：从鼻尖斜上到车顶
    for x in range(nose_x, top_x + 1):
        t = (x - nose_x) / max(1, top_x - nose_x)
        top = int(nose_y + (y0 - nose_y) * t)
        for y in range(y0, top):
            im.putpixel((x, y), (0, 0, 0, 0))
        put(im, x, top, C["line"])
        put(im, x, top + 1, C["line"])
    # 下斜边：从鼻尖斜下到车底
    for x in range(nose_x, bot_x + 1):
        t = (x - nose_x) / max(1, bot_x - nose_x)
        bot = int(nose_y + (y1 - nose_y) * t)
        for y in range(bot + 1, y1 + 1):
            put(im, x, y, C["plow"])
        put(im, x, bot, C["line"])
    # 鼻尖竖边（让尖角有厚度）
    for y in range(nose_y - 1, nose_y + 2):
        if y0 <= y <= y1:
            put(im, nose_x, y, C["body"])
    # 驾驶窗（上斜边之后）
    dwx0, dwx1 = top_x + 3, pad + loco - 3
    if dwx1 > dwx0:
        rect(im, dwx0, y0 + 3, dwx1, y0 + 3 + max(3, body_h // 4), C["win"])
    # 蓝晶体：上斜边旁
    ccx = nose_x + max(6, loco // 6)
    ccy = y0 + max(3, body_h // 3)
    r = max(2, body_h // 8)
    for dy in range(-r, r + 1):
        w2 = max(0, r - abs(dy))
        for dx in range(-w2, w2 + 1):
            put(im, ccx + dx, ccy + dy, C["crystal"])
    # 车灯：鼻尖上方
    put(im, top_x - 3, y0 + 2, C["lamp"]); put(im, top_x - 2, y0 + 2, C["lamp"])
    # 烟囱
    rect(im, pad + loco - 8, y0 - 2, pad + loco - 5, y0 - 1, C["chim"])
    # 车轮
    wy = y1 + 2
    circle(im, pad + loco - 8, wy, max(2, body_h // 8), C["wheel"])
    x = pad + loco
    for i in range(n):
        cw = rest // n
        circle(im, x + cw // 2, wy, max(2, body_h // 8), C["wheel"])
        x += cw

    thick_outline(im, ol)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=128)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--outline", type=int, default=2)
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("-o", "--output", default="train_v5.png")
    a = ap.parse_args()
    im = build(a.w, a.cars, a.outline)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width + 16, out.height + 16), (238, 244, 252, 255))
    bg.alpha_composite(out, (8, 8)); bg.save(a.output)
    print("已写出 %s" % a.output, file=sys.stderr)


if __name__ == "__main__":
    main()
