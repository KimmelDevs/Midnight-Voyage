class_name EnemyData
extends Resource
## An enemy type. Stats are given at level 1 and scale per level.

@export var id: StringName
@export var display_name: String
@export var sprite := ""              ## res:// path; a placeholder blob is drawn if missing
@export var base := {"hp": 200.0, "atk": 15.0, "def": 4.0, "spd": 15.0, "crit": 5.0}
## Per-level growth as a fraction of the level-1 value.
@export var growth := {"hp": 0.12, "atk": 0.10, "def": 0.06, "spd": 0.01, "crit": 0.0}
@export var basic: AbilityData
@export var skill: AbilityData
@export var xp := 20                  ## XP this enemy is worth at level 1
@export var coins := 15
@export var boss := false


func stats_at(level: int) -> Dictionary:
	var out := {}
	for k in base:
		out[k] = float(base[k]) * (1.0 + float(growth.get(k, 0.0)) * (level - 1))
	out["heal"] = out["atk"] * 0.6
	return out
