#!/usr/bin/env python3
"""
pixelate_pro.py — 高质量「图像 → 像素画」转换（纯 numpy + PIL 实现）

对比常见粗糙做法（LANCZOS 插值 + 中位切分量化），本实现做了三件对的事：

  ① 下采样用【块内中值/主色】，不是线性插值
     → 不产生中间色，边缘不糊
  ② 颜色聚类在【LAB 感知均匀空间】做 k-means（k-means++ 初始化）
     → 人眼看起来误差更小，不会把亮色和暗色混一起
  ③ 可选 Floyd–Steinberg 抖动（像素画常用，但精修 sprite 时通常关掉）

算法参考 pyxelate（sedthh）与 scipy/PIL 的标准做法，
但不依赖 numba / scikit-image / scikit-learn，Termux 可直接跑。

用法：
    python3 pixelate_pro.py 输入图.png -w 240 -c 12 -o 输出.png
    python3 pixelate_pro.py 输入图.png -w 240 -c 12 --down median --dither none
"""
import argparse, sys
import numpy as np
from PIL import Image, ImageFilter


# ── sRGB ↔ LAB（D65）────────────────────────────────
def srgb_to_linear(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


_XYZ_FROM_RGB = np.array([
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041]])
_WHITE = np.array([0.95047, 1.0, 1.08883])


def rgb_to_lab(rgb):
    """rgb: (...,3) float 0-255 → lab"""
    lin = srgb_to_linear(rgb)
    xyz = lin @ _XYZ_FROM_RGB.T / _WHITE
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], -1)


def lab_to_rgb(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    fy = (L + 16) / 116
    fx = fy + a / 500
    fz = fy - b / 200
    def finv(t):
        return np.where(t ** 3 > 0.008856, t ** 3, (t - 16 / 116) / 7.787)
    xyz = np.stack([finv(fx), finv(fy), finv(fz)], -1) * _WHITE
    lin = xyz @ np.linalg.inv(_XYZ_FROM_RGB).T
    return linear_to_srgb(lin)


# ── 下采样：块内统计（不插值）────────────────────────
def denoise(img, k=3):
    """轻度中值去噪：压掉 JPEG 压缩噪点，但保留边缘。
    这一步对 mode 下采样尤其重要 —— 否则噪点会被当作"块内主色"保留下来。"""
    if k < 3:
        return img
    im = Image.fromarray(img.astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.MedianFilter(size=k)))


def despeckle(small, protect=None, min_same=1, rare_frac=1.01):
    """邻居感知去斑：删掉【孤立且稀有】的像素。

    判据（两个都满足才删）：
      ① 8 邻域中和自己同色的像素 ≤ min_same（孤立）
      ② 该颜色在全图的占比 < rare_frac（稀有）
    ⇒ 保留主体色块边缘、窗框、以及保护掩码里的像素（晶体/金饰）。

    protect: 同尺寸 bool 掩码，True 处不处理。
    """
    h, w, _ = small.shape
    out = small.copy()
    vals, cnt = np.unique(small.reshape(-1, 3), axis=0, return_counts=True)
    frac = {tuple(v): c / cnt.sum() for v, c in zip(vals, cnt)}
    removed = 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if protect is not None and protect[y, x]:
                continue
            cur = small[y, x]
            key = tuple(cur)
            if frac.get(key, 1.0) >= rare_frac:      # 不是稀有颜色 → 可能是正常细节
                continue
            nb = small[y-1:y+2, x-1:x+2].reshape(-1, 3)
            same = 0
            for q in nb:
                if abs(int(q[0])-int(cur[0])) + abs(int(q[1])-int(cur[1])) + abs(int(q[2])-int(cur[2])) <= 24:
                    same += 1
            if same <= min_same:                      # 孤立
                nbf = nb.reshape(-1, 3)
                vv, cc = np.unique(nbf, axis=0, return_counts=True)
                out[y, x] = vv[np.argmax(cc)]
                removed += 1
    return out, removed


