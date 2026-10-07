#!/usr/bin/env python3
"""
make_train_v6.py — 至冬列车 sprite v6

两点修正：
  1) 车头 V 是【凹】的 —— 侧视下前缘上边线下斜、下边线上斜，
     中间形成内凹的艏弧（不是向前凸的尖角）
  2) 保留 v1 那种【质感】—— 明暗层次 + 车顶高光 + 车身板条 + 金属边

配色沿用按参考图量化的成果：
  V≈0.41  S≈0.26  主色相 240-270°（暗紫蓝，低饱和）

用法：
    python3 make_train_v6.py --w 144 --cars 2 --scale 5
"""
import argparse, sys
from PIL import Image

C = {
    "line":    (25, 23, 30),
    "body_d":  (38, 35, 51),
    "body":    (59, 55, 76),
    "body_l":  (77, 71, 96),
    "roof":    (77, 71, 96),
    "roof_l":  (99, 92, 118),
    "win":     (192, 197, 219),
    "win_d":   (128, 133, 158),
    "plow":    (86, 57, 50),
    "plow_l":  (120, 78, 66),
    "plow_d":  (58, 38, 34),
    "gold":    (150, 126, 76),
    "gold_d":  (104, 86, 50),
    "crystal": (75, 147, 198),
    "crystal_l":(140, 200, 232),
    "lamp":    (234, 208, 129),
    "wheel":   (26, 25, 30),
    "chim":    (79, 78, 86),
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


def outline(im, col=None):
    src = im.copy()
    for y in range(im.height):
        for x in range(im.width):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < im.width and 0 <= ny < im.height and src.getpixel((nx, ny))[3] > 0:
                        im.putpixel((x, y), (col or C["line"]) + (255,))
                        break


def build(w=144, cars=2):
    body_h = max(20, round(w * 0.20))
    pad = 4
    im = Image.new("RGBA", (w + pad * 2, body_h + pad * 2 + max(4, body_h // 4)), (0, 0, 0, 0))
    y0 = pad
    y1 = y0 + body_h - 1
    roof_h = max(2, body_h // 8)
    plow_h = max(4, body_h // 4)
    loco = max(44, round(w * 0.42))

    # ══ 车厢 ══
    x = pad + loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n - 1 else (w + pad - x)
        if cw < 10:
            break
        # 底盘
        rect(im, x + 1, y1 - plow_h + 1, x + cw - 2, y1, C["plow"])
        ln(im, x + 1, x + cw - 2, y1 - plow_h + 1, C["plow_l"])
        ln(im, x + 1, x + cw - 2, y1, C["plow_d"])
        # 车身
        rect(im, x, y0 + roof_h, x + cw - 1, y1 - plow_h, C["body"])
        # 板条纹理（横向，明暗交替 → 质感）
        for yy in range(y0 + roof_h + 2, y1 - plow_h, 3):
            ln(im, x + 1, x + cw - 2, yy, C["body_l"])
        # 车顶
        rect(im, x, y0, x + cw - 1, y0 + roof_h - 1, C["roof"])
        ln(im, x + 1, x + cw - 2, y0, C["roof_l"])
        ln(im, x + 1, x + cw - 2, y1 - plow_h, C["body_d"])
        # 金色腰线
        ln(im, x + 1, x + cw - 2, y0 + roof_h, C["gold_d"])
        # 侧窗（白边长窗 + 内暗）
        wy0 = y0 + roof_h + 2
        wy1 = min(y1 - plow_h - 2, wy0 + max(3, body_h // 4))
        cnt = max(2, cw // 15)
        span = cw - 8
        ww = max(5, (span - 3 * (cnt - 1)) // cnt)
        wx = x + 4
        for _ in range(cnt):
            if wx + ww > x + cw - 4:
                break
            rect(im, wx, wy0, wx + ww - 1, wy1, C["win"])
            ln(im, wx, wx + ww - 1, wy1, C["win_d"])
            ln(im, wx, wx, wy0, C["win_d"])
            wx += ww + 3
        x += cw

    # ══ 车头 ══
    lx0, lx1 = pad, pad + loco - 1
    # 先铺整车头
    rect(im, lx0, y0, lx1, y1, C["body"])
    rect(im, lx0, y0, lx1, y0 + roof_h - 1, C["roof"])
    ln(im, lx0 + 1, lx1 - 1, y0, C["roof_l"])

    # ★ 艏部轮廓：确定性公式，直接控制三点
    #   t=0(顶) x=top_back + dip ；t=0.5 x=dip ；t=1(底) x=0（最前）
    #   dip < 0 ⇒ 中段内凹（凹口）；底端 = 0 ⇒ 下缘伸到最前
    top_back = max(8, int(loco * 0.42))     # 上缘比下缘后退多少（越大越斜）
    dip      = -max(2, int(loco * 0.05))    # 中段内凹深度（负=凹）

    def edge_x(y):
        t = (y - y0) / max(1, (y1 - y0))
        base = top_back * (1.0 - t) ** 1.3          # 上宽下窄 → 下缘前伸
        bulge = 4.0 * dip * t * (1.0 - t)           # 中段抛物线扰动
        return int(round(lx0 + max(0.0, base + bulge)))

    for y in range(y0, y1 + 1):
        e = edge_x(y)
        clear(im, lx0, y, e - 1, y)
        put(im, e, y, C["line"])
    # 凹口内侧阴影
    for y in range(y0 + roof_h, y1 - plow_h + 1):
        e = edge_x(y)
        for k in range(1, 3):
            put(im, e + k, y, C["body_d"])
    # 上段高光
    for y in range(y0 + roof_h, y0 + max(2, (y1 - y0) // 3)):
        put(im, edge_x(y) + 1, y, C["body_l"])
    # 金色镶边（沿艏弧内侧）
    for y in range(y0 + roof_h, y1 - plow_h + 1, 2):
        put(im, edge_x(y) + 3, y, C["gold_d"])
    # 蓝晶体（嵌在艏弧中段）
    ymid = y0 + int((y1 - y0) * 0.58)
    cx = edge_x(ymid) + 2
    cy = ymid
    r = max(2, body_h // 9)
    for dy in range(-r, r + 1):
        w2 = max(0, r - abs(dy))
        for dx in range(-w2, w2 + 1):
            put(im, cx + dx, cy + dy,
                C["crystal_l"] if abs(dx) + abs(dy) <= max(1, r // 2) else C["crystal"])
    put(im, cx + r + 2, cy - r, C["crystal"])
    put(im, cx + r + 3, cy + r, C["crystal"])
    # 车灯
    lx_lamp = edge_x(y0 + roof_h + 1) + 3
    put(im, lx_lamp, y0 + roof_h + 1, C["lamp"])
    put(im, lx_lamp + 1, y0 + roof_h + 1, C["lamp"])
    # 排障器：从底缘开始，向前伸出并略上翘（下缘斜率缓）
    for y in range(y1 - plow_h + 1, y1 + 1):
        k = (y - (y1 - plow_h + 1)) / max(1, plow_h - 1)   # 0=排障器顶 1=底
        e = int(round(edge_x(y) - k * max(2, loco * 0.10)))  # 越往下越往前
        e = max(0, e)
        rect(im, e, y, lx1 - 4, y, C["plow"])
    ln(im, 0, lx1 - 4, y1 - plow_h + 1, C["plow_l"])
    ln(im, 0, lx1 - 4, y1, C["plow_d"])

    # 驾驶窗
    dwx0 = edge_x(y0 + roof_h + 2) + 6
    if dwx0 < lx1 - 3:
        rect(im, dwx0, y0 + roof_h + 2, lx1 - 3, y0 + roof_h + 2 + max(3, body_h // 4), C["win"])
        ln(im, dwx0, lx1 - 3, y0 + roof_h + 2 + max(3, body_h // 4), C["win_d"])
    # 烟囱
    rect(im, lx1 - 10, y0 - 2, lx1 - 7, y0 - 1, C["chim"])
    # 车轮
    wy = y1 + 2
    for wx in (lx0 + loco // 2, lx1 - 4):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 5:
                    put(im, wx + dx, wy + dy, C["wheel"])

    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=144)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--scale", type=int, default=5)
    ap.add_argument("-o", "--output", default="train_v6.png")
    a = ap.parse_args()
    im = build(a.w, a.cars)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    bg = Image.new("RGBA", (out.width + 16, out.height + 16), (232, 238, 248, 255))
    bg.alpha_composite(out, (8, 8)); bg.save(a.output)
    print("已写出 %s" % a.output, file=sys.stderr)


if __name__ == "__main__":
    main()
