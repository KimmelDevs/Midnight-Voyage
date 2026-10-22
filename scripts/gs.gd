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
	"chair":           {"name": "Chair",           "kind": "chair",    "cost": 40, "back_flip": true},
	"bookshelf":       {"name": "Bookshelf",       "kind": "deco",     "cost": 110, "ambience": 3},
	"lamp":            {"name": "Standing Lamp",   "kind": "deco",     "cost": 70, "ambience": 2},
	"fern":            {"name": "Potted Fern",     "kind": "deco",     "cost": 45, "ambience": 2},
	"plant":           {"name": "Flower Pot",      "kind": "deco",     "cost": 45, "ambience": 2, "tex": "cafe/plant"},
	"display":         {"name": "Pastry Display",  "kind": "deco",     "cost": 150, "ambience": 4, "tex": "cafe/display"},
	"chalkboard":      {"name": "Menu Board",      "kind": "deco",     "cost": 60, "ambience": 2},
	"trash":           {"name": "Trash Bin",       "kind": "deco",     "cost": 25, "ambience": 0},
	"rug":             {"name": "Rug",             "kind": "rug",      "cost": 50, "ambience": 1},
}

const DAY_LENGTH := 150.0   # seconds the café is open each day

## ---- shared progression (one source of truth for café AND battle) ----
const MAX_LEVEL := 30
## Per-level growth of the five core stats; rarity = specialisation/potential.
const GROWTH := {"R": 0.06, "SR": 0.065, "SSR": 0.07}
## Materials won in battle. golden_sugar: next dish cooked gains +1 star tier.
## training_manual: +120 XP for one character (Staff panel).
const MATERIALS := {
	"golden_sugar": {"name": "Golden Sugar", "desc": "Next dish cooked is one star better"},
	"training_manual": {"name": "Training Manual", "desc": "+120 XP to one character"},
}
const MANUAL_XP := 120
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
var inventory: Dictionary = {}  # item -> count owned but not placed
var meals: Array = []           # packed battle meals [{food, tier}] (cooked by the café kitchen)
var tickets := 0                # summon tickets (1 ticket = 1 pull)
var materials: Dictionary = {}  # material -> count
var cleared: Dictionary = {}    # encounter id -> victories
var battle_hp: Dictionary = {}  # crew key -> HP ratio carried between battles (reset each new day)


func _ready() -> void:
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
	placed = default_layout(2)
	inventory = {}
	meals = []
	tickets = 0
	materials = {}
	cleared = {}
	battle_hp = {}


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
	var cost := PULL10_COST if count == 10 else PULL_COST * count
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
func default_layout(tables: int) -> Array:
	var out: Array = []
	for e in [["stove", 0, 1], ["espresso", 0, 2], ["service_counter", 0, 3], ["sink", 0, 4],
			["dish_rack", 0, 5], ["fridge", 1, 0], ["plant", 6, 5], ["lamp", 4, 0]]:
		out.append({"item": e[0], "c": e[1], "r": e[2], "rot": 0})
	var spots := [Vector2i(3, 2), Vector2i(5, 2), Vector2i(3, 4), Vector2i(5, 4)]
	for i in clampi(tables, 2, 4):
		var t: Vector2i = spots[i]
		out.append({"item": "table_round", "c": t.x, "r": t.y, "rot": 0})
		out.append({"item": "chair", "c": t.x - 1, "r": t.y, "rot": 0})   # faces SE
		out.append({"item": "chair", "c": t.x, "r": t.y - 1, "rot": 1})   # faces SW
	return out


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
		"served_total": served_total, "version": 3,
		"day": day, "placed": placed, "inventory": inventory,
		"meals": meals, "tickets": tickets, "materials": materials, "cleared": cleared,
		"battle_hp": battle_hp,
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
	return true
