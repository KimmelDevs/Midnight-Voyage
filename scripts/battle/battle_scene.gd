class_name BattleScene
extends CanvasLayer
## Battle arena: builds units from GS (crew) and BattleDB (enemies), runs a
## BattleManager, shows the fight, then applies rewards to GS and shows the
## results screen. Runs while the café is paused (process_mode ALWAYS).

signal closed

const C_TEXT := Color("4a2f2a")
const C_PANEL := Color("f7e9d3")
const C_EDGE := Color("6b4630")
const ARENA_ORIGIN := Vector2(320, 104)   # top vertex of the floating platform
const ALLY_SPOTS: Array[Vector2] = [Vector2(262, 228), Vector2(204, 204), Vector2(200, 262)]
const ENEMY_SPOTS: Array[Vector2] = [Vector2(382, 228), Vector2(440, 204), Vector2(444, 262)]

var encounter: EncounterData
var team: Array[String] = []
var meal: Dictionary = {}
var manager: BattleManager
var views := {}               # BattleUnit -> UnitView
var root: Control
var arena: Control
var cards: Array = []         # [{unit, hp, cd, label}]
var timer_label: Label
var speed_btn: Button
var theme_ui: Theme
var result_shown := false


func _init(p_encounter: EncounterData, p_team: Array[String], p_meal: Dictionary, p_theme: Theme) -> void:
	encounter = p_encounter
	team = p_team
	meal = p_meal
	theme_ui = p_theme
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_ui
	add_child(root)
	arena = ArenaBg.new()
	arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.set("origin", ARENA_ORIGIN)
	root.add_child(arena)
	manager = BattleManager.new()
	add_child(manager)
	var allies := _make_allies()
	var foes := _make_enemies()
	for u in allies + foes:
		var tex: Texture2D = u.get_meta("tex")
		var region: Rect2 = u.get_meta("region")
		var v := UnitView.new()
		var spots := ALLY_SPOTS if u.is_ally else ENEMY_SPOTS
		v.setup(u, tex, region, spots[u.slot])
		root.add_child(v)
		views[u] = v
	# draw back-row units first
	var order := views.values()
	order.sort_custom(func(a, b): return a.home.y < b.home.y)
	for v in order:
		root.move_child(v, -1)
	_build_hud(allies)
	manager.unit_acted.connect(_on_acted)
	manager.number_popped.connect(_on_number)
	manager.unit_changed.connect(_on_changed)
	manager.unit_died.connect(_on_died)
	manager.battle_ended.connect(_on_ended)
	manager.setup(allies, foes)


# ------------------------------------------------------------------ units
func _make_allies() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var buff := BattleDB.meal_buff(meal)
	for i in team.size():
		var key := team[i]
		var u := BattleUnit.new()
		u.key = key
		u.is_ally = true
		u.slot = i
		u.display_name = GS.STAFF[key]["name"]
		u.level = GS.level(key)
		u.base = GS.combat_stats(key)
		if not buff.is_empty() and u.base.has(buff["stat"]):
			u.base[buff["stat"]] = float(u.base[buff["stat"]]) * (1.0 + float(buff["amount"]))
		u.max_hp = u.base["hp"]
		u.hp = clampf(round(u.max_hp * GS.battle_hp_ratio(key)), 1.0, u.max_hp)
		var k := BattleDB.kit(key)
		u.basic = k["basic"]
		u.skill = k["skill"]
		var sheet: String = GS.STAFF[key]["sheet"]
		var path := "res://assets/chars/%s_combat.png" % sheet
		if not ResourceLoader.exists(path):
			path = "res://assets/chars/%s.png" % sheet
		var tex: Texture2D = load(path)
		var fw := tex.get_width() / 3.0
		var fh := tex.get_height() / 4.0
		u.set_meta("tex", tex)
		u.set_meta("region", Rect2(fw, 0, fw, fh))   # standing, facing south-east (right)
		out.append(u)
	if not buff.is_empty() and buff["stat"] == "regen":
		manager.regen = float(buff["amount"])
	return out


func _make_enemies() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for i in encounter.enemies.size():
		var spec: Dictionary = encounter.enemies[i]
		var data := BattleDB.enemy(spec["id"])
		var u := BattleUnit.new()
		u.key = str(data.id)
		u.is_ally = false
		u.slot = i
		u.level = int(spec["level"])
		u.display_name = data.display_name
		u.base = data.stats_at(u.level)
		u.max_hp = u.base["hp"]
		u.hp = u.max_hp
		u.basic = data.basic
		u.skill = data.skill
		u.boss = data.boss
		var tex: Texture2D = load(data.sprite) if ResourceLoader.exists(data.sprite) else _blob(data.boss)
		u.set_meta("tex", tex)
		u.set_meta("region", Rect2(Vector2.ZERO, tex.get_size()))
		out.append(u)
	return out


