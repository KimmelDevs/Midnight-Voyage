extends Node
## Global game state: data tables, economy, gacha, save/load.

signal changed

const SAVE_PATH := "user://cafe_save.json"
const TEST_SAVE_PATH := "user://cafe_save_test.json"
## `godot -- --test-save` plays on a throwaway copy so test runs never touch the real save.
var save_path := SAVE_PATH

const FOODS := {
	"coffee":     {"name": "Hot Coffee",       "price": 8,  "cook": 3.0, "unlock": 0},
	"croissant":  {"name": "Croissant",        "price": 10, "cook": 4.0, "unlock": 0},
	"cookies":    {"name": "Cookie Plate",     "price": 12, "cook": 4.0, "unlock": 0},
	"latte":      {"name": "Heart Latte",      "price": 14, "cook": 4.5, "unlock": 60},
	"matcha":     {"name": "Matcha Tea",       "price": 15, "cook": 4.5, "unlock": 90},
	"sandwich":   {"name": "Sandwich",         "price": 18, "cook": 5.0, "unlock": 120},
	"pudding":    {"name": "Caramel Pudding",  "price": 20, "cook": 5.5, "unlock": 160},
	"melon_soda": {"name": "Melon Soda Float", "price": 22, "cook": 5.0, "unlock": 200},
	"macarons":   {"name": "Macarons",         "price": 25, "cook": 6.0, "unlock": 260},
	"pancakes":   {"name": "Pancake Stack",    "price": 28, "cook": 6.5, "unlock": 320},
	"shortcake":  {"name": "Strawberry Shortcake", "price": 32, "cook": 7.0, "unlock": 400},
	"choco_cake": {"name": "Chocolate Cake",   "price": 34, "cook": 7.0, "unlock": 480},
	"parfait":    {"name": "Fruit Parfait",    "price": 38, "cook": 7.5, "unlock": 560},
	"omurice":    {"name": "Omurice",          "price": 44, "cook": 8.5, "unlock": 680},
	"curry":      {"name": "Curry Rice",       "price": 48, "cook": 9.0, "unlock": 800},
	"ramen":      {"name": "Ramen",            "price": 55, "cook": 10.0, "unlock": 950},
}

const DRINKS := ["coffee", "latte", "matcha", "melon_soda"]

## Core stats. Café: TEC food quality, AGI cook/serve speed, END stamina,
## HOS satisfaction + tips, FOC fewer mistakes on complex recipes.
## Battle (later): TEC damage, AGI attack speed/dodge, END HP/defense,
## HOS healing/shields/buffs, FOC crit/effect accuracy.
const STATS := ["tec", "agi", "end", "hos", "foc"]
const STAT_LABEL := {"tec": "TEC", "agi": "AGI", "end": "END", "hos": "HOS", "foc": "FOC"}
const JOBS := ["Chef", "Barista", "Waiter", "Hostess", "Cleaner", "Rest"]
const JOB_STATS := {
	"Chef": ["tec", "foc"], "Barista": ["tec", "hos"], "Waiter": ["agi", "hos"],
	"Hostess": ["hos", "foc"], "Cleaner": ["agi", "end"], "Rest": [],
}

## Dish quality tiers, worst to best.
const TIERS := ["black", "plain", "bronze", "silver", "gold", "diamond"]
const TIER_NAME := {"black": "Burnt", "plain": "Plain", "bronze": "Bronze", "silver": "Silver", "gold": "Gold", "diamond": "Diamond"}
const TIER_PRICE := {"black": 0.3, "plain": 0.8, "bronze": 1.0, "silver": 1.25, "gold": 1.6, "diamond": 2.2}
const TIER_REP := {"black": 0, "plain": 1, "bronze": 1, "silver": 2, "gold": 3, "diamond": 5}

## Gacha pool. Mostly humans; a couple of rare supernaturals.
const STAFF := {
	"hana":      {"name": "Hana",      "title": "Apprentice Chef",     "rarity": "SR",  "sheet": "chef",      "job": "Chef",
		"stats": {"tec": 14, "agi": 10, "end": 11, "hos": 9, "foc": 12}},
	"leo":       {"name": "Leo",       "title": "Rookie Waiter",       "rarity": "R",   "sheet": "leo",       "job": "Waiter",
		"stats": {"tec": 6, "agi": 13, "end": 10, "hos": 11, "foc": 7}},
	"mira":      {"name": "Mira",      "title": "Barista",             "rarity": "R",   "sheet": "mira",      "job": "Barista",
		"stats": {"tec": 11, "agi": 8, "end": 8, "hos": 13, "foc": 13}},
	"kaito":     {"name": "Kaito",     "title": "Swordsman Pâtissier", "rarity": "SR",  "sheet": "kaito",     "job": "Chef",
		"stats": {"tec": 16, "agi": 13, "end": 14, "hos": 6, "foc": 15}},
	"seraphine": {"name": "Seraphine", "title": "Royal Mage Hostess",  "rarity": "SSR", "sheet": "seraphine", "job": "Hostess",
		"stats": {"tec": 12, "agi": 15, "end": 10, "hos": 21, "foc": 17}},
	"selene":    {"name": "Selene",    "title": "Vampire Bartender",   "rarity": "SSR", "sheet": "selene",    "job": "Barista",
		"stats": {"tec": 20, "agi": 14, "end": 17, "hos": 16, "foc": 18}},
}
const RATES := {"SSR": 0.05, "SR": 0.20, "R": 0.75}
const PULL_COST := 100
const PULL10_COST := 900

const GEM_TRADE := {"coins": 300, "gems": 50}

