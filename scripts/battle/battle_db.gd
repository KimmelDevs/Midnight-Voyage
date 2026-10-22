class_name BattleDB
extends RefCounted
## Registry of battle content: character kits, enemies, encounters and meal
## buffs. Add a character kit / enemy / encounter here; the BattleManager
## never needs to change.

static var _kits := {}
static var _enemies := {}
static var _encounters: Array[EncounterData] = []


static func _a(id: StringName, name: String, cd: float, effects: Array, desc := "",
		magic := false, col := Color.WHITE) -> AbilityData:
	return AbilityData.make(id, name, cd, effects, desc, magic, col)


# ------------------------------------------------------------------ crew kits
## Staff key -> {basic, skill}. Keys match GS.STAFF.
static func kit(key: String) -> Dictionary:
	if _kits.is_empty():
		_build_kits()
	return _kits.get(key, _kits["_default"])


static func _build_kits() -> void:
	var hit := [{"type": "damage", "power": 1.0, "target": "enemy"}]
	_kits["_default"] = {
		"basic": _a(&"strike", "Strike", 0, hit),
		"skill": null,
	}
	_kits["hana"] = {
		"basic": _a(&"cleaver_chop", "Cleaver Chop", 0, hit, "", false, Color("ffb070")),
		"skill": _a(&"sizzling_slam", "Sizzling Slam", 7.0, [
			{"type": "damage", "power": 1.8, "target": "enemy"},
			{"type": "dot", "power": 0.25, "duration": 4.0, "tag": "Burn", "target": "enemy"},
		], "Heavy cleaver hit that sets the target sizzling (burn).", false, Color("ff8a3c")),
	}
	_kits["leo"] = {
		"basic": _a(&"tray_strike", "Tray Strike", 0, hit, "", false, Color("dfe6f2")),
		"skill": _a(&"silver_rush", "Silver Rush", 9.0, [
			{"type": "status", "stat": "spd", "amount": 0.35, "duration": 6.0, "tag": "Haste", "target": "ally_all"},
		], "Whole team attacks 35% faster for 6s.", false, Color("bfe0ff")),
	}
	_kits["mira"] = {
		"basic": _a(&"coffee_splash", "Coffee Splash", 0, hit, "", true, Color("c58b5a")),
		"skill": _a(&"restorative_brew", "Restorative Brew", 6.0, [
			{"type": "heal", "power": 2.2, "target": "ally_lowest"},
			{"type": "hot", "power": 0.25, "duration": 4.0, "tag": "Warm", "target": "ally_lowest"},
		], "Heals the most injured ally, then keeps them warm (regen).", true, Color("8ff0a0")),
	}
	_kits["kaito"] = {
		"basic": _a(&"katana_slash", "Katana Slash", 0, [{"type": "damage", "power": 1.1, "target": "enemy"}],
			"", false, Color("e8f0ff")),
		"skill": _a(&"swift_slice", "Swift Slice", 7.0, [
			{"type": "damage", "power": 2.3, "crit_bonus": 40.0, "target": "enemy_lowest"},
		], "Finishing strike on the weakest enemy, +40% crit chance.", false, Color("ffffff")),
	}
	_kits["seraphine"] = {
		"basic": _a(&"star_bolt", "Star Bolt", 0, hit, "", true, Color("f6e27a")),
		"skill": _a(&"royal_blessing", "Royal Blessing", 10.0, [
			{"type": "shield", "power": 1.6, "target": "ally_all"},
			{"type": "status", "stat": "def", "amount": 0.2, "duration": 6.0, "tag": "Blessed", "target": "ally_all"},
		], "Shields every ally and raises their defense.", true, Color("f6d0ff")),
	}
	_kits["selene"] = {
		"basic": _a(&"crimson_strike", "Crimson Strike", 0, [
			{"type": "damage", "power": 1.0, "target": "enemy"},
			{"type": "drain", "ratio": 0.15, "target": "self"},
		], "", false, Color("ff5a6e")),
		"skill": _a(&"crimson_toast", "Crimson Toast", 8.0, [
			{"type": "damage", "power": 1.9, "target": "enemy"},
			{"type": "drain", "ratio": 0.6, "target": "ally_lowest"},
		], "Drains an enemy and pours the life into the weakest ally.", true, Color("ff3355")),
	}


# ------------------------------------------------------------------ enemies
static func enemy(id: StringName) -> EnemyData:
	if _enemies.is_empty():
		_build_enemies()
	return _enemies[id]


static func _e(id: StringName, name: String, sprite: String, base: Dictionary, basic: AbilityData,
		skill: AbilityData, xp: int, coins: int, boss := false) -> EnemyData:
	var e := EnemyData.new()
	e.id = id
	e.display_name = name
	e.sprite = sprite
	e.base = base
	e.basic = basic
	e.skill = skill
	e.xp = xp
	e.coins = coins
	e.boss = boss
	_enemies[id] = e
	return e