## Placeholder enemy art when a sprite is missing.
func _blob(big: bool) -> Texture2D:
	var s := 64 if big else 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length()
			if d < s / 2.0 - 1:
				img.set_pixel(x, y, Color("b07ce8") if d < s / 2.0 - 3 else Color("2a1a3a"))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ HUD
func _sb(bg: Color, edge: Color, border: int = 2, pad: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s


func _label(text: String, size: int, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build_hud(allies: Array[BattleUnit]) -> void:
	var top := PanelContainer.new()
	top.position = Vector2(6, 6)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	hb.add_child(_label(encounter.display_name, 13))
	timer_label = _label("0:00", 11)
	hb.add_child(timer_label)
	if not meal.is_empty():
		hb.add_child(_label("Meal: %s (%s)" % [GS.FOODS[meal["food"]]["name"], BattleDB.meal_text(meal)], 9))
	speed_btn = Button.new()
	speed_btn.text = "Speed 1x"
	speed_btn.custom_minimum_size = Vector2(70, 22)
	speed_btn.position = Vector2(564, 8)
	speed_btn.pressed.connect(func():
		manager.speed_mult = 2.0 if manager.speed_mult < 2.0 else 1.0
		speed_btn.text = "Speed %dx" % int(manager.speed_mult))
	root.add_child(speed_btn)

	var bar := HBoxContainer.new()
	bar.position = Vector2(6, 296)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for u in allies:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(C_PANEL, C_EDGE, 2, 4))
		card.custom_minimum_size = Vector2(204, 58)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		card.add_child(h)
		var face := AtlasTexture.new()
		face.atlas = u.get_meta("tex")
		var reg: Rect2 = u.get_meta("region")
		face.region = Rect2(reg.position, Vector2(reg.size.x, minf(reg.size.y, 40)))
		var fr := TextureRect.new()
		fr.texture = face
		fr.custom_minimum_size = Vector2(reg.size.x, 40)
		h.add_child(fr)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_label("%s  Lv %d" % [u.display_name, u.level], 11))
		var hp := ProgressBar.new()
		hp.show_percentage = false
		hp.custom_minimum_size = Vector2(120, 6)
		hp.max_value = u.max_hp
		hp.add_theme_stylebox_override("background", _sb(Color("4a3140"), Color("1c1428"), 1, 0))
		hp.add_theme_stylebox_override("fill", _sb(Color("6cd46a"), Color("6cd46a"), 0, 0))
		v.add_child(hp)
		var hp_l := _label("", 8)
		v.add_child(hp_l)
		var cd := ProgressBar.new()
		cd.show_percentage = false
		cd.custom_minimum_size = Vector2(120, 4)
		cd.max_value = 1.0
		cd.add_theme_stylebox_override("background", _sb(Color("4a3140"), Color("1c1428"), 1, 0))
		cd.add_theme_stylebox_override("fill", _sb(Color("b07ce8"), Color("b07ce8"), 0, 0))
		v.add_child(cd)
		v.add_child(_label(u.skill.display_name if u.skill else "-", 8, Color("7a4f9a")))
		bar.add_child(card)
		cards.append({"unit": u, "hp": hp, "hp_l": hp_l, "cd": cd})


func _process(_delta: float) -> void:
	if manager == null:
		return
	var t := int(manager.elapsed)
	timer_label.text = "%d:%02d" % [t / 60, t % 60]
	for c in cards:
		var u: BattleUnit = c["unit"]
		c["hp"].value = u.hp
		c["hp_l"].text = "HP %d/%d%s" % [u.hp, u.max_hp, ("  +%d shield" % u.shield) if u.shield >= 1.0 else ""]
		c["cd"].value = u.skill_progress() if u.alive() else 0.0


