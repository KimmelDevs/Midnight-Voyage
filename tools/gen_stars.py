"""Draw the dish-quality star badges as hand-placed pixel art.

  python tools/gen_stars.py
Writes assets/ui/star_<tier>.png (11x11) for black, plain, bronze, silver, gold, diamond.
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")

SHAPE = [
    "....X....",
    "...XXX...",
    "...XXX...",
    "XXXXXXXXX",
    ".XXXXXXX.",
    "..XXXXX..",
    "..XXXXX..",
    ".XXX.XXX.",
    ".XX...XX.",
]

# tier: (base, highlight, shade, outline)
TIERS = {
    "black":   ((46, 40, 54), (88, 80, 98), (24, 20, 30), (150, 140, 156)),
    "plain":   ((238, 232, 222), (255, 255, 250), (186, 178, 168), (52, 34, 40)),
    "bronze":  ((198, 120, 62), (238, 172, 106), (138, 78, 38), (52, 28, 22)),
    "silver":  ((188, 198, 214), (244, 248, 252), (128, 138, 158), (40, 40, 56)),
    "gold":    ((246, 194, 58), (255, 238, 140), (194, 132, 26), (60, 36, 14)),
    "diamond": ((118, 216, 248), (232, 252, 255), (58, 146, 210), (22, 44, 86)),
}


def star(base, hi, shade, edge):
    img = Image.new("RGBA", (11, 11), (0, 0, 0, 0))
    filled = {(x + 1, y + 1) for y, row in enumerate(SHAPE) for x, c in enumerate(row) if c == "X"}
    for (x, y) in filled:
        c = base
        if (x - 1, y) not in filled or (x, y - 1) not in filled:
            c = hi
        if (x + 1, y) not in filled and (x, y + 1) not in filled:
            c = shade
        if y >= 7:
            c = shade
        img.putpixel((x, y), (*c, 255))
    img.putpixel((5, 4), (*hi, 255))
    for (x, y) in filled:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in filled and 0 <= q[0] < 11 and 0 <= q[1] < 11:
                img.putpixel(q, (*edge, 255))
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, cols in TIERS.items():
        img = star(*cols)
        if name == "diamond":  # glint
            img.putpixel((7, 4), (255, 255, 255, 255))
            img.putpixel((4, 6), (255, 255, 255, 255))
        img.save(os.path.join(OUT, f"star_{name}.png"))
    print("stars ->", OUT)
