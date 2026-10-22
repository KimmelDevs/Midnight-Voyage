class_name BattleManager
extends Node
## Runs one auto-battle. Every unit fills an action gauge at a rate set by its
## Speed; at 100 it acts: its skill when ready (and useful), otherwise its
## basic attack. Abilities are AbilityData effect lists, so new skills and
## enemies plug in without touching this file. The view listens to signals.

signal unit_acted(unit: BattleUnit, ability: AbilityData, targets: Array)
signal number_popped(unit: BattleUnit, amount: float, kind: String)  ## dmg crit heal shield miss dot
signal unit_changed(unit: BattleUnit)
signal unit_died(unit: BattleUnit)
signal battle_ended(victory: bool)

const GAUGE_RATE := 1.6       ## gauge per point of Speed per second
const CRIT_MULT := 1.6
const DEF_WEIGHT := 4.0       ## damage *= 100 / (100 + DEF * DEF_WEIGHT)
const FRONT_WEIGHTS := [0.5, 0.3, 0.2]  ## chance an attack aims at slot 0/1/2

var allies: Array[BattleUnit] = []
var enemies: Array[BattleUnit] = []
var speed_mult := 1.0
var running := false
var elapsed := 0.0
var regen := 0.0              ## meal: fraction of max HP regained per second (allies)
var _tick := 0.0


func setup(p_allies: Array[BattleUnit], p_enemies: Array[BattleUnit]) -> void:
	allies = p_allies
	enemies = p_enemies
	for u in allies + enemies:
		u.gauge = randf_range(0.0, 40.0)   # stagger the opening
		u.skill_cd = (u.skill.cooldown * 0.5) if u.skill else 0.0
	running = true


func _process(delta: float) -> void:
	if not running:
		return
	var dt := delta * speed_mult
	elapsed += dt
	_tick += dt
	var whole_second := _tick >= 1.0
	if whole_second:
		_tick -= 1.0
	for u in allies + enemies:
		if not u.alive():
			continue
		_update_statuses(u, dt, whole_second)
		if whole_second and regen > 0.0 and u.is_ally:
			_heal(u, u.max_hp * regen, false)
	if _check_end():
		return
	for u in allies + enemies:
		if not u.alive():
			continue
		u.skill_cd = maxf(0.0, u.skill_cd - dt)
		u.gauge += u.stat("spd") * GAUGE_RATE * dt
		if u.gauge >= 100.0:
			u.gauge -= 100.0
			_act(u)
			if _check_end():
				return


func _update_statuses(u: BattleUnit, dt: float, whole_second: bool) -> void:
	var changed := false
	for st in u.statuses.duplicate():
		if whole_second and st["kind"] == "dot":
			_damage_raw(u, float(st["power"]), "dot")
		elif whole_second and st["kind"] == "hot":
			_heal(u, float(st["power"]), false)
		st["time"] = float(st["time"]) - dt
		if st["time"] <= 0.0:
			u.statuses.erase(st)
			changed = true
	if changed:
		unit_changed.emit(u)


func _act(u: BattleUnit) -> void:
	var ability := u.basic
	if u.skill_ready() and _worth_casting(u, u.skill):
		ability = u.skill
		u.skill_cd = u.skill.cooldown
	_execute(u, ability)


## Pure heals wait until someone on the team is actually hurt.
func _worth_casting(u: BattleUnit, ab: AbilityData) -> bool:
	if not ab.heals_only():
		return true
	for a in _team(u):
		if a.alive() and a.hp_ratio() < 0.85:
			return true
	return false


func _team(u: BattleUnit) -> Array[BattleUnit]:
	return allies if u.is_ally else enemies


func _foes(u: BattleUnit) -> Array[BattleUnit]:
	return enemies if u.is_ally else allies


func _living(list: Array[BattleUnit]) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for x in list:
		if x.alive():
			out.append(x)
	return out


## Front-weighted pick: units in front draw more attacks.
func _pick_front(list: Array[BattleUnit]) -> BattleUnit:
	var live := _living(list)
	if live.is_empty():
		return null
	var total := 0.0
	for x in live:
		total += FRONT_WEIGHTS[clampi(x.slot, 0, 2)]
	var r := randf() * total
	for x in live:
		r -= FRONT_WEIGHTS[clampi(x.slot, 0, 2)]
		if r <= 0.0:
			return x
	return live[0]