## Placeable furniture. kind drives behaviour: stove (chefs cook), espresso
## (baristas brew), counter (dishes wait for pickup), sink (dishes are washed),
## rack (faster washing), fridge (faster cooking), table/chair (seating),
## rug (walkable floor decor), deco (ambience: patience + tips).
## Art lives in assets/furniture/<key>.png unless "tex" says otherwise.
## "faces": which way the unmirrored art points (0 = SE, 1 = SW; default 1 -
## the ChatGPT furniture faces lower-left, chairs face lower-right).
const ITEMS := {
	"stove":           {"name": "Stove",           "kind": "stove",    "cost": 160},
	"espresso":        {"name": "Espresso Machine", "kind": "espresso", "cost": 180},
	"prep_counter":    {"name": "Prep Counter",    "kind": "counter",  "cost": 70},
	"service_counter": {"name": "Service Counter", "kind": "counter",  "cost": 120, "tex": "cafe/counter"},
	"sink":            {"name": "Sink",            "kind": "sink",     "cost": 120},
	"dish_rack":       {"name": "Drying Rack",     "kind": "rack",     "cost": 60},
	"dish_tub":        {"name": "Dish Tub",        "kind": "deco",     "cost": 30, "ambience": 0},
	"fridge":          {"name": "Fridge",          "kind": "fridge",   "cost": 200},
	"table_round":     {"name": "Round Table",     "kind": "table",    "cost": 90},
	"table_square":    {"name": "Square Table",    "kind": "table",    "cost": 80},
	"chair":           {"name": "Chair",           "kind": "chair",    "cost": 40, "faces": 0, "back_flip": true},
	"bookshelf":       {"name": "Bookshelf",       "kind": "deco",     "cost": 110, "ambience": 3},
	"lamp":            {"name": "Standing Lamp",   "kind": "deco",     "cost": 70, "ambience": 2},
	"fern":            {"name": "Potted Fern",     "kind": "deco",     "cost": 45, "ambience": 2},
	"plant":           {"name": "Flower Pot",      "kind": "deco",     "cost": 45, "ambience": 2, "tex": "cafe/plant"},
	"display":         {"name": "Pastry Display",  "kind": "deco",     "cost": 150, "ambience": 4, "tex": "cafe/display"},
	"chalkboard":      {"name": "Menu Board",      "kind": "deco",     "cost": 60, "ambience": 2},
	"trash":           {"name": "Trash Bin",       "kind": "deco",     "cost": 25, "ambience": 0},
	"rug":             {"name": "Rug",             "kind": "rug",      "cost": 50, "ambience": 1},
	# walls sit on one EDGE of a tile (rot picks the edge); doorways and posts don't block
	"wall_plain":      {"name": "Wall",            "kind": "wall",     "cost": 30, "tex": "walls/wall_plain"},
	"wall_art":        {"name": "Wall (painting)", "kind": "wall",     "cost": 45, "ambience": 1, "tex": "walls/wall_art"},
	"wall_window":     {"name": "Wall (window)",   "kind": "wall",     "cost": 50, "ambience": 1, "tex": "walls/wall_window"},
	"wall_shelf":      {"name": "Wall (cup shelf)", "kind": "wall",    "cost": 50, "ambience": 1, "tex": "walls/wall_shelf"},
	"wall_door":       {"name": "Doorway",         "kind": "wall",     "cost": 60, "blocks": false, "tex": "walls/wall_door"},
	"wall_post":       {"name": "Corner Post",     "kind": "wall",     "cost": 15, "blocks": false, "tex": "walls/wall_post"},
}

const DAY_LENGTH := 150.0   # seconds the café is open each day

## ---- the Sky Café airship: the café map is the ship's deck ----
## Deck mask: row = r, character index = c ("X" = deck tile). The long axis
## runs along c (stern at c = 0, bow at the far end). Saved per game so the
## ship can be expanded tile by tile later.
const SHIP_TEMPLATE := [
	"XXXXXXXXXXXX",
	"XXXXXXXXXXXX",
	"XXXXXXXXXXXX",
	"XXXXXXXXXXXX",
	"XXXXXXXXXXXX",
	"XXXXXXXXXXXX",
]
const SHIP_CABIN := [0, 0, 8, 4]     ## [c, r, width, height] indoor café room at the stern
## Cabin front-row tiles whose outer (lower-left) wall is an open doorway.
const SHIP_CABIN_DOORS := [[4, 3], [5, 3]]
const SHIP_GANGWAY := [6, 5]         ## deck tile where customers come aboard

