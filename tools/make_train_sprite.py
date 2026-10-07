#!/usr/bin/env python3
"""
make_train_sprite.py — 程序化生成「至冬列车」2.5D 等距像素 sprite

依据四张游戏截图 + 实体照提取的识别要素：
  · 深色车身（近黑/深蓝）
  · 亮暖色车窗（暗背景里唯一能跳出来的元素）
  · 车头斜面切角、前端微微上翘
  · 车顶平直，有通风器突起
  · 金色点缀灯
  · 深蓝底盘 + 亮色底缘线

用法：
    python3 make_train_sprite.py                     # 默认侧面 96 宽
    python3 make_train_sprite.py --w 64 --cars 2
    python3 make_train_sprite.py --iso               # 3/4 等距朝向（带正面透视）
    python3 make_train_sprite.py --scale 6 -o out.png
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow")


# ── 调色板（从截图提取的主色）────────────────────────
C = {
    "outline": (10, 14, 24),        # 描边
    "hull_d":  (26, 34, 54),        # 车身上暗部
    "hull":    (40, 50, 74),        # 车身主色
    "hull_l":  (62, 76, 108),       # 车身上亮部
    "roof":    (74, 88, 120),       # 车顶（明显亮于车身）
    "roof_l":  (112, 128, 164),     # 车顶高光
    "win":     (252, 224, 168),     # 车窗（亮暖）
    "win_d":   (196, 158, 104),     # 车窗暗部
    "gold":    (222, 178, 92),      # 金色点缀
    "blue":    (96, 150, 214),      # 蓝色装饰
    "skirt":   (18, 24, 38),        # 底盘
    "rail":    (120, 134, 160),     # 底缘亮线
}


def px(im, x, y, col):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), col + (255,))


def rect(im, x0, y0, x1, y1, col):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            px(im, x, y, col)


def hline(im, x0, x1, y, col):
    rect(im, x0, y, x1, y, col)


def draw_car(im, x0, y0, w, h, window_count, body="hull"):
    """画一节车厢（长高比约 3:1）：底盘 + 车身 + 车顶 + 小方窗"""
    top = y0
    roof_h = max(2, h // 8)            # 车顶厚度
    skirt_h = max(2, h // 6)           # 底盘厚度
    body_y0 = top + roof_h
    body_y1 = y0 + h - skirt_h - 1
    # 底盘
    rect(im, x0 + 1, y0 + h - skirt_h, x0 + w - 2, y0 + h, C["skirt"])
    # 车身
    rect(im, x0, body_y0, x0 + w - 1, body_y1, C[body])
    # 车身上缘高光 + 下缘暗线
    hline(im, x0 + 1, x0 + w - 2, body_y0, C["hull_l"])
    hline(im, x0 + 1, x0 + w - 2, body_y1, C["outline"])
    # 车顶
    rect(im, x0, top, x0 + w - 1, body_y0 - 1, C["roof"])
    hline(im, x0 + 1, x0 + w - 2, top, C["roof_l"])
    # 车顶通风器（每节 2 个）
    for i in range(2):
        vx = x0 + 4 + i * max(5, (w - 10) // 2)
        if vx + 2 < x0 + w - 3 and top >= 1:
            rect(im, vx, top - 1, vx + 2, top - 1, C["roof_l"])
    # 底盘亮线
    px(im, x0 + 2, y0 + h, C["rail"])
    hline(im, x0 + 3, x0 + w - 4, y0 + h - 1, C["rail"])
    # 车窗：横向为主的小矩形，等距排布
    if window_count > 0:
        wy0 = body_y0 + 2
        wy1 = min(body_y1 - 2, wy0 + max(2, (body_y1 - body_y0) // 3))
        margin = 3
        avail = w - margin * 2
        ww = max(2, avail // (window_count * 2))     # 窗宽
        gap = max(1, (avail - ww * window_count) // max(1, window_count))
        wx = x0 + margin
        for i in range(window_count):
            if wx + ww - 1 > x0 + w - margin:
                break
            rect(im, wx, wy0, wx + ww - 1, wy1, C["win"])
            hline(im, wx, wx + ww - 1, wy1, C["win_d"])
            wx += ww + gap
    # 车厢连接缝
    hline(im, x0, x0, body_y0 + 1, C["outline"])
    hline(im, x0 + w - 1, x0 + w - 1, body_y0 + 1, C["outline"])


def draw_locomotive(im, x0, y0, w, h):
    """车头：前部斜面切角 + 上翘鼻 + 蓝色菱形 + 金灯 + 驾驶室窗"""
    top = y0
    roof_h = max(2, h // 8)
    skirt_h = max(2, h // 6)
    body_y0 = top + roof_h
    body_y1 = y0 + h - skirt_h - 1
    # 底盘
    rect(im, x0 + 2, y0 + h - skirt_h, x0 + w - 1, y0 + h, C["skirt"])
    # 车身主体
    rect(im, x0, body_y0, x0 + w - 1, body_y1, C["hull"])
    hline(im, x0 + 1, x0 + w - 2, body_y0, C["hull_l"])
    hline(im, x0 + 1, x0 + w - 2, body_y1, C["outline"])
    # 车顶
    rect(im, x0 + 3, top, x0 + w - 1, body_y0 - 1, C["roof"])
    hline(im, x0 + 4, x0 + w - 2, top, C["roof_l"])
    # 前部斜面：从上往下向左切（形成引擎盖斜切）
    nose = max(5, w // 4)
    for i in range(nose):
        yy = body_y0 + 1 + i
        if yy <= body_y1:
            px(im, x0 + i, yy, C["outline"])
    # 楔形鼻：前缘从车顶高度斜切到底盘
    for i in range(nose):
        yy = body_y0 + i
        if yy <= body_y1:
            px(im, x0 + i, yy, C["hull"])
    # 车顶向前延伸出鼻尖，再向下切
    rect(im, x0 + 1, body_y0 - 1, x0 + 2, body_y0 - 1, C["roof_l"])
    px(im, x0, body_y0, C["roof"])
    px(im, x0, body_y0 + 1, C["hull_l"])
    # 前缘高光（让斜面有体积感）
    for i in range(2, nose):
        px(im, x0 + i, body_y0 + i - 1, C["hull_l"])
    # 蓝色菱形装饰（标识点，放在车头侧面靠前）
    cx, cy = x0 + nose + 4, body_y0 + (body_y1 - body_y0) // 2 + 1
    diamond = [(0, -2), (-1, -1), (0, -1), (1, -1),
               (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
               (-1, 1), (0, 1), (1, 1), (0, 2)]
    for dx, dy in diamond:
        px(im, cx + dx, cy + dy, C["blue"])
    # 金色灯（车头前缘上下各一）
    px(im, x0 + nose - 1, body_y0 + 1, C["gold"])
    px(im, x0 + nose - 1, body_y1 - 1, C["gold"])
    # 驾驶室窗（车头后段）
    wx0 = x0 + nose + 8
    if wx0 < x0 + w - 3:
        wy0 = body_y0 + 2
        wy1 = min(body_y1 - 3, wy0 + max(1, (body_y1 - body_y0) // 4))
        if wx0 < x0 + w - 4:
            rect(im, wx0, wy0, x0 + w - 4, wy1, C["win"])
            hline(im, wx0, x0 + w - 4, wy1, C["win_d"])


def build(w=96, cars=2, iso=False):
    # 高度按比例
    h = max(14, round(w * 0.22))
    im = Image.new("RGBA", (w, h + 6), (0, 0, 0, 0))
    y0 = 2

    # 车头占前 30%，其余分给车厢
    loco_w = max(26, round(w * 0.36))
    rest = w - loco_w
    car_w = rest // cars if cars else 0

    draw_locomotive(im, 0, y0, loco_w - 1, h)
    x = loco_w
    for i in range(cars):
        cw = car_w if i < cars - 1 else (w - x)
        # 车厢之间留 1px 缝（连接器）
        draw_car(im, x, y0, cw - 1, h, window_count=max(3, cw // 7))
        x += cw
        if i < cars - 1:
            px(im, x - 1, y0 + h - 2, C["outline"])

    # 外描边（让剪影在暗背景里读得出来）
    src = im.copy()
    for y in range(im.height):
        for x_ in range(im.width):
            if src.getpixel((x_, y))[3] == 0:
                near = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x_ + dx, y + dy
                    if 0 <= nx < im.width and 0 <= ny < im.height:
                        if src.getpixel((nx, ny))[3] > 0:
                            near = True
                            break
                if near:
                    im.putpixel((x_, y), C["outline"] + (255,))

    if iso:
        # 3/4 等距：横向压到 0.92，顶部加一条"侧面透视"高光
        nw = max(1, int(im.width * 0.92))
        im = im.resize((nw, im.height), Image.NEAREST)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=96)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--iso", action="store_true")
    ap.add_argument("--scale", type=int, default=8)
    ap.add_argument("-o", "--output", default="train_sprite.png")
    a = ap.parse_args()

    im = build(a.w, a.cars, a.iso)
    print("原始尺寸 %d × %d" % im.size, file=sys.stderr)
    out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
    # 深色底衬，方便看清
    bg = Image.new("RGBA", (out.width + 16, out.height + 16), (24, 28, 40, 255))
    bg.alpha_composite(out, (8, 8))
    bg.save(a.output)
    print("已写出 %s（放大 %dx）" % (a.output, a.scale), file=sys.stderr)
    im.save(a.output.replace(".png", "_1x.png"))
    print("1x 版本 %s" % a.output.replace(".png", "_1x.png"), file=sys.stderr)


if __name__ == "__main__":
    main()