func _lowest(list: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for x in _living(list):
		if best == null or x.hp_ratio() < best.hp_ratio():
			best = x
	return best


func _targets(u: BattleUnit, spec: String, focus: BattleUnit) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	match spec:
		"enemy":
			var t: BattleUnit = focus if focus and focus.alive() else _pick_front(_foes(u))
			if t:
				out.append(t)
		"enemy_lowest":
			var t: BattleUnit = _lowest(_foes(u))
			if t:
				out.append(t)
		"enemy_all":
			out = _living(_foes(u))
		"ally_lowest":
			var t: BattleUnit = _lowest(_team(u))
			if t:
				out.append(t)
		"ally_all":
			out = _living(_team(u))
		"self":
			out.append(u)
	return out


func _execute(u: BattleUnit, ab: AbilityData) -> void:
	var dealt := 0.0
	var shown: Array = []
	var focus: BattleUnit = null   # consecutive "enemy" effects hit the same foe
	for e in ab.effects:
		var targets := _targets(u, str(e.get("target", "enemy")), focus)
		if e.get("target", "enemy") == "enemy" and not targets.is_empty():
			focus = targets[0]
		for t in targets:
			match e["type"]:
				"damage":
					dealt += _attack(u, t, float(e.get("power", 1.0)), float(e.get("crit_bonus", 0.0)),
						ab.cooldown <= 0.0)
				"heal":
					_heal(t, u.stat("heal") * float(e.get("power", 1.0)) * randf_range(0.92, 1.08), true)
				"shield":
					var amt := u.stat("heal") * float(e.get("power", 1.0))
					t.shield += amt
					number_popped.emit(t, amt, "shield")
					unit_changed.emit(t)
				"status":
					t.add_status({"tag": e["tag"], "stat": e["stat"], "amount": float(e["amount"]),
						"time": float(e["duration"]), "kind": "status"})
					unit_changed.emit(t)
				"dot":
					t.add_status({"tag": e["tag"], "stat": "", "amount": 0.0, "kind": "dot",
						"time": float(e["duration"]), "power": u.stat("atk") * float(e["power"])})
					unit_changed.emit(t)
				"hot":
					t.add_status({"tag": e.get("tag", "Regen"), "stat": "", "amount": 0.0, "kind": "hot",
						"time": float(e["duration"]), "power": u.stat("heal") * float(e["power"])})
					unit_changed.emit(t)
				"drain":
					if dealt > 0.0:
						_heal(t, dealt * float(e.get("ratio", 0.5)), true)
			if not shown.has(t):
				shown.append(t)
	unit_acted.emit(u, ab, shown)


## One hit. Basic attacks can be dodged (target faster = more evasion);
## skills always land. FOC-based crit from the attacker.
func _attack(u: BattleUnit, t: BattleUnit, power: float, crit_bonus: float, can_miss: bool) -> float:
	if can_miss:
		var evade := clampf(3.0 + (t.stat("spd") - u.stat("spd")) * 0.6, 0.0, 25.0)
		if randf() * 100.0 < evade:
			number_popped.emit(t, 0.0, "miss")
			return 0.0
	var dmg := u.stat("atk") * power * 100.0 / (100.0 + t.stat("def") * DEF_WEIGHT)
	dmg *= randf_range(0.9, 1.1)
	var crit := randf() * 100.0 < u.stat("crit") + crit_bonus
	if crit:
		dmg *= CRIT_MULT
	return _damage_raw(t, dmg, "crit" if crit else "dmg")


func _damage_raw(t: BattleUnit, dmg: float, kind: String) -> float:
	dmg = maxf(1.0, round(dmg))
	var absorbed := minf(t.shield, dmg)
	t.shield -= absorbed
	t.hp = maxf(0.0, t.hp - (dmg - absorbed))
	number_popped.emit(t, dmg, kind)
	unit_changed.emit(t)
	if not t.alive():
		t.statuses.clear()
		t.shield = 0.0
		unit_died.emit(t)
	return dmg


func _heal(t: BattleUnit, amount: float, show: bool) -> void:
	if not t.alive():
		return
	var before := t.hp
	t.hp = minf(t.max_hp, t.hp + round(amount))
	if show or t.hp - before >= 1.0:
		number_popped.emit(t, t.hp - before, "heal")
	unit_changed.emit(t)


func _check_end() -> bool:
	if _living(enemies).is_empty():
		_finish(true)
		return true
	if _living(allies).is_empty():
		_finish(false)
		return true
	return false


func _finish(victory: bool) -> void:
	running = false
	battle_ended.emit(victory)