## ---- shared progression (one source of truth for café AND battle) ----
const MAX_LEVEL := 30
## Per-level growth of the five core stats; rarity = specialisation/potential.
const GROWTH := {"R": 0.06, "SR": 0.065, "SSR": 0.07}
## Materials won in battle. golden_sugar: next dish cooked gains +1 star tier.
## training_manual: +120 XP for one character (Staff panel).
const MATERIALS := {
	"golden_sugar": {"name": "Golden Sugar", "desc": "Next dish cooked is one star better"},
	"training_manual": {"name": "Training Manual", "desc": "+120 XP to one character"},
	"build_mats": {"name": "Building Materials", "desc": "Timber, metal and nails for repairs and upgrades"},
	"aether_shards": {"name": "Aether Shards", "desc": "Raw Aether; an engineer refines it into fuel"},
}
const MANUAL_XP := 120
## ---- starting island: town buildings (the café itself lives on the ship) ----
const ISLAND_SIZE := 24                       ## island grid is ISLAND_SIZE x ISLAND_SIZE tiles
const CORE_AREA := Rect2i(4, 4, 16, 16)       ## buildable before the Town Hall Lv 5 expansion
const EXPANDED_AREA := Rect2i(1, 1, 22, 22)
const MAX_FACILITY_LEVEL := 5
## size = footprint in island tiles; th = Town Hall level that unlocks it;
## phase > 1 = planned for a later update (shown as coming soon).
const BUILDINGS := {
	"town_hall":  {"name": "Town Hall", "size": Vector2i(5, 5), "th": 1, "phase": 1,
		"desc": "Sets the level cap of every facility and unlocks new buildings and land."},
	"shop":       {"name": "General Shop", "size": Vector2i(3, 3), "th": 1, "phase": 1,
		"desc": "Furniture, cooking supplies and building materials. Higher levels stock more."},
	"tavern":     {"name": "Recruitment Tavern", "size": Vector2i(3, 3), "th": 1, "phase": 1,
		"desc": "Summon crew. Upgrades add conveniences (daily ticket, cheaper 10-pull), never better odds."},
	"guild":      {"name": "Adventurers' Guild", "size": Vector2i(3, 3), "th": 3, "phase": 1,
		"desc": "Bounties and tougher battles. Each level opens harder encounters.",
		"build": {"coins": 1500, "mats": 15}},
	"blacksmith": {"name": "Blacksmith", "size": Vector2i(3, 3), "th": 2, "phase": 2,
		"desc": "Forge weapons and combat equipment."},
	"farm":       {"name": "Farm & Garden", "size": Vector2i(4, 3), "th": 2, "phase": 2,
		"desc": "Grows ingredients and magical herbs for the café."},
	"alchemy":    {"name": "Alchemy Workshop", "size": Vector2i(3, 3), "th": 4, "phase": 3,
		"desc": "Potions, food enhancements and upgrade materials."},
}
## Requirements to RAISE the Town Hall to the given level.
const TH_REQUIREMENTS := {
	2: {"coins": 800, "mats": 10, "facilities": {"cafe": 1}, "served": 30, "clear": ""},
	3: {"coins": 5000, "mats": 30, "facilities": {"cafe": 2, "shop": 2}, "served": 100, "clear": "sweet_trouble"},
	4: {"coins": 12000, "mats": 60, "facilities": {"cafe": 3, "tavern": 2, "guild": 2}, "served": 250,
		"clear": "kitchen_haunt"},
	5: {"coins": 25000, "mats": 120, "facilities": {"cafe": 4, "shop": 3, "guild": 3}, "served": 500,
		"clear": "sugar_golem"},
}
const MATS_PRICE := 45                        ## coins per Building Material at the General Shop

## Packing a battle meal costs this many times the dish price.
const MEAL_COST_MULT := 2

var coins := 50
var gems := 300
var rep_level := 1
var rep_xp := 0
var unlocked: Array = ["coffee", "croissant", "cookies"]
var staff: Dictionary = {}           # key -> {level, xp, role, mastery:{job:xp}, bond}
var served_total := 0
var day := 1
var placed: Array = []        # [{item, c, r, rot 0..3}]
var ship: Dictionary = {}       # {deck: [row strings], cabin: [c, r, w, h], gangway: [c, r]}
var inventory: Dictionary = {}  # item -> count owned but not placed
var meals: Array = []           # packed battle meals [{food, tier}] (cooked by the café kitchen)
var tickets := 0                # summon tickets (1 ticket = 1 pull)
var materials: Dictionary = {}  # material -> count
var cleared: Dictionary = {}    # encounter id -> victories
## Island town. th = Town Hall level (single source); cafe = ship café level.
## buildings: [{id, x, y, level}] footprints on the island grid.
var town: Dictionary = {}
var battle_hp: Dictionary = {}
## Airship progress: fuel, hull, engine condition (0-100), upgrade levels and
## crew stations (travel-shift assignments, separate from café roles).
var airship: Dictionary = {}
var battle_party: Array = []   ## last battle team, reused for voyage ambushes  # crew key -> HP ratio carried between battles (reset each new day)


func _ready() -> void:
	_setup_font()
	if "--test-save" in OS.get_cmdline_user_args():
		save_path = TEST_SAVE_PATH
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if not load_game():
		new_game()
	# starter waiter joins once his art exists (older saves included)
	if not staff.has("leo") and sheet_exists("leo"):
		staff["leo"] = new_member("Waiter")


func new_game() -> void:
	coins = 50
	gems = 300
	rep_level = 1
	rep_xp = 0
	unlocked = ["coffee", "croissant", "cookies"]
	staff = {"hana": new_member("Chef")}
	if sheet_exists("leo"):
		staff["leo"] = new_member("Waiter")
	served_total = 0
	day = 1
	ship = default_ship()
	placed = default_layout(2)
	inventory = {}
	meals = []
	tickets = 0
	materials = {}
	cleared = {}
	battle_hp = {}
	town = default_town()
	airship = default_airship()
	battle_party = []


## Game-wide pixel fonts (Pixel Operator, CC0, Jayvee Enaguas). Body text is
## always drawn at its native 8 px and titles at the 16 px cut, so every glyph
## lands on whole pixels whatever font size a control asks for.
var title_font: FontFile


func _pixel_font(path: String, px: int) -> FontFile:
	var f := load(path) as FontFile
	if f == null:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.fixed_size = px
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_DISABLE
	return f


func _setup_font() -> void:
	title_font = _pixel_font("res://assets/fonts/PixelOperator.ttf", 16)
	var f := _pixel_font("res://assets/fonts/PixelOperator8.ttf", 8)
	if f == null:
		return
	ThemeDB.fallback_font = f
	ThemeDB.fallback_font_size = 8
	ThemeDB.get_default_theme().default_font = f
	ThemeDB.get_default_theme().default_font_size = 8


## A crew member's permanent record. mastery (job -> XP) and bond are
## extension points: mastery grows from café work, bond is reserved for
## interactions / combo skills.
func new_member(role: String) -> Dictionary:
	return {"level": 1, "xp": 0, "role": role, "mastery": {}, "bond": 0}


