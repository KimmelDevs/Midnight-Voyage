"""Rebuild every game asset from the ChatGPT sources in art_src/.

  python tools/build_art.py
Object sheets are split in the component order pixelize.py reports; the name
lists below map that order to file names (check a contact sheet if a source
image is regenerated).
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PX = os.path.join(ROOT, "tools", "pixelize.py")
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "assets")


def run(*args):
    subprocess.run([sys.executable, PX, *args], check=True, cwd=ROOT, stdout=subprocess.DEVNULL)


def objects(src, mult, dest, names):
    """Sample at `mult` x each object's true pixel pitch.
    names: list of (index, name); unnamed components are dropped."""
    tmp = os.path.join(OUT, "_tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    run("objects", os.path.join(SRC, src), tmp, "--mult", str(mult))
    os.makedirs(dest, exist_ok=True)
    for i, name in names:
        shutil.move(os.path.join(tmp, f"obj_{i:02d}.png"), os.path.join(dest, f"{name}.png"))
    shutil.rmtree(tmp)


CHARS = {"chef": "mv_chef_iso.png", "leo": "mv_leo.png", "mira": "mv_mira.png",
         "kaito": "mv_kaito.png", "seraphine": "mv_seraphine.png", "selene": "mv_selene.png"}
CAFE = [(0, "wall_left"), (1, "wall_right"), (2, "floor_wood"), (3, "floor_check"), (4, "counter"),
        (5, "stove"), (7, "table"), (8, "chair_se"), (9, "display"), (10, "door"), (11, "chair_sw"),
        (12, "plant")]
FOOD = ["melon_soda", "latte", "coffee", "matcha", "shortcake", "choco_cake", "croissant", "pancakes",
        "ramen", "parfait", "omurice", "curry", "sandwich", "pudding", "macarons", "cookies"]
GACHA = [(0, "machine"), (1, "capsule_r"), (2, "capsule_sr"), (3, "capsule_ssr"), (5, "gem_big"),
         (6, "ticket"), (8, "sparkle"), (11, "coin_big"), (15, "frame_r"), (16, "frame_sr"), (17, "frame_ssr")]

if __name__ == "__main__":
    chars = os.path.join(OUT, "chars")
    os.makedirs(chars, exist_ok=True)
    for key, src in CHARS.items():
        run("grid", os.path.join(SRC, src), os.path.join(chars, f"{key}.png"), "--height", "66", "--cell", "auto")
        print("char", key)
    grid = os.path.join(chars, "_customers_grid.png")
    run("grid", os.path.join(SRC, "mv_customers.png"), grid, "--height", "62", "--cell", "auto")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "split_customers.py"), grid, chars, "--cell", "auto"],
                   check=True, cwd=ROOT, stdout=subprocess.DEVNULL)
    os.remove(grid)
    print("customers")
    objects("mv_cafe_sheet.png", 2, os.path.join(OUT, "cafe"), CAFE)
    print("cafe")
    food = list(enumerate(FOOD))
    objects("mv_food_sheet.png", 1, os.path.join(OUT, "food"), food)                 # large showcase
    objects("mv_food_sheet.png", 2, os.path.join(OUT, "food", "small"), food)        # bubbles + menu
    objects("mv_food_sheet.png", 3, os.path.join(OUT, "food", "tiny"), food)         # plates on tables
    print("food")
    gacha = os.path.join(OUT, "gacha")
    objects("mv_gacha_sheet.png", 2, gacha, [g for g in GACHA if not g[1].startswith("frame")])
    objects("mv_gacha_sheet.png", 1, gacha, [g for g in GACHA if g[1].startswith("frame")])
    objects("mv_gacha_sheet.png", 3, gacha, [(5, "gem"), (11, "coin")])
    print("gacha")
