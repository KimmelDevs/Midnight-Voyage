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


def objects_fit(src, factor, dest, names):
    """Like objects() but grid-fitted near a target factor (for oversized sources)."""
    tmp = os.path.join(OUT, "_tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    run("objects", os.path.join(SRC, src), tmp, "--factor", str(factor))
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
FURNITURE = [(2, "stove"), (3, "sink"), (4, "dish_rack"), (5, "dish_tub"), (6, "espresso"), (7, "fridge"),
             (8, "table_square"), (9, "prep_counter"), (10, "table_round"), (11, "chair"), (12, "bookshelf"),
             (13, "lamp"), (14, "fern"), (15, "chalkboard"), (16, "trash"), (17, "rug")]
# back views come out in a slightly different component order than the fronts
FURNITURE_BACK = [(0, "stove"), (2, "sink"), (3, "dish_rack"), (4, "dish_tub"), (5, "espresso"),
                  (6, "prep_counter"), (7, "fridge"), (8, "table_square"), (9, "table_round"), (10, "chair"),
                  (11, "bookshelf"), (12, "lamp"), (13, "fern"), (14, "chalkboard"), (15, "trash"), (16, "rug")]
ENEMIES = [(0, "royal_sugar_golem"), (1, "animated_teapot"), (2, "cursed_kitchenware"), (3, "flour_slime"),
           (4, "sugar_imp")]
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
    if os.path.exists(os.path.join(SRC, "mv_customers_sit.png")):  # SW-facing sitting poses
        objects_fit("mv_customers_sit.png", 9.5, chars, [(1, "customer_0_sit"), (2, "customer_1_sit"),
                                                      (3, "customer_2_sit"), (0, "customer_3_sit")])
    for key in CHARS:  # combat / outside outfits shown in the gacha
        src = os.path.join(SRC, f"mv_{key}_combat.png")
        if os.path.exists(src):
            run("grid", src, os.path.join(chars, f"{key}_combat.png"), "--height", "66", "--cell", "auto")
    print("customers")
    objects("mv_cafe_sheet.png", 2, os.path.join(OUT, "cafe"), CAFE)
    print("cafe")
    objects("mv_utility.png", 2, os.path.join(OUT, "furniture"), FURNITURE)
    if os.path.exists(os.path.join(SRC, "mv_utility_back.png")):  # back views for rotation
        objects("mv_utility_back.png", 2, os.path.join(OUT, "furniture"), [(i, n + "_back") for i, n in FURNITURE_BACK])
    print("furniture")
    if os.path.exists(os.path.join(SRC, "mv_enemies.png")):  # battle enemies, facing south-west
        os.makedirs(os.path.join(OUT, "enemies"), exist_ok=True)
        objects_fit("mv_enemies.png", 4.7, os.path.join(OUT, "enemies"), ENEMIES)
        print("enemies")
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
