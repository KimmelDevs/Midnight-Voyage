"""Turn ChatGPT "pixel art" images into clean, grid-true pixel art.

ChatGPT images are pixel-art *looking* but drawn at ~5x with blurry, uneven
pixel blocks on a magenta background. This script:
  1. keys out the magenta background,
  2. finds each sprite (grid mode) or each separate object (objects mode),
  3. quantizes to a shared palette,
  4. downsamples every block of `factor` px to one pixel by majority vote.

Grid mode (character sheets, feet aligned to a common baseline):
  python tools/pixelize.py grid art_src/mv_chef_iso.png assets/chars/chef.png --factor 5 --cell 48x64
Objects mode (tile/prop sheets, one PNG per object, reading order):
  python tools/pixelize.py objects art_src/cafe_sheet.png assets/cafe/ --factor 5 --names a,b,c
"""
import argparse
import os
from collections import Counter, deque

import numpy as np
from PIL import Image

MAGENTA = np.array([255, 0, 255])


def load(path, key_dist):
    rgb = np.array(Image.open(path).convert("RGB")).astype(int)
    dist = np.sqrt(((rgb - MAGENTA) ** 2).sum(2))
    # magenta-ish halo: strong red+blue, weak green
    halo = (rgb[:, :, 0] > 170) & (rgb[:, :, 2] > 170) & (rgb[:, :, 1] < 110)
    mask = (dist > key_dist) & ~halo
    return rgb, mask


def bands(profile, min_len=6):
    out, start = [], None
    for i, v in enumerate(profile):
        if v > 0 and start is None:
            start = i
        elif v == 0 and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(profile) - 1))
    return [b for b in out if b[1] - b[0] >= min_len]


def components(mask, step=3, min_px=40):
    """Bounding boxes of connected opaque regions (coarse grid, 8-neighbour)."""
    small = mask[::step, ::step]
    h, w = small.shape
    seen = np.zeros_like(small, dtype=bool)
    boxes = []
    for y in range(h):
        for x in range(w):
            if not small[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            y0 = y1 = y
            x0 = x1 = x
            n = 0
            while q:
                cy, cx = q.popleft()
                n += 1
                y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            if n >= min_px:
                boxes.append((x0 * step, y0 * step, (x1 + 1) * step, (y1 + 1) * step))
    # reading order: by row band (tolerant), then x
    boxes.sort(key=lambda b: (b[1] // 60, b[0]))
    return boxes


def build_palette(rgb, mask, colors):
    px = rgb[mask].astype(np.uint8)
    strip = Image.fromarray(px.reshape(1, -1, 3), "RGB")
    return strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def pixelize(rgb, mask, box, factor, pal_img, alpha_vote=0.5):
    x0, y0, x1, y1 = box
    sub = rgb[y0:y1, x0:x1].astype(np.uint8)
    sub_mask = mask[y0:y1, x0:x1]
    q = np.array(Image.fromarray(sub, "RGB").quantize(palette=pal_img, dither=Image.Dither.NONE))
    pal = np.array(pal_img.getpalette()[: 3 * 256]).reshape(-1, 3)
    oh, ow = (y1 - y0) // factor, (x1 - x0) // factor
    out = np.zeros((oh, ow, 4), dtype=np.uint8)
    for oy in range(oh):
        for ox in range(ow):
            bm = sub_mask[oy * factor:(oy + 1) * factor, ox * factor:(ox + 1) * factor]
            if bm.mean() < alpha_vote:
                continue
            bq = q[oy * factor:(oy + 1) * factor, ox * factor:(ox + 1) * factor][bm]
            idx = Counter(bq.tolist()).most_common(1)[0][0]
            out[oy, ox, :3] = pal[idx]
            out[oy, ox, 3] = 255
    return Image.fromarray(defringe(out), "RGBA")


def defringe(px):
    """Recolor magenta-tinted edge pixels (background bleed) to a dark outline."""
    h, w = px.shape[:2]
    r, g, b, a = (px[:, :, i].astype(int) for i in range(4))
    pink = (a > 0) & (r - g > 60) & (b - g > 40) & (b > 70)
    for y, x in zip(*np.nonzero(pink)):
        edge = any(not (0 <= y + dy < h and 0 <= x + dx < w) or px[y + dy, x + dx, 3] == 0
                   for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge:
            px[y, x, :3] = (52, 30, 40)
    return px


def trim(img):
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["grid", "objects"])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--factor", type=int, default=5)
    ap.add_argument("--colors", type=int, default=40)
    ap.add_argument("--key", type=float, default=110)
    ap.add_argument("--cell", default="48x64", help="grid mode: output cell WxH")
    ap.add_argument("--names", default="", help="objects mode: comma names in reading order")
    a = ap.parse_args()

    rgb, mask = load(a.src, a.key)
    pal = build_palette(rgb, mask, a.colors)

    if a.mode == "grid":
        cw, ch = (int(v) for v in a.cell.split("x"))
        rows = bands(mask.sum(1))
        cols = bands(mask.sum(0))
        sheet = Image.new("RGBA", (cw * len(cols), ch * len(rows)), (0, 0, 0, 0))
        for r, (ry0, ry1) in enumerate(rows):
            for c, (cx0, cx1) in enumerate(cols):
                sub = mask[ry0:ry1 + 1, cx0:cx1 + 1]
                ys, xs = np.nonzero(sub)
                box = (cx0 + xs.min(), ry0 + ys.min(), cx0 + xs.max() + 1, ry0 + ys.max() + 1)
                spr = trim(pixelize(rgb, mask, box, a.factor, pal))
                # bottom-centre on the cell (feet baseline 1px above cell bottom)
                px = c * cw + (cw - spr.width) // 2
                py = r * ch + ch - 1 - spr.height
                sheet.alpha_composite(spr, (max(c * cw, px), max(r * ch, py)))
        os.makedirs(os.path.dirname(a.dst) or ".", exist_ok=True)
        sheet.save(a.dst)
        print(f"grid {len(rows)}x{len(cols)} -> {a.dst} {sheet.size}")
    else:
        names = [n for n in a.names.split(",") if n]
        boxes = components(mask)
        os.makedirs(a.dst, exist_ok=True)
        for i, box in enumerate(boxes):
            spr = trim(pixelize(rgb, mask, box, a.factor, pal))
            name = names[i] if i < len(names) else f"obj_{i:02d}"
            spr.save(os.path.join(a.dst, f"{name}.png"))
            print(f"{name}: box={box} -> {spr.size}")


if __name__ == "__main__":
    main()
