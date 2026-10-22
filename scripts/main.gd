extends Node2D
## Isometric café: customers arrive, order food, chefs cook, waiters serve.
## Coins unlock menu items and tables; gems pull new staff from the gacha.

const HW := 29            # half tile width (px)
const HH := 18            # half tile height (px)
const TILE_ANCHOR := Vector2(29, 19)  # diamond centre inside the floor tile image
const COLS := 7
const ROWS := 6
const ORIGIN := Vector2(330, 92)   # top vertex of tile (0,0)
const WALL_H := 74

const DOOR := Vector2i(6, 0)
const STOVE := Vector2i(0, 1)
const COOK_SPOT := Vector2i(1, 1)
const COUNTER := Vector2i(0, 3)
const PICKUP := Vector2i(1, 3)
const DISPLAY := Vector2i(0, 5)
const PLANT := Vector2i(6, 5)
const CHEF_IDLE := Vector2i(1, 2)
const WAITER_IDLE := Vector2i(2, 3)
const REST_SPOT := Vector2i(1, 5)
const TABLES: Array[Vector2i] = [Vector2i(3, 2), Vector2i(5, 2), Vector2i(3, 4), Vector2i(5, 4)]

const C_TEXT := Color("4a2f2a")
const C_PANEL := Color("f7e9d3")
const C_EDGE := Color("6b4630")
const C_PINK := Color("e98b9c")
const C_PINK_DK := Color("b85d70")
const RARITY_COL := {"R": Color("aab4c4"), "SR": Color("b07ce8"), "SSR": Color("f2c14e")}

var astar := AStarGrid2D.new()
var world: Node2D
var fx: Node2D
var ui: CanvasLayer
var hud_coins: Label
var hud_gems: Label
var hud_rep: Label
var hud_bar: ProgressBar
var toast_box: VBoxContainer
var overlay: Control
var tables: Array = []          # {tile, chairs:[{tile, dir, taken}], node, plate:Sprite2D}
var counter_dishes: Array = []  # Sprite2D on counter
var customers: Array = []
var orders: Array = []
var staff_actors := {}
var spawn_t := 3.0
var save_t := 0.0
var customer_sheets: Array[Texture2D] = []
var theme_ui: Theme


# ------------------------------------------------------------------ setup
func _ready() -> void:
	randomize()
	_build_background()
	_build_floor()
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	fx = Node2D.new()
	fx.z_index = 50
	add_child(fx)
	_setup_grid()
	_build_furniture()
	_load_customer_sheets()
	_build_ui()
	for key in GS.staff:
		_spawn_staff(key)
	GS.changed.connect(_refresh_hud)
	_refresh_hud()
	_toast("Welcome to the Midnight Voyage Café!")
	# `godot -- --demo-summon` showcases a 10-pull (used for screenshots/tests)
	if "--demo-summon" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		GS.gems += GS.PULL10_COST
		_open_summon()
		await get_tree().create_timer(1.0).timeout
		_do_pull(10, overlay.get_child(1).get_child(0).get_child(1).get_child(0))


func tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func tile_pos(t: Vector2i) -> Vector2:
	return ORIGIN + Vector2((t.x - t.y) * HW, (t.x + t.y) * HH + HH)


func _setup_grid() -> void:
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for t in [STOVE, COUNTER, DISPLAY, PLANT]:
		astar.set_point_solid(t, true)


func _build_background() -> void:
	var bg := BgNode.new()
	bg.z_index = -20
	add_child(bg)
	var walls := WallNode.new()
	walls.z_index = -15
	walls.origin = ORIGIN
	walls.cols = COLS
	walls.rows = ROWS
	walls.hw = HW
	walls.hh = HH
	walls.wall_h = WALL_H
	add_child(walls)
	# wall decorations, sheared to sit flat on the 2:1 walls
	_wall_decor("res://assets/cafe/wall_left.png", 3.0, true)
	_wall_decor("res://assets/cafe/wall_right.png", 2.4, false)
	_wall_decor("res://assets/cafe/door.png", 6.3, false)


