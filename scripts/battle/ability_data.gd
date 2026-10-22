class_name AbilityData
extends Resource
## One basic attack or skill. Abilities are pure data: BattleManager runs the
## effect list in order, so new skills need no combat-code changes.
##
## Effect dictionaries ("target" picks who it hits):
##   {type = "damage", power = 1.0, crit_bonus = 0.0}      ATK-scaled hit
##   {type = "heal",   power = 1.0}                        HEAL-scaled restore
##   {type = "shield", power = 1.0}                        HEAL-scaled barrier
##   {type = "status", stat = "spd", amount = 0.3, duration = 6.0, tag = "Haste"}
##        multiplies a stat (amount > 0 buff, < 0 debuff) for a while
##   {type = "dot",  power = 0.2, duration = 4.0, tag = "Burn"}   ATK-scaled per second
##   {type = "hot",  power = 0.15, duration = 5.0, tag = "Regen"} HEAL-scaled per second
##   {type = "drain", ratio = 0.5}   heal target by a share of damage dealt so far
## targets: "enemy" (front-weighted), "enemy_lowest", "enemy_all",
##          "ally_lowest", "ally_all", "self"

@export var id: StringName
@export var display_name: String
@export var cooldown := 0.0          ## seconds; 0 = basic attack
@export var magic := false           ## ranged/magic visual (bolt instead of lunge)
@export var color := Color.WHITE     ## effect / number tint
@export var description := ""
@export var effects: Array[Dictionary] = []


static func make(p_id: StringName, p_name: String, p_cooldown: float, p_effects: Array,
		p_desc: String = "", p_magic: bool = false, p_color: Color = Color.WHITE) -> AbilityData:
	var a := AbilityData.new()
	a.id = p_id
	a.display_name = p_name
	a.cooldown = p_cooldown
	a.effects.assign(p_effects)
	a.description = p_desc
	a.magic = p_magic
	a.color = p_color
	return a


## True for pure healing skills (no point casting them on a healthy team).
func heals_only() -> bool:
	var heal := false
	for e in effects:
		if str(e.get("target", "enemy")).begins_with("enemy"):
			return false
		if e["type"] == "heal":
			heal = true
	return heal
