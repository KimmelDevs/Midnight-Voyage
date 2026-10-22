extends Node2D
## The Sky Café airship. The café map is the ship's deck, built tile by tile
## from GS.ship: an indoor cabin (kitchen) at the stern and an open deck with
## railings, over a hull drawn from the deck outline. Customers come aboard by
## the gangway; chefs cook, baristas brew, waiters serve, hostesses greet,
## cleaners wash dishes. Days: open -> closing -> night (edit furniture).

const HW := 29            # half tile width (px)
const HH := 18            # half tile height (px)
const TILE_ANCHOR := Vector2(29, 18)  # diamond centre inside the floor tile image
const ORIGIN := Vector2(240, 70)   # top vertex of deck tile (0,0)
const WALL_H := 74
const HULL_DEPTH := 78.0           # hull height under the middle of the ship

const REST_SPOT := Vector2i(1, 5)
const IDLE_SPOTS := {
	"Chef": Vector2i(1, 1), "Barista": Vector2i(1, 2), "Waiter": Vector2i(4, 4),
	"Hostess": Vector2i(6, 4), "Cleaner": Vector2i(2, 4), "Rest": REST_SPOT,
}
## rot 0..3: facing SE, SW, NW, NE (+c, +r, -c, -r). 0/1 use the front art
## (1 mirrored); 2/3 use the <item>_back art when it exists.
const ROT_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

const C_TEXT := Color("4a2f2a")
const C_PANEL := Color("f7e9d3")
const C_EDGE := Color("6b4630")
const C_PINK := Color("e98b9c")
const C_PINK_DK := Color("b85d70")
const RARITY_COL := {"R": Color("aab4c4"), "SR": Color("b07ce8"), "SSR": Color("f2c14e")}
const NIGHT_TINT := Color(0.55, 0.56, 0.82)
const SEAT_SLIDE := 0.35   # fraction of the chair->table step a seated customer moves in

# ship geometry (from GS.ship)
var COLS := 1
var ROWS := 1
var DOOR := Vector2i.ZERO          # gangway tile
var deck := {}                     # Vector2i -> true
var cabin := Rect2i()

var astar := AStarGrid2D.new()
var ship_root: Node2D
var camera: Camera2D
var world: Node2D
var rug_layer: Node2D
var fx: Node2D
var ui: CanvasLayer
var tint: CanvasModulate
var hud_coins: Label
var hud_gems: Label
var hud_rep: Label
var hud_bar: ProgressBar
var hud_day: Label
var toast_box: VBoxContainer
var overlay: Control
var night_bar: VBoxContainer
var edit_bar: PanelContainer
var edit_list: VBoxContainer
var edit_hint: Label

# layout (rebuilt from GS.placed)
var furn_nodes: Array = []      # sprites of placed items
var occupied := {}              # Vector2i -> index into GS.placed (solid items)
var rug_at := {}                # Vector2i -> index into GS.placed (rugs)
var seats: Array = []           # {tile, dir, table, taken, dirty, plate, cleaning}
var stations := {}              # kind -> Array[Vector2i]
var station_busy := {}          # Vector2i -> staff key
var counter_dishes := {}        # counter tile -> Array[Sprite2D]

var customers: Array = []
var orders: Array = []
var staff_actors := {}
var stamina := {}               # key -> current stamina
var tired := {}                 # key -> bool
var working := {}               # key -> bool (doing a task)
var dirty_dishes := 0           # plates waiting at the sink
var spawn_t := 3.0
var save_t := 0.0
var bob_t := 0.0
var customer_sheets: Array[Texture2D] = []
var theme_ui: Theme
var kit := {}                   # ship-kit piece anchors (assets/ship/kit.json)

# day cycle: "open" -> "closing" -> "night"
var phase := "open"
var day_t := 0.0

# battles
var battle: BattleScene
var prep_enc: EncounterData
var prep_team: Array[String] = []
var prep_meal := -1

# edit mode
var editing := false
var held: Dictionary = {}       # {item, rot, from: Vector2i or null}
var ghost: Sprite2D
var grid_node: GridNode
var hover := Vector2i(-1, -1)


# ------------------------------------------------------------------ setup
func _ready() -> void:
	randomize()
	_load_ship()
	tint = CanvasModulate.new()
	add_child(tint)
	var sky := CanvasLayer.new()
	sky.layer = -1
	add_child(sky)
	sky.add_child(BgNode.new())
	sky.add_child(CloudNode.new())
	ship_root = Node2D.new()
	add_child(ship_root)
	camera = Camera2D.new()
	camera.position = _ship_center() + Vector2(-60, -95)
	add_child(camera)
	_build_ship()
	rug_layer = Node2D.new()
	rug_layer.z_index = -9
	ship_root.add_child(rug_layer)
	world = Node2D.new()
	world.y_sort_enabled = true
	ship_root.add_child(world)
	_build_front_rails()
	fx = Node2D.new()
	fx.z_index = 50
	ship_root.add_child(fx)
	grid_node = GridNode.new()
	grid_node.main = self
	grid_node.z_index = -8
	grid_node.visible = false
	ship_root.add_child(grid_node)
	ghost = Sprite2D.new()
	ghost.centered = false
	ghost.z_index = 60
	ghost.visible = false
	ship_root.add_child(ghost)
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	_apply_layout()
	_load_customer_sheets()
	_build_ui()
	for key in GS.staff:
		_spawn_staff(key)
	GS.changed.connect(_refresh_hud)
	_refresh_hud()
	_toast("Day %d - the Sky Café is open!" % GS.day)
	var args := OS.get_cmdline_user_args()
	# `godot -- --demo-staff` / `--demo-menu` / `--demo-night` / `--demo-shop` (screenshots/tests)
	if "--demo-night" in args:
		day_t = GS.DAY_LENGTH
	if "--demo-edit" in args:  # night, then pick up / rotate / re-place a chair and the stove
		phase = "closing"
		await get_tree().create_timer(1.0).timeout
		_set_editing(true)
		hover = Vector2i(2, 2)
		_pick_up(Vector2i(2, 2))
		_rotate_held()
		_rotate_held()
		_place(Vector2i(2, 2))
		_pick_up(Vector2i(0, 1))
		_rotate_held()
		_update_ghost()
		await get_tree().create_timer(1.0).timeout
		_place(Vector2i(0, 1))
	if "--demo-battle" in args or "--demo-boss" in args:  # auto-run an encounter with the first 3 crew
		await get_tree().create_timer(1.0).timeout
		prep_enc = BattleDB.encounters()[3 if "--demo-boss" in args else 0]
		prep_team.assign(GS.staff.keys().slice(0, 3))
		prep_meal = -1
		if "--demo-meal" in args:
			GS.coins += 100
			GS.pack_meal(GS.unlocked[0])
			prep_meal = GS.meals.size() - 1
		_start_battle()
		battle.manager.speed_mult = 2.0
		if "--demo-return" in args:  # press "Return to Café" once results are up
			while not battle.result_shown:
				await get_tree().create_timer(0.5).timeout
			await get_tree().create_timer(2.0).timeout
			_end_battle()
	if "--demo-board" in args:
		await get_tree().create_timer(1.0).timeout
		_open_board()
	if "--demo-prepare" in args:
		await get_tree().create_timer(1.0).timeout
		prep_enc = BattleDB.encounters()[0]
		prep_team.assign(GS.staff.keys().slice(0, 3))
		_open_prepare()
	if "--demo-staff" in args:
		await get_tree().create_timer(3.0).timeout
		_open_staff()
	if "--demo-menu" in args:
		await get_tree().create_timer(1.0).timeout
		_open_menu()
	if "--demo-shop" in args:
		await get_tree().create_timer(1.0).timeout
		_open_shop()
	if "--demo-pan" in args:  # glide the camera along the ship
		var tw := create_tween()
		tw.tween_property(camera, "position", camera.position + Vector2(160, 60), 3.0)
		tw.tween_property(camera, "position", camera.position + Vector2(-140, -40), 3.0)
	# `godot -- --demo-summon` showcases a 10-pull (used for screenshots/tests)
	if "--demo-summon" in args:
		await get_tree().create_timer(1.0).timeout
		GS.gems += GS.PULL10_COST
		_open_summon()
		await get_tree().create_timer(1.0).timeout
		_do_pull(10, overlay.get_child(1).get_child(0).get_child(1).get_child(0))


func tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func tile_pos(t: Vector2i) -> Vector2:
	return ORIGIN + Vector2((t.x - t.y) * HW, (t.x + t.y) * HH + HH)


func pos_tile(p: Vector2) -> Vector2i:
	var q := p - ORIGIN - Vector2(0, HH)
	var a := q.x / HW
	var b := q.y / HH
	return Vector2i(roundi((a + b) / 2.0), roundi((b - a) / 2.0))