func _wall_decor(path: String, t: float, left_wall: bool) -> void:
	var tx := tex(path)
	if tx == null:
		return
	var s := Sprite2D.new()
	s.texture = tx
	s.centered = false
	s.offset = Vector2(-tx.get_width() / 2.0, -tx.get_height()).floor()
	var k := float(HH) / HW - 0.375
	var base: Vector2
	if left_wall:
		base = ORIGIN + Vector2(-t * HW, t * HH)
		s.transform = Transform2D(Vector2(-1, k), Vector2(0, 1), base + Vector2(0, -2))
	else:
		base = ORIGIN + Vector2(t * HW, t * HH)
		s.transform = Transform2D(Vector2(1, k), Vector2(0, 1), base + Vector2(0, -2))
	s.z_index = -14
	add_child(s)


func _build_floor() -> void:
	var wood := tex("res://assets/cafe/floor_wood.png")
	var check := tex("res://assets/cafe/floor_check.png")
	for sum in range(COLS + ROWS - 1):
		for c in COLS:
			var r := sum - c
			if r < 0 or r >= ROWS:
				continue
			var s := Sprite2D.new()
			s.texture = check if c <= 1 else wood
			s.centered = false
			s.position = tile_pos(Vector2i(c, r)) - TILE_ANCHOR
			s.z_index = -10
			add_child(s)


func _prop(path: String, t: Vector2i, foot: float = 12.0, flip: bool = false, shift: Vector2 = Vector2.ZERO) -> Sprite2D:
	var tx := tex(path)
	var s := Sprite2D.new()
	s.texture = tx
	s.centered = false
	s.flip_h = flip
	if tx:
		s.offset = Vector2(-tx.get_width() / 2.0, -tx.get_height() + foot).floor() + shift
	s.position = tile_pos(t)
	world.add_child(s)
	return s


func _build_furniture() -> void:
	_prop("res://assets/cafe/stove.png", STOVE, 12, false)
	_prop("res://assets/cafe/counter.png", COUNTER, 14, true)
	_prop("res://assets/cafe/display.png", DISPLAY, 12, true)
	_prop("res://assets/cafe/plant.png", PLANT, 10)
	for i in TABLES.size():
		var t: Vector2i = TABLES[i]
		var entry := {"tile": t, "chairs": [], "node": null, "plates": []}
		entry["chairs"] = [
			{"tile": t + Vector2i(-1, 0), "dir": Actor.Dir.SE, "taken": false, "node": null},
			{"tile": t + Vector2i(0, -1), "dir": Actor.Dir.SW, "taken": false, "node": null},
		]
		tables.append(entry)
	_refresh_tables()


func _refresh_tables() -> void:
	for i in tables.size():
		var e: Dictionary = tables[i]
		var owned := i < GS.tables_owned
		if owned and e["node"] == null:
			e["node"] = _prop("res://assets/cafe/table.png", e["tile"], 11)
			astar.set_point_solid(e["tile"], true)
			for ch in e["chairs"]:
				var img := "res://assets/cafe/chair_se.png" if ch["dir"] == Actor.Dir.SE else "res://assets/cafe/chair_sw.png"
				ch["node"] = _prop(img, ch["tile"], 10)
				astar.set_point_solid(ch["tile"], true)


func _load_customer_sheets() -> void:
	for i in 8:
		var t := tex("res://assets/chars/customer_%d.png" % i)
		if t:
			customer_sheets.append(t)


# ------------------------------------------------------------------ routing
func free_neighbor(t: Vector2i, toward: Vector2i) -> Vector2i:
	var best := t
	var best_d := 1 << 30
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = t + d
		if not astar.is_in_boundsv(n) or astar.is_point_solid(n):
			continue
		var dist: int = absi(n.x - toward.x) + absi(n.y - toward.y)
		if dist < best_d:
			best_d = dist
			best = n
	return best


func route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := from
	if astar.is_point_solid(from):
		start = free_neighbor(from, to)
		out.append(start)
	var goal := to
	var end_on_solid := astar.is_point_solid(to)
	if end_on_solid:
		goal = free_neighbor(to, start)
	var mid := astar.get_id_path(start, goal)
	for i in range(1, mid.size()):
		out.append(mid[i])
	if end_on_solid:
		out.append(to)
	return out


