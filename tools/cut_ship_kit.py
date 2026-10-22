"""Cut the ChatGPT airship construction kit into grid-sized pixel-art pieces.

  python tools/cut_ship_kit.py
Each piece is pixelized at its own factor so its width matches the café grid
(a hull / rail piece spans two tile edges = 58 px across). Prints each piece's
top-edge slope: "SW" pieces run down to the right (face under a tile's
lower-left edge); "SE" pieces are mirrored in game.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src", "mv_ship_kit.png")
OUT = os.path.join(ROOT, "assets", "ship")

# component index (pixelize.components reading order) -> (name, target width px)
PIECES = {
    3: ("deck", 59), 0: ("hull_a", 62), 1: ("hull_port", 62), 2: ("hull_b", 62),
    4: ("hull_port_b", 62), 5: ("bow", 62), 6: ("stern", 56), 7: ("rail_a", 62),
    8: ("rail_b", 62), 9: ("post", 30), 10: ("propeller", 44), 11: ("gangway", 56),
    12: ("wall_window_a", 50), 13: ("wall_window_b", 50), 14: ("awning", 62), 15: ("dome", 40),
}


def slope(img):
    a = np.array(img)[:, :, 3]
    h, w = a.shape

    def top(x0, x1):
        ys = [np.argmax(a[:, x] > 0) for x in range(x0, x1) if a[:, x].any()]
        return float(np.mean(ys)) if ys else 0.0

    left, right = top(0, max(1, w // 8)), top(w - max(1, w // 8), w)
    return "SW" if right > left + 2 else ("SE" if left > right + 2 else "flat")


def anchors(img):
    """Top and bottom edge end points (x, y) measured a couple of columns in."""
    a = np.array(img)[:, :, 3] > 0
    h, w = a.shape
    cols = [x for x in range(w) if a[:, x].any()]
    x0, x1 = cols[min(2, len(cols) - 1)], cols[max(0, len(cols) - 3)]
    top = lambda x: int(np.argmax(a[:, x]))
    bot = lambda x: int(h - 1 - np.argmax(a[::-1, x]))
    return {"top": [[x0, top(x0)], [x1, top(x1)]], "bottom": [[x0, bot(x0)], [x1, bot(x1)]], "size": [w, h]}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    rgb, mask = P.load(SRC, 110)
    pal = P.build_palette(rgb, mask, 48)
    boxes = P.components(mask)
    for i, (name, target) in PIECES.items():
        box = boxes[i]
        factor = (box[2] - box[0]) / float(target)
        img = P.trim(P.pixelize_fit(rgb, mask, box, factor, pal))
        img.save(os.path.join(OUT, f"{name}.png"))
        meta[name] = anchors(img)
        meta[name]["slope"] = slope(img)
        print(f"{name:14s} {img.size}  slope={slope(img)}")
    with open(os.path.join(OUT, "kit.json"), "w") as f:
        json.dump(meta, f, indent=1)