## Tile under the mouse (the ship bobs, so use its local space).
func mouse_tile() -> Vector2i:
	return pos_tile(ship_root.get_local_mouse_position())


func in_room(t: Vector2i) -> bool:
	return deck.has(t)


# ------------------------------------------------------------------ the ship
func _load_ship() -> void:
	var rows: Array = GS.ship["deck"]
	ROWS = rows.size()
	COLS = 0
	for r in rows.size():
		var line: String = rows[r]
		COLS = maxi(COLS, line.length())
		for c in line.length():
			if line[c] == "X":
				deck[Vector2i(c, r)] = true
	var cb: Array = GS.ship["cabin"]
	cabin = Rect2i(int(cb[0]), int(cb[1]), int(cb[2]), int(cb[3]))
	DOOR = Vector2i(int(GS.ship["gangway"][0]), int(GS.ship["gangway"][1]))


func in_cabin(t: Vector2i) -> bool:
	return cabin.has_point(t)


func _ship_center() -> Vector2:
	return tile_pos(Vector2i(COLS / 2, ROWS / 2)) + Vector2(0, 30)


## Deck tiles in back-to-front order (so floor tiles overlap correctly).
func _deck_tiles_sorted() -> Array:
	var out: Array = deck.keys()
	out.sort_custom(func(a, b): return a.x + a.y < b.x + b.y or (a.x + a.y == b.x + b.y and a.x < b.x))
	return out


func _build_ship() -> void:
	var f := FileAccess.open("res://assets/ship/kit.json", FileAccess.READ)
	if f:
		kit = JSON.parse_string(f.get_as_text())
	var C := COLS
	var R := ROWS
	var v := func(c: int, r: int, corner: String) -> Vector2:
		var p := tile_pos(Vector2i(c, r))
		match corner:
			"top": return p + Vector2(0, -HH)
			"right": return p + Vector2(HW, 0)
			"bottom": return p + Vector2(0, HH)
		return p + Vector2(-HW, 0)
	# hull: the long side (lower-left faces) in 2-tile sections, portholes alternating
	for c in range(0, C - 1, 2):
		var piece := "hull_port" if (c / 2) % 2 == 1 else "hull_a"
		_kit_edge(piece, "top", v.call(c, R - 1, "left"), v.call(c + 1, R - 1, "bottom"), -12)
	# hull: the bow end (lower-right faces), mirrored sections
	for r in range(0, R - 1, 2):
		var piece := "hull_port" if (r / 2) % 2 == 1 else "hull_a"
		_kit_edge(piece, "top", v.call(C - 1, r, "right"), v.call(C - 1, r + 1, "bottom"), -12)
	# lower belly row, a little shorter at each end, so the hull curves under the deck
	var drop := Vector2(0, 27)
	for c in range(2, C - 3, 2):
		_kit_edge("hull_b" if (c / 2) % 2 == 0 else "hull_port_b", "top", v.call(c, R - 1, "left") + drop,
			v.call(c + 1, R - 1, "bottom") + drop, -13)
	for r in range(2, R - 3, 2):
		_kit_edge("hull_b", "top", v.call(C - 1, r, "right") + drop, v.call(C - 1, r + 1, "bottom") + drop, -13)
	_kit_at("bow", v.call(C - 1, R - 1, "bottom") + Vector2(0, -8), -11, Vector2(0.5, 0.0))
	_kit_at("stern", v.call(0, R - 1, "left") + Vector2(-6, -6), -11, Vector2(0.5, 0.0))
	_kit_at("propeller", v.call(0, R - 1, "left") + Vector2(-24, 40), -11, Vector2(0.5, 0.5), true)
	_kit_at("propeller", v.call(C - 1, 0, "right") + Vector2(18, 40), -11, Vector2(0.5, 0.5))
	# cabin back walls with arched windows
	for c in range(cabin.position.x, cabin.end.x - 1, 2):
		_kit_edge("wall_window_a", "bottom", v.call(c, cabin.position.y, "top"),
			v.call(c + 1, cabin.position.y, "right"), -15)
	for r in range(cabin.position.y, cabin.end.y - 1, 2):
		_kit_edge("wall_window_b", "bottom", v.call(cabin.position.x, r + 1, "left"),
			v.call(cabin.position.x, r, "top"), -15)
	var corner: Vector2 = v.call(cabin.position.x, cabin.position.y, "top")
	_kit_at("dome", corner + Vector2(0, -74), -14, Vector2(0.5, 1.0))
	_kit_at("awning", v.call(cabin.end.x - 1, cabin.position.y, "right") + Vector2(-8, -40), -13, Vector2(0.5, 0.5))
	# back railings beyond the cabin
	for c in range(cabin.end.x, C - 1, 2):
		_kit_edge("rail_a", "bottom", v.call(c, 0, "top"), v.call(c + 1, 0, "right"), -11)
	for r in range(cabin.end.y, R - 1, 2):
		_kit_edge("rail_a", "bottom", v.call(0, r, "top"), v.call(0, r + 1, "left"), -11)
	# deck floor: cabin checker inside, planks outside
	var wood := tex("res://assets/cafe/floor_wood.png")
	var check := tex("res://assets/cafe/floor_check.png")
	for t in _deck_tiles_sorted():
		var s := Sprite2D.new()
		s.texture = check if in_cabin(t) else wood
		s.centered = false
		s.position = tile_pos(t) - TILE_ANCHOR
		s.z_index = -10
		ship_root.add_child(s)


## Front railings, lantern posts and the gangway are y-sorted with the
## furniture so they pass in front of whatever stands behind them.
func _build_front_rails() -> void:
	var C := COLS
	var R := ROWS
	for c in range(0, C - 1, 2):
		if DOOR.y == R - 1 and (DOOR.x == c or DOOR.x == c + 1):
			continue  # gap for the gangway
		var a := tile_pos(Vector2i(c, R - 1)) + Vector2(-HW, 0)
		var b := tile_pos(Vector2i(c + 1, R - 1)) + Vector2(0, HH)
		_kit_edge("rail_a", "bottom", a, b, 0, true)
	for r in range(0, R - 1, 2):
		var a := tile_pos(Vector2i(C - 1, r)) + Vector2(HW, 0)
		var b := tile_pos(Vector2i(C - 1, r + 1)) + Vector2(0, HH)
		_kit_edge("rail_a", "bottom", a, b, 0, true)
	for corner in [tile_pos(Vector2i(0, R - 1)) + Vector2(-HW, 0), tile_pos(Vector2i(C - 1, R - 1)) + Vector2(0, HH),
			tile_pos(Vector2i(C - 1, 0)) + Vector2(HW, 0)]:
		_kit_at("post", corner + Vector2(0, 2), 0, Vector2(0.5, 1.0), false, true)
	var gate := tile_pos(DOOR) + Vector2(-HW / 2.0, HH / 2.0)
	_kit_at("post", gate + Vector2(-16, -8), 0, Vector2(0.5, 1.0), false, true)
	_kit_at("post", gate + Vector2(14, 10), 0, Vector2(0.5, 1.0), false, true)
	_kit_at("gangway", gate + Vector2(-22, 22), 0, Vector2(0.5, 0.5), true, true)


## Lay a kit piece along a tile edge: its anchor line (top or bottom edge of
## the art, from kit.json) is stretched/sheared onto a -> b. When a is the
## right-hand end the piece comes out mirrored (other side of the ship).
func _kit_edge(piece: String, edge: String, a: Vector2, b: Vector2, z: int, sorted := false) -> void:
	var t := tex("res://assets/ship/%s.png" % piece)
	if t == null or not kit.has(piece):
		return
	var m: Array = kit[piece][edge]
	var s := Vector2(m[0][0], m[0][1])
	var e := Vector2(m[1][0], m[1][1])
	var sx := (b.x - a.x) / (e.x - s.x)
	var k := (b.y - a.y - (e.y - s.y)) / (e.x - s.x)
	var spr := Sprite2D.new()
	spr.texture = t
	spr.centered = false
	var origin := a - Vector2(sx * s.x, s.y + k * s.x)
	if sorted:  # y-sort by the edge's middle
		var holder := Node2D.new()
		holder.position = ((a + b) / 2.0 + Vector2(0, 2)).round()
		spr.transform = Transform2D(Vector2(sx, k), Vector2(0, 1), origin - holder.position)
		holder.add_child(spr)
		world.add_child(holder)
	else:
		spr.transform = Transform2D(Vector2(sx, k), Vector2(0, 1), origin)
		spr.z_index = z
		ship_root.add_child(spr)


