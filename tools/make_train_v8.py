#!/usr/bin/env python3
"""
make_train_v8.py — 至冬列车 sprite v8

依据实机截图（提亮后）看清的车头分层结构：
  ① 前脸上部：一排【梯形/斜边】窗，整体向前倾斜
  ② 顶上：向前上方悬挑的【檐/冠】
  ③ 中下部：弧面壳，蓝晶体嵌在里面
  ④ 最下：向前下方收尾的圆润壳体
  ⇒ 前脸是上下分层、上檐外挑的，不是一块平壳

纯侧面视角。配色沿用参考量化结果：V≈0.41 S≈0.26 H240-270°

用法：
    python3 make_train_v8.py --w 160 --cars 2 --scale 5
"""
import argparse, sys
from PIL import Image

C = {
    "line":     (22, 20, 27),
    "body_d":   (35, 32, 47),
    "body":     (54, 50, 70),
    "body_l":   (72, 66, 90),
    "roof":     (72, 66, 90),
    "roof_l":   (94, 87, 112),
    "win":      (198, 203, 223),
    "win_d":    (132, 137, 162),
    "win_warm": (226, 214, 186),   # 暖色窗（实机窗是暖白的）
    "shell":    (64, 57, 72),
    "shell_l":  (90, 80, 98),
    "shell_d":  (40, 35, 46),
    "gold":     (150, 126, 76),
    "gold_d":   (104, 86, 50),
    "crystal":  (75, 147, 198),
    "crystal_l":(148, 205, 235),
    "lamp":     (234, 208, 129),
    "wheel":    (24, 23, 28),
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


def build(w=160, cars=2):
    body_h = max(22, round(w * 0.185))
    pad = 5
    im = Image.new("RGBA", (w + pad*2, body_h + pad*2 + max(6, body_h//3)), (0,0,0,0))
    y0 = pad
    y1 = y0 + body_h - 1
    roof_h = max(3, body_h // 7)
    loco = max(52, round(w * 0.44))
    frame_h = max(4, body_h // 5)

    # ══ 车厢 ══
    x = pad + loco
    rest = w - loco
    n = max(1, cars)
    for i in range(n):
        cw = rest // n if i < n-1 else (w + pad - x)
        if cw < 12: break
        rect(im, x+1, y1-frame_h+1, x+cw-2, y1, C["body_d"])
        rect(im, x, y0+roof_h, x+cw-1, y1-frame_h, C["body"])
        for yy in range(y0+roof_h+2, y1-frame_h, 3):
            ln(im, x+1, x+cw-2, yy, C["body_l"])
        # 筒形车顶（中间高、两边低）
        for k in range(roof_h):
            inset = k // 2
            ln(im, x+inset, x+cw-1-inset, y0+roof_h-1-k, C["roof"] if k < roof_h-1 else C["roof_l"])
        ln(im, x+1, x+cw-2, y1-frame_h, C["body_d"])
        ln(im, x+1, x+cw-2, y0+roof_h, C["gold_d"])
        wy0 = y0+roof_h+2
        wy1 = min(y1-frame_h-2, wy0 + max(4, body_h//3))
        cnt = max(2, cw // 16); span = cw-8
        ww = max(6, (span - 3*(cnt-1)) // cnt)
        wx = x+4
        for _ in range(cnt):
            if wx+ww > x+cw-4: break
            rect(im, wx, wy0, wx+ww-1, wy1, C["win_warm"])
            ln(im, wx, wx+ww-1, wy1, C["win_d"]); ln(im, wx, wx, wy0, C["win_d"])
            wx += ww+3
        x += cw

    # ══ 车头 ══
    lx0, lx1 = pad, pad + loco - 1
    rect(im, lx0, y0, lx1, y1, C["body"])
    rect(im, lx0, y0, lx1, y0+roof_h-1, C["roof"])

    nose = int(loco * 0.86)
    def shell_edge(y):
        """壳体前缘 x(y)：t=0 顶 → 1 底"""
        t = (y - y0) / max(1, (y1 - y0))
        back = nose * (1 - t) ** 1.20            # 上部后掠
        recover = 0.0
        if t > 0.88:                              # 底部回收（圆钝收尾）
            recover = nose * 0.20 * ((t - 0.88) / 0.12) ** 2
        return int(round(lx0 + back + recover))

    # ① 前脸上部的梯形窗（前倾）
    band_y0 = y0 + roof_h + 1
    band_y1 = band_y0 + max(4, body_h // 3)
    # 檐（悬挑出去的冠）
    eave_x0 = shell_edge(band_y0) - int(loco * 0.10)
    eave_x1 = lx1 - 4
    rect(im, eave_x0, y0, eave_x1, y0 + roof_h - 1, C["roof"])
    ln(im, eave_x0, eave_x1, y0, C["roof_l"])
    # 檐下阴影
    ln(im, eave_x0, eave_x1, y0 + roof_h, C["body_d"])
    # 梯形窗（上宽下窄 → 斜边体现前倾）
    nwin = 4
    bw = (eave_x1 - eave_x0 - 6) // nwin
    for k in range(nwin):
        x0 = eave_x0 + 3 + k * bw
        x1 = x0 + bw - 3
        if x1 <= x0: continue
        for y in range(band_y0, band_y1 + 1):
            t = (y - band_y0) / max(1, band_y1 - band_y0)
            inset = int(t * 1.5 + 0.5)          # 越往下越窄
            a, bq = x0 + inset, x1 - inset
            if bq > a:
                rect(im, a, y, bq, y, C["win"])
        ln(im, x0, x1, band_y1, C["win_d"])

    # ③ 中下部弧面壳
    for y in range(band_y1 + 1, y1 + 1):
        e = shell_edge(y)
        clear(im, lx0, y, e - 1, y)
        for xx in range(e, lx1 + 1):
            put(im, xx, y, C["shell"])
        put(im, e, y, C["line"])
        put(im, e + 1, y, C["shell_l"])
    # 壳上的弧线（体现圆壳）
    for k in (4, 8, 13):
        for y in range(band_y1 + 1, y1 + 1):
            put(im, shell_edge(y) + k, y, C["shell_l"] if k < 9 else C["shell_d"])
    # 金色镶边
    for y in range(band_y1 + 1, y1 + 1, 2):
        put(im, shell_edge(y) + 2, y, C["gold_d"])
    # ④ 蓝晶体（壳体中央）
    cyy = band_y1 + max(2, (y1 - band_y1) // 2)
    cxx = shell_edge(cyy) + int(loco * 0.14)
    r = max(2, body_h // 10)
    for dy in range(-r, r+1):
        w2 = max(0, r - abs(dy))
        for dx in range(-w2, w2+1):
            put(im, cxx+dx, cyy+dy,
                C["crystal_l"] if abs(dx)+abs(dy) <= max(1, r//2) else C["crystal"])
    for k in range(1, r+2):     # 晶体尖瓣
        put(im, cxx, cyy-r-k, C["crystal"]); put(im, cxx, cyy+r+k, C["crystal"])
    # 车灯（前缘）
    put(im, shell_edge(band_y1+2)+3, band_y1+2, C["lamp"])
    put(im, shell_edge(band_y1+2)+4, band_y1+2, C["lamp"])
    # 烟囱
    rect(im, lx1-11, y0-2, lx1-8, y0-1, C["chim"])
    # 车轮
    wy = y1 + 2
    for wx in (lx0 + loco//2, lx1-4):
        for dy in range(-2,3):
            for dx in range(-2,3):
                if dx*dx+dy*dy <= 5: put(im, wx+dx, wy+dy, C["wheel"])
    # 底架
    rect(im, lx0+2, y1-frame_h+2, lx1-2, y1, C["body_d"])

    outline(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=160)
    ap.add_argument("--cars", type=int, default=2)
    ap.add_argument("--scale", type=int, default=5)
    ap.add_argument("-o", "--output", default="train_v8.png")
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