func sheet_exists(key: String) -> bool:
	return ResourceLoader.exists("res://assets/chars/%s.png" % STAFF[key]["sheet"])


func available_pool(rarity: String) -> Array:
	var out: Array = []
	for k in STAFF:
		if STAFF[k]["rarity"] == rarity and sheet_exists(k):
			out.append(k)
	return out


func roll_rarity(min_sr: bool = false) -> String:
	var r := randf()
	if r < RATES["SSR"] and not available_pool("SSR").is_empty():
		return "SSR"
	if (r < RATES["SSR"] + RATES["SR"] or min_sr) and not available_pool("SR").is_empty():
		return "SR"
	return "R" if not available_pool("R").is_empty() else "SR"


## Returns [{key, new:bool, level:int}] or [] if not enough gems.
func pull(count: int) -> Array:
	var cost := pull10_cost() if count == 10 else PULL_COST * count
	if gems < cost:
		return []
	gems -= cost
	var results: Array = []
	for i in count:
		var rarity := roll_rarity(count == 10 and i == count - 1)
		var pool := available_pool(rarity)
		var key: String = pool[randi() % pool.size()]
		var is_new := not staff.has(key)
		if is_new:
			staff[key] = new_member(STAFF[key]["job"])
		else:  # duplicate: one level up
			staff[key]["level"] = min(int(staff[key]["level"]) + 1, MAX_LEVEL)
		results.append({"key": key, "new": is_new, "level": staff[key]["level"]})
	changed.emit()
	save_game()
	return results


## Core stat with level growth (rarity sets the growth rate). Café work AND
## combat both read this, so every level-up helps both.
func stat(key: String, s: String) -> float:
	var base: float = STAFF[key]["stats"][s]
	var lv: int = staff[key]["level"]
	return base * (1.0 + GROWTH[STAFF[key]["rarity"]] * (lv - 1))


func level(key: String) -> int:
	return int(staff[key]["level"])


func xp_needed(lv: int) -> int:
	return 40 + lv * 30


## Grant XP; returns how many levels were gained.
func add_xp(key: String, amount: int) -> int:
	var m: Dictionary = staff[key]
	var gained := 0
	m["xp"] = int(m.get("xp", 0)) + amount
	while int(m["level"]) < MAX_LEVEL and int(m["xp"]) >= xp_needed(int(m["level"])):
		m["xp"] = int(m["xp"]) - xp_needed(int(m["level"]))
		m["level"] = int(m["level"]) + 1
		gained += 1
	if int(m["level"]) >= MAX_LEVEL:
		m["xp"] = 0
	changed.emit()
	return gained


## Combat stats derived from the five core stats + level.
func combat_stats(key: String) -> Dictionary:
	var lv := level(key)
	return {
		"hp": 80.0 + stat(key, "end") * 12.0 + lv * 8.0,
		"atk": 5.0 + stat(key, "tec") * 2.0 + lv,
		"def": 2.0 + stat(key, "end") * 0.5,
		"spd": 10.0 + stat(key, "agi"),
		"crit": 3.0 + stat(key, "foc") * 0.5,
		"heal": 4.0 + stat(key, "hos") * 2.0 + lv,
	}


## Job mastery (extension point): café tasks completed in a job.
func add_mastery(key: String, job: String, amount: int = 1) -> void:
	var m: Dictionary = staff[key].get("mastery", {})
	m[job] = int(m.get(job, 0)) + amount
	staff[key]["mastery"] = m


func mastery_level(key: String, job: String) -> int:
	return int(sqrt(float(staff[key].get("mastery", {}).get(job, 0)) / 10.0))


## The kitchen's best cook (highest TEC + FOC, preferring assigned Chefs).
func best_cook() -> String:
	var best := ""
	var best_s := -1.0
	for k in staff:
		var sc := stat(k, "tec") + stat(k, "foc") * 0.5 + (100.0 if staff[k]["role"] == "Chef" else 0.0)
		if sc > best_s:
			best_s = sc
			best = k
	return best


func meal_cost(food: String) -> int:
	return int(FOODS[food]["price"]) * MEAL_COST_MULT


## Pack a battle meal from an unlocked recipe; quality rolled by the best cook.
func pack_meal(food: String) -> Dictionary:
	if not food in unlocked or coins < meal_cost(food):
		return {}
	coins -= meal_cost(food)
	var cook := best_cook()
	var tier := roll_quality(cook, food, staff[cook]["role"], false)
	var meal := {"food": food, "tier": tier}
	meals.append(meal)
	changed.emit()
	save_game()
	return meal


## Remove one meal (exactly once) and save immediately.
func consume_meal(index: int) -> Dictionary:
	if index < 0 or index >= meals.size():
		return {}
	var meal: Dictionary = meals[index]
	meals.remove_at(index)
	save_game()
	return meal


func add_material(id: String, n: int = 1) -> void:
	materials[id] = int(materials.get(id, 0)) + n
	changed.emit()


func use_material(id: String) -> bool:
	if int(materials.get(id, 0)) <= 0:
		return false
	materials[id] = int(materials[id]) - 1
	if materials[id] <= 0:
		materials.erase(id)
	changed.emit()
	return true


# ------------------------------------------------------------------ airship
func default_airship() -> Dictionary:
	return {
		"fuel": 20, "hull": 100.0, "engine": 100.0,
		"upgrades": {"core": 1, "tank": 1, "hull": 1, "runes": 1, "hold": 1},
		"stations": {"pilot": "", "engineer": "", "quartermaster": ""},
		"voyages": 0,
	}


func fuel() -> int:
	return int(airship["fuel"])


