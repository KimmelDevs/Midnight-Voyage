extends Node
## Global game state: data tables, economy, gacha, save/load.

signal changed

const SAVE_PATH := "user://cafe_save.json"

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

## Gacha pool. cook = cooking speed multiplier, serve = walk speed multiplier,
## charm = tip fraction. Mostly humans; a couple of rare supernaturals.
const STAFF := {
	"hana":      {"name": "Hana",      "title": "Apprentice Chef",       "rarity": "SR",  "sheet": "chef",      "cook": 1.3, "serve": 1.0, "charm": 0.05},
	"leo":       {"name": "Leo",       "title": "Rookie Waiter",         "rarity": "R",   "sheet": "leo",       "cook": 0.9, "serve": 1.2, "charm": 0.05},
	"mira":      {"name": "Mira",      "title": "Barista",               "rarity": "R",   "sheet": "mira",      "cook": 1.15, "serve": 1.05, "charm": 0.08},
	"kaito":     {"name": "Kaito",     "title": "Swordsman Pâtissier",   "rarity": "SR",  "sheet": "kaito",     "cook": 1.5, "serve": 1.15, "charm": 0.06},
	"seraphine": {"name": "Seraphine", "title": "Royal Mage Hostess",    "rarity": "SSR", "sheet": "seraphine", "cook": 1.2, "serve": 1.4, "charm": 0.25},
	"selene":    {"name": "Selene",    "title": "Vampire Bartender",     "rarity": "SSR", "sheet": "selene",    "cook": 1.7, "serve": 1.25, "charm": 0.18},
}
const RATES := {"SSR": 0.05, "SR": 0.20, "R": 0.75}
const PULL_COST := 100
const PULL10_COST := 900

const TABLE_COSTS := [0, 0, 250, 600]   # tables 1-2 free, 3-4 bought
const GEM_TRADE := {"coins": 300, "gems": 50}

var coins := 50
var gems := 300
var rep_level := 1
var rep_xp := 0
var unlocked: Array = ["coffee", "croissant", "cookies"]
var staff: Dictionary = {}           # key -> {level:int, role:String}
var tables_owned := 2
var served_total := 0


func _ready() -> void:
	if not load_game():
		new_game()
	# starter waiter joins once his art exists (older saves included)
	if not staff.has("leo") and sheet_exists("leo"):
		staff["leo"] = {"level": 1, "role": "Waiter"}


func new_game() -> void:
	coins = 50
	gems = 300
	rep_level = 1
	rep_xp = 0
	unlocked = ["coffee", "croissant", "cookies"]
	staff = {"hana": {"level": 1, "role": "Chef"}}
	if sheet_exists("leo"):
		staff["leo"] = {"level": 1, "role": "Waiter"}
	tables_owned = 2
	served_total = 0


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
			staff[key] = {"level": 1, "role": "Rest"}
		else:
			staff[key]["level"] = min(int(staff[key]["level"]) + 1, 10)
		results.append({"key": key, "new": is_new, "level": staff[key]["level"]})
	changed.emit()
	save_game()
	return results


func stat(key: String, s: String) -> float:
	var base: float = STAFF[key][s]
	var lv: int = staff[key]["level"]
	if s == "charm":
		return base + 0.02 * (lv - 1)
	return base * (1.0 + 0.08 * (lv - 1))


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


func buy_table() -> bool:
	if tables_owned >= TABLE_COSTS.size():
		return false
	var cost: int = TABLE_COSTS[tables_owned]
	if coins < cost:
		return false
	coins -= cost
	tables_owned += 1
	changed.emit()
	save_game()
	return true


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
		"unlocked": unlocked, "staff": staff, "tables_owned": tables_owned,
		"served_total": served_total,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	coins = int(d.get("coins", 50))
	gems = int(d.get("gems", 300))
	rep_level = int(d.get("rep_level", 1))
	rep_xp = int(d.get("rep_xp", 0))
	unlocked = d.get("unlocked", ["coffee"])
	tables_owned = int(d.get("tables_owned", 2))
	served_total = int(d.get("served_total", 0))
	staff = {}
	var s: Dictionary = d.get("staff", {})
	for k in s:
		if STAFF.has(k):
			staff[k] = {"level": int(s[k]["level"]), "role": str(s[k]["role"])}
	if staff.is_empty():
		staff = {"hana": {"level": 1, "role": "Chef"}}
	return true
