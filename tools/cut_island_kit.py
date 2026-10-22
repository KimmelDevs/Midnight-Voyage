"""Cut the ChatGPT floating-island tile kit into grid-sized pieces.

  python tools/cut_island_kit.py
Writes assets/island/<name>.png and island.json: edge anchors for cliff
pieces (like the ship kit) and, for ground tiles, the centre of the top
diamond so tiles line up on the café grid.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize as P  # noqa: E402
from cut_ship_kit import anchors, slope  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src", "mv_island_kit.png")
OUT = os.path.join(ROOT, "assets", "island")

# component index -> (name, target width px)
PIECES = {
    1: ("grass", 60), 2: ("grass_flowers", 60), 3: ("path", 60), 0: ("pier", 60),
    4: ("cliff_a", 62), 5: ("cliff_roots", 62), 6: ("cliff_crystal", 62), 7: ("tip", 40),
    8: ("pier_post", 14), 9: ("tree", 50), 10: ("lamp", 22), 11: ("crates", 44), 12: ("bush", 34),
    13: ("shipyard", 124), 14: ("pump", 44), 15: ("crane", 64),
}
GROUND = {"grass", "grass_flowers", "path", "pier"}


def diamond_centre(img):
    """Centre of the top face: middle column, widest row of the upper part."""
    a = np.array(img)[:, :, 3] > 0
    h, w = a.shape
    widths = [a[y].sum() for y in range(h)]
    upper = widths[: max(1, int(h * 0.75))]
    y = int(np.argmax(upper))
    return [w / 2.0, float(y)]


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rgb, mask = P.load(SRC, 110)
    pal = P.build_palette(rgb, mask, 48)
    boxes = P.components(mask)
    meta = {}
    for i, (name, target) in PIECES.items():
        box = boxes[i]
        img = P.trim(P.pixelize_fit(rgb, mask, box, (box[2] - box[0]) / float(target), pal))
        img.save(os.path.join(OUT, f"{name}.png"))
        meta[name] = anchors(img)
        meta[name]["slope"] = slope(img)
        if name in GROUND:
            meta[name]["centre"] = diamond_centre(img)
        print(f"{name:14s} {img.size} slope={slope(img)}")
    with open(os.path.join(OUT, "island.json"), "w") as f:
        json.dump(meta, f, indent=1)