func buy_fuel(n: int) -> bool:
	var room := int(ShipStats.stat("fuel_cap")) - fuel()
	n = mini(n, room)
	if n <= 0 or coins < n * ShipStats.FUEL_PRICE:
		return false
	coins -= n * ShipStats.FUEL_PRICE
	airship["fuel"] = fuel() + n
	changed.emit()
	save_game()
	return true


## Engineer refines Aether Shards into fuel.
func refine_shards() -> int:
	if int(materials.get("aether_shards", 0)) < ShipStats.SHARDS_PER_REFINE:
		return 0
	var room := int(ShipStats.stat("fuel_cap")) - fuel()
	var made := mini(ShipStats.refine_yield(), room)
	if made <= 0:
		return 0
	materials["aether_shards"] = int(materials["aether_shards"]) - ShipStats.SHARDS_PER_REFINE
	if materials["aether_shards"] <= 0:
		materials.erase("aether_shards")
	airship["fuel"] = fuel() + made
	changed.emit()
	save_game()
	return made


func repair_hull() -> bool:
	var missing := int(ceil(ShipStats.stat("hull") - float(airship["hull"])))
	if missing <= 0:
		return false
	var c := ShipStats.repair_cost(missing)
	if coins < int(c["coins"]) or mats() < int(c["mats"]):
		return false
	coins -= int(c["coins"])
	materials["build_mats"] = mats() - int(c["mats"])
	airship["hull"] = ShipStats.stat("hull")
	var eng := ShipStats.station_key("engineer")
	if eng != "":
		add_mastery(eng, "Engineer", 2)
	changed.emit()
	save_game()
	return true


func maintain_engine() -> bool:
	var cost := ShipStats.maintain_cost()
	if float(airship["engine"]) >= 100.0 or coins < cost:
		return false
	coins -= cost
	airship["engine"] = 100.0
	var eng := ShipStats.station_key("engineer")
	if eng != "":
		add_mastery(eng, "Engineer", 2)
	changed.emit()
	save_game()
	return true


func ship_upgrade_block(id: String) -> String:
	var lv := ShipStats.level(id)
	if lv >= ShipStats.data.max_upgrade:
		return "Max level."
	var c := ShipStats.data.upgrade_cost(lv + 1)
	if coins < int(c["coins"]) or mats() < int(c["mats"]):
		return "Needs %d coins and %d Building Materials." % [c["coins"], c["mats"]]
	return ""


func upgrade_ship(id: String) -> bool:
	if ship_upgrade_block(id) != "":
		return false
	var lv := ShipStats.level(id)
	var c := ShipStats.data.upgrade_cost(lv + 1)
	coins -= int(c["coins"])
	materials["build_mats"] = mats() - int(c["mats"])
	airship["upgrades"][id] = lv + 1
	if id == "hull":
		airship["hull"] = float(airship["hull"]) + float(ShipStats.data.upgrades["hull"]["gain"]["hull"])
	changed.emit()
	save_game()
	return true


func assign_station(st: String, key: String) -> void:
	for other in airship["stations"]:  # one station per crew member
		if airship["stations"][other] == key:
			airship["stations"][other] = ""
	airship["stations"][st] = key
	save_game()


# ------------------------------------------------------------------ town
func default_town() -> Dictionary:
	return {
		"th": 1, "cafe": 1, "expanded": false,
		"buildings": [
			{"id": "town_hall", "x": 10, "y": 9, "level": 1},
			{"id": "shop", "x": 6, "y": 15, "level": 1},
			{"id": "tavern", "x": 15, "y": 6, "level": 1},
		],
	}


func th_level() -> int:
	return int(town["th"])


## Level of a facility ("cafe" = the ship café); 0 if not built.
func facility_level(id: String) -> int:
	if id == "cafe":
		return int(town["cafe"])
	if id == "town_hall":
		return th_level()
	for b in town["buildings"]:
		if b["id"] == id:
			return int(b["level"])
	return 0


func building_entry(id: String) -> Dictionary:
	for b in town["buildings"]:
		if b["id"] == id:
			return b
	return {}


func mats() -> int:
	return int(materials.get("build_mats", 0))


## Coins + materials to raise a facility (not the Town Hall) to `to_level`.
func facility_cost(to_level: int) -> Dictionary:
	return {"coins": int(250 * pow(to_level, 1.7)), "mats": 4 * to_level}


## [{text, done}] checklist for the next Town Hall level (empty at max).
func th_checklist() -> Array:
	var next := th_level() + 1
	if not TH_REQUIREMENTS.has(next):
		return []
	var r: Dictionary = TH_REQUIREMENTS[next]
	var out: Array = []
	out.append({"text": "%d coins" % r["coins"], "done": coins >= int(r["coins"])})
	out.append({"text": "%d Building Materials" % r["mats"], "done": mats() >= int(r["mats"])})
	for f in r["facilities"]:
		var name: String = "Café (ship)" if f == "cafe" else BUILDINGS[f]["name"]
		out.append({"text": "%s Lv %d" % [name, r["facilities"][f]], "done": facility_level(f) >= int(r["facilities"][f])})
	out.append({"text": "Serve %d customers (%d)" % [r["served"], served_total], "done": served_total >= int(r["served"])})
	if r["clear"] != "":
		out.append({"text": "Win the battle: %s" % BattleDB.encounter(StringName(r["clear"])).display_name,
			"done": int(cleared.get(r["clear"], 0)) > 0})
	return out


