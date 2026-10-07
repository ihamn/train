#!/usr/bin/env python3
"""
make_train_v7.py — 至冬列车 sprite v7（纯侧面，整块船首）

对线稿的理解（4 张线稿 + 实机照片）：
  车头不是「斜切 + 排障器」两件东西，而是【一个整块的船首壳体】，
  它从车体前上方一直兜到最下方，前缘是一条连续弧。

纯侧面下的表现：
  · 上部车体向右上收（后掠）
  · 下部船首壳向前下方鼓出，比上部明显更前  ← 你要的"下面伸出去"
  · 底部前缘与车身下缘的交界形成一个 V 形折角  ← 你要的"V"
  · 前脸上有蓝晶体 + 白色大 V 装饰（侧面只能看到它的一点边缘）

配色沿用按参考量化的结果：V≈0.41 S≈0.26 H240-270°

用法：
    python3 make_train_v7.py --w 144 --cars 2 --scale 5
"""
import argparse, sys, math
from PIL import Image

C = {
    "line":     (25, 23, 30),
    "body_d":   (38, 35, 51),
    "body":     (59, 55, 76),
    "body_l":   (77, 71, 96),
    "roof":     (77, 71, 96),
    "roof_l":   (99, 92, 118),
    "win":      (192, 197, 219),
    "win_d":    (128, 133, 158),
    "bow":      (70, 62, 74),      # 船首壳（比车身略暖）
    "bow_l":    (96, 86, 100),
    "bow_d":    (44, 39, 50),
    "trim_w":   (206, 208, 222),   # 白色装饰（前脸的 V）
    "gold":     (150, 126, 76),
    "gold_d":   (104, 86, 50),
    "crystal":  (75, 147, 198),
    "crystal_l":(140, 200, 232),
    "lamp":     (234, 208, 129),
    "wheel":    (26, 25, 30),
    "chim":     (79, 78, 86),
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


def clear(im, x0, y0, x1, y1):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            if 0 <= x < im.width and 0 <= y < im.height:
                im.putpixel((x, y), (0, 0, 0, 0))


def outline(im):
    src = im.copy()
    for y in range(im.height):
        for x in range(im.width):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < im.width and 0 <= ny < im.height and src.getpixel((nx,ny))[3] > 0:
                        im.putpixel((x, y), C["line"] + (255,)); break


def build(w=144, cars=2):
    body_h = max(20, round(w * 0.195))
    pad = 4
    im = Image.new("RGBA", (w + pad*2, body_h + pad*2 + max(5, body_h//3)), (0,0,0,0))
    y0 = pad
    y1 = y0 + body_h - 1
    roof_h = max(2, body_h // 8)
    loco = max(46, round(w * 0.42))

    # ══ 车厢 ══
    x = pad + loco
    rest = w - loco
    n = max(1, cars)
    frame_h = max(4, body_h // 4)          # 车厢底架
    for i in range(n):
        cw = rest // n if i < n-1 else (w + pad - x)
        if cw < 10: break
        rect(im, x+1, y1-frame_h+1, x+cw-2, y1, C["bow_d"])
        rect(im, x, y0+roof_h, x+cw-1, y1-frame_h, C["body"])
        for yy in range(y0+roof_h+2, y1-frame_h, 3):
            ln(im, x+1, x+cw-2, yy, C["body_l"])
        rect(im, x, y0, x+cw-1, y0+roof_h-1, C["roof"])
        ln(im, x+1, x+cw-2, y0, C["roof_l"])
        ln(im, x+1, x+cw-2, y1-frame_h, C["body_d"])
        ln(im, x+1, x+cw-2, y0+roof_h, C["gold_d"])
        wy0 = y0+roof_h+2
        wy1 = min(y1-frame_h-2, wy0 + max(3, body_h//4))
        cnt = max(2, cw // 15); span = cw-8
        ww = max(5, (span - 3*(cnt-1)) // cnt)
        wx = x+4
        for _ in range(cnt):
            if wx+ww > x+cw-4: break
            rect(im, wx, wy0, wx+ww-1, wy1, C["win"])
            ln(im, wx, wx+ww-1, wy1, C["win_d"]); ln(im, wx, wx, wy0, C["win_d"])
            wx += ww+3
        x += cw

    # ══ 车头：整块船首 ══
    lx0, lx1 = pad, pad + loco - 1
    # 车身段（车头后半）
    rect(im, lx0, y0, lx1, y1, C["body"])
    rect(im, lx0, y0, lx1, y0+roof_h-1, C["roof"])
    ln(im, lx0+1, lx1-1, y0, C["roof_l"])

    # 船首壳：整块，从车体前上兜到最下
    #   前缘 x(y)：上端后退多、中部最前、底端略回 —— 连续弧
    nose_len = int(loco * 0.80)
    def bow_edge(y):
        t = (y - y0) / max(1, (y1 - y0))      # 0 顶 → 1 底
        # 上部陡降（后掠），下部前鼓
        back = nose_len * (1 - t) ** 1.15
        # 底部轻微回收，形成圆钝的船首而不是尖角
        recover = 0.0
        if t > 0.86:
            recover = nose_len * 0.16 * ((t - 0.86) / 0.14) ** 2
        return int(round(lx0 + back + recover))

    for y in range(y0, y1 + 1):
        e = bow_edge(y)
        # 船首壳底色（比车身暖）
        for xx in range(e, lx1 + 1):
            put(im, xx, y, C["bow"])
    # 壳上的弧线（体现壳体是圆的）
    for k in (3, 7, 12):
        for y in range(y0 + roof_h, y1 + 1):
            e = bow_edge(y)
            put(im, e + k, y, C["bow_l"] if k < 8 else C["bow_d"])
    # 前缘描边 + 内侧亮边（让弧面有体积）
    for y in range(y0, y1 + 1):
        e = bow_edge(y)
        put(im, e, y, C["line"])
        if y > y0 + roof_h:
            put(im, e + 1, y, C["bow_l"])
    # 挖掉前缘以外
    for y in range(y0, y1 + 1):
        e = bow_edge(y)
        clear(im, lx0, y, e - 1, y)

    # 白色大 V（前脸上的装饰，侧面看到它的一部分边缘）
    vy0 = y0 + int(body_h * 0.30)
    vy1 = y1 - int(body_h * 0.12)
    vx = bow_edge(vy1) + int(loco * 0.18)     # V 的顶点在内侧
    for k in range(0, vy1 - vy0):
        y = vy0 + k
        e = bow_edge(y)
        # 上臂（往左上）与下臂（往左下）—— 侧面只露靠外的一段
        t = k / max(1, vy1 - vy0)
        arm = int(e + (vx - e) * (1 - abs(2*t - 1)))
        put(im, arm, y, C["trim_w"])
        put(im, arm + 1, y, C["trim_w"])
    # 蓝晶体（V 的顶点附近）
    cxx = bow_edge(y0 + int(body_h*0.62)) + int(loco * 0.20)
    cyy = y0 + int(body_h * 0.62)
    r = max(2, body_h // 9)
    for dy in range(-r, r+1):
        w2 = max(0, r - abs(dy))
        for dx in range(-w2, w2+1):
            put(im, cxx+dx, cyy+dy,
                C["crystal_l"] if abs(dx)+abs(dy) <= max(1, r//2) else C["crystal"])
    # 金色镶边（沿前缘内侧）
    for y in range(y0 + roof_h, y1 + 1, 2):
        put(im, bow_edge(y) + 2, y, C["gold_d"])
    # 车灯
    put(im, bow_edge(y0+roof_h+2) + 4, y0+roof_h+1, C["lamp"])
    put(im, bow_edge(y0+roof_h+2) + 5, y0+roof_h+1, C["lamp"])
    # 驾驶窗
    dwx0 = bow_edge(y0+roof_h+2) + 8
    if dwx0 < lx1 - 3:
        wy1 = y0+roof_h+2 + max(3, body_h//4)
        rect(im, dwx0, y0+roof_h+2, lx1-3, wy1, C["win"])
        ln(im, dwx0, lx1-3, wy1, C["win_d"])
    # 烟囱
    rect(im, lx1-10, y0-2, lx1-7, y0-1, C["chim"])
    # 车轮
    wy = y1 + 2
    for wx in (lx0 + loco//2, lx1-4):
        for dy in range(-2,3):
            for dx in range(-2,3):
                if dx*dx+dy*dy <= 5: put(im, wx+dx, wy+dy, C["wheel"])

    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=144)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--scale", type=int, default=5)
    ap.add_argument("-o", "--output", default="train_v7.png")
    a = ap.parse_args()
    im = build(a.w, a.cars)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png","_1x.png"))
    out = im.resize((im.width*a.scale, im.height*a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width+16, out.height+16), (232,238,248,255))
    bg.alpha_composite(out, (8,8)); bg.save(a.output)
    print("已写出 %s" % a.output, file=sys.stderr)


if __name__ == "__main__":
    main()
