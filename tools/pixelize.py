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
FIT = True
MULT = 0


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


def _edge_profile(img, axis):
    d = np.abs(np.diff(img, axis=axis)).sum(2)
    return d.sum(0) if axis == 1 else d.sum(1)


def _grid_score(prof, p):
    """Best phase and its edge score for pitch p."""
    n = len(prof)
    best = (-1.0, 0.0)
    for f in np.arange(0, p, 0.25):
        idx = np.round(np.arange(f, n - 1, p)).astype(int)
        s = prof[idx].mean()
        if s > best[0]:
            best = (s, f)
    return best


def fit_window(profile, lo, hi):
    """Best (pitch, phase) with pitch in [lo, hi]."""
    prof = profile / (profile.mean() + 1e-9)
    best = (-1.0, lo, 0.0)
    for p in np.arange(lo, hi, 0.02):
        s, f = _grid_score(prof, p)
        if s > best[0]:
            best = (s, p, f)
    return best[1], best[2]


def fit_grid(profile, target):
    """Find the art's true pixel pitch, then the whole multiple of it nearest `target`.

    ChatGPT 'pixels' are ~3-4.5px blocks, not a whole number; sampling with a
    fixed integer factor drifts off the grid and smears neighbours together.
    Multiples of the true pitch also hit edges, so the smallest pitch scoring
    close to the best is taken as the true one.
    """
    prof = profile / (profile.mean() + 1e-9)
    scores = [(p, *_grid_score(prof, p)) for p in np.arange(2.6, 7.0, 0.02)]
    top = max(s for _, s, _ in scores)
    true_p = min(p for p, s, _ in scores if s >= 0.88 * top)
    # refine around the chosen pitch
    p, s, f = max(((p, s, f) for p, s, f in scores if abs(p - true_p) < 0.15), key=lambda t: t[1])
    m = max(1, round(target / p))
    return p * m, f


def pixelize_fit(rgb, mask, box, factor, pal_img, alpha_vote=0.5):
    """Grid-aligned sampling at the measured fractional pitch (near `factor`)."""
    x0, y0, x1, y1 = box
    h, w = mask.shape
    x0, y0, x1, y1 = max(0, x0 - 4), max(0, y0 - 4), min(w, x1 + 4), min(h, y1 + 4)
    crop = rgb[y0:y1, x0:x1].astype(float)
    # ChatGPT sheets have no exact global grid, so fit pitch + phase per sprite and
    # per axis, but only within ±8% of the scale the sheet needs (keeps sizes even)
    px, fx = fit_window(_edge_profile(crop, 1), factor * 0.92, factor * 1.08)
    py, fy = fit_window(_edge_profile(crop, 0), factor * 0.92, factor * 1.08)
    q = np.array(Image.fromarray(crop.astype(np.uint8), "RGB").quantize(palette=pal_img, dither=Image.Dither.NONE))
    pal = np.array(pal_img.getpalette()[: 3 * 256]).reshape(-1, 3)
    m = mask[y0:y1, x0:x1]
    xs = np.arange(fx, crop.shape[1] - px * 0.5, px)
    ys = np.arange(fy, crop.shape[0] - py * 0.5, py)
    out = np.zeros((len(ys), len(xs), 4), dtype=np.uint8)
    for j, yy in enumerate(ys):
        a0, a1 = int(yy + py * 0.25), int(yy + py * 0.75) + 1
        for i, xx in enumerate(xs):
            b0, b1 = int(xx + px * 0.25), int(xx + px * 0.75) + 1
            bm = m[a0:a1, b0:b1]
            if bm.size == 0 or bm.mean() < alpha_vote:
                continue
            idx = Counter(q[a0:a1, b0:b1][bm].tolist()).most_common(1)[0][0]
            out[j, i, :3] = pal[idx]
            out[j, i, 3] = 255
    return Image.fromarray(defringe(out), "RGBA")


