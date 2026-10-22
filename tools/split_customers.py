"""Split a pixelized 6x4 customer grid into per-customer 3x2 sheets.

Input row = one customer: SW walk1, SW stand, SW walk2, NW walk1, NW stand, NW walk2.
Output customer_<i>.png: row 0 = SW, row 1 = NW (Actor mirrors them for SE/NE).
  python tools/split_customers.py assets/chars/_customers_grid.png assets/chars --start 0
"""
import argparse
import os

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("dst_dir")
ap.add_argument("--cell", default="48x64")
ap.add_argument("--start", type=int, default=0)
a = ap.parse_args()

grid = Image.open(a.src)
if a.cell == "auto":
    cw, ch = grid.width // 6, grid.height // 4
else:
    cw, ch = (int(v) for v in a.cell.split("x"))
rows = grid.height // ch
for r in range(rows):
    out = Image.new("RGBA", (cw * 3, ch * 2), (0, 0, 0, 0))
    for c in range(6):
        cell = grid.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
        out.paste(cell, ((c % 3) * cw, (c // 3) * ch))
    path = os.path.join(a.dst_dir, f"customer_{a.start + r}.png")
    out.save(path)
    print(path)