static func _build_enemies() -> void:
	var hit := [{"type": "damage", "power": 1.0, "target": "enemy"}]
	_e(&"sugar_imp", "Sugar Imp", "res://assets/enemies/sugar_imp.png",
		{"hp": 220.0, "atk": 18.0, "def": 3.0, "spd": 26.0, "crit": 8.0},
		_a(&"candy_poke", "Candy Poke", 0, hit, "", false, Color("ff9ad0")),
		_a(&"sugar_rush", "Sugar Rush", 8.0, [
			{"type": "status", "stat": "spd", "amount": 0.4, "duration": 5.0, "tag": "Sugar Rush", "target": "self"},
			{"type": "damage", "power": 1.2, "target": "enemy"},
		], "Speeds itself up and pokes.", false, Color("ff9ad0")),
		14, 10)
	_e(&"flour_slime", "Flour Slime", "res://assets/enemies/flour_slime.png",
		{"hp": 480.0, "atk": 12.0, "def": 8.0, "spd": 12.0, "crit": 3.0},
		_a(&"dough_slap", "Dough Slap", 0, hit, "", false, Color("f4ecd8")),
		_a(&"doughy_wall", "Doughy Wall", 10.0, [
			{"type": "shield", "power": 3.0, "target": "self"},
			{"type": "status", "stat": "spd", "amount": -0.25, "duration": 5.0, "tag": "Sticky", "target": "enemy"},
		], "Shields itself and slows a foe.", false, Color("f4ecd8")),
		18, 14)
	_e(&"animated_teapot", "Animated Teapot", "res://assets/enemies/animated_teapot.png",
		{"hp": 260.0, "atk": 20.0, "def": 4.0, "spd": 16.0, "crit": 6.0},
		_a(&"tea_bolt", "Tea Bolt", 0, hit, "", true, Color("9fd8ff")),
		_a(&"scalding_steam", "Scalding Steam", 9.0, [
			{"type": "damage", "power": 0.7, "target": "enemy_all"},
		], "Steam hits every crew member.", true, Color("dff4ff")),
		18, 15)
	_e(&"cursed_kitchenware", "Cursed Kitchenware", "res://assets/enemies/cursed_kitchenware.png",
		{"hp": 360.0, "atk": 14.0, "def": 16.0, "spd": 13.0, "crit": 4.0},
		_a(&"ladle_bash", "Ladle Bash", 0, hit, "", false, Color("c9b0ff")),
		_a(&"clatter_guard", "Clatter Guard", 10.0, [
			{"type": "status", "stat": "def", "amount": 0.4, "duration": 6.0, "tag": "Guard", "target": "ally_all"},
		], "Raises its team's defense.", false, Color("c9b0ff")),
		20, 16)
	_e(&"royal_sugar_golem", "Royal Sugar Golem", "res://assets/enemies/royal_sugar_golem.png",
		{"hp": 1800.0, "atk": 34.0, "def": 10.0, "spd": 9.0, "crit": 5.0},
		_a(&"golem_smash", "Golem Smash", 0, [{"type": "damage", "power": 1.3, "target": "enemy"}],
			"", false, Color("ffcf6b")),
		_a(&"caramel_quake", "Caramel Quake", 11.0, [
			{"type": "damage", "power": 0.9, "target": "enemy_all"},
			{"type": "status", "stat": "spd", "amount": -0.3, "duration": 5.0, "tag": "Caramel", "target": "enemy_all"},
		], "Quake that hits and slows the whole crew.", false, Color("e8a050")),
		120, 120, true)


# ------------------------------------------------------------------ encounters
static func encounters() -> Array[EncounterData]:
	if _encounters.is_empty():
		_build_encounters()
	return _encounters


static func encounter(id: StringName) -> EncounterData:
	for e in encounters():
		if e.id == id:
			return e
	return null


static func _enc(id: StringName, name: String, desc: String, rec: int, enemies: Array,
		coins: int, xp: int, drops: Array, first: Array, recipe := false,
		boss := false) -> void:
	var e := EncounterData.new()
	e.id = id
	e.display_name = name
	e.description = desc
	e.recommended_level = rec
	e.enemies.assign(enemies)
	e.coins = coins
	e.xp = xp
	e.drops.assign(drops)
	e.first_clear.assign(first)
	e.unlock_recipe = recipe
	e.boss = boss
	_encounters.append(e)