## Place a kit piece with its pivot (fractions of its size) at a point.
func _kit_at(piece: String, at: Vector2, z: int, pivot: Vector2, flip := false, sorted := false) -> void:
	var t := tex("res://assets/ship/%s.png" % piece)
	if t == null:
		return
	var spr := Sprite2D.new()
	spr.texture = t
	spr.centered = false
	spr.flip_h = flip
	spr.offset = (-t.get_size() * pivot).round()
	if sorted:
		spr.position = at.round()
		world.add_child(spr)
	else:
		spr.position = at.round()
		spr.z_index = z
		ship_root.add_child(spr)


func _wall_decor(path: String, t: float, left_wall: bool) -> void:
	var tx := tex(path)
	if tx == null:
		return
	var s := Sprite2D.new()
	s.texture = tx
	s.centered = false
	s.offset = Vector2(-tx.get_width() / 2.0, -tx.get_height()).floor()
	var k := float(HH) / HW - 0.375
	var o := tile_pos(cabin.position) - Vector2(0, HH)
	var base: Vector2
	if left_wall:
		base = o + Vector2(-t * HW, t * HH)
		s.transform = Transform2D(Vector2(-1, k), Vector2(0, 1), base + Vector2(0, -2))
	else:
		base = o + Vector2(t * HW, t * HH)
		s.transform = Transform2D(Vector2(1, k), Vector2(0, 1), base + Vector2(0, -2))
	s.z_index = -14
	ship_root.add_child(s)


# ------------------------------------------------------------------ layout
func _kind(item: String) -> String:
	return GS.ITEMS[item]["kind"]


## Texture + mirror flag for an item at a rotation.
func _item_look(item: String, rot: int) -> Array:
	if rot >= 2:
		var back := tex(GS.item_tex_path(item).replace(".png", "_back.png"))
		if back:
			# back art faces NW; "back_flip" items were drawn facing NE instead
			return [back, (rot == 3) != bool(GS.ITEMS[item].get("back_flip", false))]
	return [tex(GS.item_tex_path(item)), rot % 2 == 1]


func _rotations(item: String) -> int:
	return 4 if ResourceLoader.exists(GS.item_tex_path(item).replace(".png", "_back.png")) else 2


func _make_sprite(item: String, rot: int, t: Vector2i) -> Sprite2D:
	var look := _item_look(item, rot)
	var tx: Texture2D = look[0]
	var s := Sprite2D.new()
	s.texture = tx
	s.flip_h = look[1]
	s.centered = false
	if tx:
		# base of the art sits on the tile's lower vertex area
		var foot := 6.0 if _kind(item) == "rug" else 12.0
		s.offset = Vector2(-tx.get_width() / 2.0, -tx.get_height() + foot).floor()
	s.position = tile_pos(t)
	return s


## Rebuild sprites, path grid, seats and stations from GS.placed.
func _apply_layout() -> void:
	for n in furn_nodes:
		n.queue_free()
	furn_nodes.clear()
	occupied.clear()
	rug_at.clear()
	stations.clear()
	astar.fill_solid_region(astar.region, false)
	for c in COLS:
		for r in ROWS:
			if not deck.has(Vector2i(c, r)):
				astar.set_point_solid(Vector2i(c, r), true)  # open sky
	for i in GS.placed.size():
		var p: Dictionary = GS.placed[i]
		var t := Vector2i(p["c"], p["r"])
		var s := _make_sprite(p["item"], p["rot"], t)
		if _kind(p["item"]) == "rug":
			rug_layer.add_child(s)
			rug_at[t] = i
		else:
			world.add_child(s)
			occupied[t] = i
			astar.set_point_solid(t, true)
			var k := _kind(p["item"])
			if not stations.has(k):
				stations[k] = []
			stations[k].append(t)
		furn_nodes.append(s)
	# a chair is a seat when it faces a table
	var old := {}
	for s in seats:
		old[s["tile"]] = s
	seats.clear()
	for t in occupied:
		var p: Dictionary = GS.placed[occupied[t]]
		if _kind(p["item"]) != "chair":
			continue
		var facing: Vector2i = t + ROT_DIRS[p["rot"]]
		if occupied.has(facing) and _kind(GS.placed[occupied[facing]]["item"]) == "table":
			var seat := {"tile": t, "dir": p["rot"], "table": facing, "taken": false, "dirty": false,
				"plate": null, "cleaning": false}
			if old.has(t) and old[t]["table"] == facing:
				seat = old[t]
			seats.append(seat)
	for t in counter_dishes.keys():
		if not occupied.has(t):
			for d in counter_dishes[t]:
				d.queue_free()
			counter_dishes.erase(t)
	if grid_node:
		grid_node.queue_redraw()


func _station_list(kind: String) -> Array:
	return stations.get(kind, [])


## Where to stand to use a station: its front tile if free, else any free side.
func work_tile(st: Vector2i) -> Vector2i:
	var p: Dictionary = GS.placed[occupied[st]]
	var order: Array[Vector2i] = [ROT_DIRS[p["rot"]]]
	for d in ROT_DIRS:
		if d != order[0]:
			order.append(d)
	for d in order:
		var n: Vector2i = st + d
		if in_room(n) and not astar.is_point_solid(n):
			return n
	return st


func _nearest_station(kind: String, from: Vector2i, need_free: bool, key: String = "") -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for st in _station_list(kind):
		if need_free and station_busy.has(st) and station_busy[st] != key:
			continue
		var d: int = absi(st.x - from.x) + absi(st.y - from.y)
		if d < best_d:
			best_d = d
			best = st
	return best


## Free tile closest to `want` (staff idle spots may get covered by furniture).
func free_spot(want: Vector2i) -> Vector2i:
	if in_room(want) and not astar.is_point_solid(want) and want != DOOR:
		return want
	var best := want
	var best_d := 1 << 30
	for t in deck:
		if astar.is_point_solid(t) or t == DOOR:
			continue
		var d: int = absi(t.x - want.x) + absi(t.y - want.y)
		if d < best_d:
			best_d = d
			best = t
	return best


## Placement is fine as long as everything people actually use stays reachable
## from the door: work stations (stove, espresso, counter, sink) and chairs that
## face a table. Decor, tables, fridges, racks and spare chairs may block freely.
func layout_ok(extra_solid: Vector2i = Vector2i(-1, -1)) -> bool:
	var extra_kind := "" if held.is_empty() else _kind(held["item"])
	var extra_rot: int = 0 if held.is_empty() else held["rot"]
	var kind_at := func(t: Vector2i) -> String:
		if t == extra_solid:
			return extra_kind
		return _kind(GS.placed[occupied[t]]["item"]) if occupied.has(t) else ""
	var seen := {DOOR: true}
	var queue: Array[Vector2i] = [DOOR]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_front()
		for d in ROT_DIRS:
			var n: Vector2i = t + d
			if in_room(n) and not seen.has(n) and kind_at.call(n) == "":
				seen[n] = true
				queue.append(n)
	var tiles: Array = occupied.keys()
	if in_room(extra_solid):
		tiles.append(extra_solid)
	for t in tiles:
		var k: String = kind_at.call(t)
		var needs := k in ["stove", "espresso", "counter", "sink"]
		if k == "chair":
			var rot: int = extra_rot if t == extra_solid else GS.placed[occupied[t]]["rot"]
			needs = kind_at.call(t + ROT_DIRS[rot]) == "table"
		if not needs:
			continue
		var ok := false
		for d in ROT_DIRS:
			if seen.has(t + d):
				ok = true
				break
		if not ok:
			return false
	return true


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
	var a := make_actor(sheet, 4, free_spot(REST_SPOT))
	staff_actors[key] = a
	stamina[key] = GS.max_stamina(key)
	_update_speed(key)
	_staff_loop(key)


func is_tired(key: String) -> bool:
	return tired.get(key, false)


func _update_speed(key: String) -> void:
	var a: Actor = staff_actors[key]
	a.speed = 34.0 * GS.agi_mult(key) * (0.6 if is_tired(key) else 1.0)
	a.modulate = Color(0.78, 0.78, 0.9) if is_tired(key) else Color.WHITE


func _role(key: String) -> String:
	return GS.staff[key]["role"]


func _has_role(role: String) -> bool:
	for k in staff_actors:
		if GS.staff.has(k) and _role(k) == role:
			return true
	return false