func walk(a: Actor, to: Vector2i) -> void:
	var tiles := route(a.tile, to)
	var pts: Array[Vector2] = []
	for t in tiles:
		pts.append(tile_pos(t))
	await a.go(pts, tiles)


func make_actor(sheet: Texture2D, rows: int, at: Vector2i) -> Actor:
	var a := Actor.new()
	a.setup(sheet, rows)
	a.tile = at
	a.position = tile_pos(at)
	world.add_child(a)
	return a


# ------------------------------------------------------------------ staff
func _spawn_staff(key: String) -> void:
	if staff_actors.has(key) or not GS.sheet_exists(key):
		return
	var sheet := tex("res://assets/chars/%s.png" % GS.STAFF[key]["sheet"])
	var a := make_actor(sheet, 4, REST_SPOT)
	a.speed = 42.0 * GS.stat(key, "serve")
	staff_actors[key] = a
	_staff_loop(key)


func _pick_task(key: String) -> Dictionary:
	var role: String = GS.staff[key]["role"]
	if role == "Rest":
		return {}
	var cook: Dictionary = {}
	var deliver: Dictionary = {}
	for o in orders:
		if o["state"] == "waiting" and cook.is_empty():
			cook = o
		elif o["state"] == "ready" and deliver.is_empty():
			deliver = o
	var cooks := _count_role("Chef")
	var waiters := _count_role("Waiter")
	if role == "Chef":
		if not cook.is_empty():
			return {"type": "cook", "order": cook}
		if waiters == 0 and not deliver.is_empty():
			return {"type": "deliver", "order": deliver}
	else:
		if not deliver.is_empty():
			return {"type": "deliver", "order": deliver}
		if cooks == 0 and not cook.is_empty():
			return {"type": "cook", "order": cook}
	return {}


func _count_role(role: String) -> int:
	var n := 0
	for k in GS.staff:
		if GS.staff[k]["role"] == role and staff_actors.has(k):
			n += 1
	return n


func _staff_loop(key: String) -> void:
	var a: Actor = staff_actors[key]
	while is_instance_valid(a):
		var task := _pick_task(key)
		if task.is_empty():
			var role: String = GS.staff[key]["role"]
			var idle := REST_SPOT if role == "Rest" else (CHEF_IDLE if role == "Chef" else WAITER_IDLE)
			if a.tile != idle:
				await walk(a, idle)
				a.face(Actor.Dir.SE)
			await get_tree().create_timer(0.4).timeout
			continue
		if task["type"] == "cook":
			await _do_cook(key, a, task["order"])
		else:
			await _do_deliver(key, a, task["order"])


func _do_cook(key: String, a: Actor, o: Dictionary) -> void:
	o["state"] = "cooking"
	await walk(a, COOK_SPOT)
	a.face_tile(STOVE)
	var food: Dictionary = GS.FOODS[o["food"]]
	var dur: float = food["cook"] / GS.stat(key, "cook")
	a.bubble.show_icon(tex("res://assets/food/small/%s.png" % o["food"]))
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		a.bubble.set_progress(t / dur, Color("f0a640"))
	a.bubble.visible = false
	a.bubble.set_progress(-1)
	if o["customer"]["state"] != "waiting":
		orders.erase(o)
		return
	await walk(a, PICKUP)
	a.face_tile(COUNTER)
	var dish := Sprite2D.new()
	dish.texture = tex("res://assets/food/small/%s.png" % o["food"])
	dish.position = tile_pos(COUNTER) + Vector2(-4 + counter_dishes.size() * 7, -30)
	dish.z_index = 5
	fx.add_child(dish)
	counter_dishes.append(dish)
	o["dish"] = dish
	o["state"] = "ready"