static func _build_encounters() -> void:
	_enc(&"sweet_trouble", "Sweet Trouble", "Sugar imps raid the pantry with a floury friend.", 1,
		[{"id": &"flour_slime", "level": 1}, {"id": &"sugar_imp", "level": 1}, {"id": &"sugar_imp", "level": 1}],
		40, 30,
		[{"kind": "material", "id": "golden_sugar", "n": 1, "chance": 0.3}],
		[{"kind": "tickets", "n": 1}])
	_enc(&"kitchen_haunt", "Kitchen Haunting", "The cupboards rattle - something is brewing.", 3,
		[{"id": &"cursed_kitchenware", "level": 3}, {"id": &"animated_teapot", "level": 3}, {"id": &"sugar_imp", "level": 2}],
		70, 50,
		[{"kind": "material", "id": "training_manual", "n": 1, "chance": 0.35},
		 {"kind": "material", "id": "golden_sugar", "n": 1, "chance": 0.25}],
		[{"kind": "gems", "n": 50}])
	_enc(&"doughy_swamp", "Doughy Swamp", "Rising dough everywhere. Bring healing.", 5,
		[{"id": &"flour_slime", "level": 5}, {"id": &"animated_teapot", "level": 5}, {"id": &"flour_slime", "level": 4}],
		110, 80,
		[{"kind": "material", "id": "golden_sugar", "n": 2, "chance": 0.35},
		 {"kind": "tickets", "n": 1, "chance": 0.1}],
		[{"kind": "material", "id": "training_manual", "n": 2}])
	_enc(&"sugar_golem", "Royal Sugar Golem", "BOSS - the sugar king of the clouds wakes up.", 7,
		[{"id": &"royal_sugar_golem", "level": 7}, {"id": &"sugar_imp", "level": 6}, {"id": &"sugar_imp", "level": 6}],
		300, 160,
		[{"kind": "material", "id": "training_manual", "n": 1, "chance": 1.0},
		 {"kind": "material", "id": "golden_sugar", "n": 2, "chance": 0.5},
		 {"kind": "tickets", "n": 1, "chance": 0.25}],
		[{"kind": "tickets", "n": 2}], true, true)


# ------------------------------------------------------------------ meals
## Packed meal -> team buff for one battle. Scaled by the dish's star tier.
const MEAL_BUFFS := {
	"pancakes":   {"stat": "hp",   "amount": 0.10, "text": "+%d%% Max HP"},
	"latte":      {"stat": "spd",  "amount": 0.10, "text": "+%d%% Speed"},
	"omurice":    {"stat": "atk",  "amount": 0.10, "text": "+%d%% Attack"},
	"shortcake":  {"stat": "post_heal", "amount": 0.15, "text": "Recover %d%% HP after victory"},
	"curry":      {"stat": "def",  "amount": 0.10, "text": "+%d%% Defense"},
	"ramen":      {"stat": "regen", "amount": 0.01, "text": "Regenerate %.1f%% HP/s", "float": true},
	"coffee":     {"stat": "spd",  "amount": 0.05, "text": "+%d%% Speed"},
	"croissant":  {"stat": "atk",  "amount": 0.05, "text": "+%d%% Attack"},
	"cookies":    {"stat": "def",  "amount": 0.05, "text": "+%d%% Defense"},
	"matcha":     {"stat": "crit", "amount": 0.20, "text": "+%d%% Crit chance"},
	"sandwich":   {"stat": "hp",   "amount": 0.06, "text": "+%d%% Max HP"},
	"pudding":    {"stat": "heal", "amount": 0.12, "text": "+%d%% Healing & shields"},
	"melon_soda": {"stat": "spd",  "amount": 0.08, "text": "+%d%% Speed"},
	"macarons":   {"stat": "crit", "amount": 0.30, "text": "+%d%% Crit chance"},
	"choco_cake": {"stat": "atk",  "amount": 0.08, "text": "+%d%% Attack"},
	"parfait":    {"stat": "heal", "amount": 0.18, "text": "+%d%% Healing & shields"},
}
## Star tier -> buff strength (burnt food does nothing).
const TIER_BUFF := {"black": 0.0, "plain": 0.6, "bronze": 0.8, "silver": 1.0, "gold": 1.2, "diamond": 1.5}


static func meal_buff(meal: Dictionary) -> Dictionary:
	if meal.is_empty() or not MEAL_BUFFS.has(meal["food"]):
		return {}
	var b: Dictionary = MEAL_BUFFS[meal["food"]]
	return {"stat": b["stat"], "amount": float(b["amount"]) * float(TIER_BUFF[meal["tier"]])}


static func meal_text(meal: Dictionary) -> String:
	var b: Dictionary = MEAL_BUFFS.get(meal["food"], {})
	if b.is_empty():
		return ""
	var amt: float = float(b["amount"]) * float(TIER_BUFF[meal["tier"]]) * 100.0
	if meal["tier"] == "black":
		return "Burnt - no effect"
	return b["text"] % (amt if b.get("float", false) else int(round(amt)))