## What this staff member should do next. Each job has its own work first,
## then covers for jobs nobody is assigned to.
func _pick_task(key: String) -> Dictionary:
	var food_order: Dictionary = {}
	var drink_order: Dictionary = {}
	var ready: Dictionary = {}
	for o in orders:
		if o["state"] == "waiting":
			if o["food"] in GS.DRINKS:
				if drink_order.is_empty():
					drink_order = o
			elif food_order.is_empty():
				food_order = o
		elif o["state"] == "ready" and ready.is_empty():
			ready = o
	var greet: Dictionary = {}
	for c in customers:
		if c["state"] == "waiting" and not c.get("greeted", false) and not c.get("greeting", false):
			greet = c
			break
	var dirty: Dictionary = {}
	for seat in seats:
		if seat["dirty"] and not seat["cleaning"]:
			dirty = seat
			break
	var wash := dirty_dishes > 0 and not _station_list("sink").is_empty() and not _anyone_washing()
	var no_chef := not _has_role("Chef")
	var no_barista := not _has_role("Barista")
	var no_waiter := not _has_role("Waiter")
	var no_cleaner := not _has_role("Cleaner")
	var cook_any := food_order if not food_order.is_empty() else drink_order
	match _role(key):
		"Chef":
			if not food_order.is_empty():
				return {"type": "cook", "order": food_order}
			if no_barista and not drink_order.is_empty():
				return {"type": "cook", "order": drink_order}
			if no_waiter and not ready.is_empty():
				return {"type": "deliver", "order": ready}
		"Barista":
			if not drink_order.is_empty():
				return {"type": "cook", "order": drink_order}
			if no_chef and not food_order.is_empty():
				return {"type": "cook", "order": food_order}
			if no_waiter and not ready.is_empty():
				return {"type": "deliver", "order": ready}
		"Waiter":
			if not ready.is_empty():
				return {"type": "deliver", "order": ready}
			if no_cleaner and not dirty.is_empty():
				return {"type": "clean", "seat": dirty}
			if no_cleaner and wash:
				return {"type": "wash"}
			if no_chef and no_barista and not cook_any.is_empty():
				return {"type": "cook", "order": cook_any}
		"Hostess":
			if not greet.is_empty():
				return {"type": "greet", "customer": greet}
			if no_waiter and not ready.is_empty():
				return {"type": "deliver", "order": ready}
		"Cleaner":
			if not dirty.is_empty():
				return {"type": "clean", "seat": dirty}
			if wash:
				return {"type": "wash"}
			if no_waiter and not ready.is_empty():
				return {"type": "deliver", "order": ready}
	return {}


func _anyone_washing() -> bool:
	for st in _station_list("sink"):
		if station_busy.has(st):
			return true
	return false


func _staff_loop(key: String) -> void:
	var a: Actor = staff_actors[key]
	while is_instance_valid(a):
		var task: Dictionary = {} if is_tired(key) else _pick_task(key)
		if task.is_empty():
			var want: Vector2i = IDLE_SPOTS.get(_role(key), REST_SPOT)
			if is_tired(key) or phase == "night":
				want = REST_SPOT + Vector2i(staff_actors.keys().find(key) % 3, 0)
			var idle := free_spot(want)
			if a.tile != idle:
				await walk(a, idle)
				a.face(Actor.Dir.SE)
			await get_tree().create_timer(0.4, false).timeout
			continue
		working[key] = true
		match task["type"]:
			"cook":
				await _do_cook(key, a, task["order"])
			"deliver":
				await _do_deliver(key, a, task["order"])
			"greet":
				await _do_greet(key, a, task["customer"])
			"clean":
				await _do_clean(key, a, task["seat"])
			"wash":
				await _do_wash(key, a)
		working[key] = false
		if GS.staff.has(key):
			GS.add_mastery(key, _role(key))


## Stamina drains while working (END slows it); tired staff rest until 40%.
func _tick_stamina(delta: float) -> void:
	for key in staff_actors:
		if not GS.staff.has(key):
			continue
		var mx := GS.max_stamina(key)
		var s: float = stamina.get(key, mx)
		if working.get(key, false):
			s -= GS.stamina_drain(key) * delta
		else:
			s += (6.0 if _role(key) == "Rest" or is_tired(key) or phase == "night" else 2.5) * delta
		s = clampf(s, 0.0, mx)
		stamina[key] = s
		var was := is_tired(key)
		if s <= 0.0:
			tired[key] = true
		elif s >= mx * 0.4:
			tired[key] = false
		if was != is_tired(key):
			_update_speed(key)
			if is_tired(key):
				_float_text(staff_actors[key].position + Vector2(0, -80), "Tired...", Color("b8b8e0"))


func _work(a: Actor, dur: float, icon: Texture2D, col: Color) -> void:
	a.bubble.show_icon(icon)
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		if get_tree().paused:  # battle in progress: the café is frozen
			continue
		t += get_process_delta_time()
		a.bubble.set_progress(t / dur, col)
	a.bubble.visible = false
	a.bubble.set_progress(-1)


