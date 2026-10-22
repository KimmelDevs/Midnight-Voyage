class_name BattleUnit
extends RefCounted
## Temporary per-battle state of one combatant. Permanent progression stays in
## GS.staff; nothing here is saved except the HP ratio carried between fights.

var display_name := ""
var key := ""                    ## GS.STAFF key for crew, enemy id for enemies
var is_ally := true
var slot := 0                    ## 0 = front, 1 = middle, 2 = back
var level := 1
var base := {}                   ## hp, atk, def, spd, crit, heal (after meal buff)
var max_hp := 1.0
var hp := 1.0
var shield := 0.0
var basic: AbilityData
var skill: AbilityData
var skill_cd := 0.0              ## seconds until the skill is ready
var gauge := 0.0                 ## acts at 100
## [{tag, stat, amount, time, kind ("status"/"dot"/"hot"), power, source}]
var statuses: Array = []
var boss := false
var sprite := ""                 ## enemy sprite path (crew use their sheets)


func alive() -> bool:
	return hp > 0.0


func hp_ratio() -> float:
	return hp / max_hp


## Stat with active buffs/debuffs applied (never below 20% of base).
func stat(s: String) -> float:
	var mult := 1.0
	for st in statuses:
		if st["kind"] == "status" and st["stat"] == s:
			mult += float(st["amount"])
	return float(base.get(s, 0.0)) * maxf(mult, 0.2)


func skill_ready() -> bool:
	return skill != null and skill_cd <= 0.0


func skill_progress() -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 1.0
	return 1.0 - clampf(skill_cd / skill.cooldown, 0.0, 1.0)


## Add or refresh a status by tag (same tag = refresh, not stack).
func add_status(entry: Dictionary) -> void:
	for st in statuses:
		if st["tag"] == entry["tag"]:
			st.merge(entry, true)
			return
	statuses.append(entry)