func _do_deliver(key: String, a: Actor, o: Dictionary) -> void:
	o["state"] = "delivering"
	await walk(a, PICKUP)
	a.face_tile(COUNTER)
	var dish: Sprite2D = o.get("dish")
	if is_instance_valid(dish):
		counter_dishes.erase(dish)
		dish.queue_free()
	_relayout_counter()
	var c: Dictionary = o["customer"]
	if c["state"] != "waiting":
		orders.erase(o)
		return
	a.carry.texture = tex("res://assets/food/small/%s.png" % o["food"])
	a.carry.visible = true
	var chair: Dictionary = c["chair"]
	await walk(a, free_neighbor(chair["tile"], a.tile))
	a.carry.visible = false
	orders.erase(o)
	if c["state"] != "waiting":
		return
	a.face_tile(chair["tile"])
	c["state"] = "served"
	c["server"] = key


func _relayout_counter() -> void:
	for i in counter_dishes.size():
		counter_dishes[i].position = tile_pos(COUNTER) + Vector2(-4 + i * 7, -30)


# ------------------------------------------------------------------ customers
func _free_chairs() -> Array:
	var out: Array = []
	for i in GS.tables_owned:
		for ch in tables[i]["chairs"]:
			if not ch["taken"]:
				out.append({"table": tables[i], "chair": ch})
	return out


func _spawn_customer() -> void:
	var free := _free_chairs()
	if free.is_empty():
		return
	var pick: Dictionary = free[randi() % free.size()]
	var chair: Dictionary = pick["chair"]
	chair["taken"] = true
	var a: Actor
	if customer_sheets.is_empty():
		a = make_actor(tex("res://assets/chars/chef.png"), 4, DOOR)
		a.modulate = Color.from_hsv(randf(), 0.35, 1.0)
	else:
		a = make_actor(customer_sheets[randi() % customer_sheets.size()], 2, DOOR)
	a.speed = 36.0
	var c := {"actor": a, "chair": chair, "table": pick["table"], "state": "walking", "patience": 45.0, "max_patience": 45.0}
	customers.append(c)
	_customer_flow(c)


func _customer_flow(c: Dictionary) -> void:
	var a: Actor = c["actor"]
	a.modulate.a = 0.0
	create_tween().tween_property(a, "modulate:a", 1.0, 0.4)
	await walk(a, c["chair"]["tile"])
	a.position += Vector2(0, -3)
	a.face(c["chair"]["dir"])
	var menu: Array = GS.unlocked
	var food: String = menu[randi() % menu.size()]
	c["food"] = food
	a.bubble.show_icon(tex("res://assets/food/small/%s.png" % food))
	c["state"] = "waiting"
	orders.append({"food": food, "customer": c, "state": "waiting"})
	while c["state"] == "waiting":
		await get_tree().process_frame
	a.bubble.visible = false
	if c["state"] == "served":
		var plate := Sprite2D.new()
		plate.texture = tex("res://assets/food/small/%s.png" % food)
		plate.position = tile_pos(c["table"]["tile"]) + Vector2(0, -22)
		plate.z_index = 5
		fx.add_child(plate)
		await get_tree().create_timer(5.0).timeout
		plate.queue_free()
		var price: int = GS.FOODS[food]["price"]
		var tip := int(round(price * GS.stat(c["server"], "charm")))
		GS.add_coins(price + tip)
		GS.served_total += 1
		GS.add_rep(1)
		_float_text(a.position + Vector2(0, -70), "+%d" % (price + tip), Color("ffd86b"))
		if randf() < 0.08:
			GS.gems += 10
			GS.changed.emit()
			_float_text(a.position + Vector2(0, -84), "+10 gems", Color("f08bd8"))
	else:
		_float_text(a.position + Vector2(0, -70), "Too slow...", Color("ff8a8a"))
	a.position += Vector2(0, 3)
	c["chair"]["taken"] = false
	await walk(a, DOOR)
	var tw := create_tween()
	tw.tween_property(a, "modulate:a", 0.0, 0.4)
	await tw.finished
	customers.erase(c)
	a.queue_free()