func upgrade_town_hall() -> bool:
	var list := th_checklist()
	if list.is_empty():
		return false
	for item in list:
		if not item["done"]:
			return false
	var r: Dictionary = TH_REQUIREMENTS[th_level() + 1]
	coins -= int(r["coins"])
	materials["build_mats"] = mats() - int(r["mats"])
	town["th"] = th_level() + 1
	for b in town["buildings"]:
		if b["id"] == "town_hall":
			b["level"] = town["th"]
	if th_level() >= 5:
		town["expanded"] = true
	changed.emit()
	save_game()
	return true


## Why a facility can't be upgraded right now ("" = it can).
func facility_block(id: String) -> String:
	var lv := facility_level(id)
	if lv <= 0:
		return "Not built yet."
	if lv >= MAX_FACILITY_LEVEL:
		return "Max level."
	if lv >= th_level():
		return "Upgrade the Town Hall first (cap Lv %d)." % th_level()
	var c := facility_cost(lv + 1)
	if coins < int(c["coins"]) or mats() < int(c["mats"]):
		return "Needs %d coins and %d Building Materials." % [c["coins"], c["mats"]]
	return ""


func upgrade_facility(id: String) -> bool:
	if facility_block(id) != "":
		return false
	var c := facility_cost(facility_level(id) + 1)
	coins -= int(c["coins"])
	materials["build_mats"] = mats() - int(c["mats"])
	if id == "cafe":
		town["cafe"] = int(town["cafe"]) + 1
	else:
		building_entry(id)["level"] = int(building_entry(id)["level"]) + 1
	changed.emit()
	save_game()
	return true


func build_block(id: String) -> String:
	var d: Dictionary = BUILDINGS[id]
	if facility_level(id) > 0:
		return "Already built."
	if int(d["phase"]) > 1:
		return "Coming in a later update."
	if th_level() < int(d["th"]):
		return "Needs Town Hall Lv %d." % d["th"]
	var c: Dictionary = d.get("build", {"coins": 0, "mats": 0})
	if coins < int(c["coins"]) or mats() < int(c["mats"]):
		return "Needs %d coins and %d Building Materials." % [c["coins"], c["mats"]]
	return ""


func build(id: String, x: int, y: int) -> bool:
	if build_block(id) != "":
		return false
	var c: Dictionary = BUILDINGS[id].get("build", {"coins": 0, "mats": 0})
	coins -= int(c["coins"])
	materials["build_mats"] = mats() - int(c["mats"])
	town["buildings"].append({"id": id, "x": x, "y": y, "level": 1})
	changed.emit()
	save_game()
	return true


func buildable_area() -> Rect2i:
	return EXPANDED_AREA if town.get("expanded", false) else CORE_AREA


## General Shop: buy Building Materials (shop level gives a discount).
func mats_price() -> int:
	return int(MATS_PRICE * (1.0 - 0.05 * (facility_level("shop") - 1)))


func buy_mats(n: int) -> bool:
	if coins < mats_price() * n:
		return false
	coins -= mats_price() * n
	add_material("build_mats", n)
	save_game()
	return true


## Café (ship) level: +10% dish prices per level above 1.
func cafe_price_mult() -> float:
	return 1.0 + 0.1 * (facility_level("cafe") - 1)


## Recruitment Tavern conveniences (never better odds).
func pull10_cost() -> int:
	return PULL10_COST - (50 if facility_level("tavern") >= 3 else 0)


## Called when a new café day starts.
func new_day() -> Array[String]:
	var notes: Array[String] = []
	rest_crew()
	if facility_level("tavern") >= 2:
		tickets += 1
		notes.append("The Tavern left you a free Summon Ticket.")
	return notes


## HP a crew member starts a battle with. Knocked-out crew limp in at 25%.
func battle_hp_ratio(key: String) -> float:
	return clampf(float(battle_hp.get(key, 1.0)), 0.25, 1.0)


## A night's rest: everyone back to full for the next day's battles.
func rest_crew() -> void:
	battle_hp.clear()


## One summon using a ticket instead of gems.
func pull_ticket() -> Array:
	if tickets <= 0:
		return []
	tickets -= 1
	gems += PULL_COST
	return pull(1)


## Speed multiplier from AGI (10 AGI = 1.0x).
func agi_mult(key: String) -> float:
	return 0.6 + stat(key, "agi") * 0.04


func max_stamina(key: String) -> float:
	return 60.0 + stat(key, "end") * 4.0


## Stamina lost per second of work; END makes it slower.
func stamina_drain(key: String) -> float:
	return maxf(0.35, 1.3 - stat(key, "end") * 0.04)


## 0 (easy) .. 6 (ramen): complex recipes punish low FOC.
func difficulty(food: String) -> int:
	return int(FOODS[food]["unlock"] / 150)


## Roll a dish's star tier. Chefs: TEC + FOC. Baristas making drinks: TEC + HOS.
func roll_quality(key: String, food: String, job: String, tired: bool) -> String:
	var tec := stat(key, "tec")
	var foc := stat(key, "foc")
	var second := stat(key, "hos") if (job == "Barista" and food in DRINKS) else foc
	var diff := difficulty(food)
	var burn := clampf(0.22 - foc * 0.011 + diff * 0.02 + (0.1 if tired else 0.0), 0.02, 0.45)
	if randf() < burn:
		return "black"
	var s := tec * 0.8 + second * 0.3 - diff + randf_range(-5.0, 5.0) - (3.0 if tired else 0.0)
	if s < 9.0:
		return "plain"
	if s < 14.0:
		return "bronze"
	if s < 19.0:
		return "silver"
	if s < 24.0:
		return "gold"
	return "diamond"


func add_coins(n: int) -> void:
	coins += n
	changed.emit()


func add_rep(n: int) -> void:
	rep_xp += n
	while rep_xp >= rep_needed():
		rep_xp -= rep_needed()
		rep_level += 1
		gems += 50
	changed.emit()


func rep_needed() -> int:
	return 8 + rep_level * 4


