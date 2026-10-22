class_name ShipStats
extends RefCounted
## Airship rules: effective ship stats, crew station performance, fuel
## estimates and Sky Routes. Crew effectiveness always reads the shared five
## character stats (GS.stat) and job mastery - no ship-only attributes.

static var data := ShipData.default_ship()

## Station -> primary / secondary stat. More stations (Captain, Navigator,
## Purser, Lookout, Deckhand) plug in here later.
const STATIONS := {
	"pilot":         {"name": "Pilot", "p": "agi", "s": "foc", "mastery": "Pilot",
		"desc": "Faster voyages and less fuel."},
	"engineer":      {"name": "Engineer", "p": "tec", "s": "end", "mastery": "Engineer",
		"desc": "Less fuel, cheaper repairs, slower engine wear."},
	"quartermaster": {"name": "Quartermaster", "p": "foc", "s": "end", "mastery": "Quartermaster",
		"desc": "More usable cargo capacity."},
}
const PERF_BASE := 8.0       ## performance at which a station starts giving a bonus
const FUEL_PER_SEGMENT := 2.75
const FUEL_PRICE := 12       ## coins per Aether Fuel at the anchorage (always available)
const SHARDS_PER_REFINE := 3 ## Aether Shards -> 2 fuel (+1 with a good engineer)

## Sky Routes: patrols from the home anchorage (no islands yet).
## encounter = a BattleDB encounter that may ambush the ship mid-voyage.
const ROUTES := [
	{"id": "cloudsea_loop", "name": "Cloudsea Loop", "segments": 2, "hazard": 1, "encounter": "sweet_trouble",
		"ambush": 0.3, "shards": [2, 3], "coins": 60, "mats": 0,
		"desc": "A gentle lap around the anchorage. Good for a first flight."},
	{"id": "sunset_drift", "name": "Sunset Drift", "segments": 4, "hazard": 1, "encounter": "kitchen_haunt",
		"ambush": 0.5, "shards": [4, 6], "coins": 120, "mats": 2,
		"desc": "Follow the warm currents toward the horizon."},
	{"id": "storm_front", "name": "Storm Front", "segments": 6, "hazard": 3, "encounter": "doughy_swamp",
		"ambush": 0.6, "shards": [7, 10], "coins": 200, "mats": 4,
		"desc": "Rough winds. Stability and a sturdy hull matter here."},
	{"id": "golem_skies", "name": "Golem Skies", "segments": 8, "hazard": 2, "encounter": "sugar_golem",
		"ambush": 1.0, "shards": [12, 14], "coins": 400, "mats": 6,
		"desc": "The sugar golem's hunting grounds. A boss blocks the way."},
]


static func level(id: String) -> int:
	return int(GS.airship["upgrades"].get(id, 1))


## Ship stat after upgrades (station bonuses are applied where they matter).
static func stat(s: String) -> float:
	var v: float = data.base[s]
	for id in data.upgrades:
		v += float(data.upgrades[id]["gain"].get(s, 0.0)) * (level(id) - 1)
	return v


static func station_key(st: String) -> String:
	var k: String = GS.airship["stations"].get(st, "")
	return k if GS.staff.has(k) else ""


## Station performance = 0.65 P + 0.35 S + 1.5 Mastery + Trait.
static func performance(key: String, st: String) -> float:
	if key == "" or not GS.staff.has(key):
		return 0.0
	var d: Dictionary = STATIONS[st]
	var m := mini(GS.mastery_level(key, d["mastery"]), 10)
	return 0.65 * GS.stat(key, d["p"]) + 0.35 * GS.stat(key, d["s"]) + 1.5 * m + trait_bonus(key, st)


## Character traits (extension point).
static func trait_bonus(_key: String, _st: String) -> float:
	return 0.0


static func _over(st: String) -> float:
	return maxf(0.0, performance(station_key(st), st) - PERF_BASE)


## Capped station bonuses (fractions).
static func pilot_fuel() -> float:
	return minf(_over("pilot") * 0.008, 0.15)


static func pilot_speed() -> float:
	return minf(_over("pilot") * 0.015, 0.30)


static func engineer_fuel() -> float:
	return minf(_over("engineer") * 0.010, 0.18)


static func engineer_repair() -> float:
	return minf(_over("engineer") * 0.012, 0.30)


static func quartermaster_cargo() -> float:
	return minf(_over("quartermaster") * 0.010, 0.20)


static func cargo_capacity() -> int:
	return int(round(stat("cargo") * (1.0 + quartermaster_cargo())))


## Slots in use: stored furniture, packed meals and material stacks.
static func cargo_used() -> int:
	return GS.inventory.size() + GS.meals.size() + GS.materials.size()


static func cargo_load() -> float:
	return float(cargo_used()) / maxf(1.0, cargo_capacity())


## Fuel for a route, with a breakdown for the departure screen.
static func fuel_estimate(segments: int) -> Dictionary:
	var base := segments * FUEL_PER_SEGMENT
	var mult := 1.0
	var notes: Array[String] = []
	if cargo_load() > 0.75:
		mult *= 1.10
		notes.append("Heavy cargo +10%")
	var cond := float(GS.airship["engine"])
	if cond < 70.0:
		mult *= 1.0 + (70.0 - cond) / 100.0
		notes.append("Worn engine +%d%%" % int(70.0 - cond))
	mult *= 1.0 - stat("efficiency")
	if stat("efficiency") > 0.0:
		notes.append("Skyheart Core -%d%%" % int(round(stat("efficiency") * 100)))
	mult *= 1.0 - pilot_fuel()
	if pilot_fuel() > 0.0:
		notes.append("Pilot -%d%%" % int(round(pilot_fuel() * 100)))
	mult *= 1.0 - engineer_fuel()
	if engineer_fuel() > 0.0:
		notes.append("Engineer -%d%%" % int(round(engineer_fuel() * 100)))
	return {"base": base, "fuel": maxi(1, int(round(base * mult))), "notes": notes}


## Seconds a voyage takes (real time) - faster with engine power and a pilot.
static func voyage_seconds(segments: int) -> float:
	return segments * 7.0 / (stat("engine") / 10.0 * (1.0 + pilot_speed()))


## Hull damage from one hazard, softened by stability.
static func hazard_damage(hazard: int) -> int:
	return int(round(hazard * 10.0 * (1.0 - minf(0.6, stat("stability") / 50.0))))


## Small barrier every crew member starts battles with (Stabilizer Runes).
static func battle_shield() -> float:
	return (stat("stability") - 10.0) * 2.0


static func repair_cost(hp: int) -> Dictionary:
	var k := 1.0 - engineer_repair()
	return {"coins": int(ceil(hp * 3.0 * k)), "mats": int(ceil(hp / 10.0 * k))}


static func maintain_cost() -> int:
	return int(ceil((100.0 - float(GS.airship["engine"])) * 1.5 * (1.0 - engineer_repair())))


static func refine_yield() -> int:
	return 3 if performance(station_key("engineer"), "engineer") >= 16.0 else 2


## Engine wear from one voyage.
static func engine_wear(segments: int) -> float:
	return segments * 2.0 * (1.0 - engineer_repair())