func _star(tier: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex("res://assets/ui/star_%s.png" % tier)
	return s


func _do_cook(key: String, a: Actor, o: Dictionary) -> void:
	var drink: bool = o["food"] in GS.DRINKS
	# baristas brew at an espresso machine (or a counter), everyone else at a stove
	var kind := "espresso" if drink and _role(key) == "Barista" else "stove"
	if kind == "espresso" and _station_list("espresso").is_empty():
		kind = "counter"
	var st := _nearest_station(kind, a.tile, true, key)
	if st.x < 0:
		await get_tree().create_timer(0.5, false).timeout  # every station busy: try again
		return
	o["state"] = "cooking"
	station_busy[st] = key
	await walk(a, work_tile(st))
	a.face_tile(st)
	var fridge := 1.1 if not _station_list("fridge").is_empty() else 1.0
	var dur: float = GS.FOODS[o["food"]]["cook"] / GS.agi_mult(key) / fridge / (0.6 if is_tired(key) else 1.0)
	await _work(a, dur, tex("res://assets/food/small/%s.png" % o["food"]), Color("f0a640"))
	station_busy.erase(st)
	if o["customer"]["state"] != "waiting":
		orders.erase(o)
		return
	o["tier"] = GS.roll_quality(key, o["food"], _role(key), is_tired(key))
	if o["tier"] != "diamond" and o["tier"] != "black" and GS.use_material("golden_sugar"):
		o["tier"] = GS.TIERS[GS.TIERS.find(o["tier"]) + 1]
		_float_text(a.position + Vector2(0, -80), "Golden Sugar!", Color("ffd86b"))
	o["maker"] = key
	var counter := _nearest_station("counter", a.tile, false)
	if counter.x < 0:
		counter = st  # no counter: hand it over from the station itself
	elif counter != st:
		await walk(a, work_tile(counter))
		a.face_tile(counter)
	var dish := Sprite2D.new()
	dish.texture = tex("res://assets/food/tiny/%s.png" % o["food"])
	dish.z_index = 5
	var badge := _star(o["tier"])
	badge.position = Vector2(6, -8)
	dish.add_child(badge)
	fx.add_child(dish)
	if not counter_dishes.has(counter):
		counter_dishes[counter] = []
	counter_dishes[counter].append(dish)
	_relayout_counter(counter)
	o["dish"] = dish
	o["counter"] = counter
	o["state"] = "ready"


func _do_deliver(key: String, a: Actor, o: Dictionary) -> void:
	o["state"] = "delivering"
	var counter: Vector2i = o["counter"]
	await walk(a, work_tile(counter))
	a.face_tile(counter)
	var dish: Sprite2D = o.get("dish")
	if is_instance_valid(dish):
		counter_dishes.get(counter, []).erase(dish)
		dish.queue_free()
	_relayout_counter(counter)
	var c: Dictionary = o["customer"]
	if c["state"] != "waiting":
		orders.erase(o)
		return
	a.carry.texture = tex("res://assets/food/tiny/%s.png" % o["food"])
	a.carry.modulate = Color.WHITE
	a.carry.visible = true
	var seat: Dictionary = c["seat"]
	await walk(a, free_neighbor(seat["tile"], a.tile))
	a.carry.visible = false
	orders.erase(o)
	if c["state"] != "waiting":
		return
	a.face_tile(seat["tile"])
	c["state"] = "served"
	c["server"] = key
	c["tier"] = o["tier"]
	c["maker"] = o["maker"]


## Hostess welcome: more patience (HOS + FOC) and a satisfaction bonus.
func _do_greet(key: String, a: Actor, c: Dictionary) -> void:
	c["greeting"] = true
	await walk(a, free_neighbor(c["seat"]["tile"], a.tile))
	if c["state"] != "waiting":
		return
	a.face_tile(c["seat"]["tile"])
	await _work(a, 1.2, tex("res://assets/gacha/sparkle.png"), Color("f08bd8"))
	if c["state"] != "waiting":
		return
	var bonus := (GS.stat(key, "hos") + GS.stat(key, "foc")) * 0.8
	c["patience"] += bonus
	c["max_patience"] += bonus
	c["greeted"] = true
	c["satisfaction"] = 1.0 + (GS.stat(key, "hos") + GS.stat(key, "foc")) * 0.01


## Bus a dirty seat: pick up the plate and carry it to the sink pile.
func _do_clean(key: String, a: Actor, seat: Dictionary) -> void:
	seat["cleaning"] = true
	await walk(a, free_neighbor(seat["tile"], a.tile))
	a.face_tile(seat["tile"])
	await _work(a, 0.8 / GS.agi_mult(key), tex("res://assets/gacha/sparkle.png"), Color("8fd0f0"))
	var plate: Sprite2D = seat.get("plate")
	if is_instance_valid(plate):
		a.carry.texture = plate.texture
		a.carry.modulate = plate.modulate
		a.carry.visible = true
		plate.queue_free()
	seat["plate"] = null
	seat["dirty"] = false
	seat["cleaning"] = false
	var sink := _nearest_station("sink", a.tile, false)
	if sink.x >= 0:
		await walk(a, work_tile(sink))
		a.face_tile(sink)
		dirty_dishes += 1
	a.carry.visible = false


## Wash the dish pile at a sink. Speed: AGI + END, cleaners and drying racks help.
func _do_wash(key: String, a: Actor) -> void:
	var sink := _nearest_station("sink", a.tile, true, key)
	if sink.x < 0:
		return
	station_busy[sink] = key
	await walk(a, work_tile(sink))
	a.face_tile(sink)
	var racks := mini(_station_list("rack").size(), 2)
	var skill := GS.agi_mult(key) * (0.7 + GS.stat(key, "end") * 0.03) * (1.0 + 0.3 * racks)
	while dirty_dishes > 0 and not (is_tired(key) and _role(key) != "Cleaner"):
		var dur := 2.2 / skill * (1.0 if _role(key) == "Cleaner" else 1.5) / (0.6 if is_tired(key) else 1.0)
		await _work(a, dur, tex("res://assets/food/tiny/coffee.png"), Color("8fd0f0"))
		dirty_dishes -= 1
		if _role(key) != "Cleaner":
			break  # helpers wash one and go back to their own job
	station_busy.erase(sink)


func _relayout_counter(counter: Vector2i) -> void:
	var list: Array = counter_dishes.get(counter, [])
	for i in list.size():
		list[i].position = tile_pos(counter) + Vector2(-8 + (i % 3) * 8, -30 - (i / 3) * 6)


# ------------------------------------------------------------------ customers
func _free_seats() -> Array:
	var out: Array = []
	for seat in seats:
		if not seat["taken"] and not seat["dirty"]:
			out.append(seat)
	return out


func _spawn_customer() -> void:
	var free := _free_seats()
	if free.is_empty():
		return
	var seat: Dictionary = free[randi() % free.size()]
	seat["taken"] = true
	var a: Actor
	var idx := randi() % maxi(customer_sheets.size(), 1)
	if customer_sheets.is_empty():
		a = make_actor(tex("res://assets/chars/chef.png"), 4, DOOR)
		a.modulate = Color.from_hsv(randf(), 0.35, 1.0)
	else:
		a = make_actor(customer_sheets[idx], 2, DOOR)
		a.sit_tex = tex("res://assets/chars/customer_%d_sit.png" % idx)
	a.speed = 36.0
	var patience := 45.0 * (1.0 + GS.ambience() * 0.02)
	var c := {"actor": a, "seat": seat, "state": "walking", "patience": patience,
		"max_patience": patience, "satisfaction": 1.0}
	customers.append(c)
	_customer_flow(c)


func _plate_pos(seat: Dictionary) -> Vector2:
	var table := tile_pos(seat["table"])
	return table + (tile_pos(seat["tile"]) - table) * 0.25 + Vector2(0, -24)


func _customer_flow(c: Dictionary) -> void:
	var a: Actor = c["actor"]
	var seat: Dictionary = c["seat"]
	a.modulate.a = 0.0
	create_tween().tween_property(a, "modulate:a", 1.0, 0.4)
	await walk(a, seat["tile"])
	a.sit([Actor.Dir.SE, Actor.Dir.SW, Actor.Dir.NW, Actor.Dir.NE][seat["dir"]])
	# the seat is the half of the chair tile nearest the table: slide in so the
	# customer sits at the table (legs tucked under it) instead of beside it
	a.position += (tile_pos(seat["table"]) - tile_pos(seat["tile"])) * SEAT_SLIDE
	var menu: Array = GS.unlocked
	var food: String = menu[randi() % menu.size()]
	c["food"] = food
	a.bubble.show_icon(tex("res://assets/food/small/%s.png" % food))
	c["state"] = "waiting"
	orders.append({"food": food, "customer": c, "state": "waiting"})
	while c["state"] == "waiting":
		await get_tree().process_frame
	a.bubble.visible = false
	var plate: Sprite2D = null
	if c["state"] == "served":
		var tier: String = c["tier"]
		plate = Sprite2D.new()
		plate.texture = tex("res://assets/food/tiny/%s.png" % food)
		plate.position = _plate_pos(seat)
		plate.z_index = 5
		fx.add_child(plate)
		var badge := _star(tier)
		badge.position = Vector2(0, -16)
		plate.add_child(badge)
		await get_tree().create_timer(2.0 if tier == "black" else 5.0, false).timeout
		badge.queue_free()
		_pay(c, food, tier)
	else:
		_float_text(a.position + Vector2(0, -70), "Too slow...", Color("ff8a8a"))
	a.stand()
	a.position = tile_pos(seat["tile"])
	seat["taken"] = false
	if plate:  # leftovers stay until someone buses the seat
		plate.modulate = Color(0.55, 0.5, 0.5, 0.9)
		seat["dirty"] = true
		seat["plate"] = plate
	await walk(a, DOOR)
	var tw := create_tween()
	tw.tween_property(a, "modulate:a", 0.0, 0.4)
	await tw.finished
	customers.erase(c)
	a.queue_free()


## Price x star tier, plus tips from the server's HOS (and the barista's HOS on drinks).
func _pay(c: Dictionary, food: String, tier: String) -> void:
	var a: Actor = c["actor"]
	var price: int = GS.FOODS[food]["price"]
	var sat: float = c.get("satisfaction", 1.0)
	var tip_rate := GS.stat(c["server"], "hos") * 0.012 + GS.ambience() * 0.01
	if food in GS.DRINKS and GS.staff.has(c["maker"]) and _role(c["maker"]) == "Barista":
		tip_rate += GS.stat(c["maker"], "hos") * 0.006
	var earned := int(round(price * GS.TIER_PRICE[tier] + (0.0 if tier == "black" else price * tip_rate * sat)))
	GS.add_coins(earned)
	GS.served_total += 1
	GS.add_rep(int(round(GS.TIER_REP[tier] * sat)))
	var col: Color = {"black": Color("9a9aa8"), "plain": Color("fff6ea"), "bronze": Color("e8a46a"),
		"silver": Color("dfe6f2"), "gold": Color("ffd86b"), "diamond": Color("9ee8ff")}[tier]
	var msg := "+%d %s" % [earned, GS.TIER_NAME[tier]]
	if tier == "black":
		msg = "+%d  Burnt..." % earned
	_float_text(a.position + Vector2(0, -70), msg, col)
	if tier == "diamond" and randf() < 0.5:
		GS.gems += 5
		GS.changed.emit()
		_float_text(a.position + Vector2(0, -84), "+5 gems", Color("f08bd8"))
	elif randf() < 0.05:
		GS.gems += 10
		GS.changed.emit()
		_float_text(a.position + Vector2(0, -84), "+10 gems", Color("f08bd8"))


# ------------------------------------------------------------------ day cycle
func _process(delta: float) -> void:
	bob_t += delta
	ship_root.position.y = round(sin(bob_t * 1.3) * 1.5)
	var pan := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO and not overlay.visible:
		_move_camera(pan * 220.0 * delta)
	match phase:
		"open":
			day_t += delta
			spawn_t -= delta
			if spawn_t <= 0.0:
				spawn_t = maxf(2.5, 8.0 - GS.rep_level * 0.4) + randf() * 3.0
				_spawn_customer()
			if day_t >= GS.DAY_LENGTH:
				phase = "closing"
				_toast("Closing time - finishing the last orders.")
		"closing":
			if customers.is_empty():
				_start_night()
	for c in customers:
		if c["state"] == "waiting":
			c["patience"] -= delta
			var p: float = c["patience"] / c["max_patience"]
			c["actor"].bubble.set_progress(p, Color("6cc46a") if p > 0.35 else Color("e05a5a"))
			if c["patience"] <= 0.0:
				c["state"] = "angry"
	_tick_stamina(delta)
	_refresh_day_label()
	save_t += delta
	if save_t > 15.0:
		save_t = 0.0
		GS.save_game()


func _start_night() -> void:
	phase = "night"
	orders.clear()
	create_tween().tween_property(tint, "color", NIGHT_TINT, 1.5)
	night_bar.visible = true
	GS.save_game()
	_toast("The café is closed. Rearrange furniture, then open for Day %d." % (GS.day + 1))


func _open_cafe() -> void:
	var missing: Array = []
	for need in [["stove", "a stove"], ["counter", "a counter"]]:
		if _station_list(need[0]).is_empty():
			missing.append(need[1])
	if seats.is_empty():
		missing.append("a chair facing a table")
	if not missing.is_empty():
		_toast("Can't open yet - place " + ", ".join(missing) + ".")
		return
	if editing:
		_set_editing(false)
	GS.day += 1
	GS.rest_crew()
	day_t = 0.0
	spawn_t = 2.0
	phase = "open"
	night_bar.visible = false
	create_tween().tween_property(tint, "color", Color.WHITE, 1.5)
	GS.save_game()
	_toast("Day %d - the café is open!" % GS.day)


func _refresh_day_label() -> void:
	if hud_day == null:
		return
	match phase:
		"open":
			var left := int(ceil(GS.DAY_LENGTH - day_t))
			hud_day.text = "Day %d  Open %d:%02d" % [GS.day, left / 60, left % 60]
		"closing":
			hud_day.text = "Day %d  Closing..." % GS.day
		"night":
			hud_day.text = "Day %d  Night" % GS.day


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
	hud_day = Label.new()
	hud_day.add_theme_font_size_override("font_size", 11)
	hb.add_child(hud_day)

	# side buttons
	var side := VBoxContainer.new()
	side.position = Vector2(6, 210)
	side.add_theme_constant_override("separation", 4)
	root.add_child(side)
	for pair in [["Menu", _open_menu], ["Staff", _open_staff], ["Summon", _open_summon], ["Shop", _open_shop],
			["Battles", _open_board]]:
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

	# night controls
	night_bar = VBoxContainer.new()
	night_bar.position = Vector2(6, 148)
	night_bar.add_theme_constant_override("separation", 8)
	night_bar.visible = false
	root.add_child(night_bar)
	var eb := Button.new()
	eb.text = "Edit Café"
	eb.custom_minimum_size = Vector2(80, 26)
	eb.pressed.connect(func(): _set_editing(not editing))
	night_bar.add_child(eb)
	var ob := Button.new()
	ob.text = "Open Café"
	ob.custom_minimum_size = Vector2(80, 26)
	ob.pressed.connect(_open_cafe)
	night_bar.add_child(ob)

	# edit mode: storage strip + hint
	edit_bar = PanelContainer.new()
	edit_bar.position = Vector2(570, 48)
	edit_bar.custom_minimum_size = Vector2(64, 270)
	edit_bar.size = Vector2(64, 270)
	edit_bar.visible = false
	root.add_child(edit_bar)
	var esc := ScrollContainer.new()
	esc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	edit_bar.add_child(esc)
	edit_list = VBoxContainer.new()
	edit_list.add_theme_constant_override("separation", 4)
	esc.add_child(edit_list)
	edit_hint = Label.new()
	edit_hint.position = Vector2(96, 342)
	edit_hint.add_theme_font_size_override("font_size", 10)
	edit_hint.add_theme_color_override("font_color", Color("fff6ea"))
	edit_hint.add_theme_color_override("font_outline_color", Color("2a1a22"))
	edit_hint.add_theme_constant_override("outline_size", 4)
	edit_hint.text = "Click: pick up / place    Right-click or R: rotate    Del: put away    Esc: cancel"
	edit_hint.visible = false
	root.add_child(edit_hint)

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
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 3)
	for tier in GS.TIERS:
		var tr := TextureRect.new()
		tr.texture = tex("res://assets/ui/star_%s.png" % tier)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		legend.add_child(tr)
		legend.add_child(_small_label("%s x%.1f " % [GS.TIER_NAME[tier], GS.TIER_PRICE[tier]], 9))
	list.add_child(legend)
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
		icon.custom_minimum_size = Vector2(32, 30)
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
## Standing frame of a character. combat = the outside/battle outfit
## (assets/chars/<sheet>_combat.png), used by the gacha; falls back to café clothes.
func _portrait(key: String, combat: bool = false) -> TextureRect:
	var at := AtlasTexture.new()
	var sheet: String = GS.STAFF[key]["sheet"]
	at.atlas = tex("res://assets/chars/%s.png" % sheet)
	if combat and ResourceLoader.exists("res://assets/chars/%s_combat.png" % sheet):
		at.atlas = tex("res://assets/chars/%s_combat.png" % sheet)
	var fw := at.atlas.get_width() / 3.0
	var fh := at.atlas.get_height() / 4.0
	at.region = Rect2(fw, 0, fw, fh)
	var tr := TextureRect.new()
	tr.texture = at
	tr.custom_minimum_size = Vector2(fw, fh)
	return tr


