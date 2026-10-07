#!/usr/bin/env python3
"""
pixelize.py — 把一张普通图片处理成 2.5D 像素 sprite

流程（顺序很重要）：
    1. 裁掉背景（可选，按边角颜色自动判背景 / 或指定颜色）
    2. 先降采样到目标网格      ← 先降采样，避免后期糊
    3. 再量化调色板            ← 后量化，得到干净的像素色块
    4. 可选抖动
    5. 导出 PNG（像素图）+ 字符网格（文本像素用）

用法：
    python3 pixelize.py 输入.png --w 64                     # 输出 64 宽像素图
    python3 pixelize.py 输入.png --w 64 --colors 16          # 16 色调色板
    python3 pixelize.py 输入.png --w 64 --cutout             # 自动抠背景
    python3 pixelize.py 输入.png --w 64 --cutout --bg 255,255,255
    python3 pixelize.py 输入.png --w 64 -o 输出.png --blocks 输出.txt
    python3 pixelize.py 输入.png --w 64 --dither             # 有序抖动
"""
import argparse
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install Pillow")


BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]


def detect_bg_color(im, border=3):
    """用四边像素的众数当背景色"""
    w, h = im.size
    px = im.convert("RGB").load()
    samples = []
    for x in range(w):
        for y in list(range(min(border, h))) + list(range(max(0, h - border), h)):
            samples.append(px[x, y])
    for y in range(h):
        for x in list(range(min(border, w))) + list(range(max(0, w - border), w)):
            samples.append(px[x, y])
    if not samples:
        return (0, 0, 0)
    # 量化到 16 级再取众数，抗噪
    q = Counter((r // 16, g // 16, b // 16) for r, g, b in samples)
    (r, g, b), _ = q.most_common(1)[0]
    return (r * 16 + 8, g * 16 + 8, b * 16 + 8)


def cutout(im, bg, tol=42):
    """把接近背景色的像素置为透明"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    br, bg_, bb = bg
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            d = max(abs(r - br), abs(g - bg_), abs(b - bb))
            if d <= tol:
                px[x, y] = (r, g, b, 0)
            elif d <= tol * 1.6:
                # 半透明过渡边
                px[x, y] = (r, g, b, int(a * (d - tol) / (tol * 0.6)))
    return im


def downsample(im, target_w):
    w, h = im.size
    target_h = max(1, round(h * target_w / w))
    return im.resize((target_w, target_h), Image.BOX)


def quantize(im, n_colors):
    if not n_colors or n_colors >= 256:
        return im
    alpha = im.getchannel("A") if im.mode == "RGBA" else None
    rgb = im.convert("RGB")
    q = rgb.quantize(colors=n_colors, method=Image.MEDIANCUT, dither=Image.NONE)
    out = q.convert("RGBA")
    if alpha:
        # 降采样后 alpha 是硬的；阈值化即可
        a2 = alpha.point(lambda v: 255 if v >= 128 else 0)
        out.putalpha(a2)
    return out


def dither(im, strength=0.35):
    """简单的有序抖动（Bayer 8x8），在量化前调用"""
    im = im.convert("RGB")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            t = (BAYER8[y % 8][x % 8] / 64.0 - 0.5) * 255 * strength
            px[x, y] = (
                max(0, min(255, int(r + t))),
                max(0, min(255, int(g + t))),
                max(0, min(255, int(b + t))),
            )
    return im


def to_text(im, alpha_threshold=128):
    """输出文本像素网格（同色连续合并）"""
    px = im.load()
    w, h = im.size
    lines = []
    for y in range(h):
        row = []
        x = 0
        while x < w:
            r, g, b, a = px[x, y]
            if a < alpha_threshold:
                n = 0
                while x < w and px[x, y][3] < alpha_threshold:
                    n += 1
                    x += 1
                row.append("　" * n)
                continue
            n = 0
            while x < w:
                r2, g2, b2, a2 = px[x, y]
                if a2 < alpha_threshold or (r2, g2, b2) != (r, g, b):
                    break
                n += 1
                x += 1
            row.append("<color=#%02X%02X%02X>%s</color>" % (r, g, b, "■" * n))
        lines.append("".join(row))
    return "\n".join(lines)



def auto_crop_subject(im, margin=0.04):
    """粗略自动裁到主体：用"与四边背景色差异大"的像素确定包围盒。

    适合主体居中、背景相对均匀的照片。不保证成功，失败就返回原图。
    """
    im2 = im.convert("RGBA")
    w, h = im2.size
    bg = detect_bg_color(im2, border=4)
    px = im2.load()
    br, bgc, bb = bg
    xs, ys = [], []
    step = max(1, min(w, h) // 200)
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b, a = px[x, y]
            if a < 32:
                continue
            d = max(abs(r - br), abs(g - bgc), abs(b - bb))
            if d > 60:                      # 明显不是背景
                xs.append(x)
                ys.append(y)
    if len(xs) < 50:
        return im
    mx = int(w * margin)
    my = int(h * margin)
    box = (max(0, min(xs) - mx), max(0, min(ys) - my),
           min(w, max(xs) + mx), min(h, max(ys) + my))
    # 太小就当失败
    if (box[2] - box[0]) < w * 0.15 or (box[3] - box[1]) < h * 0.15:
        return im
    return im.crop(box)


def crop_frac(im, spec):
    """按 0~1 比例裁切：--crop l,t,r,b"""
    w, h = im.size
    l, t, r, b = [float(v) for v in spec.split(",")]
    return im.crop((int(l * w), int(t * h), int(r * w), int(b * h)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-w", "--width", type=int, default=64, help="目标像素宽（默认 64）")
    ap.add_argument("-o", "--output", help="输出像素图 PNG")
    ap.add_argument("--blocks", help="同时输出文本像素网格 .txt")
    ap.add_argument("--colors", type=int, default=16, help="调色板色数（0=不限）")
    ap.add_argument("--cutout", action="store_true", help="自动抠背景")
    ap.add_argument("--bg", help="手动指定背景色 r,g,b")
    ap.add_argument("--tol", type=int, default=42, help="背景容差")
    ap.add_argument("--dither", action="store_true", help="量化前加有序抖动")
    ap.add_argument("--scale", type=int, default=0, help="输出时放大倍数（0=不放大）")
    ap.add_argument("--autocrop", action="store_true", help="自动裁到主体")
    ap.add_argument("--crop", help="手动裁切，比例 l,t,r,b 例如 0.1,0.2,0.9,0.8")
    a = ap.parse_args()

    im = Image.open(a.input).convert("RGBA")
    print("输入      %d × %d" % im.size, file=sys.stderr)

    if a.crop:
        im = crop_frac(im, a.crop)
        print("手动裁切  → %d × %d" % im.size, file=sys.stderr)
    elif a.autocrop:
        im = auto_crop_subject(im)
        print("自动裁切  → %d × %d" % im.size, file=sys.stderr)

    if a.cutout or a.bg:
        bg = tuple(int(v) for v in a.bg.split(",")) if a.bg else detect_bg_color(im)
        print("背景色    rgb%s" % (bg,), file=sys.stderr)
        im = cutout(im, bg, a.tol)

    im = downsample(im, a.width)
    print("降采样到  %d × %d" % im.size, file=sys.stderr)

    if a.dither:
        rgb = dither(im)
        rgb.putalpha(im.getchannel("A"))
        im = rgb
        print("已加抖动", file=sys.stderr)

    im = quantize(im, a.colors)
    used = len(set(list(im.convert("RGB").getdata()))) if a.colors else "全部"
    print("调色板    %s 色" % used, file=sys.stderr)
    print("字符格    %d 个 → 约 %d 顶点" % (im.width * im.height, im.width * im.height * 4), file=sys.stderr)

    if a.output:
        out = im
        if a.scale > 1:
            out = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
        out.save(a.output)
        print("已写出    %s" % a.output, file=sys.stderr)
    if a.blocks:
        with open(a.blocks, "w", encoding="utf-8") as f:
            f.write(to_text(im))
        print("已写出    %s" % a.blocks, file=sys.stderr)
    if not a.output and not a.blocks:
        im.resize((im.width * 8, im.height * 8), Image.NEAREST).save("pixelized_preview.png")
        print("未指定输出，已生成预览 pixelized_preview.png", file=sys.stderr)


if __name__ == "__main__":
    main()