func unlock_food(key: String) -> bool:
	var cost: int = FOODS[key]["unlock"]
	if coins < cost or key in unlocked:
		return false
	coins -= cost
	unlocked.append(key)
	changed.emit()
	save_game()
	return true


## Starting café. `tables` (2-4) keeps tables bought in pre-layout saves.
func default_ship() -> Dictionary:
	return {"deck": SHIP_TEMPLATE.duplicate(), "cabin": SHIP_CABIN.duplicate(), "gangway": SHIP_GANGWAY.duplicate(),
		"doors": SHIP_CABIN_DOORS.duplicate(true)}


## Starting café on the ship. Kitchen + one table in the cabin, `tables`
## (2-4) more tables out on the open deck.
## Starting café on the ship, laid out like a real café:
##  - café room (cabin) with the kitchen line on its back wall, a work aisle,
##    a counter with the pastry case facing the guests, and a table by the door,
##  - outdoor seating on the deck: a bar along the back railing and round tables,
##  - plants, lamps and a menu board for atmosphere.
## rot = the way an item faces: 0 = SE (+c), 1 = SW (+r), 2 = NW, 3 = NE.
func default_layout(_tables: int = 0) -> Array:
	var out: Array = []
	var add := func(item: String, c: int, r: int, rot: int) -> void:
		out.append({"item": item, "c": c, "r": r, "rot": rot})
	# kitchen line against the back wall, facing into the room
	add.call("fridge", 0, 0, 1)
	add.call("stove", 1, 0, 1)
	add.call("espresso", 2, 0, 1)
	add.call("sink", 3, 0, 1)
	add.call("dish_rack", 4, 0, 1)
	add.call("dish_tub", 5, 0, 1)
	add.call("bookshelf", 6, 0, 1)
	add.call("plant", 7, 0, 1)
	add.call("chalkboard", 0, 1, 0)
	add.call("plant", 0, 2, 0)
	add.call("fern", 0, 3, 0)
	# counter row facing the guests; staff work behind it (aisle r = 1), gap at c = 5
	add.call("service_counter", 1, 2, 1)
	add.call("prep_counter", 2, 2, 1)
	add.call("display", 3, 2, 1)
	add.call("prep_counter", 4, 2, 1)
	# a table inside the café room
	add.call("table_round", 7, 2, 0)
	add.call("chair", 6, 2, 0)
	add.call("chair", 7, 1, 1)
	# bar along the deck's back railing (guests look out at the sky); aisle at r = 2-3
	for c in [8, 9, 10, 11]:
		add.call("table_square", c, 0, 0)
		add.call("chair", c, 1, 3)
	# round tables on the open deck, leaving walkways from the gangway
	add.call("table_round", 10, 4, 0)
	add.call("chair", 9, 4, 0)
	add.call("chair", 10, 5, 3)
	add.call("table_round", 1, 4, 0)
	add.call("chair", 2, 4, 2)
	add.call("chair", 1, 5, 3)
	_add_cabin_walls(out)
	add.call("lamp", 11, 3, 0)
	add.call("plant", 11, 5, 0)
	add.call("fern", 0, 5, 0)
	add.call("chalkboard", 5, 5, 1)
	return out


## Café-room walls as wall items: back walls inside, front walls with a doorway.
## rot = which edge of the tile: 0 = SE, 1 = SW (front), 2 = NW, 3 = NE (back).
func _add_cabin_walls(out: Array) -> void:
	var cab: Array = SHIP_CABIN
	var back := ["wall_window", "wall_plain", "wall_shelf", "wall_plain", "wall_art", "wall_window", "wall_plain", "wall_shelf"]
	for i in int(cab[2]):
		out.append({"item": back[i % back.size()], "c": int(cab[0]) + i, "r": int(cab[1]), "rot": 3})
	for i in int(cab[3]):
		out.append({"item": "wall_window" if i % 2 == 0 else "wall_plain", "c": int(cab[0]), "r": int(cab[1]) + i, "rot": 2})
	var doors := {}
	for d in SHIP_CABIN_DOORS:
		doors[Vector2i(int(d[0]), int(d[1]))] = true
	var fr := int(cab[1]) + int(cab[3]) - 1
	for i in int(cab[2]):
		var t := Vector2i(int(cab[0]) + i, fr)
		out.append({"item": "wall_door" if doors.has(t) else ("wall_window" if i % 3 == 1 else "wall_plain"),
			"c": t.x, "r": t.y, "rot": 1})
	var fc := int(cab[0]) + int(cab[2]) - 1
	for i in int(cab[3]):
		out.append({"item": "wall_window" if i % 2 == 1 else "wall_plain", "c": fc, "r": int(cab[1]) + i, "rot": 0})


## Moving from the old one-room café to the ship: rebuild the starting
## layout and put any furniture beyond it into storage.
func migrate_to_ship(old_placed: Array) -> void:
	var counts := {}
	var tables := 0
	for p in old_placed:
		counts[p["item"]] = int(counts.get(p["item"], 0)) + 1
		if ITEMS[p["item"]]["kind"] == "table":
			tables += 1
	placed = default_layout(clampi(tables, 2, 4))
	for p in placed:
		counts[p["item"]] = int(counts.get(p["item"], 0)) - 1
	for item in counts:
		if counts[item] > 0:
			inventory[item] = int(inventory.get(item, 0)) + counts[item]


func item_tex_path(item: String) -> String:
	return "res://assets/%s.png" % ITEMS[item].get("tex", "furniture/" + item)


func buy_item(item: String) -> bool:
	var cost: int = ITEMS[item]["cost"]
	if coins < cost:
		return false
	coins -= cost
	inventory[item] = int(inventory.get(item, 0)) + 1
	changed.emit()
	save_game()
	return true


