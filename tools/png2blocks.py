#!/usr/bin/env python3
"""
png2blocks.py — 把 PNG 转成千星「文本像素」用的富文本字符串

原理：每个像素 = 一个字符 "■"，用 <color=#RRGGBB> 上色，用 \n 换行。
输出可直接粘进千星【文本框控件】的「文本内容」里。

用法：
    python3 png2blocks.py 输入.png                    # 默认最大 160 列
    python3 png2blocks.py 输入.png --cols 120         # 指定列数
    python3 png2blocks.py 输入.png -o 输出.txt        # 写文件
    python3 png2blocks.py 输入.png --colors 64        # 限制调色板
    python3 png2blocks.py 输入.png --palette nes      # 用经典 NES 调色板
    python3 png2blocks.py 输入.png --trim             # 裁掉透明边
    python3 png2blocks.py 输入.png --stats            # 只打印统计

依赖：Pillow
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install Pillow")

# 经典的 2C02 (NES) 主调色板（部分常用色）
NES_PALETTE = [
    (0, 0, 0), (252, 252, 252), (188, 188, 188), (124, 124, 124),
    (0, 0, 252), (0, 0, 188), (0, 0, 124), (68, 68, 252),
    (148, 0, 0), (168, 0, 0), (204, 0, 0), (236, 0, 0),
    (0, 120, 0), (0, 168, 0), (0, 200, 0), (0, 236, 0),
    (0, 88, 0), (0, 120, 0), (0, 152, 0), (0, 188, 0),
    (252, 216, 168), (252, 188, 124), (252, 160, 88), (252, 120, 60),
    (252, 88, 0), (228, 60, 0), (200, 40, 0), (168, 24, 0),
    (252, 252, 168), (252, 252, 124), (252, 252, 88), (252, 248, 40),
]

TRANSPARENT = "　"          # 全角空格：透明像素用（保持网格对齐）
BLOCK = "■"


def load(path, trim=False, max_cols=None):
    im = Image.open(path).convert("RGBA")
    if trim:
        bbox = im.getbbox()
        if bbox:
            im = im.crop(bbox)
    if max_cols and im.width > max_cols:
        ratio = max_cols / im.width
        im = im.resize((max_cols, max(1, round(im.height * ratio))), Image.LANCZOS)
    return im


def quantize(im, n_colors, palette_name):
    """把图量化到有限调色板，退回 RGBA"""
    rgb = im.convert("RGB")
    if palette_name == "nes":
        pal_img = Image.new("P", (1, 1))
        flat = []
        for c in NES_PALETTE:
            flat.extend(c)
        flat += [0] * (768 - len(flat))
        pal_img.putpalette(flat)
        return rgb.quantize(palette=pal_img, dither=Image.NONE).convert("RGBA")
    if n_colors and n_colors < 256:
        q = rgb.quantize(colors=n_colors, method=Image.MEDIANCUT, dither=Image.NONE)
        return q.convert("RGBA")
    return im


def to_richtext(im, alpha_threshold=128):
    """生成富文本网格。

    优化：把同一行里【连续同色】的像素合并进一个 <color> 标签，
    大幅缩短字符串（标签数是"颜色段数"而不是"像素数"）。
    """
    px = im.load()
    w, h = im.size
    lines = []
    for y in range(h):
        row = []
        x = 0
        while x < w:
            r, g, b, a = px[x, y]
            if a < alpha_threshold:
                # 连续透明像素
                n = 0
                while x < w and px[x, y][3] < alpha_threshold:
                    n += 1
                    x += 1
                row.append(TRANSPARENT * n)
                continue
            # 连续同色不透明像素
            n = 0
            while x < w:
                r2, g2, b2, a2 = px[x, y]
                if a2 < alpha_threshold or (r2, g2, b2) != (r, g, b):
                    break
                n += 1
                x += 1
            row.append("<color=#%02X%02X%02X>%s</color>" % (r, g, b, BLOCK * n))
        lines.append("".join(row))
    return "\n".join(lines)


def to_richtext_naive(im, alpha_threshold=128):
    """未优化版（每个像素一个标签），保留用于对比"""
    px = im.load()
    w, h = im.size
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < alpha_threshold:
                row.append(TRANSPARENT)
            else:
                row.append("<color=#%02X%02X%02X>%s</color>" % (r, g, b, BLOCK))
        out.append("".join(row))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--output")
    ap.add_argument("--cols", type=int, default=160, help="最大列数（默认 160）")
    ap.add_argument("--colors", type=int, default=0, help="量化到 N 色（0=不量化）")
    ap.add_argument("--palette", choices=["none", "nes"], default="none")
    ap.add_argument("--trim", action="store_true", help="裁掉透明边")
    ap.add_argument("--alpha", type=int, default=128, help="透明度阈值")
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()

    im = load(a.input, trim=a.trim, max_cols=a.cols)
    if a.colors or a.palette != "none":
        im = quantize(im, a.colors, a.palette)

    text = to_richtext(im, a.alpha)

    chars = im.width * im.height
    tags = text.count("<color=")
    naive = to_richtext_naive(im, a.alpha) if im.width * im.height <= 40000 else None
    print("尺寸        %d × %d" % im.size, file=sys.stderr)
    print("字符格      %d 个（每格 4 顶点 → 约 %d 顶点）" % (chars, chars * 4), file=sys.stderr)
    print("颜色标签    %d 个" % tags, file=sys.stderr)
    print("字符串长度  %d 字符（含标签）" % len(text), file=sys.stderr)
    if naive:
        print("  （未合并同色时为 %d 字符，压缩到 %.0f%%）" % (len(naive), 100*len(text)/len(naive)), file=sys.stderr)
    if chars * 4 > 65535:
        print("⚠ 顶点超过 Unity 单网格上限 65535，需要【竖向分段】", file=sys.stderr)
        seg = (chars * 4 + 65534) // 65535
        print("  建议切成 %d 段（每段约 %d 行）" % (seg, (im.height + seg - 1) // seg), file=sys.stderr)
    if a.stats:
        return
    if a.output:
        with open(a.output, "w", encoding="utf-8") as f:
            f.write(text)
        print("已写出 %s" % a.output, file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