func _open_staff() -> void:
	var list := _scroll(_open_panel("Staff", Vector2(460, 300)))
	list.add_child(_small_label("Chef TEC+FOC   Barista TEC+HOS   Waiter AGI+HOS   Hostess HOS+FOC   Cleaner AGI+END", 9))
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
		info.add_theme_constant_override("separation", 2)
		info.add_child(_small_label("%s  [%s]  Lv %d" % [d["name"], d["rarity"], GS.staff[key]["level"]], 12))
		info.add_child(_small_label(d["title"], 10))
		var stats_row := HBoxContainer.new()
		stats_row.add_theme_constant_override("separation", 6)
		info.add_child(stats_row)
		_fill_stats(stats_row, key)
		var st := HBoxContainer.new()
		st.add_child(_small_label("Stamina", 9))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(120, 6)
		bar.show_percentage = false
		bar.max_value = GS.max_stamina(key)
		bar.value = stamina.get(key, bar.max_value)
		bar.add_theme_stylebox_override("fill", _sb(Color("8fd0f0") if not is_tired(key) else Color("b8b8e0"), Color("3b2a33"), 0, 0))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		st.add_child(bar)
		if is_tired(key):
			st.add_child(_small_label(" tired - resting", 9))
		info.add_child(st)
		var m: Dictionary = GS.staff[key]
		var cs := GS.combat_stats(key)
		info.add_child(_small_label("XP %d/%d   Battle: HP %d ATK %d DEF %d SPD %d CRIT %d%%   %s mastery Lv %d" % [
			int(m.get("xp", 0)), GS.xp_needed(GS.level(key)), cs["hp"], cs["atk"], cs["def"], cs["spd"], cs["crit"],
			m["role"], GS.mastery_level(key, m["role"])], 8))
		if int(GS.materials.get("training_manual", 0)) > 0 and GS.level(key) < GS.MAX_LEVEL:
			var mb := Button.new()
			mb.text = "Read Training Manual (+%d XP)" % GS.MANUAL_XP
			mb.add_theme_font_size_override("font_size", 8)
			mb.pressed.connect(func():
				if GS.use_material("training_manual"):
					var up := GS.add_xp(key, GS.MANUAL_XP)
					GS.save_game()
					_toast("%s studied hard%s" % [GS.STAFF[key]["name"], (" - level up!" if up > 0 else ".")])
				_open_staff())
			info.add_child(mb)
		hb.add_child(info)
		var ob := OptionButton.new()
		for r in GS.JOBS:
			ob.add_item(r)
		ob.selected = GS.JOBS.find(GS.staff[key]["role"])
		ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ob.item_selected.connect(func(i: int):
			GS.staff[key]["role"] = GS.JOBS[i]
			GS.save_game()
			_fill_stats(stats_row, key))
		hb.add_child(ob)
		list.add_child(row)


## Five stat values; the two that drive the current job are highlighted.
func _fill_stats(box: HBoxContainer, key: String) -> void:
	for ch in box.get_children():
		ch.queue_free()
	var main_stats: Array = GS.JOB_STATS[GS.staff[key]["role"]]
	for s in GS.STATS:
		var l := _small_label("%s %d" % [GS.STAT_LABEL[s], int(round(GS.stat(key, s)))], 10)
		if s in main_stats:
			l.add_theme_color_override("font_color", C_PINK_DK)
		box.add_child(l)


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
			featured.add_child(_portrait(k, true))
	info.add_child(featured)
	info.add_child(_small_label("You have %d gems, %d tickets" % [GS.gems, GS.tickets], 11))
	if GS.tickets > 0:
		var bt := Button.new()
		bt.text = "Summon x1  (1 ticket)"
		bt.pressed.connect(func(): _do_pull(1, machine, true))
		info.add_child(bt)
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


