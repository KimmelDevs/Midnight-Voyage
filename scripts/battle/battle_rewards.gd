class_name BattleRewards
extends RefCounted
## Turns a finished battle into permanent progress in GS (single source of
## truth) and returns a report for the results screen. Called exactly once
## per battle.


static func apply(enc: EncounterData, allies: Array[BattleUnit], victory: bool, meal: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	var crew: Array = []
	var xp := enc.xp
	var coins := enc.coins
	for spec in enc.enemies:
		var data := BattleDB.enemy(spec["id"])
		var lv := int(spec["level"])
		xp += int(data.xp * (1.0 + 0.2 * (lv - 1)))
		coins += int(data.coins * (1.0 + 0.15 * (lv - 1)))
	if not victory:  # a loss still teaches something
		xp = int(xp * 0.3)
		coins = 0
	if coins > 0:
		GS.add_coins(coins)
		lines.append("+%d coins" % coins)
	if victory:
		for d in enc.drops:
			if randf() < float(d.get("chance", 1.0)):
				lines.append(_grant(d))
		if int(GS.cleared.get(str(enc.id), 0)) == 0:
			for d in enc.first_clear:
				lines.append("First clear: " + _grant(d))
			if enc.unlock_recipe:
				for food in GS.FOODS:
					if not food in GS.unlocked:
						GS.unlocked.append(food)
						lines.append("New recipe unlocked: %s!" % GS.FOODS[food]["name"])
						break
		GS.cleared[str(enc.id)] = int(GS.cleared.get(str(enc.id), 0)) + 1
	# shared progression: battle XP levels the same stats the café uses
	for u in allies:
		var gained := GS.add_xp(u.key, xp)
		crew.append({"name": u.display_name, "xp": xp, "levels": gained, "level": GS.level(u.key)})
	# HP carries over until the crew rests (next café day); shortcake heals after a win
	var post := 0.0
	var buff := BattleDB.meal_buff(meal)
	if victory and not buff.is_empty() and buff["stat"] == "post_heal":
		post = float(buff["amount"])
		lines.append("Shortcake: crew recovered %d%% HP" % int(round(post * 100)))
	for u in allies:
		var ratio := u.hp / u.max_hp
		if post > 0.0 and u.alive():
			ratio = minf(1.0, ratio + post)
		GS.battle_hp[u.key] = ratio
	GS.changed.emit()
	GS.save_game()
	return {"lines": lines, "crew": crew}


static func _grant(d: Dictionary) -> String:
	var n := int(d.get("n", 1))
	match d.get("kind", ""):
		"material":
			GS.add_material(d["id"], n)
			return "%s x%d" % [GS.MATERIALS[d["id"]]["name"], n]
		"tickets":
			GS.tickets += n
			return "Summon Ticket x%d" % n
		"gems":
			GS.gems += n
			return "+%d gems" % n
	return ""
