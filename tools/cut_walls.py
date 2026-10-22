"""Cut the ChatGPT interior wall sheet into one-tile-edge wall pieces.

  python tools/cut_walls.py
Writes assets/walls/<name>.png and walls.json (edge anchors, same format as
the ship kit) so the game can lay each piece exactly on a tile edge.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize as P  # noqa: E402
from cut_ship_kit import anchors, slope  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src", "mv_walls.png")
OUT = os.path.join(ROOT, "assets", "walls")

# component index -> (name, target width px); one tile edge spans 29 px across
PIECES = {0: ("wall_plain", 34), 1: ("wall_art", 34), 2: ("wall_window", 34), 3: ("wall_shelf", 34),
          4: ("wall_door", 36), 5: ("wall_post", 9)}

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
        print(f"{name:12s} {img.size} slope={slope(img)}")
    with open(os.path.join(OUT, "walls.json"), "w") as f:
        json.dump(meta, f, indent=1)