func take_from_inventory(item: String) -> bool:
	if int(inventory.get(item, 0)) <= 0:
		return false
	inventory[item] = int(inventory[item]) - 1
	if inventory[item] <= 0:
		inventory.erase(item)
	return true


func store_item(item: String) -> void:
	inventory[item] = int(inventory.get(item, 0)) + 1


## Ambience from placed decor: +2% patience and +1% tips per point.
func ambience() -> int:
	var a := 0
	for p in placed:
		a += int(ITEMS[p["item"]].get("ambience", 0))
	return a


func trade_gems() -> bool:
	if coins < GEM_TRADE["coins"]:
		return false
	coins -= GEM_TRADE["coins"]
	gems += GEM_TRADE["gems"]
	changed.emit()
	return true


func save_game() -> void:
	var data := {
		"coins": coins, "gems": gems, "rep_level": rep_level, "rep_xp": rep_xp,
		"unlocked": unlocked, "staff": staff,
		"served_total": served_total, "version": 8, "ship": ship,
		"day": day, "placed": placed, "inventory": inventory,
		"meals": meals, "tickets": tickets, "materials": materials, "cleared": cleared,
		"battle_hp": battle_hp, "town": town, "airship": airship, "battle_party": battle_party,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	coins = int(d.get("coins", 50))
	gems = int(d.get("gems", 300))
	rep_level = int(d.get("rep_level", 1))
	rep_xp = int(d.get("rep_xp", 0))
	unlocked = d.get("unlocked", ["coffee"])
	served_total = int(d.get("served_total", 0))
	day = int(d.get("day", 1))
	placed = []
	for p in d.get("placed", []):
		if ITEMS.has(p.get("item", "")):
			placed.append({"item": p["item"], "c": int(p["c"]), "r": int(p["r"]), "rot": int(p.get("rot", 0)) % 4})
	if placed.is_empty():  # pre-layout save: rebuild with the tables bought back then
		placed = default_layout(int(d.get("tables_owned", 2)))
	ship = d.get("ship", {})
	if ship.is_empty() or int(d.get("version", 1)) < 7:  # cabin became the café room
		ship = default_ship()
	meals = []
	for m in d.get("meals", []):
		if FOODS.has(m.get("food", "")) and str(m.get("tier", "")) in TIERS:
			meals.append({"food": m["food"], "tier": m["tier"]})
	tickets = int(d.get("tickets", 0))
	materials = {}
	var mats: Dictionary = d.get("materials", {})
	for k in mats:
		if MATERIALS.has(k):
			materials[k] = int(mats[k])
	cleared = d.get("cleared", {})
	battle_hp = d.get("battle_hp", {})
	airship = default_airship()
	var ap: Dictionary = d.get("airship", {})
	for k in ["fuel", "hull", "engine", "voyages"]:
		if ap.has(k):
			airship[k] = ap[k]
	for k in ap.get("upgrades", {}):
		if airship["upgrades"].has(k):
			airship["upgrades"][k] = clampi(int(ap["upgrades"][k]), 1, 5)
	for k in ap.get("stations", {}):
		if airship["stations"].has(k) and str(ap["stations"][k]) in d.get("staff", {}):
			airship["stations"][k] = str(ap["stations"][k])
	battle_party = d.get("battle_party", [])
	town = default_town()
	var tw: Dictionary = d.get("town", {})
	if not tw.is_empty():
		town["th"] = clampi(int(tw.get("th", 1)), 1, 5)
		town["cafe"] = clampi(int(tw.get("cafe", 1)), 1, MAX_FACILITY_LEVEL)
		town["expanded"] = bool(tw.get("expanded", false))
		var bl: Array = []
		for b in tw.get("buildings", []):
			if BUILDINGS.has(b.get("id", "")):
				bl.append({"id": b["id"], "x": int(b["x"]), "y": int(b["y"]), "level": int(b.get("level", 1))})
		if not bl.is_empty():
			town["buildings"] = bl
	inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		if ITEMS.has(k):
			inventory[k] = int(inv[k])
	staff = {}
	var s: Dictionary = d.get("staff", {})
	for k in s:
		if STAFF.has(k):
			var role := str(s[k]["role"])
			# v1 saves parked new pulls on Rest and only knew Chef/Waiter
			if role not in JOBS or (int(d.get("version", 1)) < 2 and role == "Rest"):
				role = STAFF[k]["job"]
			var m := new_member(role)
			m["level"] = clampi(int(s[k]["level"]), 1, MAX_LEVEL)
			m["xp"] = int(s[k].get("xp", 0))
			m["mastery"] = s[k].get("mastery", {})
			m["bond"] = int(s[k].get("bond", 0))
			staff[k] = m
	if staff.is_empty():
		staff = {"hana": new_member("Chef")}
	if int(d.get("version", 1)) < 7:  # re-arrange into the café layout (extras go to storage)
		migrate_to_ship(placed)
	if int(d.get("version", 1)) < 8:  # walls became placeable items
		var has_walls := false
		for p in placed:
			has_walls = has_walls or ITEMS[p["item"]]["kind"] == "wall"
		if not has_walls:
			_add_cabin_walls(placed)
	_store_off_deck()
	return true


## Anything standing where there is no deck goes back into storage.
func _store_off_deck() -> void:
	var rows: Array = ship["deck"]
	var keep: Array = []
	for p in placed:
		var r := int(p["r"])
		var c := int(p["c"])
		if r >= 0 and r < rows.size() and c >= 0 and c < str(rows[r]).length() and str(rows[r])[c] == "X":
			keep.append(p)
		else:
			inventory[p["item"]] = int(inventory.get(p["item"], 0)) + 1
	placed = keep