def downsample(img, tw, th, mode="median"):
    """img: (H,W,3) uint8 → (th,tw,3) uint8。按块取统计量。"""
    H, W, _ = img.shape
    ys = (np.arange(th + 1) * H / th).astype(int)
    xs = (np.arange(tw + 1) * W / tw).astype(int)
    out = np.zeros((th, tw, 3), np.float64)
    for j in range(th):
        for i in range(tw):
            blk = img[ys[j]:max(ys[j] + 1, ys[j + 1]),
                      xs[i]:max(xs[i] + 1, xs[i + 1])].reshape(-1, 3)
            if mode == "mean":
                out[j, i] = blk.mean(0)
            elif mode == "mode":
                q = (blk // 8).astype(np.int32)
                key = q[:, 0] * 4096 + q[:, 1] * 64 + q[:, 2]
                vals, cnt = np.unique(key, return_counts=True)
                k = vals[np.argmax(cnt)]
                sel = key == k
                out[j, i] = blk[sel].mean(0)
            else:                                   # median（默认）
                out[j, i] = np.median(blk, 0)
    return np.clip(out, 0, 255)


# ── k-means++ 量化（LAB 空间）────────────────────────
def kmeans_lab(lab_px, k, iters=30, seed=0):
    rng = np.random.default_rng(seed)
    n = len(lab_px)
    if n <= k:
        return lab_px.copy()
    # k-means++ 初始化
    cent = [lab_px[rng.integers(n)]]
    d2 = ((lab_px - cent[0]) ** 2).sum(1)
    for _ in range(1, k):
        p = d2 / max(d2.sum(), 1e-12)
        cent.append(lab_px[rng.choice(n, p=p)])
        d2 = np.minimum(d2, ((lab_px - cent[-1]) ** 2).sum(1))
    cent = np.array(cent)
    for _ in range(iters):
        dist = ((lab_px[:, None, :] - cent[None, :, :]) ** 2).sum(-1)
        lab_i = dist.argmin(1)
        new = np.array([lab_px[lab_i == j].mean(0) if (lab_i == j).any() else cent[j]
                        for j in range(k)])
        if np.allclose(new, cent, atol=1e-4):
            break
        cent = new
    return cent


def quantize_lab(lab_img, k, seed=0):
    H, W, _ = lab_img.shape
    px = lab_img.reshape(-1, 3)
    cent = kmeans_lab(px, k, seed=seed)
    dist = ((px[:, None, :] - cent[None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(1)
    return cent, idx.reshape(H, W)


# ── Floyd–Steinberg 抖动（在 LAB 空间扩散误差）────────
def dither_fs(lab_img, cent):
    H, W, _ = lab_img.shape
    buf = lab_img.astype(np.float64).copy()
    out = np.zeros((H, W, 3))
    for y in range(H):
        for x in range(W):
            old = buf[y, x]
            j = ((cent - old) ** 2).sum(1).argmin()
            new = cent[j]
            out[y, x] = new
            err = old - new
            if x + 1 < W:      buf[y, x + 1] += err * 7 / 16
            if y + 1 < H:
                if x > 0:      buf[y + 1, x - 1] += err * 3 / 16
                buf[y + 1, x] += err * 5 / 16
                if x + 1 < W:  buf[y + 1, x + 1] += err * 1 / 16
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-w", "--width", type=int, default=240)
    ap.add_argument("-c", "--colors", type=int, default=12)
    ap.add_argument("--down", choices=["median", "mean", "mode"], default="median")
    ap.add_argument("--dither", choices=["none", "fs"], default="none")
    ap.add_argument("--crop", default=None, help="l,t,r,b 先裁切")
    ap.add_argument("--denoise", type=int, default=3,
                    help="下采样前中值去噪核（0=关，默认 3）")
    ap.add_argument("--despeckle", action="store_true",
                    help="邻居感知去斑：删孤立且稀有的像素")
    ap.add_argument("--speck-min", type=int, default=1,
                    help="去斑：邻域同色像素数 ≤ 此值才算孤立（默认 1，最保守）")
    ap.add_argument("--speck-rare", type=float, default=1.01,
                    help="去斑：颜色占比 < 此值才算稀有（默认 1.01=不限）")
    ap.add_argument("--bg-thr", type=int, default=238,
                    help="背景阈值：亮于此值的算背景，输出透明")
    ap.add_argument("-o", "--output", default="pixel.png")
    a = ap.parse_args()

    im = Image.open(a.src).convert("RGB")
    if a.crop:
        im = im.crop(tuple(int(v) for v in a.crop.split(",")))
    arr = np.asarray(im).astype(np.float64)
    H, W, _ = arr.shape

    # 自动裁到非背景包围盒
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    fg = lum < a.bg_thr
    if fg.sum() > 100:
        ys, xs = np.where(fg)
        arr = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        H, W, _ = arr.shape

    th = max(1, round(H * a.width / W))
    print("下采样 %dx%d → %dx%d（模式 %s）" % (W, H, a.width, th, a.down), file=sys.stderr)
    src = arr.astype(np.uint8)
    if a.denoise > 0:
        src = denoise(src, a.denoise)
        print("中值去噪 k=%d" % a.denoise, file=sys.stderr)
    small = downsample(src, a.width, th, a.down)
    if a.despeckle:
        # 保护掩码：青色晶体 + 金色（R>G>B 且偏黄）
        sr, sg, sb = small[:,:,0].astype(int), small[:,:,1].astype(int), small[:,:,2].astype(int)
        cyan = (sb > 90) & ((sb - sr) > 40) & (sg > sr)
        gold = (sr > 140) & (sg > 110) & (sg > sb + 20) & (sr > sb + 40)
        prot = cyan | gold
        small, nrm = despeckle(small, protect=prot, min_same=a.speck_min, rare_frac=a.speck_rare)
        print("邻居感知去斑：删除 %d px（保护晶体/金色 %d px）" % (nrm, prot.sum()), file=sys.stderr)

    lab = rgb_to_lab(small)
    print("LAB k-means 聚类 %d 色…" % a.colors, file=sys.stderr)
    cent, idx = quantize_lab(lab, a.colors)
    if a.dither == "fs":
        lab_out = dither_fs(lab, cent)
    else:
        lab_out = cent[idx]
    rgb_out = np.clip(lab_to_rgb(lab_out), 0, 255).astype(np.uint8)

    # 背景透明
    out = np.dstack([rgb_out, np.full((th, a.width), 255, np.uint8)])
    l2 = 0.299 * rgb_out[:, :, 0] + 0.587 * rgb_out[:, :, 1] + 0.114 * rgb_out[:, :, 2]
    out[l2 >= a.bg_thr, 3] = 0
    res = Image.fromarray(out, "RGBA")
    res.save(a.output)
    print("写出 %s  (%dx%d, %d 色)" % (a.output, res.width, res.height,
                                      len(np.unique(rgb_out.reshape(-1, 3), axis=0))),
          file=sys.stderr)


if __name__ == "__main__":
    main()