func _process(delta: float) -> void:
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = maxf(2.5, 8.0 - GS.rep_level * 0.4) + randf() * 3.0
		_spawn_customer()
	for c in customers:
		if c["state"] == "waiting":
			c["patience"] -= delta
			var p: float = c["patience"] / c["max_patience"]
			c["actor"].bubble.set_progress(p, Color("6cc46a") if p > 0.35 else Color("e05a5a"))
			if c["patience"] <= 0.0:
				c["state"] = "angry"
	save_t += delta
	if save_t > 15.0:
		save_t = 0.0
		GS.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GS.save_game()


func _float_text(at: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("2a1a22"))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 12)
	l.position = at - Vector2(20, 0)
	fx.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", at.y - 24, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ UI
func _sb(bg: Color, edge: Color, border: int = 2, pad: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s


func _build_ui() -> void:
	theme_ui = Theme.new()
	theme_ui.default_font_size = 12
	theme_ui.set_color("font_color", "Label", C_TEXT)
	theme_ui.set_stylebox("panel", "PanelContainer", _sb(C_PANEL, C_EDGE, 2, 8))
	theme_ui.set_stylebox("normal", "Button", _sb(C_PINK, C_EDGE, 2, 4))
	theme_ui.set_stylebox("hover", "Button", _sb(Color("f3a9b6"), C_EDGE, 2, 4))
	theme_ui.set_stylebox("pressed", "Button", _sb(C_PINK_DK, C_EDGE, 2, 4))
	theme_ui.set_stylebox("disabled", "Button", _sb(Color("c9b8b0"), Color("8a7a72"), 2, 4))
	theme_ui.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme_ui.set_color("font_color", "Button", Color("fffaf2"))
	theme_ui.set_color("font_hover_color", "Button", Color("fffaf2"))
	theme_ui.set_color("font_disabled_color", "Button", Color("f4ece6"))
	theme_ui.set_stylebox("normal", "OptionButton", _sb(Color("fff6ea"), C_EDGE, 2, 3))
	theme_ui.set_stylebox("hover", "OptionButton", _sb(Color("ffffff"), C_EDGE, 2, 3))
	theme_ui.set_color("font_color", "OptionButton", C_TEXT)
	theme_ui.set_color("font_hover_color", "OptionButton", C_TEXT)
	theme_ui.set_stylebox("background", "ProgressBar", _sb(Color("3b2a33"), Color("3b2a33"), 1, 0))
	theme_ui.set_stylebox("fill", "ProgressBar", _sb(Color("f2c14e"), Color("f2c14e"), 0, 0))

	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_ui
	ui.add_child(root)

	# top bar
	var top := PanelContainer.new()
	top.position = Vector2(6, 6)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	hud_coins = _icon_label(hb, "res://assets/gacha/coin.png", "coins")
	hud_gems = _icon_label(hb, "res://assets/gacha/gem.png", "gems")
	var rep := VBoxContainer.new()
	rep.add_theme_constant_override("separation", 1)
	hud_rep = Label.new()
	hud_rep.add_theme_font_size_override("font_size", 10)
	rep.add_child(hud_rep)
	hud_bar = ProgressBar.new()
	hud_bar.custom_minimum_size = Vector2(70, 5)
	hud_bar.show_percentage = false
	rep.add_child(hud_bar)
	hb.add_child(rep)

	# side buttons
	var side := VBoxContainer.new()
	side.position = Vector2(6, 236)
	side.add_theme_constant_override("separation", 4)
	root.add_child(side)
	for pair in [["Menu", _open_menu], ["Staff", _open_staff], ["Summon", _open_summon], ["Shop", _open_shop]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(70, 24)
		b.pressed.connect(pair[1])
		side.add_child(b)

	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(440, 8)
	toast_box.custom_minimum_size = Vector2(194, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)


func _icon_label(parent: Control, icon_path: String, fallback: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var t := tex(icon_path)
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		box.add_child(tr)
	var l := Label.new()
	l.text = fallback
	box.add_child(l)
	parent.add_child(box)
	return l


func _refresh_hud() -> void:
	hud_coins.text = "%d" % GS.coins + ("" if tex("res://assets/gacha/coin.png") else " coins")
	hud_gems.text = "%d" % GS.gems + ("" if tex("res://assets/gacha/gem.png") else " gems")
	hud_rep.text = "Café Lv %d" % GS.rep_level
	hud_bar.max_value = GS.rep_needed()
	hud_bar.value = GS.rep_xp


func _toast(msg: String) -> void:
	var p := PanelContainer.new()
	var l := Label.new()
	l.text = msg
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(180, 0)
	l.add_theme_font_size_override("font_size", 10)
	p.add_child(l)
	toast_box.add_child(p)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _open_panel(title: String, size := Vector2(420, 290)) -> VBoxContainer:
	for ch in overlay.get_children():
		ch.queue_free()
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.1, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.size = size
	panel.position = ((Vector2(640, 360) - size) / 2).floor()
	overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 16)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var x := Button.new()
	x.text = "X"
	x.custom_minimum_size = Vector2(22, 20)
	x.pressed.connect(_close_panel)
	head.add_child(x)
	v.add_child(head)
	return v


func _scroll(v: VBoxContainer) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	return list


func _close_panel() -> void:
	overlay.visible = false
	for ch in overlay.get_children():
		ch.queue_free()


func _small_label(text: String, size: int = 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


# ---- menu
func _open_menu() -> void:
	var list := _scroll(_open_panel("Menu"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	list.add_child(grid)
	for key in GS.FOODS:
		var f: Dictionary = GS.FOODS[key]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(196, 30)
		var icon := TextureRect.new()
		icon.texture = tex("res://assets/food/small/%s.png" % key)
		icon.custom_minimum_size = Vector2(28, 28)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(_small_label(f["name"], 11))
		info.add_child(_small_label("%d coins · %.0fs" % [f["price"], f["cook"]], 9))
		row.add_child(info)
		if key in GS.unlocked:
			row.add_child(_small_label("On menu", 9))
		else:
			var b := Button.new()
			b.text = "Unlock %d" % f["unlock"]
			b.add_theme_font_size_override("font_size", 9)
			b.disabled = GS.coins < f["unlock"]
			b.pressed.connect(func():
				if GS.unlock_food(key):
					_toast("%s added to the menu!" % f["name"])
				_open_menu())
			row.add_child(b)
		grid.add_child(row)


# ---- staff
func _portrait(key: String) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = tex("res://assets/chars/%s.png" % GS.STAFF[key]["sheet"])
	var fw := at.atlas.get_width() / 3.0
	var fh := at.atlas.get_height() / 4.0
	at.region = Rect2(fw, 0, fw, fh)
	var tr := TextureRect.new()
	tr.texture = at
	tr.custom_minimum_size = Vector2(fw, fh)
	return tr


func _open_staff() -> void:
	var list := _scroll(_open_panel("Staff"))
	var roles := ["Chef", "Waiter", "Rest"]
	for key in GS.staff:
		var d: Dictionary = GS.STAFF[key]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _sb(Color("fff6ea"), RARITY_COL[d["rarity"]], 2, 4))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)
		hb.add_child(_portrait(key))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		info.add_child(_small_label("%s  [%s]  Lv %d" % [d["name"], d["rarity"], GS.staff[key]["level"]], 12))
		info.add_child(_small_label(d["title"], 10))
		info.add_child(_small_label("Cook x%.2f   Speed x%.2f   Tips %d%%" % [GS.stat(key, "cook"), GS.stat(key, "serve"), int(GS.stat(key, "charm") * 100)], 9))
		hb.add_child(info)
		var ob := OptionButton.new()
		for r in roles:
			ob.add_item(r)
		ob.selected = roles.find(GS.staff[key]["role"])
		ob.item_selected.connect(func(i: int):
			GS.staff[key]["role"] = roles[i]
			GS.save_game())
		hb.add_child(ob)
		list.add_child(row)


# ---- summon
func _open_summon() -> void:
	var v := _open_panel("Summon", Vector2(420, 300))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(hb)
	var machine := TextureRect.new()
	machine.texture = tex("res://assets/gacha/machine.png")
	machine.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	machine.custom_minimum_size = Vector2(150, 200)
	hb.add_child(machine)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	hb.add_child(info)
	info.add_child(_small_label("Starlight Staff Summon", 14))
	info.add_child(_small_label("SSR 5%   SR 20%   R 75%", 10))
	info.add_child(_small_label("10-pull guarantees SR or better.\nDuplicates level up your staff.", 10))
	var featured := HBoxContainer.new()
	for k in GS.STAFF:
		if GS.STAFF[k]["rarity"] == "SSR" and GS.sheet_exists(k):
			featured.add_child(_portrait(k))
	info.add_child(featured)
	info.add_child(_small_label("You have %d gems" % GS.gems, 11))
	var b1 := Button.new()
	b1.text = "Summon x1  (%d gems)" % GS.PULL_COST
	b1.disabled = GS.gems < GS.PULL_COST
	b1.pressed.connect(func(): _do_pull(1, machine))
	info.add_child(b1)
	var b10 := Button.new()
	b10.text = "Summon x10  (%d gems)" % GS.PULL10_COST
	b10.disabled = GS.gems < GS.PULL10_COST
	b10.pressed.connect(func(): _do_pull(10, machine))
	info.add_child(b10)


func _do_pull(n: int, machine: Control) -> void:
	var results := GS.pull(n)
	if results.is_empty():
		_toast("Not enough gems!")
		return
	var tw := create_tween()
	for i in 6:
		tw.tween_property(machine, "position:x", machine.position.x + (3 if i % 2 == 0 else -3), 0.05)
	tw.tween_property(machine, "position:x", machine.position.x, 0.05)
	await tw.finished
	# a capsule of the best rarity pops out, wobbles, then bursts
	var best := "r"
	for r in results:
		var rar: String = GS.STAFF[r["key"]]["rarity"]
		if rar == "SSR" or (rar == "SR" and best == "r"):
			best = rar.to_lower()
	var cap := TextureRect.new()
	cap.texture = tex("res://assets/gacha/capsule_%s.png" % best)
	cap.position = Vector2(304, 140)
	cap.pivot_offset = Vector2(16, 16)
	overlay.add_child(cap)
	var ctw := create_tween()
	ctw.tween_property(cap, "position:y", 170.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for i in 4:
		ctw.tween_property(cap, "rotation", 0.3 if i % 2 == 0 else -0.3, 0.08)
	ctw.tween_property(cap, "rotation", 0.0, 0.08)
	await ctw.finished
	var spark := TextureRect.new()
	spark.texture = tex("res://assets/gacha/sparkle.png")
	spark.position = cap.position - Vector2(-4, -4)
	spark.pivot_offset = Vector2(12, 12)
	overlay.add_child(spark)
	cap.queue_free()
	var stw := create_tween()
	stw.tween_property(spark, "scale", Vector2(4, 4), 0.3)
	stw.parallel().tween_property(spark, "modulate:a", 0.0, 0.3)
	await stw.finished
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "modulate:a", 0.0, 0.5)
	ftw.tween_callback(flash.queue_free)
	_show_results(results)
	for r in results:
		_spawn_staff(r["key"])


func _show_results(results: Array) -> void:
	var v := _open_panel("Summon Results", Vector2(440, 300) if results.size() > 1 else Vector2(220, 240))
	var grid := GridContainer.new()
	grid.columns = 5 if results.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var best := "R"
	for i in results.size():
		var r: Dictionary = results[i]
		var d: Dictionary = GS.STAFF[r["key"]]
		if d["rarity"] == "SSR" or (d["rarity"] == "SR" and best == "R"):
			best = d["rarity"]
		var card := PanelContainer.new()
		var frame_tex := tex("res://assets/gacha/frame_%s.png" % d["rarity"].to_lower())
		if frame_tex:
			var sbt := StyleBoxTexture.new()
			sbt.texture = frame_tex
			sbt.set_texture_margin_all(10 if d["rarity"] == "SSR" else 8)
			sbt.set_content_margin_all(7)
			card.add_theme_stylebox_override("panel", sbt)
		else:
			card.add_theme_stylebox_override("panel", _sb(Color("2e2240"), RARITY_COL[d["rarity"]], 3, 4))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 1)
		card.add_child(cv)
		var pr := _portrait(r["key"])
		pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(pr)
		var nl := _small_label("%s %s" % [d["rarity"], d["name"]], 9)
		nl.add_theme_color_override("font_color", C_TEXT if frame_tex else RARITY_COL[d["rarity"]])
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nl)
		var tag := _small_label("NEW!" if r["new"] else "Lv %d" % r["level"], 9)
		tag.add_theme_color_override("font_color", C_PINK_DK if frame_tex else Color("ffffff"))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(tag)
		card.modulate.a = 0.0
		grid.add_child(card)
		var tw := create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(card, "modulate:a", 1.0, 0.25)
	if best == "SSR":
		_toast("SSR! A legendary new face joins the café!")
	var again := Button.new()
	again.text = "Back to Summon"
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_open_summon)
	v.add_child(again)