def pixelize_multiple(rgb, mask, box, mult, pal_img, alpha_vote=0.5):
    """Sample at an exact multiple of the sprite's own true pixel pitch.

    Prop/food sheets are drawn finer (~2.7-4px) than characters, so landing
    on their grid at game scale means taking every 2nd/3rd grid line and
    voting over the whole block.
    """
    x0, y0, x1, y1 = box
    h, w = mask.shape
    x0, y0, x1, y1 = max(0, x0 - 4), max(0, y0 - 4), min(w, x1 + 4), min(h, y1 + 4)
    crop = rgb[y0:y1, x0:x1].astype(float)
    # one square pitch per sprite, scored on both axes together (per-axis
    # estimates sometimes lock onto a sub-multiple and distort the aspect)
    profs = []
    for ax in (1, 0):
        prof = _edge_profile(crop, ax)
        profs.append(prof / (prof.mean() + 1e-9))

    def both(p):
        (sx, fx_), (sy, fy_) = _grid_score(profs[0], p), _grid_score(profs[1], p)
        return sx + sy, fx_, fy_

    scores = [(p, both(p)[0]) for p in np.arange(2.5, 7.0, 0.02)]
    top = max(s for _, s in scores)
    est = min(p for p, s in scores if s >= 0.9 * top)
    p = max(np.arange(est - 0.12, est + 0.12, 0.01), key=lambda q: both(q)[0])
    _, fx, fy = both(p)
    px = py = p * mult
    q = np.array(Image.fromarray(crop.astype(np.uint8), "RGB").quantize(palette=pal_img, dither=Image.Dither.NONE))
    pal = np.array(pal_img.getpalette()[: 3 * 256]).reshape(-1, 3)
    m = mask[y0:y1, x0:x1]
    k = 0.25 if mult == 1 else 0.08  # centre sample for 1x, whole block vote for multiples
    xs = np.arange(fx, crop.shape[1] - px * 0.5, px)
    ys = np.arange(fy, crop.shape[0] - py * 0.5, py)
    out = np.zeros((len(ys), len(xs), 4), dtype=np.uint8)
    for j, yy in enumerate(ys):
        a0, a1 = int(yy + py * k), int(yy + py * (1 - k)) + 1
        for i, xx in enumerate(xs):
            b0, b1 = int(xx + px * k), int(xx + px * (1 - k)) + 1
            bm = m[a0:a1, b0:b1]
            if bm.size == 0 or bm.mean() < alpha_vote:
                continue
            idx = Counter(q[a0:a1, b0:b1][bm].tolist()).most_common(1)[0][0]
            out[j, i, :3] = pal[idx]
            out[j, i, 3] = 255
    return Image.fromarray(defringe(out), "RGBA")


def pixelize(rgb, mask, box, factor, pal_img, alpha_vote=0.5):
    if MULT:
        return pixelize_multiple(rgb, mask, box, MULT, pal_img, alpha_vote)
    if FIT:
        return pixelize_fit(rgb, mask, box, factor, pal_img, alpha_vote)
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
    ap.add_argument("--factor", type=float, default=5)
    ap.add_argument("--height", type=int, default=0, help="grid mode: target sprite height (sets factor)")
    ap.add_argument("--colors", type=int, default=40)
    ap.add_argument("--key", type=float, default=110)
    ap.add_argument("--cell", default="48x64", help="grid mode: output cell WxH")
    ap.add_argument("--names", default="", help="objects mode: comma names in reading order")
    ap.add_argument("--no-fit", action="store_true", help="fixed integer factor instead of grid fitting")
    ap.add_argument("--mult", type=int, default=0, help="sample at N x each sprite's true pixel pitch")
    a = ap.parse_args()
    global FIT, MULT
    FIT = not a.no_fit
    MULT = a.mult

    rgb, mask = load(a.src, a.key)
    pal = build_palette(rgb, mask, a.colors)

    if a.mode == "grid":
        rows = bands(mask.sum(1))
        cols = bands(mask.sum(0))
        if a.height:  # derive the factor that makes the median sprite `height` px tall
            hs = sorted(r1 - r0 for r0, r1 in rows)
            a.factor = hs[len(hs) // 2] / a.height
            print(f"factor {a.factor:.2f} for height {a.height}")
        sprites = {}
        for r, (ry0, ry1) in enumerate(rows):
            for c, (cx0, cx1) in enumerate(cols):
                sub = mask[ry0:ry1 + 1, cx0:cx1 + 1]
                ys, xs = np.nonzero(sub)
                box = (cx0 + xs.min(), ry0 + ys.min(), cx0 + xs.max() + 1, ry0 + ys.max() + 1)
                sprites[r, c] = trim(pixelize(rgb, mask, box, a.factor, pal))
        if a.cell == "auto":  # smallest even cell that fits every frame
            cw = max(s.width for s in sprites.values()) + 2
            ch = max(s.height for s in sprites.values()) + 2
            cw, ch = cw + cw % 2, ch + ch % 2
        else:
            cw, ch = (int(v) for v in a.cell.split("x"))
        sheet = Image.new("RGBA", (cw * len(cols), ch * len(rows)), (0, 0, 0, 0))
        for (r, c), spr in sprites.items():
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
