class_name ShipData
extends Resource
## Permanent airship configuration: base stats and how each upgrade raises
## them. Runtime/progress values (fuel, hull, levels, stations) live in
## GS.airship; effective stats are computed by ShipStats.

## Base stats of the starting airship.
@export var base := {
	"hull": 100.0,         ## max Hull HP
	"engine": 10.0,        ## Engine Power (travel speed)
	"efficiency": 0.0,     ## Fuel Efficiency (fraction of fuel saved)
	"fuel_cap": 40.0,      ## Aether tank capacity (units)
	"cargo": 12.0,         ## Cargo Capacity (storage slots)
	"stability": 10.0,     ## reduces hazard damage; gives a small battle shield
	"crew": 8.0,           ## Crew Capacity (quarters)
}

## upgrade id -> {name, desc, stat gains per level above 1}
@export var upgrades := {
	"core":  {"name": "Skyheart Core", "desc": "Engine power and fuel efficiency.",
		"gain": {"engine": 3.0, "efficiency": 0.06}},
	"tank":  {"name": "Aether Tank", "desc": "Holds more fuel for longer routes.",
		"gain": {"fuel_cap": 20.0}},
	"hull":  {"name": "Reinforced Hull", "desc": "More Hull HP.",
		"gain": {"hull": 40.0}},
	"runes": {"name": "Stabilizer Runes", "desc": "Less hazard damage, bigger battle shield.",
		"gain": {"stability": 6.0}},
	"hold":  {"name": "Cargo Hold", "desc": "More cargo slots.",
		"gain": {"cargo": 6.0}},
}
@export var max_upgrade := 5


## Coins + Building Materials to raise an upgrade to `to_level`.
func upgrade_cost(to_level: int) -> Dictionary:
	return {"coins": int(300 * pow(to_level, 1.8)), "mats": 3 * to_level}


static func default_ship() -> ShipData:
	return ShipData.new()