# ---- shop
func _open_shop() -> void:
	var v := _open_panel("Shop", Vector2(320, 200))
	if GS.tables_owned < GS.TABLE_COSTS.size():
		var cost: int = GS.TABLE_COSTS[GS.tables_owned]
		var b := Button.new()
		b.text = "Add a table (2 seats)  -  %d coins" % cost
		b.disabled = GS.coins < cost
		b.pressed.connect(func():
			if GS.buy_table():
				_refresh_tables()
				_toast("New table placed!")
			_open_shop())
		v.add_child(b)
	else:
		v.add_child(_small_label("All tables placed.", 11))
	var g := Button.new()
	g.text = "Trade %d coins  ->  %d gems" % [GS.GEM_TRADE["coins"], GS.GEM_TRADE["gems"]]
	g.disabled = GS.coins < GS.GEM_TRADE["coins"]
	g.pressed.connect(func():
		if GS.trade_gems():
			_toast("Gems acquired!")
		_open_shop())
	v.add_child(g)
	v.add_child(_small_label("Reaching a new Café Lv gives +50 gems.", 10))


# ------------------------------------------------------------------ drawing helpers
class BgNode extends Node2D:
	func _draw() -> void:
		var top := Color("1c1838")
		var bot := Color("5a3f74")
		for y in range(0, 360, 4):
			draw_rect(Rect2(0, y, 640, 4), top.lerp(bot, y / 360.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		for i in 70:
			var p := Vector2(rng.randi_range(0, 639), rng.randi_range(0, 200))
			draw_rect(Rect2(p, Vector2.ONE * (2 if rng.randf() < 0.15 else 1)), Color(1, 1, 0.9, rng.randf_range(0.4, 1.0)))
		for i in 6:
			var c := Vector2(rng.randi_range(0, 640), rng.randi_range(250, 350))
			for j in 4:
				var r := rng.randi_range(14, 28)
				draw_circle(c + Vector2(j * 18 - 27, rng.randi_range(-6, 6)), r, Color("7a5c95"))


class WallNode extends Node2D:
	var origin: Vector2
	var cols: int
	var rows: int
	var hw: int
	var hh: int
	var wall_h: int

	func _draw() -> void:
		var t := origin
		var r := origin + Vector2(cols * hw, cols * hh)
		var l := origin + Vector2(-rows * hw, rows * hh)
		var up := Vector2(0, -wall_h)
		var wain := Vector2(0, -22)
		_wall(l, t, up, wain, Color("e9cdbb"), Color("8c5a3a"), Color("a56c46"))
		_wall(t, r, up, wain, Color("f6dccb"), Color("9c6542"), Color("b77b52"))
		draw_line(t, t + up, Color("6b4630"), 2)

	func _wall(a: Vector2, b: Vector2, up: Vector2, wain: Vector2, plaster: Color, wood_dk: Color, wood: Color) -> void:
		draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), plaster)
		draw_colored_polygon(PackedVector2Array([a, b, b + wain, a + wain]), wood)
		draw_line(a + wain, b + wain, wood_dk, 2)
		draw_line(a + up, b + up, Color("6b4630"), 3)
		draw_line(a + up + Vector2(0, 3), b + up + Vector2(0, 3), Color("c99572"), 1)