func _do_pull(n: int, machine: Control, ticket: bool = false) -> void:
	var results := GS.pull_ticket() if ticket else GS.pull(n)
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
		var pr := _portrait(r["key"], true)
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


# ---- battles: Magical Encounter Board
func _open_board() -> void:
	var v := _open_panel("Magical Encounter Board", Vector2(470, 306))
	var info := "Meals packed: %d    Tickets: %d    Crew HP is restored each new day." % [GS.meals.size(), GS.tickets]
	v.add_child(_small_label(info, 9))
	var list := _scroll(v)
	for enc in BattleDB.encounters():
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _sb(Color("fff6ea"), Color("f2c14e") if enc.boss else C_EDGE, 2, 4))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		row.add_child(hb)
		var faces := HBoxContainer.new()
		faces.add_theme_constant_override("separation", 0)
		for spec in enc.enemies:
			var data := BattleDB.enemy(spec["id"])
			var tr := TextureRect.new()
			tr.texture = tex(data.sprite)
			tr.custom_minimum_size = Vector2(34, 40)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			faces.add_child(tr)
		hb.add_child(faces)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var names: Array[String] = []
		for spec in enc.enemies:
			names.append("%s Lv%d" % [BattleDB.enemy(spec["id"]).display_name, spec["level"]])
		col.add_child(_small_label(("BOSS  " if enc.boss else "") + enc.display_name + "   (rec. Lv %d)" % enc.recommended_level, 11))
		col.add_child(_small_label(enc.description, 8))
		col.add_child(_small_label(", ".join(names), 8))
		col.add_child(_small_label(_reward_text(enc), 8))
		hb.add_child(col)
		var b := Button.new()
		b.text = "Prepare"
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			prep_enc = enc
			prep_team.clear()
			prep_meal = -1
			_open_prepare())
		hb.add_child(b)
		list.add_child(row)


func _reward_text(enc: EncounterData) -> String:
	var parts: Array[String] = ["Coins", "XP"]
	for d in enc.drops:
		match d["kind"]:
			"material": parts.append(GS.MATERIALS[d["id"]]["name"])
			"tickets": parts.append("Ticket")
			"gems": parts.append("Gems")
	var first := ""
	if int(GS.cleared.get(str(enc.id), 0)) == 0:
		var fc: Array[String] = []
		for d in enc.first_clear:
			fc.append({"material": GS.MATERIALS.get(d.get("id", ""), {}).get("name", ""), "tickets": "%d Ticket" % d["n"],
				"gems": "%d Gems" % d["n"]}[d["kind"]])
		if enc.unlock_recipe:
			fc.append("a new recipe")
		first = "   First clear: " + ", ".join(fc)
	else:
		first = "   Cleared x%d" % int(GS.cleared[str(enc.id)])
	return "Rewards: " + ", ".join(parts) + first


func _open_prepare() -> void:
	var enc := prep_enc
	var v := _open_panel("Prepare: " + enc.display_name, Vector2(470, 306))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)

	# crew picker
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(170, 0)
	left.add_child(_small_label("Crew (click to add / remove)", 9))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	sc.add_child(grid)
	for key in GS.staff:
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 84)
		var cap := _small_label("%s\nLv%d %d%%" % [GS.STAFF[key]["name"], GS.level(key), int(GS.battle_hp_ratio(key) * 100)], 8)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(54, 24)
		cap.size = Vector2(54, 24)
		cap.position = Vector2(0, 56)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		var face := _portrait(key, true)   # combat outfit, cropped to head + body
		var ft: AtlasTexture = face.texture
		ft.region.size.y = minf(ft.region.size.y, 52.0)
		face.custom_minimum_size = ft.region.size
		face.size = ft.region.size
		face.position = Vector2((54 - ft.region.size.x) / 2.0, 3)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(face)
		if key in prep_team:
			b.add_theme_stylebox_override("normal", _sb(Color("f2c14e"), C_EDGE, 2, 2))
			b.add_theme_stylebox_override("hover", _sb(Color("f6d27a"), C_EDGE, 2, 2))
		b.pressed.connect(func():
			if key in prep_team:
				prep_team.erase(key)
			elif prep_team.size() < 3:
				prep_team.append(key)
			_open_prepare())
		grid.add_child(b)
	cols.add_child(left)

	# formation + meal
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(270, 0)
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)
	right.add_child(_small_label("Formation (front draws the most attacks)", 9))
	var slots := ["Front", "Middle", "Back"]
	for i in 3:
		var line := "%s: -" % slots[i]
		if i < prep_team.size():
			var k: String = prep_team[i]
			var cs := GS.combat_stats(k)
			line = "%s: %s  HP %d ATK %d DEF %d SPD %d CRIT %d%%" % [slots[i], GS.STAFF[k]["name"],
				cs["hp"] * GS.battle_hp_ratio(k), cs["atk"], cs["def"], cs["spd"], cs["crit"]]
			var sk: AbilityData = BattleDB.kit(k)["skill"]
			if sk:
				line += "\n   %s: %s" % [sk.display_name, sk.description]
		var fl := _small_label(line, 8)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD
		fl.custom_minimum_size = Vector2(270, 0)
		right.add_child(fl)

	right.add_child(_small_label("Meal for this battle (eaten when it starts)", 9))
	var mo := OptionButton.new()
	mo.add_item("No meal")
	for i in GS.meals.size():
		var m: Dictionary = GS.meals[i]
		mo.add_item("%s [%s] %s" % [GS.FOODS[m["food"]]["name"], GS.TIER_NAME[m["tier"]], BattleDB.meal_text(m)])
	mo.selected = prep_meal + 1 if prep_meal < GS.meals.size() else 0
	mo.add_theme_font_size_override("font_size", 9)
	mo.custom_minimum_size = Vector2(270, 0)
	mo.clip_text = true
	mo.item_selected.connect(func(i: int): prep_meal = i - 1)
	right.add_child(mo)

	right.add_child(_small_label("Pack a meal (best cook rolls the star tier)", 9))
	var pack := HBoxContainer.new()
	var ro := OptionButton.new()
	ro.add_theme_font_size_override("font_size", 9)
	ro.custom_minimum_size = Vector2(170, 0)
	ro.clip_text = true
	for f in GS.unlocked:
		ro.add_item("%s - %s" % [GS.FOODS[f]["name"], BattleDB.meal_text({"food": f, "tier": "silver"})])
	pack.add_child(ro)
	var pb := Button.new()
	pb.add_theme_font_size_override("font_size", 9)
	var pick := func() -> String: return GS.unlocked[maxi(ro.selected, 0)]
	pb.text = "Pack (%d coins)" % GS.meal_cost(pick.call())
	ro.item_selected.connect(func(_i): pb.text = "Pack (%d coins)" % GS.meal_cost(pick.call()))
	pb.pressed.connect(func():
		var meal := GS.pack_meal(pick.call())
		if meal.is_empty():
			_toast("Not enough coins.")
		else:
			_toast("Packed %s - %s quality!" % [GS.FOODS[meal["food"]]["name"], GS.TIER_NAME[meal["tier"]]])
			prep_meal = GS.meals.size() - 1
		_open_prepare())
	pack.add_child(pb)
	right.add_child(pack)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_open_board)
	btns.add_child(back)
	var go := Button.new()
	go.text = "Start Battle"
	go.disabled = prep_team.is_empty()
	go.pressed.connect(_start_battle)
	btns.add_child(go)
	right.add_child(btns)


## Leave the café paused and fight. The meal is eaten (and saved) right here,
## exactly once.
func _start_battle() -> void:
	if prep_team.is_empty() or battle != null:
		return
	var meal := {}
	if prep_meal >= 0 and prep_meal < GS.meals.size():
		meal = GS.consume_meal(prep_meal)
	prep_meal = -1
	_close_panel()
	if editing:
		_set_editing(false)
	var team: Array[String] = []
	team.assign(prep_team)
	battle = BattleScene.new(prep_enc, team, meal, theme_ui)
	battle.closed.connect(_end_battle)
	add_child(battle)
	ui.visible = false
	get_tree().paused = true


func _end_battle() -> void:
	battle.queue_free()
	battle = null
	get_tree().paused = false
	ui.visible = true
	_refresh_hud()
	_toast("Back at the café.")