# ------------------------------------------------------------------ events
func _on_acted(u: BattleUnit, ab: AbilityData, targets: Array) -> void:
	var v: UnitView = views[u]
	if ab.cooldown > 0.0:
		_float(v.home + Vector2(0, -v.size.y - 26), ab.display_name, ab.color, 10)
		v.glow(ab.color)
	var foe_targets := targets.filter(func(t): return t.is_ally != u.is_ally)
	if foe_targets.is_empty():
		for t in targets:
			views[t].glow(ab.color)
		return
	if ab.magic:
		for t in foe_targets:
			_bolt(v.home + Vector2(0, -v.size.y / 2.0), views[t].home + Vector2(0, -views[t].size.y / 2.0), ab.color)
	else:
		v.lunge(views[foe_targets[0]].home)


func _on_number(t: BattleUnit, amount: float, kind: String) -> void:
	var v: UnitView = views[t]
	var at := v.home + Vector2(randf_range(-8, 8), -v.size.y - 6)
	match kind:
		"miss":
			_float(at, "Miss", Color("d8d0e8"), 10)
		"heal":
			if amount >= 1.0:
				_float(at, "+%d" % amount, Color("8ff0a0"), 11)
		"shield":
			_float(at, "+%d shield" % amount, Color("dff4ff"), 10)
		"crit":
			_float(at, "%d!" % amount, Color("ffd86b"), 14)
			v.hit()
		"dot":
			_float(at, "%d" % amount, Color("ffa060"), 9)
		_:
			_float(at, "%d" % amount, Color("ffffff"), 11)
			v.hit()


func _on_changed(u: BattleUnit) -> void:
	views[u].refresh()


func _on_died(u: BattleUnit) -> void:
	views[u].faint()


func _float(at: Vector2, text: String, col: Color, size: int) -> void:
	var l := _label(text, size, col)
	l.add_theme_color_override("font_outline_color", Color("1c1428"))
	l.add_theme_constant_override("outline_size", 4)
	l.position = at - Vector2(text.length() * size * 0.28, 0)
	root.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", at.y - 18, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.4)
	tw.tween_callback(l.queue_free)


func _bolt(from: Vector2, to: Vector2, col: Color) -> void:
	var s := TextureRect.new()
	s.texture = load("res://assets/gacha/sparkle.png")
	s.modulate = col
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.position = from - Vector2(8, 8)
	root.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "position", to - Vector2(8, 8), 0.18)
	tw.tween_callback(s.queue_free)


# ------------------------------------------------------------------ results
func _on_ended(victory: bool) -> void:
	if result_shown:
		return
	result_shown = true
	await get_tree().create_timer(0.8).timeout
	var report := BattleRewards.apply(encounter, manager.allies, victory, meal)
	_show_results(victory, report)


func _show_results(victory: bool, report: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.1, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_EDGE, 2, 10))
	panel.custom_minimum_size = Vector2(380, 0)
	panel.position = Vector2(130, 40)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var title := _label("Victory!" if victory else "Defeat...", 20, Color("b8862a") if victory else Color("8a5a7a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_label("Time %d:%02d" % [int(manager.elapsed) / 60, int(manager.elapsed) % 60], 9))
	for line in report["lines"]:
		v.add_child(_label(line, 11))
	v.add_child(_label("Crew experience", 12, Color("7a4f9a")))
	for m in report["crew"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_label("%s  +%d XP" % [m["name"], m["xp"]], 11))
		if m["levels"] > 0:
			row.add_child(_label("Level up! Lv %d" % m["level"], 11, Color("c0602a")))
		else:
			row.add_child(_label("Lv %d" % m["level"], 10))
		v.add_child(row)
	if not victory:
		v.add_child(_label("Tip: level up crew in the café, pack a meal, or put a sturdy\nfighter in the front slot.", 9))
	var back := Button.new()
	back.text = "Return to Café"
	back.custom_minimum_size = Vector2(140, 26)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): closed.emit())
	v.add_child(back)


## Floating platform made of the café's checker tiles under a night sky.
class ArenaBg extends Control:
	var origin := Vector2.ZERO

	func _draw() -> void:
		var top := Color("1c1838")
		var bot := Color("5a3f74")
		for y in range(0, 360, 4):
			draw_rect(Rect2(0, y, 640, 4), top.lerp(bot, y / 360.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 60:
			draw_rect(Rect2(rng.randi_range(0, 639), rng.randi_range(0, 180), 1, 1), Color(1, 1, 0.9, rng.randf_range(0.4, 1.0)))
		var tile: Texture2D = load("res://assets/cafe/floor_check.png")
		for sum in range(11):
			for c in 6:
				var r := sum - c
				if r < 0 or r >= 6:
					continue
				var p := origin + Vector2((c - r) * 29, (c + r) * 18 + 18)
				draw_texture(tile, p - Vector2(29, 18))