# ---- shop
func _open_shop() -> void:
	var list := _scroll(_open_panel("Furniture Shop", Vector2(460, 300)))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var g := Button.new()
	g.text = "Trade %d coins -> %d gems" % [GS.GEM_TRADE["coins"], GS.GEM_TRADE["gems"]]
	g.disabled = GS.coins < GS.GEM_TRADE["coins"]
	g.pressed.connect(func():
		if GS.trade_gems():
			_toast("Gems acquired!")
		_open_shop())
	top.add_child(g)
	top.add_child(_small_label("Bought items go to storage.\nPlace them at night with Edit Café.", 9))
	list.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	list.add_child(grid)
	for item in GS.ITEMS:
		var d: Dictionary = GS.ITEMS[item]
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", _sb(Color("fff6ea"), C_EDGE, 1, 4))
		cell.custom_minimum_size = Vector2(138, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		cell.add_child(v)
		var icon := TextureRect.new()
		icon.texture = tex(GS.item_tex_path(item))
		icon.custom_minimum_size = Vector2(130, 70)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		v.add_child(icon)
		v.add_child(_small_label(d["name"], 11))
		v.add_child(_small_label(_item_blurb(item), 8))
		var owned := int(GS.inventory.get(item, 0))
		var b := Button.new()
		b.text = "Buy  %d" % d["cost"] + ("   (stored %d)" % owned if owned > 0 else "")
		b.add_theme_font_size_override("font_size", 9)
		b.disabled = GS.coins < d["cost"]
		b.pressed.connect(func():
			if GS.buy_item(item):
				_toast("%s bought - place it at night." % d["name"])
				if editing:
					_refresh_edit_list()
			_open_shop())
		v.add_child(b)
		grid.add_child(cell)


func _item_blurb(item: String) -> String:
	match _kind(item):
		"stove": return "Chefs cook here"
		"espresso": return "Baristas brew drinks"
		"counter": return "Finished dishes wait here"
		"sink": return "Dirty dishes are washed"
		"rack": return "Washing +30%"
		"fridge": return "Cooking +10%"
		"table": return "Chairs facing it = seats"
		"chair": return "Face it toward a table"
		"rug": return "Walkable, ambience +1"
	return "Ambience +%d" % int(GS.ITEMS[item].get("ambience", 0))


# ---- edit mode (night only)
func _set_editing(on: bool) -> void:
	if on and phase != "night":
		_toast("You can rearrange once the café closes for the night.")
		return
	if not on and not held.is_empty():
		_cancel_held()
	editing = on
	edit_bar.visible = on
	edit_hint.visible = on
	grid_node.visible = on
	ghost.visible = false
	if on:
		_close_panel()
		_refresh_edit_list()


func _refresh_edit_list() -> void:
	for ch in edit_list.get_children():
		ch.queue_free()
	if GS.inventory.is_empty():
		var empty := _small_label("Storage empty.
Buy items in the Shop.", 9)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(52, 0)
		edit_list.add_child(empty)
	for item in GS.inventory:
		var b := Button.new()
		b.icon = tex(GS.item_tex_path(item))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(52, 44)
		b.text = "x%d" % GS.inventory[item]
		b.add_theme_font_size_override("font_size", 9)
		b.tooltip_text = GS.ITEMS[item]["name"]
		b.pressed.connect(func():
			if not held.is_empty():
				_cancel_held()
			if GS.take_from_inventory(item):
				held = {"item": item, "rot": 0, "from": null}
				_refresh_edit_list()
				_update_ghost())
		edit_list.add_child(b)


func _pick_up(t: Vector2i) -> void:
	var idx: int = occupied.get(t, rug_at.get(t, -1))
	if idx < 0:
		return
	var p: Dictionary = GS.placed[idx]
	for seat in seats:
		if (seat["tile"] == t or seat["table"] == t) and seat["dirty"]:
			_toast("Clear the dirty dishes there first.")
			return
	held = {"item": p["item"], "rot": p["rot"], "from": t}
	GS.placed.remove_at(idx)
	_apply_layout()
	_update_ghost()


func _can_place(t: Vector2i) -> bool:
	if held.is_empty() or not in_room(t) or t == DOOR:
		return false
	if _kind(held["item"]) == "rug":
		return not rug_at.has(t)
	if occupied.has(t):
		return false
	return layout_ok(t)


func _place(t: Vector2i) -> void:
	if not _can_place(t):
		var free := in_room(t) and not occupied.has(t) and t != DOOR
		_toast("Can't place there - a station or seat would be cut off from the door." if free else "That spot is taken.")
		return
	GS.placed.append({"item": held["item"], "c": t.x, "r": t.y, "rot": held["rot"]})
	held = {}
	ghost.visible = false
	_apply_layout()
	GS.save_game()


## Put the held item back where it came from (or into storage).
func _cancel_held() -> void:
	if held.is_empty():
		return
	if held["from"] != null:
		var t: Vector2i = held["from"]
		GS.placed.append({"item": held["item"], "c": t.x, "r": t.y, "rot": held["rot"]})
		_apply_layout()
	else:
		GS.store_item(held["item"])
		_refresh_edit_list()
	held = {}
	ghost.visible = false


func _store_held() -> void:
	if held.is_empty():
		return
	GS.store_item(held["item"])
	held = {}
	ghost.visible = false
	_refresh_edit_list()
	GS.save_game()


func _rotate_held() -> void:
	if held.is_empty():
		return
	held["rot"] = (int(held["rot"]) + 1) % _rotations(held["item"])
	_update_ghost()


func _update_ghost() -> void:
	if held.is_empty():
		ghost.visible = false
		return
	var s := _make_sprite(held["item"], held["rot"], hover if in_room(hover) else Vector2i(3, 3))
	ghost.texture = s.texture
	ghost.flip_h = s.flip_h
	ghost.offset = s.offset
	ghost.position = s.position
	s.free()
	ghost.visible = true
	ghost.modulate = Color(0.6, 1, 0.6, 0.8) if _can_place(hover) else Color(1, 0.5, 0.5, 0.7)


## Pan around the ship: drag with the middle mouse button (or left/right
## drag when not editing), or WASD / arrow keys.
func _move_camera(d: Vector2) -> void:
	var c := _ship_center()
	camera.position = (camera.position + d).clamp(c - Vector2(230, 170), c + Vector2(230, 90)).round()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not overlay.visible:
		var m: int = event.button_mask
		if m & MOUSE_BUTTON_MASK_MIDDLE or (not editing and m & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)):
			_move_camera(-event.relative)
			return
	if not editing or overlay.visible:
		return
	if event is InputEventMouseMotion:
		var t := mouse_tile()
		if t != hover:
			hover = t
			grid_node.queue_redraw()
			_update_ghost()
	elif event is InputEventMouseButton and event.pressed:
		var t := mouse_tile()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if held.is_empty():
				_pick_up(t)
			else:
				_place(t)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if held.is_empty() and occupied.has(t):
				var p: Dictionary = GS.placed[occupied[t]]  # rotate in place
				p["rot"] = (int(p["rot"]) + 1) % _rotations(p["item"])
				_apply_layout()
				GS.save_game()
			else:
				_rotate_held()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_rotate_held()
			KEY_DELETE, KEY_BACKSPACE:
				_store_held()
			KEY_ESCAPE:
				_cancel_held()


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


## Tile outlines shown while editing; the hovered tile is highlighted.
class GridNode extends Node2D:
	var main: Node2D

	func _draw() -> void:
		for t in main.deck:
			if true:
				var p: Vector2 = main.tile_pos(t)
				var pts := PackedVector2Array([p + Vector2(0, -main.HH), p + Vector2(main.HW, 0),
					p + Vector2(0, main.HH), p + Vector2(-main.HW, 0), p + Vector2(0, -main.HH)])
				var col := Color(1, 1, 1, 0.18)
				if t == main.hover:
					col = Color(1, 0.95, 0.6, 0.9)
				if t == main.DOOR:
					col = Color(1, 0.5, 0.5, 0.4)
				draw_polyline(pts, col, 1.0)


## Slowly drifting clouds behind the ship (screen space).
class CloudNode extends Node2D:
	var clouds: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 9:
			clouds.append({"pos": Vector2(rng.randf_range(0, 700), rng.randf_range(150, 350)),
				"speed": rng.randf_range(4, 12), "size": rng.randf_range(14, 30), "far": rng.randf() < 0.5})

	func _process(delta: float) -> void:
		for c in clouds:
			c["pos"].x -= c["speed"] * delta
			if c["pos"].x < -120:
				c["pos"].x = 760
		queue_redraw()

	func _draw() -> void:
		for c in clouds:
			var col := Color("6c4f8e") if c["far"] else Color("8a6aaa")
			var top := Color("8d70ad") if c["far"] else Color("b49bd0")
			var p: Vector2 = c["pos"].round()
			var s: float = c["size"]
			for j in 4:
				var o := Vector2(j * s * 0.8 - s * 1.2, sin(j * 2.1) * s * 0.25)
				draw_circle(p + o, s * (0.7 + 0.2 * (j % 2)), col)
				draw_circle(p + o + Vector2(0, -3), s * (0.6 + 0.2 * (j % 2)), top)
